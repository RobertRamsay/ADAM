/// ADAM - turns the project into a bootable Amiga disk (.ADF)
///
/// ADAM never writes code. The fixed 68000 engine (datafiles/engine/engine.bin,
/// source in engine.s) reads a game data block that is appended straight after
/// it. The bootblock (boot.bin) loads engine + data into chip RAM and runs it.
/// The data block layout is documented at the top of engine.s.

#macro ADF_SIZE 901120
#macro ADF_HDR 116
#macro D2_TRACK 5632            // disk 2: songs start on a track (11 sectors of 512)
#macro D2_RAW_BYTES 12800       // engine.s RAW_WORDS x 2: the raw track buffer
#macro ADF_SONGS_MAX 4
#macro RULES_DISK_MAX 128       // rules (cards) on the disk (engine.s RULES_MAX); each AND DO line adds 8 bytes
#macro OS_RESERVE_KB 160
// Original A500s have only 512KB of chip RAM. Even with a trapdoor slow-RAM card
// the engine, data and screens must all be in chip RAM, so the usable budget is
// 512KB minus the same OS_RESERVE_KB (Kickstart, trackdisk buffers, strap
// display, the boot copper list) = about 352KB. ADAM targets 1MB, so a bigger
// game only gets a warning; on a 512KB A500 the bootblock shows a red screen.
#macro A500_512K_CHIP_KB 512

function be16(_b, _v)
{
    var _w = floor(_v) & 0xffff;
    buffer_write(_b, buffer_u8, (_w >> 8) & 255);
    buffer_write(_b, buffer_u8, _w & 255);
}

function be32(_b, _v)
{
    var _l = floor(_v) & 0xffffffff;
    buffer_write(_b, buffer_u8, (_l >> 24) & 255);
    buffer_write(_b, buffer_u8, (_l >> 16) & 255);
    buffer_write(_b, buffer_u8, (_l >> 8) & 255);
    buffer_write(_b, buffer_u8, _l & 255);
}

function poke16(_b, _o, _v)
{
    var _w = floor(_v) & 0xffff;
    buffer_poke(_b, _o, buffer_u8, (_w >> 8) & 255);
    buffer_poke(_b, _o + 1, buffer_u8, _w & 255);
}

function poke32(_b, _o, _v)
{
    var _l = floor(_v) & 0xffffffff;
    buffer_poke(_b, _o, buffer_u8, (_l >> 24) & 255);
    buffer_poke(_b, _o + 1, buffer_u8, (_l >> 16) & 255);
    buffer_poke(_b, _o + 2, buffer_u8, (_l >> 8) & 255);
    buffer_poke(_b, _o + 3, buffer_u8, _l & 255);
}

function peek32(_b, _o)
{
    return (buffer_peek(_b, _o, buffer_u8) << 24) | (buffer_peek(_b, _o + 1, buffer_u8) << 16) | (buffer_peek(_b, _o + 2, buffer_u8) << 8) | buffer_peek(_b, _o + 3, buffer_u8);
}

function buf_align(_b, _n)
{
    while ((buffer_tell(_b) mod _n) != 0) { buffer_write(_b, buffer_u8, 0); }
}

function buf_zeros(_b, _n)
{
    var _l = _n div 4;
    for (var i = 0; i < _l; i++) { buffer_write(_b, buffer_u32, 0); }
    for (var k = 0; k < (_n mod 4); k++) { buffer_write(_b, buffer_u8, 0); }
}

/// Text in a fixed-size, zero-padded field (upper case, font characters only)
/// A DO line on the disk: act, target, value (6 bytes) - a rule's DO or one of its AND DO lines
function adf_do_line(_b, _d, _ncol, _nsnd)
{
    var _val = _d.value;
    if (_d.act == 8) { _val = clamp(_val, 0, _ncol - 1); }
    if (_d.act == 2) { _val = clamp(_val, 0, _nsnd - 1); }
    if (_d.act == 18) { _val = clamp(_val, 0, ADF_SONGS_MAX - 1); }
    if (do_value_is_item(_d.act)) { _val = clamp(_val, 0, max(0, array_length(proj.items) - 1)); }
    if (_d.act == 30) { _val = clamp(_val, 0, max(0, array_length(proj.recipes) - 1)); }
    be16(_b, clamp(_d.act, 0, 31));
    if (_d.act == 27) { be16(_b, clamp(_d.target, 0, 250)); }       // Switch palette: fade frames
    else if (_d.act == 28 || _d.act == 29) { be16(_b, clamp(_d.target, 1, ITEM_CARRY_MAX)); }   // Give / Take an item: how many
    else if (_d.act > 29) { be16(_b, 0); }
    else { be16(_b, clamp(_d.target, 0, ACT_MAX_ALL - 1)); }
    be16(_b, clamp(_val, 0, 65535));
}

/// The IF lines of rule _r as the engine reads them (after its AND DO lines, 8 bytes each:
/// act = IF_LINE + cond, target = n, value = item, 0)
function adf_if_lines(_b, _r)
{
    var _ni = max(1, array_length(proj.items));
    for (var f = 0; f < min(array_length(_r.ifs), RULE_IFS_MAX); f++)
    {
        var _fl = _r.ifs[f];
        be16(_b, 0x8000 | clamp(_fl.cond, 0, 3));
        be16(_b, clamp(_fl.n, 1, ITEM_CARRY_MAX));
        be16(_b, clamp(_fl.item, 0, _ni - 1));
        be16(_b, 0);
    }
}

/// Which sounds go on the disk: those a written rule (DO or AND DO line) or a
/// dug tile plays. ADAM Lite plays only its first lim_sounds() (the rest are silent).
function sfx_used_on_disk(_p, _rules)
{
    var _n = clamp(array_length(_p.sfx), 1, SFX_MAX);
    var _used = array_create(_n, false);
    for (var r = 0; r < array_length(_rules); r++)
    {
        var _ru = _rules[r];
        if (_ru.act == 2) { _used[clamp(_ru.value, 0, _n - 1)] = true; }
        for (var m = 0; m < min(array_length(_ru.more), RULE_DOS_MAX - 1); m++)
        {
            if (_ru.more[m].act == 2) { _used[clamp(_ru.more[m].value, 0, _n - 1)] = true; }
        }
    }
    if (_p.tiles_on)
    {
        for (var t = 0; t < array_length(_p.tiles); t++)
        {
            if (_p.tiles[t].sound >= 0) { _used[clamp(_p.tiles[t].sound, 0, _n - 1)] = true; }
        }
    }
    for (var k = lim_sounds(); k < _n; k++) { _used[k] = false; }
    return _used;
}

function buf_fixed_text(_b, _s, _n)
{
    var _t = string_upper(string_copy(_s, 1, _n - 1));
    for (var i = 1; i <= _n; i++)
    {
        var _c = 0;
        if (i <= string_length(_t))
        {
            _c = ord(string_char_at(_t, i));
            if (_c < 32 || _c > 95) { _c = 32; }
        }
        buffer_write(_b, buffer_u8, _c);
    }
}

/// Upper-case ASCII the engine font can draw, zero terminated
function buf_text(_b, _s)
{
    var _t = string_upper(string_copy(_s, 1, 36));
    for (var i = 1; i <= string_length(_t); i++)
    {
        var _c = ord(string_char_at(_t, i));
        if (_c < 32 || _c > 95) { _c = 32; }
        buffer_write(_b, buffer_u8, _c);
    }
    buffer_write(_b, buffer_u8, 0);
}

/// Ground height per column (first ground-colour pixel from the top, 256 = none)
function ground_table(_p)
{
    var _out = array_create(BD_W, 256);
    for (var gx = 0; gx < BD_W; gx++)
    {
        for (var gy = 0; gy < BD_H; gy++)
        {
            if (_p.solid[_p.pixels[gy * BD_W + gx]] != 0)
            {
                _out[gx] = gy;
                break;
            }
        }
    }
    return _out;
}

/// Ground table for previews: all 256 (no line) when no colour is ground
function ground_table_cached(_p)
{
    for (var sc = 0; sc < PAL_MAX; sc++)
    {
        if (_p.solid[sc] != 0) { return ground_table(_p); }
    }
    return array_create(BD_W, 256);
}

/// Writes one hardware sprite block (POS, CTL, 24 lines x 2 words, end) from sprite
/// struct _s (its top-left 16 x 24 pixels). Returns its offset.
function adf_sprite_block(_b, _s)
{
    buf_align(_b, 8);
    var _o = buffer_tell(_b);
    be32(_b, 0);
    for (var sy = 0; sy < SPR_H; sy++)
    {
        var _w0 = 0;
        var _w1 = 0;
        for (var sx = 0; sx < SPR_W; sx++)
        {
            var _sv = spr_get(_s, sx, sy);
            if ((_sv & 1) != 0) { _w0 = _w0 | (0x8000 >> sx); }
            if ((_sv & 2) != 0) { _w1 = _w1 | (0x8000 >> sx); }
        }
        be16(_b, _w0);
        be16(_b, _w1);
    }
    be32(_b, 0);
    return _o;
}

/// Backdrop colour nearest to _rgb (never colour 0, the sky / background)
function pal_nearest(_p, _rgb, _ncol)
{
    var _best = 1;
    var _bd = -1;
    var _r = (_rgb >> 16) & 255;
    var _g = (_rgb >> 8) & 255;
    var _bl = _rgb & 255;
    for (var c = 1; c < _ncol; c++)
    {
        var _q = _p.pal[c];
        var _dr = ((_q >> 16) & 255) - _r;
        var _dg = ((_q >> 8) & 255) - _g;
        var _db = (_q & 255) - _bl;
        var _d = _dr * _dr * 3 + _dg * _dg * 4 + _db * _db * 2;
        if (_bd < 0 || _d < _bd)
        {
            _bd = _d;
            _best = c;
        }
    }
    return _best;
}

/// Writes one BOB image (engine.s A_BSIZE) of sprite struct _s, _bw x _bh
/// pixels (cropped or padded to that): a BI_* header, _bw/16 x _bh mask words, then _depth
/// planes the same size. Sprite pixel 1-3 becomes backdrop colour _map[0-2]. Returns its offset.
function adf_bob_image(_b, _s, _bw, _bh, _map, _depth)
{
    buf_align(_b, 8);
    var _o = buffer_tell(_b);
    var _nw = _bw div 16;
    // header (version 14): the rows and word columns with pixels, the rightmost pixel from
    // the left of the first of those words, the planes empty / solid under the mask
    // (= adf_reference.py bimg); bob_draw only blits that part
    var _x0 = _bw;
    var _x1 = -1;
    var _y0 = _bh;
    var _y1 = -1;
    var _zero = (1 << _depth) - 1;
    var _full = (1 << _depth) - 1;
    for (var hy = 0; hy < _bh; hy++)
    {
        for (var hx = 0; hx < _bw; hx++)
        {
            var _hv = spr_get(_s, hx, hy);
            if (_hv != 0)
            {
                _x0 = min(_x0, hx);
                _x1 = max(_x1, hx);
                _y0 = min(_y0, hy);
                _y1 = max(_y1, hy);
                for (var hp = 0; hp < _depth; hp++)
                {
                    if (((_map[_hv - 1] >> hp) & 1) != 0)
                    {
                        _zero = _zero & ~(1 << hp);
                    }
                    else
                    {
                        _full = _full & ~(1 << hp);
                    }
                }
            }
        }
    }
    if (_x1 < 0)
    {
        be16(_b, 0); be16(_b, 0); be16(_b, 0); be16(_b, 0);
        be16(_b, 0); be16(_b, (1 << _depth) - 1); be16(_b, 0); be16(_b, 0);
    }
    else
    {
        var _wx = _x0 div 16;
        be16(_b, _y0);                   // BI_Y0
        be16(_b, _y1 - _y0 + 1);         // BI_NH
        be16(_b, _wx);                   // BI_WX
        be16(_b, (_x1 div 16) - _wx + 1); // BI_NW
        be16(_b, _x1 - _wx * 16);        // BI_LAST
        be16(_b, _zero);                 // BI_ZERO
        be16(_b, _full);                 // BI_FULL
        be16(_b, 0);
    }
    for (var my = 0; my < _bh; my++)
    {
        for (var mw = 0; mw < _nw; mw++)
        {
            var _m = 0;
            for (var mx = 0; mx < 16; mx++)
            {
                if (spr_get(_s, mw * 16 + mx, my) != 0) { _m = _m | (0x8000 >> mx); }
            }
            be16(_b, _m);
        }
    }
    for (var pl = 0; pl < _depth; pl++)
    {
        for (var py = 0; py < _bh; py++)
        {
            for (var pw = 0; pw < _nw; pw++)
            {
                var _w = 0;
                for (var px = 0; px < 16; px++)
                {
                    var _v = spr_get(_s, pw * 16 + px, py);
                    if (_v != 0)
                    {
                        if (((_map[_v - 1] >> pl) & 1) != 0) { _w = _w | (0x8000 >> px); }
                    }
                }
                be16(_b, _w);
            }
        }
    }
    return _o;
}

/// One picture of an actor: a hardware sprite block, or a BOB image of size _bsz
function adf_actor_image(_b, _s, _isbob, _bsz, _map, _depth)
{
    if (_isbob) { return adf_bob_image(_b, _s, _bsz[0], _bsz[1], _map, _depth); }
    return adf_sprite_block(_b, _s);
}

