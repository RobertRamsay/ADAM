/// ADAM - top bar, workspace switching, shortcuts

#macro WS_HOME 0
#macro WS_BACKDROP 1
#macro WS_SPRITES 2
#macro WS_ACTORS 3
#macro WS_LOGIC 4
#macro WS_SOUND 5
#macro WS_BUILD 6
#macro WS_LEVELS 7
#macro WS_MUSIC 8
#macro WS_ANIMATE 9
#macro WS_TILES 10
#macro WS_UI 11
#macro WS_COUNT 12

function ws_set(_i)
{
    if (ws == _i) { return; }
    if (ws == WS_SOUND && mus_playing && (mus_play_what == "sound" || mus_play_what == "sound_note")) { sfx_preview_stop(); }
    ws = _i;
    ui_focus = "";
    ui_popup_open = false;
    // an offer for the page we are leaving no longer applies
    tut_offer_on = false;
    if (!tut_active && !les_active && auto_tutorials && !ws_seen[_i])
    {
        ws_seen[_i] = true;
        settings_save();
        tut_offer(_i);
    }
}

/// Logo capsule: boing ball + "ADAM" + Amiga rainbow check (just the ball
/// when _compact, for narrow windows). Returns its width.
function draw_logo(_x, _y, _compact)
{
    var _h = 34;
    var _r = _h * 0.5;
    draw_set_font(global.f_title);
    var _tw = ui_sw("ADAM");
    var _w = 10 + 26 + 10 + _tw + 14 + 22;
    if (_compact) { _w = 42; }
    ui_rrect(_x, _y + 2, _x + _w, _y + _h + 2, _r, c_black, c_black, 0.3);
    ui_rrect(_x, _y, _x + _w, _y + _h, _r, make_colour_rgb(68, 79, 96), make_colour_rgb(38, 45, 57), 1);
    ui_rrect(_x + 2, _y + 1, _x + _w - 2, _y + _h * 0.45, _r - 1, c_white, c_white, 0.06);
    ui_rrect_line(_x, _y, _x + _w, _y + _h, _r, global.TH.panel_edge, 0.8, 1);

    // the ball doubles as the quit button: hovered, it fades into an X (0.4 s)
    var _qhot = ui_register("top_quit", _x + 2, _y, _x + 40, _y + _h, "Quit ADAM|Click to close ADAM. Your work is kept: it opens again next time you start ADAM.");
    var _qstep = (delta_time / 1000000) / 0.4;
    if (_qhot) { logo_quit_k = min(1, logo_quit_k + _qstep); }
    else { logo_quit_k = max(0, logo_quit_k - _qstep); }
    var _qk = logo_quit_k;
    if (_qk < 1) { draw_boing(_x + 8, _y + 4, 26, 1 - _qk); }
    if (_qk > 0)
    {
        var _qx = _x + 21;
        var _qy = _y + 17;
        draw_set_alpha(_qk);
        draw_circle_colour(_qx, _qy, 13, global.TH.danger, global.TH.danger_dark, false);
        draw_set_colour(c_white);
        draw_line_width(_qx - 5, _qy - 5, _qx + 5, _qy + 5, 3);
        draw_line_width(_qx - 5, _qy + 5, _qx + 5, _qy - 5, 3);
        draw_set_alpha(1);
    }
    if (_qhot && ui_pressed)
    {
        ui_take_click();
        app_quit_ask();
    }
    if (_compact) { return _w; }
    ui_text(_x + 44, _y + _h * 0.5, "ADAM", c_white, fa_left, fa_middle, global.f_title, 1);
    // the four Amiga "checkmark" stripes
    var _stripes = [make_colour_rgb(230, 60, 50), make_colour_rgb(250, 160, 40), make_colour_rgb(90, 190, 90), make_colour_rgb(60, 130, 230)];
    var _sx = _x + 44 + _tw + 8;
    for (var i = 0; i < 4; i++)
    {
        draw_set_colour(_stripes[i]);
        var _ox = _sx + i * 4;
        draw_primitive_begin(pr_trianglestrip);
        draw_vertex(_ox, _y + _h - 9);
        draw_vertex(_ox + 3, _y + _h - 9);
        draw_vertex(_ox + 9, _y + 9);
        draw_vertex(_ox + 12, _y + 9);
        draw_primitive_end();
    }
    return _w;
}

