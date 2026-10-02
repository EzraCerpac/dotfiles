#!/usr/bin/env python3
"""Targeted native package removal; config editing belongs to the coordinator."""

import json
import os
from pathlib import Path
import re
import subprocess


MANAGERS = {"brew", "brew-cask", "apt", "dnf", "pacman", "apk", "mas"}


def environment():
    # Homebrew uninstall otherwise automatically removes unused dependencies.
    return {**os.environ, "LC_ALL": "C", "HOMEBREW_NO_AUTOREMOVE": "1",
            "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_COLOR": "1"}


def probe(command, allowed=(0,)):
    result = subprocess.run(command, capture_output=True, text=True, env=environment())
    if result.returncode not in allowed:
        raise ValueError(f"{' '.join(command)} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result


def privileged(command):
    return command if os.geteuid() == 0 else ["sudo", *command]


def only_target(names, name):
    if len(names) != 1 or names[0] != name:
        raise ValueError(f"refusing transaction for {name}: expected only that package, got {', '.join(names) or 'no removals'}")


def validate_name(manager, name):
    if manager not in MANAGERS:
        raise ValueError(f"unsupported package manager: {manager}")
    expression = r"[A-Za-z0-9][A-Za-z0-9_.+@/-]*" if manager.startswith("brew") else r"[A-Za-z0-9][A-Za-z0-9_.+:-]*"
    if not re.fullmatch(expression, name) or (manager == "mas" and not name.isdigit()):
        raise ValueError(f"invalid {manager} package name: {name!r}")


def installed_names(manager):
    # Query entire installed-name lists so a missing target cannot hide a broken
    # manager/database behind the same exit code as 'not installed'.
    commands = {
        "apt": ["dpkg-query", "-W", "-f=${Package}:${Architecture} ${db:Status-Status}\\n"],
        "dnf": ["rpm", "-qa", "--qf", "%{NAME}\\n"],
        "pacman": ["pacman", "-Qq"],
        "apk": ["apk", "info"],
        "mas": ["mas", "list"],
    }
    output = probe(commands[manager]).stdout
    if manager == "apt":
        names = {line.split()[0] for line in output.splitlines()
                 if len(line.split()) == 2 and line.split()[1] == "installed"}
        return names | {item.split(":")[0] for item in names}
    if manager == "mas":
        return {line.split()[0] for line in output.splitlines()
                if line.split() and line.split()[0].isdigit()}
    return set(output.splitlines())


def brew_installed_names(manager):
    kind = "--formula" if manager == "brew" else "--cask"
    # --full-name distinguishes identical tokens from different taps and works
    # even when a formula has disappeared from the upstream catalog.
    return probe(["brew", "list", kind, "--full-name", "-1"]).stdout.splitlines()


def brew_identity(manager, name, names):
    builtin = "homebrew/core/" if manager == "brew" else "homebrew/cask/"
    canonical = lambda item: item[len(builtin):] if item.startswith(builtin) else item
    matches = [item for item in names if item == name or
               ("/" not in name and item.rsplit("/", 1)[-1] == name) or
               canonical(item) == canonical(name)]
    if len(matches) > 1:
        raise ValueError(f"ambiguous installed Homebrew package {name}: {', '.join(matches)}")
    return matches[0] if matches else None


def apt_preview(name):
    preview = probe(["apt-get", "--simulate", "--no-auto-remove", "remove", name]).stdout
    return preview, re.findall(r"^Remv (\S+)", preview, re.MULTILINE)


def apt_qualified_name(name, names):
    if ":" in name:
        return name
    identities = [item for item in names if item.startswith(name + ":")]
    if len(identities) == 1:
        return identities[0]
    architecture = probe(["dpkg", "--print-architecture"]).stdout.strip()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", architecture):
        raise ValueError("cannot verify native dpkg architecture")
    return f"{name}:{architecture}"


def apt_selector(name):
    return ":" not in name or name.rsplit(":", 1)[-1] in {"native", "any"}


def apt_identity(name, names, removals=None):
    base = name.split(":")[0]
    if not apt_selector(name):
        return name if name in names else None
    if base not in names:
        return None
    if removals is None:
        _, removals = apt_preview(name)
    # Dependencies may also be removed in the preview. They are irrelevant to
    # shared ownership, but the requested package must resolve to one identity.
    targets = [item for item in removals if item.split(":")[0] == base]
    if not targets and ":" in name:
        return None
    if len(targets) != 1:
        raise ValueError(f"ambiguous apt removal identity for {name}: {', '.join(targets) or 'no target'}")
    selected = apt_qualified_name(targets[0], names)
    if selected not in names:
        raise ValueError(f"cannot verify installed apt package {selected}")
    return selected


def apt_plan(name):
    installed = installed_names("apt")
    if (name.split(":")[0] if apt_selector(name) else name) not in installed:
        return []
    preview, removals = apt_preview(name)
    wildcard = ":" in name and apt_selector(name)
    selected = apt_identity(name, installed, removals) if wildcard else name
    # A selector may select no installed architecture. Other changes still
    # cannot be accepted as an absence check.
    if selected is None and not removals and not re.search(r"^(Inst|Conf) ", preview, re.MULTILINE):
        return []
    # Keep every row, including dependents and duplicate architectures.
    only_target([item.split(":")[0] if ":" not in name else apt_qualified_name(item, installed)
                 for item in removals], name if ":" not in name else selected)
    if re.search(r"^(Inst|Conf) ", preview, re.MULTILINE):
        raise ValueError("refusing apt transaction that installs or configures other packages")
    return [privileged(["apt-get", "--yes", "--no-auto-remove", "remove", selected if wildcard else name])]


def shares_installation(manager, name, other_names):
    """Compare declarations against native installed identities without removing."""
    validate_name(manager, name)
    for other in other_names:
        validate_name(manager, other)
    if name in other_names:
        return True
    if manager.startswith("brew"):
        candidates = [other for other in other_names
                      if name.rsplit("/", 1)[-1] == other.rsplit("/", 1)[-1]
                      and ("/" not in name or "/" not in other)]
        if not candidates:
            return False
        names = brew_installed_names(manager)
        selected = brew_identity(manager, name, names)
        return selected is not None and any(brew_identity(manager, other, names) == selected
                                           for other in candidates)
    if manager == "apt":
        candidates = [other for other in other_names
                      if name.split(":")[0] == other.split(":")[0]
                      and (apt_selector(name) or apt_selector(other))]
        if not candidates:
            return False
        names = installed_names(manager)
        selected = apt_identity(name, names)
        return selected is not None and any(apt_identity(other, names) == selected
                                           for other in candidates)
    return False


def brew_plan(manager, name):
    kind = "--formula" if manager == "brew" else "--cask"
    selected = brew_identity(manager, name, brew_installed_names(manager))
    if selected is None:
        if manager == "brew-cask":
            metadata = json.loads(probe(["brew", "info", "--json=v2", "--cask", name]).stdout)
            casks = metadata.get("casks", [])
            if len(casks) != 1:
                raise ValueError(f"cannot verify unregistered cask {name} is absent")
            app_paths = []
            for artifact in casks[0].get("artifacts", []):
                if "app" not in artifact or set(artifact) - {"app", "target"}:
                    raise ValueError(f"cask {name} has no Homebrew receipt; cannot verify its non-app artifacts are absent; use its reviewed uninstall recipe")
                source = artifact["app"][0]
                target = artifact.get("target")
                options = next((item for item in artifact["app"] if isinstance(item, dict)), {})
                app_name = options.get("target", source)
                app_paths.extend([Path("/Applications") / app_name, Path.home() / "Applications" / app_name])
                if target:
                    app_paths.append(Path(target).expanduser())
            if not app_paths:
                raise ValueError(f"cask {name} has no Homebrew receipt; cannot verify its non-app artifacts are absent; use its reviewed uninstall recipe")
            existing = [str(path) for path in app_paths if path.exists()]
            if existing:
                raise ValueError(f"cask {name} has no Homebrew receipt but an app remains at {', '.join(sorted(set(existing)))}; review ownership before uninstalling it")
        return []
    if manager == "brew":
        users = probe(["brew", "uses", "--installed", "--recursive", selected]).stdout.strip()
        if users:
            raise ValueError(f"cannot remove {selected}; installed dependents: {users}")
    return [["brew", "uninstall", kind, selected]]


def plan_remove(manager, name):
    """Read-only preflight. Return commands, installed status and display summary."""
    validate_name(manager, name)
    token = name.rsplit("/", 1)[-1]
    if (manager == "brew" and token.split("@")[0] == "kanata") or (manager == "brew-cask" and token.split("@")[0] == "karabiner-elements"):
        raise ValueError("Kanata and Karabiner are held installer exceptions; change their reviewed hold recipe instead")

    commands = []
    if manager.startswith("brew"):
        commands = brew_plan(manager, name)
    elif manager == "apt":
        commands = apt_plan(name)
    elif name in installed_names(manager):
        if manager == "dnf":
            # Native RPM dependency checking refuses removal of packages needed
            # by others; DNF defaults to cascading removal, so disable cleanup.
            probe(privileged(["rpm", "-e", "--test", name]))
            options = ["--setopt=clean_requirements_on_remove=False"]
            result = probe(privileged(["dnf", *options, "--assumeno", "remove", name]), allowed=(0, 1))
            preview = result.stdout + result.stderr
            rows = re.findall(r"^\s+([A-Za-z0-9][\w.+-]*)\s+(?:noarch|x86_64|aarch64|i[3-6]86|arm\S*|ppc\S*|s390\S*)\s+", preview, re.MULTILINE)
            only_target(rows, name)
            counts = re.findall(r"(?:Remove\s+(\d+)\s+Packages?|Removing:\s+(\d+)\s+packages?)", preview)
            if len(counts) != 1 or (counts[0][0] or counts[0][1]) != "1" or re.search(r"^\s*(Installing|Upgrading|Downgrading|Reinstalling|Removing dependent|Removing unused)", preview, re.MULTILINE):
                raise ValueError("cannot verify DNF preview contains only the requested removal")
            commands = [privileged(["dnf", *options, "--assumeyes", "remove", name])]
        elif manager == "pacman":
            names = probe(["pacman", "-R", "--print-format", "%n", name]).stdout.splitlines()
            only_target(names, name)
            commands = [privileged(["pacman", "-R", "--noconfirm", name])]
        elif manager == "apk":
            preview = probe(["apk", "del", "--simulate", name]).stdout
            changes = re.findall(r"^\(\s*\d+/\d+\) (\w+) (\S+) ", preview, re.MULTILINE)
            only_target([package for action, package in changes], name)
            if any(action != "Purging" for action, package in changes):
                raise ValueError("refusing apk transaction that changes other packages")
            commands = [privileged(["apk", "del", name])]
        elif manager == "mas":
            commands = [["mas", "uninstall", name]]

    return {"manager": manager, "name": name, "commands": commands,
            "installed": bool(commands),
            "summary": f"{manager}:{name}: {'uninstall' if commands else 'already absent'}"}


def execute_remove(plan):
    # Recheck native state immediately before acting; earlier targets or another
    # process may have changed dependency constraints since batch preflight.
    current = plan_remove(plan["manager"], plan["name"])
    for command in current["commands"]:
        subprocess.run(command, check=True, env=environment())
