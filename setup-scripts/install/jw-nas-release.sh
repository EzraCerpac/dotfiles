#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/../local/common"

require_setup_profile nas
install_if_missing=0
case "${1:-}" in
    "") ;;
    --if-missing) install_if_missing=1 ;;
    *) echo "usage: jw-nas-release.sh [--if-missing]" >&2; exit 2 ;;
esac
[[ "$#" -le 1 ]] || { echo "usage: jw-nas-release.sh [--if-missing]" >&2; exit 2; }
INSTALL_DIR="${JW_INSTALL_DIR:-${HOME}/.local/bin}"
INSTALL_PATH="${INSTALL_DIR}/jw"

if [[ "$install_if_missing" -eq 1 && ( -e "$INSTALL_PATH" || -L "$INSTALL_PATH" ) ]]; then
    [[ -f "$INSTALL_PATH" && -x "$INSTALL_PATH" ]] || {
        echo "existing jw is not executable: $INSTALL_PATH" >&2; exit 1;
    }
    current="$(mise_exec "$INSTALL_PATH" --version 2>/dev/null || true)"
    [[ "$current" == jw\ * ]] || {
        echo "existing destination does not identify as jw: $INSTALL_PATH" >&2; exit 1;
    }
    echo "Kept existing ${current} at ${INSTALL_PATH}"
    exit 0
fi

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64)
        VERSION="${JW_NAS_VERSION:-0.3.1}"
        EXPECTED_SHA256="${JW_NAS_SHA256:-d175a4922264c32378f538ed7b6382028df68ecd2eaec564e4db75e2361ae2f8}"
        ASSET_DIR="jj-waltz-x86_64-unknown-linux-musl"
        hash_command=(sha256sum)
        ;;
    Darwin/x86_64)
        VERSION="${JW_NAS_MAC_VERSION:-0.8.0}"
        EXPECTED_SHA256="${JW_NAS_MAC_SHA256:-706ac0782401172a885ad2493d1a2053192355807e6fb956984826ac75f77dda}"
        ASSET_DIR="jj-waltz-x86_64-apple-darwin"
        hash_command=(shasum -a 256)
        ;;
    Linux/aarch64|Linux/arm64)
        VERSION="${JW_NAS_LINUX_ARM_VERSION:-0.8.0}"
        EXPECTED_SHA256="${JW_NAS_LINUX_ARM_SHA256:-b3cf9b62eb7a82e242555e52b9fe8316a5638b84fc3a376c739eb6b6cce4d43b}"
        ASSET_DIR="jj-waltz-aarch64-unknown-linux-gnu"
        hash_command=(sha256sum)
        ;;
    Darwin/arm64|Darwin/aarch64)
        VERSION="${JW_NAS_MAC_ARM_VERSION:-0.8.0}"
        EXPECTED_SHA256="${JW_NAS_MAC_ARM_SHA256:-037cec4ffe875ffdf2ad9d09d98873d3362ddc4aad8cc7a8ffb781182d9168fc}"
        ASSET_DIR="jj-waltz-aarch64-apple-darwin"
        hash_command=(shasum -a 256)
        ;;
    *) echo "the NAS jw release installer supports Linux and macOS on x86_64 and ARM64" >&2; exit 1 ;;
esac
ASSET="${ASSET_DIR}.tar.gz"
BASE_URL="https://github.com/EzraCerpac/jj-waltz/releases/download/v${VERSION}"

[[ "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "jw release SHA-256 must be a pinned 64-character lowercase value" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v "${hash_command[0]}" >/dev/null 2>&1 || { echo "${hash_command[0]} is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }

mkdir -p "$INSTALL_DIR"
tmp_dir="$(mktemp -d "${INSTALL_DIR}/.jw-release.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
curl -fsSL "${BASE_URL}/${ASSET}" -o "${tmp_dir}/${ASSET}"
printf '%s  %s\n' "$EXPECTED_SHA256" "${tmp_dir}/${ASSET}" | "${hash_command[@]}" -c -

archive_entries="$(tar -tzf "${tmp_dir}/${ASSET}")"
member="${ASSET_DIR}/jw"
member_count=0
while IFS= read -r entry; do
    [[ "$entry" != "$member" ]] || member_count=$((member_count + 1))
done <<< "$archive_entries"
[[ "$member_count" -eq 1 ]] || { echo "release archive must contain exactly one jw binary" >&2; exit 1; }
member_details="$(tar -tvzf "${tmp_dir}/${ASSET}" "$member")"
[[ "${member_details:0:1}" == "-" ]] || { echo "release jw member is not a regular file" >&2; exit 1; }
# Stream the single verified member into our private staging directory. Other
# archive entries, including documentation, never become filesystem paths.
source_binary="${tmp_dir}/jw"
tar -xOzf "${tmp_dir}/${ASSET}" "$member" > "$source_binary"
chmod 700 "$source_binary"
require_executable "$source_binary"
expected_version="jw ${VERSION}"
actual_version="$(mise_exec "$source_binary" --version)"
[[ "$actual_version" == "$expected_version" ]] || {
    echo "release binary reports '${actual_version}', expected '${expected_version}'" >&2
    exit 1
}

if [[ -L "$INSTALL_PATH" ]]; then
    existing_target="$(realpath "$INSTALL_PATH" 2>/dev/null || true)"
    expected_target="$(realpath "$source_binary")"
    [[ "$existing_target" == "$expected_target" ]] || {
        echo "refusing to replace a jw symlink with another owner: $INSTALL_PATH" >&2
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

staged="${tmp_dir}/jw.install"
install -m 0755 "$source_binary" "$staged"
mv -f "$staged" "$INSTALL_PATH"
[[ "$(mise_exec "$INSTALL_PATH" --version)" == "$expected_version" ]]
echo "Installed ${actual_version} at ${INSTALL_PATH}"