function draw_topbar(_gw)
{
    ui_rrect(0, -20, _gw, 60, 0, global.TH.bar_top, global.TH.bar_bot, 1);
    draw_line_colour(0, 60, _gw, 60, global.TH.panel_edge, global.TH.panel_edge);
    draw_set_alpha(0.25);
    draw_line_colour(0, 61, _gw, 61, c_black, c_black);
    draw_set_alpha(1);

    // widths of the right-hand buttons, sized from their labels so they are never cut short
    var _tabs = ws_tabs();
    var _nt = array_length(_tabs);
    var _tutlab = "Learn ADAM";
    var _playlab = "Build & play (F5)";
    draw_set_font(global.f_bold);
    var _tutw = max(104, ceil(ui_sw(_tutlab)) + 24);
    var _playw = ceil(ui_sw(_playlab)) + 28;
    var _helpw = 102;
    // the page tab labels: a tab needs its label + 12 (ui_tab fits text to its width - 10)
    var _lsum = 0;
    for (var tl = 0; tl < _nt; tl++) { _lsum += ceil(ui_sw(ws_name(_tabs[tl]))); }
    var _udw = 64;
    draw_set_font(global.f_title);
    var _logo_full = 10 + 26 + 10 + ui_sw("ADAM") + 14 + 22;
    // narrow window: if the page tabs would get squeezed, use the compact bar -
    // just the ball for the logo, shorter labels and no Helpers button (it is on Home too).
    // At 1280 wide only the compact bar fits the 12 tabs (labels are about 590 px together).
    var _full_avail = _gw - (14 + _logo_full + 10 + 54 + 8 + 150 + 18) - (14 + _tutw + 6 + _helpw + 6 + 64 + 6 + 64 + 12 + _playw + 12);
    var _compact = (_full_avail < _lsum + 16 * _nt);
    var _mw = 150;
    var _mlab = machine_cur().short_name;
    if (_compact)
    {
        _tutlab = "Learn";
        _playlab = "Play";          // F5 is in its help bubble
        draw_set_font(global.f_bold);
        _tutw = ceil(ui_sw(_tutlab)) + 24;
        _playw = ceil(ui_sw(_playlab)) + 24;
        _helpw = 0;
        _udw = 58;
        // the machine without its memory ("A500/600", "A1200"); the help bubble has the rest
        var _sp = string_pos(" ", _mlab);
        if (_sp > 1) { _mlab = string_copy(_mlab, 1, _sp - 1); }
        _mw = ceil(ui_sw(_mlab)) + 24;
    }

    var _logo_w = draw_logo(14, 13, _compact);

    // edition chip: LITE or PRO (ADAM_PRO in scr_licence) - opens the ADAM Pro tab
    var _ex = 14 + _logo_w + 10;
    var _ew = 54;
    var _elab = "LITE";
    var _est = BTN_GHOST;
    var _ehelp = "ADAM Lite|This is the free edition, with every feature. Click to see the extra games and lessons ADAM Pro adds.";
    if (pro_edition())
    {
        _elab = "PRO";
        _est = BTN_ON;
        _ehelp = "ADAM Pro|Every feature, plus the extra example games and lessons.";
    }
    if (ui_button("top_edition", _ex, 14, _ew, 32, _elab, _ehelp, _est))
    {
        about_open_pro();
    }

    // machine badge
    var _m = machine_cur();
    var _mx = _ex + _ew + 8;
    var _mst = BTN_NORMAL;
    if (_m.aga) { _mst = BTN_ON; }
    if (ui_button("top_machine", _mx, 14, _mw, 32, _mlab, "Target machine|" + _m.name + ": " + _m.chipset + ", " + _m.cpu + ", " + _m.ram_label + ". Click to change the machine this game is made for.", _mst))
    {
        machine_pick_open(false);
    }

    // page tabs share what is left
    var _right = 14 + _tutw + 6 + _udw + 6 + _udw + 12 + _playw + 12;
    if (_helpw > 0) { _right += _helpw + 6; }
    var _tw = 96;
    var _tx = _mx + _mw + 18;
    var _avail = _gw - _tx - _right;
    // each tab 96 wide when there is room; otherwise sized to its label plus an
    // even share of the space, so "Backdrop" and "Animate" are not cut short
    var _tws = array_create(_nt, _tw);
    if (_avail < _tw * _nt)
    {
        draw_set_font(global.f_bold);
        for (var t0 = 0; t0 < _nt; t0++)
        {
            _tws[t0] = ceil(ui_sw(ws_name(_tabs[t0])));
        }
        var _pad = floor((_avail - _lsum) / _nt);
        if (_pad >= 12)
        {
            for (var t1 = 0; t1 < _nt; t1++) { _tws[t1] += _pad; }
        }
        else
        {
            for (var t2 = 0; t2 < _nt; t2++) { _tws[t2] = max(56, floor(_avail / _nt)); }
        }
    }
    var _tsum = 0;
    for (var t3 = 0; t3 < _nt; t3++) { _tsum += _tws[t3]; }
    ui_rrect(_tx - 6, 11, _tx + _tsum + 6, 49, 19, global.TH.inset_top, global.TH.inset_bot, 0.8);
    var _tabx = _tx;
    for (var i = 0; i < _nt; i++)
    {
        var _w = _tabs[i];
        if (ui_tab("tab_" + string(_w), _tabx, 14, _tws[i] - 2, 32, ui_text_fit(ws_name(_w), global.f_bold, _tws[i] - 10), ws == _w, ws_help(_w)))
        {
            ws_set(_w);
        }
        _tabx += _tws[i];
    }

    var _rx = _gw - 14;
    _rx -= _tutw;
    // Learn ADAM: this page's tutorial (F1), the guided tour and the lessons
    var _learn = ui_menu_button("top_learn", _rx, 14, _tutw, 32, _tutlab, learn_menu_names(), "Learn ADAM|This page's tutorial (also F1), the guided tour of every page, and lessons that each make a whole game step by step: Basics, Beginner, Intermediate and Experienced, then BOBs for ADAM Pro.", BTN_ACCENT);
    if (_learn == 0) { tut_start(ws); }
    if (_learn == 1) { tut_start(-1); }
    if (_learn >= 2 && _learn < 2 + array_length(les_defs)) { lesson_start(_learn - 2); }
    if (_learn == 2 + array_length(les_defs)) { whatsnew_open(true); }
    if (_helpw > 0)
    {
        _rx -= _helpw + 6;
        var _hlab = "Helpers off";
        var _hsty = BTN_NORMAL;
        if (helpers_on)
        {
            _hlab = "Helpers on";
            _hsty = BTN_ON;
        }
        if (ui_button("top_helpers", _rx, 14, _helpw, 32, _hlab, "Hover helpers|When on, resting the mouse on any control draws guide lines and a help bubble explaining it.", _hsty))
        {
            helpers_on = !helpers_on;
            settings_save();
        }
    }
    var _pg = ws_name(ws);
    _rx -= _udw + 6;
    var _rst = BTN_GHOST;
    if (redo_count() > 0) { _rst = BTN_NORMAL; }
    if (ui_button("top_redo", _rx, 14, _udw, 32, "Redo", "Redo (" + _pg + ")|Puts back the last change you undid on this page (" + string(redo_count()) + " to redo). Every page keeps its own history. Shortcut: Ctrl+Y.", _rst))
    {
        redo_do();
    }
    _rx -= _udw + 6;
    var _ust = BTN_GHOST;
    if (undo_count() > 0) { _ust = BTN_NORMAL; }
    if (ui_button("top_undo", _rx, 14, _udw, 32, "Undo", "Undo (" + _pg + ")|Takes back your last change on this page (" + string(undo_count()) + " to undo). Every page keeps its own history, so undoing here never touches the other pages. Shortcut: Ctrl+Z.", _ust))
    {
        undo_do();
    }
    if (undo_count() > 0)
    {
        draw_circle_colour(_rx + _udw - 4, 18, 7, global.TH.accent, global.TH.accent_dark, false);
        ui_text(_rx + _udw - 4, 18, string(min(99, undo_count())), c_white, fa_center, fa_middle, global.f_small, 1);
    }
    _rx -= _playw + 12;
    if (ui_button("top_play", _rx, 14, _playw, 32, _playlab, "Build and play|Builds your game's .ADF disk and boots it in FS-UAE straight away, from any page - the same as Build and play on the Build page. Shortcut: F5.", BTN_ACCENT))
    {
        build_ws_build(true);
    }
}

