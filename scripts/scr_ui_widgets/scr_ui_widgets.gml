/// ADAM - immediate-mode widgets (run in obj_app scope)
/// Help strings use "Title|Longer explanation" format.

#macro BTN_NORMAL 0
#macro BTN_ACCENT 1
#macro BTN_DANGER 2
#macro BTN_GHOST  3
#macro BTN_ON     4

function ui_frame_begin()
{
    ui_mx = device_mouse_x_to_gui(0);
    ui_my = device_mouse_y_to_gui(0);
    ui_pressed  = mouse_check_button_pressed(mb_left);
    ui_held     = mouse_check_button(mb_left);
    ui_released = mouse_check_button_released(mb_left);
    ui_rpressed = mouse_check_button_pressed(mb_right);
    ui_rheld    = mouse_check_button(mb_right);
    ui_pressed_raw = ui_pressed;
    ui_focus_claimed = false;
    ui_wheel = 0;
    if (mouse_wheel_up())   { ui_wheel = 1; }
    if (mouse_wheel_down()) { ui_wheel = -1; }

    ui_hot_prev = ui_hot;
    ui_hot = "";
    ui_help_title = "";
    ui_help_body = "";
    ui_force_input = false;
    ui_clip_on = false;
    ds_map_clear(ui_rects);

    ui_input_ok = true;
    if (ui_popup_open)
    {
        ui_input_ok = false;
    }
    if (machine_pick_active)
    {
        ui_input_ok = false;
    }
    if (tut_active)
    {
        ui_input_ok = false;
        if (tut_allow_target && array_length(tut_target_rect) == 4)
        {
            var _r = tut_target_rect;
            if (point_in_rectangle(ui_mx, ui_my, _r[0] - 4, _r[1] - 4, _r[2] + 4, _r[3] + 4))
            {
                if (!point_in_rectangle(ui_mx, ui_my, tut_card_rect[0], tut_card_rect[1], tut_card_rect[2], tut_card_rect[3]))
                {
                    ui_input_ok = true;
                }
            }
        }
    }
    if (!ui_held)
    {
        ui_drag_id = "";
    }
}

function ui_frame_end()
{
    if (ui_pressed_raw && !ui_focus_claimed)
    {
        ui_focus = "";
    }
    if (ui_hot != "" && ui_hot == ui_hot_prev)
    {
        ui_hot_time += delta_time / 1000000;
    }
    else
    {
        ui_hot_time = 0;
    }
}

function ui_can_input()
{
    if (ui_force_input) { return true; }
    return ui_input_ok;
}

function ui_hit(_x1, _y1, _x2, _y2)
{
    if (!ui_can_input()) { return false; }
    if (!point_in_rectangle(ui_mx, ui_my, _x1, _y1, _x2, _y2)) { return false; }
    if (ui_clip_on)
    {
        if (!point_in_rectangle(ui_mx, ui_my, ui_clip[0], ui_clip[1], ui_clip[2], ui_clip[3])) { return false; }
    }
    return true;
}

/// Registers a control's rect (for tutorials) and its hover help. Returns hovered.
function ui_register(_id, _x1, _y1, _x2, _y2, _help)
{
    ds_map_replace(ui_rects, _id, [_x1, _y1, _x2, _y2]);
    var _hot = ui_hit(_x1, _y1, _x2, _y2);
    if (_hot)
    {
        ui_hot = _id;
        ui_hot_rect = [_x1, _y1, _x2, _y2];
        var _bar = string_pos("|", _help);
        if (_bar > 0)
        {
            ui_help_title = string_copy(_help, 1, _bar - 1);
            ui_help_body = string_delete(_help, 1, _bar);
        }
        else
        {
            ui_help_title = _help;
            ui_help_body = "";
        }
    }
    return _hot;
}

function ui_anim_to(_id, _target)
{
    var _v = ds_map_find_value(ui_anim, _id);
    if (is_undefined(_v)) { _v = 0; }
    _v = lerp(_v, _target, 0.22);
    if (abs(_v - _target) < 0.01) { _v = _target; }
    ds_map_replace(ui_anim, _id, _v);
    return _v;
}

function ui_take_click()
{
    ui_pressed = false;
}

