#!/bin/bash

# Hybrid volume: icon+label plus hidden slider that animates on change/hover

# Base volume item (icon + numeric label)
sketchybar --add item volume right \
           --set volume script="$PLUGIN_DIR/volume.sh" \
                     icon.color=$WHITE \
                     label.color=$WHITE \
                     label.shadow.drawing=off \
                     background.drawing=on \
                     background.color=$BACKGROUND_1 \
                     background.border_color=$BACKGROUND_2 \
                     padding_left=2 padding_right=2 \
                     icon.padding_left=10 icon.padding_right=10 \
                     label.padding_right=20 \
           --subscribe volume volume_change mouse.entered mouse.exited.global

# Slider (initially width 0, no icon/label)
VOLUME_SLIDER_WIDTH=100
sketchybar --add slider volume_slider right \
           --set volume_slider script="$PLUGIN_DIR/volume.sh" \
                                 slider.width=0 \
                                 slider.knob=􀀁 \
                                 slider.background.height=5 \
                                 slider.background.corner_radius=3 \
                                 slider.background.color=0x66ffffff \
                                 slider.highlight_color=$WHITE \
                                 background.drawing=on \
                                 background.color=$BACKGROUND_1 \
                                 background.border_color=$BACKGROUND_2 \
                                 padding_left=2 padding_right=2 \
                                 icon.padding_left=10 icon.padding_right=10 \
                                 label.padding_right=20 \
                                 label.drawing=off \
                                 icon.drawing=off \
                                 updates=on \
           --subscribe volume_slider volume_change mouse.entered mouse.exited.global
