/// ADAM - Tiles workspace: a tile set editor (tiles of 8 x 8, 16 x 16, 32 x 32
/// or 64 x 64 pixels - one size per game - in the backdrop colours; up to 96
/// in ADAM Lite and 512 in ADAM Pro) and a map editor for a tile world that
/// scrolls both ways behind the actors (up to 256 x 256 tiles in Lite, 1024 x
/// 1024 in Pro, and never more than 32640 pixels across). Memory is the real
/// limit: the memory bar shows what the game needs. The player can dig tiles
/// (fire + a direction) and place them again (fire).
///
/// Tile 0 is always empty air: colour 0, so the copper sky shows through.
/// Engine side: data block version 6, H_TILES / T_* / TP_* in engine.s.

#macro TILE_MAX 512             // tile types, ADAM Pro (lim_tiles)
#macro MAP_MAX 1024             // map width / height in tiles, ADAM Pro (lim_map_w / lim_map_h)
#macro WORLD_PX_MAX 32640       // the world is at most this many pixels across and down (engine words)
#macro TILE_ATLAS_COLS 32       // tiles across the atlas surface

/// A tile size ADAM supports: 8, 16, 32 or 64 (anything else becomes 16)
function tile_size_ok(_s)
{
    if (_s == 8 || _s == 16 || _s == 32 || _s == 64) { return _s; }
    return 16;
}

/// The scrolling picture for tiles of _s pixels (engine.s T_*): shift = log2 S,
/// ncol x nrow tiles, line bytes per line, ring bytes per plane (kept twice)
function tile_geometry(_s)
{
    var _sh = 4;
    if (_s == 8) { _sh = 3; }
    if (_s == 32) { _sh = 5; }
    if (_s == 64) { _sh = 6; }
    var _nc = 320 div _s + 2;
    var _nr = 256 div _s + 2;
    var _line = _nc * _s div 8;
    return { shift : _sh, ncol : _nc, nrow : _nr, line : _line, ring : _nr * _s * _line };
}

/// Smallest map in tiles: a screen and a bit (the engine's scrolling picture)
function map_w_min(_s)
{
    return 320 div _s + 2;
}

function map_h_min(_s)
{
    return 256 div _s + 2;
}

/// Biggest map in tiles for this edition (_s = tile size)
function map_w_max(_s)
{
    return min(lim_map_w(), WORLD_PX_MAX div _s);
}

function map_h_max(_s)
{
    return min(lim_map_h(), WORLD_PX_MAX div _s);
}

/// The tile size of the project (8, 16, 32 or 64)
function tile_px()
{
    return proj.tile_size;
}

function tile_new(_name, _s)
{
    return {
        name : _name,                       // up to 4 letters (shown on the HUD)
        px : array_create(_s * _s, 0),      // _s x _s colour numbers
        solid : true,                       // actors stand on it and cannot walk through it
        dig : true,                         // the player can dig it
        hard : 12,                          // 50ths of a second of digging
        points : 0,                         // score for digging it
        goal : false,                       // counts towards the level goal
        sound : -1,                         // sound when it is dug, -1 = none
        becomes : 0                         // the tile left behind
    };
}

/// A small pattern helper for the starter tiles: _base with _dark / _light specks
function tile_tex(_t, _base, _dark, _light, _seed)
{
    for (var i = 0; i < array_length(_t.px); i++)
    {
        var _h = ((i * 73 + _seed * 151) * 2654435761) mod 97;
        var _v = _base;
        if (_h < 18) { _v = _dark; }
        else if (_h > 84) { _v = _light; }
        _t.px[i] = _v;
    }
    return _t;
}

/// Pixels _px of a _from x _from tile as a _to x _to tile (nearest pixel)
function tile_rescale_px(_px, _from, _to)
{
    var _out = array_create(_to * _to, 0);
    for (var ty = 0; ty < _to; ty++)
    {
        for (var tx = 0; tx < _to; tx++)
        {
            _out[ty * _to + tx] = _px[(ty * _from div _to) * _from + (tx * _from div _to)];
        }
    }
    return _out;
}

/// 16 starter tiles in the default palette, so a new tile world can be painted
/// at once (drawn at 16 x 16, then made _s x _s)
function tiles_default(_s)
{
    var _t = [];
    var _air = tile_new("AIR", 16);
    _air.solid = false;
    _air.dig = false;
    array_push(_t, _air);
    var _g = tile_tex(tile_new("GRAS", 16), 11, 4, 12, 1);
    for (var gy = 0; gy < 4; gy++)
    {
        for (var gx = 0; gx < 16; gx++)
        {
            var _gv = 9;
            if ((gx + gy) mod 3 == 0) { _gv = 10; }
            if (gy == 3) { _gv = 8; }
            _g.px[gy * 16 + gx] = _gv;
        }
    }
    _g.sound = 3;
    array_push(_t, _g);
    var _d = tile_tex(tile_new("DIRT", 16), 11, 4, 12, 2);
    _d.sound = 3;
    _d.becomes = 15;
    array_push(_t, _d);
    var _st = tile_tex(tile_new("STON", 16), 15, 4, 1, 3);
    _st.hard = 24;
    _st.becomes = 15;
    array_push(_t, _st);
    var _sa = tile_tex(tile_new("SAND", 16), 12, 3, 14, 4);
    _sa.hard = 6;
    array_push(_t, _sa);
    var _br = tile_new("BRIK", 16);
    for (var by = 0; by < 16; by++)
    {
        for (var bx = 0; bx < 16; bx++)
        {
            var _off = 0;
            if ((by div 4) mod 2 == 1) { _off = 4; }
            var _bv = 13;
            if (by mod 4 == 3 || (bx + _off) mod 8 == 7) { _bv = 15; }
            _br.px[by * 16 + bx] = _bv;
        }
    }
    _br.hard = 50;
    array_push(_t, _br);
    var _w = tile_tex(tile_new("WOOD", 16), 11, 4, 12, 5);
    _w.solid = false;
    array_push(_t, _w);
    var _l = tile_tex(tile_new("LEAF", 16), 9, 8, 10, 6);
    _l.solid = false;
    _l.hard = 3;
    array_push(_t, _l);
    var _gold = tile_tex(tile_new("GOLD", 16), 15, 4, 14, 7);
    _gold.hard = 30;
    _gold.points = 20;
    _gold.goal = true;
    _gold.sound = 0;
    _gold.becomes = 15;
    array_push(_t, _gold);
    var _gem = tile_tex(tile_new("GEM", 16), 15, 4, 6, 8);
    _gem.hard = 40;
    _gem.points = 50;
    _gem.goal = true;
    _gem.sound = 0;
    _gem.becomes = 15;
    array_push(_t, _gem);
    var _ice = tile_tex(tile_new("ICE", 16), 7, 6, 1, 9);
    _ice.hard = 16;
    array_push(_t, _ice);
    var _wat = tile_tex(tile_new("WATR", 16), 2, 5, 6, 10);
    _wat.solid = false;
    _wat.dig = false;
    array_push(_t, _wat);
    var _lava = tile_tex(tile_new("LAVA", 16), 13, 3, 14, 11);
    _lava.solid = false;
    _lava.dig = false;
    array_push(_t, _lava);
    var _coal = tile_tex(tile_new("COAL", 16), 15, 0, 4, 12);
    _coal.hard = 26;
    _coal.points = 2;
    _coal.becomes = 15;
    array_push(_t, _coal);
    var _bed = tile_tex(tile_new("BEDR", 16), 4, 0, 15, 13);
    _bed.dig = false;
    array_push(_t, _bed);
    var _wall = tile_tex(tile_new("WALL", 16), 4, 0, 11, 14);
    _wall.solid = false;
    _wall.dig = false;
    array_push(_t, _wall);
    if (_s != 16)
    {
        for (var k = 0; k < array_length(_t); k++) { _t[k].px = tile_rescale_px(_t[k].px, 16, _s); }
    }
    return _t;
}

