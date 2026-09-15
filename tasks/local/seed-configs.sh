#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common"
case "$SETUP_PROFILE" in
    workstation|nas) ;;
    delftblue) exit 0 ;;
esac
# Seed only missing files. Existing application preferences remain authoritative.
seed_file() {
    local relative="$1" source_file="$SETUP_ROOT/seeds/$1" target="$HOME/$1"
    [[ -e "$target" || -L "$target" ]] && return 0
    [[ -f "$source_file" ]] || return 1
    local previous_umask
    previous_umask="$(umask)"
    umask 077
    mkdir -p "$(dirname "$target")"
    # noclobber also protects a destination created after the initial check.
    (set -o noclobber; cat "$source_file" > "$target")
    umask "$previous_umask"
    printf 'Created default configuration: %s\n' "$relative"
}
seed_file .codex/config.toml
if [[ "$SETUP_PROFILE" == workstation ]]; then
    seed_file .config/nvim/lazyvim.json
    seed_file .pi/agent/settings.json
    if [[ "$(uname -s)" == Darwin ]]; then
        seed_file .config/aegis/config.json
        seed_file .config/karabiner/karabiner.json
    fi
fi
