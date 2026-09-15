#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

grep -Fq $'BoringNotch\ttheboringteam.boringnotch' \
    "$ROOT/dotfiles/.local/bin/present" || fail "presentation mode does not manage BoringNotch"

dock_defaults="$(awk '
    $0 == "[bootstrap.macos.defaults.\"com.apple.dock\"]" { in_dock = 1; next }
    in_dock && /^\[/ { exit }
    in_dock { print }
' "$ROOT/config.workstation.toml")"
grep -Fqx 'static-only = true' <<<"$dock_defaults" || fail "Dock static-only setting is missing"
grep -Fqx 'expose-group-apps = true' <<<"$dock_defaults" || fail "Dock group-app setting is missing"
grep -Fqx 'enterMissionControlByTopWindowDrag = false' <<<"$dock_defaults" || \
    fail "top-edge Mission Control drag is not disabled"
if grep -Eq '^showMissionControlGestureEnabled[[:space:]]*=[[:space:]]*false$' <<<"$dock_defaults"; then
    fail "native vertical Mission Control fallback is disabled"
fi

printf 'window-manager refinement tests passed\n'