/// A tile from a loaded file, made safe, _s x _s pixels (older files: 16 x 16)
function tile_from_loaded(_raw, _s)
{
    var _t = struct_overlay(tile_new("TILE", _s), _raw);
    if (!is_string(_t.name)) { _t.name = "TILE"; }
    _t.name = string_upper(string_copy(_t.name, 1, 4));
    if (!is_array(_t.px)) { _t.px = array_create(_s * _s, 0); }
    if (array_length(_t.px) != _s * _s)
    {
        // a tile of another size (8, 16, 32 or 64): scaled; anything else starts empty
        var _from = round(sqrt(array_length(_t.px)));
        if (_from * _from == array_length(_t.px) && tile_size_ok(_from) == _from) { _t.px = tile_rescale_px(_t.px, _from, _s); }
        else { _t.px = array_create(_s * _s, 0); }
    }
    for (var i = 0; i < _s * _s; i++)
    {
        if (!is_numeric(_t.px[i])) { _t.px[i] = 0; }
        _t.px[i] = clamp(floor(_t.px[i]), 0, PAL_MAX - 1);
    }
    if (!is_bool(_t.solid)) { _t.solid = (is_numeric(_t.solid) && _t.solid != 0); }
    if (!is_bool(_t.dig)) { _t.dig = (is_numeric(_t.dig) && _t.dig != 0); }
    if (!is_bool(_t.goal)) { _t.goal = (is_numeric(_t.goal) && _t.goal != 0); }
    if (!is_numeric(_t.hard)) { _t.hard = 12; }
    _t.hard = clamp(floor(_t.hard), 1, 250);
    if (!is_numeric(_t.points)) { _t.points = 0; }
    _t.points = clamp(floor(_t.points), 0, 999);
    if (!is_numeric(_t.sound)) { _t.sound = -1; }
    _t.sound = clamp(floor(_t.sound), -1, 7);
    if (!is_numeric(_t.becomes)) { _t.becomes = 0; }
    _t.becomes = clamp(floor(_t.becomes), 0, TILE_MAX - 1);
    return _t;
}

/// Checks the tile set and map of a loaded project (called by project_from_loaded).
/// Keeps everything up to the ADAM Pro limits (a Lite build trims at build time).
function tiles_fix(_p)
{
    if (!is_numeric(_p.tile_size)) { _p.tile_size = 16; }
    _p.tile_size = tile_size_ok(_p.tile_size);
    var _s = _p.tile_size;
    var _lt = _p.tiles;
    var _t = [];
    if (is_array(_lt))
    {
        for (var i = 0; i < min(TILE_MAX, array_length(_lt)); i++) { array_push(_t, tile_from_loaded(_lt[i], _s)); }
    }
    if (array_length(_t) == 0) { _t = tiles_default(_s); }
    _t[0].solid = false;                    // air is always air
    _t[0].dig = false;
    for (var k = 0; k < array_length(_t); k++)
    {
        if (_t[k].becomes >= array_length(_t)) { _t[k].becomes = 0; }
    }
    _p.tiles = _t;
    if (!is_numeric(_p.map_w)) { _p.map_w = 64; }
    if (!is_numeric(_p.map_h)) { _p.map_h = 32; }
    var _mw = clamp(floor(_p.map_w), map_w_min(_s), min(MAP_MAX, WORLD_PX_MAX div _s));
    var _mh = clamp(floor(_p.map_h), map_h_min(_s), min(MAP_MAX, WORLD_PX_MAX div _s));
    var _n = _mw * _mh;
    if (!is_array(_p.map) || array_length(_p.map) != floor(_p.map_w) * floor(_p.map_h))
    {
        _p.map = array_create(_n, 0);
        _p.map_w = _mw;
        _p.map_h = _mh;
    }
    else
    {
        _p.map_w = floor(_p.map_w);
        _p.map_h = floor(_p.map_h);
        if (_mw != _p.map_w || _mh != _p.map_h) { map_resize(_p, _mw, _mh); }
    }
    var _nt = array_length(_t);
    for (var c = 0; c < _n; c++)
    {
        var _v = _p.map[c];
        if (!is_numeric(_v) || _v < 0 || _v >= _nt) { _p.map[c] = 0; }
    }
    if (!is_bool(_p.tiles_on)) { _p.tiles_on = (is_numeric(_p.tiles_on) && _p.tiles_on != 0); }
    if (!is_bool(_p.tile_dig)) { _p.tile_dig = (is_numeric(_p.tile_dig) && _p.tile_dig != 0); }
}

/// A starter world: sky, grass, dirt, stone and bedrock across the map
function map_starter(_w, _h)
{
    var _m = array_create(_w * _h, 0);
    for (var mx = 0; mx < _w; mx++)
    {
        var _top = floor(_h * 0.5) + round(2 * sin(mx / 5));
        for (var my = _top; my < _h; my++)
        {
            var _v = 3;
            if (my == _top) { _v = 1; }
            else if (my < _top + 4) { _v = 2; }
            if (my == _h - 1) { _v = 14; }
            _m[my * _w + mx] = _v;
        }
    }
    return _m;
}

/// Changes the map size, keeping the top-left of what was there
function map_resize(_p, _w, _h)
{
    var _nm = array_create(_w * _h, 0);
    for (var my = 0; my < min(_h, _p.map_h); my++)
    {
        for (var mx = 0; mx < min(_w, _p.map_w); mx++)
        {
            _nm[my * _w + mx] = _p.map[my * _p.map_w + mx];
        }
    }
    _p.map_w = _w;
    _p.map_h = _h;
    _p.map = _nm;
}

