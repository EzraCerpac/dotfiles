#!/bin/sh

SLIDER_ITEM=volume
SLIDER_TARGET_WIDTH=100
CLOSE_DELAY=2
WHITE=0xffffffff

set_icon_and_label() {
  VOLUME="$1"
  case "$VOLUME" in
    [6-9][0-9]|100) ICON="󰕾" ;;
    [3-5][0-9]) ICON="󰖀" ;;
    [1-9]|[1-2][0-9]) ICON="󰕿" ;;
    *) ICON="󰖁" ;;
  esac
   sketchybar --set volume icon="$ICON" label="$VOLUME%" icon.color=0xffffffff label.color=0xffffffff

}

open_slider() {
  CUR_WIDTH="$(sketchybar --query $SLIDER_ITEM | jq -r '.slider.width')"
  if [ "$CUR_WIDTH" -eq 0 ]; then
    sketchybar --animate tanh 30 --set $SLIDER_ITEM slider.width=$SLIDER_TARGET_WIDTH
  fi
}

close_slider_if_idle() {
  # Only close if width still at target (no intervening change/hover)
  CUR_PERC="$(sketchybar --query $SLIDER_ITEM | jq -r '.slider.percentage')"
  if [ "$CUR_PERC" = "$LAST_PERCENT" ]; then
    sketchybar --animate tanh 30 --set $SLIDER_ITEM slider.width=0
  fi
}

case "$SENDER" in
  volume_change)
    LAST_PERCENT="$INFO"
    set_icon_and_label "$INFO"
    sketchybar --set $SLIDER_ITEM slider.percentage=$INFO
    open_slider
    ( sleep $CLOSE_DELAY; LAST_PERCENT_CHECK="$INFO"; close_slider_if_idle ) &
    ;;
  mouse.entered)
    open_slider
    ;;
  mouse.exited.global)
    ( sleep $CLOSE_DELAY; close_slider_if_idle ) &
    ;;
  mouse.clicked)
    # Left click toggle mute (simple approach)
    if [ "$BUTTON" = "left" ]; then
      CUR_VOL=$(osascript -e 'output volume of (get volume settings)')
      if [ "$CUR_VOL" -gt 0 ]; then
        osascript -e 'set volume with output muted'
        set_icon_and_label 0
        sketchybar --set $SLIDER_ITEM slider.percentage=0
      else
        osascript -e 'set volume without output muted'
        NEW_VOL=$(osascript -e 'output volume of (get volume settings)')
        set_icon_and_label "$NEW_VOL"
        sketchybar --set $SLIDER_ITEM slider.percentage=$NEW_VOL
      fi
    fi
    ;;
 esac
