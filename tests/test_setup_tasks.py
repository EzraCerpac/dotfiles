from __future__ import annotations

import os
import json
import pty
import shutil
import select
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]


class SetupTaskTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = self.base / "setup-root"
        shutil.copytree(SOURCE_ROOT / "tasks", self.root / "tasks")
        # Each test owns its exception set; live profile exceptions may require
        # app data or a running app that deliberately does not exist in fixtures.
        (self.root / "tasks/setup/exceptions.tsv").write_text("")
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.log = self.base / "mise.log"
        self.git_log = self.base / "git.log"
        self._write_executable(
            self.bin / "mise",
            """#!/usr/bin/env bash
set -u
printf 'CALL' >> "$MISE_LOG"
printf '\\t%s' "$@" >> "$MISE_LOG"
printf '\\n' >> "$MISE_LOG"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -C|-E|--cd|--env) shift 2 ;;
        --quiet) shift ;;
        --yes) shift ;;
        *) break ;;
    esac
done
if [[ "${1:-}" == "settings" && "${2:-}" == "get" ]]; then
    printf '%s\\n' "${MISE_HISTORY_MODE:-manual}"
    exit 0
fi
if [[ "${FAIL_TOOL_STATUS:-0}" == "1" && "${1:-}" == "ls" && "${2:-}" == "--current" ]]; then
    exit 43
fi
if [[ "${FAIL_TOOL_UPGRADE:-0}" == "1" && "${1:-}" == "upgrade" && "${2:-}" == "--no-prune" ]]; then
    exit 44
fi
if [[ "${1:-}" == "which" && "${2:-}" == "ruby" ]]; then
    printf '%s\\n' "${MISE_TEST_RUBY_PATH:-}"
    exit 0
fi
if [[ "${1:-}" == "which" && "${2:-}" == "codex-acp" ]]; then
    printf '%s\\n' "${CODEX_ACP_CLI:-}"
    exit 0
fi
if [[ "${REQUIRE_RUBY_BIN:-0}" == "1" && "${1:-}" == "bootstrap" && "${2:-}" == "status" ]]; then
    case ":$PATH:" in
        *":$EXPECTED_RUBY_BIN:"*) ;;
        *) printf 'selected Ruby bin missing from PATH\\n' >&2; exit 77 ;;
    esac
fi
if [[ "${REQUIRE_RUBY_BIN:-0}" == "1" && "${1:-}" == "bootstrap" && "${2:-}" == "dotfiles" && "${3:-}" == "status" ]]; then
    case ":$PATH:" in
        *":$EXPECTED_RUBY_BIN:"*) printf 'Ruby bin leaked into dotfile status PATH\\n' >&2; exit 78 ;;
    esac
fi
if [[ "${1:-}" == "exec" ]]; then
    shift
    [[ "${1:-}" == "--" ]] && shift
    exec "$@"
fi
if [[ "${FAIL_PACKAGES:-0}" == "1" && "${1:-}" == "bootstrap" && "${2:-}" == "packages" && "${3:-}" == "upgrade" ]]; then
    exit 41
fi
if [[ "${FAIL_PULL:-0}" == "1" && "${1:-}" == "bootstrap" && "${2:-}" == "dotfiles" && "${3:-}" == "pull" ]]; then
    exit 42
fi
if [[ "${1:-}" == "bootstrap" && "${2:-}" == "dotfiles" && "${3:-}" == "paths" ]]; then
    if [[ "${4:-}" == "--json" ]]; then
        printf '%s' "$SETUP_HISTORY_PATHS_JSON"
    else
        printf '%s' "${SETUP_HISTORY_PATHS:-}"
    fi
    exit 0
fi
exit 0
""",
        )
        self._write_executable(
            self.bin / "git",
            """#!/usr/bin/env bash
set -euo pipefail
printf 'GIT' >> "$GIT_LOG"
printf '\\t%s' "$@" >> "$GIT_LOG"
printf '\\n' >> "$GIT_LOG"
if [[ "${1:-}" == "clone" ]]; then
    if [[ "${FAIL_CLONE:-0}" == "1" ]]; then exit 31; fi
    origin="$4"
    destination="$5"
    mkdir -p "$destination"
    printf '%s\\n' "$origin" > "$destination/FIXTURE_ORIGIN"
    printf 'fixture-remote-commit\\n' > "$destination/FIXTURE_COMMIT"
    touch "$destination/FIXTURE_BARE"
    exit 0
fi
if [[ "${1:-}" == --git-dir=* ]]; then
    store="${1#--git-dir=}"
    shift
    case "${1:-} ${2:-}" in
        'rev-parse --is-bare-repository')
            [[ -f "$store/FIXTURE_BARE" ]] || exit 1
            printf 'true\\n'
            ;;
        'config --get')
            [[ "${3:-}" == remote.origin.url && -f "$store/FIXTURE_ORIGIN" ]] || exit 1
            cat "$store/FIXTURE_ORIGIN"
            ;;
        'rev-parse --verify')
            [[ -f "$store/FIXTURE_COMMIT" ]] || exit 1
            cat "$store/FIXTURE_COMMIT"
            ;;
        'for-each-ref --format=%(refname)')
            [[ -f "$store/FIXTURE_COMMIT" ]] || exit 1
            printf 'refs/remotes/origin/setup\\n'
            ;;
        *) exit 90 ;;
    esac
    exit 0
fi
exit 91
""",
        )
        self._write_executable(
            self.bin / "pgrep",
            "#!/usr/bin/env bash\n[[ \"${WATCHER_ACTIVE:-0}\" == 1 ]] && exit 0\nexit 1\n",
        )
        self._write_executable(
            self.bin / "sudo",
            "#!/usr/bin/env bash\nexit 1\n",
        )
        self._write_executable(
            self.bin / "node",
            "#!/usr/bin/env bash\nif [[ \"${1:-}\" == \"-e\" && \"${2:-}\" == \"process.exit(0)\" ]]; then exit 0; fi\nexec python3 -c 'import json,sys; d=json.load(sys.stdin); [print(e[\"path\"]) for e in d[\"entries\"] if e.get(\"mode\")==\"track\"]'\n",
        )
        self._write_executable(
            self.bin / "age-keygen",
            "#!/usr/bin/env bash\nprintf 'age1fixturepublicrecipient0000000000000000000000000000000000000\\n'\n",
        )
        self._write_executable(
            self.bin / "nvim",
            "#!/usr/bin/env bash\nprintf 'NVIM' >> \"$MISE_LOG\"\nprintf '\\t%s' \"$@\" >> \"$MISE_LOG\"\nprintf '\\n' >> \"$MISE_LOG\"\n",
        )
        self.env = os.environ.copy()
        self.env.update(
            {
                "PATH": f"{self.bin}{os.pathsep}{self.env['PATH']}",
                "MISE_LOG": str(self.log),
                "GIT_LOG": str(self.git_log),
                "MISE_CONFIG_DIR": "/an/irrelevant/global/config",
                "SETUP_CONFIG_ROOT": str(self.root),
                "SETUP_MISE_BIN": str(self.bin / "mise"),
                "SETUP_PROFILE": "workstation",
                "SETUP_MACHINE_ID": "mac-primary",
                "HOME": str(self.base / "home"),
                "XDG_DATA_HOME": str(self.base / "home/.local/share"),
                "MISE_STATE_DIR": str(self.base / "state/mise"),
            }
        )
        Path(self.env["HOME"]).mkdir()
        codex_acp_modules = self.base / "mise-codex-acp/node_modules"
        codex_acp_cli = codex_acp_modules / ".bin/codex-acp"
        codex_acp_cli.parent.mkdir(parents=True)
        codex_acp_native = (
            codex_acp_modules
            / ".mise/@zed-industries+codex-acp-darwin-arm64@fixture/node_modules/"
            "@zed-industries/codex-acp-darwin-arm64/bin/codex-acp"
        )
        codex_acp_native.parent.mkdir(parents=True)
        self._write_executable(codex_acp_cli, '#!/usr/bin/env bash\nexec "$CODEX_ACP_NATIVE" "$@"\n')
        self._write_executable(codex_acp_native, "#!/usr/bin/env bash\nprintf 'fixture codex-acp help\\n'\n")
        self.env["CODEX_ACP_CLI"] = str(codex_acp_cli)
        self.env["CODEX_ACP_NATIVE"] = str(codex_acp_native)
        codex_config = Path(self.env["HOME"]) / ".codex/config.toml"
        codex_config.parent.mkdir(parents=True)
        codex_config.write_text("[fixture]\nrestored = true\n")
        identity = Path(self.env["HOME"]) / ".config/age/keys.txt"
        identity.parent.mkdir(parents=True)
        identity.write_text("fixture age identity\n")
        self.env["SETUP_AGE_IDENTITY"] = str(identity)
        self.env["SETUP_HISTORY_PATHS_JSON"] = json.dumps(
            {"entries": [{"path": str(codex_config), "mode": "track"}]}
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _write_executable(path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(0o755)

    def _prepare_brew_exceptions(
        self,
        *,
        installed: str = "zoom karabiner-elements tailscale-app font-sf-pro",
        outdated: str = "",
        busy: str = "",
        sudo_ok: str = "1",
    ) -> tuple[Path, Path, Path]:
        brew_log = self.base / "brew.log"
        sudo_log = self.base / "sudo.log"
        pgrep_log = self.base / "pgrep.log"
        self._write_executable(
            self.bin / "uname",
            "#!/usr/bin/env bash\n[[ \"${1:-}\" == -m ]] && printf 'arm64\\n' || printf 'Darwin\\n'\n",
        )
        self._write_executable(
            self.bin / "brew",
            """#!/usr/bin/env bash
set -euo pipefail
printf 'BREW' >> "$BREW_LOG"
for arg in "$@"; do printf '\\t%s' "$arg" >> "$BREW_LOG"; done
printf '\\n' >> "$BREW_LOG"
if [[ "${1:-}" == "--prefix" ]]; then
    printf '/opt/homebrew\\n'
    exit 0
fi
case "${1:-}" in
    list)
        token="${3:-}"
        case " ${BREW_INSTALLED:-} " in *" $token "*) exit 0 ;; *) exit 1 ;; esac
        ;;
    outdated)
        token=""
        for arg in "$@"; do token="$arg"; done
        case " ${BREW_OUTDATED:-} " in *" $token "*) printf '%s\\n' "$token" ;; *) : ;; esac
        exit "${BREW_OUTDATED_STATUS:-0}"
        ;;
    install|upgrade)
        [[ "${HOMEBREW_NO_AUTOREMOVE:-}" == "1" && "${HOMEBREW_NO_INSTALL_CLEANUP:-}" == "1" ]] || exit 91
        exit 0
        ;;
    *) exit 90 ;;
esac
""",
        )
        self._write_executable(
            self.bin / "sudo",
            """#!/usr/bin/env bash
printf 'SUDO\\t%s\\n' "$*" >> "$SUDO_LOG"
[[ "${SUDO_OK:-0}" == "1" ]]
""",
        )
        self._write_executable(
            self.bin / "id",
            "#!/usr/bin/env bash\n[[ \"${1:-}\" == \"-u\" ]] || exit 9\nprintf '501\\n'\n",
        )
        self._write_executable(
            self.bin / "pgrep",
            """#!/usr/bin/env bash
printf 'PGREP\\t%s\\n' "$*" >> "$PGREP_LOG"
[[ "${1:-}" == "-x" ]] || exit 2
case " ${BREW_BUSY_PROCESSES:-} " in *" ${2:-} "*) exit 0 ;; *) exit 1 ;; esac
""",
        )
        self.env.update(
            {
                "BREW_LOG": str(brew_log),
                "SUDO_LOG": str(sudo_log),
                "PGREP_LOG": str(pgrep_log),
                "BREW_INSTALLED": installed,
                "BREW_OUTDATED": outdated,
                "BREW_BUSY_PROCESSES": busy,
                "SUDO_OK": sudo_ok,
            }
        )
        return brew_log, sudo_log, pgrep_log

    def _run(self, task: str, *args: str, cwd: Path | None = None, extra_env: dict[str, str | None] | None = None):
        env = self.env.copy()
        if extra_env:
            for key, value in extra_env.items():
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = value
        return subprocess.run(
            [str(self.root / "tasks" / "setup" / task), *args],
            cwd=cwd or self.base,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def _calls(self) -> list[list[str]]:
        if not self.log.exists():
            return []
        return [line.split("\t")[1:] for line in self.log.read_text().splitlines()]

    def _git_calls(self) -> list[list[str]]:
        if not self.git_log.exists():
            return []
        return [line.split("\t")[1:] for line in self.git_log.read_text().splitlines()]

    def _history_store(self) -> Path:
        return Path(self.env["MISE_STATE_DIR"]) / "history/repo.git"

    def _mise_wrapper(self, path: Path) -> None:
        self._write_executable(
            path,
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$MISE_WRAPPER_NAME\" >> \"$MISE_SELECTION_LOG\"\nexec \"$BASE_MISE_STUB\" \"$@\"\n",
        )

    def _make_local_history(self, origin: str | None = None) -> Path:
        store = self._history_store()
        store.mkdir(parents=True)
        (store / "FIXTURE_BARE").touch()
        (store / "FIXTURE_COMMIT").write_text("fixture-local-commit\n")
        if origin:
            (store / "FIXTURE_ORIGIN").write_text(origin + "\n")
        return store

    def test_status_pins_every_child_mise_to_setup_root_and_selected_host(self) -> None:
        project = self.base / "some-project"
        project.mkdir()
        result = self._run("status", cwd=project)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self._calls()
        self.assertGreaterEqual(len(calls), 2)
        for call in calls:
            self.assertEqual(call[:4], ["-C", str(self.root.resolve()), "-E", "workstation,host-mac-primary"])
        self.assertIn(["ls", "--current"], [call[4:] for call in calls])
        self.assertIn("Setup profile: workstation", result.stdout)

    def test_status_fails_when_declared_tool_listing_fails(self) -> None:
        result = self._run("status", extra_env={"FAIL_TOOL_STATUS": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("status inspection reported a failure", result.stderr)

    def test_macos_aggregate_status_uses_selected_mise_ruby_without_leaking_path(self) -> None:
        platform_bin = self.base / "darwin-bin"
        platform_bin.mkdir()
        self._write_executable(platform_bin / "uname", "#!/usr/bin/env bash\nprintf 'Darwin\\n'\n")
        ruby_bin = self.base / "selected-ruby/bin"
        ruby_bin.mkdir(parents=True)
        ruby_path = ruby_bin / "ruby"
        self._write_executable(ruby_path, "#!/usr/bin/env bash\nexit 0\n")

        result = self._run(
            "status",
            extra_env={
                "PATH": f"{platform_bin}{os.pathsep}{self.env['PATH']}",
                "MISE_TEST_RUBY_PATH": str(ruby_path),
                "EXPECTED_RUBY_BIN": str(ruby_bin),
                "REQUIRE_RUBY_BIN": "1",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = [call[4:] for call in self._calls()]
        self.assertIn(["which", "ruby"], commands)
        self.assertIn(["bootstrap", "status"], commands)
        self.assertIn(["bootstrap", "dotfiles", "status"], commands)

    def test_backup_uses_outer_or_standalone_mise_before_older_path_entry(self) -> None:
        home = Path(self.env["HOME"])
        stable = home / ".local/bin/mise"
        stable.parent.mkdir(parents=True)
        self._mise_wrapper(stable)

        older_bin = self.base / "older-mise-bin"
        older_bin.mkdir()
        self._write_executable(
            older_bin / "mise",
            "#!/usr/bin/env bash\nprintf 'older-path\\n' >> \"$MISE_SELECTION_LOG\"\nexit 91\n",
        )
        invoking = self.base / "invoking-mise"
        self._mise_wrapper(invoking)
        selection_log = self.base / "mise-selection.log"
        test_env = {
            "PATH": f"{older_bin}{os.pathsep}{self.env['PATH']}",
            "SETUP_CONFIG_ROOT": str(self.root),
            "SETUP_MISE_BIN": None,
            "MISE_BIN": str(invoking),
            "MISE_SELECTION_LOG": str(selection_log),
            "BASE_MISE_STUB": str(self.bin / "mise"),
            "MISE_WRAPPER_NAME": "invoking",
        }

        from_outer = self._run("backup", extra_env=test_env)
        self.assertEqual(from_outer.returncode, 0, from_outer.stderr)
        self.assertTrue(all(line == "invoking" for line in selection_log.read_text().splitlines()))
        commands = [call[4:] for call in self._calls()]
        self.assertIn(["settings", "get", "history.sync"], commands)
        self.assertIn(["bootstrap", "dotfiles", "save"], commands)
        self.assertIn(["bootstrap", "dotfiles", "sync"], commands)

        selection_log.unlink()
        test_env["MISE_BIN"] = None
        test_env["MISE_WRAPPER_NAME"] = "standalone"
        from_standalone = self._run("backup", extra_env=test_env)
        self.assertEqual(from_standalone.returncode, 0, from_standalone.stderr)
        self.assertTrue(all(line == "standalone" for line in selection_log.read_text().splitlines()))

        selection_log.unlink()
        test_env["SETUP_MISE_BIN"] = str(self.bin / "mise")
        test_env["MISE_BIN"] = str(invoking)
        from_fixture = self._run("backup", extra_env=test_env)
        self.assertEqual(from_fixture.returncode, 0, from_fixture.stderr)
        self.assertFalse(selection_log.exists())

        def bootstrap_path(setup_mise_bin: str | None, mise_bin: str | None) -> str:
            env = self.env.copy()
            env.update(
                {
                    "PATH": f"{older_bin}{os.pathsep}{self.env['PATH']}",
                    "MISE_CONFIG_DIR": str(self.root),
                }
            )
            for key, value in (("SETUP_MISE_BIN", setup_mise_bin), ("MISE_BIN", mise_bin)):
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = value
            script = 'source "$1/tasks/bootstrap/common.sh"; bootstrap_init || exit $?; printf "%s\\n" "$BOOTSTRAP_MISE_BIN"'
            result = subprocess.run(
                ["bash", "-c", script, "bootstrap-path-probe", str(self.root)],
                cwd=self.base,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip()

        self.assertEqual(bootstrap_path(None, str(invoking)), str(invoking))
        self.assertEqual(bootstrap_path(None, None), str(stable))
        self.assertEqual(bootstrap_path(str(self.bin / "mise"), str(invoking)), str(self.bin / "mise"))

    def test_codex_acp_mode_repair_changes_only_selected_mise_payload(self) -> None:
        node_modules = self.base / "selected-mise/node_modules"
        cli = node_modules / ".bin/codex-acp"
        native = (
            node_modules
            / ".mise/@zed-industries+codex-acp-darwin-arm64@0.16.0/node_modules/"
              "@zed-industries/codex-acp-darwin-arm64/bin/codex-acp"
        )
        cli.parent.mkdir(parents=True)
        native.parent.mkdir(parents=True)
        self._write_executable(
            cli,
            """#!/usr/bin/env bash
exec "$CODEX_ACP_NATIVE" "$@"
""",
        )
        self._write_executable(
            native,
            """#!/usr/bin/env bash
[[ "$1" == "--help" ]] && printf 'codex-acp fixture help\\n'
""",
        )
        native.chmod(0o644)
        unrelated = self.base / "other-mise/codex-acp"
        unrelated.parent.mkdir()
        unrelated.write_text("unrelated install\n")
        unrelated.chmod(0o644)
        old_homebrew = self.base / "old-homebrew/codex-acp"
        old_homebrew.parent.mkdir()
        old_homebrew.write_text("old global launcher\n")
        old_homebrew.chmod(0o644)

        darwin_bin = self.base / "darwin-bin"
        darwin_bin.mkdir()
        self._write_executable(
            darwin_bin / "uname",
            """#!/usr/bin/env bash
[[ "$1" == "-m" ]] && printf 'arm64\\n' || printf 'Darwin\\n'
""",
        )
        result = self._run(
            "fix-codex-acp-mode",
            "--install-only",
            extra_env={
                "PATH": f"{darwin_bin}{os.pathsep}{self.env['PATH']}",
                "CODEX_ACP_CLI": str(cli),
                "CODEX_ACP_NATIVE": str(native),
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Repaired executable mode", result.stdout)
        self.assertIn("Verified Codex ACP", result.stdout)
        self.assertEqual(stat.S_IMODE(native.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE(unrelated.stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(old_homebrew.stat().st_mode), 0o644)

    def test_codex_acp_repair_runs_after_failed_tool_upgrade(self) -> None:
        selected_payload = Path(self.env["CODEX_ACP_NATIVE"])
        selected_payload.chmod(0o644)
        darwin_bin = self.base / "darwin-update-bin"
        darwin_bin.mkdir()
        self._write_executable(
            darwin_bin / "uname",
            "#!/usr/bin/env bash\n[[ \"${1:-}\" == -m ]] && printf 'arm64\\n' || printf 'Darwin\\n'\n",
        )

        result = self._run(
            "update",
            extra_env={
                "FAIL_TOOL_UPGRADE": "1",
                "PATH": f"{darwin_bin}{os.pathsep}{self.env['PATH']}",
            },
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("declared mise tools", result.stdout)
        self.assertIn("Result: failed (exit 44)", result.stdout)
        self.assertIn("Verified Codex ACP", result.stdout)
        self.assertEqual(stat.S_IMODE(selected_payload.stat().st_mode), 0o755)

    def test_update_aggregates_independent_failures_without_broad_upgrades(self) -> None:
        result = self._run("update", extra_env={"SETUP_PROFILE": "nas", "SETUP_MACHINE_ID": "cerpacnas", "FAIL_PACKAGES": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("declared host packages", result.stdout)
        self.assertIn("Update report: failures", result.stdout)
        calls = self._calls()
        commands = [call[4:] for call in calls]
        self.assertIn(["upgrade", "--no-prune"], commands)
        self.assertIn(["self-update", "--yes"], commands)
        self.assertEqual(commands[0], ["bootstrap", "dotfiles", "save"])
        self.assertEqual(commands[-1], ["bootstrap", "dotfiles", "save"])
        self.assertLess(commands.index(["self-update", "--yes"]), len(commands) - 1)
        rendered = " ".join(" ".join(command) for command in commands)
        self.assertNotIn("npm", rendered)
        self.assertNotIn("uv tool upgrade", rendered)
        self.assertNotIn("--prune", [arg for command in commands for arg in command])

    def test_macos_update_defers_mas_noninteractively_but_runs_other_managers(self) -> None:
        platform_bin = self.base / "macos-update-bin"
        platform_bin.mkdir()
        self._write_executable(
            platform_bin / "uname",
            "#!/usr/bin/env bash\n[[ \"${1:-}\" == -m ]] && printf 'arm64\\n' || printf 'Darwin\\n'\n",
        )
        sudo_log = self.base / "sudo.log"
        self._write_executable(
            platform_bin / "sudo",
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$SUDO_LOG\"\nexit 1\n",
        )

        result = self._run(
            "update",
            extra_env={
                "PATH": f"{platform_bin}{os.pathsep}{self.env['PATH']}",
                "SUDO_LOG": str(sudo_log),
            },
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Deferred: App Store updates need administrator authorization", result.stdout)
        self.assertIn("Homebrew formulae", result.stdout)
        self.assertIn("Homebrew casks", result.stdout)
        self.assertIn("declared mise tools", result.stdout)
        self.assertTrue(sudo_log.exists())
        self.assertEqual(sudo_log.read_text(), "-n true\n")

        commands = [call[4:] for call in self._calls()]
        self.assertIn(["bootstrap", "packages", "upgrade", "--manager", "brew", "--yes"], commands)
        self.assertIn(["bootstrap", "packages", "upgrade", "--manager", "brew-cask", "--yes"], commands)
        self.assertNotIn(["bootstrap", "packages", "upgrade", "--manager", "mas", "--yes"], commands)
        self.assertIn(["upgrade", "--no-prune"], commands)
        self.assertIn(["self-update", "--yes"], commands)

    def test_update_runs_only_named_exception_script(self) -> None:
        exception = self.root / "tasks/setup/exceptions/herdr-npm"
        exception.parent.mkdir(parents=True, exist_ok=True)
        self._write_executable(exception, "#!/usr/bin/env bash\nprintf 'called herdr\\n' >> \"$EXCEPTION_LOG\"\n")
        (self.root / "tasks/setup/exceptions.tsv").write_text("workstation\therdr-npm\n")
        result = self._run("update", extra_env={"EXCEPTION_LOG": str(self.base / "exception.log"), "SETUP_PROFILE": "workstation"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.base / "exception.log").read_text(), "called herdr\n")
        calls = self._calls()
        exception_calls = [call for call in calls if any(Path(arg).name == exception.name for arg in call)]
        self.assertEqual(len(exception_calls), 1)
        self.assertIn(str(exception.resolve()), exception_calls[0])

    def test_auto_update_cask_exceptions_use_named_greedy_only(self) -> None:
        brew_log, _, _ = self._prepare_brew_exceptions(
            outdated="zoom karabiner-elements tailscale-app font-sf-pro",
        )
        (self.root / "tasks/setup/exceptions.tsv").write_text(
            "workstation\tzoom\n"
            "workstation\tkarabiner-elements\n"
            "workstation\ttailscale-app\n"
            "workstation\tfont-sf-pro\n"
        )

        result = self._run("update")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        for token in ("zoom", "karabiner-elements", "tailscale-app", "font-sf-pro"):
            self.assertIn(["outdated", "--cask", "--greedy", "--quiet", token], calls)
            self.assertIn(["upgrade", "--cask", "--greedy", token], calls)
        self.assertFalse(any("--zap" in call or "--prune" in call for call in calls))

        refused = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; update_brew_cask_exception unlisted-cask ""',
                "brew-exception-test",
                str(self.root / "tasks/lib/brew-exception.sh"),
            ],
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(refused.returncode, 2)
        self.assertIn("Refusing unlisted Homebrew cask exception", refused.stderr)

    def test_cask_outdated_accepts_status_one_only_with_a_result(self) -> None:
        brew_log, _, _ = self._prepare_brew_exceptions(outdated="zoom")
        self.env["BREW_OUTDATED_STATUS"] = "1"
        result = subprocess.run(
            [str(self.root / "tasks/setup/exceptions/zoom")],
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        self.assertIn(["upgrade", "--cask", "--greedy", "zoom"], calls)

        brew_log.write_text("")
        self.env["BREW_OUTDATED"] = ""
        result = subprocess.run(
            [str(self.root / "tasks/setup/exceptions/zoom")],
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any("upgrade" in line for line in brew_log.read_text().splitlines()))

        brew_log.write_text("")
        self.env["BREW_OUTDATED"] = "zoom"
        self.env["BREW_OUTDATED_STATUS"] = "2"
        result = subprocess.run(
            [str(self.root / "tasks/setup/exceptions/zoom")],
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertFalse(any("upgrade" in line for line in brew_log.read_text().splitlines()))

    def test_named_formula_exceptions_are_exact_and_non_greedy(self) -> None:
        formulas = {
            "memo": "antoniorodr/memo/memo",
            "qmk": "qmk/qmk/qmk",
            "peekaboo": "steipete/tap/peekaboo",
        }
        brew_log, _, _ = self._prepare_brew_exceptions(
            installed=" ".join(formulas.values()),
            outdated=" ".join(formulas.values()),
        )
        self.env["BREW_OUTDATED_STATUS"] = "1"
        for exception, formula in formulas.items():
            result = subprocess.run(
                [str(self.root / "tasks/setup/exceptions" / exception)],
                cwd=self.base,
                env=self.env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
            self.assertIn(["outdated", "--formula", "--quiet", formula], calls)
            self.assertIn(["upgrade", "--formula", formula], calls)
            self.assertFalse(any("--greedy" in call for call in calls))

        config = (SOURCE_ROOT / "config.workstation.toml").read_text()
        for formula in formulas.values():
            self.assertNotIn(f'"brew:{formula}"', config)

        brew_log.write_text("")
        for exception, formula in formulas.items():
            result = subprocess.run(
                [str(self.root / "tasks/setup/exceptions" / exception), "--install-only"],
                cwd=self.base,
                env=self.env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"Already installed: {formula}", result.stdout)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        self.assertFalse(any(call and call[0] in ("install", "outdated", "upgrade") for call in calls))

        refused = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; update_brew_formula_exception unlisted-formula',
                "brew-formula-test",
                str(self.root / "tasks/lib/brew-exception.sh"),
            ],
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(refused.returncode, 2)
        self.assertIn("Refusing unlisted Homebrew formula exception", refused.stderr)

    def test_brew_cask_exceptions_defer_busy_or_unauthorized_installs(self) -> None:
        brew_log, sudo_log, _ = self._prepare_brew_exceptions(
            outdated="zoom karabiner-elements tailscale-app font-sf-pro",
            busy="zoom.us Karabiner-Core-Service Tailscale",
            sudo_ok="0",
        )
        scripts = self.root / "tasks/setup/exceptions"
        for token in ("zoom", "karabiner-elements", "tailscale-app"):
            result = subprocess.run(
                [str(scripts / token)],
                cwd=self.base,
                env=self.env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("is running; close it before upgrading", result.stdout)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        self.assertFalse(any(call and call[0] == "upgrade" for call in calls))
        self.assertFalse(sudo_log.exists())

        self.env["SUDO_OK"] = "1"
        result = subprocess.run(
            [str(scripts / "font-sf-pro")],
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        self.assertIn(["upgrade", "--cask", "--greedy", "font-sf-pro"], calls)
        self.assertTrue(sudo_log.exists())

        for path in (brew_log, sudo_log):
            path.write_text("")
        for token in ("zoom", "karabiner-elements", "tailscale-app", "font-sf-pro"):
            result = subprocess.run(
                [str(scripts / token), "--install-only"],
                cwd=self.base,
                env=self.env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"Already installed: {token}", result.stdout)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        self.assertFalse(any(call and call[0] in ("install", "outdated", "upgrade") for call in calls))
        self.assertEqual(sudo_log.read_text(), "")

        self.env["BREW_INSTALLED"] = "zoom karabiner-elements"
        self.env["BREW_BUSY_PROCESSES"] = ""
        self.env["SUDO_OK"] = "0"
        install = subprocess.run(
            [str(scripts / "tailscale-app"), "--install-only"],
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(install.returncode, 0, install.stderr)
        self.assertIn("needs interactive administrator authorization", install.stdout)
        self.assertIn("sudo -v && mise -C ~/.config/mise run setup:update", install.stdout)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        self.assertFalse(any(call and call[0] == "install" for call in calls))

    def test_interactive_cask_update_leaves_admin_prompt_to_brew(self) -> None:
        brew_log, sudo_log, _ = self._prepare_brew_exceptions(
            outdated="zoom",
            sudo_ok="0",
        )
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen(
                [str(self.root / "tasks/setup/exceptions/zoom")],
                cwd=self.base,
                env=self.env,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                close_fds=True,
            )
        finally:
            os.close(slave)
        try:
            while process.poll() is None:
                readable, _, _ = select.select([master], [], [], 0.1)
                if readable:
                    try:
                        os.read(master, 4096)
                    except OSError:
                        break
            returncode = process.wait(timeout=20)
        finally:
            os.close(master)
        self.assertEqual(returncode, 0)
        calls = [line.split("\t")[1:] for line in brew_log.read_text().splitlines()]
        self.assertIn(["upgrade", "--cask", "--greedy", "zoom"], calls)
        self.assertFalse(sudo_log.exists())

    def test_update_defers_missing_lazy_without_starting_editor(self) -> None:
        result = self._run("update")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Deferred: Lazy.nvim is not installed", result.stdout)
        self.assertNotIn("NVIM", self.log.read_text())

    def test_delftblue_update_refuses_before_any_mise_command(self) -> None:
        result = self._run("update", extra_env={"SETUP_PROFILE": "delftblue", "SETUP_MACHINE_ID": "delftblue"})
        self.assertEqual(result.returncode, 2)
        self.assertIn("disabled for delftblue", result.stderr)
        self.assertEqual(self._calls(), [])

    def _run_lazy_fixture(self, fail: bool = False) -> tuple[subprocess.CompletedProcess[str], Path]:
        nvim = shutil.which("nvim")
        if not nvim:
            self.skipTest("Neovim is unavailable for isolated Lazy updater fixture")

        fixture = self.base / "lazy-fixture"
        lua = fixture / "lua"
        fake_bin = fixture / "bin"
        fake_bin.mkdir(parents=True)
        clean = fixture / "plugins/clean-plugin"
        dirty = fixture / "plugins/dirty-plugin"
        pinned = fixture / "plugins/pinned-plugin"
        version_false = fixture / "plugins/version-false-plugin"
        for directory in (clean, dirty, pinned, version_false):
            (directory / ".git").mkdir(parents=True)
        (dirty / "dirty-marker").touch()
        (lua / "lazy/core").mkdir(parents=True)
        updates = fixture / "updated.txt"

        (lua / "lazy.lua").write_text(
            """local plugins = {
  { name = "clean-plugin", dir = vim.env.CLEAN_PLUGIN, _ = { tasks = {} } },
  { name = "dirty-plugin", dir = vim.env.DIRTY_PLUGIN, _ = { tasks = {} } },
  { name = "pinned-plugin", dir = vim.env.PINNED_PLUGIN, pin = true, _ = { tasks = {} } },
  { name = "commit-plugin", dir = vim.env.PINNED_PLUGIN, commit = "abc123", _ = { tasks = {} } },
  { name = "tag-plugin", dir = vim.env.PINNED_PLUGIN, tag = "v1.2.3", _ = { tasks = {} } },
  { name = "version-plugin", dir = vim.env.PINNED_PLUGIN, version = "1.2", _ = { tasks = {} } },
  { name = "version-false-plugin", dir = vim.env.VERSION_FALSE_PLUGIN, version = false, _ = { tasks = {} } },
  { name = "missing-plugin", dir = vim.env.MISSING_PLUGIN, _ = { tasks = {} } },
}
local by_name = {}
for _, plugin in ipairs(plugins) do by_name[plugin.name] = plugin end
local M = {}
function M.plugins() return plugins end
function M.update(opts)
  local file = assert(io.open(vim.env.UPDATE_LOG, "w"))
  for _, selected in ipairs(opts.plugins) do
    local plugin = type(selected) == "string" and by_name[selected] or selected
    file:write(plugin.name .. "\\n")
    local failed = vim.env.TEST_FAIL == "1"
    plugin._.tasks = {{
      has_errors = function() return failed end,
      output = function() return failed and "fixture task failure" or "" end,
    }}
  end
  file:close()
end
return M
"""
        )
        (lua / "lazy/core/config.lua").write_text(
            """local lazy = require("lazy")
local plugins = {}
for _, plugin in ipairs(lazy.plugins()) do plugins[plugin.name] = plugin end
return { plugins = plugins }
"""
        )
        self._write_executable(
            fake_bin / "git",
            "#!/bin/sh\n[ \"$1\" = -C ] || exit 9\n[ \"$3\" = status ] || exit 9\ncase \"$2\" in *dirty-plugin*) echo ' M local-change' ;; esac\n",
        )
        home = fixture / "home"
        home.mkdir()
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{fake_bin}{os.pathsep}{env['PATH']}",
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(fixture / "config"),
                "XDG_DATA_HOME": str(fixture / "data"),
                "XDG_STATE_HOME": str(fixture / "state"),
                "XDG_CACHE_HOME": str(fixture / "cache"),
                "SETUP_TEST_LUA_PATH": str(lua),
                "SETUP_TEST_SCRIPT": str(SOURCE_ROOT / "tasks/setup/lazy-update.lua"),
                "CLEAN_PLUGIN": str(clean),
                "DIRTY_PLUGIN": str(dirty),
                "PINNED_PLUGIN": str(pinned),
                "VERSION_FALSE_PLUGIN": str(version_false),
                "MISSING_PLUGIN": str(fixture / "plugins/missing-plugin"),
                "UPDATE_LOG": str(updates),
                "TEST_FAIL": "1" if fail else "0",
            }
        )
        try:
            result = subprocess.run(
                [
                    nvim,
                    "--headless",
                    "-u",
                    "NONE",
                    "--cmd",
                    "lua package.path = vim.env.SETUP_TEST_LUA_PATH .. '/?.lua;' .. vim.env.SETUP_TEST_LUA_PATH .. '/?/init.lua;' .. package.path",
                    "-c",
                    "lua dofile(vim.env.SETUP_TEST_SCRIPT)",
                    "-c",
                    "qa",
                ],
                cwd=fixture,
                env=env,
                text=True,
                capture_output=True,
                timeout=20,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise AssertionError(f"isolated Lazy script hung: stdout={error.stdout!r} stderr={error.stderr!r}") from error
        return result, updates

    def test_lazy_updater_selects_clean_unpinned_plugins_only(self) -> None:
        result, updates = self._run_lazy_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updates.read_text().splitlines(), ["clean-plugin", "version-false-plugin"])
        output = result.stdout + result.stderr
        self.assertIn("Pinned plugins kept: commit-plugin, pinned-plugin, tag-plugin, version-plugin", output)
        self.assertIn("Dirty plugins deferred: dirty-plugin", output)
        self.assertIn("Missing plugin checkouts deferred: missing-plugin", output)

    def test_lazy_task_errors_return_nonzero(self) -> None:
        result, _ = self._run_lazy_fixture(fail=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Lazy plugin update failures", result.stderr)
        self.assertIn("fixture task failure", result.stderr)

    def test_first_restore_clones_fetches_and_applies_remote_seed_without_publishing(self) -> None:
        origin = "git@github.com:EzraCerpac/dotfiles-state.git"
        tracked = Path(self.env["HOME"]) / ".config/aegis/config.json"
        tracked.parent.mkdir(parents=True)
        tracked.write_text('{"fixture":true}\n')
        tracked.chmod(0o644)
        unmanaged = Path(self.env["HOME"]) / ".config/aegis/linked.json"
        unmanaged.write_text('{"fixture":false}\n')
        codex_config = Path(self.env["HOME"]) / ".codex/config.toml"
        paths_json = json.dumps(
            {
                "entries": [
                    {"path": str(tracked), "mode": "track"},
                    {"path": str(codex_config), "mode": "track"},
                    {"path": str(unmanaged), "mode": "symlink"},
                ]
            }
        )
        result = self._run("restore", extra_env={"SETUP_HISTORY_ORIGIN": origin, "SETUP_HISTORY_PATHS_JSON": paths_json})
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self._calls()
        commands = [call[4:] for call in calls]
        self.assertEqual(commands[0], ["--yes", "bootstrap", "dotfiles", "origin", "set", origin, "--sync", "fetch-only"])
        self.assertIn(["bootstrap", "dotfiles", "status"], commands)
        self.assertIn(["--yes", "bootstrap", "dotfiles", "pull"], commands)
        self.assertIn(["bootstrap", "dotfiles", "rollback", "--to", "commit:fixture-remote-commit", "--all", "--dry-run"], commands)
        self.assertIn(["bootstrap", "dotfiles", "rollback", "--to", "commit:fixture-remote-commit", "--all", "--yes"], commands)
        rendered_calls = " ".join(" ".join(command) for command in commands)
        self.assertIn("dotfiles paths --json", rendered_calls)
        self.assertIn("exec -- node -e", rendered_calls)
        self.assertEqual(commands[-1], ["settings", "set", "history.sync", "manual"])
        self.assertFalse(any(command[1:3] == ["dotfiles", "sync"] for command in commands))
        self.assertFalse(any(command[1:3] == ["dotfiles", "save"] for command in commands))
        clone_calls = [call for call in self._git_calls() if call and call[0] == "clone"]
        self.assertEqual(len(clone_calls), 1)
        self.assertEqual(clone_calls[0][1:4], ["--bare", "--single-branch", origin])
        self.assertTrue((self._history_store() / "FIXTURE_BARE").exists())
        self.assertEqual(stat.S_IMODE(tracked.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(codex_config.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(unmanaged.stat().st_mode), 0o644)

    def test_connected_restore_keeps_existing_history_path_and_skips_seed_rollback(self) -> None:
        origin = "git@github.com:EzraCerpac/dotfiles-state.git"
        store = self._make_local_history(origin)
        result = self._run("restore", extra_env={"SETUP_HISTORY_ORIGIN": origin})
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = [call[4:] for call in self._calls()]
        self.assertFalse(any(call and call[0] == "clone" for call in self._git_calls()))
        self.assertFalse(any("rollback" in command for command in commands))
        self.assertEqual((store / "FIXTURE_COMMIT").read_text(), "fixture-local-commit\n")
        self.assertEqual(commands[-1], ["settings", "set", "history.sync", "manual"])

    def test_unconnected_history_requires_flag_and_is_preserved_before_replacement(self) -> None:
        origin = "git@github.com:EzraCerpac/dotfiles-state.git"
        old_store = self._make_local_history()
        (old_store / "old-history-marker").write_text("keep me\n")

        refused = self._run("restore", extra_env={"SETUP_HISTORY_ORIGIN": origin})
        self.assertEqual(refused.returncode, 2)
        self.assertIn("--initialize-history", refused.stderr)
        self.assertEqual((old_store / "old-history-marker").read_text(), "keep me\n")
        self.assertFalse(any(call and call[0] == "clone" for call in self._git_calls()))
        self.assertEqual(self._calls(), [])

        initialized = self._run("restore", "--initialize-history", extra_env={"SETUP_HISTORY_ORIGIN": origin})
        self.assertEqual(initialized.returncode, 0, initialized.stderr)
        backups = list(old_store.parent.glob("repo.git.pre-restore.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "repo.git/old-history-marker").read_text(), "keep me\n")
        self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o700)
        self.assertEqual((old_store / "FIXTURE_ORIGIN").read_text().strip(), origin)

    def test_clone_failure_keeps_old_history_store_at_original_path(self) -> None:
        old_store = self._make_local_history()
        marker = old_store / "old-history-marker"
        marker.write_text("preserve\n")
        result = self._run(
            "restore",
            "--initialize-history",
            extra_env={"SETUP_HISTORY_ORIGIN": "git@github.com:EzraCerpac/dotfiles-state.git", "FAIL_CLONE": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), "preserve\n")
        self.assertEqual(list(old_store.parent.glob("repo.git.pre-restore.*")), [])
        self.assertIn("left unchanged", result.stderr)

    def test_failed_pull_leaves_a_marker_so_first_restore_can_resume(self) -> None:
        origin = "git@github.com:EzraCerpac/dotfiles-state.git"
        first = self._run("restore", extra_env={"SETUP_HISTORY_ORIGIN": origin, "FAIL_PULL": "1"})
        self.assertNotEqual(first.returncode, 0)
        marker = self._history_store().parent / ".repo.git.restore-pending"
        self.assertEqual(marker.read_text().strip(), origin)
        self.log.unlink()

        resumed = self._run("restore", extra_env={"SETUP_HISTORY_ORIGIN": origin})
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(len([call for call in self._git_calls() if call and call[0] == "clone"]), 1)
        commands = [call[4:] for call in self._calls()]
        self.assertTrue(any("rollback" in command for command in commands))

    def test_restore_refuses_public_source_and_running_watcher(self) -> None:
        origin = "git@github.com:EzraCerpac/dotfiles-state.git"
        wrong = self._run("restore", extra_env={"SETUP_HISTORY_ORIGIN": "git@github.com:EzraCerpac/dotfiles.git"})
        self.assertEqual(wrong.returncode, 2)
        self.assertIn("private EzraCerpac/dotfiles-state", wrong.stderr)
        self.assertEqual(self._calls(), [])

        active = self._run(
            "restore",
            extra_env={"SETUP_HISTORY_ORIGIN": origin, "WATCHER_ACTIVE": "1"},
        )
        self.assertNotEqual(active.returncode, 0)
        self.assertIn("history watcher is running", active.stderr)
        self.assertFalse(any(call and call[0] == "clone" for call in self._git_calls()))
        self.assertEqual(self._calls(), [])

    def test_backup_requires_manual_sync_and_saves_before_publish(self) -> None:
        blocked = self._run("backup", extra_env={"MISE_HISTORY_MODE": "sync"})
        self.assertNotEqual(blocked.returncode, 0)
        self.assertEqual([call[4:] for call in self._calls()], [["settings", "get", "history.sync"]])
        self.log.unlink()

        result = self._run("backup")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = [call[4:] for call in self._calls()]
        self.assertEqual(commands, [["settings", "get", "history.sync"], ["bootstrap", "dotfiles", "save"], ["bootstrap", "dotfiles", "sync"]])

    def test_history_permissions_accepts_an_empty_path_list_under_nounset(self) -> None:
        helper = self.root / "tasks/bootstrap/history-permissions.sh"
        result = subprocess.run(
            ["bash", str(helper)],
            cwd=self.base,
            env=self.env,
            input="",
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Secured 0 tracked history files", result.stdout)

    def test_secrets_refuse_live_drift_and_install_reconciled_files_privately(self) -> None:
        encrypted = self.root / "encrypted"
        encrypted.mkdir()
        wakatime_secret = b"[settings]\napi_key = SECRET_WAKATIME_FIXTURE\n"
        himalaya_secret = b"[accounts.personal]\nemail = 'fixture@example.test'\n"
        (encrypted / "wakatime.cfg.age").write_bytes(wakatime_secret)
        (encrypted / "himalaya-config.toml.age").write_bytes(himalaya_secret)

        identity = self.base / "age-identity.txt"
        identity.write_text("AGE-SECRET-IDENTITY-FIXTURE\n")
        self._write_executable(
            self.bin / "age",
            """#!/usr/bin/env bash
set -euo pipefail
output=''
input=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d) shift ;;
        -i) shift 2 ;;
        -o) output="$2"; shift 2 ;;
        *) input="$1"; shift ;;
    esac
done
cp "$input" "$output"
""",
        )
        live_wakatime = Path(self.env["HOME"]) / ".wakatime.cfg"
        live_wakatime.write_text("[settings]\napi_key = INDEPENDENT_LIVE_VALUE\n")
        env = {"SETUP_AGE_IDENTITY": str(identity)}

        refused = self._run("secrets", extra_env=env)
        self.assertNotEqual(refused.returncode, 0)
        self.assertEqual(live_wakatime.read_text(), "[settings]\napi_key = INDEPENDENT_LIVE_VALUE\n")
        self.assertFalse((Path(self.env["HOME"]) / ".config/himalaya/config.toml").exists())
        self.assertNotIn("SECRET_WAKATIME_FIXTURE", refused.stdout + refused.stderr)

        installed = self._run("secrets", "--reconcile", "wakatime.cfg", extra_env=env)
        self.assertEqual(installed.returncode, 0, installed.stderr)
        self.assertEqual(live_wakatime.read_bytes(), wakatime_secret)
        live_himalaya = Path(self.env["HOME"]) / ".config/himalaya/config.toml"
        self.assertEqual(live_himalaya.read_bytes(), himalaya_secret)
        self.assertEqual(stat.S_IMODE(live_wakatime.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(live_himalaya.stat().st_mode), 0o600)
        self.assertNotIn("SECRET_WAKATIME_FIXTURE", installed.stdout + installed.stderr)

        live_wakatime.chmod(0o644)
        live_himalaya.chmod(0o644)
        repeated = self._run("secrets", extra_env=env)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertEqual(stat.S_IMODE(live_wakatime.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(live_himalaya.stat().st_mode), 0o600)
        self.assertEqual(live_wakatime.read_bytes(), wakatime_secret)

        live_himalaya.unlink()
        live_himalaya.mkdir()
        refused_directory = self._run("secrets", "--reconcile", "himalaya-config.toml", extra_env=env)
        self.assertNotEqual(refused_directory.returncode, 0)
        self.assertEqual(list(live_himalaya.iterdir()), [])

        live_himalaya.rmdir()
        live_himalaya.parent.rmdir()
        redirected = self.root / "public-config-fixture"
        redirected.mkdir()
        live_himalaya.parent.symlink_to(redirected, target_is_directory=True)
        refused_parent = self._run("secrets", extra_env=env)
        self.assertNotEqual(refused_parent.returncode, 0)
        self.assertEqual(list(redirected.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