/// Changes the tile size of the project: every tile is scaled (nearest pixel),
/// the map keeps its tiles (so the world grows or shrinks in pixels, and the
/// actors move with it), and the map is fitted to the new size's limits.
function tile_set_size(_new)
{
    var _old = proj.tile_size;
    _new = tile_size_ok(_new);
    if (_new == _old) { return; }
    for (var t = 0; t < array_length(proj.tiles); t++) { proj.tiles[t].px = tile_rescale_px(proj.tiles[t].px, _old, _new); }
    proj.tile_size = _new;
    var _mw = clamp(proj.map_w, map_w_min(_new), max(map_w_min(_new), min(MAP_MAX, WORLD_PX_MAX div _new)));
    var _mh = clamp(proj.map_h, map_h_min(_new), max(map_h_min(_new), min(MAP_MAX, WORLD_PX_MAX div _new)));
    if (_mw != proj.map_w || _mh != proj.map_h) { map_resize(proj, _mw, _mh); }
    for (var a = 0; a < array_length(proj.actors) && proj.tiles_on; a++)
    {
        var _ac = proj.actors[a];
        _ac.x = clamp(round(_ac.x * _new / _old), 0, proj.map_w * _new - SPR_W);
        _ac.y = clamp(round(_ac.y * _new / _old), 0, proj.map_h * _new - SPR_H);
    }
    tile_camx = round(tile_camx * _new / _old);
    tile_camy = round(tile_camy * _new / _old);
    tiles_mark_all();
}

/// Width and height of the world actors move in: the screen, or the tile map
function world_w()
{
    if (proj.tiles_on) { return proj.map_w * proj.tile_size; }
    return BD_W;
}

function world_h()
{
    if (proj.tiles_on) { return proj.map_h * proj.tile_size; }
    return BD_H;
}

/// Bytes the tile world takes on the Amiga at colour depth _depth: the tile
/// pictures, the map (twice: as designed and as played), the scrolling picture
function tiles_mem_bytes(_depth)
{
    var _s = proj.tile_size;
    var _nt = array_length(proj.tiles);
    var _cell = 1;
    if (_nt > 256) { _cell = 2; }
    return _nt * _depth * _s * _s div 8 + 2 * proj.map_w * proj.map_h * _cell + _depth * 2 * tile_geometry(_s).ring;
}

// ---------------------------------------------------------------------------
// Pictures: an index surface with the tiles in a grid (the atlas, 32 across)
// and a cached picture of the part of the map in view, both coloured through
// the backdrop palette shader.
// ---------------------------------------------------------------------------

function tiles_mark_all()
{
    tile_atlas_dirty = true;
    tile_map_dirty = true;
}

/// Where tile _t is in the atlas
function tile_atlas_x(_t)
{
    return (_t mod TILE_ATLAS_COLS) * proj.tile_size;
}

function tile_atlas_y(_t)
{
    return (_t div TILE_ATLAS_COLS) * proj.tile_size;
}

function tile_atlas_surface()
{
    var _s = proj.tile_size;
    var _aw = TILE_ATLAS_COLS * _s;
    var _ah = max(1, ceil(array_length(proj.tiles) / TILE_ATLAS_COLS)) * _s;
    if (surface_exists(tile_atlas_surf))
    {
        if (surface_get_width(tile_atlas_surf) != _aw || surface_get_height(tile_atlas_surf) != _ah)
        {
            surface_free(tile_atlas_surf);
        }
    }
    if (!surface_exists(tile_atlas_surf))
    {
        tile_atlas_surf = surface_create(_aw, _ah);
        tile_atlas_dirty = true;
    }
    if (tile_atlas_dirty)
    {
        if (buffer_exists(tile_atlas_buf))
        {
            if (buffer_get_size(tile_atlas_buf) != _aw * _ah * 4)
            {
                buffer_delete(tile_atlas_buf);
                tile_atlas_buf = -1;
            }
        }
        if (!buffer_exists(tile_atlas_buf)) { tile_atlas_buf = buffer_create(_aw * _ah * 4, buffer_fixed, 1); }
        buffer_fill(tile_atlas_buf, 0, buffer_u32, 0xff000000, _aw * _ah * 4);
        for (var t = 0; t < array_length(proj.tiles); t++)
        {
            var _px = proj.tiles[t].px;
            var _ox = tile_atlas_x(t);
            var _oy = tile_atlas_y(t);
            for (var ty = 0; ty < _s; ty++)
            {
                for (var tx = 0; tx < _s; tx++)
                {
                    var _v = _px[ty * _s + tx];
                    if (_v != 0) { buffer_poke(tile_atlas_buf, (((_oy + ty) * _aw) + _ox + tx) * 4, buffer_u32, 0xff000000 | _v); }
                }
            }
        }
        buffer_set_surface(tile_atlas_buf, tile_atlas_surf, 0);
        tile_atlas_dirty = false;
        tile_map_dirty = true;
    }
    return tile_atlas_surf;
}

/// After drawing on tile _t: just that tile is put into the atlas again
function tile_atlas_update(_t)
{
    if (!surface_exists(tile_atlas_surf) || tile_atlas_dirty)
    {
        tile_atlas_dirty = true;
        return;
    }
    var _s = proj.tile_size;
    var _tb = buffer_create(_s * _s * 4, buffer_fixed, 1);
    var _px = proj.tiles[_t].px;
    for (var i = 0; i < _s * _s; i++) { buffer_write(_tb, buffer_u32, 0xff000000 | _px[i]); }
    var _ts = surface_create(_s, _s);
    buffer_set_surface(_tb, _ts, 0);
    buffer_delete(_tb);
    surface_set_target(tile_atlas_surf);
    gpu_set_blendenable(false);
    draw_surface(_ts, tile_atlas_x(_t), tile_atlas_y(_t));
    gpu_set_blendenable(true);
    surface_reset_target();
    surface_free(_ts);
    tile_map_dirty = true;
}

/// Draws map cell (_c, _r) into the view cache (it must be the target), whose
/// top left is map pixel (tile_view_mx, tile_view_my)
function tile_map_cell(_atlas, _c, _r)
{
    var _s = proj.tile_size;
    var _t = proj.map[_r * proj.map_w + _c];
    draw_surface_part(_atlas, tile_atlas_x(_t), tile_atlas_y(_t), _s, _s, _c * _s - tile_view_mx, _r * _s - tile_view_my);
}

/// The view cache: the map round map pixel (_mx, _my) .. + (_w, _h) as an index
/// picture, starting on a tile edge and one tile bigger, so it is only redrawn
/// when the view moves onto another tile or the map changes.
function tile_view_surface(_mx, _my, _w, _h)
{
    var _atlas = tile_atlas_surface();
    var _ts = proj.tile_size;
    _mx = (_mx div _ts) * _ts;
    _my = (_my div _ts) * _ts;
    _w = max(1, _w) + _ts;
    _h = max(1, _h) + _ts;
    if (surface_exists(tile_map_surf))
    {
        if (surface_get_width(tile_map_surf) != _w || surface_get_height(tile_map_surf) != _h) { surface_free(tile_map_surf); }
    }
    if (!surface_exists(tile_map_surf))
    {
        tile_map_surf = surface_create(_w, _h);
        tile_map_dirty = true;
    }
    if (tile_map_dirty || _mx != tile_view_mx || _my != tile_view_my)
    {
        tile_view_mx = _mx;
        tile_view_my = _my;
        var _s = proj.tile_size;
        surface_set_target(tile_map_surf);
        draw_clear_alpha(c_black, 1);
        gpu_set_blendenable(false);
        gpu_set_texfilter(false);
        var _c0 = max(0, _mx div _s);
        var _r0 = max(0, _my div _s);
        var _c1 = min(proj.map_w - 1, (_mx + _w - 1) div _s);
        var _r1 = min(proj.map_h - 1, (_my + _h - 1) div _s);
        for (var r = _r0; r <= _r1; r++)
        {
            for (var c = _c0; c <= _c1; c++)
            {
                if (proj.map[r * proj.map_w + c] != 0) { tile_map_cell(_atlas, c, r); }
            }
        }
        gpu_set_blendenable(true);
        gpu_set_texfilter(true);
        surface_reset_target();
        tile_map_dirty = false;
    }
    return tile_map_surf;
}

