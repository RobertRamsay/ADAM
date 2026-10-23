/// ADAM - Home workspace

function home_save(_save_as)
{
    var _path = proj_path;
    if (_save_as || _path == "")
    {
        _path = get_save_filename("ADAM project|*.adam", proj.name + ".adam");
        if (_path == "") { return; }
        if (filename_ext(_path) == "") { _path += ".adam"; }
    }
    project_save_to(_path);
}

function home_open()
{
    if (proj_dirty)
    {
        confirm_open("Open another project?", confirm_unsaved_text("Opening another project"), "Open...", "Cancel", true, home_open_now, 0);
        return;
    }
    home_open_now(0);
}

function home_open_now(_unused)
{
    var _path = get_open_filename("ADAM project|*.adam", "");
    if (_path != "") { project_load_from(_path); }
}

function home_new()
{
    if (proj_dirty)
    {
        confirm_open("Start a new project?", confirm_unsaved_text("A new project"), "New project", "Cancel", true, home_new_now, 0);
        return;
    }
    home_new_now(0);
}

function home_new_now(_unused)
{
    var _machine = proj.machine;
    proj = project_new();
    proj.machine = _machine;
    proj_path = "";
    out_path = "";            // asked on the first build, so another game's disk is never overwritten
    proj_dirty = false;
    undo_clear_all();
    project_after_change();
    settings_save();
    toast("New project ready", 0);
}

/// Height of a Home list row _w wide: the title line and the wrapped text,
/// at least _min (the icon: about four text rows). _pic_w = room for a picture on the right.
function home_row_h(_desc, _w, _min, _pic_w)
{
    draw_set_font(global.f_small);
    return max(_min, 34 + ceil(ui_sh_ext(_desc, _w - 16 - 76 - 12 - _pic_w)) + 10);
}

/// Example _i's screenshot sprite (datafiles/examples/shots, made by gen_examples.py
/// shot()), the A1200 version on the A1200; -1 when there is none
function home_shot(_i)
{
    var _aga = (machine_cur().id == "A1200");
    var _n = array_length(global.EXAMPLES);
    if (array_length(home_shots) != _n || home_shots_aga != _aga)
    {
        for (var k = 0; k < array_length(home_shots); k++)
        {
            if (home_shots[k] >= 0) { sprite_delete(home_shots[k]); }
        }
        home_shots = array_create(_n, -1);
        home_shots_aga = _aga;
        for (var e = 0; e < _n; e++)
        {
            var _path = working_directory + "examples/shots/" + filename_change_ext(example_file(global.EXAMPLES[e]), ".png");
            if (file_exists(_path)) { home_shots[e] = sprite_add(_path, 1, false, false, 0, 0); }
        }
    }
    if (_i < 0 || _i >= _n) { return -1; }
    return home_shots[_i];
}

/// The first letters of a name's words, for an example's icon ("Dig Deep" -> "DD")
function home_initials(_name)
{
    var _s = string_upper(string_char_at(_name, 1));
    var _p = string_pos(" ", _name);
    if (_p > 0) { _s += string_upper(string_char_at(_name, _p + 1)); }
    return _s;
}

