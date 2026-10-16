/// ADAM Pro - loading screen: a picture shown while the game loads, with a
/// bar made of a left cap, a repeating middle tile and a right cap that fills
/// from left to right. The bootblock reads it before the game (boot.s,
/// loadscr.s); this script makes its data block. The same layout is in
/// tools/reference/adf_reference.py.

#macro LS_BAR_H_MIN 4
#macro LS_BAR_H_MAX 64
#macro LS_PIECE_W_MAX 32
#macro LS_HDR 40                 // loadscr.s LS_SIZE

function loadscr_new()
{
    return {
        on : false,                       // show the loading screen (ADAM Pro)
        source : 0,                       // 0 = the game's backdrop, 1 = its own picture
        pixels : [],                      // own picture: 320 x 256 colour numbers (source 1)
        pal : [],                         // own picture: 0xRRGGBB colours
        depth : 5,                        // own picture: bitplanes (A500/600 up to 5, A1200 up to 8)
        bar_x : 32,
        bar_y : 216,
        bar_w : 256,
        bar_h : 16,
        style : "Metal",                  // a HUD frame preset, or "Custom" (the pieces below)
        left_w : 8,
        mid_w : 8,
        right_w : 8,
        left : [],                        // left_w x bar_h colour numbers, 0 = see-through
        mid : [],                         // mid_w x bar_h, repeated along the bar
        right : [],                       // right_w x bar_h
        empty : 0                         // the empty bar: 0 = a darker copy of the full one, 1 = the picture
    };
}

function loadscr_from_loaded(_raw)
{
    var _l = loadscr_new();
    if (!is_struct(_raw)) { return _l; }
    var _on = _raw[$ "on"];
    if (is_numeric(_on)) { _l.on = (_on != 0); }
    var _nums = ["source", "depth", "bar_x", "bar_y", "bar_w", "bar_h", "left_w", "mid_w", "right_w", "empty"];
    for (var i = 0; i < array_length(_nums); i++)
    {
        var _v = _raw[$ _nums[i]];
        if (is_numeric(_v)) { _l[$ _nums[i]] = floor(_v); }
    }
    if (is_string(_raw[$ "style"])) { _l.style = _raw.style; }
    _l.source = clamp(_l.source, 0, 1);
    _l.depth = clamp(_l.depth, 1, 8);
    _l.empty = clamp(_l.empty, 0, 1);
    _l.bar_h = clamp(_l.bar_h, LS_BAR_H_MIN, LS_BAR_H_MAX);
    _l.left_w = clamp(_l.left_w, 1, LS_PIECE_W_MAX);
    _l.mid_w = clamp(_l.mid_w, 1, LS_PIECE_W_MAX);
    _l.right_w = clamp(_l.right_w, 1, LS_PIECE_W_MAX);
    _l.bar_w = clamp(_l.bar_w, _l.left_w + _l.right_w, BD_W);
    _l.bar_x = clamp(_l.bar_x, 0, BD_W - _l.bar_w);
    _l.bar_y = clamp(_l.bar_y, 0, BD_H - _l.bar_h);
    var _px = _raw[$ "pixels"];
    if (is_array(_px) && array_length(_px) == BD_W * BD_H) { _l.pixels = loadscr_clean_px(_px, 255); }
    var _pal = _raw[$ "pal"];
    if (is_array(_pal))
    {
        for (var c = 0; c < min(256, array_length(_pal)); c++)
        {
            var _col = 0;
            if (is_numeric(_pal[c])) { _col = clamp(floor(_pal[c]), 0, 0xffffff); }
            array_push(_l.pal, _col);
        }
    }
    if (_l.source == 1 && (array_length(_l.pixels) != BD_W * BD_H || array_length(_l.pal) < 2)) { _l.source = 0; }
    _l.left = loadscr_piece_from(_raw[$ "left"], _l.left_w * _l.bar_h);
    _l.mid = loadscr_piece_from(_raw[$ "mid"], _l.mid_w * _l.bar_h);
    _l.right = loadscr_piece_from(_raw[$ "right"], _l.right_w * _l.bar_h);
    if (_l.style == "Custom" && (array_length(_l.left) == 0 || array_length(_l.mid) == 0 || array_length(_l.right) == 0)) { _l.style = "Metal"; }
    return _l;
}

function loadscr_clean_px(_a, _max)
{
    var _out = array_create(array_length(_a), 0);
    for (var i = 0; i < array_length(_a); i++)
    {
        if (is_numeric(_a[i])) { _out[i] = clamp(floor(_a[i]), 0, _max); }
    }
    return _out;
}

function loadscr_piece_from(_a, _n)
{
    if (!is_array(_a) || array_length(_a) != _n) { return []; }
    return loadscr_clean_px(_a, 255);
}

/// Bitplanes the loading screen may use on this machine
function loadscr_max_depth(_aga)
{
    if (_aga) { return 8; }
    return 5;
}

/// The picture the loading screen shows: { pixels, pal, depth, ncol }
function loadscr_picture(_p)
{
    var _l = _p.loadscr;
    var _aga = machine_get(_p.machine).aga;
    var _md = loadscr_max_depth(_aga);
    var _res = { pixels : _p.pixels, pal : _p.pal, depth : clamp(_p.depth, 1, _md), ncol : 0 };
    if (_l.source == 1 && array_length(_l.pixels) == BD_W * BD_H && array_length(_l.pal) >= 2)
    {
        _res.pixels = _l.pixels;
        _res.pal = _l.pal;
        _res.depth = clamp(_l.depth, 1, _md);
    }
    _res.ncol = min(1 << _res.depth, array_length(_res.pal));
    return _res;
}

/// The colour in _pal (first _n) nearest 0xRRGGBB _rgb, never 0 unless _allow0
function loadscr_nearest(_pal, _n, _rgb, _allow0)
{
    var _r = (_rgb >> 16) & 255;
    var _g = (_rgb >> 8) & 255;
    var _b = _rgb & 255;
    var _best = 1;
    if (_allow0) { _best = 0; }
    var _bd = 1000000000;
    var _start = 1;
    if (_allow0) { _start = 0; }
    for (var c = _start; c < _n; c++)
    {
        var _q = _pal[c];
        var _dr = ((_q >> 16) & 255) - _r;
        var _dg = ((_q >> 8) & 255) - _g;
        var _db = (_q & 255) - _b;
        var _d = _dr * _dr * 3 + _dg * _dg * 4 + _db * _db * 2;
        if (_d < _bd) { _bd = _d; _best = c; }
    }
    return _best;
}

/// The bar pieces in the picture's colours: { left, mid, right } (0 = see-through)
function loadscr_pieces(_l, _pic)
{
    if (_l.style == "Custom") { return { left : _l.left, mid : _l.mid, right : _l.right }; }
    return loadscr_preset_pieces(_l, _pic, _l.style);
}

