/// ADAM - project data model, example game, save/load, undo, settings

#macro SPR_COUNT 128           // sprite bank slots in every project (ADAM Lite and Pro)
#macro SPR_W 16
#macro SPR_H 24
#macro BD_W 320
#macro BD_H 256
#macro ACT_XMAX 304
#macro ACT_YMAX 232
#macro SPR_BIG_W 64             // ADAM Pro: sprites up to 64 x 64 (drawn as BOBs)
#macro SPR_BIG_H 64
#macro PAL_MAX 128

function project_defs_init()
{
    global.ROLE_NAMES = ["Player (joystick)", "Bouncer (diagonal)", "Patrol left-right", "Patrol up-down", "Chaser (follows player)", "Still (does not move)", "Platform player (walks + jumps)", "Hopper (jumps left and right)", "Faller (drops onto the ground)"];
    global.WHEN_NAMES = ["Actor touches actor", "Fire button is pressed", "Every few seconds", "Score reaches", "Lives run out", "The game starts", "Actor jumps", "A level starts"];
    global.DO_NAMES   = ["Add to score", "Lose a life", "Play a sound", "Flash the screen", "Send actor back to start",
                         "Move actor to a random spot", "Hide actor", "Show actor", "Change background colour",
                         "Game over", "You win!", "Speed up actor", "Slow down actor", "Add a life", "Move actor to another actor",
                         "Show actor for a moment", "Make actor safe for a while", "Count towards the level goal",
                         "Play music", "Stop music"];
    global.WAVE_NAMES = ["Triangle (soft)", "Sawtooth (buzzy)", "Square (classic)", "Noise (crunchy)"];
    global.SFX_PRESET_NAMES = ["Coin", "Laser", "Explosion", "Jump", "Hit", "Power up", "Lose", "Blip"];
    global.TEMPLATE_NAMES = ["Player touches enemy: lose a life", "Player gets pickup: score",
                             "Score target: you win", "Out of lives: game over", "Every 10 s: enemy speeds up",
                             "Fire button: play a sound"];
    global.DEPTH_NAMES = ["2 colours", "4 colours", "8 colours", "16 colours", "32 colours", "64 colours", "128 colours"];
}

/// The starting palette: 16 hand-picked colours, then a hue wheel for AGA
function palette_default()
{
    var _p = [
        0x000000, 0xffffff, 0x0055aa, 0xff8800, 0x1a2a4a, 0x33598c, 0x5c9cd6, 0xa8d8ff,
        0x1e4a1e, 0x3f8a2e, 0x7acc44, 0x6a4426, 0xb07a45, 0xdd3322, 0xffdd33, 0x8a8a8a
    ];
    for (var i = 16; i < PAL_MAX; i++)
    {
        var _k = i - 16;
        var _hue = (_k mod 16) * 16;
        var _row = _k div 16;
        var _sat = 255;
        var _val = 255;
        if (_row == 0) { _sat = 255; _val = 255; }
        if (_row == 1) { _sat = 170; _val = 255; }
        if (_row == 2) { _sat = 90;  _val = 255; }
        if (_row == 3) { _sat = 255; _val = 190; }
        if (_row == 4) { _sat = 255; _val = 120; }
        if (_row == 5) { _sat = 140; _val = 140; }
        if (_row == 6) { _sat = 0;   _val = (_k mod 16) * 17; }
        var _c = make_colour_hsv(_hue, _sat, _val);
        array_push(_p, rgb_make(colour_get_red(_c), colour_get_green(_c), colour_get_blue(_c)));
    }
    return _p;
}

/// Sprite bank slots: 64 in ADAM Lite, 128 in ADAM Pro (lim_bank)
function spr_bank_size()
{
    return lim_bank();
}

function sprite_new(_name)
{
    return {
        name : _name,
        w : SPR_W,
        h : SPR_H,
        px : array_create(SPR_W * SPR_H, 0),
        cols : [0xffdd33, 0xdd3322, 0xffffff]
    };
}

/// Sprite sizes: 16 x 24 (a hardware sprite), and in ADAM Pro 16-64 wide in
/// steps of 16 and 16, 24, 32, 48 or 64 high (bigger than 16 x 24 = a BOB)
function spr_size_ok(_w, _h)
{
    if (!is_real(_w) || !is_real(_h)) { return false; }
    if (_w != 16 && _w != 32 && _w != 48 && _w != 64) { return false; }
    if (_h != 16 && _h != 24 && _h != 32 && _h != 48 && _h != 64) { return false; }
    return true;
}

/// Pixel (0 = clear, 1-3) of sprite struct _s; 0 outside it
function spr_get(_s, _px, _py)
{
    if (_px < 0 || _py < 0 || _px >= _s.w || _py >= _s.h) { return 0; }
    return _s.px[_py * _s.w + _px];
}

/// True when the sprite is too big for a hardware sprite (so it can only be a BOB)
function spr_is_big(_s)
{
    return _s.w > SPR_W || _s.h > SPR_H;
}

function actor_new(_name)
{
    return {
        name : _name,
        sprite : 0,
        role : 5,
        speed : 2,
        x : 152,
        y : 116,
        visible : true,
        start_left : false,
        start_up : false,
        anim_sprite : -1,       // two-frame animation (and a hopper's crouch frame)
        anim_rate : 8,
        anim_moving : false,
        anims : anims_new(),    // Idle, Walk, Jump, Fall (Animate page)
        anim_flip : false,      // frames turn round when it moves left
        anim_dirs : false,      // (older files; the 8 directions are on when they have frames)
        from_level : 1,
        faster_every : 0,
        bob : false             // ADAM Pro: drawn by the blitter instead of a hardware sprite
    };
}

// ---------------------------------------------------------------------------
// Animations (Animate page, Lite and Pro). Each actor has 4: Idle (standing
// still), Walk (moving), Jump and Fall (in the air - platform players,
// hoppers and fallers). Each is up to ANIM_FRAMES sprite-bank slots, a speed
// in 50ths of a second per frame and a mode. Empty ones borrow from the
// others when the disk is built (anim_plan, same as adf_reference.py).
// ---------------------------------------------------------------------------
#macro ANIM_COUNT 21            // stored per actor: 0 Idle, 1 Walk, 2 Jump, 3 Fall, 4..11 N NE E SE S SW W NW,
                                // 12 Fire, 13..20 Fire + N .. NW (the player holding fire)
#macro ANIM_BASIC 4             // Idle, Walk, Jump, Fall
#macro ANIM_DIR0 4              // first of the 8 directions
#macro ANIM_FIRE0 12            // Fire with no direction; 13..20 = Fire + the 8 directions
#macro ANIM_FRAMES 8

function anim_new()
{
    return { frames : [], rate : 8, mode : 0 };      // mode 0 loop, 1 once, 2 ping-pong
}

