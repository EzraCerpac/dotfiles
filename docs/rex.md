# Rex terminal workflow

Rex is the daily terminal and multiplexer.
Its keymap, helpers and server definitions live in this setup source.
WezTerm remains installed with its existing configuration for rollback.

## Daily use

| Shortcut | Action |
| --- | --- |
| Cmd+K | Rex session picker |
| Cmd+Shift+O | Open a recent project on the selected host |
| Cmd+T | New tab |
| Cmd+D / Cmd+Shift+D | Split right / down |
| Ctrl/Alt combinations without Cmd | Pass through to the terminal program |
| Meh+H/J/K/L or arrows | Neovim split, then Rex pane, then AeroSpace window |
| Hyper+Enter | Open a new Rex shell window on T |
| Meh+9 | Show btop (Rex session `ops`); press again to return to the previous session and workspace |

Meh means Cmd+Ctrl+Alt;
Hyper adds Shift.
Rex uses its native Cmd shortcuts with no imported modal keymap or Ctrl+B prefix.
Ctrl/Alt combinations without Cmd belong to Neovim, jjui and the shell,
including Ctrl+B and Ctrl+S.
Use Meh-direction for the editor-aware navigation chain.
Cmd+K and the Open recent project palette action also work without the prefix.

In Rex's Terminal settings,
set Option key to **Sends Alt** so Option shortcuts reach terminal programs
instead of composing macOS layout characters.
This app-written preference is included in the private settings history.

Choose the host in Rex before opening a recent project.
The launcher uses that host's zoxide history and fzf,
then reuses or creates a shell session for the selected directory.
Its private host-local registry records canonical paths and session IDs.
Cancellation returns to the previous session.
It does not create or remove Git/JJ workspaces.

Normal Rex windows route to T.
Meh+9 shows btop in the Rex window on T as the `ops` session;
pressing it again restores the previous session and workspace.
Quitting btop ends the `ops` session.

## NAS connections and startup

The workstation follows its local Rex home server for shortcuts and hosts.
The host template declares CerpacNAS and DriehuisNAS using their dedicated
`rex-cerpacnas` and `rex-driehuisnas` Tailscale identities.
In this beta,
also add each HTTPS address once through Rex's Add Remote Host interface;
the CLI/config host list does not populate the app's private host list.
Rex reconnects to configured hosts when the app opens.
The NAS servers run under the existing `root` and `server` accounts.

CerpacNAS uses a lingering systemd user service named `rex-nas.service`.
DriehuisNAS uses `com.ezra.rex-nas` in launchd's system domain,
with `UserName=server` and explicit home, shell and state paths.
These identities remain persistent;
short-lived Codex Cloud devices should use a separate ephemeral enrollment key.

Initial NAS setup is explicit:

```sh
mise -C ~/.config/mise run rex:setup
```

On DriehuisNAS,
setup installs the official signed app in `~/Applications` if it is absent.
Then register the boot daemon from an interactive administrator terminal:

```sh
mise -C ~/.config/mise run rex:install-daemon
```

Complete the one-time Tailscale sign-in for each server.
The installer refuses to replace an existing daemon silently
or stop an unrelated personal Rex server.

Inspect the existing server without starting another one:

```sh
mise -C ~/.config/mise run rex:status
```

Routine `dots up` stages updates for an already provisioned Linux server
without enabling, starting or restarting its service.
Mac app upgrades use Rex's app updater;
routine setup leaves the running app and server alone.
On a workstation without Rex,
`dots up` installs the pinned official Mac app without launching it.
Restart a server only when its processes can be interrupted.

Remote processes survive a client or network disconnect while the NAS server
keeps running.
Session restoration after a server restart does not resurrect running processes.
Cold-boot behavior needs verification at an approved NAS reboot;
initial service registration does not itself prove a reboot test.

## Configuration and appearance

Edit the linked Rex files or their sources under `dotfiles/.config/rex/`.
The host list renders from `templates/.config/rex/hosts.lua.tera`.
Neovim's editor-only RPC sockets and navigation requests use owner-private
directories under `~/.local/state/rex/`.
Navigation errors and ambiguous focus stop the handoff.

Rex appearance remains app-written state,
with private encrypted settings history.
The native Glass style and Use glass for panes option provide translucency.
The installed beta does not document a numeric background-opacity or blur control.

Catppuccin's Ghostty palettes are managed under `~/.config/rex/themes/`:
`catppuccin-latte.conf` for light mode and `catppuccin-mocha.conf` for dark mode.
Import them through Rex's Appearance settings and select each for its matching mode.
Keep appearance on Auto to follow macOS automatically.
The imported choices remain private app-written preferences;
routine updates deploy the files without resetting those choices.
Leave **Force theme palette for text** off so Neovim and other truecolor programs
retain their own RGB colors instead of being remapped into the terminal palette.
The upstream palettes and their license come from
[Catppuccin for Ghostty](https://github.com/catppuccin/ghostty).

Neovim uses the plugin's unambiguous `catppuccin-nvim` entry point,
because Neovim 0.12 also ships a built-in theme named `catppuccin`.
Its transparent-background callback preserves foreground colors and styles.
Typst references use peach and label definitions use teal,
with bold text to distinguish them from prose in both light and dark mode.

## References

- [Rex remote access](https://www.superlogical.com/rex/docs/linux/remote-access)
- [Rex Mac settings](https://www.superlogical.com/rex/docs/reference/mac-settings)
- [Window-manager runbook](window-manager-runbook.md)
