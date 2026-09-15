#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/../local/common"

require_setup_profile nas
MICROMAMBA_VERSION="2.8.1-0"
MICROMAMBA_SHA256="9689782d863c05a1bf5d2d371ba527104e7a4eb4310c1637d8653b751aed9c82"
MICROMAMBA_URL="https://github.com/mamba-org/micromamba-releases/releases/download/${MICROMAMBA_VERSION}/micromamba-linux-64"
LOCAL_BIN="${HOME}/.local/bin"
MICROMAMBA_PATH="${LOCAL_BIN}/micromamba"
GIT_PREFIX="${HOME}/.local/share/git-modern"
GIT_PATH="${GIT_PREFIX}/bin/git"
GIT_LINK="${LOCAL_BIN}/git"

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
    echo "the preserved CerpacNAS Git recipe supports Linux x86_64 only" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }

if [[ -L "$GIT_LINK" ]]; then
    existing_target="$(realpath "$GIT_LINK" 2>/dev/null || true)"
    expected_target="$(realpath "$GIT_PATH" 2>/dev/null || true)"
    link_value="$(readlink "$GIT_LINK")"
    [[ "$link_value" == "$GIT_PATH" || ( -n "$expected_target" && "$existing_target" == "$expected_target" ) ]] || {
        echo "refusing to replace conflicting git symlink: ${GIT_LINK} -> $(readlink "$GIT_LINK")" >&2
        exit 1
    }
elif [[ -e "$GIT_LINK" ]]; then
    echo "refusing to replace an existing git command at $GIT_LINK" >&2
    exit 1
fi

mkdir -p "$LOCAL_BIN"
tmp_dir="$(mktemp -d "${LOCAL_BIN}/.nas-git.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
curl -fsSL "$MICROMAMBA_URL" -o "${tmp_dir}/micromamba"
printf '%s  %s\n' "$MICROMAMBA_SHA256" "${tmp_dir}/micromamba" | sha256sum -c -
chmod 0755 "${tmp_dir}/micromamba"

if [[ -e "$MICROMAMBA_PATH" || -L "$MICROMAMBA_PATH" ]]; then
    [[ -f "$MICROMAMBA_PATH" && -x "$MICROMAMBA_PATH" && ! -L "$MICROMAMBA_PATH" ]] || {
        echo "refusing to replace unexpected micromamba path: $MICROMAMBA_PATH" >&2
        exit 1
    }
    existing_micromamba_version="$(mise_exec "$MICROMAMBA_PATH" --version 2>/dev/null || true)"
    [[ "$existing_micromamba_version" == *"${MICROMAMBA_VERSION%%-*}"* ]] || {
        echo "refusing to replace unexpected micromamba version: ${existing_micromamba_version:-unknown}" >&2
        exit 1
    }
fi
mv -f "${tmp_dir}/micromamba" "$MICROMAMBA_PATH"

if [[ -x "$GIT_PATH" ]]; then
    mise_exec "$MICROMAMBA_PATH" install -y -p "$GIT_PREFIX" -c conda-forge 'git>=2.41'
else
    if [[ -e "$GIT_PREFIX" && ! -d "$GIT_PREFIX" ]]; then
        echo "refusing to replace non-directory Git prefix: $GIT_PREFIX" >&2
        exit 1
    fi
    mise_exec "$MICROMAMBA_PATH" create -y -p "$GIT_PREFIX" -c conda-forge 'git>=2.41'
fi
require_executable "$GIT_PATH"

if [[ -L "$GIT_LINK" ]]; then
    existing_target="$(realpath "$GIT_LINK" 2>/dev/null || true)"
    expected_target="$(realpath "$GIT_PATH")"
    link_value="$(readlink "$GIT_LINK")"
    [[ "$link_value" == "$GIT_PATH" || "$existing_target" == "$expected_target" ]] || {
        echo "refusing to replace conflicting git symlink: ${GIT_LINK} -> $(readlink "$GIT_LINK")" >&2
        exit 1
    }
else
    ln -s "$GIT_PATH" "${tmp_dir}/git"
    mv "${tmp_dir}/git" "$GIT_LINK"
fi

echo "User-space Git ready: $(mise_exec "$GIT_LINK" --version)"