function anims_new()
{
    var _a = [];
    for (var i = 0; i < ANIM_COUNT; i++) { array_push(_a, anim_new()); }
    return _a;
}

/// Makes a loaded anims array safe: 12 entries (older files have 4), up to 8 frames each, values in range
function anims_from_loaded(_raw)
{
    var _out = anims_new();
    if (!is_array(_raw)) { return _out; }
    for (var i = 0; i < min(ANIM_COUNT, array_length(_raw)); i++)
    {
        var _e = _raw[i];
        if (!is_struct(_e)) { continue; }
        var _fr = _e[$ "frames"];
        if (is_array(_fr))
        {
            for (var k = 0; k < min(ANIM_FRAMES, array_length(_fr)); k++)
            {
                if (is_numeric(_fr[k])) { array_push(_out[i].frames, clamp(floor(_fr[k]), 0, SPR_COUNT - 1)); }
            }
        }
        var _r = _e[$ "rate"];
        if (is_numeric(_r)) { _out[i].rate = clamp(floor(_r), 2, 30); }
        var _m = _e[$ "mode"];
        if (is_numeric(_m)) { _out[i].mode = clamp(floor(_m), 0, 2); }
    }
    return _out;
}

/// True when the actor has any Animate-page frames (they replace the two-frame animation).
/// The 8 directions only count while 8 directions is switched on.
function anims_used(_ac)
{
    var _n = ANIM_FIRE0;
    for (var i = 0; i < _n; i++)
    {
        if (array_length(_ac.anims[i].frames) > 0) { return true; }
    }
    return anims_fire_used(_ac);
}

/// True when the joystick directions have frames: then the 8 directions are used
/// instead of Walk (empty ones borrow from the others and from Walk)
function anims_dirs_on(_ac)
{
    for (var i = ANIM_DIR0; i < ANIM_DIR0 + 8; i++)
    {
        if (array_length(_ac.anims[i].frames) > 0) { return true; }
    }
    return false;
}

/// True when the actor has Fire animations (played while the player holds fire).
/// ADAM Lite has no With Fire joystick, so they are left out there.
function anims_fire_used(_ac)
{
    if (!lim_fire()) { return false; }
    for (var i = ANIM_FIRE0; i < ANIM_COUNT; i++)
    {
        if (array_length(_ac.anims[i].frames) > 0) { return true; }
    }
    return false;
}

/// Starts the Animate page from the actor's two-frame animation, if it has one.
/// Either way the two-frame animation is switched off (a hopper keeps its
/// crouch frame), so clearing every frame here really leaves one frame.
function anims_seed_from_legacy(_ac)
{
    if (_ac.role == 7) { return; }
    if (!anims_used(_ac) && _ac.anim_sprite >= 0)
    {
        var _r = clamp(_ac.anim_rate, 2, 30);
        _ac.anims[1].frames = [_ac.sprite, _ac.anim_sprite];
        _ac.anims[1].rate = _r;
        if (_ac.anim_moving) { _ac.anims[0].frames = [_ac.sprite]; }
        else { _ac.anims[0].frames = [_ac.sprite, _ac.anim_sprite]; }
        _ac.anims[0].rate = _r;
    }
    _ac.anim_sprite = -1;
}

/// The directions tried, in order, for each of the 8 (N NE E SE S SW W NW) when it
/// has no frames: [entry, turn] pairs - turn 1 = turned round (only with anim_flip),
/// 2 = turned round when anim_flip is on; entry 1 is Walk. Same as DIR_CHAINS in
/// tools/reference/adf_reference.py.
function anim_dir_chains()
{
    return [
        [[4, 0], [1, 0]],
        [[5, 0], [11, 1], [6, 0], [10, 1], [1, 0]],
        [[6, 0], [10, 1], [1, 0]],
        [[7, 0], [9, 1], [6, 0], [10, 1], [1, 0]],
        [[8, 0], [1, 0]],
        [[9, 0], [7, 1], [10, 0], [6, 1], [1, 2]],
        [[10, 0], [6, 1], [1, 2]],
        [[11, 0], [5, 1], [10, 0], [6, 1], [1, 2]]
    ];
}

/// The 8 directions resolved from entries _base.._base+7 of _e (undefined = empty)
/// with anim_dir_chains, where entry 1 means _walk. Empty ones end up as east (or west).
function anim_resolve_dirs(_e, _base, _walk, _flip)
{
    var _chains = anim_dir_chains();
    var _dirs = array_create(8, undefined);
    for (var d = 0; d < 8; d++)
    {
        var _ch = _chains[d];
        for (var c = 0; c < array_length(_ch); c++)
        {
            var _k = _ch[c][0];
            var _t = _ch[c][1];
            if (_t == 1 && !_flip) { continue; }
            var _src = _walk;
            if (_k != 1) { _src = _e[_k - ANIM_DIR0 + _base]; }
            if (!is_undefined(_src))
            {
                var _fl = false;
                if (_t == 1) { _fl = true; }
                if (_t == 2 && _flip) { _fl = true; }
                _dirs[d] = { frames : _src.frames, rate : _src.rate, mode : _src.mode, flip : _fl };
                break;
            }
        }
    }
    for (var d2 = 0; d2 < 8; d2++)
    {
        if (is_undefined(_dirs[d2]))
        {
            if (!is_undefined(_dirs[2])) { _dirs[d2] = _dirs[2]; }
            else if (!is_undefined(_dirs[6])) { _dirs[d2] = _dirs[6]; }
        }
    }
    return _dirs;
}