/// A HUD frame preset cut into a left cap, a middle tile and a right cap of the bar's height
function loadscr_preset_pieces(_l, _pic, _style)
{
    var _h = _l.bar_h;
    var _out = { left : array_create(_l.left_w * _h, 0), mid : array_create(_l.mid_w * _h, 0), right : array_create(_l.right_w * _h, 0) };
    var _cache = {};
    for (var _py = 0; _py < _h; _py++)
    {
        // rows: the frame's top 8, its middle 8 repeated, its bottom 8 (short bars: top and bottom halves)
        var _fy = 0;
        if (_h >= 16)
        {
            if (_py < 8) { _fy = _py; }
            else if (_py >= _h - 8) { _fy = 16 + _py - (_h - 8); }
            else { _fy = 8 + (_py - 8) mod 8; }
        }
        else
        {
            if (_py < _h div 2) { _fy = _py; }
            else { _fy = 24 - (_h - _py); }
        }
        for (var _k = 0; _k < 3; _k++)
        {
            var _w = _l.left_w;
            var _arr = _out.left;
            if (_k == 1) { _w = _l.mid_w; _arr = _out.mid; }
            if (_k == 2) { _w = _l.right_w; _arr = _out.right; }
            for (var _px = 0; _px < _w; _px++)
            {
                var _fx = 8 + _px mod 8;
                if (_k == 0) { _fx = min(_px, 7); if (_px >= 8) { _fx = 8 + (_px - 8) mod 8; } }
                if (_k == 2) { _fx = 23 - min(_w - 1 - _px, 7); if (_w - 1 - _px >= 8) { _fx = 8 + _px mod 8; } }
                var _c = ui_frame_rgb(_style, _fx, _fy);
                if (_c < 0) { continue; }
                var _ck = string(_c);
                var _hit = _cache[$ _ck];
                if (is_undefined(_hit))
                {
                    _hit = loadscr_nearest(_pic.pal, _pic.ncol, _c, false);
                    _cache[$ _ck] = _hit;
                }
                _arr[_py * _w + _px] = _hit;
            }
        }
    }
    return _out;
}

/// The full bar's colour at bar pixel (_u, _v), 0 = see-through
function loadscr_bar_px(_l, _pc, _u, _v)
{
    if (_u < _l.left_w) { return _pc.left[_v * _l.left_w + _u]; }
    var _ru = _u - (_l.bar_w - _l.right_w);
    if (_ru >= 0) { return _pc.right[_v * _l.right_w + _ru]; }
    return _pc.mid[_v * _l.mid_w + (_u - _l.left_w) mod _l.mid_w];
}

/// The screens the loader shows: { screen (empty bar), full (full bar), pal, depth, ncol }
/// Both are 320 x 256 colour numbers; they only differ inside the bar.
function loadscr_compose(_p)
{
    var _l = _p.loadscr;
    var _pic = loadscr_picture(_p);
    var _pc = loadscr_pieces(_l, _pic);
    var _screen = array_create(BD_W * BD_H, 0);
    array_copy(_screen, 0, _pic.pixels, 0, BD_W * BD_H);
    var _maxc = _pic.ncol - 1;
    for (var i = 0; i < BD_W * BD_H; i++) { _screen[i] = min(_screen[i], _maxc); }
    var _full = array_create(BD_W * BD_H, 0);
    array_copy(_full, 0, _screen, 0, BD_W * BD_H);
    // the empty bar: each colour of the full bar made darker
    var _dark = array_create(_pic.ncol, 0);
    for (var c = 0; c < _pic.ncol; c++)
    {
        var _q = _pic.pal[c];
        var _dr = floor(((_q >> 16) & 255) * 0.4);
        var _dg = floor(((_q >> 8) & 255) * 0.4);
        var _db = floor((_q & 255) * 0.4);
        _dark[c] = loadscr_nearest(_pic.pal, _pic.ncol, (_dr << 16) | (_dg << 8) | _db, true);
    }
    for (var _v = 0; _v < _l.bar_h; _v++)
    {
        for (var _u = 0; _u < _l.bar_w; _u++)
        {
            var _c = loadscr_bar_px(_l, _pc, _u, _v);
            if (_c <= 0) { continue; }
            _c = min(_c, _maxc);
            var _at = (_l.bar_y + _v) * BD_W + _l.bar_x + _u;
            _full[_at] = _c;
            if (_l.empty == 0) { _screen[_at] = _dark[_c]; }
        }
    }
    return { screen : _screen, full : _full, pal : _pic.pal, depth : _pic.depth, ncol : _pic.ncol };
}

/// The copper sky the loading screen shows: the game's, when it shows the backdrop and the
/// game has one (256 0xRRGGBB colours, one a line), else undefined
function loadscr_sky(_p)
{
    if (_p.loadscr.source == 0 && _p.sky_on) { return sky_table(_p); }
    return undefined;
}

/// The loader's copper list as [register, value] pairs; pointer values are
/// offsets from the block start (loadscr.s adds the block's address). _sky: the copper
/// sky (colour 0 on each line), or undefined. A WAIT is [line << 8 | 0x07, 0xfffe].
function loadscr_copper(_depth, _aga, _pal, _ncol, _planes_off, _spr_off, _sky = undefined)
{
    var _c = [];
    var _con0 = ((_depth & 7) << 12) | 0x200;
    if (_depth == 8) { _con0 = _con0 | 0x10; }
    array_push(_c, [0x100, _con0], [0x102, 0], [0x104, 0], [0x8e, 0x2c81], [0x90, 0x2cc1], [0x92, 0x38], [0x94, 0xd0], [0x108, 0], [0x10a, 0]);
    if (_aga) { array_push(_c, [0x1fc, 0], [0x10c, 0x0011], [0x106, 0x0c00]); }
    for (var p = 0; p < _depth; p++)
    {
        var _o = _planes_off + p * 10240;
        array_push(_c, [0xe0 + p * 4, (_o >> 16) & 0xffff], [0xe2 + p * 4, _o & 0xffff]);
    }
    for (var s = 0; s < 8; s++) { array_push(_c, [0x120 + s * 4, (_spr_off >> 16) & 0xffff], [0x122 + s * 4, _spr_off & 0xffff]); }
    if (!_aga)
    {
        for (var k = 0; k < min(_ncol, 32); k++)
        {
            var _q = _pal[k];
            array_push(_c, [0x180 + k * 2, (((_q >> 20) & 15) << 8) | (((_q >> 12) & 15) << 4) | ((_q >> 4) & 15)]);
        }
    }
    else
    {
        // AGA: 24-bit colours, 32 per bank - the high nibbles, then the low nibbles with LOCT
        var _banks = ceil(_ncol / 32);
        for (var b = 0; b < _banks; b++)
        {
            array_push(_c, [0x106, (b << 13) | 0x0c00]);
            for (var k2 = 0; k2 < 32; k2++)
            {
                var _ci = b * 32 + k2;
                if (_ci >= _ncol) { break; }
                var _q2 = _pal[_ci];
                array_push(_c, [0x180 + k2 * 2, (((_q2 >> 20) & 15) << 8) | (((_q2 >> 12) & 15) << 4) | ((_q2 >> 4) & 15)]);
            }
            array_push(_c, [0x106, (b << 13) | 0x0e00]);
            for (var k3 = 0; k3 < 32; k3++)
            {
                var _cj = b * 32 + k3;
                if (_cj >= _ncol) { break; }
                var _q3 = _pal[_cj];
                array_push(_c, [0x180 + k3 * 2, (((_q3 >> 16) & 15) << 8) | (((_q3 >> 8) & 15) << 4) | (_q3 & 15)]);
            }
        }
        array_push(_c, [0x106, 0x0c00]);
    }
    if (!is_undefined(_sky))
    {
        // the copper sky: colour 0 changes on every line, as in the game (build_grad)
        for (var _ln = 0; _ln < 256; _ln++)
        {
            var _vl = _ln + 0x2c;
            if (_vl == 0x100) { array_push(_c, [0xffdf, 0xfffe]); }      // past line 255: wait for the wrap
            if (_ln > 0) { array_push(_c, [((_vl & 0xff) << 8) | 0x07, 0xfffe]); }
            array_push(_c, [0x180, copper_hi(_sky[_ln])]);
            if (_aga)
            {
                array_push(_c, [0x106, 0x0e00]);
                array_push(_c, [0x180, copper_lo(_sky[_ln])]);
                array_push(_c, [0x106, 0x0c00]);
            }
        }
    }
    return _c;
}