function ui_button(_id, _x, _y, _w, _h, _label, _help, _style)
{
    var _hot = ui_register(_id, _x, _y, _x + _w, _y + _h, _help);
    var _tgt = 0;
    if (_hot) { _tgt = 1; }
    var _a = ui_anim_to(_id, _tgt);
    var _down = false;
    if (_hot && ui_held) { _down = true; }
    var _r = min(global.TH.radius, _h * 0.5);

    var _ct = merge_colour(global.TH.btn_top, global.TH.btn_hot_top, _a);
    var _cb = merge_colour(global.TH.btn_bot, global.TH.btn_hot_bot, _a);
    var _tc = global.TH.text;
    var _edge = global.TH.panel_edge;
    switch (_style)
    {
        case BTN_ACCENT:
            _ct = merge_colour(global.TH.accent, c_white, _a * 0.15);
            _cb = merge_colour(global.TH.accent_dark, global.TH.accent, _a * 0.25);
            _tc = c_white;
            _edge = global.TH.accent;
            break;
        case BTN_DANGER:
            _ct = merge_colour(global.TH.danger, c_white, _a * 0.12);
            _cb = global.TH.danger_dark;
            _tc = c_white;
            _edge = global.TH.danger;
            break;
        case BTN_GHOST:
            _ct = merge_colour(global.TH.panel_top, global.TH.btn_hot_top, _a);
            _cb = merge_colour(global.TH.panel_bot, global.TH.btn_hot_bot, _a);
            _edge = global.TH.panel_edge;
            break;
        case BTN_ON:
            _ct = merge_colour(global.TH.accent2, c_white, _a * 0.12);
            _cb = merge_colour(make_colour_rgb(46, 140, 116), global.TH.accent2, _a * 0.2);
            _tc = make_colour_rgb(16, 30, 28);
            _edge = global.TH.accent2;
            break;
    }
    var _oy = 0;
    if (_down) { _oy = 1; }
    if (_style != BTN_GHOST || _a > 0.05)
    {
        ui_rrect(_x, _y + 2, _x + _w, _y + _h + 2, _r, c_black, c_black, 0.25);
    }
    var _alpha = 1;
    if (_style == BTN_GHOST) { _alpha = 0.35 + 0.65 * _a; }
    ui_rrect(_x, _y + _oy, _x + _w, _y + _h + _oy, _r, _ct, _cb, _alpha);
    ui_rrect_line(_x, _y + _oy, _x + _w, _y + _h + _oy, _r, _edge, 0.45 + 0.4 * _a, 1);
    ui_rrect(_x + 2, _y + 1 + _oy, _x + _w - 2, _y + _h * 0.45 + _oy, _r - 1, c_white, c_white, 0.06);
    ui_glow(_x, _y + _oy, _x + _w, _y + _h + _oy, _r, global.TH.accent, _a * 0.8);
    var _lab = ui_text_fit(_label, global.f_bold, _w - 12);
    ui_text(_x + _w * 0.5, _y + _h * 0.5 + _oy, _lab, _tc, fa_center, fa_middle, global.f_bold, 1);

    if (_hot && ui_pressed)
    {
        ui_take_click();
        return true;
    }
    return false;
}

function ui_tab(_id, _x, _y, _w, _h, _label, _selected, _help)
{
    var _hot = ui_register(_id, _x, _y, _x + _w, _y + _h, _help);
    var _tgt = 0;
    if (_hot) { _tgt = 1; }
    var _a = ui_anim_to(_id, _tgt);
    var _s = 0;
    if (_selected) { _s = 1; }
    var _sa = ui_anim_to(_id + "_sel", _s);
    var _r = _h * 0.5;
    if (_sa > 0.02)
    {
        ui_rrect(_x, _y, _x + _w, _y + _h, _r, global.TH.accent, global.TH.accent_dark, _sa);
        ui_glow(_x, _y, _x + _w, _y + _h, _r, global.TH.accent, _sa * 0.6);
    }
    if (_a > 0.02 && !_selected)
    {
        ui_rrect(_x, _y, _x + _w, _y + _h, _r, global.TH.btn_hot_top, global.TH.btn_hot_bot, _a * 0.8);
    }
    var _tc = merge_colour(global.TH.text_dim, global.TH.text, max(_a, _sa));
    if (_selected) { _tc = c_white; }
    ui_text(_x + _w * 0.5, _y + _h * 0.5, _label, _tc, fa_center, fa_middle, global.f_bold, 1);
    if (_hot && ui_pressed)
    {
        ui_take_click();
        return true;
    }
    return false;
}