/// Sets map cell (_c, _r) to tile _t and redraws it in the view cache
function tile_map_set(_c, _r, _t)
{
    if (_c < 0 || _r < 0 || _c >= proj.map_w || _r >= proj.map_h) { return; }
    var _i = _r * proj.map_w + _c;
    if (proj.map[_i] == _t) { return; }
    proj.map[_i] = _t;
    proj_dirty = true;
    if (surface_exists(tile_map_surf) && !tile_map_dirty)
    {
        var _atlas = tile_atlas_surface();
        var _s = proj.tile_size;
        surface_set_target(tile_map_surf);
        gpu_set_blendenable(false);
        gpu_set_texfilter(false);
        draw_rectangle_colour(_c * _s - tile_view_mx, _r * _s - tile_view_my, _c * _s - tile_view_mx + _s - 1, _r * _s - tile_view_my + _s - 1, c_black, c_black, c_black, c_black, false);
        tile_map_cell(_atlas, _c, _r);
        gpu_set_blendenable(true);
        gpu_set_texfilter(true);
        surface_reset_target();
    }
}

/// Draws the part of the map from map pixel (_mx, _my), _w x _h map pixels,
/// at screen (_x, _y) magnified _scale times, in the Amiga colours
function tile_map_draw(_x, _y, _mx, _my, _w, _h, _scale)
{
    var _fx = floor(_mx);
    var _fy = floor(_my);
    var _s = tile_view_surface(_fx, _fy, _w, _h);
    var _ox = _fx - tile_view_mx;           // the view inside the cache
    var _oy = _fy - tile_view_my;
    backdrop_shader_begin();
    // the copper sky is fixed to the screen: the view's top line is line 0
    backdrop_shader_sky(surface_get_height(_s), -_oy);
    draw_surface_part_ext(_s, _ox, _oy, _w, _h, _x, _y, _scale, _scale, c_white, 1);
    backdrop_shader_end();
}

/// Draws tile _t at (_x, _y), _size pixels square
function tile_draw(_t, _x, _y, _size)
{
    var _a = tile_atlas_surface();
    var _s = proj.tile_size;
    backdrop_shader_begin();
    backdrop_shader_sky(0, 120);   // air in a tile picture: one line of mid sky
    draw_surface_part_ext(_a, tile_atlas_x(_t), tile_atlas_y(_t), _s, _s, _x, _y, _size / _s, _size / _s, c_white, 1);
    backdrop_shader_end();
}

function tiles_gfx_free()
{
    if (surface_exists(tile_atlas_surf)) { surface_free(tile_atlas_surf); }
    if (surface_exists(tile_map_surf)) { surface_free(tile_map_surf); }
    if (buffer_exists(tile_atlas_buf)) { buffer_delete(tile_atlas_buf); }
}

// ---------------------------------------------------------------------------
// The page
// ---------------------------------------------------------------------------

/// The grid of tiles to pick from, scrolling in the box _y .. _y2. Returns the bottom y.
function tiles_grid(_x, _y, _w, _y2, _id)
{
    var _cols = 5;
    var _cell = floor((_w - (_cols - 1) * 6) / _cols);
    var _n = array_length(proj.tiles);
    var _content = ceil(_n / _cols) * (_cell + 6) + 4;
    var _boxh = min(_content, _y2 - _y);
    if (_content > _boxh)
    {
        // room for the scroll bar
        _cell = floor((_w - 14 - (_cols - 1) * 6) / _cols);
        _content = ceil(_n / _cols) * (_cell + 6) + 4;
    }
    var _off = ui_scroll_begin(_id + "scroll", _x - 4, _y - 2, _x + _w + 4, _y + _boxh, _content);
    for (var i = 0; i < _n; i++)
    {
        var _gx = _x + (i mod _cols) * (_cell + 6);
        var _gy = _y + (i div _cols) * (_cell + 6) - _off;
        if (_gy < _y - _cell || _gy > _y + _boxh) { continue; }
        var _t = proj.tiles[i];
        var _what = "";
        if (_t.solid) { _what += "solid"; }
        else { _what += "see-through"; }
        if (_t.dig) { _what += ", can be dug"; }
        if (_t.goal) { _what += ", counts for the goal"; }
        var _hot = ui_register(_id + string(i), _gx, _gy, _gx + _cell, _gy + _cell, string(i) + ": " + _t.name + "|Click to pick this tile (" + _what + ").");
        ui_rrect(_gx, _gy, _gx + _cell, _gy + _cell, 6, pal_col(0), pal_col(0), 1);
        tile_draw(i, _gx + 3, _gy + 3, _cell - 6);
        if (i == 0) { ui_text(_gx + _cell / 2, _gy + _cell / 2, "air", global.TH.text_faint, fa_center, fa_middle, global.f_small, 1); }
        if (i >= lim_tiles())
        {
            // a Pro project in Lite: this tile is air on the disk
            ui_rrect(_gx, _gy, _gx + _cell, _gy + _cell, 6, c_black, c_black, 0.5);
            ui_text(_gx + _cell / 2, _gy + _cell / 2, "Pro", global.TH.warn, fa_center, fa_middle, global.f_small, 1);
        }
        if (tile_sel == i) { ui_rrect_line(_gx - 2, _gy - 2, _gx + _cell + 2, _gy + _cell + 2, 8, global.TH.accent, 1, 2); }
        else if (_hot) { ui_rrect_line(_gx - 1, _gy - 1, _gx + _cell + 1, _gy + _cell + 1, 7, global.TH.accent, 0.6, 1); }
        if (_hot && ui_pressed)
        {
            ui_take_click();
            tile_sel = i;
        }
    }
    ui_scroll_end(_id + "scroll", _x - 4, _y - 2, _x + _w + 4, _y + _boxh, _content);
    return _y + _boxh + 4;
}

