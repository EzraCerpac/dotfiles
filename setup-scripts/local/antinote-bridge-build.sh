#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/common"

require_setup_profile workstation
require_macos

SOURCE_FILE="${SETUP_ROOT}/dotfiles/.local/share/personal-concierge/antinote-bridge/main.swift"
INSTALL_DIR="${HOME}/.local/libexec/antinote"
INSTALL_PATH="${INSTALL_DIR}/antinote"
STATE_DIR="${HOME}/.local/state/mise/antinote-bridge"
MARKER="${STATE_DIR}/source.sha256"
require_file "$SOURCE_FILE"

command -v shasum >/dev/null 2>&1 || { echo "shasum is required" >&2; exit 1; }
fingerprint="$(shasum -a 256 "$SOURCE_FILE" | awk '{print $1}')"
if [[ -f "$MARKER" && "$(<"$MARKER")" == "$fingerprint" && -x "$INSTALL_PATH" ]]; then
    echo "Antinote bridge is current (${fingerprint})"
    exit 0
fi

mkdir -p "$INSTALL_DIR" "$STATE_DIR"
if [[ -L "$INSTALL_PATH" ]]; then
    echo "refusing to replace a symlinked Antinote bridge: $INSTALL_PATH" >&2
    exit 1
fi
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/antinote-bridge.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "${build_dir}/module-cache"
mise_exec env SWIFT_MODULECACHE_PATH="${build_dir}/module-cache" swiftc \
    -O \
    -framework Foundation \
    -framework AppKit \
    -framework CryptoKit \
    -lsqlite3 \
    -module-cache-path "${build_dir}/module-cache" \
    "$SOURCE_FILE" \
    -o "${build_dir}/antinote"
chmod 0755 "${build_dir}/antinote"
mv "${build_dir}/antinote" "$INSTALL_PATH"

marker_tmp="$(mktemp "${STATE_DIR}/.source.XXXXXX")"
printf '%s\n' "$fingerprint" > "$marker_tmp"
chmod 0600 "$marker_tmp"
mv "$marker_tmp" "$MARKER"
echo "Built Antinote bridge at ${INSTALL_PATH}"
