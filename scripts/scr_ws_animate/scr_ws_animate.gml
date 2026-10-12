/// ADAM - Animate workspace (ADAM Lite and Pro): Idle, Walk, Jump and Fall animations
/// of up to 8 frames for each actor, picked from the sprite bank.
///
/// The engine picks the animation by itself: Idle while the actor stands
/// still, Walk while it moves, Jump / Fall while a platform player, hopper or
/// faller is in the air. Empty animations borrow from the others (anim_plan).

function anim_names()
{
    return ["Idle", "Walk", "Jump", "Fall"];
}

function anim_mode_names()
{
    return ["Loop", "Once (stop on the last frame)", "Ping-pong"];
}

/// True when the Animate page may change things (every edition; kept as the
/// one place to gate it with pro_gate("Animations") again)
function anim_can_edit()
{
    return true;
}

/// Marks an undo step for the selected actor, starting from its two-frame
/// animation the first time it is changed here
function anim_begin_edit(_ac, _tag)
{
    undo_mark(_tag);
    anims_seed_from_legacy(_ac);
    anim_t0 = current_time;
}

/// Draws sprite design _i, turned round when _flip, in colours _cols
function draw_sprite_amiga_flip(_i, _x, _y, _scale, _flip, _cols, _alpha)
{
    if (_i < 0 || _i >= SPR_COUNT) { return; }
    if (!_flip)
    {
        draw_sprite_amiga_cols(_i, _x, _y, _scale, _cols, _alpha);
        return;
    }
    spr_cache_update(_i);
    var _w = proj.sprites[_i].w;
    gpu_set_texfilter(false);
    for (var c = 0; c < 3; c++)
    {
        draw_surface_ext(spr_surf[_i][c], _x + _w * _scale, _y, -_scale, _scale, 0, amiga_col(_cols[c]), _alpha);
    }
    gpu_set_texfilter(true);
}

