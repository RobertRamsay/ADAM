/// ADAM - project data model, example game, save/load, undo, settings

#macro SPR_COUNT 32
#macro SPR_W 16
#macro SPR_H 24
#macro BD_W 320
#macro BD_H 256
#macro ACT_XMAX 304
#macro ACT_YMAX 232
#macro PAL_MAX 128

function project_defs_init()
{
    global.ROLE_NAMES = ["Player (joystick)", "Bouncer (diagonal)", "Patrol left-right", "Patrol up-down", "Chaser (follows player)", "Still (does not move)"];
    global.WHEN_NAMES = ["Actor touches actor", "Fire button is pressed", "Every few seconds", "Score reaches", "Lives run out", "The game starts"];
    global.DO_NAMES   = ["Add to score", "Lose a life", "Play a sound", "Flash the screen", "Send actor back to start",
                         "Move actor to a random spot", "Hide actor", "Show actor", "Change background colour",
                         "Game over", "You win!", "Speed up actor", "Slow down actor", "Add a life"];
    global.WAVE_NAMES = ["Triangle (soft)", "Sawtooth (buzzy)", "Square (classic)", "Noise (crunchy)"];
    global.SFX_PRESET_NAMES = ["Coin", "Laser", "Explosion", "Jump", "Hit", "Power up", "Lose", "Blip"];
    global.TEMPLATE_NAMES = ["Player touches enemy: lose a life", "Player touches pickup: score + move pickup",
                             "Score target: you win", "Out of lives: game over", "Every 10 seconds: speed up enemy",
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

function sprite_new(_name)
{
    return {
        name : _name,
        px : array_create(SPR_W * SPR_H, 0),
        cols : [0xffdd33, 0xdd3322, 0xffffff]
    };
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
        start_up : false
    };
}

function rule_new()
{
    return { when : 0, a : 0, b : 1, n : 1, act : 0, target : 0, value : 10 };
}

function sfx_new(_name)
{
    return { name : _name, wave : 2, pitch : 60, sweep : 0, len : 10, atk : 0, dec : 8, sus : 0, rel : 6 };
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
        sfx : [],
        lives : 3,
        show_score : true,
        show_lives : true,
        hud_row : 0,
        hud_colour : 1,
        msg_colour : 14,
        over_text : "GAME OVER - PRESS FIRE",
        win_text : "YOU WIN! - PRESS FIRE"
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

/// Builds a full working example game
function project_example()
{
    var _p = project_new();
    _p.name = "Gem Hunter";
    // ---- backdrop: banded sky, two rows of hills, a frame and a title ----
    var _sky = [4, 4, 5, 5, 6, 6, 7];
    for (var py = 0; py < BD_H; py++)
    {
        for (var px = 0; px < BD_W; px++)
        {
            var _c = _sky[clamp(py div 26, 0, 6)];
            var _far = 170 + round(sin(px / 23) * 10 + sin(px / 9) * 4);
            var _near = 196 + round(sin(px / 37 + 1) * 12);
            if (py > _far) { _c = 9; }
            if (py > _near) { _c = 8; }
            if (py > 236) { _c = 11; }
            if (py > 240 && ((px div 8) + (py div 4)) mod 5 == 0) { _c = 12; }
            if (px < 4 || px >= BD_W - 4 || py < 12 || py >= BD_H - 4) { _c = 2; }
            _p.pixels[py * BD_W + px] = _c;
        }
    }
    backdrop_text_into(_p, "COLLECT GEMS - AVOID GHOSTS", 52, 244, 1);

    // ---- sprites ----
    var _hero = _p.sprites[0];
    _hero.name = "Hero";
    _hero.cols = [0xffd23a, 0x3a2410, 0xffffff];
    for (var y0 = 0; y0 < SPR_H; y0++)
    {
        for (var x0 = 0; x0 < SPR_W; x0++)
        {
            var _v = 0;
            var _d = point_distance(x0, y0, 7.5, 9.5);
            if (_d <= 7.4) { _v = 1; }
            if ((x0 == 5 || x0 == 10) && (y0 == 7 || y0 == 8)) { _v = 2; }
            if (y0 == 12 && x0 >= 5 && x0 <= 10) { _v = 2; }
            if (y0 == 11 && (x0 == 4 || x0 == 11)) { _v = 2; }
            if ((x0 == 5 || x0 == 10) && y0 == 6) { _v = 3; }
            if (y0 >= 17 && y0 <= 22 && (x0 == 5 || x0 == 6 || x0 == 9 || x0 == 10)) { _v = 2; }
            _hero.px[y0 * SPR_W + x0] = _v;
        }
    }
    var _gh = _p.sprites[1];
    _gh.name = "Ghost";
    _gh.cols = [0xc060ff, 0xffffff, 0x201040];
    for (var y1 = 0; y1 < SPR_H; y1++)
    {
        for (var x1 = 0; x1 < SPR_W; x1++)
        {
            var _in = false;
            if (y1 < 9) { if (point_distance(x1, y1, 7.5, 9) <= 7.6) { _in = true; } }
            else
            {
                if (y1 < 19) { _in = true; }
                else { if (((x1 div 2) + y1) mod 3 != 0) { _in = true; } }
            }
            if (x1 < 0 || x1 > 15) { _in = false; }
            var _gv = 0;
            if (_in) { _gv = 1; }
            if (_in && (x1 == 4 || x1 == 5 || x1 == 10 || x1 == 11) && y1 >= 6 && y1 <= 10) { _gv = 2; }
            if (_in && (x1 == 5 || x1 == 11) && (y1 == 8 || y1 == 9)) { _gv = 3; }
            _gh.px[y1 * SPR_W + x1] = _gv;
        }
    }
    var _gem = _p.sprites[2];
    _gem.name = "Gem";
    _gem.cols = [0x30e0ff, 0xffffff, 0x1060a0];
    for (var y2 = 0; y2 < SPR_H; y2++)
    {
        for (var x2 = 0; x2 < SPR_W; x2++)
        {
            var _m = abs(x2 - 7.5) * 1.15 + abs(y2 - 11.5);
            var _gv2 = 0;
            if (_m <= 8) { _gv2 = 1; }
            if (_m <= 8 && _m > 6.8) { _gv2 = 3; }
            if (_m <= 3.5 && x2 < 8 && y2 < 12) { _gv2 = 2; }
            _gem.px[y2 * SPR_W + x2] = _gv2;
        }
    }

    var _a0 = actor_new("Hero");
    _a0.sprite = 0; _a0.role = 0; _a0.speed = 2; _a0.x = 152; _a0.y = 190;
    var _a1 = actor_new("Ghost");
    _a1.sprite = 1; _a1.role = 4; _a1.speed = 1; _a1.x = 30; _a1.y = 40;
    var _a2 = actor_new("Bouncy Ghost");
    _a2.sprite = 1; _a2.role = 1; _a2.speed = 2; _a2.x = 260; _a2.y = 60;
    var _a3 = actor_new("Gem");
    _a3.sprite = 2; _a3.role = 5; _a3.speed = 1; _a3.x = 240; _a3.y = 150;
    _p.actors = [_a0, _a1, _a2, _a3];

    _p.rules = [];
    var _r;
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 1; _r.act = 1; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 1; _r.act = 4; _r.target = 0; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 1; _r.act = 2; _r.value = 6; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 2; _r.act = 1; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 2; _r.act = 4; _r.target = 0; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 2; _r.act = 3; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 3; _r.act = 0; _r.value = 10; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 3; _r.act = 5; _r.target = 3; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 0; _r.a = 0; _r.b = 3; _r.act = 2; _r.value = 0; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 2; _r.n = 10; _r.act = 11; _r.target = 2; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 3; _r.n = 200; _r.act = 10; array_push(_p.rules, _r);
    _r = rule_new(); _r.when = 4; _r.act = 9; array_push(_p.rules, _r);
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
    var _sprites = _p.sprites;
    var _sfx = _p.sfx;
    var _pal = _p.pal;
    struct_overlay(_p, _raw);
    _p.machine = machine_get(_p.machine).id;
    _p.depth = clamp(floor(_p.depth), 1, 7);
    if (!is_array(_p.pixels) || array_length(_p.pixels) != BD_W * BD_H) { _p.pixels = array_create(BD_W * BD_H, 0); }
    if (!is_array(_p.pal)) { _p.pal = _pal; }
    if (array_length(_p.pal) < PAL_MAX)
    {
        for (var c = array_length(_p.pal); c < PAL_MAX; c++) { array_push(_p.pal, _pal[c]); }
    }

    var _ls = _raw[$ "sprites"];
    for (var i = 0; i < SPR_COUNT; i++)
    {
        var _s = sprite_new("Sprite " + string(i + 1));
        if (is_array(_ls) && i < array_length(_ls)) { struct_overlay(_s, _ls[i]); }
        if (!is_array(_s.px) || array_length(_s.px) != SPR_W * SPR_H) { _s.px = array_create(SPR_W * SPR_H, 0); }
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
        for (var k = 0; k < min(8, array_length(_la)); k++)
        {
            array_push(_acts, struct_overlay(actor_new("Actor"), _la[k]));
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

function project_save_to(_path)
{
    file_write_text(_path, json_stringify(proj));
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
    proj_dirty = false;
    project_after_change();
    undo_stack = [];
    redo_stack = [];
    toast("Opened " + filename_name(_path), 0);
    if (proj.machine != _old_machine)
    {
        toast("This project is for the " + machine_cur().name + " - machine switched", 0);
    }
    return true;
}

function project_after_change()
{
    for (var i = 0; i < SPR_COUNT; i++) { spr_dirty[i] = true; }
    bd_dirty = true;
    proj.depth = clamp(proj.depth, 1, machine_cur().max_depth);
    bd_sel = clamp(bd_sel, 0, pal_count() - 1);
    sel_actor = clamp(sel_actor, 0, max(0, array_length(proj.actors) - 1));
    build_listing = [];
}

/// Call BEFORE changing proj. Coalesces rapid edits with the same tag.
function undo_mark(_tag)
{
    proj_dirty = true;
    if (_tag == undo_last_tag && current_time - undo_last_time < 1200)
    {
        undo_last_time = current_time;
        return;
    }
    undo_last_tag = _tag;
    undo_last_time = current_time;
    array_push(undo_stack, json_stringify(proj));
    if (array_length(undo_stack) > 60) { array_delete(undo_stack, 0, 1); }
    redo_stack = [];
}

function undo_do()
{
    if (array_length(undo_stack) == 0) { toast("Nothing to undo", 1); return; }
    array_push(redo_stack, json_stringify(proj));
    var _s = array_pop(undo_stack);
    proj = project_from_loaded(json_parse(_s));
    undo_last_tag = "";
    proj_dirty = true;
    project_after_change();
}

function redo_do()
{
    if (array_length(redo_stack) == 0) { toast("Nothing to redo", 1); return; }
    array_push(undo_stack, json_stringify(proj));
    var _s = array_pop(redo_stack);
    proj = project_from_loaded(json_parse(_s));
    undo_last_tag = "";
    proj_dirty = true;
    project_after_change();
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
    fsuae_path = ini_read_string("paths", "fsuae", "");
    kick_path = ini_read_string("paths", "kickstart", "");
    fsuae_light = ini_read_real("emulator", "light", 1) == 1;
    out_path = ini_read_string("paths", "adf", "");
    proj_path = ini_read_string("paths", "project", "");
    last_machine = ini_read_string("machine", "last", "A1200");
    helpers_on = ini_read_real("ui", "helpers", 1) == 1;
    auto_tutorials = ini_read_real("ui", "auto_tutorials", 1) == 1;
    ui_scale_pref = ini_read_real("ui", "scale", 0);
    start_fullscreen = ini_read_real("ui", "fullscreen", 1) == 1;
    for (var i = 0; i < WS_COUNT; i++)
    {
        ws_seen[i] = ini_read_real("seen", "ws" + string(i), 0) == 1;
    }
    ini_close();
    last_machine = machine_get(last_machine).id;
}

function settings_save()
{
    ini_open("adam_settings.ini");
    ini_write_string("paths", "fsuae", fsuae_path);
    ini_write_string("paths", "kickstart", kick_path);
    var _light = 0;
    if (fsuae_light) { _light = 1; }
    ini_write_real("emulator", "light", _light);
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
    for (var i = 0; i < WS_COUNT; i++)
    {
        var _s = 0;
        if (ws_seen[i]) { _s = 1; }
        ini_write_real("seen", "ws" + string(i), _s);
    }
    ini_close();
}

function autosave_path()
{
    return game_save_id + "autosave.adam";
}
