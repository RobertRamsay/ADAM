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
        var _c = rgb_machine(pal_shown(i));
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

/// Ends a backdrop_shader_begin() block: back to the default shader and
/// smooth texture filtering (the shader needs point sampling)
function backdrop_shader_end()
{
    shader_reset();
    gpu_set_texfilter(true);
}

/// Draws the painted backdrop (index surface through the palette shader) with
/// its top-left at _x, _y in GUI pixels, _scale screen pixels per Amiga pixel
/// (1 = 320 x 256). The sky uniforms are whatever backdrop_shader_begin set.
function backdrop_draw(_x, _y, _scale)
{
    var _s = backdrop_surface();
    backdrop_shader_begin();
    draw_surface_ext(_s, _x, _y, _scale, _scale, 0, c_white, 1);
    backdrop_shader_end();
}

/// Frees the backdrop index surface, its pixel buffer bd_buf and the Levels
/// page terrain surface (terr_surf, made in scr_levels). Called from the
/// CleanUp event; the surfaces are remade on demand if drawn again.
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

/// A column's foot (actor setting 'Reaches the floor'): row _row of sprite design _i drawn
/// again on _rows lines from _x, _y down, in colours _cols (as draw_sprite_amiga_cols)
function draw_sprite_column_cols(_i, _row, _x, _y, _scale, _rows, _cols, _alpha)
{
    if (_i < 0 || _i >= SPR_COUNT || _rows <= 0) { return; }
    spr_cache_update(_i);
    gpu_set_texfilter(false);
    var _w = surface_get_width(spr_surf[_i][0]);
    for (var c = 0; c < 3; c++)
    {
        draw_surface_part_ext(spr_surf[_i][c], 0, _row, _w, 1, _x, _y, _scale, _scale * _rows, amiga_col(_cols[c]), _alpha);
    }
    gpu_set_texfilter(true);
}

/// Draws sprite design _i in its own colours
function draw_sprite_amiga(_i, _x, _y, _scale, _alpha)
{
    if (_i < 0 || _i >= SPR_COUNT) { return; }
    draw_sprite_amiga_cols(_i, _x, _y, _scale, proj.sprites[_i].cols, _alpha);
}

/// Frees the three colour-mask surfaces of every sprite design (CleanUp event).
/// spr_cache_update remakes a missing one the next time the sprite is drawn.
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

/// Marks every sprite design for a redraw of its mask surfaces (for example
/// after the whole sprite bank is replaced). Not called anywhere at present.
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

// ---------------------------------------------------------------------------
// IFF pictures (Deluxe Paint, Personal Paint, Brilliance...): FORM ILBM (bitplanes)
// and FORM PBM (chunky, DPaint's other format). iff_read gives the palette, a colour
// number per pixel and which pixels are see-through (a brush's mask plane or its
// transparent colour). EHB pictures get their 32 half-bright colours; HAM and 24-bit
// ones are refused. ByteRun1 (compression 1) or none. iff_to_png writes one as a PNG
// so the PNG import (sprites) and picture_quantize (backdrop) can take it.
// ---------------------------------------------------------------------------

/// Is _path an IFF picture by its name (.iff, .ilbm, .lbm, .bbm)?
function iff_is_path(_path)
{
    var _e = string_lower(filename_ext(_path));
    return _e == ".iff" || _e == ".ilbm" || _e == ".lbm" || _e == ".bbm";
}

/// Big-endian word / long / 4-letter id at byte _o of buffer _b
function iff_u16(_b, _o)
{
    return (buffer_peek(_b, _o, buffer_u8) << 8) | buffer_peek(_b, _o + 1, buffer_u8);
}
function iff_u32(_b, _o)
{
    return (iff_u16(_b, _o) << 16) | iff_u16(_b, _o + 2);
}
function iff_id(_b, _o)
{
    var _s = "";
    for (var i = 0; i < 4; i++) { _s += chr(buffer_peek(_b, _o + i, buffer_u8)); }
    return _s;
}

