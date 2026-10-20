/// ADAM - Lite / Pro edition
///
/// ADAM Lite is free; ADAM Pro is a separate paid download on itch.io. Both
/// come from this one project: set ADAM_PRO below and build each one
/// (ADAM_..._LITE and ADAM_..._PRO, see docs/RELEASE.md).
/// Both editions have the HUD editor; drawing a custom font is Pro-only. Pro adds extra
/// example games and lessons and higher limits (lim_* below). pro_edition() / pro_gate() decide those;
/// pro_on() and feature_gate() are the old feature switches, now always on -
/// the one place to make a feature Pro-only again.

#macro ADAM_PRO 1               // 0 = build ADAM Lite, 1 = build ADAM Pro
#macro ADAM_PRO_URL "https://polytricity.itch.io/adam-amiga-developmental-machine"          // the ADAM Pro page on itch.io ("" hides the 'Get ADAM Pro' button)

/// True when this is the ADAM Pro build (the extra example games and lessons)
function pro_edition()
{
    if (ADAM_DEV_TOOLS) { return global.pro_preview == 1; }
    return ADAM_PRO == 1;
}

/// Dev tool (ADAM_DEV_TOOLS): Shift+F12 switches the editor between Lite and
/// Pro, to check the limits and extras without rebuilding. Public builds keep ADAM_PRO.
function pro_preview_toggle()
{
    if (!ADAM_DEV_TOOLS) { return; }
    if (global.pro_preview == 1)
    {
        global.pro_preview = 0;
        toast("Dev: acting as ADAM Lite (Shift+F12 for Pro)", 0);
    }
    else
    {
        global.pro_preview = 1;
        toast("Dev: acting as ADAM Pro (Shift+F12 for Lite)", 0);
    }
}

/// True when the editing features may be used: every edition
function pro_on()
{
    return true;
}

/// For a feature button: always allowed (see the note at the top)
function feature_gate(_what)
{
    return true;
}

/// For Pro extras (example games, lessons): true in ADAM Pro, otherwise a
/// friendly message saying it comes with ADAM Pro. _what names it.
function pro_gate(_what)
{
    if (pro_edition()) { return true; }
    toast(_what + " comes with ADAM Pro - click LITE at the top to find out more", 1);
    return false;
}

// ---------------------------------------------------------------------------
// Lite and Pro limits (Bob, Oct 2026): ADAM Lite has every feature with a
// smaller ceiling; ADAM Pro raises it and adds custom font drawing. A Pro project opened in Lite keeps
// all its data - the editor shows what is over the Lite limit and the disk
// gets a trimmed copy (lite_trim, with a warning on the Build page).
// ---------------------------------------------------------------------------
#macro LITE_FRAMES 6            // frames per animation (Pro: ANIM_FRAMES = 16)
#macro LITE_ACTORS 12           // actors on the disk: the 8 sprites, the rest BOBs (Pro: 32)
#macro LITE_BANK 64             // sprite bank slots (Pro: 128)
#macro LITE_SPR_W 32            // biggest sprite / BOB (Pro: 64 x 64)
#macro LITE_SPR_H 32
#macro LITE_TILES 96            // tile types in a tile set (Pro: TILE_MAX = 512)
#macro LITE_MAP_W 256           // tile map size in tiles (Pro: MAP_MAX = 1024 x 1024); memory is the real limit
#macro LITE_MAP_H 256
#macro LITE_SOUNDS 8            // sounds (Sound page slots; Pro: SFX_MAX = 64)

function lim_sounds()
{
    if (pro_edition()) { return SFX_MAX; }
    return LITE_SOUNDS;
}

function lim_frames()
{
    if (pro_edition()) { return ANIM_FRAMES; }
    return LITE_FRAMES;
}

/// True when the With Fire joystick (Fire animations) can be used
function lim_fire()
{
    return true;
}

function lim_actors()
{
    if (pro_edition()) { return ACT_MAX_ALL; }
    return LITE_ACTORS;
}

function lim_bank()
{
    if (pro_edition()) { return SPR_COUNT; }
    return LITE_BANK;
}

function lim_spr_w()
{
    if (pro_edition()) { return 64; }
    return LITE_SPR_W;
}

