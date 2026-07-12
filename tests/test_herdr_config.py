import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class HerdrConfigTest(unittest.TestCase):
    def test_workspace_keys_are_terminal_safe_and_distinct(self) -> None:
        config = tomllib.loads((ROOT / "dot_config/herdr/config.toml").read_text())

        self.assertEqual(config["keys"]["switch_workspace"], "prefix+alt+1..9")
        self.assertEqual(config["keys"]["close_workspace"], "prefix+d")

        commands = {entry["command"]: entry["key"] for entry in config["keys"]["command"]}
        self.assertEqual(commands["ezracerpac.jj-waltz.remove"], "prefix+shift+d")

    def test_cerpacnas_handoff_clears_only_nested_marker(self) -> None:
        config = tomllib.loads(
            (ROOT / "dot_config/herdr/plugins/config/herdr-picker-plus/config.toml").read_text()
        )

        integration = next(item for item in config["integrations"] if item["id"] == "cerpacnas")
        self.assertIn("env -u HERDR_ENV", integration["open"])
        self.assertIn("--remote cerpacnas --handoff", integration["open"])
        self.assertNotIn("allow_nested", integration["open"])
        self.assertFalse(config.get("sessions", {}).get("entries"))


if __name__ == "__main__":
    unittest.main()
