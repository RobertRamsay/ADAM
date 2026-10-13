/// ADAM - Sprites workspace (16 x 24 hardware sprites, 3 colours; ADAM Pro: up to 64 x 64, drawn as BOBs)

function spr_get_px(_s, _x, _y)
{
    return _s.px[_y * _s.w + _x];
}

function spr_set_px(_s, _x, _y, _v)
{
    _s.px[_y * _s.w + _x] = _v;
}

/// Changes sprite _s to _w x _h pixels, keeping the top-left of the picture
function spr_resize(_s, _w, _h)
{
    var _np = array_create(_w * _h, 0);
    for (var py = 0; py < min(_h, _s.h); py++)
    {
        for (var px = 0; px < min(_w, _s.w); px++)
        {
            _np[py * _w + px] = _s.px[py * _s.w + px];
        }
    }
    _s.w = _w;
    _s.h = _h;
    _s.px = _np;
}

/// Paints a line of cells from (_ax, _ay) to (_bx, _by) so fast strokes stay joined up.
/// Returns true if any pixel changed.
function spr_paint_line(_s, _ax, _ay, _bx, _by, _v)
{
    var _changed = false;
    var _dx = abs(_bx - _ax);
    var _dy = -abs(_by - _ay);
    var _sx = 1;
    if (_ax > _bx) { _sx = -1; }
    var _sy = 1;
    if (_ay > _by) { _sy = -1; }
    var _err = _dx + _dy;
    var _cx = _ax;
    var _cy = _ay;
    while (true)
    {
        if (spr_get_px(_s, _cx, _cy) != _v)
        {
            spr_set_px(_s, _cx, _cy, _v);
            _changed = true;
        }
        if (_cx == _bx && _cy == _by) { break; }
        var _e2 = 2 * _err;
        if (_e2 >= _dy)
        {
            _err += _dy;
            _cx += _sx;
        }
        if (_e2 <= _dx)
        {
            _err += _dx;
            _cy += _sy;
        }
    }
    return _changed;
}

function spr_transform(_s, _kind)
{
    var _sw = _s.w;
    var _sh = _s.h;
    var _old = array_create(_sw * _sh, 0);
    array_copy(_old, 0, _s.px, 0, _sw * _sh);
    for (var py = 0; py < _sh; py++)
    {
        for (var px = 0; px < _sw; px++)
        {
            var _sx = px;
            var _sy = py;
            var _v = 0;
            var _ok = true;
            switch (_kind)
            {
                case "fliph": _sx = _sw - 1 - px; break;
                case "flipv": _sy = _sh - 1 - py; break;
                case "left":  _sx = px + 1; break;
                case "right": _sx = px - 1; break;
                case "up":    _sy = py + 1; break;
                case "down":  _sy = py - 1; break;
                case "clear": _ok = false; break;
            }
            if (_sx < 0 || _sx >= _sw || _sy < 0 || _sy >= _sh) { _ok = false; }
            if (_ok) { _v = _old[_sy * _sw + _sx]; }
            _s.px[py * _sw + px] = _v;
        }
    }
}

