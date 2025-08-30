#!/bin/sh

# The $NAME variable is passed from sketchybar and holds the name of
# the item invoking this script:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting

# Get CPU usage percentage
CPU_USAGE=$(top -l 1 | grep -E "^CPU" | grep -o '[0-9]\+\.[0-9]\+% user' | sed 's/% user//')

if [ -z "$CPU_USAGE" ]; then
  # Fallback method using iostat
  CPU_USAGE=$(iostat -c 1 | tail -1 | awk '{print 100 - $6}' | cut -d. -f1)
fi

# Round to nearest integer
CPU_USAGE=$(printf "%.0f" "$CPU_USAGE")

sketchybar --set "$NAME" label="${CPU_USAGE}%" icon.color=0xffffffff label.color=0xffffffff
