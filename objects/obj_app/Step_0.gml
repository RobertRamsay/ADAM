/// Window sizing, autosave, shortcuts, emulator launch

// full-screen window on launch (done a frame late so the runner has a window)
startup_frames += 1;
if (startup_frames == 2 && start_fullscreen)
{
    window_set_fullscreen(true);
}
if (keyboard_check_pressed(vk_f11))
{
    window_set_fullscreen(!window_get_fullscreen());
}

// interface scale for HD / QHD / 4K
var _ww = window_get_width();
var _wh = window_get_height();
if (_ww > 0 && _wh > 0)
{
    var _s = ui_scale_for(_ww, _wh);
    if (ui_scale_pref > 0) { _s = max(1, min(ui_scale_pref, _ww / 1100, _wh / 640)); }
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
        file_write_text(autosave_path(), json_stringify(proj));
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

shortcuts_step();

var _cap = "ADAM - " + proj.name + "  (" + machine_cur().name + ")";
if (proj_dirty) { _cap += " *"; }
if (_cap != caption_last)
{
    caption_last = _cap;
    window_set_caption(_cap);
}
