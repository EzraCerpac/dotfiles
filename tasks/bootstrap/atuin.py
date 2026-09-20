#!/usr/bin/env python3
"""Create and consume the narrow encrypted Atuin enrollment bundle."""

from __future__ import annotations

import argparse
import json
import os
import pty
import re
import select
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path


ACCOUNT = "EzraCerpac"
EXIT_USAGE = 2
EXIT_DEFERRED = 3
EXIT_ACCOUNT = 20
EXIT_AUTH = 21
EXIT_NETWORK = 22
COMMAND_TIMEOUT = 30
LOGIN_TIMEOUT = 60
RECIPIENT = re.compile(r"^age1[0-9a-z]{20,}$")
SAFE_STATUS = re.compile(r"^[A-Za-z0-9:+., _/()\-]{1,100}$")
LOGGED_OUT_STATUS = "You are not logged in to a sync server - cannot show sync status"


class AtuinError(RuntimeError):
    def __init__(self, message: str, code: int = EXIT_USAGE) -> None:
        super().__init__(message)
        self.code = code


def executable(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise AtuinError(f"{name} is not installed")
    return path


def clean_env(*, ensure_session: bool = False) -> dict[str, str]:
    env = os.environ.copy()
    for name in tuple(env):
        upper = name.upper()
        if upper.startswith("ATUIN_") and any(word in upper for word in ("PASSWORD", "KEY", "SECRET")):
            env.pop(name, None)
    if ensure_session and not env.get("ATUIN_SESSION"):
        result = subprocess.run(
            [executable("atuin"), "uuid"],
            env=env,
            text=True,
            capture_output=True,
            timeout=COMMAND_TIMEOUT,
            check=False,
        )
        candidate = result.stdout.strip()
        try:
            parsed = uuid.UUID(candidate)
        except ValueError:
            raise AtuinError("Atuin could not create a native session for sync", EXIT_DEFERRED)
        if result.returncode != 0 or candidate.lower() not in {str(parsed), parsed.hex}:
            raise AtuinError("Atuin could not create a native session for sync", EXIT_DEFERRED)
        env["ATUIN_SESSION"] = candidate
    return env


def run_atuin(
    *args: str, timeout: int = COMMAND_TIMEOUT, ensure_session: bool = False
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [executable("atuin"), *args],
        env=clean_env(ensure_session=ensure_session),
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def validate_secret(value: object, name: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise AtuinError(f"encrypted bundle has an invalid {name}")
    if "\x00" in value or "\n" in value or "\r" in value:
        raise AtuinError(f"encrypted bundle has an invalid {name}")
    return value


def validate_bundle(value: object) -> dict[str, str]:
    if not isinstance(value, dict) or set(value) != {"version", "username", "password", "history_key"}:
        raise AtuinError("decrypted Atuin bundle has an unexpected shape")
    if value["version"] != 1 or value["username"] != ACCOUNT:
        raise AtuinError("encrypted Atuin bundle is for a different account")
    return {
        "username": ACCOUNT,
        "password": validate_secret(value["password"], "password"),
        "history_key": validate_secret(value["history_key"], "history key"),
    }


def read_password() -> str:
    raw = sys.stdin.readline(4097)
    if len(raw) == 4097 and not raw.endswith("\n"):
        raise AtuinError("encrypted bundle has an invalid password")
    if raw.endswith("\n"):
        raw = raw[:-1]
        if raw.endswith("\r"):
            raw = raw[:-1]
    return validate_secret(raw, "password")


def current_key() -> str:
    result = run_atuin("key")
    if result.returncode != 0:
        raise AtuinError("Atuin has no readable local history key")
    return validate_secret(result.stdout.strip(), "history key")


def atomic_encrypt(document: dict[str, object], output: Path, recipients: list[str]) -> None:
    if not recipients or any(not RECIPIENT.fullmatch(item) for item in recipients):
        raise AtuinError("supply at least one valid age public recipient")
    recipients = list(dict.fromkeys(recipients))
    output = output.expanduser()
    if output.exists() or output.is_symlink():
        raise AtuinError("output already exists; review it before replacing the bundle")
    if not output.parent.is_dir():
        raise AtuinError("output directory does not exist")

    payload = json.dumps(document, separators=(",", ":")).encode()
    age_args = [executable("age")]
    for recipient in recipients:
        age_args.extend(("--recipient", recipient))

    try:
        fd, temporary_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    except OSError:
        raise AtuinError("could not create the encrypted output beside its destination")
    temporary = Path(temporary_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb", closefd=True) as encrypted:
            process = subprocess.Popen(
                age_args,
                env=clean_env(),
                stdin=subprocess.PIPE,
                stdout=encrypted,
                stderr=subprocess.DEVNULL,
            )
            try:
                process.communicate(payload, timeout=COMMAND_TIMEOUT)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                raise AtuinError("age encryption timed out")
            if process.returncode != 0:
                raise AtuinError("age could not encrypt the Atuin bundle")
            encrypted.flush()
            os.fsync(encrypted.fileno())
        try:
            os.link(temporary, output)
        except FileExistsError:
            raise AtuinError("output already exists; review it before replacing the bundle")
        except OSError:
            raise AtuinError("could not publish the encrypted Atuin bundle")
    finally:
        payload = b""
        temporary.unlink(missing_ok=True)


def bundle_command(output: Path, recipients: list[str]) -> None:
    if output.expanduser().exists() or output.expanduser().is_symlink():
        raise AtuinError("output already exists; review it before replacing the bundle")
    password = read_password()
    history_key = current_key()
    atomic_encrypt(
        {"version": 1, "username": ACCOUNT, "password": password, "history_key": history_key},
        output,
        recipients,
    )
    password = ""
    history_key = ""
    print(f"Encrypted Atuin enrollment bundle written to {output.expanduser()}")


def regular_file(path: Path, label: str) -> Path:
    path = path.expanduser()
    try:
        mode = path.lstat().st_mode
    except OSError:
        raise AtuinError(f"{label} is missing or unreadable")
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode) or not os.access(path, os.R_OK):
        raise AtuinError(f"{label} must be a readable regular file")
    return path


def decrypt_bundle(path: Path, identity: Path) -> dict[str, str]:
    bundle = regular_file(path, "Atuin bundle")
    key_file = regular_file(identity, "age identity")
    if bundle.stat().st_size > 65_536:
        raise AtuinError("encrypted Atuin bundle is unexpectedly large")
    try:
        result = subprocess.run(
            [executable("age"), "--decrypt", "--identity", str(key_file), str(bundle)],
            env=clean_env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=COMMAND_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise AtuinError("Atuin bundle decryption timed out")
    if result.returncode != 0 or len(result.stdout) > 16_384:
        raise AtuinError("cannot decrypt Atuin bundle with this age identity")
    try:
        value = json.loads(result.stdout)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise AtuinError("decrypted Atuin bundle is not valid JSON")
    return validate_bundle(value)


def remote_state() -> tuple[str | None, str | None, str]:
    result = run_atuin("status")
    text = f"{result.stdout}\n{result.stderr}"
    username = None
    matched = re.search(r"(?im)^\s*Username:\s*([A-Za-z0-9._-]{1,64})\s*$", text)
    if matched:
        username = matched.group(1)
    last_sync = None
    matched = re.search(r"(?im)^\s*Last sync:\s*(.+?)\s*$", text)
    if matched and SAFE_STATUS.fullmatch(matched.group(1)):
        last_sync = matched.group(1)
    if result.returncode == 0 and username:
        state = "ready"
    elif result.returncode != 0 and LOGGED_OUT_STATUS in text and username is None:
        state = "logged_out"
    else:
        state = "error"
    return username, last_sync, state


def hub_authenticated() -> bool:
    result = run_atuin("doctor")
    if result.returncode != 0:
        return False
    starts = [matched.start() for matched in re.finditer(r"(?m)^\{", result.stdout)]
    for start in reversed(starts):
        try:
            document = json.loads(result.stdout[start:])
            auth_state = document["atuin"]["sync"]["auth_state"]
        except (json.JSONDecodeError, KeyError, TypeError):
            continue
        return auth_state == "Hub (authenticated)"
    return False


def native_login(history_key: str, password: str) -> None:
    cli = executable("atuin")
    pid, master = pty.fork()
    if pid == 0:
        try:
            os.execve(cli, [cli, "login", "--username", ACCOUNT], clean_env())
        except BaseException:
            os._exit(127)

    deadline = time.monotonic() + LOGIN_TIMEOUT
    transcript = bytearray()
    sent_key = False
    sent_password = False
    deferred = False
    rejected = False
    pending_error: AtuinError | None = None
    returncode: int | None = None

    def poll_child() -> int | None:
        waited, child_status = os.waitpid(pid, os.WNOHANG)
        return os.waitstatus_to_exitcode(child_status) if waited else None

    def stop_child() -> None:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    try:
        while returncode is None:
            returncode = poll_child()
            if returncode is not None:
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                pending_error = AtuinError("Atuin login timed out; rerun enrollment", EXIT_DEFERRED)
                stop_child()
                break
            readable, _, _ = select.select([master], [], [], min(0.25, remaining))
            if not readable:
                continue
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            transcript.extend(chunk)
            if len(transcript) > 32_768:
                del transcript[:-16_384]
            lower = transcript.decode(errors="ignore").lower()
            key_prompt = "please enter encryption key"
            password_prompt = "please enter password"
            if sent_key and key_prompt in lower:
                rejected = True
                stop_child()
                break
            if sent_password and password_prompt in lower:
                rejected = True
                stop_child()
                break
            if not sent_key and key_prompt in lower:
                os.write(master, history_key.encode() + b"\n")
                sent_key = True
                transcript.clear()
            elif not sent_password and password_prompt in lower:
                os.write(master, password.encode() + b"\n")
                sent_password = True
                transcript.clear()
            elif any(marker in lower for marker in ("totp", "two-factor", "two factor", "2fa", "open your browser", "open this url", "visit http")):
                deferred = True
                stop_child()
                break
        wait_deadline = time.monotonic() + 3
        while returncode is None and time.monotonic() < wait_deadline:
            returncode = poll_child()
            if returncode is None:
                time.sleep(0.05)
        if returncode is None:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            _, child_status = os.waitpid(pid, 0)
            returncode = os.waitstatus_to_exitcode(child_status)
    finally:
        os.close(master)
        if returncode is None:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass

    if pending_error:
        raise pending_error
    if deferred:
        raise AtuinError("Atuin needs a browser or two-factor step; rerun enrollment in a terminal", EXIT_DEFERRED)
    if rejected:
        raise AtuinError("Atuin rejected the account password or history key", EXIT_AUTH)
    if returncode != 0:
        raise AtuinError("Atuin rejected the account password or history key", EXIT_AUTH)
    if not sent_key or not sent_password:
        raise AtuinError("Atuin login prompts changed; rerun after updating the enrollment helper", EXIT_DEFERRED)


def configure() -> None:
    settings = (
        ("auto_sync", "true", "boolean"),
        ("sync_frequency", "5m", "string"),
        ("filter_mode", "global", "string"),
        ("ai.enabled", "true", "boolean"),
    )
    for key, value, value_type in settings:
        result = run_atuin("config", "set", key, value, "--type", value_type)
        if result.returncode != 0:
            raise AtuinError(f"Atuin could not set {key}")
    print("Atuin sync, global search, and AI settings are configured.")


def enroll(root: Path, identity: Path | None) -> None:
    executable("atuin")
    root = root.expanduser()
    bundle_path = root / "encrypted/atuin.json.age"
    identity_path = identity or Path("~/.config/age/keys.txt")
    username, _, login_state = remote_state()
    if login_state == "error":
        raise AtuinError("Atuin could not safely inspect the current login; rerun enrollment", EXIT_DEFERRED)
    if username and username != ACCOUNT:
        raise AtuinError(f"Atuin is already logged in as {username}; refusing to replace that account", EXIT_ACCOUNT)

    configure()

    if username == ACCOUNT:
        try:
            current_key()
        except AtuinError:
            raise AtuinError("Atuin reports the expected account but its local history key is unavailable", EXIT_AUTH)
        print(f"Atuin is already logged in as {ACCOUNT}; preserving the current session and history.")
    else:
        expanded_bundle = bundle_path.expanduser()
        expanded_identity = identity_path.expanduser()
        if not expanded_bundle.exists() and not expanded_bundle.is_symlink():
            raise AtuinError("settings are configured; login deferred because the Atuin bundle is missing", EXIT_DEFERRED)
        if not expanded_identity.exists() and not expanded_identity.is_symlink():
            raise AtuinError("settings are configured; login deferred because the age identity is missing", EXIT_DEFERRED)
        secrets = decrypt_bundle(bundle_path, identity_path)
        native_login(secrets["history_key"], secrets["password"])
        verified_username, _, verified_state = remote_state()
        if verified_state != "ready" or verified_username != ACCOUNT:
            raise AtuinError("Atuin login did not produce the expected account", EXIT_AUTH)
        print(f"Atuin login completed for {ACCOUNT}.")

    sync = run_atuin("sync", timeout=LOGIN_TIMEOUT, ensure_session=True)
    if sync.returncode != 0:
        raise AtuinError("Atuin login is ready, but the first native sync failed; rerun enrollment", EXIT_NETWORK)
    print("Atuin history synchronized through the native client.")


def status() -> None:
    path = shutil.which("atuin")
    if not path:
        print("Installation: missing")
        print("Login: unavailable")
        print("Last sync: unavailable")
        print("AI readiness: unavailable")
        return
    version = run_atuin("--version")
    version_text = version.stdout.strip().splitlines()[0] if version.returncode == 0 else "installed"
    if not SAFE_STATUS.fullmatch(version_text):
        version_text = "installed"
    username, last_sync, login_state = remote_state()
    print(f"Installation: {version_text}")
    if login_state == "error":
        print("Login: unavailable")
    elif login_state == "logged_out":
        print("Login: not logged in")
    elif username == ACCOUNT:
        print(f"Login: ready ({ACCOUNT})")
    elif username:
        print("Login: different account")
    else:
        print("Login: not logged in")
    print(f"Last sync: {last_sync or 'never or unavailable'}")
    ai = run_atuin("config", "get", "ai.enabled")
    ai_enabled = ai.returncode == 0 and ai.stdout.strip().lower() == "true"
    if not ai_enabled:
        print("AI readiness: disabled")
    elif hub_authenticated():
        print("AI readiness: enabled; Hub authentication verified")
    else:
        print("AI readiness: enabled; Hub authentication unverified")


def parser() -> argparse.ArgumentParser:
    top = argparse.ArgumentParser(description=__doc__)
    commands = top.add_subparsers(dest="command", required=True)
    commands.add_parser("configure", help="set the narrow native Atuin preferences")
    enroll_parser = commands.add_parser("enroll", help="decrypt the bundle and enroll this machine")
    enroll_parser.add_argument("--root", required=True, type=Path)
    enroll_parser.add_argument("--identity", type=Path)
    commands.add_parser("status", help="print sanitized Atuin readiness")
    bundle_parser = commands.add_parser("bundle", help="encrypt the existing Atuin key and stdin password")
    bundle_parser.add_argument("--output", required=True, type=Path)
    bundle_parser.add_argument("--recipient", required=True, action="append")
    return top


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "configure":
            configure()
        elif args.command == "enroll":
            enroll(args.root, args.identity)
        elif args.command == "status":
            status()
        elif args.command == "bundle":
            bundle_command(args.output, args.recipient)
    except subprocess.TimeoutExpired:
        print("Atuin command timed out; rerun this step.", file=sys.stderr)
        return EXIT_DEFERRED
    except AtuinError as error:
        print(f"Atuin enrollment: {error}", file=sys.stderr)
        return error.code
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
