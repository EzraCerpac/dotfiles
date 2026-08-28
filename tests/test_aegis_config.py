import json
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AegisConfigTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = json.loads((ROOT / "dot_config/aegis/config.json").read_text())

    def test_json_is_valid_and_selects_rift(self) -> None:
        self.assertEqual(self.config["windowManagerType"], "rift")
        self.assertTrue(self.config["launchAtLogin"])
        self.assertEqual(self.config["menuBarHeight"], 48.0)

    def test_bar_switcher_status_and_notifications_stay_enabled(self) -> None:
        for key in (
            "showSpaceIndicators",
            "showAppLauncher",
            "showContextButton",
            "showSystemStatus",
            "showCPUMonitor",
            "showRAMMonitor",
            "appSwitcherEnabled",
            "appSwitcherShowPreviews",
            "showNotchHUD",
            "showNotificationHUD",
        ):
            with self.subTest(key=key):
                self.assertTrue(self.config[key])
        self.assertEqual(self.config["monitorDisplayStyle"], "graph")
        self.assertEqual(self.config["systemStatusOrder"], ["focus", "cpu", "ram", "wifi", "battery", "clock", "date"])

    def test_boring_notch_owns_media_and_device_huds(self) -> None:
        for key in (
            "showVirtualNotch",
            "showOverlayHUD",
            "showMusicHUD",
            "showDeviceHUD",
            "showFocusHUD",
        ):
            with self.subTest(key=key):
                self.assertFalse(self.config[key])

    def test_context_button_is_menu_only(self) -> None:
        self.assertTrue(self.config["showContextButton"])
        self.assertTrue(self.config["contextButtonMenuOnly"])
        self.assertFalse(self.config["expandContextButtonOnScroll"])

    def test_workspace_bar_uses_shortcut_labels(self) -> None:
        self.assertTrue(self.config["hideEmptyWorkspaces"])
        self.assertEqual(self.config["workspaceLabelStyle"], "index")
        overrides = {"10": "B", "11": "T", "12": "E", "13": "M"}
        self.assertEqual(self.config["workspaceLabelOverrides"], overrides)

        rift = tomllib.loads((ROOT / "dot_config/rift/config.toml").read_text())
        keys = rift["keys"]
        for workspace, shortcut in {10: "B", 11: "T", 12: "E"}.items():
            with self.subTest(workspace=workspace, shortcut=shortcut):
                self.assertEqual(keys[f"Meh + {shortcut}"]["switch_to_workspace"], workspace)

        self.assertEqual(
            keys["Meh + M"]["exec"],
            ["/bin/sh", "-lc", "~/.local/bin/rift-preferred-workspace switch 13"],
        )
        self.assertEqual(
            keys["Hyper + 9"]["exec"],
            ["/bin/sh", "-lc", "~/.local/bin/rift-preferred-workspace move 9"],
        )
        self.assertEqual(
            keys["Hyper + M"]["exec"],
            [
                "/bin/sh",
                "-lc",
                "~/.local/bin/rift-preferred-workspace launch 13 com.apple.Music Music",
            ],
        )
        self.assertEqual(
            keys["Meh + 9"]["exec"],
            ["/bin/sh", "-lc", "~/.local/bin/start-btop --focus"],
        )

    def test_trial_safety_and_custom_commands(self) -> None:
        self.assertFalse(self.config["useSwipeToDestroySpace"])
        self.assertEqual(self.config["notificationHUDAutoHideDelay"], 8.0)
        self.assertEqual(self.config["notificationExcludedApps"], [])

        commands = self.config["customCommands"]
        self.assertEqual(
            [command["label"] for command in commands],
            ["Laptop Scrolling", "Docked Traditional", "Reload Rift", "Restart Rift"],
        )
        self.assertEqual(
            commands[0]["command"],
            "~/.local/bin/rift-layout-profile scrolling",
        )
        self.assertEqual(
            commands[1]["command"],
            "~/.local/bin/rift-layout-profile traditional",
        )
        self.assertEqual(commands[2]["command"], "rift-cli execute config reload")
        self.assertEqual(
            commands[3]["command"],
            "/bin/launchctl kickstart -k gui/$(id -u)/git.acsandmann.rift",
        )

    def test_smart_apply_readds_aegis_drift(self) -> None:
        smart_apply = tomllib.loads((ROOT / "dot_config/chezmoi/smart-apply.toml").read_text())
        self.assertIn("~/.config/aegis/config.json", smart_apply["allowlist"])


if __name__ == "__main__":
    unittest.main()