/// The loading-screen block for the disk: { buf, size (padded to sectors), mem }
/// (loadscr.bin, then the LS_* header, copper list, empty sprite, picture
/// planes and the full bar strip). _measure: sizes only, no picture work.
function loadscr_block(_p, _measure = false)
{
    var _l = _p.loadscr;
    var _aga = machine_get(_p.machine).aga;
    var _f = working_directory + "engine/loadscr.bin";
    if (!file_exists(_f)) { return undefined; }
    var _code = buffer_load(_f);
    var _csize = buffer_get_size(_code);
    var _pic = loadscr_picture(_p);
    var _depth = _pic.depth;
    var _sx0 = _l.bar_x >> 3;
    var _stride = ((_l.bar_x + _l.bar_w - 1) >> 3) - _sx0 + 1;
    var _hdr = _csize;
    var _cop_off = _hdr + LS_HDR;
    var _sky = loadscr_sky(_p);
    var _ncop = array_length(loadscr_copper(_depth, _aga, _pic.pal, _pic.ncol, 0, 0, _sky)) + 1;
    var _spr_off = _cop_off + _ncop * 4;
    _spr_off = ((_spr_off + 7) >> 3) << 3;
    var _planes_off = _spr_off + 8;
    var _strip_off = _planes_off + _depth * 10240;
    var _end = _strip_off + _stride * _l.bar_h * _depth;
    var _size = ((_end + 511) >> 9) << 9;
    if (_measure)
    {
        buffer_delete(_code);
        return { buf : -1, size : _size, mem : _size };
    }
    var _cmp = loadscr_compose(_p);
    var _b = buffer_create(_size, buffer_fixed, 1);
    buffer_fill(_b, 0, buffer_u8, 0, _size);
    buffer_copy(_code, 0, _csize, _b, 0);
    buffer_delete(_code);
    // header
    buffer_seek(_b, buffer_seek_start, _hdr);
    buffer_write(_b, buffer_u8, ord("L"));
    buffer_write(_b, buffer_u8, ord("S"));
    buffer_write(_b, buffer_u8, ord("C"));
    buffer_write(_b, buffer_u8, ord("R"));
    be16(_b, 1);                                 // LS_VER
    var _flags = 0;
    if (_aga) { _flags = 1; }
    be16(_b, _flags);                            // LS_FLAGS
    be16(_b, _depth);                            // LS_DEPTH
    be16(_b, 0);                                 // LS_MODE: left to right
    be32(_b, _cop_off);                          // LS_COPPER
    be32(_b, _planes_off);                       // LS_PLANES
    be32(_b, _strip_off);                        // LS_STRIP
    be16(_b, _l.bar_x);
    be16(_b, _l.bar_y);
    be16(_b, _l.bar_w);
    be16(_b, _l.bar_h);
    be16(_b, _sx0);                              // LS_SX0
    be16(_b, _stride);                           // LS_SSTRIDE
    // copper list
    buffer_seek(_b, buffer_seek_start, _cop_off);
    var _cop = loadscr_copper(_depth, _aga, _cmp.pal, _cmp.ncol, _planes_off, _spr_off, _sky);
    for (var i = 0; i < array_length(_cop); i++)
    {
        be16(_b, _cop[i][0]);
        be16(_b, _cop[i][1]);
    }
    be16(_b, 0xffff);
    be16(_b, 0xfffe);
    // picture planes, then the strip of the full bar (whole bytes)
    buffer_seek(_b, buffer_seek_start, _planes_off);
    for (var p = 0; p < _depth; p++)
    {
        for (var _y = 0; _y < BD_H; _y++)
        {
            var _row = _y * BD_W;
            for (var _xb = 0; _xb < 40; _xb++)
            {
                var _v = 0;
                var _at = _row + _xb * 8;
                for (var bit = 0; bit < 8; bit++) { _v = (_v << 1) | ((_cmp.screen[_at + bit] >> p) & 1); }
                buffer_write(_b, buffer_u8, _v);
            }
        }
    }
    buffer_seek(_b, buffer_seek_start, _strip_off);
    for (var p2 = 0; p2 < _depth; p2++)
    {
        for (var _r = 0; _r < _l.bar_h; _r++)
        {
            var _row2 = (_l.bar_y + _r) * BD_W;
            for (var _sb = 0; _sb < _stride; _sb++)
            {
                var _v2 = 0;
                var _at2 = _row2 + (_sx0 + _sb) * 8;
                for (var bit2 = 0; bit2 < 8; bit2++) { _v2 = (_v2 << 1) | ((_cmp.full[_at2 + bit2] >> p2) & 1); }
                buffer_write(_b, buffer_u8, _v2);
            }
        }
    }
    return { buf : _b, size : _size, mem : _size };
}

/// True when the game's disk gets the loading screen (ADAM Pro, switched on)
function loadscr_active(_p)
{
    return (pro_edition() && _p.loadscr.on);
}

/// What loadscr.s does for progress _prog (0..1024), on a copy of the block's
/// planes (dev self-test): returns the planes after the reveal
function loadscr_sim_reveal(_b, _hdr, _prog)
{
    var _depth = buffer_peek(_b, _hdr + 8, buffer_u8) * 256 + buffer_peek(_b, _hdr + 9, buffer_u8);
    var _planes = peek32(_b, _hdr + 16);
    var _strip = peek32(_b, _hdr + 20);
    var _bx = buffer_peek(_b, _hdr + 24, buffer_u8) * 256 + buffer_peek(_b, _hdr + 25, buffer_u8);
    var _by = buffer_peek(_b, _hdr + 26, buffer_u8) * 256 + buffer_peek(_b, _hdr + 27, buffer_u8);
    var _bw = buffer_peek(_b, _hdr + 28, buffer_u8) * 256 + buffer_peek(_b, _hdr + 29, buffer_u8);
    var _bh = buffer_peek(_b, _hdr + 30, buffer_u8) * 256 + buffer_peek(_b, _hdr + 31, buffer_u8);
    var _sx0 = buffer_peek(_b, _hdr + 32, buffer_u8) * 256 + buffer_peek(_b, _hdr + 33, buffer_u8);
    var _st = buffer_peek(_b, _hdr + 34, buffer_u8) * 256 + buffer_peek(_b, _hdr + 35, buffer_u8);
    var _out = array_create(_depth * 10240, 0);
    for (var i = 0; i < _depth * 10240; i++) { _out[i] = buffer_peek(_b, _planes + i, buffer_u8); }
    var _px = (_bw * _prog) >> 10;
    var _x0 = _bx;
    var _x1 = _bx + _px;
    for (var _col = _x0 >> 3; _col * 8 < _x1; _col++)
    {
        var _lo = max(0, _x0 - _col * 8);
        var _hi = min(8, _x1 - _col * 8);
        var _mask = (0xff >> _lo) & ~(0xff >> _hi) & 0xff;
        for (var p = 0; p < _depth; p++)
        {
            for (var r = 0; r < _bh; r++)
            {
                var _si = _strip + p * _st * _bh + r * _st + (_col - _sx0);
                var _di = p * 10240 + (_by + r) * 40 + _col;
                _out[_di] = (_out[_di] & ~_mask & 0xff) | (buffer_peek(_b, _si, buffer_u8) & _mask);
            }
        }
    }
    return _out;
}

