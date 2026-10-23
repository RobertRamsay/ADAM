/// ADAM - rounded, gradient drawing primitives

#macro UI_MIN_W 1280        // every page is laid out for at least this much room (interface pixels)
#macro UI_MIN_H 720
#macro UI_SCALE_MIN 0.6     // smallest interface scale, for a window far below 1280 x 720
#macro WIN_MIN_W 960        // smallest window (fits a 1366 x 768 laptop, or 1080p at 150% scaling)
#macro WIN_MIN_H 540

function ui_rr_points(_x1, _y1, _x2, _y2, _r)
{
    var _pts = [];
    var _cx = [_x1 + _r, _x2 - _r, _x2 - _r, _x1 + _r];
    var _cy = [_y1 + _r, _y1 + _r, _y2 - _r, _y2 - _r];
    var _start = [180, 270, 0, 90];
    var _segs = 7;
    for (var c = 0; c < 4; c++)
    {
        for (var s = 0; s <= _segs; s++)
        {
            var _a = degtorad(_start[c] + (90 * s / _segs));
            array_push(_pts, _cx[c] + cos(_a) * _r);
            array_push(_pts, _cy[c] + sin(_a) * _r);
        }
    }
    return _pts;
}

/// Filled rounded rectangle with a vertical gradient
function ui_rrect(_x1, _y1, _x2, _y2, _r, _ctop, _cbot, _alpha)
{
    if (_x2 <= _x1 || _y2 <= _y1) { return; }
    var _rr = min(_r, (_x2 - _x1) * 0.5, (_y2 - _y1) * 0.5);
    var _h = _y2 - _y1;
    var _pts = ui_rr_points(_x1, _y1, _x2, _y2, _rr);
    var _n = array_length(_pts);
    draw_primitive_begin(pr_trianglefan);
    var _cy = (_y1 + _y2) * 0.5;
    draw_vertex_colour((_x1 + _x2) * 0.5, _cy, merge_colour(_ctop, _cbot, 0.5), _alpha);
    for (var i = 0; i < _n; i += 2)
    {
        var _t = clamp((_pts[i + 1] - _y1) / _h, 0, 1);
        draw_vertex_colour(_pts[i], _pts[i + 1], merge_colour(_ctop, _cbot, _t), _alpha);
    }
    var _t0 = clamp((_pts[1] - _y1) / _h, 0, 1);
    draw_vertex_colour(_pts[0], _pts[1], merge_colour(_ctop, _cbot, _t0), _alpha);
    draw_primitive_end();
}

/// Rounded outline, optional thickness (drawn as inset rings)
function ui_rrect_line(_x1, _y1, _x2, _y2, _r, _col, _alpha, _thick)
{
    if (_x2 <= _x1 || _y2 <= _y1) { return; }
    var _rings = max(1, round(_thick));
    for (var k = 0; k < _rings; k++)
    {
        var _o = k;
        var _rr = max(0, min(_r - _o, (_x2 - _x1 - _o * 2) * 0.5, (_y2 - _y1 - _o * 2) * 0.5));
        var _pts = ui_rr_points(_x1 + _o, _y1 + _o, _x2 - _o, _y2 - _o, _rr);
        var _n = array_length(_pts);
        draw_primitive_begin(pr_linestrip);
        for (var i = 0; i < _n; i += 2)
        {
            draw_vertex_colour(_pts[i], _pts[i + 1], _col, _alpha);
        }
        draw_vertex_colour(_pts[0], _pts[1], _col, _alpha);
        draw_primitive_end();
    }
}

function ui_shadow(_x1, _y1, _x2, _y2, _r, _strength)
{
    for (var i = 4; i >= 1; i--)
    {
        var _g = i * 2;
        ui_rrect(_x1 - _g + 1, _y1 - _g + 4, _x2 + _g - 1, _y2 + _g + 4, _r + _g, c_black, c_black, 0.045 * _strength);
    }
}

