#!/usr/bin/env python3
"""Build verified jj-waltz main in scratch space and atomically activate jw."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile


REPOSITORY = "https://github.com/EzraCerpac/jj-waltz.git"
COMMIT = re.compile(r"[0-9a-f]{40}")
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")


class UpdateError(Exception):
    pass


def safe_directory(path, create=False):
    """Never traverse directory links when writing the installation."""
    for directory in reversed((path, *path.parents)):
        if directory.is_symlink():
            raise UpdateError(f"refusing symlinked installation directory: {directory}")
        if directory.exists():
            if not directory.is_dir():
                raise UpdateError(f"installation directory is not a directory: {directory}")
        elif create:
            directory.mkdir(mode=0o700)
        else:
            raise UpdateError(f"installation directory is missing: {directory}")


def regular_file(path, executable=False):
    if path.is_symlink() or not path.is_file():
        raise UpdateError(f"expected a regular file: {path}")
    if executable and not os.access(path, os.X_OK):
        raise UpdateError(f"expected an executable: {path}")


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def command_environment():
    environment = dict(os.environ)
    # Keep the selected toolchain and normal cache, but isolate Git paths and
    # reject ambient Cargo output/target/wrapper overrides for this build.
    for name in list(environment):
        if name.startswith(("GIT_", "CARGO_BUILD_", "CARGO_TARGET_", "CARGO_PROFILE_")) or name in {
            "RUSTFLAGS", "RUSTDOCFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_ENCODED_RUSTDOCFLAGS",
            "RUSTC", "RUSTDOC", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "RUSTC_BOOTSTRAP",
        }:
            del environment[name]
    environment["GIT_TERMINAL_PROMPT"] = "0"
    return environment


def run(arguments, cwd=None, environment=None):
    result = subprocess.run(arguments, cwd=cwd, env=environment, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        details = result.stderr.strip()
        # Cargo emits Rust diagnostics in its JSON stream.
        if arguments[0] == "cargo":
            diagnostics = []
            for line in result.stdout.splitlines():
                try:
                    rendered = json.loads(line).get("message", {}).get("rendered")
                    if rendered:
                        diagnostics.append(rendered.strip())
                except (ValueError, AttributeError):
                    pass
            details = "\n".join([details, *diagnostics]).strip()
        raise UpdateError(f"{arguments[0]} failed (exit {result.returncode})"
                          + (f":\n{details}" if details else ""))
    return result.stdout


def binary_version(path):
    regular_file(path, executable=True)
    result = subprocess.run([str(path), "--version"], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    reported = result.stdout.strip()
    if result.returncode or not reported.startswith("jw ") or not VERSION.fullmatch(reported[3:]):
        raise UpdateError(f"binary does not identify as jw: {path} ({reported!r})")
    return reported[3:]


def metadata(commit, version, checksum):
    return {"schema": 1, "repository": REPOSITORY, "source_commit": commit,
            "version": version, "sha256": checksum}


def managed_version(directory, commit=None, require_identity=False):
    safe_directory(directory)
    marker = directory / "source-commit"
    regular_file(marker)
    source_commit = marker.read_text().strip()
    if not COMMIT.fullmatch(source_commit):
        raise UpdateError(f"invalid jw source commit marker: {marker}")
    binary = directory / "jw"
    version = binary_version(binary)
    if directory.name != f"{version}-{source_commit[:12]}":
        raise UpdateError(f"jw version/source marker does not match installation directory: {directory}")
    if commit is not None and source_commit != commit:
        raise UpdateError(f"cached jw source commit does not match main: {directory}")
    checksum = digest(binary)
    identity = directory / "build.json"
    if require_identity and not identity.exists():
        raise UpdateError(f"cached jw lacks a validated build identity: {directory}")
    if identity.exists() or identity.is_symlink():
        regular_file(identity)
        try:
            recorded = json.loads(identity.read_text())
        except ValueError as error:
            raise UpdateError(f"invalid jw build identity: {identity}") from error
        if recorded != metadata(source_commit, version, checksum):
            raise UpdateError(f"jw build identity or binary digest mismatch: {directory}")
    return source_commit, version, checksum


def file_identity(path):
    info = path.lstat()
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def active_installation(active, managed_root, legacy_binary):
    if not active.exists() and not active.is_symlink():
        return None
    safe_directory(active.parent)
    if active.is_symlink():
        target = Path(os.path.abspath(active.parent / os.readlink(active)))
        if target.parent.parent == managed_root and target.name == "jw":
            commit, version, checksum = managed_version(target.parent)
            kind = "managed"
        elif target == legacy_binary:
            safe_directory(target.parent)
            version, checksum, commit, kind = binary_version(target), digest(target), None, "legacy"
        else:
            raise UpdateError(f"refusing jw symlink with another owner: {active} -> {os.readlink(active)}")
        identity = (file_identity(active), os.readlink(active), file_identity(target), checksum)
    else:
        target = active
        version, checksum, commit, kind = binary_version(target), digest(target), None, "legacy"
        identity = (file_identity(active), checksum)
    return {"target": target, "commit": commit, "version": version,
            "checksum": checksum, "kind": kind, "identity": identity}


def validate_previous(root):
    previous = root / "previous"
    if not previous.exists() and not previous.is_symlink():
        return
    if not previous.is_symlink():
        raise UpdateError(f"refusing unmanaged rollback pointer: {previous}")
    target = Path(os.path.abspath(root / os.readlink(previous)))
    if target.parent.parent != root or target.name != "jw":
        raise UpdateError(f"refusing rollback symlink with another owner: {previous}")
    if target.parent.name.startswith("legacy-"):
        safe_directory(target.parent)
        checksum = digest(target)
        binary_version(target)
        if target.parent.name != f"legacy-{checksum[:16]}":
            raise UpdateError(f"invalid legacy rollback binary: {target}")
    else:
        managed_version(target.parent, require_identity=True)


def write_identity(directory, commit, version, checksum):
    identity = directory / "build.json"
    if not identity.exists():
        # Marker-only versioned installs predate this helper. Adopt them only
        # after path, version and full source marker validation.
        descriptor, temporary = tempfile.mkstemp(prefix=".identity-", dir=directory)
        try:
            with os.fdopen(descriptor, "w") as destination:
                json.dump(metadata(commit, version, checksum), destination, sort_keys=True)
                destination.write("\n")
            os.link(temporary, identity)
        finally:
            os.unlink(temporary)


def publish_binary(root, binary, name, commit=None, version=None):
    destination = root / name
    checksum = digest(binary)
    if destination.exists() or destination.is_symlink():
        if commit:
            managed_version(destination, commit, require_identity=True)
        else:
            safe_directory(destination)
            if binary_version(destination / "jw") != version or digest(destination / "jw") != checksum:
                raise UpdateError(f"refusing different rollback binary: {destination}")
        return destination / "jw"
    stage = Path(tempfile.mkdtemp(prefix=".stage-", dir=root))
    try:
        shutil.copyfile(binary, stage / "jw")
        (stage / "jw").chmod(0o755)
        if binary_version(stage / "jw") != version or digest(stage / "jw") != checksum:
            raise UpdateError("staged jw failed binary validation")
        if commit:
            (stage / "source-commit").write_text(commit + "\n")
            write_identity(stage, commit, version, checksum)
        stage.rename(destination)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return destination / "jw"


def build_main(root, expected, environment):
    with tempfile.TemporaryDirectory(prefix=".build-", dir=root) as scratch:
        scratch = Path(scratch)
        source, target = scratch / "source", scratch / "target"
        git = lambda *args: run(["git", "-c", "core.hooksPath=/dev/null", *args], environment=environment)
        git("init", str(source))
        git("-C", str(source), "remote", "add", "origin", REPOSITORY)
        git("-C", str(source), "fetch", "--depth=1", "origin", "refs/heads/main")
        fetched = git("-C", str(source), "rev-parse", "FETCH_HEAD").strip()
        if fetched != expected:
            raise UpdateError("jj-waltz main changed during fetch; active jw was kept, retry dots up")
        git("-C", str(source), "checkout", "--detach", fetched)
        if (git("-C", str(source), "rev-parse", "HEAD").strip() != expected
                or git("-C", str(source), "config", "--get", "remote.origin.url").strip() != REPOSITORY
                or git("-C", str(source), "status", "--porcelain").strip()):
            raise UpdateError("isolated jj-waltz source failed repository/commit/cleanliness validation")
        manifest = source / "Cargo.toml"
        environment = {**environment, "CARGO_TARGET_DIR": str(target)}
        description = json.loads(run(["cargo", "metadata", "--locked", "--no-deps",
                                      "--format-version", "1", "--manifest-path", str(manifest)],
                                     cwd=source, environment=environment))
        packages = [package for package in description["packages"]
                    if package["manifest_path"] == str(manifest)]
        if len(packages) != 1 or packages[0]["name"] != "jj-waltz":
            raise UpdateError("isolated Cargo manifest is not the jj-waltz package")
        package = packages[0]
        version = package["version"]
        if (not VERSION.fullmatch(version)
                or not any(item["name"] == "jw" and "bin" in item["kind"]
                           for item in package["targets"])):
            raise UpdateError("jj-waltz manifest lacks a valid jw binary/version")
        destination = root / f"{version}-{expected[:12]}"
        if destination.exists() or destination.is_symlink():
            managed_version(destination, expected, require_identity=True)
            print(f"Reusing verified jw {version} at {expected}")
            return destination / "jw"
        print(f"Building jw {version} from jj-waltz main {expected}", flush=True)
        output = run(["cargo", "build", "--locked", "--release", "--bin", "jw",
                      "--manifest-path", str(manifest), "--target-dir", str(target),
                      "--message-format=json-render-diagnostics"], cwd=source, environment=environment)
        artifacts = []
        for line in output.splitlines():
            event = json.loads(line)
            if (event.get("reason") == "compiler-artifact" and event.get("package_id") == package["id"]
                    and event.get("target", {}).get("name") == "jw"
                    and "bin" in event.get("target", {}).get("kind", []) and event.get("executable")):
                artifacts.append(Path(event["executable"]))
        if len(artifacts) != 1:
            raise UpdateError("Cargo did not emit exactly one jj-waltz jw executable")
        binary = artifacts[0]
        regular_file(binary, executable=True)
        if not binary.resolve().is_relative_to(target.resolve()):
            raise UpdateError("Cargo jw executable escaped the isolated build directory")
        if binary_version(binary) != version:
            raise UpdateError("built jw version does not match its Cargo manifest")
        if (git("-C", str(source), "rev-parse", "HEAD").strip() != expected
                or git("-C", str(source), "status", "--porcelain").strip()):
            raise UpdateError("jj-waltz source changed during the locked build")
        return publish_binary(root, binary, destination.name, expected, version)


def stage_link(path, target):
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}-", dir=path.parent)
    os.close(descriptor)
    os.unlink(temporary)
    try:
        os.symlink(str(target), temporary)
    except OSError:
        if os.path.lexists(temporary):
            os.unlink(temporary)
        raise
    return temporary


def link_identity(path):
    return (file_identity(path), os.readlink(path)) if path.is_symlink() else None


def activate(active, binary, root, previous, before, legacy_binary):
    staged = []
    rollback = root / "previous"
    try:
        launcher = stage_link(active, binary)
        staged.append(launcher)
        saved_rollback = link_identity(rollback)
        restore = replacement = None
        if previous:
            validate_previous(root)
            replacement = stage_link(rollback, previous)
            staged.append(replacement)
            if saved_rollback:
                restore = stage_link(rollback, saved_rollback[1])
                staged.append(restore)
        if active_installation(active, root, legacy_binary) != before:
            raise UpdateError("active jw changed before activation; refusing replacement")
        if link_identity(rollback) != saved_rollback:
            raise UpdateError("jw rollback pointer changed before activation; refusing replacement")
        if replacement:
            os.replace(replacement, rollback)
            replaced_rollback = link_identity(rollback)
        try:
            os.replace(launcher, active)
        except OSError as error:
            if replacement:
                if link_identity(rollback) != replaced_rollback:
                    raise UpdateError("jw activation failed; rollback pointer changed externally, leaving it intact") from error
                try:
                    if restore:
                        os.replace(restore, rollback)
                    else:
                        rollback.unlink()
                except OSError as restore_error:
                    raise UpdateError(f"jw activation failed; rollback pointer restoration failed: {restore_error}") from error
            raise
    finally:
        for temporary in staged:
            if os.path.lexists(temporary):
                os.unlink(temporary)


def update(existing_only):
    home = Path(os.path.abspath(os.path.expanduser("~")))
    install_dir = Path(os.path.abspath(os.environ.get("JW_INSTALL_DIR", str(home / ".local/bin"))))
    active = install_dir / "jw"
    root = home / ".local/libexec/jj-waltz"
    legacy_binary = home / "Projects/jj-waltz/target/release/jw"
    if existing_only and not active.exists() and not active.is_symlink():
        print(f"Skipped jw: no existing installation at {active}")
        return
    safe_directory(install_dir, create=True)
    safe_directory(root, create=True)
    descriptor = os.open(root / ".update.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "r+") as lock:
        if not stat.S_ISREG(os.fstat(lock.fileno()).st_mode):
            raise UpdateError("jw updater lock is not a regular file")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise UpdateError("another jw updater is running; active jw was kept") from error
        before = active_installation(active, root, legacy_binary)
        validate_previous(root)
        environment = command_environment()
        result = run(["git", "ls-remote", "--exit-code", REPOSITORY, "refs/heads/main"], environment=environment)
        matches = [line.split() for line in result.splitlines()]
        if len(matches) != 1 or len(matches[0]) != 2 or matches[0][1] != "refs/heads/main" or not COMMIT.fullmatch(matches[0][0]):
            raise UpdateError("jj-waltz main did not resolve to one full source commit")
        desired = matches[0][0]
        if before and before["commit"] == desired:
            if active_installation(active, root, legacy_binary) != before:
                raise UpdateError("active jw changed during the update check; refusing identity adoption")
            write_identity(before["target"].parent, desired, before["version"], before["checksum"])
            print(f"jw is current: {before['version']} at {desired}")
            return
        binary = build_main(root, desired, environment)
        # An updater using this helper is serialized by the lock. A manual
        # installer can still change jw, so compare its full file/link identity.
        current = active_installation(active, root, legacy_binary)
        if current != before:
            raise UpdateError("active jw changed during the build; refusing activation")
        validate_previous(root)
        _, activated_version, _ = managed_version(binary.parent, desired, require_identity=True)
        previous = None
        if before:
            previous = before["target"]
            if before["kind"] == "managed":
                write_identity(previous.parent, before["commit"], before["version"], before["checksum"])
            else:
                previous = publish_binary(root, previous, f"legacy-{before['checksum'][:16]}",
                                          version=before["version"])
                if digest(previous) != before["checksum"]:
                    raise UpdateError("legacy jw changed while preserving rollback")
        # Prepare both links before mutation; preserve rollback if activation fails.
        activate(active, binary, root, previous, before, legacy_binary)
        print(f"Activated jw {activated_version} at {desired}: {active}")
        if before:
            print(f"Rollback binary retained at {root / 'previous'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-existing", action="store_true",
                        help="skip hosts without an existing jw installation")
    arguments = parser.parse_args()
    try:
        update(arguments.update_existing)
    except (UpdateError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(f"jw update failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
