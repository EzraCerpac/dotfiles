#!/bin/bash

STATE="$(echo "$INFO" | jq -r '.state')"
if [ "$STATE" = "playing" ]; then
  MEDIA="$(echo "$INFO" | jq -r '.title + " - " + .artist')"
  sketchybar --set "$NAME" label="$MEDIA" drawing=on icon.color=0xffffffff label.color=0xffffffff background.drawing=on
else
  sketchybar --set "$NAME" drawing=off background.drawing=off
fi
