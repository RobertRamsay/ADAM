/// ADAM - immediate-mode widgets (run in obj_app scope)
/// Help strings use "Title|Longer explanation" format.
///
/// How the immediate-mode UI works (read this before debugging a control):
/// - Nothing is kept between frames except a few obj_app variables. Every
///   frame Draw GUI (Draw_64) calls ui_frame_begin, then the page's ws_*_draw
///   draws every control afresh, then ui_frame_end. A widget such as
///   ui_button(id, ...) both draws itself and returns true on the frame it
///   is clicked, so the calling page acts on it straight away.
/// - Coordinates are UI pixels (GUI layer), not window pixels. Step_0 sets
///   global.ui_scale from the window size (ui_scale_for / ui_scale_fixed in
///   scr_ui_draw), sets the GUI size to window / scale, and keeps
///   global.ui_sx / ui_sy = window pixels per UI pixel. Mouse positions come
///   from device_mouse_x_to_gui, so they are already in UI pixels. Only the
///   scissor (ui_scissor) works in window pixels, so it multiplies by ui_sx / sy.
/// - ui_register(id, rect, help) is the heart of it: it stores the rect in
///   ui_rects[id] (cleared each frame), and if the mouse is over it (ui_hit)
///   makes it ui_hot and loads its help text. The status bar and hover help
///   card (scr_ui_help) show ui_help_title / ui_help_body; tutorials and
///   lessons (scr_tutorial, scr_lessons) find a control by looking its id
///   string up in ui_rects, so ids must be unique and stable from frame to frame.
///   The last control registered under the mouse wins ui_hot.
/// - ui_pressed is true on the frame the left button goes down. The first
///   widget that uses the click calls ui_take_click() (sets it false) so the
///   controls drawn after it - or underneath it - do not also react.
///   ui_pressed_raw keeps the untouched value for ui_frame_end.
/// - ui_input_ok is false while a modal is up (popup list, machine picker,
///   About, confirm box, What's new, Submit your game, the crash question,
///   a tutorial step); ui_hit then says no
///   to every control. A tutorial step lets clicks through its own target
///   rect only. ui_force_input lets the popup itself still take input.
/// - ui_focus = id of the text field being typed into ("" = none). A field
///   claims it on click (ui_focus_claimed); a click anywhere else clears it in
///   ui_frame_end. Keyboard shortcuts check ui_focus so typing does not trigger them.
/// - ui_drag_id = id of the slider / scroll bar / thing being dragged while
///   the button is held; cleared when the button is up.
/// - Scrolling panels: off = ui_scroll_begin(id, rect, content_h) clips the
///   drawing (scissor) and the mouse (ui_clip, checked by ui_hit) to the rect;
///   draw the content at y - off, then ui_scroll_end(id, same rect, content_h)
///   handles the wheel and draws / drags the scroll bar. Offsets live in the
///   ui_scroll map under the id. Panels do not nest.
/// - ui_anim map: per-id hover / select fade values (0..1), eased by ui_anim_to.

#macro BTN_NORMAL 0
#macro BTN_ACCENT 1
#macro BTN_DANGER 2
#macro BTN_GHOST  3
#macro BTN_ON     4

/// Starts a UI frame (Draw_64 calls it before the page is drawn). Reads the
/// mouse in UI pixels and its buttons / wheel, clears ui_hot, the help text,
/// the clip and ui_rects, and works out ui_input_ok: false while any modal
/// card is up, except over the current tutorial target rect, and false over
/// the tour offer, new version and lesson cards so clicks do not fall through.
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
    ui_repeat_seen = false;
    if (!ui_held || ui_pressed_raw) { ui_repeat_id = ""; }
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
    if (about_active)
    {
        ui_input_ok = false;
    }
    if (confirm_active)
    {
        ui_input_ok = false;
    }
    if (whatsnew_active)
    {
        ui_input_ok = false;
    }
    if (submit_active || crash_active)
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
    // the "Show me around?" card takes clicks over its own area only
    if (tut_offer_on && point_in_rectangle(ui_mx, ui_my, tut_offer_rect[0], tut_offer_rect[1], tut_offer_rect[2], tut_offer_rect[3]))
    {
        ui_input_ok = false;
    }
    // so does the "new version" card
    if (update_card_on && point_in_rectangle(ui_mx, ui_my, update_card_rect[0], update_card_rect[1], update_card_rect[2], update_card_rect[3]))
    {
        ui_input_ok = false;
    }
    // so does the lesson card
    if (les_active && point_in_rectangle(ui_mx, ui_my, les_card_rect[0], les_card_rect[1], les_card_rect[2], les_card_rect[3]))
    {
        ui_input_ok = false;
    }
    if (!ui_held)
    {
        ui_drag_id = "";
    }
}

