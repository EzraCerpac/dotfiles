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
    def invoke(self, function, arguments, responses):
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
            result = function(*arguments)
        self.assertEqual(len(calls), len(responses))
        return result, calls

    def plan(self, manager, name, responses):
        return self.invoke(PACKAGES.plan_remove, (manager, name), responses)

    def shared(self, manager, name, other_names, responses):
        return self.invoke(PACKAGES.shares_installation, (manager, name, other_names), responses)

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

    def test_brew_shared_identity_uses_one_native_list(self):
        for manager in ["brew", "brew-cask"]:
            for name, other in [("foo", "owner/tap/foo"), ("owner/tap/foo", "foo")]:
                with self.subTest(manager=manager, name=name):
                    shared, calls = self.shared(manager, name, [other], ["owner/tap/foo\n"])
                    self.assertTrue(shared)
                    self.assertEqual(calls, [["brew", "list", "--formula" if manager == "brew" else "--cask", "--full-name", "-1"]])

    def test_brew_builtin_identity_handles_both_native_spellings(self):
        for manager, builtin in [("brew", "core"), ("brew-cask", "cask")]:
            full = f"homebrew/{builtin}/foo"
            for name, other in [("foo", full), (full, "foo")]:
                for installed in ["foo\n", full + "\n"]:
                    with self.subTest(manager=manager, name=name, installed=installed):
                        shared, _ = self.shared(manager, name, [other], [installed])
                        self.assertTrue(shared)

    def test_brew_shared_identity_refuses_ambiguous_bare_token(self):
        for name, other in [("foo", "one/tap/foo"), ("one/tap/foo", "foo")]:
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "ambiguous"):
                self.shared("brew", name, [other], ["one/tap/foo\ntwo/tap/foo\n"])

    def test_obvious_distinct_native_identities_do_not_probe(self):
        for manager, name, others in [
            ("brew", "one/tap/foo", ["two/tap/foo"]),
            ("brew", "foo", ["bar", "owner/tap/bar"]),
            ("apt", "foo:amd64", ["foo:i386"]),
            ("apt", "foo", ["bar:amd64"]),
            ("dnf", "foo", ["bar"]),
        ]:
            with self.subTest(manager=manager, name=name):
                shared, _ = self.shared(manager, name, others, [])
                self.assertFalse(shared)

    def test_exact_shared_declaration_does_not_probe(self):
        for manager, name in [("brew", "owner/tap/foo"), ("apt", "foo:amd64"), ("mas", "123")]:
            with self.subTest(manager=manager):
                shared, _ = self.shared(manager, name, [name], [])
                self.assertTrue(shared)

    def test_shared_identity_does_not_guess_missing_or_other_tap(self):
        for manager, name, other, responses in [
            ("brew", "foo", "one/tap/foo", [""]),
            ("brew", "foo", "one/tap/foo", ["two/tap/foo\n"]),
            ("apt", "foo", "foo:amd64", [""]),
        ]:
            with self.subTest(manager=manager, responses=responses):
                shared, _ = self.shared(manager, name, [other], responses)
                self.assertFalse(shared)

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
        self.assertEqual(calls[0], ["dpkg-query", "-W", "-f=${Package}:${Architecture} ${db:Status-Status}\\n"])

    def test_apt_shared_identity_resolves_bare_request_both_directions(self):
        for name, other in [("foo", "foo:amd64"), ("foo:amd64", "foo")]:
            with self.subTest(name=name):
                shared, calls = self.shared("apt", name, [other], ["foo:amd64 installed\nfoo:i386 installed\n", "Remv foo:amd64 [1]\n"])
                self.assertTrue(shared)
                self.assertEqual(calls[-1], ["apt-get", "--simulate", "--no-auto-remove", "remove", "foo"])

    def test_apt_wildcard_selectors_target_resolved_installed_architecture(self):
        for selector in ["native", "any"]:
            for architecture in ["amd64", "all"]:
                with self.subTest(selector=selector, architecture=architecture):
                    plan, calls = self.plan("apt", f"foo:{selector}", [f"foo:{architecture} installed\n", "Remv foo [1]\n"])
                    self.assertEqual(calls[-1], ["apt-get", "--simulate", "--no-auto-remove", "remove", f"foo:{selector}"])
                    self.assertEqual(plan["commands"], [["sudo", "apt-get", "--yes", "--no-auto-remove", "remove", f"foo:{architecture}"]])

    def test_apt_wildcard_selectors_missing_package_or_architecture_are_noops(self):
        for selector in ["native", "any"]:
            for responses in [[""], ["foo:i386 installed\n", "Package foo is not installed, so not removed\n"]]:
                with self.subTest(selector=selector, responses=responses):
                    plan, _ = self.plan("apt", f"foo:{selector}", responses)
                    self.assertFalse(plan["installed"])

    def test_apt_wildcard_selectors_share_actual_architecture_both_directions(self):
        for selector in ["native", "any"]:
            for architecture in ["amd64", "all"]:
                selected, qualified = f"foo:{selector}", f"foo:{architecture}"
                for name, other in [(selected, qualified), (qualified, selected)]:
                    with self.subTest(selector=selector, architecture=architecture, name=name):
                        shared, _ = self.shared("apt", name, [other], [f"{qualified} installed\n", "Remv foo [1]\n"])
                        self.assertTrue(shared)

    def test_apt_wildcard_selectors_do_not_share_different_foreign_architecture(self):
        for selector in ["native", "any"]:
            for name, other in [(f"foo:{selector}", "foo:i386"), ("foo:i386", f"foo:{selector}")]:
                with self.subTest(selector=selector, name=name):
                    shared, _ = self.shared("apt", name, [other], ["foo:amd64 installed\nfoo:i386 installed\n", "Remv foo:amd64 [1]\n"])
                    self.assertFalse(shared)

    def test_apt_wildcard_plan_refuses_dependents_or_multiple_architectures(self):
        for selector in ["native", "any"]:
            for preview in ["Remv foo:amd64 [1]\nRemv bar:amd64 [1]\n", "Remv foo:amd64 [1]\nRemv foo:i386 [1]\n", "Remv foo:amd64 [1]\nInst bar (1)\n"]:
                with self.subTest(selector=selector, preview=preview), self.assertRaises(ValueError):
                    self.plan("apt", f"foo:{selector}", ["foo:amd64 installed\nfoo:i386 installed\nbar:amd64 installed\n", preview])
            shared, _ = self.shared("apt", f"foo:{selector}", ["foo:amd64"], ["foo:amd64 installed\nbar:amd64 installed\n", "Remv foo:amd64 [1]\nRemv bar:amd64 [1]\n"])
            self.assertTrue(shared)

    def test_apt_shared_identity_does_not_conflate_foreign_architecture(self):
        for name, other in [("foo", "foo:i386"), ("foo:i386", "foo")]:
            with self.subTest(name=name):
                shared, _ = self.shared("apt", name, [other], ["foo:amd64 installed\nfoo:i386 installed\n", "Remv foo:amd64 [1]\n"])
                self.assertFalse(shared)

    def test_apt_plain_native_removal_row_resolves_using_dpkg_architecture(self):
        shared, calls = self.shared("apt", "foo", ["foo:amd64"], ["foo:amd64 installed\nfoo:i386 installed\n", "Remv foo [1]\n", "amd64\n"])
        self.assertTrue(shared)
        self.assertEqual(calls[-1], ["dpkg", "--print-architecture"])
        plan, _ = self.plan("apt", "foo:amd64", ["foo:amd64 installed\nfoo:i386 installed\n", "Remv foo [1]\n", "amd64\n"])
        self.assertTrue(plan["installed"])

    def test_apt_plain_removal_row_preserves_unique_installed_architecture(self):
        for architecture in ["all", "amd64", "i386"]:
            qualified = f"foo:{architecture}"
            for name, other in [("foo", qualified), (qualified, "foo")]:
                with self.subTest(architecture=architecture, name=name):
                    shared, _ = self.shared("apt", name, [other], [f"{qualified} installed\n", "Remv foo [1]\n"])
                    self.assertTrue(shared)
            plan, _ = self.plan("apt", qualified, [f"{qualified} installed\n", "Remv foo [1]\n"])
            self.assertTrue(plan["installed"])

    def test_apt_plain_removal_row_does_not_guess_architecture(self):
        with self.assertRaisesRegex(ValueError, "architecture"):
            self.shared("apt", "foo", ["foo:amd64"], ["foo:amd64 installed\nfoo:i386 installed\n", "Remv foo [1]\n", "unknown architecture\n"])
        with self.assertRaisesRegex(ValueError, "expected only that package"):
            self.plan("apt", "foo:amd64", ["foo:amd64 installed\nfoo:i386 installed\n", "Remv foo [1]\n", "i386\n"])

    def test_apt_shared_identity_allows_dependent_preview_rows(self):
        responses = ["foo:amd64 installed\nbar:amd64 installed\n", "Remv bar [1]\nRemv foo:amd64 [1]\n"]
        shared, _ = self.shared("apt", "foo", ["foo:amd64"], responses)
        self.assertTrue(shared)
        with self.assertRaisesRegex(ValueError, "expected only that package"):
            self.plan("apt", "foo", responses)

    def test_apt_shared_identity_refuses_ambiguous_or_inconsistent_target(self):
        for preview in ["Remv foo:amd64 [1]\nRemv foo:i386 [1]\n", "Remv foo:amd64 [1]\nRemv foo:amd64 [1]\n", "Remv bar [1]\n", "Remv foo:arm64 [1]\n"]:
            with self.subTest(preview=preview), self.assertRaises(ValueError):
                self.shared("apt", "foo", ["foo:amd64"], ["foo:amd64 installed\nfoo:i386 installed\n", preview])

    def test_shared_identity_propagates_native_query_failure(self):
        for manager, other in [("apt", "foo:amd64"), ("brew", "owner/tap/foo")]:
            with self.subTest(manager=manager), self.assertRaisesRegex(ValueError, "broken database"):
                self.shared(manager, "foo", [other], [(2, "", "broken database")])

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