function ws_sprites_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 230;
    var _rw = 320;
    var _bank = spr_bank_size();
    spr_sel = clamp(spr_sel, 0, _bank - 1);
    var _s = proj.sprites[spr_sel];

    // ---------------- sprite bank ----------------
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "Sprite bank (" + string(_bank) + ")");
    var _ly = _y1 + 54;
    var _rowh = 60;
    var _lcontent = _bank * _rowh + 10;
    var _loff = ui_scroll_begin("spr_list", _x1 + 6, _y1 + 50, _x1 + _lw - 6, _y2 - 8, _lcontent);
    for (var i = 0; i < _bank; i++)
    {
        var _ry = _ly + i * _rowh - _loff;
        if (_ry < _y1 - _rowh || _ry > _y2) { continue; }
        var _id = "spr_slot_" + string(i);
        var _hot = ui_register(_id, _x1 + 10, _ry, _x1 + _lw - 10, _ry + _rowh - 6, proj.sprites[i].name + "|Click to edit this sprite. Actors use sprites as their pictures.");
        var _tgt = 0;
        if (_hot) { _tgt = 1; }
        var _a = ui_anim_to(_id, _tgt);
        if (spr_sel == i)
        {
            ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + _rowh - 6, 10, global.TH.accent, global.TH.accent_dark, 0.9);
        }
        else
        {
            ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + _rowh - 6, 10, global.TH.btn_hot_top, global.TH.btn_hot_bot, _a);
        }
        var _th = _rowh - 14;
        ui_rrect(_x1 + 16, _ry + 4, _x1 + 16 + _th, _ry + 4 + _th, 6, pal_col(0), pal_col(0), 1);
        var _ts = proj.sprites[i];
        var _sc = (_th - 4) / max(_ts.w, _ts.h);
        draw_sprite_amiga(i, _x1 + 16 + (_th - _ts.w * _sc) / 2, _ry + 4 + (_th - _ts.h * _sc) / 2, _sc, 1);
        ui_text(_x1 + 26 + _th, _ry + (_rowh - 6) * 0.5 - 8, ui_text_fit(proj.sprites[i].name, global.f_bold, _lw - 60 - _th), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        var _users = 0;
        for (var u = 0; u < array_length(proj.actors); u++)
        {
            if (proj.actors[u].sprite == i) { _users += 1; }
        }
        var _ut = "Not used yet";
        if (_users == 1) { _ut = "Used by 1 actor"; }
        if (_users > 1) { _ut = "Used by " + string(_users) + " actors"; }
        ui_text(_x1 + 26 + _th, _ry + (_rowh - 6) * 0.5 + 9, _ut, global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            spr_sel = i;
            ui_take_click();
        }
    }
    ui_scroll_end("spr_list", _x1 + 6, _y1 + 50, _x1 + _lw - 6, _y2 - 8, _lcontent);

    // ---------------- editor grid ----------------
    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;
    ui_panel(_cx1, _y1, _cx2, _y2, "");
    var _ps = floor(min((_cx2 - _cx1 - 40) / _s.w, (_y2 - _y1 - 70) / _s.h));
    _ps = max(4, _ps);
    var _gw = _s.w * _ps;
    var _gh = _s.h * _ps;
    var _gx = floor((_cx1 + _cx2 - _gw) / 2);
    var _gy = floor(_y1 + 20 + ((_y2 - _y1 - 40) - _gh) / 2);
    ui_rrect(_gx - 8, _gy - 8, _gx + _gw + 8, _gy + _gh + 8, 10, c_black, c_black, 0.35);
    draw_set_colour(pal_col(0));
    draw_rectangle(_gx, _gy, _gx + _gw - 1, _gy + _gh - 1, false);
    for (var py = 0; py < _s.h; py++)
    {
        for (var px = 0; px < _s.w; px++)
        {
            var _v = spr_get_px(_s, px, py);
            if (_v != 0)
            {
                draw_set_colour(amiga_col(_s.cols[_v - 1]));
                draw_rectangle(_gx + px * _ps, _gy + py * _ps, _gx + px * _ps + _ps - 1, _gy + py * _ps + _ps - 1, false);
            }
        }
    }
    draw_set_alpha(0.14);
    for (var gx = 0; gx <= _s.w; gx++) { draw_line_colour(_gx + gx * _ps, _gy, _gx + gx * _ps, _gy + _gh, c_white, c_white); }
    for (var gy = 0; gy <= _s.h; gy++) { draw_line_colour(_gx, _gy + gy * _ps, _gx + _gw, _gy + gy * _ps, c_white, c_white); }
    draw_set_alpha(0.35);
    for (var hx = 8; hx < _s.w; hx += 8) { draw_line_colour(_gx + hx * _ps, _gy, _gx + hx * _ps, _gy + _gh, global.TH.accent, global.TH.accent); }
    for (var hy = 8; hy < _s.h; hy += 8) { draw_line_colour(_gx, _gy + hy * _ps, _gx + _gw, _gy + hy * _ps, global.TH.accent, global.TH.accent); }
    draw_set_alpha(1);

    var _hot2 = ui_register("spr_grid", _gx, _gy, _gx + _gw - 1, _gy + _gh - 1, "Sprite canvas|Left-click draws with the selected pen, right-click rubs out. Amiga hardware sprites are 16 pixels wide with 3 colours plus see-through; bigger sprites (ADAM Pro) are drawn as BOBs.");
    if (_hot2)
    {
        var _hx = clamp(floor((ui_mx - _gx) / _ps), 0, _s.w - 1);
        var _hy = clamp(floor((ui_my - _gy) / _ps), 0, _s.h - 1);
        draw_set_alpha(0.3);
        draw_set_colour(global.TH.accent);
        draw_rectangle(_gx + _hx * _ps, _gy, _gx + _hx * _ps + _ps - 1, _gy + _gh - 1, true);
        draw_rectangle(_gx, _gy + _hy * _ps, _gx + _gw - 1, _gy + _hy * _ps + _ps - 1, true);
        draw_set_alpha(1);
        draw_rectangle_colour(_gx + _hx * _ps, _gy + _hy * _ps, _gx + _hx * _ps + _ps - 1, _gy + _hy * _ps + _ps - 1, c_white, c_white, c_white, c_white, true);
        ui_text(_gx, _gy + _gh + 14, "X " + string(_hx) + "   Y " + string(_hy), global.TH.text_dim, fa_left, fa_top, global.f_small, 1);
        if (ui_pressed || ui_rpressed)
        {
            undo_mark("sprdraw" + string(current_time));
            spr_drawing = true;
            spr_last_x = _hx;
            spr_last_y = _hy;
            ui_take_click();
        }
        if (spr_drawing)
        {
            // join up from the last cell, so a fast stroke doesn't leave gaps
            var _paint_v = -1;
            if (ui_held) { _paint_v = spr_pen; }
            if (ui_rheld) { _paint_v = 0; }
            if (_paint_v >= 0 && spr_paint_line(_s, spr_last_x, spr_last_y, _hx, _hy, _paint_v))
            {
                spr_dirty[spr_sel] = true;
                proj_dirty = true;
            }
            spr_last_x = _hx;
            spr_last_y = _hy;
        }
    }
    if (!ui_held && !ui_rheld) { spr_drawing = false; }

    // ---------------- properties ----------------
    var _px2 = _x2 - _rw;
    ui_panel(_px2, _y1, _x2, _y2, "Sprite " + string(spr_sel + 1));
    var _fx = _px2 + 20;
    var _fw = _rw - 40;
    var _y = _y1 + 56;
    ui_heading(_fx, _y, "Name");
    set_val(_s, "name", ui_textfield("spr_name", _fx, _y + 18, _fw, 32, _s.name, 20, "Sprite name|A friendly name so you can find this sprite when choosing actors."), "sprname");
    _y += 62;

    // size: 16 x 24 is a hardware sprite; ADAM Pro goes up to 64 x 64 (a BOB)
    var _szh = "Size";
    if (spr_is_big(_s)) { _szh = "Size - a BOB"; }      // with the Lite note below it must fit 280 px
    if (!pro_edition()) { _szh += "   (Lite: up to " + string(LITE_SPR_W) + " x " + string(LITE_SPR_H) + ")"; }
    ui_heading(_fx, _y, _szh);
    var _szw = floor((_fw - 12) / 2);
    var _wvals = [16, 32, 48, 64];
    var _hvals = [16, 24, 32, 48, 64];
    var _wcur = 0;
    for (var wi = 0; wi < 4; wi++)
    {
        if (_wvals[wi] == _s.w) { _wcur = wi; }
    }
    var _hcur = 1;
    for (var hi = 0; hi < 5; hi++)
    {
        if (_hvals[hi] == _s.h) { _hcur = hi; }
    }
    var _wnew = ui_dropdown("spr_w", _fx, _y + 18, _szw, 32, ["16 wide", "32 wide", "48 wide", "64 wide"], _wcur, "Sprite width|A hardware sprite is 16 x 24 pixels. A sprite can be 16 or 32 pixels wide in ADAM Lite, up to 64 in ADAM Pro; one bigger than 16 x 24 is drawn as a BOB with the nearest backdrop colours. Making it smaller cuts off the right-hand side.");
    var _hnew = ui_dropdown("spr_h", _fx + _szw + 12, _y + 18, _szw, 32, ["16 high", "24 high", "32 high", "48 high", "64 high"], _hcur, "Sprite height|A hardware sprite is 16 x 24 pixels. A sprite can be 16, 24 or 32 pixels high in ADAM Lite, up to 64 in ADAM Pro; one bigger than 16 x 24 is drawn as a BOB. Making it smaller cuts off the bottom.");
    if (_wnew != _wcur || _hnew != _hcur)
    {
        // only growing past the limit is refused, so a Pro sprite opened in Lite can still be made smaller
        if ((_wvals[_wnew] > lim_spr_w() && _wvals[_wnew] > _s.w) || (_hvals[_hnew] > lim_spr_h() && _hvals[_hnew] > _s.h))
        {
            lim_toast("Sprites and BOBs are up to " + string(lim_spr_w()) + " x " + string(lim_spr_h()), "up to 64 x 64");
        }
        else if (feature_gate("Bigger sprites"))
        {
            undo_mark("sprsize" + string(current_time));
            spr_resize(_s, _wvals[_wnew], _hvals[_hnew]);
            spr_dirty[spr_sel] = true;
            proj_dirty = true;
        }
    }
    _y += 62;
    ui_heading(_fx, _y, "Pen");
    var _pw3 = floor((_fw - 16) / 3);
    var _phelp = ["Colour 1|Draws with this sprite's first colour.", "Colour 2|Draws with this sprite's second colour.", "Colour 3|Draws with this sprite's third colour."];
    for (var p = 0; p < 3; p++)
    {
        var _bx = _fx + p * (_pw3 + 8);
        var _st = BTN_GHOST;
        if (spr_pen == p + 1) { _st = BTN_ACCENT; }
        if (ui_button("spr_pen_" + string(p), _bx, _y + 18, _pw3, 44, "", _phelp[p], _st)) { spr_pen = p + 1; }
        var _pc = amiga_col(_s.cols[p]);
        ui_rrect(_bx + 8, _y + 24, _bx + 26, _y + 42, 4, _pc, _pc, 1);
        ui_text(_bx + 8, _y + 52, "Colour " + string(p + 1), global.TH.text, fa_left, fa_middle, global.f_small, 1);
    }
    _y += 74;
    ui_heading(_fx, _y, "Colour " + string(spr_pen) + "   " + rgb_hex(_s.cols[spr_pen - 1]));
    _y += 20;
    var _nc = ui_rgb_sliders("spr_rgb", _fx, _y, _fw, _s.cols[spr_pen - 1], "Sprite colour|Mix the colour for this pen. Two actors on the same hardware sprite pair share their colours, so ADAM pairs up actors whose colours match.");
    if (_nc != rgb_machine(_s.cols[spr_pen - 1]))
    {
        undo_mark("sprcol" + string(spr_sel) + "_" + string(spr_pen));
        _s.cols[spr_pen - 1] = _nc;
    }
    _y += 100;

    ui_heading(_fx, _y, "Change the whole sprite");
    _y += 18;
    var _bw = floor((_fw - 16) / 3);
    var _ops = ["Flip H", "Flip V", "Clear", "Left", "Right", "Copy", "Up", "Down", "Paste"];
    var _kinds = ["fliph", "flipv", "clear", "left", "right", "copy", "up", "down", "paste"];
    var _ohelp = ["Flip horizontally|Mirrors the sprite left to right - handy for making a character face the other way.",
                  "Flip vertically|Turns the sprite upside down.",
                  "Clear|Rubs out the whole sprite. You can Undo this.",
                  "Shift left|Moves every pixel one step left.",
                  "Shift right|Moves every pixel one step right.",
                  "Copy|Copies this sprite (pixels and colours) so you can paste it into another slot.",
                  "Shift up|Moves every pixel one step up.",
                  "Shift down|Moves every pixel one step down.",
                  "Paste|Replaces this sprite with the one you copied (the name is kept)."];
    for (var o = 0; o < 9; o++)
    {
        var _ox = _fx + (o mod 3) * (_bw + 8);
        var _oy = _y + (o div 3) * 38;
        var _sty = BTN_NORMAL;
        if (_kinds[o] == "clear") { _sty = BTN_DANGER; }
        if (_kinds[o] == "paste" && spr_clip == "") { _sty = BTN_GHOST; }
        if (ui_button("spr_op_" + _kinds[o], _ox, _oy, _bw, 32, _ops[o], _ohelp[o], _sty))
        {
            if (_kinds[o] == "copy")
            {
                spr_clip = json_stringify(_s);
                toast("Sprite copied", 0);
            }
            else
            {
                if (_kinds[o] == "paste")
                {
                    if (spr_clip != "")
                    {
                        undo_mark("sprpaste" + string(current_time));
                        var _keep = _s.name;
                        var _ns = struct_overlay(sprite_new(_keep), json_parse(spr_clip));
                        _ns.name = _keep;
                        if (!spr_size_ok(_ns.w, _ns.h) || !is_array(_ns.px) || array_length(_ns.px) != _ns.w * _ns.h)
                        {
                            _ns.w = SPR_W;
                            _ns.h = SPR_H;
                            _ns.px = array_create(SPR_W * SPR_H, 0);
                        }
                        proj.sprites[spr_sel] = _ns;
                        spr_dirty[spr_sel] = true;
                    }
                    else { toast("Copy a sprite first", 1); }
                }
                else
                {
                    undo_mark("sprop" + string(current_time));
                    spr_transform(_s, _kinds[o]);
                    spr_dirty[spr_sel] = true;
                }
            }
        }
    }
    _y += 3 * 38 + 8;
    if (_y + 90 < _y2)
    {
        ui_heading(_fx, _y, "Actual size (on colour 0)");
        // 1x, 2x and 3x, as many as fit across and down
        var _box_b = min(_y2 - 14, _y + 18 + max(SPR_H, _s.h) * 3 + 16);
        ui_inset(_fx, _y + 18, _fx + _fw, _box_b, 8);
        ui_rrect(_fx + 6, _y + 24, _fx + _fw - 6, _box_b - 6, 6, pal_col(0), pal_col(0), 1);
        var _ax = _fx + 14;
        for (var sc = 1; sc <= 3; sc++)
        {
            if (_ax + _s.w * sc > _fx + _fw - 10 || _y + 28 + _s.h * sc > _box_b - 8) { break; }
            draw_sprite_amiga(spr_sel, _ax, _y + 28, sc, 1);
            _ax += _s.w * sc + 14;
        }
    }
}
