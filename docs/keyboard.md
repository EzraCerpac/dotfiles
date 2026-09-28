# Keyboard workflow (Corne + QMK)

Kanata configuration and its held-version installer belong to base on macOS.
Use `kbd activate` from your logged-in Mac account to activate only that user's
session. It requests administrator approval for the root-owned driver service,
saves the previous service files for rollback, and uses Kanata's lock-screen
guard. The root wrapper joins your GUI session and stops its child when another
user takes the console. This is separate from building or flashing a keyboard.

Keyboard source lives at `~/.config/keyboard/corne-qmk` and syncs into a local `qmk_firmware` checkout at `~/Projects/keyboards/qmk_firmware`.

Commands:

- `kbd provision` → validate setup prerequisites, prepare QMK, activate VirtualHID, and install the Kanata daemon
- `kbd activate` → refresh the daemon for the currently logged-in Mac user only
- `kbd doctor` → diagnose macOS Kanata/Karabiner runtime, TCC grants, and duplicate VirtualHID daemons
- `kbd sync` → copy keymap source into `qmk_firmware`, regenerate layout images, and reload HUD
- `kbd build` → build `crkbd/rev1:ezra_corne` (`rp2040_ce` by default)
- `kbd build-all` → build both `rp2040_ce` and `sparkfun_pm2040`
- `kbd build --left` / `kbd build --right` → build convenience left/right-tagged UF2 artifacts
- `kbd flash left` / `kbd flash right` → authoritative split-handedness flash flow (`uf2-split-left/right`)
- `kbd layout-images` → regenerate JSON/YAML/SVG/PNG layer images from `keymap.c`
- `kbd hud-reload` → reload Hammerspoon HUD overlay
- `kbd open-artifacts` → open UF2 artifact folder in Finder

`kbd provision` is an explicit lifecycle task; it may request `sudo`. If macOS needs DriverKit, Input Monitoring, or Accessibility approval, the command stops with the exact System Settings action. Complete that action, then rerun the same task; finished stages are safe to repeat.

Kanata remains a root process because the Karabiner VirtualHID socket is
root-only. Its root-owned supervisor records the non-root console UID when you
run `kbd activate`, and starts Kanata only while that same user owns the Mac
console. Locking the screen or switching users releases the keyboard grab;
another Mac user never inherits your remapping. Kanata's
`--release-grab-on-lock` option handles the lock/fast-user-switch transition.
Run `kbd activate` again after changing the Kanata source or switching the
owner account. The held Kanata 1.12.0 and Karabiner-Elements 16.0.0 versions
are intentional compatibility choices.

Run keyboard tasks from the setup root so mise loads the selected profile:

- `mise -C ~/.config/mise run kbd_provision`
- `mise -C ~/.config/mise run kbd_sync`
- `mise -C ~/.config/mise run kbd_build`
- `mise -C ~/.config/mise run kbd_build_all`
- `mise -C ~/.config/mise run kbd_build_left`
- `mise -C ~/.config/mise run kbd_build_right`
- `mise -C ~/.config/mise run kbd_flash_left`
- `mise -C ~/.config/mise run kbd_flash_right`
- `mise -C ~/.config/mise run kbd_hud`
- `mise -C ~/.config/mise run kbd_images`