/// Reads IFF picture _path -> { w, h, pal (array of $RRGGBB), idx (colour per pixel,
/// row by row), clear (true = see-through), masked (it had a mask or transparent
/// colour), err ("" = fine, else why it could not be read) }
function iff_read(_path)
{
    var _res = indexed_new();
    var _b = buffer_load(_path);
    if (_b == -1)
    {
        _res.err = "Could not read that file";
        return _res;
    }
    var _len = buffer_get_size(_b);
    if (_len < 12 || iff_id(_b, 0) != "FORM")
    {
        buffer_delete(_b);
        _res.err = "That is not an IFF file";
        return _res;
    }
    var _form = iff_id(_b, 8);
    if (_form != "ILBM" && _form != "PBM ")
    {
        buffer_delete(_b);
        _res.err = "That IFF file is not a picture (ILBM)";
        return _res;
    }
    var _w = 0;
    var _h = 0;
    var _np = 0;
    var _mask = 0;
    var _comp = 0;
    var _tcol = -1;
    var _camg = 0;
    var _body = -1;
    var _blen = 0;
    var _cmap = [];
    var _end = min(_len, 8 + iff_u32(_b, 4));
    var _o = 12;
    while (_o + 8 <= _end)
    {
        var _id = iff_id(_b, _o);
        var _sz = iff_u32(_b, _o + 4);
        var _d = _o + 8;
        if (_d + _sz > _len) { _sz = _len - _d; }
        if (_id == "BMHD" && _sz >= 20)
        {
            _w = iff_u16(_b, _d);
            _h = iff_u16(_b, _d + 2);
            _np = buffer_peek(_b, _d + 8, buffer_u8);
            _mask = buffer_peek(_b, _d + 9, buffer_u8);
            _comp = buffer_peek(_b, _d + 10, buffer_u8);
            _tcol = iff_u16(_b, _d + 12);
        }
        else if (_id == "CMAP")
        {
            for (var i = 0; i + 2 < _sz; i += 3)
            {
                array_push(_cmap, rgb_make(buffer_peek(_b, _d + i, buffer_u8), buffer_peek(_b, _d + i + 1, buffer_u8), buffer_peek(_b, _d + i + 2, buffer_u8)));
            }
        }
        else if (_id == "CAMG" && _sz >= 4)
        {
            _camg = iff_u32(_b, _d);
        }
        else if (_id == "BODY")
        {
            _body = _d;
            _blen = _sz;
        }
        _o = _d + _sz + (_sz & 1);
    }
    if (_w <= 0 || _h <= 0 || _body < 0)
    {
        buffer_delete(_b);
        _res.err = "There is no picture in that IFF file";
        return _res;
    }
    if ((_camg & 0x800) != 0)
    {
        buffer_delete(_b);
        _res.err = "HAM pictures can't be imported - save it with up to 256 colours";
        return _res;
    }
    if (_np > 8 || (_form == "ILBM" && _np < 1))
    {
        buffer_delete(_b);
        _res.err = "Only pictures of 1 to 8 bitplanes (2 to 256 colours) can be imported";
        return _res;
    }
    if (_comp > 1)
    {
        buffer_delete(_b);
        _res.err = "That IFF picture is packed in a way ADAM does not know";
        return _res;
    }
    // old painting programs write 4-bit colours as $X0: make them full ($XX)
    var _lownib = false;
    for (var c = 0; c < array_length(_cmap); c++)
    {
        if ((_cmap[c] & 0x0f0f0f) != 0) { _lownib = true; }
    }
    if (!_lownib)
    {
        for (var c2 = 0; c2 < array_length(_cmap); c2++) { _cmap[c2] = _cmap[c2] | ((_cmap[c2] >> 4) & 0x0f0f0f); }
    }
    // Extra Half-Brite: colours 32..63 are 0..31 at half brightness
    if ((_camg & 0x80) != 0 && _np == 6 && array_length(_cmap) >= 32)
    {
        array_resize(_cmap, 32);
        for (var e = 0; e < 32; e++) { array_push(_cmap, rgb_make(rgb_r(_cmap[e]) >> 1, rgb_g(_cmap[e]) >> 1, rgb_b(_cmap[e]) >> 1)); }
    }
    // a picture with no palette: greys
    if (array_length(_cmap) == 0)
    {
        var _ng = 1 << max(1, _np);
        for (var gq = 0; gq < _ng; gq++)
        {
            var _gv = round(gq * 255 / max(1, _ng - 1));
            array_push(_cmap, rgb_make(_gv, _gv, _gv));
        }
    }
    // unpack BODY: ILBM rows are each plane in turn (and a mask plane), PBM rows are bytes
    var _rb = ((_w + 15) >> 4) << 1;
    var _planes = _np;
    if (_mask == 1) { _planes += 1; }
    var _row = _rb * _planes;
    if (_form == "PBM ") { _row = _w + (_w & 1); }
    var _total = _row * _h;
    var _u = buffer_create(_total, buffer_fixed, 1);
    buffer_fill(_u, 0, buffer_u8, 0, _total);
    var _p = _body;
    var _pe = min(_len, _body + _blen);
    var _q = 0;
    if (_comp == 0)
    {
        buffer_copy(_b, _body, min(_total, _pe - _body), _u, 0);
    }
    else
    {
        while (_q < _total && _p < _pe)
        {
            var _n = buffer_peek(_b, _p, buffer_s8);
            _p += 1;
            if (_n >= 0)
            {
                for (var k = 0; k <= _n && _q < _total && _p < _pe; k++)
                {
                    buffer_poke(_u, _q, buffer_u8, buffer_peek(_b, _p, buffer_u8));
                    _p += 1;
                    _q += 1;
                }
            }
            else if (_n != -128)
            {
                var _v = buffer_peek(_b, _p, buffer_u8);
                _p += 1;
                for (var k2 = 0; k2 <= -_n && _q < _total; k2++)
                {
                    buffer_poke(_u, _q, buffer_u8, _v);
                    _q += 1;
                }
            }
        }
    }
    buffer_delete(_b);
    var _idx = array_create(_w * _h, 0);
    var _clr = array_create(_w * _h, false);
    for (var _iy = 0; _iy < _h; _iy++)
    {
        var _ro = _iy * _row;
        for (var _ix = 0; _ix < _w; _ix++)
        {
            var _ci = 0;
            if (_form == "PBM ")
            {
                _ci = buffer_peek(_u, _ro + _ix, buffer_u8);
            }
            else
            {
                var _byo = _ro + (_ix >> 3);
                var _bit = 7 - (_ix & 7);
                for (var pl = 0; pl < _np; pl++)
                {
                    _ci |= ((buffer_peek(_u, _byo + pl * _rb, buffer_u8) >> _bit) & 1) << pl;
                }
                if (_mask == 1 && ((buffer_peek(_u, _byo + _np * _rb, buffer_u8) >> _bit) & 1) == 0) { _clr[_iy * _w + _ix] = true; }
            }
            if (_mask == 2 && _ci == _tcol) { _clr[_iy * _w + _ix] = true; }
            _idx[_iy * _w + _ix] = _ci;
        }
    }
    buffer_delete(_u);
    _res.w = _w;
    _res.h = _h;
    _res.pal = _cmap;
    _res.idx = _idx;
    _res.clear = _clr;
    _res.masked = (_mask == 1 || _mask == 2);
    return _res;
}

