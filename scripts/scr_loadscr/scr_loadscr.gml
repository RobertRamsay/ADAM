/// ADAM Pro - loading screen: a picture shown while the game loads, with a
/// bar made of a left cap, a repeating middle tile and a right cap that fills
/// from left to right. The bootblock reads it before the game (boot.s,
/// loadscr.s); this script makes its data block. The same layout is in
/// tools/reference/adf_reference.py.

#macro LS_BAR_H_MIN 4
#macro LS_BAR_H_MAX 64
#macro LS_PIECE_W_MAX 32
#macro LS_HDR 48                 // loadscr.s LS_SIZE
#macro LS_PIC_MAX 16             // pictures that show at a percentage
#macro LS_PI_SIZE 16             // loadscr.s PI_SIZE

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
        empty : 0,                        // the empty bar: 0 = a darker copy of the full one, 1 = the picture
        mode : 0,                         // how it fills: 0 left to right, 1 right to left, 2 bottom to top, 3 top to bottom
        pics : []                         // pictures that show at a percentage: { spr, x, y, pct } (loadscr_pic_new)
    };
}

/// A picture on the loading screen: sprite _spr at (_x, _y), shown once _pct % has loaded
function loadscr_pic_new(_spr, _x, _y, _pct)
{
    return { spr : _spr, x : _x, y : _y, pct : _pct };
}

