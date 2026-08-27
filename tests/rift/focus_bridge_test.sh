#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$ROOT/dot_local/bin/executable_wm-focus"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

FAKE_BIN="$TEST_TMP/bin"
CALLS="$TEST_TMP/calls"
WINDOWS="$TEST_TMP/windows.json"
mkdir -p "$FAKE_BIN"
: >"$CALLS"

export CALLS WINDOWS
export RIFT_CLI="$FAKE_BIN/rift-cli"
export HERDR_BIN_PATH="$FAKE_BIN/herdr"
export PATH="$FAKE_BIN:$PATH"

cat >"$RIFT_CLI" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'rift-cli' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"

if [[ ${1:-} == query && ${2:-} == windows ]]; then
    cat "$WINDOWS"
fi
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
chmod +x "$RIFT_CLI" "$HERDR_BIN_PATH"

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

reset_case
printf '%s\n' '[{"is_focused":true,"bundle_id":"com.apple.Safari","title":"Docs"}]' >"$WINDOWS"
bash "$HELPER" left
assert_calls $'rift-cli <query> <windows>\nrift-cli <execute> <window> <focus> <left>'

reset_case
printf '%s\n' '[{"is_focused":true,"bundle_id":"com.github.wez.wezterm","title":"Herdr thesis"}]' >"$WINDOWS"
bash "$HELPER" right
assert_calls $'rift-cli <query> <windows>\nherdr <pane> <process-info> <--current>\nherdr <plugin> <action> <invoke> <vim-herdr-navigation.right>'

reset_case
printf '%s\n' '[{"is_focused":true,"bundle_id":null,"title":"Herdr — c-002: main"}]' >"$WINDOWS"
bash "$HELPER" left
assert_calls $'rift-cli <query> <windows>\nherdr <pane> <process-info> <--current>\nherdr <plugin> <action> <invoke> <vim-herdr-navigation.left>'

reset_case
export HERDR_PROCESS_JSON='{"result":{"process_info":{"foreground_processes":[{"name":"bash"}]}}}'
bash "$HELPER" down
assert_calls $'rift-cli <query> <windows>\nherdr <pane> <process-info> <--current>\nherdr <pane> <neighbor> <--direction> <down> <--current>\nherdr <pane> <focus> <--direction> <down> <--current>'

reset_case
bash "$HELPER" --from-nvim up
assert_calls $'rift-cli <query> <windows>\nherdr <pane> <neighbor> <--direction> <up> <--current>\nherdr <pane> <focus> <--direction> <up> <--current>'

reset_case
printf '%s\n' '[{"is_focused":true,"bundle_id":"com.github.wez.wezterm","title":"btop"}]' >"$WINDOWS"
bash "$HELPER" right
assert_calls $'rift-cli <query> <windows>\nrift-cli <execute> <window> <focus> <right>'

reset_case
printf '%s\n' '[{"is_focused":true,"bundle_id":null,"title":"raw shell"}]' >"$WINDOWS"
bash "$HELPER" left
assert_calls $'rift-cli <query> <windows>\nrift-cli <execute> <window> <focus> <left>'

reset_case
printf '%s\n' '[{"is_focused":true,"bundle_id":"com.github.wez.wezterm","title":"Gitlogue"}]' >"$WINDOWS"
bash "$HELPER" right
assert_calls $'rift-cli <query> <windows>\nrift-cli <execute> <window> <focus> <right>'

printf 'wm-focus tests passed\n'
