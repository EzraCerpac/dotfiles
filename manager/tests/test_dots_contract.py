"""The configuration contract: hooks, commands, installer exceptions and settings.

Every test runs a copy of the manager against a fixture configuration with a
fake mise, a temporary HOME and no network. Nothing touches the real machine.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

from lib.prereq import requires

MANAGER = Path(__file__).resolve().parents[1]

# A fake mise: logs every call, answers [vars] from FAKE_VAR_<name> or else
# from the string in the --file it was given, runs `exec -- COMMAND` directly,
# simulates source sync with FAKE_SYNC, and succeeds for every other
# subcommand without doing anything.
FAKE_MISE = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_MISE_LOG"
while [[ "${1:-}" == -C || "${1:-}" == -E ]]; do shift 2; done
case "${1:-}" in
    config)
        if [[ "${2:-}" == get ]]; then
            key="${5:-}"
            case "$key" in
                vars.*)
                    variable="FAKE_VAR_${key#vars.}"
                    if [[ -n "${!variable+set}" ]]; then printf '%s\n' "${!variable}"; exit 0; fi
                    [[ "${3:-}" == --file && -f "${4:-}" ]] || exit 1
                    exec python3 -c '
import sys, tomllib
value = tomllib.load(open(sys.argv[1], "rb")).get("vars", {}).get(sys.argv[2])
sys.exit(1) if not isinstance(value, str) else print(value)
' "$4" "${key#vars.}" ;;
                *) exit 1 ;;
            esac
        fi
        exit 0 ;;
    exec)
        shift
        [[ "${1:-}" == -- ]] && shift
        for argument in "$@"; do
            if [[ "$argument" == */source-repo.mjs ]]; then
                [[ -z "${FAKE_SYNC:-}" ]] || bash -c "$FAKE_SYNC"
                exit 0
            fi
        done
        exec "$@" ;;
    ls) printf '{}\n' ;;
    which|settings) exit 1 ;;
    *) exit 0 ;;
esac
"""


def write(path: Path, text: str, mode: int = 0o644) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(text).lstrip())
    path.chmod(mode)
    return path


class Fixture:
    """A manager copy, a configuration, a fake mise and a private HOME."""

    def __init__(self, base: Path, *, profiles: str | None = "laptop server") -> None:
        self.base = base
        self.manager = base / "manager"
        shutil.copytree(MANAGER, self.manager, ignore=shutil.ignore_patterns("dots-up", "tests", "__pycache__"))
        self.config = base / "config"
        self.config.mkdir()
        (self.config / "config.toml").write_text("# minimal configuration\n")
        self.home = base / "home"
        self.home.mkdir()
        self.log = base / "mise.log"
        self.log.touch()
        self.mise = write(base / "bin/mise", FAKE_MISE, 0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("DOTS_", "MISE_", "SETUP_", "XDG_"))}
        self.env.update(HOME=str(self.home), DOTS_ROOT=str(self.config), DOTS_HOME=str(self.manager),
                        SETUP_MISE_BIN=str(self.mise), DOTS_MISE_BIN=str(self.mise), FAKE_MISE_LOG=str(self.log),
                        DOTS_UP_BIN="/nonexistent/dots-up")
        if profiles is not None:
            self.env["FAKE_VAR_dots_profiles"] = profiles

    def hook(self, kind: str, name: str, body: str, mode: int = 0o755) -> Path:
        return write(self.config / "dots/hooks" / kind / name, "#!/usr/bin/env bash\n" + textwrap.dedent(body), mode)

    def update(self, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        environment = {**self.env, "SETUP_PROFILE": "laptop", "DOTS_SOURCE_SYNC_DONE": "1", **env}
        return subprocess.run(["bash", str(self.manager / "tasks/update"), *args], cwd=self.config,
                              env=environment, capture_output=True, text=True, timeout=120, check=False)

    def dots(self, *args: str, cwd: Path | None = None, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(self.manager / "bin/dots"), *args], cwd=cwd or self.config,
                              env={**self.env, **env}, capture_output=True, text=True, timeout=60, check=False)

    def bash(self, script: str, **env: str) -> subprocess.CompletedProcess[str]:
        prelude = f'source "{self.manager}/lib/setup-common.sh"\n'
        return subprocess.run(["bash", "-c", prelude + script], cwd=self.config,
                              env={**self.env, "SETUP_PROFILE": "laptop", **env},
                              capture_output=True, text=True, timeout=60, check=False)


