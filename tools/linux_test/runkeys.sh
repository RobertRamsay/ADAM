#!/bin/bash
pkill -x fs-uae; pkill -x Xvfb; sleep 0.5
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 1
export DISPLAY=:99 SDL_AUDIODRIVER=dummy
fs-uae --amiga_model=$2 --floppy_drive_0=$1 --fullscreen=0 --window_width=760 --window_height=600 --base_dir=/tmp/fsuae --floppy_drive_speed=0 --automatic_input_grab=0 --joystick_port_1=keyboard >/tmp/fsuae.log 2>&1 &
sleep 16
W=$(xdotool search --name "FS-UAE" | head -1); xdotool windowactivate $W 2>/dev/null; xdotool windowfocus $W
xwd -root -silent | convert xwd:- before.png
xdotool keydown Left; sleep 1.5; xdotool keyup Left
xdotool keydown Up; sleep 1; xdotool keyup Up
sleep 0.5
xwd -root -silent | convert xwd:- after.png
pkill -x fs-uae; pkill -x Xvfb
