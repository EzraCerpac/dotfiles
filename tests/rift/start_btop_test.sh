#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/dot_local/bin/executable_start-btop"
TEST_TMP=$(mktemp -d)
export CALLS="$TEST_TMP/calls" WINDOW_STATE="$TEST_TMP/window" ACTIVE_WORKSPACE="$TEST_TMP/active"
export RIFT_CLI="$TEST_TMP/rift-cli" OPEN_BIN="$TEST_TMP/open" BTOP="$TEST_TMP/btop"
export WEZTERM_APP="$TEST_TMP/WezTerm.app" JQ=jq LOCKF=/usr/bin/lockf
export START_BTOP_LOCK_PATH="$TEST_TMP/lock" START_BTOP_TIMER_STATE="$TEST_TMP/timer"
export START_BTOP_CLOSE_AFTER=60 TIMER_DIR="$TEST_TMP/timers" TIMER_MODE=ignore
mkdir -p "$TIMER_DIR"; : >"$CALLS"; echo 3 >"$ACTIVE_WORKSPACE"
cleanup() { touch "$TIMER_DIR/stop"; /bin/sleep 0.1; rm -rf "$TEST_TMP"; }
trap cleanup EXIT

cat >"$RIFT_CLI" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rift-cli' >>"$CALLS"; printf ' <%s>' "$@" >>"$CALLS"; printf '\n' >>"$CALLS"
state_json() {
  IFS=$'\t' read -r pid idx wsid workspace bundle title <"$WINDOW_STATE"
  jq -n --argjson pid "$pid" --argjson idx "$idx" --argjson wsid "$wsid" --argjson workspace "$workspace" \
    --arg bundle "$bundle" --arg title "$title" \
    '{id:{pid:$pid,idx:$idx},title:$title,bundle_id:$bundle,window_server_id:$wsid,workspace:$workspace}'
}
case "$1:$2" in
  query:displays) jq -n '[{space:42,is_active_context:true}]' ;;
  query:workspaces)
    active=$(<"$ACTIVE_WORKSPACE")
    if test -e "$WINDOW_STATE"; then window=$(state_json); else window=null; fi
    jq -n --argjson active "$active" --argjson window "$window" \
      '[range(0;8) as $i | {index:$i,is_active:($i==$active),windows:(if $window != null and $window.workspace==$i then [$window] else [] end)}]'
    ;;
  query:window)
    if test "${RIFT_RESTARTED:-0}" = 1; then exit 1; fi
    test -e "$WINDOW_STATE"
    requested_pid=$(jq -r .pid <<<"$3"); requested_idx=$(jq -r .idx <<<"$3")
    if state_json | jq -e --argjson pid "$requested_pid" --argjson idx "$requested_idx" '.id.pid==$pid and .id.idx==$idx' >/dev/null; then
      state_json
    else
      exit 1
    fi
    ;;
  execute:workspace)
    case "$3" in
      move-window)
        target=$4; follow=false; shift 4
        while test "$#" -gt 0; do test "$1" = --follow && follow=true; shift; done
        IFS=$'\t' read -r pid old_idx wsid old_ws bundle title <"$WINDOW_STATE"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$old_idx" "$wsid" "$target" "$bundle" "$title" >"$WINDOW_STATE"
        if test "$follow" = true; then echo "$target" >"$ACTIVE_WORKSPACE"; fi
        ;;
      switch) echo "$4" >"$ACTIVE_WORKSPACE" ;;
      *) exit 2 ;;
    esac ;;
  execute:window)
    test "$3" = close && test "$4" = --window-server-id
    IFS=$'\t' read -r pid idx wsid ws bundle title <"$WINDOW_STATE"; test "$wsid" = "$5"
    rm -f "$WINDOW_STATE" ;;
  *) exit 2 ;;
esac
EOF
cat >"$OPEN_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'open' >>"$CALLS"; printf ' <%s>' "$@" >>"$CALLS"; printf '\n' >>"$CALLS"
/bin/sleep 0
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$OPEN_PID" "$OPEN_IDX" "$OPEN_WINDOW_SERVER_ID" \
  "$(<"$ACTIVE_WORKSPACE")" com.github.wez.wezterm btop >"$WINDOW_STATE"
EOF
cat >"$TEST_TMP/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if test "$1" = 60; then
  if test "$TIMER_MODE" = hold; then
    marker="$TIMER_DIR/$$"; touch "$marker.started"
    while test ! -e "$TIMER_DIR/stop" && test ! -e "$marker.release"; do /bin/sleep 0.01; done
  else
    while test ! -e "$TIMER_DIR/stop"; do /bin/sleep 0.01; done
  fi
  exit 0
