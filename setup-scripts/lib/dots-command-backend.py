#!/usr/bin/env python3
"""Structured status and progress bridge for the dots dashboard."""
import json
import os
import socket
import subprocess
import sys

mise, root, command, *arguments = sys.argv[1:]

def emit(kind, **fields):
    payload = json.dumps({"v": 1, "kind": kind, **fields}, separators=(",", ":"), ensure_ascii=True)
    nonce = os.environ.get("DOTS_UP_STREAM_NONCE")
    fd = os.environ.get("DOTS_UP_EVENT_FD")
    try:
        if nonce:
            os.write(1, f"\x1edots-up/1:{nonce}:{payload}\x1f".encode())
        elif fd:
            os.write(int(fd), (payload + "\n").encode())
    except (OSError, ValueError):
        pass

def stage_start(id, group, label, handoff=False):
    emit("stage_start", id=id, group=group, label=label, terminal="handoff" if handoff else "hidden")
    if handoff and os.environ.get("DOTS_UP_ACK_FD"):
        fd = int(os.environ["DOTS_UP_ACK_FD"])
        line = b""
        while not line.endswith(b"\n"):
            char = os.read(fd, 1)
            if not char:
                raise RuntimeError("terminal handoff did not complete")
            line += char
        if line.decode().strip() != f"go:{id}":
            raise RuntimeError("invalid terminal handoff")

def stage_end(id, label, code):
    state = "ok" if code == 0 else "attention" if code == 3 else "failed"
    emit("stage_end", id=id, label=label, status=state, exit_code=code, summary="completed" if code == 0 else f"exit {code}")

def item(group, key, state, summary, action=""):
    emit("item_upsert", id=f"{group.lower()}:{key}", group=group, label=str(key), status=state, summary=str(summary), action=action, before="", after="")

def state(value):
    value = str(value).lower().replace("-", "_")
    if value in ("applied", "tracked", "present", "installed", "ok", "ready", "satisfied", "set", "current"): return "ok"
    if value in ("missing", "source_missing", "not_installed"): return "missing"
    if value in ("differs", "drift", "orphaned", "orphaned_changed", "would_remove"): return "drift"
    if value in ("error", "failed"): return "failed"
    return "unknown"

def run_json(label, argv):
    try:
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    except OSError as error:
        print(f"{label}: {error}", file=sys.stderr)
        return None, 1
    if result.returncode not in (0, 3):
        print(f"{label}: inspection failed (exit {result.returncode})", file=sys.stderr)
        return None, result.returncode or 1
    try:
        return json.loads(result.stdout), result.returncode
    except (ValueError, TypeError):
        if result.returncode == 3:
            item("Inspection", label, "attention", "inspection deferred")
            return None, 3
        print(f"{label}: invalid structured output", file=sys.stderr)
        return None, 1