/// A copy of sprite _s turned to face the other way (for actors that face left)
function spr_flipped(_s)
{
    var _c = { name : _s.name, w : _s.w, h : _s.h, px : array_create(_s.w * _s.h, 0), cols : _s.cols };
    for (var py = 0; py < _s.h; py++)
    {
        for (var px = 0; px < _s.w; px++)
        {
            _c.px[py * _s.w + px] = _s.px[py * _s.w + (_s.w - 1 - px)];
        }
    }
    return _c;
}

/// [width, height] in pixels that actor _a is drawn at as a BOB: its sprite's size
function adf_bob_dims(_p, _a)
{
    var _s = _p.sprites[clamp(_p.actors[_a].sprite, 0, SPR_COUNT - 1)];
    return [_s.w, _s.h];
}

/// Builds the game data block. Returns { buf, size, warnings[], sound_bytes, plane_bytes }.
/// _measure = true only sizes it (the memory bar): the backdrop planes are left blank.
/// The game data block for project _p. ADAM Lite writes a copy trimmed to its
/// limits (lite_trim): the project itself is not changed.
/// _two: put the level songs on disk 2 even when the project does not ask (it does not fit)
function adam_data_block(_p, _measure = false, _two = false)
{
    var _lwarn = [];
    var _q = _p;
    if (!pro_edition()) { _q = lite_trim(_p, _lwarn); }
    _q = disk_expand(_q);
    _q.d2_on = (_p.disk2_music || _two);
    var _keep = proj;
    proj = _q;                      // the helpers (actors_on_disk, anim_plan ...) read proj
    var _r = undefined;
    try
    {
        _r = adam_data_block_raw(_q, _measure);
    }
    catch (_err)
    {
        proj = _keep;
        throw _err;
    }
    proj = _keep;
    for (var i = 0; i < array_length(_lwarn); i++) { array_push(_r.warnings, _lwarn[i]); }
    return _r;
}

/// Actor _i of the project -> its first actor on the disk (0 when it is not on the disk)
function disk_actor(_first, _i)
{
    if (_i >= 0 && _i < array_length(_first) && _first[_i] >= 0) { return _first[_i]; }
    return 0;
}

/// A DO line (a rule or an AND DO line) naming disk actors
function disk_do_line(_d, _first)
{
    var _o = struct_overlay({}, _d);
    if (do_target_is_actor(_d.act)) { _o.target = disk_actor(_first, _d.target); }
    if (do_value_is_actor(_d.act)) { _o.value = disk_actor(_first, _d.value); }
    return _o;
}

/// The project as the disk sees it (as disk_project in gen_examples.py): each actor, then
/// its copies (Actors page 'Copies'), as many as go on the disk. A run of shots with the
/// same aim and speed, or of effects with the same sprite, are copies of the first of the
/// run too (rapid fire, several explosions at once). Copies after the first, and actors a
/// spawner sends out, start hidden. Rules name disk actors (a rule names an actor and all
/// its copies). Returns a shallow copy of _p: .actors / .rules replaced (each actor with
/// disk_type = the disk actor of the first of its copies, disk_fire = the shot it fires),
/// .disk_first[i] = actor i's first disk actor (-1 = not on the disk), .src_actors = _p.actors
function disk_expand(_p)
{
    var _q = struct_overlay({}, _p);
    var _lim = lim_actors();
    if (_p.tiles_on) { _lim = ACT_MAX_TILE; }
    var _acts = _p.actors;
    var _out = [];                  // [actor, type] for each disk actor
    var _first = [];
    for (var i = 0; i < array_length(_acts); i++)
    {
        var _a = _acts[i];
        var _head = array_length(_out);
        if (_head >= _lim)
        {
            array_push(_first, -1);
            continue;
        }
        var _typ = _head;
        if (i > 0 && _first[i - 1] >= 0)
        {
            var _b = _acts[i - 1];
            var _shots = (_a.role == 9 && _b.role == 9 && _a.aim == _b.aim && _a.speed == _b.speed);
            var _fx = (_a.role == 12 && _b.role == 12 && _a.sprite == _b.sprite);
            if (_shots || _fx) { _typ = _out[_first[i - 1]][1]; }
        }
        array_push(_first, _head);
        var _nc = clamp(_a.copies, 1, COPIES_MAX);
        for (var k = 0; k < _nc; k++)
        {
            if (array_length(_out) >= _lim) { break; }
            array_push(_out, [i, _typ]);
        }
    }
    var _spawned = array_create(array_length(_acts), false);
    if (_p.shmup_map && !_p.tiles_on)
    {
        for (var s = 0; s < array_length(_p.spawners); s++)
        {
            var _sa = _p.spawners[s].act;
            if (_sa >= 0 && _sa < array_length(_acts)) { _spawned[_sa] = true; }
        }
    }
    var _dacts = [];
    for (var d = 0; d < array_length(_out); d++)
    {
        var _ai = _out[d][0];
        var _ac = struct_overlay({}, _acts[_ai]);
        if (d > _first[_ai] || _spawned[_ai]) { _ac.visible = false; }     // copies wait for a spawner / Shoot / Spawn
        _ac.disk_type = _out[d][1];
        _ac.disk_fire = -1;
        var _f = _acts[_ai].fire;
        if (_f >= 0 && _f < array_length(_first) && _first[_f] >= 0) { _ac.disk_fire = _first[_f]; }
        array_push(_dacts, _ac);
    }
    var _rules = [];
    for (var r = 0; r < array_length(_p.rules); r++)
    {
        var _ru = _p.rules[r];
        var _r2 = disk_do_line(_ru, _first);
        _r2.a = disk_actor(_first, _ru.a);
        _r2.b = disk_actor(_first, _ru.b);
        var _mo = [];
        for (var m = 0; m < array_length(_ru.more); m++) { array_push(_mo, disk_do_line(_ru.more[m], _first)); }
        _r2.more = _mo;
        array_push(_rules, _r2);
    }
    _q.actors = _dacts;
    _q.rules = _rules;
    _q.disk_first = _first;
    _q.src_actors = _acts;
    return _q;
}

/// The shoot 'em up map's spawners as the engine reads them (engine.s SP_*, as
/// spawner_records in gen_examples.py), in the order they go off: from the bottom of the
/// map up. _p is a disk_expand project. Each: { trig (the view's top line when it goes
/// off), x, y (where on the screen they come in), act (disk actor), n, gap, pat (0xff =
/// the actor's own), edge, dx }
function adf_spawner_records(_p)
{
    var _first = _p.disk_first;
    var _src = _p.src_actors;
    var _rows = _p.map_h;
    var _recs = [];
    for (var n = 0; n < array_length(_p.spawners); n++)
    {
        var _s = _p.spawners[n];
        var _ai = _s.act;
        if (_ai < 0 || _ai >= array_length(_first) || _first[_ai] < 0) { continue; }
        var _a = _src[_ai];
        var _sp = _p.sprites[clamp(_a.sprite, 0, SPR_COUNT - 1)];
        var _w = SPR_W;
        var _h = SPR_H;
        if (_a.bob || _sp.w > SPR_W || _sp.h > SPR_H)
        {
            _w = _sp.w;
            _h = _sp.h;
        }
        var _pat = _s.pattern;
        var _pp = _pat;
        if (_pat < 0) { _pp = _a.pattern; }
        var _edge = _s.edge & 3;
        var _trig = _s.y;
        var _sx = _p.map_w * 16;        // the right edge of the play area
        var _sy = _s.at;
        if (_pp == 4)
        {
            _trig = _s.y + _h;          // it sits on the map: it comes in at the top when the view gets there
            _sx = _s.x;
            _sy = -_h;
        }
        else if (_edge == 0)
        {
            _sx = _s.x;
            _sy = -_h;
        }
        else if (_edge == 2)
        {
            _sx = _s.x;
            _sy = 256;
        }
        else if (_edge == 3)
        {
            _sx = -_w;
        }
        var _pt = 0xff;
        if (_pat >= 0) { _pt = clamp(_pat, 0, 5); }
        array_push(_recs, { trig : clamp(_trig, 0, _rows * 16), idx : n, x : _sx, y : _sy, act : _first[_ai],
                            n : clamp(_s.n, 1, COPIES_MAX), gap : clamp(_s.gap, 0, 250), pat : _pt, edge : _edge, dx : _s.dx });
    }
    array_sort(_recs, function(_ea, _eb)
    {
        if (_ea.trig != _eb.trig) { return _eb.trig - _ea.trig; }
        return _ea.idx - _eb.idx;
    });
    return _recs;
}

/// A shoot 'em up map goes on the disk: tiles of 16, an even 12 to 20 across, a screen high
/// at least (else the backdrop scrolls, with a warning)
function shmup_map_disk(_p)
{
    return scroll_on_disk(_p) && _p.shmup_map && _p.tile_size == 16 && shmup_cols_ok(_p.map_w) && _p.map_h >= BD_H div 16;
}