/// Ends a UI frame (after everything is drawn). Stops a held "+" / "-"
/// repeat whose button was not drawn this frame, drops text focus after a
/// click that no text field claimed, and times how long the mouse has rested
/// on the same control (ui_hot_time, seconds; the hover help card waits for 0.35).
function ui_frame_end()
{
    if (!ui_repeat_seen) { ui_repeat_id = ""; }
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

/// True if controls may react to the mouse this frame: ui_input_ok (no modal
/// in the way) or ui_force_input (set while the popup list draws itself).
function ui_can_input()
{
    if (ui_force_input) { return true; }
    return ui_input_ok;
}

/// True if the mouse is inside the rect (UI pixels, edges included), input
/// is allowed, and - inside a scrolling panel - the mouse is also inside the
/// panel's clip (ui_clip), so rows scrolled out of view cannot be clicked.
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
/// _id: unique, stable string (tutorial / lesson steps name it); _help:
/// "Title|Body" or just "Title". A hovered control becomes ui_hot, sets
/// ui_hot_rect and the help text; a later hovered control overrides it.
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

/// Eases the fade value stored under _id in ui_anim 22% of the way to
/// _target each call (snaps when within 0.01) and returns it. Used for hover
/// and selection highlights (0 = off, 1 = full). Ids are often the control id
/// plus a suffix ("_sel", "_h", "_f") so one control can fade several things.
function ui_anim_to(_id, _target)
{
    var _v = ds_map_find_value(ui_anim, _id);
    if (is_undefined(_v)) { _v = 0; }
    _v = lerp(_v, _target, 0.22);
    if (abs(_v - _target) < 0.01) { _v = _target; }
    ds_map_replace(ui_anim, _id, _v);
    return _v;
}

/// Uses up this frame's click (ui_pressed = false) so no control drawn after
/// this one reacts to it. Call it whenever a control acts on ui_pressed.
function ui_take_click()
{
    ui_pressed = false;
}

/// Push button at (_x, _y), _w x _h UI pixels; _style is a BTN_* macro
/// (normal, accent, danger, ghost = only shows on hover, on = lit toggle).
/// The label is cut with "..." to fit. Returns true on the frame it is
/// clicked (and takes the click). A button labelled "+", "-" or "−" repeats
/// while held: first after 600 ms, then every 40 ms (ui_repeat_id).
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
            _ct = merge_colour(make_colour_rgb(255, 196, 110), c_white, _a * 0.12);
            _cb = merge_colour(make_colour_rgb(200, 96, 14), global.TH.accent2, _a * 0.2);
            _tc = make_colour_rgb(34, 18, 4);
            _edge = global.TH.accent2;
            break;
    }
    // metal: a dark outline and drop shadow, the face (darker while held down), a
    // gloss over its top half, then a rim lit along the top edge (ui_rrect_rim)
    var _oy = 0;
    if (_down)
    {
        _oy = 1;
        _ct = merge_colour(_ct, c_black, 0.18);
        _cb = merge_colour(_cb, c_black, 0.1);
    }
    var _alpha = 1;
    if (_style == BTN_GHOST) { _alpha = 0.35 + 0.65 * _a; }
    if (_style != BTN_GHOST || _a > 0.05)
    {
        ui_rrect(_x, _y + 2, _x + _w, _y + _h + 2, _r, c_black, c_black, 0.35 * _alpha);
        ui_rrect_line(_x - 1, _y - 1 + _oy, _x + _w + 1, _y + _h + 1 + _oy, _r + 1, c_black, 0.6 * _alpha, 1);
    }
    ui_rrect(_x, _y + _oy, _x + _w, _y + _h + _oy, _r, _ct, _cb, _alpha);
    if (!_down)
    {
        ui_rrect(_x + 1, _y + 1 + _oy, _x + _w - 1, _y + _h * 0.5 + _oy, _r - 1, c_white, _ct, 0.13 * _alpha);
    }
    ui_rrect_rim(_x, _y + _oy, _x + _w, _y + _h + _oy, _r, merge_colour(_edge, c_white, 0.65), merge_colour(_cb, c_black, 0.35), (0.55 + 0.35 * _a) * _alpha);
    ui_glow(_x, _y + _oy, _x + _w, _y + _h + _oy, _r, global.TH.accent, _a * 0.6);
    var _lab = ui_text_fit(_label, global.f_bold, _w - 12);
    // a dark line under light lettering, a light one under dark lettering: engraved
    if (colour_get_value(_tc) > 128)
    {
        ui_text(_x + _w * 0.5, _y + _h * 0.5 + _oy + 1, _lab, c_black, fa_center, fa_middle, global.f_bold, 0.35 * _alpha);
    }
    ui_text(_x + _w * 0.5, _y + _h * 0.5 + _oy, _lab, _tc, fa_center, fa_middle, global.f_bold, 1);

    if (_hot && ui_pressed)
    {
        if (_label == "+" || _label == "-" || _label == "−")
        {
            ui_repeat_id = _id;
            ui_repeat_next = current_time + 600;
            ui_repeat_seen = true;
        }
        ui_take_click();
        return true;
    }
    if (ui_repeat_id == _id)
    {
        ui_repeat_seen = true;
        if (!_hot || !ui_held)
        {
            ui_repeat_id = "";
        }
        else if (current_time >= ui_repeat_next)
        {
            ui_repeat_next = current_time + 40;
            return true;
        }
    }
    return false;
}