def status():
    profile = os.environ.get("SETUP_PROFILE", "")
    if profile not in ("workstation", "nas"):
        print("setup: SETUP_PROFILE must be workstation or nas", file=sys.stderr)
        return 2
    selector = profile + (",host-" + os.environ["SETUP_MACHINE_ID"] if os.environ.get("SETUP_MACHINE_ID") else "")
    base = [mise, "-C", root, "-E", selector]
    probes = [
        ("source", "Source", base + ["exec", "--", "node", root + "/setup-scripts/lib/source-repo.mjs", "status", root, "--json"]),
        ("atuin", "Atuin", base + ["exec", "--", "uv", "run", "--no-project", "python", root + "/setup-scripts/bootstrap/atuin.py", "status", "--json"]),
        ("setup", "Declared setup", base + ["bootstrap", "status", "--json"]),
        ("tools", "Tools", base + ["ls", "--current", "--json"]),
        ("history", "Files and history", base + ["bootstrap", "dotfiles", "status", "--json"]),
    ]
    failure = False
    for id, label, argv in probes:
        stage_start(id, "Inspection", label)
        data, code = run_json(label, argv)
        if data is not None:
            try:
                if id == "source":
                    workspace = data["workspace"]
                    revision = data.get("base_revision", "")
                    revision = revision[:12] if isinstance(revision, str) and len(revision) >= 12 and all(c in "0123456789abcdef" for c in revision) else "unavailable"
                    item("Source", "repository", "unknown" if workspace == "jj" else "attention", f"{'JJ' if workspace == 'jj' else 'Git'} workspace; base {revision}; working state not inspected", "Review source state" if workspace == "jj" else "Initialize JJ when ready")
                elif id == "atuin":
                    for key in ("installation", "login", "last_sync", "ai_readiness"):
                        value = data.get(key, "unavailable")
                        if key == "installation": result = "missing" if value == "missing" else "ok"
                        elif key == "login": result = "ok" if str(value).startswith("ready") else "unknown" if value == "unavailable" else "attention"
                        elif key == "last_sync": result = "unknown" if "unavailable" in str(value) else "ok"
                        else: result = "skipped" if value == "disabled" else "attention" if "unverified" in str(value) else "unknown" if value == "unavailable" else "ok"
                        item("History", "Atuin " + key.replace("_", " "), result, value)
                elif id == "tools":
                    for name, records in data.items():
                        for record in records:
                            if record.get("active", True):
                                installed = record.get("installed")
                                result = "ok" if installed is True else "missing" if installed is False else "unknown"
                                item("Tools", name + "@" + str(record.get("requested_version") or record.get("version") or "unknown"), result, record.get("version") or "not available")
                elif id == "history":
                    for section in ("files", "edits", "orphaned"):
                        for entry in data.get(section, []):
                            key = entry.get("target") or entry.get("path")
                            if key:
                                result = "ok" if entry.get("state") == "absent" else state(entry.get("state", "unknown"))
                                item("Files", key, result, result, "Review file status" if result in ("missing", "drift", "attention") else "")
                    history = data.get("history") or {}
                    if history:
                        sync = history.get("sync") or {}
                        problem = history.get("unavailable") or sync.get("last_error") or sync.get("application_failure") or sync.get("validation_error")
                        enabled = history.get("enabled")
                        item("History", "settings history", "attention" if problem else "ok" if enabled is True else "skipped" if enabled is False else "unknown", "history reports an error" if problem else "enabled" if enabled is True else "disabled" if enabled is False else "unavailable", "Review history status" if problem else "")
                        watcher = history.get("watcher")
                        if watcher is not None:
                            watcher_state = "ok" if watcher in ("watching", "service-watching", "running") else "attention" if watcher in ("service-not-watching", "not-watching", "degraded") else "unknown"
                            item("History", "watcher", watcher_state, watcher, "Review watcher health" if watcher_state == "attention" else "")
                        conflicts = sync.get("conflicts") or []
                        pending = sync.get("pending_applications") or []
                        if sync:
                            sync_problem = bool(conflicts or pending or sync.get("last_error") or sync.get("application_failure") or sync.get("validation_error"))
                            item("History", "synchronization", "attention" if sync_problem else "unknown", f"{len(conflicts)} conflicts; {len(pending)} pending applications" if isinstance(conflicts, list) and isinstance(pending, list) else "sync details unavailable", "Review history status" if sync_problem else "")
                else:
                    for manager, collection in data.get("packages", {}).items():
                        for entry in collection.get("packages", []):
                            name = manager + ":" + entry["package"]
                            result = state(entry.get("state", "unknown"))
                            item("Packages", name, result, entry.get("installed_version") or result, "Review package status" if result in ("missing", "drift", "attention") else "")
                    sections = {key: value for key, value in data.items() if isinstance(value, list) and key not in ("tools",)}
                    for key, child in (("macos_login_items", "entries"), ("macos_defaults", "entries"), ("launchd", "agents"), ("systemd", "units")):
                        sections[key] = (data.get(key) or {}).get(child, [])
                    for section, collection in sections.items():
                        group = {"files": "Directories", "secrets": "Secret inputs", "user_services": "User services", "macos_defaults": "macOS defaults", "macos_login_items": "Login items"}.get(section, section.replace("_", " ").title())
                        for entry in collection:
                            if not isinstance(entry, dict): continue
                            ident = entry.get("id")
                            key = ident.get("name") if isinstance(ident, dict) else ident if isinstance(ident, str) else None
                            key = key or next((entry[k] for k in ("name", "path", "target", "service", "repo", "label", "unit") if isinstance(entry.get(k), str) and entry[k]), None)
                            if section == "macos_defaults" and entry.get("domain") and entry.get("key"):
                                key = str(entry["domain"]) + ":" + str(entry["key"])
                            if not key: continue
                            raw = entry.get("state")
                            action = entry.get("action")
                            result = state(raw) if raw is not None else "ok" if action == "noop" else "drift" if isinstance(action, str) and action not in ("", "unknown") else "unknown"
                            item(group, key, result, result, "Review resource status" if result in ("missing", "drift", "attention") else "")
                    shell = data.get("login_shell")
                    if isinstance(shell, dict):
                        result = state(shell.get("state", "unknown"))
                        item("Login shell", "login shell", result, result, "Review login shell status" if result in ("missing", "drift", "attention") else "")
            except (KeyError, TypeError, AttributeError) as error:
                print(f"{label}: unexpected structured output: {error}", file=sys.stderr)
                code = 1
        stage_end(id, label, code)
        if code not in (0, 3): failure = True
    stage_start("exceptions", "Inspection", "Installer exceptions")
    code = 0
    try:
        manifest = os.path.join(root, "setup-scripts/setup/exceptions.tsv")
        if os.path.exists(manifest):
            for line in open(manifest, encoding="utf-8"):
                if not line.strip() or line.startswith("#"): continue
                fields = line.rstrip("\n").split("\t")
                if len(fields) != 2 or fields[0] not in ("base", "workstation", "nas"):
                    raise ValueError("invalid installer exception row")
                role, name = fields
                if role not in ("base", profile): continue
                if not name or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for c in name) or not name[0].isalnum():
                    raise ValueError("invalid installer exception name")
                executable = os.access(os.path.join(root, "setup-scripts/setup/exceptions", name), os.X_OK)
                item("Exceptions", name, "ok" if executable else "missing", "ready" if executable else "missing executable")
                if not executable: code = 2
    except (OSError, ValueError) as error:
        print(f"Installer exceptions: {error}", file=sys.stderr)
        code = 2
    stage_end("exceptions", "Installer exceptions", code)
    return 1 if failure or code else 0

