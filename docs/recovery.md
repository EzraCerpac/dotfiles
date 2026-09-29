# Recover app-written settings

The watcher saves selected app-written files locally in encrypted history.
When you want to publish those snapshots, run `dots backup`. On a replacement
machine, configure the private history connection and key, then follow
[the restore guide](history.md) and use `dots restore`.

For a fresh replacement, select the old identity on the **first** adoption, before
the machine receives a new identity. After installing mise with the installer
from the [README](../README.md#start-a-new-machine), run:

```sh
SETUP_RESTORE_MACHINE_ID=mac-primary SETUP_AGE_IDENTITY=/Volumes/Recovery/age-key.txt "$HOME/.local/bin/mise" -E workstation bootstrap --adopt EzraCerpac/dotfiles --skip services
```

Resume that same restoration with
`dots bootstrap --restore mac-primary --identity /Volumes/Recovery/age-key.txt`.
Restoration runs before the history watcher is enabled. A machine already enrolled
under a different identity refuses this operation. Keep an external backup of the
recovery key: encrypted history alone cannot recover it.

Bootstrap credentials live in an age-encrypted bundle, separate from settings
history. To capture your existing WakaTime and Himalaya configuration, use
`dots bundle create --from-live --output /tmp/bootstrap.json.age --recipient age1...`,
with your recovery key's public recipient. Review and move that ciphertext to
`encrypted/bootstrap.json.age`; the private key stays outside both repositories.
On the new machine, run `dots bootstrap --bundle /path/bootstrap.json.age --identity /path/key.txt`.
Changed private destination files are left for reconciliation.
The bundle's external identity path is remembered separately from the new
machine's history key. Keep that external key available when applying the bundle
again; a missing key defers private setup without replacing existing files.

For unattended account enrollment, the bundle's version-1 JSON `secrets` object
may also contain `tailscale_auth_key` and `github_token`. Create it from a private
JSON file with `dots bundle create --input /private/path/inputs.json --output /tmp/bootstrap.json.age --recipient age1...`.
Use a fresh one-use Tailscale key when preparing a machine; expired keys require
replacement or browser login. Do not put private JSON or identities in this repository.

`mise dot` is mise's native dotfile interface. For example,
`mise dot edit ~/.config/fish/config.fish` opens the managed source, and
`mise dot add -g --mode symlink ~/.config/new-app/config.toml` registers a new
hand-edited file. Application-written files use `mise dot track`; configure
encryption before their first sensitive snapshot. `dots` adds the broader
machine update, recovery, and bootstrap workflow around these native commands.

The repository already lives at mise's configuration directory, so the documented
self-managing configuration pattern would add unnecessary links here. Native
`--adopt` provides the persistent checkout used by both local and remote setup.

This private recovery history is separate from publishing your Fish source or
tool declarations with JJ. Keep age keys outside both repositories. The older
migration backups remain available; see [migration and rollback](migration.md).
