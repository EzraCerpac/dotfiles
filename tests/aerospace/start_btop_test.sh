#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/dot_config/aerospace/bin/executable_start-btop"
TEST_TMP=$(mktemp -d)

export CALLS="$TEST_TMP/calls"
export WINDOW_STATE="$TEST_TMP/window"
export AEROSPACE="$TEST_TMP/aerospace"
export OPEN_BIN="$TEST_TMP/open"
export BTOP="$TEST_TMP/btop"
export WEZTERM_APP="$TEST_TMP/WezTerm.app"
export START_BTOP_LOCK_PATH="$TEST_TMP/start-btop.lock"
export START_BTOP_TIMER_STATE="$TEST_TMP/start-btop.timer"
export START_BTOP_CLOSE_AFTER=60
export TIMER_DIR="$TEST_TMP/timers"
export TIMER_MODE=ignore
mkdir -p "$TIMER_DIR"
: >"$CALLS"

cleanup() {
    touch "$TIMER_DIR/stop"
    /bin/sleep 0.1
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

cat >"$AEROSPACE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
    list-windows)
        if [[ -e "$WINDOW_STATE" ]]; then
            printf '%s\tWezTerm\tbtop\n' "$(<"$WINDOW_STATE")"
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
    close)
        [[ ${2:-} == --window-id && -n ${3:-} ]] || {
            printf 'unexpected close command: %s\n' "$*" >&2
            exit 1
        }
        if [[ -e "$WINDOW_STATE" && $(<"$WINDOW_STATE") == "$3" ]]; then
            rm -f "$WINDOW_STATE"
        fi
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
/bin/sleep "${FAKE_OPEN_DELAY:-0}"
printf '%s\n' "${OPEN_WINDOW_ID:-101}" >"$WINDOW_STATE"
EOF

cat >"$TEST_TMP/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == 60 ]]; then
    case "$TIMER_MODE" in
        ignore)
            while [[ ! -e "$TIMER_DIR/stop" ]]; do
                /bin/sleep 0.01
            done
            ;;
        hold)
            mkdir -p "$TIMER_DIR"
            marker="$TIMER_DIR/$$"
            touch "$marker.started"
            while [[ ! -e "$TIMER_DIR/stop" && ! -e "$marker.release" ]]; do
                /bin/sleep 0.01
            done
            ;;
        *)
            printf 'unexpected TIMER_MODE: %s\n' "$TIMER_MODE" >&2
            exit 1
            ;;
    esac
    exit 0
fi

exec /bin/sleep "$@"
EOF
chmod +x "$AEROSPACE" "$OPEN_BIN" "$TEST_TMP/sleep"
export PATH="$TEST_TMP:$PATH"

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

timer_count() {
    find "$TIMER_DIR" -name '*.started' -type f -print | wc -l | tr -d ' '
}

wait_for_timer_count() {
    local expected=$1
    for _ in {1..100}; do
        [[ $(timer_count) -ge $expected ]] && return 0
        /bin/sleep 0.01
    done
    fail "expected at least $expected timer(s), got $(timer_count)"
}

wait_for_close() {
    local window_id=$1
    for _ in {1..100}; do
        grep -q "^aerospace <close> <--window-id> <$window_id>$" "$CALLS" && return 0
        /bin/sleep 0.01
    done
    fail "timer did not close btop window $window_id"
}

timer_marker() {
    find "$TIMER_DIR" -name '*.started' -type f -print | sort | sed -n "${1}p"
}

release_timer() {
    local marker=$1
    touch "${marker%.started}.release"
}

reset_timer_state() {
    touch "$TIMER_DIR/stop"
    /bin/sleep 0.05
    rm -f "$TIMER_DIR"/*
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

# A newly opened btop window gets a detached, one-minute close timer.
reset_timer_state
rm -f "$WINDOW_STATE"
: >"$CALLS"
export TIMER_MODE=hold
export OPEN_WINDOW_ID=201
bash "$HELPER" --focus &
timer_test_pid=$!
wait_for_timer_count 1
wait "$timer_test_pid"
if grep -q '^aerospace <close> <--window-id> <201>$' "$CALLS"; then
    fail "btop closed before the timer deadline"
fi
release_timer "$(timer_marker 1)"
wait_for_close 201
[[ ! -e "$WINDOW_STATE" ]] || fail "close command did not remove btop window state"

# Pressing the shortcut again resets the deadline for the same window.
reset_timer_state
rm -f "$WINDOW_STATE"
: >"$CALLS"
export TIMER_MODE=hold
export OPEN_WINDOW_ID=301
bash "$HELPER" --focus &
first_timer_pid=$!
wait_for_timer_count 1
wait "$first_timer_pid"

bash "$HELPER" --focus &
second_timer_pid=$!
wait_for_timer_count 2
wait "$second_timer_pid"
release_timer "$(timer_marker 1)"
/bin/sleep 0.1
if grep -q '^aerospace <close> <--window-id> <301>$' "$CALLS"; then
    fail "first timer closed btop after the deadline was reset"
fi
release_timer "$(timer_marker 2)"
wait_for_close 301
[[ $(grep -c '^aerospace <close> <--window-id> <301>$' "$CALLS") -eq 1 ]] || fail "deadline reset caused an unexpected number of closes"

# An old timer must not close a replacement window that has a different ID.
reset_timer_state
rm -f "$WINDOW_STATE"
: >"$CALLS"
export TIMER_MODE=hold
export OPEN_WINDOW_ID=401
bash "$HELPER" &
identity_timer_pid=$!
wait_for_timer_count 1
wait "$identity_timer_pid"
printf '402\n' >"$WINDOW_STATE"
release_timer "$(timer_marker 1)"
/bin/sleep 0.1
if grep -q '^aerospace <close> <--window-id> <401>$' "$CALLS"; then
    fail "old timer closed a replacement btop window"
fi
[[ $(<"$WINDOW_STATE") == 402 ]] || fail "replacement btop window was lost"

printf 'start-btop tests passed\n'
