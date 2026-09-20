#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"

case "$SETUP_PROFILE" in
    nas)
        echo "NAS role keeps its current login shell unchanged."
        exit 0
        ;;
    delftblue)
        echo "DelftBlue role keeps its current login shell unchanged."
        exit 0
        ;;
esac

if command -v fish >/dev/null 2>&1; then
    shell_name=fish
    target_shell="$(command -v fish)"
elif command -v xonsh >/dev/null 2>&1; then
    shell_name=xonsh
    target_shell="$(command -v xonsh)"
else
    echo "No supported interactive shell is installed; install fish or xonsh first." >&2
    exit 1
fi

# Resolve the host's installed path after installer exceptions have run, then
# let native mise own /etc/shells and the account update.
setup_mise config set --file "$SETUP_ROOT/config.local.toml" bootstrap.user.login_shell "$target_shell"
setup_mise bootstrap user apply --yes
