#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["tomlkit"]
# ///
"""Record approved mise declarations while preserving unrelated TOML edits."""

from __future__ import annotations

import argparse
from collections.abc import Mapping, MutableMapping, MutableSequence, Sequence
from copy import deepcopy
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

import tomlkit


MISSING = object()


def read_toml(path: Path, missing_ok: bool = False):
    if not path.exists():
        if missing_ok:
            return tomlkit.document()
        raise ValueError(f"file does not exist: {path}")
    try:
        return tomlkit.parse(path.read_text(encoding="utf-8"))
    except (OSError, tomlkit.exceptions.TOMLKitError) as exc:
        raise ValueError(f"cannot read TOML file {path}: {exc}") from exc


def get_path(value, path):
    for key in path:
        if not isinstance(value, Mapping) or key not in value:
            return MISSING
        value = value[key]
    return value


def plain(value):
    if value is MISSING:
        return MISSING
    if hasattr(value, "unwrap"):
        value = value.unwrap()
    if isinstance(value, Mapping):
        return {str(key): plain(item) for key, item in value.items()}
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        return [plain(item) for item in value]
    return value


def table_at(parent, key):
    value = parent.get(key)
    if value is None:
        value = tomlkit.table()
        parent[key] = value
    if not isinstance(value, MutableMapping):
        raise ValueError(f"{key!r} is not a TOML table")
    return value


def keep_comment(old, new):
    old_trivia = getattr(old, "trivia", None)
    new_trivia = getattr(new, "trivia", None)
    if old_trivia is not None and new_trivia is not None:
        new_trivia.comment = old_trivia.comment
    return new


def atomic_write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def check_unchanged(current, snapshot, paths):
    for path in paths:
        if plain(get_path(current, path)) != plain(get_path(snapshot, path)):
            raise ValueError(f"target changed since snapshot at {'.'.join(path)}; refusing to overwrite it")


def record_package(args):
    target = Path(args.target).resolve()
    staged = read_toml(Path(args.staged_config))
    snapshot = read_toml(Path(args.before))
    desired = get_path(staged, ("bootstrap", "packages", args.key))
    if desired is MISSING:
        raise ValueError(f"staged config has no bootstrap.packages entry for {args.key!r}")

    current = read_toml(target, missing_ok=True)
    paths = [("bootstrap", "packages", args.key)]
    if args.replace_key and args.replace_key != args.key:
        paths.append(("bootstrap", "packages", args.replace_key))
    check_unchanged(current, snapshot, paths)

    packages = table_at(table_at(current, "bootstrap"), "packages")
    existing = packages.get(args.key, MISSING)
    changed = plain(existing) != plain(desired)
    if changed:
        packages[args.key] = keep_comment(existing, deepcopy(desired)) if existing is not MISSING else deepcopy(desired)
    if args.replace_key and args.replace_key != args.key and args.replace_key in packages:
        del packages[args.replace_key]
        changed = True
    if changed:
        atomic_write(target, tomlkit.dumps(current))
    return changed


def split_options(request: str):
    """Remove balanced bracket groups while respecting quoted/nested values."""
    base, groups, index = [], [], 0
    while index < len(request):
        if request[index] != "[":
            base.append(request[index])
            index += 1
            continue
        start, depth, quote, escaped = index + 1, 1, None, False
        index += 1
        while index < len(request) and depth:
            char = request[index]
            if quote:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
            elif char in "\"'":
                quote = char
            elif char == "[":
                depth += 1
            elif char == "]":
                depth -= 1
                if not depth:
                    groups.append(request[start:index])
            index += 1
        if depth:
            raise ValueError("unterminated tool option group")
    options = []
    for group in groups:
        start, quote, escaped, depth = 0, None, False, 0
        for index, char in enumerate(group):
            if quote:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
            elif char in "\"'":
                quote = char
            elif char in "([{":
                depth += 1
            elif char in ")]}" and depth:
                depth -= 1
            elif char == "," and depth == 0:
                options.append(group[start:index].strip())
                start = index + 1
        options.append(group[start:].strip())
    if any(not option for option in options):
        raise ValueError("empty tool option in bracket group")
    return "".join(base).strip(), options


def parse_request(request: str):
    base, raw_options = split_options(request.strip())
    if not base or any(char.isspace() for char in base):
        raise ValueError("tool request must contain one mise TOOL@VERSION argument")
    delimiter = base.rfind("@")
    if base.startswith("npm:@") and delimiter == len("npm:"):
        delimiter = -1  # scoped package marker, not a version
    key, version = (base, "latest") if delimiter < 0 else (base[:delimiter], base[delimiter + 1 :])
    if not key or key.endswith(":") or not version:
        raise ValueError("tool name and explicit version cannot be empty")

    options = {}
    for option in raw_options:
        if "=" not in option:
            raise ValueError(f"tool option must be key=value: {option!r}")
        name, raw_value = (part.strip() for part in option.split("=", 1))
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name) or name == "version":
            raise ValueError(f"invalid tool option name: {name!r}")
        if not raw_value:
            raise ValueError(f"tool option value cannot be empty: {name}")
        if name in options:
            raise ValueError(f"tool option supplied more than once: {name}")
        if not raw_value:
            raise ValueError("tool option value cannot be empty")
        try:
            options[name] = tomlkit.parse(f"value = {raw_value}")["value"]
        except tomlkit.exceptions.TOMLKitError:
            if raw_value.startswith(("\"", "'")):
                raise ValueError(f"invalid quoted tool option value: {raw_value}")
            options[name] = raw_value  # mise treats a bare value such as pcre2 as a string
    return key, version, options


def inline_declaration(version, options):
    item = tomlkit.inline_table()
    item.append("version", version)
    for name, value in options.items():
        item.append(name, deepcopy(value))
    return item


