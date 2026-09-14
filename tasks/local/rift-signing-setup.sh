#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"
require_setup_profile workstation
require_macos
helper="${HOME}/.local/bin/rift-local-signing-setup"
require_executable "$helper"
mise_exec "$helper" "$@"
