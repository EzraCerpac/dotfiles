#!/usr/bin/env bash

sketchybar --add event aerospace_workspace_change

workspace_presentation_dispatcher=(
  drawing=off
  updates=on
  script="$PLUGIN_DIR/space_windows.sh"
)

sketchybar --add item workspace.presentation left \
           --set workspace.presentation "${workspace_presentation_dispatcher[@]}" \
           --subscribe workspace.presentation aerospace_workspace_change front_app_switched

"$PLUGIN_DIR/workspace_presentation.sh"
