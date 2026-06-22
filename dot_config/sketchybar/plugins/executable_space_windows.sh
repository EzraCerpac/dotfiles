#!/usr/bin/env bash

source "$CONFIG_DIR/colors.sh"

reload_workspace_icon() {
  workspace="$1"
  apps=$(aerospace list-windows --workspace "$workspace" | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}')

  icon_strip=" "
  if [ "${apps}" != "" ]; then
    while read -r app
    do
      icon_strip+=" $($CONFIG_DIR/plugins/icon_map.sh "$app")"
    done <<< "${apps}"
  else
    icon_strip=" —"
  fi

  sketchybar --animate sin 10 --set "space.$workspace" label="$icon_strip"
}

if [ "$SENDER" = "aerospace_workspace_change" ]; then
  if [ -n "$AEROSPACE_PREV_WORKSPACE" ]; then
    reload_workspace_icon "$AEROSPACE_PREV_WORKSPACE"
  fi
  if [ -n "$AEROSPACE_FOCUSED_WORKSPACE" ]; then
    reload_workspace_icon "$AEROSPACE_FOCUSED_WORKSPACE"
  fi

  if [ -n "$AEROSPACE_FOCUSED_WORKSPACE" ]; then
    sketchybar --set "space.$AEROSPACE_FOCUSED_WORKSPACE" icon.highlight=true \
                           label.highlight=true \
                           background.border_color=$GREY
  fi

  if [ -n "$AEROSPACE_PREV_WORKSPACE" ]; then
    sketchybar --set "space.$AEROSPACE_PREV_WORKSPACE" icon.highlight=false \
                           label.highlight=false \
                           background.border_color=$BACKGROUND_2
  fi

  AEROSPACE_FOCUSED_MONITOR=$(aerospace list-monitors --focused | awk '{print $1}')
  AEROSPACE_WORKSPACES_FOCUSED_MONITOR=$(aerospace list-workspaces --monitor focused --empty no)
  AEROSPACE_EMPTY_WORKESPACE=$(aerospace list-workspaces --monitor focused --empty)

  for i in $AEROSPACE_WORKSPACES_FOCUSED_MONITOR; do
    sketchybar --set space.$i display=$AEROSPACE_FOCUSED_MONITOR
  done

  for i in $AEROSPACE_EMPTY_WORKESPACE; do
    sketchybar --set space.$i display=0
  done

  if [ -n "$AEROSPACE_FOCUSED_WORKSPACE" ]; then
    sketchybar --set "space.$AEROSPACE_FOCUSED_WORKSPACE" display=$AEROSPACE_FOCUSED_MONITOR
  fi

fi
