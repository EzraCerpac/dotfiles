#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/../local/common"

require_setup_profile workstation
mise_exec python3 "${SCRIPT_DIR}/../lib/jw-update.py" "$@"