function ui_label(_x, _y, _str)
{
    ui_text(_x, _y, _str, global.TH.text_dim, fa_left, fa_top, global.f_small, 1);
}

function ui_toggle(_id, _x, _y, _label, _value, _help)
{
    draw_set_font(global.f_body);
    var _tw = ui_sw(_label);
    var _w = 44 + 10 + _tw;
    var _hot = ui_register(_id, _x, _y, _x + _w, _y + 24, _help);
    var _tgt = 0;
    if (_value) { _tgt = 1; }
    var _k = ui_anim_to(_id, _tgt);
    var _h = 0;
    if (_hot) { _h = 1; }
    var _ha = ui_anim_to(_id + "_h", _h);
    var _track = merge_colour(make_colour_rgb(30, 35, 43), global.TH.accent2, _k);
    ui_rrect(_x, _y + 2, _x + 44, _y + 22, 10, merge_colour(_track, c_white, 0.08), _track, 1);
    ui_rrect_line(_x, _y + 2, _x + 44, _y + 22, 10, global.TH.panel_edge, 0.6, 1);
    var _kx = _x + 12 + _k * 20;
    draw_set_alpha(0.3);
    draw_circle_colour(_kx, _y + 14, 9, c_black, c_black, false);
    draw_set_alpha(1);
    draw_circle_colour(_kx, _y + 12, 8, c_white, make_colour_rgb(210, 216, 226), false);
    ui_glow(_x, _y + 2, _x + 44, _y + 22, 10, global.TH.accent, _ha * 0.6);
    ui_text(_x + 54, _y + 12, _label, global.TH.text, fa_left, fa_middle, global.f_body, 1);
    if (_hot && ui_pressed)
    {
        ui_take_click();
        return !_value;
    }
    return _value;
}

function ui_stepper(_id, _x, _y, _w, _value, _min, _max, _help)
{
    var _h = 30;
    ui_register(_id, _x, _y, _x + _w, _y + _h, _help);
    var _v = _value;
    var _step = 1;
    if (keyboard_check(vk_shift)) { _step = 10; }
    ui_inset(_x, _y, _x + _w, _y + _h, 9);
    if (ui_button(_id + "_m", _x + 3, _y + 3, 24, _h - 6, "-", _help, BTN_GHOST))
    {
        _v = max(_min, _v - _step);
    }
    if (ui_button(_id + "_p", _x + _w - 27, _y + 3, 24, _h - 6, "+", _help, BTN_GHOST))
    {
        _v = min(_max, _v + _step);
    }
    if (ui_hit(_x, _y, _x + _w, _y + _h) && ui_wheel != 0)
    {
        _v = clamp(_v + ui_wheel * _step, _min, _max);
        ui_wheel = 0;
    }
    ui_text(_x + _w * 0.5, _y + _h * 0.5, string(_v), global.TH.text, fa_center, fa_middle, global.f_bold, 1);
    if (ui_hot == _id || ui_hot == _id + "_m" || ui_hot == _id + "_p")
    {
        ui_rrect_line(_x, _y, _x + _w, _y + _h, 9, global.TH.accent, 0.6, 1);
    }
    return _v;
}