/// Dev self-test: the block's layout, and a full reveal gives the full bar's planes
function loadscr_selftest()
{
    var _ok = true;
    var _keep = proj;
    proj = project_new();
    proj.loadscr.on = true;
    proj.loadscr.bar_x = 21;
    proj.loadscr.bar_w = 203;
    proj.loadscr.bar_y = 200;
    proj.loadscr.bar_h = 12;
    for (var i = 0; i < BD_W * BD_H; i++) { proj.pixels[i] = (i * 7 + (i div BD_W)) mod 16; }
    var _blk = loadscr_block(proj);
    if (is_undefined(_blk)) { _ok = false; }
    else
    {
        var _b = _blk.buf;
        var _hdr = 0;
        var _code = buffer_load(working_directory + "engine/loadscr.bin");
        _hdr = buffer_get_size(_code);
        buffer_delete(_code);
        if (_hdr mod 8 != 0) { _ok = false; }
        if (buffer_peek(_b, _hdr, buffer_u8) != ord("L") || buffer_peek(_b, _hdr + 3, buffer_u8) != ord("R")) { _ok = false; }
        if (_blk.size mod 512 != 0 || _blk.size != loadscr_block(proj, true).size) { _ok = false; }
        if (peek32(_b, _hdr + 16) mod 8 != 0) { _ok = false; }
        var _cmp = loadscr_compose(proj);
        var _depth = _cmp.depth;
        // the full reveal must match the full bar's planes; the half reveal must stop at the right pixel
        var _all = loadscr_sim_reveal(_b, _hdr, 1024);
        var _half = loadscr_sim_reveal(_b, _hdr, 512);
        var _cut = 21 + (203 * 512 >> 10);
        for (var _y = 200; _y < 212; _y++)
        {
            for (var _x = 0; _x < BD_W; _x++)
            {
                var _full_c = 0;
                var _half_c = 0;
                for (var p = 0; p < _depth; p++)
                {
                    var _bitv = 0x80 >> (_x & 7);
                    if ((_all[p * 10240 + _y * 40 + (_x >> 3)] & _bitv) != 0) { _full_c |= (1 << p); }
                    if ((_half[p * 10240 + _y * 40 + (_x >> 3)] & _bitv) != 0) { _half_c |= (1 << p); }
                }
                if (_full_c != _cmp.full[_y * BD_W + _x]) { _ok = false; }
                var _want = _cmp.screen[_y * BD_W + _x];
                if (_x >= 21 && _x < _cut) { _want = _cmp.full[_y * BD_W + _x]; }
                if (_half_c != _want) { _ok = false; }
            }
        }
        buffer_delete(_b);
    }
    var _back = loadscr_from_loaded(json_parse(json_stringify({ on : 1, bar_w : 9999, bar_x : -5, style : "Custom", source : 1 })));
    if (!_back.on || _back.bar_w != BD_W || _back.bar_x != 0 || _back.style != "Metal" || _back.source != 0) { _ok = false; }
    proj = _keep;
    if (_ok) { show_debug_message("ADAM loading screen self-test: PASS"); }
    else { show_debug_message("ADAM loading screen self-test: FAIL"); }
}

// ---------------------------------------------------------------------------
// Editor: the Loading screen tab of the UI page (ADAM Pro)
// ---------------------------------------------------------------------------

function loadscr_gfx_free()
{
    if (surface_exists(ls_surf_empty)) { surface_free(ls_surf_empty); }
    if (surface_exists(ls_surf_full)) { surface_free(ls_surf_full); }
    if (buffer_exists(ls_buf)) { buffer_delete(ls_buf); }
    ls_key = "";
}

/// Keeps the bar on the screen and at least as wide as its caps
function loadscr_fix(_l)
{
    _l.bar_h = clamp(_l.bar_h, LS_BAR_H_MIN, LS_BAR_H_MAX);
    _l.left_w = clamp(_l.left_w, 1, LS_PIECE_W_MAX);
    _l.mid_w = clamp(_l.mid_w, 1, LS_PIECE_W_MAX);
    _l.right_w = clamp(_l.right_w, 1, LS_PIECE_W_MAX);
    _l.bar_w = clamp(_l.bar_w, _l.left_w + _l.right_w, BD_W);
    _l.bar_x = clamp(_l.bar_x, 0, BD_W - _l.bar_w);
    _l.bar_y = clamp(_l.bar_y, 0, BD_H - _l.bar_h);
}

/// A piece of _ow x _oh pixels cut or padded (see-through) to _nw x _nh
function loadscr_piece_resize(_a, _ow, _oh, _nw, _nh)
{
    var _out = array_create(_nw * _nh, 0);
    if (array_length(_a) != _ow * _oh) { return _out; }
    for (var _py = 0; _py < min(_oh, _nh); _py++)
    {
        for (var _px = 0; _px < min(_ow, _nw); _px++) { _out[_py * _nw + _px] = _a[_py * _ow + _px]; }
    }
    return _out;
}

/// After the bar's height or a piece's width changed: drawn pieces keep their pixels
function loadscr_pieces_refit(_l, _oh, _olw, _omw, _orw)
{
    if (_l.style != "Custom") { return; }
    if (_l.bar_h == _oh && _l.left_w == _olw && _l.mid_w == _omw && _l.right_w == _orw) { return; }
    _l.left = loadscr_piece_resize(_l.left, _olw, _oh, _l.left_w, _l.bar_h);
    _l.mid = loadscr_piece_resize(_l.mid, _omw, _oh, _l.mid_w, _l.bar_h);
    _l.right = loadscr_piece_resize(_l.right, _orw, _oh, _l.right_w, _l.bar_h);
}

/// Before the first stroke on a piece: the preset becomes the drawn pieces
function loadscr_make_custom(_l, _pic)
{
    if (_l.style == "Custom") { return; }
    var _pc = loadscr_preset_pieces(_l, _pic, _l.style);
    _l.left = _pc.left;
    _l.mid = _pc.mid;
    _l.right = _pc.right;
    _l.style = "Custom";
}

/// Fewer (or more) colours for the loading screen's own picture: going down,
/// each pixel takes the nearest of the colours that are left
function loadscr_set_depth(_l, _depth)
{
    var _old = _l.depth;
    _l.depth = _depth;
    if (_l.source != 1 || _depth >= _old) { return; }
    var _n = min(1 << _depth, array_length(_l.pal));
    var _map = array_create(256, 0);
    for (var c = 0; c < 256; c++)
    {
        if (c < _n) { _map[c] = c; }
        else if (c < array_length(_l.pal)) { _map[c] = loadscr_nearest(_l.pal, _n, _l.pal[c], true); }
    }
    for (var i = 0; i < array_length(_l.pixels); i++) { _l.pixels[i] = _map[_l.pixels[i]]; }
    for (var j = 0; j < array_length(_l.left); j++) { _l.left[j] = max(min(_l.left[j], 1), _map[_l.left[j]]); }
    for (var j2 = 0; j2 < array_length(_l.mid); j2++) { _l.mid[j2] = max(min(_l.mid[j2], 1), _map[_l.mid[j2]]); }
    for (var j3 = 0; j3 < array_length(_l.right); j3++) { _l.right[j3] = max(min(_l.right[j3], 1), _map[_l.right[j3]]); }
}

