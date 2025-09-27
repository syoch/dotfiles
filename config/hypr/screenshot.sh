#!/usr/bin/env bash

mode=$(
  cat <<EOS | wofi --dmenu
Screen
Rect region
Whole desktop
Brightness 30%
Brightness 100%
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
elif [ "$mode" == "Brightness 30%" ]; then
  brightnessctl set 30%
  sudo ddcutil -n L56051794302 setvcp 0x10 30
  sudo ddcutil -l SB240Y setvcp 0x10 30
elif [ "$mode" == "Brightness 100%" ]; then
  brightnessctl set 100%
  sudo ddcutil -n L56051794302 setvcp 0x10 100
  sudo ddcutil -l SB240Y setvcp 0x10 100
fi