def update_tool(existing, version, options):
    if existing is MISSING:
        return inline_declaration(version, options)
    if isinstance(existing, MutableMapping):
        updated = deepcopy(existing)
        old_version = updated.get("version", MISSING)
        updated["version"] = keep_comment(old_version, tomlkit.string(version)) if old_version is not MISSING else version
        for name, value in options.items():
            old_value = updated.get(name, MISSING)
            updated[name] = keep_comment(old_value, deepcopy(value)) if old_value is not MISSING else deepcopy(value)
        return updated
    if isinstance(existing, MutableSequence):
        updated = deepcopy(existing)
        for index, item in enumerate(updated):
            if isinstance(item, Mapping) and plain(item.get("version", MISSING)) == version:
                updated[index] = update_tool(item, version, options)
                return updated
        updated.append(inline_declaration(version, options))
        return updated
    if not options:
        return keep_comment(existing, tomlkit.string(version))
    return keep_comment(existing, inline_declaration(version, options))


def show_tool(target: Path, request: str):
    key, version, options = parse_request(request)
    current = read_toml(target, missing_ok=True)
    existing = get_path(current, ("tools", key))
    display = tomlkit.document()
    tools = tomlkit.table()
    tools[key] = deepcopy(update_tool(existing, version, options))
    display["tools"] = tools
    return tomlkit.dumps(display)


def record_tool(args):
    target = Path(args.target).resolve()
    snapshot = read_toml(Path(args.before))
    current = read_toml(target, missing_ok=True)
    key, version, options = parse_request(args.request)
    check_unchanged(current, snapshot, [("tools", key)])
    tools = table_at(current, "tools")
    old = tools.get(key, MISSING)
    updated = update_tool(old, version, options)
    if old is not MISSING and plain(old) == plain(updated):
        return False
    tools[key] = updated
    atomic_write(target, tomlkit.dumps(current))
    return True


def stage_tools(args):
    """Copy static tool declarations without carrying target executable config."""
    source = read_toml(Path(args.source), missing_ok=True)
    tools = get_path(source, ("tools",))
    if tools is MISSING:
        tools = tomlkit.table()
    if not isinstance(tools, Mapping):
        raise ValueError("tools is not a TOML table")

    def reject_templates(value):
        if isinstance(value, Mapping):
            for key, item in value.items():
                reject_templates(key)
                reject_templates(item)
        elif isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
            for item in value:
                reject_templates(item)
        elif isinstance(value, str) and any(marker in value for marker in ("{{", "{%")):
            raise ValueError("templated tool declarations cannot be staged safely; use mise directly from the trusted target")

    key, _, _ = parse_request(args.request)
    selected = tomlkit.table()
    if key in tools:
        reject_templates(plain(tools[key]))
        selected[key] = deepcopy(tools[key])
    staged = tomlkit.document()
    staged["tools"] = selected
    atomic_write(Path(args.staged_config), tomlkit.dumps(staged))


def record_tools(args):
    target = Path(args.target).resolve()
    staged = read_toml(Path(args.staged_config))
    snapshot = read_toml(Path(args.before))
    current = read_toml(target, missing_ok=True)
    staged_tools = get_path(staged, ("tools",))
    stage_before = read_toml(Path(args.staged_before)) if args.staged_before else snapshot
    before_tools = get_path(stage_before, ("tools",))
    current_tools = get_path(current, ("tools",))
    staged_tools = staged_tools if isinstance(staged_tools, Mapping) else {}
    before_tools = before_tools if isinstance(before_tools, Mapping) else {}
    current_tools = current_tools if isinstance(current_tools, Mapping) else {}
    keys = set(staged_tools) | set(before_tools)
    changed = [key for key in keys if plain(staged_tools.get(key, MISSING)) != plain(before_tools.get(key, MISSING))]
    check_unchanged(current, snapshot, [("tools", key) for key in changed])
    if not changed:
        return 0

    tools = table_at(current, "tools")
    writes = False
    for key in changed:
        desired = staged_tools.get(key, MISSING)
        existing = tools.get(key, MISSING)
        if desired is MISSING:
            if existing is not MISSING:
                del tools[key]
                writes = True
        elif plain(existing) != plain(desired):
            tools[key] = keep_comment(existing, deepcopy(desired)) if existing is not MISSING else deepcopy(desired)
            writes = True
    if writes:
        atomic_write(target, tomlkit.dumps(current))
    return len(changed) if writes else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    package = commands.add_parser("record-package")
    package.add_argument("target")
    package.add_argument("staged_config")
    package.add_argument("key")
    package.add_argument("--replace-key")
    package.add_argument("--before", required=True)
    package.set_defaults(run=record_package)
    tool = commands.add_parser("record-tool")
    tool.add_argument("target")
    tool.add_argument("request")
    tool.add_argument("--before", required=True)
    tool.set_defaults(run=record_tool)
    tools = commands.add_parser("record-tools")
    tools.add_argument("target")
    tools.add_argument("staged_config")
    tools.add_argument("--before", required=True)
    tools.add_argument("--staged-before")
    tools.set_defaults(run=record_tools)
    stage = commands.add_parser("stage-tools")
    stage.add_argument("source")
    stage.add_argument("staged_config")
    stage.add_argument("request")
    stage.set_defaults(run=stage_tools)
    show = commands.add_parser("show-tool")
    show.add_argument("target")
    show.add_argument("request")
    show.set_defaults(run=lambda args: print(show_tool(Path(args.target), args.request)) or False)
    args = parser.parse_args()
    try:
        args.run(args)
    except (OSError, ValueError, tomlkit.exceptions.TOMLKitError) as exc:
        print(f"dots: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
