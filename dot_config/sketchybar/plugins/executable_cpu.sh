#!/bin/sh

# The $NAME variable is passed from sketchybar and holds the name of
# the item invoking this script:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting

# Sum process CPU from ps. Cheaper than spawning top every update.
CPU_USAGE=$(ps -A -o %cpu= | awk '{sum += $1} END {printf "%.0f", sum}')

sketchybar --set "$NAME" label="${CPU_USAGE}%" icon.color=0xffffffff label.color=0xffffffff
