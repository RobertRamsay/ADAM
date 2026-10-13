/// ADAM - Animate workspace (ADAM Lite and Pro): Idle, Walk, Jump and Fall
/// animations of up to 16 frames for each actor, picked from the sprite bank,
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
    return ["Idle", "Walk", "Jump", "Fall", "N", "NE", "E", "SE", "S", "SW", "W", "NW",
            "Fire", "N", "NE", "E", "SE", "S", "SW", "W", "NW"];
}

function anim_long_names()
{
    return ["Idle", "Walk", "Jump", "Fall", "Up", "Up and right", "Right", "Down and right", "Down", "Down and left", "Left", "Up and left",
            "Fire", "Fire + up", "Fire + up and right", "Fire + right", "Fire + down and right", "Fire + down", "Fire + down and left", "Fire + left", "Fire + up and left"];
}

function anim_mode_names()
{
    return ["Loop", "Once (then hold)", "Ping-pong"];
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
    if (_i >= spr_bank_size())
    {
        lim_toast("Sprite " + string(_i + 1) + " is past the sprite bank", "a bank of " + string(SPR_COUNT) + " sprites");
        return;
    }
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

/// Input for test mode: keyboard (arrows / WASD) or any gamepad (stick / d-pad).
/// Fire is Space / Ctrl on keyboard, or A on a gamepad.
/// Returns [dx, dy, fire] with -1, 0 or 1 each and fire true / false.
function anim_test_input(_source)
{
    var _dx = 0;
    var _dy = 0;
    var _fire = false;
    if (_source == 0 && ui_focus == "")
    {
        if (keyboard_check(vk_space) || keyboard_check(vk_control)) { _fire = true; }
        if (keyboard_check(vk_left) || keyboard_check(ord("A"))) { _dx -= 1; }
        if (keyboard_check(vk_right) || keyboard_check(ord("D"))) { _dx += 1; }
        if (keyboard_check(vk_up) || keyboard_check(ord("W"))) { _dy -= 1; }
        if (keyboard_check(vk_down) || keyboard_check(ord("S"))) { _dy += 1; }
    }
    if (_source == 1)
    {
        for (var g = 0; g < 12; g++)
        {
            if (!gamepad_is_connected(g)) { continue; }
            var _ax = gamepad_axis_value(g, gp_axislh);
            var _ay = gamepad_axis_value(g, gp_axislv);
            if (_ax < -0.4 || gamepad_button_check(g, gp_padl)) { _dx -= 1; }
            if (_ax > 0.4 || gamepad_button_check(g, gp_padr)) { _dx += 1; }
            if (_ay < -0.4 || gamepad_button_check(g, gp_padu)) { _dy -= 1; }
            if (_ay > 0.4 || gamepad_button_check(g, gp_padd)) { _dy += 1; }
            if (gamepad_button_check(g, gp_face1)) { _fire = true; }
        }
    }
    return [clamp(_dx, -1, 1), clamp(_dy, -1, 1), _fire];
}

/// Direction 0..7 (N NE E SE S SW W NW) of a move, as engine.s dir_tab
function anim_dir_of(_dx, _dy)
{
    var _tab = [7, 0, 1, 6, 0, 2, 5, 4, 3];
    return _tab[(_dy + 1) * 3 + (_dx + 1)];
}

/// Draws plan entry _k of an actor playing live in a square _w wide at (_x, _y).
/// A direction without an entry of its own plays Walk, as the engine does.
function anim_slot_preview(_plan, _k, _x, _y, _w, _cols, _alpha)
{
    if (is_undefined(_plan)) { return; }
    var _kk = _k;
    if (_kk >= array_length(_plan))
    {
        if (_kk >= ANIM_FIRE0) { return; }
        _kk = 1;
    }
    var _e = _plan[_kk];
    if (_e.mode == 3 && array_length(_plan) > ANIM_DIR0 + 2) { _e = _plan[ANIM_DIR0 + 2]; }    // stands facing right
    anim_strip_preview(_e.frames, _e.rate, _e.mode, _e.flip, _x, _y, _w, _cols, _alpha);
}

/// Draws frames _frames playing live (rate, mode, turned round) in a square _w wide.
/// Once replays after a short pause, so a preview never stops for good.
function anim_strip_preview(_frames, _rate, _mode, _flip, _x, _y, _w, _cols, _alpha)
{
    var _n = array_length(_frames);
    if (_n == 0) { return; }
    var _bw = 8;
    var _bh = 8;
    for (var f = 0; f < _n; f++)
    {
        var _fs = proj.sprites[clamp(_frames[f], 0, SPR_COUNT - 1)];
        _bw = max(_bw, _fs.w);
        _bh = max(_bh, _fs.h);
    }
    var _ticks = current_time div 20;
    var _md = _mode;
    if (_md == 3) { _md = 0; }
    if (_md == 1) { _ticks = _ticks mod (_n * max(2, _rate) + 30); }
    var _fi = anim_frame_at({ frames : _frames, rate : _rate, mode : _md }, _ticks);
    var _si = clamp(_frames[_fi], 0, SPR_COUNT - 1);
    var _ps = proj.sprites[_si];
    var _sc = (_w - 8) / max(_bw, _bh);
    draw_sprite_amiga_flip(_si, _x + (_w - _ps.w * _sc) / 2, _y + (_w - _ps.h * _sc) / 2, _sc, _flip, _cols, _alpha);
}

/// Grid cell (-1..1, -1..1) of direction 0..7 (N NE E SE S SW W NW)
function anim_dir_cell(_d)
{
    var _gx = [0, 1, 1, 1, 0, -1, -1, -1];
    var _gy = [-1, -1, 0, 1, 1, 1, 0, -1];
    return [_gx[_d], _gy[_d]];
}

/// Copies animation (frames, rate, mode) into entry _k of the selected actor - a drop
/// from the animation library or from another joystick slot
function anim_drop_into(_s, _k, _frames, _rate, _mode)
{
    if (_k < 0 || _k >= ANIM_COUNT || !anim_can_edit()) { return; }
    anim_begin_edit(_s, "animdrop" + string(current_time));
    var _fr = [];
    for (var f = 0; f < min(array_length(_frames), lim_frames()); f++) { array_push(_fr, _frames[f]); }
    if (array_length(_frames) > lim_frames()) { lim_toast("Only the first " + string(lim_frames()) + " frames were dropped in - an animation has up to " + string(lim_frames()) + " frames", "up to " + string(ANIM_FRAMES)); }
    _s.anims[_k].frames = _fr;
    _s.anims[_k].rate = clamp(_rate, 2, 30);
    var _m = _mode;
    if (_m == 3) { _m = 0; }
    _s.anims[_k].mode = clamp(_m, 0, 2);
    anim_sel = _k;
    anim_slot = 0;
    anim_t0 = current_time;
    var _ln = anim_long_names();
    toast(_ln[_k] + ": " + string(array_length(_fr)) + " frames dropped in", 0);
}

/// Starts dragging an animation (frames, rate, mode, turned round) once the mouse
/// has moved a little with the button held; _src = the joystick slot it came from (-1 = library)
function anim_drag_arm(_frames, _rate, _mode, _flip, _cols, _label, _src)
{
    anim_drag_armed = true;
    anim_drag_on = false;
    anim_drag_x0 = ui_mx;
    anim_drag_y0 = ui_my;
    anim_drag_frames = _frames;
    anim_drag_rate = _rate;
    anim_drag_mode = _mode;
    anim_drag_flip = _flip;
    anim_drag_cols = _cols;
    anim_drag_label = _label;
    anim_drag_src = _src;
}

/// Marks entry _k as the drop target when an animation is dragged over (_x1,_y1)-(_x2,_y2)
/// and draws the drop highlight
function anim_drop_zone(_k, _x1, _y1, _x2, _y2)
{
    if (!anim_drag_on || _k == anim_drag_src) { return; }
    if (point_in_rectangle(ui_mx, ui_my, _x1, _y1, _x2, _y2))
    {
        anim_drop_k = _k;
        ui_rrect_line(_x1 - 3, _y1 - 3, _x2 + 3, _y2 + 3, 10, global.TH.accent, 1, 3);
    }
    else
    {
        ui_rrect_line(_x1 - 1, _y1 - 1, _x2 + 1, _y2 + 1, 9, global.TH.accent, 0.35 + 0.25 * sin(current_time / 120), 1);
    }
}

/// One joystick, seen from above: _which 0 = Moving (Idle in the middle and the
/// 8 directions round it), 1 = With Fire (Fire in the middle, its fire button
/// lights up). Each is a square slot playing its animation live. Hovering a
/// direction pushes the stick that way; clicking picks that animation; dragging
/// copies it to another slot, and animations from the library can be dropped in.
/// In Test it follows the keys or gamepad.
function anim_joystick(_which, _x, _y, _size, _s, _plan, _cols, _in, _test_k)
{
    var _locked = !anim_can_edit();
    var _gap = 6;
    var _cell = floor((_size - 4 * _gap) / 3);
    var _cx = _x + _size / 2;
    var _cy = _y + _size / 2;
    var _k0 = 0;                                 // the middle: Idle
    var _kd = ANIM_DIR0;                         // first direction
    if (_which == 1)
    {
        _k0 = ANIM_FIRE0;
        _kd = ANIM_FIRE0 + 1;
    }
    var _lnames = anim_long_names();

    // the base plate
    ui_rrect(_x, _y + 3, _x + _size, _y + _size + 3, 18, c_black, c_black, 0.35);
    ui_rrect(_x, _y, _x + _size, _y + _size, 18, make_colour_rgb(58, 62, 72), make_colour_rgb(30, 32, 38), 1);
    ui_rrect_line(_x, _y, _x + _size, _y + _size, 18, global.TH.panel_edge, 0.8, 1);

    // which way the stick leans: the direction hovered, else the one picked, else Test
    var _push = -1;
    var _hot_any = false;
    for (var d = 0; d < 9; d++)
    {
        // d 0..7 = the directions, 8 = the middle
        var _k = _k0;
        var _gcx = 0;
        var _gcy = 0;
        if (d < 8)
        {
            _k = _kd + d;
            var _gc = anim_dir_cell(d);
            _gcx = _gc[0];
            _gcy = _gc[1];
        }
        var _sx = _cx + _gcx * (_cell + _gap) - _cell / 2;
        var _sy = _cy + _gcy * (_cell + _gap) - _cell / 2;
        var _id = "anim_dir_" + string(_k);
        var _help = _lnames[_k] + "|Plays live here. Click to give this direction its own frames, drag it to copy it to another slot, or drop an animation from the library on it. Empty directions borrow from the others (turned round when 'Turn to face left' is on), or from Walk.";
        if (_which == 1) { _help = _lnames[_k] + "|Plays while the player holds fire and pushes this way - digging, shooting, swinging. Drag to copy it, or drop an animation from the library on it. Empty: it borrows from the other Fire directions."; }
        if (d == 8)
        {
            _id = "anim_mid_" + string(_which);
            _help = "Idle|Plays while the actor stands still. Click to edit it, drag it to copy it, or drop an animation on it. Empty: it stands facing the way it last moved (with directions) or shows its sprite.";
            if (_which == 1) { _help = "Fire|Plays while the player holds fire without pushing a direction. Click to edit it, or drop an animation on it. Empty: it uses a Fire direction, or the normal animation."; }
        }
        var _hot = ui_register(_id, _sx, _sy, _sx + _cell, _sy + _cell, _help);
        if (_hot && d < 8 && !anim_drag_on)
        {
            _push = d;
            _hot_any = true;
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
            var _own0 = _s.anims[_k].frames;
            if (array_length(_own0) > 0) { anim_drag_arm(_own0, _s.anims[_k].rate, _s.anims[_k].mode, false, _cols, _lnames[_k], _k); }
        }
        // the slot: a square window playing its animation (faint when it borrows)
        var _own = array_length(_s.anims[_k].frames);
        var _bg = make_colour_rgb(22, 24, 30);
        if (_hot) { _bg = make_colour_rgb(44, 48, 58); }
        ui_rrect(_sx, _sy, _sx + _cell, _sy + _cell, 8, _bg, _bg, 1);
        var _a = 1;
        if (_own == 0) { _a = 0.3; }
        anim_slot_preview(_plan, _k, _sx, _sy, _cell, _cols, _a);
        var _ring = global.TH.panel_edge;
        var _rw = 1;
        if (_own > 0) { _ring = global.TH.accent2; }
        if (anim_sel == _k)
        {
            _ring = global.TH.accent;
            _rw = 3;
        }
        if (anim_test && _test_k == _k)
        {
            _ring = c_white;
            _rw = 3;
        }
        ui_rrect_line(_sx - (_rw - 1), _sy - (_rw - 1), _sx + _cell + (_rw - 1), _sy + _cell + (_rw - 1), 8, _ring, 1, _rw);
        if (d == 8)
        {
            var _mlab = "Idle";
            if (_which == 1) { _mlab = "Fire"; }
            if (_own > 0) { _mlab += " " + string(_own); }
            var _mcol = global.TH.text_dim;
            if (anim_sel == _k) { _mcol = global.TH.accent; }
            ui_text(_sx + 4, _sy + _cell - 2, _mlab, _mcol, fa_left, fa_bottom, global.f_small, 1);
        }
        if (!_locked) { anim_drop_zone(_k, _sx, _sy, _sx + _cell, _sy + _cell); }
    }
    if (_push < 0 && anim_sel >= _kd && anim_sel < _kd + 8) { _push = anim_sel - _kd; }
    var _fire_lit = false;
    if (anim_test)
    {
        var _tfire = (_which == 1 && _in[2]);
        var _tmove = (_which == 0 && !_in[2]);
        if ((_tfire || _tmove) && (_in[0] != 0 || _in[1] != 0)) { _push = anim_dir_of(_in[0], _in[1]); }
        if (_tfire) { _fire_lit = true; }
    }
    if (_which == 1 && (_hot_any || (anim_sel >= ANIM_FIRE0))) { _fire_lit = true; }

    // the stick: a small knob in the middle slot's corner that leans the way it is pushed
    var _tx = 0;
    var _ty = 0;
    if (_push >= 0)
    {
        var _pc = anim_dir_cell(_push);
        _tx = _pc[0] * _cell * 0.3;
        _ty = _pc[1] * _cell * 0.3;
    }
    var _kn = anim_knob[_which];
    _kn[0] = lerp(_kn[0], _tx, 0.35);
    _kn[1] = lerp(_kn[1], _ty, 0.35);
    anim_knob[_which] = _kn;
    var _kx = _cx + _kn[0];
    var _ky = _cy + _kn[1];
    var _kr = max(6, _cell * 0.13);
    var _ka = 0.35;
    if (_push >= 0) { _ka = 0.9; }
    draw_set_alpha(_ka);
    draw_line_width_colour(_cx, _cy, _kx, _ky, _kr * 0.7, make_colour_rgb(20, 20, 24), make_colour_rgb(50, 50, 56));
    var _kc = make_colour_rgb(200, 40, 40);
    if (_which == 0) { _kc = make_colour_rgb(40, 40, 46); }
    draw_circle_colour(_kx, _ky, _kr, merge_colour(_kc, c_white, 0.25), merge_colour(_kc, c_black, 0.3), false);
    draw_circle_colour(_kx - _kr * 0.3, _ky - _kr * 0.3, _kr * 0.35, merge_colour(_kc, c_white, 0.6), _kc, false);
    draw_set_alpha(1);

    // the fire button (beside the With Fire heading): lights up when fire is held
    if (_which == 1)
    {
        var _br = 8;
        var _bx = _x + _size - _br - 2;
        var _by = _y - 12;
        var _bc = make_colour_rgb(110, 20, 20);
        if (_fire_lit)
        {
            _bc = make_colour_rgb(255, 70, 50);
            draw_set_alpha(0.35 + 0.15 * sin(current_time / 90));
            draw_circle_colour(_bx, _by, _br * 1.9, _bc, _bc, false);
            draw_set_alpha(1);
        }
        draw_circle_colour(_bx, _by, _br, merge_colour(_bc, c_white, 0.2), merge_colour(_bc, c_black, 0.35), false);
    }
    if (_locked)
    {
        ui_rrect(_x, _y, _x + _size, _y + _size, 18, c_black, c_black, 0.55);
        ui_text(_cx, _cy, "ADAM Pro", global.TH.text, fa_center, fa_middle, global.f_bold, 1);
    }
}

function ws_animate_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 240;
    var _rw = 330;
    var _na = array_length(proj.actors);
    sel_actor = clamp(sel_actor, 0, max(0, _na - 1));
    var _alloc = actors_alloc_channels();
    anim_drop_k = -1;           // set by a slot the dragged animation is over

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
        var _ncount = ANIM_COUNT;
        for (var ae = 0; ae < _ncount; ae++) { _nfr += array_length(_ac.anims[ae].frames); }
        var _sub = "Not animated yet";
        if (_nfr > 0)
        {
            _sub = string(_nfr) + " frames";
            if (anims_dirs_on(_ac)) { _sub += ", 8 directions"; }
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
    anim_sel = clamp(anim_sel, 0, ANIM_COUNT - 1);
    var _names = anim_names();
    var _lnames = anim_long_names();
    var _gravity = (_s.role >= 6);
    var _dirs_on = anims_dirs_on(_s);

    // ---------------- centre: two joysticks, preview, frames ----------------
    ui_panel(_cx1, _y1, _cx2, _y2, ui_text_fit("Animate " + _s.name, global.f_title, _cx2 - _cx1 - 32));
    var _plan = anim_plan(_s);
    var _an = _s.anims[anim_sel];
    var _nf = array_length(_an.frames);
    var _smax = min(_nf, lim_frames() - 1);
    if (_nf > lim_frames()) { _smax = _nf - 1; }        // a Pro project in Lite: its extra frames can still be picked and removed
    anim_slot = clamp(anim_slot, 0, _smax);

    // test mode: read the joystick, pick the animation as engine.s does
    var _in = [0, 0, false];
    var _test_k = anim_sel;
    var _test_flip = false;
    if (anim_test)
    {
        _in = anim_test_input(anim_test_source);
        var _k2 = 0;
        if (_in[0] != 0 || _in[1] != 0)
        {
            anim_test_dir = anim_dir_of(_in[0], _in[1]);
            if (_dirs_on) { _k2 = ANIM_DIR0 + anim_test_dir; }
            else
            {
                _k2 = 1;
                if (_gravity && _in[1] < 0) { _k2 = 2; }       // up: in the air
                if (_gravity && _in[1] > 0) { _k2 = 3; }       // down: falling
            }
            if (_in[0] < 0) { anim_test_face = true; }
            if (_in[0] > 0) { anim_test_face = false; }
        }
        // holding fire: the Fire animations, picked from the joystick direction
        var _fire_on = false;
        if (!is_undefined(_plan)) { _fire_on = (_in[2] && array_length(_plan) > ANIM_FIRE0); }
        if (_fire_on)
        {
            _k2 = ANIM_FIRE0;
            if (_in[0] != 0 || _in[1] != 0) { _k2 = ANIM_FIRE0 + 1 + anim_test_dir; }
        }
        if (_k2 != anim_test_entry)
        {
            anim_test_entry = _k2;
            anim_test_t0 = current_time;
        }
        _test_k = _k2;
        if (!_dirs_on && _s.anim_flip && anim_test_face && _k2 < ANIM_BASIC) { _test_flip = true; }
    }

    // left: the Moving joystick above the With Fire joystick, then Walk /
    // In air / Falling and the Test switch
    var _jx = _cx1 + 20;
    var _jy = _y1 + 52;
    var _jsize = floor(min(190, (_y2 - _jy - 20 - 2 * 24 - 2 * 38 - 40) / 2));
    _jsize = max(110, _jsize);
    ui_heading(_jx, _jy, "Moving");
    _jy += 20;
    anim_joystick(0, _jx, _jy, _jsize, _s, _plan, _cols, _in, _test_k);
    _jy += _jsize + 10;
    var _nfire = 0;
    for (var fe = ANIM_FIRE0; fe < ANIM_COUNT; fe++) { _nfire += array_length(_s.anims[fe].frames); }
    var _fh = "With Fire";
    if (_s.role != 0 && _s.role != 6) { _fh = "With Fire (player only)"; }
    ui_heading(_jx, _jy, _fh);
    _jy += 20;
    anim_joystick(1, _jx, _jy, _jsize, _s, _plan, _cols, _in, _test_k);
    _jy += _jsize + 12;
    // Walk / In air / Falling and Test are a little wider than the joysticks, so
    // "In air 8" and "Falling 8" fit their tabs
    var _colw = _jsize + 30;
    var _tw0 = floor((_colw - 88) / 2);
    var _tbw = [_tw0, _tw0, _colw - 8 - 2 * _tw0];
    var _tbx = _jx;
    var _side = [1, 2, 3];
    var _slab = ["Walk", "In air", "Falling"];
    var _shelp = [
        "Walk|Plays while the actor moves. The 8 directions of the Moving joystick borrow it when they have no frames of their own (turned round for left when 'Turn to face left' is on).",
        "In air|Plays while a platform player, hopper or faller goes up through the air. Empty: it uses Walk.",
        "Falling|Plays while a platform player, hopper or faller comes down. Empty: it uses In air."
    ];
    for (var sb = 0; sb < 3; sb++)
    {
        var _sk = _side[sb];
        var _sl = _slab[sb];
        if (array_length(_s.anims[_sk].frames) > 0) { _sl += " " + string(array_length(_s.anims[_sk].frames)); }
        anim_drop_zone(_sk, _tbx, _jy, _tbx + _tbw[sb], _jy + 30);
        if (ui_tab("anim_tab_" + string(_sk), _tbx, _jy, _tbw[sb], 30, _sl, anim_sel == _sk, _shelp[sb]))
        {
            if (anim_sel != _sk)
            {
                anim_sel = _sk;
                anim_slot = 0;
                anim_t0 = current_time;
            }
        }
        _tbx += _tbw[sb] + 4;
    }
    _jy += 38;
    var _tst = BTN_NORMAL;
    if (anim_test) { _tst = BTN_ON; }
    var _tlab = "Test";
    if (anim_test) { _tlab = "Stop"; }
    var _test_btnw = floor((_colw - 4) / 2);
    if (ui_button("anim_test", _jx, _jy, _test_btnw, 32, _tlab, "Test|Drive the animation preview with the selected input. The preview stays in place while its animation changes.", _tst))
    {
        anim_test = !anim_test;
        anim_test_entry = -1;
    }
    var _input_names = ["Keys", "Gamepad"];
    var _input_help = "Test input|Choose keyboard controls (Arrows / WASD, fire Space / Ctrl) or a connected gamepad (D-pad / stick, fire A).";
    var _input_new = ui_dropdown("anim_test_source", _jx + _test_btnw + 4, _jy, _colw - _test_btnw - 4, 32, _input_names, anim_test_source, _input_help);
    if (_input_new != anim_test_source)
    {
        anim_test_source = clamp(_input_new, 0, 1);
        anim_test_entry = -1;
    }
    var _ax1 = _jx + _colw + 20;               // the preview, frames and controls go right of the joysticks

    var _py1 = _y1 + 52;
    var _strip_h = 164;
    var _ctrl_h = 132;
    var _py2 = _y2 - 20 - _strip_h - _ctrl_h;
    var _vx1 = _ax1;

    // preview: what the Amiga will play
    ui_inset(_vx1, _py1, _cx2 - 20, _py2, 10);
    ui_rrect(_vx1 + 6, _py1 + 6, _cx2 - 26, _py2 - 6, 8, pal_col(0), pal_col(0), 1);
    var _input_desc = "Arrows / WASD; fire: Space / Ctrl";
    if (anim_test_source == 1) { _input_desc = "D-pad / stick; fire: A"; }
    ui_register("anim_preview", _vx1, _py1, _cx2 - 20, _py2, "Preview|Plays the animation at the real Amiga speed (50 frames a second), in the colours the actor really gets. Switch on Test and choose Keys or Gamepad to change the directional animation in place.");
    var _note = "";
    if (is_undefined(_plan))
    {
        _note = "One frame - pick sprites from the bank on the right to animate it";
        var _bs = proj.sprites[clamp(_s.sprite, 0, SPR_COUNT - 1)];
        var _bsc = max(1, floor(min((_cx2 - 20 - _vx1 - 40) / _bs.w, (_py2 - _py1 - 50) / _bs.h)));
        draw_sprite_amiga_flip(_s.sprite, floor((_vx1 + _cx2 - 20 - _bs.w * _bsc) / 2), floor((_py1 + _py2 - 20 - _bs.h * _bsc) / 2), _bsc, _test_flip, _cols, 1);
    }
    else if (_test_k >= array_length(_plan))
    {
        _note = "No Fire animations yet - pick sprites from the bank to add some (until then the player keeps its normal animation)";
        var _fs = proj.sprites[clamp(_s.sprite, 0, SPR_COUNT - 1)];
        var _fsc = max(1, floor(min((_cx2 - 20 - _vx1 - 40) / _fs.w, (_py2 - _py1 - 50) / _fs.h)));
        draw_sprite_amiga_cols(_s.sprite, floor((_vx1 + _cx2 - 20 - _fs.w * _fsc) / 2), floor((_py1 + _py2 - 20 - _fs.h * _fsc) / 2), _fsc, _cols, 0.35);
    }
    else
    {
        var _pk = _test_k;
        var _pe = _plan[_pk];
        var _ticks = (current_time - anim_t0) div 20;
        if (anim_test) { _ticks = (current_time - anim_test_t0) div 20; }
        var _flip = _pe.flip;
        if (!anim_test && !_dirs_on && _s.anim_flip && anim_face_left && _pk < ANIM_BASIC) { _flip = !_flip; }
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
        draw_sprite_amiga_flip(_psi2, _dx, _dy, _sc, _flip, _cols, 1);
        if (anim_test)
        {
            _note = "Test: " + _lnames[_test_k] + "   -   " + _input_desc;
            if (_gravity && !_dirs_on) { _note += " (up = in air, down = falling)"; }
        }
        else if (_nf == 0)
        {
            _note = "Empty - borrows from another animation (shown)";
            if (!anims_used(_s)) { _note = "Plays the two-frame animation from the Actors page - add frames here to replace it"; }
            if (anim_sel == 0 && _dirs_on) { _note = "Empty - stands facing the way it last moved"; }
        }
        else
        {
            _note = _lnames[anim_sel] + ":  frame " + string(_fi + 1) + " of " + string(array_length(_pe.frames)) + "   -   sprite " + string(_psi2 + 1) + ": " + _ps.name;
        }
    }
    if (!anim_test) { _note += "   |   Test: " + _input_desc; }
    // the note wraps upwards from the bottom of the preview, clear of the Facing left switch
    var _show_face = (_s.anim_flip && !_dirs_on && !anim_test && anim_sel < ANIM_BASIC);
    var _nw = _cx2 - 26 - 12 - (_vx1 + 16);
    if (_show_face) { _nw = _cx2 - 170 - 12 - (_vx1 + 16); }
    draw_set_font(global.f_small);
    var _nh = ui_sh_ext(_note, _nw);
    ui_text_wrap(_vx1 + 16, _py2 - 14 - _nh, _note, global.TH.text_dim, _nw, global.f_small, 1);
    if (_show_face)
    {
        anim_face_left = ui_toggle("anim_faceleft", _cx2 - 170, _py2 - 34, "Facing left", anim_face_left, "Facing left|Shows the frames turned round, as the actor looks while it moves left.");
    }
    if (!_gravity && (anim_sel == 2 || anim_sel == 3))
    {
        ui_text((_vx1 + _cx2 - 20) / 2, _py1 + 22, "Only platform players, hoppers and fallers use this", global.TH.warn, fa_center, fa_middle, global.f_small, 1);
    }

    // frame strip: up to 16 frames in two rows; the slot after the last one adds a frame
    var _sy = _py2 + 14;
    var _fhw = _cx2 - 20 - _ax1;
    var _fhd = string_upper(_lnames[anim_sel] + " frames  (" + string(_nf) + " / " + string(lim_frames()) + ")  -  click a frame, then a sprite in the bank");
    draw_set_font(global.f_small);
    if (ui_sw(_fhd) > _fhw)
    {
        _fhd = string_upper(_lnames[anim_sel] + " frames  (" + string(_nf) + " / " + string(lim_frames()) + ")  -  click a frame, then a sprite");
    }
    ui_heading(_ax1, _sy, ui_text_fit(_fhd, global.f_small, _fhw));
    var _lim = lim_frames();
    _sy += 20;
    var _strip_cols = 8;
    var _strip_rows = ceil(ANIM_FRAMES / _strip_cols);
    var _cellw = min(64, floor((_fhw - (_strip_cols - 1) * 8) / _strip_cols));
    for (var k = 0; k < ANIM_FRAMES; k++)
    {
        var _kx = _ax1 + (k mod _strip_cols) * (_cellw + 8);
        var _sloty = _sy + (k div _strip_cols) * (_cellw + 8);
        var _kid = "anim_slot_" + string(k);
        if (k >= _lim && k >= _nf)
        {
            // over the Lite limit: a locked slot
            var _phot = ui_register(_kid, _kx, _sloty, _kx + _cellw, _sloty + _cellw, "ADAM Pro|Animations have up to " + string(_lim) + " frames in ADAM Lite and " + string(ANIM_FRAMES) + " in ADAM Pro.");
            ui_rrect_line(_kx, _sloty, _kx + _cellw, _sloty + _cellw, 8, global.TH.panel_edge, 0.35, 1);
            ui_text(_kx + _cellw / 2, _sloty + _cellw / 2, "Pro", global.TH.text_faint, fa_center, fa_middle, global.f_small, 1);
            if (_phot && ui_pressed)
            {
                ui_take_click();
                lim_toast("An animation has up to " + string(_lim) + " frames", "up to " + string(ANIM_FRAMES));
            }
        }
        else if (k < _nf)
        {
            var _khot = ui_register(_kid, _kx, _sloty, _kx + _cellw, _sloty + _cellw, "Frame " + string(k + 1) + "|Click to select it, then click a sprite in the bank to change it. Double-click to draw it on the Sprites page. Remove, move or clear it with the buttons below.");
            ui_rrect(_kx, _sloty, _kx + _cellw, _sloty + _cellw, 8, pal_col(0), pal_col(0), 1);
            var _ks = proj.sprites[clamp(_an.frames[k], 0, SPR_COUNT - 1)];
            var _ksc = (_cellw - 8) / max(_ks.w, _ks.h);
            var _fa = 1;
            if (k >= _lim) { _fa = 0.35; }          // a Pro project in Lite: not played
            draw_sprite_amiga_cols(_an.frames[k], _kx + (_cellw - _ks.w * _ksc) / 2, _sloty + (_cellw - _ks.h * _ksc) / 2, _ksc, _cols, _fa);
            if (k >= _lim) { ui_text(_kx + _cellw - 4, _sloty + _cellw - 2, "Pro", global.TH.warn, fa_right, fa_bottom, global.f_small, 1); }
            ui_text(_kx + 5, _sloty + 4, string(k + 1), global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
            if (anim_slot == k) { ui_rrect_line(_kx - 2, _sloty - 2, _kx + _cellw + 2, _sloty + _cellw + 2, 9, global.TH.accent, 1, 2); }
            else { ui_rrect_line(_kx, _sloty, _kx + _cellw, _sloty + _cellw, 8, global.TH.panel_edge, 0.8, 1); }
            if (_khot && ui_pressed)
            {
                anim_slot = k;
                ui_take_click();
                if (anim_dbl(_kid)) { anim_edit_sprite(_an.frames[k]); }
            }
        }
        else if (k == _nf)
        {
            var _ahot = ui_register(_kid, _kx, _sloty, _kx + _cellw, _sloty + _cellw, "Add a frame|Select this slot, then click sprites in the bank: each one is added to the end of the animation.");
            var _aa = 0.35;
            if (_ahot) { _aa = 0.7; }
            ui_rrect(_kx, _sloty, _kx + _cellw, _sloty + _cellw, 8, global.TH.btn_hot_top, global.TH.btn_hot_bot, _aa);
            ui_text(_kx + _cellw / 2, _sloty + _cellw / 2, "+", global.TH.text, fa_center, fa_middle, global.f_title, 1);
            if (anim_slot == k) { ui_rrect_line(_kx - 2, _sloty - 2, _kx + _cellw + 2, _sloty + _cellw + 2, 9, global.TH.accent, 1, 2); }
            if (_ahot && ui_pressed)
            {
                anim_slot = k;
                ui_take_click();
            }
        }
        else
        {
            ui_rrect_line(_kx, _sloty, _kx + _cellw, _sloty + _cellw, 8, global.TH.panel_edge, 0.35, 1);
        }
    }

    // controls
    var _ky = _sy + _strip_rows * (_cellw + 8) + 10;
    var _half = floor((_cx2 - 20 - _ax1 - 12) / 2);
    var _sphd = "Speed (50ths of a second per frame)";
    draw_set_font(global.f_small);
    if (ui_sw(string_upper(_sphd)) > _half) { _sphd = "Speed (50ths per frame)"; }
    ui_heading(_ax1, _ky, _sphd);
    ui_heading(_ax1 + 12 + _half, _ky, "Plays");
    var _nr = ui_stepper("anim_rate", _ax1, _ky + 18, min(_half, 180), _an.rate, 2, 30, "Animation speed|How many 50ths of a second each frame stays on screen. 4 is quick, 8 a brisk walk, 20 a slow blink.");
    if (_nr != _an.rate && anim_can_edit())
    {
        anim_begin_edit(_s, "animrate" + string(sel_actor) + "_" + string(anim_sel));
        _s.anims[anim_sel].rate = _nr;
    }
    var _nm = ui_dropdown("anim_mode", _ax1 + 12 + _half, _ky + 18, _half, 30, anim_mode_names(), _an.mode, "How it plays|Loop starts again after the last frame. Once plays to the last frame and holds it while the animation lasts - a ship veering and holding its lean, or a landing. Ping-pong plays forwards then backwards.");
    if (_nm != _an.mode && anim_can_edit())
    {
        anim_begin_edit(_s, "animmode" + string(current_time));
        _s.anims[anim_sel].mode = _nm;
    }
    _ky += 58;
    // four buttons; when the row is narrow, Move left / right and Remove keep room for their
    // labels and Clear (the shortest) takes what is left
    var _bavail = _cx2 - 20 - _ax1 - 3 * 8;
    var _bw4 = floor(_bavail / 4);
    var _bw_mv = max(_bw4, 100);
    var _bw_rm = max(_bw4, 80);
    var _bw_cl = _bavail - 2 * _bw_mv - _bw_rm;
    var _bx_rm = _ax1 + 2 * (_bw_mv + 8);
    var _bx_cl = _bx_rm + _bw_rm + 8;
    var _sel_real = (anim_slot < _nf);
    var _st = BTN_NORMAL;
    if (!_sel_real || anim_slot == 0) { _st = BTN_GHOST; }
    if (ui_button("anim_left", _ax1, _ky, _bw_mv, 32, "Move left", "Move left|Swaps the selected frame with the one before it.", _st))
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
    if (ui_button("anim_right", _ax1 + (_bw_mv + 8), _ky, _bw_mv, 32, "Move right", "Move right|Swaps the selected frame with the one after it.", _st))
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
    if (ui_button("anim_remove", _bx_rm, _ky, _bw_rm, 32, "Remove", "Remove frame|Takes the selected frame out of this animation. You can Undo this.", _st))
    {
        if (_sel_real && anim_can_edit())
        {
            anim_begin_edit(_s, "animdel" + string(current_time));
            array_delete(_s.anims[anim_sel].frames, anim_slot, 1);
        }
    }
    _st = BTN_DANGER;
    if (_nf == 0) { _st = BTN_GHOST; }
    if (ui_button("anim_clear", _bx_cl, _ky, _bw_cl, 32, "Clear", "Clear animation|Removes every frame of this animation, so it borrows from the others again (with nothing left, the actor shows its own sprite). You can Undo this.", _st))
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
    if (_dirs_on) { _fhelp = "Turn round missing directions|When the joystick directions have frames: an empty left-side direction (W, NW, SW) uses its right-side partner turned round, and the other way about - draw one side and get both."; }
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
    // the bank of sprites (frames), or the library of animations ready to drag onto a slot
    var _ltw = floor((_fw - 6) / 2);
    if (ui_tab("anim_lib_tab_0", _fx, _oy, _ltw, 30, "Sprites", anim_lib_tab == 0, "Sprites|The sprite bank: click a sprite to put it in the selected frame.")) { anim_lib_tab = 0; }
    if (ui_tab("anim_lib_tab_1", _fx + _ltw + 6, _oy, _ltw, 30, "Animations", anim_lib_tab == 1, "Animation library|Every animation your actors already have, playing live. Drag one onto a joystick slot (or Walk, In air, Falling) to copy it there.")) { anim_lib_tab = 1; }
    _oy += 38;
    if (anim_lib_tab == 1)
    {
        anim_library_draw(_rx2, _fx, _fw, _oy, _x2, _y2, _alloc);
        anim_drag_update();
        return;
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
                else if (array_length(_cur) < lim_frames())
                {
                    anim_begin_edit(_s, "animadd" + string(current_time));
                    array_push(_s.anims[anim_sel].frames, b);
                    anim_click_added = true;
                    anim_slot = min(array_length(_s.anims[anim_sel].frames), lim_frames() - 1);
                }
                else
                {
                    lim_toast("An animation has up to " + string(lim_frames()) + " frames", "up to " + string(ANIM_FRAMES));
                }
            }
        }
    }
    ui_scroll_end("anim_bank", _rx2 + 6, _gtop, _x2 - 6, _y2 - 8, _gcontent);
    anim_drag_update();
}

