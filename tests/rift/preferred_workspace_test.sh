#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/dotfiles/.local/bin/rift-preferred-workspace"
TEST_TMP=$(mktemp -d)
CALLS="$TEST_TMP/calls"
DISPLAY_JSON="$TEST_TMP/displays.json"
WINDOWS_DIR="$TEST_TMP/windows"
RIFT_CLI="$TEST_TMP/rift-cli"
OPEN_BIN="$TEST_TMP/open"
mkdir -p "$WINDOWS_DIR"
touch "$CALLS"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

cat >"$RIFT_CLI" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'rift-cli %s\n' "$*" >>"$CALLS"
case "$1:$2" in
    query:displays)
        cat "$DISPLAY_JSON"
        ;;
    query:windows)
        test "$3" = --space-id
        if test -f "$WINDOWS_DIR/$4.json"; then
            cat "$WINDOWS_DIR/$4.json"
        else
            printf '[]\n'
        fi
        ;;
    execute:display|execute:workspace)
        ;;
    *)
        exit 2
        ;;
esac
EOF

cat >"$OPEN_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'open %s\n' "$*" >>"$CALLS"
EOF
chmod +x "$RIFT_CLI" "$OPEN_BIN"

run_helper() {
    : >"$CALLS"
    env CALLS="$CALLS" DISPLAY_JSON="$DISPLAY_JSON" WINDOWS_DIR="$WINDOWS_DIR" \
        RIFT_CLI="$RIFT_CLI" OPEN_BIN="$OPEN_BIN" JQ=jq \
        /bin/bash "$HELPER" "$@"
}

has_call() {
    grep -Fqx "$1" "$CALLS"
}

not_has_call() {
    ! grep -Fqx "$1" "$CALLS"
}

set_displays() {
    printf '%s\n' "$1" >"$DISPLAY_JSON"
}

set_space_windows() {
    printf '%s\n' "$2" >"$WINDOWS_DIR/$1.json"
}

set_displays '[
  {"uuid":"internal","space":11,"is_builtin":true,"is_active_context":true,"frame":{"origin":{"x":0,"y":0}}}
]'
run_helper switch 4
has_call 'rift-cli execute display focus --uuid internal' || fail 'single-display fallback did not focus active display'
has_call 'rift-cli execute workspace switch 4' || fail 'switch did not select requested workspace'

set_displays '[
  {"uuid":"internal","space":11,"is_builtin":true,"is_active_context":true,"frame":{"origin":{"x":0,"y":0}}},
  {"uuid":"left","space":22,"is_builtin":false,"is_active_context":false,"frame":{"origin":{"x":1200,"y":0}}},
  {"uuid":"upper","space":33,"is_builtin":false,"is_active_context":false,"frame":{"origin":{"x":2400,"y":200}}},
  {"uuid":"lower","space":44,"is_builtin":false,"is_active_context":false,"frame":{"origin":{"x":2400,"y":300}}}
]'
run_helper switch 6
has_call 'rift-cli execute display focus --uuid lower' || fail 'rightmost external tie was not broken by greatest y'

set_displays '[
  {"uuid":"internal","name":"Built-in Retina Display","screen_id":1,"space":11,"is_active_context":true,"frame":{"origin":{"x":0,"y":0}}},
  {"uuid":"external","name":"Studio Display","screen_id":2,"space":22,"is_active_context":false,"frame":{"origin":{"x":1800,"y":0}}}
]'
run_helper switch 9
has_call 'rift-cli execute display focus --uuid external' || fail 'live-shaped display records did not select the external display'

set_displays '[
  {"uuid":"internal","space":11,"is_builtin":true,"is_active_context":true,"frame":{"origin":{"x":0,"y":0}}},
  {"uuid":"external","space":22,"is_builtin":false,"is_active_context":false,"frame":{"origin":{"x":1800,"y":0}}}
]'
set_space_windows 11 '[{"id":{"pid":1,"idx":101},"is_focused":true,"bundle_id":"com.apple.Safari","title":"Docs"}]'
run_helper move 9
has_call 'rift-cli execute display move-window --uuid external --window-id 101' || fail 'focused window was not moved to preferred display'
has_call 'rift-cli execute display focus --uuid external' || fail 'focused move did not focus target display'
has_call 'rift-cli execute workspace move-window 9 --follow 101' || fail 'focused move did not follow target workspace'

set_space_windows 11 '[
  {"id":{"pid":1,"idx":201},"is_focused":true,"bundle_id":"com.apple.Safari","title":"Docs"},
  {"id":{"pid":1,"idx":202},"is_focused":false,"bundle_id":"com.apple.Safari","title":"Other"}
]'
run_helper move 9 202
has_call 'rift-cli execute display move-window --uuid external --window-id 202' || fail 'explicit window index was not selected'
not_has_call 'rift-cli execute display move-window --uuid external --window-id 201' || fail 'explicit move used focused window instead'

set_space_windows 11 '[
  {"id":{"pid":2,"idx":301},"is_focused":false,"bundle_id":"com.apple.Music","title":"Library"},
  {"id":{"pid":2,"idx":302},"is_focused":true,"bundle_id":"com.apple.Music","title":"Music"}
]'
set_space_windows 22 '[]'
run_helper launch 13 com.apple.Music Music
has_call 'rift-cli execute display move-window --uuid external --window-id 302' || fail 'existing Music window was not reused'
has_call 'rift-cli execute workspace move-window 13 --follow 302' || fail 'existing Music window did not follow target workspace'
not_has_call 'open -a Music' || fail 'existing Music window caused a duplicate launch'
[[ "$(grep -c 'rift-cli query windows --space-id' "$CALLS")" -eq 2 ]] \
    || fail 'launch did not scan every managed display space'

set_space_windows 11 '[]'
set_space_windows 22 '[]'
run_helper launch 13 com.apple.Music Music
has_call 'rift-cli execute display focus --uuid external' || fail 'absent launch did not focus preferred display'
has_call 'rift-cli execute workspace switch 13' || fail 'absent launch did not switch workspace'
has_call 'open -a Music' || fail 'absent Music window was not launched'

set_displays '[
  {"uuid":"internal-a","space":11,"is_builtin":true,"is_active_context":true,"frame":{"origin":{"x":0,"y":0}}},
  {"uuid":"internal-b","space":22,"is_builtin":true,"is_active_context":true,"frame":{"origin":{"x":0,"y":0}}}
]'
if run_helper switch 1 >/dev/null 2>&1; then
    fail 'ambiguous active display was not rejected'
fi
if grep -q '^rift-cli execute' "$CALLS"; then
    fail 'ambiguous active display caused a focus or switch command'
fi

printf 'rift preferred-workspace tests passed\n'
