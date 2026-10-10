/// ADAM - Build workspace

function build_log_add(_text, _kind)
{
    array_push(build_log, { text : _text, kind : _kind });
    if (array_length(build_log) > 200) { array_delete(build_log, 0, 1); }
}

function build_choose_output()
{
    var _name = string_replace_all(proj.name, " ", "_");
    var _p = get_save_filename("Amiga disk image|*.adf", _name + ".adf");
    if (_p == "") { return false; }
    if (string_lower(filename_ext(_p)) != ".adf") { _p += ".adf"; }
    out_path = _p;
    settings_save();
    return true;
}

function build_ws_build(_run)
{
    if (out_path == "")
    {
        if (!build_choose_output()) { return; }
    }
    var _t0 = current_time;
    if (build_adf(out_path))
    {
        build_log_add(build_msg + "  (" + string(current_time - _t0) + " ms)", 0);
        for (var i = 0; i < array_length(build_warnings); i++) { build_log_add(build_warnings[i], 1); }
        toast("Build complete!", 0);
        build_make_listing();
        if (_run) { launch_fsuae(out_path); }
    }
    else
    {
        build_log_add(build_msg, 2);
        toast("Build failed - see the log", 2);
    }
}

function draw_check(_x, _y, _kind)
{
    var _c = global.TH.accent2;
    if (_kind == 0) { _c = make_colour_rgb(95, 211, 140); }
    if (_kind == 1) { _c = global.TH.warn; }
    if (_kind == 2) { _c = global.TH.danger; }
    draw_circle_colour(_x, _y, 10, _c, merge_colour(_c, c_black, 0.25), false);
    if (_kind == 0)
    {
        draw_line_width_colour(_x - 5, _y, _x - 1, _y + 4, 2, c_white, c_white);
        draw_line_width_colour(_x - 1, _y + 4, _x + 5, _y - 4, 2, c_white, c_white);
    }
    else
    {
        draw_line_width_colour(_x, _y - 5, _x, _y + 1, 2, c_white, c_white);
        draw_circle_colour(_x, _y + 5, 1.5, c_white, c_white, false);
    }
}