function ui_slider(_id, _x, _y, _w, _value, _min, _max, _help)
{
    var _h = 26;
    var _hot = ui_register(_id, _x, _y, _x + _w, _y + _h, _help);
    if (_hot && ui_pressed)
    {
        ui_drag_id = _id;
        ui_take_click();
    }
    var _v = _value;
    if (ui_drag_id == _id && ui_held)
    {
        var _t = clamp((ui_mx - (_x + 8)) / max(1, _w - 16), 0, 1);
        _v = round(_min + _t * (_max - _min));
    }
    if (_hot && ui_wheel != 0)
    {
        _v = clamp(_v + ui_wheel, _min, _max);
        ui_wheel = 0;
    }
    var _t2 = (_v - _min) / max(1, _max - _min);
    var _cy = _y + _h * 0.5;
    ui_rrect(_x, _cy - 4, _x + _w, _cy + 4, 4, global.TH.inset_top, global.TH.inset_bot, 1);
    ui_rrect(_x, _cy - 4, _x + 8 + _t2 * (_w - 16), _cy + 4, 4, global.TH.accent, global.TH.accent_dark, 1);
    var _kx = _x + 8 + _t2 * (_w - 16);
    var _ht = 0;
    if (_hot || ui_drag_id == _id) { _ht = 1; }
    var _a = ui_anim_to(_id, _ht);
    draw_circle_colour(_kx, _cy, 8 + _a * 2, c_white, make_colour_rgb(200, 208, 220), false);
    if (_a > 0.05)
    {
        draw_set_alpha(0.25 * _a);
        draw_circle_colour(_kx, _cy, 15, global.TH.accent, global.TH.accent, false);
        draw_set_alpha(1);
    }
    return _v;
}

function ui_textfield(_id, _x, _y, _w, _h, _value, _maxlen, _help)
{
    var _hot = ui_register(_id, _x, _y, _x + _w, _y + _h, _help);
    var _v = _value;
    if (_hot && ui_pressed)
    {
        ui_focus = _id;
        keyboard_string = _v;
        ui_take_click();
    }
    if (_hot && ui_pressed_raw)
    {
        ui_focus_claimed = true;
    }
    if (ui_focus == _id)
    {
        if (string_length(keyboard_string) > _maxlen)
        {
            keyboard_string = string_copy(keyboard_string, 1, _maxlen);
        }
        _v = keyboard_string;
        if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_escape))
        {
            ui_focus = "";
        }
    }
    ui_inset(_x, _y, _x + _w, _y + _h, 8);
    var _f = 0;
    if (ui_focus == _id) { _f = 1; }
    var _fa = ui_anim_to(_id + "_f", _f);
    if (_fa > 0.02)
    {
        ui_rrect_line(_x, _y, _x + _w, _y + _h, 8, global.TH.accent, _fa, 2);
    }
    else
    {
        if (_hot)
        {
            ui_rrect_line(_x, _y, _x + _w, _y + _h, 8, global.TH.accent, 0.4, 1);
        }
    }
    var _shown = ui_text_fit(_v, global.f_body, _w - 20);
    ui_text(_x + 10, _y + _h * 0.5, _shown, global.TH.text, fa_left, fa_middle, global.f_body, 1);
    if (ui_focus == _id && (current_time div 500) mod 2 == 0)
    {
        draw_set_font(global.f_body);
        var _cx = _x + 11 + ui_sw(_shown);
        draw_line_width_colour(_cx, _y + 7, _cx, _y + _h - 7, 2, global.TH.accent, global.TH.accent);
    }
    return _v;
}

/// Pill that opens a popup list. Returns selected index.
function ui_dropdown(_id, _x, _y, _w, _h, _options, _index, _help)
{
    var _i = _index;
    if (ui_popup_result_id == _id)
    {
        _i = ui_popup_result;
        ui_popup_result_id = "";
    }
    var _hot = ui_register(_id, _x, _y, _x + _w, _y + _h, _help);
    var _tgt = 0;
    if (_hot) { _tgt = 1; }
    if (ui_popup_open && ui_popup_id == _id) { _tgt = 1; }
    var _a = ui_anim_to(_id, _tgt);
    ui_rrect(_x, _y + 2, _x + _w, _y + _h + 2, 9, c_black, c_black, 0.2);
    ui_rrect(_x, _y, _x + _w, _y + _h, 9, merge_colour(global.TH.btn_top, global.TH.btn_hot_top, _a), merge_colour(global.TH.btn_bot, global.TH.btn_hot_bot, _a), 1);
    ui_rrect_line(_x, _y, _x + _w, _y + _h, 9, merge_colour(global.TH.panel_edge, global.TH.accent, _a), 0.7, 1);
    var _lab = "";
    if (_i >= 0 && _i < array_length(_options)) { _lab = _options[_i]; }
    _lab = ui_text_fit(_lab, global.f_body, _w - 34);
    ui_text(_x + 10, _y + _h * 0.5, _lab, global.TH.text, fa_left, fa_middle, global.f_body, 1);
    ui_chevron(_x + _w - 14, _y + _h * 0.5, 4, global.TH.text_dim, true);
    if (_hot && ui_pressed)
    {
        ui_take_click();
        ui_popup_open = true;
        ui_popup_id = _id;
        ui_popup_kind = 0;
        ui_popup_x = _x;
        ui_popup_y = _y + _h + 4;
        ui_popup_w = max(_w, 160);
        ui_popup_opts = _options;
        ui_popup_index = _i;
        ui_popup_anchor_y = _y;
        ui_popup_scroll = 0;
    }
    if (_hot && ui_wheel != 0 && !ui_popup_open)
    {
        _i = clamp(_i - ui_wheel, 0, array_length(_options) - 1);
        ui_wheel = 0;
    }
    return _i;
}

