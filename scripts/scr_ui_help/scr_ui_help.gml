/// ADAM - hover helper lines, help bubbles, status bar, toasts

function ui_help_draw(_gw, _gh)
{
    var _show = false;
    if (helpers_on && !tut_active && !ui_popup_open && ui_hot != "" && ui_drag_id == "" && ui_hot_time > 0.35 && ui_help_body != "")
    {
        _show = true;
    }
    var _tgt = 0;
    if (_show) { _tgt = 1; }
    help_alpha = lerp(help_alpha, _tgt, 0.2);
    if (_show)
    {
        help_last_rect = ui_hot_rect;
        help_last_title = ui_help_title;
        help_last_body = ui_help_body;
    }
    if (help_alpha < 0.02 || array_length(help_last_rect) != 4) { return; }

    var _r = help_last_rect;
    var _a = help_alpha;
    var _col = global.TH.accent;

    // alignment guide lines through the hovered control
    var _top = 64;
    var _bot = _gh - 40;
    ui_dotted_line(0, _r[1] - 3, _gw, _r[1] - 3, _col, 0.22 * _a, 4);
    ui_dotted_line(0, _r[3] + 3, _gw, _r[3] + 3, _col, 0.22 * _a, 4);
    ui_dotted_line(_r[0] - 3, _top, _r[0] - 3, _bot, _col, 0.22 * _a, 4);
    ui_dotted_line(_r[2] + 3, _top, _r[2] + 3, _bot, _col, 0.22 * _a, 4);
    ui_rrect_line(_r[0] - 3, _r[1] - 3, _r[2] + 3, _r[3] + 3, 10, _col, 0.9 * _a, 2);

    // bubble
    var _bw = 300;
    draw_set_font(global.f_body);
    var _th = ui_sh_ext(help_last_body, _bw - 28);
    var _bh = _th + 52;
    var _cy = (_r[1] + _r[3]) * 0.5;
    var _bx = _r[2] + 60;
    var _side = 1;
    if (_bx + _bw > _gw - 12)
    {
        _bx = _r[0] - 60 - _bw;
        _side = -1;
    }
    if (_bx < 12)
    {
        _bx = clamp((_r[0] + _r[2]) * 0.5 - _bw * 0.5, 12, _gw - _bw - 12);
        _side = 0;
    }
    var _by = clamp(_cy - _bh * 0.5, 70, _gh - 50 - _bh);
    if (_side == 0)
    {
        _by = _r[3] + 40;
        if (_by + _bh > _gh - 50) { _by = _r[1] - 40 - _bh; }
        // a tall, wide control (a whole panel) has room neither below nor above: keep it on screen
        _by = clamp(_by, 8, _gh - 8 - _bh);
    }

    var _sx = _r[2] + 3;
    var _sy = _cy;
    var _ex = _bx;
    var _ey = _by + _bh * 0.5;
    if (_side == -1)
    {
        _sx = _r[0] - 3;
        _ex = _bx + _bw;
    }
    if (_side == 0)
    {
        _sx = (_r[0] + _r[2]) * 0.5;
        _sy = _r[3] + 3;
        _ex = _bx + _bw * 0.5;
        _ey = _by;
        if (_by < _r[1])
        {
            _sy = _r[1] - 3;
            _ey = _by + _bh;
        }
    }
    ui_leader(_sx, _sy, _ex, _ey, _col, _a);

    ui_shadow(_bx, _by, _bx + _bw, _by + _bh, 12, _a * 1.4);
    ui_rrect(_bx, _by, _bx + _bw, _by + _bh, 12, global.TH.btn_top, global.TH.panel_bot, 0.97 * _a);
    ui_rrect_line(_bx, _by, _bx + _bw, _by + _bh, 12, _col, 0.8 * _a, 1);
    ui_rrect(_bx, _by, _bx + 5, _by + _bh, 3, global.TH.accent, global.TH.accent_dark, _a);
    ui_text(_bx + 16, _by + 12, ui_text_fit(help_last_title, global.f_bold, _bw - 28), c_white, fa_left, fa_top, global.f_bold, _a);
    ui_text_wrap(_bx + 16, _by + 36, help_last_body, global.TH.text_dim, _bw - 28, global.f_body, _a);
}