/// Path row: label, inset path text and a button. Returns true when the button is pressed.
function build_path_row(_id, _x, _y, _w, _label, _value, _empty, _btn, _help)
{
    ui_heading(_x, _y, _label);
    var _v = _value;
    if (_v == "") { _v = _empty; }
    ui_inset(_x, _y + 18, _x + _w - 96, _y + 50, 8);
    ui_text(_x + 10, _y + 34, ui_text_fit(_v, global.f_small, _w - 120), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    return ui_button(_id, _x + _w - 88, _y + 18, 88, 32, _btn, _help, BTN_NORMAL);
}

function ws_build_draw(_x1, _y1, _x2, _y2)
{
    var _lw = min(500, floor((_x2 - _x1) * 0.42));
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "Build your game");
    var _fx = _x1 + 20;
    var _fw = _lw - 40;
    var _y = _y1 + 58;
    var _m = machine_cur();

    // checklist
    var _na = array_length(proj.actors);
    var _nr = array_length(proj.rules);
    var _has_player = false;
    for (var i = 0; i < _na; i++)
    {
        if (proj.actors[i].role == 0 || proj.actors[i].role == 6) { _has_player = true; }
    }
    var _lose = false;
    var _end = false;
    for (var r = 0; r < _nr; r++)
    {
        if (proj.rules[r].act == 1) { _lose = true; }
        if (proj.rules[r].act == 9 || proj.rules[r].act == 10 || proj.rules[r].act == 17) { _end = true; }
    }
    var _alloc = actors_alloc_channels();
    var _conf = 0;
    for (var c = 0; c < array_length(_alloc.conflict); c++)
    {
        if (_alloc.conflict[c]) { _conf += 1; }
    }
    var _items = [];
    var _kinds = [];
    array_push(_items, "Target: " + _m.name + " (" + _m.chipset + ", " + _m.ram_label + ")");
    array_push(_kinds, 0);
    // a 512KB-chip A500 is not the target, so a big game only warns (see A500_512K_CHIP_KB)
    if (build_ok && !_m.aga)
    {
        if (build_size > (A500_512K_CHIP_KB - OS_RESERVE_KB) * 1024) { array_push(_items, "Last build is too big for a 512KB chip A500 (fine on 1MB)"); array_push(_kinds, 1); }
        else { array_push(_items, "Last build also fits a 512KB chip A500"); array_push(_kinds, 0); }
    }
    if (_has_player) { array_push(_items, "There is a Player actor for the joystick"); array_push(_kinds, 0); }
    else { array_push(_items, "No Player actor - set one on the Actors page"); array_push(_kinds, 1); }
    array_push(_items, string(_na) + " of 8 hardware sprites used");
    if (_na > 0) { array_push(_kinds, 0); } else { array_push(_kinds, 1); }
    if (_conf > 0) { array_push(_items, string(_conf) + " actor(s) borrow another actor's sprite colours"); array_push(_kinds, 1); }
    array_push(_items, string(_nr) + " rule(s)");
    if (_nr > 0) { array_push(_kinds, 0); } else { array_push(_kinds, 1); }
    if (_end) { array_push(_items, "The game can end (game over or win)"); array_push(_kinds, 0); }
    else { array_push(_items, "Nothing ends the game yet - add a Game over or You win rule"); array_push(_kinds, 1); }
    if (proj.levels_on)
    {
        array_push(_items, string(array_length(proj.levels)) + " level(s) with hills");
        array_push(_kinds, 0);
        var _gl = false;
        for (var g = 0; g < _nr; g++)
        {
            if (proj.rules[g].act == 17) { _gl = true; }
        }
        if (proj.goal_on && _gl) { array_push(_items, "Collect " + string(proj.goal) + " " + string_lower(proj.goal_label) + " to finish each level"); array_push(_kinds, 0); }
        else { array_push(_items, "Nothing finishes a level - add a 'Count towards the level goal' rule"); array_push(_kinds, 1); }
    }
    if (proj.show_lives && !_lose) { array_push(_items, "Lives are shown but no rule takes a life away"); array_push(_kinds, 1); }
    ui_heading(_fx, _y, "Checklist");
    _y += 22;
    for (var k = 0; k < array_length(_items); k++)
    {
        draw_check(_fx + 10, _y + 11, _kinds[k]);
        ui_text(_fx + 30, _y + 11, ui_text_fit(_items[k], global.f_body, _fw - 34), global.TH.text, fa_left, fa_middle, global.f_body, 1);
        _y += 28;
    }
    _y += 10;

    if (ui_button("build_adf", _fx, _y, _fw, 46, "Build .ADF disk   (Ctrl+B)", "Build|Turns your project into a bootable Amiga floppy disk image (.ADF). It runs in FS-UAE, WinUAE, on a Gotek or written to a real disk.", BTN_ACCENT))
    {
        build_ws_build(false);
    }
    _y += 54;
    var _rst = BTN_ON;
    if (os_type != os_windows && os_type != os_macosx) { _rst = BTN_GHOST; }
    if (ui_button("build_run", _fx, _y, _fw, 46, "Build and play in FS-UAE", "Build and play|Builds the disk and boots it in FS-UAE as a stock " + _m.name + ". Joystick: FS-UAE maps a gamepad, or the cursor keys and right Ctrl, to port 2.", _rst))
    {
        build_ws_build(true);
    }
    _y += 62;

    if (build_path_row("build_outpath", _fx, _y, _fw, "Disk file", out_path, "(you will be asked the first time you build)", "Change", "Disk file|Choose where the .ADF file is saved."))
    {
        build_choose_output();
    }
    _y += 60;
    // FS-UAE: the user's own copy, ADAM's test copy, or an install found on disk
    ui_heading(_fx, _y, "FS-UAE emulator");
    var _btn_w = 88;
    var _row_w = _fw - _btn_w - 8;
    if (ADAM_DEV_TOOLS) { _row_w -= _btn_w + 8; }
    ui_inset(_fx, _y + 18, _fx + _row_w, _y + 50, 8);
    if (fsuae_dl_id >= 0)
    {
        var _t = 0;
        if (fsuae_dl_total > 0) { _t = clamp(fsuae_dl_got / fsuae_dl_total, 0, 1); }
        ui_rrect(_fx + 4, _y + 22, _fx + 4 + (_row_w - 8) * _t, _y + 46, 6, global.TH.accent2, merge_colour(global.TH.accent2, c_black, 0.3), 1);
        ui_text(_fx + 10, _y + 34, "Downloading FS-UAE...  " + string(round(_t * 100)) + "%", global.TH.text, fa_left, fa_middle, global.f_small, 1);
    }
    else
    {
        var _src = fsuae_source_label();
        var _scol = global.TH.text_dim;
        if (_src == "")
        {
            _src = "(not found - click Find to choose fs-uae.exe)";
            if (os_type == os_macosx) { _src = "(not found - install FS-UAE in Applications, or Find it)"; }
            if (ADAM_DEV_TOOLS) { _src = "(not found - Get test copy, or Find your own)"; }
            _scol = global.TH.warn;
        }
        ui_text(_fx + 10, _y + 34, ui_text_fit(_src, global.f_small, _row_w - 20), _scol, fa_left, fa_middle, global.f_small, 1);
    }
    if (ui_button("build_fsuae", _fx + _fw - _btn_w, _y + 18, _btn_w, 32, "Find", "Find FS-UAE|Point ADAM at your own fs-uae.exe (free from fs-uae.net). Your choice always wins over ADAM's test copy. Right-click clears it.", BTN_NORMAL))
    {
        var _filter = "FS-UAE|fs-uae.exe;fs-uae";
        if (os_type == os_macosx) { _filter = "FS-UAE|*.app;fs-uae"; }
        var _v = get_open_filename(_filter, "");
        if (_v != "")
        {
            fsuae_path = _v;
            settings_save();
        }
    }
    if (ui_hot == "build_fsuae" && ui_rpressed)
    {
        fsuae_path = "";
        settings_save();
        toast("Using ADAM's test copy or an installed FS-UAE", 0);
    }
    var _lt = ui_toggle("build_light", _fx, _y + 56, "Light emulator mode", fsuae_light, "Light emulator mode|Runs FS-UAE without syncing to your monitor and without smoothing. Much lighter on your PC; turn it off for the smoothest scrolling.");
    if (_lt != fsuae_light)
    {
        fsuae_light = _lt;
        settings_save();
    }
    if (ADAM_DEV_TOOLS)
    {
        var _glab = "Get test copy";
        if (file_exists(fsuae_test_exe())) { _glab = "Re-download"; }
        if (ui_button("build_fsuae_get", _fx + _fw - _btn_w * 2 - 8, _y + 18, _btn_w, 32, _glab, "FS-UAE test copy|Developer convenience: downloads the official FS-UAE 3.1.66 for Windows into ADAM's save folder, so Build and play works straight away (on a Mac it opens the FS-UAE disk image to drag into Applications). 'Build and play' fetches it by itself when no FS-UAE is found.", BTN_GHOST))
        {
            fsuae_download("");
        }
    }
    _y += 92;
    if (build_path_row("build_kick", _fx, _y, _fw, "Kickstart ROM (optional)", kick_path, "(none - FS-UAE uses its free AROS ROM)", "Find", "Kickstart ROM|Optional. ADAM games boot on FS-UAE's built-in AROS ROM, but you can use your own Kickstart for the most authentic test. Right-click clears it."))
    {
        var _k = get_open_filename("Kickstart ROM|*.rom;*.bin", "");
        if (_k != "")
        {
            kick_path = _k;
            settings_save();
        }
    }
    if (ui_hot == "build_kick" && ui_rpressed)
    {
        kick_path = "";
        settings_save();
    }
    _y += 68;

    // chip memory bar
    ui_heading(_fx, _y, "Chip RAM used (after last build)");
    _y += 20;
    ui_inset(_fx, _y, _fx + _fw, _y + 26, 8);
    if (build_ok)
    {
        var _range = max(1, build_chip_free);
        var _iw = _fw - 4;
        var _ew = build_engine_size / _range * _iw;
        var _pw = build_plane_size / _range * _iw;
        var _sw = build_sound_size / _range * _iw;
        var _rest = max(0, build_size - build_engine_size - build_plane_size - build_sound_size);
        var _ow = _rest / _range * _iw;
        var _bx = _fx + 2;
        ui_rrect(_bx, _y + 2, _bx + _ew, _y + 24, 4, global.TH.accent, global.TH.accent_dark, 1);
        _bx += _ew;
        ui_rrect(_bx, _y + 2, _bx + _pw, _y + 24, 4, global.TH.accent2, merge_colour(global.TH.accent2, c_black, 0.3), 1);
        _bx += _pw;
        ui_rrect(_bx, _y + 2, _bx + _sw, _y + 24, 4, global.TH.warn, merge_colour(global.TH.warn, c_black, 0.3), 1);
        _bx += _sw;
        ui_rrect(_bx, _y + 2, _bx + _ow, _y + 24, 4, make_colour_rgb(95, 211, 140), make_colour_rgb(60, 150, 100), 1);
        var _mem_help = "Chip RAM|Blue: the ADAM engine (about " + string(ceil(build_engine_size / 1024)) + " KB, including the ProTracker music player). Orange: the backdrop (the original, a copy with the hills, and the screen). Yellow: sound samples and music. Green: sprites, rules and the rest. The full bar is the chip RAM left free on a stock " + _m.name + ".";
        if (!_m.aga)
        {
            // red tick: the most that fits an A500 with only 512KB of chip RAM
            var _kx = _fx + 2 + min(1, (A500_512K_CHIP_KB - OS_RESERVE_KB) * 1024 / _range) * _iw;
            draw_line_width_colour(_kx, _y - 2, _kx, _y + 28, 2, global.TH.danger, global.TH.danger);
            _mem_help += " The red tick is about " + string(A500_512K_CHIP_KB - OS_RESERVE_KB) + " KB: games past it will not run on an A500 with only 512KB of chip RAM (it shows a red screen).";
        }
        ui_register("build_mem", _fx, _y, _fx + _fw, _y + 26, _mem_help);
        _y += 34;
        ui_text(_fx, _y, "Engine   Backdrop   Sound & music   Other        " + string(ceil(build_size / 1024)) + " KB of about " + string(build_chip_free div 1024) + " KB", global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
    }
    else
    {
        ui_text(_fx + 12, _y + 13, "Build to see the memory map", global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
    }

    // ---------------- log / listing ----------------
    var _rx = _x1 + _lw + 12;
    ui_panel(_rx, _y1, _x2, _y2, "Build log");
    var _sa = ui_toggle("build_showasm", _x2 - 300, _y1 + 12, "Show the 68000 engine", build_show_asm, "68000 engine|For the curious: shows the assembly language source of the engine your game runs on. ADAM never writes code - it adds your game as data after the engine.");
    if (_sa != build_show_asm)
    {
        build_show_asm = _sa;
        if (_sa && array_length(build_listing) == 0) { build_make_listing(); }
    }
    var _lx1 = _rx + 14;
    var _ly1 = _y1 + 52;
    var _lx2 = _x2 - 14;
    var _ly2 = _y2 - 12;
    ui_inset(_lx1, _ly1, _lx2, _ly2, 10);
    if (build_show_asm)
    {
        var _n = array_length(build_listing);
        var _content = _n * 18 + 20;
        var _off = ui_scroll_begin("build_asm", _lx1, _ly1, _lx2, _ly2, _content);
        var _first = max(0, floor((_off - 10) / 18));
        var _last = min(_n, _first + ceil((_ly2 - _ly1) / 18) + 2);
        for (var l = _first; l < _last; l++)
        {
            var _line = build_listing[l];
            var _col = global.TH.text_dim;
            var _c1 = string_char_at(_line, 1);
            if (_c1 != " " && _c1 != "") { _col = global.TH.accent; }
            if (_c1 == ";") { _col = global.TH.text_faint; }
            ui_text(_lx1 + 56, _ly1 + 10 + l * 18 - _off, string_replace_all(_line, "\t", "    "), _col, fa_left, fa_top, global.f_small, 1);
            ui_text(_lx1 + 46, _ly1 + 10 + l * 18 - _off, string(l + 1), global.TH.text_faint, fa_right, fa_top, global.f_small, 0.6);
        }
        ui_scroll_end("build_asm", _lx1, _ly1, _lx2, _ly2, _content);
    }
    else
    {
        var _ln = array_length(build_log);
        if (_ln == 0)
        {
            ui_text_wrap(_lx1 + 16, _ly1 + 16, "Nothing built yet. Press 'Build .ADF disk' and your game becomes a bootable Amiga floppy for the " + _m.name + ". Messages and tips will appear here.", global.TH.text_faint, _lx2 - _lx1 - 32, global.f_body, 1);
        }
        var _ly = _ly1 + 14;
        for (var m = max(0, _ln - 30); m < _ln; m++)
        {
            var _e = build_log[m];
            draw_check(_lx1 + 22, _ly + 10, _e.kind);
            ui_text(_lx1 + 42, _ly + 10, ui_text_fit(_e.text, global.f_body, _lx2 - _lx1 - 56), global.TH.text, fa_left, fa_middle, global.f_body, 1);
            _ly += 28;
            if (_ly > _ly2 - 20) { break; }
        }
    }
}
