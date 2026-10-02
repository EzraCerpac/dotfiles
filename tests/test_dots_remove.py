"""Focused removal resolution, rollback and owned-app behavior checks."""
import hashlib
import contextlib
import io
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

try:
    import tomlkit
except ImportError:
    raise unittest.SkipTest("dots remove tests need tomlkit in the test interpreter") from None

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("dots_remove", ROOT / "setup-scripts/lib/dots-remove.py")
remove = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remove)


class RemoveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.base = self.root / "config.toml"
        self.local = self.root / "config.local.toml"
        self.base.write_text('[tools]\nnode = "20" # pinned\n[bootstrap.packages]\n"brew:jq" = "*"\n')
        self.local.write_text('[tools]\n"github:jaskirat1616/mactap-app" = "latest"\n')
        self.packages = Mock()
        self.packages.plan_remove.return_value = {"summary": "uninstall jq", "commands": [], "installed": True}
        self.packages.shares_installation.return_value = False

    def test_discovery_and_url_short_resolution(self):
        entries = remove.discover([self.base, self.local])
        records = {"github:jaskirat1616/mactap-app": [(self.root / "marker", {"path": "/Applications/MacTap.app"})]}
        self.assertEqual(remove.resolve(["MACTAP", "https://github.com/Jaskirat1616/MacTap-App.git/"], entries, records), ["github:jaskirat1616/mactap-app"])
        self.assertEqual(remove.resolve(["jq", "node"], entries, {}), ["brew:jq", "node"])

    def test_ambiguity_and_case_sensitive_backend_ids(self):
        self.base.write_text('[tools]\n"npm:Example" = "1"\n"npm:example" = "2"\n"cargo:jq" = "1"\njq = "2"\n[bootstrap.packages]\n"brew:jq" = "*"\n')
        entries = remove.discover([self.base])
        with self.assertRaisesRegex(ValueError, "ambiguous.*mise:jq"):
            remove.resolve(["jq"], entries, {})
        self.assertEqual(remove.resolve(["mise:jq"], entries, {}), ["jq"])
        with self.assertRaisesRegex(ValueError, "no declaration"):
            remove.resolve(["mise:missing"], entries, {})
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            remove.resolve(["EXAMPLE"], entries, {})
        self.assertEqual(remove.resolve(["npm:Example"], entries, {}), ["npm:Example"])

    def test_all_targets_resolved_before_any_mutation(self):
        with patch.object(remove, "active_configs", return_value=[self.base]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "execute") as execute:
            with self.assertRaisesRegex(ValueError, "no declaration"):
                remove.main(["mise", str(self.root), "node", "missing"])
            execute.assert_not_called()

    def test_builtin_homebrew_aliases_resolve_and_preserve_original_keys(self):
        for manager, tap in (("brew", "homebrew/core"), ("brew-cask", "homebrew/cask")):
            short, qualified = f"{manager}:foo", f"{manager}:{tap}/foo"
            for key in (short, qualified):
                with self.subTest(key=key):
                    self.base.write_text(f'[tools]\n"{key}" = "latest"\n')
                    declarations = remove.discover([self.base])
                    self.assertEqual(remove.resolve([short, qualified], declarations, {}), [short])
                    self.assertEqual(declarations[short][0]["key"], key)
                    plan = remove.prepare(short, declarations[short], {}, True, self.packages)
                    def run(command, **kwargs):
                        self.assertEqual(command[-1], key)
                        remove.remove_entry(declarations[short][0])
                    with patch.object(remove.subprocess, "run", side_effect=run):
                        remove.execute(plan, "mise", self.root, True, self.packages)
                    self.assertNotIn(short, remove.discover([self.base]))
        for key in ("brew:other/tap/foo", "brew-cask:other/tap/foo", "brew:homebrew/cask/foo", "brew-cask:homebrew/core/foo"):
            with self.subTest(key=key):
                self.assertEqual(remove.canonical(key), key)

    def test_selected_builtin_homebrew_alias_retains_shared_package(self):
        for manager, tap in (("brew", "homebrew/core"), ("brew-cask", "homebrew/cask")):
            short, qualified = f"{manager}:foo", f"{manager}:{tap}/foo"
            for selected, other in ((short, qualified), (qualified, short)):
                for selector in (["--base"], ["--path", str(self.base)]):
                    with self.subTest(selected=selected, selector=selector):
                        self.base.write_text(f'[bootstrap.packages]\n"{selected}" = "*"\n')
                        self.local.write_text(f'[bootstrap.packages]\n"{other}" = "*"\n')
                        self.packages.reset_mock()
                        other_contents = self.local.read_bytes()
                        with patch.object(remove, "active_configs", return_value=[self.base.resolve(), self.local.resolve()]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), contextlib.redirect_stdout(io.StringIO()):
                            self.assertEqual(remove.main(["mise", str(self.root), *selector, selected]), 0)
                        self.packages.plan_remove.assert_not_called()
                        self.packages.execute_remove.assert_not_called()
                        self.assertNotIn(short, remove.discover([self.base]))
                        self.assertEqual(self.local.read_bytes(), other_contents)
                        self.assertIn(short, remove.discover([self.local]))

    def test_selected_native_equivalent_retains_shared_package(self):
        for manager, qualified in (("brew", "owner/tap/foo"), ("brew-cask", "owner/tap/foo"), ("apt", "foo:amd64")):
            for selected, other in (("foo", qualified), (qualified, "foo")):
                for selector in (["--base"], ["--path", str(self.base)]):
                    with self.subTest(manager=manager, selected=selected, selector=selector):
                        key = f"{manager}:{selected}"
                        self.base.write_text(f'[bootstrap.packages]\n"{key}" = "*"\n')
                        self.local.write_text(f'[bootstrap.packages]\n"{manager}:{other}" = "*"\n')
                        other_contents = self.local.read_bytes()
                        self.packages.reset_mock()
                        self.packages.shares_installation.return_value = True
                        with patch.object(remove, "active_configs", return_value=[self.base.resolve(), self.local.resolve()]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), contextlib.redirect_stdout(io.StringIO()):
                            self.assertEqual(remove.main(["mise", str(self.root), *selector, key]), 0)
                        self.packages.shares_installation.assert_called_once_with(manager, selected, [other])
                        self.packages.plan_remove.assert_not_called()
                        self.packages.execute_remove.assert_not_called()
                        self.assertNotIn(key, remove.discover([self.base]))
                        self.assertEqual(self.local.read_bytes(), other_contents)

    def test_native_identity_mismatch_uses_normal_package_removal(self):
        self.base.write_text('[bootstrap.packages]\n"brew:foo" = "*"\n')
        self.local.write_text('[bootstrap.packages]\n"brew:owner/tap/foo" = "*"\n"apt:foo" = "*"\n')
        other_contents = self.local.read_bytes()
        with patch.object(remove, "active_configs", return_value=[self.base.resolve(), self.local.resolve()]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), contextlib.redirect_stdout(io.StringIO()):
            remove.main(["mise", str(self.root), "--base", "brew:foo"])
        self.packages.shares_installation.assert_called_once_with("brew", "foo", ["owner/tap/foo"])
        self.packages.plan_remove.assert_called_once_with("brew", "foo")
        self.packages.execute_remove.assert_called_once_with(self.packages.plan_remove.return_value)
        self.assertNotIn("brew:foo", remove.discover([self.base]))
        self.assertEqual(self.local.read_bytes(), other_contents)

    def test_default_exact_request_preserves_native_equivalent_declaration(self):
        for manager, qualified in (("brew", "owner/tap/foo"), ("brew-cask", "owner/tap/foo"), ("apt", "foo:amd64")):
            for selected, other in (("foo", qualified), (qualified, "foo")):
                for same_config in (True, False):
                    with self.subTest(manager=manager, selected=selected, same_config=same_config):
                        key, other_key = f"{manager}:{selected}", f"{manager}:{other}"
                        self.base.write_text(f'[bootstrap.packages]\n"{key}" = "*"\n' + (f'"{other_key}" = "*"\n' if same_config else ""))
                        self.local.write_text('[bootstrap.packages]\n' + ("" if same_config else f'"{other_key}" = "*"\n'))
                        self.packages.reset_mock()
                        self.packages.shares_installation.return_value = True
                        with patch.object(remove, "active_configs", return_value=[self.base.resolve(), self.local.resolve()]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), contextlib.redirect_stdout(io.StringIO()):
                            self.assertEqual(remove.main(["mise", str(self.root), key]), 0)
                        self.packages.shares_installation.assert_called_once_with(manager, selected, [other])
                        self.packages.plan_remove.assert_not_called()
                        self.packages.execute_remove.assert_not_called()
                        remaining = remove.discover([self.base, self.local])
                        self.assertNotIn(key, remaining)
                        self.assertIn(other_key, remaining)

    def test_native_identity_probe_skipped_when_all_aliases_removed_or_keep_installed(self):
        for arguments in (["brew:foo", "brew:owner/tap/foo"], ["--base", "--keep-installed", "brew:foo"]):
            with self.subTest(arguments=arguments):
                self.base.write_text('[bootstrap.packages]\n"brew:foo" = "*"\n')
                self.local.write_text('[bootstrap.packages]\n"brew:owner/tap/foo" = "*"\n')
                self.packages.reset_mock()
                with patch.object(remove, "active_configs", return_value=[self.base.resolve(), self.local.resolve()]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), contextlib.redirect_stdout(io.StringIO()):
                    remove.main(["mise", str(self.root), *arguments])
                self.packages.shares_installation.assert_not_called()
                if "--keep-installed" not in arguments:
                    self.assertNotIn("brew:foo", remove.discover([self.base]))
                    self.assertNotIn("brew:owner/tap/foo", remove.discover([self.local]))

    def test_native_identity_probe_failure_preserves_declarations(self):
        self.base.write_text('[bootstrap.packages]\n"apt:foo" = "*"\n')
        self.local.write_text('[bootstrap.packages]\n"apt:foo:amd64" = "*"\n')
        originals = [path.read_bytes() for path in (self.base, self.local)]
        self.packages.shares_installation.side_effect = ValueError("native identity unavailable")
        with patch.object(remove, "active_configs", return_value=[self.base.resolve(), self.local.resolve()]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), self.assertRaisesRegex(ValueError, "native identity unavailable"):
            remove.main(["mise", str(self.root), "--base", "apt:foo"])
        self.packages.plan_remove.assert_not_called()
        self.packages.execute_remove.assert_not_called()
        self.assertEqual([path.read_bytes() for path in (self.base, self.local)], originals)

    def test_dry_run_all_active_configs_and_selector(self):
        original = self.local.read_bytes()
        with patch.object(remove, "active_configs", return_value=[self.base, self.local]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), patch.object(remove, "execute") as execute:
            self.assertEqual(remove.main(["mise", str(self.root), "--dry-run", "https://github.com/jaskirat1616/mactap-app"]), 0)
            execute.assert_not_called()
            with self.assertRaisesRegex(ValueError, "no declaration"):
                remove.main(["mise", str(self.root), "--base", "--dry-run", "https://github.com/jaskirat1616/mactap-app"])
        self.assertEqual(self.local.read_bytes(), original)

    def test_native_unuse_keep_installed(self):
        entries = remove.discover([self.base])["node"]
        plan = remove.prepare("node", entries, {}, True, self.packages)
        def run(command, **kwargs):
            self.assertEqual(command, ["mise", "-C", str(self.root), "unuse", "--path", str(self.base), "--no-prune", "node"])
            remove.remove_entry(entries[0])
        with patch.object(remove.subprocess, "run", side_effect=run):
            remove.execute(plan, "mise", self.root, True, self.packages)
        self.assertNotIn("node", remove.discover([self.base]))
        self.packages.plan_remove.assert_not_called()

    def test_unuse_failure_surgical_rollback_preserves_unrelated_edit(self):
        entries = remove.discover([self.base])["node"]
        plan = remove.prepare("node", entries, {}, False, self.packages)
        def run(command, **kwargs):
            remove.remove_entry(entries[0])
            document = remove.editor.read_toml(self.base)
            document["tools"]["new-tool"] = "3"
            remove.editor.atomic_write(self.base, tomlkit.dumps(document))
            raise subprocess.CalledProcessError(1, command)
        with patch.object(remove.subprocess, "run", side_effect=run), self.assertRaises(subprocess.CalledProcessError):
            remove.execute(plan, "mise", self.root, False, self.packages)
        document = remove.editor.read_toml(self.base)
        self.assertEqual(document["tools"]["node"], "20")
        self.assertEqual(document["tools"]["new-tool"], "3")
        self.assertIn("# pinned", self.base.read_text())

    def test_package_failure_preserves_declaration(self):
        entries = remove.discover([self.base])["brew:jq"]
        plan = remove.prepare("brew:jq", entries, {}, False, self.packages)
        self.packages.execute_remove.side_effect = ValueError("dependency")
        original = self.base.read_bytes()
        with self.assertRaisesRegex(ValueError, "dependency"):
            remove.execute(plan, "mise", self.root, False, self.packages)
        self.assertEqual(self.base.read_bytes(), original)

    def test_package_success_and_shared_selector_keep_installed(self):
        entries = remove.discover([self.base])["brew:jq"]
        plan = remove.prepare("brew:jq", entries, {}, False, self.packages, shared=True)
        remove.execute(plan, "mise", self.root, False, self.packages)
        self.packages.plan_remove.assert_not_called()
        self.packages.execute_remove.assert_not_called()
        self.assertNotIn("brew:jq", remove.discover([self.base]))

    def test_concurrent_selected_edit_refused(self):
        entries = remove.discover([self.base])["node"]
        self.base.write_text('[tools]\nnode = "22"\n')
        with self.assertRaisesRegex(ValueError, "changed since discovery"):
            remove.check_entries(entries)

    def test_held_installers_preflight(self):
        for identity in ("brew:kanata", "brew-cask:karabiner-elements", "brew-cask:owner/tap/karabiner-elements"):
            with self.subTest(identity=identity), self.assertRaisesRegex(ValueError, "held"):
                remove.prepare(identity, [], {}, False, self.packages)

    def make_owned_app(self):
        applications = self.root / "Applications"
        app = applications / "MacTap.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "app.mactap.MacTap", "CFBundleExecutable": "MacTap"}))
        binary = app / "Contents/MacOS/MacTap"
        binary.write_bytes(b"executable")
        binary.chmod(0o755)
        marker = self.root / (hashlib.sha256(app.name.encode()).hexdigest() + ".json")
        owner = {"repo": "jaskirat1616/mactap-app", "path": str(app), "bundle_id": "app.mactap.MacTap"}
        marker.write_text(json.dumps(owner))
        return applications, app, marker, owner

    def test_owner_path_bundle_and_symlink_protection(self):
        applications, app, marker, owner = self.make_owned_app()
        self.assertEqual(remove.validate_app("github:jaskirat1616/mactap-app", marker, owner, applications), app)
        for changed in (dict(owner, bundle_id="replacement"), dict(owner, path=str(self.root / "unmanaged.app")), dict(owner, repo="other/repo")):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                remove.validate_app("github:jaskirat1616/mactap-app", marker, changed, applications)
        renamed = app.with_name("real.app")
        app.rename(renamed)
        app.symlink_to(renamed)
        with self.assertRaises(ValueError):
            remove.validate_app("github:jaskirat1616/mactap-app", marker, owner, applications)

    def test_app_move_and_failed_unuse_restores_app_and_marker(self):
        applications, app, marker, owner = self.make_owned_app()
        entries = remove.discover([self.local])["github:jaskirat1616/mactap-app"]
        plan = {"identity": "github:jaskirat1616/mactap-app", "entries": entries, "apps": [(marker, owner, app)], "package": None, "shared": False, "prunable": []}
        validate = remove.validate_app
        def failure(*args, **kwargs):
            self.assertFalse(app.exists())
            raise subprocess.CalledProcessError(1, args[0])
        with patch.object(remove, "validate_app", side_effect=lambda identity, mark, own: validate(identity, mark, own, applications)), patch.object(remove.Path, "home", return_value=self.root), patch.object(remove.subprocess, "run", side_effect=failure), self.assertRaises(subprocess.CalledProcessError):
            remove.execute(plan, "mise", self.root, False, self.packages)
        self.assertTrue(app.exists())
        self.assertTrue(marker.exists())
        self.assertEqual(list((self.root / ".Trash").iterdir()), [])

    def test_failed_native_prune_restores_app_and_declaration(self):
        applications, app, marker, owner = self.make_owned_app()
        entries = remove.discover([self.local])["github:jaskirat1616/mactap-app"]
        plan = {"identity": "github:jaskirat1616/mactap-app", "entries": entries, "apps": [(marker, owner, app)], "package": None, "shared": False}
        validate = remove.validate_app
        def run(command, **kwargs):
            if "unuse" in command:
                remove.remove_entry(entries[0])
            else:
                self.assertIn("prune", command)
                self.assertFalse(marker.exists())
                raise subprocess.CalledProcessError(1, command)
        with patch.object(remove, "validate_app", side_effect=lambda identity, mark, own: validate(identity, mark, own, applications)), patch.object(remove.Path, "home", return_value=self.root), patch.object(remove.subprocess, "run", side_effect=run), self.assertRaises(subprocess.CalledProcessError):
            remove.execute(plan, "mise", self.root, False, self.packages)
        self.assertTrue(app.exists())
        self.assertTrue(marker.exists())
        self.assertIn("github:jaskirat1616/mactap-app", remove.discover([self.local]))

    def test_full_removal_second_unuse_failure_preserves_installed_release(self):
        applications, app, marker, owner = self.make_owned_app()
        identity = "github:jaskirat1616/mactap-app"
        self.base.write_text(f'[tools]\n"{identity}" = "latest"\n')
        entries = remove.discover([self.base, self.local])[identity]
        plan = {"identity": identity, "entries": entries, "apps": [(marker, owner, app)], "package": None}
        release = self.root / "installed-release"
        release.write_bytes(b"installed artifact")
        validate = remove.validate_app
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            self.assertIn("unuse", command)
            # Model the installer's implicit pruning, so this catches omitted flags.
            if "--no-prune" not in command:
                release.unlink()
            self.assertEqual(release.read_bytes(), b"installed artifact")
            self.assertFalse(app.exists())
            remove.remove_entry(entries[len(calls) - 1])
            if len(calls) == 2:
                raise subprocess.CalledProcessError(1, command)
        with patch.object(remove, "validate_app", side_effect=lambda identity, mark, own: validate(identity, mark, own, applications)), patch.object(remove.Path, "home", return_value=self.root), patch.object(remove.subprocess, "run", side_effect=run), self.assertRaises(subprocess.CalledProcessError):
            remove.execute(plan, "mise", self.root, False, self.packages)
        self.assertEqual(len(calls), 2)
        self.assertEqual(release.read_bytes(), b"installed artifact")
        self.assertTrue(app.exists())
        self.assertEqual(json.loads(marker.read_text()), owner)
        for path in (self.base, self.local):
            self.assertIn(identity, remove.discover([path]))
        self.assertEqual(list((self.root / ".Trash").iterdir()), [])

    def test_marker_cleanup_failure_restores_prior_marker_before_pruning(self):
        applications, app, marker, owner = self.make_owned_app()
        import shutil
        second_app = applications / "MacTap-copy.app"
        shutil.copytree(app, second_app)
        second_marker = self.root / (hashlib.sha256(second_app.name.encode()).hexdigest() + ".json")
        second_owner = dict(owner, path=str(second_app))
        second_marker.write_text(json.dumps(second_owner))
        identity = "github:jaskirat1616/mactap-app"
        entries = remove.discover([self.local])[identity]
        plan = {"identity": identity, "entries": entries, "apps": [(marker, owner, app), (second_marker, second_owner, second_app)], "package": None}
        release = self.root / "installed-release"
        release.write_bytes(b"installed artifact")
        validate, unlink = remove.validate_app, Path.unlink
        calls = []
        def run(command, **kwargs):
            calls.append(command)
            if "prune" in command or "--no-prune" not in command:
                release.unlink()
            if "unuse" in command:
                remove.remove_entry(entries[0])
        def remove_marker(path, *args, **kwargs):
            if path == second_marker:
                self.assertFalse(marker.exists())
                self.assertEqual(release.read_bytes(), b"installed artifact")
                raise OSError("marker cleanup failed")
            return unlink(path, *args, **kwargs)
        with patch.object(remove, "validate_app", side_effect=lambda identity, mark, own: validate(identity, mark, own, applications)), patch.object(remove.Path, "home", return_value=self.root), patch.object(remove.subprocess, "run", side_effect=run), patch.object(Path, "unlink", new=remove_marker), self.assertRaisesRegex(OSError, "marker cleanup failed"):
            remove.execute(plan, "mise", self.root, False, self.packages)
        self.assertEqual(len(calls), 1)
        self.assertEqual(release.read_bytes(), b"installed artifact")
        self.assertIn(identity, remove.discover([self.local]))
        for owned_app, owned_marker, expected_owner in ((app, marker, owner), (second_app, second_marker, second_owner)):
            self.assertTrue(owned_app.exists())
            self.assertEqual(json.loads(owned_marker.read_text()), expected_owner)
        self.assertEqual(list((self.root / ".Trash").iterdir()), [])

    def test_app_success_trashes_app_preserves_settings_and_clears_marker(self):
        applications, app, marker, owner = self.make_owned_app()
        settings = self.root / "Library/Preferences/app.mactap.MacTap.plist"
        settings.parent.mkdir(parents=True)
        settings.write_bytes(b"personal settings")
        entries = remove.discover([self.local])["github:jaskirat1616/mactap-app"]
        plan = {"identity": "github:jaskirat1616/mactap-app", "entries": entries, "apps": [(marker, owner, app)], "package": None, "shared": False, "prunable": []}
        validate = remove.validate_app
        with patch.object(remove, "validate_app", side_effect=lambda identity, mark, own: validate(identity, mark, own, applications)), patch.object(remove.Path, "home", return_value=self.root), patch.object(remove.subprocess, "run", side_effect=lambda command, **kwargs: remove.remove_entry(entries[0]) if "unuse" in command else None):
            remove.execute(plan, "mise", self.root, False, self.packages)
        self.assertFalse(app.exists())
        self.assertFalse(marker.exists())
        self.assertEqual(settings.read_bytes(), b"personal settings")
        self.assertEqual(len(list((self.root / ".Trash").glob("MacTap-*.app"))), 1)

    def test_missing_owned_app_cleans_marker(self):
        applications, app, marker, owner = self.make_owned_app()
        import shutil
        shutil.rmtree(app)
        self.assertEqual(remove.validate_app("github:jaskirat1616/mactap-app", marker, owner, applications), app)

    def test_source_protection_uses_all_tracked_sources(self):
        response = Mock(stdout=json.dumps([{"sources": [{"path": str(self.local)}, {"path": str(self.root / "other-project/mise.toml") }]}]))
        with patch.object(remove.subprocess, "run", return_value=response) as run:
            paths = remove.release_sources("mise", self.root, "github:o/r")
        self.assertEqual(paths, {self.local.resolve(), (self.root / "other-project/mise.toml").resolve()})
        run.assert_called_once_with(["mise", "-C", str(self.root), "ls", "github:o/r", "--json", "--all-sources"], check=True, capture_output=True, text=True)

    def test_selected_app_shared_by_other_project_is_retained(self):
        applications, app, marker, owner = self.make_owned_app()
        records = {"github:jaskirat1616/mactap-app": [(marker, owner)]}
        entries = remove.discover([self.local])["github:jaskirat1616/mactap-app"]
        plan = remove.prepare("github:jaskirat1616/mactap-app", entries, records, False, self.packages, shared=True)
        self.assertEqual(plan["apps"], [])
        with patch.object(remove.subprocess, "run", side_effect=lambda command, **kwargs: remove.remove_entry(entries[0]) if "unuse" in command else None):
            remove.execute(plan, "mise", self.root, False, self.packages)
        self.assertTrue(app.exists())
        self.assertTrue(marker.exists())

    def test_keep_installed_owner_alias_survives_for_later_removal(self):
        _, app, marker, owner = self.make_owned_app()
        records = {"github:jaskirat1616/mactap-app": [(marker, owner)]}
        self.assertEqual(remove.resolve(["mactap"], {}, records), ["github:jaskirat1616/mactap-app"])
        plan = remove.prepare("github:jaskirat1616/mactap-app", [], records, True, self.packages)
        remove.execute(plan, "mise", self.root, True, self.packages)
        self.assertTrue(app.exists())
        self.assertTrue(marker.exists())

    def test_marker_only_uninstall_uses_native_targeted_pruning(self):
        plan = {"identity": "github:o/r", "entries": [], "apps": [(Mock(), {}, self.root / "missing.app")], "package": None, "shared": False}
        plan["apps"][0][0].read_text.return_value = "{}"
        plan["apps"][0][0].read_bytes.return_value = b"{}"
        plan["apps"][0][0].is_symlink.return_value = False
        with patch.object(remove, "validate_app"), patch.object(remove.subprocess, "run") as run:
            remove.execute(plan, "mise", self.root, False, self.packages)
        run.assert_called_once_with(["mise", "-C", str(self.root), "prune", "--yes", "--tools", "github:o/r"], check=True)

    def test_profile_and_explicit_path_select_only_the_requested_file(self):
        profile = self.root / "config.nas.toml"
        profile.write_text('[tools]\nnode = "22"\n')
        external = self.root / "external/mise.toml"
        external.parent.mkdir()
        external.write_text('[tools]\nnode = "24"\n')
        with patch.object(remove, "active_configs", return_value=[self.base, profile]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), patch.object(remove, "execute") as execute:
            remove.main(["mise", str(self.root), "--profile", "nas", "node"])
            self.assertEqual([entry["path"] for entry in execute.call_args.args[0]["entries"]], [profile.resolve()])
            execute.reset_mock()
            remove.main(["mise", str(self.root), "--path", str(external), "node"])
            self.assertEqual([entry["path"] for entry in execute.call_args.args[0]["entries"]], [external.resolve()])

    def test_batch_stops_at_first_failure_and_reports_completed_targets(self):
        self.base.write_text('[tools]\nnode = "20"\nruby = "3"\npython = "3"\n')
        stderr = io.StringIO()
        with patch.object(remove, "active_configs", return_value=[self.base]), patch.object(remove, "state_directory", return_value=self.root / "state"), patch.object(remove, "load_module", return_value=self.packages), patch.object(remove, "execute", side_effect=[None, ValueError("failure"), None]) as execute, contextlib.redirect_stderr(stderr):
            with self.assertRaisesRegex(ValueError, "failure"):
                remove.main(["mise", str(self.root), "node", "ruby", "python"])
        self.assertEqual(execute.call_count, 2)
        self.assertIn("completed before failure: node", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
