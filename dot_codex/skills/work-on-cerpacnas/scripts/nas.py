#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
import tomllib
from collections.abc import Sequence
from pathlib import Path, PurePosixPath
from typing import NamedTuple

DEFAULT_MANIFEST = Path("~/.config/cerpacnas/projects.toml").expanduser()
STATE_RELATIVE = Path(".local/state/nas-agent")
SAFE_TASK = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
FORBIDDEN_ARTIFACT_PARTS = {
    ".git",
    ".jj",
    ".ssh",
    ".codex",
    "node_modules",
    "__pycache__",
}
RSYNC_EXCLUDES = (
    ".git/",
    ".jj/",
    ".ssh/",
    ".codex/",
    "node_modules/",
    "__pycache__/",
    ".env",
    ".env.*",
    "*.pem",
    "*.key",
    "id_*",
    "auth.json",
)


class NasError(RuntimeError):
    pass


class ManifestError(NasError):
    pass


class HostConfig(NamedTuple):
    ssh_alias: str
    remote_home: Path
    remote_project_root: Path
    dotfiles_branch: str
    explore_model: str
    work_model: str


class ArtifactConfig(NamedTuple):
    name: str
    path: Path


class ProjectConfig(NamedTuple):
    name: str
    repo: str
    local_path: Path
    remote_path: Path
    remote_name: str
    rules_file: Path
    artifacts: dict[str, ArtifactConfig]


class Manifest(NamedTuple):
    path: Path
    host: HostConfig
    projects: dict[str, ProjectConfig]


def _required(table: dict[str, object], key: str, context: str) -> object:
    if key not in table:
        raise ManifestError(f"missing {context}.{key}")
    return table[key]


def _string(table: dict[str, object], key: str, context: str) -> str:
    value = _required(table, key, context)
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(f"{context}.{key} must be a non-empty string")
    return value


def _absolute_path(table: dict[str, object], key: str, context: str) -> Path:
    path = Path(os.path.expanduser(_string(table, key, context)))
    if not path.is_absolute():
        raise ManifestError(f"{context}.{key} must be absolute")
    if ".." in path.parts:
        raise ManifestError(f"{context}.{key} may not contain ..")
    return path


def require_contained(path: Path, root: Path, context: str) -> None:
    try:
        path.relative_to(root)
    except ValueError as error:
        raise ManifestError(f"{context} must stay below {root}") from error


