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
        self.assertEqual(scrolling["gestures"], {"enabled": False})
        self.assertEqual(
            settings["gestures"],
            {
                "enabled": True,
                "consume_dock_swipe": True,
                "invert_horizontal_swipe": False,
                "swipe_vertical_tolerance": 0.4,
                "skip_empty": True,
                "fingers": 4,
                "distance_pct": 0.08,
                "haptics_enabled": True,
                "haptic_pattern": "level_change",
            },
        )
        self.assertEqual(virtual["default_workspace_count"], 14)
        self.assertEqual(
            virtual["workspace_names"],
            [
                "Flow",
                "Thesis",
                "ChatGPT",
                "3",
                "4",
                "5",
                "6",
                "7",
                "8",
                "Ops",
                "Browser Hub",
                "Terminal Hub",
                "Comms",
                "Media",
            ],
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

        orion_preview = by_app[("com.kagi.kagimacOS", "^Orion Preview$")]
        raycast = by_app[("com.raycast.macos", None)]
        self.assertFalse(orion_preview["manage"])
        self.assertFalse(raycast["manage"])
        self.assertEqual(
            [rule for rule in rules if rule.get("app_id") == "com.kagi.kagimacOS"],
            [orion_preview],
        )

        self.assertEqual(by_app[("com.openai.codex", None)]["workspace"], 2)
        self.assertEqual(by_app[("com.apple.mail", None)]["workspace"], 12)
        self.assertEqual(by_app[("net.whatsapp.WhatsApp", None)]["workspace"], 12)
        self.assertEqual(by_app[("com.apple.Music", None)]["workspace"], 13)
        self.assertEqual(by_app[("com.github.wez.wezterm", "(?i)^herdr([[:space:]]|$)")]["workspace"], 11)
        self.assertEqual(by_app[("com.github.wez.wezterm", "(?i)^btop([[:space:]]|$)")]["workspace"], 9)
        self.assertNotIn(("com.google.Chrome", None), by_app)
        self.assertNotIn(("com.apple.Safari", None), by_app)

        transient_rules = rules[:7]
        self.assertEqual(transient_rules[0], orion_preview)
        self.assertEqual(transient_rules[1], raycast)
        self.assertEqual(
            transient_rules[2:],
            [
                {"ax_subrole": "AXDialog", "floating": True},
                {"ax_subrole": "AXSystemDialog", "floating": True},
                {"ax_role": "AXSheet", "floating": True},
                {"ax_subrole": "AXFloatingWindow", "floating": True},
                {"ax_subrole": "AXSystemFloatingWindow", "floating": True},
            ],
        )
        self.assertTrue(all(rule.get("floating") for rule in transient_rules[2:]))
        self.assertTrue(all(rule.get("manage", True) for rule in transient_rules[2:]))
        self.assertTrue(all(rule.get("app_id") for rule in rules[7:]))

        floating = {
            rule["app_id"]
            for rule in rules
            if rule.get("floating") and rule.get("app_id")
        }
        self.assertEqual(
            floating,
            {"com.chabomakers.Antinote", "com.apple.weather", "com.apple.AddressBook"},
        )

    def test_keys_use_supported_v05_commands(self) -> None:
        keys = self.config["keys"]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertEqual(
            self.config["modifier_combinations"],
            {
                "Meh": "Meta + Ctrl + Alt",
                "Hyper": "Meta + Ctrl + Alt + Shift",
            },
        )

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
            "show_mission_control_all",
            "show_mission_control_current",
        }
        for binding in keys.values():
            command = binding if isinstance(binding, str) else next(iter(binding))
            self.assertIn(command, supported, binding)

        self.assertTrue(
            all(
                key.startswith(("Meh + ", "Hyper + "))
                or key in {"F3", "Shift + F3"}
                for key in keys
            )
        )
        self.assertTrue(all("Meta + Ctrl + Alt" not in key for key in keys))
        self.assertEqual(keys["F3"], "show_mission_control_all")
        self.assertEqual(keys["Shift + F3"], "show_mission_control_current")
        self.assertEqual(keys["Meh + O"], "show_mission_control_all")
        self.assertIn("wm-focus left", keys["Meh + H"]["exec"][-1])
        self.assertEqual(keys["Meh + 9"]["exec"][0:2], ["/bin/sh", "-lc"])
        for workspace in range(9):
            with self.subTest(workspace=workspace):
                self.assertEqual(
                    keys[f"Meh + {workspace}"],
                    {"switch_to_workspace": workspace},
                )
                self.assertEqual(
                    keys[f"Hyper + {workspace}"],
                    {"move_window_to_workspace": {"workspace": workspace, "follow": True}},
                )
        for shortcut, workspace in {"B": 10, "T": 11, "E": 12}.items():
            with self.subTest(shortcut=shortcut):
                self.assertEqual(keys[f"Meh + {shortcut}"], {"switch_to_workspace": workspace})
                self.assertEqual(
                    keys[f"Hyper + {shortcut}"],
                    {"move_window_to_workspace": {"workspace": workspace, "follow": True}},
                )
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
        self.assertEqual(keys["Meh + Tab"], "switch_to_last_workspace")
        self.assertEqual(
            keys["Hyper + Tab"]["move_window_to_display"]["selector"],
            "right",
        )
        self.assertEqual(
            keys["Hyper + Enter"]["exec"],
            ["/opt/homebrew/bin/wezterm", "start", "--", "/opt/homebrew/bin/fish", "-l"],
        )
        self.assertEqual(
            keys["Hyper + A"]["exec"],
            ["/usr/bin/open", "-a", "Activity Monitor"],
        )
        self.assertIn("Meh + [", keys)
        self.assertIn("Hyper + Dot", keys)
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
