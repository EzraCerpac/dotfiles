#!/usr/bin/env sh
# Mise captures stdout as a credential; never log or persist it here.
set -eu
host=${MISE_CREDENTIAL_HOST:-github.com}
data_dir=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}
# Avoid mise shims while mise itself is resolving GitHub authentication.
# The latest link survives ordinary gh upgrades without a versioned path.
for gh_bin in "$data_dir"/installs/gh/latest/bin/gh "$data_dir"/installs/gh/latest/*/bin/gh; do
    if [ -x "$gh_bin" ]; then
        if "$gh_bin" auth token --hostname "$host" 2>/dev/null; then
            exit 0
        fi
        break
    fi
done
# A fresh machine may have gh from its native package manager. Do not recurse
# into a mise shim while mise itself is requesting authentication.
gh_bin=$(command -v gh 2>/dev/null || true)
case "$gh_bin" in
    ""|*/mise/shims/*) ;;
    *) if "$gh_bin" auth token --hostname "$host" 2>/dev/null; then exit 0; fi ;;
esac
# CerpacNAS already authenticates Git through its credential helper. Reuse that
# credential in memory; no new login, token file, or interactive prompt.
credential=$(printf 'protocol=https\nhost=%s\n\n' "$host" |
    GIT_TERMINAL_PROMPT=0 git -c credential.interactive=false credential fill 2>/dev/null) || exit 1
token=$(printf '%s\n' "$credential" | sed -n 's/^password=//p')
[ -n "$token" ] || exit 1
printf '%s\n' "$token"
