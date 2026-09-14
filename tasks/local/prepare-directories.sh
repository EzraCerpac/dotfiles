#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common"
case "$SETUP_PROFILE" in
    workstation|nas) mkdir -p "$HOME/Projects" "$HOME/Scripts" "$HOME/.local/bin" "$HOME/.local/share" ;;
    delftblue) ;;
esac