function ui_status_bar(_gw, _gh)
{
    var _y = _gh - 34;
    ui_rrect(0, _y, _gw, _gh + 20, 0, global.TH.bar_bot, global.TH.bg_bot, 1);
    draw_line_colour(0, _y, _gw, _y, global.TH.panel_edge, global.TH.panel_edge);
    var _msg = "Hover over anything to see what it does. Press F1 for a tutorial on this page.";
    if (ui_help_title != "")
    {
        _msg = ui_help_title;
        if (ui_help_body != "") { _msg += "  -  " + ui_help_body; }
    }
    var _dirty = "Saved";
    if (proj_dirty) { _dirty = "Unsaved changes"; }
    var _right = proj.name + "   |   " + machine_cur().name + "   |   " + _dirty;
    draw_set_font(global.f_small);
    var _rw = ui_sw(_right);
    // memory bar, just left of the project name
    var _mw = 200;
    var _mx = _gw - 16 - _rw - 28 - _mw;
    mem_bar_draw(_mx, _y + 11, _mw, 12);
    var _help_w = max(120, _mx - 210 - 32);
    ui_text(16, _y + 17, ui_text_fit(_msg, global.f_small, _help_w), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    ui_text(_gw - 16, _y + 17, _right, global.TH.text_faint, fa_right, fa_middle, global.f_small, 1);
}

function toast(_text, _kind)
{
    array_push(toasts, { text : _text, life : 3.5, kind : _kind, a : 0 });
}

function toasts_draw(_gw, _gh)
{
    var _y = _gh - 50;
    // stack above a card in the bottom-right corner (tour offer, new version, lesson),
    // which is drawn later and would hide the toast
    var _cards = [tut_offer_rect, update_card_rect, les_card_rect];
    for (var c = 0; c < array_length(_cards); c++)
    {
        var _rc = _cards[c];
        if (_rc[2] > _gw * 0.5 && _rc[1] - 4 < _y)
        {
            _y = _rc[1] - 4;
        }
    }
    var _dt = delta_time / 1000000;
    for (var i = array_length(toasts) - 1; i >= 0; i--)
    {
        var _t = toasts[i];
        _t.life -= _dt;
        if (_t.life <= 0)
        {
            array_delete(toasts, i, 1);
            continue;
        }
        _t.a = lerp(_t.a, min(1, _t.life * 2), 0.25);
        var _txt = ui_text_fit(_t.text, global.f_bold, _gw - 40 - 48);
        draw_set_font(global.f_bold);
        var _w = ui_sw(_txt) + 48;
        var _h = 40;
        var _x = _gw - 20 - _w;
        _y -= _h + 8;
        var _c = global.TH.accent2;
        if (_t.kind == 1) { _c = global.TH.warn; }
        if (_t.kind == 2) { _c = global.TH.danger; }
        ui_shadow(_x, _y, _x + _w, _y + _h, 12, _t.a);
        ui_rrect(_x, _y, _x + _w, _y + _h, 12, global.TH.btn_top, global.TH.panel_bot, _t.a);
        ui_rrect_line(_x, _y, _x + _w, _y + _h, 12, _c, 0.8 * _t.a, 1);
        draw_set_alpha(_t.a);
        draw_circle_colour(_x + 18, _y + _h * 0.5, 5, _c, _c, false);
        draw_set_alpha(1);
        ui_text(_x + 32, _y + _h * 0.5, _txt, global.TH.text, fa_left, fa_middle, global.f_bold, _t.a);
    }
}

/// Section heading inside panels
function ui_heading(_x, _y, _str)
{
    ui_text(_x, _y, string_upper(_str), global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
}
