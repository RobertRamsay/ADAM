/// ADAM - Animate workspace (ADAM Lite and Pro): Idle, Walk, Jump and Fall
/// animations of up to 8 frames for each actor, picked from the sprite bank,
/// or a movement layout of 8 directions (N NE E SE S SW W NW) - people
/// walking every way, a ship that veers and holds its lean - with a test
/// mode driven by the arrow keys, WASD or a gamepad.
///
/// The engine picks the animation by itself: Idle while the actor stands
/// still, Walk (or the direction it moves in) while it moves, Jump / Fall
/// while a platform player, hopper or faller is in the air. Empty animations
/// borrow from the others (anim_plan).

function anim_names()
{
    return ["Idle", "Walk", "Jump", "Fall", "N", "NE", "E", "SE", "S", "SW", "W", "NW"];
}

function anim_long_names()
{
    return ["Idle", "Walk", "Jump", "Fall", "Up", "Up and right", "Right", "Down and right", "Down", "Down and left", "Left", "Up and left"];
}

function anim_mode_names()
{
    return ["Loop", "Once (hold the last frame)", "Ping-pong"];
}

/// True when the Animate page may change things (every edition; kept as the
/// one place to gate it with pro_gate("Animations") again)
function anim_can_edit()
{
    return true;
}

/// Marks an undo step for the selected actor. The first change here starts
/// from its two-frame animation and switches that off for good, so clearing
/// every frame really leaves one still frame.
function anim_begin_edit(_ac, _tag)
{
    undo_mark(_tag);
    anims_seed_from_legacy(_ac);
    anim_t0 = current_time;
}

/// True on the second click of a double-click on control _id (within 0.4 s)
function anim_dbl(_id)
{
    if (anim_click_id == _id && current_time - anim_click_time < 400)
    {
        anim_click_id = "";
        return true;
    }
    anim_click_id = _id;
    anim_click_time = current_time;
    return false;
}

