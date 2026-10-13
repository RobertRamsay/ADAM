/// ADAM - backdrop and sprite drawing, the 8x8 font, picture import

/// 8x8 font for characters 32..95 (public domain font8x8 by Daniel Hepper).
/// The same bytes are inside the engine, so text looks identical in game.
function font_init()
{
    global.FONT8 = [
        0, 0, 0, 0, 0, 0, 0, 0, 24, 60, 60, 24, 24, 0, 24, 0,
        108, 108, 0, 0, 0, 0, 0, 0, 108, 108, 254, 108, 254, 108, 108, 0,
        48, 124, 192, 120, 12, 248, 48, 0, 0, 198, 204, 24, 48, 102, 198, 0,
        56, 108, 56, 118, 220, 204, 118, 0, 96, 96, 192, 0, 0, 0, 0, 0,
        24, 48, 96, 96, 96, 48, 24, 0, 96, 48, 24, 24, 24, 48, 96, 0,
        0, 102, 60, 255, 60, 102, 0, 0, 0, 48, 48, 252, 48, 48, 0, 0,
        0, 0, 0, 0, 0, 48, 48, 96, 0, 0, 0, 252, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 48, 48, 0, 6, 12, 24, 48, 96, 192, 128, 0,
        124, 198, 206, 222, 246, 230, 124, 0, 48, 112, 48, 48, 48, 48, 252, 0,
        120, 204, 12, 56, 96, 204, 252, 0, 120, 204, 12, 56, 12, 204, 120, 0,
        28, 60, 108, 204, 254, 12, 30, 0, 252, 192, 248, 12, 12, 204, 120, 0,
        56, 96, 192, 248, 204, 204, 120, 0, 252, 204, 12, 24, 48, 48, 48, 0,
        120, 204, 204, 120, 204, 204, 120, 0, 120, 204, 204, 124, 12, 24, 112, 0,
        0, 48, 48, 0, 0, 48, 48, 0, 0, 48, 48, 0, 0, 48, 48, 96,
        24, 48, 96, 192, 96, 48, 24, 0, 0, 0, 252, 0, 0, 252, 0, 0,
        96, 48, 24, 12, 24, 48, 96, 0, 120, 204, 12, 24, 48, 0, 48, 0,
        124, 198, 222, 222, 222, 192, 120, 0, 48, 120, 204, 204, 252, 204, 204, 0,
        252, 102, 102, 124, 102, 102, 252, 0, 60, 102, 192, 192, 192, 102, 60, 0,
        248, 108, 102, 102, 102, 108, 248, 0, 254, 98, 104, 120, 104, 98, 254, 0,
        254, 98, 104, 120, 104, 96, 240, 0, 60, 102, 192, 192, 206, 102, 62, 0,
        204, 204, 204, 252, 204, 204, 204, 0, 120, 48, 48, 48, 48, 48, 120, 0,
        30, 12, 12, 12, 204, 204, 120, 0, 230, 102, 108, 120, 108, 102, 230, 0,
        240, 96, 96, 96, 98, 102, 254, 0, 198, 238, 254, 254, 214, 198, 198, 0,
        198, 230, 246, 222, 206, 198, 198, 0, 56, 108, 198, 198, 198, 108, 56, 0,
        252, 102, 102, 124, 96, 96, 240, 0, 120, 204, 204, 204, 220, 120, 28, 0,
        252, 102, 102, 124, 108, 102, 230, 0, 120, 204, 224, 112, 28, 204, 120, 0,
        252, 180, 48, 48, 48, 48, 120, 0, 204, 204, 204, 204, 204, 204, 252, 0,
        204, 204, 204, 204, 204, 120, 48, 0, 198, 198, 198, 214, 254, 238, 198, 0,
        198, 198, 108, 56, 56, 108, 198, 0, 204, 204, 204, 120, 48, 48, 120, 0,
        254, 198, 140, 24, 50, 102, 254, 0, 120, 96, 96, 96, 96, 96, 120, 0,
        192, 96, 48, 24, 12, 6, 2, 0, 120, 24, 24, 24, 24, 24, 120, 0,
        16, 56, 108, 198, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255
    ];
}

