#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

grep -Fq $'BoringNotch\ttheboringteam.boringnotch' \
    "$ROOT/dot_local/bin/executable_present" || fail "presentation mode does not manage BoringNotch"

mission_script="$ROOT/run_onchange_05-configure-mission-control.sh.tmpl"
[[ -f "$mission_script" ]] || fail "Mission Control run-on-change script is missing"
grep -Fq 'enterMissionControlByTopWindowDrag -bool false' "$mission_script" || \
    fail "top-edge Mission Control drag is not disabled"
if rg -q 'showMissionControlGestureEnabled.*false' "$mission_script"; then
    fail "native vertical Mission Control fallback is disabled"
fi

if rg -q 'move_boring_notch_to_trash|mv .*boringNotch' \
    "$ROOT/run_after_04-migrate-window-manager.sh.tmpl"; then
    fail "migration still moves BoringNotch to Trash"
fi

printf 'window-manager refinement tests passed\n'