fi
exec /bin/sleep "$@"
EOF
chmod +x "$RIFT_CLI" "$OPEN_BIN" "$TEST_TMP/sleep"; export PATH="$TEST_TMP:$PATH"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
wait_for_timer() {
  for i in $(seq 1 100); do
    find "$TIMER_DIR" -name '*.started' -type f -print -quit | grep -q . && return 0
    /bin/sleep 0.01
  done
  fail 'timer did not start'
}
wait_for_timer_count() {
  expected=$1
  for i in $(seq 1 100); do
    test "$(find "$TIMER_DIR" -name '*.started' -type f | wc -l | tr -d ' ')" -ge "$expected" && return 0
    /bin/sleep 0.01
  done
  fail "expected $expected timers"
}
stop_timers() { touch "$TIMER_DIR/stop"; /bin/sleep 0.05; rm -f "$TIMER_DIR"/* "$START_BTOP_TIMER_STATE"; rm -f "$TIMER_DIR/stop"; }

export OPEN_PID=701 OPEN_IDX=1701 OPEN_WINDOW_SERVER_ID=2701
rm -f "$WINDOW_STATE"; bash "$HELPER"
grep -q 'rift-cli <query> <displays>' "$CALLS" || fail 'did not query active display'
grep -q 'rift-cli <query> <workspaces> <--space-id> <42>' "$CALLS" || fail 'did not query native space'
grep -q 'rift-cli <execute> <workspace> <move-window> <5> <1701>' "$CALLS" || fail 'did not move to Ops'
grep -q 'rift-cli <execute> <workspace> <switch> <3>' "$CALLS" || fail 'did not restore workspace'
test "$(awk -F '\t' '{print NF}' "$START_BTOP_TIMER_STATE")" = 4 || fail 'timer state fields are wrong'
stop_timers

: >"$CALLS"; export OPEN_PID=702 OPEN_IDX=1702 OPEN_WINDOW_SERVER_ID=2702
echo 3 >"$ACTIVE_WORKSPACE"; rm -f "$WINDOW_STATE"; bash "$HELPER" --focus
grep -q 'rift-cli <execute> <workspace> <move-window> <5> <--follow> <1702>' "$CALLS" || fail 'focus did not follow'
if grep -q 'rift-cli <execute> <workspace> <switch>' "$CALLS"; then fail 'focus switched back'; fi
stop_timers

: >"$CALLS"; export TIMER_MODE=hold OPEN_PID=703 OPEN_IDX=1703 OPEN_WINDOW_SERVER_ID=2703
rm -f "$WINDOW_STATE"; bash "$HELPER" --focus; wait_for_timer
marker=$(find "$TIMER_DIR" -name '*.started' -type f -print -quit); touch "$(dirname "$marker")/$(basename "$marker" .started).release"
for i in $(seq 1 100); do
  grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2703>' "$CALLS" && break
  /bin/sleep 0.01
done
grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2703>' "$CALLS" || fail 'timer did not close btop'
test ! -e "$WINDOW_STATE" || fail 'close did not remove btop'; stop_timers

: >"$CALLS"; export TIMER_MODE=hold OPEN_PID=705 OPEN_IDX=1705 OPEN_WINDOW_SERVER_ID=2705
rm -f "$WINDOW_STATE"; bash "$HELPER" --focus; wait_for_timer
first_marker=$(find "$TIMER_DIR" -name '*.started' -type f -print -quit)
bash "$HELPER" --focus; wait_for_timer_count 2
second_marker=$(find "$TIMER_DIR" -name '*.started' -type f ! -path "$first_marker" -print -quit)
touch "$(dirname "$first_marker")/$(basename "$first_marker" .started).release"
/bin/sleep 0.1
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'reset timer closed btop too early'; fi
touch "$(dirname "$second_marker")/$(basename "$second_marker" .started).release"
for i in $(seq 1 100); do grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2705>' "$CALLS" && break; /bin/sleep 0.01; done
grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2705>' "$CALLS" || fail 'reset timer did not close btop'
test "$(grep -c 'rift-cli <execute> <window> <close>' "$CALLS")" = 1 || fail 'reset timer closed more than once'
stop_timers

: >"$CALLS"; printf '704\t1704\t2704\t5\tcom.github.wez.wezterm\tbtop\n' >"$WINDOW_STATE"
export TIMER_MODE=ignore OPEN_PID=704 OPEN_IDX=1704 OPEN_WINDOW_SERVER_ID=2704
bash "$HELPER" --focus; generation=$(cut -f4 "$START_BTOP_TIMER_STATE")
RIFT_RESTARTED=1 bash "$HELPER" --expire 704 1704 2704 "$generation"
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'restart caused unsafe close'; fi
printf 'start-btop Rift tests passed\n'