def main():
    if command in ("up", "update"):
        os.execv(mise, [mise, "-C", root, "run", "setup:update", *arguments])
    if command == "status" and not arguments and not os.environ.get("DOTS_STATUS_IN_ENV"):
        os.execvpe(mise, [mise, "-C", root, "exec", "--", "python3", __file__, mise, root, command], {**os.environ, "DOTS_STATUS_IN_ENV": "1", "MISE_CONFIG_DIR": root, "MISE_AUTO_INSTALL": "0", "MISE_EXEC_AUTO_INSTALL": "0", "MISE_AUTO_UPDATE": "0", "MISE_NO_HOOKS": "1"})
    emit("run_start", command=command, profile=os.environ.get("SETUP_PROFILE", ""), host=socket.gethostname().split(".")[0])
    try:
        if command == "status" and not arguments:
            code = status()
        else:
            stage_start(command, "Command", command, handoff=command not in ("sync", "backup", "test", "add", "remove"))
            event_fd = os.environ.get("DOTS_UP_EVENT_FD")
            pass_fds = tuple(int(os.environ[key]) for key in ("DOTS_UP_EVENT_FD", "DOTS_UP_ACK_FD") if os.environ.get(key, "").isdecimal())
            code = subprocess.call([root + "/dotfiles/.local/bin/dots", "--backend", command, *arguments], env={**os.environ, "DOTS_ROOT": root, "DOTS_MISE_BIN": mise}, pass_fds=pass_fds)
            stage_end(command, command, code)
    except (OSError, RuntimeError) as error:
        print(f"dots: {error}", file=sys.stderr)
        code = 1
    emit("run_end", status="ok" if code == 0 else "attention" if code == 3 else "failed", exit_code=code)
    return code

if __name__ == "__main__":
    sys.exit(main())