function adam_data_block_raw(_p, _measure = false)
{
    var _warn = [];
    var _m = machine_get(_p.machine);
    var _depth = clamp(_p.depth, 1, _m.max_depth);
    var _ww = BD_W;                       // where actors can be: the screen, the tile map, or a
    var _wh = BD_H;                       // shoot 'em up map's play area
    if (_p.tiles_on)
    {
        _ww = _p.map_w * _p.tile_size;
        _wh = _p.map_h * _p.tile_size;
    }
    else if (shmup_map_disk(_p))
    {
        _ww = _p.map_w * 16;
    }
    var _ncol = 1 << _depth;
    var _acts = _p.actors;
    var _na = actors_on_disk();
    var _bob = actors_bob_flags();
    var _anybob = false;
    for (var bq = 0; bq < _na; bq++)
    {
        if (_bob[bq]) { _anybob = true; }
    }
    var _rules = [];
    var _rcut = false;
    var _ritems = 0;
    for (var ru = 0; ru < array_length(_p.rules); ru++)
    {
        var _rr = _p.rules[ru];
        var _off_grp = group_off_in(_p.groups, _rr.group);     // its group, or a group that is inside, is off
        if (_off_grp) { continue; }
        if (rule_uses_items(_rr) && array_length(_p.items) == 0)     // items it names do not exist
        {
            _ritems += 1;
            continue;
        }
        if (array_length(_rules) >= RULES_DISK_MAX)
        {
            _rcut = true;
            break;
        }
        array_push(_rules, _rr);
    }
    var _nr = array_length(_rules);
    var _nsnd = clamp(array_length(_p.sfx), 1, SFX_MAX);
    var _snd_used = sfx_used_on_disk(_p, _rules);
    var _b = buffer_create(262144, buffer_grow, 1);
    buf_zeros(_b, ADF_HDR);
    buf_align(_b, 8);

    // palette
    var _off_pal = buffer_tell(_b);
    for (var c = 0; c < _ncol; c++) { be32(_b, rgb_machine(_p.pal[c])); }
    buf_align(_b, 8);

    // backdrop bitplanes (pristine copy)
    var _off_planes = buffer_tell(_b);
    if (_measure) { buf_zeros(_b, _depth * 10240); }
    for (var pl = 0; pl < _depth && !_measure; pl++)
    {
        for (var _iy = 0; _iy < BD_H; _iy++)
        {
            var _row = _iy * BD_W;
            for (var xb = 0; xb < 40; xb++)
            {
                var _v = 0;
                var _base = _row + xb * 8;
                for (var bit = 0; bit < 8; bit++)
                {
                    if (((_p.pixels[_base + bit] >> pl) & 1) != 0) { _v = _v | (128 >> bit); }
                }
                buffer_write(_b, buffer_u8, _v);
            }
        }
    }
    buf_align(_b, 8);

    // hardware sprite blocks per actor (a hopper's crouch frame too); BOBs get
    // BOB images in the nearest backdrop colours instead. Then every frame of
    // its animations, once per sprite slot (and once more turned round when it
    // faces left), and the animation tables (engine.s AN_*).
    var _spr_off = array_create(_na, 0);
    var _spr2_off = array_create(_na, 0);
    var _anim_off = array_create(_na, 0);
    var _plans = array_create(_na, undefined);
    var _imgs = array_create(_na, undefined);
    for (var a = 0; a < _na; a++)
    {
        var _si = clamp(_acts[a].sprite, 0, SPR_COUNT - 1);
        var _ai = _acts[a].anim_sprite;
        var _map = [0, 0, 0];
        var _bsz = [SPR_W, SPR_H];
        if (_bob[a])
        {
            var _scol = _p.sprites[_si].cols;
            _map = [pal_nearest(_p, _scol[0], _ncol), pal_nearest(_p, _scol[1], _ncol), pal_nearest(_p, _scol[2], _ncol)];
            _bsz = adf_bob_dims(_p, a);
        }
        _spr_off[a] = adf_actor_image(_b, _p.sprites[_si], _bob[a], _bsz, _map, _depth);
        if (_acts[a].role == 7 && _ai >= 0 && _ai < SPR_COUNT)
        {
            _spr2_off[a] = adf_actor_image(_b, _p.sprites[_ai], _bob[a], _bsz, _map, _depth);
        }
        var _plan = anim_plan(_acts[a]);
        _plans[a] = _plan;
        if (!is_undefined(_plan))
        {
            // images made so far, by sprite slot: [as drawn, turned round] (-1 = not made yet)
            var _made = {};
            _made[$ string(_si)] = [_spr_off[a], -1];
            var _dirs = anims_dirs_on(_acts[a]);
            for (var e = 0; e < array_length(_plan); e++)
            {
                var _fr = _plan[e].frames;
                for (var f = 0; f < array_length(_fr); f++)
                {
                    var _fs = clamp(_fr[f], 0, SPR_COUNT - 1);
                    var _key = string(_fs);
                    var _got = _made[$ _key];
                    if (is_undefined(_got)) { _got = [-1, -1]; }
                    // which ways round it is needed: as the entry says, and turned
                    // the other way too when it faces left (not with 8 directions)
                    var _need0 = !_plan[e].flip;
                    var _need1 = _plan[e].flip;
                    if (_acts[a].anim_flip && !_dirs && (e < ANIM_BASIC || e == ANIM_FIRE0 || e >= anim_plan_main_len(_acts[a], _plan)))
                    {
                        _need0 = true;
                        _need1 = true;
                    }
                    var _o0 = _got[0];
                    var _o1 = _got[1];
                    if (_need0 && _o0 < 0) { _o0 = adf_actor_image(_b, _p.sprites[_fs], _bob[a], _bsz, _map, _depth); }
                    if (_need1 && _o1 < 0) { _o1 = adf_actor_image(_b, spr_flipped(_p.sprites[_fs]), _bob[a], _bsz, _map, _depth); }
                    _made[$ _key] = [_o0, _o1];
                }
            }
            _imgs[a] = _made;
        }
    }
    buf_align(_b, 8);
    for (var a3 = 0; a3 < _na; a3++)
    {
        var _pl = _plans[a3];
        if (is_undefined(_pl)) { continue; }
        buf_align(_b, 8);
        _anim_off[a3] = buffer_tell(_b);
        var _dirs2 = anims_dirs_on(_acts[a3]);
        for (var e2 = 0; e2 < array_length(_pl); e2++)
        {
            var _fr2 = _pl[e2].frames;
            var _nf = min(ANIM_FRAMES, array_length(_fr2));
            be16(_b, _nf);
            be16(_b, _pl[e2].rate);
            be16(_b, _pl[e2].mode);
            be16(_b, 0);
            for (var side = 0; side < 2; side++)
            {
                // right: as the entry says; left: turned the other way when it faces
                // left (8 directions and Fire + a direction bake any turning into the entries instead;
                // Fire on its own turns round like Idle)
                var _way = 0;
                if (_pl[e2].flip) { _way = 1; }
                if (side == 1 && _acts[a3].anim_flip && !_dirs2 && (e2 < ANIM_BASIC || e2 == ANIM_FIRE0 || e2 >= anim_plan_main_len(_acts[a3], _pl))) { _way = 1 - _way; }
                for (var k = 0; k < ANIM_FRAMES; k++)
                {
                    var _fi = 0;
                    if (k < _nf) { _fi = k; }
                    var _im = _imgs[a3][$ string(clamp(_fr2[_fi], 0, SPR_COUNT - 1))];
                    be32(_b, _im[_way]);
                }
            }
        }
    }
    buf_align(_b, 8);

    // actor records
    var _alloc = actors_alloc_channels();
    var _off_act = buffer_tell(_b);
    var _player = -1;
    for (var a2 = 0; a2 < _na; a2++)
    {
        var _ac = _acts[a2];
        if ((_ac.role == 0 || _ac.role == 6) && _player < 0) { _player = a2; }
        var _s2 = _p.sprites[clamp(_ac.sprite, 0, SPR_COUNT - 1)];
        var _aw = SPR_W;                 // size on screen: 16 x 24 for a sprite
        var _ah = SPR_H;
        var _bsize = 0;
        if (_bob[a2])
        {
            var _bd = adf_bob_dims(_p, a2);
            _aw = _bd[0];
            _ah = _bd[1];
            _bsize = (_ah << 6) | (_aw div 16 + 1);
        }
        else if (spr_is_big(_s2))
        {
            array_push(_warn, "Actor '" + _ac.name + "' uses a sprite bigger than 16 x 24 - as a hardware sprite only its top-left 16 x 24 shows.");
        }
        var _bx0 = 99;
        var _by0 = 99;
        var _bx1 = -1;
        var _by1 = -1;
        for (var qy = 0; qy < _ah; qy++)
        {
            for (var qx = 0; qx < _aw; qx++)
            {
                if (spr_get(_s2, qx, qy) != 0)
                {
                    _bx0 = min(_bx0, qx);
                    _bx1 = max(_bx1, qx);
                    _by0 = min(_by0, qy);
                    _by1 = max(_by1, qy);
                }
            }
        }
        if (_bx1 < 0)
        {
            _bx0 = 0; _by0 = 0; _bx1 = _aw - 1; _by1 = _ah - 1;
            array_push(_warn, "Actor '" + _ac.name + "' uses an empty sprite - it will be invisible.");
        }
        var _vis = 0;
        if (_ac.visible) { _vis = 1; }
        var _left = 0;
        if (_ac.start_left) { _left = 1; }
        var _up = 0;
        if (_ac.start_up) { _up = 1; }
        if (_ac.role == 9) { _up = clamp(_ac.aim, 0, 6); }    // A_UP of a shot = its aim (6 = homing missile)
        be16(_b, clamp(_ac.x, 0, _ww - _aw));     // tile world: anywhere on the map
        be16(_b, clamp(_ac.y, 0, _wh - _ah));
        be16(_b, clamp(_ac.role, 0, 12));
        be16(_b, clamp(_ac.speed, 1, 8));
        be16(_b, _vis);
        be16(_b, _left);
        be16(_b, _up);
        be16(_b, _bx0);
        be16(_b, _by0);
        be16(_b, _bx1);
        be16(_b, _by1);
        be32(_b, _spr_off[a2]);
        be16(_b, max(0, _alloc.chan[a2]));
        be32(_b, _spr2_off[a2]);
        var _carry = 0;                  // A_CARRY: the player can pick it up and throw it
        if (_ac.carry) { _carry = 1; }
        be16(_b, _carry);
        var _am = 0;                     // A_AMODE: bit 0 = 8 directions, bit 1 = Fire animations, bit 2 = Hit / Die
        if (!is_undefined(_plans[a2]))
        {
            var _nmain = anim_plan_main_len(_ac, _plans[a2]);
            if (anims_dirs_on(_ac) && _nmain >= ANIM_FIRE0) { _am = _am | 1; }
            if (_nmain > ANIM_FIRE0) { _am = _am | 2; }
            if (anims_hd_used(_ac)) { _am = _am | 4; }
        }
        be16(_b, _am);
        be16(_b, clamp(_ac.from_level, 1, LEVEL_MAX));
        be16(_b, clamp(_ac.faster_every, 0, LEVEL_MAX));
        var _isbob = 0;
        if (_bob[a2]) { _isbob = 1; }
        be16(_b, _isbob);                // A_BOB
        be16(_b, _ww - _aw);             // A_XMAX
        be16(_b, _wh - _ah);             // A_YMAX
        be16(_b, _bsize);                // A_BSIZE
        be32(_b, _anim_off[a2]);         // A_ANIM
        // shoot 'em up (version 9): A_PAT, A_ENTER (high byte bit 0 = comes back, low byte =
        // edge 0 top 1 right 2 bottom 3 left), A_HP (hits), A_RANK (an option's place behind the player)
        var _rank = 0;
        if (_ac.role == 11)
        {
            _rank = 1;
            for (var rk = 0; rk < a2; rk++)
            {
                if (_acts[rk].role == 11) { _rank += 1; }
            }
            _rank = min(6, _rank);
        }
        var _ent = clamp(_ac.enter, 0, 3);
        if (_ac.comeback) { _ent = _ent | 0x100; }
        be16(_b, clamp(_ac.pattern, 0, 5));
        be16(_b, _ent);
        be16(_b, clamp(_ac.hits, 1, 99));
        be16(_b, _rank);
        // version 10: A_TYPE (the first of its copies - rules name them all), A_FIRE (the shot it
        // fires by itself, -1 none), A_FRATE (frames between volleys), A_FPAT (how it fires)
        var _fire = _ac.disk_fire;
        if (_fire < 0 || _fire >= _na) { _fire = -1; }
        be16(_b, clamp(_ac.disk_type, 0, _na - 1));
        be16(_b, _fire & 0xffff);
        be16(_b, clamp(_ac.fire_rate, 10, 500));
        be16(_b, clamp(_ac.fire_pat, 0, 4));
        if (_alloc.conflict[a2]) { array_push(_warn, "Actor '" + _ac.name + "' shares a sprite colour pair with different colours - it will borrow its partner's colours."); }
        if (_bob[a2] && !_ac.bob)
        {
            if (spr_is_big(_s2)) { array_push(_warn, "Actor '" + _ac.name + "' is drawn as a BOB - its sprite is bigger than a hardware sprite (16 x 24)."); }
            else { array_push(_warn, "Actor '" + _ac.name + "' is drawn as a BOB - the Amiga has 8 hardware sprites."); }
        }
        if (!pro_on() && _ac.bob) { array_push(_warn, "Actor '" + _ac.name + "' is set to BOB - BOBs are part of ADAM Pro, so it is a sprite here."); }
    }
    buf_align(_b, 8);

    // rules
    var _off_rules = buffer_tell(_b);
    // each rule: 16 bytes (R_*, R_NAND = its AND DO lines), then 8 bytes per AND DO line
    for (var r = 0; r < _nr; r++)
    {
        var _ru = _rules[r];
        var _nand = min(array_length(_ru.more), RULE_DOS_MAX - 1);
        var _nif = min(array_length(_ru.ifs), RULE_IFS_MAX);
        be16(_b, clamp(_ru.when, 0, 18));
        be16(_b, clamp(_ru.a, 0, ACT_MAX_ALL - 1));
        be16(_b, clamp(_ru.b, 0, ACT_MAX_ALL - 1));
        if (_ru.when == 17 || _ru.when == 18) { be16(_b, clamp(_ru.n, 0, max(0, array_length(_p.items) - 1))); }   // the item
        else { be16(_b, clamp(_ru.n, 1, 65535)); }
        adf_do_line(_b, _ru, _ncol, _nsnd);
        be16(_b, _nand + _nif);          // R_NAND: the AND DO lines, then the IF lines
        for (var rm2 = 0; rm2 < _nand; rm2++)
        {
            adf_do_line(_b, _ru.more[rm2], _ncol, _nsnd);
            be16(_b, 0);
        }
        adf_if_lines(_b, _ru);
    }
    buf_align(_b, 8);

    // sprite pair colours
    var _off_sprcol = buffer_tell(_b);
    for (var pr = 0; pr < 4; pr++)
    {
        for (var k = 0; k < 3; k++) { be32(_b, rgb_machine(_alloc.pair_cols[pr][k])); }
    }

    // messages
    var _off_over = buffer_tell(_b);
    buf_text(_b, _p.over_text);
    var _off_win = buffer_tell(_b);
    buf_text(_b, _p.win_text);
    buf_align(_b, 8);

    // sound samples, then their table: one entry per sound (engine play_sfx),
    // but only sounds a rule or a tile plays take chip RAM - the rest are length 0
    var _snd_off = array_create(_nsnd, 0);
    var _snd_len = array_create(_nsnd, 0);
    var _snd_per = array_create(_nsnd, 0);
    var _snd_bytes = 0;
    for (var s = 0; s < _nsnd; s++)
    {
        if (!_snd_used[s]) { continue; }
        buf_align(_b, 8);
        _snd_off[s] = buffer_tell(_b);
        var _r = sfx_render_ex(_p.sfx[s], true);
        var _smp = _r.smp;
        for (var i = 0; i < array_length(_smp); i++) { buffer_write(_b, buffer_s8, _smp[i]); }
        _snd_len[s] = array_length(_smp) div 2;
        _snd_per[s] = _r.period;
        _snd_bytes += array_length(_smp);
    }
    buf_align(_b, 8);
    var _off_sfx = buffer_tell(_b);
    for (var s2 = 0; s2 < _nsnd; s2++)
    {
        be32(_b, _snd_off[s2]);
        be16(_b, _snd_len[s2]);
        be16(_b, _snd_per[s2]);
    }
    buf_align(_b, 8);

    // copper sky: one $0RGB colour per display line; on AGA a second table of
    // the low nibbles follows (the engine writes them with LOCT set)
    var _off_grad = 0;
    if (_p.sky_on)
    {
        _off_grad = buffer_tell(_b);
        var _sky = sky_table(_p);
        for (var g = 0; g < 256; g++) { be16(_b, copper_hi(_sky[g])); }
        if (_m.aga)
        {
            for (var g2 = 0; g2 < 256; g2++) { be16(_b, copper_lo(_sky[g2])); }
        }
        buf_align(_b, 8);
    }

    // ground: for each column, the first pixel from the top in a ground colour
    var _off_ground = 0;
    var _any_solid = false;
    for (var sc = 0; sc < PAL_MAX; sc++)
    {
        if (_p.solid[sc] != 0) { _any_solid = true; }
    }
    if (_any_solid)
    {
        _off_ground = buffer_tell(_b);
        var _gt = ground_table(_p);
        for (var gx = 0; gx < BD_W; gx++) { be16(_b, _gt[gx]); }
        buf_align(_b, 8);
    }

    // game block: levels and their hills, goal counter, title screen
    var _off_game = 0;
    var _lv_on = (_p.levels_on && array_length(_p.levels) > 0);
    if (_lv_on || _p.goal_on || _p.title_on)
    {
        _off_game = buffer_tell(_b);
        var _nlv = 1;
        if (_lv_on) { _nlv = array_length(_p.levels); }
        var _terr = 0;
        if (_lv_on && _p.hills_on) { _terr = 1; }
        var _goal = 0;
        if (_p.goal_on) { _goal = clamp(_p.goal, 1, 99); }
        var _tit = 0;
        if (_p.title_on) { _tit = 1; }
        be16(_b, _nlv);
        be16(_b, _terr);
        for (var tc = 0; tc < 4; tc++) { be16(_b, clamp(_p.terrain_cols[tc], 0, _ncol - 1)); }
        be16(_b, _goal);
        be16(_b, _tit);
        buf_fixed_text(_b, _p.goal_label, 8);
        buf_fixed_text(_b, _p.title1, 40);
        buf_fixed_text(_b, _p.title2, 40);
        buf_fixed_text(_b, _p.lev_text, 16);
        for (var lv = 0; lv < _nlv; lv++)
        {
            for (var hx = 0; hx < BD_W; hx++)
            {
                var _hv = 256;
                if (_lv_on) { _hv = clamp(_p.levels[lv].heights[hx], 100, 240); }
                be16(_b, _hv);
            }
        }
        buf_align(_b, 8);
    }

    // tile world (engine.s T_*): the tile set, its pictures and the map; the
    // map as played and the scrolling picture go in cleared memory after the data
    var _off_tiles = 0;
    var _tile_fix = 0;
    if (_p.tiles_on)
    {
        buf_align(_b, 8);
        _off_tiles = buffer_tell(_b);
        var _nt = array_length(_p.tiles);
        var _ts = _p.tile_size;                         // 8, 16, 32 or 64
        var _tg = tile_geometry(_ts);
        var _wcell = (_nt > 256);                       // more than 256 tile types: map cells are words
        be16(_b, _p.map_w);
        be16(_b, _p.map_h);
        be16(_b, _nt);
        var _tf = 0;
        if (_p.tile_dig) { _tf = 1; }
        if (_wcell) { _tf = _tf | 2; }
        be16(_b, _tf);
        _tile_fix = buffer_tell(_b);
        buf_zeros(_b, 20);              // T_IMG T_MAP T_WMAP T_BUF T_BUFPL, filled in below
        be16(_b, _ts);                  // T_SIZE, T_SHIFT, T_LINE, T_NCOL, T_NROW, 0, T_RING
        be16(_b, _tg.shift);
        be16(_b, _tg.line);
        be16(_b, _tg.ncol);
        be16(_b, _tg.nrow);
        var _ntool = 0;                 // T_NTOOL: the space bar menu (only where the player digs)
        if (_p.tile_dig) { _ntool = min(array_length(_p.tools), TOOL_MAX); }
        be16(_b, _ntool);
        be32(_b, _tg.ring);
        for (var ti = 0; ti < _nt; ti++)
        {
            var _td = _p.tiles[ti];
            var _fl = 0;
            if (_td.solid) { _fl = _fl | 1; }
            if (_td.dig) { _fl = _fl | 2; }
            if (_td.goal) { _fl = _fl | 4; }
            if (_td.ladder) { _fl = _fl | 8; }
            var _snd = 0xff;
            if (_td.sound >= 0) { _snd = clamp(_td.sound, 0, _nsnd - 1); }
            buffer_write(_b, buffer_u8, _fl);
            buffer_write(_b, buffer_u8, _snd);
            be16(_b, clamp(_td.hard, 1, 250));
            be16(_b, clamp(_td.points, 0, 999));
            var _bec = _td.becomes;
            if (_bec < 0 || _bec >= _nt) { _bec = 0; }
            be16(_b, _bec);
        }
        for (var tn = 0; tn < _nt; tn++) { buf_fixed_text(_b, _p.tiles[tn].name, 5); buffer_seek(_b, buffer_seek_relative, -1); }
        for (var tt = 0; tt < _ntool; tt++)             // TL_*: what fire does, its tile, 8 letters
        {
            var _tl = _p.tools[tt];
            var _ttile = _tl.tile;
            if (_ttile < 0 || _ttile >= _nt) { _ttile = 0; }
            var _tact = clamp(_tl.act, 0, 3);
            if (_tact == 3)                             // a weapon: Auto in the flags byte, its reach for the tile
            {
                if (_tl.auto) { _tact = _tact | 0x100; }
                _ttile = clamp(_tl.reach, 4, 64);
            }
            be16(_b, _tact);
            be16(_b, _ttile);
            buf_fixed_text(_b, _tl.name, 9);
            buffer_seek(_b, buffer_seek_relative, -1);
        }
        buf_align(_b, 8);
        var _off_timg = buffer_tell(_b);
        if (_measure) { buf_zeros(_b, _nt * _depth * _ts * _ts div 8); }     // the memory bar only needs the size
        for (var tp = 0; tp < _nt && !_measure; tp++)
        {
            var _tpx = _p.tiles[tp].px;
            for (var pl2 = 0; pl2 < _depth; pl2++)
            {
                for (var ty = 0; ty < _ts; ty++)
                {
                    for (var tb = 0; tb < _ts div 8; tb++)
                    {
                        var _tw = 0;
                        for (var tx = 0; tx < 8; tx++)
                        {
                            if (((_tpx[ty * _ts + tb * 8 + tx] >> pl2) & 1) != 0) { _tw = _tw | (0x80 >> tx); }
                        }
                        buffer_write(_b, buffer_u8, _tw);
                    }
                }
            }
        }
        buf_align(_b, 8);
        var _off_tmap = buffer_tell(_b);
        if (_measure)
        {
            var _cb = 1;
            if (_wcell) { _cb = 2; }
            buf_zeros(_b, _p.map_w * _p.map_h * _cb);
        }
        else if (_wcell)
        {
            for (var mc = 0; mc < _p.map_w * _p.map_h; mc++) { be16(_b, clamp(_p.map[mc], 0, _nt - 1)); }
        }
        else
        {
            for (var mc2 = 0; mc2 < _p.map_w * _p.map_h; mc2++) { buffer_write(_b, buffer_u8, clamp(_p.map[mc2], 0, _nt - 1)); }
        }
        buf_align(_b, 8);
        poke32(_b, _tile_fix, _off_timg);
        poke32(_b, _tile_fix + 4, _off_tmap);
    }

    // custom HUD (ADAM Pro UI page, engine.s UI_*): flags, rows, the fields, the
    // font (when not the built-in one) and the panel picture (the backdrop strip
    // with the frame baked in), depth planes x rows x 8 lines x 40 bytes
    var _off_ui = 0;
    var _u = _p.ui;
    if (_u.on)
    {
        buf_align(_b, 8);
        _off_ui = buffer_tell(_b);
        var _uf = 1;
        if (_u.bottom && !_p.tiles_on && !scroll_on_disk(_p)) { _uf = _uf | 2; }     // a scrolling game: always the top
        // fields on rows the panel has, starting inside the screen (the rest are left out)
        var _ufl = [];
        for (var uq = 0; uq < array_length(_u.fields); uq++)
        {
            if (_u.fields[uq].row < _u.rows && _u.fields[uq].col < 40 && array_length(_ufl) < 16) { array_push(_ufl, _u.fields[uq]); }
        }
        var _unf = array_length(_ufl);
        be16(_b, _uf);
        be16(_b, _u.rows);
        be16(_b, _unf);
        be16(_b, 0);
        var _ufix = buffer_tell(_b);
        buf_zeros(_b, 8);               // UI_FONT, UI_PANEL: filled in below
        for (var uf = 0; uf < _unf; uf++)
        {
            var _fd = _ufl[uf];
            be16(_b, _fd.type);
            be16(_b, _fd.col);
            be16(_b, _fd.row);
            be16(_b, clamp(_fd.colour, 0, _ncol - 1));
            var _shc = -1;
            if (_fd.shadow >= 0) { _shc = clamp(_fd.shadow, 0, _ncol - 1); }
            be16(_b, _shc & 0xffff);
            var _fdig = _fd.digits;
            if (_fd.type == 7) { _fdig = (clamp(_fd.item, 0, ITEM_MAX - 1) << 8) | _fd.digits; }   // item count: the item in the high byte
            be16(_b, _fdig);
            buf_fixed_text(_b, string_upper(string_copy(_fd.label, 1, UI_LABEL_MAX)), 20);
        }
        buf_align(_b, 8);
        var _off_ufont = 0;
        if (_u.font_style != 0)
        {
            _off_ufont = buffer_tell(_b);
            var _fb = ui_font_bytes(_u);
            for (var fb = 0; fb < 512; fb++) { buffer_write(_b, buffer_u8, _fb[fb]); }
            buf_align(_b, 8);
        }
        var _off_upanel = 0;
        if (_u.frame_on)
        {
            _off_upanel = buffer_tell(_b);
            var _pp = ui_panel_pixels(_u, _p.pixels);
            var _uh = _u.rows * 8;
            for (var upl = 0; upl < _depth; upl++)
            {
                for (var uy = 0; uy < _uh; uy++)
                {
                    for (var ubx = 0; ubx < 40; ubx++)
                    {
                        var _ub = 0;
                        for (var uk = 0; uk < 8; uk++)
                        {
                            if (((min(_pp[uy * 320 + ubx * 8 + uk], _ncol - 1) >> upl) & 1) != 0) { _ub = _ub | (0x80 >> uk); }
                        }
                        buffer_write(_b, buffer_u8, _ub);
                    }
                }
            }
            buf_align(_b, 8);
        }
        poke32(_b, _ufix, _off_ufont);
        poke32(_b, _ufix + 4, _off_upanel);
    }

    // music: the songs as ProTracker MODs, played by ptplayer in the engine
    var _mus = adf_music_table(_b, _p, _warn, _rules);
    var _off_music = _mus.off;

    // the backdrop + hills working copy (score text is restored from it)
    var _off_work = buffer_tell(_b);
    buf_zeros(_b, _depth * 10240);
    buf_align(_b, 8);

    // the display bitplanes the game draws into
    var _off_disp = buffer_tell(_b);
    buf_zeros(_b, _depth * 10240);

    // BOBs: a second display (double buffering) and the background they are
    // wiped from. 8 spare bytes after each: a BOB at the bottom right blits
    // one word past the end of its buffer.
    var _off_disp2 = 0;
    var _off_back = 0;
    var _nbuf = 3;
    var _scr = scroll_on_disk(_p);
    if (_anybob && !_scr)               // (a scrolling game keeps its BOBs in the scroll buffers)
    {
        buf_zeros(_b, 8);
        _off_disp2 = buffer_tell(_b);
        buf_zeros(_b, _depth * 10240 + 8);
        _off_back = buffer_tell(_b);
        buf_zeros(_b, _depth * 10240 + 8);
        _nbuf = 5;
    }
    // scrolling backdrop (engine.s SC_*): direction, speed, where its buffers start (cleared
    // memory after the data), how many (3 with BOBs: two shown in turn and the background)
    var _off_scroll = 0;
    var _sc_fix = 0;
    var _sc_nbuf = 1;
    var _shm = _scr && _p.shmup_map;
    if (_shm && !shmup_map_disk(_p))
    {
        array_push(_warn, "A shoot 'em up map needs tiles of 16 x 16 and a map " + string(SHMUP_COLS_MIN) + " to " + string(SHMUP_COLS_MAX) + " tiles across (an even number) and at least 16 high (Tiles page) - the backdrop scrolls instead.");
        _shm = false;
    }
    var _sdir = _p.scroll_dir;
    if (_shm) { _sdir = 1; }            // a shoot 'em up map: the ship flies up it
    if (_scr)
    {
        buf_align(_b, 8);
        _off_scroll = buffer_tell(_b);
        if (_anybob) { _sc_nbuf = 3; }
        be16(_b, _sdir);
        be16(_b, clamp(_p.scroll_speed, 1, 16));
        _sc_fix = buffer_tell(_b);
        be32(_b, 0);                    // SC_BUF, filled in below
        be16(_b, _sc_nbuf);
        be16(_b, 0);
        be32(_b, 0);                    // SC_MAP, filled in below
        buf_align(_b, 8);
    }
    if (_shm)
    {
        // the shoot 'em up map (version 10, engine.s MP_*): map_w x map_h tiles of 16 that the
        // view climbs once - the tile pictures (depth planes x 16 lines x 2 bytes), the cells
        // (words with more than 256 tiles), the spawners (SP_*) in the order they go off. map_w
        // is the play area's width in tiles, centred on the screen
        var _off_map = buffer_tell(_b);
        var _mnt = array_length(_p.tiles);
        var _mword = (_mnt > 256);
        var _sps = adf_spawner_records(_p);
        var _mrows = _p.map_h;
        be16(_b, _mrows);
        be16(_b, _mnt);
        var _mfix = buffer_tell(_b);
        be32(_b, 0);                    // MP_IMG, MP_MAP: filled in below
        be32(_b, 0);
        be16(_b, array_length(_sps));
        if (_mword) { be16(_b, 1); }
        else { be16(_b, 0); }
        be32(_b, 0);                    // MP_SP
        be16(_b, _p.map_w);             // MP_COLS
        be16(_b, 0);
        buf_align(_b, 8);
        var _off_mimg = buffer_tell(_b);
        if (_measure) { buf_zeros(_b, _mnt * _depth * 32); }
        for (var mt = 0; mt < _mnt && !_measure; mt++)
        {
            var _mpx = _p.tiles[mt].px;
            for (var mpl = 0; mpl < _depth; mpl++)
            {
                for (var my = 0; my < 16; my++)
                {
                    var _mw16 = 0;
                    for (var mx = 0; mx < 16; mx++)
                    {
                        if (((_mpx[my * 16 + mx] >> mpl) & 1) != 0) { _mw16 = _mw16 | (0x8000 >> mx); }
                    }
                    be16(_b, _mw16);
                }
            }
        }
        buf_align(_b, 8);
        var _off_mcells = buffer_tell(_b);
        var _mcn = _p.map_w * _mrows;
        if (_measure)
        {
            if (_mword) { buf_zeros(_b, _mcn * 2); }
            else { buf_zeros(_b, _mcn); }
        }
        else
        {
            for (var mc3 = 0; mc3 < _mcn; mc3++)
            {
                var _cv = clamp(_p.map[mc3], 0, _mnt - 1);
                if (_mword) { be16(_b, _cv); }
                else { buffer_write(_b, buffer_u8, _cv); }
            }
        }
        buf_align(_b, 8);
        var _off_msp = buffer_tell(_b);
        for (var se = 0; se < array_length(_sps); se++)
        {
            var _e = _sps[se];
            be16(_b, _e.trig);
            be16(_b, _e.x & 0xffff);
            be16(_b, _e.y & 0xffff);
            be16(_b, _e.act);
            be16(_b, _e.n);
            be16(_b, _e.gap);
            buffer_write(_b, buffer_u8, _e.pat);
            buffer_write(_b, buffer_u8, _e.edge);
            be16(_b, _e.dx & 0xffff);
        }
        buf_align(_b, 8);
        poke32(_b, _mfix, _off_mimg);
        poke32(_b, _mfix + 4, _off_mcells);
        poke32(_b, _mfix + 12, _off_msp);
        poke32(_b, _off_scroll + 12, _off_map);
    }

    // named palettes (version 11): PS_N, the palette each level starts with, then each
    // palette's changed colours { index, 0, $00RRGGBB }
    var _off_pals = 0;
    var _npal = min(array_length(_p.palettes), PALETTE_MAX);
    if (_npal > 0)
    {
        buf_align(_b, 8);
        _off_pals = buffer_tell(_b);
        be16(_b, _npal);
        for (var lpl = 0; lpl < 10; lpl++)
        {
            var _lpv = 0;
            if (lpl < array_length(_p.level_pal)) { _lpv = clamp(_p.level_pal[lpl], 0, _npal); }
            buffer_write(_b, buffer_u8, _lpv);
        }
        var _pfix = buffer_tell(_b);
        for (var pf = 0; pf < _npal; pf++) { be32(_b, 0); }
        for (var pw = 0; pw < _npal; pw++)
        {
            poke32(_b, _pfix + pw * 4, buffer_tell(_b));
            var _pcs = _p.palettes[pw].cols;
            var _pn = min(_ncol, array_length(_pcs));
            var _ne = 0;
            for (var pc = 0; pc < _pn; pc++)
            {
                if (_pcs[pc] >= 0) { _ne += 1; }
            }
            be16(_b, _ne);
            for (var pe = 0; pe < _pn; pe++)
            {
                if (_pcs[pe] >= 0)
                {
                    be16(_b, pe);
                    be16(_b, 0);
                    be32(_b, rgb_machine(_pcs[pe]));
                }
            }
        }
        buf_align(_b, 8);
    }
    // items (version 13, engine.s IT_* / RC_*): IT_N, IT_NR, then each item (20 bytes: disk
    // actor or -1, use, flags, uses, carry up to, start with, 8-letter name 0 terminated in 10
    // bytes), then each recipe (8 bytes: a, b, out, flags, n)
    var _off_items = 0;
    var _nitem = min(array_length(_p.items), ITEM_MAX);
    if (_nitem > 0)
    {
        buf_align(_b, 8);
        _off_items = buffer_tell(_b);
        var _nrcp = min(array_length(_p.recipes), RECIPE_MAX);
        be16(_b, _nitem);
        be16(_b, _nrcp);
        var _dfirst = _p[$ "disk_first"];
        for (var it = 0; it < _nitem; it++)
        {
            var _itm = _p.items[it];
            var _ia = -1;
            if (_itm.actor >= 0 && is_array(_dfirst) && _itm.actor < array_length(_dfirst)) { _ia = _dfirst[_itm.actor]; }
            if (_ia >= _na) { _ia = -1; }
            be16(_b, _ia & 0xffff);
            buffer_write(_b, buffer_u8, clamp(_itm.use, 0, 2));
            var _ifl = 0;
            if (_itm.keep_level) { _ifl = _ifl | 1; }
            if (_itm.lose_life) { _ifl = _ifl | 2; }
            buffer_write(_b, buffer_u8, _ifl);
            be16(_b, clamp(_itm.uses, 1, ITEM_CARRY_MAX));
            be16(_b, clamp(_itm.max, 1, ITEM_CARRY_MAX));
            be16(_b, clamp(_itm.start, 0, _itm.max));
            buf_fixed_text(_b, string_upper(string_copy(_itm.name, 1, ITEM_NAME_LEN)), 10);
        }
        for (var rq = 0; rq < _nrcp; rq++)
        {
            var _rcq = _p.recipes[rq];
            be16(_b, clamp(_rcq.a, 0, _nitem - 1));
            be16(_b, clamp(_rcq.b, 0, _nitem - 1));
            be16(_b, clamp(_rcq.out, 0, _nitem - 1));
            var _rfl = 0;
            if (_rcq.keep_a) { _rfl = _rfl | 1; }
            if (_rcq.keep_b) { _rfl = _rfl | 2; }
            buffer_write(_b, buffer_u8, _rfl);
            buffer_write(_b, buffer_u8, clamp(_rcq.n, 1, 9));
        }
        buf_align(_b, 8);
    }
    // disk 2 (version 12): D2_ID, then where the raw track buffer and the song buffer are
    var _off_d2 = 0;
    if (!is_undefined(_mus.d2))
    {
        buf_align(_b, 8);
        _off_d2 = buffer_tell(_b);
        be32(_b, _mus.d2_id);
        be32(_b, 0);
        be32(_b, 0);
        buf_align(_b, 8);
    }
    var _size = buffer_tell(_b);

    // tile world: cleared memory after the data (not on the disk): the map as
    // played, then the scrolling picture - a ring kept twice (engine.s draw_cell)
    var _bss = 0;
    if (_p.tiles_on)
    {
        var _base = (_size + 7) & ~7;
        var _bufpl = (2 * tile_geometry(_p.tile_size).ring + 8 + 7) & ~7;
        var _cellb = 1;
        if (array_length(_p.tiles) > 256) { _cellb = 2; }
        var _off_wmap = _base;
        var _off_tbuf = _off_wmap + ((_p.map_w * _p.map_h * _cellb + 7) & ~7);
        _bss = _off_tbuf + _depth * _bufpl - _size;
        poke32(_b, _tile_fix + 8, _off_wmap);
        poke32(_b, _tile_fix + 12, _off_tbuf);
        poke32(_b, _tile_fix + 16, _bufpl);
    }
    if (_scr)
    {
        var _sbase = (_size + 7) & ~7;
        var _spl = 36864;                               // SCR_PLH: 384 lines x 96 bytes (across)
        if (_sdir == 1 || _sdir == 3) { _spl = 25600; }     // SCR_PLV: 640 lines x 40 bytes
        if (_shm) { _spl = 640 * _p.map_w * 2; }            // a map: 640 lines of its play area's width
        _bss = _sbase - _size + _sc_nbuf * (_depth * _spl + 16);
        poke32(_b, _sc_fix, _sbase);
    }
    if (_off_d2 > 0)
    {
        // disk 2: the raw track buffer, then room for its biggest song (whole tracks)
        var _d2base = (_size + _bss + 7) & ~7;
        poke32(_b, _off_d2 + 4, _d2base);
        poke32(_b, _off_d2 + 8, _d2base + D2_RAW_BYTES);
        _bss = _d2base + D2_RAW_BYTES + ceil(_mus.d2_max / D2_TRACK) * D2_TRACK - _size;
    }

    // header
    buffer_poke(_b, 0, buffer_u8, ord("A"));
    buffer_poke(_b, 1, buffer_u8, ord("D"));
    buffer_poke(_b, 2, buffer_u8, ord("A"));
    buffer_poke(_b, 3, buffer_u8, ord("M"));
    var _flags = 0;
    if (_m.aga) { _flags = 1; }
    var _sc = 0;
    if (_p.show_score) { _sc = 1; }
    var _lv = 0;
    if (_p.show_lives) { _lv = 1; }
    poke16(_b, 4, 14);                   // data block version 14: BOB frame headers (BI_*); 13: items (H_ITEMS), IF lines, WHEN 17 / 18, DO 28..31; 12: disk 2 (H_DISK2); 11: named palettes (H_PALS); 10: shoot 'em up map (SC_MAP), A_TYPE..A_FPAT; 9: shoot 'em up (H_SCROLL, A_PAT..A_RANK); 8: 16-frame animation tables; 7: custom HUD (H_UI); 6: tile world (H_TILES); 5: animation tables (A_ANIM); 4: BOBs
    poke16(_b, 6, _flags);
    poke16(_b, 8, _depth);
    poke16(_b, 10, _na);
    poke16(_b, 12, _nr);
    poke16(_b, 14, clamp(_p.lives, 0, 9));
    poke16(_b, 16, _sc);
    poke16(_b, 18, _lv);
    poke16(_b, 20, clamp(_p.hud_row, 0, 31));
    poke16(_b, 22, clamp(_p.hud_colour, 0, _ncol - 1));
    poke16(_b, 24, clamp(_p.msg_colour, 0, _ncol - 1));
    poke16(_b, 26, _player);
    poke32(_b, 32, _off_pal);
    poke32(_b, 36, _off_planes);
    poke32(_b, 40, _off_act);
    poke32(_b, 44, _off_rules);
    poke32(_b, 48, _off_sfx);
    poke32(_b, 52, _off_over);
    poke32(_b, 56, _off_win);
    poke32(_b, 60, _off_sprcol);
    poke32(_b, 64, _off_disp);
    poke32(_b, 68, _off_grad);
    poke32(_b, 72, _off_ground);
    poke32(_b, 76, _off_work);
    poke32(_b, 28, _off_game);
    poke32(_b, 80, _off_music);
    poke32(_b, 84, _off_disp2);
    poke32(_b, 88, _off_back);
    poke32(_b, 92, _off_tiles);
    poke32(_b, 96, _off_ui);
    poke32(_b, 100, _off_scroll);
    poke32(_b, 104, _off_pals);
    poke32(_b, 108, _off_d2);
    poke32(_b, 112, _off_items);

    for (var rm = 0; rm < _nr; rm++)
    {
        var _bad_song = (_rules[rm].act == 18 && _rules[rm].value >= _mus.nsongs);
        for (var rs = 0; rs < array_length(_rules[rm].more); rs++)
        {
            if (_rules[rm].more[rs].act == 18 && _rules[rm].more[rs].value >= _mus.nsongs) { _bad_song = true; }
        }
        if (_bad_song)
        {
            array_push(_warn, "A rule plays a song that does not exist - make it on the Music page.");
            break;
        }
    }
    if (_ritems > 0) { array_push(_warn, string(_ritems) + " rule(s) use items, but the game has none - make them on the Logic page (Items tab). Those rules are left out."); }
    if (_rcut) { array_push(_warn, "The game has more than " + string(RULES_DISK_MAX) + " rules - the ones after that are left out. Merge some into AND DO lines."); }
    if (_na == 0) { array_push(_warn, "There are no actors yet - the game will just show your backdrop."); }
    if (_player < 0 && _na > 0) { array_push(_warn, "No actor is set as Player, so the joystick will not move anything."); }
    var _nbobs = 0;
    for (var bc = 0; bc < _na; bc++)
    {
        if (_bob[bc]) { _nbobs += 1; }
    }
    var _bmax = bobs_max(_m, _depth);
    if (bobs_load() > _bmax)
    {
        array_push(_warn, string(_nbobs) + " BOBs is a lot for the " + _m.short_name + " at " + string(_ncol) + " colours - about " + string(_bmax) + " small ones run at full speed (big BOBs count as several); with more the game slows down. Fewer BOBs or fewer colours help.");
    }
    if (array_length(_acts) > _na)
    {
        if (pro_on()) { array_push(_warn, "Only the first " + string(ACT_MAX_ALL) + " actors go on the disk."); }
        else { array_push(_warn, "Only the first " + string(ACT_MAX_SPR) + " actors go on the disk - more actors (as BOBs) are part of ADAM Pro."); }
    }
    if (_p.tiles_on && array_length(_acts) > ACT_MAX_TILE) { array_push(_warn, "A tile world has up to " + string(ACT_MAX_TILE) + " actors (hardware sprites - the scrolling display uses sprite 8's time) - only the first " + string(ACT_MAX_TILE) + " go on the disk."); }
    if (_p.tiles_on && _p.scroll_dir > 0) { array_push(_warn, "The backdrop does not scroll in a tile world - the map scrolls with the player instead."); }
    return { buf : _b, size : _size, warnings : _warn, sound_bytes : _snd_bytes + _mus.bytes, plane_bytes : _depth * 10240 * _nbuf, bss : _bss,
             d2 : _mus.d2, d2_bytes : _mus.d2_bytes };
}

