/// ADAM - Backdrop workspace (paint the 320 x 256 playfield)

/// ADAM Pro dither pattern: a pixel is painted when its Bayer threshold is
/// below this (64 = solid, every pixel). ADAM Lite always paints solid.
function bd_pat_level()
{
    if (!pro_on()) { return 64; }
    return global.BD_PATTERN_LEVELS[clamp(bd_pattern, 0, array_length(global.BD_PATTERN_LEVELS) - 1)];
}

/// Fills a rectangle of backdrop pixels (clipped). _solid ignores the dither pattern.
function backdrop_fill_rect(_x1, _y1, _x2, _y2, _v, _solid = false)
{
    var _ax = clamp(min(_x1, _x2), 0, BD_W - 1);
    var _bx = clamp(max(_x1, _x2), 0, BD_W - 1);
    var _ay = clamp(min(_y1, _y2), 0, BD_H - 1);
    var _by = clamp(max(_y1, _y2), 0, BD_H - 1);
    var _lev = 64;
    if (!_solid) { _lev = bd_pat_level(); }
    for (var py = _ay; py <= _by; py++)
    {
        var _row = py * BD_W;
        for (var px = _ax; px <= _bx; px++)
        {
            if (_lev < 64)
            {
                if (bayer8(px, py) >= _lev) { continue; }
            }
            proj.pixels[_row + px] = _v;
            buffer_poke(bd_buf, (_row + px) * 4, buffer_u32, 0xff000000 | _v);
        }
    }
    proj_dirty = true;
    bd_upload = true;
}

/// Square brush centred on a pixel
function backdrop_stamp(_x, _y, _v)
{
    var _s = bd_brush;
    var _h = _s div 2;
    backdrop_fill_rect(_x - _h, _y - _h, _x - _h + _s - 1, _y - _h + _s - 1, _v);
}

/// Brush line between two pixels
function backdrop_line(_x1, _y1, _x2, _y2, _v)
{
    var _dx = abs(_x2 - _x1);
    var _dy = abs(_y2 - _y1);
    var _steps = max(_dx, _dy);
    if (_steps == 0)
    {
        backdrop_stamp(_x1, _y1, _v);
        return;
    }
    for (var i = 0; i <= _steps; i++)
    {
        backdrop_stamp(round(lerp(_x1, _x2, i / _steps)), round(lerp(_y1, _y2, i / _steps)), _v);
    }
}

/// Scanline flood fill (with the dither pattern in ADAM Pro)
function backdrop_flood(_x, _y, _v)
{
    var _target = proj.pixels[_y * BD_W + _x];
    if (_target == _v) { return; }
    var _lev = bd_pat_level();
    var _area = backdrop_region(_x, _y);
    for (var i = 0; i < array_length(_area); i++)
    {
        var _i = _area[i];
        if (_lev < 64)
        {
            if (bayer8(_i mod BD_W, _i div BD_W) >= _lev) { continue; }
        }
        proj.pixels[_i] = _v;
    }
    bd_dirty = true;
    proj_dirty = true;
}

/// Pixel indices of the area of one colour joined to (_x, _y) (scanline flood)
function backdrop_region(_x, _y)
{
    var _target = proj.pixels[_y * BD_W + _x];
    var _seen = array_create(BD_W * BD_H, false);
    var _out = [];
    var _stack = [_x, _y];
    while (array_length(_stack) > 0)
    {
        var _sy = array_pop(_stack);
        var _sx = array_pop(_stack);
        if (_seen[_sy * BD_W + _sx]) { continue; }
        var _l = _sx;
        while (_l > 0 && proj.pixels[_sy * BD_W + _l - 1] == _target && !_seen[_sy * BD_W + _l - 1]) { _l -= 1; }
        var _r = _sx;
        while (_r < BD_W - 1 && proj.pixels[_sy * BD_W + _r + 1] == _target && !_seen[_sy * BD_W + _r + 1]) { _r += 1; }
        for (var px = _l; px <= _r; px++)
        {
            _seen[_sy * BD_W + px] = true;
            array_push(_out, _sy * BD_W + px);
            if (_sy > 0)
            {
                var _u = (_sy - 1) * BD_W + px;
                if (!_seen[_u] && proj.pixels[_u] == _target) { array_push(_stack, px, _sy - 1); }
            }
            if (_sy < BD_H - 1)
            {
                var _d = (_sy + 1) * BD_W + px;
                if (!_seen[_d] && proj.pixels[_d] == _target) { array_push(_stack, px, _sy + 1); }
            }
        }
    }
    return _out;
}

