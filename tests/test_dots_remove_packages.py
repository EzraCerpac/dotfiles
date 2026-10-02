import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("remove_packages", Path(__file__).resolve().parents[1] / "setup-scripts/lib/dots-remove-packages.py")
PACKAGES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGES)


class PackageRemovalTests(unittest.TestCase):
    def plan(self, manager, name, responses):
        calls = []

        def run(command, **kwargs):
            calls.append(command)
            self.assertEqual(kwargs["env"]["LC_ALL"], "C")
            self.assertEqual(kwargs["env"]["HOMEBREW_NO_AUTOREMOVE"], "1")
            reply = responses[len(calls) - 1]
            if isinstance(reply, str):
                reply = (0, reply, "")
            return subprocess.CompletedProcess(command, *reply)

        with patch.object(PACKAGES.subprocess, "run", side_effect=run), patch.object(PACKAGES.os, "geteuid", return_value=501):
            plan = PACKAGES.plan_remove(manager, name)
        self.assertEqual(len(calls), len(responses))
        return plan, calls

    def test_missing_packages_are_noops(self):
        for manager in PACKAGES.MANAGERS:
            with self.subTest(manager=manager):
                name = "123" if manager == "mas" else "example"
                responses = [""]
                if manager == "brew-cask":
                    responses.append(json.dumps({"casks": [{"artifacts": [{"app": ["DotsAbsentExample.app"]}]}]}))
                result, _ = self.plan(manager, name, responses)
                self.assertFalse(result["installed"])
                self.assertEqual(result["commands"], [])

    def test_brew_target_and_no_autoremove(self):
        plan, calls = self.plan("brew", "foo", ["owner/tap/foo\nbar\n", ""])
        self.assertEqual(plan["commands"], [["brew", "uninstall", "--formula", "owner/tap/foo"]])
        self.assertEqual(calls[-1], ["brew", "uses", "--installed", "--recursive", "owner/tap/foo"])

    def test_brew_cask_and_builtin_tap(self):
        plan, _ = self.plan("brew-cask", "homebrew/cask/firefox", ["firefox\n"])
        self.assertEqual(plan["commands"], [["brew", "uninstall", "--cask", "firefox"]])

    def test_unregistered_cask_with_adopted_app_refuses_removal(self):
        metadata = json.dumps({"casks": [{"artifacts": [{"app": ["Adopted.app"], "target": "/Applications/Adopted.app"}]}]})
        with patch.object(PACKAGES.Path, "exists", return_value=True):
            with self.assertRaisesRegex(ValueError, "app remains"):
                self.plan("brew-cask", "adopted", ["", metadata])
        with self.assertRaisesRegex(ValueError, "non-app artifacts"):
            self.plan("brew-cask", "pkg", ["", json.dumps({"casks": [{"artifacts": [{"pkg": ["Example.pkg"]}]}]})])

    def test_unregistered_cask_with_mixed_artifacts_refuses_even_when_app_is_absent(self):
        for artifacts in [
            [{"app": ["Example.app"]}, {"pkg": ["Example.pkg"]}],
            [{"app": ["Example.app"]}, {"binary": ["example"]}],
            [{"app": ["Example.app"], "pkg": ["Example.pkg"]}],
        ]:
            metadata = json.dumps({"casks": [{"artifacts": artifacts}]})
            with self.subTest(artifacts=artifacts), patch.object(PACKAGES.Path, "exists", return_value=False):
                with self.assertRaisesRegex(ValueError, "non-app artifacts"):
                    self.plan("brew-cask", "example", ["", metadata])

    def test_brew_dependencies_and_ambiguity_refused(self):
        with self.assertRaisesRegex(ValueError, "installed dependents"):
            self.plan("brew", "foo", ["foo\n", "bar\n"])
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.plan("brew", "foo", ["one/tap/foo\ntwo/tap/foo\n"])
        plan, _ = self.plan("brew", "third/tap/foo", ["one/tap/foo\n"])
        self.assertFalse(plan["installed"])

    def test_apt_exact_removal_and_architecture(self):
        plan, calls = self.plan("apt", "foo", ["foo:amd64 installed\nbar config-files\n", "Remv foo:amd64 [1.0]\n"])
        self.assertEqual(plan["commands"], [["sudo", "apt-get", "--yes", "--no-auto-remove", "remove", "foo"]])
        self.assertIn("--simulate", calls[-1])
        plan, _ = self.plan("apt", "foo:amd64", ["foo:amd64 installed\n", "Remv foo:amd64 [1.0]\n"])
        self.assertEqual(plan["commands"][0][-1], "foo:amd64")

    def test_apt_refuses_duplicate_and_mismatched_architecture_rows(self):
        for name, preview in [
            ("foo", "Remv foo:amd64 [1.0]\nRemv foo:i386 [1.0]\n"),
            ("foo", "Remv foo:amd64 [1.0]\nRemv foo:amd64 [1.0]\n"),
            ("foo:amd64", "Remv foo:i386 [1.0]\n"),
        ]:
            with self.subTest(name=name, preview=preview), self.assertRaises(ValueError):
                self.plan("apt", name, ["foo:amd64 installed\nfoo:i386 installed\n", preview])

    def test_apt_refuses_other_removals_or_installs(self):
        for preview in ["Remv foo [1]\nRemv bar [2]\n", "Remv foo [1]\nInst bar (2)\n", "unknown format\n"]:
            with self.subTest(preview=preview), self.assertRaises(ValueError):
                self.plan("apt", "foo", ["foo installed\n", preview])

    def test_dnf_exact_removal_with_cleanup_disabled(self):
        preview = "Removing:\n foo x86_64 1.0 @repo 2 k\nTransaction Summary\nRemove 1 Package\nOperation aborted.\n"
        plan, calls = self.plan("dnf", "foo", ["foo\n", "", (1, preview, "")])
        self.assertEqual(calls[1], ["sudo", "rpm", "-e", "--test", "foo"])
        self.assertEqual(plan["commands"], [["sudo", "dnf", "--setopt=clean_requirements_on_remove=False", "--assumeyes", "remove", "foo"]])

    def test_dnf_bad_previews_refused(self):
        for preview in ["cannot load database", " foo x86_64 1.0 @repo 2 k\n bar noarch 1.0 @repo 2 k\nRemove 2 Packages\n", " foo x86_64 1.0 @repo 2 k\nRemove 1 Package\nInstalling:\n"]:
            with self.subTest(preview=preview), self.assertRaises(ValueError):
                self.plan("dnf", "foo", ["foo\n", "", (1, preview, "")])

    def test_dnf_native_dependency_failure(self):
        with self.assertRaisesRegex(ValueError, "needed by"):
            self.plan("dnf", "foo", ["foo\n", (1, "", "foo is needed by bar")])

    def test_pacman_preserves_config_and_requires_exact_preview(self):
        plan, _ = self.plan("pacman", "foo", ["foo\n", "foo\n"])
        self.assertEqual(plan["commands"], [["sudo", "pacman", "-R", "--noconfirm", "foo"]])
        with self.assertRaises(ValueError):
            self.plan("pacman", "foo", ["foo\n", "foo\nbar\n"])

    def test_apk_rejects_automatic_dependency_cleanup(self):
        plan, _ = self.plan("apk", "foo", ["foo\n", "(1/1) Purging foo (1.0)\nOK: 5 MiB\n"])
        self.assertEqual(plan["commands"], [["sudo", "apk", "del", "foo"]])
        for preview in ["(1/2) Purging foo (1)\n(2/2) Purging bar (1)\n", "OK: 5 MiB\n", "(1/1) Upgrading foo (1 -> 2)\n"]:
            with self.subTest(preview=preview), self.assertRaises(ValueError):
                self.plan("apk", "foo", ["foo\n", preview])

    def test_mas_targets_numeric_id(self):
        plan, _ = self.plan("mas", "123", ["123 Example App (1.0)\n456 Other App (2.0)\n"])
        self.assertEqual(plan["commands"], [["mas", "uninstall", "123"]])

    def test_invalid_names_and_exceptions_never_probe(self):
        for manager, name in [("apt", "-foo"), ("dnf", "foo*"), ("mas", "App"), ("apk", "foo bar"), ("brew", "kanata@1"), ("brew-cask", "karabiner-elements"), ("unknown", "foo")]:
            with self.subTest(manager=manager, name=name), patch.object(PACKAGES.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    PACKAGES.plan_remove(manager, name)
                run.assert_not_called()

    def test_probe_errors_do_not_mean_absent(self):
        with self.assertRaisesRegex(ValueError, "database"):
            self.plan("apt", "foo", [(2, "", "broken database")])

    def test_execute_rechecks_and_propagates_uninstall_failure(self):
        plan = {"manager": "brew", "name": "foo"}
        command = ["brew", "uninstall", "--formula", "foo"]
        with patch.object(PACKAGES, "plan_remove", return_value={"commands": [command]}) as preflight:
            with patch.object(PACKAGES.subprocess, "run", side_effect=subprocess.CalledProcessError(1, command)) as run:
                with self.assertRaises(subprocess.CalledProcessError):
                    PACKAGES.execute_remove(plan)
                preflight.assert_called_once_with("brew", "foo")
                self.assertTrue(run.call_args.kwargs["check"])


if __name__ == "__main__":
    unittest.main()
