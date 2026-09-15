#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/../local/common"

require_setup_profile workstation
HERDR_BIN="${HERDR_BIN:-${HOME}/.local/bin/herdr}"
require_executable "$HERDR_BIN"

plugins=(
    "cloudmanic.herdr-plus|cloudmanic/herdr-plus|013fe1667a638487004164955a01707584ab7b9e"
    "ezracerpac.jj-waltz|EzraCerpac/jj-waltz/plugins/herdr|fcc2d16d293d66dafbe6d64188370f9d01108ae7"
    "vim-herdr-navigation|paulbkim-dev/vim-herdr-navigation|53e318c772c4d3b7fbd904ac43bcf3e5b5d8b244"
    "herdr-picker-plus|thanhdat77/herdr-picker-plus|1a80beef4f4c217ba6052d5153f3dfe876a8ee1c"
)

for item in "${plugins[@]}"; do
    IFS='|' read -r plugin_id plugin_repo plugin_commit <<<"$item"
    # shellcheck disable=SC2016 # jq expands $id, not the surrounding shell.
    current_commit="$(mise_exec "$HERDR_BIN" plugin list --plugin "$plugin_id" --json |
        mise_exec jq -r --arg id "$plugin_id" \
            '.result.plugins[]? | select(.plugin_id == $id) | .source.resolved_commit // empty' |
        head -n 1)"
    if [[ "$current_commit" == "$plugin_commit" ]]; then
        echo "unchanged: ${plugin_id} (${plugin_commit})"
        continue
    fi

    echo "installing pinned Herdr plugin ${plugin_id} (${plugin_commit})"
    mise_exec "$HERDR_BIN" plugin install "$plugin_repo" --ref "$plugin_commit" --yes
done