/// 1x1 white pixel sprite for exact-size filled rectangles
function pixel_sprite_init()
{
    var _surf = surface_create(1, 1);
    mask_to_surface(_surf, 1, 1, [1]);
    global.spr_px = sprite_create_from_surface(_surf, 0, 0, 1, 1, false, false, 0, 0);
    surface_free(_surf);
}

/// Pixel-exact filled rectangle (w x h pixels)
function px_rect(_x, _y, _w, _h, _col)
{
    draw_sprite_ext(global.spr_px, 0, _x, _y, _w, _h, 0, _col, 1);
}

/// Writes a white/transparent mask straight into a surface. _mask = 0/1, row-major.
function mask_to_surface(_surf, _w, _h, _mask)
{
    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    for (var i = 0; i < _w * _h; i++)
    {
        if (_mask[i] != 0) { buffer_write(_buf, buffer_u32, 0xffffffff); }
        else { buffer_write(_buf, buffer_u32, 0); }
    }
    buffer_set_surface(_buf, _surf, 0);
    buffer_delete(_buf);
}

/// Glyph row bits for a character (lower case folds to upper case)
function font_glyph_row(_ch, _row)
{
    var _c = ord(string_upper(_ch));
    if (_c < 32 || _c > 95) { _c = 32; }
    return global.FONT8[(_c - 32) * 8 + _row];
}

/// Writes text into a project's backdrop pixels in palette colour _col
function backdrop_text_into(_p, _str, _x, _y, _col)
{
    for (var i = 1; i <= string_length(_str); i++)
    {
        var _ch = string_char_at(_str, i);
        for (var r = 0; r < 8; r++)
        {
            var _bits = font_glyph_row(_ch, r);
            for (var b = 0; b < 8; b++)
            {
                if ((_bits & (128 >> b)) != 0)
                {
                    var _px = _x + (i - 1) * 8 + b;
                    var _py = _y + r;
                    if (_px >= 0 && _px < BD_W && _py >= 0 && _py < BD_H) { _p.pixels[_py * BD_W + _px] = _col; }
                }
            }
        }
    }
}

/// Draws text with the game font (as it will look on the Amiga). Returns width.
function draw_font8(_x, _y, _str, _scale, _col)
{
    for (var i = 1; i <= string_length(_str); i++)
    {
        var _ch = string_char_at(_str, i);
        for (var r = 0; r < 8; r++)
        {
            var _bits = font_glyph_row(_ch, r);
            if (_bits == 0) { continue; }
            for (var b = 0; b < 8; b++)
            {
                if ((_bits & (128 >> b)) != 0)
                {
                    px_rect(_x + ((i - 1) * 8 + b) * _scale, _y + r * _scale, _scale, _scale, _col);
                }
            }
        }
    }
    return string_length(_str) * 8 * _scale;
}

// ---------------------------------------------------------------------------
// Backdrop: an index surface (palette number in red or blue) drawn through
// sh_palette, so palette edits are instant and painting is one pixel write.
// ---------------------------------------------------------------------------

function backdrop_gfx_init()
{
    bd_surf = -1;
    bd_dirty = true;
    bd_upload = true;
    bd_buf = buffer_create(BD_W * BD_H * 4, buffer_fixed, 1);
    bd_uniform = shader_get_uniform(sh_palette, "u_pal");
    bd_pal_floats = array_create(PAL_MAX * 3, 0);
    bd_u_sky_on = shader_get_uniform(sh_palette, "u_sky_on");
    bd_u_sky_tex = shader_get_sampler_index(sh_palette, "u_sky_tex");
    bd_u_sky_map = shader_get_uniform(sh_palette, "u_sky_map");
    bd_sky_surf = -1;           // 256 x 1: the copper sky's colour on each line
    bd_sky_key = "";            // what bd_sky_surf was drawn from
}

