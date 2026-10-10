# Mac idle sleep

On macOS, the `workstation` profile copies
`com.ezra.mac-idle-awake.plist` into the user's `~/Library/LaunchAgents`.
At login, launchd starts `/usr/bin/caffeinate -i` and keeps it running.
This prevents idle system sleep on battery and AC power. Display sleep and
screen locking keep their existing settings. The lid must remain open;
manual sleep, logout, shutdown and battery exhaustion can still suspend work.
Keeping the Mac awake increases battery use. NAS and Linux workstation profiles
do not select this agent.

Control it with the copied `awake` command:

```bash
awake off     # Stop it and keep it off across logins
awake on      # Enable it after login and start it now
awake status  # Show whether it is running
```

`awake enable` and `awake disable` are aliases for `on` and `off`. Repeating
`on` preserves a running agent; repeating `off` leaves it disabled. The default
command is `status`.

For initial setup, apply just these two files, then enable the agent:

```bash
mise -C ~/.config/mise bootstrap dotfiles apply ~/Library/LaunchAgents/com.ezra.mac-idle-awake.plist ~/.local/bin/awake
awake on
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
awake off
```

The disabled override remains across logins even if dotfiles reapplies the
plist. Run `awake on` to opt in again.