/// Pill-shaped tab; _selected draws it lit (the caller keeps which tab is
/// chosen). Returns true on the frame it is clicked (and takes the click).
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
        // the chosen tab: a lit cobalt pill with a gloss and a light rim
        ui_rrect(_x, _y + 1, _x + _w, _y + _h + 1, _r, c_black, c_black, 0.4 * _sa);
        ui_rrect(_x, _y, _x + _w, _y + _h, _r, merge_colour(global.TH.accent, c_white, 0.12), global.TH.accent_dark, _sa);
        ui_rrect(_x + 1, _y + 1, _x + _w - 1, _y + _h * 0.5, _r - 1, c_white, global.TH.accent, 0.18 * _sa);
        ui_rrect_rim(_x, _y, _x + _w, _y + _h, _r, merge_colour(global.TH.accent, c_white, 0.7), global.TH.accent_dark, 0.8 * _sa);
        ui_glow(_x, _y, _x + _w, _y + _h, _r, global.TH.accent, _sa * 0.5);
    }
    if (_a > 0.02 && !_selected)
    {
        ui_rrect(_x, _y, _x + _w, _y + _h, _r, global.TH.btn_hot_top, global.TH.btn_hot_bot, _a * 0.8);
    }
    var _tc = merge_colour(global.TH.text_dim, global.TH.text, max(_a, _sa));
    if (_selected) { _tc = c_white; }
    var _lab = ui_text_fit(_label, global.f_bold, _w - 10);
    ui_text(_x + _w * 0.5, _y + _h * 0.5, _lab, _tc, fa_center, fa_middle, global.f_bold, 1);
    if (_hot && ui_pressed)
    {
        ui_take_click();
        return true;
    }
    return false;
}

/// Small dim caption text, top-left at (_x, _y). Not registered: no hover help.
function ui_label(_x, _y, _str)
{
    ui_text(_x, _y, _str, global.TH.text_dim, fa_left, fa_top, global.f_small, 1);
}