/// The songs that go on disk 2 (version 12): with _on, every song a level starts with
/// that no 'play music' rule plays - they are read at the level card, so a game never
/// waits for the disk in the middle of a level
function disk2_song_flags(_p, _rules, _ns, _on)
{
    var _f = array_create(_ns, false);
    if (!_on) { return _f; }
    var _nl = 1;
    if (_p.levels_on) { _nl = clamp(array_length(_p.levels), 1, LEVEL_MAX); }
    for (var lv = 0; lv < _nl; lv++)
    {
        if (!is_array(_p.level_song) || lv >= array_length(_p.level_song)) { break; }
        var _ls = _p.level_song[lv];
        if (is_numeric(_ls) && _ls >= 0 && _ls < _ns) { _f[floor(_ls)] = true; }
    }
    for (var r = 0; r < array_length(_rules); r++)
    {
        var _ru = _rules[r];
        if (_ru.act == 18 && _ru.value >= 0 && _ru.value < _ns) { _f[floor(_ru.value)] = false; }
        for (var m = 0; m < array_length(_ru.more); m++)
        {
            var _d = _ru.more[m];
            if (_d.act == 18 && _d.value >= 0 && _d.value < _ns) { _f[floor(_d.value)] = false; }
        }
    }
    return _f;
}