/// Writes IFF picture _iff (from iff_read) to PNG file _out, see-through pixels clear.
/// Returns true when written.
function iff_to_png(_iff, _out)
{
    var _w = _iff.w;
    var _h = _iff.h;
    var _ord = surface_byte_order();
    var _buf = buffer_create(_w * _h * 4, buffer_fixed, 1);
    var _np = array_length(_iff.pal);
    for (var i = 0; i < _w * _h; i++)
    {
        var _c = 0;
        var _ci = _iff.idx[i];
        if (_ci < _np) { _c = _iff.pal[_ci]; }
        var _o = i * 4;
        buffer_poke(_buf, _o + _ord[0], buffer_u8, rgb_r(_c));
        buffer_poke(_buf, _o + _ord[1], buffer_u8, rgb_g(_c));
        buffer_poke(_buf, _o + _ord[2], buffer_u8, rgb_b(_c));
        var _a = 255;
        if (_iff.clear[i]) { _a = 0; }
        buffer_poke(_buf, _o + 3, buffer_u8, _a);
    }
    var _surf = surface_create(_w, _h);
    buffer_set_surface(_buf, _surf, 0);
    buffer_delete(_buf);
    surface_save(_surf, _out);
    surface_free(_surf);
    return file_exists(_out);
}

/// Puts indexed picture _iff (iff_read / indexed_read) into the backdrop with its own
/// colours and pixels when it uses no more colours than the backdrop shows and is about
/// screen size (up to 384 x 300, an overscan picture: cut to 320 x 256 round its middle;
/// a smaller one goes top left). Colour numbers past the last colour are packed down,
/// colour 0 staying 0. Returns false (nothing changed) otherwise - then quantize it.
function backdrop_import_indexed(_iff)
{
    if (_iff.w > 384 || _iff.h > 300) { return false; }
    var _nc = array_length(_iff.pal);
    var _pc = pal_count();
    // the colours actually used decide, not the palette's length
    var _use = array_create(256, false);
    _use[0] = true;
    var _top = 0;
    for (var i = 0; i < array_length(_iff.idx); i++)
    {
        var _ci = _iff.idx[i] & 255;
        _use[_ci] = true;
        _top = max(_top, _ci);
    }
    var _map = array_create(256, 0);
    var _n = 0;
    for (var c = 0; c < 256; c++)
    {
        if (_top < _pc) { _map[c] = c; }
        else if (_use[c])
        {
            _map[c] = _n;
            _n += 1;
        }
    }
    if (_n > _pc) { return false; }
    for (var c2 = 0; c2 < 256; c2++)
    {
        var _to = _map[c2];
        // (colours past the picture's palette keep what they were)
        if ((_top < _pc || _use[c2]) && _to < _pc && c2 < _nc) { proj.pal[_to] = rgb_machine(_iff.pal[c2]); }
    }
    var _ox = max(0, (_iff.w - BD_W) div 2);
    var _oy = max(0, (_iff.h - BD_H) div 2);
    var _px = array_create(BD_W * BD_H, 0);
    for (var _iy = 0; _iy < min(BD_H, _iff.h); _iy++)
    {
        var _row = (_iy + _oy) * _iff.w + _ox;
        for (var _ix = 0; _ix < min(BD_W, _iff.w); _ix++) { _px[_iy * BD_W + _ix] = _map[_iff.idx[_row + _ix] & 255]; }
    }
    proj.pixels = _px;
    bd_dirty = true;
    return true;
}