/// Opens sprite _i on the Sprites page to draw it
function anim_edit_sprite(_i)
{
    spr_sel = clamp(_i, 0, SPR_COUNT - 1);
    ws_set(WS_SPRITES);
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

/// Joystick for the test mode: arrow keys, WASD or any gamepad (stick or d-pad).
/// Returns [dx, dy] with -1, 0 or 1 each.
function anim_test_input()
{
    var _dx = 0;
    var _dy = 0;
    if (ui_focus == "")
    {
        if (keyboard_check(vk_left) || keyboard_check(ord("A"))) { _dx -= 1; }
        if (keyboard_check(vk_right) || keyboard_check(ord("D"))) { _dx += 1; }
        if (keyboard_check(vk_up) || keyboard_check(ord("W"))) { _dy -= 1; }
        if (keyboard_check(vk_down) || keyboard_check(ord("S"))) { _dy += 1; }
    }
    for (var g = 0; g < 12; g++)
    {
        if (!gamepad_is_connected(g)) { continue; }
        var _ax = gamepad_axis_value(g, gp_axislh);
        var _ay = gamepad_axis_value(g, gp_axislv);
        if (_ax < -0.4 || gamepad_button_check(g, gp_padl)) { _dx -= 1; }
        if (_ax > 0.4 || gamepad_button_check(g, gp_padr)) { _dx += 1; }
        if (_ay < -0.4 || gamepad_button_check(g, gp_padu)) { _dy -= 1; }
        if (_ay > 0.4 || gamepad_button_check(g, gp_padd)) { _dy += 1; }
    }
    return [clamp(_dx, -1, 1), clamp(_dy, -1, 1)];
}

/// Direction 0..7 (N NE E SE S SW W NW) of a move, as engine.s dir_tab
function anim_dir_of(_dx, _dy)
{
    var _tab = [7, 0, 1, 6, 0, 2, 5, 4, 3];
    return _tab[(_dy + 1) * 3 + (_dx + 1)];
}

/// One cell of the movement layout (compass): entry _k of actor _s
function anim_compass_cell(_s, _plan, _k, _cx, _cy, _cell, _cols, _lit)
{
    var _names = anim_names();
    var _lnames = anim_long_names();
    var _id = "anim_dir_" + string(_k);
    var _own = array_length(_s.anims[_k].frames);
    var _help = _lnames[_k] + "|Click to give this direction its own frames. Empty directions borrow from the others (turned round when 'Turn to face left' is on).";
    if (_k == 0) { _help = "Idle|Plays while the actor stands still. Empty: it stands facing the way it last moved (the first frame of that direction)."; }
    var _hot = ui_register(_id, _cx, _cy, _cx + _cell, _cy + _cell, _help);
    var _bg = 0.35;
    if (_hot) { _bg = 0.6; }
    ui_rrect(_cx, _cy, _cx + _cell, _cy + _cell, 8, pal_col(0), pal_col(0), 1);
    if (!is_undefined(_plan))
    {
        var _e = _plan[_k];
        if (_e.mode == 3) { _e = _plan[ANIM_DIR0 + 2]; }
        var _fi = clamp(_e.frames[0], 0, SPR_COUNT - 1);
        var _ts = proj.sprites[_fi];
        var _sc = (_cell - 14) / max(_ts.w, _ts.h);
        var _a = 1;
        if (_own == 0) { _a = 0.35; }
        draw_sprite_amiga_flip(_fi, _cx + (_cell - _ts.w * _sc) / 2, _cy + 4 + (_cell - 8 - _ts.h * _sc) / 2, _sc, _e.flip, _cols, _a);
    }
    var _tag = _names[_k];
    if (_own > 0)
    {
        var _mt = ["", "  once", "  ping"];
        _tag += _mt[clamp(_s.anims[_k].mode, 0, 2)];
    }
    ui_text(_cx + 5, _cy + 3, _tag, global.TH.text_dim, fa_left, fa_top, global.f_small, 1);
    if (anim_sel == _k)
    {
        ui_rrect_line(_cx - 2, _cy - 2, _cx + _cell + 2, _cy + _cell + 2, 9, global.TH.accent, 1, 2);
    }
    else if (_lit)
    {
        ui_rrect_line(_cx - 1, _cy - 1, _cx + _cell + 1, _cy + _cell + 1, 9, global.TH.accent2, 1, 2);
    }
    else
    {
        ui_rrect_line(_cx, _cy, _cx + _cell, _cy + _cell, 8, global.TH.panel_edge, 0.4 + _bg * 0.5, 1);
    }
    if (_hot && ui_pressed)
    {
        ui_take_click();
        if (anim_sel != _k)
        {
            anim_sel = _k;
            anim_slot = 0;
            anim_t0 = current_time;
        }
    }
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
        var _ncount = ANIM_BASIC;
        if (_ac.anim_dirs) { _ncount = ANIM_COUNT; }
        for (var ae = 0; ae < _ncount; ae++) { _nfr += array_length(_ac.anims[ae].frames); }
        var _sub = "Not animated yet";
        if (_nfr > 0)
        {
            _sub = string(_nfr) + " frames";
            if (_ac.anim_dirs) { _sub += ", 8 directions"; }
        }
        else if (_ac.anim_sprite >= 0 && _ac.role != 7) { _sub = "Two-frame animation"; }
        ui_text(_x1 + 60, _ry + 35, ui_text_fit(_sub, global.f_small, _lw - 84), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            if (sel_actor != i)
            {
                sel_actor = i;
                anim_slot = 0;
                anim_t0 = current_time;
                anim_test_entry = -1;
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
    if (!_s.anim_dirs && anim_sel >= ANIM_BASIC) { anim_sel = 0; }
    if (_s.anim_dirs && anim_sel == 1) { anim_sel = ANIM_DIR0 + 2; }
    anim_sel = clamp(anim_sel, 0, ANIM_COUNT - 1);
    var _names = anim_names();
    var _lnames = anim_long_names();
    var _gravity = (_s.role >= 6);

    // ---------------- centre: animations, movement layout, preview, frames ----------------
    ui_panel(_cx1, _y1, _cx2, _y2, "Animate " + _s.name);

    // which animations: Idle / Walk / Jump / Fall, or Idle + the 8 directions (+ Jump / Fall)
    var _tabs = [0, 1, 2, 3];
    if (_s.anim_dirs) { _tabs = [0, 2, 3]; }
    var _tw = 84;
    var _thelp = [
        "Idle|Plays while the actor stands still.",
        "Walk|Plays while the actor moves.",
        "Jump|Plays while a platform player, hopper or faller goes up through the air. Empty: it uses Walk.",
        "Fall|Plays while a platform player, hopper or faller comes down. Empty: it uses Jump (or Walk)."
    ];
    for (var t = 0; t < array_length(_tabs); t++)
    {
        var _tk = _tabs[t];
        var _lab = _names[_tk];
        var _tn = array_length(_s.anims[_tk].frames);
        if (_tn > 0) { _lab += "  " + string(_tn); }
        if (ui_tab("anim_tab_" + string(_tk), _cx1 + 20 + t * (_tw + 6), _y1 + 50, _tw, 30, _lab, anim_sel == _tk, _thelp[_tk]))
        {
            if (anim_sel != _tk)
            {
                anim_sel = _tk;
                anim_slot = 0;
                anim_t0 = current_time;
            }
        }
    }
    var _tgx = _cx1 + 20 + array_length(_tabs) * (_tw + 6) + 10;
    var _dirs_v = ui_toggle("anim_dirs", _tgx, _y1 + 53, "8 directions", _s.anim_dirs, "8 directions|A movement layout: give the actor its own animation for each of 8 directions - people walking every way, or a ship that veers and holds its lean (Once). Missing directions borrow from the others. Replaces Walk.");
    if (_dirs_v != _s.anim_dirs && anim_can_edit())
    {
        anim_begin_edit(_s, "animdirs" + string(current_time));
        _s.anim_dirs = _dirs_v;
        anim_slot = 0;
        if (_dirs_v) { anim_sel = ANIM_DIR0 + 2; }
        else { anim_sel = 1; }
    }
    draw_set_font(global.f_body);
    var _tgx2 = _tgx + 54 + ui_sw("8 directions") + 18;
    var _test_v = ui_toggle("anim_test", _tgx2, _y1 + 53, "Test", anim_test, "Test|Drive the preview with the arrow keys, WASD or a gamepad and watch the animations change as the Amiga will change them.");
    if (_test_v != anim_test)
    {
        anim_test = _test_v;
        anim_test_entry = -1;
        anim_test_x = 0;
        anim_test_y = 0;
    }

    // the plan: what the Amiga plays, with the empty animations filled in
    var _plan = anim_plan(_s);
    var _an = _s.anims[anim_sel];
    var _nf = array_length(_an.frames);
    anim_slot = clamp(anim_slot, 0, min(_nf, ANIM_FRAMES - 1));

    var _py1 = _y1 + 94;
    var _strip_h = 92;
    var _ctrl_h = 132;
    var _py2 = _y2 - 20 - _strip_h - _ctrl_h;
    var _vx1 = _cx1 + 20;

    // test mode: read the joystick, pick the animation as engine.s does
    var _test_k = anim_sel;
    var _test_flip = false;
    if (anim_test)
    {
        var _in = anim_test_input();
        var _k2 = 0;
        if (_in[0] != 0 || _in[1] != 0)
        {
            if (_s.anim_dirs)
            {
                anim_test_dir = anim_dir_of(_in[0], _in[1]);
                _k2 = ANIM_DIR0 + anim_test_dir;
            }
            else
            {
                _k2 = 1;
                if (_gravity && _in[1] < 0) { _k2 = 2; }       // up: in the air going up
                if (_gravity && _in[1] > 0) { _k2 = 3; }       // down: coming down
            }
            if (_in[0] < 0) { anim_test_face = true; }
            if (_in[0] > 0) { anim_test_face = false; }
            anim_test_x += _in[0] * 1.5;
            anim_test_y += _in[1] * 1.5;
        }
        if (_k2 != anim_test_entry)
        {
            anim_test_entry = _k2;
            anim_test_t0 = current_time;
        }
        _test_k = _k2;
        if (!_s.anim_dirs && _s.anim_flip && anim_test_face) { _test_flip = true; }
    }

    // movement layout: a compass of the 8 directions round Idle
    if (_s.anim_dirs)
    {
        var _cell = floor(min(70, (_py2 - _py1 - 8) / 3));
        var _order = [11, 4, 5, 10, 0, 6, 9, 8, 7];       // NW N NE / W Idle E / SW S SE
        for (var q = 0; q < 9; q++)
        {
            var _qx = _vx1 + (q mod 3) * (_cell + 4);
            var _qy = _py1 + (q div 3) * (_cell + 4);
            var _lit = (anim_test && _order[q] == _test_k);
            anim_compass_cell(_s, _plan, _order[q], _qx, _qy, _cell, _cols, _lit);
        }
        _vx1 += 3 * (_cell + 4) + 10;
    }

    // preview: what the Amiga will play
    ui_inset(_vx1, _py1, _cx2 - 20, _py2, 10);
    ui_rrect(_vx1 + 6, _py1 + 6, _cx2 - 26, _py2 - 6, 8, pal_col(0), pal_col(0), 1);
    ui_register("anim_preview", _vx1, _py1, _cx2 - 20, _py2, "Preview|Plays the animation at the real Amiga speed (50 frames a second), in the colours the actor really gets. Switch on Test to drive it with the arrow keys, WASD or a gamepad.");
    var _note = "";
    if (is_undefined(_plan))
    {
        _note = "One frame - pick sprites from the bank on the right to animate it";
        var _bs = proj.sprites[clamp(_s.sprite, 0, SPR_COUNT - 1)];
        var _bsc = max(1, floor(min((_cx2 - 20 - _vx1 - 40) / _bs.w, (_py2 - _py1 - 50) / _bs.h)));
        draw_sprite_amiga_flip(_s.sprite, floor((_vx1 + _cx2 - 20 - _bs.w * _bsc) / 2), floor((_py1 + _py2 - 20 - _bs.h * _bsc) / 2), _bsc, _test_flip, _cols, 1);
    }
    else
    {
        var _pk = _test_k;
        var _pe = _plan[_pk];
        var _ticks = (current_time - anim_t0) div 20;
        if (anim_test) { _ticks = (current_time - anim_test_t0) div 20; }
        var _flip = _pe.flip;
        if (!anim_test && !_s.anim_dirs && _s.anim_flip && anim_face_left) { _flip = !_flip; }
        if (_test_flip) { _flip = !_flip; }
        var _fi = 0;
        if (_pe.mode == 3)
        {
            // stand facing the way it last moved
            var _fd = 2;
            if (anim_test) { _fd = anim_test_dir; }
            _pe = _plan[ANIM_DIR0 + _fd];
            _flip = _pe.flip;
        }
        else
        {
            _fi = anim_frame_at(_pe, _ticks);
        }
        var _psi2 = clamp(_pe.frames[_fi], 0, SPR_COUNT - 1);
        var _ps = proj.sprites[_psi2];
        var _bw = 16;
        var _bh = 16;
        for (var q2 = 0; q2 < array_length(_pe.frames); q2++)
        {
            var _qs = proj.sprites[clamp(_pe.frames[q2], 0, SPR_COUNT - 1)];
            _bw = max(_bw, _qs.w);
            _bh = max(_bh, _qs.h);
        }
        var _sc = max(1, floor(min((_cx2 - 20 - _vx1 - 40) / _bw, (_py2 - _py1 - 50) / _bh)));
        if (anim_test) { _sc = max(1, floor(_sc * 0.6)); }
        var _dx = floor((_vx1 + _cx2 - 20 - _bw * _sc) / 2);
        var _dy = floor((_py1 + _py2 - 20 - _bh * _sc) / 2);
        if (anim_test)
        {
            // the actor drifts round the box as it moves (and wraps at the edges)
            var _rx = (_cx2 - 20 - _vx1 - 20 - _bw * _sc) / 2;
            var _ryy = (_py2 - _py1 - 40 - _bh * _sc) / 2;
            if (anim_test_x > _rx) { anim_test_x = -_rx; }
            if (anim_test_x < -_rx) { anim_test_x = _rx; }
            if (anim_test_y > _ryy) { anim_test_y = -_ryy; }
            if (anim_test_y < -_ryy) { anim_test_y = _ryy; }
            _dx += floor(anim_test_x);
            _dy += floor(anim_test_y);
        }
        draw_sprite_amiga_flip(_psi2, _dx, _dy, _sc, _flip, _cols, 1);
        if (anim_test)
        {
            _note = "Test: " + _lnames[_test_k] + "   -   arrow keys, WASD or gamepad";
            if (_gravity && !_s.anim_dirs) { _note += " (up = jump, down = fall)"; }
        }
        else if (_nf == 0)
        {
            _note = "Empty - borrows from another animation (shown)";
            if (!anims_used(_s)) { _note = "Plays the two-frame animation from the Actors page - add frames here to replace it"; }
            if (anim_sel == 0 && _s.anim_dirs) { _note = "Empty - stands facing the way it last moved"; }
        }
        else
        {
            _note = _lnames[anim_sel] + ":  frame " + string(_fi + 1) + " of " + string(array_length(_pe.frames)) + "   -   sprite " + string(_psi2 + 1) + ": " + _ps.name;
        }
    }
    ui_text(_vx1 + 16, _py2 - 22, ui_text_fit(_note, global.f_small, _cx2 - _vx1 - 200), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    if (_s.anim_flip && !_s.anim_dirs && !anim_test)
    {
        anim_face_left = ui_toggle("anim_faceleft", _cx2 - 170, _py2 - 34, "Facing left", anim_face_left, "Facing left|Shows the frames turned round, as the actor looks while it moves left.");
    }
    if (!_gravity && (anim_sel == 2 || anim_sel == 3))
    {
        ui_text((_vx1 + _cx2 - 20) / 2, _py1 + 22, "Only platform players, hoppers and fallers jump and fall", global.TH.warn, fa_center, fa_middle, global.f_small, 1);
    }

    // frame strip: up to 8 frames; the slot after the last one adds a frame
    var _sy = _py2 + 14;
    ui_heading(_cx1 + 20, _sy, _lnames[anim_sel] + " frames  (" + string(_nf) + " / " + string(ANIM_FRAMES) + ")  -  click a frame, then a sprite in the bank");
    _sy += 20;
    var _cellw = min(64, floor((_cx2 - _cx1 - 40 - 7 * 8) / ANIM_FRAMES));
    for (var k = 0; k < ANIM_FRAMES; k++)
    {
        var _kx = _cx1 + 20 + k * (_cellw + 8);
        var _kid = "anim_slot_" + string(k);
        if (k < _nf)
        {
            var _khot = ui_register(_kid, _kx, _sy, _kx + _cellw, _sy + _cellw, "Frame " + string(k + 1) + "|Click to select it, then click a sprite in the bank to change it. Double-click to draw it on the Sprites page. Remove, move or clear it with the buttons below.");
            ui_rrect(_kx, _sy, _kx + _cellw, _sy + _cellw, 8, pal_col(0), pal_col(0), 1);
            var _ks = proj.sprites[clamp(_an.frames[k], 0, SPR_COUNT - 1)];
            var _ksc = (_cellw - 8) / max(_ks.w, _ks.h);
            draw_sprite_amiga_cols(_an.frames[k], _kx + (_cellw - _ks.w * _ksc) / 2, _sy + (_cellw - _ks.h * _ksc) / 2, _ksc, _cols, 1);
            ui_text(_kx + 5, _sy + 4, string(k + 1), global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
            if (anim_slot == k) { ui_rrect_line(_kx - 2, _sy - 2, _kx + _cellw + 2, _sy + _cellw + 2, 9, global.TH.accent, 1, 2); }
            else { ui_rrect_line(_kx, _sy, _kx + _cellw, _sy + _cellw, 8, global.TH.panel_edge, 0.8, 1); }
            if (_khot && ui_pressed)
            {
                anim_slot = k;
                ui_take_click();
                if (anim_dbl(_kid)) { anim_edit_sprite(_an.frames[k]); }
            }
        }
        else if (k == _nf)
        {
            var _ahot = ui_register(_kid, _kx, _sy, _kx + _cellw, _sy + _cellw, "Add a frame|Select this slot, then click sprites in the bank: each one is added to the end of the animation.");
            var _aa = 0.35;
            if (_ahot) { _aa = 0.7; }
            ui_rrect(_kx, _sy, _kx + _cellw, _sy + _cellw, 8, global.TH.btn_hot_top, global.TH.btn_hot_bot, _aa);
            ui_text(_kx + _cellw / 2, _sy + _cellw / 2, "+", global.TH.text, fa_center, fa_middle, global.f_title, 1);
            if (anim_slot == k) { ui_rrect_line(_kx - 2, _sy - 2, _kx + _cellw + 2, _sy + _cellw + 2, 9, global.TH.accent, 1, 2); }
            if (_ahot && ui_pressed)
            {
                anim_slot = k;
                ui_take_click();
            }
        }
        else
        {
            ui_rrect_line(_kx, _sy, _kx + _cellw, _sy + _cellw, 8, global.TH.panel_edge, 0.35, 1);
        }
    }

    // controls
    var _ky = _sy + _cellw + 18;
    var _half = floor((_cx2 - _cx1 - 40 - 12) / 2);
    ui_heading(_cx1 + 20, _ky, "Speed (50ths of a second per frame)");
    ui_heading(_cx1 + 32 + _half, _ky, "Plays");
    var _nr = ui_stepper("anim_rate", _cx1 + 20, _ky + 18, min(_half, 180), _an.rate, 2, 30, "Animation speed|How many 50ths of a second each frame stays on screen. 4 is quick, 8 a brisk walk, 20 a slow blink.");
    if (_nr != _an.rate && anim_can_edit())
    {
        anim_begin_edit(_s, "animrate" + string(sel_actor) + "_" + string(anim_sel));
        _s.anims[anim_sel].rate = _nr;
    }
    var _nm = ui_dropdown("anim_mode", _cx1 + 32 + _half, _ky + 18, _half, 30, anim_mode_names(), _an.mode, "How it plays|Loop starts again after the last frame. Once plays to the last frame and holds it while the animation lasts - a ship veering and holding its lean, or a landing. Ping-pong plays forwards then backwards.");
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
    if (ui_button("anim_clear", _cx1 + 20 + 3 * (_bw4 + 8), _ky, _bw4, 32, "Clear", "Clear animation|Removes every frame of this animation, so it borrows from the others again (with nothing left, the actor shows its own sprite). You can Undo this.", _st))
    {
        if (_nf > 0 && anim_can_edit())
        {
            anim_begin_edit(_s, "animclear" + string(current_time));
            _s.anims[anim_sel].frames = [];
            anim_slot = 0;
        }
    }

    // ---------------- right: options and the sprite bank ----------------
    var _rx2 = _x2 - _rw;
    ui_panel(_rx2, _y1, _x2, _y2, "Sprite bank");
    var _fx = _rx2 + 20;
    var _fw = _rw - 40;
    var _oy = _y1 + 54;
    var _fhelp = "Turn to face left|Draw the frames facing right; while the actor moves left the Amiga shows them turned round. The turned copies take a little more chip RAM.";
    if (_s.anim_dirs) { _fhelp = "Turn round missing directions|With 8 directions: an empty left-side direction (W, NW, SW) uses its right-side partner turned round, and the other way about - draw one side and get both."; }
    var _flipv = ui_toggle("anim_flip", _fx, _oy, "Turn to face left", _s.anim_flip, _fhelp);
    if (_flipv != _s.anim_flip && anim_can_edit())
    {
        anim_begin_edit(_s, "animflip" + string(current_time));
        _s.anim_flip = _flipv;
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
    var _goff = ui_scroll_begin("anim_bank", _rx2 + 6, _gtop, _x2 - 6, _y2 - 8, _gcontent);
    for (var b = 0; b < _bank; b++)
    {
        var _gx = _fx + (b mod _gcols) * (_gcell + 6);
        var _gy = _gtop + 4 + (b div _gcols) * (_gcell + 6) - _goff;
        if (_gy < _gtop - _gcell || _gy > _y2) { continue; }
        var _bid = "anim_bank_" + string(b);
        var _bsp = proj.sprites[b];
        var _bhot = ui_register(_bid, _gx, _gy, _gx + _gcell, _gy + _gcell, string(b + 1) + ": " + _bsp.name + "|Click to put this sprite in the selected frame (or add it at the end). Double-click to draw it on the Sprites page. On a hardware sprite every frame shows in the actor's own colours.");
        var _ba = 0;
        if (_bhot) { _ba = 1; }
        ui_rrect(_gx, _gy, _gx + _gcell, _gy + _gcell, 6, pal_col(0), pal_col(0), 1);
        var _gsc = (_gcell - 6) / max(_bsp.w, _bsp.h);
        draw_sprite_amiga(b, _gx + (_gcell - _bsp.w * _gsc) / 2, _gy + (_gcell - _bsp.h * _gsc) / 2, _gsc, 1);
        // read the frames afresh: a button above may have just removed or cleared some
        var _live = _s.anims[anim_sel].frames;
        var _inanim = false;
        for (var f = 0; f < array_length(_live); f++)
        {
            if (_live[f] == b) { _inanim = true; }
        }
        if (_inanim) { ui_rrect_line(_gx, _gy, _gx + _gcell, _gy + _gcell, 6, global.TH.accent2, 0.9, 2); }
        else { ui_rrect_line(_gx, _gy, _gx + _gcell, _gy + _gcell, 6, global.TH.accent, 0.25 + 0.65 * _ba, 1); }
        if (_bhot && ui_pressed)
        {
            ui_take_click();
            if (anim_dbl(_bid))
            {
                // double-click: draw it instead. The first click added it at the end - take that back.
                var _back = _s.anims[anim_sel].frames;
                if (anim_click_added && array_length(_back) > 0 && _back[array_length(_back) - 1] == b)
                {
                    array_delete(_back, array_length(_back) - 1, 1);
                    anim_slot = array_length(_back);
                }
                anim_click_added = false;
                anim_edit_sprite(b);
            }
            else if (anim_can_edit())
            {
                anim_click_added = false;
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
                    anim_click_added = true;
                    anim_slot = min(array_length(_s.anims[anim_sel].frames), ANIM_FRAMES - 1);
                }
                else
                {
                    toast("An animation has up to " + string(ANIM_FRAMES) + " frames", 1);
                }
            }
        }
    }
    ui_scroll_end("anim_bank", _rx2 + 6, _gtop, _x2 - 6, _y2 - 8, _gcontent);
}
