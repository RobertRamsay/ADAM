/// ADAM - Actors workspace (cast + stage) and hardware sprite channel allocation

function actor_names()
{
    var _n = [];
    for (var i = 0; i < array_length(proj.actors); i++) { array_push(_n, proj.actors[i].name); }
    if (array_length(_n) == 0) { array_push(_n, "(no actors yet)"); }
    return _n;
}

/// Names for sprite drop-downs: the bank, or all 128 when a Pro project opened in
/// ADAM Lite uses sprites past the Lite bank (those are marked Pro)
function sprite_names()
{
    var _n = [];
    var _count = spr_bank_size();
    if (_count < SPR_COUNT && spr_used_past(_count)) { _count = SPR_COUNT; }
    for (var i = 0; i < _count; i++)
    {
        var _nm = string(i + 1) + ": " + proj.sprites[i].name;
        if (i >= spr_bank_size()) { _nm += "  (Pro)"; }
        array_push(_n, _nm);
    }
    return _n;
}

/// True when an actor uses a sprite slot at or past _n (as its sprite, second frame or a frame)
function spr_used_past(_n)
{
    for (var a = 0; a < array_length(proj.actors); a++)
    {
        var _ac = proj.actors[a];
        if (_ac.sprite >= _n || _ac.anim_sprite >= _n) { return true; }
        for (var k = 0; k < array_length(_ac.anims); k++)
        {
            var _fr = _ac.anims[k].frames;
            for (var f = 0; f < array_length(_fr); f++)
            {
                if (_fr[f] >= _n) { return true; }
            }
        }
    }
    return false;
}

/// Colour key of a sprite design as the machine shows it
function sprite_colour_key(_si)
{
    var _c = proj.sprites[clamp(_si, 0, SPR_COUNT - 1)].cols;
    return string(rgb_machine(_c[0])) + "," + string(rgb_machine(_c[1])) + "," + string(rgb_machine(_c[2]));
}

#macro ACT_MAX_SPR 8        // the Amiga's hardware sprites
#macro ACT_MAX_TILE 7       // a tile world: the scrolling display's early fetch (DDFSTRT $30) takes sprite 7's DMA
#macro ACT_MAX_ALL 32       // actors the engine can run (MAX_ACT in engine.s) - the rest are BOBs, ADAM Pro

// Blitter time per BOB per bitplane each frame: the cookie-cut (24 lines x 2
// words, 4 cycles a word) plus the wipe (2 cycles a word) = 288 DMA cycles.
#macro BOB_CYCLES_PER_PLANE 288

/// How many BOBs machine _m can draw every frame (50 a second) at _depth
/// bitplanes. A PAL frame has about 70,000 bus cycles; the A500/600 leaves
/// the blitter about 30,000 after the bitplanes and the game, the A1200
/// (64-bit bitplane fetch, faster CPU) about 45,000. Tested: 23 BOBs run
/// smoothly on an A600 at 16 colours and an A1200 at 128.
function bobs_max(_m, _depth)
{
    var _budget = 30000;
    if (_m.aga) { _budget = 45000; }
    return floor(_budget / (BOB_CYCLES_PER_PLANE * max(1, _depth)));
}

/// [width, height] actor _ac takes up on screen: its sprite's size when it is
/// a BOB (ADAM Pro), otherwise a 16 x 24 hardware sprite
function actor_dims(_ac)
{
    var _s = proj.sprites[clamp(_ac.sprite, 0, SPR_COUNT - 1)];
    if (pro_on() && (_ac.bob || spr_is_big(_s))) { return [min(_s.w, lim_spr_w()), min(_s.h, lim_spr_h())]; }   // Lite cuts big ones to 32 x 32
    return [SPR_W, SPR_H];
}

/// Blitter time of this project's BOBs, counted in 16 x 24 BOBs (a 32 x 32
/// one counts as 2, a 64 x 64 one as about 6.7): each costs height x (width
/// in words + 1) words x 6 cycles per plane
function bobs_load()
{
    var _bob = actors_bob_flags();
    var _cyc = 0;
    for (var i = 0; i < array_length(_bob); i++)
    {
        if (_bob[i])
        {
            var _s = proj.sprites[clamp(proj.actors[i].sprite, 0, SPR_COUNT - 1)];
            _cyc += min(_s.h, lim_spr_h()) * (min(_s.w, lim_spr_w()) div 16 + 1) * 6;
        }
    }
    return _cyc / BOB_CYCLES_PER_PLANE;
}

