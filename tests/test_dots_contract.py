"""The configuration contract: hooks, commands, installer exceptions and settings.

Every test runs a copy of the manager against a fixture configuration with a
fake mise, a temporary HOME and no network. Nothing touches the real machine.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from lib.prereq import requires

ROOT = Path(__file__).resolve().parents[1]

# A fake mise: logs every call, answers [vars] from FAKE_VAR_<name>, runs
# `exec -- COMMAND` directly, simulates source sync with FAKE_SYNC, and
# succeeds for every other subcommand without doing anything.
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
                    [[ -n "${!variable+set}" ]] || exit 1
                    printf '%s\n' "${!variable}"; exit 0 ;;
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
        shutil.copytree(ROOT / "manager", self.manager, ignore=shutil.ignore_patterns("dots-up", "__pycache__"))
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
        (self.f.config / "dots/hooks/update.d/80-directory").mkdir()

        result = self.f.update()

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        labels = [line[3:-3] for line in result.stdout.splitlines() if line.startswith("== ")]
        hooks = labels[labels.index("first"):labels.index("standalone mise")]
        self.assertEqual(hooks, ["first", "Deferred step", "skipped", "broken", "after failure"])
        self.assertIn("== Deferred step ==\nResult: deferred; needs attention", result.stdout)
        self.assertIn("== skipped ==\nSkipped: not here\nResult: skipped", result.stdout)
        self.assertIn("== broken ==\nbroken-output\nResult: failed (exit 7)", result.stdout)
        self.assertIn("Update report: failures: broken; ", result.stdout)
        self.assertTrue((out / "after").exists(), "a later hook did not run after a failure")
        self.assertFalse((out / "not-executable").exists())
        self.assertFalse((out / "odd").exists())
        self.assertEqual((out / "env").read_text().splitlines(),
                         [str(self.f.config), str(self.f.manager), "laptop", "1", "1", str(self.f.config)])
        # Hooks run after installer exceptions and before standalone mise.
        self.assertLess(result.stdout.index("== declared mise tools =="), result.stdout.index("== first =="))

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


class HookListingTests(ContractTestCase):
    def test_listing_and_labels(self) -> None:
        self.f.hook("bootstrap.d", "b-two", "")
        self.f.hook("bootstrap.d", "A-one.sh", "")
        self.f.hook("bootstrap.d", "-dash", "")
        self.f.hook("bootstrap.d", "skip.me~", "")
        self.f.hook("bootstrap.d", "plain", "", mode=0o644)
        directory = self.f.config / "dots/hooks/bootstrap.d"
        result = self.f.bash(f'setup_list_hooks "{directory}"; setup_list_hooks "{directory}/missing"; '
                             'for n in 10-Login-shell.sh 20_a.b.c 7 x-; do setup_hook_label "$n"; done')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [f"{directory}/A-one.sh", f"{directory}/b-two",
                                                      "Login shell", "a.b", "7", "x "])


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
            "laptop\tone\thold=kanata\n": "invalid hold package 'kanata'",
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
                             'setup_print_exceptions && setup_list_hooks "$SETUP_ROOT/dots/hooks/update.d"')
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual(listed.stdout, "Installer exceptions: none declared\n")

    def test_update_names_a_missing_profiles_setting(self) -> None:
        del self.f.env["FAKE_VAR_dots_profiles"]
        result = self.f.update()
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing setting: add dots_profiles to [vars]", result.stderr)


class RepositorySettingsTests(unittest.TestCase):
    def test_this_configuration_declares_the_manager_settings(self) -> None:
        text = (ROOT / "config.toml").read_text()
        for name in ("dots_profiles", "dots_source_repo", "dots_state_repo"):
            self.assertRegex(text, rf'(?m)^{name} = "[^"]+"$')


if __name__ == "__main__":
    unittest.main()
