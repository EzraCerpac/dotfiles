#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"
require_setup_profile workstation
require_macos
helper="${HOME}/.local/bin/rift-local-install"
require_executable "$helper"
if [[ "${1:-}" == --activate ]]; then
    echo "Rift activation can stop the current manager and load the Rift LaunchAgent." >&2
    echo "This task is explicit; omit --activate to build and stage only." >&2
fi
mise_exec "$helper" "$@"