/// Colour swatch pill that opens the backdrop palette popup. Returns a palette index.
function ui_colour_drop(_id, _x, _y, _w, _h, _value, _help)
{
    var _v = _value;
    if (ui_popup_result_id == _id)
    {
        _v = ui_popup_result;
        ui_popup_result_id = "";
    }
    var _n = pal_count();
    _v = clamp(_v, 0, _n - 1);
    var _hot = ui_register(_id, _x, _y, _x + _w, _y + _h, _help);
    var _tgt = 0;
    if (_hot) { _tgt = 1; }
    var _a = ui_anim_to(_id, _tgt);
    ui_rrect(_x, _y, _x + _w, _y + _h, 9, global.TH.btn_top, global.TH.btn_bot, 1);
    ui_rrect(_x + 5, _y + 5, _x + 5 + (_h - 10), _y + _h - 5, 6, pal_col(_v), pal_col(_v), 1);
    ui_rrect_line(_x + 5, _y + 5, _x + 5 + (_h - 10), _y + _h - 5, 6, c_white, 0.35, 1);
    var _name = ui_text_fit("Colour " + string(_v) + "  " + rgb_hex(proj.pal[_v]), global.f_body, _w - _h - 26);
    ui_text(_x + _h + 2, _y + _h * 0.5, _name, global.TH.text, fa_left, fa_middle, global.f_body, 1);
    ui_rrect_line(_x, _y, _x + _w, _y + _h, 9, merge_colour(global.TH.panel_edge, global.TH.accent, _a), 0.7, 1);
    ui_chevron(_x + _w - 12, _y + _h * 0.5, 4, global.TH.text_dim, true);
    if (_hot && ui_pressed)
    {
        ui_take_click();
        ui_popup_open = true;
        ui_popup_id = _id;
        ui_popup_kind = 1;
        ui_popup_x = _x;
        ui_popup_y = _y + _h + 4;
        ui_popup_w = 8 * 28 + 16;
        ui_popup_index = _v;
        ui_popup_anchor_y = _y;
    }
    if (_hot && ui_wheel != 0 && !ui_popup_open)
    {
        _v = (_v - ui_wheel + _n) mod _n;
        ui_wheel = 0;
    }
    return _v;
}

/// Palette grid: _cols swatches per row, every colour of the backdrop. Returns the selected index.
function ui_palette_grid(_id, _x, _y, _cell, _cols, _value, _help)
{
    var _v = _value;
    var _n = pal_count();
    var _rows = ceil(_n / _cols);
    ds_map_replace(ui_rects, _id, [_x, _y, _x + _cols * (_cell + 4) - 4, _y + _rows * (_cell + 4) - 4]);
    for (var i = 0; i < _n; i++)
    {
        var _cx = _x + (i mod _cols) * (_cell + 4);
        var _cy = _y + (i div _cols) * (_cell + 4);
        var _cid = _id + "_" + string(i);
        var _hot = ui_register(_cid, _cx, _cy, _cx + _cell, _cy + _cell, _help + " (colour " + string(i) + "  " + rgb_hex(proj.pal[i]) + ")");
        ui_rrect(_cx, _cy, _cx + _cell, _cy + _cell, 5, pal_col(i), pal_col(i), 1);
        ui_rrect_line(_cx, _cy, _cx + _cell, _cy + _cell, 5, c_black, 0.5, 1);
        if (proj.solid[i] != 0)
        {
            draw_circle_colour(_cx + _cell - 5, _cy + _cell - 5, 3, c_white, c_white, false);
            draw_circle_colour(_cx + _cell - 5, _cy + _cell - 5, 2, global.TH.warn, global.TH.warn, false);
        }
        if (i == _v)
        {
            ui_rrect_line(_cx - 3, _cy - 3, _cx + _cell + 3, _cy + _cell + 3, 7, c_white, 1, 2);
        }
        else
        {
            if (_hot)
            {
                ui_rrect_line(_cx - 2, _cy - 2, _cx + _cell + 2, _cy + _cell + 2, 7, global.TH.accent, 0.8, 1);
            }
        }
        if (_hot && ui_pressed)
        {
            ui_take_click();
            _v = i;
        }
    }
    return _v;
}