// ---------------------------------------------------------------------------
// Indexed pictures (a palette and a colour number per pixel): IFF (iff_read), PNG with
// a palette (colour type 3) or greys of up to 8 bits, BMP of 1, 4 or 8 bits (plain or
// RLE) and GIF (its first picture). indexed_read gives the same struct as iff_read, so
// the backdrop keeps a picture's own colours and the sprite import its colour numbers.
// A picture that is not indexed (a true-colour or interlaced PNG, a JPG) comes back
// with indexed = false and no error: import it as RGB.
// ---------------------------------------------------------------------------

/// An empty indexed-picture struct (what iff_read and indexed_read return)
function indexed_new()
{
    return { w : 0, h : 0, pal : [], idx : [], clear : [], masked : false, err : "", indexed : true };
}

/// Reads picture file _path by what is in it (not its name): IFF, PNG, BMP or GIF
function indexed_read(_path)
{
    var _res = indexed_new();
    var _b = buffer_load(_path);
    if (_b == -1)
    {
        _res.err = "Could not read that file";
        return _res;
    }
    var _len = buffer_get_size(_b);
    var _id = "";
    if (_len >= 4) { _id = iff_id(_b, 0); }
    if (_id == "FORM")
    {
        buffer_delete(_b);
        return iff_read(_path);
    }
    if (_len >= 8 && buffer_peek(_b, 0, buffer_u8) == 0x89 && string_copy(_id, 2, 3) == "PNG") { png_read_indexed(_b, _res); }
    else if (_len >= 2 && string_copy(_id, 1, 2) == "BM") { bmp_read_indexed(_b, _res); }
    else if (_len >= 6 && string_copy(_id, 1, 3) == "GIF") { gif_read_indexed(_b, _res); }
    else { _res.indexed = false; }
    buffer_delete(_b);
    return _res;
}

