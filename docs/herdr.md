# Herdr terminal workflow

WezTerm is the terminal window; Herdr owns terminal organization and persistence:

- a **session** is one persistent Herdr server containing all local work
- a **workspace** is one project row in Herdr's left sidebar
- a **tab** is one activity inside a workspace
- a **pane** is a visible terminal split inside a tab
- a Rift workspace is a macOS window-management space and is unrelated to a Herdr workspace

New Herdr panes use Fish on both roles, including saved remote machines. Bootstrap
validates Fish's stable executable path and records it in ignored local mise
configuration, then renders Herdr's `terminal.default_shell`. Workstation keeps the
keybindings and plugins below; NAS gets only the shell settings. This does not
install Herdr on hosts that do not already use it.

Both bootstrap and `dots up` prepare and apply this setting after tools are installed,
then reload an already-running Herdr server. Existing installations migrate through
`dots up`; an account-shell change still belongs to explicit bootstrap.
Changing your account's login shell does not change an already-running Herdr
server's inherited `$SHELL`. After applying a changed Herdr configuration, run
`herdr server reload-config` on that machine (or
`herdr --machine cerpacnas server reload-config` from the Mac). New splits then use
the configured shell; existing panes keep running. No server restart is needed.
If bootstrap reports that the login-shell change needs administrator approval,
Herdr can still use Fish; finish the account step to make fresh SSH logins use it too.

Closing WezTerm or pressing `Ctrl-B`, then `q`, detaches the client without stopping pane processes. Opening WezTerm again reattaches to the local default session. Herdr does not pin workspace rows; an open `Remote shells` workspace stays in the sidebar because the session persists.

Useful keys all start with the default `Ctrl-B` prefix:

- `up` / `down`: Herdr Plus Projects / Quick Actions
- `t`: Picker Plus search across agents, remotes, workspaces, projects, sessions, and actions
- `left` / `right`: previous / next workspace
- `Alt-1..9`: switch workspace; `1..9`: switch tab
- `d`: close Herdr workspace; `Shift-d`: remove its `jw` checkout
- `h/j/k/l`: focus panes; `w`: workspace picker; `?`: full key help

Herdr Plus manages the reproducible project layouts under `~/.config/herdr/plugins/config/cloudmanic.herdr-plus/`. Use the `Remote shells` project for a local shell and a normal `ssh delftblue` tab. SSH keepalives reduce idle disconnects. DelftBlue still needs `kinit` on the login node when `/tudelft.net` credentials expire.

Picker Plus exposes `CerpacNAS` as a remote Herdr target. Its custom integration clears the inherited `HERDR_ENV` marker before running Herdr's remote handoff, while global nested launches remain disabled. It bootstraps a matching remote binary when needed and opens the NAS server's own persistent sidebar. The NAS session is separate from the local sidebar; detach it with `Ctrl-B`, then `q`.
