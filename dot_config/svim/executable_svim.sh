#!/usr/bin/env sh

# This script is executed when either the mode changes,
# or the commandline changes. The variables $MODE and $CMDLINE hold the
# current editor mode and the current commandline content, respectively.

BLACK=0xff000000
STATE_FILE="${TMPDIR:-/tmp}/svim_prev_mode"

# Determine if mode changed since last update
PREV_MODE=""
if [ -f "$STATE_FILE" ]; then
  PREV_MODE=$(cat "$STATE_FILE" 2>/dev/null || true)
fi
MODE_CHANGED=0
if [ "$PREV_MODE" != "$MODE" ]; then
  MODE_CHANGED=1
fi

# Persist current mode for next invocation
printf "%s" "$MODE" > "$STATE_FILE" 2>/dev/null || true

# Mode label setup
if [ -n "$MODE" ]; then
  sketchybar \
    --set svim.mode \
      drawing=on \
      label="[$MODE]" \
      label.color=$BLACK \
      label.align=left \
      icon.drawing=off
else
  sketchybar \
    --set svim.mode \
      drawing=off \
      label=""
fi

# Cmdline: inline to the right of mode
# - Always disappear when mode changes
# - Otherwise show only when non-empty
if [ "$MODE_CHANGED" -eq 1 ]; then
  sketchybar \
    --set svim.cmdline \
      drawing=off \
      label=""
elif [ -n "$CMDLINE" ]; then
  sketchybar \
    --set svim.cmdline \
      drawing=on \
      label="$CMDLINE" \
      label.color=$BLACK \
      label.align=left \
      icon.drawing=off
else
  sketchybar \
    --set svim.cmdline \
      drawing=off \
      label=""
fi

# Note: Item creation and static config are defined in
# dot_config/sketchybar/items/executable_svim.sh (chezmoi destination without prefix).