/// Fills _res from PNG file buffer _b when it has a palette (or is grey, up to 8 bits a
/// pixel, not interlaced); else sets _res.indexed false
function png_read_indexed(_b, _res)
{
    var _len = buffer_get_size(_b);
    var _w = 0;
    var _h = 0;
    var _bd = 0;
    var _ct = -1;
    var _il = 0;
    var _plte = [];
    var _trns = -1;
    var _tlen = 0;
    var _z = buffer_create(1, buffer_fixed, 1);
    var _zl = 0;
    var _o = 8;
    while (_o + 12 <= _len)
    {
        var _sz = iff_u32(_b, _o);
        var _id = iff_id(_b, _o + 4);
        var _d = _o + 8;
        if (_d + _sz > _len) { _sz = _len - _d; }
        if (_id == "IHDR" && _sz >= 13)
        {
            _w = iff_u32(_b, _d);
            _h = iff_u32(_b, _d + 4);
            _bd = buffer_peek(_b, _d + 8, buffer_u8);
            _ct = buffer_peek(_b, _d + 9, buffer_u8);
            _il = buffer_peek(_b, _d + 12, buffer_u8);
            // only a palette or greys of up to 8 bits are indexed: stop reading the rest
            if ((_ct != 3 && _ct != 0) || _bd > 8 || _il != 0) { break; }
        }
        else if (_id == "PLTE")
        {
            for (var i = 0; i + 2 < _sz; i += 3)
            {
                array_push(_plte, rgb_make(buffer_peek(_b, _d + i, buffer_u8), buffer_peek(_b, _d + i + 1, buffer_u8), buffer_peek(_b, _d + i + 2, buffer_u8)));
            }
        }
        else if (_id == "tRNS")
        {
            _trns = _d;
            _tlen = _sz;
        }
        else if (_id == "IDAT" && _sz > 0)
        {
            buffer_resize(_z, _zl + _sz);
            buffer_copy(_b, _d, _sz, _z, _zl);
            _zl += _sz;
        }
        else if (_id == "IEND") { break; }
        _o = _d + _sz + 4;
    }
    if ((_ct != 3 && _ct != 0) || _bd > 8 || _il != 0)
    {
        buffer_delete(_z);
        _res.indexed = false;
        return;
    }
    if (_w <= 0 || _h <= 0 || _zl == 0 || (_ct == 3 && array_length(_plte) == 0))
    {
        buffer_delete(_z);
        _res.err = "There is no picture in that PNG file";
        return;
    }
    if (_w > SPR_IMP_MAX || _h > SPR_IMP_MAX)
    {
        buffer_delete(_z);
        _res.err = "Pictures up to " + string(SPR_IMP_MAX) + " x " + string(SPR_IMP_MAX) + " pixels";
        return;
    }
    var _u = buffer_decompress(_z);
    buffer_delete(_z);
    if (_u < 0)
    {
        _res.err = "That PNG file is damaged";
        return;
    }
    // undo each row's filter (1 byte a pixel or less: the pixel to the left is 1 byte back)
    var _ul = buffer_get_size(_u);
    var _rb = (_w * _bd + 7) >> 3;
    var _rows = buffer_create(_rb * _h, buffer_fixed, 1);
    buffer_fill(_rows, 0, buffer_u8, 0, _rb * _h);
    for (var _iy = 0; _iy < _h; _iy++)
    {
        var _so = _iy * (_rb + 1);
        if (_so + _rb + 1 > _ul) { break; }
        var _f = buffer_peek(_u, _so, buffer_u8);
        var _do = _iy * _rb;
        for (var k = 0; k < _rb; k++)
        {
            var _v = buffer_peek(_u, _so + 1 + k, buffer_u8);
            if (_f != 0)
            {
                var _a = 0;
                var _up = 0;
                var _c = 0;
                if (k > 0) { _a = buffer_peek(_rows, _do + k - 1, buffer_u8); }
                if (_iy > 0) { _up = buffer_peek(_rows, _do - _rb + k, buffer_u8); }
                if (k > 0 && _iy > 0) { _c = buffer_peek(_rows, _do - _rb + k - 1, buffer_u8); }
                switch (_f)
                {
                    case 1: _v += _a; break;
                    case 2: _v += _up; break;
                    case 3: _v += (_a + _up) >> 1; break;
                    case 4:
                        var _pp = _a + _up - _c;
                        var _pa = abs(_pp - _a);
                        var _pb = abs(_pp - _up);
                        var _pc = abs(_pp - _c);
                        if (_pa <= _pb && _pa <= _pc) { _v += _a; }
                        else if (_pb <= _pc) { _v += _up; }
                        else { _v += _c; }
                        break;
                }
            }
            buffer_poke(_rows, _do + k, buffer_u8, _v & 255);
        }
    }
    buffer_delete(_u);
    // the palette and which colour numbers are see-through
    var _pal = _plte;
    var _ncol = 1 << _bd;
    var _clr = array_create(256, false);
    if (_ct == 0)
    {
        _pal = [];
        for (var g = 0; g < _ncol; g++)
        {
            var _gv = round(g * 255 / max(1, _ncol - 1));
            array_push(_pal, rgb_make(_gv, _gv, _gv));
        }
        if (_trns >= 0 && _tlen >= 2) { _clr[iff_u16(_b, _trns) & 255] = true; }
    }
    else if (_trns >= 0)
    {
        for (var t = 0; t < min(_tlen, 256); t++)
        {
            if (buffer_peek(_b, _trns + t, buffer_u8) < 128) { _clr[t] = true; }
        }
    }
    var _n = _w * _h;
    var _idx = array_create(_n, 0);
    var _cl = array_create(_n, false);
    var _any = false;
    var _mk = _ncol - 1;
    for (var _ry = 0; _ry < _h; _ry++)
    {
        var _ro = _ry * _rb;
        for (var _rx = 0; _rx < _w; _rx++)
        {
            var _ci = 0;
            if (_bd == 8) { _ci = buffer_peek(_rows, _ro + _rx, buffer_u8); }
            else
            {
                var _bit = _rx * _bd;
                _ci = (buffer_peek(_rows, _ro + (_bit >> 3), buffer_u8) >> (8 - _bd - (_bit & 7))) & _mk;
            }
            _idx[_ry * _w + _rx] = _ci;
            if (_clr[_ci])
            {
                _cl[_ry * _w + _rx] = true;
                _any = true;
            }
        }
    }
    buffer_delete(_rows);
    _res.w = _w;
    _res.h = _h;
    _res.pal = _pal;
    _res.idx = _idx;
    _res.clear = _cl;
    _res.masked = _any;
}

