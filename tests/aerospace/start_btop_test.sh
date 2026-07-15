#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/dot_config/aerospace/bin/executable_start-btop"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export CALLS="$TEST_TMP/calls"
export WINDOW_STATE="$TEST_TMP/window"
export AEROSPACE="$TEST_TMP/aerospace"
export OPEN_BIN="$TEST_TMP/open"
export BTOP="$TEST_TMP/btop"
export WEZTERM_APP="$TEST_TMP/WezTerm.app"
export START_BTOP_LOCK_PATH="$TEST_TMP/start-btop.lock"
: >"$CALLS"

cat >"$AEROSPACE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
    list-windows)
        if [[ -e "$WINDOW_STATE" ]]; then
            printf '101\tWezTerm\tbtop\n'
        fi
        ;;
    list-workspaces)
        printf '3\n'
        ;;
    move-node-to-workspace | workspace)
        printf 'aerospace' >>"$CALLS"
        printf ' <%s>' "$@" >>"$CALLS"
        printf '\n' >>"$CALLS"
        ;;
    *)
        printf 'unexpected aerospace command: %s\n' "$*" >&2
        exit 1
        ;;
esac
EOF

cat >"$OPEN_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'open' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"
sleep "${FAKE_OPEN_DELAY:-0}"
touch "$WINDOW_STATE"
EOF

chmod +x "$AEROSPACE" "$OPEN_BIN"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_calls() {
    local expected=$1
    local actual
    actual=$(cat "$CALLS")
    [[ $actual == "$expected" ]] || fail "expected calls [$expected], got [$actual]"
}

rm -f "$WINDOW_STATE"
: >"$CALLS"
bash "$HELPER"
assert_calls $'open <-na> <'"$WEZTERM_APP"$'> <--args> <start> <--> <'"$BTOP"$'>\naerospace <move-node-to-workspace> <9> <--window-id> <101>\naerospace <workspace> <3>'

: >"$CALLS"
bash "$HELPER" --focus
assert_calls $'aerospace <move-node-to-workspace> <9> <--window-id> <101>\naerospace <workspace> <9>'

rm -f "$WINDOW_STATE"
: >"$CALLS"
FAKE_OPEN_DELAY=0.2 bash "$HELPER" &
first=$!
FAKE_OPEN_DELAY=0.2 bash "$HELPER" --focus &
second=$!
wait "$first"
wait "$second"
if [[ $(grep -c '^open ' "$CALLS") -ne 1 ]]; then
    fail "concurrent invocations launched more than one window"
fi
grep -q '^aerospace <workspace> <9>$' "$CALLS" || fail "waiting focus request did not switch to workspace 9"

printf 'start-btop tests passed\n'