/// On / off switch with its label to the right; 24 high, width = 54 + label.
/// The whole switch and label are clickable. Returns the new value
/// (_value flipped on the frame it is clicked, else _value).
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

/// Number box with "-" / "+" buttons (ids _id + "_m" / "_p", which repeat
/// while held); 30 high. Wheel over it also steps. Shift steps by 10.
/// Returns the new value, kept within _min.._max.
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

/// Horizontal slider, 26 high. Click sets ui_drag_id and the knob follows the
/// mouse while held (8 px margin each end); the wheel steps by 1. Returns the
/// new whole-number value within _min.._max.
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

/// One-line text box. Click gives it ui_focus and copies _value into
/// keyboard_string; while focused, typing edits keyboard_string (cut to
/// _maxlen characters), Ctrl+V pastes, Enter / Esc end editing. Returns the
/// current text, so the caller stores it back every frame.
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
        // Ctrl+V pastes (one line - a licence key copied from a web page, say)
        if (keyboard_check(vk_control) && keyboard_check_pressed(ord("V")) && clipboard_has_text())
        {
            var _clip = string_replace_all(string_replace_all(clipboard_get_text(), "\r", ""), "\n", " ");
            keyboard_string = string_replace_all(keyboard_string, chr(22), "") + string_trim(_clip);
        }
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
    // while typing, show the end of the text (where the caret is) rather than cutting it off
    var _shown = "";
    if (ui_focus == _id)
    {
        draw_set_font(global.f_body);
        _shown = _v;
        while (string_length(_shown) > 1 && ui_sw(_shown) > _w - 20)
        {
            _shown = string_delete(_shown, 1, 1);
        }
    }
    else
    {
        _shown = ui_text_fit(_v, global.f_body, _w - 20);
    }
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
/// A click only opens the popup (ui_popup_*); ui_popup_draw, drawn last,
/// puts the choice in ui_popup_result / ui_popup_result_id, and this
/// dropdown picks it up the next frame it is drawn. Wheel steps the choice.
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
        // wide enough for the longest option (text inset + scrollbar gutter)
        draw_set_font(global.f_body);
        var _ow = 0;
        for (var o = 0; o < array_length(_options); o++) { _ow = max(_ow, ui_sw(_options[o])); }
        ui_popup_w = max(_w, 160, ceil(_ow) + 40);
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

