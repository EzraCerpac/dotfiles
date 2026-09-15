"""Render one native mise Tera dotfile into an isolated test home."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
MISE = Path(os.environ.get("SETUP_TEST_MISE") or shutil.which("mise") or "mise")


def _toml_value(value: Any) -> str:
    if isinstance(value, (str, bool, int, float)):
        return json.dumps(value)
    if isinstance(value, list):
        return "[" + ", ".join(_toml_value(item) for item in value) + "]"
    raise TypeError(f"unsupported Tera fixture value: {type(value).__name__}")


def read_string_vars(config: str | Path, keys: list[str]) -> dict[str, str]:
    """Read selected basic-string assignments from a mise ``[vars]`` table."""
    wanted = set(keys)
    found: dict[str, str] = {}
    in_vars = False
    assignment = re.compile(r'^([A-Za-z0-9_-]+)\s*=\s*("(?:\\.|[^"\\])*")\s*$')
    for line in Path(config).read_text().splitlines():
        table = line.strip()
        if table.startswith("[") and table.endswith("]"):
            in_vars = table == "[vars]"
            continue
        if not in_vars:
            continue
        match = assignment.fullmatch(line.strip())
        if match and match.group(1) in wanted:
            value = json.loads(match.group(2))
            if not isinstance(value, str):
                raise TypeError(f"mise variable {match.group(1)} must be a string")
            found[match.group(1)] = value
    missing = wanted - found.keys()
    if missing:
        raise KeyError(f"missing mise variables in {config}: {', '.join(sorted(missing))}")
    return found


def render_template(
    source: str | Path,
    *,
    target: str | Path,
    scratch: str | Path,
    vars: dict[str, Any] | None = None,
    env: dict[str, str] | None = None,
) -> str:
    """Render ``source`` at an absolute target beneath ``scratch`` using mise.

    Each call gets its own home, config, data, state, and cache directories.
    Only the requested target is declared, so the command cannot apply the
    repository's real dotfile set.
    """
    source_path = Path(source).resolve(strict=True)
    target_path = Path(target)
    scratch_path = Path(scratch).resolve()
    if not source_path.is_relative_to(ROOT.resolve()):
        raise ValueError("Tera fixture source must be beneath the repository")
    if not scratch_path.is_relative_to(Path(tempfile.gettempdir()).resolve()):
        raise ValueError("Tera fixture scratch directory must be beneath the system temp root")
    if not target_path.is_absolute():
        raise ValueError("Tera fixture target must be absolute")
    target_path = target_path.resolve()
    if not target_path.is_relative_to(scratch_path):
        raise ValueError("Tera fixture target must be beneath its scratch directory")
    if not MISE.is_file():
        raise FileNotFoundError(f"staged mise binary is missing: {MISE}")

    home = scratch_path / "home"
    config = scratch_path / "mise-config"
    cache = scratch_path / "mise-cache"
    data = scratch_path / "mise-data"
    state = scratch_path / "mise-state"
    for directory in (home, config, cache, data, state, target_path.parent):
        directory.mkdir(parents=True, exist_ok=True)

    config_text = [
        'min_version = "2026.9.7"',
        "",
        "[settings]",
        f"dotfiles.root = {json.dumps(str(ROOT))}",
        "",
        "[vars]",
    ]
    config_text.extend(
        f"{name} = {_toml_value(value)}" for name, value in (vars or {}).items()
    )
    config_text.extend(
        [
            "",
            "[dotfiles]",
            f"{json.dumps(str(target_path))} = {{ source = {json.dumps(str(source_path))}, mode = \"template\" }}",
            "",
        ]
    )
    (config / "mise.toml").write_text("\n".join(config_text))

    command_env = {
        "HOME": str(home),
        "USER": "mise-template-fixture",
        "PATH": os.defpath,
        "TMPDIR": str(scratch_path),
        "MISE_CONFIG_DIR": str(config),
        "MISE_CACHE_DIR": str(cache),
        "MISE_DATA_DIR": str(data),
        "MISE_STATE_DIR": str(state),
        "MISE_TRUSTED_CONFIG_PATHS": str(config),
        "MISE_NO_AUTO_INSTALL": "1",
        "MISE_NO_HOOKS": "1",
    }
    command_env.update(env or {})
    subprocess.run(
        [str(MISE), "--cd", str(config), "bootstrap", "dotfiles", "apply", "--yes", str(target_path)],
        env=command_env,
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return target_path.read_text()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source")
    parser.add_argument("--target")
    parser.add_argument("--scratch")
    parser.add_argument("--vars-json", default="{}")
    parser.add_argument("--env-json", default="{}")
    parser.add_argument("--read-vars")
    parser.add_argument("--var-key", action="append", default=[])
    arguments = parser.parse_args()
    if arguments.read_vars:
        print(json.dumps(read_string_vars(arguments.read_vars, arguments.var_key)))
        raise SystemExit(0)
    if not all((arguments.source, arguments.target, arguments.scratch)):
        parser.error("--source, --target, and --scratch are required for rendering")
    rendered = render_template(
        arguments.source,
        target=arguments.target,
        scratch=arguments.scratch,
        vars=json.loads(arguments.vars_json),
        env=json.loads(arguments.env_json),
    )
    print(rendered, end="")