class ContractTestCase(unittest.TestCase):
    profiles: str | None = "laptop server"

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="dots-contract-")
        self.addCleanup(temporary.cleanup)
        self.f = Fixture(Path(temporary.name).resolve(), profiles=self.profiles)


@requires("jq")
class UpdateHookTests(ContractTestCase):
    def test_hooks_run_in_name_order_with_contract_environment_and_statuses(self) -> None:
        out = self.f.base / "out"
        out.mkdir()
        # Created out of order; dispatch follows the names.
        self.f.hook("update.d", "50-after-failure", f"touch {out}/after\n")
        self.f.hook("update.d", "40-broken", "echo broken-output; exit 7\n")
        self.f.hook("update.d", "30-skipped.sh", "echo 'Skipped: not here'; exit 4\n")
        self.f.hook("update.d", "20-Deferred_step", "exit 3\n")
        self.f.hook("update.d", "10-first", f"""
            printf '%s\\n' "$DOTS_ROOT" "$DOTS_HOME" "$DOTS_PROFILE" "$DOTS_TOOLS_OK" "$DOTS_TOOLS_UPGRADED" "$PWD" > {out}/env
        """)
        self.f.hook("update.d", "60-not-executable", f"touch {out}/not-executable\n", mode=0o644)
        self.f.hook("update.d", "70 odd name", f"touch {out}/odd\n")
        self.f.hook("update.d", "45-laptop-only@laptop", "true\n")
        self.f.hook("update.d", "46-server-only@server", f"touch {out}/server\n")
        (self.f.config / "dots/hooks/update.d/80-directory").mkdir()

        result = self.f.update()

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        labels = [line[3:-3] for line in result.stdout.splitlines() if line.startswith("== ")]
        hooks = labels[labels.index("first"):labels.index("standalone mise")]
        self.assertEqual(hooks, ["first", "Deferred step", "skipped", "broken", "laptop only", "after failure"])
        self.assertIn("== Deferred step ==\nResult: deferred; needs attention", result.stdout)
        self.assertIn("== skipped ==\nSkipped: not here\nResult: skipped", result.stdout)
        self.assertIn("== broken ==\nbroken-output\nResult: failed (exit 7)", result.stdout)
        self.assertIn("Update report: failures: broken; ", result.stdout)
        self.assertTrue((out / "after").exists(), "a later hook did not run after a failure")
        self.assertFalse((out / "not-executable").exists())
        self.assertFalse((out / "odd").exists())
        self.assertFalse((out / "server").exists())
        self.assertEqual((out / "env").read_text().splitlines(),
                         [str(self.f.config), str(self.f.manager), "laptop", "1", "1", str(self.f.config)])
        # Hooks run after installer exceptions and before standalone mise.
        self.assertLess(result.stdout.index("== declared mise tools =="), result.stdout.index("== first =="))

    def test_hook_changes_reach_the_stage_report(self) -> None:
        import json
        write(self.f.config / "dots/exceptions/recipe", "#!/usr/bin/env bash\ntrue\n", 0o755)
        write(self.f.config / "dots/exceptions.tsv", "laptop\trecipe\n")
        self.f.hook("update.d", "10-Reports-changes", r"""
            printf 'plugin-a\tabc123\tdef456\n' >> "$DOTS_CHANGES"
            printf 'no tabs here\n\none\ttwo\n\tempty\titem\na\tb\tc\td\n' >> "$DOTS_CHANGES"
            printf 'plugin-b\tnot installed\t\n' >> "$DOTS_CHANGES"
        """)
        self.f.hook("update.d", "20-Silent", '[[ -f "$DOTS_CHANGES" ]] && printf "%s" "$DOTS_CHANGES" > ' + f'{self.f.base}/path\n')
        events = self.f.base / "events"
        # The dashboard passes events on descriptor 3; recipes and hooks must not disturb it.
        result = subprocess.run(["bash", "-c", 'exec 3>>"$0"; exec bash "$1"', str(events), str(self.f.manager / "tasks/update")],
                                cwd=self.f.config, env={**self.f.env, "SETUP_PROFILE": "laptop", "DOTS_SOURCE_SYNC_DONE": "1",
                                                        "DOTS_UP_EVENT_FD": "3"},
                                capture_output=True, text=True, timeout=120, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        parsed = [json.loads(line) for line in events.read_text().splitlines()]
        changes = [(e["stage"], e["item"], e["before"], e["after"]) for e in parsed if e["kind"] == "change"]
        self.assertEqual(changes, [("Reports-changes", "plugin-a", "abc123", "def456"),
                                   ("Reports-changes", "plugin-b", "not installed", "")])
        self.assertIn("Note: ignored 4 malformed DOTS_CHANGES line(s)", result.stdout)
        notices = [e for e in parsed if e["kind"] == "notice" and e.get("stage") == "Reports-changes"]
        self.assertEqual(len(notices), 1)
        self.assertIn({"kind": "stage_end", "id": "installer-exception--recipe", "status": "ok"},
                      [{k: e.get(k) for k in ("kind", "id", "status")} for e in parsed])
        # Every hook gets its own file, removed after the stage.
        self.assertFalse(Path((self.f.base / "path").read_text()).exists())

    @unittest.skipUnless(sys.platform == "darwin", "the Homebrew app stages are macOS only")
    def test_declared_casks_and_app_store_apps_select_the_homebrew_stages(self) -> None:
        plain = self.f.update()
        self.assertIn("== newly declared host packages ==", plain.stdout)
        self.assertNotIn("Homebrew", plain.stdout)
        write(self.f.config / "config.laptop.toml", '[bootstrap.packages]\n"mas:123" = { os = "macos/arm64" }\n')
        apps = self.f.update()
        self.assertIn("Skipped: Mac App Store updates (use dots up --mas to include them).", apps.stdout)
        self.assertIn("== new Homebrew casks ==", apps.stdout)
        self.assertNotIn("== newly declared host packages ==", apps.stdout)
        write(self.f.config / "config.laptop.toml", '[bootstrap.packages."brew-cask:thing"]\nos = "macos/arm64"\n')
        casks = self.f.update()
        self.assertIn("== new Homebrew casks ==", casks.stdout)
        self.assertNotIn("Mac App Store", casks.stdout)
        # Another profile's declarations do not count.
        server = self.f.update(SETUP_PROFILE="server")
        self.assertIn("== newly declared host packages ==", server.stdout)

    def test_unknown_profile_suffix_runs_no_hooks_and_fails(self) -> None:
        marker = self.f.base / "ran"
        self.f.hook("update.d", "10-fine", f"touch {marker}\n")
        self.f.hook("update.d", "20-typo@labtop", "true\n")
        result = self.f.update()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('names unknown profile "labtop"', result.stderr)
        self.assertIn("Update report: failures: update hooks; ", result.stdout)
        self.assertFalse(marker.exists())

    def test_deferred_hook_is_reported_without_failing_the_run(self) -> None:
        self.f.hook("update.d", "10-Later", "exit 3\n")
        result = self.f.update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Update report: completed; needs attention: Later; ", result.stdout)

    def test_failed_tools_install_is_visible_to_hooks(self) -> None:
        out = self.f.base / "tools"
        self.f.hook("update.d", "10-tools", f'printf "%s %s" "$DOTS_TOOLS_OK" "$DOTS_TOOLS_UPGRADED" > {out}\n')
        failing = write(self.f.base / "bin/failing-mise", FAKE_MISE.replace(
            "    *) exit 0 ;;\nesac", "    install) exit 9 ;;\n    *) exit 0 ;;\nesac"), 0o755)
        result = self.f.update(SETUP_MISE_BIN=str(failing))
        self.assertIn("== newly declared mise tools ==\nResult: failed (exit 9)", result.stdout)
        self.assertNotIn("== declared mise tools ==", result.stdout)
        self.assertEqual(out.read_text(), "0 0")

    def test_install_only_exceptions_run_with_the_flag(self) -> None:
        log = self.f.base / "recipes"
        for name in ("plain-app", "self-updater", "everywhere"):
            write(self.f.config / "dots/exceptions" / name, f'#!/usr/bin/env bash\necho "{name} $*" >> {log}\n', 0o755)
        write(self.f.config / "dots/exceptions.tsv",
              "# profile\tname\tflags\nlaptop\tplain-app\nlaptop\tself-updater\tinstall-only,hold=brew:thing\n"
              "server\tnot-here\nbase\teverywhere\n")
        result = self.f.update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(log.read_text().splitlines(), ["plain-app ", "self-updater --install-only", "everywhere "])
        self.assertIn("== installer exception: self-updater ==", result.stdout)

    def test_recipes_get_the_callers_stdin_not_the_manifest(self) -> None:
        log = self.f.base / "stdin"
        for name in ("reader", "after-reader"):
            write(self.f.config / "dots/exceptions" / name,
                  f'#!/usr/bin/env bash\nIFS= read -r line || line="<eof>"\necho "{name}:$line" >> {log}\n', 0o755)
        write(self.f.config / "dots/exceptions.tsv", "laptop\treader\nlaptop\tafter-reader\n")
        result = subprocess.run(["bash", str(self.f.manager / "tasks/update")], cwd=self.f.config,
                                env={**self.f.env, "SETUP_PROFILE": "laptop", "DOTS_SOURCE_SYNC_DONE": "1"},
                                input="from-terminal\nsecond-line\n", capture_output=True, text=True, timeout=120, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # Each recipe reads the caller's input; neither consumes a manifest row.
        self.assertEqual(log.read_text().splitlines(), ["reader:from-terminal", "after-reader:second-line"])

    def test_source_sync_that_changes_the_manager_reexecs_once_into_the_new_code(self) -> None:
        update = self.f.manager / "tasks/update"
        changed = self.f.base / "update.new"
        changed.write_text(update.read_text().replace("no updater failures.", "no updater failures (new manager)."))
        changed.chmod(0o755)
        sync = f'cp "{changed}" "{update}.tmp" && mv "{update}.tmp" "{update}"'
        result = self.f.update(DOTS_SOURCE_SYNC_DONE="0", FAKE_SYNC=sync)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Update report: completed; no updater failures (new manager).", result.stdout)
        calls = self.f.log.read_text().splitlines()
        self.assertEqual(sum("source-repo.mjs sync" in call for call in calls), 1, calls)
        reexecs = [call for call in calls if call.endswith(f"exec -- bash {self.f.manager}/tasks/update")]
        self.assertEqual(len(reexecs), 1, calls)


class ProfileTests(ContractTestCase):
    def test_internal_profile_selects_a_profile_of_the_configuration(self) -> None:
        result = self.f.dots("internal", "profile", "--profile", "server", "--machine-id", "fx",
                             MISE_CONFIG_DIR=str(self.f.config))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Saved local setup profile server for host fx.", result.stdout)
        self.assertEqual((self.f.config / "miserc.toml").read_text(), 'env = ["server", "host-fx"]\n')
        unknown = self.f.dots("internal", "profile", "--profile", "desktop", "--machine-id", "fx",
                              MISE_CONFIG_DIR=str(self.f.config))
        self.assertEqual(unknown.returncode, 2)
        self.assertIn("profile must be one of: laptop, server", unknown.stderr)


class HookListingTests(ContractTestCase):
    def list(self, directory: Path, profile: str = "laptop") -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(self.f.manager / "lib/dots-hooks"), str(directory), profile, "laptop", "server"],
                              capture_output=True, text=True, timeout=60, check=False)

    def test_listing_labels_and_profile_suffixes(self) -> None:
        self.f.hook("bootstrap.d", "b-two", "")
        self.f.hook("bootstrap.d", "A-one.sh", "")
        self.f.hook("bootstrap.d", "-dash", "")
        self.f.hook("bootstrap.d", "skip.me~", "")
        self.f.hook("bootstrap.d", "plain", "", mode=0o644)
        self.f.hook("bootstrap.d", "10-Login-shell.sh", "")
        self.f.hook("bootstrap.d", "20_a.b.c", "")
        self.f.hook("bootstrap.d", "30-Laptop-only@laptop", "")
        self.f.hook("bootstrap.d", "31-x.sh@server", "")
        self.f.hook("bootstrap.d", "32-backup@laptop~", "")
        directory = self.f.config / "dots/hooks/bootstrap.d"
        result = self.list(directory)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            f"Login shell\t{directory}/10-Login-shell.sh", f"a.b\t{directory}/20_a.b.c",
            f"Laptop only\t{directory}/30-Laptop-only@laptop", f"A one\t{directory}/A-one.sh", f"b two\t{directory}/b-two"])
        server = self.list(directory, "server")
        self.assertEqual([line.split("\t")[0] for line in server.stdout.splitlines()],
                         ["Login shell", "a.b", "x", "A one", "b two"])
        missing = self.list(directory / "missing")
        self.assertEqual((missing.returncode, missing.stdout), (0, ""))

    def test_unknown_profile_suffix_fails_without_listing(self) -> None:
        self.f.hook("update.d", "10-fine", "")
        typo = self.f.hook("update.d", "20-typo@labtop", "")
        result = self.list(typo.parent)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn(f'dots: hook {typo} names unknown profile "labtop"; use one of: laptop server', result.stderr)


