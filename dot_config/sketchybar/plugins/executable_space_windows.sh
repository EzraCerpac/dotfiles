#!/usr/bin/env bash

set -euo pipefail

case "${SENDER:-}" in
  aerospace_workspace_change | front_app_switched)
    exec "$CONFIG_DIR/plugins/workspace_presentation.sh"
    ;;
esac