function ws_tiles_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 260;
    var _rw = 320;
    tile_sel = clamp(tile_sel, 0, array_length(proj.tiles) - 1);
    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;

    // ---------------- left: the tiles, and the world settings ----------------
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "Tiles (" + string(array_length(proj.tiles)) + " / " + string(lim_tiles()) + ")");
    var _S = proj.tile_size;
    var _ly = tiles_grid(_x1 + 16, _y1 + 54, _lw - 32, max(_y1 + 160, _y2 - 360), "tile_pick_") + 10;
    var _bw = floor((_lw - 32 - 8) / 2);
    if (ui_button("tile_add", _x1 + 16, _ly, _bw, 30, "New tile", "New tile|Adds a tile (up to " + string(lim_tiles()) + "), starting as a copy of the one picked.", BTN_NORMAL))
    {
        if (array_length(proj.tiles) < lim_tiles())
        {
            undo_mark("tileadd" + string(current_time));
            var _nt = tile_from_loaded(json_parse(json_stringify(proj.tiles[tile_sel])), _S);
            if (tile_sel == 0)
            {
                _nt = tile_new("NEW", _S);
                for (var q = 0; q < _S * _S; q++) { _nt.px[q] = 1; }
            }
            else { _nt.name = string_copy(_nt.name, 1, 3) + "2"; }
            array_push(proj.tiles, _nt);
            tile_sel = array_length(proj.tiles) - 1;
            tile_atlas_dirty = true;
        }
        else { lim_toast("A tile set has up to " + string(lim_tiles()) + " tiles", string(TILE_MAX) + " tiles"); }
    }
    var _dst = BTN_DANGER;
    if (tile_sel == 0 || tile_sel != array_length(proj.tiles) - 1) { _dst = BTN_GHOST; }
    if (ui_button("tile_del", _x1 + 16 + _bw + 8, _ly, _bw, 30, "Remove last", "Remove the last tile|Takes the last tile out of the set (the map's cells that used it become air). Air cannot be removed. You can Undo this.", _dst))
    {
        var _last = array_length(proj.tiles) - 1;
        if (_last > 0)
        {
            undo_mark("tiledel" + string(current_time));
            array_delete(proj.tiles, _last, 1);
            for (var c = 0; c < array_length(proj.map); c++)
            {
                if (proj.map[c] >= _last) { proj.map[c] = 0; }
            }
            for (var k = 0; k < array_length(proj.tiles); k++)
            {
                if (proj.tiles[k].becomes >= _last) { proj.tiles[k].becomes = 0; }
            }
            tile_sel = min(tile_sel, _last - 1);
            tiles_mark_all();
        }
    }
    _ly += 40;
    ui_heading(_x1 + 16, _ly, "Tile size (one size for the whole game)");
    _ly += 18;
    var _sizes = [8, 16, 32, 64];
    var _scur = 1;
    for (var si = 0; si < 4; si++)
    {
        if (_sizes[si] == _S) { _scur = si; }
    }
    var _snew = ui_dropdown("tile_size", _x1 + 16, _ly, _lw - 32, 30, ["8 x 8 pixels", "16 x 16 pixels", "32 x 32 pixels", "64 x 64 pixels"], _scur, "Tile size|Every tile in the game is this size. 8 x 8: fine detail and huge worlds; 16 x 16: the classic Amiga size; 32 x 32 and 64 x 64: big chunky blocks with lots of detail each (and more memory - watch the bar at the bottom). Changing it scales every tile; you can Undo it.");
    if (_snew != _scur)
    {
        undo_mark_full("tilesz" + string(current_time));
        tile_set_size(_sizes[_snew]);
        _S = proj.tile_size;
    }
    _ly += 40;
    ui_heading(_x1 + 16, _ly, "Tile world");
    _ly += 20;
    var _on = ui_toggle("tile_on", _x1 + 16, _ly, "Use a tile world", proj.tiles_on, "Tile world|The game plays on this map instead of the backdrop: it scrolls left, right, up and down as the player moves, and actors stand on solid tiles. The backdrop is still used for the title, the level cards and the HUD strip at the top. Up to 8 actors, all hardware sprites.");
    if (_on != proj.tiles_on)
    {
        undo_mark_full("tileon" + string(current_time));
        proj.tiles_on = _on;
        if (_on)
        {
            // actors start near the top left of the map, inside it
            for (var a = 0; a < array_length(proj.actors); a++)
            {
                proj.actors[a].x = clamp(proj.actors[a].x, 0, world_w() - SPR_W);
                proj.actors[a].y = clamp(proj.actors[a].y, 0, world_h() - SPR_H);
            }
        }
        else
        {
            // back on the backdrop: bring actors placed deep in the map onto the screen
            for (var b = 0; b < array_length(proj.actors); b++)
            {
                var _ad = actor_dims(proj.actors[b]);
                proj.actors[b].x = clamp(proj.actors[b].x, 0, BD_W - _ad[0]);
                proj.actors[b].y = clamp(proj.actors[b].y, 0, BD_H - _ad[1]);
            }
        }
    }
    _ly += 32;
    set_val(proj, "tile_dig", ui_toggle("tile_dig", _x1 + 16, _ly, "Dig and place", proj.tile_dig, "Dig and place|The player digs: fire + a direction digs the tile that way (each tile says how long it takes), fire on its own puts the last tile dug back down in front of it. Up jumps. The HUD shows the tile carried and how many."), "tiledig");
    _ly += 36;
    ui_heading(_x1 + 16, _ly, "Map size (tiles)");
    _ly += 18;
    var _hw = floor((_lw - 32 - 8) / 2);
    var _mwmax = map_w_max(_S);
    if (proj.map_w > _mwmax) { _mwmax = proj.map_w; }      // a Pro project in Lite: never cut it here
    var _mhmax = map_h_max(_S);
    if (proj.map_h > _mhmax) { _mhmax = proj.map_h; }
    var _prohelp = "";
    if (!pro_edition()) { _prohelp = " ADAM Pro goes to " + string(min(MAP_MAX, WORLD_PX_MAX div _S)) + "."; }
    var _mwhelp = "Map width|In tiles of " + string(_S) + " pixels: " + string(map_w_min(_S)) + " to " + string(map_w_max(_S)) + " (a screen is " + string(320 div _S) + "). Hold Shift for steps of 10. Making it smaller cuts off the right-hand side." + _prohelp;
    var _mhhelp = "Map height|In tiles of " + string(_S) + " pixels: " + string(map_h_min(_S)) + " to " + string(map_h_max(_S)) + " (a screen is " + string(256 div _S) + "). Hold Shift for steps of 10. Making it smaller cuts off the bottom." + _prohelp;
    var _nw = ui_stepper("tile_mw", _x1 + 16, _ly, _hw, proj.map_w, map_w_min(_S), _mwmax, _mwhelp);
    var _nh = ui_stepper("tile_mh", _x1 + 16 + _hw + 8, _ly, _hw, proj.map_h, map_h_min(_S), _mhmax, _mhhelp);
    if (_nw != proj.map_w || _nh != proj.map_h)
    {
        undo_mark("tilesize");
        map_resize(proj, _nw, _nh);
        tile_map_dirty = true;
    }
    _ly += 40;
    var _mkb = ceil(tiles_mem_bytes(clamp(proj.depth, 1, machine_cur().max_depth)) / 1024);
    ui_text_wrap(_x1 + 16, _ly, string(proj.map_w * _S) + " x " + string(proj.map_h * _S) + " pixels (" + string_format(proj.map_w * _S / 320, 0, 1) + " x " + string_format(proj.map_h * _S / 256, 0, 1) + " screens) - the tile world needs about " + string(_mkb) + " KB of chip RAM", global.TH.text_faint, _lw - 32, global.f_small, 1);

    // ---------------- centre: Tile set or Map ----------------
    ui_panel(_cx1, _y1, _cx2, _y2, "");
    var _tabs = ["Map", "Tile set"];
    var _thelp = ["Map|Paint the world with tiles and drag actors to where they start.", "Tile set|Draw the tiles, " + string(_S) + " x " + string(_S) + " pixels in the backdrop colours, and say what each one does."];
    for (var tb = 0; tb < 2; tb++)
    {
        if (ui_tab("tile_tab_" + string(tb), _cx1 + 16 + tb * 120, _y1 + 12, 114, 30, _tabs[tb], tile_page == tb, _thelp[tb])) { tile_page = tb; }
    }
    if (tile_page == 1) { tiles_set_editor(_cx1, _y1 + 50, _cx2, _y2); }
    else { tiles_map_editor(_cx1, _y1 + 50, _cx2, _y2); }

    // ---------------- right: the picked tile ----------------
    var _rx = _x2 - _rw;
    var _t = proj.tiles[tile_sel];
    ui_panel(_rx, _y1, _x2, _y2, "Tile " + string(tile_sel) + ": " + _t.name);
    var _fx = _rx + 20;
    var _fw = _rw - 40;
    var _y = _y1 + 56;
    if (tile_sel == 0)
    {
        ui_text_wrap(_fx, _y, "Air is the empty tile: colour 0, so the copper sky (or colour 0) shows through. Actors move through it and it cannot be dug. Pick another tile to change it.", global.TH.text_dim, _fw, global.f_body, 1);
        return;
    }
    ui_heading(_fx, _y, "Name (4 letters, for the HUD)");
    var _nm = ui_textfield("tile_name", _fx, _y + 18, _fw, 32, _t.name, 4, "Name|Up to 4 letters. The HUD shows it for the tile the player carries.");
    set_val(_t, "name", string_upper(_nm), "tilename");
    _y += 62;
    set_val(_t, "solid", ui_toggle("tile_solid", _fx, _y, "Solid", _t.solid, "Solid|Actors stand on it and cannot walk through it. Switch it off for things in the background: tree trunks, cave walls, water."), "tilesolid");
    _y += 32;
    set_val(_t, "dig", ui_toggle("tile_digok", _fx, _y, "Can be dug", _t.dig, "Can be dug|The player can dig it out (with Dig and place on) and carries it to put down again."), "tiledigok");
    _y += 32;
    set_val(_t, "goal", ui_toggle("tile_goal", _fx, _y, "Counts towards the goal", _t.goal, "Counts towards the level goal|Digging it adds one to the level goal counter (Levels page) - gold, gems, treasure."), "tilegoal");
    _y += 36;
    var _half = floor((_fw - 12) / 2);
    ui_heading(_fx, _y, "Dig time (50ths)");
    ui_heading(_fx + _half + 12, _y, "Points");
    set_val(_t, "hard", ui_stepper("tile_hard", _fx, _y + 18, _half, _t.hard, 1, 250, "Dig time|How long it takes to dig, in 50ths of a second: 6 is sand, 25 stone, 60 a strong wall. Hold Shift for steps of 10."), "tilehard");
    set_val(_t, "points", ui_stepper("tile_pts", _fx + _half + 12, _y + 18, _half, _t.points, 0, 999, "Points|Added to the score when it is dug."), "tilepts");
    _y += 62;
    ui_heading(_fx, _y, "Sound when dug");
    var _sn = ["(none)"];
    for (var s = 0; s < 8; s++) { array_push(_sn, string(s + 1) + ": " + proj.sfx[s].name); }
    set_val(_t, "sound", ui_dropdown("tile_snd", _fx, _y + 18, _fw, 30, _sn, _t.sound + 1, "Sound|Plays when the tile is dug out. Make sounds on the Sound page.") - 1, "tilesnd");
    _y += 58;
    ui_heading(_fx, _y, "Leaves behind");
    var _tn = [];
    for (var k2 = 0; k2 < array_length(proj.tiles); k2++) { array_push(_tn, string(k2) + ": " + proj.tiles[k2].name); }
    set_val(_t, "becomes", ui_dropdown("tile_bec", _fx, _y + 18, _fw, 30, _tn, _t.becomes, "Leaves behind|What is left when it is dug: air (the sky shows), or a background tile like a dark cave wall."), "tilebec");
    _y += 58;
    if (_y + 90 < _y2)
    {
        ui_heading(_fx, _y, "Actual size");
        ui_inset(_fx, _y + 18, _fx + _fw, _y + 18 + 70, 8);
        var _ax = _fx + 10;
        // actual size (twice as big for small tiles), then three in a row to check how it tiles
        var _shown = min(56, _S * max(1, 32 div _S));
        ui_rrect(_ax - 2, _y + 26, _ax + _shown + 2, _y + 28 + _shown, 2, pal_col(0), pal_col(0), 1);
        tile_draw(tile_sel, _ax, _y + 27, _shown);
        _ax += _shown + 16;
        for (var rr = 0; rr < 3; rr++) { tile_draw(tile_sel, _ax + rr * 32, _y + 27, 32); }
    }
}