/// What the disk plays: undefined for one frame, else 4 (12 with 8 directions,
/// 21 with Fire animations) x { frames, rate, mode, flip } with empty animations
/// filled in from the others (flip = its frames are turned round; mode 3 = stand
/// facing the last direction). Must match anim_plan in tools/reference/adf_reference.py.
function anim_plan(_ac)
{
    if (anims_used(_ac))
    {
        var _e = [];
        for (var i = 0; i < ANIM_COUNT; i++)
        {
            var _src = _ac.anims[i];
            if (array_length(_src.frames) > 0)
            {
                var _pf = _src.frames;
                if (array_length(_pf) > lim_frames())
                {
                    // ADAM Lite plays the first 4 frames (as lite_trim writes them)
                    _pf = [];
                    for (var pf = 0; pf < lim_frames(); pf++) { array_push(_pf, _src.frames[pf]); }
                }
                array_push(_e, { frames : _pf, rate : clamp(_src.rate, 2, 30), mode : clamp(_src.mode, 0, 2), flip : false });
            }
            else { array_push(_e, undefined); }
        }
        var _idle = _e[0];
        var _walk = _e[1];
        var _jump = _e[2];
        var _fall = _e[3];
        var _dirs = undefined;
        var _one = { frames : [_ac.sprite], rate : 8, mode : 0, flip : false };
        if (anims_dirs_on(_ac))
        {
            var _w0 = _walk;
            if (is_undefined(_w0)) { _w0 = _idle; }
            _dirs = anim_resolve_dirs(_e, ANIM_DIR0, _w0, _ac.anim_flip);
            for (var d = 0; d < 8; d++)
            {
                if (is_undefined(_dirs[d])) { _dirs[d] = _one; }
            }
            if (is_undefined(_idle)) { _idle = { frames : [_ac.sprite], rate : 8, mode : 3, flip : false }; }
            if (is_undefined(_walk)) { _walk = _dirs[2]; }
        }
        else
        {
            if (is_undefined(_idle))
            {
                if (!is_undefined(_walk)) { _idle = _walk; }
                else { _idle = _one; }
            }
            if (is_undefined(_walk)) { _walk = _idle; }
        }
        if (is_undefined(_jump)) { _jump = _walk; }
        if (is_undefined(_fall)) { _fall = _jump; }
        var _out = [_idle, _walk, _jump, _fall];
        if (anims_fire_used(_ac))
        {
            if (is_undefined(_dirs)) { _dirs = array_create(8, _walk); }     // not used without 8 directions
            var _fstand = _e[ANIM_FIRE0];
            var _fd = anim_resolve_dirs(_e, ANIM_FIRE0 + 1, _fstand, _ac.anim_flip);
            if (is_undefined(_fstand))
            {
                if (!is_undefined(_fd[2])) { _fstand = _fd[2]; }
                else if (!is_undefined(_fd[6])) { _fstand = _fd[6]; }
                else { _fstand = _idle; }
            }
            for (var d3 = 0; d3 < 8; d3++)
            {
                if (is_undefined(_fd[d3])) { _fd[d3] = _fstand; }
            }
            for (var d4 = 0; d4 < 8; d4++) { array_push(_out, _dirs[d4]); }
            array_push(_out, _fstand);
            for (var d5 = 0; d5 < 8; d5++) { array_push(_out, _fd[d5]); }
            return _out;
        }
        if (!is_undefined(_dirs))
        {
            for (var d6 = 0; d6 < 8; d6++) { array_push(_out, _dirs[d6]); }
        }
        return _out;
    }
    if (_ac.anim_sprite >= 0 && _ac.role != 7)
    {
        var _rt = clamp(_ac.anim_rate, 2, 30);
        var _both = { frames : [_ac.sprite, _ac.anim_sprite], rate : _rt, mode : 0, flip : false };
        var _lidle = _both;
        if (_ac.anim_moving) { _lidle = { frames : [_ac.sprite], rate : _rt, mode : 0, flip : false }; }
        return [_lidle, _both, _both, _both];
    }
    return undefined;
}

/// Frame number 0..n-1 of an animation _ticks 50ths of a second after it started (as engine.s does)
function anim_frame_at(_e, _ticks)
{
    var _n = array_length(_e.frames);
    if (_n <= 1) { return 0; }
    var _steps = floor(_ticks / max(2, _e.rate));
    if (_e.mode == 1) { return min(_steps, _n - 1); }
    if (_e.mode == 2)
    {
        var _per = 2 * _n - 2;
        var _m = _steps mod _per;
        if (_m >= _n) { return _per - _m; }
        return _m;
    }
    return _steps mod _n;
}

/// The sprite an actor shows on the Actors page stage right now (its idle animation)
function actor_preview_sprite(_ac)
{
    var _plan = anim_plan(_ac);
    if (is_undefined(_plan)) { return _ac.sprite; }
    var _e = _plan[0];
    if (_e.mode == 3) { _e = _plan[ANIM_DIR0 + 2]; }      // stands facing east
    return _e.frames[anim_frame_at(_e, current_time div 20)];
}

function rule_new()
{
    return { when : 0, a : 0, b : 1, n : 1, act : 0, target : 0, value : 10, group : -1 };
}

function sfx_new(_name)
{
    return {
        name : _name, kind : 0,
        wave : 2, pitch : 60, sweep : 0, len : 10, atk : 0, dec : 8, sus : 0, rel : 6,
        smp : "", smp_rate : 0, smp_len : 0, smp_file : "",
        rate : 11025, bits : 8, gain : 100, trim_a : 0, trim_b : 1000
    };
}

function sfx_apply_preset(_s, _p)
{
    var _t = [
        [2, 60, 6, 8, 0, 6, 0, 4],
        [1, 120, -8, 12, 0, 8, 0, 6],
        [3, 40, -1, 25, 0, 10, 0, 9],
        [0, 30, 4, 14, 0, 7, 4, 5],
        [3, 14, 0, 6, 0, 5, 0, 3],
        [2, 40, 3, 30, 2, 6, 8, 6],
        [0, 50, -2, 30, 0, 9, 6, 8],
        [2, 90, 0, 3, 0, 3, 0, 2]
    ];
    var _v = _t[clamp(_p, 0, 7)];
    _s.wave = _v[0];
    _s.pitch = _v[1];
    _s.sweep = _v[2];
    _s.len = _v[3];
    _s.atk = _v[4];
    _s.dec = _v[5];
    _s.sus = _v[6];
    _s.rel = _v[7];
}

function project_new()
{
    var _p = {
        version : 1,
        name : "My Amiga Game",
        machine : last_machine,
        depth : 4,
        pal : palette_default(),
        pixels : array_create(BD_W * BD_H, 0),
        sprites : [],
        actors : [],
        rules : [],
        groups : [],
        sfx : [],
        lives : 3,
        show_score : true,
        show_lives : true,
        hud_row : 0,
        hud_colour : 1,
        msg_colour : 14,
        over_text : "GAME OVER - PRESS FIRE",
        win_text : "YOU WIN! - PRESS FIRE",
        solid : array_create(PAL_MAX, 0),
        levels_on : false,
        levels : [],
        terrain_cols : [10, 9, 11, 12],
        goal_on : false,
        goal : 20,
        goal_label : "GEMS",
        title_on : false,
        title1 : "MY AMIGA GAME",
        title2 : "PRESS FIRE TO START",
        lev_text : "LEVEL",
        sky_on : false,
        sky_top : 0x102060,
        sky_mid : 0x4080c0,
        sky_bot : 0xffa040,
        sky_mid_y : 128,
        songs : [],                              // Phase 2 contract: 0..4 songs (Music page)
        level_song : array_create(LEVEL_MAX, -1), // Phase 2 contract: song per level, -1 = none
        tiles_on : false,                        // play on the tile map (Tiles page) instead of the backdrop
        tile_size : 16,                          // 8, 16, 32 or 64 pixels: every tile in the game
        tiles : tiles_default(16),               // up to TILE_MAX tiles; 0 = air
        map_w : 64,
        map_h : 32,
        map : map_starter(64, 32),               // map_w x map_h tile numbers
        tile_dig : true                          // the player digs (fire + direction) and places (fire)
    };
    for (var i = 0; i < 8; i++)
    {
        var _s = sfx_new(global.SFX_PRESET_NAMES[i]);
        sfx_apply_preset(_s, i);
        array_push(_p.sfx, _s);
    }
    for (var k = 0; k < SPR_COUNT; k++)
    {
        array_push(_p.sprites, sprite_new("Sprite " + string(k + 1)));
    }
    return _p;
}