class CommandTests(ContractTestCase):
    def command(self, name: str, body: str) -> Path:
        return write(self.f.config / "dots/commands" / name, "#!/usr/bin/env bash\n" + body, 0o755)

    def test_config_command_receives_literal_arguments_and_environment(self) -> None:
        self.command("hello", 'printf "[%s]\\n" "$@" "$DOTS_ROOT" "$DOTS_HOME" "$DOTS_PROFILE" "$PWD"\n')
        elsewhere = self.f.base / "elsewhere"
        elsewhere.mkdir()
        result = self.f.dots("hello", "two words", "--help", "*", "", "-x", cwd=elsewhere, SETUP_PROFILE="server")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["[two words]", "[--help]", "[*]", "[]", "[-x]",
                                                      f"[{self.f.config}]", f"[{self.f.manager}]", "[server]", f"[{elsewhere}]"])
        self.assertEqual(self.f.log.read_text(), "", "a configuration command loaded mise")

    def test_builtin_commands_win(self) -> None:
        marker = self.f.base / "ran"
        self.command("sync", f"touch {marker}\n")
        result = self.f.dots("sync", "extra")
        self.assertEqual(result.returncode, 2)
        self.assertIn("dots: sync accepts only --source-only", result.stderr)
        self.assertFalse(marker.exists())

    def test_names_with_a_slash_or_leading_dash_are_rejected(self) -> None:
        self.command("hello", "echo ran\n")
        for name in ("../config/dots/commands/hello", "dots/commands/hello", "-hello"):
            with self.subTest(name=name):
                result = self.f.dots(name)
                self.assertEqual(result.returncode, 2)
                self.assertIn(f"dots: invalid command name '{name}'; use dots help", result.stderr)
                self.assertNotIn("ran", result.stdout)

    def test_missing_command_is_unknown(self) -> None:
        result = self.f.dots("nope", "arg")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stderr, "dots: unknown command 'nope'; use dots help\n")
        write(self.f.config / "dots/commands/nope", "#!/usr/bin/env bash\necho ran\n", 0o644)
        self.assertEqual(self.f.dots("nope").stderr, "dots: unknown command 'nope'; use dots help\n")

    def test_internal_listings_for_the_menu(self) -> None:
        self.command("hello", "true\n")
        self.command("status", "true\n")
        write(self.f.config / "dots/commands/plain", "true\n", 0o644)
        self.assertEqual(self.f.dots("internal", "commands").stdout, "hello\n")
        self.assertEqual(self.f.dots("internal", "profiles").stdout, "laptop\nserver\n")

    def test_help_lists_configuration_commands(self) -> None:
        self.command("hello", "true\n")
        self.command("status", "true\n")
        result = self.f.dots("help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Configuration commands", result.stdout)
        self.assertIn("  dots hello [ARGS...]", result.stdout)
        self.assertNotIn("dots status [ARGS...]", result.stdout)


