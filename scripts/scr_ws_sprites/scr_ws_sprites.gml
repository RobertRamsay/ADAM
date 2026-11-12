/// ADAM - Sprites workspace (16 x 24 hardware sprites, 3 colours; ADAM Pro: up to 64 x 64, drawn as BOBs)

/// Pen at pixel (_x, _y) of sprite _s: 0 = see-through, 1..3 = _s.cols[pen - 1].
/// px is one row after another, _s.w pens a row.
function spr_get_px(_s, _x, _y)
{
    return _s.px[_y * _s.w + _x];
}

/// Sets pixel (_x, _y) of sprite _s to pen _v (0 = see-through, 1..3 = the sprite's colours).
/// No range check: the caller keeps _x, _y inside _s.w x _s.h.
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

/// Changes the whole of sprite _s in place. _kind: "fliph" / "flipv" mirror it, "left" / "right" /
/// "up" / "down" shift every pixel one step (the edge it leaves is see-through), "clear" rubs it out.
/// Any other string leaves the picture as it was. Colours and size are kept; the caller marks undo
/// and spr_dirty.
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

/// The onion skin's frames for sprite _k: [before, after] (-1 = none). When an animation
/// (Animate page) uses it, its neighbours in the first one found (wrapping round); else
/// the bank slots either side.
function spr_onion_pair(_k)
{
    for (var i = 0; i < array_length(proj.actors); i++)
    {
        var _an = proj.actors[i].anims;
        for (var j = 0; j < array_length(_an); j++)
        {
            var _fr = _an[j].frames;
            var _n = array_length(_fr);
            if (_n < 2) { continue; }
            for (var f = 0; f < _n; f++)
            {
                if (_fr[f] == _k)
                {
                    return [_fr[(f + _n - 1) mod _n], _fr[(f + 1) mod _n]];
                }
            }
        }
    }
    var _b = -1;
    var _a = -1;
    if (_k > 0) { _b = _k - 1; }
    if (_k < spr_bank_size() - 1) { _a = _k + 1; }
    return [_b, _a];
}

/// Draws sprite _k's pixels ghosted on the canvas at _gx, _gy (cells _ps big, cut to _w x _h),
/// in its own colours tinted towards _tint
function spr_onion_draw(_k, _gx, _gy, _ps, _w, _h, _tint, _alpha)
{
    if (_k < 0 || _k >= array_length(proj.sprites)) { return; }
    var _o = proj.sprites[_k];
    draw_set_alpha(_alpha);
    for (var py = 0; py < min(_h, _o.h); py++)
    {
        for (var px = 0; px < min(_w, _o.w); px++)
        {
            var _v = spr_get_px(_o, px, py);
            if (_v != 0)
            {
                draw_set_colour(merge_colour(amiga_col(_o.cols[_v - 1]), _tint, 0.45));
                draw_rectangle(_gx + px * _ps, _gy + py * _ps, _gx + px * _ps + _ps - 1, _gy + py * _ps + _ps - 1, false);
            }
        }
    }
    draw_set_alpha(1);
}

