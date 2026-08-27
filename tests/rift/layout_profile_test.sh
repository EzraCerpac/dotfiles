#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/dot_local/bin/executable_rift-layout-profile"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

cat >"$tmp/rift-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "query displays" ]]; then
    printf '%s\n' '[{"uuid":"built-in","space":11,"is_active_context":true},{"uuid":"external","space":22,"is_active_context":false}]'
    exit 0
fi
printf '%s\n' "$*" >>"${CALL_LOG:?}"
EOF
chmod +x "$tmp/rift-cli"
: >"$tmp/calls"

CALL_LOG="$tmp/calls" RIFT_CLI="$tmp/rift-cli" JQ=jq bash "$HELPER" traditional

grep -Fqx 'execute config set settings.layout.mode traditional' "$tmp/calls" \
    || fail "runtime default was not changed"
[[ "$(grep -c 'execute workspace set-layout .* traditional' "$tmp/calls")" -eq 16 ]] \
    || fail "not every workspace on both displays was updated"
[[ "$(grep -c 'execute display focus --uuid built-in' "$tmp/calls")" -eq 2 ]] \
    || fail "original display was not restored"
grep -Fqx 'execute display focus --uuid external' "$tmp/calls" \
    || fail "external display was not visited"

if CALL_LOG="$tmp/calls" RIFT_CLI="$tmp/rift-cli" JQ=jq bash "$HELPER" bsp >/dev/null 2>&1; then
    fail "unsupported profile was accepted"
fi

echo "rift layout-profile tests passed"