function lim_spr_h()
{
    if (pro_edition()) { return 64; }
    return LITE_SPR_H;
}

function lim_tiles()
{
    if (pro_edition()) { return TILE_MAX; }
    return LITE_TILES;
}

function lim_map_w()
{
    if (pro_edition()) { return MAP_MAX; }
    return LITE_MAP_W;
}

function lim_map_h()
{
    if (pro_edition()) { return MAP_MAX; }
    return LITE_MAP_H;
}

/// Toast for reaching a Lite limit: _what (e.g. "An animation has 6 frames") and what Pro gives
function lim_toast(_what, _pro)
{
    if (pro_edition())
    {
        toast(_what, 1);
        return;
    }
    toast(_what + " in ADAM Lite - ADAM Pro gives " + _pro, 1);
}

/// A copy of project _p that fits ADAM Lite, for writing the disk: the shared
/// parts are not copied, only what is trimmed. Notes go in _warn.
function lite_trim(_p, _warn)
{
    var _q = {};
    var _names = variable_struct_get_names(_p);
    for (var i = 0; i < array_length(_names); i++) { _q[$ _names[i]] = _p[$ _names[i]]; }

    // actors: the first 12 (a tile world: 8), frames cut to 6
    var _keepn = LITE_ACTORS;
    if (_p.tiles_on) { _keepn = ACT_MAX_TILE; }
    var _cut_frames = false;
    var _acts = [];
    for (var a = 0; a < min(_keepn, array_length(_p.actors)); a++)
    {
        var _src = _p.actors[a];
        var _ac = {};
        var _an = variable_struct_get_names(_src);
        for (var k = 0; k < array_length(_an); k++) { _ac[$ _an[k]] = _src[$ _an[k]]; }
        var _anims = [];
        for (var e = 0; e < array_length(_src.anims); e++)
        {
            var _sa = _src.anims[e];
            var _fr = [];
            var _nf = array_length(_sa.frames);
            if (_nf > LITE_FRAMES) { _cut_frames = true; }
            for (var f = 0; f < min(_nf, LITE_FRAMES); f++) { array_push(_fr, _sa.frames[f]); }
            array_push(_anims, { frames : _fr, rate : _sa.rate, mode : _sa.mode });
        }
        _ac.anims = _anims;
        array_push(_acts, _ac);
    }
    _q.actors = _acts;
    if (array_length(_p.actors) > LITE_ACTORS && !_p.tiles_on) { array_push(_warn, "ADAM Lite puts " + string(LITE_ACTORS) + " actors on the disk (the 8 hardware sprites, the rest BOBs) - ADAM Pro takes up to " + string(ACT_MAX_ALL) + "."); }
    // rules that name an actor left off the disk are left out too
    if (array_length(_p.actors) > _keepn)
    {
        var _rl = [];
        var _dropped = 0;
        for (var r = 0; r < array_length(_p.rules); r++)
        {
            var _ru = _p.rules[r];
            var _far = (_ru.a >= _keepn || _ru.b >= _keepn || (_ru.target >= _keepn && do_target_is_actor(_ru.act)));
            for (var mq = 0; mq < array_length(_ru.more); mq++)
            {
                if (_ru.more[mq].target >= _keepn && do_target_is_actor(_ru.more[mq].act)) { _far = true; }
            }
            if (_far) { _dropped += 1; }
            else { array_push(_rl, _ru); }
        }
        _q.rules = _rl;
        if (_dropped > 0) { array_push(_warn, string(_dropped) + " rules use actors that are not on the disk, so they are left out."); }
    }
    if (_cut_frames) { array_push(_warn, "Animations play their first " + string(LITE_FRAMES) + " frames in ADAM Lite - ADAM Pro plays up to " + string(ANIM_FRAMES) + "."); }
    // sounds after the 8th are silent (sfx_used_on_disk leaves them off)
    if (array_length(_p.sfx) > LITE_SOUNDS)
    {
        var _far_snd = false;
        for (var su = 0; su < array_length(_p.sfx); su++)
        {
            if (su >= LITE_SOUNDS && sfx_ref_count(_p, su, true) > 0) { _far_snd = true; }
        }
        if (_far_snd) { array_push(_warn, "ADAM Lite plays sounds 1 to " + string(LITE_SOUNDS) + " - rules and tiles that play a later sound are silent. ADAM Pro has up to " + string(SFX_MAX) + " sounds."); }
    }

    // sprites bigger than 32 x 32 are cut to 32 x 32
    var _cut_spr = false;
    var _sprs = [];
    for (var s = 0; s < array_length(_p.sprites); s++)
    {
        var _sp = _p.sprites[s];
        if (_sp.w <= LITE_SPR_W && _sp.h <= LITE_SPR_H)
        {
            array_push(_sprs, _sp);
            continue;
        }
        _cut_spr = true;
        var _nw = min(_sp.w, LITE_SPR_W);
        var _nh = min(_sp.h, LITE_SPR_H);
        var _ns = {};
        var _sn = variable_struct_get_names(_sp);
        for (var n = 0; n < array_length(_sn); n++) { _ns[$ _sn[n]] = _sp[$ _sn[n]]; }
        var _px = array_create(_nw * _nh, 0);
        for (var py = 0; py < _nh; py++)
        {
            for (var px = 0; px < _nw; px++) { _px[py * _nw + px] = _sp.px[py * _sp.w + px]; }
        }
        _ns.w = _nw;
        _ns.h = _nh;
        _ns.px = _px;
        array_push(_sprs, _ns);
    }
    _q.sprites = _sprs;
    if (_cut_spr) { array_push(_warn, "Sprites and BOBs are up to " + string(LITE_SPR_W) + " x " + string(LITE_SPR_H) + " in ADAM Lite, so bigger ones are cut to that size - ADAM Pro draws them up to 64 x 64."); }

    // Keep the HUD in Lite; custom fonts use ADAM on the disk.
    // Copy only the UI struct so the original project keeps its custom font.
    if (_p.ui.font_style == 5)
    {
        var _uq = {};
        var _un = variable_struct_get_names(_p.ui);
        for (var uk = 0; uk < array_length(_un); uk++) { _uq[$ _un[uk]] = _p.ui[$ _un[uk]]; }
        _uq.font_style = 0;
        _q.ui = _uq;
        array_push(_warn, "Custom fonts are part of ADAM Pro - the game uses the ADAM font and keeps your custom HUD.");
    }

    // tile world or shoot 'em up map: 96 tile types, a map up to 256 x 256 tiles
    if (_p.tiles_on || _p.shmup_map)
    {
        var _nt = min(LITE_TILES, array_length(_p.tiles));
        var _mw = min(_p.map_w, LITE_MAP_W);
        var _mh = min(_p.map_h, LITE_MAP_H);
        var _cut_t = (array_length(_p.tiles) > LITE_TILES);
        if (_cut_t || _mh < _p.map_h || _mw < _p.map_w)
        {
            var _tl = [];
            for (var t = 0; t < _nt; t++)
            {
                var _tt = _p.tiles[t];
                if (_tt.becomes >= _nt)
                {
                    var _tc = {};
                    var _tn = variable_struct_get_names(_tt);
                    for (var tk = 0; tk < array_length(_tn); tk++) { _tc[$ _tn[tk]] = _tt[$ _tn[tk]]; }
                    _tc.becomes = 0;
                    _tt = _tc;
                }
                array_push(_tl, _tt);
            }
            var _map = array_create(_mw * _mh, 0);
            for (var mr = 0; mr < _mh; mr++)
            {
                for (var mc = 0; mc < _mw; mc++)
                {
                    var _v = _p.map[mr * _p.map_w + mc];
                    if (_v < _nt) { _map[mr * _mw + mc] = _v; }
                }
            }
            _q.tiles = _tl;
            _q.map = _map;
            _q.map_w = _mw;
            _q.map_h = _mh;
            if (_cut_t) { array_push(_warn, "A tile set has " + string(LITE_TILES) + " tile types in ADAM Lite, so map cells using the others are air - ADAM Pro has " + string(TILE_MAX) + "."); }
            if (_mh < _p.map_h || _mw < _p.map_w) { array_push(_warn, "Tile maps are up to " + string(LITE_MAP_W) + " x " + string(LITE_MAP_H) + " tiles in ADAM Lite, so the map is cut to that - ADAM Pro goes to " + string(MAP_MAX) + " x " + string(MAP_MAX) + "."); }
        }
    }
    return _q;
}
