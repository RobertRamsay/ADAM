/// ADAM - turns the project into a bootable Amiga disk (.ADF)
///
/// ADAM never writes code. The fixed 68000 engine (datafiles/engine/engine.bin,
/// source in engine.s) reads a game data block that is appended straight after
/// it. The bootblock (boot.bin) loads engine + data into chip RAM and runs it.
/// The data block layout is documented at the top of engine.s.

#macro ADF_SIZE 901120
#macro ADF_HDR 92
#macro ADF_SONGS_MAX 4
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

/// Writes one hardware sprite block (POS, CTL, 24 lines x 2 words, end). Returns its offset.
function adf_sprite_block(_b, _img)
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
            var _sv = _img[sy * SPR_W + sx];
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

/// Writes one BOB image (engine.s BOB_*): 24 mask words, then _depth x 24
/// words of bitplanes. Sprite pixel 1-3 becomes backdrop colour _map[0-2]. Returns its offset.
function adf_bob_image(_b, _img, _map, _depth)
{
    buf_align(_b, 8);
    var _o = buffer_tell(_b);
    for (var my = 0; my < SPR_H; my++)
    {
        var _m = 0;
        for (var mx = 0; mx < SPR_W; mx++)
        {
            if (_img[my * SPR_W + mx] != 0) { _m = _m | (0x8000 >> mx); }
        }
        be16(_b, _m);
    }
    for (var pl = 0; pl < _depth; pl++)
    {
        for (var py = 0; py < SPR_H; py++)
        {
            var _w = 0;
            for (var px = 0; px < SPR_W; px++)
            {
                var _v = _img[py * SPR_W + px];
                if (_v != 0)
                {
                    if (((_map[_v - 1] >> pl) & 1) != 0) { _w = _w | (0x8000 >> px); }
                }
            }
            be16(_b, _w);
        }
    }
    return _o;
}

