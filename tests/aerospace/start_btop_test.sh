#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/dot_local/bin/executable_start-btop"
TEST_TMP=$(mktemp -d)
FAKE_BIN="$TEST_TMP/bin"
mkdir -p "$FAKE_BIN" "$TEST_TMP/timers"
export CALLS="$TEST_TMP/calls"
export WINDOWS="$TEST_TMP/windows"
export FOCUSED_WORKSPACE="$TEST_TMP/focused-workspace"
export VISIBLE_WORKSPACES="$TEST_TMP/visible-workspaces"
export FULLSCREEN_CALLS="$TEST_TMP/fullscreen-calls"
export TIMER_PIDS="$TEST_TMP/timers/pids"
export TIMER_RELEASE="$TEST_TMP/timers/release"
export DAEMON_PID_FILE="$TEST_TMP/daemon-pid"
export AEROSPACE_BIN="$FAKE_BIN/aerospace"
export OPEN_BIN="$FAKE_BIN/open"
export LOCKF="$FAKE_BIN/lockf"
export PGREP="$FAKE_BIN/pgrep"
export SLEEP="$FAKE_BIN/sleep"
export JQ=jq
export START_BTOP_LOCK_PATH="$TEST_TMP/lock"
export START_BTOP_TIMER_STATE="$TEST_TMP/timer-state"
export START_BTOP_CLOSE_AFTER=60
export BTOP="$TEST_TMP/btop"
export WEZTERM_APP="$TEST_TMP/WezTerm.app"
export NEXT_WINDOW_ID=101 NEXT_APP_PID=701
export PATH="$FAKE_BIN:$PATH"

cleanup() {
    if [[ -f "$TIMER_PIDS" ]]; then
        while IFS= read -r pid; do kill "$pid" 2>/dev/null || true; done <"$TIMER_PIDS"
    fi
    touch "$TIMER_RELEASE"
    /bin/sleep 0.05
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

: >"$CALLS"
: >"$WINDOWS"
: >"$FULLSCREEN_CALLS"
: >"$TIMER_PIDS"
printf '3\n' >"$FOCUSED_WORKSPACE"
printf '900\n' >"$DAEMON_PID_FILE"
printf '[{"workspace":"2","monitorId":1}]\n' >"$VISIBLE_WORKSPACES"
printf '2\t200\tcom.example.Editor\tEditor\t3\n' >"$WINDOWS"

cat >"$AEROSPACE_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'aerospace' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"

has_arg() {
    local wanted=$1 arg
    shift
    for arg in "$@"; do [[ "$arg" == "$wanted" ]] && return 0; done
    return 1
}

case "${1:-}" in
    list-windows)
        [[ ${FAIL_WINDOWS:-0} -eq 0 ]] || exit 1
        if has_arg --focused "$@"; then
            cat "$FOCUSED_WORKSPACE"
        else
            cat "$WINDOWS"
        fi
        ;;
    list-workspaces)
        if [[ "${2:-}" == --monitor ]]; then
            [[ ${FAIL_VISIBLE:-0} -eq 0 ]] || exit 1
            cat "$VISIBLE_WORKSPACES"
        else
            cat "$FOCUSED_WORKSPACE"
        fi
        ;;
    move-node-to-workspace)
        [[ "$2" == --window-id ]]
        window_id=$3
        target_workspace=$4
        awk -F '\t' -v OFS='\t' -v id="$window_id" -v ws="$target_workspace" \
            '$1 == id { $5 = ws } { print }' "$WINDOWS" >"$WINDOWS.tmp"
        mv "$WINDOWS.tmp" "$WINDOWS"
        ;;
    fullscreen)
        printf '%s\n' "$*" >>"$FULLSCREEN_CALLS"
        ;;
    workspace)
        printf '%s\n' "$2" >"$FOCUSED_WORKSPACE"
        ;;
    focus)
        [[ "$2" == --window-id && "$3" =~ ^[0-9]+$ ]]
        ;;
    close)
        [[ "$2" == --window-id ]]
        window_id=$3
        awk -F '\t' -v id="$window_id" '$1 != id' "$WINDOWS" >"$WINDOWS.tmp"
        mv "$WINDOWS.tmp" "$WINDOWS"
        ;;
    *)
        exit 2
        ;;
esac
EOF

cat >"$OPEN_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'open' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"
workspace=$(<"$FOCUSED_WORKSPACE")
printf '%s\t%s\t%s\t%s\t%s\n' \
    "$NEXT_WINDOW_ID" "$NEXT_APP_PID" com.github.wez.wezterm btop "$workspace" >>"$WINDOWS"
EOF

cat >"$LOCKF" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'lockf' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"
[[ "$1" == -k ]]
shift 2
exec "$@"
EOF

cat >"$PGREP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -a && "$2" == -x && "$3" == AeroSpace ]]
cat "$DAEMON_PID_FILE"
EOF

cat >"$SLEEP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == 60 ]]; then
    printf '%s\n' "$$" >>"$TIMER_PIDS"
    while [[ ! -e "$TIMER_RELEASE" ]]; do /bin/sleep 0.01; done
