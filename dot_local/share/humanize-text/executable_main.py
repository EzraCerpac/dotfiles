#!/usr/bin/env -S uv run --script --locked
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#   "humanize-text @ git+https://github.com/lynote-ai/humanize-text@e43ca3ad79328da197f48a72e0fdc57196634009",
#   "pyyaml==6.0.3",
# ]
# ///
"""Guarded command front end for Lynote's humanize-text pipeline."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import tomllib
from collections.abc import Callable, Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

UPSTREAM_COMMIT = "e43ca3ad79328da197f48a72e0fdc57196634009"
KEYCHAIN_SERVICE = "HUMANIZE_TEXT_NIUTRANS_API_KEY"
DEFAULTS_PATH = Path("~/.config/humanize-text/defaults.toml").expanduser()
LOCAL_CONFIG_PATH = Path("~/.config/humanize-text/config.toml").expanduser()
PROXY_CONFIG_PATH = Path("~/.cli-proxy-api/config.yaml").expanduser()
GUARD_ADAPTER = Path("~/.local/share/humanize-text/typst_guard_cli.lua").expanduser()
CONFIGURE_WIZARD = Path("~/.local/share/humanize-text/configure.sh").expanduser()
ENV_OVERRIDES = (
    "LLM_PROVIDER",
    "LLM_BASE_URL",
    "LLM_API_KEY",
    "LLM_MODEL",
    "OPENROUTER_API_KEY",
    "DEEPSEEK_API_KEY",
    "ATLASCLOUD_API_KEY",
    "ATLAS_CLOUD_API_KEY",
)


class HumanizeError(RuntimeError):
    """A safe, user-facing failure without source text."""


@dataclass(frozen=True)
class RunSettings:
    temperature: float
    paragraphs: bool
    proxy_url: str
    proxy_config: Path
    model: str
    intermediate_language: str
    compile_command: tuple[str, ...]


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_toml(path: Path, *, required: bool) -> dict[str, Any]:
    try:
        with path.open("rb") as stream:
            return tomllib.load(stream)
    except FileNotFoundError as error:
        if required:
            raise HumanizeError(f"Missing managed configuration: {path}") from error
        return {}
    except tomllib.TOMLDecodeError as error:
        raise HumanizeError(f"Invalid TOML in {path}: {error}") from error


def load_settings(
    preset: str,
    *,
    temperature: float | None,
    paragraph_override: bool | None,
    defaults_path: Path = DEFAULTS_PATH,
    local_path: Path = LOCAL_CONFIG_PATH,
) -> RunSettings:
    config = deep_merge(load_toml(defaults_path, required=True), load_toml(local_path, required=False))
    try:
        preset_config = config["presets"][preset]
        proxy = config["proxy"]
    except (KeyError, TypeError) as error:
        raise HumanizeError(f"Configuration is missing the {preset!r} preset or proxy settings") from error

    chosen_temperature = float(temperature if temperature is not None else preset_config["temperature"])
    if not 0.0 <= chosen_temperature <= 2.0:
        raise HumanizeError("Temperature must be between 0 and 2")
    paragraphs = bool(preset_config.get("paragraphs", False))
    if paragraph_override is not None:
        paragraphs = paragraph_override

    model = str(config.get("llm", {}).get("model", "")).strip()
    if not model:
        raise HumanizeError("No proxy model configured. Run: humanize-text configure")
    compile_command = config.get("typst", {}).get("compile_command", [])
    if not isinstance(compile_command, list) or not all(isinstance(item, str) for item in compile_command):
        raise HumanizeError("typst.compile_command must be an array of command arguments")

    return RunSettings(
        temperature=chosen_temperature,
        paragraphs=paragraphs,
        proxy_url=str(proxy.get("base_url", "http://127.0.0.1:8317/v1")).rstrip("/"),
        proxy_config=Path(str(proxy.get("config_path", PROXY_CONFIG_PATH))).expanduser(),
        model=model,
        intermediate_language=str(config.get("pipeline", {}).get("intermediate_language", "fi")),
        compile_command=tuple(compile_command),
    )


def read_proxy_key(path: Path) -> str | None:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except FileNotFoundError as error:
        raise HumanizeError(f"CLIProxyAPI config is missing: {path}") from error
    except yaml.YAMLError as error:
        raise HumanizeError(f"CLIProxyAPI config is invalid YAML: {path}") from error
    keys = data.get("api-keys", [])
    if not isinstance(keys, list):
        raise HumanizeError("CLIProxyAPI config has no usable api-keys list")
    for value in keys:
        if isinstance(value, str) and value.strip() and not value.startswith("your-api-key"):
            return value.strip()
    return None


def proxy_models(defaults_path: Path = DEFAULTS_PATH, local_path: Path = LOCAL_CONFIG_PATH) -> list[str]:
    config = deep_merge(load_toml(defaults_path, required=True), load_toml(local_path, required=False))
    proxy = config.get("proxy", {})
    base_url = str(proxy.get("base_url", "http://127.0.0.1:8317/v1")).rstrip("/")
    config_path = Path(str(proxy.get("config_path", PROXY_CONFIG_PATH))).expanduser()
    key = read_proxy_key(config_path)
    from urllib.error import HTTPError, URLError
    from urllib.request import Request, urlopen

    headers = {"Authorization": f"Bearer {key}"} if key else {}
    request = Request(f"{base_url}/models", headers=headers)
    try:
        with urlopen(request, timeout=5) as response:
            payload = json.load(response)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        raise HumanizeError(f"CLIProxyAPI model query failed: {type(error).__name__}") from error
    models = payload.get("data", []) if isinstance(payload, dict) else []
    result = sorted(
        value["id"]
        for value in models
        if isinstance(value, dict) and isinstance(value.get("id"), str) and value["id"].strip()
    )
    if not result:
        raise HumanizeError("CLIProxyAPI returned no models")
    return result


def save_model(model: str, path: Path = LOCAL_CONFIG_PATH) -> None:
    if not model or any(character in model for character in ('"', "\n", "\r")):
        raise HumanizeError("Model name is empty or contains invalid TOML characters")
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    llm_start: int | None = None
    llm_end = len(lines)
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "[llm]":
            llm_start = index
            continue
        if llm_start is not None and index > llm_start and stripped.startswith("["):
            llm_end = index
            break
    model_line = f'model = "{model}"'
    if llm_start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["[llm]", model_line])
    else:
        model_index = next(
            (index for index in range(llm_start + 1, llm_end) if re.match(r"^\s*model\s*=", lines[index])),
            None,
        )
        if model_index is None:
            lines.insert(llm_start + 1, model_line)
        else:
            lines[model_index] = model_line
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(path, "\n".join(lines) + "\n", refuse_existing=False, mode=0o600)


def read_niutrans_key() -> str:
    command = [
        "security",
        "find-generic-password",
        "-a",
        os.environ.get("USER", ""),
        "-s",
        KEYCHAIN_SERVICE,
        "-w",
    ]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        raise HumanizeError("Niutrans key is not configured. Run: humanize-text configure") from error
    key = result.stdout.strip()
    if not key:
        raise HumanizeError("Niutrans key is empty. Run: humanize-text configure")
    return key


@contextlib.contextmanager
def without_upstream_env_overrides() -> Iterator[None]:
    saved = {name: os.environ.pop(name) for name in ENV_OVERRIDES if name in os.environ}
    try:
        yield
    finally:
        os.environ.update(saved)


def make_cloud_rewriter(settings: RunSettings) -> Callable[[str], str]:
    proxy_key = read_proxy_key(settings.proxy_config)
    niutrans_key = read_niutrans_key()
    config = {
        "api_keys": {
            "deepseek_api_key": proxy_key or "local-no-auth",
            "niutrans_api_key": niutrans_key,
        },
        "llm": {
            "provider": "deepseek",
            "base_url": settings.proxy_url,
            "model": settings.model,
            "temperature": settings.temperature,
        },
        "pipeline": {
            "model": settings.model,
            "temperature": settings.temperature,
            "intermediate_lang": settings.intermediate_language,
        },
    }

    def rewrite(text: str) -> str:
        if not text.strip():
            return text
        try:
            from src.standard.pipeline import run_standard_pipeline

            with without_upstream_env_overrides():
                result = run_standard_pipeline(text, config, target_lang="en")
        except Exception as error:
            raise HumanizeError(f"Cloud pipeline failed: {type(error).__name__}") from error
        output = result.get("result", "")
        if not isinstance(output, str) or not output.strip():
            raise HumanizeError("Cloud pipeline returned empty output")
        return output

    return rewrite


def split_plain_paragraphs(text: str) -> list[tuple[bool, str]]:
    parts = re.split(r"(\n[ \t]*\n+)", text)
    return [(not bool(re.fullmatch(r"\n[ \t]*\n+", part)), part) for part in parts if part]


def rewrite_plain(text: str, paragraphs: bool, rewrite: Callable[[str], str]) -> str:
    if not text.strip():
        raise HumanizeError("Input is empty")
    if not paragraphs:
        return rewrite(text)
    result: list[str] = []
    for is_content, part in split_plain_paragraphs(text):
        result.append(rewrite(part) if is_content and part.strip() else part)
    return "".join(result)


def run_guard(operation: str, payload: dict[str, Any], adapter: Path = GUARD_ADAPTER) -> dict[str, Any]:
    if not adapter.is_file():
        raise HumanizeError(f"Typst guard adapter is missing: {adapter}")
    command = ["nvim", "--headless", "-u", "NONE", "-l", str(adapter), operation]
    try:
        result = subprocess.run(
            command,
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError as error:
        raise HumanizeError("Neovim is required for the Typst guard") from error
    except subprocess.CalledProcessError as error:
        try:
            reported = json.loads(error.stdout or "").get("error")
        except (json.JSONDecodeError, AttributeError):
            reported = None
        if isinstance(reported, str) and reported:
            raise HumanizeError(f"Typst guard {operation} failed: {reported}") from error
        diagnostic = (error.stderr or "").strip().splitlines()
        suffix = f": {diagnostic[-1]}" if diagnostic else ""
        raise HumanizeError(f"Typst guard {operation} failed{suffix}") from error
    try:
        decoded = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise HumanizeError(f"Typst guard {operation} returned invalid JSON") from error
    if not isinstance(decoded, dict):
        raise HumanizeError(f"Typst guard {operation} returned an invalid result")
    return decoded


def rewrite_typst(
    source: str,
    paragraphs: bool,
    rewrite: Callable[[str], str],
    *,
    guard: Callable[[str, dict[str, Any]], dict[str, Any]] = run_guard,
) -> str:
    prepared = guard("prepare", {"source": source, "paragraph_mode": paragraphs})
    chunks = prepared.get("chunks")
    plan = prepared.get("plan")
    if not isinstance(chunks, list) or not isinstance(plan, dict):
        raise HumanizeError("Typst guard returned an invalid preparation plan")
    outputs: list[dict[str, str]] = []
    for index, chunk in enumerate(chunks, start=1):
        if (
            not isinstance(chunk, dict)
            or not isinstance(chunk.get("id"), (str, int))
            or not isinstance(chunk.get("text"), str)
        ):
            raise HumanizeError("Typst guard returned an invalid chunk")
        try:
            output = rewrite(chunk["text"])
        except HumanizeError as error:
            raise HumanizeError(f"Paragraph {index} failed: {error}") from error
        outputs.append({"id": chunk["id"], "text": output})
    restored = guard("restore", {"plan": plan, "outputs": outputs})
    result = restored.get("source")
    if not isinstance(result, str):
        raise HumanizeError("Typst guard returned an invalid reconstruction")
    return result


def command_result(command: Sequence[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, capture_output=True, text=True)


def find_standalone(path: Path) -> Path | None:
    for directory in (path.parent, *path.parents):
        candidate = directory / "standalone.typ"
        if candidate.is_file():
            return candidate
    return None


def expand_compile_command(template: Sequence[str], *, proposal: Path, output: Path, relative_file: str) -> list[str]:
    replacements = {
        "file": str(proposal),
        "output": str(output),
        "relative_file": relative_file,
    }
    try:
        return [part.format(**replacements) for part in template]
    except KeyError as error:
        raise HumanizeError(f"Unknown Typst compile placeholder: {error.args[0]}") from error


def compile_typst_proposal(target: Path, proposal_text: str, settings: RunSettings) -> None:
    target = target.resolve()
    temporary: Path | None = None
    try:
        descriptor, name = tempfile.mkstemp(prefix=".humanize-", suffix=".typ", dir=target.parent)
        os.close(descriptor)
        temporary = Path(name)
        temporary.write_text(proposal_text, encoding="utf-8")
        with tempfile.TemporaryDirectory(prefix="humanize-typst-") as output_directory:
            output = Path(output_directory) / "check.pdf"
            relative = temporary.name
            if settings.compile_command:
                command = expand_compile_command(
                    settings.compile_command,
                    proposal=temporary,
                    output=output,
                    relative_file=relative,
                )
                cwd = target.parent
            else:
                standalone = find_standalone(target)
                if standalone:
                    relative = str(temporary.relative_to(standalone.parent))
                    command = [
                        "typst",
                        "compile",
                        str(standalone),
                        str(output),
                        "--input",
                        f"chapter={relative}",
                    ]
                    cwd = standalone.parent
                else:
                    command = ["typst", "compile", str(temporary), str(output)]
                    cwd = target.parent
            result = command_result(command, cwd)
            if result.returncode != 0:
                lines = (result.stderr or result.stdout or "").strip().splitlines()
                detail = lines[-1] if lines else "unknown compile error"
                raise HumanizeError(f"Typst compile check failed: {detail}")
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def atomic_write(path: Path, text: str, *, refuse_existing: bool, mode: int | None = None) -> None:
    path = path.resolve()
    if refuse_existing and path.exists():
        raise HumanizeError(f"Output already exists: {path}")
    if not path.parent.is_dir():
        raise HumanizeError(f"Output directory does not exist: {path.parent}")
    chosen_mode = mode
    if chosen_mode is None:
        chosen_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.chmod(temporary, chosen_mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def jj_root(path: Path) -> Path:
    result = command_result(["jj", "root"], path.parent)
    if result.returncode != 0:
        raise HumanizeError("Default Typst output needs a JJ repository; use --write or --output")
    return Path(result.stdout.strip()).resolve()


def require_clean_jj(root: Path, target: Path) -> str:
    status = command_result(["jj", "status", "--no-pager"], root)
    if status.returncode != 0 or "The working copy has no changes." not in status.stdout:
        raise HumanizeError("JJ working copy is not clean; use --write or --output")
    relative = str(target.resolve().relative_to(root))
    tracked = command_result(["jj", "file", "list", relative], root)
    if tracked.returncode != 0 or relative not in tracked.stdout.splitlines():
        raise HumanizeError("Default commit mode requires an existing tracked file")
    return relative


def changed_files(root: Path) -> list[str]:
    result = command_result(["jj", "diff", "--name-only"], root)
    if result.returncode != 0:
        raise HumanizeError("Could not inspect JJ changes")
    return [line for line in result.stdout.splitlines() if line]


def write_and_commit(target: Path, proposal: str, message: str, settings: RunSettings) -> None:
    root = jj_root(target)
    relative = require_clean_jj(root, target)
    original = target.read_text(encoding="utf-8")
    try:
        atomic_write(target, proposal, refuse_existing=False)
        compile_typst_proposal(target, proposal, settings)
        if changed_files(root) != [relative]:
            raise HumanizeError("JJ change isolation failed; only the requested file may change")
        committed = command_result(["jj", "commit", "-m", message], root)
        if committed.returncode != 0:
            raise HumanizeError("JJ could not create the revision commit")
    except Exception:
        if changed_files(root):
            atomic_write(target, original, refuse_existing=False)
        raise


def write_in_place(target: Path, proposal: str, *, typst: bool, settings: RunSettings) -> None:
    original = target.read_text(encoding="utf-8")
    try:
        atomic_write(target, proposal, refuse_existing=False)
        if typst:
            compile_typst_proposal(target, proposal, settings)
    except Exception:
        atomic_write(target, original, refuse_existing=False)
        raise


def default_commit_message(path: Path) -> str:
    return f"docs(manuscript): revise {path.stem} prose"


def make_parser(*, clipboard: bool) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="humanize-clipboard" if clipboard else "humanize-text",
        description="Run the pinned humanize-text cloud chain with atomic output handling.",
    )
    if clipboard:
        parser.add_argument("--typst", action="store_true", help="Treat clipboard text as a Typst fragment")
    else:
        parser.add_argument("file", nargs="?", type=Path, help="Input file; .typ enables the Typst guard")
        parser.add_argument("--text", help="Use literal text instead of a file or stdin")
        sink = parser.add_mutually_exclusive_group()
        sink.add_argument("--write", action="store_true", help="Update the input file without committing")
        sink.add_argument("--output", type=Path, help="Write a new output file")
        sink.add_argument("--stdout", action="store_true", help="Write to stdout instead of the default Typst commit")
        parser.add_argument("--message", help="Override the default JJ commit description")
    paragraph = parser.add_mutually_exclusive_group()
    paragraph.add_argument(
        "--paragraphs", dest="paragraphs", action="store_true", help="Process each paragraph separately"
    )
    paragraph.add_argument("--whole", dest="paragraphs", action="store_false", help="Process all prose in one request")
    parser.set_defaults(paragraphs=None)
    parser.add_argument("--temperature", type=float, help="Override the preset temperature")
    return parser


def read_input(args: argparse.Namespace, *, clipboard: bool) -> tuple[str, Path | None, bool]:
    if clipboard:
        try:
            result = subprocess.run(["pbpaste"], check=True, capture_output=True, text=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as error:
            raise HumanizeError("Could not read the macOS clipboard") from error
        return result.stdout, None, bool(args.typst)
    if args.text is not None and args.file is not None:
        raise HumanizeError("Choose either FILE or --text")
    if args.text is not None:
        return args.text, None, False
    if args.file is not None:
        target = args.file.expanduser().resolve()
        if not target.is_file():
            raise HumanizeError(f"Input file does not exist: {target}")
        try:
            return target.read_text(encoding="utf-8"), target, target.suffix.lower() == ".typ"
        except UnicodeDecodeError as error:
            raise HumanizeError("Input file must be UTF-8 text") from error
    if sys.stdin.isatty():
        raise HumanizeError("Pass FILE, --text, or pipe text on stdin")
    return sys.stdin.read(), None, False


def publish(
    result: str,
    *,
    args: argparse.Namespace,
    clipboard: bool,
    target: Path | None,
    typst: bool,
    settings: RunSettings,
) -> None:
    if clipboard:
        try:
            subprocess.run(["pbcopy"], input=result, text=True, check=True)
        except (FileNotFoundError, subprocess.CalledProcessError) as error:
            raise HumanizeError("Could not update the macOS clipboard") from error
        return
    if args.output is not None:
        atomic_write(args.output.expanduser(), result, refuse_existing=True)
        return
    if args.write:
        if target is None:
            raise HumanizeError("--write requires a file input")
        write_in_place(target, result, typst=typst, settings=settings)
        return
    if typst and target is not None and not args.stdout:
        write_and_commit(target, result, args.message or default_commit_message(target), settings)
        return
    if args.message:
        raise HumanizeError("--message only applies to default Typst commit mode")
    sys.stdout.write(result)
    if result and not result.endswith("\n"):
        sys.stdout.write("\n")


def run(argv: Sequence[str] | None = None, *, program: str | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    executable = Path(program or sys.argv[0]).name
    clipboard = executable == "humanize-clipboard"
    if not clipboard and arguments[:1] == ["configure"]:
        if len(arguments) != 1:
            raise HumanizeError("configure takes no arguments")
        if not CONFIGURE_WIZARD.is_file():
            raise HumanizeError(f"Configuration wizard is missing: {CONFIGURE_WIZARD}")
        return subprocess.run(["bash", str(CONFIGURE_WIZARD)]).returncode
    if not clipboard and arguments[:1] == ["models"]:
        if len(arguments) != 1:
            raise HumanizeError("models takes no arguments")
        print("\n".join(proxy_models()))
        return 0
    if not clipboard and arguments[:1] == ["save-model"]:
        if len(arguments) != 2:
            raise HumanizeError("save-model needs one model name")
        save_model(arguments[1])
        return 0

    parser = make_parser(clipboard=clipboard)
    args = parser.parse_args(arguments)
    source, target, typst = read_input(args, clipboard=clipboard)
    preset = "typst" if typst else "plain"
    settings = load_settings(
        preset,
        temperature=args.temperature,
        paragraph_override=args.paragraphs,
    )
    rewriter = make_cloud_rewriter(settings)
    if typst:
        result = rewrite_typst(source, settings.paragraphs, rewriter)
        if target is not None:
            compile_typst_proposal(target, result, settings)
    else:
        result = rewrite_plain(source, settings.paragraphs, rewriter)
    publish(result, args=args, clipboard=clipboard, target=target, typst=typst, settings=settings)
    return 0


def main() -> None:
    try:
        raise SystemExit(run())
    except HumanizeError as error:
        print(f"humanize-text: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