function shortcuts_step()
{
    var _music_keys = (ws == WS_MUSIC && mus_ed_keys_hover);
    mus_ed_keys_hover = false;   // the music editor sets it again while it draws
    if (ui_focus != "") { return; }
    if (machine_pick_active) { return; }
    if (about_active) { return; }
    if (confirm_active) { return; }
    if (whatsnew_active) { return; }
    var _ctrl = keyboard_check(vk_control);
    if (_ctrl && keyboard_check_pressed(ord("Z"))) { undo_do(); }
    if (_ctrl && keyboard_check_pressed(ord("Y"))) { redo_do(); }
    if (_ctrl && keyboard_check_pressed(ord("S")) && !(ws == WS_ANIMATE && anim_test)) { home_save(false); }
    if (_ctrl && keyboard_check_pressed(ord("B"))) { build_ws_build(false); }
    if (keyboard_check_pressed(vk_f5)) { build_ws_build(true); }
    if (_ctrl && (keyboard_check_pressed(187) || keyboard_check_pressed(vk_add))) { ui_scale_step(1); }
    if (_ctrl && (keyboard_check_pressed(189) || keyboard_check_pressed(vk_subtract))) { ui_scale_step(-1); }
    if (_ctrl && keyboard_check_pressed(ord("0"))) { ui_scale_pref = 0; settings_save(); toast("Interface size: auto", 0); }
    if (keyboard_check_pressed(vk_f1))
    {
        if (tut_active) { tut_active = false; }
        else { tut_start(ws); }
    }
    if (!tut_active && !_ctrl && !(ws == WS_SOUND && proj.sfx[snd_sel].kind == 1 && proj.sfx[snd_sel].smp != ""))
    {
        var _tabs = ws_tabs();
        for (var i = 0; i < min(9, array_length(_tabs)); i++)
        {
            if (_music_keys && i < 4) { continue; }   // 1-4 = grid snap in the music editor
            if (keyboard_check_pressed(ord(string(i + 1)))) { ws_set(_tabs[i]); }
        }
        if (array_length(_tabs) >= 10 && keyboard_check_pressed(ord("0"))) { ws_set(_tabs[array_length(_tabs) - 1]); }   // 0 = Build
    }
}