function ui_glow(_x1, _y1, _x2, _y2, _r, _col, _strength)
{
    if (_strength <= 0.01) { return; }
    for (var i = 1; i <= 4; i++)
    {
        var _g = i * 2;
        ui_rrect_line(_x1 - _g, _y1 - _g, _x2 + _g, _y2 + _g, _r + _g, _col, (0.32 - i * 0.07) * _strength, 1);
    }
}

/// Raised panel with title
function ui_panel(_x1, _y1, _x2, _y2, _title)
{
    var _r = global.TH.radius + 2;
    ui_shadow(_x1, _y1, _x2, _y2, _r, 1);
    ui_rrect(_x1, _y1, _x2, _y2, _r, global.TH.panel_top, global.TH.panel_bot, 0.96);
    ui_rrect_line(_x1, _y1, _x2, _y2, _r, global.TH.panel_edge, 0.55, 1);
    // top sheen
    ui_rrect(_x1 + 2, _y1 + 1, _x2 - 2, _y1 + 18, _r - 1, c_white, global.TH.panel_top, 0.05);
    if (_title != "")
    {
        ui_text(_x1 + 16, _y1 + 13, _title, global.TH.text, fa_left, fa_top, global.f_title, 1);
        draw_line_colour(_x1 + 14, _y1 + 42, _x2 - 14, _y1 + 42, global.TH.panel_edge, global.TH.panel_edge);
    }
}

/// Sunken area (canvas wells, lists)
function ui_inset(_x1, _y1, _x2, _y2, _r)
{
    ui_rrect(_x1, _y1, _x2, _y2, _r, global.TH.inset_top, global.TH.inset_bot, 1);
    ui_rrect_line(_x1, _y1, _x2, _y2, _r, c_black, 0.35, 1);
    draw_line_colour(_x1 + _r, _y2, _x2 - _r, _y2, global.TH.panel_edge, global.TH.panel_edge);
}