/// Three sliders that edit an Amiga $RRGGBB colour. 4-bit steps on OCS, 8-bit on AGA.
function ui_rgb_sliders(_id, _x, _y, _w, _value, _help)
{
    var _aga = machine_cur().aga;
    var _c = rgb_machine(_value);
    var _gun = [rgb_r(_c), rgb_g(_c), rgb_b(_c)];
    var _lab = ["R", "G", "B"];
    var _tint = [make_colour_rgb(255, 90, 90), make_colour_rgb(90, 230, 120), make_colour_rgb(100, 150, 255)];
    var _max = 15;
    if (_aga) { _max = 255; }
    for (var k = 0; k < 3; k++)
    {
        var _sy = _y + k * 30;
        ui_text(_x, _sy + 13, _lab[k], _tint[k], fa_left, fa_middle, global.f_bold, 1);
        var _cur = _gun[k];
        if (!_aga) { _cur = _gun[k] div 17; }
        var _nv = ui_slider(_id + "_" + _lab[k], _x + 18, _sy, _w - 58, _cur, 0, _max, _help);
        ui_text(_x + _w, _sy + 13, string(_nv), global.TH.text, fa_right, fa_middle, global.f_bold, 1);
        if (_aga) { _gun[k] = _nv; }
        else { _gun[k] = _nv * 17; }
    }
    return rgb_make(_gun[0], _gun[1], _gun[2]);
}

