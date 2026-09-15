# Window-manager glossary

The operating steps are in [the window-manager runbook](docs/window-manager-runbook.md).

- **AeroSpace**: The daily window manager. Its tracked configuration defines persistent workspace shortcuts, app routing, layouts, gaps, and keyboard controls. Focus follows the pointer, while monitor changes leave the pointer in place.
- **Aegis**: The workspace bar, app switcher, and command menu. The managed configuration connects it to AeroSpace.
- **BoringNotch**: The owner of the media, volume, brightness, and device HUDs.
- **Native Space**: A macOS Mission Control desktop. macOS controls whether displays have separate Spaces; AeroSpace's window and workspace behavior must preserve that setting.
- **Workspace**: An AeroSpace destination selected by a number or letter shortcut. The startup helper places Ops and Media on the rightmost external display when the display mapping is unambiguous. Codex routes to workspace 2.
- **Meh**: Cmd+Ctrl+Alt. **Hyper**: Meh plus Shift. The current AeroSpace controls keep this chord family.
- **Rift rollback**: The retained source config and explicit local build/install task provide the rollback path. Normal mise bootstrap does not deploy or activate the old LaunchAgent. Rollback requires an explicit manager handoff.
- **Native fullscreen separation**: The macOS setting that keeps fullscreen Spaces attached to their own display. The window-manager config does not set `com.apple.spaces spans-displays`.
