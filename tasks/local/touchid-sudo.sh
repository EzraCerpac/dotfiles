#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"
require_setup_profile workstation
require_macos

PAM_SUDO_LOCAL="/etc/pam.d/sudo_local"
PAM_TOUCH_ID_LINE="auth       sufficient     pam_tid.so"

if [[ -f "$PAM_SUDO_LOCAL" ]] && grep -qF "$PAM_TOUCH_ID_LINE" "$PAM_SUDO_LOCAL"; then
    echo "Touch ID for sudo is already enabled."
    exit 0
fi

tmp_file="$(mktemp "${TMPDIR:-/tmp}/sudo_local.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT
if [[ -f "$PAM_SUDO_LOCAL" ]]; then
    cp -p "$PAM_SUDO_LOCAL" "$tmp_file"
fi
printf '%s\n' "$PAM_TOUCH_ID_LINE" >> "$tmp_file"
if ! sudo install -m 0644 "$tmp_file" "$PAM_SUDO_LOCAL"; then
    echo "Could not update ${PAM_SUDO_LOCAL}; no file was replaced." >&2
    exit 1
fi
echo "Touch ID for sudo enabled in ${PAM_SUDO_LOCAL}."