/// The 256 x 1 strip of copper sky colours the shader reads, redrawn only
/// when the sky, or the machine (12-bit or 24-bit), changes.
function sky_strip_surface()
{
    var _key = string(proj.sky_top) + "," + string(proj.sky_mid) + "," + string(proj.sky_bot) + "," + string(proj.sky_mid_y) + "," + proj.machine;
    if (!surface_exists(bd_sky_surf))
    {
        bd_sky_surf = surface_create(256, 1);
        bd_sky_key = "";
    }
    if (_key != bd_sky_key)
    {
        bd_sky_key = _key;
        var _sky = sky_table(proj);
        surface_set_target(bd_sky_surf);
        draw_clear_alpha(c_black, 1);
        for (var i = 0; i < 256; i++)
        {
            var _c = _sky[i];
            draw_point_colour(i, 0, make_colour_rgb(rgb_r(_c), rgb_g(_c), rgb_b(_c)));
        }
        surface_reset_target();
    }
    return bd_sky_surf;
}

/// The backdrop index surface. Painting only changes bd_buf (an exact copy of
/// the pixels); the whole buffer is sent to the surface once per frame, so the
/// picture can never be lost or overwritten by drawing into the surface.
function backdrop_surface()
{
    if (!surface_exists(bd_surf))
    {
        bd_surf = surface_create(BD_W, BD_H);
        bd_upload = true;
    }
    if (bd_dirty)
    {
        var _n = BD_W * BD_H;
        buffer_seek(bd_buf, buffer_seek_start, 0);
        for (var i = 0; i < _n; i++)
        {
            buffer_write(bd_buf, buffer_u32, 0xff000000 | proj.pixels[i]);
        }
        bd_dirty = false;
        bd_upload = true;
    }
    if (bd_upload)
    {
        buffer_set_surface(bd_buf, bd_surf, 0);
        bd_upload = false;
    }
    return bd_surf;
}

/// Ordered (Bayer 8 x 8) dither threshold for a pixel, 0-63
function bayer8(_px, _py)
{
    return global.BAYER8[(_py & 7) * 8 + (_px & 7)];
}

/// Writes one backdrop pixel into the project and the picture buffer
function backdrop_plot(_x, _y, _v)
{
    if (_x < 0 || _y < 0 || _x >= BD_W || _y >= BD_H) { return; }
    var _i = _y * BD_W + _x;
    if (proj.pixels[_i] == _v) { return; }
    proj.pixels[_i] = _v;
    proj_dirty = true;
    buffer_poke(bd_buf, _i * 4, buffer_u32, 0xff000000 | _v);
    bd_upload = true;
}

/// Palette shader on, with the current palette and copper sky
function backdrop_shader_begin()
{
    for (var i = 0; i < PAL_MAX; i++)
    {
        var _c = rgb_machine(proj.pal[i]);
        bd_pal_floats[i * 3] = rgb_r(_c) / 255;
        bd_pal_floats[i * 3 + 1] = rgb_g(_c) / 255;
        bd_pal_floats[i * 3 + 2] = rgb_b(_c) / 255;
    }
    var _strip = -1;
    if (proj.sky_on) { _strip = sky_strip_surface(); }   // before shader_set: it draws to a surface
    gpu_set_texfilter(false);
    shader_set(sh_palette);
    shader_set_uniform_f_array(bd_uniform, bd_pal_floats);
    var _on = 0;
    if (proj.sky_on) { _on = 1; }
    shader_set_uniform_f(bd_u_sky_on, _on);
    shader_set_uniform_f(bd_u_sky_map, 256, 0);
    if (_strip != -1)
    {
        gpu_set_texfilter_ext(bd_u_sky_tex, false);
        texture_set_stage(bd_u_sky_tex, surface_get_texture(_strip));
    }
}

/// While the palette shader is set: which sky line each texel shows -
/// screen line = texture y (0..1) * _texh + _ofs
function backdrop_shader_sky(_texh, _ofs)
{
    shader_set_uniform_f(bd_u_sky_map, _texh, _ofs);
}