/// How many actors go on the disk: up to 12 in ADAM Lite, 32 in ADAM Pro
function actors_on_disk()
{
    if (proj.tiles_on) { return min(ACT_MAX_TILE, array_length(proj.actors)); }    // tile world: hardware sprites only, not sprite 7
    return min(lim_actors(), array_length(proj.actors));
}

/// For each actor on the disk, true when it is drawn as a BOB (blitter object)
/// instead of a hardware sprite. In ADAM Pro that is every actor set to BOB,
/// plus any sprite actor after the 8th. ADAM Lite has no BOBs.
function actors_bob_flags()
{
    var _n = actors_on_disk();
    var _out = array_create(_n, false);
    if (!pro_on() || proj.tiles_on) { return _out; }
    var _spr = 0;
    for (var i = 0; i < _n; i++)
    {
        if (proj.actors[i].bob || _spr >= ACT_MAX_SPR || spr_is_big(proj.sprites[clamp(proj.actors[i].sprite, 0, SPR_COUNT - 1)]))
        {
            _out[i] = true;
        }
        else
        {
            _spr += 1;
        }
    }
    return _out;
}

/// The Amiga's 8 sprites are 4 pairs and each pair shares one set of 3 colours.
/// Puts actors whose colours match on the same pair. Returns
/// { chan[], conflict[], pair_cols[4] }; chan is -1 for a BOB.
function actors_alloc_channels()
{
    var _na = actors_on_disk();
    var _bob = actors_bob_flags();
    var _chan = array_create(_na, -1);
    var _conf = array_create(_na, false);
    var _key = ["", "", "", ""];
    var _used = [0, 0, 0, 0];
    var _owner = [-1, -1, -1, -1];
    var _cap = [2, 2, 2, 2];             // actors per colour pair
    if (proj.tiles_on) { _cap[3] = 1; }  // a tile world loses sprite 7 (the second of pair 3)
    for (var i = 0; i < _na; i++)
    {
        if (_bob[i]) { continue; }
        var _k = sprite_colour_key(proj.actors[i].sprite);
        var _p = -1;
        for (var a = 0; a < 4; a++)
        {
            if (_p < 0 && _used[a] == 1 && _cap[a] > 1 && _key[a] == _k) { _p = a; }
        }
        for (var b = 0; b < 4; b++)
        {
            if (_p < 0 && _used[b] == 0) { _p = b; }
        }
        for (var c = 0; c < 4; c++)
        {
            if (_p < 0 && _used[c] < _cap[c]) { _p = c; _conf[i] = true; }
        }
        if (_used[_p] == 0)
        {
            _key[_p] = _k;
            _owner[_p] = i;
        }
        _chan[i] = _p * 2 + _used[_p];
        _used[_p] += 1;
    }
    var _pc = [];
    for (var q = 0; q < 4; q++)
    {
        if (_owner[q] >= 0) { array_push(_pc, proj.sprites[proj.actors[_owner[q]].sprite].cols); }
        else { array_push(_pc, [0, 0, 0]); }
    }
    return { chan : _chan, conflict : _conf, pair_cols : _pc };
}

/// The colours actor _i will really have on the Amiga
function actor_shown_cols(_i)
{
    return actor_cols_from(actors_alloc_channels(), _i);
}