/// Draws and runs the Sprites page inside (_x1, _y1)-(_x2, _y2), in UI pixels: sprite bank list on the
/// left (_lw wide), drawing canvas in the middle, properties (name, size, pens, colours, whole-sprite
/// buttons, actual size) on the right (_rw wide). Pixels go into proj.sprites[spr_sel].px; spr_dirty
/// tells scr_gfx to rebuild that sprite's cached picture.
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
        // rows scrolled out of the panel are skipped (the scroll scissor would hide them anyway)
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

    // importing a picture or sheet: the import view takes the editor's place
    if (spr_imp_on)
    {
        spr_import_draw(_x1 + _lw + 12, _y1, _x2, _y2, _rw);
        return;
    }

    // ---------------- editor grid ----------------
    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;
    ui_panel(_cx1, _y1, _cx2, _y2, "");
    // _ps = size of one sprite pixel on screen: the biggest whole number that fits (at least 4);
    // 120 leaves room below the canvas for the X / Y read-out and the onion skin dropdown
    var _ps = floor(min((_cx2 - _cx1 - 40) / _s.w, (_y2 - _y1 - 120) / _s.h));
    _ps = max(4, _ps);
    var _gw = _s.w * _ps;
    var _gh = _s.h * _ps;
    var _gx = floor((_cx1 + _cx2 - _gw) / 2);
    var _gy = floor(_y1 + 20 + ((_y2 - _y1 - 90) - _gh) / 2);
    ui_rrect(_gx - 8, _gy - 8, _gx + _gw + 8, _gy + _gh + 8, 10, c_black, c_black, 0.35);
    draw_set_colour(pal_col(0));
    draw_rectangle(_gx, _gy, _gx + _gw - 1, _gy + _gh - 1, false);
    // onion skin: the frame before (tinted red) and after (tinted green), under this one
    var _onp = spr_onion_pair(spr_sel);
    if (spr_onion == 2) { spr_onion_draw(_onp[1], _gx, _gy, _ps, _s.w, _s.h, c_lime, 0.3); }
    if (spr_onion >= 1) { spr_onion_draw(_onp[0], _gx, _gy, _ps, _s.w, _s.h, c_red, 0.4); }
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
    // faint pixel grid, then stronger accent lines every 8 pixels
    draw_set_alpha(0.14);
    if (_ps >= 4)       // (a tall column picture is drawn small: no pixel grid)
    {
        for (var gx = 0; gx <= _s.w; gx++) { draw_line_colour(_gx + gx * _ps, _gy, _gx + gx * _ps, _gy + _gh, c_white, c_white); }
        for (var gy = 0; gy <= _s.h; gy++) { draw_line_colour(_gx, _gy + gy * _ps, _gx + _gw, _gy + gy * _ps, c_white, c_white); }
    }
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
        // a new press starts a stroke: one undo step per stroke (the key is unique, so strokes never merge)
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

    // onion skin: see the frames either side while drawing an animation
    var _ow = 230;
    var _ox1 = _cx2 - 16 - _ow;
    var _oy1 = _y2 - 46;
    ui_text(_ox1 - 10, _oy1 + 15, "Onion skin", global.TH.text_dim, fa_right, fa_middle, global.f_small, 1);
    spr_onion = ui_dropdown("spr_onion", _ox1, _oy1, _ow, 30, ["Off", "Frame before", "Frames before and after"], spr_onion,
        "Onion skin|Shows the frame before (tinted red) and after (tinted green) faintly under the canvas, so you can line up an animation. The frames come from the first animation that uses this sprite (Animate page), or else the sprite slots either side.");
    if (spr_onion > 0)
    {
        var _onl = "";
        if (_onp[0] >= 0) { _onl = "Before: " + proj.sprites[_onp[0]].name; }
        if (spr_onion == 2 && _onp[1] >= 0)
        {
            if (_onl != "") { _onl += "   "; }
            _onl += "After: " + proj.sprites[_onp[1]].name;
        }
        ui_text(_ox1 + _ow, _oy1 - 6, ui_text_fit(_onl, global.f_small, _cx2 - _cx1 - 40), global.TH.text_dim, fa_right, fa_bottom, global.f_small, 1);
    }

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
    var _hvals = [16, 24, 32, 48, 64, 128, 256];
    var _wcur = 0;
    for (var wi = 0; wi < 4; wi++)
    {
        if (_wvals[wi] == _s.w) { _wcur = wi; }
    }
    var _hcur = 1;
    for (var hi = 0; hi < 7; hi++)
    {
        if (_hvals[hi] == _s.h) { _hcur = hi; }
    }
    var _wnew = ui_dropdown("spr_w", _fx, _y + 18, _szw, 32, ["16 wide", "32 wide", "48 wide", "64 wide"], _wcur, "Sprite width|A hardware sprite is 16 x 24 pixels. A sprite can be 16 or 32 pixels wide in ADAM Lite, up to 64 in ADAM Pro; one bigger than 16 x 24 is drawn as a BOB with the nearest backdrop colours. Making it smaller cuts off the right-hand side.");
    var _hnew = ui_dropdown("spr_h", _fx + _szw + 12, _y + 18, _szw, 32, ["16 high", "24 high", "32 high", "48 high", "64 high", "128 high", "256 high"], _hcur, "Sprite height|A hardware sprite is 16 x 24 pixels. A sprite can be 16, 24 or 32 pixels high in ADAM Lite, up to 64 in ADAM Pro; one bigger than 16 x 24 is drawn as a BOB. 128 and 256 (ADAM Pro) are for a column's whole picture (Actors page, 'Reaches the floor'): a pillar, a piston, a tree trunk that rises out of the ground - the screen bottom cuts it off. Making it smaller cuts off the bottom.");
    if (_wnew != _wcur || _hnew != _hcur)
    {
        // only growing past the limit is refused, so a Pro sprite opened in Lite can still be made smaller
        if ((_wvals[_wnew] > lim_spr_w() && _wvals[_wnew] > _s.w) || (_hvals[_hnew] > lim_spr_h() && _hvals[_hnew] > _s.h))
        {
            lim_toast("Sprites and BOBs are up to " + string(lim_spr_w()) + " x " + string(lim_spr_h()), "up to 64 x 64, columns 64 x 256");
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
    if (ui_button("spr_import", _fx, _y, _fw, 32, "Import picture or sheet...", "Import a picture or sprite sheet|Loads a PNG, JPG, GIF, BMP or Amiga IFF (Deluxe Paint pictures and brushes). One picture becomes this sprite; a sheet (a grid of frames) fills this slot and the ones after it. You set the cell size, margins and spacing, and the see-through colour; each sprite gets the 3 colours that suit it best, or - from an indexed picture - keeps the colour numbers you drew it with.", BTN_ACCENT))
    {
        var _f = get_open_filename("Pictures|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.iff;*.ilbm;*.lbm;*.bbm|Amiga IFF|*.iff;*.ilbm;*.lbm;*.bbm", "");
        if (_f != "") { spr_import_open(_f); }
    }
    _y += 44;
    // pens 1..3 = the sprite's three colours (pen 0, see-through, is the right mouse button)
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

    // whole-sprite buttons, 3 x 3: copy / paste use spr_clip (the sprite as JSON); the rest go to spr_transform
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
                        // a clip with a bad size or pixel count becomes a blank 16 x 24 sprite
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

// ---------------------------------------------------------------------------
// Import a picture or a sprite sheet (Sprites page, 'Import picture or sheet...').
// spr_import_load reads the picture once into spr_imp_px (0xAARRGGBB a pixel);
// the import view (spr_import_draw) sets the cell size, margin, spacing, how many
// frames, the see-through colour and the colours (one set of 3 for all, or each its
// own), and spr_import_run fills sprite slots from spr_sel on. Editor only: the disk
// sees ordinary sprites.
// ---------------------------------------------------------------------------

#macro SPR_IMP_MAX 2048          // biggest picture (each side) the import reads

/// Reads picture file _path (PNG / JPG / GIF) into spr_imp_* and opens the import view.
/// Returns true when it could be read.
function spr_import_load(_path)
{
    var _spr = sprite_add(_path, 1, false, false, 0, 0);
    if (_spr == -1)
    {
        toast("Could not read that picture", 1);
        return false;
    }
    var _w = sprite_get_width(_spr);
    var _h = sprite_get_height(_spr);
    if (_w > SPR_IMP_MAX || _h > SPR_IMP_MAX)
    {
        sprite_delete(_spr);
        toast("Pictures up to " + string(SPR_IMP_MAX) + " x " + string(SPR_IMP_MAX) + " pixels", 1);
        return false;
    }
    // drawn 1:1 with blending off, so the alpha comes through as it is in the file
    var _surf = surface_create(_w, _h);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 0);
    gpu_set_blendenable(false);
    gpu_set_texfilter(false);
    draw_sprite(_spr, 0, 0, 0);
    gpu_set_texfilter(true);
    gpu_set_blendenable(true);
    surface_reset_target();
    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _surf, 0);
    surface_free(_surf);
    var _ord = surface_byte_order();
    var _n = _w * _h;
    var _any_clear = false;
    spr_imp_px = array_create(_n, 0);
    for (var i = 0; i < _n; i++)
    {
        var _o = i * 4;
        var _a = buffer_peek(_buf, _o + 3, buffer_u8);
        if (_a < 128) { _any_clear = true; }
        spr_imp_px[i] = (_a << 24) | (buffer_peek(_buf, _o + _ord[0], buffer_u8) << 16) | (buffer_peek(_buf, _o + _ord[1], buffer_u8) << 8) | buffer_peek(_buf, _o + _ord[2], buffer_u8);
    }
    buffer_delete(_buf);
    if (sprite_exists(spr_imp_spr)) { sprite_delete(spr_imp_spr); }
    spr_imp_spr = _spr;                 // kept for the preview
    spr_imp_w = _w;
    spr_imp_h = _h;
    spr_imp_name = filename_change_ext(filename_name(_path), "");
    // a first guess at the cells: the whole picture if it fits one sprite, else square
    // cells as tall as a strip, else 16 x 24
    if (_w <= lim_spr_w() && _h <= lim_spr_h())
    {
        spr_imp_cw = _w;
        spr_imp_ch = _h;
    }
    else if (_h <= 64 && _w mod _h == 0)
    {
        spr_imp_cw = _h;
        spr_imp_ch = _h;
    }
    else if (_w <= 64 && _h mod _w == 0)
    {
        spr_imp_cw = _w;
        spr_imp_ch = _w;
    }
    else
    {
        spr_imp_cw = SPR_W;
        spr_imp_ch = SPR_H;
    }
    spr_imp_mx = 0;
    spr_imp_my = 0;
    spr_imp_gx = 0;
    spr_imp_gy = 0;
    spr_imp_n = 0;
    spr_imp_ckey = "";
    spr_imp_key = 1;                    // no transparency in the file: the top-left colour is see-through
    if (_any_clear) { spr_imp_key = 0; }
    spr_imp_on = true;
    return true;
}