/// Disk 2's id (D2_ID): from the length of each song on it and every 256th byte
/// (adf_reference.py disk2_id does the same)
function disk2_id_add(_id, _mb, _len)
{
    var _h = ((_id * 31) + _len) & 0xffffffff;
    for (var k = 0; k < _len; k += 256) { _h = ((_h * 31) + buffer_peek(_mb, k, buffer_u8)) & 0xffffffff; }
    return _h;
}

/// <disk>_disk2.adf next to the game's disk
function adf_disk2_path(_path)
{
    return filename_change_ext(_path, "") + "_disk2.adf";
}

/// Writes the music table and the songs (as ProTracker MODs) at the end of _b.
/// Layout (engine.s M_*): word nsongs, word 0, 10 bytes song per level ($ff = none),
/// word 0, then nsongs x { long offset of the MOD bytes, long length }. A song on disk 2
/// (_p.d2_on, disk2_song_flags) has bit 31 of its offset set: the rest is where it starts
/// on disk 2 (a track; the disk's first track holds 'ADM2' and its id).
/// Returns { off (0 = no music), bytes, nsongs, d2 (disk 2's bytes, or undefined), d2_max, d2_id, d2_bytes }.
function adf_music_table(_b, _p, _warn, _rules)
{
    var _res = { off : 0, bytes : 0, nsongs : 0, d2 : undefined, d2_max : 0, d2_id : 0, d2_bytes : 0 };
    if (!is_array(_p.songs)) { return _res; }
    var _ns = min(ADF_SONGS_MAX, array_length(_p.songs));
    if (_ns <= 0) { return _res; }

    buf_align(_b, 8);
    var _off = buffer_tell(_b);
    be16(_b, _ns);
    be16(_b, 0);
    for (var lv = 0; lv < LEVEL_MAX; lv++)
    {
        var _ls = -1;
        if (is_array(_p.level_song) && lv < array_length(_p.level_song)) { _ls = _p.level_song[lv]; }
        if (!is_numeric(_ls)) { _ls = -1; }
        _ls = floor(_ls);
        if (_ls < 0 || _ls >= _ns) { _ls = 0xff; }
        buffer_write(_b, buffer_u8, _ls);
    }
    be16(_b, 0);
    var _tab = buffer_tell(_b);
    buf_zeros(_b, _ns * 8);
    var _d2f = disk2_song_flags(_p, _rules, _ns, _p.d2_on);
    var _d2pos = D2_TRACK;
    var _d2id = 0x41444d32;

    for (var s = 0; s < _ns; s++)
    {
        var _song = _p.songs[s];
        var _mb = undefined;
        var _ms = song_to_modsong(_song);
        if (!is_undefined(_ms)) { _mb = mod_write(_ms); }
        var _have = false;
        if (!is_undefined(_mb))
        {
            if (buffer_exists(_mb)) { _have = true; }
        }
        var _len = 0;
        if (_have) { _len = buffer_get_size(_mb); }
        if (_len < 1084)
        {
            // 1084 = the smallest possible M.K. header (no patterns, no samples)
            var _nm = "Song " + string(s + 1);
            if (is_struct(_song))
            {
                if (is_string(_song[$ "name"])) { _nm = _song[$ "name"]; }
            }
            array_push(_warn, "Song '" + _nm + "' could not be turned into a MOD - it will be silent.");
            if (_have) { buffer_delete(_mb); }
            continue;
        }
        if (_d2f[s])
        {
            // on disk 2, from a track start
            if (_d2pos + _len > ADF_SIZE)
            {
                array_push(_warn, "Disk 2 is full - a song is left out (silent).");
                buffer_delete(_mb);
                continue;
            }
            if (is_undefined(_res.d2))
            {
                _res.d2 = buffer_create(ADF_SIZE, buffer_fixed, 1);
                buffer_fill(_res.d2, 0, buffer_u8, 0, ADF_SIZE);
            }
            buffer_copy(_mb, 0, _len, _res.d2, _d2pos);
            _d2id = disk2_id_add(_d2id, _mb, _len);
            buffer_delete(_mb);
            poke32(_b, _tab + s * 8, 0x80000000 | _d2pos);
            poke32(_b, _tab + s * 8 + 4, _len);
            _res.d2_max = max(_res.d2_max, _len);
            _res.d2_bytes += _len;
            _d2pos += ceil(_len / D2_TRACK) * D2_TRACK;
            continue;
        }
        // the MOD starts on an even address (samples must be word aligned for Paula)
        buf_align(_b, 8);
        var _pos = buffer_tell(_b);
        if (buffer_get_size(_b) < _pos + _len) { buffer_resize(_b, _pos + _len + 65536); }
        buffer_copy(_mb, 0, _len, _b, _pos);
        buffer_seek(_b, buffer_seek_start, _pos + _len);
        buffer_delete(_mb);
        poke32(_b, _tab + s * 8, _pos);
        poke32(_b, _tab + s * 8 + 4, _len);
        _res.bytes += _len;
    }
    buf_align(_b, 8);
    if (!is_undefined(_res.d2))
    {
        if (_d2id == 0) { _d2id = 1; }
        _res.d2_id = _d2id;
        buffer_poke(_res.d2, 0, buffer_u8, ord("A"));       // disk 2's first sector: 'ADM2', the id
        buffer_poke(_res.d2, 1, buffer_u8, ord("D"));
        buffer_poke(_res.d2, 2, buffer_u8, ord("M"));
        buffer_poke(_res.d2, 3, buffer_u8, ord("2"));
        poke32(_res.d2, 4, _d2id);
    }
    _res.off = _off;
    _res.nsongs = _ns;
    return _res;
}

