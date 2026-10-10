#!/bin/bash
# usage: run.sh adf model secs out.png
pkill -x fs-uae; pkill -x Xvfb; sleep 0.5
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 1
export DISPLAY=:99 SDL_AUDIODRIVER=dummy
mkdir -p /tmp/fsuae
fs-uae --amiga_model=$2 --floppy_drive_0=$1 --fullscreen=0 --window_width=760 --window_height=600 --base_dir=/tmp/fsuae --floppy_drive_speed=0 --automatic_input_grab=0 --audio_driver=null $5 >/tmp/fsuae.log 2>&1 &
sleep $3
xwd -root -silent | convert xwd:- $4
pkill -x fs-uae; pkill -x Xvfb
