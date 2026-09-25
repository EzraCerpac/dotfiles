from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1]


class HistoryEnrollmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.config = self.home / ".config/mise"
        self.bin = self.base / "bin"
        self.home.mkdir()
        self.config.mkdir(parents=True)
        self.bin.mkdir()
        self.tasks = self.base / "setup-scripts/bootstrap"
        shutil.copytree(SOURCE_ROOT / "setup-scripts/bootstrap", self.tasks)
        shared_tasks = self.base / "setup-scripts/lib"
        shared_tasks.mkdir(parents=True)
        shutil.copy2(SOURCE_ROOT / "setup-scripts/lib/mise-bin.sh", shared_tasks / "mise-bin.sh")
        (self.config / "config.toml").write_text("min_version = '2026.9.7'\n")
        self.log = self.base / "mise.log"
        self.identity = self.home / ".config/age/keys.txt"
        self.identity.parent.mkdir(parents=True)
        self.identity.write_text("AGE-SECRET-IDENTITY-FIXTURE\n")
        self.recipient = "age1localfixturepublicrecipient000000000000000000000000000000"

        self._write_executable(
            self.bin / "mise",
            """#!/usr/bin/env bash
set -euo pipefail
printf 'CALL' >> "$MISE_LOG"
for arg in "$@"; do printf '\\t%s' "$arg" >> "$MISE_LOG"; done
printf '\\n' >> "$MISE_LOG"
if [[ "${MISE_FAIL_PATHS:-}" == 1 && "$*" == *"bootstrap dotfiles paths" ]]; then
    exit 9
fi
if [[ "$*" == *"config get --file"* ]]; then
    last=""
    for arg in "$@"; do last="$arg"; done
    if [[ "$last" == env ]]; then printf '%s\\n' "${MISE_TEST_MISERC_ENV:-[]}"; fi
    exit 0
fi
""",
        )
        self._write_executable(
            self.bin / "age-keygen",
            """#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "-y" && -n "${2:-}" ]]
printf '%s\\n' "${AGE_TEST_RECIPIENT:?}"
""",
        )
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "MISE_CONFIG_DIR": str(self.config),
                "MISE_STATE_DIR": str(self.base / "mise-state"),
                "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                "SETUP_MISE_BIN": str(self.bin / "mise"),
                "MISE_LOG": str(self.log),
                "AGE_TEST_RECIPIENT": self.recipient,
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _write_executable(path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(0o755)

    def _run(self, task: str, *args: str, extra_env: dict[str, str] | None = None):
        env = self.env.copy()
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [str(self.tasks / task), *args],
            cwd=self.base,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def _calls(self) -> list[list[str]]:
        if not self.log.exists():
            return []
        return [line.split("\t")[1:] for line in self.log.read_text().splitlines()]

    def test_enrollment_persists_profile_encrypts_exact_paths_and_never_saves(self) -> None:
        (self.home / ".codex").mkdir()
        codex_config = self.home / ".codex/config.toml"
        codex_config.write_text("provider = 'fixture'\n")
        (self.home / ".config/fish").mkdir()
        fish_variables = self.home / ".config/fish/fish_variables"
        fish_variables.write_text("SET fish_user_paths\n")
        wakatime_config = self.home / ".wakatime.cfg"
        wakatime_config.write_text(
            "[settings]\napi_key = 'FIXTURE_PRIVATE_CONFIGURATION_SENTINEL'\n"
        )
        (self.home / ".pi/agent").mkdir(parents=True)
        pi_settings = self.home / ".pi/agent/settings.json"
        pi_settings.write_text('{"provider":"fixture"}\n')
        for path in (codex_config, fish_variables, wakatime_config, pi_settings):
            path.chmod(0o644)
        self.identity.chmod(0o640)
        (self.config / "miserc.toml").write_text(
            '# keep local early settings\n'
            'env = ["old-profile"]\n'
            'ceiling_paths = ["{{ env.HOME }}"]\n'
        )
        local_config = self.config / "config.local.toml"
        local_config.write_text('[vars]\nkeep = "preserve-me"\n')

        result = self._run(
            "enroll-history",
            "--profile",
            "workstation",
            "--machine-id",
            "mac-primary",
            "--identity",
            "~/.config/age/keys.txt",
            "--origin",
            "git@github.com:example/private.git",
            "--recipient",
            "age1recoveryfixturepublicrecipient000000000000000000000000000000",
            extra_env={"MISE_TEST_MISERC_ENV": '["old-profile"]'},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Prepared 3 encrypted file paths", result.stdout)
        self.assertNotIn("AGE-SECRET-IDENTITY-FIXTURE", result.stdout + result.stderr)
        self.assertNotIn(self.recipient, result.stdout + result.stderr)
        self.assertNotIn("FIXTURE_PRIVATE_CONFIGURATION_SENTINEL", result.stdout + result.stderr)
        for path in (codex_config, fish_variables, wakatime_config):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(pi_settings.stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(self.identity.stat().st_mode), 0o640)

        miserc = (self.config / "miserc.toml").read_text()
        self.assertTrue(
            miserc.startswith('env = ["workstation", "host-mac-primary", "old-profile"]\n')
        )
        self.assertIn('ceiling_paths = ["{{ env.HOME }}"]', miserc)
        self.assertEqual(stat.S_IMODE((self.config / "miserc.toml").stat().st_mode), 0o600)
        self.assertEqual(local_config.read_text(), '[vars]\nkeep = "preserve-me"\n')
        self.assertEqual(stat.S_IMODE(local_config.stat().st_mode), 0o600)

        variant = (self.config / "config.host-mac-primary.toml").read_text()
        for path in (
            "~/.codex/config.toml",
            "~/.config/fish/fish_variables",
            "~/.wakatime.cfg",
        ):
            self.assertIn(f'[dotfiles."{path}"]', variant)
        self.assertNotIn('~/.pi/agent/settings.json', variant)
        self.assertEqual(variant.count('encrypt = true'), 3)
        self.assertIn('variants = [{ profile = "host-mac-primary" }]', variant)
        self.assertNotIn("age1", variant)
        self.assertNotIn(str(self.identity), variant)
        self.assertEqual(stat.S_IMODE((self.config / "config.host-mac-primary.toml").stat().st_mode), 0o644)

        rendered = [" ".join(call) for call in self._calls()]
        self.assertTrue(any("env.SETUP_PROFILE" in call for call in rendered))
        self.assertTrue(any("env.SETUP_MACHINE_ID" in call for call in rendered))
        self.assertTrue(any("settings.age.identity_files" in call for call in rendered))
        self.assertTrue(any("history.encryption.recipients" in call for call in rendered))
        self.assertTrue(any(call.endswith("bootstrap dotfiles paths") for call in rendered))
        forbidden = (" dotfiles save", " dotfiles track", " dotfiles sync", " dotfiles pull", " origin set")
        self.assertFalse(any(any(marker in f" {call}" for marker in forbidden) for call in rendered))
        self.assertFalse((self.base / "mise-state/history/repo.git").exists())

    def test_failed_native_path_validation_keeps_file_permissions_unchanged(self) -> None:
        target = self.home / ".codex/config.toml"
        target.parent.mkdir()
        target.write_text("private=fixture\n")
        target.chmod(0o644)
        result = self._run(
            "enroll-history",
            "--profile",
            "workstation",
            "--machine-id",
            "mac-primary",
            "--identity",
            "~/.config/age/keys.txt",
            extra_env={"MISE_FAIL_PATHS": "1"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o644)

    def test_enrollment_refuses_symlink_without_chmodding_external_target(self) -> None:
        external_key = self.base / "outside-age-identity.txt"
        external_key.write_text("AGE-SECRET-EXTERNAL-FIXTURE\n")
        external_key.chmod(0o640)
        link = self.home / ".config/external-key.toml"
        link.symlink_to(external_key)
        result = self._run(
            "enroll-history",
            "--profile",
            "nas",
            "--machine-id",
            "nas",
            "--identity",
            "~/.config/age/keys.txt",
            "--file",
            "~/.config/external-key.toml",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("refusing symlink history path", result.stderr)
        self.assertNotIn("AGE-SECRET-EXTERNAL-FIXTURE", result.stdout + result.stderr)
        self.assertEqual(stat.S_IMODE(external_key.stat().st_mode), 0o640)
        self.assertEqual(self._calls(), [])

    def test_refresh_appends_restored_files_without_dropping_existing_entries(self) -> None:
        codex_config = self.home / ".codex/config.toml"
        codex_config.parent.mkdir()
        codex_config.write_text("codex=fixture\n")
        initial = self._run(
            "enroll-history",
            "--profile",
            "workstation",
            "--machine-id",
            "mac-primary",
            "--identity",
            "~/.config/age/keys.txt",
        )
        self.assertEqual(initial.returncode, 0, initial.stderr)

        fish_variables = self.home / ".config/fish/fish_variables"
        fish_variables.parent.mkdir(parents=True)
        fish_variables.write_text("fish=restored\n")
        fish_variables.chmod(0o644)
        variant_path = self.config / "config.host-mac-primary.toml"
        with variant_path.open("a") as variant:
            variant.write(
                '\n[dotfiles."~/.custom-private.toml"]\n'
                'mode = "track"\nencrypt = true\n'
                'variants = [{ profile = "host-mac-primary" }]\n'
                '\n[vars]\ncustom = "preserve-me"\n'
            )
        previous_variant = variant_path.read_text()

        without_refresh = self._run(
            "enroll-history",
            "--profile",
            "workstation",
            "--machine-id",
            "mac-primary",
            "--identity",
            "~/.config/age/keys.txt",
        )
        self.assertEqual(without_refresh.returncode, 2)
        self.assertIn("--refresh", without_refresh.stderr)
        self.assertEqual(variant_path.read_text(), previous_variant)
        self.assertEqual(stat.S_IMODE(fish_variables.stat().st_mode), 0o644)

        refreshed = self._run(
            "enroll-history",
            "--profile",
            "workstation",
            "--machine-id",
            "mac-primary",
            "--identity",
            "~/.config/age/keys.txt",
            "--refresh",
        )
        self.assertEqual(refreshed.returncode, 0, refreshed.stdout + refreshed.stderr)
        variant = variant_path.read_text()
        self.assertIn('[dotfiles."~/.custom-private.toml"]', variant)
        self.assertIn('custom = "preserve-me"', variant)
        self.assertIn('[dotfiles."~/.config/fish/fish_variables"]', variant)
        self.assertEqual(variant.count('[dotfiles."~/.codex/config.toml"]'), 1)
        self.assertEqual(variant.count('encrypt = true'), 3)
        self.assertEqual(stat.S_IMODE(fish_variables.stat().st_mode), 0o600)

    def test_refresh_refuses_existing_plaintext_tracking_declaration(self) -> None:
        target = self.home / ".codex/config.toml"
        target.parent.mkdir()
        target.write_text("private=fixture\n")
        target.chmod(0o644)
        variant_path = self.config / "config.host-mac-primary.toml"
        variant_path.write_text(
            '[dotfiles."~/.custom.toml"]\nmode = "track"\nencrypt = false\n'
        )
        original_variant = variant_path.read_text()
        result = self._run(
            "enroll-history",
            "--profile",
            "workstation",
            "--machine-id",
            "mac-primary",
            "--identity",
            "~/.config/age/keys.txt",
            "--refresh",
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("existing history declarations must all be encrypted", result.stderr)
        self.assertEqual(variant_path.read_text(), original_variant)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o644)

    def test_permissions_helper_uses_exact_pathlist_and_rejects_external_symlinks(self) -> None:
        secure_file = self.home / ".config/private.toml"
        secure_file.write_text("private=fixture\n")
        secure_file.chmod(0o644)
        result = subprocess.run(
            ["bash", str(self.tasks / "history-permissions.sh")],
            input=f"{secure_file}\n",
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stat.S_IMODE(secure_file.stat().st_mode), 0o600)

        external_file = self.base / "external-secret.txt"
        external_file.write_text("do-not-touch\n")
        external_file.chmod(0o640)
        external_link = self.home / ".config/external-secret.txt"
        external_link.symlink_to(external_file)
        pending_file = self.home / ".config/pending-private.toml"
        pending_file.write_text("pending=fixture\n")
        pending_file.chmod(0o644)
        rejected = subprocess.run(
            ["bash", str(self.tasks / "history-permissions.sh")],
            input=f"{pending_file}\n{external_link}\n",
            cwd=self.base,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(rejected.returncode, 2)
        self.assertEqual(stat.S_IMODE(pending_file.stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(external_file.stat().st_mode), 0o640)

    def test_profile_task_sets_native_early_selector_without_an_identity(self) -> None:
        result = self._run("profile", "--profile", "nas", "--machine-id", "cerpacnas")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.config / "miserc.toml").read_text(), 'env = ["nas", "host-cerpacnas"]\n')
        rendered = [" ".join(call) for call in self._calls()]
        self.assertTrue(any("env.SETUP_PROFILE nas" in call for call in rendered))
        self.assertTrue(any("env.SETUP_MACHINE_ID cerpacnas" in call for call in rendered))
        self.assertTrue(any("settings.history.sync manual" in call for call in rendered))
        self.assertFalse(any("settings.age.identity_files" in call for call in rendered))
        self.assertFalse((self.base / "mise-state/history/repo.git").exists())

    def test_real_mise_selects_persisted_role_and_host_without_env_flag(self) -> None:
        mise = os.environ.get("MISE_TEST_BINARY") or shutil.which("mise")
        if not mise:
            self.skipTest("real mise binary is unavailable")
        version = subprocess.run(
            [mise, "--version"], text=True, capture_output=True, check=False
        )
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", version.stdout)
        if version.returncode or not match or tuple(map(int, match.groups())) < (2026, 9, 7):
            self.skipTest("real mise 2026.9.7 or newer is required")

        (self.config / "config.workstation.toml").write_text(
            '[env]\nNATIVE_ROLE_MARKER = "workstation-loaded"\n'
        )
        (self.config / "config.host-mac-primary.toml").write_text(
            '[env]\nNATIVE_HOST_MARKER = "host-loaded"\n'
        )
        (self.config / "config.local.toml").write_text('[vars]\nkeep = "preserve-me"\n')
        (self.config / "miserc.toml").write_text(
            "# unrelated early config survives\n"
            "env = [\n"
            "  'workstation',\n"
            "  'host-old-machine',\n"
            "  'custom-tools',\n"
            "]\n"
            'ceiling_paths = ["{{ env.HOME }}"]\n'
        )
        result = self._run(
            "profile",
            "--profile",
            "workstation",
            "--machine-id",
            "mac-primary",
            extra_env={"SETUP_MISE_BIN": mise},
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        native_env = self.env.copy()
        native_env["SETUP_MISE_BIN"] = mise
        native_env.pop("MISE_ENV", None)
        config_ls = subprocess.run(
            [mise, "--quiet", "--cd", str(self.config), "config", "ls"],
            env=native_env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(config_ls.returncode, 0, config_ls.stderr)
        self.assertIn("config.workstation.toml", config_ls.stdout)
        self.assertIn("config.host-mac-primary.toml", config_ls.stdout)

        resolved = subprocess.run(
            [mise, "--quiet", "--cd", str(self.config), "env", "--json"],
            env=native_env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(resolved.returncode, 0, resolved.stderr)
        env_values = json.loads(resolved.stdout)
        self.assertEqual(env_values["NATIVE_ROLE_MARKER"], "workstation-loaded")
        self.assertEqual(env_values["NATIVE_HOST_MARKER"], "host-loaded")
        self.assertEqual(env_values["SETUP_PROFILE"], "workstation")
        self.assertEqual(env_values["SETUP_MACHINE_ID"], "mac-primary")
        self.assertEqual(
            (self.config / "miserc.toml").read_text(),
            'env = ["workstation", "host-mac-primary", "custom-tools"]\n'
            '# unrelated early config survives\n'
            'ceiling_paths = ["{{ env.HOME }}"]\n',
        )
        self.assertIn('keep = "preserve-me"', (self.config / "config.local.toml").read_text())

    def test_persist_selected_generates_and_keeps_a_stable_id(self) -> None:
        self._write_executable(self.bin / "uuidgen", "#!/usr/bin/env bash\nprintf 'AABB-CCDD\\n'\n")
        first = self._run("persist-selected", extra_env={"SETUP_PROFILE": "nas", "SETUP_MACHINE_ID": ""})
        self.assertEqual(first.returncode, 0, first.stderr)
        expected = 'env = ["nas", "host-auto-aabbccdd"]\n'
        self.assertEqual((self.config / "miserc.toml").read_text(), expected)

        self.log.unlink()
        second = self._run(
            "persist-selected",
            extra_env={
                "SETUP_PROFILE": "workstation",
                "MISE_TEST_MISERC_ENV": '["nas", "host-auto-aabbccdd"]',
            },
        )
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.config / "miserc.toml").read_text(), expected)
        self.assertIn("Kept existing mise role nas", second.stdout)

    def test_persist_selected_does_not_override_existing_native_role_or_id(self) -> None:
        original_miserc = (
            "# keep unrelated early selectors\n"
            "env = [\n"
            "  'workstation',\n"
            "  'host-mac-primary',\n"
            "  'custom-tools',\n"
            "]\n"
        )
        (self.config / "miserc.toml").write_text(original_miserc)
        result = self._run(
            "persist-selected",
            extra_env={
                "SETUP_PROFILE": "nas",
                "SETUP_MACHINE_ID": "cerpacnas",
                "MISE_TEST_MISERC_ENV": '["workstation", "host-mac-primary", "custom-tools"]',
            },
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.config / "miserc.toml").read_text(), original_miserc)
        rendered = [" ".join(call) for call in self._calls()]
        self.assertTrue(any("env.SETUP_PROFILE workstation" in call for call in rendered))
        self.assertTrue(any("env.SETUP_MACHINE_ID mac-primary" in call for call in rendered))
        self.assertFalse((self.base / "mise-state/history/repo.git").exists())

    def test_enrollment_requires_identity_and_existing_exact_custom_files(self) -> None:
        missing_identity = self._run("enroll-history", "--profile", "workstation", "--machine-id", "mac-primary")
        self.assertEqual(missing_identity.returncode, 2)
        self.assertIn("--identity is required", missing_identity.stderr)
        self.assertEqual(self._calls(), [])

        missing_file = self._run(
            "enroll-history",
            "--profile",
            "nas",
            "--machine-id",
            "nas",
            "--identity",
            str(self.identity),
            "--file",
            "~/.config/not-present.toml",
        )
        self.assertEqual(missing_file.returncode, 2)
        self.assertIn("requested file does not exist", missing_file.stderr)
        self.assertFalse((self.config / "miserc.toml").exists())


if __name__ == "__main__":
    unittest.main()
