#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["tomlkit"]
# ///
"""Remove setup declarations using their native installer, preserving app data."""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

import tomlkit


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


editor = load_module("dots_remove_editor", "dots-add-config.py")
github = load_module("dots_remove_github", "dots-github.py")
MANAGERS = {"brew", "brew-cask", "apt", "dnf", "pacman", "apk", "mas"}


def state_directory():
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "dots/github-apps"


def active_configs(mise, root):
    result = subprocess.run([mise, "-C", str(root), "config", "ls", "--json"], check=True, capture_output=True, text=True)
    files = json.loads(result.stdout)
    if not isinstance(files, list):
        raise ValueError("mise returned an invalid active config list")
    return list(dict.fromkeys(Path(item["path"]).resolve() for item in files
                              if Path(item["path"]).resolve().is_relative_to(root)))


def canonical(key):
    if key.startswith("github:"):
        return "github:" + github.repository("https://github.com/" + key[7:])
    return key


def aliases(key):
    result = {canonical(key).casefold()}
    tail = key.partition(":")[2] if ":" in key else key
    result.add(tail.casefold())
    result.add(tail.rsplit("/", 1)[-1].casefold())
    return result


def app_records(state):
    records = {}
    for marker in state.glob("*.json"):
        try:
            owner = json.loads(marker.read_text())
            if not isinstance(owner, dict) or not isinstance(owner.get("repo"), str):
                continue
            identity = canonical("github:" + owner["repo"])
        except (ValueError, OSError):
            continue
        records.setdefault(identity, []).append((marker, owner))
    return records


def discover(paths):
    declarations = {}
    for path in paths:
        document = editor.read_toml(path)
        for section in (("tools",), ("bootstrap", "packages")):
            table = editor.get_path(document, section)
            if table is editor.MISSING:
                continue
            if not isinstance(table, dict) and not hasattr(table, "items"):
                raise ValueError(f"{path}: {'.'.join(section)} must be a table")
            for key, value in table.items():
                if section != ("tools",) and key.partition(":")[0] not in MANAGERS:
                    continue
                declarations.setdefault(canonical(key), []).append({
                    "path": path, "section": section, "key": key, "value": deepcopy(value),
                })
    return declarations


def resolve(targets, declarations, records):
    index = {}
    for identity, entries in declarations.items():
        names = aliases(entries[0]["key"])
        for marker, owner in records.get(identity, []):
            if isinstance(owner.get("path"), str):
                names.add(Path(owner["path"]).stem.casefold())
        for name in names:
            index.setdefault(name, set()).add(identity)
    # Ownership survives --keep-installed, allowing a later full uninstall.
    for identity, owners in records.items():
        for name in aliases(identity) | {Path(owner["path"]).stem.casefold()
                                        for _, owner in owners if isinstance(owner.get("path"), str)}:
            index.setdefault(name, set()).add(identity)
    selected = []
    for request in targets:
        name = "github:" + github.repository(request) if request.startswith("https://") else canonical(request)
        if name.startswith("mise:") and ":" not in name[5:]:
            bare = name[5:]
            matches = {bare} if bare in declarations and any(entry["section"] == ("tools",) for entry in declarations[bare]) else set()
        else:
            matches = {name} if ":" in name and (name in declarations or name in records) else index.get(name.casefold(), set())
        if not matches:
            raise ValueError(f"no declaration or managed app matches {request!r}")
        if len(matches) != 1:
            choices = sorted(identity if ":" in identity else f"mise:{identity}" for identity in matches)
            raise ValueError(f"ambiguous target {request!r}; use one of: {', '.join(choices)}")
        identity = next(iter(matches))
        if identity not in selected:
            selected.append(identity)
    return selected


def check_held(identity):
    manager, _, tail = identity.partition(":")
    name = tail.rsplit("/", 1)[-1].split("@", 1)[0]
    if (manager, name) in {("brew", "kanata"), ("brew-cask", "karabiner-elements")}:
        raise ValueError("Kanata and Karabiner are held installer exceptions; change their reviewed hold recipe instead")