class ExceptionManifestTests(ContractTestCase):
    def read(self, manifest: str) -> subprocess.CompletedProcess[str]:
        write(self.f.config / "dots/exceptions.tsv", manifest)
        return self.f.bash(
            f'SETUP_ROOT="{self.f.config}"; SETUP_EXCEPTION_MANIFEST="$SETUP_ROOT/dots/exceptions.tsv"\n'
            'row() { printf "%s|%s|%s\\n" "$1" "${2##*/}" "$3"; }\n'
            'setup_read_exceptions row laptop || exit $?\necho ---\nsetup_read_exceptions row "" || exit $?\n'
            'echo ---\nsetup_exception_holder brew-cask:org/tap/thing@2; echo "holder=$SETUP_HOLDER"\n')

    def test_flags_column_is_optional_and_parsed(self) -> None:
        result = self.read("# comment\nlaptop\tone\nserver\ttwo\tinstall-only\nbase\tthree\tinstall-only,hold=brew-cask:thing\n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split("---\n"), [
            "one|one|\nthree|three|install-only,hold=brew-cask:thing\n",
            "one|one|\ntwo|two|install-only\nthree|three|install-only,hold=brew-cask:thing\n",
            "holder=three\n",
        ])

    def test_invalid_rows_stop(self) -> None:
        cases = {
            "laptop\tone\tinstall-only\textra\n": "invalid installer exception row",
            "desktop\tone\n": "invalid installer exception row",
            "laptop\tone\tsometimes\n": "unknown installer exception flag 'sometimes'",
            "laptop\tone\thold=some-app\n": "invalid hold package 'some-app'",
            "laptop\t../one\n": "invalid installer exception name",
        }
        for manifest, message in cases.items():
            with self.subTest(manifest=manifest):
                result = self.read(manifest)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn(message, result.stderr)

    def test_missing_profiles_setting_is_named(self) -> None:
        del self.f.env["FAKE_VAR_dots_profiles"]
        result = self.read("laptop\tone\n")
        self.assertEqual(result.returncode, 2)
        self.assertIn(f"missing setting: add dots_profiles to [vars] in {self.f.config}/config.toml", result.stderr)

    def test_dots_add_refuses_a_held_package(self) -> None:
        write(self.f.config / "dots/exceptions.tsv", "laptop\tpinned\thold=brew:pinned-tool\n")
        result = self.f.dots("add", "--base", "brew:tap/x/pinned-tool@1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("brew:tap/x/pinned-tool@1 is held by installer exception 'pinned'", result.stderr)


@requires("age-keygen")
class HistoryFilesTests(ContractTestCase):
    def enroll(self, manifest: str) -> subprocess.CompletedProcess[str]:
        write(self.f.config / "dots/history-files.tsv", manifest)
        for name in ("shared", "laptop", "server"):
            write(self.f.home / ".config" / name, f"{name}\n")
        key = self.f.base / "keys/key.txt"
        key.parent.mkdir()
        subprocess.run(["age-keygen", "-o", str(key)], capture_output=True, check=True)
        return subprocess.run(
            ["bash", str(self.f.manager / "bootstrap/enroll-history"), "--profile", "laptop", "--machine-id", "fx",
             "--identity", str(key)],
            cwd=self.f.config, env={**self.f.env, "MISE_CONFIG_DIR": str(self.f.config)},
            capture_output=True, text=True, timeout=60, check=False)

    def test_profile_rows_select_the_tracked_files(self) -> None:
        result = self.enroll("# comment\nbase\t~/.config/shared\nlaptop\t~/.config/laptop\n"
                             "server\t~/.config/server\nlaptop\t~/.config/missing\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        variant = (self.f.config / "config.host-fx.toml").read_text()
        self.assertIn('[dotfiles."~/.config/shared"]', variant)
        self.assertIn('[dotfiles."~/.config/laptop"]', variant)
        self.assertNotIn("server", variant)
        self.assertNotIn("missing", variant)

    def test_unknown_profile_row_stops(self) -> None:
        result = self.enroll("desktop\t~/.config/laptop\n")
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid history file row", result.stderr)


@requires("jq")
class MinimalConfigurationTests(ContractTestCase):
    """A configuration with only config.toml (and its profiles) works."""

    def test_update_help_commands_and_exceptions_need_no_dots_directory(self) -> None:
        self.assertFalse((self.f.config / "dots").exists())
        result = self.f.update()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Update report: completed; no updater failures.", result.stdout)
        self.assertNotIn("installer exception", result.stdout)
        help_text = self.f.dots("help")
        self.assertEqual(help_text.returncode, 0, help_text.stderr)
        self.assertNotIn("Configuration commands", help_text.stdout)
        self.assertEqual(self.f.dots("anything").stderr, "dots: unknown command 'anything'; use dots help\n")
        listed = self.f.bash(f'SETUP_ROOT="{self.f.config}"; SETUP_EXCEPTION_MANIFEST="$SETUP_ROOT/dots/exceptions.tsv"; '
                             f'DOTS_HOME="{self.f.manager}"; setup_print_exceptions && setup_list_hooks "$SETUP_ROOT/dots/hooks/update.d"')
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual(listed.stdout, "Installer exceptions: none declared\n")

    def test_update_names_a_missing_profiles_setting(self) -> None:
        del self.f.env["FAKE_VAR_dots_profiles"]
        result = self.f.update()
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing setting: add dots_profiles to [vars]", result.stderr)


class InitTests(ContractTestCase):
    def init(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([str(self.f.manager / "bin/dots"), "init", *args], cwd=self.f.base,
                              env={key: value for key, value in self.f.env.items() if key != "DOTS_ROOT"},
                              capture_output=True, text=True, timeout=60, check=False)

    def test_creates_a_working_minimal_configuration_and_is_idempotent(self) -> None:
        result = self.init("fresh")
        self.assertEqual(result.returncode, 0, result.stderr)
        fresh = self.f.base / "fresh"
        self.assertTrue((fresh / "config.toml").read_text().startswith('[vars]\n'))
        self.assertIn('dots_profiles = "default"\n', (fresh / "config.toml").read_text())
        for directory in ("hooks/update.d", "hooks/bootstrap.d", "commands", "exceptions"):
            self.assertTrue((fresh / "dots" / directory).is_dir(), directory)
        for name in ("README.md", "exceptions.tsv", "history-files.tsv", "retired-dotfiles"):
            self.assertEqual((fresh / "dots" / name).read_text(), (self.f.manager / "init" / name).read_text())
        self.assertEqual((fresh / ".gitleaks.toml").read_text(), (self.f.manager / "init/gitleaks.toml").read_text())
        self.assertIn("created  dots/README.md", result.stdout)
        # The new configuration works: its profile is valid and its manifest parses.
        listed = self.f.dots("internal", "profiles", DOTS_ROOT=str(fresh), FAKE_VAR_dots_profiles="default")
        self.assertEqual(listed.stdout, "default\n")
        (fresh / "dots/README.md").write_text("mine\n")
        again = self.init("fresh")
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertNotIn("created", again.stdout)
        self.assertIn("kept     config.toml [vars] dots_profiles", again.stdout)
        self.assertEqual((fresh / "dots/README.md").read_text(), "mine\n")

    def test_adds_settings_to_an_existing_vars_table_once(self) -> None:
        config = write(self.f.base / "existing/config.toml",
                       'min_version = "1"\n\n[vars]\nname = "x"\ndots_source_repo = "a/b"\n\n[tools]\njq = "1"\n', 0o600)
        result = self.init(str(config.parent))
        self.assertEqual(result.returncode, 0, result.stderr)
        text = config.read_text()
        self.assertEqual(text.count("[vars]"), 1)
        self.assertLess(text.index("[vars]"), text.index('dots_profiles = "default"'))
        self.assertLess(text.index('dots_profiles = "default"'), text.index("[tools]"))
        self.assertNotIn("# dots_source_repo", text)
        self.assertIn("# dots_state_repo", text)
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
        no_vars = write(self.f.base / "plain/config.toml", '[tools]\njq = "1"\n')
        self.init(str(no_vars.parent))
        self.assertTrue(no_vars.read_text().startswith('[tools]\njq = "1"\n\n[vars]\n'))


if __name__ == "__main__":
    unittest.main()