/// Fills _res from BMP file buffer _b: 1, 4 or 8 bits a pixel, plain or RLE packed
function bmp_read_indexed(_b, _res)
{
    var _len = buffer_get_size(_b);
    if (_len < 26)
    {
        _res.err = "That BMP file is damaged";
        return;
    }
    var _off = buffer_peek(_b, 10, buffer_u32);
    var _hs = buffer_peek(_b, 14, buffer_u32);
    var _w = 0;
    var _h = 0;
    var _bpp = 0;
    var _comp = 0;
    var _nc = 0;
    var _pe = 4;
    if (_hs == 12)
    {
        _w = buffer_peek(_b, 18, buffer_u16);
        _h = buffer_peek(_b, 20, buffer_u16);
        _bpp = buffer_peek(_b, 24, buffer_u16);
        _pe = 3;
    }
    else
    {
        if (_len < 54)
        {
            _res.err = "That BMP file is damaged";
            return;
        }
        _w = buffer_peek(_b, 18, buffer_s32);
        _h = buffer_peek(_b, 22, buffer_s32);
        _bpp = buffer_peek(_b, 28, buffer_u16);
        _comp = buffer_peek(_b, 30, buffer_u32);
        _nc = buffer_peek(_b, 46, buffer_u32);
    }
    if (_bpp != 1 && _bpp != 4 && _bpp != 8)
    {
        _res.err = "Only BMP pictures of 2 to 256 colours (1, 4 or 8 bits) can be imported - save others as PNG";
        return;
    }
    if (_comp != 0 && !(_comp == 1 && _bpp == 8) && !(_comp == 2 && _bpp == 4))
    {
        _res.err = "That BMP picture is packed in a way ADAM does not know";
        return;
    }
    var _topdown = false;
    if (_h < 0)
    {
        _h = -_h;
        _topdown = true;
    }
    if (_w <= 0 || _h <= 0 || _w > SPR_IMP_MAX || _h > SPR_IMP_MAX)
    {
        _res.err = "Pictures up to " + string(SPR_IMP_MAX) + " x " + string(SPR_IMP_MAX) + " pixels";
        return;
    }
    if (_nc <= 0 || _nc > 256) { _nc = 1 << _bpp; }
    var _pal = [];
    var _po = 14 + _hs;
    for (var c = 0; c < _nc && _po + c * _pe + 2 < _len; c++)
    {
        var _q = _po + c * _pe;
        array_push(_pal, rgb_make(buffer_peek(_b, _q + 2, buffer_u8), buffer_peek(_b, _q + 1, buffer_u8), buffer_peek(_b, _q, buffer_u8)));
    }
    var _idx = array_create(_w * _h, 0);
    var _mk = (1 << _bpp) - 1;
    if (_comp == 0)
    {
        var _stride = ((_w * _bpp + 31) >> 5) * 4;
        for (var _r = 0; _r < _h; _r++)
        {
            var _dy = _h - 1 - _r;
            if (_topdown) { _dy = _r; }
            var _ro = _off + _r * _stride;
            if (_ro + _stride > _len) { break; }
            for (var _ix = 0; _ix < _w; _ix++)
            {
                var _bit = _ix * _bpp;
                _idx[_dy * _w + _ix] = (buffer_peek(_b, _ro + (_bit >> 3), buffer_u8) >> (8 - _bpp - (_bit & 7))) & _mk;
            }
        }
    }
    else
    {
        // RLE8 / RLE4: runs, end of line, end of picture, a jump, or pixels as they are
        var _p = _off;
        var _cx = 0;
        var _cr = 0;
        while (_p + 1 < _len && _cr < _h)
        {
            var _cnt = buffer_peek(_b, _p, buffer_u8);
            var _val = buffer_peek(_b, _p + 1, buffer_u8);
            _p += 2;
            var _ry = _h - 1 - _cr;
            if (_topdown) { _ry = _cr; }
            if (_cnt > 0)
            {
                for (var k = 0; k < _cnt; k++)
                {
                    var _ci = _val;
                    if (_comp == 2)
                    {
                        if ((k & 1) == 0) { _ci = _val >> 4; }
                        else { _ci = _val & 15; }
                    }
                    if (_cx < _w) { _idx[_ry * _w + _cx] = _ci; }
                    _cx += 1;
                }
            }
            else if (_val == 0)
            {
                _cx = 0;
                _cr += 1;
            }
            else if (_val == 1) { break; }
            else if (_val == 2)
            {
                if (_p + 1 >= _len) { break; }
                _cx += buffer_peek(_b, _p, buffer_u8);
                _cr += buffer_peek(_b, _p + 1, buffer_u8);
                _p += 2;
            }
            else
            {
                var _nb = _val;
                if (_comp == 2) { _nb = (_val + 1) >> 1; }
                for (var k2 = 0; k2 < _val && _p + (k2 >> 1) < _len; k2++)
                {
                    var _ca = 0;
                    if (_comp == 1) { _ca = buffer_peek(_b, _p + k2, buffer_u8); }
                    else
                    {
                        var _by = buffer_peek(_b, _p + (k2 >> 1), buffer_u8);
                        if ((k2 & 1) == 0) { _ca = _by >> 4; }
                        else { _ca = _by & 15; }
                    }
                    if (_cx < _w) { _idx[_ry * _w + _cx] = _ca; }
                    _cx += 1;
                }
                _p += _nb + (_nb & 1);
            }
        }
    }
    _res.w = _w;
    _res.h = _h;
    _res.pal = _pal;
    _res.idx = _idx;
    _res.clear = array_create(_w * _h, false);
    _res.masked = false;
}

