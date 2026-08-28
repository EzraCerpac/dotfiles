#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/dot_local/bin/executable_start-btop"
TEST_TMP=$(mktemp -d)
export CALLS="$TEST_TMP/calls" WINDOW_STATE="$TEST_TMP/window" ACTIVE_WORKSPACE="$TEST_TMP/active"
export ACTIVE_DISPLAY="$TEST_TMP/active-display" DISPLAY_FIXTURE="$TEST_TMP/displays"
export RIFT_CLI="$TEST_TMP/rift-cli" OPEN_BIN="$TEST_TMP/open" BTOP="$TEST_TMP/btop"
export WEZTERM_APP="$TEST_TMP/WezTerm.app" JQ=jq LOCKF=/usr/bin/lockf
export START_BTOP_LOCK_PATH="$TEST_TMP/lock" START_BTOP_TIMER_STATE="$TEST_TMP/timer"
export START_BTOP_CLOSE_AFTER=60 TIMER_DIR="$TEST_TMP/timers" TIMER_MODE=ignore
mkdir -p "$TIMER_DIR"; : >"$CALLS"; echo 3 >"$ACTIVE_WORKSPACE"; echo built-in >"$ACTIVE_DISPLAY"
cleanup() { touch "$TIMER_DIR/stop"; /bin/sleep 0.1; rm -rf "$TEST_TMP"; }
trap cleanup EXIT

cat >"$RIFT_CLI" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rift-cli' >>"$CALLS"; printf ' <%s>' "$@" >>"$CALLS"; printf '\n' >>"$CALLS"
state_json() {
  IFS=$'\t' read -r pid idx wsid space workspace bundle app_name title <"$WINDOW_STATE"
  jq -n --argjson pid "$pid" --argjson idx "$idx" --arg wsid "$wsid" --argjson space "$space" --argjson workspace "$workspace" \
    --arg bundle "$bundle" --arg app_name "$app_name" --arg title "$title" '
      {
        id:{pid:$pid,idx:$idx},
        title:$title,
        bundle_id:(if $bundle == "null" then null else $bundle end),
        app_name:$app_name,
        window_server_id:(if $wsid == "null" then null else ($wsid | tonumber) end),
        space:$space,
        workspace:$workspace
      }'
}
display_json() {
  jq --arg active "$(<"$ACTIVE_DISPLAY")" 'map(. + {is_active_context:(.uuid==$active)})' "$DISPLAY_FIXTURE"
}
space_for_display() {
  local uuid=$1
  jq -er --arg uuid "$uuid" '.[] | select(.uuid==$uuid) | .space' "$DISPLAY_FIXTURE"
}
case "$1:$2" in
  query:displays) display_json ;;
  query:workspaces)
    if test "${RIFT_WORKSPACE_QUERY_FAIL:-0}" = 1; then exit 1; fi
    requested_space=$4
    active=$(<"$ACTIVE_WORKSPACE")
    if test -e "$WINDOW_STATE" && test "$(cut -f4 "$WINDOW_STATE")" = "$requested_space"; then window=$(state_json); else window=null; fi
    jq -n --argjson active "$active" --argjson window "$window" \
      '[range(0;14) as $i | {index:$i,is_active:($i==$active),windows:(if $window != null and $window.workspace==$i then [$window] else [] end)}]'
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
        IFS=$'\t' read -r pid old_idx wsid old_space old_ws bundle app_name title <"$WINDOW_STATE"
        target_space=$(space_for_display "$(<"$ACTIVE_DISPLAY")")
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$old_idx" "$wsid" "$target_space" "$target" "$bundle" "$app_name" "$title" >"$WINDOW_STATE"
        if test "$follow" = true && test "$old_ws" != "$target"; then echo "$target" >"$ACTIVE_WORKSPACE"; fi
        ;;
      switch) echo "$4" >"$ACTIVE_WORKSPACE" ;;
      *) exit 2 ;;
    esac ;;
  execute:window)
    case "$3" in
      close)
        test "$4" = --window-server-id
        IFS=$'\t' read -r pid idx wsid space ws bundle app_name title <"$WINDOW_STATE"; test "$wsid" = "$5"
        rm -f "$WINDOW_STATE" ;;
      focus)
        test "$4" = --window-id
        requested_pid=$(jq -r .pid <<<"$5"); requested_idx=$(jq -r .idx <<<"$5")
        IFS=$'\t' read -r pid idx wsid space ws bundle app_name title <"$WINDOW_STATE"
        test "$pid" = "$requested_pid" && test "$idx" = "$requested_idx" ;;
      *) exit 2 ;;
    esac ;;
  execute:display)
    case "$3" in
      focus)
        test "$4" = --uuid
        echo "$5" >"$ACTIVE_DISPLAY" ;;
      move-window)
        test "$4" = --uuid && test "$6" = --window-id
        target_space=$(space_for_display "$5")
        IFS=$'\t' read -r pid old_idx wsid old_space old_ws bundle app_name title <"$WINDOW_STATE"
        test "$old_idx" = "$7"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$old_idx" "$wsid" "$target_space" "$old_ws" "$bundle" "$app_name" "$title" >"$WINDOW_STATE" ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