/// Opens picture file _path in the import view. A true-colour PNG or a JPG straight away;
/// an indexed picture (IFF picture or brush, PNG with a palette, GIF, BMP) through a PNG
/// copy in the temp folder (its mask or transparent colour see-through), keeping its
/// colour numbers in spr_imp_ix for 'The picture's own colour numbers'
function spr_import_open(_path)
{
    var _iff = indexed_read(_path);
    if (_iff.err != "")
    {
        toast(_iff.err, 1);
        return false;
    }
    if (!_iff.indexed)
    {
        if (!spr_import_load(_path)) { return false; }
        spr_imp_ix = [];
        spr_imp_ipal = [];
        if (spr_imp_cols == 2) { spr_imp_cols = 0; }
        return true;
    }
    var _tmp = temp_directory + "adam_iff_import.png";
    if (!iff_to_png(_iff, _tmp))
    {
        toast("Could not convert that picture", 1);
        return false;
    }
    if (!spr_import_load(_tmp)) { return false; }
    spr_imp_name = filename_change_ext(filename_name(_path), "");
    spr_imp_ix = _iff.idx;
    spr_imp_ipal = _iff.pal;
    spr_imp_cols = 2;
    return true;
}

/// Closes the import view and lets go of the picture
function spr_import_close()
{
    spr_imp_on = false;
    if (sprite_exists(spr_imp_spr)) { sprite_delete(spr_imp_spr); }
    spr_imp_spr = -1;
    spr_imp_px = [];
    spr_imp_ix = [];
    spr_imp_ipal = [];
    spr_imp_cells = [];
    spr_imp_ckey = "";
}

