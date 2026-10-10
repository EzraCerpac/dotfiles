# Mac idle sleep

The `host-mac-primary` workstation profile copies
`com.ezra.mac-idle-awake.plist` into the user's `~/Library/LaunchAgents`.
At login, launchd starts `/usr/bin/caffeinate -i` and keeps it running.
This prevents idle system sleep on battery and AC power. Display sleep and
screen locking keep their existing settings. The lid must remain open;
manual sleep, logout, shutdown and battery exhaustion can still suspend work.
Keeping the Mac awake increases battery use. NAS and other host profiles do
not select this agent.

Apply just this file, then load just this agent:

```bash
mise -C ~/.config/mise bootstrap dotfiles apply ~/Library/LaunchAgents/com.ezra.mac-idle-awake.plist
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ezra.mac-idle-awake.plist"
```

If the agent is already loaded, leave it running. Ordinary dotfile application
does not restart it. This copy is self-contained: its operation does not depend
on a repository checkout remaining available.

Inspect the job and its assertion:

```bash
launchctl print "gui/$(id -u)/com.ezra.mac-idle-awake"
pmset -g assertions
```

The running caffeinate PID should own `PreventUserIdleSystemSleep`, without a
display-sleep or AC-only system-sleep assertion. `RunAtLoad` and `KeepAlive` in
the installed plist provide persistence after login and restart after exit.

To roll back persistently without touching other jobs or power settings:

```bash
launchctl disable "gui/$(id -u)/com.ezra.mac-idle-awake"
launchctl bootout "gui/$(id -u)/com.ezra.mac-idle-awake"
```

The disabled override remains across logins even if dotfiles reapplies the
plist. To opt in again, run `launchctl enable` for that same service target,
then the `bootstrap` command above.