EOF
cat >"$OPEN_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'open' >>"$CALLS"; printf ' <%s>' "$@" >>"$CALLS"; printf '\n' >>"$CALLS"
/bin/sleep 0
space=$(jq -er --arg uuid "$(<"$ACTIVE_DISPLAY")" '.[] | select(.uuid==$uuid) | .space' "$DISPLAY_FIXTURE")
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$OPEN_PID" "$OPEN_IDX" "$OPEN_WINDOW_SERVER_ID" \
  "$space" "$(<"$ACTIVE_WORKSPACE")" com.github.wez.wezterm WezTerm btop >"$WINDOW_STATE"
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
cat >"$DISPLAY_FIXTURE" <<'EOF'
[
  {"uuid":"built-in","space":42,"is_builtin":true,"frame":{"origin":{"x":0,"y":0}}},
  {"uuid":"external-left","space":43,"is_builtin":false,"frame":{"origin":{"x":-1600,"y":100}}},
  {"uuid":"external-right","space":44,"is_builtin":false,"frame":{"origin":{"x":1920,"y":180}}}
]
EOF
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
grep -q 'rift-cli <execute> <workspace> <move-window> <9> <1701>' "$CALLS" || fail 'did not move to Ops'
grep -q 'rift-cli <execute> <workspace> <switch> <3>' "$CALLS" || fail 'did not restore workspace'
test "$(awk -F '\t' '{print NF}' "$START_BTOP_TIMER_STATE")" = 4 || fail 'timer state fields are wrong'
stop_timers

: >"$CALLS"; export OPEN_PID=702 OPEN_IDX=1702 OPEN_WINDOW_SERVER_ID=2702
echo 3 >"$ACTIVE_WORKSPACE"; rm -f "$WINDOW_STATE"; bash "$HELPER" --focus
grep -q 'rift-cli <execute> <display> <focus> <--uuid> <external-right>' "$CALLS" || fail 'focus did not choose rightmost external display'
grep -q 'rift-cli <execute> <workspace> <move-window> <9> <--follow> <1702>' "$CALLS" || fail 'focus did not follow'
if grep -q 'rift-cli <execute> <workspace> <switch>' "$CALLS"; then fail 'focus switched back'; fi
stop_timers

: >"$CALLS"; export TIMER_MODE=hold OPEN_PID=703 OPEN_IDX=1703 OPEN_WINDOW_SERVER_ID=2703
rm -f "$WINDOW_STATE"; bash "$HELPER" --focus; wait_for_timer
marker=$(find "$TIMER_DIR" -name '*.started' -type f -print -quit)
echo 10 >"$ACTIVE_WORKSPACE"
touch "$(dirname "$marker")/$(basename "$marker" .started).release"
for i in $(seq 1 100); do
  grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2703>' "$CALLS" && break
  /bin/sleep 0.01
done
grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2703>' "$CALLS" || fail 'timer did not close btop'
test ! -e "$WINDOW_STATE" || fail 'close did not remove btop'; stop_timers