/// Is picture pixel _c see-through? Pixels mostly transparent in the file always are;
/// spr_imp_key 1: so is the top-left pixel's colour.
function spr_import_clear(_c)
{
    if (((_c >> 24) & 255) < 128) { return true; }
    if (spr_imp_key == 1 && array_length(spr_imp_px) > 0) { return (_c & 0xffffff) == (spr_imp_px[0] & 0xffffff); }
    return false;
}

/// Does the cell at _cx, _cy have a pixel that is not see-through?
function spr_import_cell_used(_cx, _cy)
{
    for (var _iy = 0; _iy < spr_imp_ch; _iy++)
    {
        var _row = (_cy + _iy) * spr_imp_w + _cx;
        for (var _ix = 0; _ix < spr_imp_cw; _ix++)
        {
            if (!spr_import_clear(spr_imp_px[_row + _ix])) { return true; }
        }
    }
    return false;
}

/// The cells to import, row by row: [[x, y], ...] tops-left in the picture, at most _max,
/// empty ones left out when spr_imp_skip. With _all, every cell (for the preview), each
/// as [x, y, used].
function spr_import_cells(_max, _all)
{
    var _out = [];
    var _cw = max(1, spr_imp_cw);
    var _ch = max(1, spr_imp_ch);
    var _cy = spr_imp_my;
    while (_cy + _ch <= spr_imp_h && array_length(_out) < _max)
    {
        var _cx = spr_imp_mx;
        while (_cx + _cw <= spr_imp_w && array_length(_out) < _max)
        {
            var _used = true;
            if (spr_imp_skip) { _used = spr_import_cell_used(_cx, _cy); }
            if (_all) { array_push(_out, [_cx, _cy, _used]); }
            else if (_used) { array_push(_out, [_cx, _cy]); }
            _cx += _cw + spr_imp_gx;
        }
        _cy += _ch + spr_imp_gy;
    }
    return _out;
}