/// ADAM Pro gradient fill: the area of one colour under (_x1, _y1) shades from colour
/// _from at the start of the drag to colour _to at its end, with a Bayer dither between
/// the steps. With _range it steps through the palette colours in between, as Deluxe
/// Paint ranges do; otherwise it dithers straight from one colour to the other.
function backdrop_gradient(_x1, _y1, _x2, _y2, _from, _to, _range)
{
    var _cols = [_from, _to];
    if (_range && abs(_to - _from) > 1)
    {
        _cols = [];
        var _st = sign(_to - _from);
        for (var c = _from; c != _to + _st; c += _st) { array_push(_cols, c); }
    }
    var _m = array_length(_cols) - 1;
    var _dx = _x2 - _x1;
    var _dy = _y2 - _y1;
    var _len2 = max(1, _dx * _dx + _dy * _dy);
    var _area = backdrop_region(_x1, _y1);
    for (var i = 0; i < array_length(_area); i++)
    {
        var _i = _area[i];
        var _px = _i mod BD_W;
        var _py = _i div BD_W;
        var _t = clamp(((_px - _x1) * _dx + (_py - _y1) * _dy) / _len2, 0, 1);
        var _pos = _t * _m;
        var _k = min(floor(_pos), _m - 1);
        var _f = _pos - _k;
        var _v = _cols[_k];
        if ((bayer8(_px, _py) + 0.5) / 64 < _f) { _v = _cols[_k + 1]; }
        proj.pixels[_i] = _v;
    }
    bd_dirty = true;
    proj_dirty = true;
}

/// Stamps one font character at the text cursor
function backdrop_text_char(_ch)
{
    for (var r = 0; r < 8; r++)
    {
        var _bits = font_glyph_row(_ch, r);
        for (var b = 0; b < 8; b++)
        {
            if ((_bits & (128 >> b)) != 0) { backdrop_plot(bd_text_x + b, bd_text_y + r, bd_sel); }
        }
    }
    bd_text_x += 8;
}

