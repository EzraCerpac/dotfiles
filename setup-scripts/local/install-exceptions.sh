#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common"
failures=0
install_exception() {
    local name="$1" executable="$2"
    printf 'Installer exception: %s\n' "$name"
    if ! setup_mise exec -- "$executable" --install-only; then
        printf 'Failed installer exception: %s\n' "$name" >&2
        failures=$((failures + 1))
    fi
}
setup_each_exception install_exception
if [[ "$SETUP_PROFILE" == workstation ]]; then
    if ! setup_mise exec -- "$SETUP_ROOT/setup-scripts/setup/fix-codex-acp-mode" --install-only; then
        failures=$((failures + 1))
    fi
fi
[[ "$failures" -eq 0 ]]