function ws_actors_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 240;
    var _rw = 320;
    var _na = array_length(proj.actors);
    sel_actor = clamp(sel_actor, 0, max(0, _na - 1));
    var _alloc = actors_alloc_channels();
    var _amax = lim_actors();

    // ---------------- cast list ----------------
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "Cast  (" + string(_na) + " / " + string(_amax) + ")");
    var _ly = _y1 + 54;
    var _rowh = 58;
    var _by = _y2 - 130;
    var _lcontent = _na * _rowh + 8;
    var _loff = ui_scroll_begin("act_list", _x1 + 6, _y1 + 50, _x1 + _lw - 6, _by - 8, _lcontent);
    var _role_short = ["Player", "Bouncer", "Patrol L-R", "Patrol U-D", "Chaser", "Still", "Platform player", "Hopper", "Faller"];
    for (var i = 0; i < _na; i++)
    {
        var _ac = proj.actors[i];
        var _ry = _ly + i * _rowh - _loff;
        if (_ry < _y1 - _rowh || _ry > _by) { continue; }
        var _id = "act_slot_" + string(i);
        var _hot = ui_register(_id, _x1 + 10, _ry, _x1 + _lw - 10, _ry + _rowh - 6, _ac.name + "|Click to select this actor and change its settings on the right.");
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
        var _ts = proj.sprites[clamp(_ac.sprite, 0, SPR_COUNT - 1)];
        var _tsc = min(1, SPR_H / max(_ts.w, _ts.h));
        draw_sprite_amiga_cols(_ac.sprite, _x1 + 33 - _ts.w * _tsc / 2, _ry + 7 + (SPR_H - _ts.h * _tsc) / 2, _tsc, actor_cols_from(_alloc, i), 1);
        ui_text(_x1 + 60, _ry + 16, ui_text_fit(_ac.name, global.f_bold, _lw - 84), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        var _sub = _role_short[clamp(_ac.role, 0, 8)];
        var _subc = global.TH.text_dim;
        if (i < array_length(_alloc.conflict))
        {
            // "Platform player  -  colours shared!" (227 px) never fitted the 160 px here: the warning gets the line
            if (_alloc.conflict[i])
            {
                _sub = "Colours shared!";
                _subc = global.TH.warn;
            }
            if (_alloc.chan[i] < 0) { _sub += "  -  BOB"; }
        }
        ui_text(_x1 + 60, _ry + 35, ui_text_fit(_sub, global.f_small, _lw - 80), _subc, fa_left, fa_middle, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            sel_actor = i;
            ui_take_click();
        }
    }
    ui_scroll_end("act_list", _x1 + 6, _y1 + 50, _x1 + _lw - 6, _by - 8, _lcontent);
    var _bw = _lw - 32;
    var _st = BTN_ACCENT;
    if (_na >= _amax) { _st = BTN_GHOST; }
    var _addhelp = "Add actor|Adds a new actor, up to " + string(_amax) + ". The first 8 can be hardware sprites; the rest are BOBs, drawn by the blitter. New actors start in the middle of the screen.";
    if (!pro_edition()) { _addhelp += " (ADAM Lite: 12 - the 8 hardware sprites, the rest BOBs; ADAM Pro: up to " + string(ACT_MAX_ALL) + ".)"; }
    if (ui_button("act_add", _x1 + 16, _by, _bw, 34, "Add actor", _addhelp, _st))
    {
        if (_na < _amax)
        {
            undo_mark("actadd" + string(current_time));
            var _n = actor_new("Actor " + string(_na + 1));
            _n.sprite = min(_na, SPR_COUNT - 1);
            if (_na == 0) { _n.role = 0; _n.name = "Player"; }
            array_push(proj.actors, _n);
            sel_actor = _na;
        }
        else
        {
            lim_toast("A game has up to " + string(_amax) + " actors", "up to " + string(ACT_MAX_ALL));
        }
    }
    if (ui_button("act_dup", _x1 + 16, _by + 42, _bw, 34, "Duplicate", "Duplicate|Makes a copy of the selected actor, slightly to the side.", BTN_NORMAL))
    {
        if (_na > 0 && _na < _amax)
        {
            undo_mark("actdup" + string(current_time));
            var _cp = struct_overlay(actor_new(""), json_parse(json_stringify(proj.actors[sel_actor])));
            _cp.name = _cp.name + " 2";
            _cp.x = min(world_w() - actor_dims(_cp)[0], _cp.x + 30);
            array_push(proj.actors, _cp);
            sel_actor = _na;
        }
    }
    if (ui_button("act_del", _x1 + 16, _by + 84, _bw, 34, "Remove", "Remove actor|Deletes the selected actor. Rules that used it will point at the first actor instead. You can Undo this.", BTN_DANGER))
    {
        if (_na > 0)
        {
            undo_mark("actdel" + string(current_time));
            actor_remove(sel_actor);
            sel_actor = max(0, sel_actor - 1);
            _na = array_length(proj.actors);
            _alloc = actors_alloc_channels();
        }
    }

    // ---------------- stage ----------------
    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;
    ui_panel(_cx1, _y1, _cx2, _y2, "");
    var _scale = min((_cx2 - _cx1 - 32) / BD_W, (_y2 - _y1 - 70) / BD_H);
    if (_scale >= 2) { _scale = floor(_scale); }
    var _fw = BD_W * _scale;
    var _fh = BD_H * _scale;
    var _fx = floor((_cx1 + _cx2 - _fw) / 2);
    var _fy = floor((_y1 + _y2 - _fh) / 2) - 10;
    ui_rrect(_fx - 6, _fy - 6, _fx + _fw + 6, _fy + _fh + 6, 10, c_black, c_black, 0.35);
    // tile world: the stage is a screen of the map, round the selected actor
    var _ox = 0;
    var _oy = 0;
    if (proj.tiles_on)
    {
        if (!act_drag && _na > 0)
        {
            act_camx = clamp(proj.actors[sel_actor].x + 8 - BD_W div 2, 0, world_w() - BD_W);
            act_camy = clamp(proj.actors[sel_actor].y + 12 - 136, 0, world_h() - BD_H);
        }
        _ox = act_camx;
        _oy = act_camy;
        tile_map_draw(_fx, _fy, _ox, _oy, BD_W, BD_H, _scale);
    }
    else
    {
        backdrop_draw(_fx, _fy, _scale);
        terrain_draw(_fx, _fy, _scale);
    }
    // the ground line that walkers, hoppers and fallers stand on
    if (!proj.tiles_on && current_time - ground_cache_time > 400)
    {
        ground_cache = ground_table_cached(proj);
        var _lh = level_heights_shown();
        if (!is_undefined(_lh)) { ground_cache = _lh; }
        ground_cache_time = current_time;
    }
    var _gtab = ground_cache;
    draw_set_alpha(0.55);
    for (var gl = 0; gl < BD_W - 1 && !proj.tiles_on; gl++)
    {
        if (_gtab[gl] < 256 && _gtab[gl + 1] < 256 && (gl div 3) mod 2 == 0)
        {
            draw_line_width_colour(_fx + gl * _scale, _fy + _gtab[gl] * _scale, _fx + (gl + 1) * _scale, _fy + _gtab[gl + 1] * _scale, 2, global.TH.warn, global.TH.warn);
        }
    }
    draw_set_alpha(1);

    var _sthelp = "Stage|Drag actors to set where they start. Hidden actors are drawn faded.";
    if (proj.tiles_on) { _sthelp = "Stage|A screen of the tile world round the selected actor: drag actors to set where they start. To place them anywhere on the map, use the Map on the Tiles page."; }
    ui_register("act_stage", _fx, _fy, _fx + _fw, _fy + _fh, _sthelp);
    var _hover = -1;
    if (ui_hit(_fx, _fy, _fx + _fw, _fy + _fh))
    {
        for (var h = _na - 1; h >= 0; h--)
        {
            var _hx = _fx + (proj.actors[h].x - _ox) * _scale;
            var _hy = _fy + (proj.actors[h].y - _oy) * _scale;
            var _hd = actor_dims(proj.actors[h]);
            if (point_in_rectangle(ui_mx, ui_my, _hx, _hy, _hx + _hd[0] * _scale, _hy + _hd[1] * _scale))
            {
                _hover = h;
                break;
            }
        }
    }
    if (_hover >= 0 && ui_pressed)
    {
        sel_actor = _hover;
        act_drag = true;
        act_drag_dx = ui_mx - (_fx + (proj.actors[_hover].x - _ox) * _scale);
        act_drag_dy = ui_my - (_fy + (proj.actors[_hover].y - _oy) * _scale);
        undo_mark("actdrag" + string(current_time));
        ui_take_click();
    }
    if (!ui_held) { act_drag = false; }
    if (act_drag && _na > 0)
    {
        var _ad = proj.actors[sel_actor];
        var _dd = actor_dims(_ad);
        _ad.x = clamp(round((ui_mx - act_drag_dx - _fx) / _scale) + _ox, 0, world_w() - _dd[0]);
        _ad.y = clamp(round((ui_my - act_drag_dy - _fy) / _scale) + _oy, 0, world_h() - _dd[1]);
        proj_dirty = true;
    }
    // draw back to front: lower channels are in front on the Amiga
    for (var d = _na - 1; d >= 0; d--)
    {
        var _ac2 = proj.actors[d];
        var _dx = _fx + (_ac2.x - _ox) * _scale;
        var _dy = _fy + (_ac2.y - _oy) * _scale;
        if (_dx < _fx - SPR_W * _scale || _dy < _fy - SPR_H * _scale || _dx > _fx + _fw || _dy > _fy + _fh) { continue; }
        var _alpha = 1;
        if (!_ac2.visible) { _alpha = 0.4; }
        var _frame_spr = actor_preview_sprite(_ac2);
        draw_sprite_amiga_cols(_frame_spr, _dx, _dy, _scale, actor_cols_from(_alloc, d), _alpha);
    }
    for (var d2 = 0; d2 < _na; d2++)
    {
        var _ac3 = proj.actors[d2];
        var _ex = _fx + (_ac3.x - _ox) * _scale;
        var _ey = _fy + (_ac3.y - _oy) * _scale;
        if (_ex < _fx - SPR_W * _scale || _ey < _fy - SPR_H * _scale || _ex > _fx + _fw || _ey > _fy + _fh) { continue; }
        var _ed = actor_dims(_ac3);
        if (d2 == sel_actor)
        {
            ui_rrect_line(_ex - 4, _ey - 4, _ex + _ed[0] * _scale + 4, _ey + _ed[1] * _scale + 4, 6, global.TH.accent, 1, 2);
            ui_text(_ex, _ey - 8, _ac3.name, c_white, fa_left, fa_bottom, global.f_small, 1);
        }
        else
        {
            if (d2 == _hover)
            {
                ui_rrect_line(_ex - 3, _ey - 3, _ex + _ed[0] * _scale + 3, _ey + _ed[1] * _scale + 3, 6, c_white, 0.7, 1);
                ui_help_title = _ac3.name;
                ui_help_body = "Drag to move where this actor starts.";
            }
        }
    }
    if (act_drag && _na > 0)
    {
        var _ag = proj.actors[sel_actor];
        var _agd = actor_dims(_ag);
        var _gx = _fx + (_ag.x - _ox + _agd[0] div 2) * _scale;
        var _gy = _fy + (_ag.y - _oy + _agd[1] div 2) * _scale;
        ui_dotted_line(_fx, _gy, _fx + _fw, _gy, global.TH.warn, 0.7, 5);
        ui_dotted_line(_gx, _fy, _gx, _fy + _fh, global.TH.warn, 0.7, 5);
        var _txt = "X " + string(_ag.x) + "   Y " + string(_ag.y);
        draw_set_font(global.f_small);
        var _tw = ui_sw(_txt) + 20;
        ui_rrect(_gx + 14, _gy + 14, _gx + 14 + _tw, _gy + 38, 10, global.TH.btn_top, global.TH.btn_bot, 0.95);
        ui_text(_gx + 24, _gy + 26, _txt, global.TH.warn, fa_left, fa_middle, global.f_small, 1);
    }
    ui_text((_cx1 + _cx2) / 2, _fy + _fh + 22, "Drag actors to place them. Behaviour, speed and picture are on the right.", global.TH.text_faint, fa_center, fa_middle, global.f_small, 1);

    // ---------------- properties ----------------
    var _px = _x2 - _rw;
    ui_panel(_px, _y1, _x2, _y2, "Actor settings");
    var _fx2 = _px + 20;
    var _fw2 = _rw - 40;
    if (_na == 0)
    {
        ui_text_wrap(_fx2, _y1 + 60, "No actors yet. Press 'Add actor' to create your player. The first actor you add is set up as the player for you.", global.TH.text_dim, _fw2, global.f_body, 1);
        return;
    }
    var _s = proj.actors[sel_actor];
    // scrolls when the window is too short for every setting (last frame's height, kept in ui_scroll)
    var _sy1 = _y1 + 46;
    var _sy2 = _y2 - 6;
    var _sh = ds_map_find_value(ui_scroll, "act_props_h");
    if (is_undefined(_sh)) { _sh = 0; }
    var _soff = ui_scroll_begin("act_props", _px + 4, _sy1, _x2 - 4, _sy2, _sh);
    var _y = _y1 + 56 - _soff;
    ui_heading(_fx2, _y, "Name");
    set_val(_s, "name", ui_textfield("act_name", _fx2, _y + 18, _fw2, 32, _s.name, 20, "Actor name|Used in the Logic page so your rules read nicely, e.g. 'Hero touches Ghost'."), "actname");
    _y += 62;
    ui_heading(_fx2, _y, "Sprite");
    set_val(_s, "sprite", ui_dropdown("act_sprite", _fx2, _y + 18, _fw2, 32, sprite_names(), _s.sprite, "Sprite|Which picture this actor uses. Draw them on the Sprites page. The picture's colours come with it."), "actsprite");
    _y += 62;
    ui_heading(_fx2, _y, "Behaviour");
    set_val(_s, "role", ui_dropdown("act_role", _fx2, _y + 18, _fw2, 32, global.ROLE_NAMES, _s.role, "Behaviour|How this actor moves on its own. Pick 'Player' for the one the joystick controls."), "actrole");
    _y += 58;
    var _rdesc = [
        "Moves with a joystick in port 2. Stops at the edges of the screen.",
        "Moves diagonally and bounces off every edge like a ball.",
        "Moves left and right, turning around at the screen edges.",
        "Moves up and down, turning around at the top and bottom.",
        "Always heads towards the player. Speed 1 is gentle, 3 is scary!",
        "Stays where you put it. Great for pickups, doors and goals.",
        "Walks left and right on the ground and jumps with fire (or up). Follows the hills - set your ground colours on the Backdrop page.",
        "Hops along the ground on its own: it squats, springs up and drifts left or right in the air. Jump over it or run under it. Give it a second sprite and that one is shown while it squats.",
        "Falls until it lands on the ground, then stays there. Use 'Move actor to another actor' to drop it from a cloud."
    ];
    var _desc = _rdesc[clamp(_s.role, 0, 8)];
    draw_set_font(global.f_small);
    var _dh = max(50, ceil(ui_sh_ext(_desc, _fw2 - 20)) + 14);
    ui_rrect(_fx2, _y, _fx2 + _fw2, _y + _dh, 8, global.TH.inset_top, global.TH.inset_bot, 0.8);
    ui_text_wrap(_fx2 + 10, _y + 7, _desc, global.TH.text_dim, _fw2 - 20, global.f_small, 1);
    _y += _dh + 12;
    var _half = floor((_fw2 - 12) / 2);
    ui_heading(_fx2, _y, "Speed");
    set_val(_s, "speed", ui_stepper("act_speed", _fx2, _y + 18, _half, _s.speed, 1, 8, "Speed|Pixels moved every frame (50 frames per second). 1 is slow, 8 is very fast."), "actspeed");
    ui_heading(_fx2 + _half + 12, _y, "Visible at start");
    set_val(_s, "visible", ui_toggle("act_vis", _fx2 + _half + 12, _y + 22, "Shown", _s.visible, "Visible at start|Hidden actors can be shown later with the 'Show actor' action in Logic."), "actvis");
    _y += 62;
    if (_s.role == 1 || _s.role == 2)
    {
        set_val(_s, "start_left", ui_toggle("act_left", _fx2, _y, "Starts moving left", _s.start_left, "Start direction|Whether this actor starts heading left instead of right."), "actleft");
        _y += 32;
    }
    if (_s.role == 1 || _s.role == 3)
    {
        set_val(_s, "start_up", ui_toggle("act_up", _fx2, _y, "Starts moving up", _s.start_up, "Start direction|Whether this actor starts heading up instead of down."), "actup");
        _y += 32;
    }
    _y += 6;
    var _sd = actor_dims(_s);
    ui_heading(_fx2, _y, "Start X");
    set_val(_s, "x", ui_stepper("act_x", _fx2, _y + 18, _half, _s.x, 0, world_w() - _sd[0], "Start X|Horizontal start position in pixels (0 = left edge, " + string(world_w() - _sd[0]) + " = right edge). Hold Shift for steps of 10."), "actx");
    ui_heading(_fx2 + _half + 12, _y, "Start Y");
    set_val(_s, "y", ui_stepper("act_y", _fx2 + _half + 12, _y + 18, _half, _s.y, 0, world_h() - _sd[1], "Start Y|Vertical start position (0 = top, " + string(world_h() - _sd[1]) + " = bottom). Hold Shift for steps of 10."), "acty");
    _y += 66;

    // levels
    if (proj.levels_on)
    {
        ui_heading(_fx2, _y, "Joins on level");
        set_val(_s, "from_level", ui_stepper("act_from", _fx2, _y + 18, _half, _s.from_level, 1, LEVEL_MAX, "Joins on level|The first level this actor appears on - add an extra enemy every level."), "actfrom");
        ui_heading(_fx2 + _half + 12, _y, "+1 speed every");
        set_val(_s, "faster_every", ui_stepper("act_fast", _fx2 + _half + 12, _y + 18, _half, _s.faster_every, 0, LEVEL_MAX, "Faster on later levels|0 = never. 3 = one step faster on levels 4, 7 and 10."), "actfast");
        _y += 62;
    }

    // animations made on the Animate page replace the two-frame animation
    if (anims_used(_s))
    {
        var _nfr = 0;
        for (var ae = 0; ae < ANIM_COUNT; ae++) { _nfr += array_length(_s.anims[ae].frames); }
        ui_heading(_fx2, _y, "Animation");
        ui_text(_fx2, _y + 26, ui_text_fit(string(_nfr) + " frames on the Animate page", global.f_body, _fw2), global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
        if (ui_button("act_goanim", _fx2, _y + 42, _fw2, 32, "Open the Animate page", "Animate page|Idle, walk, jump and fall animations (4 frames each in ADAM Lite, 8 in ADAM Pro), for this actor.", BTN_NORMAL))
        {
            ws_set(WS_ANIMATE);
        }
        _y += 84;
    }
    // two-frame animation
    else
    {
        ui_heading(_fx2, _y, "Animation (second frame)");
        var _anames = ["(none - one frame)"];
        var _sn = sprite_names();
        for (var an = 0; an < array_length(_sn); an++) { array_push(_anames, _sn[an]); }
        var _na2 = ui_dropdown("act_anim", _fx2, _y + 18, _fw2, 32, _anames, _s.anim_sprite + 1, "Animation|Pick a second sprite and the actor flips between the two - a walk cycle, flapping wings or a twinkle. Use the same colours as the first frame (copy and paste on the Sprites page, then change a few pixels).") - 1;
        set_val(_s, "anim_sprite", _na2, "actanim");
        _y += 58;
        if (_s.anim_sprite >= 0)
        {
            ui_heading(_fx2, _y, "Frames each");
            set_val(_s, "anim_rate", ui_stepper("act_arate", _fx2, _y + 18, _half, _s.anim_rate, 2, 30, "Animation speed|How many 50ths of a second each frame stays on screen. 6 is a brisk walk, 15 a slow blink."), "actarate");
            _y += 58;
            set_val(_s, "anim_moving", ui_toggle("act_amove", _fx2, _y, "Only when moving", _s.anim_moving, "Only when moving|The actor shows its first frame while standing still - perfect for walk cycles."), "actamove");
            _y += 34;
        }
    }

    // sprite or BOB (ADAM Pro)
    var _boblabel = "Draw as a BOB";
    if (!pro_on()) { _boblabel = "Draw as a BOB  (Pro)"; }
    var _bobv = ui_toggle("act_bob", _fx2, _y, _boblabel, _s.bob && pro_on(), "Draw as a BOB|A BOB (blitter object) is drawn into the backdrop by the Amiga's blitter instead of being a hardware sprite. BOBs use the nearest backdrop colours and do not take one of the 8 sprites, so a game can have up to 32 actors. Actors after the 8th sprite become BOBs anyway. Part of ADAM Pro.");
    if (_bobv != (_s.bob && pro_on()))
    {
        if (feature_gate("BOBs")) { set_val(_s, "bob", _bobv, "actbob"); }
    }
    _y += 34;
    if (_s.role != 0 && _s.role != 6)
    {
        set_val(_s, "carry", ui_toggle("act_carry", _fx2, _y, "Can be carried", _s.carry, "Can be carried|The player picks it up by touching it and pressing fire - it rides on the player's head - and fire again throws it the way the player faces, in an arc. Make rules with WHEN 'Thrown actor hits actor' (knock out an enemy, break a box) and 'Player picks up actor'. A rock, a barrel, a bomb, a key."), "actcarry");
        _y += 34;
    }
    var _yend = _y;

    // hardware sprite channel
    var _hw = false;
    var _isbob = false;
    if (sel_actor < array_length(_alloc.chan))
    {
        if (_alloc.chan[sel_actor] >= 0) { _hw = true; }
        else { _isbob = true; }
    }
    if (_isbob)
    {
        ui_heading(_fx2, _y, "Amiga BOB");
        var _bmsg = "Drawn by the blitter in the nearest backdrop colours (shown on the stage).";
        if (!_s.bob)
        {
            if (spr_is_big(proj.sprites[clamp(_s.sprite, 0, SPR_COUNT - 1)])) { _bmsg = "Its sprite is bigger than a hardware sprite (16 x 24), so this actor is drawn as a BOB by the blitter, in the nearest backdrop colours."; }
            else { _bmsg = "All 8 hardware sprites are taken, so this actor is drawn as a BOB by the blitter, in the nearest backdrop colours."; }
        }
        draw_set_font(global.f_small);
        var _bh = max(48, ceil(ui_sh_ext(_bmsg, _fw2 - 20)) + 14);
        ui_rrect(_fx2, _y + 18, _fx2 + _fw2, _y + 18 + _bh, 8, global.TH.inset_top, global.TH.inset_bot, 0.8);
        ui_text_wrap(_fx2 + 10, _y + 24, _bmsg, global.TH.text_dim, _fw2 - 20, global.f_small, 1);
        _yend = _y + 18 + _bh;
    }
    if (_hw)
    {
        var _ch = _alloc.chan[sel_actor];
        ui_heading(_fx2, _y, "Amiga hardware sprite");
        var _msg = "Sprite " + string(_ch) + " (colour pair " + string(_ch div 2) + "). ";
        var _kind = 0;
        if (_alloc.conflict[sel_actor])
        {
            _msg += "All 4 colour pairs are taken, so this actor has to borrow its partner's colours. Give it the same colours as another actor to fix this.";
            _kind = 1;
        }
        else
        {
            _msg += "ADAM puts actors with matching colours on the same pair automatically.";
        }
        draw_set_font(global.f_small);
        var _mh = max(64, ceil(ui_sh_ext(_msg, _fw2 - 20)) + 14);
        ui_rrect(_fx2, _y + 18, _fx2 + _fw2, _y + 18 + _mh, 8, global.TH.inset_top, global.TH.inset_bot, 0.8);
        var _mc = global.TH.text_dim;
        if (_kind == 1) { _mc = global.TH.warn; }
        ui_text_wrap(_fx2 + 10, _y + 24, _msg, _mc, _fw2 - 20, global.f_small, 1);
        _yend = _y + 18 + _mh;
    }
    ds_map_replace(ui_scroll, "act_props_h", _yend + _soff - _sy1 + 12);
    ui_scroll_end("act_props", _px + 4, _sy1, _x2 - 4, _sy2, _sh);
}

/// Colours for actor _i from an allocation result
function actor_cols_from(_alloc, _i)
{
    if (_i >= array_length(_alloc.chan)) { return proj.sprites[proj.actors[_i].sprite].cols; }
    if (_alloc.chan[_i] < 0) { return actor_bob_cols(_i); }
    return _alloc.pair_cols[_alloc.chan[_i] div 2];
}

/// The backdrop colours a BOB actor's 3 sprite colours become (as adam_data_block maps them)
function actor_bob_cols(_i)
{
    var _ncol = 1 << clamp(proj.depth, 1, machine_cur().max_depth);
    var _sc = proj.sprites[clamp(proj.actors[_i].sprite, 0, SPR_COUNT - 1)].cols;
    var _out = [];
    for (var c = 0; c < 3; c++)
    {
        array_push(_out, proj.pal[pal_nearest(proj, _sc[c], _ncol)]);
    }
    return _out;
}