/// The tile set editor: the picked tile, 16 x 16, drawn with the backdrop colours
function tiles_set_editor(_x1, _y1, _x2, _y2)
{
    var _t = proj.tiles[tile_sel];
    var _S = proj.tile_size;
    var _ncol = pal_count();
    var _pcols = 16;
    var _pcell = min(26, floor((_x2 - _x1 - 40 - (_pcols - 1) * 4) / _pcols));
    var _prow = ceil(_ncol / _pcols);
    var _ph = _prow * (_pcell + 4) + 30;
    var _avail = min(_x2 - _x1 - 40, _y2 - _y1 - _ph - 80);
    var _ps = max(4, floor(_avail / _S));
    var _gw = _ps * _S;
    var _gx = floor((_x1 + _x2 - _gw) / 2);
    var _gy = _y1 + 10;
    ui_rrect(_gx - 8, _gy - 8, _gx + _gw + 8, _gy + _gw + 8, 10, c_black, c_black, 0.35);
    tile_draw(tile_sel, _gx, _gy, _gw);
    if (_ps >= 6)
    {
        draw_set_alpha(0.14);
        for (var gl = 0; gl <= _S; gl++)
        {
            draw_line_colour(_gx + gl * _ps, _gy, _gx + gl * _ps, _gy + _gw, c_white, c_white);
            draw_line_colour(_gx, _gy + gl * _ps, _gx + _gw, _gy + gl * _ps, c_white, c_white);
        }
        draw_set_alpha(1);
    }
    if (tile_sel == 0)
    {
        ui_text((_x1 + _x2) / 2, _gy + _gw / 2, "Air is always empty", global.TH.text_dim, fa_center, fa_middle, global.f_bold, 1);
    }
    var _hot = ui_register("tile_canvas", _gx, _gy, _gx + _gw - 1, _gy + _gw - 1, "Tile|Left-click draws with the colour picked below, right-click with colour 0 (see-through to the sky). The tile repeats across the map, so make its edges meet.");
    if (_hot && tile_sel > 0)
    {
        var _hx = clamp(floor((ui_mx - _gx) / _ps), 0, _S - 1);
        var _hy = clamp(floor((ui_my - _gy) / _ps), 0, _S - 1);
        draw_rectangle_colour(_gx + _hx * _ps, _gy + _hy * _ps, _gx + _hx * _ps + _ps - 1, _gy + _hy * _ps + _ps - 1, c_white, c_white, c_white, c_white, true);
        if (ui_pressed || ui_rpressed)
        {
            undo_mark("tiledraw" + string(current_time));
            tile_drawing = true;
            ui_take_click();
        }
        if (tile_drawing)
        {
            var _v = -1;
            if (ui_held) { _v = tile_pen; }
            if (ui_rheld) { _v = 0; }
            if (_v >= 0 && _t.px[_hy * _S + _hx] != _v)
            {
                _t.px[_hy * _S + _hx] = _v;
                proj_dirty = true;
                tile_atlas_update(tile_sel);
            }
        }
    }
    if (!ui_held && !ui_rheld) { tile_drawing = false; }

    // colours and whole-tile buttons
    var _py = _gy + _gw + 20;
    ui_heading(_x1 + 20, _py, "Colour " + string(tile_pen) + "  (the backdrop palette)");
    tile_pen = clamp(ui_palette_grid("tile_pal", _x1 + 20, _py + 18, _pcell, _pcols, tile_pen, "Colour|Pick the colour to draw with. Tiles use the backdrop's colours; colour 0 lets the copper sky show through."), 0, _ncol - 1);
    var _by = _py + 18 + _prow * (_pcell + 4) + 8;
    var _ops = ["Fill", "Flip H", "Flip V", "Clear"];
    var _ow = floor((_x2 - _x1 - 40 - 3 * 8) / 4);
    for (var o = 0; o < 4; o++)
    {
        var _st = BTN_NORMAL;
        if (o == 3) { _st = BTN_DANGER; }
        if (ui_button("tile_op_" + string(o), _x1 + 20 + o * (_ow + 8), _by, _ow, 30, _ops[o], _ops[o] + "|Changes the whole tile. You can Undo it.", _st) && tile_sel > 0)
        {
            undo_mark("tileop" + string(current_time));
            var _old = array_create(_S * _S, 0);
            array_copy(_old, 0, _t.px, 0, _S * _S);
            for (var p = 0; p < _S * _S; p++)
            {
                var _ox = p mod _S;
                var _oy = p div _S;
                var _nv = _old[p];
                if (o == 0) { _nv = tile_pen; }
                if (o == 1) { _nv = _old[_oy * _S + (_S - 1 - _ox)]; }
                if (o == 2) { _nv = _old[(_S - 1 - _oy) * _S + _ox]; }
                if (o == 3) { _nv = 0; }
                _t.px[p] = _nv;
            }
            tile_atlas_update(tile_sel);
        }
    }
}

