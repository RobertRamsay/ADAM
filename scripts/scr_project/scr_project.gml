/// ADAM - project data model, example game, save/load, undo, settings

#macro SPR_COUNT 128           // sprite bank slots in every project (ADAM Lite and Pro)
#macro SFX_MAX 64              // sounds in a project (ADAM Pro; Lite plays the first LITE_SOUNDS)
#macro SFX_START 8             // sounds in a new project
#macro SPR_W 16
#macro SPR_H 24
#macro BD_W 320
#macro BD_H 256
#macro ACT_XMAX 304
#macro ACT_YMAX 232
#macro SPR_BIG_W 64             // ADAM Pro: sprites up to 64 x 64 (drawn as BOBs)
#macro SPR_BIG_H 64
#macro PAL_MAX 128
#macro PALETTE_MAX 8            // named palettes (Backdrop page, DO 27 Switch palette, per level)
#macro ITEM_MAX 16              // inventory items (Logic page, Items tab)
#macro RECIPE_MAX 16            // recipes: item + item makes an item
#macro ITEM_CARRY_MAX 99        // the most of one item the player can carry
#macro ITEM_NAME_LEN 8          // item names: upper case (the game's font), shown in the space bar menu

function project_defs_init()
{
    global.ROLE_NAMES = ["Player (joystick)", "Bouncer (diagonal)", "Patrol left-right", "Patrol up-down", "Chaser (follows player)", "Still (does not move)", "Platform player (walks + jumps)", "Hopper (jumps left and right)", "Faller (drops onto the ground)", "Shot (fired by a Shoot rule)", "Flyer (shoot 'em up enemy)", "Option (flies behind the player)", "Effect (explosion, sparkle)"];
    global.WHEN_NAMES = ["Actor touches actor", "Fire button is pressed", "Every few seconds", "Score reaches", "Lives run out", "The game starts", "Actor jumps", "A level starts", "Fire is held (stick still)", "Actor is in view", "Player strikes actor", "Thrown or shot actor hits", "Player picks up actor", "Seconds into the level", "Fire is held (auto-fire)", "The map reaches its end", "An animation ends", "Player gets an item", "Player uses an item on"];
    global.DO_NAMES   = ["Add to score", "Lose a life", "Play a sound", "Flash the player", "Send actor back to start",
                         "Move actor to a random spot", "Hide actor", "Show actor", "Change background colour",
                         "Game over", "You win!", "Speed up actor", "Slow down actor", "Add a life", "Move actor to another actor",
                         "Show actor for a moment", "Make actor safe for a while", "Count towards the level goal",
                         "Play music", "Stop music", "Place a tile (tile world)", "Drop what is carried", "Shoot (fire a shot actor)",
                         "Power up the player", "Set off an effect", "Spawn actor (split into)", "Play an animation", "Switch palette",
                         "Give the player an item", "Take an item away", "Make a recipe", "Drop an item"];
    global.PAL_FADES = [0, 12, 25, 50, 100, 200];   // DO 27 target: frames the fade takes
    global.PAL_FADE_NAMES = ["at once", "fading 1/4 s", "fading 1/2 s", "fading 1 s", "fading 2 s", "fading 4 s"];
    global.HD_NAMES = ["Hit", "Die", "Hit or Die"];       // DO 26 value (0 / 1), WHEN 16 n (0 / 1 / 2 either)
    global.ITEM_USE_NAMES = ["Used up", "Kept", "A few uses"];   // item.use: what using an item does to it
    global.IF_NAMES = ["has", "uses", "has no", "has at least"];  // IF line cond: check / needs it and uses it / has none / has n or more
    global.AIM_NAMES = ["The way the shooter moves", "Up", "Down", "Left", "Right", "At the player", "Homing missile"];
    global.FIRE_PAT_NAMES = ["The shot's own aim", "At the player", "Three at the player", "Ring of 8", "Fan of three"];
    global.PATTERN_NAMES = ["Straight", "Wave", "Zigzag", "Homing (drifts at the player)", "Moves with the scenery", "Comes in and stays (boss)"];
    global.EDGE_NAMES = ["Top", "Right", "Bottom", "Left"];
    global.POWER_NAMES = ["Firepower (more shots)", "Speed", "Add an option", "Lose all power-ups", "Homing missiles"];
    global.SCROLL_NAMES = ["No scrolling", "Flies up", "Flies right", "Flies down", "Flies left"];
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
        bob : false,            // ADAM Pro: drawn by the blitter instead of a hardware sprite
        carry : false,          // the player picks it up (fire on it) and throws it (fire again)
        aim : 0,                // a shot (role 9): 0 the way the shooter moves, 1 up, 2 down, 3 left, 4 right, 5 at the player
        pattern : 0,            // a flyer (role 10): 0 straight, 1 wave, 2 zigzag, 3 homing, 4 with the scenery, 5 comes in and stays (boss)
        enter : 1,              // a flyer's edge: 0 top, 1 right, 2 bottom, 3 left
        comeback : true,        // a flyer that leaves the far edge comes in again (else it hides)
        hits : 1,               // shots it takes before WHEN 'Thrown or shot actor hits' fires (toughness)
        copies : 1,             // how many of it go on the disk (a wave, a pool of shots); rules name them all
        fire : -1,              // the shot (role 9) it fires by itself while on the screen, -1 = none
        fire_rate : 60,         // frames between its volleys (a little random is added)
        fire_pat : 0            // 0 the shot's own aim, 1 at the player, 2 three at the player, 3 ring of 8, 4 fan of three
    };
}