function loadscr_from_loaded(_raw)
{
    var _l = loadscr_new();
    if (!is_struct(_raw)) { return _l; }
    var _on = _raw[$ "on"];
    if (is_numeric(_on)) { _l.on = (_on != 0); }
    var _nums = ["source", "depth", "bar_x", "bar_y", "bar_w", "bar_h", "left_w", "mid_w", "right_w", "empty", "mode"];
    for (var i = 0; i < array_length(_nums); i++)
    {
        var _v = _raw[$ _nums[i]];
        if (is_numeric(_v)) { _l[$ _nums[i]] = floor(_v); }
    }
    if (is_string(_raw[$ "style"])) { _l.style = _raw.style; }
    _l.source = clamp(_l.source, 0, 1);
    _l.depth = clamp(_l.depth, 1, 8);
    _l.empty = clamp(_l.empty, 0, 1);
    _l.mode = clamp(_l.mode, 0, 3);
    var _lp = _raw[$ "pics"];
    if (is_array(_lp))
    {
        for (var k = 0; k < min(LS_PIC_MAX, array_length(_lp)); k++)
        {
            var _r = _lp[k];
            if (!is_struct(_r)) { continue; }
            var _q = loadscr_pic_new(0, 0, 0, 50);
            var _pk = ["spr", "x", "y", "pct"];
            for (var j = 0; j < 4; j++)
            {
                var _pv = _r[$ _pk[j]];
                if (is_numeric(_pv)) { _q[$ _pk[j]] = floor(_pv); }
            }
            _q.spr = max(0, _q.spr);
            _q.x = clamp(_q.x, 0, BD_W - 16);
            _q.y = clamp(_q.y, 0, BD_H - 16);
            _q.pct = clamp(_q.pct, 0, 100);
            array_push(_l.pics, _q);
        }
    }
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

/// The loading screen's pictures in the order they show (by percentage, then list
/// order), each { thr (0..1024), x, y, w, h, px (colour numbers, 0 = see-through) }
/// in the picture's nearest colours, cut to the screen
function loadscr_pics(_p, _pic)
{
    var _l = _p.loadscr;
    var _out = [];
    for (var i = 0; i < array_length(_l.pics); i++)
    {
        var _q = _l.pics[i];
        if (_q.spr < 0 || _q.spr >= array_length(_p.sprites)) { continue; }
        var _sp = _p.sprites[_q.spr];
        var _w = min(_sp.w, BD_W - _q.x);
        var _h = min(_sp.h, BD_H - _q.y);
        if (_w < 1 || _h < 1) { continue; }
        var _map = [0, 0, 0, 0];
        for (var c = 0; c < 3; c++) { _map[c + 1] = loadscr_nearest(_pic.pal, _pic.ncol, _sp.cols[c], false); }
        var _px = array_create(_w * _h, 0);
        for (var _py = 0; _py < _h; _py++)
        {
            for (var _pxx = 0; _pxx < _w; _pxx++)
            {
                var _v = _sp.px[_py * _sp.w + _pxx];
                if (_v > 0) { _px[_py * _w + _pxx] = _map[clamp(_v, 1, 3)]; }
            }
        }
        array_push(_out, { thr : (clamp(_q.pct, 0, 100) * 1024) div 100, x : _q.x, y : _q.y, w : _w, h : _h, px : _px, idx : i });
    }
    array_sort(_out, function(_ea, _eb)
    {
        if (_ea.thr != _eb.thr) { return _ea.thr - _eb.thr; }
        return _ea.idx - _eb.idx;
    });
    return _out;
}

/// Draws picture _q (loadscr_pics) into 320 x 256 colour numbers _a
function loadscr_pic_draw(_a, _q)
{
    for (var _py = 0; _py < _q.h; _py++)
    {
        for (var _pxx = 0; _pxx < _q.w; _pxx++)
        {
            var _v = _q.px[_py * _q.w + _pxx];
            if (_v > 0) { _a[@ (_q.y + _py) * BD_W + _q.x + _pxx] = _v; }
        }
    }
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
    // the pictures: their records, then each one's screen bytes, plane after plane
    var _pics = loadscr_pics(_p, _pic);
    var _np = array_length(_pics);
    var _pics_off = 0;
    if (_np > 0)
    {
        _pics_off = ((_end + 7) >> 3) << 3;
        _end = _pics_off + _np * LS_PI_SIZE;
        for (var q = 0; q < _np; q++)
        {
            var _qa = _pics[q];
            var _wb = ((_qa.x + _qa.w - 1) >> 3) - (_qa.x >> 3) + 1;
            _end += _wb * _qa.h * _depth;
        }
    }
    var _size = ((_end + 511) >> 9) << 9;
    if (_measure)
    {
        buffer_delete(_code);
        return { buf : -1, size : _size, mem : _size };
    }
    var _cmp = loadscr_compose(_p);
    // a picture shows on top of the ones before it, and the full bar keeps them
    for (var q2 = 0; q2 < _np; q2++) { loadscr_pic_draw(_cmp.full, _pics[q2]); }
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
    be16(_b, 2);                                 // LS_VER
    var _flags = 0;
    if (_aga) { _flags = 1; }
    be16(_b, _flags);                            // LS_FLAGS
    be16(_b, _depth);                            // LS_DEPTH
    be16(_b, _l.mode);                           // LS_MODE: 0 left to right, 1 right to left, 2 bottom to top, 3 top to bottom
    be32(_b, _cop_off);                          // LS_COPPER
    be32(_b, _planes_off);                       // LS_PLANES
    be32(_b, _strip_off);                        // LS_STRIP
    be16(_b, _l.bar_x);
    be16(_b, _l.bar_y);
    be16(_b, _l.bar_w);
    be16(_b, _l.bar_h);
    be16(_b, _sx0);                              // LS_SX0
    be16(_b, _stride);                           // LS_SSTRIDE
    be16(_b, _np);                               // LS_NPIC
    be16(_b, 0);
    be32(_b, _pics_off);                         // LS_PICS
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
    if (_np > 0)
    {
        // each picture's bytes: the screen with it (and the ones before it) drawn in
        var _shown = array_create(BD_W * BD_H, 0);
        array_copy(_shown, 0, _cmp.screen, 0, BD_W * BD_H);
        var _dat = _pics_off + _np * LS_PI_SIZE;
        for (var q3 = 0; q3 < _np; q3++)
        {
            var _qb = _pics[q3];
            loadscr_pic_draw(_shown, _qb);
            var _c0 = _qb.x >> 3;
            var _wb2 = ((_qb.x + _qb.w - 1) >> 3) - _c0 + 1;
            buffer_seek(_b, buffer_seek_start, _pics_off + q3 * LS_PI_SIZE);
            be16(_b, _qb.thr);                   // PI_THR
            be16(_b, _c0);                       // PI_COL
            be16(_b, _qb.y);                     // PI_Y
            be16(_b, _wb2);                      // PI_WB
            be16(_b, _qb.h);                     // PI_H
            be16(_b, 0);
            be32(_b, _dat);                      // PI_DATA
            buffer_seek(_b, buffer_seek_start, _dat);
            for (var p3 = 0; p3 < _depth; p3++)
            {
                for (var _r3 = 0; _r3 < _qb.h; _r3++)
                {
                    var _row3 = (_qb.y + _r3) * BD_W;
                    for (var _cb = 0; _cb < _wb2; _cb++)
                    {
                        var _v3 = 0;
                        var _at3 = _row3 + (_c0 + _cb) * 8;
                        for (var bit3 = 0; bit3 < 8; bit3++) { _v3 = (_v3 << 1) | ((_shown[_at3 + bit3] >> p3) & 1); }
                        buffer_write(_b, buffer_u8, _v3);
                    }
                }
            }
            _dat += _wb2 * _qb.h * _depth;
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
/// planes (dev self-test): the fill (each direction), then the pictures reached
function loadscr_sim_reveal(_b, _hdr, _prog)
{
    var _pk = function(_bb, _o) { return buffer_peek(_bb, _o, buffer_u8) * 256 + buffer_peek(_bb, _o + 1, buffer_u8); };
    var _depth = _pk(_b, _hdr + 8);
    var _mode = _pk(_b, _hdr + 10);
    var _planes = peek32(_b, _hdr + 16);
    var _strip = peek32(_b, _hdr + 20);
    var _bx = _pk(_b, _hdr + 24);
    var _by = _pk(_b, _hdr + 26);
    var _bw = _pk(_b, _hdr + 28);
    var _bh = _pk(_b, _hdr + 30);
    var _sx0 = _pk(_b, _hdr + 32);
    var _st = _pk(_b, _hdr + 34);
    var _np = _pk(_b, _hdr + 36);
    var _pics = peek32(_b, _hdr + 40);
    var _out = array_create(_depth * 10240, 0);
    for (var i = 0; i < _depth * 10240; i++) { _out[i] = buffer_peek(_b, _planes + i, buffer_u8); }
    if (_mode < 2)
    {
        var _n = (_bw * _prog) >> 10;
        var _x0 = _bx;
        var _x1 = _bx + _n;
        if (_mode == 1)
        {
            _x0 = _bx + _bw - _n;
            _x1 = _bx + _bw;
        }
        for (var _col = _x0 >> 3; _col * 8 < _x1 && _n > 0; _col++)
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
    }
    else
    {
        var _nr = (_bh * _prog) >> 10;
        var _r0 = 0;
        if (_mode == 2) { _r0 = _bh - _nr; }
        for (var p2 = 0; p2 < _depth; p2++)
        {
            for (var r2 = _r0; r2 < _r0 + _nr; r2++)
            {
                for (var c2 = 0; c2 < _st; c2++)
                {
                    _out[p2 * 10240 + (_by + r2) * 40 + _sx0 + c2] = buffer_peek(_b, _strip + p2 * _st * _bh + r2 * _st + c2, buffer_u8);
                }
            }
        }
    }
    for (var q = 0; q < _np; q++)
    {
        var _rec = _pics + q * LS_PI_SIZE;
        if (_pk(_b, _rec) > _prog) { break; }
        var _pc0 = _pk(_b, _rec + 2);
        var _py = _pk(_b, _rec + 4);
        var _pwb = _pk(_b, _rec + 6);
        var _ph = _pk(_b, _rec + 8);
        var _dat = peek32(_b, _rec + 12);
        for (var p3 = 0; p3 < _depth; p3++)
        {
            for (var r3 = 0; r3 < _ph; r3++)
            {
                for (var c3 = 0; c3 < _pwb; c3++)
                {
                    _out[p3 * 10240 + (_py + r3) * 40 + _pc0 + c3] = buffer_peek(_b, _dat, buffer_u8);
                    _dat += 1;
                }
            }
        }
    }
    return _out;
}

/// Colour number of pixel (_x, _y) in planes _a (loadscr_sim_reveal)
function loadscr_sim_px(_a, _depth, _x, _y)
{
    var _c = 0;
    for (var p = 0; p < _depth; p++)
    {
        if ((_a[p * 10240 + _y * 40 + (_x >> 3)] & (0x80 >> (_x & 7))) != 0) { _c |= (1 << p); }
    }
    return _c;
}

/// Dev self-test: the block's layout; for each fill direction, a full reveal gives the full
/// bar and a half reveal stops at the right place; a picture shows at its percentage
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
    for (var k = 0; k < SPR_W * SPR_H; k++) { proj.sprites[0].px[k] = (k * 5) mod 4; }
    var _code = buffer_load(working_directory + "engine/loadscr.bin");
    var _hdr = buffer_get_size(_code);
    buffer_delete(_code);
    if (_hdr mod 8 != 0) { _ok = false; }
    for (var _mode = 0; _mode < 4 && _ok; _mode++)
    {
        proj.loadscr.mode = _mode;
        proj.loadscr.pics = [];
        if (_mode == 3) { proj.loadscr.pics = [loadscr_pic_new(0, 13, 40, 50)]; }
        var _blk = loadscr_block(proj);
        if (is_undefined(_blk))
        {
            _ok = false;
            break;
        }
        var _b = _blk.buf;
        if (buffer_peek(_b, _hdr, buffer_u8) != ord("L") || buffer_peek(_b, _hdr + 3, buffer_u8) != ord("R")) { _ok = false; }
        if (_blk.size mod 512 != 0 || _blk.size != loadscr_block(proj, true).size) { _ok = false; }
        if (peek32(_b, _hdr + 16) mod 8 != 0) { _ok = false; }
        var _cmp = loadscr_compose(proj);
        var _depth = _cmp.depth;
        var _all = loadscr_sim_reveal(_b, _hdr, 1024);
        var _half = loadscr_sim_reveal(_b, _hdr, 512);
        var _cut = (203 * 512) >> 10;
        var _rcut = (12 * 512) >> 10;
        for (var _y = 200; _y < 212; _y++)
        {
            for (var _x = 0; _x < BD_W; _x++)
            {
                if (loadscr_sim_px(_all, _depth, _x, _y) != _cmp.full[_y * BD_W + _x]) { _ok = false; }
                var _in = false;
                if (_x >= 21 && _x < 224)
                {
                    if (_mode == 0) { _in = (_x < 21 + _cut); }
                    if (_mode == 1) { _in = (_x >= 224 - _cut); }
                    if (_mode == 2) { _in = (_y >= 212 - _rcut); }
                    if (_mode == 3) { _in = (_y < 200 + _rcut); }
                }
                var _want = _cmp.screen[_y * BD_W + _x];
                if (_in) { _want = _cmp.full[_y * BD_W + _x]; }
                if (loadscr_sim_px(_half, _depth, _x, _y) != _want) { _ok = false; }
            }
        }
        if (_mode == 3)
        {
            // the picture: not at 49 %, there at 50 %
            var _pre = loadscr_sim_reveal(_b, _hdr, (49 * 1024) div 100);
            var _qs = loadscr_pics(proj, loadscr_picture(proj));
            var _shown = array_create(BD_W * BD_H, 0);
            array_copy(_shown, 0, _cmp.screen, 0, BD_W * BD_H);
            loadscr_pic_draw(_shown, _qs[0]);
            for (var _yy = 40; _yy < 40 + SPR_H; _yy++)
            {
                for (var _xx = 13; _xx < 13 + SPR_W; _xx++)
                {
                    if (loadscr_sim_px(_pre, _depth, _xx, _yy) != _cmp.screen[_yy * BD_W + _xx]) { _ok = false; }
                    if (loadscr_sim_px(_half, _depth, _xx, _yy) != _shown[_yy * BD_W + _xx]) { _ok = false; }
                }
            }
        }
        buffer_delete(_b);
    }
    var _back = loadscr_from_loaded(json_parse(json_stringify({ on : 1, bar_w : 9999, bar_x : -5, style : "Custom", source : 1, mode : 7, pics : [{ spr : 2, x : 400, y : 3, pct : 150 }] })));
    if (!_back.on || _back.bar_w != BD_W || _back.bar_x != 0 || _back.style != "Metal" || _back.source != 0 || _back.mode != 3) { _ok = false; }
    if (array_length(_back.pics) != 1 || _back.pics[0].x != BD_W - 16 || _back.pics[0].pct != 100) { _ok = false; }
    proj = _keep;
    if (_ok) { show_debug_message("ADAM loading screen self-test: PASS"); }
    else { show_debug_message("ADAM loading screen self-test: FAIL"); }
}

function loadscr_gfx_free()
{
    if (surface_exists(ls_surf_empty)) { surface_free(ls_surf_empty); }
    if (surface_exists(ls_surf_full)) { surface_free(ls_surf_full); }
    if (buffer_exists(ls_buf)) { buffer_delete(ls_buf); }
    loadscr_pic_surfs_free();
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
    _key += "|" + json_stringify(_l.pics);
    for (var u = 0; u < array_length(_l.pics); u++)
    {
        var _us = _l.pics[u].spr;
        if (_us >= 0 && _us < array_length(_p.sprites)) { _key += json_stringify(_p.sprites[_us]); }
    }
    var _surfs_ok = true;
    for (var v = 0; v < array_length(ls_pic_surfs); v++)
    {
        if (!surface_exists(ls_pic_surfs[v].surf)) { _surfs_ok = false; }
    }
    if (_key == ls_key && _surfs_ok && surface_exists(ls_surf_empty) && surface_exists(ls_surf_full)) { return; }
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
    // the pictures that show at a percentage, each on its own surface (0 = see-through)
    loadscr_pic_surfs_free();
    var _qs = loadscr_pics(_p, ls_pic);
    for (var q = 0; q < array_length(_qs); q++)
    {
        var _q = _qs[q];
        var _qb = buffer_create(_q.w * _q.h * 4, buffer_fixed, 1);
        for (var w = 0; w < _q.w * _q.h; w++)
        {
            if (_q.px[w] > 0) { buffer_write(_qb, buffer_u32, _lut[_q.px[w]]); }
            else { buffer_write(_qb, buffer_u32, 0); }
        }
        var _qsf = surface_create(_q.w, _q.h);
        buffer_set_surface(_qb, _qsf, 0);
        buffer_delete(_qb);
        array_push(ls_pic_surfs, { surf : _qsf, x : _q.x, y : _q.y, w : _q.w, h : _q.h, thr : _q.thr });
    }
}

function loadscr_pic_surfs_free()
{
    for (var i = 0; i < array_length(ls_pic_surfs); i++)
    {
        if (surface_exists(ls_pic_surfs[i].surf)) { surface_free(ls_pic_surfs[i].surf); }
    }
    ls_pic_surfs = [];
}

/// The part of the screen the bar has filled at progress _prog (0..1): [x, y, w, h]
function loadscr_fill_rect(_l, _prog)
{
    var _pr = clamp(_prog, 0, 1);
    if (_l.mode == 1)
    {
        var _n1 = floor(_l.bar_w * _pr);
        return [_l.bar_x + _l.bar_w - _n1, _l.bar_y, _n1, _l.bar_h];
    }
    if (_l.mode == 2)
    {
        var _n2 = floor(_l.bar_h * _pr);
        return [_l.bar_x, _l.bar_y + _l.bar_h - _n2, _l.bar_w, _n2];
    }
    if (_l.mode == 3) { return [_l.bar_x, _l.bar_y, _l.bar_w, floor(_l.bar_h * _pr)]; }
    return [_l.bar_x, _l.bar_y, floor(_l.bar_w * _pr), _l.bar_h];
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
        var _bdn = "The backdrop, " + string(ls_pic.ncol) + " colours (no hills).";
        if (proj.sky_on) { _bdn = "The backdrop, " + string(ls_pic.ncol) + " colours, with its copper sky (no hills)."; }
        ui_text_wrap(_fx, _y - 4, _bdn, global.TH.text_faint, _fw, global.f_small, 1);
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
    ui_heading(_fx + _half + 8, _y, "Fills");
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
    set_val(_l, "mode", ui_dropdown("ls_mode", _fx + _half + 8, _y + 18, _half, 30, ["Left to right", "Right to left", "Bottom to top", "Top to bottom"], _l.mode, "Fills|Which way the bar fills as the game loads. Make the bar the whole screen (or a big part of it) and draw the full picture into its pieces for a picture that builds up."), "lsmode");
    var _nst = ui_dropdown("ls_style", _fx, _y + 18, _half, 30, _snames, _si, "Bar style|A ready-made bar like the HUD frames, in the picture's nearest colours. Draw on a piece on the right (or import a strip) to make your own.");
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
    var _ph = _y2 - _y1 - 50 - 200;
    var _sc = max(1, floor(min(_pw / BD_W, _ph / BD_H) * 4) / 4);
    var _vx = floor((_cx1 + _cx2 - BD_W * _sc) / 2);
    var _vy = _y1 + 54;
    ui_rrect(_vx - 6, _vy - 6, _vx + BD_W * _sc + 6, _vy + BD_H * _sc + 6, 10, c_black, c_black, 0.35);
    gpu_set_texfilter(false);
    draw_surface_ext(ls_surf_empty, _vx, _vy, _sc, _sc, 0, c_white, 1);
    var _fr = loadscr_fill_rect(_l, ls_prog);
    if (_fr[2] > 0 && _fr[3] > 0) { draw_surface_part_ext(ls_surf_full, _fr[0], _fr[1], _fr[2], _fr[3], _vx + _fr[0] * _sc, _vy + _fr[1] * _sc, _sc, _sc, c_white, 1); }
    var _pthr = floor(clamp(ls_prog, 0, 1) * 1024);
    for (var q = 0; q < array_length(ls_pic_surfs); q++)
    {
        var _qs = ls_pic_surfs[q];
        if (_qs.thr <= _pthr && surface_exists(_qs.surf)) { draw_surface_ext(_qs.surf, _vx + _qs.x * _sc, _vy + _qs.y * _sc, _sc, _sc, 0, c_white, 1); }
    }
    gpu_set_texfilter(true);
    // the pictures: outlined, the picked one brighter; drag one to move it
    var _phit = -1;
    for (var q2 = 0; q2 < array_length(_l.pics); q2++)
    {
        var _pq = _l.pics[q2];
        var _pd = loadscr_pic_dims(_pq);
        var _px1 = _vx + _pq.x * _sc;
        var _py1 = _vy + _pq.y * _sc;
        var _pcol = global.TH.text_faint;
        if (q2 == ls_psel) { _pcol = global.TH.accent; }
        draw_set_alpha(0.8);
        draw_rectangle_colour(_px1 - 1, _py1 - 1, _px1 + _pd[0] * _sc, _py1 + _pd[1] * _sc, _pcol, _pcol, _pcol, _pcol, true);
        draw_set_alpha(1);
        ui_text(_px1 + 2, _py1 + 1, string(q2 + 1), _pcol, fa_left, fa_top, global.f_small, 1);
        if (point_in_rectangle(ui_mx, ui_my, _px1, _py1, _px1 + _pd[0] * _sc, _py1 + _pd[1] * _sc)) { _phit = q2; }
    }
    if (_phit >= 0 && ui_pressed && ls_drag == 0 && !ls_pdrag && ui_hit(_vx, _vy, _vx + BD_W * _sc, _vy + BD_H * _sc))
    {
        ui_take_click();
        undo_mark("lspic" + string(current_time));
        ls_psel = _phit;
        ls_pdrag = true;
        ls_pdrag_dx = ui_mx - (_vx + _l.pics[_phit].x * _sc);
        ls_pdrag_dy = ui_my - (_vy + _l.pics[_phit].y * _sc);
    }
    if (ls_pdrag)
    {
        if (!ui_held || ls_psel >= array_length(_l.pics)) { ls_pdrag = false; }
        else
        {
            var _dq = _l.pics[ls_psel];
            var _dd = loadscr_pic_dims(_dq);
            _dq.x = clamp(round((ui_mx - ls_pdrag_dx - _vx) / _sc), 0, BD_W - _dd[0]);
            _dq.y = clamp(round((ui_my - ls_pdrag_dy - _vy) / _sc), 0, BD_H - _dd[1]);
            proj_dirty = true;
        }
    }
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
    loadscr_pics_panel(_l, _cx1 + 16, _sy + 44, _cx2 - _cx1 - 32);
    if (!_l.on) { ui_text_wrap(_cx1 + 16, _y2 - 34, "The loading screen is off: switch on 'Show a loading screen' on the left to put it on the disk.", global.TH.warn, _cx2 - _cx1 - 32, global.f_small, 1); }

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

/// The size a loading-screen picture shows at: its sprite's, cut to the screen
function loadscr_pic_dims(_q)
{
    var _w = 16;
    var _h = 16;
    if (_q.spr >= 0 && _q.spr < array_length(proj.sprites))
    {
        _w = proj.sprites[_q.spr].w;
        _h = proj.sprites[_q.spr].h;
    }
    return [max(1, min(_w, BD_W - _q.x)), max(1, min(_h, BD_H - _q.y))];
}

/// The pictures that show at a percentage: add, pick, and the picked one's sprite, percentage
/// and place (drag it on the preview too)
function loadscr_pics_panel(_l, _x, _y, _w)
{
    ui_heading(_x, _y, "Pictures at a percentage");
    var _n = array_length(_l.pics);
    if (ui_button("ls_pic_add", _x + _w - 120, _y - 6, 120, 28, "Add picture", "Add picture|A sprite from the sprite bank that appears on the loading screen once that much has loaded - a ship being built, a crowd gathering, a title stamping in. Drag it on the preview to place it. Keep them off the bar.", BTN_NORMAL) && _n < LS_PIC_MAX)
    {
        undo_mark("lspicadd" + string(current_time));
        var _pct = 25 * (_n + 1);
        if (_pct > 100) { _pct = 100; }
        array_push(_l.pics, loadscr_pic_new(0, 152 - 8 * (_n mod 4), 40 + 28 * (_n mod 4), _pct));
        ls_psel = _n;
        _n += 1;
    }
    if (_n == 0)
    {
        ui_text_wrap(_x, _y + 26, "None yet: sprites can appear on the loading screen at a percentage of the load.", global.TH.text_faint, _w - 130, global.f_small, 1);
        return;
    }
    ls_psel = clamp(ls_psel, 0, _n - 1);
    var _cw = 30;
    for (var i = 0; i < _n; i++)
    {
        if (ui_tab("ls_pic_" + string(i), _x + i * (_cw + 4), _y + 20, _cw, 26, string(i + 1), ls_psel == i, "Picture " + string(i + 1) + "|Pick it to change it below.")) { ls_psel = i; }
    }
    var _q = _l.pics[ls_psel];
    var _fw = floor((_w - 4 * 8 - 90) / 4);
    var _ry = _y + 70;
    ui_heading(_x, _ry - 18, "Sprite");
    ui_heading(_x + (_fw + 8), _ry - 18, "Shows at %");
    ui_heading(_x + (_fw + 8) * 2, _ry - 18, "Across");
    ui_heading(_x + (_fw + 8) * 3, _ry - 18, "Down");
    var _ns = ui_stepper("ls_pic_spr", _x, _ry, _fw, _q.spr + 1, 1, array_length(proj.sprites), "Sprite|Which sprite from the sprite bank, drawn in the picture's nearest colours.") - 1;
    if (_ns != _q.spr) { set_val(_q, "spr", _ns, "lspicspr"); }
    set_val(_q, "pct", ui_stepper("ls_pic_pct", _x + (_fw + 8), _ry, _fw, _q.pct, 0, 100, "Shows at|How much of the game has loaded when it appears, 0 to 100 %. Pictures appear on top of the ones before them."), "lspicpct");
    var _dm = loadscr_pic_dims(_q);
    set_val(_q, "x", ui_stepper("ls_pic_x", _x + (_fw + 8) * 2, _ry, _fw, _q.x, 0, BD_W - _dm[0], "Across|Its left edge, in pixels (or drag it on the preview)."), "lspicx");
    set_val(_q, "y", ui_stepper("ls_pic_y", _x + (_fw + 8) * 3, _ry, _fw, _q.y, 0, BD_H - _dm[1], "Down|Its top, in lines (or drag it on the preview)."), "lspicy");
    if (ui_button("ls_pic_del", _x + _w - 82, _ry, 82, 30, "Delete", "Delete|Takes this picture off the loading screen.", BTN_NORMAL))
    {
        undo_mark("lspicdel" + string(current_time));
        array_delete(_l.pics, ls_psel, 1);
        ls_psel = max(0, ls_psel - 1);
    }
}