/// Imports a picture file as the loading screen's own picture
function loadscr_import_picture(_l, _path)
{
    var _md = loadscr_max_depth(machine_cur().aga);
    _l.depth = clamp(_l.depth, 1, _md);
    var _q = picture_quantize(_path, 1 << _l.depth, bd_dither);
    if (is_undefined(_q)) { return false; }
    _l.pixels = _q.pixels;
    _l.pal = _q.pal;
    _l.source = 1;
    return true;
}

/// Imports a picture of the bar: the left cap, middle tile and right cap side by
/// side. Exactly left + middle + right wide keeps the widths; otherwise it is cut
/// into three equal parts. Its height is the bar's; see-through pixels stay
/// see-through. Returns "" or what was wrong.
function loadscr_import_strip(_l, _pic, _path)
{
    var _spr = sprite_add(_path, 1, false, false, 0, 0);
    if (_spr == -1) { return "That picture could not be read"; }
    var _w = sprite_get_width(_spr);
    var _h = sprite_get_height(_spr);
    var _lw = _l.left_w;
    var _mw = _l.mid_w;
    var _rw = _l.right_w;
    if (_w != _lw + _mw + _rw)
    {
        if (_w mod 3 != 0 || _w div 3 > LS_PIECE_W_MAX || _w < 3)
        {
            sprite_delete(_spr);
            return "The strip must be 3 equal parts of up to " + string(LS_PIECE_W_MAX) + " pixels (or left + middle + right wide)";
        }
        _lw = _w div 3;
        _mw = _lw;
        _rw = _lw;
    }
    if (_h < LS_BAR_H_MIN || _h > LS_BAR_H_MAX)
    {
        sprite_delete(_spr);
        return "The strip must be " + string(LS_BAR_H_MIN) + " to " + string(LS_BAR_H_MAX) + " pixels high";
    }
    var _surf = surface_create(_w, _h);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 0);
    gpu_set_blendenable(false);
    draw_sprite(_spr, 0, 0, 0);
    gpu_set_blendenable(true);
    surface_reset_target();
    sprite_delete(_spr);
    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _surf, 0);
    surface_free(_surf);
    var _ord = surface_byte_order();
    var _all = array_create(_w * _h, 0);
    var _cache = {};
    for (var i = 0; i < _w * _h; i++)
    {
        if (buffer_peek(_buf, i * 4 + 3, buffer_u8) < 128) { continue; }
        var _rgb = rgb_make(buffer_peek(_buf, i * 4 + _ord[0], buffer_u8), buffer_peek(_buf, i * 4 + _ord[1], buffer_u8), buffer_peek(_buf, i * 4 + _ord[2], buffer_u8));
        var _ck = string(_rgb);
        var _hit = _cache[$ _ck];
        if (is_undefined(_hit))
        {
            _hit = loadscr_nearest(_pic.pal, _pic.ncol, _rgb, false);
            _cache[$ _ck] = _hit;
        }
        _all[i] = _hit;
    }
    buffer_delete(_buf);
    _l.left_w = _lw;
    _l.mid_w = _mw;
    _l.right_w = _rw;
    _l.bar_h = _h;
    _l.left = array_create(_lw * _h, 0);
    _l.mid = array_create(_mw * _h, 0);
    _l.right = array_create(_rw * _h, 0);
    for (var _py = 0; _py < _h; _py++)
    {
        for (var a = 0; a < _lw; a++) { _l.left[_py * _lw + a] = _all[_py * _w + a]; }
        for (var b = 0; b < _mw; b++) { _l.mid[_py * _mw + b] = _all[_py * _w + _lw + b]; }
        for (var c = 0; c < _rw; c++) { _l.right[_py * _rw + c] = _all[_py * _w + _lw + _mw + c]; }
    }
    _l.style = "Custom";
    loadscr_fix(_l);
    return "";
}

/// Updates the preview surfaces (the picture with the empty and with the full
/// bar) when anything they show changed; keeps the picture and pieces in ls_pic / ls_pc
function loadscr_preview_update(_p)
{
    var _l = _p.loadscr;
    var _src = _p.pixels;
    if (_l.source == 1 && array_length(_l.pixels) == BD_W * BD_H) { _src = _l.pixels; }
    var _hash = 0;
    for (var i = 0; i < BD_W * BD_H; i += 37) { _hash = (_hash * 31 + _src[i] + i) mod 1000000007; }
    var _key = string(_l.source) + "," + string(_l.depth) + "," + string(_l.bar_x) + "," + string(_l.bar_y) + "," + string(_l.bar_w) + "," + string(_l.bar_h) + "," + _l.style + "," + string(_l.left_w) + "," + string(_l.mid_w) + "," + string(_l.right_w) + "," + string(_l.empty) + "|" + string(_hash) + "|" + string(_p.depth) + "," + string(_p.machine) + "|" + json_stringify(_l.left) + json_stringify(_l.mid) + json_stringify(_l.right);
    if (_l.source == 1) { _key += json_stringify(_l.pal); }
    else { _key += json_stringify(_p.pal); }
    var _sky = loadscr_sky(_p);                 // colour 0: the copper sky, line by line
    if (!is_undefined(_sky)) { _key += "|sky" + json_stringify(_sky); }
    if (_key == ls_key && surface_exists(ls_surf_empty) && surface_exists(ls_surf_full)) { return; }
    ls_key = _key;
    var _cmp = loadscr_compose(_p);
    ls_pic = loadscr_picture(_p);
    ls_pc = loadscr_pieces(_l, ls_pic);
    var _ord = surface_byte_order();
    var _lut = array_create(256, 0xff000000);
    for (var c = 0; c < _cmp.ncol; c++)
    {
        var _m = rgb_machine(_cmp.pal[c]);
        _lut[c] = 0xff000000 | (rgb_r(_m) << (_ord[0] * 8)) | (rgb_g(_m) << (_ord[1] * 8)) | (rgb_b(_m) << (_ord[2] * 8));
    }
    if (!buffer_exists(ls_buf)) { ls_buf = buffer_create(BD_W * BD_H * 4, buffer_fixed, 1); }
    if (!surface_exists(ls_surf_empty)) { ls_surf_empty = surface_create(BD_W, BD_H); }
    if (!surface_exists(ls_surf_full)) { ls_surf_full = surface_create(BD_W, BD_H); }
    var _skyc = array_create(BD_H, _lut[0]);
    if (!is_undefined(_sky))
    {
        for (var s = 0; s < BD_H; s++)
        {
            var _sm = rgb_machine(_sky[s]);
            _skyc[s] = 0xff000000 | (rgb_r(_sm) << (_ord[0] * 8)) | (rgb_g(_sm) << (_ord[1] * 8)) | (rgb_b(_sm) << (_ord[2] * 8));
        }
    }
    buffer_seek(ls_buf, buffer_seek_start, 0);
    for (var j = 0; j < BD_W * BD_H; j++)
    {
        var _cj = _cmp.screen[j];
        if (_cj == 0) { buffer_write(ls_buf, buffer_u32, _skyc[j div BD_W]); }
        else { buffer_write(ls_buf, buffer_u32, _lut[_cj]); }
    }
    buffer_set_surface(ls_buf, ls_surf_empty, 0);
    buffer_seek(ls_buf, buffer_seek_start, 0);
    for (var k = 0; k < BD_W * BD_H; k++)
    {
        var _ck = _cmp.full[k];
        if (_ck == 0) { buffer_write(ls_buf, buffer_u32, _skyc[k div BD_W]); }
        else { buffer_write(ls_buf, buffer_u32, _lut[_ck]); }
    }
    buffer_set_surface(ls_buf, ls_surf_full, 0);
}