else
    /bin/sleep 0.001
fi
EOF
chmod +x "$AEROSPACE_BIN" "$OPEN_BIN" "$LOCKF" "$PGREP" "$SLEEP"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

clear_calls() {
    : >"$CALLS"
}

run_helper() {
    bash "$HELPER" "$@"
}

run_expire_current() {
    local window_id app_pid bundle title workspace generation daemon_pid
    IFS=$'\t' read -r window_id app_pid bundle title workspace generation daemon_pid <"$START_BTOP_TIMER_STATE"
    run_helper --expire "$window_id" "$app_pid" "$bundle" "$title" "$generation" "$daemon_pid"
}

timer_generation() {
    awk -F '\t' '{ print $6 }' "$START_BTOP_TIMER_STATE"
}

wait_for_timer_count() {
    local expected=$1
    for _ in {1..100}; do
        if [[ -f "$TIMER_PIDS" ]] && [[ $(wc -l <"$TIMER_PIDS" | tr -d ' ') -ge $expected ]]; then
            return 0
        fi
        /bin/sleep 0.01
    done
    fail "expected $expected timer processes"
}

assert_no_close() {
    ! grep -q 'aerospace <close>' "$CALLS" || fail 'unexpected AeroSpace close'
}

# First launch inherits the current workspace, then moves only that window to Ops.
run_helper
grep -q '^open ' "$CALLS" || fail 'did not launch WezTerm btop'
grep -q 'aerospace <move-node-to-workspace> <--window-id> <101> <9>' "$CALLS" || fail 'did not move the new window to Ops'
grep -Fxq 'aerospace <fullscreen> <on> <--window-id> <101>' "$CALLS" || fail 'did not set fullscreen on the window id'
grep -q 'lockf <-k>' "$CALLS" || fail 'did not run under lockf'
if grep -q 'move-node-to-monitor\\|focus-monitor\\|aerospace <workspace> <9>\\|aerospace <focus>' "$CALLS"; then
    fail 'normal launch moved monitors or changed focus'
fi
awk -F '\t' '$1 == 101 && $5 == 9 { found = 1 } END { exit !found }' "$WINDOWS" || fail 'btop is not on workspace 9'
[[ $(awk -F '\t' '{ print NF }' "$START_BTOP_TIMER_STATE") -eq 7 ]] || fail 'timer state does not contain full identity and generation'
[[ $(awk -F '\t' '{ print $5 }' "$START_BTOP_TIMER_STATE") == 9 ]] || fail 'timer did not record Ops workspace'
[[ $(awk -F '\t' '{ print $7 }' "$START_BTOP_TIMER_STATE") == 900 ]] || fail 'timer did not record AeroSpace daemon pid'
first_generation=$(timer_generation)
wait_for_timer_count 1

# Reuse the same exact window; --focus selects Ops even when another workspace was active.
awk -F '\t' -v OFS='\t' '$1 == 101 { $5 = 3 } { print }' "$WINDOWS" >"$WINDOWS.tmp"
mv "$WINDOWS.tmp" "$WINDOWS"
printf '2\n' >"$FOCUSED_WORKSPACE"
clear_calls
run_helper --focus
[[ $(grep -c '^open ' "$CALLS" || true) -eq 0 ]] || fail 'reused btop opened another window'
grep -q 'aerospace <move-node-to-workspace> <--window-id> <101> <9>' "$CALLS" || fail 'reused window away from Ops was not moved back'
grep -q 'aerospace <workspace> <9>' "$CALLS" || fail '--focus did not select Ops'
grep -q 'aerospace <focus> <--window-id> <101>' "$CALLS" || fail '--focus did not focus by AeroSpace window id'
grep -Fxq 'aerospace <fullscreen> <on> <--window-id> <101>' "$CALLS" || fail 'reused btop was not kept fullscreen by id'
second_generation=$(timer_generation)
[[ "$second_generation" != "$first_generation" ]] || fail 'reuse did not replace the timer generation'
wait_for_timer_count 2

# Even when btop is already on Ops, --focus must select workspace 9.
printf '2\n' >"$FOCUSED_WORKSPACE"
clear_calls
run_helper --focus
if grep -q 'aerospace <move-node-to-workspace>' "$CALLS"; then fail 'already-correct Ops window was moved again'; fi
grep -q 'aerospace <workspace> <9>' "$CALLS" || fail '--focus skipped workspace 9 when btop was already there'
grep -q 'aerospace <focus> <--window-id> <101>' "$CALLS" || fail '--focus skipped the existing window id'
third_generation=$(timer_generation)
[[ "$third_generation" != "$second_generation" ]] || fail 'second reuse did not replace the timer generation'
wait_for_timer_count 3

# A stale timer generation cannot close a later reuse.
clear_calls
run_helper --expire 101 701 com.github.wez.wezterm btop "$first_generation" 900
assert_no_close
[[ -f "$WINDOWS" ]] || fail 'stale generation removed the windows file'

