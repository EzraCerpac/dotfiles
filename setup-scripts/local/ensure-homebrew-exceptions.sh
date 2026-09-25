#!/usr/bin/env bash

set -euo pipefail
umask 077
[[ "$(uname -s)" == Darwin ]] || exit 0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SETUP_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
# NOTE: setup-scripts/local/common is intentionally not sourced here. Bootstrap hooks
# run before any profile is persisted on fresh clones, so this prerequisite
# must work without SETUP_PROFILE.
setup_error() {
    printf 'setup: %s\n' "$*" >&2
}
if [[ "$(uname -s)" != Darwin ]]; then
    echo "this task requires macOS" >&2
    exit 1
fi

# shellcheck source=../lib/brew-exception.sh
source "${SETUP_ROOT}/setup-scripts/lib/brew-exception.sh"

readonly installer_commit="8949852f785a3bacaba2a979d0790337950b0a4a"
readonly installer_sha256="25548e1da7930c1563dbbe2cb05834a4131c4da09234540b6fdac812fda3c287"
readonly installer_url="https://raw.githubusercontent.com/Homebrew/install/${installer_commit}/install.sh"

if brew_bin="$(find_real_brew)"; then
    printf 'Homebrew is already available: %s\n' "$brew_bin"
    exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    setup_error "Homebrew is missing. Re-run bootstrap in an interactive terminal so the official installer can request admin approval."
    exit 1
fi
if [[ -n "${NONINTERACTIVE:-}" || -n "${CI:-}" ]]; then
    setup_error "Homebrew is missing, but the environment requests non-interactive operation; rerun bootstrap in a normal interactive shell."
    exit 1
fi
for required_path in /usr/bin/curl /usr/bin/shasum /usr/bin/mktemp /usr/bin/awk /bin/bash; do
    [[ -x "$required_path" ]] || {
        setup_error "required macOS command is unavailable: ${required_path}"
        exit 1
    }
done

temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mise-homebrew-installer.XXXXXX")"
cleanup() {
    [[ -n "${temp_dir:-}" && -d "$temp_dir" ]] && rm -rf -- "$temp_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

installer="${temp_dir}/install.sh"
echo "Downloading the pinned official Homebrew installer (${installer_commit})"
/usr/bin/curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    --retry 2 --connect-timeout 15 --output "$installer" "$installer_url" || {
    setup_error "could not download the official Homebrew installer"
    exit 1
}
[[ -s "$installer" ]] || {
    setup_error "the downloaded Homebrew installer is empty"
    exit 1
}
actual_sha256="$(/usr/bin/shasum -a 256 "$installer" | /usr/bin/awk '{print $1}')"
[[ "$actual_sha256" == "$installer_sha256" ]] || {
    setup_error "Homebrew installer SHA-256 mismatch; refusing to execute downloaded content"
    exit 1
}
IFS= read -r first_line < "$installer"
[[ "$first_line" == '#!/bin/bash' ]] || {
    setup_error "downloaded content is not the expected Bash installer"
    exit 1
}
chmod 600 "$installer"

echo 'Starting the official installer. It may request your normal macOS admin approval.'
if ! /bin/bash "$installer"; then
    setup_error "the official Homebrew installer failed; review its output and retry after resolving the reported prerequisite"
    exit 1
fi

if ! brew_bin="$(find_real_brew)"; then
    setup_error "the installer completed, but no working Homebrew was found in /opt/homebrew or /usr/local"
    exit 1
fi
printf 'Homebrew is ready at %s\n' "$brew_bin"
echo 'This prerequisite task did not install or update any packages.'