/// GameMaker colour of loading-screen colour _c
function loadscr_col(_c)
{
    var _pal = ls_pic.pal;
    if (_c < 0 || _c >= array_length(_pal)) { return c_black; }
    return amiga_col(_pal[_c]);
}

/// A grid of the loading screen's colours (the backdrop's, or its own picture's).
/// Returns the colour picked.
function loadscr_pal_grid(_id, _x, _y, _cell, _cols, _value, _help)
{
    var _v = _value;
    var _n = ls_pic.ncol;
    for (var i = 0; i < _n; i++)
    {
        var _cx = _x + (i mod _cols) * (_cell + 3);
        var _cy = _y + (i div _cols) * (_cell + 3);
        var _hot = ui_register(_id + "_" + string(i), _cx, _cy, _cx + _cell, _cy + _cell, _help + " (colour " + string(i) + "  " + rgb_hex(ls_pic.pal[i]) + ")");
        var _gc = loadscr_col(i);
        draw_rectangle_colour(_cx, _cy, _cx + _cell - 1, _cy + _cell - 1, _gc, _gc, _gc, _gc, false);
        if (i == _v) { draw_rectangle_colour(_cx - 2, _cy - 2, _cx + _cell + 1, _cy + _cell + 1, c_white, c_white, c_white, c_white, true); }
        else if (_hot) { draw_rectangle_colour(_cx - 1, _cy - 1, _cx + _cell, _cy + _cell, global.TH.accent, global.TH.accent, global.TH.accent, global.TH.accent, true); }
        if (_hot && ui_pressed)
        {
            ui_take_click();
            _v = i;
        }
    }
    return _v;
}

/// Disk and memory the loading screen costs, as a line of text
function loadscr_info(_p)
{
    var _m = loadscr_block(_p, true);
    if (is_undefined(_m)) { return "loadscr.bin is missing from the engine folder"; }
    var _kb = ceil(_m.size / 1024);
    var _secs = max(0.1, _m.size / 20000);
    return "Disk: " + string(_kb) + " KB, about " + string_format(_secs, 1, 1) + " s more to load. Chip RAM while loading: " + string(_kb) + " KB more, freed before the game starts.";
}

