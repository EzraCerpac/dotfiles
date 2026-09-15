#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"

if [[ "${1:-}" == "--prepare-source" ]]; then
    if [[ "$#" -ne 1 ]]; then
        setup_error "usage: $0 [--prepare-source]"
        exit 2
    fi
    [[ "$SETUP_PROFILE" == workstation ]] || exit 0

    ssh_template="${SETUP_ROOT}/templates/.ssh/config.tera"
    if [[ -L "$ssh_template" || ! -f "$ssh_template" ]]; then
        setup_error "expected a regular SSH config template at $ssh_template"
        exit 1
    fi
    chmod 0600 "$ssh_template"
    echo "Prepared the SSH config template for private rendering."
    exit 0
elif [[ "$#" -gt 0 ]]; then
    setup_error "usage: $0 [--prepare-source]"
    exit 2
fi


ensure_private_directory() {
    local path="${1:?directory path required}"
    if [[ -L "$path" ]]; then
        setup_error "refusing to change permissions through symlinked directory: $path"
        return 1
    fi
    if [[ -e "$path" && ! -d "$path" ]]; then
        setup_error "expected a directory at $path"
        return 1
    fi
    mkdir -p "$path"
    chmod 0700 "$path"
}

secure_private_file() {
    local path="${1:?file path required}"
    local source_path="${2:-}"
    if [[ -L "$path" ]]; then
        if [[ -n "$source_path" ]]; then
            local actual_target expected_target
            actual_target="$(realpath "$path" 2>/dev/null || true)"
            expected_target="$(realpath "$source_path" 2>/dev/null || true)"
            if [[ -n "$expected_target" && "$actual_target" == "$expected_target" ]]; then
                chmod 0600 "$source_path"
                echo "secured declared source behind private link: $path"
                return 0
            fi
        fi
        setup_error "refusing to change permissions through unexpected symlink: $path"
        return 1
    fi
    [[ -f "$path" ]] || {
        setup_error "declared private config is missing or not a regular file: $path"
        return 1
    }
    chmod 0600 "$path"
}

if [[ "$SETUP_PROFILE" == workstation ]]; then
    ensure_private_directory "${HOME}/.ssh"
fi
ensure_private_directory "${HOME}/.config/jj"

# SSH config is rendered into a regular file. The two jj configs are public
# source symlinks today; if either is a regular host-local copy, keep it private.
if [[ "$SETUP_PROFILE" == workstation ]]; then
    secure_private_file "${HOME}/.ssh/config"
fi
secure_private_file "${HOME}/.config/jj/config.toml" \
    "${SETUP_ROOT}/dotfiles/.config/jj/config.toml"
secure_private_file "${HOME}/.config/jj/agent-config.toml" \
    "${SETUP_ROOT}/dotfiles/.config/jj/agent-config.toml"

echo "Private dotfile permissions verified for the ${SETUP_PROFILE} profile."