/// The sprite size a cell of _cw x _ch goes into: the smallest allowed size that holds
/// it (16-64 wide in steps of 16; 16, 24, 32, 48, 64, 128, 256 high), within this
/// edition's limits (a bigger cell is cut off right and bottom). -> [w, h]
function spr_import_size(_cw, _ch)
{
    var _w = 16;
    while (_w < _cw && _w < 64) { _w += 16; }
    _w = min(_w, lim_spr_w());
    var _hs = [16, 24, 32, 48, 64, 128, 256];
    var _h = 256;
    for (var i = 0; i < array_length(_hs); i++)
    {
        if (_hs[i] >= _ch)
        {
            _h = _hs[i];
            break;
        }
    }
    _h = min(_h, lim_spr_h());
    return [_w, _h];
}

/// The 3 colours (in the machine's colours) for the pixels of cells _cells (each [x, y]),
/// picked by median cut; fewer colours in the picture leave the rest black
function spr_import_colours(_cells, _sw, _sh)
{
    var _cnt = array_create(4096, 0);
    var _sr = array_create(4096, 0);
    var _sg = array_create(4096, 0);
    var _sb = array_create(4096, 0);
    for (var k = 0; k < array_length(_cells); k++)
    {
        var _cx = _cells[k][0];
        var _cy = _cells[k][1];
        for (var _iy = 0; _iy < min(spr_imp_ch, _sh); _iy++)
        {
            for (var _ix = 0; _ix < min(spr_imp_cw, _sw); _ix++)
            {
                var _c = spr_imp_px[(_cy + _iy) * spr_imp_w + _cx + _ix];
                if (spr_import_clear(_c)) { continue; }
                var _r = (_c >> 16) & 255;
                var _g = (_c >> 8) & 255;
                var _b = _c & 255;
                var _bin = ((_r >> 4) << 8) | ((_g >> 4) << 4) | (_b >> 4);
                _cnt[_bin] += 1;
                _sr[_bin] += _r;
                _sg[_bin] += _g;
                _sb[_bin] += _b;
            }
        }
    }
    var _used = [];
    for (var q = 0; q < 4096; q++)
    {
        if (_cnt[q] > 0) { array_push(_used, q); }
    }
    var _out = [0x000000, 0x000000, 0x000000];
    if (array_length(_used) == 0) { return _out; }
    var _cols = median_cut(_used, _cnt, _sr, _sg, _sb, 3);
    for (var c = 0; c < min(3, array_length(_cols)); c++) { _out[c] = rgb_machine(_cols[c]); }
    return _out;
}

/// Pens for an indexed picture's own colour numbers in cells _cells (each [x, y]):
/// { ok, map (colour number -> pen 1..3), cols (the 3 in the machine's colours) }.
/// Numbers in one group of 4 after its first (like the Amiga's sprite colours 17-19,
/// 16 see-through) keep pen = number mod 4; else up to 3 numbers go to pens 1-3 in order.
/// ok is false when the cells use more than 3.
function spr_import_ixmap(_cells, _sw, _sh)
{
    var _res = { ok : false, map : array_create(256, 1), cols : [0x000000, 0x000000, 0x000000] };
    var _use = array_create(256, false);
    var _list = [];
    for (var k = 0; k < array_length(_cells); k++)
    {
        var _cx = _cells[k][0];
        var _cy = _cells[k][1];
        for (var _iy = 0; _iy < min(spr_imp_ch, _sh); _iy++)
        {
            for (var _ix = 0; _ix < min(spr_imp_cw, _sw); _ix++)
            {
                var _o = (_cy + _iy) * spr_imp_w + _cx + _ix;
                if (spr_import_clear(spr_imp_px[_o])) { continue; }
                var _ci = spr_imp_ix[_o] & 255;
                if (!_use[_ci])
                {
                    _use[_ci] = true;
                    array_push(_list, _ci);
                    if (array_length(_list) > 3) { return _res; }
                }
            }
        }
    }
    array_sort(_list, true);
    var _nu = array_length(_list);
    var _np = array_length(spr_imp_ipal);
    var _same = (_nu > 0);
    for (var i = 0; i < _nu; i++)
    {
        if ((_list[i] & 3) == 0 || (_list[i] >> 2) != (_list[0] >> 2)) { _same = false; }
    }
    if (_same)
    {
        var _g = (_list[0] >> 2) << 2;
        for (var p = 1; p <= 3; p++)
        {
            _res.map[_g + p] = p;
            if (_g + p < _np) { _res.cols[p - 1] = rgb_machine(spr_imp_ipal[_g + p]); }
        }
    }
    else
    {
        for (var j = 0; j < _nu; j++)
        {
            _res.map[_list[j]] = j + 1;
            if (_list[j] < _np) { _res.cols[j] = rgb_machine(spr_imp_ipal[_list[j]]); }
        }
    }
    _res.ok = true;
    return _res;
}