/// Copies fields that exist in _src over the defaults in _dst
function struct_overlay(_dst, _src)
{
    if (!is_struct(_src)) { return _dst; }
    var _names = variable_struct_get_names(_src);
    for (var i = 0; i < array_length(_names); i++)
    {
        var _k = _names[i];
        _dst[$ _k] = _src[$ _k];
    }
    return _dst;
}

function project_from_loaded(_raw)
{
    var _p = project_new();
    if (!is_struct(_raw)) { return _p; }
    project_unpack(_raw);
    var _sprites = _p.sprites;
    var _sfx = _p.sfx;
    var _pal = _p.pal;
    struct_overlay(_p, _raw);
    _p.machine = machine_get(_p.machine).id;
    _p.depth = clamp(floor(_p.depth), 1, 7);
    if (!is_array(_p.pixels) || array_length(_p.pixels) != BD_W * BD_H) { _p.pixels = array_create(BD_W * BD_H, 0); }
    if (!is_array(_p.pal)) { _p.pal = _pal; }
    if (!is_array(_p.solid) || array_length(_p.solid) != PAL_MAX) { _p.solid = array_create(PAL_MAX, 0); }
    if (array_length(_p.pal) < PAL_MAX)
    {
        for (var c = array_length(_p.pal); c < PAL_MAX; c++) { array_push(_p.pal, _pal[c]); }
    }

    var _ls = _raw[$ "sprites"];
    for (var i = 0; i < SPR_COUNT; i++)
    {
        var _s = sprite_new("Sprite " + string(i + 1));
        if (is_array(_ls) && i < array_length(_ls)) { struct_overlay(_s, _ls[i]); }
        if (!spr_size_ok(_s.w, _s.h)) { _s.w = SPR_W; _s.h = SPR_H; }
        if (!is_array(_s.px) || array_length(_s.px) != _s.w * _s.h) { _s.px = array_create(_s.w * _s.h, 0); }
        if (!is_array(_s.cols) || array_length(_s.cols) != 3) { _s.cols = [0xffdd33, 0xdd3322, 0xffffff]; }
        _sprites[i] = _s;
    }
    _p.sprites = _sprites;

    var _lf = _raw[$ "sfx"];
    for (var j = 0; j < 8; j++)
    {
        var _f = _sfx[j];
        if (is_array(_lf) && j < array_length(_lf)) { struct_overlay(_f, _lf[j]); }
    }
    _p.sfx = _sfx;

    var _acts = [];
    var _la = _raw[$ "actors"];
    if (is_array(_la))
    {
        // up to 32 (ADAM Pro, with BOBs); ADAM Lite puts the first 8 on the disk
        for (var k = 0; k < min(ACT_MAX_ALL, array_length(_la)); k++)
        {
            var _lact = struct_overlay(actor_new("Actor"), _la[k]);
            _lact.anims = anims_from_loaded(_lact.anims);
            if (!is_bool(_lact.anim_dirs))
            {
                var _dv = false;
                if (is_numeric(_lact.anim_dirs)) { _dv = (_lact.anim_dirs != 0); }
                _lact.anim_dirs = _dv;
            }
            if (!is_bool(_lact.anim_flip))
            {
                var _fv = false;
                if (is_numeric(_lact.anim_flip)) { _fv = (_lact.anim_flip != 0); }
                _lact.anim_flip = _fv;
            }
            if (!is_bool(_lact.bob))
            {
                var _bv = false;
                if (is_numeric(_lact.bob)) { _bv = (_lact.bob != 0); }
                _lact.bob = _bv;
            }
            array_push(_acts, _lact);
        }
    }
    _p.actors = _acts;

    var _rules = [];
    var _lr = _raw[$ "rules"];
    if (is_array(_lr))
    {
        for (var m = 0; m < min(100, array_length(_lr)); m++)
        {
            array_push(_rules, struct_overlay(rule_new(), _lr[m]));
        }
    }
    _p.rules = _rules;

    var _grs = [];
    var _lg = _raw[$ "groups"];
    if (is_array(_lg))
    {
        for (var gi = 0; gi < array_length(_lg); gi++) { array_push(_grs, struct_overlay(group_new("Group"), _lg[gi])); }
    }
    _p.groups = _grs;
    for (var ri = 0; ri < array_length(_p.rules); ri++)
    {
        if (_p.rules[ri].group >= array_length(_grs) || _p.rules[ri].group < -1) { _p.rules[ri].group = -1; }
    }

    var _lv = [];
    if (is_array(_p.levels))
    {
        for (var l = 0; l < min(LEVEL_MAX, array_length(_p.levels)); l++)
        {
            var _src = _p.levels[l];
            var _nl = level_new(1000 + l * 37);
            struct_overlay(_nl, _src);
            if (!is_array(_nl.heights) || array_length(_nl.heights) != BD_W) { _nl.heights = terrain_generate(_nl.seed, _nl.hilly, _nl.base); }
            array_push(_lv, _nl);
        }
    }
    _p.levels = _lv;
    if (!is_array(_p.terrain_cols) || array_length(_p.terrain_cols) != 4) { _p.terrain_cols = [10, 9, 11, 12]; }

    // Phase 2 contract: songs and the song for each level (older files have none)
    var _songs = [];
    var _lsg = _raw[$ "songs"];
    if (is_array(_lsg))
    {
        for (var si = 0; si < min(MUS_SONG_MAX, array_length(_lsg)); si++) { array_push(_songs, song_from_loaded(_lsg[si])); }
    }
    _p.songs = _songs;
    var _lsv = array_create(LEVEL_MAX, -1);
    var _lls = _raw[$ "level_song"];
    if (is_array(_lls))
    {
        for (var li = 0; li < min(LEVEL_MAX, array_length(_lls)); li++)
        {
            var _v = _lls[li];
            if (is_numeric(_v) && _v >= 0 && _v < array_length(_songs)) { _lsv[li] = floor(_v); }
        }
    }
    _p.level_song = _lsv;
    tiles_fix(_p);                       // tile world (older files have none)
    return _p;
}

function file_write_text(_path, _text)
{
    var _b = buffer_create(string_byte_length(_text) + 1, buffer_grow, 1);
    buffer_write(_b, buffer_text, _text);
    buffer_save_ext(_b, _path, 0, buffer_tell(_b));
    buffer_delete(_b);
    return true;
}