def validate_app(identity, marker, owner, applications=Path("/Applications")):
    if marker.is_symlink() or set(owner) != {"repo", "path", "bundle_id"}:
        raise ValueError("invalid managed app ownership; refusing removal")
    if not isinstance(owner["path"], str) or not isinstance(owner["bundle_id"], str):
        raise ValueError("invalid managed app ownership; refusing removal")
    app = Path(owner["path"])
    if (canonical("github:" + owner["repo"]) != identity or app.parent != applications
            or not app.name.endswith(".app") or app.name in {".app", "..app"}
            or marker.name != hashlib.sha256(app.name.encode()).hexdigest() + ".json"
            or app.is_symlink() or app.parent.is_symlink()):
        raise ValueError(f"invalid managed app ownership for {app}; refusing removal")
    if app.exists() and github.validate_bundle(app) != owner["bundle_id"]:
        raise ValueError(f"installed app identity differs at {app}; refusing removal")
    return app


def check_entries(entries):
    for entry in entries:
        current = editor.read_toml(entry["path"])
        actual = editor.get_path(current, (*entry["section"], entry["key"]))
        if editor.plain(actual) != editor.plain(entry["value"]):
            raise ValueError(f"declaration changed since discovery: {entry['path']} {entry['key']}")


def remove_entry(entry):
    check_entries([entry])
    document = editor.read_toml(entry["path"])
    table = editor.get_path(document, entry["section"])
    del table[entry["key"]]
    editor.atomic_write(entry["path"], tomlkit.dumps(document))


def restore_entries(entries):
    # Restore only removed keys; concurrent edits to unrelated declarations survive.
    for entry in entries:
        document = editor.read_toml(entry["path"])
        actual = editor.get_path(document, (*entry["section"], entry["key"]))
        if actual is not editor.MISSING:
            if editor.plain(actual) != editor.plain(entry["value"]):
                raise ValueError(f"cannot restore concurrently changed declaration {entry['key']} in {entry['path']}")
            continue
        table = document
        for component in entry["section"]:
            table = editor.table_at(table, component)
        table[entry["key"]] = deepcopy(entry["value"])
        editor.atomic_write(entry["path"], tomlkit.dumps(document))


def release_sources(mise, root, identity):
    result = subprocess.run([mise, "-C", str(root), "ls", identity, "--json", "--all-sources"],
                            check=True, capture_output=True, text=True)
    installed = json.loads(result.stdout)
    if not isinstance(installed, list):
        raise ValueError("mise returned an invalid installed release list")
    return {Path(source["path"]).resolve() for version in installed for source in version.get("sources", [])
            if source.get("path")}


def prepare(identity, entries, records, keep, packages, shared=False):
    check_held(identity)
    plan = {"identity": identity, "entries": entries, "apps": [], "package": None, "shared": shared}
    if not keep and not shared:
        for marker, owner in records.get(identity, []):
            app = validate_app(identity, marker, owner)
            plan["apps"].append((marker, owner, app))
        package_entries = [entry for entry in entries if entry["section"] != ("tools",)]
        if package_entries:
            manager, _, name = package_entries[0]["key"].partition(":")
            plan["package"] = packages.plan_remove(manager, name)
    return plan


