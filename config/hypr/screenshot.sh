#!/bin/bash

mode=$(
  cat <<EOS | wofi --dmenu
Screen
Rect region
Whole desktop
EOS
)

sleep 0.5

if [ "$mode" == "Whole desktop" ]; then
  grim_flag=""
  grim - | wl-copy
  notify-send -t 1000 "Screenshot" "Whole desktop copied to clipboard"
elif [ "$mode" == "Screen" ]; then
  geometry=$(slurp -o -b '#000000b0' -c '00000000')
  sleep 1
  grim -g "$geometry" - | wl-copy
  notify-send -t 1000 "Screenshot" "Screen copied to clipboard"
elif [ "$mode" == "Rect region" ]; then
  geometry=$(slurp -b '#000000b0' -c '00000000')
  sleep 1
  grim -g "$geometry" - | wl-copy
  notify-send -t 1000 "Screenshot" "Rect region copied to clipboard"
fi
