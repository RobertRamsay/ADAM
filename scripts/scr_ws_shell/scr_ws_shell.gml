/// ADAM - top bar, workspace switching, shortcuts

#macro WS_HOME 0
#macro WS_BACKDROP 1
#macro WS_SPRITES 2
#macro WS_ACTORS 3
#macro WS_LOGIC 4
#macro WS_SOUND 5
#macro WS_BUILD 6
#macro WS_LEVELS 7
#macro WS_COUNT 8

function ws_set(_i)
{
    if (ws == _i) { return; }
    ws = _i;
    ui_focus = "";
    ui_popup_open = false;
    if (!tut_active && auto_tutorials && !ws_seen[_i])
    {
        ws_seen[_i] = true;
        settings_save();
        tut_start(_i);
    }
}

/// Logo capsule: boing ball + "ADAM" + Amiga rainbow check. Returns its width.
function draw_logo(_x, _y)
{
    var _h = 34;
    var _r = _h * 0.5;
    draw_set_font(global.f_title);
    var _tw = ui_sw("ADAM");
    var _w = 10 + 26 + 10 + _tw + 14 + 22;
    ui_rrect(_x, _y + 2, _x + _w, _y + _h + 2, _r, c_black, c_black, 0.3);
    ui_rrect(_x, _y, _x + _w, _y + _h, _r, make_colour_rgb(68, 79, 96), make_colour_rgb(38, 45, 57), 1);
    ui_rrect(_x + 2, _y + 1, _x + _w - 2, _y + _h * 0.45, _r - 1, c_white, c_white, 0.06);
    ui_rrect_line(_x, _y, _x + _w, _y + _h, _r, global.TH.panel_edge, 0.8, 1);
    draw_boing(_x + 8, _y + 4, 26, 1);
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
    var _logo_w = draw_logo(14, 13);

    // machine badge
    var _m = machine_cur();
    var _mx = 14 + _logo_w + 12;
    var _mw = 150;
    var _mst = BTN_NORMAL;
    if (_m.aga) { _mst = BTN_ON; }
    if (ui_button("top_machine", _mx, 14, _mw, 32, _m.short_name, "Target machine|" + _m.name + ": " + _m.chipset + ", " + _m.cpu + ", " + _m.ram_label + ". Click to change the machine this game is made for.", _mst))
    {
        machine_pick_open(false);
    }

    var _tabs = ws_tabs();
    var _nt = array_length(_tabs);
    var _tw = 96;
    var _tx = _mx + _mw + 18;
    var _avail = _gw - _tx - 380;
    if (_avail < _tw * _nt) { _tw = max(64, floor(_avail / _nt)); }
    ui_rrect(_tx - 6, 11, _tx + _tw * _nt + 6, 49, 19, global.TH.inset_top, global.TH.inset_bot, 0.8);
    for (var i = 0; i < _nt; i++)
    {
        var _w = _tabs[i];
        if (ui_tab("tab_" + string(_w), _tx + i * _tw, 14, _tw - 2, 32, ui_text_fit(ws_name(_w), global.f_bold, _tw - 10), ws == _w, ws_help(_w)))
        {
            ws_set(_w);
        }
    }

    var _rx = _gw - 14;
    _rx -= 104;
    if (ui_button("top_tutorial", _rx, 14, 104, 32, "Tutorial (F1)", "Tutorial|Shows a step-by-step guide for the page you are on. Every page has its own tutorial.", BTN_ACCENT))
    {
        tut_start(ws);
    }
    _rx -= 108;
    var _hlab = "Helpers off";
    var _hsty = BTN_NORMAL;
    if (helpers_on)
    {
        _hlab = "Helpers on";
        _hsty = BTN_ON;
    }
    if (ui_button("top_helpers", _rx, 14, 102, 32, _hlab, "Hover helpers|When on, resting the mouse on any control draws guide lines and a help bubble explaining it.", _hsty))
    {
        helpers_on = !helpers_on;
        settings_save();
    }
    var _pg = ws_name(ws);
    _rx -= 70;
    var _rst = BTN_GHOST;
    if (redo_count() > 0) { _rst = BTN_NORMAL; }
    if (ui_button("top_redo", _rx, 14, 64, 32, "Redo", "Redo (" + _pg + ")|Puts back the last change you undid on this page (" + string(redo_count()) + " to redo). Every page keeps its own history. Shortcut: Ctrl+Y.", _rst))
    {
        redo_do();
    }
    _rx -= 70;
    var _ust = BTN_GHOST;
    if (undo_count() > 0) { _ust = BTN_NORMAL; }
    if (ui_button("top_undo", _rx, 14, 64, 32, "Undo", "Undo (" + _pg + ")|Takes back your last change on this page (" + string(undo_count()) + " to undo). Every page keeps its own history, so undoing here never touches the other pages. Shortcut: Ctrl+Z.", _ust))
    {
        undo_do();
    }
    if (undo_count() > 0)
    {
        draw_circle_colour(_rx + 60, 18, 7, global.TH.accent, global.TH.accent_dark, false);
        ui_text(_rx + 60, 18, string(min(99, undo_count())), c_white, fa_center, fa_middle, global.f_small, 1);
    }
}