: >"$CALLS"; export TIMER_MODE=hold OPEN_PID=712 OPEN_IDX=1712 OPEN_WINDOW_SERVER_ID=2712
echo 3 >"$ACTIVE_WORKSPACE"; rm -f "$WINDOW_STATE"; bash "$HELPER" --focus; wait_for_timer
first_marker=$(find "$TIMER_DIR" -name '*.started' -type f -print -quit)
first_generation=$(cut -f4 "$START_BTOP_TIMER_STATE")
touch "$(dirname "$first_marker")/$(basename "$first_marker" .started).release"
wait_for_timer_count 2
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'active Ops closed btop'; fi
second_generation=$(cut -f4 "$START_BTOP_TIMER_STATE")
test "$second_generation" != "$first_generation" || fail 'active Ops did not replace timer generation'
bash "$HELPER" --expire 712 1712 2712 "$first_generation"
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'old timer generation closed btop'; fi
second_marker=$(find "$TIMER_DIR" -name '*.started' -type f ! -path "$first_marker" -print -quit)
touch "$(dirname "$second_marker")/$(basename "$second_marker" .started).release"
wait_for_timer_count 3
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'repeated active check closed btop'; fi
third_marker=$(find "$TIMER_DIR" -name '*.started' -type f ! -path "$first_marker" ! -path "$second_marker" -print -quit)
echo 10 >"$ACTIVE_WORKSPACE"
touch "$(dirname "$third_marker")/$(basename "$third_marker" .started).release"
for i in $(seq 1 100); do grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2712>' "$CALLS" && break; /bin/sleep 0.01; done
grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2712>' "$CALLS" || fail 'inactive Ops did not close deferred btop'
test ! -e "$WINDOW_STATE" || fail 'deferred close did not remove btop'; stop_timers

: >"$CALLS"; export TIMER_MODE=hold OPEN_PID=705 OPEN_IDX=1705 OPEN_WINDOW_SERVER_ID=2705
rm -f "$WINDOW_STATE"; bash "$HELPER" --focus; wait_for_timer
first_marker=$(find "$TIMER_DIR" -name '*.started' -type f -print -quit)
echo 10 >"$ACTIVE_WORKSPACE"
bash "$HELPER" --focus; wait_for_timer_count 2
test "$(<"$ACTIVE_WORKSPACE")" = 9 || fail 'existing btop did not switch to Ops'
grep -Fq 'rift-cli <execute> <window> <focus> <--window-id> <{"pid":705,"idx":1705}>' "$CALLS" \
  || fail 'existing btop was not focused by stable Rift identity'
second_marker=$(find "$TIMER_DIR" -name '*.started' -type f ! -path "$first_marker" -print -quit)
touch "$(dirname "$first_marker")/$(basename "$first_marker" .started).release"
/bin/sleep 0.1
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'reset timer closed btop too early'; fi
echo 10 >"$ACTIVE_WORKSPACE"
touch "$(dirname "$second_marker")/$(basename "$second_marker" .started).release"
for i in $(seq 1 100); do grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2705>' "$CALLS" && break; /bin/sleep 0.01; done
grep -q 'rift-cli <execute> <window> <close> <--window-server-id> <2705>' "$CALLS" || fail 'reset timer did not close btop'
test "$(grep -c 'rift-cli <execute> <window> <close>' "$CALLS")" = 1 || fail 'reset timer closed more than once'
stop_timers

: >"$CALLS"; printf '704\t1704\t2704\t44\t5\tcom.github.wez.wezterm\tWezTerm\tbtop\n' >"$WINDOW_STATE"
export TIMER_MODE=ignore OPEN_PID=704 OPEN_IDX=1704 OPEN_WINDOW_SERVER_ID=2704
bash "$HELPER" --focus; generation=$(cut -f4 "$START_BTOP_TIMER_STATE")
RIFT_RESTARTED=1 bash "$HELPER" --expire 704 1704 2704 "$generation"
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'restart caused unsafe close'; fi
test ! -e "$START_BTOP_TIMER_STATE" || fail 'restart left stale timer state'