function file_read_text(_path)
{
    if (!file_exists(_path)) { return ""; }
    var _b = buffer_load(_path);
    if (_b == -1) { return ""; }
    buffer_seek(_b, buffer_seek_start, 0);
    var _s = "";
    if (buffer_get_size(_b) > 0) { _s = buffer_read(_b, buffer_text); }
    buffer_delete(_b);
    return _s;
}

// ---------------------------------------------------------------------------
// Packed arrays. The backdrop (81920 pixels), sprite pixels and level heights
// are written to .adam files and undo snapshots as zlib-compressed bytes in
// base64 ("pixels_z", "pxz", "heights_z") instead of long JSON number lists.
// In memory they stay plain arrays; project_from_loaded unpacks them, and
// files without the packed keys (older saves, the examples) load as before.
// ---------------------------------------------------------------------------

/// Array of whole numbers 0-255 -> base64 of the zlib-compressed bytes
function pack_u8(_arr)
{
    var _n = array_length(_arr);
    if (_n == 0) { return ""; }
    var _b = buffer_create(_n, buffer_fixed, 1);
    for (var i = 0; i < _n; i++) { buffer_write(_b, buffer_u8, clamp(_arr[i], 0, 255)); }
    var _z = buffer_compress(_b, 0, _n);
    buffer_delete(_b);
    var _s = buffer_base64_encode(_z, 0, buffer_get_size(_z));
    buffer_delete(_z);
    return _s;
}

/// The reverse of pack_u8. Returns an array of exactly _n entries, or
/// undefined if the text is damaged or holds a different number of bytes.
function unpack_u8(_str, _n)
{
    if (!is_string(_str) || _str == "" || _n <= 0) { return undefined; }
    var _z = buffer_base64_decode(_str);
    if (!buffer_exists(_z)) { return undefined; }
    var _b = buffer_decompress(_z);
    buffer_delete(_z);
    if (!buffer_exists(_b)) { return undefined; }
    if (buffer_get_size(_b) != _n)
    {
        buffer_delete(_b);
        return undefined;
    }
    var _arr = array_create(_n, 0);
    buffer_seek(_b, buffer_seek_start, 0);
    for (var i = 0; i < _n; i++) { _arr[i] = buffer_read(_b, buffer_u8); }
    buffer_delete(_b);
    return _arr;
}

/// Array of whole numbers 0-65535 -> base64 of the zlib-compressed 16-bit words
/// (a map with more than 256 tile types)
function pack_u16(_arr)
{
    var _n = array_length(_arr);
    if (_n == 0) { return ""; }
    var _b = buffer_create(_n * 2, buffer_fixed, 1);
    for (var i = 0; i < _n; i++) { buffer_write(_b, buffer_u16, clamp(_arr[i], 0, 65535)); }
    var _z = buffer_compress(_b, 0, _n * 2);
    buffer_delete(_b);
    var _s = buffer_base64_encode(_z, 0, buffer_get_size(_z));
    buffer_delete(_z);
    return _s;
}

/// The reverse of pack_u16: an array of exactly _n entries, or undefined
function unpack_u16(_str, _n)
{
    if (!is_string(_str) || _str == "" || _n <= 0) { return undefined; }
    var _z = buffer_base64_decode(_str);
    if (!buffer_exists(_z)) { return undefined; }
    var _b = buffer_decompress(_z);
    buffer_delete(_z);
    if (!buffer_exists(_b)) { return undefined; }
    if (buffer_get_size(_b) != _n * 2)
    {
        buffer_delete(_b);
        return undefined;
    }
    var _arr = array_create(_n, 0);
    buffer_seek(_b, buffer_seek_start, 0);
    for (var i = 0; i < _n; i++) { _arr[i] = buffer_read(_b, buffer_u16); }
    buffer_delete(_b);
    return _arr;
}

/// Shallow copy of a project (or part of one, as in an undo snapshot) with
/// the big arrays packed. _src itself is not changed.
function project_pack(_src)
{
    var _out = {};
    var _names = variable_struct_get_names(_src);
    for (var i = 0; i < array_length(_names); i++) { _out[$ _names[i]] = _src[$ _names[i]]; }

    if (is_array(_src[$ "pixels"]))
    {
        variable_struct_remove(_out, "pixels");
        _out.pixels_z = pack_u8(_src.pixels);
    }

    var _ls = _src[$ "sprites"];
    if (is_array(_ls))
    {
        var _ns = [];
        for (var k = 0; k < array_length(_ls); k++)
        {
            var _s = _ls[k];
            if (is_struct(_s) && is_array(_s[$ "px"]))
            {
                var _c = struct_overlay({}, _s);
                variable_struct_remove(_c, "px");
                _c.pxz = pack_u8(_s.px);
                _s = _c;
            }
            array_push(_ns, _s);
        }
        _out.sprites = _ns;
    }

    if (is_array(_src[$ "map"]))
    {
        variable_struct_remove(_out, "map");
        var _big = false;
        var _lt0 = _src[$ "tiles"];
        if (is_array(_lt0)) { _big = (array_length(_lt0) > 256); }
        if (_big) { _out.map_z16 = pack_u16(_src.map); }      // more than 256 tile types: 16-bit cells
        else { _out.map_z = pack_u8(_src.map); }
    }
    var _lt = _src[$ "tiles"];
    if (is_array(_lt))
    {
        var _ntl = [];
        for (var t = 0; t < array_length(_lt); t++)
        {
            var _tt = _lt[t];
            if (is_struct(_tt) && is_array(_tt[$ "px"]))
            {
                var _ct = struct_overlay({}, _tt);
                variable_struct_remove(_ct, "px");
                _ct.pxz = pack_u8(_tt.px);
                _tt = _ct;
            }
            array_push(_ntl, _tt);
        }
        _out.tiles = _ntl;
    }

    var _lv = _src[$ "levels"];
    if (is_array(_lv))
    {
        var _nl = [];
        for (var l = 0; l < array_length(_lv); l++)
        {
            var _v = _lv[l];
            if (is_struct(_v) && is_array(_v[$ "heights"]))
            {
                var _cl = struct_overlay({}, _v);
                variable_struct_remove(_cl, "heights");
                _cl.heights_z = pack_u8(_v.heights);
                _v = _cl;
            }
            array_push(_nl, _v);
        }
        _out.levels = _nl;
    }

    // Phase 2 contract: imported songs' sample bytes and patterns ("data_z", "patterns_z")
    if (is_array(_src[$ "songs"])) { _out.songs = songs_pack(_src.songs); }
    return _out;
}

