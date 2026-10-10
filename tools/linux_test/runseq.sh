#!/bin/bash
pkill -x fs-uae; pkill -x Xvfb; sleep 0.5
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 1
export DISPLAY=:99
fs-uae --amiga_model=A600 --floppy_drive_0=$1 --fullscreen=0 --window_width=760 --window_height=600 --base_dir=/tmp/fsuae --floppy_drive_speed=0 --automatic_input_grab=0 --joystick_port_1=keyboard --audio_driver=null >/tmp/fsuae.log 2>&1 &
sleep 21
W=$(xdotool search --name "FS-UAE" | head -1); xdotool windowactivate $W 2>/dev/null; xdotool windowfocus $W
xdotool keydown Right
for i in $(seq -w 1 40); do xwd -root -silent | convert xwd:- -crop 760x600+132+84 -resize 40% sq_$i.png; sleep 0.12; done
xdotool keyup Right
pkill -x fs-uae; pkill -x Xvfb
