# CerpacNAS setup

CerpacNAS uses `nas` plus the shared base. Its system is Debian 10, x86-64,
with glibc 2.28. System packages, mounts, containers, and network services stay
outside this setup's ownership.

Fish is the login shell, using the stable `~/.local/bin/fish` link to mise's
official standalone Fish release. The distro's `/usr/bin/fish` and system Git
remain installed. Git continues to use `~/.local/share/git-modern/bin/git`;
Codex continues to use the desktop host's standalone installation.

The ignored `config.local.toml` records this host's compatibility choices:

- Atuin and Delta use the official GitHub musl release assets and track latest.
- Neovim's prebuilt Aqua package is disabled. Its source build lives in
  `~/.local/share/neovim-built/current`, whose `bin` directory is added to PATH.
- `SETUP_NAS_NEOVIM_BUILD=1` enables the named source-build exception in
  `dots up`. It checks the latest release through mise, uses portable
  mise-managed CMake, builds with two jobs, and switches `current` only after
  a successful configuration-free startup. Old versions remain for rollback.
- OpenCode remains declared locally, preserving the existing NAS tool.

Private snapshots use `host-cerpacnas` in `EzraCerpac/dotfiles-state`.
The watcher saves locally; `dots backup` explicitly publishes them.
The NAS has its own age identity at `~/.config/age/keys.txt`, mode `0600`.
Snapshots also use the existing recovery public recipient. No Mac private key
was copied. Back up the NAS identity separately from either repository.

The Mac-only WakaTime/Himalaya bundle is optional on NAS. Supply a bundle
explicitly when this host needs private bootstrap inputs.

The protected migration backup is
`~/.local/state/mise-migration/nas-20260920T091845Z`.
It contains the old checkout, live configuration, file modes, mise/chezmoi
binaries, and the pre-cutover mount/container inventory. Keep it until rollback
is no longer needed. The old chezmoi checkout is recovery material; do not
apply it over the mise-owned files.

The user selected the current shared Neovim configuration. Existing app-written
settings, spelling additions, project checkouts, and dirty plugin checkouts
are retained. A plugin update must report dirty checkouts rather than reset them.

The legacy `nas.py` command and bundled NAS skill are retired. Use `dots` for
configuration and backups, normal JJ/JW commands for source work, and native
Codex Remote SSH for remote tasks. Their unused project manifest and rules
templates are also retired; existing project-owned `AGENTS.md` files are kept.