/// The map editor: paint tiles, drag actors; wheel scrolls (Shift: sideways,
/// Ctrl: zoom), the middle button or Space + drag moves the view
function tiles_map_editor(_x1, _y1, _x2, _y2)
{
    var _S = proj.tile_size;
    var _mw = proj.map_w * _S;
    var _mh = proj.map_h * _S;
    // tools
    var _tools = ["Paint", "Box", "Pick"];
    var _toolh = ["Paint|Left-click paints the picked tile, right-click paints air.", "Box|Drag a box to fill it with the picked tile (right-drag: air).", "Pick|Click a tile on the map to pick it."];
    for (var tl = 0; tl < 3; tl++)
    {
        if (ui_tab("tile_tool_" + string(tl), _x2 - 16 - (3 - tl) * 90, _y1 - 38, 86, 30, _tools[tl], tile_tool == tl, _toolh[tl])) { tile_tool = tl; }
    }
    var _vx1 = _x1 + 16;
    var _vy1 = _y1 + 4;
    var _vx2 = _x2 - 16;
    var _vy2 = _y2 - 40;
    // zoom: 1/4 to 4; zooming out stops where the view would hold too many tiles to draw quickly
    var _zooms = [0.25, 0.5, 1, 2, 3, 4];
    var _zmin = 0;
    while (_zmin < 3 && (((_vx2 - _vx1) / _zooms[_zmin] / _S) * ((_vy2 - _vy1) / _zooms[_zmin] / _S) > 12000 || (_vx2 - _vx1) / _zooms[_zmin] > 4000 || (_vy2 - _vy1) / _zooms[_zmin] > 4000)) { _zmin += 1; }
    var _zi = 2;
    for (var zq = 0; zq < 6; zq++)
    {
        if (_zooms[zq] == tile_zoom) { _zi = zq; }
    }
    _zi = max(_zi, _zmin);
    tile_zoom = _zooms[_zi];
    var _sc = tile_zoom;
    var _vw = floor((_vx2 - _vx1) / _sc);              // map pixels shown
    var _vh = floor((_vy2 - _vy1) / _sc);
    _vw = min(_vw, _mw);
    _vh = min(_vh, _mh);
    tile_camx = clamp(tile_camx, 0, max(0, _mw - _vw));
    tile_camy = clamp(tile_camy, 0, max(0, _mh - _vh));
    var _dx = _vx1;
    var _dy = _vy1;
    ui_rrect(_dx - 4, _dy - 4, _dx + _vw * _sc + 4, _dy + _vh * _sc + 4, 8, c_black, c_black, 0.35);
    tile_map_draw(_dx, _dy, tile_camx, tile_camy, _vw, _vh, _sc);

    // the screen the Amiga shows at the start (round the player)
    var _pl = -1;
    for (var a = 0; a < array_length(proj.actors); a++)
    {
        if ((proj.actors[a].role == 0 || proj.actors[a].role == 6) && _pl < 0) { _pl = a; }
    }
    if (_pl >= 0)
    {
        var _sx = clamp(proj.actors[_pl].x + 8 - 160, 0, _mw - BD_W);
        var _sy = clamp(proj.actors[_pl].y + 12 - 136, 0, _mh - BD_H);
        var _rx1 = _dx + (_sx - tile_camx) * _sc;
        var _ry1 = _dy + (_sy - tile_camy) * _sc;
        draw_set_alpha(0.6);
        draw_rectangle_colour(_rx1, _ry1, _rx1 + BD_W * _sc, _ry1 + BD_H * _sc, c_white, c_white, c_white, c_white, true);
        draw_set_alpha(1);
    }

    // actors on the map: drag them to where they start
    var _alloc = actors_alloc_channels();
    var _hover = -1;
    var _inview = ui_hit(_dx, _dy, _dx + _vw * _sc, _dy + _vh * _sc);
    for (var d = array_length(proj.actors) - 1; d >= 0; d--)
    {
        var _ac = proj.actors[d];
        var _ax = _dx + (_ac.x - tile_camx) * _sc;
        var _ay = _dy + (_ac.y - tile_camy) * _sc;
        if (_ax < _dx - SPR_W * _sc || _ay < _dy - SPR_H * _sc || _ax > _dx + _vw * _sc || _ay > _dy + _vh * _sc) { continue; }
        var _alpha = 1;
        if (!_ac.visible) { _alpha = 0.4; }
        draw_sprite_amiga_cols(actor_preview_sprite(_ac), _ax, _ay, _sc, actor_cols_from(_alloc, d), _alpha);
        if (_inview && point_in_rectangle(ui_mx, ui_my, _ax, _ay, _ax + SPR_W * _sc, _ay + SPR_H * _sc) && _hover < 0) { _hover = d; }
    }
    var _help = "Map|Paint with the tile picked on the left (right-click: air). Drag an actor to move where it starts. Mouse wheel scrolls (Shift: sideways, Ctrl: zoom); drag with the middle button or Space held to move the view. The white box is the first screen the Amiga shows.";
    ui_register("tile_map", _dx, _dy, _dx + _vw * _sc, _dy + _vh * _sc, _help);
    var _cellx = floor((ui_mx - _dx) / _sc + tile_camx) div _S;
    var _celly = floor((ui_my - _dy) / _sc + tile_camy) div _S;

    // scrolling and zoom
    if (_inview && ui_wheel != 0)
    {
        if (keyboard_check(vk_control)) { tile_zoom = _zooms[clamp(_zi + sign(ui_wheel), _zmin, 5)]; }
        else if (keyboard_check(vk_shift)) { tile_camx -= ui_wheel * 48; }
        else { tile_camy -= ui_wheel * 48; }
        ui_wheel = 0;
    }
    var _panning = mouse_check_button(mb_middle) || (keyboard_check(vk_space) && ui_held && ui_focus == "");
    if (_inview && (mouse_check_button_pressed(mb_middle) || (keyboard_check(vk_space) && ui_pressed && ui_focus == "")))
    {
        tile_pan = true;
        tile_pan_mx = ui_mx;
        tile_pan_my = ui_my;
        tile_pan_cx = tile_camx;
        tile_pan_cy = tile_camy;
        if (ui_pressed) { ui_take_click(); }
    }
    if (tile_pan)
    {
        if (!_panning) { tile_pan = false; }
        else
        {
            tile_camx = tile_pan_cx - (ui_mx - tile_pan_mx) / _sc;
            tile_camy = tile_pan_cy - (ui_my - tile_pan_my) / _sc;
        }
    }

    // dragging an actor
    if (!tile_pan && _hover >= 0 && ui_pressed && tile_drag_actor < 0 && !tile_painting)
    {
        sel_actor = _hover;
        tile_drag_actor = _hover;
        tile_drag_dx = ui_mx - (_dx + (proj.actors[_hover].x - tile_camx) * _sc);
        tile_drag_dy = ui_my - (_dy + (proj.actors[_hover].y - tile_camy) * _sc);
        undo_mark("tileactor" + string(current_time));
        ui_take_click();
    }
    if (tile_drag_actor >= 0)
    {
        if (!ui_held) { tile_drag_actor = -1; }
        else if (tile_drag_actor < array_length(proj.actors))
        {
            var _da = proj.actors[tile_drag_actor];
            _da.x = clamp(round((ui_mx - tile_drag_dx - _dx) / _sc + tile_camx), 0, _mw - SPR_W);
            _da.y = clamp(round((ui_my - tile_drag_dy - _dy) / _sc + tile_camy), 0, _mh - SPR_H);
            proj_dirty = true;
        }
    }

    // painting
    if (!tile_pan && tile_drag_actor < 0 && _inview)
    {
        if (_cellx >= 0 && _celly >= 0 && _cellx < proj.map_w && _celly < proj.map_h)
        {
            var _hx = _dx + (_cellx * _S - tile_camx) * _sc;
            var _hy = _dy + (_celly * _S - tile_camy) * _sc;
            draw_rectangle_colour(_hx, _hy, _hx + _S * _sc - 1, _hy + _S * _sc - 1, c_white, c_white, c_white, c_white, true);
            if (ui_pressed || ui_rpressed)
            {
                ui_take_click();
                if (tile_tool == 2) { tile_sel = proj.map[_celly * proj.map_w + _cellx]; }
                else if (tile_sel >= lim_tiles() && !ui_rpressed)
                {
                    lim_toast("Tiles past " + string(lim_tiles()) + " are air on the disk", string(TILE_MAX) + " tiles");
                }
                else
                {
                    undo_mark("tilepaint" + string(current_time));
                    tile_painting = true;
                    tile_paint_v = tile_sel;
                    if (ui_rpressed) { tile_paint_v = 0; }
                    tile_box_c = _cellx;
                    tile_box_r = _celly;
                }
            }
            if (tile_painting && tile_tool == 0)
            {
                // join up to the last cell painted, so a fast drag leaves no gaps
                var _steps = max(abs(_cellx - tile_box_c), abs(_celly - tile_box_r));
                for (var st = 1; st <= _steps; st++)
                {
                    tile_map_set(tile_box_c + round((_cellx - tile_box_c) * st / _steps), tile_box_r + round((_celly - tile_box_r) * st / _steps), tile_paint_v);
                }
                tile_map_set(_cellx, _celly, tile_paint_v);
                tile_box_c = _cellx;
                tile_box_r = _celly;
            }
        }
    }
    if (tile_painting && tile_tool == 1)
    {
        var _c0 = min(tile_box_c, _cellx);
        var _c1 = max(tile_box_c, _cellx);
        var _r0 = min(tile_box_r, _celly);
        var _r1 = max(tile_box_r, _celly);
        var _bx1 = _dx + (_c0 * _S - tile_camx) * _sc;
        var _by1 = _dy + (_r0 * _S - tile_camy) * _sc;
        var _bx2 = _dx + ((_c1 + 1) * _S - tile_camx) * _sc;
        var _by2 = _dy + ((_r1 + 1) * _S - tile_camy) * _sc;
        draw_rectangle_colour(_bx1, _by1, _bx2, _by2, global.TH.accent, global.TH.accent, global.TH.accent, global.TH.accent, true);
        if (!ui_held && !ui_rheld)
        {
            for (var br = max(0, _r0); br <= min(proj.map_h - 1, _r1); br++)
            {
                for (var bc = max(0, _c0); bc <= min(proj.map_w - 1, _c1); bc++) { proj.map[br * proj.map_w + bc] = tile_paint_v; }
            }
            proj_dirty = true;
            tile_map_dirty = true;
        }
    }
    if (!ui_held && !ui_rheld) { tile_painting = false; }

    // status line
    var _st = "Map " + string(proj.map_w) + " x " + string(proj.map_h) + " tiles of " + string(_S) + " x " + string(_S) + "  -  zoom " + string(tile_zoom) + "x";
    if (_inview && _cellx >= 0 && _celly >= 0 && _cellx < proj.map_w && _celly < proj.map_h)
    {
        var _under = proj.map[_celly * proj.map_w + _cellx];
        _st += "  -  column " + string(_cellx) + ", row " + string(_celly) + ": " + proj.tiles[_under].name;
    }
    if (!proj.tiles_on) { _st += "  -  switch 'Use a tile world' on (left) to play on this map"; }
    ui_text(_x1 + 20, _y2 - 20, ui_text_fit(_st, global.f_small, _x2 - _x1 - 40), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
}
