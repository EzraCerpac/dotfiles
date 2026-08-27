#!/usr/bin/env bash

sketchybar --add event aerospace_workspace_change
sketchybar --add event aerospace_mode_change

aerospace_mode=(
  drawing=off
  updates=on
  icon.drawing=off
  label.align=center
  label.color=$RED
  script="$PLUGIN_DIR/aerospace_mode.sh"
)

sketchybar --add item aerospace.mode left \
           --set aerospace.mode "${aerospace_mode[@]}" \
           --subscribe aerospace.mode aerospace_mode_change

NAME=aerospace.mode "$PLUGIN_DIR/aerospace_mode.sh"

workspace_presentation_dispatcher=(
  drawing=off
  updates=on
  script="$PLUGIN_DIR/space_windows.sh"
)

sketchybar --add item workspace.presentation left \
           --set workspace.presentation "${workspace_presentation_dispatcher[@]}" \
           --subscribe workspace.presentation aerospace_workspace_change front_app_switched

"$PLUGIN_DIR/workspace_presentation.sh"