#macro COPIES_MAX 16            // copies of one actor on the disk
#macro SPAWN_MAX 128            // spawners on a shoot 'em up map
#macro STAMP_MAX 64             // saved stamps (metatiles) on the Tiles page
#macro SHMUP_COLS_MIN 12        // a shoot 'em up map's play area: 12 to 20 tiles of 16 across, an even
#macro SHMUP_COLS_MAX 20        // number, centred on the screen (20 = the whole screen)
#macro SHMUP_COLS_NEW 12        // a new map: less to draw, so an A500 keeps up

/// A spawner on the shoot 'em up map (Tiles page): when the view reaches map line y it
/// sends out n copies of actor act, gap frames apart, from an edge (0 top, 1 right, 3 left)
/// at x (top) or at height 'at' (sides), each dx pixels further across; pattern -1 = the
/// actor's own flight pattern (4 = it sits on the map where it was placed)
function spawner_new(_y, _act)
{
    return { y : _y, act : _act, n : 1, gap : 20, pattern : -1, edge : 0, x : 152, dx : 0, at : 40 };
}

/// A loaded spawner, made safe
function spawner_from_loaded(_raw)
{
    var _s = spawner_new(0, 0);
    if (!is_struct(_raw)) { return _s; }
    var _keys = ["y", "act", "n", "gap", "pattern", "edge", "x", "dx", "at"];
    for (var i = 0; i < array_length(_keys); i++)
    {
        var _v = _raw[$ _keys[i]];
        if (is_numeric(_v)) { _s[$ _keys[i]] = floor(_v); }
    }
    _s.act = clamp(_s.act, 0, ACT_MAX_ALL - 1);
    _s.n = clamp(_s.n, 1, COPIES_MAX);
    _s.gap = clamp(_s.gap, 0, 250);
    _s.pattern = clamp(_s.pattern, -1, 5);
    _s.edge = clamp(_s.edge, 0, 3);
    _s.x = clamp(_s.x, -64, 320);
    _s.dx = clamp(_s.dx, -160, 160);
    _s.at = clamp(_s.at, 0, 255);
    _s.y = max(0, _s.y);
    return _s;
}

/// A loaded stamp (a block of map cells saved on the Tiles page), made safe; undefined if broken
function stamp_from_loaded(_raw)
{
    if (!is_struct(_raw)) { return undefined; }
    var _w = _raw[$ "w"];
    var _h = _raw[$ "h"];
    var _c = _raw[$ "cells"];
    if (!is_numeric(_w) || !is_numeric(_h) || !is_array(_c)) { return undefined; }
    _w = floor(_w);
    _h = floor(_h);
    if (_w < 1 || _h < 1 || _w > 64 || _h > 64 || array_length(_c) != _w * _h) { return undefined; }
    var _name = "Stamp";
    if (is_string(_raw[$ "name"])) { _name = string_copy(_raw.name, 1, 24); }
    var _cells = array_create(_w * _h, 0);
    for (var i = 0; i < _w * _h; i++)
    {
        if (is_numeric(_c[i])) { _cells[i] = max(0, floor(_c[i])); }
    }
    return { name : _name, w : _w, h : _h, cells : _cells };
}

/// Does DO action _act use its value as an actor (move to, shoot, set off, spawn)?
function do_value_is_actor(_act)
{
    return _act == 14 || _act == 22 || _act == 24 || _act == 25;
}

/// False for the DO actions whose target is not an actor (27 Switch palette: fade frames;
/// 28 Give / 29 Take an item: how many; 30 Make a recipe, 31 Drop an item: unused)
function do_target_is_actor(_act)
{
    return _act < 27;
}

/// Does DO action _act use its value as an item (give, take, drop)?
function do_value_is_item(_act)
{
    return _act == 28 || _act == 29 || _act == 31;
}

// ---------------------------------------------------------------------------
// Animations (Animate page, Lite and Pro). Each actor has 4: Idle (standing
// still), Walk (moving), Jump and Fall (in the air - platform players,
// hoppers and fallers). Each is up to ANIM_FRAMES sprite-bank slots, a speed
// in 50ths of a second per frame and a mode. Empty ones borrow from the
// others when the disk is built (anim_plan, same as adf_reference.py).
// ---------------------------------------------------------------------------
#macro ANIM_COUNT 23            // stored per actor: 0 Idle, 1 Walk, 2 Jump, 3 Fall, 4..11 N NE E SE S SW W NW,
                                // 12 Fire, 13..20 Fire + N .. NW (the player holding fire), 21 Hit, 22 Die
