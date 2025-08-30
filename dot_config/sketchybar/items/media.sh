#!/bin/bash

sketchybar --add item media e \
  --set media label.max_chars=22 \
  icon.padding_left=0 \
  scroll_texts=on \
  icon=􀑪 \
  background.drawing=on \
  background.color=$BACKGROUND_1 \
  background.border_color=$BACKGROUND_2 \
  icon.color=$WHITE \
  label.color=$WHITE \
  label.shadow.drawing=off \
  padding_left=2 padding_right=2 \
  icon.padding_left=10 icon.padding_right=10 \
  label.padding_right=20 \
  script="$PLUGIN_DIR/media.sh" \
  --subscribe media media_change mouse.entered mouse.exited.global