function ui_popup_draw(_gw, _gh)
{
    if (!ui_popup_open) { return; }
    ui_force_input = true;
    var _x = ui_popup_x;
    var _y = ui_popup_y;
    var _w = ui_popup_w;
    var _h = 0;
    if (ui_popup_kind == 0)
    {
        _h = min(array_length(ui_popup_opts) * 28 + 8, _gh - 80);
    }
    else
    {
        _h = ceil(pal_count() / 8) * 28 + 16;
    }
    if (_y + _h > _gh - 10)
    {
        _y = max(10, ui_popup_anchor_y - _h - 4);
    }
    if (_x + _w > _gw - 10)
    {
        _x = _gw - 10 - _w;
    }
    ui_popup_rect = [_x, _y, _x + _w, _y + _h];
    ui_shadow(_x, _y, _x + _w, _y + _h, 10, 1.5);
    ui_rrect(_x, _y, _x + _w, _y + _h, 10, global.TH.btn_top, global.TH.panel_bot, 1);
    ui_rrect_line(_x, _y, _x + _w, _y + _h, 10, global.TH.accent, 0.6, 1);

    if (ui_popup_kind == 0)
    {
        var _n = array_length(ui_popup_opts);
        var _content = _n * 28 + 8;
        var _maxs = max(0, _content - _h);
        if (point_in_rectangle(ui_mx, ui_my, _x, _y, _x + _w, _y + _h) && ui_wheel != 0)
        {
            ui_popup_scroll = clamp(ui_popup_scroll - ui_wheel * 28, 0, _maxs);
            ui_wheel = 0;
        }
        ui_scissor(_x, _y + 2, _w, _h - 4);
        for (var i = 0; i < _n; i++)
        {
            var _iy = _y + 4 + i * 28 - ui_popup_scroll;
            var _hot = point_in_rectangle(ui_mx, ui_my, _x + 4, _iy, _x + _w - 4, _iy + 26) && point_in_rectangle(ui_mx, ui_my, _x, _y, _x + _w, _y + _h);
            if (i == ui_popup_index)
            {
                ui_rrect(_x + 4, _iy, _x + _w - 4, _iy + 26, 7, global.TH.accent, global.TH.accent_dark, 0.85);
            }
            else
            {
                if (_hot)
                {
                    ui_rrect(_x + 4, _iy, _x + _w - 4, _iy + 26, 7, global.TH.btn_hot_top, global.TH.btn_hot_bot, 1);
                }
            }
            ui_text(_x + 14, _iy + 13, ui_text_fit(ui_popup_opts[i], global.f_body, _w - 24), global.TH.text, fa_left, fa_middle, global.f_body, 1);
            if (_hot && ui_pressed)
            {
                ui_popup_result_id = ui_popup_id;
                ui_popup_result = i;
                ui_popup_open = false;
                ui_take_click();
            }
        }
        ui_scissor_reset();
    }
    else
    {
        var _pn = pal_count();
        for (var c = 0; c < _pn; c++)
        {
            var _cx = _x + 8 + (c mod 8) * 28;
            var _cy = _y + 8 + (c div 8) * 28;
            var _hot2 = point_in_rectangle(ui_mx, ui_my, _cx, _cy, _cx + 24, _cy + 24);
            ui_rrect(_cx, _cy, _cx + 24, _cy + 24, 5, pal_col(c), pal_col(c), 1);
            ui_rrect_line(_cx, _cy, _cx + 24, _cy + 24, 5, c_black, 0.5, 1);
            if (c == ui_popup_index)
            {
                ui_rrect_line(_cx - 2, _cy - 2, _cx + 26, _cy + 26, 7, c_white, 1, 2);
            }
            if (_hot2)
            {
                ui_rrect_line(_cx - 2, _cy - 2, _cx + 26, _cy + 26, 7, global.TH.accent, 1, 1);
                ui_help_title = "Colour " + string(c);
                ui_help_body = rgb_hex(proj.pal[c]) + ". Click to choose it.";
            }
            if (_hot2 && ui_pressed)
            {
                ui_popup_result_id = ui_popup_id;
                ui_popup_result = c;
                ui_popup_open = false;
                ui_take_click();
            }
        }
    }
    if (ui_popup_open && ui_pressed)
    {
        if (!point_in_rectangle(ui_mx, ui_my, _x, _y, _x + _w, _y + _h))
        {
            ui_popup_open = false;
            ui_take_click();
        }
    }
    if (keyboard_check_pressed(vk_escape))
    {
        ui_popup_open = false;
    }
    ui_force_input = false;
}

/// Scroll region. Returns the scroll offset to subtract from content y.
function ui_scroll_begin(_id, _x1, _y1, _x2, _y2, _content_h)
{
    var _off = ds_map_find_value(ui_scroll, _id);
    if (is_undefined(_off)) { _off = 0; }
    var _max = max(0, _content_h - (_y2 - _y1));
    _off = clamp(_off, 0, _max);
    ds_map_replace(ui_scroll, _id, _off);
    ui_scissor(_x1, _y1, _x2 - _x1, _y2 - _y1);
    ui_clip = [_x1, _y1, _x2, _y2];
    ui_clip_on = true;
    return _off;
}

function ui_scroll_end(_id, _x1, _y1, _x2, _y2, _content_h)
{
    ui_scissor_reset();
    ui_clip_on = false;
    var _off = ds_map_find_value(ui_scroll, _id);
    if (is_undefined(_off)) { _off = 0; }
    var _view = _y2 - _y1;
    var _max = max(0, _content_h - _view);
    if (ui_wheel != 0 && ui_can_input() && point_in_rectangle(ui_mx, ui_my, _x1, _y1, _x2, _y2))
    {
        _off = clamp(_off - ui_wheel * 48, 0, _max);
        ui_wheel = 0;
        ds_map_replace(ui_scroll, _id, _off);
    }
    if (_max > 0)
    {
        var _bh = max(30, _view * (_view / _content_h));
        var _by = _y1 + (_view - _bh) * (_off / _max);
        ui_rrect(_x2 - 7, _y1 + 2, _x2 - 3, _y2 - 2, 2, c_black, c_black, 0.25);
        ui_rrect(_x2 - 7, _by, _x2 - 3, _by + _bh, 2, global.TH.text_dim, global.TH.text_faint, 0.8);
    }
}
