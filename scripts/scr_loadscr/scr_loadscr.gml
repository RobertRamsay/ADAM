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

/// The loader's copper list as [register, value] pairs; pointer values are
/// offsets from the block start (loadscr.s adds the block's address)
function loadscr_copper(_depth, _aga, _pal, _ncol, _planes_off, _spr_off)
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
    var _ncop = array_length(loadscr_copper(_depth, _aga, _pic.pal, _pic.ncol, 0, 0)) + 1;
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
    var _cop = loadscr_copper(_depth, _aga, _cmp.pal, _cmp.ncol, _planes_off, _spr_off);
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