function ws_backdrop_draw(_x1, _y1, _x2, _y2)
{
    var _rw = 330;
    var _cx2 = _x2 - _rw - 12;
    ui_panel(_x1, _y1, _cx2, _y2, "");

    // ---------------- canvas ----------------
    var _vx1 = _x1 + 16;
    var _vy1 = _y1 + 16;
    var _vx2 = _cx2 - 16;
    var _vy2 = _y2 - 40;
    var _fit = min((_vx2 - _vx1) / BD_W, (_vy2 - _vy1) / BD_H);
    if (_fit >= 2) { _fit = floor(_fit); }
    var _scale = _fit;
    if (bd_zoom > 0) { _scale = bd_zoom; }
    var _vis_w = min(BD_W, (_vx2 - _vx1) / _scale);
    var _vis_h = min(BD_H, (_vy2 - _vy1) / _scale);
    bd_pan_x = clamp(bd_pan_x, 0, BD_W - _vis_w);
    bd_pan_y = clamp(bd_pan_y, 0, BD_H - _vis_h);
    if (bd_zoom == 0)
    {
        bd_pan_x = 0;
        bd_pan_y = 0;
    }
    var _cw = _vis_w * _scale;
    var _ch = _vis_h * _scale;
    var _ox = floor((_vx1 + _vx2 - _cw) / 2);
    var _oy = floor((_vy1 + _vy2 - _ch) / 2);
    ui_rrect(_ox - 6, _oy - 6, _ox + _cw + 6, _oy + _ch + 6, 8, c_black, c_black, 0.35);
    ui_scissor(_ox, _oy, _cw, _ch);
    backdrop_draw(_ox - bd_pan_x * _scale, _oy - bd_pan_y * _scale, _scale);
    if (bd_show_hills && proj.levels_on) { terrain_draw(_ox - bd_pan_x * _scale, _oy - bd_pan_y * _scale, _scale); }
    if (bd_show_actors)
    {
        for (var a = 0; a < array_length(proj.actors); a++)
        {
            var _ac = proj.actors[a];
            var _al = 0.85;
            if (!_ac.visible) { _al = 0.35; }
            draw_sprite_amiga_cols(_ac.sprite, _ox + (_ac.x - bd_pan_x) * _scale, _oy + (_ac.y - bd_pan_y) * _scale, _scale, actor_shown_cols(a), _al);
        }
    }
    if (bd_show_hud)
    {
        var _hy = _oy + (proj.hud_row * 8 - bd_pan_y) * _scale;
        var _hc = pal_col(proj.hud_colour);
        if (proj.show_score) { draw_font8(_ox + (8 - bd_pan_x) * _scale, _hy, "SCORE 00000", _scale, _hc); }
        if (proj.show_lives) { draw_font8(_ox + (248 - bd_pan_x) * _scale, _hy, "LIVES " + string(proj.lives), _scale, _hc); }
    }
    ui_scissor_reset();

    var _hot = ui_register("bd_canvas", _ox, _oy, _ox + _cw, _oy + _ch, "Backdrop|Left-click paints with the selected colour, right-click paints colour 0. Alt-click picks a colour up. Mouse wheel zooms, middle-drag (or Space + drag) moves around when zoomed in.");
    var _mpx = floor((ui_mx - _ox) / _scale + bd_pan_x);
    var _mpy = floor((ui_my - _oy) / _scale + bd_pan_y);
    var _inside = (_mpx >= 0 && _mpy >= 0 && _mpx < BD_W && _mpy < BD_H);

    // zoom and pan
    if (_hot && ui_wheel != 0)
    {
        var _levels = [0, 2, 3, 4, 6, 8, 12];
        var _li = 0;
        for (var l = 0; l < array_length(_levels); l++)
        {
            if (_levels[l] == bd_zoom) { _li = l; }
        }
        var _nl = clamp(_li + ui_wheel, 0, array_length(_levels) - 1);
        while (ui_wheel > 0 && _nl < array_length(_levels) - 1 && _levels[_nl] != 0 && _levels[_nl] <= _fit) { _nl += 1; }
        bd_zoom = _levels[_nl];
        var _ns = _fit;
        if (bd_zoom > 0) { _ns = bd_zoom; }
        if (_ns <= _fit) { bd_zoom = 0; }
        if (bd_zoom > 0 && _inside)
        {
            bd_pan_x = _mpx - (ui_mx - _ox) / _ns;
            bd_pan_y = _mpy - (ui_my - _oy) / _ns;
        }
        ui_wheel = 0;
    }
    var _pan_key = keyboard_check(vk_space) && ui_focus == "" && !bd_text_on;
    if (_hot && (mouse_check_button_pressed(mb_middle) || (_pan_key && ui_pressed)))
    {
        bd_panning = true;
        bd_pan_mx = ui_mx;
        bd_pan_my = ui_my;
        ui_take_click();
    }
    if (bd_panning)
    {
        if (mouse_check_button(mb_middle) || (ui_held && _pan_key))
        {
            bd_pan_x -= (ui_mx - bd_pan_mx) / _scale;
            bd_pan_y -= (ui_my - bd_pan_my) / _scale;
            bd_pan_mx = ui_mx;
            bd_pan_my = ui_my;
        }
        else { bd_panning = false; }
    }

    // painting
    if (_hot && _inside && !bd_panning)
    {
        // cursor preview
        var _bs = 1;
        if (bd_tool == 0 || bd_tool == 1) { _bs = bd_brush; }
        var _bh = _bs div 2;
        if (bd_tool == 3 || bd_tool == 5 || bd_tool == 6) { _bh = 0; _bs = 1; }
        draw_rectangle_colour(_ox + (_mpx - _bh - bd_pan_x) * _scale, _oy + (_mpy - _bh - bd_pan_y) * _scale,
                              _ox + (_mpx - _bh + _bs - bd_pan_x) * _scale - 1, _oy + (_mpy - _bh + _bs - bd_pan_y) * _scale - 1, c_white, c_white, c_white, c_white, true);
        var _alt = keyboard_check(vk_alt);
        if ((ui_pressed || ui_rpressed) && (_alt || bd_tool == 5))
        {
            bd_sel = proj.pixels[_mpy * BD_W + _mpx];
            ui_take_click();
        }
        else
        {
            if (ui_pressed || ui_rpressed)
            {
                var _v = bd_sel;
                if (ui_rpressed) { _v = 0; }
                bd_paint_v = _v;
                undo_mark("bdpaint" + string(current_time));
                ui_take_click();
                switch (bd_tool)
                {
                    case 0:
                        bd_drawing = true;
                        bd_line_x = _mpx;
                        bd_line_y = _mpy;
                        backdrop_stamp(_mpx, _mpy, _v);
                        break;
                    case 1:
                    case 2:
                    case 6:
                        bd_drawing = true;
                        bd_line_x = _mpx;
                        bd_line_y = _mpy;
                        break;
                    case 3:
                        backdrop_flood(_mpx, _mpy, _v);
                        break;
                    case 4:
                        bd_text_on = true;
                        bd_text_x = _mpx;
                        bd_text_y = _mpy;
                        bd_text_start_x = _mpx;
                        keyboard_string = "";
                        ui_focus = "bd_text";
                        break;
                }
            }
        }
    }
    if (bd_drawing)
    {
        var _held = ui_held || ui_rheld;
        var _cx = clamp(_mpx, 0, BD_W - 1);
        var _cy = clamp(_mpy, 0, BD_H - 1);
        if (bd_tool == 0 && _held)
        {
            backdrop_line(bd_line_x, bd_line_y, _cx, _cy, bd_paint_v);
            bd_line_x = _cx;
            bd_line_y = _cy;
        }
        if ((bd_tool == 1 || bd_tool == 2) && _held)
        {
            // rubber-band preview
            var _pc = pal_col(bd_paint_v);
            var _ax = _ox + (bd_line_x - bd_pan_x + 0.5) * _scale;
            var _ay = _oy + (bd_line_y - bd_pan_y + 0.5) * _scale;
            var _bx = _ox + (_cx - bd_pan_x + 0.5) * _scale;
            var _by = _oy + (_cy - bd_pan_y + 0.5) * _scale;
            if (bd_tool == 1) { draw_line_width_colour(_ax, _ay, _bx, _by, max(1, bd_brush * _scale), _pc, _pc); }
            else
            {
                draw_set_alpha(0.8);
                draw_rectangle_colour(min(_ax, _bx) - _scale * 0.5, min(_ay, _by) - _scale * 0.5, max(_ax, _bx) + _scale * 0.5, max(_ay, _by) + _scale * 0.5, _pc, _pc, _pc, _pc, false);
                draw_set_alpha(1);
            }
            ui_text(_bx + 14, _by + 14, string(abs(_cx - bd_line_x) + 1) + " x " + string(abs(_cy - bd_line_y) + 1), global.TH.warn, fa_left, fa_top, global.f_small, 1);
        }
        if (bd_tool == 6 && _held)
        {
            // gradient direction: from colour (start) to colour (end)
            var _gx1 = _ox + (bd_line_x - bd_pan_x + 0.5) * _scale;
            var _gy1 = _oy + (bd_line_y - bd_pan_y + 0.5) * _scale;
            var _gx2 = _ox + (_cx - bd_pan_x + 0.5) * _scale;
            var _gy2 = _oy + (_cy - bd_pan_y + 0.5) * _scale;
            draw_line_width_colour(_gx1, _gy1, _gx2, _gy2, 3, c_black, c_black);
            draw_line_width_colour(_gx1, _gy1, _gx2, _gy2, 1, c_white, c_white);
            draw_circle_colour(_gx1, _gy1, 7, pal_col(bd_paint_v), pal_col(bd_paint_v), false);
            draw_circle_colour(_gx2, _gy2, 7, pal_col(bd_grad_to), pal_col(bd_grad_to), false);
            draw_circle_colour(_gx1, _gy1, 7, c_white, c_white, true);
            draw_circle_colour(_gx2, _gy2, 7, c_white, c_white, true);
        }
        if (!_held)
        {
            if (bd_tool == 1) { backdrop_line(bd_line_x, bd_line_y, _cx, _cy, bd_paint_v); }
            if (bd_tool == 2) { backdrop_fill_rect(bd_line_x, bd_line_y, _cx, _cy, bd_paint_v); }
            if (bd_tool == 6) { backdrop_gradient(bd_line_x, bd_line_y, _cx, _cy, bd_paint_v, bd_grad_to, bd_grad_range); }
            bd_drawing = false;
        }
    }

    // text tool typing
    if (bd_text_on)
    {
        if (ui_focus != "bd_text" || keyboard_check_pressed(vk_escape) || bd_tool != 4)
        {
            bd_text_on = false;
            if (ui_focus == "bd_text") { ui_focus = ""; }
        }
        else
        {
            ui_focus_claimed = true;
            var _typed = keyboard_string;
            keyboard_string = "";
            for (var t = 1; t <= string_length(_typed); t++)
            {
                undo_mark("bdtext");
                backdrop_text_char(string_char_at(_typed, t));
            }
            if (keyboard_check_pressed(vk_backspace)) { bd_text_x -= 8; }
            if (keyboard_check_pressed(vk_enter))
            {
                bd_text_x = bd_text_start_x;
                bd_text_y += 9;
            }
            if ((current_time div 400) mod 2 == 0)
            {
                var _tx = _ox + (bd_text_x - bd_pan_x) * _scale;
                var _ty = _oy + (bd_text_y - bd_pan_y) * _scale;
                draw_rectangle_colour(_tx, _ty, _tx + 8 * _scale - 1, _ty + 8 * _scale - 1, c_white, c_white, c_white, c_white, true);
            }
        }
    }

    // status line
    var _info = "320 x 256  -  " + string(pal_count()) + " colours (" + string(proj.depth) + " bitplanes)";
    if (_inside && _hot) { _info = "X " + string(_mpx) + "   Y " + string(_mpy) + "   colour " + string(proj.pixels[_mpy * BD_W + _mpx]) + "      " + _info; }
    var _zl = "Fit";
    if (bd_zoom > 0) { _zl = string(bd_zoom) + "x"; }
    ui_text(_x1 + 20, _y2 - 22, _info, global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    ui_text(_cx2 - 20, _y2 - 22, "Zoom " + _zl + "  (mouse wheel)", global.TH.text_faint, fa_right, fa_middle, global.f_small, 1);

    // ---------------- tools panel ----------------
    var _px = _x2 - _rw;
    ui_panel(_px, _y1, _x2, _y2, "");
    var _fx = _px + 20;
    var _fw = _rw - 40;
    var _tabw = floor((_rw - 28) / 2);
    if (ui_tab("bd_tab_paint", _px + 14, _y1 + 10, _tabw, 30, "Paint", bd_panel == 0, "Paint|Tools, palette and picture import for the backdrop.")) { bd_panel = 0; }
    if (ui_tab("bd_tab_sky", _px + 14 + _tabw, _y1 + 10, _tabw, 30, "Copper sky", bd_panel == 1, "Copper sky|The classic Amiga trick: the copper changes colour 0 on every line, giving a smooth sky behind the backdrop for free.")) { bd_panel = 1; }
    if (bd_panel == 1)
    {
        backdrop_sky_panel(_fx, _y1 + 56, _fw, _y2);
        return;
    }
    var _y = _y1 + 56;
    var _names = ["Brush", "Line", "Box", "Fill", "Text", "Pick"];
    var _thelp = ["Brush|Paint freehand. Right-click paints colour 0.",
                  "Line|Drag to draw a straight line with the brush.",
                  "Box|Drag out a filled box - great for floors, walls and panels.",
                  "Fill|Floods an area of one colour with the selected colour.",
                  "Text|Click on the backdrop, then type. Uses the same 8 x 8 font as the score. Enter starts a new line, Esc stops.",
                  "Pick|Click the backdrop to pick up a colour (Alt-click does this with any tool)."];
    var _tw = floor((_fw - 10) / 3);
    for (var k = 0; k < 6; k++)
    {
        var _st = BTN_GHOST;
        if (bd_tool == k) { _st = BTN_ACCENT; }
        if (ui_button("bd_tool_" + string(k), _fx + (k mod 3) * (_tw + 5), _y + (k div 3) * 38, _tw, 32, _names[k], _thelp[k], _st)) { bd_tool = k; }
    }
    // ADAM Pro: gradient fill, dithered with a Bayer pattern
    var _gst = BTN_GHOST;
    if (bd_tool == 6) { _gst = BTN_ACCENT; }
    var _glabel = "Gradient";
    if (!pro_on()) { _glabel = "Gradient  (Pro)"; }
    if (ui_button("bd_tool_6", _fx, _y + 76, _fw, 32, _glabel, "Gradient|Drag across an area of one colour: it shades from the selected colour where you start to the 'To' colour where you let go, blended with an Amiga-style dither pattern. Great for skies, sunsets and metal. Part of ADAM Pro.", _gst))
    {
        if (pro_gate("The gradient tool")) { bd_tool = 6; }
    }
    _y += 120;
    if (bd_tool == 6)
    {
        ui_heading(_fx, _y, "Gradient to");
        bd_grad_to = ui_colour_drop("bd_grad_to", _fx, _y + 18, floor(_fw / 2) - 6, 28, clamp(bd_grad_to, 0, pal_count() - 1), "Gradient to|The colour the gradient ends with. It starts with the selected colour.");
        bd_grad_range = ui_toggle("bd_grad_range", _fx + floor(_fw / 2) + 6, _y + 20, "Colours between", bd_grad_range, "Colours in between|On: the gradient steps through every palette colour between the two, like a Deluxe Paint range - put your shades next to each other in the palette. Off: it dithers straight from one colour to the other.");
        _y += 60;
    }
    else
    {
        ui_heading(_fx, _y, "Brush size");
        var _sizes = [1, 2, 3, 5, 8];
        var _sw = floor((_fw - 16) / 5);
        for (var b2 = 0; b2 < 5; b2++)
        {
            var _sst = BTN_GHOST;
            if (bd_brush == _sizes[b2]) { _sst = BTN_ON; }
            if (ui_button("bd_size_" + string(b2), _fx + b2 * (_sw + 4), _y + 18, _sw, 28, string(_sizes[b2]), "Brush size|How many pixels wide the brush and line tools paint.", _sst)) { bd_brush = _sizes[b2]; }
        }
        _y += 56;
        // ADAM Pro: paint with a Bayer dither pattern (brush, line, box and fill)
        var _phead = "Pattern";
        if (!pro_on()) { _phead = "Pattern  (Pro)"; }
        ui_heading(_fx, _y, _phead);
        var _np = array_length(global.BD_PATTERN_NAMES);
        for (var pt = 0; pt < _np; pt++)
        {
            var _pst = BTN_GHOST;
            if (pro_on() && bd_pattern == pt) { _pst = BTN_ON; }
            if (ui_button("bd_pat_" + string(pt), _fx + pt * (_sw + 4), _y + 18, _sw, 28, global.BD_PATTERN_NAMES[pt], "Dither pattern|Brush, Line, Box and Fill paint only some pixels in an even Amiga-style pattern, so the colour underneath shows through: 50% is a checkerboard. Paint a pattern over another colour for in-between shades. Part of ADAM Pro.", _pst))
            {
                if (pro_gate("Dither patterns")) { bd_pattern = pt; }
            }
        }
        _y += 56;
    }

    ui_heading(_fx, _y, "Colours");
    var _m = machine_cur();
    var _dn = [];
    for (var d = 0; d < _m.max_depth; d++) { array_push(_dn, global.DEPTH_NAMES[d]); }
    var _nd = ui_dropdown("bd_depth", _fx + 90, _y - 6, _fw - 90, 26, _dn, proj.depth - 1, "Number of colours|More colours means more bitplanes: more memory and more work for the Amiga. The " + _m.name + " backdrop can use up to " + string(1 << _m.max_depth) + ". Fewer colours moves pixels to the nearest colour that is left.") + 1;
    if (_nd != proj.depth)
    {
        undo_mark("bddepth" + string(current_time));
        backdrop_set_depth(_nd);
    }
    _y += 28;
    var _n = pal_count();
    var _cols = 8;
    if (_n > 32) { _cols = 16; }
    var _cell = floor((_fw - (_cols - 1) * 4) / _cols);
    bd_sel = ui_palette_grid("bd_pal", _fx, _y, _cell, _cols, clamp(bd_sel, 0, _n - 1), "Palette|Click a colour to paint with it and edit it below");
    _y += ceil(_n / _cols) * (_cell + 4) + 10;

    ui_heading(_fx, _y, "Colour " + string(bd_sel) + "   " + rgb_hex(proj.pal[bd_sel]));
    ui_rrect(_fx + _fw - 46, _y - 4, _fx + _fw, _y + 14, 5, pal_col(bd_sel), pal_col(bd_sel), 1);
    _y += 20;
    var _gunhelp = "Colour mixer|Red, green and blue for this colour. The A500/600 has 16 steps per gun (4096 colours), the A1200 has 256 (16.8 million).";
    if (bd_sel == 0) { _gunhelp += " Colour 0 is also the border and the screen background."; }
    var _nc = ui_rgb_sliders("bd_rgb", _fx, _y, _fw, proj.pal[bd_sel], _gunhelp);
    if (_nc != rgb_machine(proj.pal[bd_sel]))
    {
        undo_mark("bdcol" + string(bd_sel));
        proj.pal[bd_sel] = _nc;
    }
    _y += 94;
    var _was = (proj.solid[bd_sel] != 0);
    var _gr = ui_toggle("bd_solid", _fx, _y, "Ground colour (actors stand on it)", _was, "Ground colour|Platform players, hoppers and fallers stand on the first ground-coloured pixel in each column, so they walk up and down your hills. Marked with a dot in the palette. The Actors page shows the ground line.");
    if (_gr != _was)
    {
        undo_mark("bdsolid" + string(current_time));
        if (_gr) { proj.solid[bd_sel] = 1; }
        else { proj.solid[bd_sel] = 0; }
        ground_cache_time = -10000;
    }
    _y += 34;

    ui_heading(_fx, _y, "Picture");
    _y += 18;
    if (ui_button("bd_import", _fx, _y, _fw - 120, 32, "Import picture...", "Import picture|Loads a PNG or JPG, fits it into 320 x 256 and works out the best " + string(_n) + " colours for it. This replaces the backdrop and its palette (Undo brings them back).", BTN_ACCENT))
    {
        var _f = get_open_filename("Pictures|*.png;*.jpg;*.jpeg;*.gif", "");
        if (_f != "")
        {
            undo_mark("bdimport" + string(current_time));
            if (backdrop_import(_f, bd_dither)) { toast("Picture imported with " + string(_n) + " colours", 0); }
            else { toast("Could not load that picture", 2); }
        }
    }
    bd_dither = ui_dropdown("bd_dither", _fx + _fw - 110, _y, 110, 32, ["No dither", "Smooth", "Pattern"], clamp(bd_dither, 0, 2), "Dither|How an imported picture mixes its colours so smooth shading survives with few colours. Smooth spreads the error around (Floyd-Steinberg). Pattern uses an even Bayer grid, the classic Amiga look - it also stays steady when the picture is changed slightly.");
    _y += 42;
    if (ui_button("bd_clear", _fx, _y, _fw, 30, "Fill whole backdrop with colour " + string(bd_sel), "Clear|Paints the whole backdrop in the selected colour. You can Undo this.", BTN_DANGER))
    {
        undo_mark("bdclear" + string(current_time));
        backdrop_fill_rect(0, 0, BD_W - 1, BD_H - 1, bd_sel, true);
    }
    _y += 42;
    bd_show_actors = ui_toggle("bd_actors", _fx, _y, "Show actors", bd_show_actors, "Show actors|Draws your actors where they start, so you can paint around them.");
    bd_show_hud = ui_toggle("bd_hud", _fx + floor(_fw / 2), _y, "Show score", bd_show_hud, "Show score row|Shows where the score and lives text will be drawn over the backdrop.");
    if (proj.levels_on)
    {
        _y += 32;
        bd_show_hills = ui_toggle("bd_hills", _fx, _y, "Show level hills", bd_show_hills, "Show hills|Draws the hills of the level selected on the Levels page over the backdrop, as the game will.");
    }
}

/// Copper sky settings (right panel, "Copper sky" tab)
function backdrop_sky_panel(_fx, _y, _fw, _y2)
{
    var _on = ui_toggle("sky_on", _fx, _y, "Copper sky on", proj.sky_on, "Copper sky|Every pixel painted in colour 0, and the border, shows a smooth gradient made by the copper. It costs no memory and works on the A500/600 and the A1200.");
    if (_on != proj.sky_on)
    {
        undo_mark("skyon" + string(current_time));
        proj.sky_on = _on;
    }
    _y += 36;
    var _aga = machine_cur().aga;
    var _gmax = 15;             // slider range per gun: 0..15 (12-bit) or 0..255 (24-bit)
    var _gscale = 17;
    var _intro = "Paint the parts you want to see the sky through with colour 0. The copper writes 12-bit colours, so each gun has 16 steps; neighbouring colours are blended over a few lines so the steps don't show as hard edges.";
    if (_aga)
    {
        _gmax = 255;
        _gscale = 1;
        _intro = "Paint the parts you want to see the sky through with colour 0. On the A1200 the copper writes 24-bit colours, so each gun has 256 steps - a very smooth sky.";
    }
    ui_text_wrap(_fx, _y, _intro, global.TH.text_dim, _fw, global.f_small, 1);
    _y += ceil(ui_sh_ext(_intro, _fw)) + 14;

    ui_heading(_fx, _y, "Colour stops");
    _y += 18;
    var _names = ["Top", "Middle", "Bottom"];
    var _keys = ["sky_top", "sky_mid", "sky_bot"];
    var _bw = floor((_fw - 16) / 3);
    for (var i = 0; i < 3; i++)
    {
        var _bx = _fx + i * (_bw + 8);
        var _st = BTN_GHOST;
        if (sky_stop == i) { _st = BTN_ACCENT; }
        if (ui_button("sky_stop_" + string(i), _bx, _y, _bw, 44, "", _names[i] + " colour|Click to edit this colour stop with the sliders below.", _st)) { sky_stop = i; }
        var _c = proj[$ _keys[i]];
        var _gc = amiga_col(_c);
        ui_rrect(_bx + 8, _y + 6, _bx + 26, _y + 24, 4, _gc, _gc, 1);
        ui_text(_bx + 8, _y + 34, _names[i], global.TH.text, fa_left, fa_middle, global.f_small, 1);
    }
    _y += 54;
    var _key = _keys[sky_stop];
    var _cur = proj[$ _key];
    var _shown = rgb_machine(_cur);
    var _gun = [rgb_r(_shown) div _gscale, rgb_g(_shown) div _gscale, rgb_b(_shown) div _gscale];
    var _lab = ["R", "G", "B"];
    var _tint = [make_colour_rgb(255, 90, 90), make_colour_rgb(90, 230, 120), make_colour_rgb(100, 150, 255)];
    for (var k = 0; k < 3; k++)
    {
        ui_text(_fx, _y + 13, _lab[k], _tint[k], fa_left, fa_middle, global.f_bold, 1);
        _gun[k] = ui_slider("sky_rgb_" + _lab[k], _fx + 18, _y, _fw - 58, _gun[k], 0, _gmax, "Copper colour|Red, green and blue for this stop: 0 to 15 on the A500/600 (12-bit), 0 to 255 on the A1200 (24-bit), as the copper writes them.");
        ui_text(_fx + _fw, _y + 13, string(_gun[k]), global.TH.text, fa_right, fa_middle, global.f_bold, 1);
        _y += 30;
    }
    var _nc = rgb_make(_gun[0] * _gscale, _gun[1] * _gscale, _gun[2] * _gscale);
    if (_nc != _shown)
    {
        undo_mark("skycol" + _key);
        proj[$ _key] = _nc;
    }
    _y += 10;
    ui_heading(_fx, _y, "Middle stop at line " + string(proj.sky_mid_y));
    var _my = ui_slider("sky_midy", _fx, _y + 18, _fw, proj.sky_mid_y, 1, 254, "Middle line|Which of the 256 lines the middle colour sits on. Move it down for a lower horizon.");
    set_val(proj, "sky_mid_y", _my, "skymidy");
    _y += 58;

    ui_heading(_fx, _y, "Ready-made skies");
    _y += 18;
    var _pr = sky_presets();
    var _pw = floor((_fw - 8) / 2);
    for (var p = 0; p < array_length(_pr); p++)
    {
        var _px = _fx + (p mod 2) * (_pw + 8);
        var _py = _y + (p div 2) * 38;
        if (ui_button("sky_preset_" + string(p), _px, _py, _pw, 32, _pr[p][0], "Sky preset|Sets all three colour stops and the middle line to a " + string_lower(_pr[p][0]) + " look, and turns the sky on.", BTN_NORMAL))
        {
            undo_mark("skypreset" + string(current_time));
            proj.sky_top = _pr[p][1];
            proj.sky_mid = _pr[p][2];
            proj.sky_bot = _pr[p][3];
            proj.sky_mid_y = _pr[p][4];
            proj.sky_on = true;
        }
    }
}