/// Fills _res from GIF file buffer _b: its first picture, the transparent colour see-through
function gif_read_indexed(_b, _res)
{
    var _len = buffer_get_size(_b);
    if (_len < 13)
    {
        _res.err = "That GIF file is damaged";
        return;
    }
    var _w = buffer_peek(_b, 6, buffer_u16);
    var _h = buffer_peek(_b, 8, buffer_u16);
    var _pk = buffer_peek(_b, 10, buffer_u8);
    var _bg = buffer_peek(_b, 11, buffer_u8);
    if (_w <= 0 || _h <= 0 || _w > SPR_IMP_MAX || _h > SPR_IMP_MAX)
    {
        _res.err = "Pictures up to " + string(SPR_IMP_MAX) + " x " + string(SPR_IMP_MAX) + " pixels";
        return;
    }
    var _o = 13;
    var _gpal = [];
    if ((_pk & 0x80) != 0)
    {
        var _gn = 1 << ((_pk & 7) + 1);
        for (var c = 0; c < _gn && _o + 2 < _len; c++)
        {
            array_push(_gpal, rgb_make(buffer_peek(_b, _o, buffer_u8), buffer_peek(_b, _o + 1, buffer_u8), buffer_peek(_b, _o + 2, buffer_u8)));
            _o += 3;
        }
    }
    var _tidx = -1;
    while (_o < _len)
    {
        var _bt = buffer_peek(_b, _o, buffer_u8);
        _o += 1;
        if (_bt == 0x21)
        {
            // an extension: the graphic control one says which colour is see-through
            if (_o >= _len) { break; }
            var _lab = buffer_peek(_b, _o, buffer_u8);
            _o += 1;
            if (_lab == 0xf9 && _o + 5 <= _len && (buffer_peek(_b, _o + 1, buffer_u8) & 1) != 0) { _tidx = buffer_peek(_b, _o + 4, buffer_u8); }
            while (_o < _len)
            {
                var _s = buffer_peek(_b, _o, buffer_u8);
                _o += 1 + _s;
                if (_s == 0) { break; }
            }
        }
        else if (_bt == 0x2c)
        {
            if (_o + 10 > _len) { break; }
            var _fx = buffer_peek(_b, _o, buffer_u16);
            var _fy = buffer_peek(_b, _o + 2, buffer_u16);
            var _fw = buffer_peek(_b, _o + 4, buffer_u16);
            var _fh = buffer_peek(_b, _o + 6, buffer_u16);
            var _ipk = buffer_peek(_b, _o + 8, buffer_u8);
            _o += 9;
            var _pal = _gpal;
            if ((_ipk & 0x80) != 0)
            {
                _pal = [];
                var _ln = 1 << ((_ipk & 7) + 1);
                for (var c2 = 0; c2 < _ln && _o + 2 < _len; c2++)
                {
                    array_push(_pal, rgb_make(buffer_peek(_b, _o, buffer_u8), buffer_peek(_b, _o + 1, buffer_u8), buffer_peek(_b, _o + 2, buffer_u8)));
                    _o += 3;
                }
            }
            if (array_length(_pal) == 0)
            {
                for (var g = 0; g < 256; g++) { array_push(_pal, rgb_make(g, g, g)); }
            }
            var _mcs = buffer_peek(_b, _o, buffer_u8);
            _o += 1;
            // the picture's data sub-blocks, joined
            var _d = buffer_create(max(1, _len - _o), buffer_fixed, 1);
            var _dl = 0;
            while (_o < _len)
            {
                var _s2 = buffer_peek(_b, _o, buffer_u8);
                _o += 1;
                if (_s2 == 0) { break; }
                _s2 = min(_s2, _len - _o);
                buffer_copy(_b, _o, _s2, _d, _dl);
                _dl += _s2;
                _o += _s2;
            }
            var _pix = gif_lzw(_d, _dl, _mcs, _fw * _fh);
            buffer_delete(_d);
            // interlaced pictures store rows 0, 8, 16.. then 4, 12.. then 2, 6.. then 1, 3..
            var _rowof = array_create(max(1, _fh), 0);
            if ((_ipk & 0x40) != 0)
            {
                var _starts = [0, 4, 2, 1];
                var _steps = [8, 8, 4, 2];
                var _k = 0;
                for (var ps = 0; ps < 4; ps++)
                {
                    for (var rr = _starts[ps]; rr < _fh; rr += _steps[ps])
                    {
                        _rowof[_k] = rr;
                        _k += 1;
                    }
                }
            }
            else
            {
                for (var r2 = 0; r2 < _fh; r2++) { _rowof[r2] = r2; }
            }
            // outside the picture: see-through in a transparent GIF, else the background colour
            var _n = _w * _h;
            var _fill = 0;
            if (_bg < array_length(_pal)) { _fill = _bg; }
            var _idx = array_create(_n, _fill);
            var _cl = array_create(_n, _tidx >= 0);
            for (var _k2 = 0; _k2 < _fh; _k2++)
            {
                var _dy = _fy + _rowof[_k2];
                if (_dy >= _h) { continue; }
                for (var _ix = 0; _ix < _fw; _ix++)
                {
                    var _dx = _fx + _ix;
                    if (_dx >= _w) { break; }
                    var _ci = _pix[_k2 * _fw + _ix];
                    _idx[_dy * _w + _dx] = _ci;
                    _cl[_dy * _w + _dx] = (_ci == _tidx);
                }
            }
            _res.w = _w;
            _res.h = _h;
            _res.pal = _pal;
            _res.idx = _idx;
            _res.clear = _cl;
            _res.masked = (_tidx >= 0);
            return;
        }
        else { break; }
    }
    _res.err = "There is no picture in that GIF file";
}

