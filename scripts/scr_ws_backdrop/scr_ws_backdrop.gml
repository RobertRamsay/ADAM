/// ADAM - Backdrop workspace (paint the 320 x 256 playfield)

/// Fills a rectangle of backdrop pixels (clipped) with one surface write
function backdrop_fill_rect(_x1, _y1, _x2, _y2, _v)
{
    var _ax = clamp(min(_x1, _x2), 0, BD_W - 1);
    var _bx = clamp(max(_x1, _x2), 0, BD_W - 1);
    var _ay = clamp(min(_y1, _y2), 0, BD_H - 1);
    var _by = clamp(max(_y1, _y2), 0, BD_H - 1);
    for (var py = _ay; py <= _by; py++)
    {
        var _row = py * BD_W;
        for (var px = _ax; px <= _bx; px++) { proj.pixels[_row + px] = _v; }
    }
    proj_dirty = true;
    if (surface_exists(bd_surf) && !bd_dirty)
    {
        surface_set_target(bd_surf);
        gpu_set_blendenable(false);
        px_rect(_ax, _ay, _bx - _ax + 1, _by - _ay + 1, make_colour_rgb(_v, 0, 0));
        gpu_set_blendenable(true);
        surface_reset_target();
    }
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

/// Scanline flood fill
function backdrop_flood(_x, _y, _v)
{
    var _target = proj.pixels[_y * BD_W + _x];
    if (_target == _v) { return; }
    var _stack = [_x, _y];
    while (array_length(_stack) > 0)
    {
        var _sy = array_pop(_stack);
        var _sx = array_pop(_stack);
        var _l = _sx;
        while (_l > 0 && proj.pixels[_sy * BD_W + _l - 1] == _target) { _l -= 1; }
        var _r = _sx;
        while (_r < BD_W - 1 && proj.pixels[_sy * BD_W + _r + 1] == _target) { _r += 1; }
        for (var px = _l; px <= _r; px++)
        {
            proj.pixels[_sy * BD_W + px] = _v;
            if (_sy > 0 && proj.pixels[(_sy - 1) * BD_W + px] == _target) { array_push(_stack, px, _sy - 1); }
            if (_sy < BD_H - 1 && proj.pixels[(_sy + 1) * BD_W + px] == _target) { array_push(_stack, px, _sy + 1); }
        }
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
        if (bd_tool == 3 || bd_tool == 5) { _bh = 0; _bs = 1; }
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
        if (!_held)
        {
            if (bd_tool == 1) { backdrop_line(bd_line_x, bd_line_y, _cx, _cy, bd_paint_v); }
            if (bd_tool == 2) { backdrop_fill_rect(bd_line_x, bd_line_y, _cx, _cy, bd_paint_v); }
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
    ui_panel(_px, _y1, _x2, _y2, "Paint");
    var _fx = _px + 20;
    var _fw = _rw - 40;
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
    _y += 82;
    ui_heading(_fx, _y, "Brush size");
    var _sizes = [1, 2, 3, 5, 8];
    var _sw = floor((_fw - 16) / 5);
    for (var b2 = 0; b2 < 5; b2++)
    {
        var _sst = BTN_GHOST;
        if (bd_brush == _sizes[b2]) { _sst = BTN_ON; }
        if (ui_button("bd_size_" + string(b2), _fx + b2 * (_sw + 4), _y + 18, _sw, 28, string(_sizes[b2]), "Brush size|How many pixels wide the brush and line tools paint.", _sst)) { bd_brush = _sizes[b2]; }
    }
    _y += 60;

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
    _y += 98;

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
    bd_dither = ui_toggle("bd_dither", _fx + _fw - 110, _y + 4, "Dither", bd_dither, "Dither|Mixes nearby colours in a fine pattern so smooth shading survives with few colours.");
    _y += 42;
    if (ui_button("bd_clear", _fx, _y, _fw, 30, "Fill whole backdrop with colour " + string(bd_sel), "Clear|Paints the whole backdrop in the selected colour. You can Undo this.", BTN_DANGER))
    {
        undo_mark("bdclear" + string(current_time));
        backdrop_fill_rect(0, 0, BD_W - 1, BD_H - 1, bd_sel);
    }
    _y += 42;
    bd_show_actors = ui_toggle("bd_actors", _fx, _y, "Show actors", bd_show_actors, "Show actors|Draws your actors where they start, so you can paint around them.");
    bd_show_hud = ui_toggle("bd_hud", _fx + floor(_fw / 2), _y, "Show score", bd_show_hud, "Show score row|Shows where the score and lives text will be drawn over the backdrop.");
}
