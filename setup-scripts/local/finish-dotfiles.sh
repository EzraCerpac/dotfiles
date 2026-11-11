#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/common"


# mise keeps links whose declarations were removed. Every dotfiles apply runs
# this hook from the incoming source, including the apply at the end of a sync
# still executed by the previous source's code, so retirement lives here.
bash "$DOTS_HOME/lib/retire-dotfiles.sh" "$SETUP_ROOT"

# Expose skills installed for all agents (~/.agents/skills) to Claude Code.
bash "${SCRIPT_DIR}/link-agent-skills.sh"

# Dotfiles must already be applied. This only tightens the modes of explicit
# private destinations; it never changes linked source files or services.
"${SCRIPT_DIR}/private-permissions.sh"
