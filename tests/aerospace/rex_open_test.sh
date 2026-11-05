#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/Rex Beta.app"
export PATH="$TEST_TMP/bin:$PATH" TEST_TMP
export REX_BIN="$TEST_TMP/bin/rex" AEROSPACE_BIN="$TEST_TMP/bin/aerospace"
export OPEN_BIN="$TEST_TMP/bin/open"
export SLEEP="$TEST_TMP/bin/sleep" REX_APP="$TEST_TMP/Rex Beta.app" REX_OPEN_LOCKED=1
export CALLS="$TEST_TMP/calls"

cat >"$REX_BIN" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
shift # --autostart=false
[[ "${1:-}" != --timeout ]] || shift 2
case "$1" in
    client)
        if [[ "$MODE" == multiple ]]; then count=2
        elif [[ "$MODE" == timeout || ! -e "$TEST_TMP/opened" ]]; then count=0
        else count=1; fi
        jq -n --argjson n "$count" '{clients: [range($n) | {client_id:("client:" + tostring),info:{kind:"app",platform:"macos"},connection_state:"connected",principal:{pid:123}}]}'
        ;;
    ls)
        if [[ -e "$TEST_TMP/created" ]]; then echo '{"sessions":[{"session_id":"session:new"}]}'
        else echo '{"sessions":[]}' ; fi
        ;;
    -C) echo native >>"$CALLS"; touch "$TEST_TMP/created" ;;
    session)
        if [[ "$2" == inspect ]]; then
            echo '{"label":"lively-cedar","windows":[{"window_id":"window:initial","layers":[{"blocks":[{"owner":"client:0"}]}]}]}'
        fi
        ;;
    run) echo '{"block_ids":["block:new"]}' ;;
    window) echo close-initial >>"$CALLS" ;;
    *) exit 2 ;;
esac
MOCK
cat >"$AEROSPACE_BIN" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    list-windows)
        if [[ "${2:-}" == --focused ]]; then echo 1
        elif [[ -e "$TEST_TMP/created" ]]; then printf '42\t123\tcom.superlogical.rex\tfish ~ - lively-cedar\t2\n'; fi
        ;;
    *) echo "aerospace $*" >>"$CALLS" ;;
esac
MOCK
cat >"$OPEN_BIN" <<'MOCK'
#!/usr/bin/env bash
printf 'open\n' >>"$CALLS"
touch "$TEST_TMP/opened"
MOCK
cat >"$SLEEP" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$TEST_TMP/bin/"*

export MODE=startup
result=$("$ROOT/dotfiles/.local/bin/rex-open" --title test --workspace T -- /bin/echo hello)
[[ "$result" == $'42\t123\tsession:new\tblock:new' ]]
grep -qx open "$CALLS"
grep -qx native "$CALLS"
grep -qx close-initial "$CALLS"

for MODE in timeout multiple; do
    export MODE
    rm -f "$TEST_TMP/opened" "$TEST_TMP/created"
    : >"$CALLS"
    if "$ROOT/dotfiles/.local/bin/rex-open" -- /bin/echo hello >/dev/null 2>&1; then
        echo "rex-open: $MODE unexpectedly succeeded" >&2; exit 1
    fi
    if [[ "$MODE" == timeout ]]; then
        grep -qx open "$CALLS" || { echo 'rex-open: timeout skipped app launch' >&2; exit 1; }
    elif grep -qx open "$CALLS"; then
        echo 'rex-open: multiple clients triggered app launch' >&2; exit 1
    fi
    if grep -qx native "$CALLS"; then
        echo "rex-open: $MODE created a native window" >&2; exit 1
    fi
done
printf 'rex-open startup tests passed\n'