stop_timers
: >"$CALLS"; printf '713\t1713\t2713\t44\t9\tcom.github.wez.wezterm\tWezTerm\tbtop\n' >"$WINDOW_STATE"
printf '713\t1713\t2713\tquery-failure\n' >"$START_BTOP_TIMER_STATE"
RIFT_WORKSPACE_QUERY_FAIL=1 bash "$HELPER" --expire 713 1713 2713 query-failure
if grep -q 'rift-cli <execute> <window> <close>' "$CALLS"; then fail 'workspace query failure closed btop'; fi
test ! -e "$START_BTOP_TIMER_STATE" || fail 'workspace query failure left stale timer state'

stop_timers
: >"$CALLS"; printf '706\t1706\t2706\t44\t5\tnull\tWezTerm\tbtop\n' >"$WINDOW_STATE"
bash "$HELPER" --focus
if grep -q '^open ' "$CALLS"; then fail 'missing bundle ID opened duplicate btop'; fi
grep -q 'rift-cli <query> <workspaces> <--space-id> <44>' "$CALLS" || fail 'did not scan the external native space'
grep -q 'rift-cli <execute> <workspace> <move-window> <9> <1706>' "$CALLS" || fail 'missing bundle ID was not reused'
grep -Fq 'rift-cli <execute> <window> <focus> <--window-id> <{"pid":706,"idx":1706}>' "$CALLS" \
  || fail 'missing bundle ID was not focused'
test -e "$START_BTOP_TIMER_STATE" || fail 'safe fallback identity did not schedule close'

stop_timers
: >"$CALLS"; printf '711\t1711\t2711\t42\t5\tcom.github.wez.wezterm\tWezTerm\tbtop\n' >"$WINDOW_STATE"
echo built-in >"$ACTIVE_DISPLAY"
bash "$HELPER" --focus
grep -q 'rift-cli <execute> <display> <move-window> <--uuid> <external-right> <--window-id> <1711>' "$CALLS" \
  || fail 'existing btop was not moved to the preferred display'
grep -q 'rift-cli <execute> <workspace> <move-window> <9> <1711>' "$CALLS" \
  || fail 'cross-display btop was not moved into Ops'
grep -Fq 'rift-cli <execute> <window> <focus> <--window-id> <{"pid":711,"idx":1711}>' "$CALLS" \
  || fail 'cross-display btop was not focused'

stop_timers
: >"$CALLS"; printf '707\t1707\tnull\t44\t5\tnull\tWezTerm\tbtop\n' >"$WINDOW_STATE"
bash "$HELPER" --focus
if grep -q '^open ' "$CALLS"; then fail 'missing WindowServer ID opened duplicate btop'; fi
grep -q 'rift-cli <execute> <workspace> <move-window> <9> <1707>' "$CALLS" || fail 'missing WindowServer ID was not reused'
grep -Fq 'rift-cli <execute> <window> <focus> <--window-id> <{"pid":707,"idx":1707}>' "$CALLS" \
  || fail 'missing WindowServer ID was not focused'
test ! -e "$START_BTOP_TIMER_STATE" || fail 'missing WindowServer ID scheduled unsafe close'

stop_timers
: >"$CALLS"; cp "$DISPLAY_FIXTURE" "$DISPLAY_FIXTURE.all"
jq '[.[] | select(.is_builtin == true)]' "$DISPLAY_FIXTURE.all" >"$DISPLAY_FIXTURE"
echo built-in >"$ACTIVE_DISPLAY"; rm -f "$WINDOW_STATE"
export OPEN_PID=710 OPEN_IDX=1710 OPEN_WINDOW_SERVER_ID=2710
bash "$HELPER" --focus
if grep -q 'external-' "$CALLS"; then fail 'single-display fallback tried to focus an external display'; fi
grep -q 'rift-cli <execute> <workspace> <move-window> <9> <--follow> <1710>' "$CALLS" || fail 'single-display fallback did not follow btop'
mv "$DISPLAY_FIXTURE.all" "$DISPLAY_FIXTURE"

stop_timers
: >"$CALLS"; printf '708\t1708\t2708\t44\t5\tnull\tNotWezTerm\tbtop\n' >"$WINDOW_STATE"
export OPEN_PID=709 OPEN_IDX=1709 OPEN_WINDOW_SERVER_ID=2709
bash "$HELPER" --focus
grep -q '^open ' "$CALLS" || fail 'impostor btop window was reused'
printf 'start-btop Rift tests passed\n'
