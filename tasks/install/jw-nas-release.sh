#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/../local/common"

require_setup_profile nas
VERSION="${JW_NAS_VERSION:-0.3.1}"
EXPECTED_SHA256="${JW_NAS_SHA256:-d175a4922264c32378f538ed7b6382028df68ecd2eaec564e4db75e2361ae2f8}"
ASSET="jj-waltz-x86_64-unknown-linux-musl.tar.gz"
ASSET_DIR="jj-waltz-x86_64-unknown-linux-musl"
BASE_URL="https://github.com/EzraCerpac/jj-waltz/releases/download/v${VERSION}"
INSTALL_DIR="${JW_INSTALL_DIR:-${HOME}/.local/bin}"
INSTALL_PATH="${INSTALL_DIR}/jw"

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
    echo "the static NAS release installer supports Linux x86_64 only" >&2
    exit 1
}
[[ "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "JW_NAS_SHA256 must be a pinned 64-character lowercase SHA-256" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }

mkdir -p "$INSTALL_DIR"
tmp_dir="$(mktemp -d "${INSTALL_DIR}/.jw-release.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
curl -fsSL "${BASE_URL}/${ASSET}" -o "${tmp_dir}/${ASSET}"
printf '%s  %s\n' "$EXPECTED_SHA256" "${tmp_dir}/${ASSET}" | sha256sum -c -

archive_entries="$(tar -tzf "${tmp_dir}/${ASSET}")"
found_binary=0
while IFS= read -r entry; do
    case "$entry" in
        "${ASSET_DIR}/") ;;
        "${ASSET_DIR}/jw") found_binary=1 ;;
        *) echo "release archive has an unexpected entry: $entry" >&2; exit 1 ;;
    esac
done <<< "$archive_entries"
[[ "$found_binary" -eq 1 ]] || { echo "release archive does not contain jw" >&2; exit 1; }
tar -xzf "${tmp_dir}/${ASSET}" -C "$tmp_dir"
source_binary="${tmp_dir}/${ASSET_DIR}/jw"
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