/// Imports the cells into sprite slots from spr_sel on (as many as fit in the bank, or
/// spr_imp_n), each named after the file, then closes the import view
function spr_import_run()
{
    var _max = spr_bank_size() - spr_sel;
    if (spr_imp_n > 0) { _max = min(_max, spr_imp_n); }
    var _cells = spr_import_cells(_max, false);
    var _nc = array_length(_cells);
    if (_nc == 0)
    {
        toast("Nothing to import - check the cell size and margin", 1);
        return;
    }
    var _sz = spr_import_size(spr_imp_cw, spr_imp_ch);
    var _sw = _sz[0];
    var _sh = _sz[1];
    undo_mark("sprimport" + string(current_time));
    var _shared = [0, 0, 0];
    if (spr_imp_cols == 0) { _shared = spr_import_colours(_cells, _sw, _sh); }
    var _byix = (spr_imp_cols == 2 && array_length(spr_imp_ix) == spr_imp_w * spr_imp_h);
    var _mall = undefined;
    if (_byix) { _mall = spr_import_ixmap(_cells, _sw, _sh); }
    var _fall = 0;                      // sprites with more than 3 colour numbers (their best 3 picked)
    for (var k = 0; k < _nc; k++)
    {
        var _cols = _shared;
        if (spr_imp_cols == 1) { _cols = spr_import_colours([_cells[k]], _sw, _sh); }
        var _m = undefined;
        if (_byix)
        {
            _m = _mall;
            if (!_m.ok) { _m = spr_import_ixmap([_cells[k]], _sw, _sh); }
            if (_m.ok) { _cols = _m.cols; }
            else
            {
                _cols = spr_import_colours([_cells[k]], _sw, _sh);
                _m = undefined;
                _fall += 1;
            }
        }
        var _nm = spr_imp_name;
        if (_nc > 1) { _nm = spr_imp_name + " " + string(k + 1); }
        var _s = sprite_new(string_copy(_nm, 1, 20));
        _s.w = _sw;
        _s.h = _sh;
        _s.px = array_create(_sw * _sh, 0);
        _s.cols = [_cols[0], _cols[1], _cols[2]];
        var _cx = _cells[k][0];
        var _cy = _cells[k][1];
        var _near = ds_map_create();        // colour -> pen, so each colour is matched once
        for (var _iy = 0; _iy < min(spr_imp_ch, _sh); _iy++)
        {
            for (var _ix = 0; _ix < min(spr_imp_cw, _sw); _ix++)
            {
                var _c = spr_imp_px[(_cy + _iy) * spr_imp_w + _cx + _ix];
                if (spr_import_clear(_c)) { continue; }
                if (!is_undefined(_m))
                {
                    _s.px[_iy * _sw + _ix] = _m.map[spr_imp_ix[(_cy + _iy) * spr_imp_w + _cx + _ix] & 255];
                    continue;
                }
                var _rgb = _c & 0xffffff;
                var _pen = _near[? _rgb];
                if (is_undefined(_pen))
                {
                    _pen = 1;
                    var _bd = rgb_dist(_rgb, _cols[0]);
                    for (var p = 1; p < 3; p++)
                    {
                        var _d = rgb_dist(_rgb, _cols[p]);
                        if (_d < _bd)
                        {
                            _bd = _d;
                            _pen = p + 1;
                        }
                    }
                    _near[? _rgb] = _pen;
                }
                _s.px[_iy * _sw + _ix] = _pen;
            }
        }
        ds_map_destroy(_near);
        proj.sprites[spr_sel + k] = _s;
        spr_dirty[spr_sel + k] = true;
    }
    proj_dirty = true;
    var _what = "1 sprite";
    if (_nc > 1) { _what = string(_nc) + " sprites"; }
    var _note = "";
    if (_fall > 0) { _note = " - " + string(_fall) + " used more than 3 colour numbers, so the best 3 were picked"; }
    toast("Imported " + _what + " (" + string(_sw) + " x " + string(_sh) + ")" + _note, 0);
    spr_import_close();
}