function backdrop_shader_end()
{
    shader_reset();
    gpu_set_texfilter(true);
}

function backdrop_draw(_x, _y, _scale)
{
    var _s = backdrop_surface();
    backdrop_shader_begin();
    draw_surface_ext(_s, _x, _y, _scale, _scale, 0, c_white, 1);
    backdrop_shader_end();
}

function backdrop_gfx_free()
{
    if (surface_exists(bd_surf)) { surface_free(bd_surf); }
    if (buffer_exists(bd_buf)) { buffer_delete(bd_buf); }
    if (surface_exists(terr_surf)) { surface_free(terr_surf); }
}

// ---------------------------------------------------------------------------
// Sprites: three white masks per sprite (one per colour), tinted when drawn
// ---------------------------------------------------------------------------

function spr_cache_update(_i)
{
    var _s = proj.sprites[_i];
    for (var c = 0; c < 3; c++)
    {
        if (surface_exists(spr_surf[_i][c]))
        {
            if (surface_get_width(spr_surf[_i][c]) != _s.w || surface_get_height(spr_surf[_i][c]) != _s.h)
            {
                surface_free(spr_surf[_i][c]);
            }
        }
        if (!surface_exists(spr_surf[_i][c]))
        {
            spr_surf[_i][c] = surface_create(_s.w, _s.h);
            spr_dirty[_i] = true;
        }
    }
    if (!spr_dirty[_i]) { return; }
    var _n = _s.w * _s.h;
    for (var k = 1; k <= 3; k++)
    {
        var _mask = array_create(_n, 0);
        for (var q = 0; q < _n; q++)
        {
            if (_s.px[q] == k) { _mask[q] = 1; }
        }
        mask_to_surface(spr_surf[_i][k - 1], _s.w, _s.h, _mask);
    }
    spr_dirty[_i] = false;
}

/// Draws sprite design _i with colour array _cols (3 x $RRGGBB)
function draw_sprite_amiga_cols(_i, _x, _y, _scale, _cols, _alpha)
{
    if (_i < 0 || _i >= SPR_COUNT) { return; }
    spr_cache_update(_i);
    gpu_set_texfilter(false);
    for (var c = 0; c < 3; c++)
    {
        draw_surface_ext(spr_surf[_i][c], _x, _y, _scale, _scale, 0, amiga_col(_cols[c]), _alpha);
    }
    gpu_set_texfilter(true);
}

/// Draws sprite design _i in its own colours
function draw_sprite_amiga(_i, _x, _y, _scale, _alpha)
{
    if (_i < 0 || _i >= SPR_COUNT) { return; }
    draw_sprite_amiga_cols(_i, _x, _y, _scale, proj.sprites[_i].cols, _alpha);
}

function spr_cache_free()
{
    for (var i = 0; i < SPR_COUNT; i++)
    {
        for (var c = 0; c < 3; c++)
        {
            if (surface_exists(spr_surf[i][c])) { surface_free(spr_surf[i][c]); }
        }
    }
}

function spr_mark_all_dirty()
{
    for (var i = 0; i < SPR_COUNT; i++) { spr_dirty[i] = true; }
}

// ---------------------------------------------------------------------------
// Picture import: fit any PNG/JPG into 320 x 256, find the best palette for
// the current depth (median cut) and map every pixel, optionally dithered.
// ---------------------------------------------------------------------------

/// Byte offsets of red, green and blue inside a surface buffer on this platform
function surface_byte_order()
{
    var _s = surface_create(1, 1);
    surface_set_target(_s);
    draw_clear_alpha(make_colour_rgb(255, 0, 0), 1);
    surface_reset_target();
    var _b = buffer_create(4, buffer_fixed, 1);
    buffer_get_surface(_b, _s, 0);
    var _ri = 0;
    for (var i = 0; i < 3; i++)
    {
        if (buffer_peek(_b, i, buffer_u8) > 200) { _ri = i; }
    }
    buffer_delete(_b);
    surface_free(_s);
    if (_ri == 2) { return [2, 1, 0]; }
    return [0, 1, 2];
}

