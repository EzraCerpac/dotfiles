#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/dot_local/bin/executable_wm-focus"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

FAKE_BIN="$TEST_TMP/bin"
CALLS="$TEST_TMP/calls"
FOCUSED_WINDOW="$TEST_TMP/focused-window"
mkdir -p "$FAKE_BIN"
: >"$CALLS"

export CALLS FOCUSED_WINDOW
export AEROSPACE_BIN="$FAKE_BIN/aerospace"
export HERDR_BIN_PATH="$FAKE_BIN/herdr"
export JQ=jq
export PATH="$FAKE_BIN:$PATH"

cat >"$AEROSPACE_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'aerospace' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"

case "${1:-}" in
    list-windows)
        cat "$FOCUSED_WINDOW"
        ;;
    focus)
        ;;
    *)
        exit 2
        ;;
esac
EOF

cat >"$HERDR_BIN_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'herdr' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"

case "${1:-}" in
    pane)
        case "${2:-}" in
            process-info)
                printf '%s\n' "${HERDR_PROCESS_JSON}"
                ;;
            neighbor)
                printf '%s\n' '{"result":{"neighbor":{"neighbor_pane_id":"pane-2"}}}'
                ;;
            focus)
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
    plugin)
        [[ ${HERDR_PLUGIN_FAIL:-0} -eq 0 ]]
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$AEROSPACE_BIN" "$HERDR_BIN_PATH"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_calls() {
    local expected=$1
    local actual
    actual=$(cat "$CALLS")
    [[ "$actual" == "$expected" ]] || fail "expected calls [$expected], got [$actual]"
}

reset_case() {
    : >"$CALLS"
    unset HERDR_PLUGIN_FAIL
    export HERDR_PROCESS_JSON='{"result":{"process_info":{"foreground_processes":[{"name":"nvim"}]}}}'
}

write_window() {
    printf '%s\t%s\n' "$1" "$2" >"$FOCUSED_WINDOW"
}

reset_case
write_window com.apple.Safari 'Docs'
bash "$HELPER" left
assert_calls $'aerospace <list-windows> <--focused> <--format> <%{app-bundle-id}%{tab}%{window-title}%{newline}>\naerospace <focus> <--boundaries> <all-monitors-outer-frame> <left>'

reset_case
write_window com.github.wez.wezterm 'Herdr thesis'
bash "$HELPER" RIGHT
assert_calls $'aerospace <list-windows> <--focused> <--format> <%{app-bundle-id}%{tab}%{window-title}%{newline}>\nherdr <pane> <process-info> <--current>\nherdr <plugin> <action> <invoke> <vim-herdr-navigation.right>'

reset_case
export HERDR_PROCESS_JSON='{"result":{"process_info":{"foreground_processes":[{"name":"bash"}]}}}'
write_window com.github.wez.wezterm 'herdr — c-002: main'
bash "$HELPER" down
assert_calls $'aerospace <list-windows> <--focused> <--format> <%{app-bundle-id}%{tab}%{window-title}%{newline}>\nherdr <pane> <process-info> <--current>\nherdr <pane> <neighbor> <--direction> <down> <--current>\nherdr <pane> <focus> <--direction> <down> <--current>'

reset_case
write_window com.github.wez.wezterm 'Herdr main'
bash "$HELPER" --from-nvim up
assert_calls $'aerospace <list-windows> <--focused> <--format> <%{app-bundle-id}%{tab}%{window-title}%{newline}>\nherdr <pane> <neighbor> <--direction> <up> <--current>\nherdr <pane> <focus> <--direction> <up> <--current>'

for fixture in \
    $'com.github.wez.wezterm\tbtop' \
    $'com.github.wez.wezterm\tGitlogue' \
    $'com.github.wez.wezterm\traw shell' \
    $'com.github.wez.wezterm\tHerdrStudio' \
    $'null\tHerdr legacy title'; do
    reset_case
    printf '%s\n' "$fixture" >"$FOCUSED_WINDOW"
    bash "$HELPER" right
    assert_calls $'aerospace <list-windows> <--focused> <--format> <%{app-bundle-id}%{tab}%{window-title}%{newline}>\naerospace <focus> <--boundaries> <all-monitors-outer-frame> <right>'
done

reset_case
write_window com.github.wez.wezterm 'Herdr editor'
export HERDR_PLUGIN_FAIL=1
bash "$HELPER" left
assert_calls $'aerospace <list-windows> <--focused> <--format> <%{app-bundle-id}%{tab}%{window-title}%{newline}>\nherdr <pane> <process-info> <--current>\nherdr <plugin> <action> <invoke> <vim-herdr-navigation.left>\naerospace <focus> <--boundaries> <all-monitors-outer-frame> <left>'

printf 'wm-focus AeroSpace tests passed\n'