/// Builds the ADF file. Returns true on success and fills build_* fields.
/// Size in bytes of the 68000 engine (engine.bin), or 0 if it is missing
function mem_engine_bytes()
{
    var _f = working_directory + "engine/engine.bin";
    if (!file_exists(_f)) { return 0; }
    var _eb = buffer_load(_f);
    var _n = buffer_get_size(_eb);
    buffer_delete(_eb);
    return _n;
}

/// Measures the game as it would go on the disk, for the memory bar
function mem_measure()
{
    mem_stale = false;
    mem_proj_ref = proj;
    mem_machine = proj.machine;
    var _m = machine_cur();
    mem_chip_free = max(1, (_m.chip_kb - OS_RESERVE_KB) * 1024);
    mem_disk_free = ADF_SIZE - 1024;
    try
    {
        if (loadscr_active(proj))
        {
            var _lsm = loadscr_block(proj, true);
            if (!is_undefined(_lsm)) { mem_disk_free -= _lsm.size; }    // the loading screen's room on the disk
        }
        var _data = adam_data_block(proj, true);
        mem_size = mem_engine_size + _data.size + _data.bss;
        mem_plane_size = _data.plane_bytes;
        mem_sound_size = _data.sound_bytes;
        buffer_delete(_data.buf);
        if (!is_undefined(_data.d2)) { buffer_delete(_data.d2); }
        mem_ok = true;
    }
    catch (_e)
    {
        mem_ok = false;
        if (ADAM_DEV_TOOLS) { show_debug_message("ADAM memory bar: could not measure - " + string(_e)); }
    }
}

/// Asks for the memory bar to be measured again once things settle
function mem_mark_stale()
{
    mem_stale = true;
    mem_stale_time = current_time;
}

/// The memory bar in the status bar: chip RAM (or the floppy, whichever runs
/// out first) split into engine, backdrop, sound & music and the rest
function mem_bar_draw(_x, _y, _w, _h)
{
    var _m = machine_cur();
    var _range = max(1, min(mem_chip_free, mem_disk_free));
    var _disk_first = (mem_disk_free < mem_chip_free);
    var _used = mem_size;
    var _frac = clamp(_used / _range, 0, 1);
    var _edge = global.TH.panel_edge;
    if (_used > _range * 0.75) { _edge = global.TH.warn; }
    if (_used > _range * 0.9) { _edge = global.TH.danger; }
    ui_rrect(_x, _y, _x + _w, _y + _h, 4, c_black, c_black, 0.35);
    if (mem_ok)
    {
        var _iw = _w - 2;
        var _bx = _x + 1;
        var _parts = [mem_engine_size, mem_plane_size, mem_sound_size, max(0, mem_size - mem_engine_size - mem_plane_size - mem_sound_size)];
        var _top = [global.TH.accent, global.TH.accent2, global.TH.warn, make_colour_rgb(95, 211, 140)];
        var _bot = [global.TH.accent_dark, merge_colour(global.TH.accent2, c_black, 0.3), merge_colour(global.TH.warn, c_black, 0.3), make_colour_rgb(60, 150, 100)];
        for (var i = 0; i < 4; i++)
        {
            var _pw = min(_parts[i] / _range * _iw, _x + 1 + _iw - _bx);
            if (_pw >= 1)
            {
                ui_rrect(_bx, _y + 1, _bx + _pw, _y + _h - 1, 3, _top[i], _bot[i], 1);
                _bx += _pw;
            }
        }
        if (!_m.aga)
        {
            // red tick: the most that fits an A500 with only 512KB of chip RAM
            var _kx = _x + 1 + min(1, (A500_512K_CHIP_KB - OS_RESERVE_KB) * 1024 / _range) * _iw;
            draw_line_width_colour(_kx, _y - 2, _kx, _y + _h + 2, 2, global.TH.danger, global.TH.danger);
        }
    }
    ui_rrect_line(_x, _y, _x + _w, _y + _h, 4, _edge, 0.9, 1);

    var _lab = "Memory  -";
    if (mem_ok) { _lab = "Memory  " + string(ceil(_used / 1024)) + " / " + string(_range div 1024) + " KB  (" + string(floor(_frac * 100)) + "%)"; }
    ui_text(_x - 10, _y + _h * 0.5, _lab, global.TH.text_dim, fa_right, fa_middle, global.f_small, 1);

    var _help = "Memory|How full your game is. Blue: the ADAM engine. Orange: the backdrop and the screens. Yellow: sound samples and music. Green: sprites, actors, rules and the rest.";
    if (_disk_first) { _help += " The full bar is one floppy disk (about " + string(mem_disk_free div 1024) + " KB) - on the " + _m.name + " the disk fills up before its " + string(mem_chip_free div 1024) + " KB of free chip RAM."; }
    else { _help += " The full bar is the chip RAM left free on a stock " + _m.name + " (about " + string(mem_chip_free div 1024) + " KB)."; }
    if (!_m.aga) { _help += " The red tick is about " + string(A500_512K_CHIP_KB - OS_RESERVE_KB) + " KB: past it the game will not run on an A500 with only 512KB of chip RAM."; }
    _help += " Amber from 75%, red from 90%.";
    ui_register("mem_bar", _x - 10 - 190, _y - 6, _x + _w, _y + _h + 6, _help);
}