/// The import view, in place of the editor and its panel (_x1.._x2, _y1.._y2; _rw = the
/// width of the settings panel on the right)
function spr_import_draw(_x1, _y1, _x2, _y2, _rw)
{
    var _px2 = _x2 - _rw;
    var _cx2 = _px2 - 12;
    // ---- the picture, its cells outlined: in use (numbered), empty (dim), cut off (red)
    ui_panel(_x1, _y1, _cx2, _y2, "Import: " + spr_imp_name + "  (" + string(spr_imp_w) + " x " + string(spr_imp_h) + ")");
    var _aw = _cx2 - _x1 - 40;
    var _ah = _y2 - _y1 - 90;
    var _k = min(_aw / spr_imp_w, _ah / spr_imp_h);
    if (_k >= 1) { _k = floor(_k); }
    var _gx = _x1 + 20 + (_aw - spr_imp_w * _k) / 2;
    var _gy = _y1 + 60;
    ui_rrect(_gx - 4, _gy - 4, _gx + spr_imp_w * _k + 4, _gy + spr_imp_h * _k + 4, 4, pal_col(0), pal_col(0), 1);
    if (sprite_exists(spr_imp_spr))
    {
        gpu_set_texfilter(false);
        draw_sprite_ext(spr_imp_spr, 0, _gx, _gy, _k, _k, 0, c_white, 1);
        gpu_set_texfilter(true);
    }
    var _max = spr_bank_size() - spr_sel;
    if (spr_imp_n > 0) { _max = min(_max, spr_imp_n); }
    // the cells (and which are empty) only change with the settings: worked out again then
    var _ck = string(spr_imp_cw) + "," + string(spr_imp_ch) + "," + string(spr_imp_mx) + "," + string(spr_imp_my) + "," + string(spr_imp_gx) + "," + string(spr_imp_gy) + "," + string(spr_imp_key) + "," + string(spr_imp_skip);
    if (_ck != spr_imp_ckey)
    {
        spr_imp_cells = spr_import_cells(4096, true);
        spr_imp_ckey = _ck;
    }
    var _all = spr_imp_cells;
    var _num = 0;
    var _sz = spr_import_size(spr_imp_cw, spr_imp_ch);
    for (var c = 0; c < array_length(_all); c++)
    {
        var _cl = _all[c];
        var _rx = _gx + _cl[0] * _k;
        var _ry = _gy + _cl[1] * _k;
        var _col = global.TH.text_dim;
        var _a = 0.5;
        if (_cl[2] && _num < _max)
        {
            _col = global.TH.accent;
            _a = 1;
            _num += 1;
            if (spr_imp_cw * _k >= 14) { ui_text(_rx + 2, _ry + 1, string(_num), c_white, fa_left, fa_top, global.f_small, 1); }
        }
        draw_set_alpha(_a);
        draw_rectangle_colour(_rx, _ry, _rx + spr_imp_cw * _k - 1, _ry + spr_imp_ch * _k - 1, _col, _col, _col, _col, true);
        draw_set_alpha(1);
    }
    var _info = string(_num) + " sprite";
    if (_num != 1) { _info += "s"; }
    _info += " of " + string(_sz[0]) + " x " + string(_sz[1]);
    if (_num > 0) { _info += "  ->  slots " + string(spr_sel + 1) + " to " + string(spr_sel + _num) + " (pick the first in the bank)"; }
    var _iy = _y2 - 26;
    ui_text(_x1 + 20, _iy, ui_text_fit(_info, global.f_body, _cx2 - _x1 - 40), global.TH.text, fa_left, fa_middle, global.f_body, 1);
    if (spr_imp_cw > _sz[0] || spr_imp_ch > _sz[1])
    {
        ui_text(_x1 + 20, _iy - 22, ui_text_fit("Cells bigger than " + string(lim_spr_w()) + " x " + string(lim_spr_h()) + " are cut off right and bottom.", global.f_small, _cx2 - _x1 - 40), global.TH.warn, fa_left, fa_middle, global.f_small, 1);
    }

    // ---- settings
    ui_panel(_px2, _y1, _x2, _y2, "Sprite sheet");
    var _fx = _px2 + 20;
    var _fw = _rw - 40;
    var _half = floor((_fw - 12) / 2);
    var _y = _y1 + 56;
    ui_heading(_fx, _y, "Cell size (width, height)");
    spr_imp_cw = ui_stepper("spimp_cw", _fx, _y + 18, _half, spr_imp_cw, 1, min(256, spr_imp_w), "Cell width|How wide each picture in the sheet is, in pixels. A cell becomes the smallest sprite that holds it (16, 32, 48 or 64 wide). Hold Shift for steps of 10.");
    spr_imp_ch = ui_stepper("spimp_ch", _fx + _half + 12, _y + 18, _half, spr_imp_ch, 1, min(256, spr_imp_h), "Cell height|How tall each picture in the sheet is. A sprite is 16, 24, 32, 48 or 64 high (ADAM Pro: 128 or 256 for a column's whole picture). Hold Shift for steps of 10.");
    _y += 62;
    ui_heading(_fx, _y, "Margin (left, top)");
    spr_imp_mx = ui_stepper("spimp_mx", _fx, _y + 18, _half, spr_imp_mx, 0, spr_imp_w - 1, "Left margin|Pixels to skip at the left of the sheet before the first column of cells.");
    spr_imp_my = ui_stepper("spimp_my", _fx + _half + 12, _y + 18, _half, spr_imp_my, 0, spr_imp_h - 1, "Top margin|Pixels to skip at the top of the sheet before the first row of cells.");
    _y += 62;
    ui_heading(_fx, _y, "Spacing between cells");
    spr_imp_gx = ui_stepper("spimp_gx", _fx, _y + 18, _half, spr_imp_gx, 0, 64, "Spacing across|Pixels between one cell and the next across (a grid line or a gap in the sheet).");
    spr_imp_gy = ui_stepper("spimp_gy", _fx + _half + 12, _y + 18, _half, spr_imp_gy, 0, 64, "Spacing down|Pixels between one row of cells and the next.");
    _y += 62;
    ui_heading(_fx, _y, "How many (0 = all)");
    spr_imp_n = ui_stepper("spimp_n", _fx, _y + 18, _half, spr_imp_n, 0, spr_bank_size(), "How many|Import only the first few cells (row by row), or 0 for all of them that fit in the sprite bank from the slot picked.");
    _y += 62;
    ui_heading(_fx, _y, "See-through");
    spr_imp_key = ui_dropdown("spimp_key", _fx, _y + 18, _fw, 32, ["The picture's own", "Also the top-left colour"], spr_imp_key, "See-through|Pixels that are transparent in the file are always see-through. 'Also the top-left colour': every pixel of the colour in the sheet's top-left corner is too - for sheets on a plain background (magenta, black...).");
    _y += 62;
    ui_heading(_fx, _y, "Colours");
    var _copts = ["One set of 3 for all", "Each sprite its own 3"];
    if (array_length(spr_imp_ix) > 0) { array_push(_copts, "The picture's own colour numbers"); }
    spr_imp_cols = ui_dropdown("spimp_cols", _fx, _y + 18, _fw, 32, _copts, min(spr_imp_cols, array_length(_copts) - 1), "Colours|A sprite has 3 colours plus see-through. 'One set for all' picks the 3 that suit the whole sheet - the frames of one animation, and the Amiga pairs actors whose colours match on its 8 hardware sprites. 'Each its own' suits a sheet of different things. 'The picture's own colour numbers' (an indexed picture: IFF, PNG with a palette, GIF, BMP) keeps the pens you drew with: colours 17-19 (or 1-3, 21-23...) become pens 1-3 as on the Amiga, else the 3 numbers used go to pens 1-3 in order, in the picture's own colours. BOBs are drawn in the nearest backdrop colours.");
    _y += 62;
    spr_imp_skip = ui_toggle("spimp_skip", _fx, _y, "Leave out empty cells", spr_imp_skip, "Leave out empty cells|Cells with nothing but see-through pixels (the gaps at the end of a sheet) are not imported.");
    _y += 40;
    var _bw = floor((_fw - 12) / 2);
    if (ui_button("spimp_go", _fx, _y, _bw, 36, "Import", "Import|Puts the outlined cells into the sprite bank, from the slot picked on the left on, replacing what is there (Undo brings it back).", BTN_ACCENT))
    {
        spr_import_run();
    }
    if (ui_button("spimp_cancel", _fx + _bw + 12, _y, _bw, 36, "Cancel", "Cancel|Closes the import without changing anything.", BTN_GHOST))
    {
        spr_import_close();
    }
}
