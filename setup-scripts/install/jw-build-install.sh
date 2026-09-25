#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/../local/common"

require_setup_profile workstation
JJ_WALTZ_DIR="${JW_SOURCE_DIR:-${HOME}/Projects/jj-waltz}"
MANIFEST="${JJ_WALTZ_DIR}/Cargo.toml"
SOURCE_BINARY="${JJ_WALTZ_DIR}/target/release/jw"
INSTALL_DIR="${JW_INSTALL_DIR:-${HOME}/.local/bin}"
INSTALL_PATH="${INSTALL_DIR}/jw"

require_file "$MANIFEST"

echo "Building locked jj-waltz source from ${JJ_WALTZ_DIR}"
mise_exec cargo build --locked --release --manifest-path "$MANIFEST"
require_executable "$SOURCE_BINARY"

expected_version="$(awk '
    /^\[package\]$/ { package = 1; next }
    /^\[/ { package = 0 }
    package && /^version[[:space:]]*=/ {
        gsub(/[" ]/, "", $3)
        print $3
        exit
    }
' "$MANIFEST")"
actual_version="$(mise_exec "$SOURCE_BINARY" --version)"
[[ -n "$expected_version" && "$actual_version" == "jw ${expected_version}" ]] || {
    echo "built jw reports '${actual_version}', expected 'jw ${expected_version}'" >&2
    exit 1
}

mkdir -p "$INSTALL_DIR"
if [[ -L "$INSTALL_PATH" ]]; then
    existing_target="$(realpath "$INSTALL_PATH" 2>/dev/null || true)"
    source_target="$(realpath "$SOURCE_BINARY")"
    [[ "$existing_target" == "$source_target" ]] || {
        echo "refusing to replace jw symlink with another owner: ${INSTALL_PATH} -> $(readlink "$INSTALL_PATH")" >&2
        exit 1
    }
elif [[ -e "$INSTALL_PATH" ]]; then
    [[ -f "$INSTALL_PATH" && -x "$INSTALL_PATH" ]] || {
        echo "refusing to replace non-executable jw destination: $INSTALL_PATH" >&2
        exit 1
    }
    old_version="$(mise_exec "$INSTALL_PATH" --version 2>/dev/null || true)"
    [[ "$old_version" == jw\ * ]] || {
        echo "refusing to replace a destination that does not identify as jw: $INSTALL_PATH" >&2
        exit 1
    }
fi

staged="$(mktemp "${INSTALL_DIR}/.jw.XXXXXX")"
trap 'rm -f "$staged"' EXIT
install -m 0755 "$SOURCE_BINARY" "$staged"
mv -f "$staged" "$INSTALL_PATH"
trap - EXIT
[[ "$(mise_exec "$INSTALL_PATH" --version)" == "$actual_version" ]]
echo "Installed ${actual_version} at ${INSTALL_PATH}"