# Ops visible on a second monitor keeps the exact window and reschedules its timer.
printf '[{"workspace":"2","monitorId":1},{"workspace":"9","monitorId":2}]\n' >"$VISIBLE_WORKSPACES"
clear_calls
run_expire_current
fourth_generation=$(timer_generation)
[[ "$fourth_generation" != "$third_generation" ]] || fail 'visible Ops did not reschedule the timer'
assert_no_close
grep -q 'aerospace <list-workspaces> <--monitor> <all> <--visible> <--json>' "$CALLS" || fail 'timer did not query visible workspaces on all monitors'
wait_for_timer_count 4

# With Ops inactive, close only the exact btop window and keep unrelated windows.
printf '[{"workspace":"2","monitorId":1}]\n' >"$VISIBLE_WORKSPACES"
printf '303\t3030\tcom.github.wez.wezterm\tGitlogue\t2\n' >>"$WINDOWS"
clear_calls
run_expire_current
grep -q 'aerospace <close> <--window-id> <101>' "$CALLS" || fail 'inactive Ops did not close the confirmed btop window'
awk -F '\t' '$1 == 303 && $4 == "Gitlogue" { found = 1 } END { exit !found }' "$WINDOWS" || fail 'closing btop removed an unrelated WezTerm window'
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'completed timer state was not cleared'

# Changed title invalidates the saved identity and cancels closure.
printf '101\t701\tcom.github.wez.wezterm\tbtop\t9\n' >>"$WINDOWS"
clear_calls
run_helper
changed_generation=$(timer_generation)
awk -F '\t' -v OFS='\t' '$1 == 101 { $4 = "btop session" } { print }' "$WINDOWS" >"$WINDOWS.tmp"
mv "$WINDOWS.tmp" "$WINDOWS"
clear_calls
run_helper --expire 101 701 com.github.wez.wezterm btop "$changed_generation" 900
assert_no_close
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'changed identity left a live timer'

# A reused AeroSpace window id with a different application PID is not the same target.
awk -F '\t' -v OFS='\t' '$1 == 101 { $2 = 701; $4 = "btop"; $5 = 9 } { print }' "$WINDOWS" >"$WINDOWS.tmp"
mv "$WINDOWS.tmp" "$WINDOWS"
clear_calls
run_helper
awk -F '\t' -v OFS='\t' '$1 == 101 { $2 = 702 } { print }' "$WINDOWS" >"$WINDOWS.tmp"
mv "$WINDOWS.tmp" "$WINDOWS"
clear_calls
run_expire_current
assert_no_close
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'changed app PID left a live timer'

# Moving the window away from Ops cancels closure.
awk -F '\t' -v OFS='\t' '$1 == 101 { $2 = 701; $4 = "btop"; $5 = 9 } { print }' "$WINDOWS" >"$WINDOWS.tmp"
mv "$WINDOWS.tmp" "$WINDOWS"
clear_calls
run_helper
awk -F '\t' -v OFS='\t' '$1 == 101 { $5 = 3 } { print }' "$WINDOWS" >"$WINDOWS.tmp"
mv "$WINDOWS.tmp" "$WINDOWS"
clear_calls
run_expire_current
assert_no_close
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'window moved away from Ops left a live timer'

# A changed AeroSpace daemon PID cancels closure after a restart.
awk -F '\t' -v OFS='\t' '$1 == 101 { $4 = "btop"; $5 = 9 } { print }' "$WINDOWS" >"$WINDOWS.tmp"
mv "$WINDOWS.tmp" "$WINDOWS"
clear_calls
run_helper
restart_generation=$(timer_generation)
printf '901\n' >"$DAEMON_PID_FILE"
clear_calls
run_helper --expire 101 701 com.github.wez.wezterm btop "$restart_generation" 900
assert_no_close
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'daemon restart left a live timer'

# Failed identity queries also cancel without closing anything.
printf '900\n' >"$DAEMON_PID_FILE"
clear_calls
run_helper
query_generation=$(timer_generation)
export FAIL_WINDOWS=1
clear_calls
run_helper --expire 101 701 com.github.wez.wezterm btop "$query_generation" 900
unset FAIL_WINDOWS
assert_no_close
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'failed window query left a live timer'

# A workspace-query failure cancels instead of closing an uncertain target.
clear_calls
run_helper
visible_query_generation=$(timer_generation)
export FAIL_VISIBLE=1
clear_calls
run_helper --expire 101 701 com.github.wez.wezterm btop "$visible_query_generation" 900
unset FAIL_VISIBLE
assert_no_close
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'failed workspace query left a live timer'

# Without a confirmed AeroSpace daemon PID, do not arm an auto-close timer.
rm -f "$DAEMON_PID_FILE"
clear_calls
run_helper --focus
[[ ! -e "$START_BTOP_TIMER_STATE" ]] || fail 'missing daemon PID armed a timer'
assert_no_close

printf 'start-btop AeroSpace tests passed\n'