#macro ANIM_FIRE_END 21         // one past the last Fire animation
#macro ANIM_HIT 21              // played by DO 26 (Play an animation), once; WHEN 16 fires at its end
#macro ANIM_DIE 22
#macro ANIM_BASIC 4             // Idle, Walk, Jump, Fall
#macro ANIM_DIR0 4              // first of the 8 directions
#macro ANIM_FIRE0 12            // Fire with no direction; 13..20 = Fire + the 8 directions
#macro ANIM_FRAMES 16

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

/// Makes a loaded anims array safe: ANIM_COUNT entries (older files have 4, 12 or 21), up to 16 frames each, values in range
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
    return anims_fire_used(_ac) || anims_hd_used(_ac);
}

/// True when Hit or Die has frames: both go on the disk after the others (A_AMODE bit 2)
function anims_hd_used(_ac)
{
    return array_length(_ac.anims[ANIM_HIT].frames) > 0 || array_length(_ac.anims[ANIM_DIE].frames) > 0;
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
/// The With Fire joystick and its animations are available in Lite and Pro.
function anims_fire_used(_ac)
{
    if (!lim_fire()) { return false; }
    for (var i = ANIM_FIRE0; i < ANIM_FIRE_END; i++)
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
/// facing the last direction), then Hit and Die when either has frames (an empty Hit
/// plays Die or Idle, an empty Die plays Hit). Must match anim_plan in adf_reference.py.
function anim_plan(_ac)
{
    var _pl = anim_plan_main(_ac);
    if (is_undefined(_pl) || !anims_hd_used(_ac)) { return _pl; }
    var _hit = anim_plan_entry(_ac, ANIM_HIT);
    var _die = anim_plan_entry(_ac, ANIM_DIE);
    if (is_undefined(_hit))
    {
        if (!is_undefined(_die)) { _hit = _die; }
        else { _hit = _pl[0]; }
    }
    if (is_undefined(_die)) { _die = _hit; }
    array_push(_pl, _hit, _die);
    return _pl;
}

/// Slot _k as the plan writes it (Lite: its first frames), or undefined when it is empty
function anim_plan_entry(_ac, _k)
{
    var _src = _ac.anims[_k];
    if (array_length(_src.frames) == 0) { return undefined; }
    var _pf = _src.frames;
    if (array_length(_pf) > lim_frames())
    {
        _pf = [];
        for (var pf = 0; pf < lim_frames(); pf++) { array_push(_pf, _src.frames[pf]); }
    }
    return { frames : _pf, rate : clamp(_src.rate, 2, 30), mode : clamp(_src.mode, 0, 2), flip : false };
}

/// How many of a plan's entries come before Hit and Die (4, 12 or 21)
function anim_plan_main_len(_ac, _plan)
{
    if (anims_hd_used(_ac)) { return array_length(_plan) - 2; }
    return array_length(_plan);
}

/// Where Animate-page slot _k is in a plan, or -1 when the plan has none for it (a plan
/// is 4, 12 or 21 long, 2 more with Hit and Die)
function anim_plan_k(_plan, _k)
{
    var _n = array_length(_plan);
    var _nm = _n;
    if (_n == ANIM_BASIC + 2 || _n == ANIM_FIRE0 + 2 || _n == ANIM_FIRE_END + 2) { _nm = _n - 2; }
    if (_k >= ANIM_HIT)
    {
        if (_nm == _n) { return -1; }
        return _nm + _k - ANIM_HIT;
    }
    if (_k < _nm) { return _k; }
    return -1;
}

function anim_plan_main(_ac)
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
                    // ADAM Lite plays the first 6 frames (as lite_trim writes them)
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

#macro RULE_DOS_MAX 5           // DO lines on one rule card: the DO and up to 4 AND DO lines
#macro RULE_IFS_MAX 3           // IF lines on one rule card (items the player must have)

function rule_new()
{
    // n: seconds / score / tenths held / seconds in view / item (WHEN 17, 18); value: points / sound /
    // colour / actor / song / tile / item / recipe; more: the AND DO lines (do_new), each runs when the
    // rule fires; ifs: the IF lines (if_new) - the rule fires only when they are all true
    return { when : 0, a : 0, b : 1, n : 1, act : 0, target : 0, value : 10, group : -1, more : [], ifs : [] };
}

/// An IF line of a rule: the player cond 0 has item / 1 uses item (it must have one, and using it
/// does what the item's 'When used' says) / 2 has no item / 3 has at least n of item
function if_new()
{
    return { cond : 0, item : 0, n : 1 };
}

/// An AND DO line of a rule: what it does, the actor it changes and its value
function do_new()
{
    return { act : 2, target : 0, value : 0 };
}

/// Does rule _r do _act, on its DO line or an AND DO line?
function rule_has_act(_r, _act)
{
    if (_r.act == _act) { return true; }
    for (var i = 0; i < array_length(_r.more); i++)
    {
        if (_r.more[i].act == _act) { return true; }
    }
    return false;
}

function sfx_new(_name)
{
    return {
        name : _name, kind : 0,
        wave : 2, pitch : 60, sweep : 0, len : 10, atk : 0, dec : 8, sus : 0, rel : 6,
        filt : 0, fspeed : 0, fdepth : 0,        // low-pass filter 1..15 (0 off), its sweep speed and depth
        smp : "", smp_rate : 0, smp_len : 0, smp_file : "",
        rate : 11025, bits : 8, gain : 100, trim_a : 0, trim_b : 1000,
        sample_loop : false, loop_a : 0, loop_b : 1000,
        patch : patch_new(),                     // kind 2: the Patch synth's settings (scr_patch)
        group : -1                               // Sound page folder (proj.sound_groups), -1 = none
    };
}

/// How many places play sound _k: rules (DO and AND DO lines), tiles and
/// (when _music) Music page loops that use it as an instrument
function sfx_ref_count(_p, _k, _music)
{
    var _n = 0;
    for (var r = 0; r < array_length(_p.rules); r++)
    {
        var _ru = _p.rules[r];
        if (_ru.act == 2 && _ru.value == _k) { _n += 1; }
        for (var m = 0; m < array_length(_ru.more); m++)
        {
            if (_ru.more[m].act == 2 && _ru.more[m].value == _k) { _n += 1; }
        }
    }
    for (var t = 0; t < array_length(_p.tiles); t++)
    {
        if (_p.tiles[t].sound == _k) { _n += 1; }
    }
    if (_music) { _n += sfx_music_uses(_p, _k); }
    return _n;
}

/// Music page loops that play sound _k as their instrument
function sfx_music_uses(_p, _k)
{
    var _n = 0;
    var _id = MUS_INST_USER + _k;
    for (var s = 0; s < array_length(_p.songs); s++)
    {
        var _song = _p.songs[s];
        if (_song.kind != 0) { continue; }
        for (var l = 0; l < array_length(_song.arr.loops); l++)
        {
            var _lp = _song.arr.loops[l];
            var _hit = (_lp.inst == _id);
            for (var st = 0; st < array_length(_lp.insts); st++)
            {
                if (_lp.insts[st] == _id) { _hit = true; }
            }
            if (_hit) { _n += 1; }
        }
    }
    return _n;
}

/// Renumbers sound references after sound _k is removed (_k itself must be unused)
/// or after a new sound is put in at _k (_shift = +1)
function sfx_refs_shift(_p, _k, _shift)
{
    for (var r = 0; r < array_length(_p.rules); r++)
    {
        var _ru = _p.rules[r];
        if (_ru.act == 2 && _ru.value >= _k) { _ru.value += _shift; }
        for (var m = 0; m < array_length(_ru.more); m++)
        {
            if (_ru.more[m].act == 2 && _ru.more[m].value >= _k) { _ru.more[m].value += _shift; }
        }
    }
    for (var t = 0; t < array_length(_p.tiles); t++)
    {
        if (_p.tiles[t].sound >= _k) { _p.tiles[t].sound += _shift; }
    }
    for (var s = 0; s < array_length(_p.songs); s++)
    {
        var _song = _p.songs[s];
        if (_song.kind != 0) { continue; }
        for (var l = 0; l < array_length(_song.arr.loops); l++)
        {
            var _lp = _song.arr.loops[l];
            if (_lp.inst >= MUS_INST_USER + _k) { _lp.inst += _shift; }
            for (var st = 0; st < array_length(_lp.insts); st++)
            {
                if (_lp.insts[st] >= MUS_INST_USER + _k) { _lp.insts[st] += _shift; }
            }
        }
    }
}

/// Sounds in Sound page order: those in no folder, then each folder in turn.
/// Returns { ids, names } for the sound pickers on other pages.
function sfx_pick_list(_with_none)
{
    var _ids = [];
    var _names = [];
    if (_with_none) { array_push(_ids, -1); array_push(_names, "(none)"); }
    var _ng = array_length(proj.sound_groups);
    for (var g = -1; g < _ng; g++)
    {
        var _gname = "";
        if (g >= 0) { _gname = proj.sound_groups[g].name + " / "; }
        for (var i = 0; i < array_length(proj.sfx); i++)
        {
            var _sg = proj.sfx[i].group;
            if (_sg < 0 || _sg >= _ng) { _sg = -1; }
            if (_sg != g) { continue; }
            array_push(_ids, i);
            var _nm = _gname + string(i + 1) + ": " + proj.sfx[i].name;
            if (i >= lim_sounds()) { _nm += "  (Pro)"; }
            array_push(_names, _nm);
        }
    }
    return { ids : _ids, names : _names };
}

/// The picker index of sound _k in a sfx_pick_list
function sfx_pick_index(_list, _k)
{
    for (var i = 0; i < array_length(_list.ids); i++)
    {
        if (_list.ids[i] == _k) { return i; }
    }
    return 0;
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
        sfx : [],                                // 1..SFX_MAX sounds (Sound page)
        sound_groups : [],                       // Sound page folders: { name, open }
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
        palettes : [],                           // named palettes: { name, cols } - cols[i] = $RRGGBB or -1 (the main palette's)
        level_pal : array_create(LEVEL_MAX, 0),  // the palette each level starts with: 0 main, k = palettes[k - 1]
        items : [],                              // inventory items (Logic page, Items tab): item_new
        recipes : [],                            // item + item makes an item: recipe_new
        disk2_music : false,                     // the songs levels start with go on disk 2 (Build page)
        tiles_on : false,                        // play on the tile map (Tiles page) instead of the backdrop
        tile_size : 16,                          // 8, 16, 32 or 64 pixels: every tile in the game
        tiles : tiles_default(16),               // up to TILE_MAX tiles; 0 = air
        map_w : 64,
        map_h : 32,
        map : map_starter(64, 32),               // map_w x map_h tile numbers
        tile_dig : true,                         // the player digs (fire + direction) and places (fire)
        tools : [],                              // space bar menu tools (Tools tab), [] = none
        scroll_dir : 0,                          // the backdrop scrolls: 0 no, the ship flies 1 up, 2 right, 3 down, 4 left (Levels page)
        scroll_speed : 4,                        // quarter pixels per frame, 1..16
        shmup_map : false,                       // the ship flies up a map of tiles (Tiles page) instead of a looping backdrop
        spawners : [],                           // shoot 'em up map: spawner_new, sent out as the view reaches them
        stamps : [],                             // Tiles page: saved blocks of map cells { name, w, h, cells }
        hills_on : true,                         // levels draw their hills over the backdrop
        ui : ui_new(),                           // ADAM Pro custom HUD (UI page)
        loadscr : loadscr_new()                  // ADAM Pro loading screen (UI page, scr_loadscr)
    };
    for (var i = 0; i < SFX_START; i++)
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

/// Folds every rule group (opening a project or an example)
function groups_fold_all()
{
    for (var g = 0; g < array_length(proj.groups); g++) { proj.groups[g].collapsed = true; }
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

    // sounds: as many as the file has (1..SFX_MAX), and the Sound page folders
    var _lf = _raw[$ "sfx"];
    var _nsfx = array_length(_sfx);
    if (is_array(_lf) && array_length(_lf) > 0) { _nsfx = clamp(array_length(_lf), 1, SFX_MAX); }
    var _gl = _raw[$ "sound_groups"];
    var _sgroups = [];
    if (is_array(_gl))
    {
        for (var g = 0; g < min(array_length(_gl), SFX_MAX); g++)
        {
            var _sg = { name : "Folder " + string(g + 1), open : true };
            if (is_struct(_gl[g]))
            {
                if (is_string(_gl[g][$ "name"])) { _sg.name = string_copy(_gl[g].name, 1, 24); }
                if (is_numeric(_gl[g][$ "open"])) { _sg.open = (_gl[g].open != 0); }
            }
            array_push(_sgroups, _sg);
        }
    }
    _p.sound_groups = _sgroups;
    var _sfx_out = [];
    for (var j = 0; j < _nsfx; j++)
    {
        var _f = sfx_new("Sound " + string(j + 1));
        if (j < array_length(_sfx)) { _f = _sfx[j]; }
        if (is_array(_lf) && j < array_length(_lf)) { struct_overlay(_f, _lf[j]); }
        _f.patch = patch_from_loaded(_f.patch);
        if (!is_numeric(_f.group)) { _f.group = -1; }
        _f.group = clamp(floor(_f.group), -1, array_length(_sgroups) - 1);
        if (!is_numeric(_f.kind)) { _f.kind = 0; }
        _f.kind = clamp(floor(_f.kind), 0, 2);
        array_push(_sfx_out, _f);
    }
    _p.sfx = _sfx_out;

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
            if (!is_numeric(_lact.pattern)) { _lact.pattern = 0; }
            _lact.pattern = clamp(floor(_lact.pattern), 0, 5);
            if (!is_numeric(_lact.enter)) { _lact.enter = 1; }
            _lact.enter = clamp(floor(_lact.enter), 0, 3);
            if (!is_bool(_lact.comeback))
            {
                var _cv = true;
                if (is_numeric(_lact.comeback)) { _cv = (_lact.comeback != 0); }
                _lact.comeback = _cv;
            }
            if (!is_numeric(_lact.hits)) { _lact.hits = 1; }
            _lact.hits = clamp(floor(_lact.hits), 1, 99);
            if (!is_numeric(_lact.aim)) { _lact.aim = 0; }
            _lact.aim = clamp(floor(_lact.aim), 0, 6);
            if (!is_numeric(_lact.copies)) { _lact.copies = 1; }
            _lact.copies = clamp(floor(_lact.copies), 1, COPIES_MAX);
            if (!is_numeric(_lact.fire)) { _lact.fire = -1; }
            _lact.fire = clamp(floor(_lact.fire), -1, ACT_MAX_ALL - 1);
            if (!is_numeric(_lact.fire_rate)) { _lact.fire_rate = 60; }
            _lact.fire_rate = clamp(floor(_lact.fire_rate), 10, 500);
            if (!is_numeric(_lact.fire_pat)) { _lact.fire_pat = 0; }
            _lact.fire_pat = clamp(floor(_lact.fire_pat), 0, 4);
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
            var _ru = struct_overlay(rule_new(), _lr[m]);
            var _mo = [];                   // AND DO lines (older files have none)
            if (is_array(_ru.more))
            {
                for (var mi = 0; mi < min(RULE_DOS_MAX - 1, array_length(_ru.more)); mi++)
                {
                    if (is_struct(_ru.more[mi])) { array_push(_mo, struct_overlay(do_new(), _ru.more[mi])); }
                }
            }
            _ru.more = _mo;
            var _ifs = [];                  // IF lines (older files have none)
            if (is_array(_ru.ifs))
            {
                for (var fi = 0; fi < min(RULE_IFS_MAX, array_length(_ru.ifs)); fi++)
                {
                    if (!is_struct(_ru.ifs[fi])) { continue; }
                    var _if = struct_overlay(if_new(), _ru.ifs[fi]);
                    if (!is_numeric(_if.cond)) { _if.cond = 0; }
                    if (!is_numeric(_if.item)) { _if.item = 0; }
                    if (!is_numeric(_if.n)) { _if.n = 1; }
                    _if.cond = clamp(floor(_if.cond), 0, 3);
                    _if.item = clamp(floor(_if.item), 0, ITEM_MAX - 1);
                    _if.n = clamp(floor(_if.n), 1, ITEM_CARRY_MAX);
                    array_push(_ifs, _if);
                }
            }
            _ru.ifs = _ifs;
            array_push(_rules, _ru);
        }
    }
    _p.rules = _rules;

    var _grs = [];
    var _lg = _raw[$ "groups"];
    if (is_array(_lg))
    {
        for (var gi = 0; gi < array_length(_lg); gi++) { array_push(_grs, struct_overlay(group_new("Group"), _lg[gi])); }
    }
    for (var gq = 0; gq < array_length(_grs); gq++)
    {
        var _gq = _grs[gq];
        if (!is_numeric(_gq.parent) || _gq.parent < -1 || _gq.parent >= array_length(_grs) || _gq.parent == gq) { _gq.parent = -1; }
        _gq.parent = floor(_gq.parent);
    }
    for (var gc = 0; gc < array_length(_grs); gc++)
    {
        // a loop of groups inside each other: cut it
        var _walk = _grs[gc].parent;
        var _steps = 0;
        while (_walk >= 0 && _steps <= array_length(_grs))
        {
            _walk = _grs[_walk].parent;
            _steps += 1;
        }
        if (_steps > array_length(_grs)) { _grs[gc].parent = -1; }
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
    // named palettes (older files have none)
    var _pals = [];
    var _rp = _raw[$ "palettes"];
    if (is_array(_rp))
    {
        for (var pq = 0; pq < min(PALETTE_MAX, array_length(_rp)); pq++)
        {
            var _src = _rp[pq];
            var _np = palette_new("Palette " + string(pq + 1));
            if (is_struct(_src))
            {
                if (is_string(_src[$ "name"])) { _np.name = string_copy(_src[$ "name"], 1, 20); }
                var _sc = _src[$ "cols"];
                if (is_array(_sc))
                {
                    for (var pc = 0; pc < min(PAL_MAX, array_length(_sc)); pc++)
                    {
                        if (is_numeric(_sc[pc]) && _sc[pc] >= 0) { _np.cols[pc] = floor(_sc[pc]) & 0xffffff; }
                    }
                }
            }
            array_push(_pals, _np);
        }
    }
    _p.palettes = _pals;
    var _lpv = array_create(LEVEL_MAX, 0);
    var _lpr = _raw[$ "level_pal"];
    if (is_array(_lpr))
    {
        for (var lp = 0; lp < min(LEVEL_MAX, array_length(_lpr)); lp++)
        {
            if (is_numeric(_lpr[lp])) { _lpv[lp] = clamp(floor(_lpr[lp]), 0, array_length(_pals)); }
        }
    }
    _p.level_pal = _lpv;
    _p.disk2_music = (_raw[$ "disk2_music"] == true);
    items_fix(_p, _raw);                 // inventory items and recipes (older files have none)
    if (!is_numeric(_p.scroll_dir)) { _p.scroll_dir = 0; }
    _p.scroll_dir = clamp(floor(_p.scroll_dir), 0, 4);
    if (!is_numeric(_p.scroll_speed)) { _p.scroll_speed = 4; }
    _p.scroll_speed = clamp(floor(_p.scroll_speed), 1, 16);
    if (!is_bool(_p.hills_on))
    {
        var _hon = true;
        if (is_numeric(_p.hills_on)) { _hon = (_p.hills_on != 0); }
        _p.hills_on = _hon;
    }
    tiles_fix(_p);                       // tile world (older files have none)
    shmup_fix(_p, _raw);                 // shoot 'em up map, spawners, stamps (older files have none)
    _p.ui = ui_from_loaded(_raw[$ "ui"]);       // custom HUD (older files have none)
    _p.loadscr = loadscr_from_loaded(_raw[$ "loadscr"]);   // loading screen (older files have none)
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

    // the loading screen's own picture
    var _lsc = _src[$ "loadscr"];
    if (is_struct(_lsc) && is_array(_lsc[$ "pixels"]) && array_length(_lsc.pixels) == BD_W * BD_H)
    {
        var _cls = struct_overlay({}, _lsc);
        variable_struct_remove(_cls, "pixels");
        _cls.pixels_z = pack_u8(_lsc.pixels);
        _out.loadscr = _cls;
    }
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
    var _lsc = _raw[$ "loadscr"];
    if (is_struct(_lsc) && is_string(_lsc[$ "pixels_z"]))
    {
        _lsc.pixels = unpack_u8(_lsc.pixels_z, BD_W * BD_H);
        variable_struct_remove(_lsc, "pixels_z");
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
    groups_fold_all();                  // a project opens with every rule group folded
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
    snd_sel = clamp(snd_sel, 0, array_length(proj.sfx) - 1);
    music_drum_rows_refresh();
    build_listing = [];
}

// ---------------------------------------------------------------------------
// Undo / redo, one history per editor. Each editor only snapshots the parts
// of the project it changes, so undoing on the Logic page never touches the
// backdrop you painted afterwards, and so on.
// ---------------------------------------------------------------------------

/// A named palette: changes none of the main palette's colours yet
function palette_new(_name)
{
    return { name : _name, cols : array_create(PAL_MAX, -1) };
}

/// "Main palette" and the named ones (DO 27 value / level_pal numbering)
function palette_names()
{
    var _n = ["Main palette"];
    for (var i = 0; i < array_length(proj.palettes); i++) { array_push(_n, proj.palettes[i].name); }
    return _n;
}

/// Colour _i of palette _k (0 = the main one) as the game shows it
function palette_colour(_k, _i)
{
    var _c = proj.pal[_i];
    if (_k > 0 && _k <= array_length(proj.palettes))
    {
        var _o = proj.palettes[_k - 1].cols[_i];
        if (_o >= 0) { _c = _o; }
    }
    return _c;
}

/// Removes named palette _k (1..): levels and rules that used it go back to the main one
function palette_delete(_k)
{
    array_delete(proj.palettes, _k - 1, 1);
    for (var l = 0; l < array_length(proj.level_pal); l++)
    {
        if (proj.level_pal[l] == _k) { proj.level_pal[l] = 0; }
        else if (proj.level_pal[l] > _k) { proj.level_pal[l] -= 1; }
    }
    for (var r = 0; r < array_length(proj.rules); r++)
    {
        var _ru = proj.rules[r];
        var _ds = [_ru];
        for (var m = 0; m < array_length(_ru.more); m++) { array_push(_ds, _ru.more[m]); }
        for (var d = 0; d < array_length(_ds); d++)
        {
            if (_ds[d].act == 27)
            {
                if (_ds[d].value == _k) { _ds[d].value = 0; }
                else if (_ds[d].value > _k) { _ds[d].value -= 1; }
            }
        }
    }
}

/// Sets every colour of named palette _k from the main palette by a quick look:
/// 0 darker, 1 night, 2 sunset, 3 grey, 4 red alert, 5 brighter, 6 same as the main palette
function palette_look(_k, _look)
{
    var _cols = proj.palettes[_k - 1].cols;
    for (var i = 0; i < PAL_MAX; i++)
    {
        if (i >= pal_count() || _look == 6)
        {
            _cols[@ i] = -1;
            continue;
        }
        var _c = proj.pal[i];
        var _r = rgb_r(_c);
        var _g = rgb_g(_c);
        var _b = rgb_b(_c);
        var _l = 0.3 * _r + 0.59 * _g + 0.11 * _b;
        switch (_look)
        {
            case 0: _c = rgb_make(_r * 0.55, _g * 0.55, _b * 0.55); break;
            case 1: _c = rgb_make(_r * 0.25 + _l * 0.1, _g * 0.3 + _l * 0.12, _b * 0.55 + _l * 0.2 + 24); break;
            case 2: _c = rgb_make(_r * 0.9 + 40, _g * 0.7 + 10, _b * 0.5); break;
            case 3: _c = rgb_make(_l, _l, _l); break;
            case 4: _c = rgb_make(_l * 0.6 + 70, _l * 0.25, _l * 0.25); break;
            case 5: _c = rgb_make(_r + (255 - _r) * 0.4, _g + (255 - _g) * 0.4, _b + (255 - _b) * 0.4); break;
        }
        _cols[@ i] = rgb_machine(_c);
    }
}

/// Project fields each editor owns
function undo_keys(_ws)
{
    switch (_ws)
    {
        case WS_HOME:     return ["name", "lives", "show_score", "show_lives", "hud_row", "hud_colour", "msg_colour", "over_text", "win_text"];
        case WS_BACKDROP: return ["pixels", "pal", "depth", "solid", "sky_on", "sky_top", "sky_mid", "sky_bot", "sky_mid_y", "hud_colour", "msg_colour", "terrain_cols", "palettes", "level_pal", "ui"];
        case WS_LEVELS:   return ["levels_on", "levels", "terrain_cols", "goal_on", "goal", "goal_label", "title_on", "title1", "title2", "lev_text", "level_song", "scroll_dir", "scroll_speed", "hills_on", "level_pal"];
        case WS_SPRITES:  return ["sprites"];
        case WS_ACTORS:   return ["actors", "rules", "spawners", "items"];
        case WS_LOGIC:    return ["rules", "groups", "items", "recipes", "ui"];
        case WS_SOUND:    return ["sfx", "sound_groups"];
        case WS_MUSIC:    return ["songs", "level_song"];
        case WS_ANIMATE:  return ["actors"];
        case WS_TILES:    return ["tiles_on", "tile_size", "tiles", "map_w", "map_h", "map", "tile_dig", "tools", "actors", "shmup_map", "spawners", "stamps", "scroll_dir"];
        case WS_UI:       return ["ui", "loadscr"];
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

/// An actor reference after actor _idx is removed (_gone: what one to _idx becomes)
function actor_ref_after_remove(_v, _idx, _gone)
{
    if (_v == _idx) { return _gone; }
    if (_v > _idx) { return _v - 1; }
    return _v;
}

/// Removes an actor and repairs references to actors: rules (and their AND DO lines,
/// values that name an actor), the shots actors fire, spawners (theirs are removed)
function actor_remove(_idx)
{
    array_delete(proj.actors, _idx, 1);
    for (var i = 0; i < array_length(proj.rules); i++)
    {
        var _r = proj.rules[i];
        _r.a = actor_ref_after_remove(_r.a, _idx, 0);
        _r.b = actor_ref_after_remove(_r.b, _idx, 0);
        if (do_target_is_actor(_r.act)) { _r.target = actor_ref_after_remove(_r.target, _idx, 0); }
        if (do_value_is_actor(_r.act)) { _r.value = actor_ref_after_remove(_r.value, _idx, 0); }
        for (var m = 0; m < array_length(_r.more); m++)
        {
            var _d = _r.more[m];
            if (do_target_is_actor(_d.act)) { _d.target = actor_ref_after_remove(_d.target, _idx, 0); }
            if (do_value_is_actor(_d.act)) { _d.value = actor_ref_after_remove(_d.value, _idx, 0); }
        }
    }
    for (var a = 0; a < array_length(proj.actors); a++)
    {
        if (proj.actors[a].fire >= 0) { proj.actors[a].fire = actor_ref_after_remove(proj.actors[a].fire, _idx, -1); }
    }
    for (var s = array_length(proj.spawners) - 1; s >= 0; s--)
    {
        if (proj.spawners[s].act == _idx) { array_delete(proj.spawners, s, 1); }
        else if (proj.spawners[s].act > _idx) { proj.spawners[s].act -= 1; }
    }
    for (var it = 0; it < array_length(proj.items); it++)
    {
        if (proj.items[it].actor >= 0) { proj.items[it].actor = actor_ref_after_remove(proj.items[it].actor, _idx, -1); }
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
        // the custom HUD's frame and fields too (else they show colour & (count - 1))
        var _u = proj.ui;
        for (var c = 0; c < array_length(_u.frame); c++)
        {
            if (_u.frame[c] >= _count) { _u.frame[c] = _map[clamp(_u.frame[c], 0, PAL_MAX - 1)]; }
        }
        for (var f = 0; f < array_length(_u.fields); f++)
        {
            var _f = _u.fields[f];
            if (_f.colour >= _count) { _f.colour = _map[clamp(_f.colour, 0, PAL_MAX - 1)]; }
            if (_f.shadow >= _count) { _f.shadow = _map[clamp(_f.shadow, 0, PAL_MAX - 1)]; }
        }
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
