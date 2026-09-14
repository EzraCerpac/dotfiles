#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common"
install_exception() {
    local name="$1" executable="$2"
    printf 'Installer exception: %s\n' "$name"
    setup_mise exec -- "$executable" --install-only
}
setup_each_exception install_exception
if [[ "$SETUP_PROFILE" == workstation ]]; then
    setup_mise exec -- "$SETUP_ROOT/tasks/setup/fix-codex-acp-mode" --install-only
fi
