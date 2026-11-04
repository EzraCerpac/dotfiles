# Rex terminal workflow

Rex is the daily terminal and multiplexer.
Its keymap, helpers and server definitions live in this setup source.
WezTerm and Herdr remain installed with their existing configuration and data
for rollback.

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
| Meh+9 | Open or reuse the dedicated Ops btop window |

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
The Ops helper creates its own native window on 9;
it never selects a session in an existing work window.
Hidden Ops windows expire after the existing timer interval,
but cleanup stops if the window or session has acquired other work.

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

## References

- [Rex remote access](https://www.superlogical.com/rex/docs/linux/remote-access)
- [Rex Mac settings](https://www.superlogical.com/rex/docs/reference/mac-settings)
- [Window-manager runbook](window-manager-runbook.md)
