#!/bin/bash

# Add CPU item with black and white nerd font icon
sketchybar --add item cpu right \
  --set cpu icon=󰻠 \
             icon.color=$WHITE \
             label.color=$WHITE \
             label.shadow.drawing=off \
             background.drawing=on \
             background.color=$BACKGROUND_1 \
             background.border_color=$BACKGROUND_2 \
             padding_left=2 padding_right=2 \
             icon.padding_left=10 icon.padding_right=10 \
             label.padding_right=20 \
             update_freq=2 \
             script="$PLUGIN_DIR/cpu.sh" \
             --subscribe cpu mouse.entered mouse.exited.global