/// Splits colour boxes until there are _n of them. Returns an array of $RRGGBB.
function median_cut(_bins, _cnt, _sr, _sg, _sb, _n)
{
    var _boxes = [_bins];
    var _guard = 0;
    while (array_length(_boxes) < _n && _guard < 400)
    {
        _guard += 1;
        // pick the box with the widest range weighted by pixel count
        var _best = -1;
        var _best_score = 0;
        var _best_ch = 0;
        for (var b = 0; b < array_length(_boxes); b++)
        {
            var _box = _boxes[b];
            if (array_length(_box) < 2) { continue; }
            var _lo = [99, 99, 99];
            var _hi = [-1, -1, -1];
            var _pop = 0;
            for (var k = 0; k < array_length(_box); k++)
            {
                var _bin = _box[k];
                var _ch3 = [(_bin >> 8) & 15, (_bin >> 4) & 15, _bin & 15];
                for (var c = 0; c < 3; c++)
                {
                    _lo[c] = min(_lo[c], _ch3[c]);
                    _hi[c] = max(_hi[c], _ch3[c]);
                }
                _pop += _cnt[_bin];
            }
            for (var c2 = 0; c2 < 3; c2++)
            {
                var _score = (_hi[c2] - _lo[c2]) * sqrt(_pop);
                if (_score > _best_score)
                {
                    _best_score = _score;
                    _best = b;
                    _best_ch = c2;
                }
            }
        }
        if (_best < 0) { break; }
        var _sel = _boxes[_best];
        var _shift = 8 - _best_ch * 4;
        array_sort(_sel, method({ s : _shift }, function(_a, _b2) { return ((_a >> s) & 15) - ((_b2 >> s) & 15); }));
        var _total = 0;
        for (var k2 = 0; k2 < array_length(_sel); k2++) { _total += _cnt[_sel[k2]]; }
        var _acc = 0;
        var _cut = 1;
        for (var k3 = 0; k3 < array_length(_sel) - 1; k3++)
        {
            _acc += _cnt[_sel[k3]];
            _cut = k3 + 1;
            if (_acc * 2 >= _total) { break; }
        }
        var _a1 = [];
        var _a2 = [];
        for (var k4 = 0; k4 < array_length(_sel); k4++)
        {
            if (k4 < _cut) { array_push(_a1, _sel[k4]); }
            else { array_push(_a2, _sel[k4]); }
        }
        _boxes[_best] = _a1;
        array_push(_boxes, _a2);
    }
    var _out = [];
    for (var b2 = 0; b2 < array_length(_boxes); b2++)
    {
        var _bx = _boxes[b2];
        var _tr = 0;
        var _tg = 0;
        var _tb = 0;
        var _tc = 0;
        for (var k5 = 0; k5 < array_length(_bx); k5++)
        {
            var _q = _bx[k5];
            _tr += _sr[_q];
            _tg += _sg[_q];
            _tb += _sb[_q];
            _tc += _cnt[_q];
        }
        if (_tc > 0) { array_push(_out, rgb_make(_tr / _tc, _tg / _tc, _tb / _tc)); }
    }
    return _out;
}

/// Imports a picture file into the backdrop. Returns true when done.
function backdrop_import(_path, _dither)
{
    var _q = picture_quantize(_path, pal_count(), _dither);
    if (is_undefined(_q)) { return false; }
    for (var c = 0; c < array_length(_q.pal); c++) { proj.pal[c] = _q.pal[c]; }
    proj.pixels = _q.pixels;
    bd_dirty = true;
    return true;
}