/// Steps the interface size up or down through the preset list
function ui_scale_step(_d)
{
    var _vals = global.UI_SCALE_VALUES;
    var _cur = ui_scale_pref;
    if (_cur == 0) { _cur = global.ui_scale; }
    var _best = 1;
    for (var i = 1; i < array_length(_vals); i++)
    {
        if (abs(_vals[i] - _cur) < abs(_vals[_best] - _cur)) { _best = i; }
    }
    _best = clamp(_best + _d, 1, array_length(_vals) - 1);
    ui_scale_pref = _vals[_best];
    settings_save();
    toast("Interface size: " + global.UI_SCALE_NAMES[_best], 0);
}

function ws_tabs()
{
    return [WS_HOME, WS_BACKDROP, WS_TILES, WS_LEVELS, WS_SPRITES, WS_ACTORS, WS_ANIMATE, WS_UI, WS_LOGIC, WS_SOUND, WS_MUSIC, WS_BUILD];
}

function ws_name(_w)
{
    var _n = ["Home", "Backdrop", "Sprites", "Actors", "Logic", "Sound", "Build", "Levels", "Music", "Animate", "Tiles", "UI"];
    return _n[_w];
}

function ws_help(_w)
{
    var _h = [
        "Home|Start here: open or create projects, pick the Amiga, and set game-wide options.",
        "Backdrop|Paint the 320 x 256 background picture, choose its colours, or import a picture.",
        "Sprites|Draw up to 128 sprite pictures, 16 x 24 pixels with 3 colours each, for your players, enemies and pickups.",
        "Actors|Place the things that move: the player, enemies and pickups. Choose how each one behaves.",
        "Logic|Make the game rules in plain English: WHEN something happens, DO something.",
        "Sound|Design up to 8 sound effects for the Amiga's Paula chip and hear them instantly.",
        "Build|Turn your game into a bootable Amiga disk (.ADF) and play it in FS-UAE or on a real Amiga.",
        "Levels|Up to 10 levels, each with its own hills grown from a seed and shaped by hand. Also the level goal counter and the title screen.",
        "Music|Make up to 4 songs from ready-made loops on Paula's 4 channels, edit their notes, and choose the music for each level.",
        "Animate|Give each actor Idle, Walk, Jump and Fall animations from the sprite bank (6 frames each in ADAM Lite, 16 in ADAM Pro). The Amiga picks the right one as the actor moves.",
        "Tiles|Draw a tile set - tiles of 8 x 8 up to 64 x 64 pixels, 96 kinds in ADAM Lite, 512 in Pro - and paint a tile world (up to 256 x 256 tiles in Lite, 1024 x 1024 in Pro) that scrolls both ways - with digging and placing tiles, Terraria style.",
        "UI|ADAM Pro: design the game's HUD - a framed panel (metal, wood, stone, neon, parchment or your own 9-slice frame), a font style or your own font, and fields for score, lives, the goal, the tile carried, the level and text, each with its own place, colour and shadow."
    ];
    return _h[_w];
}