def _artifact_path(value: object, context: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{context}.path must be a non-empty relative path")
    pure = PurePosixPath(value)
    if pure.is_absolute():
        raise ManifestError(f"{context}.path must be relative")
    if any(
        part in {"", ".", ".."} or part in FORBIDDEN_ARTIFACT_PARTS or not SAFE_TASK.fullmatch(part)
        for part in pure.parts
    ):
        raise ManifestError(f"{context}.path is unsafe")
    return Path(*pure.parts)


def load_manifest(path: Path = DEFAULT_MANIFEST) -> Manifest:
    path = path.expanduser()
    try:
        with path.open("rb") as handle:
            raw = tomllib.load(handle)
    except FileNotFoundError as error:
        raise ManifestError(f"manifest not found: {path}") from error
    if raw.get("version") != 1:
        raise ManifestError("manifest version must be 1")
    host_raw = raw.get("host")
    if not isinstance(host_raw, dict):
        raise ManifestError("missing [host]")
    host = HostConfig(
        ssh_alias=_string(host_raw, "ssh_alias", "host"),
        remote_home=_absolute_path(host_raw, "remote_home", "host"),
        remote_project_root=_absolute_path(host_raw, "remote_project_root", "host"),
        dotfiles_branch=_string(host_raw, "dotfiles_branch", "host"),
        explore_model=_string(host_raw, "explore_model", "host"),
        work_model=_string(host_raw, "work_model", "host"),
    )
    projects_raw = raw.get("projects")
    if not isinstance(projects_raw, dict) or not projects_raw:
        raise ManifestError("manifest needs at least one [projects.<name>] entry")
    projects: dict[str, ProjectConfig] = {}
    for name, value in projects_raw.items():
        if not isinstance(name, str) or not SAFE_TASK.fullmatch(name):
            raise ManifestError(f"unsafe project name: {name!r}")
        if not isinstance(value, dict):
            raise ManifestError(f"projects.{name} must be a table")
        context = f"projects.{name}"
        artifacts_raw = value.get("artifacts", {})
        if not isinstance(artifacts_raw, dict):
            raise ManifestError(f"{context}.artifacts must be a table")
        artifacts: dict[str, ArtifactConfig] = {}
        for artifact_name, artifact_value in artifacts_raw.items():
            if not isinstance(artifact_name, str) or not SAFE_TASK.fullmatch(artifact_name):
                raise ManifestError(f"unsafe artifact name: {artifact_name!r}")
            if not isinstance(artifact_value, dict):
                raise ManifestError(f"{context}.artifacts.{artifact_name} must be a table")
            artifact_context = f"{context}.artifacts.{artifact_name}"
            artifacts[artifact_name] = ArtifactConfig(
                artifact_name,
                _artifact_path(artifact_value.get("path"), artifact_context),
            )
        project = ProjectConfig(
            name=name,
            repo=_string(value, "repo", context),
            local_path=_absolute_path(value, "local_path", context),
            remote_path=_absolute_path(value, "remote_path", context),
            remote_name=_string(value, "remote_name", context),
            rules_file=Path(os.path.expanduser(_string(value, "rules_file", context))),
            artifacts=artifacts,
        )
        require_contained(project.remote_path, host.remote_project_root, f"{context}.remote_path")
        projects[name] = project
    return Manifest(path, host, projects)


def normalize_bookmark(task: str) -> str:
    slug = task.removeprefix("wip/")
    if not SAFE_TASK.fullmatch(slug):
        raise NasError("task must be a safe lowercase slug")
    bookmark = f"wip/{slug}"
    if task in {"main", "dev"} or not bookmark.startswith("wip/"):
        raise NasError("handoff bookmark must use wip/<task>; main is never allowed")
    return bookmark


def workspace_name(project: str, bookmark: str) -> str:
    slug = bookmark.removeprefix("wip/")
    return f"{project}-{slug}"[:63]


def remote_shell_command(arguments: Sequence[str]) -> str:
    return shlex.join([str(argument) for argument in arguments])


def rsync_args(*, apply: bool) -> list[str]:
    arguments = ["rsync", "-avh", "--partial", "--itemize-changes"]
    if not apply:
        arguments.append("--dry-run")
    arguments.extend(f"--exclude={pattern}" for pattern in RSYNC_EXCLUDES)
    return arguments


def agent_spec(host: HostConfig, mode: str) -> tuple[str, str]:
    if mode == "explore":
        return host.explore_model, "read-only"
    if mode == "work":
        return host.work_model, "workspace-write"
    raise NasError(f"unknown agent mode: {mode}")


def run(
    arguments: Sequence[str],
    *,
    cwd: Path | None = None,
    capture: bool = False,
    check: bool = True,
    tty: bool = False,
) -> subprocess.CompletedProcess[str]:
    kwargs: dict[str, object] = {
        "cwd": cwd,
        "text": True,
        "check": check,
    }
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.PIPE
    if tty:
        kwargs["stdin"] = None
    try:
        return subprocess.run([str(item) for item in arguments], **kwargs)  # type: ignore[arg-type]
    except FileNotFoundError as error:
        raise NasError(f"command not found: {arguments[0]}") from error
    except subprocess.CalledProcessError as error:
        detail = ""
        if error.stderr:
            detail = f": {error.stderr.strip()}"
        raise NasError(f"command failed ({error.returncode}): {remote_shell_command(arguments)}{detail}") from error


def output(arguments: Sequence[str], *, cwd: Path | None = None) -> str:
    return run(arguments, cwd=cwd, capture=True).stdout.strip()


def last_json(text: str) -> object:
    for line in reversed(text.splitlines()):
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            continue
    raise NasError("remote command returned no JSON payload")


def remote(
    manifest: Manifest,
    arguments: Sequence[str],
    *,
    capture: bool = False,
    tty: bool = False,
) -> subprocess.CompletedProcess[str]:
    command = [
        "uv",
        "run",
        "--python",
        "3.12",
        "--directory",
        str(manifest.host.remote_home),
        "python",
        str(manifest.host.remote_home / ".codex/skills/work-on-cerpacnas/scripts/nas.py"),
        "--manifest",
        str(manifest.host.remote_home / ".config/cerpacnas/projects.toml"),
        "_remote",
        *arguments,
    ]
    ssh = ["ssh"]
    if tty:
        ssh.append("-t")
    ssh.extend(
        [
            manifest.host.ssh_alias,
            remote_shell_command(["bash", "-lc", remote_shell_command(command)]),
        ]
    )
    return run(ssh, capture=capture, tty=tty)


def selected_projects(manifest: Manifest, selection: str) -> list[ProjectConfig]:
    if selection == "--all":
        return list(manifest.projects.values())
    try:
        return [manifest.projects[selection]]
    except KeyError as error:
        raise NasError(f"unknown project: {selection}") from error


def jj_output(project_path: Path, *arguments: str) -> str:
    return output(["jj", "-R", str(project_path), *arguments])


def revision_commit(project: ProjectConfig, bookmark: str, *, remote_tracking: bool = False) -> str:
    revision = f"{bookmark}@{project.remote_name}" if remote_tracking else bookmark
    commit = jj_output(project.local_path, "log", "-r", revision, "--no-graph", "-T", 'commit_id ++ "\\n"')
    lines = [line for line in commit.splitlines() if line]
    if len(lines) != 1:
        raise NasError(f"{revision} must resolve to exactly one commit")
    return lines[0]


def preflight_bookmark(project: ProjectConfig, bookmark: str, *, push: bool) -> str:
    if not (project.local_path / ".jj").is_dir():
        raise NasError(f"not a JJ repository: {project.local_path}")
    run(["jj", "-R", str(project.local_path), "git", "fetch", "--remote", project.remote_name])
    listing = jj_output(project.local_path, "bookmark", "list", bookmark)
    if "divergent" in listing.lower():
        raise NasError(f"bookmark is divergent: {bookmark}")
    conflict = jj_output(
        project.local_path,
        "log",
        "-r",
        f"{bookmark} & conflicts()",
        "--no-graph",
        "-T",
        'commit_id ++ "\\n"',
    )
    if conflict:
        raise NasError(f"bookmark contains conflicts: {bookmark}")
    description = jj_output(
        project.local_path,
        "log",
        "-r",
        bookmark,
        "--no-graph",
        "-T",
        'description.first_line() ++ "\\n"',
    )
    if not description:
        raise NasError(f"bookmark commit needs a one-line description: {bookmark}")
    local_commit = revision_commit(project, bookmark)
    if push:
        run(
            [
                "jj",
                "-R",
                str(project.local_path),
                "git",
                "push",
                "--remote",
                project.remote_name,
                "--bookmark",
                bookmark,
            ]
        )
        run(["jj", "-R", str(project.local_path), "git", "fetch", "--remote", project.remote_name])
    remote_commit = revision_commit(project, bookmark, remote_tracking=True)
    if remote_commit != local_commit:
        raise NasError(f"{bookmark} is not published at the same commit; rerun with --push")
    return local_commit


def rules_target(project: ProjectConfig) -> Path:
    return project.local_path / "AGENTS.md"


def apply_project_rules(project: ProjectConfig) -> None:
    source = project.rules_file.expanduser()
    if not source.is_file():
        raise NasError(f"project rules missing: {source}")
    target = rules_target(project)
    target.parent.mkdir(parents=True, exist_ok=True)
    content = source.read_bytes()
    if not target.exists() or target.read_bytes() != content:
        target.write_bytes(content)
    exclude = project.local_path / ".git/info/exclude"
    if exclude.parent.is_dir():
        existing = exclude.read_text() if exclude.exists() else ""
        lines = existing.splitlines()
        if "AGENTS.md" not in lines:
            exclude.write_text(existing.rstrip("\n") + "\nAGENTS.md\n")


def sync_project_local(project: ProjectConfig) -> None:
    if not project.local_path.exists():
        project.local_path.parent.mkdir(parents=True, exist_ok=True)
        run(
            [
                "jj",
                "git",
                "clone",
                "--remote",
                project.remote_name,
                project.repo,
                str(project.local_path),
            ]
        )
    elif not (project.local_path / ".jj").is_dir():
        raise NasError(f"existing project is not a JJ repository: {project.local_path}")
    run(["jj", "-R", str(project.local_path), "git", "fetch", "--remote", project.remote_name])
    apply_project_rules(project)
    print(f"[{project.name}] bookmark divergence report")
    run(["jj", "-R", str(project.local_path), "bookmark", "list", "--all"])


def project_status(project: ProjectConfig) -> None:
    print(f"[{project.name}] {project.local_path}")
    if not project.local_path.exists():
        print("missing")
        return
    run(["jj", "-R", str(project.local_path), "status"])
    run(["jj", "-R", str(project.local_path), "bookmark", "list", "--all"])


def state_root(manifest: Manifest) -> Path:
    return manifest.host.remote_home / STATE_RELATIVE


def owner_path(manifest: Manifest, project: str, bookmark: str) -> Path:
    return state_root(manifest) / "owners" / project / f"{bookmark.removeprefix('wip/')}.json"


def local_owner_path(project: str, bookmark: str) -> Path:
    return Path.home() / STATE_RELATIVE / "owners" / project / f"{bookmark.removeprefix('wip/')}.json"


def run_path(manifest: Manifest, run_id: str) -> Path:
    return state_root(manifest) / "runs" / run_id


def resolved_remote_workspace(manifest: Manifest, path: Path) -> Path:
    resolved_root = manifest.host.remote_project_root.resolve()
    resolved = path.resolve()
    require_contained(resolved, resolved_root, "resolved remote workspace")
    return resolved


def _write_json(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def _read_json(path: Path) -> dict[str, object]:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError as error:
        raise NasError(f"state not found: {path}") from error


def remote_receive(manifest: Manifest, project: ProjectConfig, bookmark: str, commit: str) -> dict[str, object]:
    sync_project_local(project)
    tracked = revision_commit(project, bookmark, remote_tracking=True)
    if tracked != commit:
        raise NasError(f"remote tracking commit mismatch for {bookmark}")
    owner = owner_path(manifest, project.name, bookmark)
    if owner.exists():
        current = _read_json(owner)
        if current.get("active"):
            raise NasError(f"task already owned on NAS: {bookmark}")
    name = workspace_name(project.name, bookmark)
    existing = run(["jw", "path", name], cwd=project.local_path, capture=True, check=False)
    if existing.returncode != 0:
        local_bookmark = run(
            ["jj", "-R", str(project.local_path), "log", "-r", bookmark, "--no-graph", "-T", "commit_id"],
            capture=True,
            check=False,
        )
        if local_bookmark.returncode == 0 and local_bookmark.stdout.strip():
            run(
                [
                    "jj",
                    "-R",
                    str(project.local_path),
                    "bookmark",
                    "set",
                    bookmark,
                    "-r",
                    f"{bookmark}@{project.remote_name}",
                ]
            )
            run(["jw", "add", "--at", bookmark, "--no-bookmark", name], cwd=project.local_path)
        else:
            run(
                ["jw", "add", "--at", f"{bookmark}@{project.remote_name}", "--bookmark", bookmark, name],
                cwd=project.local_path,
            )
    workspace = resolved_remote_workspace(manifest, Path(output(["jw", "path", name], cwd=project.local_path)))
    apply_project_rules(project._replace(local_path=workspace))
    payload: dict[str, object] = {
        "active": True,
        "bookmark": bookmark,
        "commit": commit,
        "project": project.name,
        "workspace": str(workspace),
        "workspace_name": name,
        "received_at": int(time.time()),
    }
    _write_json(owner, payload)
    return payload


def remote_release(manifest: Manifest, project: ProjectConfig, bookmark: str, *, push: bool) -> dict[str, object]:
    owner = owner_path(manifest, project.name, bookmark)
    payload = _read_json(owner)
    if not payload.get("active"):
        raise NasError(f"task is not active on NAS: {bookmark}")
    if any(item.get("bookmark") == bookmark for item in active_runs(manifest)):
        raise NasError(f"an agent is still running for {bookmark}")
    workspace = resolved_remote_workspace(manifest, Path(str(payload["workspace"])))
    workspace_project = project._replace(local_path=workspace)
    if jj_output(workspace, "diff", "-r", "@", "--summary"):
        raise NasError("workspace has uncommitted changes; describe the result, move the bookmark, then run jj new")
    parent = jj_output(workspace, "log", "-r", "@-", "--no-graph", "-T", 'commit_id ++ "\\n"')
    if parent != revision_commit(workspace_project, bookmark):
        raise NasError("empty working commit must be directly above the task bookmark")
    commit = preflight_bookmark(workspace_project, bookmark, push=push)
    payload["commit"] = commit
    payload.setdefault("checks", [])
    payload["skipped"] = [
        "validate all",
        "validate evidence",
        "thesis evidence gate",
        "benchmarks",
        "browser and API-live tests",
        "final acceptance on Mac or CI",
    ]
    payload["released_at"] = int(time.time())
    _write_json(owner, payload)
    return payload


def remote_clear(manifest: Manifest, project: ProjectConfig, bookmark: str) -> None:
    owner = owner_path(manifest, project.name, bookmark)
    payload = _read_json(owner)
    name = str(payload["workspace_name"])
    run(["jw", "remove", "--keep-bookmark", name], cwd=project.local_path)
    payload["active"] = False
    payload["cleared_at"] = int(time.time())
    _write_json(owner, payload)


def handle_handoff(manifest: Manifest, project: ProjectConfig, task: str, target: str, push: bool) -> None:
    bookmark = normalize_bookmark(task)
    if target == "nas":
        local_owner = local_owner_path(project.name, bookmark)
        if local_owner.exists() and _read_json(local_owner).get("owner") == "nas":
            raise NasError(f"task is already owned by NAS: {bookmark}")
        commit = preflight_bookmark(project, bookmark, push=push)
        result = remote(manifest, ["handoff-receive", project.name, bookmark, commit], capture=True)
        payload = last_json(result.stdout)
        if not isinstance(payload, dict):
            raise NasError("invalid NAS handoff payload")
        print(f"handoff ready: {bookmark} {commit[:12]}")
        print(f"NAS workspace: {payload['workspace']}")
        _write_json(
            local_owner,
            {"active": False, "bookmark": bookmark, "commit": commit, "owner": "nas", "project": project.name},
        )
        return
    result = remote(
        manifest,
        ["handoff-release", project.name, bookmark, "--push" if push else "--no-push"],
        capture=True,
    )
    payload = last_json(result.stdout)
    if not isinstance(payload, dict):
        raise NasError("invalid Mac handoff payload")
    commit = str(payload["commit"])
    run(["jj", "-R", str(project.local_path), "git", "fetch", "--remote", project.remote_name])
    tracked = revision_commit(project, bookmark, remote_tracking=True)
    if tracked != commit:
        raise NasError("GitHub does not contain released NAS commit; rerun with --push")
    run(["jj", "-R", str(project.local_path), "bookmark", "set", bookmark, "-r", f"{bookmark}@{project.remote_name}"])
    name = workspace_name(project.name, bookmark)
    if run(["jw", "path", name], cwd=project.local_path, capture=True, check=False).returncode != 0:
        run(["jw", "add", "--at", bookmark, "--no-bookmark", name], cwd=project.local_path)
    remote(manifest, ["handoff-clear", project.name, bookmark])
    _write_json(
        local_owner_path(project.name, bookmark),
        {"active": True, "bookmark": bookmark, "commit": commit, "owner": "mac", "project": project.name},
    )
    print(f"handoff received: {bookmark} {commit[:12]}")
    print(f"Mac workspace: {output(['jw', 'path', name], cwd=project.local_path)}")
    checks = payload.get("checks", [])
    skipped = payload.get("skipped", [])
    print("checks: " + (", ".join(str(item) for item in checks) if checks else "none recorded"))
    print("skipped on NAS: " + ", ".join(str(item) for item in skipped))


def active_runs(manifest: Manifest) -> list[dict[str, object]]:
    runs = state_root(manifest) / "runs"
    if not runs.exists():
        return []
    active: list[dict[str, object]] = []
    for meta in runs.glob("*/meta.json"):
        payload = _read_json(meta)
        session = str(payload.get("session", ""))
        if session and run(["tmux", "has-session", "-t", session], check=False, capture=True).returncode == 0:
            active.append(payload)
    return active


def remote_agent_start(
    manifest: Manifest,
    project: ProjectConfig,
    bookmark: str,
    mode: str,
    prompt: str,
) -> dict[str, object]:
    owner = _read_json(owner_path(manifest, project.name, bookmark))
    if not owner.get("active"):
        raise NasError(f"task is not active on NAS: {bookmark}")
    active = active_runs(manifest)
    if mode == "work" and active:
        raise NasError("work agent requires exclusive NAS agent slot")
    if mode == "explore" and (any(item.get("mode") == "work" for item in active) or len(active) >= 2):
        raise NasError("NAS allows one work agent or two exploration agents")
    model, sandbox = agent_spec(manifest.host, mode)
    task = bookmark.removeprefix("wip/")
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    run_id = f"{stamp}-{project.name}-{task}-{mode}"
    session = f"nas-agent-{project.name}-{task}-{mode}"[:63]
    destination = run_path(manifest, run_id)
    destination.mkdir(parents=True, exist_ok=False)
    workspace = resolved_remote_workspace(manifest, Path(str(owner["workspace"])))
    final_path = destination / "final.md"
    events_path = destination / "events.jsonl"
    stderr_path = destination / "stderr.log"
    exit_path = destination / "exit-code"
    codex = [
        "codex",
        "exec",
        "-C",
        str(workspace),
        "-m",
        model,
        "-s",
        sandbox,
        "--skip-git-repo-check",
        "--json",
        "--output-last-message",
        str(final_path),
        (
            prompt
            if mode == "explore"
            else (
                f"{prompt}\n\n"
                "NAS completion contract: do not push. Finish with one described, conflict-free result commit; "
                f"move {bookmark} to that commit; then run `jj new {bookmark}` so the working commit is empty. "
                "Do not run broad validation, benchmarks, browser tests, API-live tests, or make performance claims."
            )
        ),
    ]
    shell = (
        "set +e; export JULIA_NUM_THREADS=1 NAS_VALIDATION_TIMEOUT=180; "
        f"{remote_shell_command(codex)} > {shlex.quote(str(events_path))} 2> {shlex.quote(str(stderr_path))}; "
        f'status=$?; printf \'%s\\n\' "$status" > {shlex.quote(str(exit_path))}; exit "$status"'
    )
    run(["tmux", "new-session", "-d", "-s", session, "bash", "-lc", shell])
    payload: dict[str, object] = {
        "run_id": run_id,
        "session": session,
        "project": project.name,
        "bookmark": bookmark,
        "workspace": str(workspace),
        "mode": mode,
        "model": model,
        "sandbox": sandbox,
        "started_at": int(time.time()),
        "events": str(events_path),
        "final": str(final_path),
        "stderr": str(stderr_path),
        "exit_code": str(exit_path),
    }
    _write_json(destination / "meta.json", payload)
    return payload


def remote_agent_status(manifest: Manifest, run_id: str | None = None) -> list[dict[str, object]]:
    root = state_root(manifest) / "runs"
    paths = [run_path(manifest, run_id) / "meta.json"] if run_id else sorted(root.glob("*/meta.json"), reverse=True)
    results: list[dict[str, object]] = []
    for path in paths[:20]:
        payload = _read_json(path)
        running = run(["tmux", "has-session", "-t", str(payload["session"])], check=False, capture=True).returncode == 0
        exit_file = Path(str(payload["exit_code"]))
        payload["status"] = "running" if running else "finished"
        payload["result"] = exit_file.read_text().strip() if exit_file.exists() else None
        results.append(payload)
    return results


def remote_agent_logs(manifest: Manifest, run_id: str, lines: int) -> str:
    payload = _read_json(run_path(manifest, run_id) / "meta.json")
    chunks: list[str] = []
    for label in ("stderr", "final"):
        path = Path(str(payload[label]))
        if path.exists() and path.stat().st_size:
            content = path.read_text(errors="replace").splitlines()[-lines:]
            chunks.append(f"== {label} ==\n" + "\n".join(content))
    events = Path(str(payload["events"]))
    if events.exists() and events.stat().st_size:
        content = "\n".join(events.read_text(errors="replace").splitlines()[-lines:])
        chunks.append("== events ==\n" + content)
    return "\n".join(chunks)


def validation_command(lane: str) -> tuple[list[str], str]:
    cheap = {
        "web-format": (["bun", "run", "--cwd", "web", "format:check"], "web-format"),
        "web-pure": (["bun", "run", "--cwd", "web", "test:pure"], "web-pure"),
        "web-type": (["bun", "run", "--cwd", "web", "typecheck"], "web-type"),
        "julia-format": (["mise", "run", "format-check"], "julia-format"),
    }
    if lane in cheap:
        return cheap[lane]
    if lane.startswith("focus:"):
        seam = lane.removeprefix("focus:")
        if not SAFE_TASK.fullmatch(seam):
            raise NasError("focused validation seam must be a safe lowercase slug")
        return ["mise", "run", "validate", "--", "focus", seam, "--jobs", "1"], f"focus-{seam}"
    raise NasError("lane must be web-format, web-pure, web-type, julia-format, or focus:<seam>")


def validation_within_budget(return_code: int, duration_seconds: float, peak_rss_mib: float) -> bool:
    return return_code != 124 and duration_seconds <= 180 and peak_rss_mib <= 3072


def linux_process_tree_rss_kib(root_pid: int) -> int:
    parents: dict[int, int] = {}
    rss: dict[int, int] = {}
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            stat = (proc / "stat").read_text()
            fields = stat[stat.rfind(")") + 2 :].split()
            pid = int(proc.name)
            parents[pid] = int(fields[1])
            for line in (proc / "status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    rss[pid] = int(line.split()[1])
                    break
        except (FileNotFoundError, IndexError, PermissionError, ValueError):
            continue
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, parent in parents.items():
            if parent in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return sum(rss.get(pid, 0) for pid in descendants)


def run_measured_linux(
    command: Sequence[str],
    *,
    cwd: Path,
    log_file: Path,
    timeout_seconds: int,
) -> tuple[int, float, float, bool]:
    environment = os.environ.copy()
    environment["JULIA_NUM_THREADS"] = "1"
    started = time.monotonic()
    peak_rss_kib = 0
    timed_out = False
    with log_file.open("w") as log:
        try:
            process = subprocess.Popen(
                [str(item) for item in command],
                cwd=cwd,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                start_new_session=True,
            )
        except FileNotFoundError as error:
            raise NasError(f"validation command not found: {command[0]}") from error
        while process.poll() is None:
            peak_rss_kib = max(peak_rss_kib, linux_process_tree_rss_kib(process.pid))
            if time.monotonic() - started >= timeout_seconds:
                timed_out = True
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                break
            time.sleep(0.1)
    duration = time.monotonic() - started
    return (124 if timed_out else int(process.returncode), duration, peak_rss_kib / 1024, timed_out)


def remote_validate(
    manifest: Manifest,
    project: ProjectConfig,
    bookmark: str,
    lane: str,
    *,
    calibrate: bool,
) -> dict[str, object]:
    owner_file = owner_path(manifest, project.name, bookmark)
    owner = _read_json(owner_file)
    if not owner.get("active"):
        raise NasError(f"task is not active on NAS: {bookmark}")
    if active_runs(manifest):
        raise NasError("validation requires the exclusive NAS execution slot")
    command, policy_key = validation_command(lane)
    policy_path = state_root(manifest) / "validation-policy" / project.name / f"{policy_key}.json"
    focused = lane.startswith("focus:")
    if policy_path.exists() and not _read_json(policy_path).get("enabled") and not calibrate:
        raise NasError(f"{lane} is disabled on NAS; inspect its receipt before recalibrating")
    if focused and not calibrate:
        if not policy_path.exists() or not _read_json(policy_path).get("enabled"):
            raise NasError(f"{lane} is not calibrated for NAS; rerun once with --calibrate")
    workspace = resolved_remote_workspace(manifest, Path(str(owner["workspace"])))
    code = workspace / "code"
    if not code.is_dir():
        raise NasError(f"project code directory missing: {code}")
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    destination = state_root(manifest) / "validation" / project.name / f"{stamp}-{policy_key}"
    destination.mkdir(parents=True, exist_ok=False)
    log_file = destination / "output.log"
    return_code, duration, peak_rss_mib, timed_out = run_measured_linux(
        command,
        cwd=code,
        log_file=log_file,
        timeout_seconds=180,
    )
    within_budget = validation_within_budget(return_code, duration, peak_rss_mib)
    passed = return_code == 0 and within_budget
    receipt: dict[str, object] = {
        "bookmark": bookmark,
        "calibration": calibrate,
        "command": command,
        "duration_seconds": round(duration, 2),
        "exit_code": return_code,
        "lane": lane,
        "log": str(log_file),
        "passed": passed,
        "peak_rss_mib": round(peak_rss_mib, 1),
        "project": project.name,
        "timed_out": timed_out,
    }
    _write_json(destination / "receipt.json", receipt)
    if calibrate or not within_budget:
        _write_json(
            policy_path,
            {
                "enabled": passed,
                "lane": lane,
                "reason": "within budget" if passed else "failed, timed out, or exceeded 3 GiB RSS",
                "receipt": str(destination / "receipt.json"),
                "updated_at": int(time.time()),
            },
        )
    checks = owner.setdefault("checks", [])
    if isinstance(checks, list):
        checks.append(f"{lane}: {'pass' if passed else 'fail'} ({duration:.1f}s, {peak_rss_mib:.0f} MiB peak RSS)")
    _write_json(owner_file, owner)
    return receipt


def config_targets(manifest: Manifest) -> list[str]:
    return [
        str(manifest.host.remote_home / ".codex/AGENTS.md"),
        str(manifest.host.remote_home / ".codex/config.toml"),
        str(manifest.host.remote_home / ".codex/skills"),
        str(manifest.host.remote_home / ".config/cerpacnas"),
        str(manifest.host.remote_home / ".config/git/config"),
        str(manifest.host.remote_home / ".config/mise/config.toml"),
        str(manifest.host.remote_home / ".local/bin/nas"),
    ]


def config_status(manifest: Manifest) -> None:
    source = manifest.host.remote_home / ".local/share/chezmoi"
    if (source / ".jj").is_dir():
        run(["jj", "-R", str(source), "status"])
        run(["jj", "-R", str(source), "bookmark", "list", "--all", manifest.host.dotfiles_branch])
    else:
        print("remote chezmoi source is not JJ-initialized; config update will initialize it")
    run(["chezmoi", "status", *config_targets(manifest)])


def config_update(manifest: Manifest) -> None:
    source = manifest.host.remote_home / ".local/share/chezmoi"
    if not (source / ".jj").is_dir():
        run(["jj", "git", "init", "--colocate", str(source)])
    dirty = jj_output(source, "diff", "-r", "@", "--summary")
    if dirty:
        raise NasError("remote chezmoi source has local changes; refusing update")
    branch = manifest.host.dotfiles_branch
    run(["jj", "-R", str(source), "git", "fetch", "--remote", "origin"])
    remote_revision = f"{branch}@origin"
    run(["jj", "-R", str(source), "bookmark", "set", branch, "-r", remote_revision])
    run(["jj", "-R", str(source), "new", branch])
    targets = config_targets(manifest)
    run(["chezmoi", "diff", *targets])
    run(["chezmoi", "apply", *targets])


def artifact_transfer(
    manifest: Manifest, project: ProjectConfig, artifact_name: str, direction: str, apply: bool
) -> None:
    try:
        artifact = project.artifacts[artifact_name]
    except KeyError as error:
        raise NasError(f"artifact is not allowlisted: {project.name}/{artifact_name}") from error
    local_root = project.local_path.resolve()
    local_path = (local_root / artifact.path).resolve()
    try:
        local_path.relative_to(local_root)
    except ValueError as error:
        raise NasError("artifact symlink escapes project root") from error
    remote_path = project.remote_path / artifact.path
    root_command = remote_shell_command(["realpath", "-m", "--", str(manifest.host.remote_project_root)])
    path_command = remote_shell_command(["realpath", "-m", "--", str(remote_path)])
    remote_root = Path(output(["ssh", manifest.host.ssh_alias, root_command]))
    remote_resolved = Path(output(["ssh", manifest.host.ssh_alias, path_command]))
    require_contained(remote_resolved, remote_root, "resolved remote artifact path")
    arguments = rsync_args(apply=apply)
    if direction == "push":
        if not local_path.exists():
            raise NasError(f"local artifact missing: {local_path}")
        arguments.extend([f"{local_path}/", f"{manifest.host.ssh_alias}:{remote_path}/"])
    else:
        if apply:
            local_path.mkdir(parents=True, exist_ok=True)
        arguments.extend([f"{manifest.host.ssh_alias}:{remote_path}/", f"{local_path}/"])
    print("apply" if apply else "dry-run", direction, f"{project.name}/{artifact_name}")
    run(arguments)


def artifact_plan_path(project: ProjectConfig, artifact_name: str, direction: str) -> Path:
    return Path.home() / STATE_RELATIVE / "artifact-plans" / project.name / f"{artifact_name}-{direction}.json"


def record_artifact_plan(project: ProjectConfig, artifact_name: str, direction: str) -> None:
    _write_json(
        artifact_plan_path(project, artifact_name, direction),
        {
            "artifact": artifact_name,
            "created_at": int(time.time()),
            "direction": direction,
            "project": project.name,
        },
    )


def require_artifact_plan(project: ProjectConfig, artifact_name: str, direction: str) -> Path:
    path = artifact_plan_path(project, artifact_name, direction)
    payload = _read_json(path)
    if time.time() - int(payload.get("created_at", 0)) > 3600:
        raise NasError("artifact dry-run plan is older than one hour; plan again")
    if payload.get("project") != project.name or payload.get("artifact") != artifact_name:
        raise NasError("artifact dry-run receipt does not match this transfer")
    if payload.get("direction") != direction:
        raise NasError("artifact dry-run direction does not match this transfer")
    return path


def github_slug(repo: str) -> str:
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?", repo)
    if not match:
        raise NasError(f"GitHub repository URL is not supported: {repo}")
    return match.group(1)


def doctor(manifest: Manifest, *, remote_side: bool) -> None:
    required = ["jj", "jw", "codex", "gh", "uv", "rsync", "tmux", "git"]
    missing = [name for name in required if shutil.which(name) is None]
    print(f"host={socket.gethostname()} user={os.environ.get('USER', '')} manifest={manifest.path}")
    print("tools=" + ("ok" if not missing else "missing:" + ",".join(missing)))
    if missing:
        raise NasError("required tools missing")
    if remote_side:
        if Path.home() != manifest.host.remote_home:
            raise NasError(f"remote home mismatch: expected {manifest.host.remote_home}, got {Path.home()}")
        run(["codex", "login", "status"])
        run(["gh", "auth", "status"])
        headers = output(["gh", "api", "-i", "user"])
        oauth_scopes = re.search(r"^x-oauth-scopes:\s*(.+)$", headers, flags=re.IGNORECASE | re.MULTILINE)
        if oauth_scopes and oauth_scopes.group(1).strip():
            raise NasError(
                "GitHub credential uses legacy broad OAuth scopes; replace it with a fine-grained repo token"
            )
        for project in manifest.projects.values():
            run(["gh", "api", f"repos/{github_slug(project.repo)}", "--jq", ".full_name"])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="nas", description="Safe CerpacNAS project handoff and remote Codex control")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor")
    config = sub.add_parser("config")
    config.add_argument("action", choices=("status", "update"))
    projects = sub.add_parser("projects")
    projects.add_argument("action", choices=("status", "sync"))
    projects.add_argument("project", nargs="?")
    projects.add_argument("--all", action="store_true", dest="all_projects")
    handoff = sub.add_parser("handoff")
    handoff.add_argument("project")
    handoff.add_argument("task")
    handoff.add_argument("--to", choices=("nas", "mac"), required=True)
    handoff.add_argument("--push", action="store_true")
    validate = sub.add_parser("validate")
    validate.add_argument("project")
    validate.add_argument("task")
    validate.add_argument("lane")
    validate.add_argument("--calibrate", action="store_true")
    agent = sub.add_parser("agent")
    agent_sub = agent.add_subparsers(dest="agent_action", required=True)
    start = agent_sub.add_parser("start")
    start.add_argument("project")
    start.add_argument("task")
    start.add_argument("--mode", choices=("explore", "work"), required=True)
    start.add_argument("prompt", nargs="+")
    status = agent_sub.add_parser("status")
    status.add_argument("run_id", nargs="?")
    logs = agent_sub.add_parser("logs")
    logs.add_argument("run_id")
    logs.add_argument("--lines", type=int, default=80)
    attach = agent_sub.add_parser("attach")
    attach.add_argument("run_id")
    stop = agent_sub.add_parser("stop")
    stop.add_argument("run_id")
    artifact = sub.add_parser("artifact")
    artifact.add_argument("action", choices=("plan", "push", "pull"))
    artifact.add_argument("project")
    artifact.add_argument("artifact")
    artifact.add_argument("--direction", choices=("push", "pull"), default="push")
    artifact.add_argument("--apply", action="store_true")
    hidden = sub.add_parser("_remote", help=argparse.SUPPRESS)
    hidden.add_argument("remote_args", nargs=argparse.REMAINDER)
    return parser


def remote_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="nas _remote")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("doctor")
    projects = sub.add_parser("projects")
    projects.add_argument("action", choices=("status", "sync"))
    projects.add_argument("project", nargs="?")
    projects.add_argument("--all", action="store_true", dest="all_projects")
    config = sub.add_parser("config")
    config.add_argument("action", choices=("status", "update"))
    receive = sub.add_parser("handoff-receive")
    receive.add_argument("project")
    receive.add_argument("bookmark")
    receive.add_argument("commit")
    release = sub.add_parser("handoff-release")
    release.add_argument("project")
    release.add_argument("bookmark")
    release.add_argument("--push", action="store_true")
    release.add_argument("--no-push", action="store_false", dest="push")
    clear = sub.add_parser("handoff-clear")
    clear.add_argument("project")
    clear.add_argument("bookmark")
    start = sub.add_parser("agent-start")
    start.add_argument("project")
    start.add_argument("bookmark")
    start.add_argument("mode", choices=("explore", "work"))
    start.add_argument("prompt")
    status = sub.add_parser("agent-status")
    status.add_argument("run_id", nargs="?")
    logs = sub.add_parser("agent-logs")
    logs.add_argument("run_id")
    logs.add_argument("lines", type=int)
    stop = sub.add_parser("agent-stop")
    stop.add_argument("run_id")
    validate = sub.add_parser("validate")
    validate.add_argument("project")
    validate.add_argument("bookmark")
    validate.add_argument("lane")
    validate.add_argument("--calibrate", action="store_true")
    return parser


def project_by_name(manifest: Manifest, name: str) -> ProjectConfig:
    try:
        return manifest.projects[name]
    except KeyError as error:
        raise NasError(f"unknown project: {name}") from error


def remote_project_by_name(manifest: Manifest, name: str) -> ProjectConfig:
    project = project_by_name(manifest, name)
    require_contained(project.remote_path, manifest.host.remote_project_root, f"projects.{name}.remote_path")
    require_contained(
        project.remote_path.resolve(),
        manifest.host.remote_project_root.resolve(),
        f"resolved projects.{name}.remote_path",
    )
    if project.local_path != project.remote_path:
        raise NasError(f"remote manifest local_path must equal remote_path for {name}")
    return project


def handle_remote(manifest: Manifest, arguments: list[str]) -> None:
    options = remote_parser().parse_args(arguments)
    if options.command == "doctor":
        doctor(manifest, remote_side=True)
    elif options.command == "projects":
        selection = "--all" if options.all_projects or not options.project else options.project
        for project in selected_projects(manifest, selection):
            if project.local_path != project.remote_path:
                raise NasError(f"remote manifest local_path must equal remote_path for {project.name}")
            sync_project_local(project) if options.action == "sync" else project_status(project)
    elif options.command == "config":
        config_update(manifest) if options.action == "update" else config_status(manifest)
    elif options.command == "handoff-receive":
        print(
            json.dumps(
                remote_receive(
                    manifest, remote_project_by_name(manifest, options.project), options.bookmark, options.commit
                )
            )
        )
    elif options.command == "handoff-release":
        print(
            json.dumps(
                remote_release(
                    manifest,
                    remote_project_by_name(manifest, options.project),
                    options.bookmark,
                    push=options.push,
                )
            )
        )
    elif options.command == "handoff-clear":
        remote_clear(manifest, remote_project_by_name(manifest, options.project), options.bookmark)
    elif options.command == "agent-start":
        print(
            json.dumps(
                remote_agent_start(
                    manifest,
                    remote_project_by_name(manifest, options.project),
                    options.bookmark,
                    options.mode,
                    options.prompt,
                )
            )
        )
    elif options.command == "agent-status":
        print(json.dumps(remote_agent_status(manifest, options.run_id)))
    elif options.command == "agent-logs":
        print(remote_agent_logs(manifest, options.run_id, options.lines))
    elif options.command == "agent-stop":
        payload = _read_json(run_path(manifest, options.run_id) / "meta.json")
        run(["tmux", "kill-session", "-t", str(payload["session"])], check=False)
    elif options.command == "validate":
        print(
            json.dumps(
                remote_validate(
                    manifest,
                    remote_project_by_name(manifest, options.project),
                    options.bookmark,
                    options.lane,
                    calibrate=options.calibrate,
                )
            )
        )


def main(argv: list[str] | None = None) -> int:
    options = build_parser().parse_args(argv)
    try:
        manifest = load_manifest(options.manifest)
        if options.command == "_remote":
            handle_remote(manifest, options.remote_args)
        elif options.command == "doctor":
            doctor(manifest, remote_side=False)
            remote(manifest, ["doctor"])
        elif options.command == "config":
            remote(manifest, ["config", options.action])
        elif options.command == "projects":
            selection = "--all" if options.all_projects or not options.project else options.project
            for project in selected_projects(manifest, selection):
                if options.action == "sync":
                    sync_project_local(project)
                else:
                    project_status(project)
            remote(manifest, ["projects", options.action, selection])
        elif options.command == "handoff":
            handle_handoff(manifest, project_by_name(manifest, options.project), options.task, options.to, options.push)
        elif options.command == "validate":
            bookmark = normalize_bookmark(options.task)
            arguments = ["validate", options.project, bookmark, options.lane]
            if options.calibrate:
                arguments.append("--calibrate")
            result = remote(manifest, arguments, capture=True)
            payload = last_json(result.stdout)
            if not isinstance(payload, dict):
                raise NasError("invalid validation receipt")
            print(
                f"{payload['lane']}: {'pass' if payload['passed'] else 'fail'}; "
                f"{payload['duration_seconds']}s; {payload['peak_rss_mib']} MiB peak RSS"
            )
            if not payload["passed"]:
                raise NasError(f"validation failed; remote log: {payload['log']}")
        elif options.command == "agent":
            if options.agent_action == "start":
                prompt = " ".join(options.prompt).strip()
                if not prompt:
                    raise NasError("agent start needs a prompt after --")
                bookmark = normalize_bookmark(options.task)
                result = remote(
                    manifest,
                    ["agent-start", options.project, bookmark, options.mode, prompt],
                    capture=True,
                )
                payload = last_json(result.stdout)
                if not isinstance(payload, dict):
                    raise NasError("invalid agent start payload")
                print(f"started {payload['run_id']} in {payload['session']}")
            elif options.agent_action == "status":
                result = remote(
                    manifest,
                    ["agent-status", *([options.run_id] if options.run_id else [])],
                    capture=True,
                )
                payload = last_json(result.stdout)
                if not isinstance(payload, list):
                    raise NasError("invalid agent status payload")
                for item in payload:
                    print(f"{item['run_id']} {item['status']} mode={item['mode']} result={item['result']}")
            elif options.agent_action == "logs":
                result = remote(manifest, ["agent-logs", options.run_id, str(options.lines)], capture=True)
                print(result.stdout, end="")
            elif options.agent_action == "attach":
                status_result = remote(manifest, ["agent-status", options.run_id], capture=True)
                status_payload = last_json(status_result.stdout)
                if not isinstance(status_payload, list) or not status_payload:
                    raise NasError("invalid agent status payload")
                payload = status_payload[0]
                command = remote_shell_command(["tmux", "attach", "-t", str(payload["session"])])
                run(["ssh", "-t", manifest.host.ssh_alias, command], tty=True)
            elif options.agent_action == "stop":
                remote(manifest, ["agent-stop", options.run_id])
        elif options.command == "artifact":
            if options.action == "plan" and options.apply:
                raise NasError("artifact plan cannot use --apply")
            apply = options.apply and options.action in {"push", "pull"}
            if options.action in {"push", "pull"} and not options.apply:
                raise NasError("artifact push/pull requires explicit --apply; use artifact plan first")
            direction = options.direction if options.action == "plan" else options.action
            project = project_by_name(manifest, options.project)
            receipt = require_artifact_plan(project, options.artifact, direction) if apply else None
            artifact_transfer(
                manifest,
                project,
                options.artifact,
                direction,
                apply,
            )
            if options.action == "plan":
                record_artifact_plan(project, options.artifact, direction)
                print("plan receipt valid for one hour")
            elif receipt:
                receipt.unlink()
        return 0
    except NasError as error:
        print(f"nas: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
