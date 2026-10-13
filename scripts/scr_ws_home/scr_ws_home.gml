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
    var _ex = ui_menu_button("home_example", _bx, _by, 190, 40, "Example games...", example_names(), "Example games|Finished games to play and pull apart: Gem Hunter, Deep Dive, Star Catcher and Dodge Ball, plus Firefly Night for ADAM Pro, with a swarm of BOBs. Look around every page to see how they were made, then build them.", BTN_ON);
    if (_ex >= 0) { example_load(_ex); }
    if (ui_button("home_new", _bx + 200, _by, 80, 40, "New", "New project|Starts a blank project for the same machine.", BTN_NORMAL)) { home_new(); }
    if (ui_button("home_open", _bx + 288, _by, 80, 40, "Open", "Open project|Opens a .adam project file you saved earlier.", BTN_NORMAL)) { home_open(); }
    if (ui_button("home_save", _bx + 376, _by, 80, 40, "Save", "Save project|Saves your project (Ctrl+S). The first time it asks where to put it.", BTN_NORMAL)) { home_save(false); }
    if (ui_button("home_saveas", _bx + 464, _by, 96, 40, "Save as", "Save as|Saves a copy of your project under a new name.", BTN_GHOST)) { home_save(true); }

    // ---------- workflow cards: every editor, in top bar order, then the guided tour ----------
    var _cy = _y1 + 248;
    ui_panel(_x1, _cy, _split - 10, _y2, "How it works");
    ui_text(_split - 26, _cy + 19, "Click a card to open that page", global.TH.text_faint, fa_right, fa_top, global.f_small, 1);
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
    var _cols = 4;
    var _rows = ceil(_ncard / _cols);
    var _cw = floor((_split - 10 - _x1 - 32 - (_cols - 1) * 8) / _cols);
    // at 760 high a card is about 104 px: title row, then three lines of small text (60 px)
    var _ch = floor((_y2 - _cy - 50 - 12 - (_rows - 1) * 8) / _rows);
    for (var i = 0; i < _ncard; i++)
    {
        var _cx = _x1 + 16 + (i mod _cols) * (_cw + 8);
        var _cyy = _cy + 50 + (i div _cols) * (_ch + 8);
        var _id = "home_card_" + string(i);
        var _title = "Guided tour";
        var _num = "?";
        var _go = "Click to start it.";
        if (_dest[i] >= 0)
        {
            _title = ws_name(_dest[i]);
            _num = string(i + 1);
            _go = "Click to go to that page.";
        }
        var _hot = ui_register(_id, _cx, _cyy, _cx + _cw, _cyy + _ch, _title + "|" + _desc[i] + " " + _go);
        var _tgt = 0;
        if (_hot) { _tgt = 1; }
        var _a = ui_anim_to(_id, _tgt);
        ui_rrect(_cx, _cyy, _cx + _cw, _cyy + _ch, 12, merge_colour(global.TH.btn_top, global.TH.btn_hot_top, _a), merge_colour(global.TH.panel_bot, global.TH.btn_bot, _a), 1);
        ui_rrect_line(_cx, _cyy, _cx + _cw, _cyy + _ch, 12, merge_colour(global.TH.panel_edge, global.TH.accent, _a), 0.6 + 0.4 * _a, 1);
        ui_glow(_cx, _cyy, _cx + _cw, _cyy + _ch, 12, global.TH.accent, _a * 0.6);
        var _c1 = global.TH.accent;
        var _c2 = global.TH.accent_dark;
        if (_dest[i] < 0)
        {
            _c1 = global.TH.accent2;
            _c2 = merge_colour(global.TH.accent2, c_black, 0.35);
        }
        draw_circle_colour(_cx + 22, _cyy + 20, 12, _c1, _c2, false);
        ui_text(_cx + 22, _cyy + 20, _num, c_white, fa_center, fa_middle, global.f_bold, 1);
        ui_text(_cx + 42, _cyy + 20, ui_text_fit(_title, global.f_bold, _cw - 50), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        ui_text_wrap(_cx + 12, _cyy + 36, _desc[i], global.TH.text_dim, _cw - 22, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            ui_take_click();
            if (_dest[i] >= 0) { ws_set(_dest[i]); }
            else { tut_start(-1); }
        }
    }

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
