#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

cat >"$tmp/open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"$OPEN_CALL"
EOF
chmod +x "$tmp/open"
export OPEN_CALL="$tmp/open-call"
AEROSPACE_DEFAULT_WORKSPACES_OPEN_BIN="$tmp/open" bash "$root/dot_local/bin/executable_aerospace-default-workspaces"
test "$(<"$OPEN_CALL")" = "-g hammerspoon://aerospace-default-workspaces"

export AEROSPACE_DEFAULTS_TEST_ROOT="$root"
lua "$root/tests/aerospace/display_defaults_test.lua"
