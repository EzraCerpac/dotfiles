import os
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class HerdrConfigTest(unittest.TestCase):
    def test_workspace_keys_are_terminal_safe_and_distinct(self) -> None:
        config = tomllib.loads((ROOT / "dotfiles/.config/herdr/config.toml").read_text())

        self.assertEqual(config["keys"]["switch_workspace"], "prefix+alt+1..9")
        self.assertEqual(config["keys"]["close_workspace"], "prefix+d")

        commands = {entry["command"]: entry["key"] for entry in config["keys"]["command"]}
        self.assertEqual(commands["ezracerpac.jj-waltz.remove"], "prefix+shift+d")

    @unittest.skipUnless(shutil.which("mise"), "native mise required")
    def test_native_shell_template_and_old_symlink_migration(self) -> None:
        for profile, shell in [("nas", "/root/.local/bin/fish"),
                               ("nas", "/usr/local/bin/fish"),
                               ("workstation", "/opt/homebrew/bin/fish")]:
            with self.subTest(profile=profile, shell=shell), tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp)
                home = base / "different home"
                root = home / ".config/mise"
                shutil.copytree(ROOT / "templates/.config/herdr", root / "templates/.config/herdr")
                shutil.copytree(ROOT / "dotfiles/.config/herdr", root / "dotfiles/.config/herdr")
                (root / "config.toml").write_text(
                    '[vars]\nprofile = "' + profile + '"\nfish_shell = "' + shell + '"\n'
                    '[dotfiles.herdr]\nsource = "templates/.config/herdr/config.tera"\n'
                    'mode = "template"\nvariants = [{default = true, target = "~/.config/herdr/config.toml"}]\n'
                )
                source = root / "dotfiles/.config/herdr/config.toml"
                original = source.read_bytes()
                target = home / ".config/herdr/config.toml"
                target.parent.mkdir(parents=True)
                target.symlink_to(source)
                env = dict(os.environ, HOME=str(home), MISE_CONFIG_DIR=str(root),
                           MISE_DATA_DIR=str(base / "data"), MISE_CACHE_DIR=str(base / "cache"),
                           MISE_STATE_DIR=str(base / "state"), MISE_TRUSTED_CONFIG_PATHS=str(root))
                env.pop("MISE_ENV", None)
                command = [shutil.which("mise"), "-C", str(root), "bootstrap", "dotfiles", "apply", "--yes"]
                result = subprocess.run(command, env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(target.is_symlink())
                self.assertEqual(source.read_bytes(), original)
                rendered = target.read_bytes()
                config = tomllib.loads(rendered.decode())
                self.assertEqual(config["terminal"], {"default_shell": shell, "shell_mode": "auto"})
                if profile == "workstation":
                    expected = tomllib.loads(original.decode())
                    expected["terminal"] = config["terminal"]
                    self.assertEqual(config, expected)
                else:
                    self.assertEqual(set(config), {"terminal"})
                command[2] = str(base)  # Global native dotfiles also work outside the setup checkout.
                result = subprocess.run(command, env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(target.read_bytes(), rendered)

    def test_cerpacnas_handoff_clears_only_nested_marker(self) -> None:
        config = tomllib.loads(
            (ROOT / "dotfiles/.config/herdr/plugins/config/herdr-picker-plus/config.toml").read_text()
        )

        integration = next(item for item in config["integrations"] if item["id"] == "cerpacnas")
        self.assertIn("env -u HERDR_ENV", integration["open"])
        self.assertIn("--remote cerpacnas --handoff", integration["open"])
        self.assertNotIn("allow_nested", integration["open"])
        self.assertFalse(config.get("sessions", {}).get("entries"))


if __name__ == "__main__":
    unittest.main()