/// A row in a Home list: an icon (_badge on a rounded square), the title, a tag
/// (e.g. "ADAM Pro"), the text and a picture on the right (sprite _pic, -1 = none,
/// _pic_w wide). Returns true when it is clicked.
function home_row(_id, _x1, _y1, _x2, _h, _badge, _c1, _c2, _title, _tag, _desc, _help, _pic, _pic_w)
{
    var _hot = ui_register(_id, _x1, _y1, _x2, _y1 + _h, _help);
    var _tgt = 0;
    if (_hot) { _tgt = 1; }
    var _a = ui_anim_to(_id, _tgt);
    ui_rrect(_x1, _y1, _x2, _y1 + _h, 10, merge_colour(global.TH.btn_top, global.TH.btn_hot_top, _a), merge_colour(global.TH.panel_bot, global.TH.btn_bot, _a), 1);
    ui_rrect_line(_x1, _y1, _x2, _y1 + _h, 10, merge_colour(global.TH.panel_edge, global.TH.accent, _a), 0.6 + 0.4 * _a, 1);
    ui_glow(_x1, _y1, _x2, _y1 + _h, 10, global.TH.accent, _a * 0.6);
    // the icon: 48 x 48, centred in the row's height
    var _iy = _y1 + floor((_h - 48) / 2);
    ui_rrect(_x1 + 10, _iy, _x1 + 58, _iy + 48, 10, _c1, _c2, 1);
    ui_text(_x1 + 34, _iy + 24, _badge, c_white, fa_center, fa_middle, global.f_bold, 1);
    if (_pic_w > 0)
    {
        // the picture: the 320 x 256 screen at _pic_w wide, on the right, centred in the
        // row's height (an empty frame without one)
        var _pw = _pic_w;
        var _ph = round(_pw * 0.8);
        var _px1 = _x2 - 8 - _pw;
        var _py1 = _y1 + floor((_h - _ph) / 2);
        if (_pic >= 0)
        {
            gpu_set_texfilter(true);
            draw_sprite_stretched(_pic, 0, _px1, _py1, _pw, _ph);
            gpu_set_texfilter(false);
        }
        else { ui_rrect(_px1, _py1, _px1 + _pw, _py1 + _ph, 4, global.TH.panel_bot, global.TH.panel_bot, 1); }
        ui_rrect_line(_px1, _py1, _px1 + _pw, _py1 + _ph, 4, merge_colour(global.TH.panel_edge, global.TH.accent, _a), 0.8, 1);
        _x2 -= _pw + 8;
    }
    var _tx = _x1 + 72;
    var _tw = _x2 - _tx - 12;
    var _tagw = 0;
    if (_tag != "")
    {
        draw_set_font(global.f_small);
        _tagw = ui_sw(_tag) + 16;
        ui_rrect(_x2 - 10 - _tagw, _y1 + 8, _x2 - 10, _y1 + 28, 9, global.TH.accent2, merge_colour(global.TH.accent2, c_black, 0.35), 0.9);
        ui_text(_x2 - 10 - _tagw / 2, _y1 + 18, _tag, c_white, fa_center, fa_middle, global.f_small, 1);
    }
    ui_text(_tx, _y1 + 18, ui_text_fit(_title, global.f_bold, _tw - _tagw - 8), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
    ui_text_wrap(_tx, _y1 + 34, _desc, global.TH.text_dim, _tw, global.f_small, 1);
    if (_hot && ui_pressed)
    {
        ui_take_click();
        return true;
    }
    return false;
}

function ws_home_draw(_x1, _y1, _x2, _y2)
{
    var _split = _x1 + floor((_x2 - _x1) * 0.6);
    var _m = machine_cur();
    // ---------- hero ----------
    ui_panel(_x1, _y1, _split - 10, _y1 + 236, "");
    draw_boing(_split - 150, _y1 + 26, 110, 0.9);
    ui_text(_x1 + 28, _y1 + 26, "Make an Amiga game.", c_white, fa_left, fa_top, global.f_hero, 1);
    ui_text(_x1 + 28, _y1 + 62, "No code needed.", global.TH.accent2, fa_left, fa_top, global.f_hero, 1);
    // three lines (72 px) at 1280 wide, so the buttons sit below them at + 184
    ui_text_wrap(_x1 + 28, _y1 + 104, "Paint a backdrop, draw sprites, choose how things move and write the rules as simple WHEN / DO sentences. ADAM builds a bootable Amiga disk for the " + _m.name + ".", global.TH.text_dim, _split - _x1 - 220, global.f_body, 1);
    var _bx = _x1 + 28;
    var _by = _y1 + 184;
    if (ui_button("home_new", _bx, _by, 80, 40, "New", "New project|Starts a blank project for the same machine.", BTN_NORMAL)) { home_new(); }
    if (ui_button("home_open", _bx + 88, _by, 80, 40, "Open", "Open project|Opens a .adam project file you saved earlier.", BTN_NORMAL)) { home_open(); }
    if (ui_button("home_save", _bx + 176, _by, 80, 40, "Save", "Save project|Saves your project (Ctrl+S). The first time it asks where to put it.", BTN_NORMAL)) { home_save(false); }
    if (ui_button("home_saveas", _bx + 264, _by, 96, 40, "Save as", "Save as|Saves a copy of your project under a new name.", BTN_GHOST)) { home_save(true); }

    // ---------- two lists side by side, each scrolling when it outgrows its panel ----------
    var _cy = _y1 + 248;
    var _mid = _x1 + floor((_split - 10 - _x1 - 10) / 2);

    // How it works: every editor, in top bar order, then the guided tour
    ui_panel(_x1, _cy, _mid, _y2, "How it works");
    // the longest hint that fits beside the title
    var _fhint = "Click one to open that page";
    var _froom = _mid - _x1 - 190;
    draw_set_font(global.f_small);
    if (ui_sw(_fhint) > _froom) { _fhint = "Click to open"; }
    if (ui_sw(_fhint) > _froom) { _fhint = ""; }
    ui_text(_mid - 16, _cy + 19, _fhint, global.TH.text_faint, fa_right, fa_top, global.f_small, 1);
    var _dest = [WS_BACKDROP, WS_TILES, WS_LEVELS, WS_SPRITES, WS_ACTORS, WS_ANIMATE, WS_UI, WS_LOGIC, WS_SOUND, WS_MUSIC, WS_BUILD, -1];
    var _desc = ["Paint or import the 320 x 256 picture (up to " + string(1 << _m.max_depth) + " colours).",
                 "Draw tiles and paint a big scrolling world to dig through.",
                 "Up to 10 levels, their hills, the goal and the title screen.",
                 "Draw the pictures for the player, enemies and pickups.",
                 "Place them and choose how each one moves.",
                 "Walk, jump and fire animations made from your sprites.",
                 "Design the score panel: a frame, a font and fields.",
                 "WHEN the player touches a gem, DO add 10 to the score.",
                 "Lasers, coins and explosions for the Paula chip.",
                 "Songs from ready-made loops, one for each level.",
                 "A bootable .ADF disk for FS-UAE or a real Amiga.",
                 "New here? A five-minute walk through every page."];
    var _ncard = array_length(_dest);
    var _lx1 = _x1 + 4;
    var _lx2 = _mid - 4;
    var _ly1 = _cy + 48;
    var _ly2 = _y2 - 8;
    var _rows_h = 0;
    for (var hq = 0; hq < _ncard; hq++) { _rows_h += home_row_h(_desc[hq], _lx2 - _lx1, 64, 0) + 6; }
    var _off = ui_scroll_begin("home_flow", _lx1, _ly1, _lx2, _ly2, _rows_h + 6);
    var _ry = _ly1 + 4 - _off;
    for (var i = 0; i < _ncard; i++)
    {
        var _title = "Guided tour";
        var _num = "?";
        var _go = "Click to start it.";
        var _c1 = global.TH.accent;
        var _c2 = global.TH.accent_dark;
        if (_dest[i] >= 0)
        {
            _title = ws_name(_dest[i]);
            _num = string(i + 1);
            _go = "Click to go to that page.";
        }
        else
        {
            _c1 = global.TH.accent2;
            _c2 = merge_colour(global.TH.accent2, c_black, 0.35);
        }
        var _rh = home_row_h(_desc[i], _lx2 - _lx1, 64, 0);
        if (home_row("home_card_" + string(i), _lx1 + 8, _ry, _lx2 - 8, _rh, _num, _c1, _c2, _title, "", _desc[i], _title + "|" + _desc[i] + " " + _go, -1, 0))
        {
            if (_dest[i] >= 0) { ws_set(_dest[i]); }
            else { tut_start(-1); }
        }
        _ry += _rh + 6;
    }
    ui_scroll_end("home_flow", _lx1, _ly1, _lx2, _ly2, _rows_h + 6);

    // Example games: finished games to load, play and pull apart
    ui_panel(_mid + 10, _cy, _split - 10, _y2, "Example games");
    // the longest hint that fits beside the title
    var _hint = "Click to load, double-click to build and play";
    var _room = _split - _mid - 20 - 210;
    draw_set_font(global.f_small);
    if (ui_sw(_hint) > _room) { _hint = "Click: load, double-click: play"; }
    if (ui_sw(_hint) > _room) { _hint = "Double-click to play"; }
    ui_text(_split - 26, _cy + 19, _hint, global.TH.text_faint, fa_right, fa_top, global.f_small, 1);
    ui_register("home_example", _mid + 10, _cy, _split - 10, _cy + 44, "Example games|Finished games to play and pull apart. Click one to load it, then look around every page to see how it was made. Double-click one to build its disk and play it in FS-UAE straight away. The ADAM Pro ones show off BOBs, tile worlds, shoot 'em ups and items.");
    var _ex1 = _mid + 14;
    var _ex2 = _split - 14;
    var _nex = array_length(global.EXAMPLES);
    // about eight text rows each, with a screenshot on the right (narrower panels: smaller)
    var _shw = clamp(floor((_ex2 - _ex1) * 0.36), 120, 180);
    var _exmin = max(64, round(_shw * 0.8) + 16);
    var _ex_h = 0;
    for (var eq = 0; eq < _nex; eq++) { _ex_h += home_row_h(global.EXAMPLES[eq].desc, _ex2 - _ex1, _exmin, _shw + 8) + 6; }
    var _eoff = ui_scroll_begin("home_examples", _ex1, _ly1, _ex2, _ly2, _ex_h + 6);
    _ry = _ly1 + 4 - _eoff;
    for (var e = 0; e < _nex; e++)
    {
        var _ed = global.EXAMPLES[e];
        var _tag = "";
        var _e1 = global.TH.accent;
        var _e2 = global.TH.accent_dark;
        if (_ed.pro)
        {
            _e1 = global.TH.accent2;
            _e2 = merge_colour(global.TH.accent2, c_black, 0.35);
            if (!pro_edition()) { _tag = "ADAM Pro"; }
        }
        var _erh = home_row_h(_ed.desc, _ex2 - _ex1, _exmin, _shw + 8);
        if (home_row("home_ex_" + string(e), _ex1 + 8, _ry, _ex2 - 8, _erh, home_initials(_ed.name), _e1, _e2, _ed.name, _tag, _ed.desc, _ed.name + "|" + _ed.desc + " Click to load it; double-click to build it and play it in FS-UAE.", home_shot(e), _shw))
        {
            // the first click loads it; a second one within 0.4 s builds a test disk
            // and plays it (as Build & play) - only once that example really is loaded
            if (home_ex_click == e && current_time - home_ex_click_t < 400)
            {
                home_ex_click = -1;
                if (example_last == e && !proj_dirty) { build_ws_build(true); }
            }
            else
            {
                home_ex_click = e;
                home_ex_click_t = current_time;
                example_load(e);
            }
        }
        _ry += _erh + 6;
    }
    ui_scroll_end("home_examples", _ex1, _ly1, _ex2, _ly2, _ex_h + 6);

    // ---------- settings ----------
    // two panels with a clear split: the game's own settings (saved in the project) above,
    // ADAM Studio's settings (this computer, every project) below
    var _px = _split + 10;
    var _studio_h = 228;
    var _gy2 = _y2 - _studio_h - 12;
    ui_panel(_px, _y1, _x2, _gy2, "Game settings");
    ui_text(_x2 - 16, _y1 + 19, "Saved with this game", global.TH.text_faint, fa_right, fa_top, global.f_small, 1);
    ui_rrect(_px + 14, _y1 + 41, _x2 - 14, _y1 + 44, 1, global.TH.accent, global.TH.accent_dark, 0.9);
    var _fx = _px + 20;
    var _fw = _x2 - _px - 40;
    var _half = floor((_fw - 12) / 2);
    // scrolls when the window is too short for every setting (home_set_h: last frame's height)
    var _sy1 = _y1 + 46;
    var _sy2 = _gy2 - 6;
    var _soff = ui_scroll_begin("home_set", _px + 4, _sy1, _x2 - 4, _sy2, home_set_h);
    var _y = _y1 + 58 - _soff;
    var _ytop = _y;
    ui_heading(_fx, _y, "Game name");
    var _nm = ui_textfield("home_name", _fx, _y + 18, _fw, 32, proj.name, 32, "Game name|The name of your game. It is used for the saved file names too.");
    set_val(proj, "name", _nm, "name");
    _y += 64;
    ui_heading(_fx, _y, "Target machine");
    ui_inset(_fx, _y + 18, _fx + _fw - 88, _y + 50, 8);
    ui_text(_fx + 10, _y + 34, ui_text_fit(_m.name + " - " + _m.chipset + ", " + _m.ram_label, global.f_body, _fw - 108), global.TH.text, fa_left, fa_middle, global.f_body, 1);
    if (ui_button("home_machine", _fx + _fw - 80, _y + 18, 80, 32, "Change", "Change machine|Pick the Amiga 500/600 (OCS/ECS, 1MB) or the Amiga 1200 (AGA, 2MB). Moving to the 500/600 reduces the backdrop to 16 colours.", BTN_NORMAL))
    {
        machine_pick_open(false);
    }
    _y += 64;

    ui_heading(_fx, _y, "Lives at start");
    set_val(proj, "lives", ui_stepper("home_lives", _fx, _y + 18, _half, proj.lives, 0, 9, "Lives|How many lives the player starts with. Use the 'Lose a life' action in Logic to take them away."), "lives");
    ui_heading(_fx + _half + 12, _y, "Score / lives row");
    set_val(proj, "hud_row", ui_stepper("home_hudrow", _fx + _half + 12, _y + 18, _half, proj.hud_row, 0, 31, "Score row|Which 8-pixel text row (0 = top, 31 = bottom) shows the score and lives. They are drawn on top of the backdrop."), "hudrow");
    _y += 64;
    set_val(proj, "show_score", ui_toggle("home_showscore", _fx, _y, "Show score", proj.show_score, "Show score|Shows SCORE 00000 on the left of the score row."), "showscore");
    set_val(proj, "show_lives", ui_toggle("home_showlives", _fx + _half + 12, _y, "Show lives", proj.show_lives, "Show lives|Shows LIVES 3 on the right of the score row."), "showlives");
    _y += 40;
    ui_heading(_fx, _y, "Score colour");
    set_val(proj, "hud_colour", ui_colour_drop("home_hudcol", _fx, _y + 18, _half, 32, proj.hud_colour, "Score colour|The backdrop colour used for the score and lives text."), "hudcol");
    ui_heading(_fx + _half + 12, _y, "Message colour");
    set_val(proj, "msg_colour", ui_colour_drop("home_msgcol", _fx + _half + 12, _y + 18, _half, 32, proj.msg_colour, "Message colour|The colour of the game over and win messages. They sit on a box of colour 0."), "msgcol");
    _y += 64;
    ui_heading(_fx, _y, "Game over message");
    set_val(proj, "over_text", ui_textfield("home_over", _fx, _y + 18, _fw, 32, proj.over_text, 36, "Game over message|Shown in the middle of the screen when a 'Game over' action happens. The player presses fire to play again."), "overtext");
    _y += 64;
    ui_heading(_fx, _y, "Win message");
    set_val(proj, "win_text", ui_textfield("home_win", _fx, _y + 18, _fw, 32, proj.win_text, 36, "Win message|Shown when a 'You win!' action happens."), "wintext");
    home_set_h = (_y + 50 + 14) - _ytop + 12;
    ui_scroll_end("home_set", _px + 4, _sy1, _x2 - 4, _sy2, home_set_h);

    // ---------- ADAM Studio: settings for ADAM itself ----------
    var _st = _y2 - _studio_h;
    ui_panel(_px, _st, _x2, _y2, "Studio");
    ui_text(_x2 - 16, _st + 19, "ADAM's own settings - not part of your game", global.TH.text_faint, fa_right, fa_top, global.f_small, 1);
    ui_rrect(_px + 14, _st + 41, _x2 - 14, _st + 44, 1, global.TH.accent2, merge_colour(global.TH.accent2, c_black, 0.35), 0.9);
    _y = _st + 54;
    ui_heading(_fx, _y, "Interface size");
    var _si = 0;
    for (var sv = 1; sv < array_length(global.UI_SCALE_VALUES); sv++)
    {
        if (global.UI_SCALE_VALUES[sv] == ui_scale_pref) { _si = sv; }
    }
    var _nsi = ui_dropdown("home_scale", _fx, _y + 18, _half, 30, global.UI_SCALE_NAMES, _si, "Interface size|Makes everything bigger or smaller. Auto picks 200% on a 4K screen. Shortcuts: Ctrl + and Ctrl - (Ctrl 0 = auto).");
    if (_nsi != _si)
    {
        ui_scale_pref = global.UI_SCALE_VALUES[_nsi];
        settings_save();
    }
    var _fs = ui_toggle("home_fullscreen", _fx + _half + 12, _y + 21, "Start full screen", start_fullscreen, "Full screen|Opens ADAM filling the whole screen. F11 switches between full screen and a window at any time - ADAM remembers which you used last, and the window's size and place.");
    if (_fs != start_fullscreen)
    {
        start_fullscreen = _fs;
        settings_save();
        window_set_fullscreen(_fs);
    }
    _y += 60;
    var _at = ui_toggle("home_autotut", _fx, _y, "Offer page tutorials", auto_tutorials, "Tutorial offers|The first time you open each page, a small card asks if you'd like its tutorial. Turn this off once you know your way around.");
    if (_at != auto_tutorials)
    {
        auto_tutorials = _at;
        settings_save();
    }
    var _ho = ui_toggle("home_helpers", _fx + _half + 12, _y, "Hover help bubbles", helpers_on, "Hover helpers|Shows guide lines and a help bubble when you rest the mouse on something.");
    if (_ho != helpers_on)
    {
        helpers_on = _ho;
        settings_save();
    }
    _y += 34;
    var _uc = ui_toggle("home_updates", _fx, _y, "Check for updates", update_check_on, "Check for updates|When ADAM starts, it looks online for a newer version and, if there is one, shows a small card with a link to it. Nothing about you or your games is sent.");
    if (_uc != update_check_on)
    {
        update_check_on = _uc;
        settings_save();
    }
    _y += 38;
    if (ui_button("home_resettut", _fx, _y, 200, 30, "Reset page tutorials", "Reset tutorials|Makes every page offer its tutorial again the next time you visit it.", BTN_GHOST))
    {
        for (var w = 0; w < WS_COUNT; w++) { ws_seen[w] = false; }
        settings_save();
        toast("Each page will offer its tutorial again", 0);
    }
    if (ui_button("home_about", _fx + 210, _y, 236, 30, "About ADAM & licences", "About ADAM|Shows ADAM's version and the licences for the fonts and programs it uses (Poppins, font8x8, FS-UAE).", BTN_GHOST))
    {
        about_open();
    }
}