def execute(plan, mise, root, keep, packages):
    entries, moved = plan["entries"], []
    removed_markers = []
    check_entries(entries)
    attempted = []
    try:
        for marker, owner, app in plan["apps"]:
            # Revalidate immediately before moving; never follow a replacement symlink.
            current_owner = json.loads(marker.read_text())
            if current_owner != owner:
                raise ValueError(f"managed app ownership changed since discovery: {marker}")
            validate_app(plan["identity"], marker, current_owner)
            if app.exists():
                trash = Path.home() / ".Trash"
                trash.mkdir(exist_ok=True)
                destination = trash / f"{app.stem}-{uuid.uuid4().hex}{app.suffix}"
                app.rename(destination)
                moved.append((app, destination))
        if plan["package"]:
            packages.execute_remove(plan["package"])
        for entry in entries:
            attempted.append(entry)
            if entry["section"] == ("tools",):
                command = [mise, "-C", str(root), "unuse", "--path", str(entry["path"]), "--no-prune"]
                command.append(entry["key"])
                subprocess.run(command, check=True)
                document = editor.read_toml(entry["path"])
                if editor.get_path(document, ("tools", entry["key"])) is not editor.MISSING:
                    raise ValueError(f"mise unuse did not remove {entry['key']} from {entry['path']}")
            else:
                remove_entry(entry)
        for marker, owner, _ in plan["apps"]:
            if marker.is_symlink() or json.loads(marker.read_text()) != owner:
                raise ValueError(f"managed app ownership changed during removal: {marker}")
            contents = marker.read_bytes()
            marker.unlink()
            removed_markers.append((marker, contents))
        if not keep and (any(entry["section"] == ("tools",) for entry in entries) or plan["apps"]):
            # Finish reversible edits before pruning installed releases. Native
            # targeted pruning also handles marker-only removal and tracked users.
            subprocess.run([mise, "-C", str(root), "prune", "--yes", "--tools", plan["identity"]], check=True)
    except BaseException as original:
        errors = []
        try:
            restore_entries(attempted)
        except (OSError, ValueError) as exc:
            errors.append(str(exc))
        for marker, contents in removed_markers:
            try:
                if marker.exists() or marker.is_symlink():
                    raise ValueError(f"cannot restore changed ownership marker: {marker}")
                editor.atomic_write(marker, contents.decode())
            except (OSError, ValueError) as exc:
                errors.append(str(exc))
        for app, destination in reversed(moved):
            try:
                if app.exists() or app.is_symlink():
                    raise ValueError(f"cannot restore {app}: another app appeared; retained original at {destination}")
                destination.rename(app)
            except (OSError, ValueError) as exc:
                errors.append(str(exc))
        if errors:
            raise ValueError(f"{original}; rollback incomplete: {'; '.join(errors)}") from original
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mise")
    parser.add_argument("root", type=Path)
    selectors = parser.add_mutually_exclusive_group()
    selectors.add_argument("--base", action="store_true")
    selectors.add_argument("--profile", choices=("workstation", "nas"))
    selectors.add_argument("--path", type=Path)
    parser.add_argument("--keep-installed", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("targets", nargs="+")
    args = parser.parse_intermixed_args(argv)
    root = args.root.resolve()
    paths = active_configs(args.mise, root)
    if args.path:
        selected_paths = [args.path.expanduser().resolve()]
    elif args.base:
        selected_paths = [root / "config.toml"]
    elif args.profile:
        selected_paths = [root / f"config.{args.profile}.toml"]
    else:
        selected_paths = paths
    declarations = discover(selected_paths)
    all_declarations = discover(list(dict.fromkeys(paths + selected_paths)))
    records = app_records(state_directory())
    # Explicit selectors may only resolve marker aliases for declarations in that selection.
    if args.path or args.base or args.profile:
        records = {key: value for key, value in records.items() if key in declarations}
    identities = resolve(args.targets, declarations, records)
    packages = load_module("dots_remove_packages", "dots-remove-packages.py")
    plans = []
    for identity in identities:
        entries = declarations.get(identity, [])
        shared = any(entry["path"] not in selected_paths for entry in all_declarations.get(identity, []))
        if records.get(identity) and not args.keep_installed:
            shared = shared or bool(release_sources(args.mise, root, identity) - set(selected_paths))
        plan = prepare(identity, entries, records, args.keep_installed, packages, shared)
        plans.append(plan)
    for plan in plans:
        print(f"{'Forget' if args.keep_installed else 'Remove'} {plan['identity']}", flush=True)
        for entry in plan["entries"]:
            print(f"  declaration: {entry['path']} ({entry['key']})", flush=True)
        for _, _, app in plan["apps"]:
            print(f"  app to Trash: {app}", flush=True)
        if plan["package"]:
            print(f"  {plan['package']['summary']}", flush=True)
        if plan["shared"]:
            print("  retain installed software: another active config still declares it", flush=True)
    if args.dry_run:
        return 0
    completed = []
    for plan in plans:
        try:
            execute(plan, args.mise, root, args.keep_installed, packages)
            completed.append(plan["identity"])
        except BaseException:
            if completed:
                print(f"dots: completed before failure: {', '.join(completed)}", file=sys.stderr)
            raise
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"dots: {exc}", file=sys.stderr)
        sys.exit(1)