function build_adf(_path)
{
    var _dir = working_directory + "engine/";
    if (!file_exists(_dir + "engine.bin") || !file_exists(_dir + "boot.bin"))
    {
        build_ok = false;
        build_msg = "Build failed - the engine files are missing (datafiles/engine).";
        return false;
    }
    var _eng = buffer_load(_dir + "engine.bin");
    var _boot = buffer_load(_dir + "boot.bin");
    var _esize = buffer_get_size(_eng);
    var _bsize = buffer_get_size(_boot);
    var _data = adam_data_block(proj);
    build_disk2 = "";
    if (ceil((_esize + _data.size) / 512) * 512 > ADF_SIZE - 1024 && !proj.disk2_music && is_array(proj.songs) && array_length(proj.songs) > 0)
    {
        // too big for one disk: try the songs the levels start with on disk 2
        var _two = adam_data_block(proj, false, true);
        if (!is_undefined(_two.d2))
        {
            buffer_delete(_data.buf);
            _data = _two;
            array_push(_data.warnings, "The game did not fit on one disk, so the level music went on disk 2.");
        }
        else { buffer_delete(_two.buf); }
    }
    var _game = _esize + _data.size;
    var _load = ceil(_game / 512) * 512;
    var _need = _game + _data.bss;      // chip RAM: tile worlds use cleared memory after the data
    var _bss_alloc = max(0, _need - _load);
    build_warnings = _data.warnings;
    // ADAM Pro loading screen: its block goes between the bootblock and the game
    var _ls = undefined;
    var _ls_size = 0;
    var _ls_mem = 0;
    if (proj.loadscr.on && !pro_edition()) { array_push(build_warnings, "The loading screen is part of ADAM Pro - this disk loads with the plain bar."); }
    if (loadscr_active(proj))
    {
        _ls = loadscr_block(proj);
        if (is_undefined(_ls)) { array_push(build_warnings, "The loading screen's engine file is missing (datafiles/engine/loadscr.bin) - the plain bar is used."); }
        else
        {
            _ls_size = _ls.size;
            _ls_mem = _ls.mem;
        }
    }
    if (_load + _ls_size > ADF_SIZE - 1024)
    {
        buffer_delete(_eng);
        buffer_delete(_boot);
        buffer_delete(_data.buf);
        if (!is_undefined(_data.d2)) { buffer_delete(_data.d2); }
        if (!is_undefined(_ls)) { buffer_delete(_ls.buf); }
        build_ok = false;
        build_msg = "Build failed - the game is " + string(_game div 1024) + " KB and does not fit on one floppy disk.";
        if (_ls_size > 0) { build_msg = "Build failed - the game (" + string(_game div 1024) + " KB) and its loading screen (" + string(_ls_size div 1024) + " KB) do not fit on one floppy disk. Try a loading picture with fewer colours."; }
        return false;
    }
    var _m = machine_cur();
    var _chip_free = (_m.chip_kb - OS_RESERVE_KB) * 1024;
    if (_need > _chip_free)
    {
        buffer_delete(_eng);
        buffer_delete(_boot);
        buffer_delete(_data.buf);
        if (!is_undefined(_data.d2)) { buffer_delete(_data.d2); }
        if (!is_undefined(_ls)) { buffer_delete(_ls.buf); }
        build_ok = false;
        build_msg = "Build failed - the game needs " + string(_need div 1024) + " KB of chip RAM; the " + _m.name + " has about " + string(_chip_free div 1024) + " KB free. Use fewer colours, a smaller tile map or shorter sounds.";
        return false;
    }

    var _adf = buffer_create(ADF_SIZE, buffer_fixed, 1);
    buffer_fill(_adf, 0, buffer_u8, 0, ADF_SIZE);
    buffer_copy(_boot, 0, _bsize, _adf, 0);
    poke32(_adf, _bsize - 16, _ls_size);      // boot.s screenload (0 = the plain bar)
    poke32(_adf, _bsize - 12, _ls_mem);       // boot.s screenmem
    poke32(_adf, _bsize - 8, _load);          // boot.s loadsize
    poke32(_adf, _bsize - 4, _bss_alloc);     // boot.s bsssize
    // bootblock checksum: add-with-carry over 256 longwords, then invert
    var _sum = 0;
    for (var i = 0; i < 256; i++)
    {
        if (i == 1) { continue; }
        _sum += peek32(_adf, i * 4);
        if (_sum > 0xffffffff) { _sum = (_sum & 0xffffffff) + 1; }
    }
    poke32(_adf, 4, 0xffffffff - _sum);
    if (!is_undefined(_ls))
    {
        buffer_copy(_ls.buf, 0, _ls_size, _adf, 1024);
        buffer_delete(_ls.buf);
    }
    buffer_copy(_eng, 0, _esize, _adf, 1024 + _ls_size);
    buffer_copy(_data.buf, 0, _data.size, _adf, 1024 + _ls_size + _esize);
    buffer_save(_adf, _path);
    buffer_delete(_adf);
    buffer_delete(_eng);
    buffer_delete(_boot);
    buffer_delete(_data.buf);
    if (!is_undefined(_data.d2))
    {
        build_disk2 = adf_disk2_path(_path);
        buffer_save(_data.d2, build_disk2);
        buffer_delete(_data.d2);
    }

    build_ok = true;
    build_stamp = current_time;
    build_size = _need;
    build_engine_size = _esize;
    build_plane_size = _data.plane_bytes;
    build_sound_size = _data.sound_bytes;
    build_chip_free = _chip_free;
    build_msg = "Built " + filename_name(_path) + " for the " + _m.name + " - " + string(ceil(_need / 1024)) + " KB of chip RAM";
    if (build_disk2 != "") { build_msg += ", and " + filename_name(build_disk2) + " (" + string(ceil(_data.d2_bytes / 1024)) + " KB of level music)"; }
    if (!_m.aga && _need > (A500_512K_CHIP_KB - OS_RESERVE_KB) * 1024)
    {
        array_push(build_warnings, "Too big for an A500 with only 512KB of chip RAM (about " + string(A500_512K_CHIP_KB - OS_RESERVE_KB) + " KB free) - it will show a red screen there. Fine on 1MB machines.");
    }
    else if (_ls_mem > 0 && !_m.aga && _need + _ls_mem > (A500_512K_CHIP_KB - OS_RESERVE_KB) * 1024)
    {
        array_push(build_warnings, "On an A500 with only 512KB of chip RAM the loading screen (" + string(_ls_mem div 1024) + " KB while loading) does not fit next to the game - it loads with the plain bar there.");
    }
    if (_ls_mem > 0 && _need + _ls_mem > _chip_free)
    {
        array_push(build_warnings, "The loading screen needs " + string(_ls_mem div 1024) + " KB of chip RAM while loading and there is not that much left next to the game - it loads with the plain bar.");
    }
    return true;
}

/// Dev tool (ADAM_DEV_TOOLS): build a disk without the UI, then quit.
///     Runner.exe -game data.win -adam_build in.adam out.adf [-adam_mod song.mod]
/// The session's own project is put back before quitting, so the autosave
/// and settings are unchanged. The result goes to the debug output and out.adf.log.
function dev_cli_build()
{
    var _n = parameter_count();
    for (var i = 0; i < _n - 2; i++)
    {
        if (parameter_string(i) != "-adam_build") { continue; }
        var _in = parameter_string(i + 1);
        var _out = parameter_string(i + 2);
        var _keep = proj;
        var _ok = false;
        try
        {
            proj = project_from_loaded(json_parse(file_read_text(_in)));
            // -adam_mod file.mod adds that module as the next song (as Music > Import does)
            for (var m = 0; m < _n - 1; m++)
            {
                if (parameter_string(m) != "-adam_mod") { continue; }
                var _raw = mod_read(parameter_string(m + 1));
                if (is_undefined(_raw)) { continue; }
                var _ms = modsong_sanitize(_raw);
                if (is_undefined(_ms)) { continue; }
                var _song = song_new("Test");
                _song.kind = 1;
                _song[$ "mod"] = _ms;
                array_push(proj.songs, _song);
            }
            _ok = build_adf(_out);
        }
        catch (_e)
        {
            build_msg = "could not read " + _in;
        }
        var _log = "ADAM cli build: " + string(_ok) + " - " + build_msg + "\n";
        for (var w = 0; w < array_length(build_warnings); w++)
        {
            _log += "warning: " + build_warnings[w] + "\n";
        }
        show_debug_message(_log);
        file_write_text(_out + ".log", _log);
        proj = _keep;
        game_end();
        return true;
    }
    return false;
}

/// Dev tool (ADAM_DEV_TOOLS): a PNG of every page, then quit.
///     Runner.exe -game data.win -adam_shots in.adam outdir [-adam_shots_w 1920 -adam_shots_h 1080]
/// The window is set to that size at 100% scale, the mouse is ignored and nothing is
/// saved (no autosave, settings or window place), so the session is unchanged.
function dev_cli_shots()
{
    var _n = parameter_count();
    for (var i = 0; i < _n - 2; i++)
    {
        if (parameter_string(i) != "-adam_shots") { continue; }
        var _in = parameter_string(i + 1);
        shot_dir = parameter_string(i + 2);
        var _sw = 1920;
        var _sh = 1080;
        for (var k = 0; k < _n - 1; k++)
        {
            if (parameter_string(k) == "-adam_shots_w") { _sw = real(parameter_string(k + 1)); }
            if (parameter_string(k) == "-adam_shots_h") { _sh = real(parameter_string(k + 1)); }
        }
        try
        {
            proj = project_from_loaded(json_parse(file_read_text(_in)));
        }
        catch (_e)
        {
            show_debug_message("ADAM shots: could not read " + _in);
            game_end();
            return true;
        }
        project_after_change();
        proj_dirty = false;
        shot_on = true;
        shot_i = 0;
        shot_wait = 0;
        shot_w = _sw;
        shot_h = _sh;
        auto_tutorials = false;
        start_fullscreen = false;
        ui_scale_pref = 1;
        // the player's sprite is the one to show off on the Sprites page
        if (array_length(proj.actors) > 0) { spr_sel = clamp(proj.actors[0].sprite, 0, SPR_COUNT - 1); }
        return true;
    }
    return false;
}

/// Step: holds the window size and moves to the next page once the last one is saved
function dev_shots_step()
{
    if (!shot_on) { return; }
    if (window_get_fullscreen()) { window_set_fullscreen(false); }
    if (window_get_width() != shot_w || window_get_height() != shot_h)
    {
        window_set_size(shot_w, shot_h);
        shot_wait = 0;
    }
    machine_pick_active = false;
    tut_offer_on = false;
    toasts = [];
    proj_dirty = false;
    autosave_timer = 0;
    ui_scale_pref = 1;
    if (shot_i >= array_length(shot_pages))
    {
        game_end();
        return;
    }
    var _pg = shot_pages[shot_i];
    ws = _pg.ws;
    bd_panel = _pg.panel;
    ui_page_tab = 0;
    if (_pg.ws == WS_UI) { ui_page_tab = _pg.panel; }
    logic_tab = 0;
    if (_pg.ws == WS_LOGIC) { logic_tab = _pg.panel; }
    shot_wait += 1;
}

/// Draw GUI: true when this frame is captured (draw into shot_surf, then dev_shots_end)
function dev_shots_begin()
{
    if (!shot_on) { return false; }
    // the mouse stays out of the way
    ui_mx = -10000;
    ui_my = -10000;
    ui_pressed = false;
    ui_held = false;
    ui_released = false;
    ui_rpressed = false;
    ui_rheld = false;
    ui_pressed_raw = false;
    ui_wheel = 0;
    if (shot_wait < 40 || shot_i >= array_length(shot_pages)) { return false; }
    if (!surface_exists(shot_surf) || surface_get_width(shot_surf) != gui_w || surface_get_height(shot_surf) != gui_h)
    {
        if (surface_exists(shot_surf)) { surface_free(shot_surf); }
        shot_surf = surface_create(gui_w, gui_h);
    }
    surface_set_target(shot_surf);
    draw_clear(c_black);
    return true;
}

function dev_shots_end()
{
    surface_reset_target();
    var _f = shot_dir + "/" + string(shot_i + 1) + "_" + shot_pages[shot_i].name + ".png";
    surface_save(shot_surf, _f);
    show_debug_message("ADAM shots: " + _f);
    shot_i += 1;
    shot_wait = 0;
}

// ---------------------------------------------------------------------------
// FS-UAE.  Order of preference:
//   1. the fs-uae.exe the user chose with Find (always allowed)
//   2. ADAM's own test copy, downloaded on demand from the official FS-UAE
//      release into the save folder (only while ADAM_DEV_TOOLS is true)
//   3. a normal FS-UAE install in the usual places
// Set ADAM_DEV_TOOLS to false for public (itch.io) builds: users then locate
// their own FS-UAE and nothing is downloaded or bundled.
//
// macOS: GameMaker cannot start a program with arguments there (the
// execute_shell_simple extension is a Windows DLL), so ADAM writes the
// settings to a .fs-uae config file and asks Finder to open it - FS-UAE.app
// is the app that opens .fs-uae files. The "test copy" on a Mac is the
// official FS-UAE disk image (.dmg), opened in Finder for the user to drag
// into Applications. Windows-only calls must stay behind os_type checks.
// ---------------------------------------------------------------------------
#macro ADAM_DEV_TOOLS true
#macro FSUAE_HOME_URL "https://fs-uae.net"
#macro FSUAE_BUNDLED_VERSION "FS-UAE 3.2.35"   // the copy tools/release_build.ps1 puts next to ADAM.exe
#macro FSUAE_ZIP_URL "https://github.com/FrodeSolheim/fs-uae/releases/download/v3.1.66/FS-UAE_3.1.66_Windows_x86-64.zip"
// Intel build: runs on every Mac (through Rosetta on Apple silicon)
#macro FSUAE_DMG_URL "https://github.com/FrodeSolheim/fs-uae/releases/download/v3.1.66/FS-UAE_3.1.66_macOS_x86-64.dmg"

function fsuae_test_dir()
{
    return game_save_id + "fs-uae/";
}

function fsuae_test_exe()
{
    return fsuae_test_dir() + "FS-UAE/Windows/x86-64/fs-uae.exe";
}

/// True when _p is an FS-UAE the user can run (on a Mac an .app bundle is a folder)
function fsuae_path_ok(_p)
{
    if (_p == "") { return false; }
    if (file_exists(_p)) { return true; }
    if (os_type == os_macosx && directory_exists(_p)) { return true; }
    return false;
}

/// An installed FS-UAE in the usual places, or ""
function fsuae_find_installed()
{
    if (os_type == os_macosx)
    {
        var _home = environment_get_variable("HOME");
        var _mac = [
            "/Applications/FS-UAE.app",
            _home + "/Applications/FS-UAE.app",
            "/Applications/FS-UAE Launcher.app",
            _home + "/Applications/FS-UAE Launcher.app"
        ];
        for (var m = 0; m < array_length(_mac); m++)
        {
            if (directory_exists(_mac[m])) { return _mac[m]; }
        }
        return "";
    }
    if (os_type != os_windows) { return ""; }
    var _cands = [
        "C:/Program Files/FS-UAE/Windows/x86-64/fs-uae.exe",
        "C:/Program Files (x86)/FS-UAE/Windows/x86-64/fs-uae.exe",
        environment_get_variable("LOCALAPPDATA") + "/Programs/FS-UAE/Windows/x86-64/fs-uae.exe",
        environment_get_variable("USERPROFILE") + "/Documents/FS-UAE/Windows/x86-64/fs-uae.exe"
    ];
    for (var i = 0; i < array_length(_cands); i++)
    {
        if (file_exists(_cands[i])) { return _cands[i]; }
    }
    return "";
}