/// Unpacks a freshly parsed file or snapshot in place (packed keys become
/// plain arrays again). Plain-array data is left alone.
function project_unpack(_raw)
{
    if (!is_struct(_raw)) { return _raw; }

    var _pz = _raw[$ "pixels_z"];
    if (is_string(_pz))
    {
        _raw.pixels = unpack_u8(_pz, BD_W * BD_H);
        variable_struct_remove(_raw, "pixels_z");
    }

    var _ls = _raw[$ "sprites"];
    if (is_array(_ls))
    {
        for (var k = 0; k < array_length(_ls); k++)
        {
            var _s = _ls[k];
            if (is_struct(_s) && is_string(_s[$ "pxz"]))
            {
                var _pw = _s[$ "w"];
                var _ph = _s[$ "h"];
                if (!is_real(_pw) || !is_real(_ph) || !spr_size_ok(_pw, _ph)) { _pw = SPR_W; _ph = SPR_H; }
                _s.px = unpack_u8(_s.pxz, _pw * _ph);
                variable_struct_remove(_s, "pxz");
            }
        }
    }

    var _lv = _raw[$ "levels"];
    if (is_array(_lv))
    {
        for (var l = 0; l < array_length(_lv); l++)
        {
            var _v = _lv[l];
            if (is_struct(_v) && is_string(_v[$ "heights_z"]))
            {
                _v.heights = unpack_u8(_v.heights_z, BD_W);
                variable_struct_remove(_v, "heights_z");
            }
        }
    }

    var _mz = _raw[$ "map_z"];
    if (is_string(_mz))
    {
        var _mw = _raw[$ "map_w"];
        var _mh = _raw[$ "map_h"];
        if (is_numeric(_mw) && is_numeric(_mh)) { _raw.map = unpack_u8(_mz, floor(_mw) * floor(_mh)); }
        variable_struct_remove(_raw, "map_z");
    }
    var _mz16 = _raw[$ "map_z16"];
    if (is_string(_mz16))
    {
        var _mw16 = _raw[$ "map_w"];
        var _mh16 = _raw[$ "map_h"];
        if (is_numeric(_mw16) && is_numeric(_mh16)) { _raw.map = unpack_u16(_mz16, floor(_mw16) * floor(_mh16)); }
        variable_struct_remove(_raw, "map_z16");
    }
    var _tsz = 16;
    if (is_numeric(_raw[$ "tile_size"])) { _tsz = tile_size_ok(_raw.tile_size); }
    var _lt = _raw[$ "tiles"];
    if (is_array(_lt))
    {
        for (var t = 0; t < array_length(_lt); t++)
        {
            var _tt = _lt[t];
            if (is_struct(_tt) && is_string(_tt[$ "pxz"]))
            {
                _tt.px = unpack_u8(_tt.pxz, _tsz * _tsz);
                variable_struct_remove(_tt, "pxz");
            }
        }
    }

    // Phase 2 contract: imported songs
    songs_unpack(_raw[$ "songs"]);
    return _raw;
}

/// The project as .adam text (packed)
function project_to_json(_p)
{
    return json_stringify(project_pack(_p));
}

/// Dev-only (ADAM_DEV_TOOLS): round-trips test patterns and the Gem Hunter
/// example through the packed format and prints sizes, times and PASS/FAIL
/// to the IDE Output window.
function project_pack_selftest()
{
    var _ok = true;
    var _n = BD_W * BD_H;
    for (var t = 0; t < 4; t++)
    {
        var _a = array_create(_n, 0);
        for (var i = 0; i < _n; i++)
        {
            if (t == 1) { _a[i] = i mod 256; }
            if (t == 2) { _a[i] = irandom(255); }
            if (t == 3) { _a[i] = (i div 700) mod 128; }
        }
        var _back = unpack_u8(pack_u8(_a), _n);
        if (!is_array(_back) || !array_equals(_a, _back))
        {
            _ok = false;
            show_debug_message("ADAM pack self-test: pattern " + string(t) + " FAILED");
        }
    }
    if (!is_undefined(unpack_u8("not base64 at all!", _n))) { _ok = false; show_debug_message("ADAM pack self-test: damaged text not rejected"); }
    if (!is_undefined(unpack_u8(pack_u8([1, 2, 3]), _n))) { _ok = false; show_debug_message("ADAM pack self-test: wrong length not rejected"); }

    var _txt = file_read_text(working_directory + "examples/gem_hunter.adam");
    if (_txt != "")
    {
        var _t0 = get_timer();
        var _p = project_from_loaded(json_parse(_txt));
        var _t1 = get_timer();
        var _old = json_stringify(_p);
        var _t2 = get_timer();
        var _new = project_to_json(_p);
        var _t3 = get_timer();
        var _q = project_from_loaded(json_parse(_new));
        var _t4 = get_timer();
        if (!array_equals(_p.pixels, _q.pixels)) { _ok = false; show_debug_message("ADAM pack self-test: Gem Hunter pixels differ"); }
        for (var k = 0; k < SPR_COUNT; k++)
        {
            if (!array_equals(_p.sprites[k].px, _q.sprites[k].px)) { _ok = false; show_debug_message("ADAM pack self-test: sprite " + string(k) + " differs"); }
        }
        // a big (ADAM Pro) sprite keeps its size and pixels through save and load
        var _bs = _p.sprites[SPR_COUNT - 1];
        spr_resize(_bs, 48, 32);
        for (var bq = 0; bq < 48 * 32; bq++) { _bs.px[bq] = (bq * 7) mod 4; }
        var _bq = project_from_loaded(json_parse(project_to_json(_p)));
        var _bb = _bq.sprites[SPR_COUNT - 1];
        if (_bb.w != 48 || _bb.h != 32 || !array_equals(_bs.px, _bb.px)) { _ok = false; show_debug_message("ADAM pack self-test: 48 x 32 sprite differs after save and load"); }
        if (array_length(_p.levels) != array_length(_q.levels)) { _ok = false; show_debug_message("ADAM pack self-test: level count differs"); }
        else
        {
            for (var l = 0; l < array_length(_p.levels); l++)
            {
                if (!array_equals(_p.levels[l].heights, _q.levels[l].heights)) { _ok = false; show_debug_message("ADAM pack self-test: level " + string(l) + " differs"); }
            }
        }
        show_debug_message("ADAM pack: Gem Hunter old file " + string(string_byte_length(_txt)) + " bytes, plain JSON " + string(string_byte_length(_old)) + " bytes, packed " + string(string_byte_length(_new)) + " bytes");
        show_debug_message("ADAM pack: load old " + string((_t1 - _t0) / 1000) + " ms, stringify plain " + string((_t2 - _t1) / 1000) + " ms, pack+stringify " + string((_t3 - _t2) / 1000) + " ms, load packed " + string((_t4 - _t3) / 1000) + " ms");
    }
    if (_ok) { show_debug_message("ADAM pack self-test: PASS"); }
    else { show_debug_message("ADAM pack self-test: FAIL"); }
    return _ok;
}

function project_save_to(_path)
{
    var _t0 = get_timer();
    file_write_text(_path, project_to_json(proj));
    if (ADAM_DEV_TOOLS) { show_debug_message("ADAM save: " + string((get_timer() - _t0) / 1000) + " ms"); }
    proj_path = _path;
    proj_dirty = false;
    settings_save();
    toast("Saved " + filename_name(_path), 0);
}