/// The animation library: every animation with frames of its own, of every actor,
/// playing live. Press one and drag it onto a joystick slot to copy it there.
function anim_library_draw(_rx2, _fx, _fw, _oy, _x2, _y2, _alloc)
{
    var _short = anim_names();
    var _lnames = anim_long_names();
    var _items = [];
    for (var a = 0; a < array_length(proj.actors); a++)
    {
        var _ac = proj.actors[a];
        for (var k = 0; k < ANIM_COUNT; k++)
        {
            if (array_length(_ac.anims[k].frames) > 0) { array_push(_items, [a, k]); }
        }
    }
    if (array_length(_items) == 0)
    {
        ui_text_wrap(_fx, _oy + 10, "No animations yet - give an actor some frames and they show up here, ready to drag onto other slots and actors.", global.TH.text_dim, _fw, global.f_small, 1);
        return;
    }
    var _gcols = 3;
    var _gcell = floor((_fw - (_gcols - 1) * 8) / _gcols);
    var _gh = _gcell + 30;
    var _gtop = _oy;
    var _gcontent = ceil(array_length(_items) / _gcols) * (_gh + 8) + 8;
    var _goff = ui_scroll_begin("anim_lib", _rx2 + 6, _gtop, _x2 - 6, _y2 - 8, _gcontent);
    for (var i = 0; i < array_length(_items); i++)
    {
        var _ai = _items[i][0];
        var _ak = _items[i][1];
        var _ac2 = proj.actors[_ai];
        var _an = _ac2.anims[_ak];
        var _gx = _fx + (i mod _gcols) * (_gcell + 8);
        var _gy = _gtop + 4 + (i div _gcols) * (_gh + 8) - _goff;
        if (_gy < _gtop - _gh || _gy > _y2) { continue; }
        var _lid = "anim_lib_" + string(i);
        var _label = _ac2.name + " " + _short[_ak];
        if (_ak >= ANIM_FIRE0 + 1) { _label = _ac2.name + " Fire " + _short[_ak]; }
        var _hot = ui_register(_lid, _gx, _gy, _gx + _gcell, _gy + _gh, _ac2.name + ": " + _lnames[_ak] + "|" + string(array_length(_an.frames)) + " frames. Drag it onto a joystick slot - of this actor or another - to copy it there (you can Undo).");
        var _cols = actor_cols_from(_alloc, _ai);
        var _bg = pal_col(0);
        ui_rrect(_gx, _gy, _gx + _gcell, _gy + _gcell, 8, _bg, _bg, 1);
        anim_strip_preview(_an.frames, _an.rate, _an.mode, false, _gx, _gy, _gcell, _cols, 1);
        var _ea = 0.35;
        if (_hot) { _ea = 1; }
        ui_rrect_line(_gx, _gy, _gx + _gcell, _gy + _gcell, 8, global.TH.accent, _ea, 1);
        ui_text(_gx + _gcell / 2, _gy + _gcell + 4, ui_text_fit(_label, global.f_small, _gcell + 6), global.TH.text_dim, fa_center, fa_top, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            ui_take_click();
            anim_drag_arm(_an.frames, _an.rate, _an.mode, false, _cols, _label, -1);
        }
    }
    ui_scroll_end("anim_lib", _rx2 + 6, _gtop, _x2 - 6, _y2 - 8, _gcontent);
}