/// The FS-UAE that comes with ADAM (Windows release builds: an FS-UAE folder
/// next to ADAM.exe, added by tools/release_build.ps1), or ""
function fsuae_bundled_exe()
{
    if (os_type != os_windows) { return ""; }
    var _p = program_directory + "FS-UAE/Windows/x86-64/fs-uae.exe";
    if (file_exists(_p)) { return _p; }
    return "";
}

/// The fs-uae.exe (FS-UAE.app on a Mac) ADAM will run, or "" when there is none:
/// one you picked with Find, else the one that comes with ADAM, else an installed one
function fsuae_exe()
{
    if (fsuae_path_ok(fsuae_path)) { return fsuae_path; }
    if (fsuae_bundled_exe() != "") { return fsuae_bundled_exe(); }
    if (ADAM_DEV_TOOLS && file_exists(fsuae_test_exe())) { return fsuae_test_exe(); }
    return fsuae_find_installed();
}

/// Text for the Build page: where FS-UAE comes from
function fsuae_source_label()
{
    if (fsuae_path_ok(fsuae_path)) { return fsuae_path; }
    if (fsuae_bundled_exe() != "") { return "The FS-UAE that comes with ADAM (" + FSUAE_BUNDLED_VERSION + ")"; }
    if (ADAM_DEV_TOOLS && file_exists(fsuae_test_exe())) { return "ADAM's test copy (FS-UAE 3.1.66)"; }
    var _inst = fsuae_find_installed();
    if (_inst != "") { return _inst + "  (found)"; }
    return "";
}

/// Downloads the official FS-UAE Windows release for testing.
/// _then_run = an ADF to boot when it is ready, or "".
function fsuae_download(_then_run)
{
    if (!ADAM_DEV_TOOLS) { return; }
    if (fsuae_dl_id >= 0) { return; }
    if (os_type == os_macosx)
    {
        // a .dmg cannot be unpacked from GML: fetch it, then Finder opens it (see fsuae_download_async)
        fsuae_dl_zip = game_save_id + "FS-UAE_3.1.66_macOS.dmg";
        if (file_exists(fsuae_dl_zip)) { file_delete(fsuae_dl_zip); }
        fsuae_dl_got = 0;
        fsuae_dl_total = 0;
        fsuae_dl_then_run = "";
        fsuae_dl_id = http_get_file(FSUAE_DMG_URL, fsuae_dl_zip);
        build_log_add("Downloading FS-UAE 3.1.66 for macOS (about 7 MB)...", 0);
        toast("Downloading FS-UAE for testing...", 0);
        return;
    }
    if (os_type != os_windows)
    {
        toast("The FS-UAE test copy is for Windows and macOS - use Find on other systems", 1);
        return;
    }
    fsuae_dl_zip = game_save_id + "fsuae_download.zip";
    if (file_exists(fsuae_dl_zip)) { file_delete(fsuae_dl_zip); }
    fsuae_dl_got = 0;
    fsuae_dl_total = 0;
    fsuae_dl_then_run = _then_run;
    fsuae_dl_id = http_get_file(FSUAE_ZIP_URL, fsuae_dl_zip);
    build_log_add("Downloading FS-UAE 3.1.66 for testing (about 9 MB)...", 0);
    toast("Downloading FS-UAE for testing...", 0);
}

/// Async HTTP event handler for the download
function fsuae_download_async()
{
    if (fsuae_dl_id < 0) { return; }
    if (async_load[? "id"] != fsuae_dl_id) { return; }
    var _status = async_load[? "status"];
    if (_status == 1)
    {
        fsuae_dl_got = async_load[? "sizeDownloaded"];
        fsuae_dl_total = async_load[? "contentLength"];
        return;
    }
    fsuae_dl_id = -1;
    var _ok = false;
    if (os_type == os_macosx)
    {
        if (_status == 0 && async_load[? "http_status"] == 200 && file_exists(fsuae_dl_zip))
        {
            url_open(fsuae_file_url(fsuae_dl_zip));
            build_log_add("FS-UAE disk image opened in Finder: drag FS-UAE into Applications, then press Build and play", 0);
            build_log_add("(If nothing opened, double-click " + fsuae_dl_zip + ")", 0);
            toast("Drag FS-UAE into Applications", 0);
        }
        else
        {
            build_log_add("Could not download FS-UAE - check the internet connection, or get it from fs-uae.net", 2);
            toast("FS-UAE download failed", 2);
        }
        fsuae_dl_then_run = "";
        return;
    }
    if (_status == 0 && async_load[? "http_status"] == 200 && file_exists(fsuae_dl_zip))
    {
        zip_unzip(fsuae_dl_zip, fsuae_test_dir());
        file_delete(fsuae_dl_zip);
        _ok = file_exists(fsuae_test_exe());
    }
    if (_ok)
    {
        build_log_add("FS-UAE test copy ready (GPL - its licences are in the FS-UAE/Licenses folder)", 0);
        toast("FS-UAE is ready", 0);
        if (fsuae_dl_then_run != "") { launch_fsuae(fsuae_dl_then_run); }
    }
    else
    {
        build_log_add("Could not download FS-UAE - check the internet connection, or use Find", 2);
        toast("FS-UAE download failed", 2);
    }
    fsuae_dl_then_run = "";
}

/// Starts FS-UAE on the built disk (after closing an old copy - see Step)
function launch_fsuae(_adf)
{
    if (os_type != os_windows && os_type != os_macosx)
    {
        toast("Open " + filename_name(_adf) + " in FS-UAE to play", 1);
        return false;
    }
    if (fsuae_exe() == "")
    {
        if (ADAM_DEV_TOOLS)
        {
            fsuae_download(_adf);
            return false;
        }
        // no emulator yet: show the Build page, where Get FS-UAE and Find are
        ws_set(WS_BUILD);
        build_log_add("FS-UAE was not found. It is the free Amiga emulator that plays your games: click Get FS-UAE (fs-uae.net), install it, then press Build & play again. If it is installed somewhere unusual, click Find.", 1);
        toast("FS-UAE not found - click Get FS-UAE", 1);
        return false;
    }
    if (os_type == os_macosx)
    {
        return launch_fsuae_mac(_adf);
    }
    execute_shell_simple("taskkill.exe", "/F /IM fs-uae.exe", "open", 0);
    launch_pending = _adf;
    launch_timer = 20;
    toast("Launching FS-UAE...", 0);
    return true;
}

/// FS-UAE device for joystick port 2 (FS-UAE port 1), where ADAM games read the joystick.
/// Keyboard: cursor keys move, right Ctrl fires (FS-UAE won't put it there by itself).
/// Gamepad: "auto" makes FS-UAE pick the first controller it finds. Always set one or the
/// other - some FS-UAE setups default port 1 to nothing.
function fsuae_port_1()
{
    if (fsuae_pad == 1) { return "auto"; }
    return "keyboard";
}

/// Kickstart ROM for the machine the project is for ("" = FS-UAE's free AROS ROM).
/// One per machine: a 1.3 ROM for the A500 would not boot an A1200, and the other way round.
function kick_path_cur()
{
    return kick_paths[machine_index(proj.machine)];
}

function kick_path_set(_path)
{
    kick_paths[machine_index(proj.machine)] = _path;
    settings_save();
}

/// " --floppy_drive_1=..." when the last build of _adf has a disk 2 (the game reads it from DF1)
function fsuae_disk2_arg(_adf)
{
    if (build_disk2 == "" || build_disk2 != adf_disk2_path(_adf) || !file_exists(build_disk2)) { return ""; }
    return " --floppy_drive_1=\"" + build_disk2 + "\"";
}

/// Called from the Step event once the old emulator has had time to close
function launch_fsuae_now(_adf)
{
    if (os_type != os_windows) { return; }
    var _exe = fsuae_exe();
    if (_exe == "") { return; }
    var _m = machine_cur();
    var _args = "--amiga_model=" + _m.fsuae_model
        + " --chip_memory=" + string(_m.chip_kb)
        + " --slow_memory=0 --fast_memory=0"
        + " --floppy_drive_0=\"" + _adf + "\""
        + " --floppy_drive_speed=0"
        + fsuae_disk2_arg(_adf)
        + " --fullscreen=0"
        + " --window_width=960 --window_height=720"
        + " --automatic_input_grab=0 --initial_input_grab=0";
    if (fsuae_light)
    {
        // light mode: no host vsync spin-wait and no smoothing filter - far less CPU/GPU load
        _args += " --video_sync=off --texture_filter=nearest";
    }
    _args += " --joystick_port_1=" + fsuae_port_1();
    var _kick = kick_path_cur();
    if (_kick != "" && file_exists(_kick))
    {
        _args += " --kickstart_file=\"" + _kick + "\"";
    }
    if (_exe == fsuae_bundled_exe())
    {
        // the FS-UAE that comes with ADAM keeps its log and settings in ADAM's own
        // folder, not Documents\FS-UAE: anti-virus "protected folders" (AVG, Windows
        // Controlled folder access) block a program they have not seen writing there
        var _base = game_save_id + "fs-uae-data";
        if (!directory_exists(_base)) { directory_create(_base); }
        _args += " --base_dir=\"" + _base + "\"";
    }
    execute_shell_simple(_exe, _args, "open", 5, filename_dir(_exe));
}

/// "file://" URL for a local path, with spaces and other bytes %-escaped
function fsuae_file_url(_path)
{
    var _hex = "0123456789ABCDEF";
    var _out = "file://";
    var _n = string_byte_length(_path);
    for (var i = 1; i <= _n; i++)
    {
        var _b = string_byte_at(_path, i);
        var _keep = false;
        if (_b >= 0x30 && _b <= 0x39) { _keep = true; }
        if (_b >= 0x41 && _b <= 0x5a) { _keep = true; }
        if (_b >= 0x61 && _b <= 0x7a) { _keep = true; }
        if (_b == 0x2f || _b == 0x2d || _b == 0x2e || _b == 0x5f || _b == 0x7e) { _keep = true; }
        if (_keep)
        {
            _out += chr(_b);
        }
        else
        {
            _out += "%" + string_char_at(_hex, (_b >> 4) + 1) + string_char_at(_hex, (_b & 0x0f) + 1);
        }
    }
    return _out;
}

/// macOS: write the same settings as launch_fsuae_now into a .fs-uae config
/// file and let Finder open it with FS-UAE (no way to pass arguments from GML).
function launch_fsuae_mac(_adf)
{
    var _m = machine_cur();
    var _cfg = game_save_id + "adam_play.fs-uae";
    var _f = file_text_open_write(_cfg);
    if (_f < 0)
    {
        toast("Could not write the FS-UAE settings file", 2);
        return false;
    }
    var _lines = [
        "[fs-uae]",
        "amiga_model = " + _m.fsuae_model,
        "chip_memory = " + string(_m.chip_kb),
        "slow_memory = 0",
        "fast_memory = 0",
        "floppy_drive_0 = " + _adf,
        "floppy_drive_speed = 0",
        "fullscreen = 0",
        "window_width = 960",
        "window_height = 720",
        "automatic_input_grab = 0",
        "initial_input_grab = 0",
        "joystick_port_1 = " + fsuae_port_1()
    ];
    if (fsuae_light)
    {
        array_push(_lines, "video_sync = off");
        array_push(_lines, "texture_filter = nearest");
    }
    var _kick = kick_path_cur();
    if (_kick != "" && file_exists(_kick))
    {
        array_push(_lines, "kickstart_file = " + _kick);
    }
    if (fsuae_disk2_arg(_adf) != "") { array_push(_lines, "floppy_drive_1 = " + build_disk2); }
    for (var i = 0; i < array_length(_lines); i++)
    {
        file_text_write_string(_f, _lines[i]);
        file_text_writeln(_f);
    }
    file_text_close(_f);
    // macOS does not let ADAM close an old FS-UAE window, so the user quits it first
    url_open(fsuae_file_url(_cfg));
    build_log_add("Opened " + _cfg + " - FS-UAE boots it. Quit any FS-UAE that is already running first (Cmd+Q).", 0);
    build_log_add("If it opens in another app, right-click the file in Finder > Open With > FS-UAE (Always Open With).", 0);
    toast("Opening FS-UAE...", 0);
    return true;
}

/// Lines for the "show the engine" view: the engine source, then a data summary
function build_make_listing()
{
    build_listing = [];
    var _txt = file_read_text(working_directory + "engine/engine.s");
    if (_txt != "")
    {
        build_listing = string_split(string_replace_all(_txt, "\r", ""), "\n");
    }
    array_push(build_listing, "; ---------------------------------------------------------------");
    array_push(build_listing, "; game data appended after data_start for '" + proj.name + "'");
    array_push(build_listing, ";   machine " + machine_cur().name + ", " + string(pal_count()) + " colours, " + string(array_length(proj.actors)) + " actors, " + string(array_length(proj.rules)) + " rules, " + string(array_length(proj.sfx)) + " sounds");
}
