#!/usr/bin/env bash

set -euo pipefail

source "$CONFIG_DIR/colors.sh"

mode="${MODE:-}"
if [[ -z "$mode" ]]; then
  mode=$(aerospace list-modes --current)
fi

case "$mode" in
  main)
    sketchybar --set "$NAME" drawing=off label.drawing=off
    ;;
  service)
    sketchybar --set "$NAME" drawing=on label.drawing=on label=SERVICE label.color="$RED"
    ;;
  *)
    sketchybar --set "$NAME" drawing=off label.drawing=off
    ;;
esac
