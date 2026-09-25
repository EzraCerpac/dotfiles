# Linux bootstrap tests

`tests/linux-bootstrap.sh` checks the native `mise -E workstation bootstrap`
path in a disposable Fedora 44 Docker container by default. Ubuntu and Arch
remain optional diagnostics; they are not required for this migration.
It installs only the base prerequisites (`git`, `curl`, certificates,
and `sudo`) before installing the official mise 2026.9.7 binary. The binary
SHA-256 is checked against the digest published on the mise GitHub release for
the container's architecture.

Run the accepted Fedora baseline with:

```sh
tests/linux-bootstrap.sh
```

Only check its package prerequisites and mise binary:

```sh
tests/linux-bootstrap.sh --distro fedora --prepare-only
```

Full tests copy only `config.toml`, `setup-tasks.toml`, `config.workstation.toml`,
`mise.workstation.lock`, `locks/`, `dotfiles/`, `templates/`, `seeds/`,
and `setup-scripts/` into each container. They create the ordinary account
`workspace-user` at
`/workspace-user`, including the distribution's normal `/etc/skel` files, then
run the workstation bootstrap twice as that user with passwordless `sudo` for
system packages. This exercises safe adoption of byte-identical vendor defaults
and preserves real conflicts for diagnosis. The first pass explicitly selects
`workstation`; the second omits
`-E` to check that the selected role persisted. The test then executes
`node --version` through mise without `-E`. It checks fish syntax and starts an
interactive fish command to resolve and run Node, jj, and Python; it also runs
`jj --version`, `python3 --version`, and Neovim with `--clean --headless +q`.
Finally, it checks that `~/.ssh` and `~/.config/jj` are mode 0700, the SSH
config is 0600, and both resolved jj config files are 0600. It also runs a root
dry-run package plan to parse the same profile with root's own configuration
path; the full tool installation is performed only for `workspace-user`.
Each bootstrap invocation is bounded by `BOOTSTRAP_TIMEOUT_SECONDS` (default
3600 seconds); package setup, plan parsing, and the tool check have shorter
limits. Each test container is capped at two CPUs and 6 GiB of memory by
default; mise and Cargo also use at most two jobs during the workstation passes.
Override the container limits with `TEST_CONTAINER_CPUS` and
`TEST_CONTAINER_MEMORY` when needed.

The test uses no bind mounts, host home directory, or Docker socket in a
container. Every container has the label
`local.chezmoi.mise-migration.linux-bootstrap` with a run-specific value. The
script removes only containers carrying its own value after success, and
preserves failed containers for diagnosis. It never removes images or
containers that existed before the run.
Missing official base images may be downloaded and remain cached in Docker.

The script reports the container OS and architecture so results can be tied to
the actual image used. Ubuntu and Fedora use the Docker engine's native
architecture when available. The official Arch Linux image is x86_64; on an
ARM64 Docker engine it runs through Docker's emulation support and uses the x64
mise binary. In that emulated Arch container only, the harness sets pacman's
documented `DisableSandboxSyscalls` option because its downloader's seccomp
filter is incompatible with the emulated syscall layer; Docker's default
container seccomp policy remains enabled. This does not validate pacman under
native x86_64 hardware. On the ARM64 OrbStack engine used for validation,
Ubuntu 24.04 and Fedora 44 ran natively as ARM64, while Arch ran as emulated
x86_64. This is a bounded distro smoke test, not proof that every tool in the
workstation profile works on every Linux distribution or architecture.

A fresh full-profile run completed on 2026-09-15 from the workstation payload
at revision `08457fdf`, using a new Fedora 44 ARM64 container
`52bebb8b00e5` (image digest
`sha256:e402cca673711fee025f9ce21c6c08b1bd25ee26b3c482119c8675fbaaedbc85`).
The root package dry-run passed. The first bootstrap explicitly selected
`workstation` and installed all 67 native tools in 832.8 seconds; the separate
`typ2docx` installer exception built and verified its launcher. The second
bootstrap omitted `-E`, retained the workstation role, and completed with all
dotfiles already applied.

The representative Node, fish syntax and command-resolution, jj, Python,
headless Neovim, SSH/jj permission checks all passed. The test started with an
ordinary `/etc/skel` home and adopted only matching vendor defaults. Mise
warned that Grok's declared `agent` bin path was absent; a focused follow-up confirmed
`grok --help` works. The harness removed its labeled container and
successful-run logs. The pre-existing `openmaic-postgres-1` container remained
stopped and unchanged. Earlier 2026-09-14 reentrant runs and the separate
seven-tool fixture were preparatory checks; this fresh full run supersedes their
limitation.

An additional Arch Linux run completed incidentally on x86_64 under
ARM64 emulation. It passed both bootstrap invocations and built typ2docx 0.8.0
from source; it is not part of the accepted baseline and does not represent
native x86_64 hardware. A fresh Ubuntu full run was canceled at the user's
direction during its first workstation bootstrap after the root package
dry-run. Treat it as canceled, not as a failure or a completed Ubuntu result.
A normal script run always creates a new container. Record setup failures
against the distro and package backend that produced them. The NAS profile is
intentionally not bootstrapped on a host here; its configuration can be
schema-checked separately.

A separate focused Fedora 44 ARM64 fixture had also installed and executed the
seven late tool changes: Herdr 0.8.2, cargo-dist 0.33.0, StyLua 2.5.2, Trunk
0.21.14, Tytanic 0.4.1, Tokei 15.0.0, and Typst package-check at the pinned Git
revision. The two Cargo tools built with the declared Rust and sccache
prerequisites. Tytanic's static AArch64 binary ran on Fedora's glibc
environment. That container was removed after checking its task label.