function loadscr_page_draw(_x1, _y1, _x2, _y2, _lw, _rw)
{
    var _l = proj.loadscr;
    var _aga = machine_cur().aga;
    var _md = loadscr_max_depth(_aga);
    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;
    var _oh = _l.bar_h;
    var _olw = _l.left_w;
    var _omw = _l.mid_w;
    var _orw = _l.right_w;

    // ---------------- left: the picture and the bar ----------------
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "");
    ui_page_tabs(_x1, _y1, _lw);
    var _fx = _x1 + 16;
    var _fw = _lw - 32;
    var _half = floor((_fw - 8) / 2);
    var _y = _y1 + 58;
    set_val(_l, "on", ui_toggle("ls_on", _fx, _y, "Show a loading screen", _l.on, "Loading screen|While the game loads, the Amiga shows this picture with a bar that fills as the disk is read - instead of the plain loading bar."), "lson");
    _y += 36;
    ui_heading(_fx, _y, "Picture");
    var _ns = ui_dropdown("ls_src", _fx, _y + 18, _fw, 30, ["The game's backdrop", "Its own picture"], _l.source, "Picture|The backdrop (with its colours), or a picture of its own imported from a PNG, with its own colours.");
    if (_ns != _l.source)
    {
        if (_ns == 1 && array_length(_l.pixels) != BD_W * BD_H)
        {
            var _f = get_open_filename("Pictures|*.png;*.jpg;*.jpeg;*.gif", "");
            if (_f != "")
            {
                undo_mark("lsimp" + string(current_time));
                if (loadscr_import_picture(_l, _f)) { toast("Loading screen picture imported with " + string(1 << _l.depth) + " colours", 0); }
                else { toast("That picture could not be read", 1); }
            }
        }
        else { set_val(_l, "source", _ns, "lssrc"); }
    }
    _y += 58;
    if (_l.source == 1)
    {
        if (ui_button("ls_import", _fx, _y, _half, 30, "Import...", "Import a picture|Fits a PNG (or JPG / GIF) into 320 x 256 and cuts it down to the colours on the right, with the dither below.", BTN_NORMAL))
        {
            var _f2 = get_open_filename("Pictures|*.png;*.jpg;*.jpeg;*.gif", "");
            if (_f2 != "")
            {
                undo_mark("lsimp" + string(current_time));
                if (loadscr_import_picture(_l, _f2)) { toast("Loading screen picture imported with " + string(1 << _l.depth) + " colours", 0); }
                else { toast("That picture could not be read", 1); }
            }
        }
        var _nd = ui_stepper("ls_depth", _fx + _half + 8, _y, _half, _l.depth, 1, _md, "Colours|Bitplanes of the picture: 1 = 2 colours up to 5 = 32 (A1200: 8 = 256). Fewer colours load faster and use less chip RAM. Going down keeps the picture (each pixel takes the nearest colour left); going up needs Import again to use the new colours.");
        if (_nd != _l.depth)
        {
            undo_mark("lsdepth" + string(current_time));
            loadscr_set_depth(_l, _nd);
        }
        ui_text(_fx + _half + 8, _y + 34, string(1 << _l.depth) + " colours", global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
        _y += 54;
        ui_heading(_fx, _y, "Dither (when importing)");
        bd_dither = ui_dropdown("ls_dither", _fx, _y + 18, _fw, 30, ["No dither", "Smooth", "Pattern"], clamp(bd_dither, 0, 2), "Dither|How an imported picture mixes its colours: Smooth spreads the error around, Pattern uses the even Bayer grid. The same setting as the Backdrop page.");
        _y += 58;
    }
    else
    {
        ui_text_wrap(_fx, _y - 4, "The backdrop, " + string(ls_pic.ncol) + " colours (no copper sky or hills).", global.TH.text_faint, _fw, global.f_small, 1);
        _y += 50;
    }
    ui_heading(_fx, _y, "Bar left");
    ui_heading(_fx + _half + 8, _y, "Bar top");
    set_val(_l, "bar_x", ui_stepper("ls_bx", _fx, _y + 18, _half, _l.bar_x, 0, BD_W - _l.bar_w, "Bar left|Where the bar starts across the screen, in pixels (or drag the bar on the preview)."), "lsbx");
    set_val(_l, "bar_y", ui_stepper("ls_by", _fx + _half + 8, _y + 18, _half, _l.bar_y, 0, BD_H - _l.bar_h, "Bar top|How far down the screen the bar is, in lines (or drag the bar on the preview)."), "lsby");
    _y += 58;
    ui_heading(_fx, _y, "Bar width");
    ui_heading(_fx + _half + 8, _y, "Bar height");
    set_val(_l, "bar_w", ui_stepper("ls_bw", _fx, _y + 18, _half, _l.bar_w, _l.left_w + _l.right_w, BD_W - _l.bar_x, "Bar width|The whole bar, caps included, in pixels (or drag its right edge on the preview)."), "lsbw");
    set_val(_l, "bar_h", ui_stepper("ls_bh", _fx + _half + 8, _y + 18, _half, _l.bar_h, LS_BAR_H_MIN, min(LS_BAR_H_MAX, BD_H - _l.bar_y), "Bar height|In lines, " + string(LS_BAR_H_MIN) + " to " + string(LS_BAR_H_MAX) + ". Drawn pieces keep their pixels (cut or padded at the bottom)."), "lsbh");
    _y += 58;
    ui_heading(_fx, _y, "Bar style");
    var _styles = ui_frame_styles();
    var _snames = [];
    var _si = -1;
    for (var s = 0; s < array_length(_styles); s++)
    {
        array_push(_snames, _styles[s]);
        if (_styles[s] == _l.style) { _si = s; }
    }
    array_push(_snames, "Custom (drawn)");
    if (_si < 0) { _si = array_length(_styles); }
    var _nst = ui_dropdown("ls_style", _fx, _y + 18, _fw, 30, _snames, _si, "Bar style|A ready-made bar like the HUD frames, in the picture's nearest colours. Draw on a piece on the right (or import a strip) to make your own.");
    if (_nst != _si)
    {
        undo_mark("lsstyle" + string(current_time));
        if (_nst < array_length(_styles)) { _l.style = _styles[_nst]; }
        else { loadscr_make_custom(_l, ls_pic); }
    }
    _y += 58;
    loadscr_fix(_l);
    loadscr_pieces_refit(_l, _oh, _olw, _omw, _orw);
    loadscr_preview_update(proj);
    ui_text_wrap(_fx, max(_y + 4, _y2 - 84), loadscr_info(proj), global.TH.text_faint, _fw, global.f_small, 1);

    // ---------------- centre: the preview and its progress ----------------
    ui_panel(_cx1, _y1, _cx2, _y2, "Preview");
    var _pw = _cx2 - _cx1 - 32;
    var _ph = _y2 - _y1 - 50 - 90;
    var _sc = max(1, floor(min(_pw / BD_W, _ph / BD_H) * 4) / 4);
    var _vx = floor((_cx1 + _cx2 - BD_W * _sc) / 2);
    var _vy = _y1 + 54;
    ui_rrect(_vx - 6, _vy - 6, _vx + BD_W * _sc + 6, _vy + BD_H * _sc + 6, 10, c_black, c_black, 0.35);
    gpu_set_texfilter(false);
    draw_surface_ext(ls_surf_empty, _vx, _vy, _sc, _sc, 0, c_white, 1);
    var _fill = floor(_l.bar_w * clamp(ls_prog, 0, 1));
    if (_fill > 0) { draw_surface_part_ext(ls_surf_full, _l.bar_x, _l.bar_y, _fill, _l.bar_h, _vx + _l.bar_x * _sc, _vy + _l.bar_y * _sc, _sc, _sc, c_white, 1); }
    gpu_set_texfilter(true);
    var _bx1 = _vx + _l.bar_x * _sc;
    var _by1 = _vy + _l.bar_y * _sc;
    var _bx2 = _bx1 + _l.bar_w * _sc;
    var _by2 = _by1 + _l.bar_h * _sc;
    var _hot = ui_register("ls_preview", _vx, _vy, _vx + BD_W * _sc, _vy + BD_H * _sc, "Preview|The loading screen as the Amiga shows it. Drag the bar to move it, or its right edge to make it wider or narrower.");
    var _on_edge = (_hot && abs(ui_mx - _bx2) <= 6 && ui_my >= _by1 && ui_my <= _by2);
    var _on_bar = (_hot && point_in_rectangle(ui_mx, ui_my, _bx1, _by1, _bx2, _by2));
    var _oc = global.TH.accent2;
    if (_on_bar || _on_edge || ls_drag != 0) { _oc = c_white; }
    draw_set_alpha(0.7);
    draw_rectangle_colour(_bx1 - 1, _by1 - 1, _bx2, _by2, _oc, _oc, _oc, _oc, true);
    draw_set_alpha(1);
    if (_on_edge || ls_drag == 2) { draw_rectangle_colour(_bx2 - 2, _by1, _bx2 + 2, _by2, _oc, _oc, _oc, _oc, false); }
    if ((_on_edge || _on_bar) && ui_pressed && ls_drag == 0)
    {
        ui_take_click();
        undo_mark("lsdrag" + string(current_time));
        ls_drag = 1;
        if (_on_edge) { ls_drag = 2; }
        ls_drag_dx = ui_mx - _bx1;
        ls_drag_dy = ui_my - _by1;
    }
    if (ls_drag != 0)
    {
        if (!ui_held) { ls_drag = 0; }
        else if (ls_drag == 1)
        {
            _l.bar_x = clamp(round((ui_mx - ls_drag_dx - _vx) / _sc), 0, BD_W - _l.bar_w);
            _l.bar_y = clamp(round((ui_my - ls_drag_dy - _vy) / _sc), 0, BD_H - _l.bar_h);
            proj_dirty = true;
        }
        else
        {
            _l.bar_w = clamp(round((ui_mx - _vx) / _sc) - _l.bar_x, _l.left_w + _l.right_w, BD_W - _l.bar_x);
            proj_dirty = true;
        }
    }
    var _sy = _vy + BD_H * _sc + 22;
    var _bw = 96;
    var _plab = "Play";
    if (ls_playing) { _plab = "Stop"; }
    if (ui_button("ls_play", _cx1 + 16, _sy, _bw, 30, _plab, "Play|Fills the bar the way it fills while the game loads.", BTN_NORMAL))
    {
        ls_playing = !ls_playing;
        if (ls_playing && ls_prog >= 1) { ls_prog = 0; }
    }
    var _slw = _cx2 - _cx1 - 32 - _bw - 12 - 60;
    var _np = ui_slider("ls_prog", _cx1 + 16 + _bw + 12, _sy + 2, _slw, ls_prog * 100, 0, 100, "Progress|How much of the game has loaded: drag to see the bar at any point.");
    if (abs(_np - ls_prog * 100) > 0.001)
    {
        ls_prog = clamp(_np / 100, 0, 1);
        ls_playing = false;
    }
    ui_text(_cx2 - 16, _sy + 15, string(round(ls_prog * 100)) + "%", global.TH.text, fa_right, fa_middle, global.f_body, 1);
    if (ls_playing)
    {
        ls_prog += 1 / (4 * 60);            // about 4 seconds, like loading a small game
        if (ls_prog >= 1)
        {
            ls_prog = 1;
            ls_playing = false;
        }
    }
    if (!_l.on) { ui_text_wrap(_cx1 + 16, _sy + 40, "The loading screen is off: switch on 'Show a loading screen' on the left to put it on the disk.", global.TH.warn, _cx2 - _cx1 - 32, global.f_small, 1); }

    // ---------------- right: the bar pieces ----------------
    var _rx = _x2 - _rw;
    ui_panel(_rx, _y1, _x2, _y2, "Bar pieces");
    var _gx = _rx + 20;
    var _gw = _rw - 40;
    var _gy = _y1 + 54;
    var _pnames = ["Left", "Middle", "Right"];
    var _phelp = ["Left cap|The bar's left end, drawn once.", "Middle|The tile repeated along the bar, between the caps.", "Right cap|The bar's right end, drawn once."];
    var _ptw = floor((_gw - 12) / 3);
    for (var t = 0; t < 3; t++)
    {
        if (ui_tab("ls_piece_" + string(t), _gx + t * (_ptw + 6), _gy, _ptw, 30, _pnames[t], ls_piece == t, _phelp[t])) { ls_piece = t; }
    }
    _gy += 42;
    var _wkeys = ["left_w", "mid_w", "right_w"];
    var _gh = floor((_gw - 8) / 2);
    ui_heading(_gx, _gy, "Width");
    ui_heading(_gx + _gh + 8, _gy, "Empty bar");
    var _cw = _l[$ _wkeys[ls_piece]];
    var _nw = ui_stepper("ls_pw", _gx, _gy + 18, _gh, _cw, 1, LS_PIECE_W_MAX, "Width|This piece's width in pixels, 1 to " + string(LS_PIECE_W_MAX) + ". Drawn pieces keep their pixels (cut or padded at the right).");
    if (_nw != _cw)
    {
        undo_mark("lspw" + string(current_time));
        _l[$ _wkeys[ls_piece]] = _nw;
        loadscr_fix(_l);
        loadscr_pieces_refit(_l, _oh, _olw, _omw, _orw);
        loadscr_preview_update(proj);
    }
    set_val(_l, "empty", ui_dropdown("ls_empty", _gx + _gh + 8, _gy + 18, _gh, 30, ["Darker", "Picture"], _l.empty, "Empty bar|What shows where the bar hasn't filled yet: a darker copy of the bar, or just the picture."), "lsempty");
    _gy += 62;
    // the piece, magnified: left-click draws, right-click makes a pixel see-through
    var _pcs = [ls_pc.left, ls_pc.mid, ls_pc.right];
    var _pa = _pcs[ls_piece];
    var _pwid = _l[$ _wkeys[ls_piece]];
    var _n = ls_pic.ncol;
    var _cols = 8;
    if (_n > 32) { _cols = 16; }
    var _cell = max(8, min(22, floor((_gw - (_cols - 1) * 3) / _cols)));
    var _prows = ceil(_n / _cols);
    var _palh = _prows * (_cell + 3) + 18;
    var _avail = _y2 - 16 - 44 - _palh - 12 - _gy;
    var _ps = clamp(floor(min(_gw / _pwid, _avail / _l.bar_h)), 2, 16);
    var _ex = _gx + floor((_gw - _pwid * _ps) / 2);
    var _ey = _gy;
    var _ew = _pwid * _ps;
    var _eh = _l.bar_h * _ps;
    // a checker shows the see-through pixels
    for (var _cy = 0; _cy < _l.bar_h; _cy++)
    {
        for (var _ccx = 0; _ccx < _pwid; _ccx++)
        {
            var _v = 0;
            if (_cy * _pwid + _ccx < array_length(_pa)) { _v = _pa[_cy * _pwid + _ccx]; }
            var _dc = make_colour_rgb(46, 50, 60);
            if (((_ccx + _cy) & 1) == 0) { _dc = make_colour_rgb(30, 33, 40); }
            if (_v > 0) { _dc = loadscr_col(_v); }
            draw_rectangle_colour(_ex + _ccx * _ps, _ey + _cy * _ps, _ex + (_ccx + 1) * _ps - 1, _ey + (_cy + 1) * _ps - 1, _dc, _dc, _dc, _dc, false);
        }
    }
    draw_rectangle_colour(_ex - 1, _ey - 1, _ex + _ew, _ey + _eh, global.TH.panel_edge, global.TH.panel_edge, global.TH.panel_edge, global.TH.panel_edge, true);
    var _ehot = ui_register("ls_canvas", _ex, _ey, _ex + _ew - 1, _ey + _eh - 1, "Piece|Left-click draws with the colour picked, right-click makes a pixel see-through (the picture shows through). The first stroke turns a ready-made style into your own.");
    if (_ehot)
    {
        var _hx = clamp(floor((ui_mx - _ex) / _ps), 0, _pwid - 1);
        var _hy = clamp(floor((ui_my - _ey) / _ps), 0, _l.bar_h - 1);
        draw_rectangle_colour(_ex + _hx * _ps, _ey + _hy * _ps, _ex + (_hx + 1) * _ps - 1, _ey + (_hy + 1) * _ps - 1, c_white, c_white, c_white, c_white, true);
        if (ui_pressed || ui_rpressed)
        {
            ui_take_click();
            undo_mark("lsdraw" + string(current_time));
            loadscr_make_custom(_l, ls_pic);
            ls_drawing = true;
        }
        if (ls_drawing && _l.style == "Custom")
        {
            var _nv = -1;
            if (ui_held) { _nv = ls_pen; }
            if (ui_rheld) { _nv = 0; }
            var _at = _hy * _pwid + _hx;
            var _old = -1;
            if (ls_piece == 0 && _at < array_length(_l.left)) { _old = _l.left[_at]; }
            if (ls_piece == 1 && _at < array_length(_l.mid)) { _old = _l.mid[_at]; }
            if (ls_piece == 2 && _at < array_length(_l.right)) { _old = _l.right[_at]; }
            if (_nv >= 0 && _old >= 0 && _old != _nv)
            {
                if (ls_piece == 0) { _l.left[_at] = _nv; }
                if (ls_piece == 1) { _l.mid[_at] = _nv; }
                if (ls_piece == 2) { _l.right[_at] = _nv; }
                proj_dirty = true;
            }
        }
    }
    if (!ui_held && !ui_rheld) { ls_drawing = false; }
    _gy = _ey + _eh + 12;
    ls_pen = clamp(ls_pen, 1, max(1, _n - 1));
    ui_heading(_gx, _gy, "Colour " + string(ls_pen));
    ls_pen = max(1, loadscr_pal_grid("ls_pal", _gx, _gy + 18, _cell, _cols, ls_pen, "Colour|A colour of the loading screen's picture to draw with (right-click on the piece makes a pixel see-through)."));
    if (ui_button("ls_strip", _gx, _y2 - 16 - 34, _gw, 32, "Import PNG strip...", "Import the bar|A PNG of the left cap, the middle tile and the right cap side by side: three equal parts (or exactly left + middle + right wide). Its height becomes the bar's; see-through pixels stay see-through; colours become the picture's nearest.", BTN_NORMAL))
    {
        var _f3 = get_open_filename("PNG picture|*.png", "");
        if (_f3 != "")
        {
            undo_mark("lsstrip" + string(current_time));
            var _err = loadscr_import_strip(_l, ls_pic, _f3);
            if (_err == "") { toast("Bar pieces imported", 0); }
            else { toast(_err, 1); }
        }
    }
}