/// GIF's LZW: _count colour numbers from the _dl bytes of buffer _d (codes start at
/// _mcs + 1 bits, least significant bit first, up to 12 bits)
function gif_lzw(_d, _dl, _mcs, _count)
{
    var _out = array_create(max(1, _count), 0);
    _mcs = clamp(_mcs, 2, 8);
    var _clr = 1 << _mcs;
    var _eoi = _clr + 1;
    var _pre = array_create(4096, 0);
    var _suf = array_create(4096, 0);
    for (var i = 0; i < _clr; i++) { _suf[i] = i; }
    var _stk = array_create(4097, 0);
    var _size = _mcs + 1;
    var _next = _clr + 2;
    var _old = -1;
    var _fc = 0;
    var _bits = 0;
    var _nb = 0;
    var _p = 0;
    var _q = 0;
    while (_q < _count)
    {
        while (_nb < _size && _p < _dl)
        {
            _bits |= buffer_peek(_d, _p, buffer_u8) << _nb;
            _nb += 8;
            _p += 1;
        }
        if (_nb < _size) { break; }
        var _code = _bits & ((1 << _size) - 1);
        _bits = _bits >> _size;
        _nb -= _size;
        if (_code == _clr)
        {
            _size = _mcs + 1;
            _next = _clr + 2;
            _old = -1;
            continue;
        }
        if (_code == _eoi) { break; }
        if (_old == -1)
        {
            if (_code >= _clr) { break; }
            _out[_q] = _code;
            _q += 1;
            _old = _code;
            _fc = _code;
            continue;
        }
        if (_code > _next) { break; }
        var _in = _code;
        var _sp = 0;
        if (_code == _next)
        {
            // the code being made: the last string and its own first colour
            _stk[_sp] = _fc;
            _sp += 1;
            _code = _old;
        }
        while (_code >= _clr && _sp < 4096)
        {
            _stk[_sp] = _suf[_code];
            _sp += 1;
            _code = _pre[_code];
        }
        _fc = _suf[_code];
        _stk[_sp] = _fc;
        _sp += 1;
        while (_sp > 0 && _q < _count)
        {
            _sp -= 1;
            _out[_q] = _stk[_sp];
            _q += 1;
        }
        if (_next < 4096)
        {
            _pre[_next] = _old;
            _suf[_next] = _fc;
            _next += 1;
            if (_next == (1 << _size) && _size < 12) { _size += 1; }
        }
        _old = _in;
    }
    return _out;
}
