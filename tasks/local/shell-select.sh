#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"

case "$SETUP_PROFILE" in
    nas)
        echo "NAS role keeps its current login shell unchanged."
        exit 0
        ;;
    delftblue)
        echo "DelftBlue role keeps its current login shell unchanged."
        exit 0
        ;;
esac

if command -v fish >/dev/null 2>&1; then
    shell_name=fish
    target_shell="$(command -v fish)"
elif command -v xonsh >/dev/null 2>&1; then
    shell_name=xonsh
    target_shell="$(command -v xonsh)"
else
    echo "No supported interactive shell is installed; install fish or xonsh first." >&2
    exit 1
fi

current_shell="${SHELL:-}"
if [[ "$(uname -s)" == Darwin ]] && command -v dscl >/dev/null 2>&1; then
    current_shell="$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}' || true)"
elif command -v getent >/dev/null 2>&1; then
    current_shell="$(getent passwd "$(id -un)" | cut -d: -f7 || true)"
fi

if ! grep -qF "$target_shell" /etc/shells 2>/dev/null; then
    echo "Adding ${target_shell} to /etc/shells (sudo may prompt)."
    if ! printf '%s\n' "$target_shell" | sudo tee -a /etc/shells >/dev/null; then
        echo "Could not update /etc/shells. Add this line, then rerun: ${target_shell}" >&2
        exit 1
    fi
fi

if [[ "$current_shell" == "$target_shell" ]]; then
    echo "${shell_name} is already the login shell."
    exit 0
fi

if chsh -s "$target_shell"; then
    echo "Login shell set to ${shell_name} (${target_shell}); open a new login session to use it."
else
    echo "Could not change the login shell. Run: chsh -s ${target_shell}" >&2
    exit 1
fi
