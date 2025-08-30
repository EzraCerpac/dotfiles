#!/bin/bash

# Add calendar item with black and white nerd font icon
sketchybar --add item calendar right \
  --set calendar icon=󰃭 \
  icon.font="Hack Nerd Font:Bold:17.0" \
  icon.color=$WHITE \
  label.color=$WHITE \
  label.shadow.drawing=off \
  background.drawing=on \
  background.color=$BACKGROUND_1 \
  background.border_color=$BACKGROUND_2 \
  padding_left=2 padding_right=2 \
  icon.padding_left=10 icon.padding_right=10 \
  label.padding_right=20 \
  update_freq=1 \
  script="$PLUGIN_DIR/calendar.sh" \
  --subscribe calendar mouse.entered mouse.exited.global
