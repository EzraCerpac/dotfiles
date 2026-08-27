import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class RiftConfigTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = tomllib.loads(
            (ROOT / "dot_config/rift/config.toml").read_text(encoding="utf-8")
        )

    def test_scrolling_layout_and_workspace_model(self) -> None:
        settings = self.config["settings"]
        scrolling = settings["layout"]["scrolling"]
        virtual = self.config["virtual_workspaces"]

        self.assertEqual(settings["animation_duration"], 0.18)
        self.assertEqual(settings["animation_fps"], 120.0)
        self.assertTrue(settings["animate"])
        self.assertTrue(settings["focus_follows_mouse"])
        self.assertFalse(settings["mouse_follows_focus"])
        self.assertFalse(settings["mouse_hides_on_focus"])
        self.assertEqual(settings["layout"]["mode"], "scrolling")
        self.assertEqual(scrolling["column_width_ratio"], 0.7)
        self.assertEqual(scrolling["min_column_width_ratio"], 0.3)
        self.assertEqual(scrolling["max_column_width_ratio"], 0.9)
        self.assertEqual(scrolling["focus_navigation_style"], "niri")
        self.assertEqual(scrolling["gestures"]["fingers"], 3)
        self.assertTrue(scrolling["gestures"]["enabled"])
        self.assertTrue(scrolling["gestures"]["propagate_to_workspace_swipe"])
        self.assertEqual(virtual["default_workspace_count"], 8)
        self.assertEqual(
            virtual["workspace_names"],
            ["Flow", "Thesis", "ChatGPT", "Comms", "Media", "Ops", "Browser Hub", "Terminal Hub"],
        )
        self.assertTrue(virtual["preserve_focus_per_workspace"])
        self.assertFalse(virtual["workspace_auto_back_and_forth"])
        self.assertTrue(virtual["reapply_app_rules_on_title_change"])

    def test_gaps_and_rift_ui(self) -> None:
        gaps = self.config["settings"]["layout"]["gaps"]
        self.assertEqual(gaps["outer"], {"top": 10.0, "left": 10.0, "bottom": 10.0, "right": 10.0})
        self.assertEqual(gaps["inner"], {"horizontal": 10.0, "vertical": 10.0})
        self.assertFalse(self.config["settings"]["ui"]["menu_bar"]["enabled"])
        self.assertEqual(
            self.config["settings"]["run_on_start"],
            ["/opt/homebrew/bin/borders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0"],
        )

    def test_app_rules_are_exact_and_title_sensitive(self) -> None:
        rules = self.config["virtual_workspaces"]["app_rules"]
        by_app = {(rule.get("app_id"), rule.get("title_regex")): rule for rule in rules}

        self.assertEqual(by_app[("com.openai.codex", None)]["workspace"], 2)
        self.assertEqual(by_app[("com.apple.mail", None)]["workspace"], 3)
        self.assertEqual(by_app[("net.whatsapp.WhatsApp", None)]["workspace"], 3)
        self.assertEqual(by_app[("com.apple.Music", None)]["workspace"], 4)
        self.assertEqual(by_app[("com.github.wez.wezterm", "(?i)^herdr([[:space:]]|$)")]["workspace"], 7)
        self.assertEqual(by_app[("com.github.wez.wezterm", "(?i)^btop([[:space:]]|$)")]["workspace"], 5)
        self.assertNotIn(("com.google.Chrome", None), by_app)
        self.assertNotIn(("com.apple.Safari", None), by_app)
        self.assertTrue(all(rule.get("app_id") for rule in rules))

        floating = {rule["app_id"] for rule in rules if rule.get("floating")}
        self.assertEqual(
            floating,
            {"com.chabomakers.Antinote", "com.apple.weather", "com.apple.AddressBook"},
        )

    def test_keys_use_supported_v05_commands(self) -> None:
        keys = self.config["keys"]
        self.assertEqual(len(keys), len(set(keys)))

        supported = {
            "move_focus",
            "move_node",
            "switch_to_workspace",
            "switch_to_last_workspace",
            "prev_workspace",
            "next_workspace",
            "move_window_to_workspace",
            "exec",
            "toggle_fullscreen_within_gaps",
            "center_selection",
            "snap_strip",
            "unjoin_windows",
            "toggle_stack",
            "consume_or_expel_window",
            "toggle_window_floating",
            "move_window_to_display",
            "resize_window_shrink",
            "resize_window_grow",
        }
        for binding in keys.values():
            command = binding if isinstance(binding, str) else next(iter(binding))
            self.assertIn(command, supported, binding)

        self.assertTrue(all(key.startswith("Meta + Ctrl + Alt + ") for key in keys))
        self.assertIn("wm-focus left", keys["Meta + Ctrl + Alt + H"]["exec"][-1])
        self.assertEqual(keys["Meta + Ctrl + Alt + 9"]["exec"][0:2], ["/bin/sh", "-lc"])
        self.assertEqual(keys["Meta + Ctrl + Alt + Tab"], "switch_to_last_workspace")
        self.assertEqual(
            keys["Meta + Ctrl + Alt + Shift + Tab"]["move_window_to_display"]["selector"],
            "right",
        )
        self.assertEqual(
            keys["Meta + Ctrl + Alt + Shift + Enter"]["exec"],
            ["/opt/homebrew/bin/wezterm", "start", "--", "/opt/homebrew/bin/fish", "-l"],
        )
        self.assertIn("Meta + Ctrl + Alt + [", keys)
        self.assertIn("Meta + Ctrl + Alt + Shift + Dot", keys)
        self.assertNotIn("mode service", keys.values())

    def test_wezterm_marks_only_herdr_window_titles(self) -> None:
        wezterm = (ROOT / "dot_wezterm.lua").read_text(encoding="utf-8")
        self.assertIn('wezterm.on("format-window-title"', wezterm)
        self.assertIn('process_basename(pane.foreground_process_name or "") == "herdr"', wezterm)
        self.assertIn('return "Herdr — " .. title', wezterm)

    def test_modified_tab_has_no_f20_or_f16_bridge(self) -> None:
        kanata = (ROOT / "dot_config/kanata/config.kbd").read_text(encoding="utf-8")
        qmk = (
            ROOT / "dot_config/keyboard/corne-qmk/keymaps/ezra_corne/keymap.c"
        ).read_text(encoding="utf-8")
        hammerspoon = (ROOT / "dot_hammerspoon/init.lua").read_text(encoding="utf-8")

        rift = (ROOT / "dot_config/rift/config.toml").read_text(encoding="utf-8")

        self.assertNotIn("defoverridesv2", kanata)
        self.assertNotIn("f20", kanata.lower())
        self.assertNotIn("f16", kanata.lower())
        self.assertNotIn("KC_F20", qmk)
        self.assertNotIn("KC_F16", qmk)
        self.assertNotIn("bridged_tab", qmk)
        self.assertNotIn('"F20"', rift)
        self.assertNotIn('"F16"', rift)
        self.assertNotIn('["f20"]', hammerspoon)
        self.assertNotIn('["f16"]', hammerspoon)


if __name__ == "__main__":
    unittest.main()