function project_load_from(_path)
{
    var _txt = file_read_text(_path);
    if (_txt == "")
    {
        toast("Could not read that file", 2);
        return false;
    }
    var _raw = undefined;
    try
    {
        _raw = json_parse(_txt);
    }
    catch (_e)
    {
        toast("That file is not a valid ADAM project", 2);
        return false;
    }
    var _old_machine = proj.machine;
    proj = project_from_loaded(_raw);
    proj_path = _path;
    // the disk follows the project: MyGame.adam builds MyGame.adf next to it
    out_path = filename_change_ext(_path, ".adf");
    settings_save();
    proj_dirty = false;
    project_after_change();
    undo_clear_all();
    toast("Opened " + filename_name(_path), 0);
    if (proj.machine != _old_machine)
    {
        toast("This project is for the " + machine_cur().name + " - machine switched", 0);
    }
    return true;
}

function project_after_change()
{
    mem_mark_stale();
    tiles_mark_all();
    for (var i = 0; i < SPR_COUNT; i++) { spr_dirty[i] = true; }
    bd_dirty = true;
    proj.depth = clamp(proj.depth, 1, machine_cur().max_depth);
    bd_sel = clamp(bd_sel, 0, pal_count() - 1);
    sel_actor = clamp(sel_actor, 0, max(0, array_length(proj.actors) - 1));
    build_listing = [];
}

// ---------------------------------------------------------------------------
// Undo / redo, one history per editor. Each editor only snapshots the parts
// of the project it changes, so undoing on the Logic page never touches the
// backdrop you painted afterwards, and so on.
// ---------------------------------------------------------------------------

/// Project fields each editor owns
function undo_keys(_ws)
{
    switch (_ws)
    {
        case WS_HOME:     return ["name", "lives", "show_score", "show_lives", "hud_row", "hud_colour", "msg_colour", "over_text", "win_text"];
        case WS_BACKDROP: return ["pixels", "pal", "depth", "solid", "sky_on", "sky_top", "sky_mid", "sky_bot", "sky_mid_y", "hud_colour", "msg_colour", "terrain_cols"];
        case WS_LEVELS:   return ["levels_on", "levels", "terrain_cols", "goal_on", "goal", "goal_label", "title_on", "title1", "title2", "lev_text", "level_song"];
        case WS_SPRITES:  return ["sprites"];
        case WS_ACTORS:   return ["actors", "rules"];
        case WS_LOGIC:    return ["rules", "groups"];
        case WS_SOUND:    return ["sfx"];
        case WS_MUSIC:    return ["songs", "level_song"];
        case WS_ANIMATE:  return ["actors"];
        case WS_TILES:    return ["tiles_on", "tile_size", "tiles", "map_w", "map_h", "map", "tile_dig", "actors"];
    }
    return [];
}

/// Snapshot of the current editor's part of the project (or all of it)
function undo_snapshot(_ws, _full)
{
    if (_full) { return { full : true, data : project_to_json(proj) }; }
    var _keys = undo_keys(_ws);
    var _part = {};
    for (var i = 0; i < array_length(_keys); i++) { _part[$ _keys[i]] = proj[$ _keys[i]]; }
    return { full : false, data : project_to_json(_part) };
}

/// Puts a snapshot back
function undo_restore(_snap)
{
    var _t0 = get_timer();
    var _raw = project_unpack(json_parse(_snap.data));
    if (_snap.full)
    {
        proj = project_from_loaded(_raw);
    }
    else
    {
        // run the fields through the loader so they get the same checks as a saved file.
        // A shallow copy is enough: the old proj is replaced, so sharing its arrays is safe.
        var _tmp = struct_overlay({}, proj);
        var _names = variable_struct_get_names(_raw);
        for (var i = 0; i < array_length(_names); i++) { _tmp[$ _names[i]] = _raw[$ _names[i]]; }
        proj = project_from_loaded(_tmp);
    }
    proj_dirty = true;
    project_after_change();
    if (ADAM_DEV_TOOLS) { show_debug_message("ADAM undo restore: " + string((get_timer() - _t0) / 1000) + " ms, snapshot " + string(string_byte_length(_snap.data)) + " bytes"); }
}

function undo_clear_all()
{
    undo_stacks = array_create(WS_COUNT, 0);
    redo_stacks = array_create(WS_COUNT, 0);
    for (var i = 0; i < WS_COUNT; i++)
    {
        undo_stacks[i] = [];
        redo_stacks[i] = [];
    }
    undo_last_tag = "";
}

/// Call BEFORE changing proj. Coalesces rapid edits with the same tag.
function undo_mark(_tag)
{
    undo_mark_ex(_tag, false);
}

/// Like undo_mark, but saves the whole project (for changes that reach into
/// every editor, such as switching machine)
function undo_mark_full(_tag)
{
    undo_mark_ex(_tag, true);
}

function undo_mark_ex(_tag, _full)
{
    proj_dirty = true;
    mem_mark_stale();
    if (_tag == undo_last_tag && current_time - undo_last_time < 1200)
    {
        undo_last_time = current_time;
        return;
    }
    undo_last_tag = _tag;
    undo_last_time = current_time;
    var _w = ws;
    if (!_full && array_length(undo_keys(_w)) == 0) { _full = true; }
    var _t0 = get_timer();
    var _snap = undo_snapshot(_w, _full);
    if (ADAM_DEV_TOOLS) { show_debug_message("ADAM undo mark (" + ws_name(_w) + ", full " + string(_full) + "): " + string((get_timer() - _t0) / 1000) + " ms, " + string(string_byte_length(_snap.data)) + " bytes"); }
    array_push(undo_stacks[_w], _snap);
    if (array_length(undo_stacks[_w]) > 40) { array_delete(undo_stacks[_w], 0, 1); }
    redo_stacks[_w] = [];
}

function undo_do()
{
    var _w = ws;
    if (array_length(undo_stacks[_w]) == 0)
    {
        toast("Nothing to undo on the " + ws_name(_w) + " page", 1);
        return;
    }
    var _snap = array_pop(undo_stacks[_w]);
    array_push(redo_stacks[_w], undo_snapshot(_w, _snap.full));
    undo_restore(_snap);
    undo_last_tag = "";
}

function redo_do()
{
    var _w = ws;
    if (array_length(redo_stacks[_w]) == 0)
    {
        toast("Nothing to redo on the " + ws_name(_w) + " page", 1);
        return;
    }
    var _snap = array_pop(redo_stacks[_w]);
    array_push(undo_stacks[_w], undo_snapshot(_w, _snap.full));
    undo_restore(_snap);
    undo_last_tag = "";
}

function undo_count()
{
    return array_length(undo_stacks[ws]);
}