/// Builds the game data block. Returns { buf, size, warnings[], sound_bytes, plane_bytes }.
function adam_data_block(_p)
{
    var _warn = [];
    var _m = machine_get(_p.machine);
    var _depth = clamp(_p.depth, 1, _m.max_depth);
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
    for (var ru = 0; ru < array_length(_p.rules); ru++)
    {
        var _rr = _p.rules[ru];
        var _off_grp = false;
        if (_rr.group >= 0 && _rr.group < array_length(_p.groups))
        {
            if (!_p.groups[_rr.group].enabled) { _off_grp = true; }
        }
        if (!_off_grp) { array_push(_rules, _rr); }
    }
    var _nr = min(100, array_length(_rules));
    var _b = buffer_create(262144, buffer_grow, 1);
    buf_zeros(_b, ADF_HDR);
    buf_align(_b, 8);

    // palette
    var _off_pal = buffer_tell(_b);
    for (var c = 0; c < _ncol; c++) { be32(_b, rgb_machine(_p.pal[c])); }
    buf_align(_b, 8);

    // backdrop bitplanes (pristine copy)
    var _off_planes = buffer_tell(_b);
    for (var pl = 0; pl < _depth; pl++)
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

    // hardware sprite blocks per actor (and a second one when it animates);
    // BOBs get BOB images in the nearest backdrop colours instead
    var _spr_off = array_create(_na, 0);
    var _spr2_off = array_create(_na, 0);
    for (var a = 0; a < _na; a++)
    {
        var _si = clamp(_acts[a].sprite, 0, SPR_COUNT - 1);
        var _ai = _acts[a].anim_sprite;
        if (_bob[a])
        {
            var _scol = _p.sprites[_si].cols;
            var _map = [pal_nearest(_p, _scol[0], _ncol), pal_nearest(_p, _scol[1], _ncol), pal_nearest(_p, _scol[2], _ncol)];
            _spr_off[a] = adf_bob_image(_b, _p.sprites[_si].px, _map, _depth);
            if (_ai >= 0 && _ai < SPR_COUNT)
            {
                _spr2_off[a] = adf_bob_image(_b, _p.sprites[_ai].px, _map, _depth);
            }
        }
        else
        {
            _spr_off[a] = adf_sprite_block(_b, _p.sprites[_si].px);
            if (_ai >= 0 && _ai < SPR_COUNT)
            {
                _spr2_off[a] = adf_sprite_block(_b, _p.sprites[_ai].px);
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
        var _img2 = _p.sprites[clamp(_ac.sprite, 0, SPR_COUNT - 1)].px;
        var _bx0 = 99;
        var _by0 = 99;
        var _bx1 = -1;
        var _by1 = -1;
        for (var q = 0; q < SPR_W * SPR_H; q++)
        {
            if (_img2[q] != 0)
            {
                _bx0 = min(_bx0, q mod SPR_W);
                _bx1 = max(_bx1, q mod SPR_W);
                _by0 = min(_by0, q div SPR_W);
                _by1 = max(_by1, q div SPR_W);
            }
        }
        if (_bx1 < 0)
        {
            _bx0 = 0; _by0 = 0; _bx1 = SPR_W - 1; _by1 = SPR_H - 1;
            array_push(_warn, "Actor '" + _ac.name + "' uses an empty sprite - it will be invisible.");
        }
        var _vis = 0;
        if (_ac.visible) { _vis = 1; }
        var _left = 0;
        if (_ac.start_left) { _left = 1; }
        var _up = 0;
        if (_ac.start_up) { _up = 1; }
        be16(_b, clamp(_ac.x, 0, ACT_XMAX));
        be16(_b, clamp(_ac.y, 0, ACT_YMAX));
        be16(_b, clamp(_ac.role, 0, 8));
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
        be16(_b, clamp(_ac.anim_rate, 2, 30));
        var _am = 0;
        if (_ac.anim_moving) { _am = 1; }
        be16(_b, _am);
        be16(_b, clamp(_ac.from_level, 1, LEVEL_MAX));
        be16(_b, clamp(_ac.faster_every, 0, LEVEL_MAX));
        var _isbob = 0;
        if (_bob[a2]) { _isbob = 1; }
        be16(_b, _isbob);                // A_BOB
        buf_zeros(_b, 6);
        if (_alloc.conflict[a2]) { array_push(_warn, "Actor '" + _ac.name + "' shares a sprite colour pair with different colours - it will borrow its partner's colours."); }
        if (_bob[a2] && !_ac.bob) { array_push(_warn, "Actor '" + _ac.name + "' is drawn as a BOB - the Amiga has 8 hardware sprites."); }
        if (!pro_on() && _ac.bob) { array_push(_warn, "Actor '" + _ac.name + "' is set to BOB - BOBs are part of ADAM Pro, so it is a sprite here."); }
    }
    buf_align(_b, 8);

    // rules
    var _off_rules = buffer_tell(_b);
    for (var r = 0; r < _nr; r++)
    {
        var _ru = _rules[r];
        var _val = _ru.value;
        if (_ru.act == 8) { _val = clamp(_val, 0, _ncol - 1); }
        if (_ru.act == 2) { _val = clamp(_val, 0, 7); }
        if (_ru.act == 18) { _val = clamp(_val, 0, ADF_SONGS_MAX - 1); }
        be16(_b, clamp(_ru.when, 0, 7));
        be16(_b, clamp(_ru.a, 0, ACT_MAX_ALL - 1));
        be16(_b, clamp(_ru.b, 0, ACT_MAX_ALL - 1));
        be16(_b, clamp(_ru.n, 1, 65535));
        be16(_b, clamp(_ru.act, 0, 19));
        be16(_b, clamp(_ru.target, 0, ACT_MAX_ALL - 1));
        be16(_b, clamp(_val, 0, 65535));
        be16(_b, 0);
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

    // sound samples, then their table
    var _snd_off = array_create(8, 0);
    var _snd_len = array_create(8, 0);
    var _snd_per = array_create(8, 0);
    var _snd_bytes = 0;
    for (var s = 0; s < 8; s++)
    {
        buf_align(_b, 8);
        _snd_off[s] = buffer_tell(_b);
        var _r = sfx_render_ex(_p.sfx[s]);
        var _smp = _r.smp;
        for (var i = 0; i < array_length(_smp); i++) { buffer_write(_b, buffer_s8, _smp[i]); }
        _snd_len[s] = array_length(_smp) div 2;
        _snd_per[s] = _r.period;
        _snd_bytes += array_length(_smp);
    }
    buf_align(_b, 8);
    var _off_sfx = buffer_tell(_b);
    for (var s2 = 0; s2 < 8; s2++)
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
        if (_lv_on) { _terr = 1; }
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

    // music: the songs as ProTracker MODs, played by ptplayer in the engine
    var _mus = adf_music_table(_b, _p, _warn);
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
    if (_anybob)
    {
        buf_zeros(_b, 8);
        _off_disp2 = buffer_tell(_b);
        buf_zeros(_b, _depth * 10240 + 8);
        _off_back = buffer_tell(_b);
        buf_zeros(_b, _depth * 10240 + 8);
        _nbuf = 5;
    }
    var _size = buffer_tell(_b);

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
    poke16(_b, 4, 3);                    // data block version 3: adds BOBs (H_DISP2, H_BACK, A_BOB)
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

    for (var rm = 0; rm < _nr; rm++)
    {
        if (_rules[rm].act == 18 && _rules[rm].value >= _mus.nsongs)
        {
            array_push(_warn, "A rule plays a song that does not exist - make it on the Music page.");
            break;
        }
    }
    if (_na == 0) { array_push(_warn, "There are no actors yet - the game will just show your backdrop."); }
    if (_player < 0 && _na > 0) { array_push(_warn, "No actor is set as Player, so the joystick will not move anything."); }
    var _nbobs = 0;
    for (var bc = 0; bc < _na; bc++)
    {
        if (_bob[bc]) { _nbobs += 1; }
    }
    var _bmax = bobs_max(_m, _depth);
    if (_nbobs > _bmax)
    {
        array_push(_warn, string(_nbobs) + " BOBs is a lot for the " + _m.short_name + " at " + string(_ncol) + " colours - about " + string(_bmax) + " run at full speed; with more the game slows down. Fewer BOBs or fewer colours help.");
    }
    if (array_length(_acts) > _na)
    {
        if (pro_on()) { array_push(_warn, "Only the first " + string(ACT_MAX_ALL) + " actors go on the disk."); }
        else { array_push(_warn, "Only the first " + string(ACT_MAX_SPR) + " actors go on the disk - more actors (as BOBs) are part of ADAM Pro."); }
    }
    return { buf : _b, size : _size, warnings : _warn, sound_bytes : _snd_bytes + _mus.bytes, plane_bytes : _depth * 10240 * _nbuf };
}

/// Writes the music table and the songs (as ProTracker MODs) at the end of _b.
/// Layout (engine.s M_*): word nsongs, word 0, 10 bytes song per level ($ff = none),
/// word 0, then nsongs x { long offset of the MOD bytes, long length }.
/// Returns { off (0 = no music), bytes, nsongs }.
function adf_music_table(_b, _p, _warn)
{
    var _res = { off : 0, bytes : 0, nsongs : 0 };
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
    _res.off = _off;
    _res.nsongs = _ns;
    return _res;
}

/// Builds the ADF file. Returns true on success and fills build_* fields.
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
    var _game = _esize + _data.size;
    var _load = ceil(_game / 512) * 512;
    build_warnings = _data.warnings;
    if (_load > ADF_SIZE - 1024)
    {
        buffer_delete(_eng);
        buffer_delete(_boot);
        buffer_delete(_data.buf);
        build_ok = false;
        build_msg = "Build failed - the game is " + string(_game div 1024) + " KB and does not fit on one floppy disk.";
        return false;
    }
    var _m = machine_cur();
    var _chip_free = (_m.chip_kb - OS_RESERVE_KB) * 1024;
    if (_game > _chip_free)
    {
        buffer_delete(_eng);
        buffer_delete(_boot);
        buffer_delete(_data.buf);
        build_ok = false;
        build_msg = "Build failed - the game needs " + string(_game div 1024) + " KB of chip RAM; the " + _m.name + " has about " + string(_chip_free div 1024) + " KB free. Use fewer colours or shorter sounds.";
        return false;
    }

    var _adf = buffer_create(ADF_SIZE, buffer_fixed, 1);
    buffer_fill(_adf, 0, buffer_u8, 0, ADF_SIZE);
    buffer_copy(_boot, 0, _bsize, _adf, 0);
    poke32(_adf, _bsize - 4, _load);
    // bootblock checksum: add-with-carry over 256 longwords, then invert
    var _sum = 0;
    for (var i = 0; i < 256; i++)
    {
        if (i == 1) { continue; }
        _sum += peek32(_adf, i * 4);
        if (_sum > 0xffffffff) { _sum = (_sum & 0xffffffff) + 1; }
    }
    poke32(_adf, 4, 0xffffffff - _sum);
    buffer_copy(_eng, 0, _esize, _adf, 1024);
    buffer_copy(_data.buf, 0, _data.size, _adf, 1024 + _esize);
    buffer_save(_adf, _path);
    buffer_delete(_adf);
    buffer_delete(_eng);
    buffer_delete(_boot);
    buffer_delete(_data.buf);

    build_ok = true;
    build_stamp = current_time;
    build_size = _game;
    build_engine_size = _esize;
    build_plane_size = _data.plane_bytes;
    build_sound_size = _data.sound_bytes;
    build_chip_free = _chip_free;
    build_msg = "Built " + filename_name(_path) + " for the " + _m.name + " - " + string(ceil(_game / 1024)) + " KB of chip RAM";
    if (!_m.aga && _game > (A500_512K_CHIP_KB - OS_RESERVE_KB) * 1024)
    {
        array_push(build_warnings, "Too big for an A500 with only 512KB of chip RAM (about " + string(A500_512K_CHIP_KB - OS_RESERVE_KB) + " KB free) - it will show a red screen there. Fine on 1MB machines.");
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

/// The fs-uae.exe (FS-UAE.app on a Mac) ADAM will run, or "" when there is none
function fsuae_exe()
{
    if (fsuae_path_ok(fsuae_path)) { return fsuae_path; }
    if (ADAM_DEV_TOOLS && file_exists(fsuae_test_exe())) { return fsuae_test_exe(); }
    return fsuae_find_installed();
}

/// Text for the Build page: where FS-UAE comes from
function fsuae_source_label()
{
    if (fsuae_path_ok(fsuae_path)) { return fsuae_path; }
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
        if (os_type == os_macosx)
        {
            toast("Install FS-UAE in Applications, or Find it on the Build page", 1);
            return false;
        }
        toast("Find fs-uae.exe on the Build page first", 1);
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
    array_push(build_listing, ";   machine " + machine_cur().name + ", " + string(pal_count()) + " colours, " + string(array_length(proj.actors)) + " actors, " + string(array_length(proj.rules)) + " rules, 8 sounds");
}