/// Dragging an animation: starts once the mouse moves a few pixels, draws it playing
/// under the mouse, and drops it on the slot it is let go over
function anim_drag_update()
{
    if (!anim_drag_armed) { return; }
    if (ui_held && !anim_drag_on && point_distance(ui_mx, ui_my, anim_drag_x0, anim_drag_y0) > 6) { anim_drag_on = true; }
    if (anim_drag_on)
    {
        var _gw = 64;
        var _gx = ui_mx + 12;
        var _gy = ui_my + 12;
        ui_rrect(_gx, _gy, _gx + _gw, _gy + _gw, 8, pal_col(0), pal_col(0), 0.9);
        anim_strip_preview(anim_drag_frames, anim_drag_rate, anim_drag_mode, anim_drag_flip, _gx, _gy, _gw, anim_drag_cols, 1);
        ui_rrect_line(_gx, _gy, _gx + _gw, _gy + _gw, 8, global.TH.accent, 1, 2);
        ui_text(_gx, _gy + _gw + 4, anim_drag_label, global.TH.text, fa_left, fa_top, global.f_small, 1);
    }
    if (!ui_held)
    {
        if (anim_drag_on && anim_drop_k >= 0 && array_length(proj.actors) > 0)
        {
            anim_drop_into(proj.actors[sel_actor], anim_drop_k, anim_drag_frames, anim_drag_rate, anim_drag_mode);
        }
        anim_drag_armed = false;
        anim_drag_on = false;
    }
}
