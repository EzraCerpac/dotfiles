#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"

case "$SETUP_PROFILE" in
    workstation|delftblue) ;;
    nas)
        echo "NAS profile has no post-dotfiles permission work."
        exit 0
        ;;
esac

# Dotfiles must already be applied. This only tightens the modes of explicit
# private destinations; it never changes linked source files or services.
"${SCRIPT_DIR}/private-permissions.sh"