function shortcuts_step()
{
    if (ui_focus != "") { return; }
    if (machine_pick_active) { return; }
    var _ctrl = keyboard_check(vk_control);
    if (_ctrl && keyboard_check_pressed(ord("Z"))) { undo_do(); }
    if (_ctrl && keyboard_check_pressed(ord("Y"))) { redo_do(); }
    if (_ctrl && keyboard_check_pressed(ord("S"))) { home_save(false); }
    if (_ctrl && keyboard_check_pressed(ord("B"))) { build_ws_build(false); }
    if (_ctrl && (keyboard_check_pressed(187) || keyboard_check_pressed(vk_add))) { ui_scale_step(1); }
    if (_ctrl && (keyboard_check_pressed(189) || keyboard_check_pressed(vk_subtract))) { ui_scale_step(-1); }
    if (_ctrl && keyboard_check_pressed(ord("0"))) { ui_scale_pref = 0; settings_save(); toast("Interface size: auto", 0); }
    if (keyboard_check_pressed(vk_f1))
    {
        if (tut_active) { tut_active = false; }
        else { tut_start(ws); }
    }
    if (!tut_active && !_ctrl)
    {
        var _tabs = ws_tabs();
        for (var i = 0; i < min(9, array_length(_tabs)); i++)
        {
            if (keyboard_check_pressed(ord(string(i + 1)))) { ws_set(_tabs[i]); }
        }
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
    return [WS_HOME, WS_BACKDROP, WS_LEVELS, WS_SPRITES, WS_ACTORS, WS_LOGIC, WS_SOUND, WS_BUILD];
}

function ws_name(_w)
{
    var _n = ["Home", "Backdrop", "Sprites", "Actors", "Logic", "Sound", "Build", "Levels"];
    return _n[_w];
}

function ws_help(_w)
{
    var _h = [
        "Home|Start here: open or create projects, pick the Amiga, and set game-wide options.",
        "Backdrop|Paint the 320 x 256 background picture, choose its colours, or import a picture.",
        "Sprites|Draw up to 32 sprite pictures, 16 x 24 pixels with 3 colours each, for your players, enemies and pickups.",
        "Actors|Place the things that move: the player, enemies and pickups. Choose how each one behaves.",
        "Logic|Make the game rules in plain English: WHEN something happens, DO something.",
        "Sound|Design up to 8 sound effects for the Amiga's Paula chip and hear them instantly.",
        "Build|Turn your game into a bootable Amiga disk (.ADF) and play it in FS-UAE or on a real Amiga.",
        "Levels|Up to 10 levels, each with its own hills grown from a seed and shaped by hand. Also the level goal counter and the title screen."
    ];
    return _h[_w];
}
