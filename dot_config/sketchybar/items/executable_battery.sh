#!/bin/bash

# Add battery item
sketchybar --add item battery right \
           --set battery update_freq=120 script="$PLUGIN_DIR/battery.sh" \
                     icon.color=$WHITE \
                     label.color=$WHITE \
                     label.shadow.drawing=off \
                     background.drawing=on \
                     background.color=$BACKGROUND_1 \
                     background.border_color=$BACKGROUND_2 \
                     padding_left=2 padding_right=2 \
                     icon.padding_left=10 icon.padding_right=10 \
                     label.padding_right=20 \
           --subscribe battery system_woke power_source_change mouse.entered mouse.exited.global