function ws_animate_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 240;
    var _rw = 330;
    var _na = array_length(proj.actors);
    sel_actor = clamp(sel_actor, 0, max(0, _na - 1));
    var _alloc = actors_alloc_channels();

    // ---------------- cast ----------------
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "Actors");
    var _ly = _y1 + 54;
    var _rowh = 58;
    var _lcontent = _na * _rowh + 8;
    var _loff = ui_scroll_begin("anim_list", _x1 + 6, _y1 + 50, _x1 + _lw - 6, _y2 - 8, _lcontent);
    for (var i = 0; i < _na; i++)
    {
        var _ac = proj.actors[i];
        var _ry = _ly + i * _rowh - _loff;
        if (_ry < _y1 - _rowh || _ry > _y2) { continue; }
        var _id = "anim_act_" + string(i);
        var _hot = ui_register(_id, _x1 + 10, _ry, _x1 + _lw - 10, _ry + _rowh - 6, _ac.name + "|Click to animate this actor.");
        var _tgt = 0;
        if (_hot) { _tgt = 1; }
        var _a = ui_anim_to(_id, _tgt);
        if (sel_actor == i)
        {
            ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + _rowh - 6, 10, global.TH.accent, global.TH.accent_dark, 0.9);
        }
        else
        {
            ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + _rowh - 6, 10, global.TH.btn_hot_top, global.TH.btn_hot_bot, 0.25 + _a * 0.75);
        }
        ui_rrect(_x1 + 16, _ry + 5, _x1 + 50, _ry + _rowh - 11, 6, pal_col(0), pal_col(0), 1);
        var _psi = actor_preview_sprite(_ac);
        var _ts = proj.sprites[clamp(_psi, 0, SPR_COUNT - 1)];
        var _tsc = min(1, SPR_H / max(_ts.w, _ts.h));
        draw_sprite_amiga_cols(_psi, _x1 + 33 - _ts.w * _tsc / 2, _ry + 7 + (SPR_H - _ts.h * _tsc) / 2, _tsc, actor_cols_from(_alloc, i), 1);
        ui_text(_x1 + 60, _ry + 16, ui_text_fit(_ac.name, global.f_bold, _lw - 84), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        var _nfr = 0;
        for (var ae = 0; ae < ANIM_COUNT; ae++) { _nfr += array_length(_ac.anims[ae].frames); }
        var _sub = "Not animated yet";
        if (_nfr > 0) { _sub = string(_nfr) + " frames"; }
        else if (_ac.anim_sprite >= 0 && _ac.role != 7) { _sub = "Two-frame animation"; }
        ui_text(_x1 + 60, _ry + 35, ui_text_fit(_sub, global.f_small, _lw - 84), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            if (sel_actor != i)
            {
                sel_actor = i;
                anim_slot = 0;
                anim_t0 = current_time;
            }
            ui_take_click();
        }
    }
    ui_scroll_end("anim_list", _x1 + 6, _y1 + 50, _x1 + _lw - 6, _y2 - 8, _lcontent);

    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;
    if (_na == 0)
    {
        ui_panel(_cx1, _y1, _x2, _y2, "");
        ui_text((_cx1 + _x2) / 2, (_y1 + _y2) / 2, "Add actors on the Actors page first, then animate them here.", global.TH.text_dim, fa_center, fa_middle, global.f_body, 1);
        return;
    }
    var _s = proj.actors[sel_actor];
    var _cols = actor_cols_from(_alloc, sel_actor);
    anim_sel = clamp(anim_sel, 0, ANIM_COUNT - 1);
    var _an = _s.anims[anim_sel];
    var _nf = array_length(_an.frames);
    anim_slot = clamp(anim_slot, 0, min(_nf, ANIM_FRAMES - 1));
    var _names = anim_names();

    // ---------------- centre: tabs, preview, frame strip ----------------
    var _ptitle = "Animate " + _s.name;
    ui_panel(_cx1, _y1, _cx2, _y2, _ptitle);
    var _tw = floor((_cx2 - _cx1 - 40 - 3 * 8) / 4);
    var _thelp = [
        "Idle|Plays while the actor stands still.",
        "Walk|Plays while the actor moves.",
        "Jump|Plays while a platform player, hopper or faller goes up through the air. Empty: it uses Walk.",
        "Fall|Plays while a platform player, hopper or faller comes down. Empty: it uses Jump (or Walk)."
    ];
    for (var t = 0; t < ANIM_COUNT; t++)
    {
        var _lab = _names[t];
        var _tn = array_length(_s.anims[t].frames);
        if (_tn > 0) { _lab += "  " + string(_tn); }
        if (ui_tab("anim_tab_" + string(t), _cx1 + 20 + t * (_tw + 8), _y1 + 50, _tw, 32, _lab, anim_sel == t, _thelp[t]))
        {
            if (anim_sel != t)
            {
                anim_sel = t;
                anim_slot = 0;
                anim_t0 = current_time;
            }
        }
    }
    _an = _s.anims[anim_sel];
    _nf = array_length(_an.frames);
    anim_slot = clamp(anim_slot, 0, min(_nf, ANIM_FRAMES - 1));

    // preview: what the Amiga will play for this animation (empty ones borrow from the others)
    var _py1 = _y1 + 94;
    var _strip_h = 92;
    var _ctrl_h = 132;
    var _py2 = _y2 - 20 - _strip_h - _ctrl_h;
    ui_inset(_cx1 + 20, _py1, _cx2 - 20, _py2, 10);
    ui_rrect(_cx1 + 26, _py1 + 6, _cx2 - 26, _py2 - 6, 8, pal_col(0), pal_col(0), 1);
    ui_register("anim_preview", _cx1 + 20, _py1, _cx2 - 20, _py2, "Preview|Plays the animation at the real Amiga speed (50 frames a second), in the colours the actor really gets.");
    var _plan = anim_plan(_s);
    var _ticks = (current_time - anim_t0) div 20;
    var _note = "";
    if (is_undefined(_plan))
    {
        _note = "One frame - pick sprites from the bank on the right to animate it";
        var _bs = proj.sprites[clamp(_s.sprite, 0, SPR_COUNT - 1)];
        var _bsc = max(1, floor(min((_cx2 - _cx1 - 80) / _bs.w, (_py2 - _py1 - 50) / _bs.h)));
        draw_sprite_amiga_flip(_s.sprite, floor((_cx1 + _cx2 - _bs.w * _bsc) / 2), floor((_py1 + _py2 - 20 - _bs.h * _bsc) / 2), _bsc, anim_face_left && _s.anim_flip, _cols, 1);
    }
    else
    {
        var _pe = _plan[anim_sel];
        var _fi = anim_frame_at(_pe, _ticks);
        var _psi2 = clamp(_pe.frames[_fi], 0, SPR_COUNT - 1);
        var _ps = proj.sprites[_psi2];
        var _bw = 16;
        var _bh = 16;
        for (var q = 0; q < array_length(_pe.frames); q++)
        {
            var _qs = proj.sprites[clamp(_pe.frames[q], 0, SPR_COUNT - 1)];
            _bw = max(_bw, _qs.w);
            _bh = max(_bh, _qs.h);
        }
        var _sc = max(1, floor(min((_cx2 - _cx1 - 80) / _bw, (_py2 - _py1 - 50) / _bh)));
        var _dx = floor((_cx1 + _cx2 - _bw * _sc) / 2);
        var _dy = floor((_py1 + _py2 - 20 - _bh * _sc) / 2);
        draw_sprite_amiga_flip(_psi2, _dx, _dy, _sc, anim_face_left && _s.anim_flip, _cols, 1);
        if (_nf == 0)
        {
            var _from = 0;
            for (var u = 0; u < ANIM_COUNT; u++)
            {
                if (u != anim_sel && _plan[u] == _pe && array_length(_s.anims[u].frames) > 0) { _from = u; }
            }
            _note = "Empty - plays " + _names[_from];
            if (array_length(_s.anims[_from].frames) == 0) { _note = "Empty - shows the actor's sprite"; }
            if (!anims_used(_s)) { _note = "Plays the two-frame animation from the Actors page - add frames here to replace it"; }
        }
        else
        {
            _note = "Frame " + string(_fi + 1) + " of " + string(array_length(_pe.frames)) + "   -   sprite " + string(_psi2 + 1) + ": " + _ps.name;
        }
    }
    ui_text(_cx1 + 36, _py2 - 22, ui_text_fit(_note, global.f_small, _cx2 - _cx1 - 220), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    if (_s.anim_flip)
    {
        anim_face_left = ui_toggle("anim_faceleft", _cx2 - 170, _py2 - 34, "Facing left", anim_face_left, "Facing left|Shows the frames turned round, as the actor looks while it moves left.");
    }
    if (_s.role < 6 && anim_sel >= 2)
    {
        ui_text((_cx1 + _cx2) / 2, _py1 + 22, "Only platform players, hoppers and fallers jump and fall", global.TH.warn, fa_center, fa_middle, global.f_small, 1);
    }

    // frame strip: up to 8 frames; the slot after the last one adds a frame
    var _sy = _py2 + 14;
    ui_heading(_cx1 + 20, _sy, _names[anim_sel] + " frames  (" + string(_nf) + " / " + string(ANIM_FRAMES) + ")  -  click a frame, then a sprite in the bank");
    _sy += 20;
    var _cell = min(64, floor((_cx2 - _cx1 - 40 - 7 * 8) / ANIM_FRAMES));
    for (var k = 0; k < ANIM_FRAMES; k++)
    {
        var _kx = _cx1 + 20 + k * (_cell + 8);
        var _kid = "anim_slot_" + string(k);
        if (k < _nf)
        {
            var _khot = ui_register(_kid, _kx, _sy, _kx + _cell, _sy + _cell, "Frame " + string(k + 1) + "|Click to select it, then click a sprite in the bank to change it. Remove, move or clear it with the buttons below.");
            ui_rrect(_kx, _sy, _kx + _cell, _sy + _cell, 8, pal_col(0), pal_col(0), 1);
            var _ks = proj.sprites[clamp(_an.frames[k], 0, SPR_COUNT - 1)];
            var _ksc = (_cell - 8) / max(_ks.w, _ks.h);
            draw_sprite_amiga_cols(_an.frames[k], _kx + (_cell - _ks.w * _ksc) / 2, _sy + (_cell - _ks.h * _ksc) / 2, _ksc, _cols, 1);
            ui_text(_kx + 5, _sy + 4, string(k + 1), global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
            if (anim_slot == k) { ui_rrect_line(_kx - 2, _sy - 2, _kx + _cell + 2, _sy + _cell + 2, 9, global.TH.accent, 1, 2); }
            else { ui_rrect_line(_kx, _sy, _kx + _cell, _sy + _cell, 8, global.TH.panel_edge, 0.8, 1); }
            if (_khot && ui_pressed)
            {
                anim_slot = k;
                ui_take_click();
            }
        }
        else if (k == _nf)
        {
            var _ahot = ui_register(_kid, _kx, _sy, _kx + _cell, _sy + _cell, "Add a frame|Select this slot, then click sprites in the bank: each one is added to the end of the animation.");
            var _aa = 0.35;
            if (_ahot) { _aa = 0.7; }
            ui_rrect(_kx, _sy, _kx + _cell, _sy + _cell, 8, global.TH.btn_hot_top, global.TH.btn_hot_bot, _aa);
            ui_text(_kx + _cell / 2, _sy + _cell / 2, "+", global.TH.text, fa_center, fa_middle, global.f_title, 1);
            if (anim_slot == k) { ui_rrect_line(_kx - 2, _sy - 2, _kx + _cell + 2, _sy + _cell + 2, 9, global.TH.accent, 1, 2); }
            if (_ahot && ui_pressed)
            {
                anim_slot = k;
                ui_take_click();
            }
        }
        else
        {
            ui_rrect_line(_kx, _sy, _kx + _cell, _sy + _cell, 8, global.TH.panel_edge, 0.35, 1);
        }
    }

    // controls
    var _ky = _sy + _cell + 18;
    var _half = floor((_cx2 - _cx1 - 40 - 12) / 2);
    ui_heading(_cx1 + 20, _ky, "Speed (50ths of a second per frame)");
    ui_heading(_cx1 + 32 + _half, _ky, "Plays");
    var _nr = ui_stepper("anim_rate", _cx1 + 20, _ky + 18, min(_half, 180), _an.rate, 2, 30, "Animation speed|How many 50ths of a second each frame stays on screen. 4 is quick, 8 a brisk walk, 20 a slow blink.");
    if (_nr != _an.rate && anim_can_edit())
    {
        anim_begin_edit(_s, "animrate" + string(sel_actor) + "_" + string(anim_sel));
        _s.anims[anim_sel].rate = _nr;
    }
    var _nm = ui_dropdown("anim_mode", _cx1 + 32 + _half, _ky + 18, _half, 30, anim_mode_names(), _an.mode, "How it plays|Loop starts again after the last frame. Once stops on the last frame until the animation changes (handy for a landing). Ping-pong plays forwards then backwards.");
    if (_nm != _an.mode && anim_can_edit())
    {
        anim_begin_edit(_s, "animmode" + string(current_time));
        _s.anims[anim_sel].mode = _nm;
    }
    _ky += 58;
    var _bw4 = floor((_cx2 - _cx1 - 40 - 3 * 8) / 4);
    var _sel_real = (anim_slot < _nf);
    var _st = BTN_NORMAL;
    if (!_sel_real || anim_slot == 0) { _st = BTN_GHOST; }
    if (ui_button("anim_left", _cx1 + 20, _ky, _bw4, 32, "Move left", "Move left|Swaps the selected frame with the one before it.", _st))
    {
        if (_sel_real && anim_slot > 0 && anim_can_edit())
        {
            anim_begin_edit(_s, "animmove" + string(current_time));
            var _fr = _s.anims[anim_sel].frames;
            var _tmp = _fr[anim_slot - 1];
            _fr[anim_slot - 1] = _fr[anim_slot];
            _fr[anim_slot] = _tmp;
            anim_slot -= 1;
        }
    }
    _st = BTN_NORMAL;
    if (!_sel_real || anim_slot >= _nf - 1) { _st = BTN_GHOST; }
    if (ui_button("anim_right", _cx1 + 20 + (_bw4 + 8), _ky, _bw4, 32, "Move right", "Move right|Swaps the selected frame with the one after it.", _st))
    {
        if (_sel_real && anim_slot < _nf - 1 && anim_can_edit())
        {
            anim_begin_edit(_s, "animmove" + string(current_time));
            var _fr2 = _s.anims[anim_sel].frames;
            var _tmp2 = _fr2[anim_slot + 1];
            _fr2[anim_slot + 1] = _fr2[anim_slot];
            _fr2[anim_slot] = _tmp2;
            anim_slot += 1;
        }
    }
    _st = BTN_NORMAL;
    if (!_sel_real) { _st = BTN_GHOST; }
    if (ui_button("anim_remove", _cx1 + 20 + 2 * (_bw4 + 8), _ky, _bw4, 32, "Remove frame", "Remove frame|Takes the selected frame out of this animation. You can Undo this.", _st))
    {
        if (_sel_real && anim_can_edit())
        {
            anim_begin_edit(_s, "animdel" + string(current_time));
            array_delete(_s.anims[anim_sel].frames, anim_slot, 1);
        }
    }
    _st = BTN_DANGER;
    if (_nf == 0) { _st = BTN_GHOST; }
    if (ui_button("anim_clear", _cx1 + 20 + 3 * (_bw4 + 8), _ky, _bw4, 32, "Clear", "Clear animation|Removes every frame of this animation, so it borrows from the others again. You can Undo this.", _st))
    {
        if (_nf > 0 && anim_can_edit())
        {
            anim_begin_edit(_s, "animclear" + string(current_time));
            _s.anims[anim_sel].frames = [];
            anim_slot = 0;
        }
    }

    // ---------------- right: options and the sprite bank ----------------
    var _rx = _x2 - _rw;
    ui_panel(_rx, _y1, _x2, _y2, "Sprite bank");
    var _fx = _rx + 20;
    var _fw = _rw - 40;
    var _oy = _y1 + 54;
    var _flip = ui_toggle("anim_flip", _fx, _oy, "Turn to face left", _s.anim_flip, "Turn to face left|Draw the frames facing right; while the actor moves left the Amiga shows them turned round. The turned copies take a little more chip RAM.");
    if (_flip != _s.anim_flip && anim_can_edit())
    {
        anim_begin_edit(_s, "animflip" + string(current_time));
        _s.anim_flip = _flip;
    }
    _oy += 34;
    if (_s.role == 7)
    {
        ui_heading(_fx, _oy, "Crouch frame (before each hop)");
        var _cn = ["(none)"];
        var _sn = sprite_names();
        for (var cn = 0; cn < array_length(_sn); cn++) { array_push(_cn, _sn[cn]); }
        var _nc = ui_dropdown("anim_crouch", _fx, _oy + 18, _fw, 30, _cn, _s.anim_sprite + 1, "Crouch frame|A hopper shows this sprite while it crouches, just before it springs.") - 1;
        if (_nc != _s.anim_sprite)
        {
            set_val(_s, "anim_sprite", _nc, "animcrouch");
        }
        _oy += 58;
    }
    var _bank = spr_bank_size();
    var _gcols = 5;
    var _gcell = floor((_fw - (_gcols - 1) * 6) / _gcols);
    var _gtop = _oy + 4;
    var _gcontent = ceil(_bank / _gcols) * (_gcell + 6) + 6;
    var _goff = ui_scroll_begin("anim_bank", _rx + 6, _gtop, _x2 - 6, _y2 - 8, _gcontent);
    for (var b = 0; b < _bank; b++)
    {
        var _gx = _fx + (b mod _gcols) * (_gcell + 6);
        var _gy = _gtop + 4 + (b div _gcols) * (_gcell + 6) - _goff;
        if (_gy < _gtop - _gcell || _gy > _y2) { continue; }
        var _bid = "anim_bank_" + string(b);
        var _bsp = proj.sprites[b];
        var _bhot = ui_register(_bid, _gx, _gy, _gx + _gcell, _gy + _gcell, string(b + 1) + ": " + _bsp.name + "|Click to put this sprite in the selected frame (or add it at the end). On a hardware sprite every frame shows in the actor's own colours.");
        var _ba = 0;
        if (_bhot) { _ba = 1; }
        ui_rrect(_gx, _gy, _gx + _gcell, _gy + _gcell, 6, pal_col(0), pal_col(0), 1);
        var _gsc = (_gcell - 6) / max(_bsp.w, _bsp.h);
        draw_sprite_amiga(b, _gx + (_gcell - _bsp.w * _gsc) / 2, _gy + (_gcell - _bsp.h * _gsc) / 2, _gsc, 1);
        var _inanim = false;
        for (var f = 0; f < _nf; f++)
        {
            if (_an.frames[f] == b) { _inanim = true; }
        }
        if (_inanim) { ui_rrect_line(_gx, _gy, _gx + _gcell, _gy + _gcell, 6, global.TH.accent2, 0.9, 2); }
        else { ui_rrect_line(_gx, _gy, _gx + _gcell, _gy + _gcell, 6, global.TH.accent, 0.25 + 0.65 * _ba, 1); }
        if (_bhot && ui_pressed)
        {
            ui_take_click();
            if (anim_can_edit())
            {
                var _cur = _s.anims[anim_sel].frames;
                if (anim_slot < array_length(_cur))
                {
                    anim_begin_edit(_s, "animset" + string(current_time));
                    _cur = _s.anims[anim_sel].frames;
                    if (anim_slot < array_length(_cur)) { _cur[anim_slot] = b; }
                    else { array_push(_cur, b); }
                }
                else if (array_length(_cur) < ANIM_FRAMES)
                {
                    anim_begin_edit(_s, "animadd" + string(current_time));
                    array_push(_s.anims[anim_sel].frames, b);
                    anim_slot = min(array_length(_s.anims[anim_sel].frames), ANIM_FRAMES - 1);
                }
                else
                {
                    toast("An animation has up to " + string(ANIM_FRAMES) + " frames", 1);
                }
            }
        }
    }
    ui_scroll_end("anim_bank", _rx + 6, _gtop, _x2 - 6, _y2 - 8, _gcontent);
}