/// A picture file fitted into 320 x 256 and cut down to _count colours
/// (median cut, darkest colour first; _dither 0 none, 1 Floyd-Steinberg,
/// 2 pattern): { pixels, pal } in the machine's colours, or undefined
function picture_quantize(_path, _count, _dither)
{
    var _spr = sprite_add(_path, 1, false, false, 0, 0);
    if (_spr == -1) { return undefined; }
    var _w = sprite_get_width(_spr);
    var _h = sprite_get_height(_spr);
    var _k = min(BD_W / _w, BD_H / _h);
    var _surf = surface_create(BD_W, BD_H);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 1);
    gpu_set_texfilter(true);
    draw_sprite_ext(_spr, 0, (BD_W - _w * _k) / 2, (BD_H - _h * _k) / 2, _k, _k, 0, c_white, 1);
    surface_reset_target();
    sprite_delete(_spr);
    var _n = BD_W * BD_H;
    var _buf = buffer_create(_n * 4, buffer_fixed, 1);
    buffer_get_surface(_buf, _surf, 0);
    surface_free(_surf);
    var _ord = surface_byte_order();

    // read the picture and build a 12-bit histogram
    var _rr = array_create(_n, 0);
    var _gg = array_create(_n, 0);
    var _bb = array_create(_n, 0);
    var _cnt = array_create(4096, 0);
    var _sr = array_create(4096, 0);
    var _sg = array_create(4096, 0);
    var _sb = array_create(4096, 0);
    for (var i = 0; i < _n; i++)
    {
        var _r = buffer_peek(_buf, i * 4 + _ord[0], buffer_u8);
        var _g = buffer_peek(_buf, i * 4 + _ord[1], buffer_u8);
        var _b = buffer_peek(_buf, i * 4 + _ord[2], buffer_u8);
        _rr[i] = _r;
        _gg[i] = _g;
        _bb[i] = _b;
        var _bin = ((_r >> 4) << 8) | ((_g >> 4) << 4) | (_b >> 4);
        _cnt[_bin] += 1;
        _sr[_bin] += _r;
        _sg[_bin] += _g;
        _sb[_bin] += _b;
    }
    buffer_delete(_buf);
    var _used = [];
    for (var q = 0; q < 4096; q++)
    {
        if (_cnt[q] > 0) { array_push(_used, q); }
    }
    var _cols = median_cut(_used, _cnt, _sr, _sg, _sb, _count);
    // darkest colour becomes colour 0 (the border and screen background)
    array_sort(_cols, function(_a, _b2) { return (rgb_r(_a) * 3 + rgb_g(_a) * 6 + rgb_b(_a)) - (rgb_r(_b2) * 3 + rgb_g(_b2) * 6 + rgb_b(_b2)); });
    var _qpal = array_create(_count, 0);
    var _qpx = array_create(_n, 0);
    for (var c = 0; c < _count; c++)
    {
        if (c < array_length(_cols)) { _qpal[c] = rgb_machine(_cols[c]); }
    }

    // nearest palette entry for every 12-bit colour
    var _lut = array_create(4096, -1);
    var _pal_n = min(_count, array_length(_cols));
    // pattern dither: nudge every pixel by its Bayer threshold, about half the gap between palette colours
    var _spread = 0.5 * 255 / power(max(2, _pal_n), 1 / 3);
    for (var _iy = 0; _iy < BD_H; _iy++)
    {
        for (var _ix = 0; _ix < BD_W; _ix++)
        {
            var _i2 = _iy * BD_W + _ix;
            var _nudge = 0;
            if (_dither == 2) { _nudge = ((bayer8(_ix, _iy) + 0.5) / 64 - 0.5) * _spread; }
            var _cr = clamp(_rr[_i2] + _nudge, 0, 255);
            var _cg = clamp(_gg[_i2] + _nudge, 0, 255);
            var _cb = clamp(_bb[_i2] + _nudge, 0, 255);
            var _key = ((round(_cr) >> 4) << 8) | ((round(_cg) >> 4) << 4) | (round(_cb) >> 4);
            if (_lut[_key] < 0)
            {
                var _want = rgb_make(_cr, _cg, _cb);
                var _bi = 0;
                var _bd = 999999999;
                for (var p = 0; p < _pal_n; p++)
                {
                    var _d = rgb_dist(_want, _qpal[p]);
                    if (_d < _bd) { _bd = _d; _bi = p; }
                }
                _lut[_key] = _bi;
            }
            var _idx = _lut[_key];
            _qpx[_i2] = _idx;
            if (_dither == 1)
            {
                // Floyd-Steinberg error diffusion
                var _pc = _qpal[_idx];
                var _er = _cr - rgb_r(_pc);
                var _eg = _cg - rgb_g(_pc);
                var _eb = _cb - rgb_b(_pc);
                var _nb = [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]];
                for (var e = 0; e < 4; e++)
                {
                    var _nx = _ix + _nb[e][0];
                    var _ny = _iy + _nb[e][1];
                    if (_nx < 0 || _nx >= BD_W || _ny >= BD_H) { continue; }
                    var _j = _ny * BD_W + _nx;
                    _rr[_j] += _er * _nb[e][2] / 16;
                    _gg[_j] += _eg * _nb[e][2] / 16;
                    _bb[_j] += _eb * _nb[e][2] / 16;
                }
            }
        }
    }
    return { pixels : _qpx, pal : _qpal };
}

