#!/bin/bash

# SVIM (SketchyBar + Neovim status) items
# Creates two right-side items:
#  - svim.mode: shows current mode (e.g., [NORMAL])
#  - svim.cmdline: shows current command, inline to the right of mode
# Styling: no icons, left-aligned labels, black text

BLACK=0xff000000

svim_mode=(
  label.align=center
  label.color=$BLACK
  icon.drawing=off
  padding_left=10
)

svim_cmdline=(
  drawing=off # hidden until a command is active
  label.align=left
  label.color=$BLACK
  icon.drawing=off
)

sketchybar \
  --add item svim.mode e \
  --set svim.mode "${svim_mode[@]}" \
  --add item svim.cmdline e \
  --set svim.cmdline "${svim_cmdline[@]}"