function ui_text(_x, _y, _str, _col, _ha, _va, _font, _alpha)
{
    draw_set_font(_font);
    draw_set_halign(_ha);
    draw_set_valign(_va);
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
    var _k = 1 / global.ui_scale;
    draw_text_transformed(_x, _y, _str, _k, _k, 0);
    draw_set_alpha(1);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

function ui_text_wrap(_x, _y, _str, _col, _w, _font, _alpha)
{
    draw_set_font(_font);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_colour(_col);
    draw_set_alpha(_alpha);
    var _k = 1 / global.ui_scale;
    draw_text_ext_transformed(_x, _y, _str, -1, _w * global.ui_scale, _k, _k, 0);
    draw_set_alpha(1);
}

// ---- resolution independence: fonts are rasterised at ui_scale and drawn at 1/ui_scale,
// ---- so text stays sharp while the GUI layer is scaled up for 4K screens.
function ui_sw(_str)
{
    return string_width(_str) / global.ui_scale;
}

function ui_sh_ext(_str, _w)
{
    return string_height_ext(_str, -1, _w * global.ui_scale) / global.ui_scale;
}

function ui_scissor(_x, _y, _w, _h)
{
    gpu_set_scissor(floor(_x * global.ui_sx), floor(_y * global.ui_sy), ceil(_w * global.ui_sx), ceil(_h * global.ui_sy));
}

function ui_scissor_reset()
{
    // = the window; in interface pixels while a dev shot draws into its surface
    gpu_set_scissor(0, 0, ceil(display_get_gui_width() * global.ui_sx), ceil(display_get_gui_height() * global.ui_sy));
}

/// Automatic interface scale: 1080p = 100%, 1440p = 125%, 4K = 200%. A window
/// smaller than 1280 x 720 (a small laptop, or a 1080p one at 150% Windows
/// scaling) shrinks the interface instead, so every page keeps the layout it
/// has at 1280 x 720 - just smaller - rather than running off the bottom.
function ui_scale_for(_ww, _wh)
{
    var _s = floor((_wh / 1080) * 4) / 4;
    _s = min(_s, floor((_wh / 720) * 4) / 4, floor((_ww / 1280) * 4) / 4);
    _s = max(1, _s);
    var _fit = min(_ww / UI_MIN_W, _wh / UI_MIN_H);
    if (_fit < 1) { _s = max(UI_SCALE_MIN, _fit); }
    return _s;
}

/// The scale picked on Home (Interface size), held down so the page is never
/// smaller than 1280 x 720 (shrinking below 100% in a small window, as Auto does)
function ui_scale_fixed(_pref, _ww, _wh)
{
    return max(UI_SCALE_MIN, min(_pref, _ww / UI_MIN_W, _wh / UI_MIN_H));
}

function ui_text_fit(_str, _font, _w)
{
    draw_set_font(_font);
    if (ui_sw(_str) <= _w) { return _str; }
    var _s = _str;
    while (string_length(_s) > 1 && ui_sw(_s + "...") > _w)
    {
        _s = string_copy(_s, 1, string_length(_s) - 1);
    }
    return _s + "...";
}

function ui_dotted_line(_x1, _y1, _x2, _y2, _col, _alpha, _dash)
{
    var _len = point_distance(_x1, _y1, _x2, _y2);
    if (_len < 1) { return; }
    var _dx = (_x2 - _x1) / _len;
    var _dy = (_y2 - _y1) / _len;
    var _p = 0;
    draw_set_alpha(_alpha);
    while (_p < _len)
    {
        var _e = min(_p + _dash, _len);
        draw_line_colour(_x1 + _dx * _p, _y1 + _dy * _p, _x1 + _dx * _e, _y1 + _dy * _e, _col, _col);
        _p += _dash * 2;
    }
    draw_set_alpha(1);
}

/// Smooth curved leader line with end dots
function ui_leader(_x1, _y1, _x2, _y2, _col, _alpha)
{
    var _mx = (_x1 + _x2) * 0.5;
    var _px = _x1;
    var _py = _y1;
    draw_set_alpha(_alpha);
    for (var i = 1; i <= 20; i++)
    {
        var _t = i / 20;
        var _u = 1 - _t;
        var _bx = _u * _u * _u * _x1 + 3 * _u * _u * _t * _mx + 3 * _u * _t * _t * _mx + _t * _t * _t * _x2;
        var _by = _u * _u * _u * _y1 + 3 * _u * _u * _t * _y1 + 3 * _u * _t * _t * _y2 + _t * _t * _t * _y2;
        draw_line_width_colour(_px, _py, _bx, _by, 2, _col, _col);
        _px = _bx;
        _py = _by;
    }
    draw_circle_colour(_x1, _y1, 4, _col, _col, false);
    draw_circle_colour(_x2, _y2, 3, _col, _col, false);
    draw_set_alpha(_alpha * 0.35);
    draw_circle_colour(_x1, _y1, 8, _col, _col, false);
    draw_set_alpha(1);
}

function ui_chevron(_x, _y, _size, _col, _down)
{
    draw_set_colour(_col);
    if (_down)
    {
        draw_triangle(_x - _size, _y - _size * 0.5, _x + _size, _y - _size * 0.5, _x, _y + _size * 0.6, false);
    }
    else
    {
        draw_triangle(_x - _size, _y + _size * 0.5, _x + _size, _y + _size * 0.5, _x, _y - _size * 0.6, false);
    }
}

function ui_background(_w, _h)
{
    draw_rectangle_colour(0, 0, _w, _h, global.TH.bg_top, global.TH.bg_top, global.TH.bg_bot, global.TH.bg_bot, false);
    // soft vignette corners
    draw_set_alpha(0.18);
    draw_circle_colour(_w * 0.15, -_h * 0.2, _h * 0.9, make_colour_rgb(70, 82, 100), global.TH.bg_top, false);
    draw_set_alpha(1);
}
