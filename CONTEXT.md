# Window-manager glossary

This glossary defines the terms used by the Rift, Aegis, and BoringNotch setup. The operating steps live in [the window-manager runbook](docs/window-manager-runbook.md).

- **Desktop plumbing**: The macOS services, login agents, permissions, applications, and helpers that make the window workflow run.
- **Workflow behavior**: The windows, workspaces, shortcuts, gestures, layout profiles, and HUD ownership that Ezra uses day to day.
- **Tracking build**: The local Rift or Aegis build whose source revision and signing details are recorded for repeatable updates.
- **Custom patch**: A deliberate local change that is kept separate from upstream code and can be replaced by the official build.
- **Daily pin**: The exact tracking-build revision selected for normal use.
- **Candidate build**: A newer tracking build built for a limited trial before it replaces the daily pin or becomes an upstream change.
- **Rift activation**: The explicit `rift-local-install --activate` cutover. It switches the signed release pointer and managed service as one rollback-safe transaction; Chezmoi only stages files.
- **Single-column expansion**: The Rift layout behavior that lets one non-floating column fill the usable tiling area while preserving gaps.
- **External bar reserve**: The 58 px outer top gap on every non-built-in display: 48 px for Aegis and the normal 10 px breathing gap.
- **Notch target**: A display with a hardware notch, or a notchless display only when Aegis's virtual-notch setting is explicitly enabled.
- **macOS Space**: A native Mission Control desktop. Rift manages windows inside it.
- **Virtual workspace**: One indexed Rift window group inside a macOS Space.
- **Scrolling workspace**: A workspace whose windows form a horizontal strip of columns. A column may contain a vertical stack.
- **Flow**: The mixed workspace for the current task.
- **Thesis**: The workspace reserved for thesis work. It has no broad automatic routing.
- **Flexible numbered workspace**: An unassigned workspace for temporary or manual work.
- **Special workspace**: A shortcut-driven workspace with one focused job. Ops is special because it owns temporary btop.
- **Hub**: A stable home for a workbench that switches projects internally, such as a browser or Herdr.
- **Anchor**: A dedicated destination for one application, such as ChatGPT.
- **Ops**: The operations workspace that owns the temporary btop session.
- **Browser Hub**: The workspace for manually anchored browser work.
- **Terminal Hub**: The workspace for the persistent default Herdr session.
- **Media**: The workspace for Music.
- **Comms**: The workspace for Mail and WhatsApp.
- **Preferred external display**: The rightmost managed external display, or the current display when no external display is connected.
- **Laptop Scrolling**: The runtime profile for a laptop display and scrolling layout.
- **Docked Traditional**: The runtime profile for side-by-side displays where scrolling windows could leak between displays.
- **Managed window**: A window Rift places in a virtual workspace and exposes through its layout and queries.
- **Unmanaged window**: A window Rift leaves outside its layouts, such as a Raycast launcher or transient preview.
- **Transient window**: A dialog, preview, update prompt, or utility panel that should remain overlaid instead of taking a layout column.
- **Native notification ownership**: The macOS notification system keeps its banner because Aegis does not dismiss or replace it.
- **Aegis notification HUD**: Aegis's optional second notification banner. When it is off, native macOS banners remain untouched.
- **Focused border**: The visible white JankyBorders outline around the focused window. Inactive outlines are transparent.
- **Aegis status pill**: The compact system-status control in Aegis's menu bar.
- **Aegis follow-ups**: Three separate upstream-ready changes for the configured Rift CLI path, notification-HUD lifecycle, and adaptive-min status sizing. The MediaService adapter shutdown fix is reserved for a separate future change.
