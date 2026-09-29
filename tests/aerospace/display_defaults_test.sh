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
AEROSPACE_DEFAULT_WORKSPACES_OPEN_BIN="$tmp/open" bash "$root/dotfiles/.local/bin/aerospace-default-workspaces"
test "$(<"$OPEN_CALL")" = "-g hammerspoon://aerospace-default-workspaces"

export AEROSPACE_DEFAULTS_TEST_ROOT="$root"
if ! command -v lua >/dev/null 2>&1; then
    echo "skip: display defaults Lua checks need lua"
    exit 77
fi
lua "$root/tests/aerospace/display_defaults_test.lua"
