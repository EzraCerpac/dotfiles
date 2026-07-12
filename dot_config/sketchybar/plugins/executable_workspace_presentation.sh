#!/usr/bin/env bash

set -euo pipefail

if [[ ${WORKSPACE_PRESENTATION_LOCKED:-} != 1 ]]; then
  export WORKSPACE_PRESENTATION_LOCKED=1
  exec /usr/bin/lockf -k "${TMPDIR:-/tmp}/sketchybar-workspace-presentation.lock" /bin/bash "$0"
fi

source "$CONFIG_DIR/colors.sh"

readonly ICON_MAP="$CONFIG_DIR/plugins/icon_map.sh"

focused_workspace=$(aerospace list-workspaces --focused)
monitor_output=$(aerospace list-monitors)

workspace_ids=()
workspace_displays=()
workspace_labels=()
workspace_highlights=()

while IFS= read -r monitor_line; do
  [[ -n $monitor_line ]] || continue
  read -r monitor _ <<< "$monitor_line"

  workspace_output=$(aerospace list-workspaces --monitor "$monitor")
  empty_output=$(aerospace list-workspaces --monitor "$monitor" --empty)

  while IFS= read -r workspace; do
    [[ -n $workspace ]] || continue

    apps=$(aerospace list-windows --workspace "$workspace" \
      | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}')

    icon_strip=" —"
    if [[ -n $apps ]]; then
      icon_strip=" "
      while IFS= read -r app; do
        [[ -n $app ]] || continue
        icon=$("$ICON_MAP" "$app")
        icon_strip+=" $icon"
      done <<< "$apps"
    fi

    display=$monitor
    while IFS= read -r empty_workspace; do
      if [[ $workspace == "$empty_workspace" && $workspace != "$focused_workspace" ]]; then
        display=0
        break
      fi
    done <<< "$empty_output"

    highlight=false
    if [[ $workspace == "$focused_workspace" ]]; then
      highlight=true
    fi

    workspace_ids+=("$workspace")
    workspace_displays+=("$display")
    workspace_labels+=("$icon_strip")
    workspace_highlights+=("$highlight")
  done <<< "$workspace_output"
done <<< "$monitor_output"

bar_output=$(sketchybar --query bar)
existing_workspace_items=$(printf '%s\n' "$bar_output" \
  | sed -n 's/^[[:space:]]*"\(space\.[^"]*\)",*$/\1/p')

while IFS= read -r existing_item; do
  [[ -n $existing_item ]] || continue
  existing_workspace=${existing_item#space.}
  current=false
  for workspace in "${workspace_ids[@]}"; do
    if [[ $workspace == "$existing_workspace" ]]; then
      current=true
      break
    fi
  done

  if [[ $current == false ]]; then
    sketchybar --set "$existing_item" \
      display=0 \
      icon.highlight=false \
      label.highlight=false \
      background.border_color="$BACKGROUND_2"
  fi
done <<< "$existing_workspace_items"

for ((index = 0; index < ${#workspace_ids[@]}; index++)); do
  workspace=${workspace_ids[$index]}
  item="space.$workspace"

  if ! sketchybar --query "$item" >/dev/null 2>&1; then
    sketchybar --add item "$item" left \
               --subscribe "$item" mouse.clicked
  fi

  border_color=$BACKGROUND_2
  if [[ ${workspace_highlights[$index]} == true ]]; then
    border_color=$GREY
  fi

  sketchybar --set "$item" \
    icon="$workspace" \
    icon.highlight_color="$RED" \
    icon.highlight="${workspace_highlights[$index]}" \
    icon.padding_left=10 \
    icon.padding_right=10 \
    display="${workspace_displays[$index]}" \
    padding_left=2 \
    padding_right=2 \
    label="${workspace_labels[$index]}" \
    label.highlight="${workspace_highlights[$index]}" \
    label.padding_right=20 \
    label.color="$GREY" \
    label.highlight_color="$WHITE" \
    label.font="sketchybar-app-font:Regular:16.0" \
    label.y_offset=-1 \
    background.color="$BACKGROUND_1" \
    background.border_color="$border_color" \
    script="$CONFIG_DIR/plugins/space.sh"
done