/// Draws the open popup (if any) on top of the page; Draw_64 calls it after
/// the page so it sits over everything. _gw / _gh = GUI size in UI pixels.
/// ui_popup_kind 0 = option list from ui_dropdown (28 px rows, scrolls when
/// longer than the room), 1 = palette grid from ui_colour_drop (8 swatches a
/// row). Opens below the control, else above, else on the roomier side.
/// A choice sets ui_popup_result_id / ui_popup_result and closes it; a click
/// outside or Esc closes it with no choice.
function ui_popup_draw(_gw, _gh)
{
    if (!ui_popup_open) { return; }
    ui_force_input = true;
    var _x = ui_popup_x;
    var _y = ui_popup_y;
    var _w = min(ui_popup_w, _gw - 20);
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
        // no room below: open above, or (a long list) on the roomier side, shortened to fit - it scrolls
        var _below = _gh - 10 - _y;
        var _above = ui_popup_anchor_y - 4 - 10;
        if (_h <= _above)
        {
            _y = ui_popup_anchor_y - 4 - _h;
        }
        else
        {
            if (ui_popup_kind == 0)
            {
                if (_above > _below)
                {
                    _h = max(64, _above);
                    _y = ui_popup_anchor_y - 4 - _h;
                }
                else
                {
                    _h = max(64, _below);
                }
            }
            else
            {
                _y = max(10, ui_popup_anchor_y - _h - 4);
            }
        }
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
        if (_maxs > 0)
        {
            var _pbh = max(24, _h * (_h / _content));
            var _pby = _y + (_h - _pbh) * (ui_popup_scroll / _maxs);
            if (point_in_rectangle(ui_mx, ui_my, _x + _w - 14, _y, _x + _w, _y + _h) && ui_pressed)
            {
                ui_drag_id = "popup_sb";
                ui_take_click();
            }
            if (ui_drag_id == "popup_sb" && ui_held)
            {
                ui_popup_scroll = round(clamp((ui_my - _y - _pbh * 0.5) / max(1, _h - _pbh), 0, 1) * _maxs);
                _pby = _y + (_h - _pbh) * (ui_popup_scroll / _maxs);
            }
            ui_rrect(_x + _w - 9, _pby + 2, _x + _w - 3, _pby + _pbh - 2, 3, global.TH.text_dim, global.TH.text_faint, 0.9);
        }
        ui_scissor(_x, _y + 2, _w - 12, _h - 4);
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
            ui_text(_x + 14, _iy + 13, ui_text_fit(ui_popup_opts[i], global.f_body, _w - 28), global.TH.text, fa_left, fa_middle, global.f_body, 1);
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
/// _content_h = full height of what is drawn inside (usually last frame's
/// measured height). Sets the scissor and ui_clip to the rect (less the 14 px
/// scroll bar strip when it scrolls). Must be paired with ui_scroll_end.
function ui_scroll_begin(_id, _x1, _y1, _x2, _y2, _content_h)
{
    var _off = ds_map_find_value(ui_scroll, _id);
    if (is_undefined(_off)) { _off = 0; }
    var _max = max(0, _content_h - (_y2 - _y1));
    _off = clamp(_off, 0, _max);
    ds_map_replace(ui_scroll, _id, _off);
    ui_scissor(_x1, _y1, _x2 - _x1, _y2 - _y1);
    ui_clip = [_x1, _y1, _x2, _y2];
    if (_max > 0) { ui_clip = [_x1, _y1, _x2 - 14, _y2]; }   // keep the scroll bar free to drag
    ui_clip_on = true;
    return _off;
}

/// Closes a ui_scroll_begin region (same id, rect and content height):
/// resets the scissor and clip, scrolls 48 px per wheel notch over the rect,
/// and draws the scroll bar at the right edge (click or drag it; the grab
/// point is kept in ui_scroll[_id + "_grab"]). The new offset is used from
/// the next frame.
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
        var _sid = _id + "_sb";
        var _bar_hot = false;
        if (ui_can_input() && point_in_rectangle(ui_mx, ui_my, _x2 - 14, _y1, _x2, _y2)) { _bar_hot = true; }
        if (_bar_hot && ui_pressed)
        {
            // grab the thumb where it was clicked, or jump the thumb to the click
            var _grab = ui_my - _by;
            if (_grab < 0 || _grab > _bh) { _grab = _bh * 0.5; }
            ds_map_replace(ui_scroll, _id + "_grab", _grab);
            ui_drag_id = _sid;
            ui_take_click();
        }
        if (ui_drag_id == _sid && ui_held)
        {
            var _g = ds_map_find_value(ui_scroll, _id + "_grab");
            if (is_undefined(_g)) { _g = _bh * 0.5; }
            var _tt = clamp((ui_my - _g - _y1) / max(1, _view - _bh), 0, 1);
            _off = round(_tt * _max);
            ds_map_replace(ui_scroll, _id, _off);
            _by = _y1 + (_view - _bh) * (_off / _max);
        }
        var _hl = 0;
        if (_bar_hot || ui_drag_id == _sid) { _hl = 1; }
        var _ha = ui_anim_to(_sid, _hl);
        var _bw = 4 + _ha * 4;
        ui_rrect(_x2 - 3 - _bw, _y1 + 2, _x2 - 3, _y2 - 2, 3, c_black, c_black, 0.25 + 0.1 * _ha);
        ui_rrect(_x2 - 3 - _bw, _by, _x2 - 3, _by + _bh, 3, merge_colour(global.TH.text_dim, global.TH.accent, _ha), global.TH.text_faint, 0.8 + 0.2 * _ha);
    }
}
