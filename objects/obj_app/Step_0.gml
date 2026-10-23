/// Window sizing, autosave, shortcuts, emulator launch

// full-screen window on launch (done a frame late so the runner has a window)
startup_frames += 1;
if (startup_frames == 2)
{
    if (start_fullscreen) { window_set_fullscreen(true); }
    else
    {
        // put the window back where it was last time (kept on screen)
        if (wsave_w >= 640 && wsave_h >= 400)
        {
            var _dw = display_get_width();
            var _dh = display_get_height();
            var _rw = min(wsave_w, _dw);
            var _rh = min(wsave_h, _dh);
            var _rx = clamp(wsave_x, 0, max(0, _dw - _rw));
            var _ry = clamp(wsave_y, 0, max(0, _dh - _rh));
            window_set_rectangle(_rx, _ry, _rw, _rh);
        }
    }
}

// dev: page screenshots (-adam_shots) - keeps its own window size, saves nothing
dev_shots_step();

// remember the window: full screen or not, and its size and place when windowed
if (startup_frames > 10 && !shot_on)
{
    wsave_timer += 1;
    if (wsave_timer >= 30)
    {
        wsave_timer = 0;
        var _changed = false;
        var _fsnow = window_get_fullscreen();
        if (_fsnow != start_fullscreen)
        {
            start_fullscreen = _fsnow;
            _changed = true;
        }
        if (!_fsnow && window_get_width() > 0)
        {
            var _wx = window_get_x();
            var _wy = window_get_y();
            var _ww2 = window_get_width();
            var _wh2 = window_get_height();
            if (_wx != wsave_x || _wy != wsave_y || _ww2 != wsave_w || _wh2 != wsave_h)
            {
                wsave_x = _wx;
                wsave_y = _wy;
                wsave_w = _ww2;
                wsave_h = _wh2;
                _changed = true;
            }
        }
        if (_changed) { settings_save(); }
    }
}
if (keyboard_check_pressed(vk_f11))
{
    window_set_fullscreen(!window_get_fullscreen());
}
if (keyboard_check_pressed(vk_f12) && keyboard_check(vk_shift))
{
    pro_preview_toggle();
}

// step right back while another window (FS-UAE) has the focus, so the
// emulator gets the CPU and GPU instead of ADAM redrawing at full speed
var _focus = window_has_focus();
if (_focus != app_focused)
{
    app_focused = _focus;
    if (_focus) { game_set_speed(60, gamespeed_fps); }
    else { game_set_speed(10, gamespeed_fps); }
    // back from another program while full screen: some graphics cards lose
    // the screen meanwhile and show black, so set it up afresh (the backdrop,
    // sprite and hill images are rebuilt by themselves when they are missing)
    if (_focus && window_get_fullscreen()) { display_reset(app_aa, true); }
}

// interface scale for HD / QHD / 4K
var _ww = window_get_width();
var _wh = window_get_height();
if (_ww > 0 && _wh > 0)
{
    var _s = ui_scale_for(_ww, _wh);
    if (ui_scale_pref > 0) { _s = ui_scale_fixed(ui_scale_pref, _ww, _wh); }
    var _scale_changed = (_s != global.ui_scale);
    if (_scale_changed)
    {
        global.ui_scale = _s;
        fonts_load(_s);
    }
    if (_scale_changed || _ww != win_w || _wh != win_h)
    {
        win_w = _ww;
        win_h = _wh;
        gui_w = round(_ww / _s);
        gui_h = round(_wh / _s);
        display_set_gui_size(gui_w, gui_h);
        global.ui_sx = _ww / gui_w;
        global.ui_sy = _wh / gui_h;
    }
}

autosave_timer += delta_time / 1000000;
if (autosave_timer > 30)
{
    autosave_timer = 0;
    if (proj_dirty)
    {
        file_write_text(autosave_path(), project_to_json(proj));
    }
}

// FS-UAE starts a moment after the old copy was closed
if (launch_timer > 0)
{
    launch_timer -= 1;
    if (launch_timer == 0 && launch_pending != "")
    {
        launch_fsuae_now(launch_pending);
        launch_pending = "";
    }
}

// memory bar: measure again a moment after a change, never in the middle of a stroke
if (mem_proj_ref != proj || mem_machine != proj.machine)
{
    if (!mem_stale) { mem_mark_stale(); }
}
if (mem_stale && !mouse_check_button(mb_left) && !mouse_check_button(mb_right) && current_time - mem_stale_time > 400)
{
    mem_measure();
}

// Music page preview: keep Paula's four channels streaming
music_preview_step();

shortcuts_step();

var _edition = "Lite";
if (pro_edition()) { _edition = "Pro"; }
var _cap = "ADAM " + _edition + " " + ADAM_VERSION + " - " + proj.name + "  (" + machine_cur().name + ")";
if (proj_dirty) { _cap += " *"; }
if (_cap != caption_last)
{
    caption_last = _cap;
    window_set_caption(_cap);
}