function redo_count()
{
    return array_length(redo_stacks[ws]);
}

/// Sets struct field with undo when the value changes
function set_val(_struct, _key, _value, _tag)
{
    if (_struct[$ _key] != _value)
    {
        undo_mark(_tag);
        _struct[$ _key] = _value;
        return true;
    }
    return false;
}

/// Removes an actor and repairs rule references
function actor_remove(_idx)
{
    array_delete(proj.actors, _idx, 1);
    for (var i = 0; i < array_length(proj.rules); i++)
    {
        var _r = proj.rules[i];
        if (_r.a == _idx) { _r.a = 0; }
        else { if (_r.a > _idx) { _r.a -= 1; } }
        if (_r.b == _idx) { _r.b = 0; }
        else { if (_r.b > _idx) { _r.b -= 1; } }
        if (_r.target == _idx) { _r.target = 0; }
        else { if (_r.target > _idx) { _r.target -= 1; } }
    }
}

/// Distance between two $RRGGBB colours (weighted for the eye)
function rgb_dist(_a, _b)
{
    var _dr = rgb_r(_a) - rgb_r(_b);
    var _dg = rgb_g(_a) - rgb_g(_b);
    var _db = rgb_b(_a) - rgb_b(_b);
    return _dr * _dr * 3 + _dg * _dg * 4 + _db * _db * 2;
}

/// Changes the backdrop's number of bitplanes. Pixels using colours that no
/// longer exist are moved to the nearest remaining colour.
function backdrop_set_depth(_depth)
{
    var _new = clamp(_depth, 1, 7);
    if (_new == proj.depth) { return; }
    var _count = 1 << _new;
    if (_new < proj.depth)
    {
        var _map = array_create(PAL_MAX, 0);
        for (var i = 0; i < PAL_MAX; i++)
        {
            if (i < _count) { _map[i] = i; }
            else
            {
                var _best = 0;
                var _bd = 999999999;
                for (var k = 0; k < _count; k++)
                {
                    var _d = rgb_dist(proj.pal[i], proj.pal[k]);
                    if (_d < _bd) { _bd = _d; _best = k; }
                }
                _map[i] = _best;
            }
        }
        var _n = BD_W * BD_H;
        for (var p = 0; p < _n; p++)
        {
            var _v = proj.pixels[p];
            if (_v >= _count) { proj.pixels[p] = _map[_v]; }
        }
        proj.hud_colour = _map[clamp(proj.hud_colour, 0, PAL_MAX - 1)];
        proj.msg_colour = _map[clamp(proj.msg_colour, 0, PAL_MAX - 1)];
    }
    proj.depth = _new;
    bd_dirty = true;
    bd_sel = clamp(bd_sel, 0, _count - 1);
}

function settings_load()
{
    ini_open("adam_settings.ini");
    settings_first_run = !ini_key_exists("machine", "last");
    whatsnew_seen = ini_read_string("ui", "whatsnew_seen", "");
    update_check_on = ini_read_real("ui", "update_check", 1) == 1;
    fsuae_path = ini_read_string("paths", "fsuae", "");
    var _old_kick = ini_read_string("paths", "kickstart", "");     // before one ROM per machine
    for (var k = 0; k < array_length(global.MACHINES); k++)
    {
        kick_paths[k] = ini_read_string("paths", "kickstart_" + global.MACHINES[k].id, "");
    }
    fsuae_light = ini_read_real("emulator", "light", 1) == 1;
    fsuae_pad = clamp(round(ini_read_real("emulator", "pad", 0)), 0, 1);
    out_path = ini_read_string("paths", "adf", "");
    proj_path = ini_read_string("paths", "project", "");
    last_machine = ini_read_string("machine", "last", "A1200");
    if (_old_kick != "" && kick_paths[machine_index(last_machine)] == "")
    {
        kick_paths[machine_index(last_machine)] = _old_kick;   // goes to the machine you used last
    }
    helpers_on = ini_read_real("ui", "helpers", 1) == 1;
    auto_tutorials = ini_read_real("ui", "auto_tutorials", 1) == 1;
    ui_scale_pref = ini_read_real("ui", "scale", 0);
    start_fullscreen = ini_read_real("ui", "fullscreen", 1) == 1;
    wsave_x = ini_read_real("window", "x", -1);
    wsave_y = ini_read_real("window", "y", -1);
    wsave_w = ini_read_real("window", "w", -1);
    wsave_h = ini_read_real("window", "h", -1);
    for (var i = 0; i < WS_COUNT; i++)
    {
        ws_seen[i] = ini_read_real("seen", "ws" + string(i), 0) == 1;
    }
    for (var l = 0; l < array_length(les_done); l++)
    {
        les_done[l] = ini_read_real("lessons", "done" + string(l), 0) == 1;
    }
    ini_close();
    last_machine = machine_get(last_machine).id;
}

function settings_save()
{
    ini_open("adam_settings.ini");
    ini_write_string("paths", "fsuae", fsuae_path);
    for (var k = 0; k < array_length(global.MACHINES); k++)
    {
        ini_write_string("paths", "kickstart_" + global.MACHINES[k].id, kick_paths[k]);
    }
    ini_key_delete("paths", "kickstart");
    var _light = 0;
    if (fsuae_light) { _light = 1; }
    ini_write_real("emulator", "light", _light);
    ini_write_real("emulator", "pad", fsuae_pad);
    ini_write_string("paths", "adf", out_path);
    ini_write_string("paths", "project", proj_path);
    ini_write_string("machine", "last", last_machine);
    var _h = 0;
    if (helpers_on) { _h = 1; }
    ini_write_real("ui", "helpers", _h);
    var _t = 0;
    if (auto_tutorials) { _t = 1; }
    ini_write_real("ui", "auto_tutorials", _t);
    ini_write_real("ui", "scale", ui_scale_pref);
    var _fs = 0;
    if (start_fullscreen) { _fs = 1; }
    ini_write_real("ui", "fullscreen", _fs);
    ini_write_string("ui", "whatsnew_seen", whatsnew_seen);
    var _uc = 0;
    if (update_check_on) { _uc = 1; }
    ini_write_real("ui", "update_check", _uc);
    ini_write_real("window", "x", wsave_x);
    ini_write_real("window", "y", wsave_y);
    ini_write_real("window", "w", wsave_w);
    ini_write_real("window", "h", wsave_h);
    for (var i = 0; i < WS_COUNT; i++)
    {
        var _s = 0;
        if (ws_seen[i]) { _s = 1; }
        ini_write_real("seen", "ws" + string(i), _s);
    }
    for (var l = 0; l < array_length(les_done); l++)
    {
        var _d = 0;
        if (les_done[l]) { _d = 1; }
        ini_write_real("lessons", "done" + string(l), _d);
    }
    ini_close();
}

function autosave_path()
{
    return game_save_id + "autosave.adam";
}