// ---------------------------------------------------------------------------
// Copper sky: colour 0 changes on every one of the 256 lines (and the border
// with it). Three colour stops. The A500/600 copper writes 12-bit colours
// (16 steps per gun); on the A1200 it writes the low nibbles too (LOCT), so
// each gun has 256 steps. Neighbouring colour bands are blended over the
// lines with COPPER_BLEND, so the steps don't show as hard edges.
// ---------------------------------------------------------------------------

/// Line pattern for blending one whole colour (A) into the next (B). Only two
/// colours ever mix: blends run from the middle of one colour band to the
/// middle of the next, and neighbouring blends share the solid lines at the
/// ends (the pattern's last BBBB are the next blend's first AAAA), so for
/// three colours it reads AAAABAAABAABABABBABBBABBBBCBBBCBBCBCBCCBCCCBCCCC.
#macro COPPER_BLEND "AAAABAAABAABABABBABBBABBBB"
#macro COPPER_BLEND_SOLID 4

/// Share of B in COPPER_BLEND between positions _p0 and _p1 (each letter is 1
/// wide; past the end counts as B). A blend shorter than the pattern covers
/// several letters per line - picking single letters would alias - so each
/// line takes the share of B over its stretch of the pattern instead.
function copper_blend_share(_p0, _p1)
{
    var _len = string_length(COPPER_BLEND);
    var _sum = 0;
    var _p = _p0;
    while (_p < _p1 - 0.000001)
    {
        var _c = floor(_p);
        var _e = min(_c + 1, _p1);
        if (_c >= _len)
        {
            _sum += _e - _p;
        }
        else
        {
            if (_c >= 0 && string_char_at(COPPER_BLEND, _c + 1) == "B") { _sum += _e - _p; }
        }
        _p = _e;
    }
    return _sum / (_p1 - _p0);
}

