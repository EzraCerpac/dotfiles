#!/usr/bin/env sh
# Mise captures stdout as a credential; never log or persist it here.
set -eu
host=${MISE_CREDENTIAL_HOST:-github.com}
data_dir=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}
# Avoid mise shims while mise itself is resolving GitHub authentication.
# The latest link survives ordinary gh upgrades without a versioned path.
for gh_bin in "$data_dir"/installs/gh/latest/bin/gh "$data_dir"/installs/gh/latest/*/bin/gh; do
    if [ -x "$gh_bin" ]; then
        exec "$gh_bin" auth token --hostname "$host"
    fi
done
# A fresh machine may already have gh from its native package manager.
exec gh auth token --hostname "$host"
