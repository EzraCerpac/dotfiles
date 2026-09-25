#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/common"


# Dotfiles must already be applied. This only tightens the modes of explicit
# private destinations; it never changes linked source files or services.
"${SCRIPT_DIR}/private-permissions.sh"