/// Any copper bar: _q holds one colour per line, already rounded to the
/// machine's steps (so it is made of bands). Returns the lines with each
/// pair of neighbouring bands blended by COPPER_BLEND.
function copper_blend_lines(_q)
{
    var _len = array_length(_q);
    var _out = array_create(_len, 0);
    if (_len == 0) { return _out; }
    var _bcol = [];
    var _bmid = [];
    var _blen = [];
    var _start = 0;
    for (var i = 1; i <= _len; i++)
    {
        if (i == _len || _q[i] != _q[_start])
        {
            array_push(_bcol, _q[_start]);
            array_push(_bmid, (_start + i - 1) / 2);
            array_push(_blen, i - _start);
            _start = i;
        }
    }
    // A sliver band (one gun stepping a line before the others) would swallow
    // the blend between the two big colours round it: leave it out, so its
    // lines become part of that blend. Shortest first; never the end bands.
    var _gone = true;
    while (_gone)
    {
        _gone = false;
        var _pick = -1;
        for (var k = 1; k < array_length(_blen) - 1; k++)
        {
            if (_blen[k] * 4 < _blen[k - 1] + _blen[k + 1])
            {
                if (_pick < 0 || _blen[k] < _blen[_pick]) { _pick = k; }
            }
        }
        if (_pick >= 0)
        {
            array_delete(_bcol, _pick, 1);
            array_delete(_bmid, _pick, 1);
            array_delete(_blen, _pick, 1);
            _gone = true;
        }
    }
    var _nb = array_length(_bcol);
    var _n = string_length(COPPER_BLEND) - COPPER_BLEND_SOLID;
    var _b = 0;
    var _span = -1;
    var _carry = 0;                     // B owed so far in this blend (spreads it over the lines)
    for (var j = 0; j < _len; j++)
    {
        while (_b + 1 < _nb && j >= _bmid[_b + 1]) { _b += 1; }
        if (j < _bmid[_b] || _b + 1 >= _nb)
        {
            _out[j] = _bcol[_b];        // above the first middle, or below the last: solid
        }
        else
        {
            if (_span != _b)
            {
                _span = _b;
                _carry = 0;
            }
            // this line covers [_f, _f + 1/L) of the blend, i.e. that stretch of the pattern
            var _l = _bmid[_b + 1] - _bmid[_b];
            var _f = (j - _bmid[_b]) / _l;
            _carry += copper_blend_share(COPPER_BLEND_SOLID + _f * _n, COPPER_BLEND_SOLID + (_f + 1 / _l) * _n);
            if (_carry >= 0.5)
            {
                _out[j] = _bcol[_b + 1];
                _carry -= 1;
            }
            else
            {
                _out[j] = _bcol[_b];
            }
        }
    }
    return _out;
}

/// 256 copper colours ($RRGGBB, as the machine shows them) for project _p:
/// 12-bit steps on the A500/600, 24-bit on the A1200, bands blended.
function sky_table(_p)
{
    var _aga = machine_get(_p.machine).aga;
    var _max = 15;
    var _scale = 17;
    if (_aga)
    {
        _max = 255;
        _scale = 1;
    }
    var _q = array_create(256, 0);
    var _my = clamp(_p.sky_mid_y, 1, 254);
    for (var i = 0; i < 256; i++)
    {
        var _a = _p.sky_top;
        var _b = _p.sky_mid;
        var _t = i / _my;
        if (i > _my)
        {
            _a = _p.sky_mid;
            _b = _p.sky_bot;
            _t = (i - _my) / (255 - _my);
        }
        var _r = clamp(round(lerp(rgb_r(_a), rgb_r(_b), _t) / _scale), 0, _max);
        var _g = clamp(round(lerp(rgb_g(_a), rgb_g(_b), _t) / _scale), 0, _max);
        var _bl = clamp(round(lerp(rgb_b(_a), rgb_b(_b), _t) / _scale), 0, _max);
        _q[i] = rgb_make(_r * _scale, _g * _scale, _bl * _scale);
    }
    return copper_blend_lines(_q);
}

/// $0RGB copper word: the high nibble of each gun (all the A500/600 has)
function copper_hi(_c)
{
    return ((rgb_r(_c) >> 4) << 8) | ((rgb_g(_c) >> 4) << 4) | (rgb_b(_c) >> 4);
}

/// $0RGB copper word of the low nibbles - the A1200 writes it with LOCT set
function copper_lo(_c)
{
    return ((rgb_r(_c) & 15) << 8) | ((rgb_g(_c) & 15) << 4) | (rgb_b(_c) & 15);
}

/// Ready-made skies: [name, top, middle, bottom, middle line]
function sky_presets()
{
    return [
        ["Sunset",    0x101040, 0x5080d0, 0xffa040, 150],
        ["Blue sky",  0x2050c0, 0x60a0f0, 0xd0f0ff, 160],
        ["Night",     0x000000, 0x101030, 0x302060, 180],
        ["Under sea", 0x60d0f0, 0x1060a0, 0x001030, 90],
        ["Neon",      0x400060, 0xc02090, 0x102080, 128],
        ["Lava",      0x200000, 0x902000, 0xffc020, 170]
    ];
}
