# Bootstrap validation — 20 September 2026

Implemented and checked against mise 2026.9.10.

- Fedora 44 ARM64: installed the workstation in a disposable container with
  home `/workspace-user`, fixed executable discovery for system-installed mise,
  then repeated bootstrap successfully. Both completed passes reported zero
  failures. JJ, GH, ripgrep, Neovim, and the newly built JW execute successfully.
  Root package planning was also checked. No other distribution was tested.
- Native SSH adoption: a separate disposable account at `/remote-home` adopted
  a small fixture repository over localhost SSH. Its source checkout and live
  symlink remained usable after mise removed its remote staging directory.
  This checks native adoption and cleanup, not a second complete workstation.
- Encrypted history: real age/mise fixtures cover encrypted checkpoints,
  profile separation, cross-home recovery, recipient changes, missing keys,
  permissions, and first fetch-only restoration. Public checkout history and
  the remote history tip remain unchanged during restore.
- Bootstrap bundle: real encryption/decryption, wrong keys, native secret/file
  rendering, private permissions, unchanged reapplication, destination drift,
  and symlink rejection pass with synthetic secrets. The approved live WakaTime
  and Himalaya bundle also decrypts and validates; its identity remains external.
- Maintenance: updater and short-command tests pass, including Herdr handoff
  success/failure and preserving the running server after an upgrade failure.
- Tailscale: fixture tests cover connected no-op, private temporary key cleanup,
  expired keys, and an unavailable backend. The live Mac check left its existing
  connection unchanged. Native Fedora repository/package installation and a
  second unchanged installation passed with Tailscale 1.102.4. No real
  new-device enrollment was performed.
- Fish: two isolated sessions retain separate arrow history without modifying
  existing saved history. Atuin's independent recording and Ctrl-R remain enabled.
- Mac preferences: captured values match this Mac. No Dock/Finder relaunch was
  performed. Keyboard provisioning fixtures pass; the live held Kanata 1.12.0
  now runs through the owner-session gate with its native lock-screen poller.
  The user confirmed normal remapping before and after lock/unlock; the live
  log also records grab pause and resumption. Fast user switching was tested
  through a console-UID fixture, not with a second physical Mac account.
- Herdr: live handoff to the mise-owned 0.9.1 executable completed and server
  status reports matching version and compatible protocol.

Fresh-machine follow-up remains explicit: supply private recovery credentials,
select Fish interactively where account authorization is needed, install/start
Tailscale on Linux hosts outside the tested Fedora path, and complete OS permission
or account prompts. Containers without a user service supervisor use explicit
history snapshots. Fedora bootstrap installs Tailscale and starts its vendor
service when systemd is running; ordinary updates never start a service.
Signed local desktop applications retain their separate build
and permission workflows.

CerpacNAS was not contacted. No pristine Mac installation, Intel Mac cutover,
second physical machine, or NAS deployment is claimed by these checks.
