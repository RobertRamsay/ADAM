/// ADAM - Logic workspace (WHEN / DO rules)

function logic_find_role(_roles, _fallback)
{
    for (var i = 0; i < array_length(proj.actors); i++)
    {
        for (var r = 0; r < array_length(_roles); r++)
        {
            if (proj.actors[i].role == _roles[r]) { return i; }
        }
    }
    return _fallback;
}

function logic_add_template(_t)
{
    if (array_length(proj.rules) > 96)
    {
        toast("That is a lot of rules! The limit is 100.", 1);
        return;
    }
    undo_mark("tpl" + string(current_time));
    var _first = array_length(proj.rules);
    var _pl = logic_find_role([0, 6], 0);
    var _en = logic_find_role([4, 7, 1, 2, 3], min(1, max(0, array_length(proj.actors) - 1)));
    var _pk = logic_find_role([5], min(2, max(0, array_length(proj.actors) - 1)));
    var _r;
    switch (_t)
    {
        case 0:
            // one card: lose a life AND go home AND flash AND flash safely for a while
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _en; _r.act = 1;
            array_push(_r.more, { act : 4, target : _pl, value : 0 });
            array_push(_r.more, { act : 3, target : 0, value : 0 });
            array_push(_r.more, { act : 16, target : _pl, value : 0 });
            array_push(proj.rules, _r);
            break;
        case 1:
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _pk; _r.act = 0; _r.value = 10;
            array_push(_r.more, { act : 5, target : _pk, value : 0 });
            array_push(_r.more, { act : 2, target : 0, value : 0 });
            array_push(proj.rules, _r);
            break;
        case 2:
            _r = rule_new(); _r.when = 3; _r.n = 100; _r.act = 10; array_push(proj.rules, _r);
            break;
        case 3:
            _r = rule_new(); _r.when = 4; _r.act = 9; array_push(proj.rules, _r);
            break;
        case 4:
            _r = rule_new(); _r.when = 2; _r.n = 10; _r.act = 11; _r.target = _en; array_push(proj.rules, _r);
            break;
        case 5:
            _r = rule_new(); _r.when = 1; _r.act = 2; _r.value = 1; array_push(proj.rules, _r);
            break;
    }
    // the new rules get a group named after the recipe
    array_push(proj.groups, group_new(global.TEMPLATE_NAMES[_t]));
    var _g = array_length(proj.groups) - 1;
    for (var i = _first; i < array_length(proj.rules); i++) { proj.rules[i].group = _g; }
    logic_sort_rules();
    toast("Rules added in a new group - check the actors are the ones you meant", 0);
}

/// The sound picker list ({ ids, names }, Sound page order with folders)
function sfx_names()
{
    return sfx_pick_list(false);
}

/// Name of song _i for rule sentences, or "(no song)" when it does not exist
function logic_song_name(_i)
{
    if (!is_array(proj.songs)) { return "(no song)"; }
    if (_i < 0 || _i >= array_length(proj.songs)) { return "(no song)"; }
    var _s = proj.songs[_i];
    if (is_struct(_s))
    {
        if (is_string(_s[$ "name"])) { return _s[$ "name"]; }
    }
    return "Song " + string(_i + 1);
}

/// "1: name" for each song (Play music dropdown)
function logic_song_names()
{
    var _n = [];
    if (!is_array(proj.songs)) { return _n; }
    for (var i = 0; i < min(ADF_SONGS_MAX, array_length(proj.songs)); i++) { array_push(_n, string(i + 1) + ": " + logic_song_name(i)); }
    return _n;
}

function logic_sentence(_r)
{
    var _names = actor_names();
    var _na = array_length(proj.actors);
    var _s = "When ";
    if (_r.when == 2) { _s = ""; }
    var _an = "?";
    var _bn = "?";
    if (_r.a < _na) { _an = _names[_r.a]; }
    if (_r.b < _na) { _bn = _names[_r.b]; }
    switch (_r.when)
    {
        case 0:
            if (_r.a == _r.b) { _s += _an + " touches anything"; }
            else { _s += _an + " touches " + _bn; }
            break;
        case 1: _s += "the fire button is pressed"; break;
        case 2: _s += "Every " + string(_r.n) + " seconds"; break;
        case 3: _s += "the score reaches " + string(_r.n); break;
        case 4: _s += "the player runs out of lives"; break;
        case 5: _s += "the game starts"; break;
        case 6: _s += _an + " jumps"; break;
        case 7: _s += "a level starts"; break;
        case 8: _s += "fire is held for " + string_format(_r.n / 10, 0, 1) + " seconds with the stick still"; break;
        case 9: _s += _an + " is in view (every " + string(_r.n) + " seconds)"; break;
        case 10: _s += "the player strikes " + _bn; break;
        case 11:
            if (_r.a == _r.b) { _s += _an + " (thrown or shot) hits anything"; }
            else { _s += _an + " (thrown or shot) hits " + _bn; }
            break;
        case 12: _s += "the player picks up " + _an; break;
        case 13: _s += "the level has run " + string(_r.n) + " seconds"; break;
        case 14: _s += "fire is held (every " + string(_r.n) + " 50ths of a second)"; break;
        case 15: _s += "the shoot 'em up map reaches its end"; break;
        case 16: _s += _an + "'s " + string_lower(global.HD_NAMES[clamp(_r.n, 0, 2)]) + " animation ends"; break;
    }
    _s += ", " + logic_do_phrase(_r, _names, _na);
    for (var m = 0; m < array_length(_r.more); m++)
    {
        _s += ", then " + logic_do_phrase(_r.more[m], _names, _na);
    }
    return _s + ".";
}

/// What one DO / AND DO line does, as words (_d: act, target, value)
function logic_do_phrase(_d, _names, _na)
{
    var _s = "";
    var _tn = "?";
    if (_d.target < _na) { _tn = _names[_d.target]; }
    switch (_d.act)
    {
        case 0: _s += "add " + string(_d.value) + " to the score"; break;
        case 1: _s += "lose a life"; break;
        case 2: _s += "play sound '" + proj.sfx[clamp(_d.value, 0, array_length(proj.sfx) - 1)].name + "'"; break;
        case 3: _s += "flash the screen"; break;
        case 4: _s += "send " + _tn + " back to its start"; break;
        case 5: _s += "move " + _tn + " to a random spot"; break;
        case 6: _s += "hide " + _tn; break;
        case 7: _s += "show " + _tn; break;
        case 8: _s += "make the background colour " + string(clamp(_d.value, 0, pal_count() - 1)); break;
        case 9: _s += "it's game over"; break;
        case 10: _s += "the player wins"; break;
        case 11: _s += "speed up " + _tn; break;
        case 12: _s += "slow down " + _tn; break;
        case 13: _s += "add a life"; break;
        case 14:
            var _vn = "?";
            if (_d.value < _na) { _vn = _names[_d.value]; }
            _s += "move " + _tn + " to " + _vn;
            break;
        case 15: _s += "show " + _tn + " for a moment"; break;
        case 16: _s += "make " + _tn + " safe for a while (it flashes)"; break;
        case 17: _s += "count one towards the " + string_lower(proj.goal_label) + " goal"; break;
        case 18: _s += "play the music '" + logic_song_name(_d.value) + "' from the start"; break;
        case 19: _s += "stop the music"; break;
        case 20:
            var _tln = "?";
            if (_d.value >= 0 && _d.value < array_length(proj.tiles)) { _tln = proj.tiles[_d.value].name; }
            _s += "put a " + _tln + " tile where " + _tn + " is (if nothing solid is there)";
            break;
        case 21: _s += "the player drops what it carries"; break;
        case 22:
            var _fn = "?";
            if (_d.value < _na) { _fn = _names[_d.value]; }
            _s += "shoot " + _tn + " from " + _fn;
            break;
        case 23:
            switch (clamp(_d.value, 0, 4))
            {
                case 0: _s += "give the player more firepower"; break;
                case 1: _s += "make the player faster"; break;
                case 2: _s += "give the player an option"; break;
                case 3: _s += "the player loses every power-up"; break;
                case 4: _s += "give the player a homing missile"; break;
            }
            break;
        case 24:
            var _en = "?";
            if (_d.value < _na) { _en = _names[_d.value]; }
            _s += "set off " + _tn + " at " + _en;
            break;
        case 25:
            var _sn = "?";
            if (_d.value < _na) { _sn = _names[_d.value]; }
            _s += "a " + _tn + " comes out of " + _sn;
            break;
        case 26: _s += "play " + _tn + "'s " + string_lower(global.HD_NAMES[clamp(_d.value, 0, 1)]) + " animation"; break;
        case 27:
            var _pln = palette_names();
            _s += "switch to " + _pln[clamp(_d.value, 0, array_length(_pln) - 1)] + " " + global.PAL_FADE_NAMES[pal_fade_index(_d.target)];
            break;
    }
    return _s;
}

// ---------------------------------------------------------------------------
// Groups: named, collapsible sets of rules, which can sit inside other groups
// (parent = the group they are in, -1 = top level). proj.rules stays in run
// order and is kept sorted by group (rules outside any group first, then each
// group's rules in tree order: a group, then the groups inside it), so what you
// see top to bottom is exactly the order the Amiga checks. Groups start folded.
// ---------------------------------------------------------------------------

function group_new(_name)
{
    return { name : _name, collapsed : true, enabled : true, parent : -1 };
}

function group_colour(_g)
{
    return make_colour_hsv((_g * 47 + 140) mod 255, 150, 230);
}

/// The parent of group _g in _groups (-1 = top level, or when it is not a valid group)
function group_parent_of(_groups, _g)
{
    if (_g < 0 || _g >= array_length(_groups)) { return -1; }
    var _p = _groups[_g].parent;
    if (!is_numeric(_p) || _p < 0 || _p >= array_length(_groups)) { return -1; }
    return _p;
}

/// True when group _g (or a group it is inside) is switched off - its rules are not built
function group_off_in(_groups, _g)
{
    var _n = 0;
    while (_g >= 0 && _g < array_length(_groups) && _n <= array_length(_groups))
    {
        if (!_groups[_g].enabled) { return true; }
        _g = group_parent_of(_groups, _g);
        _n += 1;
    }
    return false;
}

/// How deep group _g sits (0 = top level)
function group_depth(_g)
{
    var _d = 0;
    var _p = group_parent_of(proj.groups, _g);
    while (_p >= 0 && _d <= array_length(proj.groups))
    {
        _d += 1;
        _p = group_parent_of(proj.groups, _p);
    }
    return _d;
}

/// True when _g is _anc or inside it (at any depth)
function group_inside(_g, _anc)
{
    var _n = 0;
    while (_g >= 0 && _n <= array_length(proj.groups))
    {
        if (_g == _anc) { return true; }
        _g = group_parent_of(proj.groups, _g);
        _n += 1;
    }
    return false;
}

/// True when a group _g is inside is folded (so _g is not shown)
function group_hidden(_g)
{
    var _p = group_parent_of(proj.groups, _g);
    var _n = 0;
    while (_p >= 0 && _n <= array_length(proj.groups))
    {
        if (proj.groups[_p].collapsed) { return true; }
        _p = group_parent_of(proj.groups, _p);
        _n += 1;
    }
    return false;
}

/// The groups in tree order: each group, then the groups inside it
function group_order()
{
    var _out = [];
    var _stack = [];
    for (var g = array_length(proj.groups) - 1; g >= 0; g--)
    {
        if (group_parent_of(proj.groups, g) < 0) { array_push(_stack, g); }
    }
    while (array_length(_stack) > 0 && array_length(_out) <= array_length(proj.groups))
    {
        var _g = array_pop(_stack);
        array_push(_out, _g);
        for (var c = array_length(proj.groups) - 1; c >= 0; c--)
        {
            if (group_parent_of(proj.groups, c) == _g) { array_push(_stack, c); }
        }
    }
    return _out;
}

/// Stable sort of the rules by group (-1 = no group comes first), groups in tree order
function logic_sort_rules()
{
    var _out = [];
    var _order = group_order();
    for (var i0 = 0; i0 < array_length(proj.rules); i0++)
    {
        if (proj.rules[i0].group < 0) { array_push(_out, proj.rules[i0]); }
    }
    for (var k = 0; k < array_length(_order); k++)
    {
        var g = _order[k];
        for (var i = 0; i < array_length(proj.rules); i++)
        {
            if (proj.rules[i].group == g) { array_push(_out, proj.rules[i]); }
        }
    }
    proj.rules = _out;
}

/// "Outer > Inner" name of group _g
function group_path(_g)
{
    var _s = proj.groups[_g].name;
    var _p = group_parent_of(proj.groups, _g);
    var _n = 0;
    while (_p >= 0 && _n < 8)
    {
        _s = proj.groups[_p].name + " > " + _s;
        _p = group_parent_of(proj.groups, _p);
        _n += 1;
    }
    return _s;
}

function group_names()
{
    var _n = ["(no group)"];
    for (var g = 0; g < array_length(proj.groups); g++) { array_push(_n, group_path(g)); }
    return _n;
}

/// Removes group _g: its rules and the groups inside it move up into its parent
function group_delete(_g)
{
    var _up = group_parent_of(proj.groups, _g);
    for (var i = 0; i < array_length(proj.rules); i++)
    {
        var _r = proj.rules[i];
        if (_r.group == _g) { _r.group = _up; }
    }
    for (var c = 0; c < array_length(proj.groups); c++)
    {
        if (proj.groups[c].parent == _g) { proj.groups[c].parent = _up; }
    }
    for (var i2 = 0; i2 < array_length(proj.rules); i2++)
    {
        if (proj.rules[i2].group > _g) { proj.rules[i2].group -= 1; }
    }
    for (var c2 = 0; c2 < array_length(proj.groups); c2++)
    {
        if (proj.groups[c2].parent > _g) { proj.groups[c2].parent -= 1; }
    }
    array_delete(proj.groups, _g, 1);
    logic_sort_rules();
}

/// Swaps groups _a and _b (two groups with the same parent: their order flips)
function group_swap(_a, _b)
{
    var _tmp = proj.groups[_a];
    proj.groups[_a] = proj.groups[_b];
    proj.groups[_b] = _tmp;
    for (var i = 0; i < array_length(proj.rules); i++)
    {
        var _r = proj.rules[i];
        if (_r.group == _a) { _r.group = _b; }
        else { if (_r.group == _b) { _r.group = _a; } }
    }
    for (var c = 0; c < array_length(proj.groups); c++)
    {
        var _gp = proj.groups[c];
        if (_gp.parent == _a) { _gp.parent = _b; }
        else { if (_gp.parent == _b) { _gp.parent = _a; } }
    }
    logic_sort_rules();
}

/// The group before (_dir -1) or after (_dir 1) _g with the same parent, or -1
function group_sibling(_g, _dir)
{
    var _p = group_parent_of(proj.groups, _g);
    var _j = _g + _dir;
    while (_j >= 0 && _j < array_length(proj.groups))
    {
        if (group_parent_of(proj.groups, _j) == _p) { return _j; }
        _j += _dir;
    }
    return -1;
}

/// Is rule _r switched off by its group (or a group that group is inside)?
function rule_disabled(_r)
{
    return group_off_in(proj.groups, _r.group);
}

/// One DO line of a rule card (_d = the rule, or one of its AND DO lines); _pill = "DO" or "AND".
/// _xr = the x the row must stop at (clear of the buttons on the right of the card).
function logic_do_row(_d, _rid, _x, _y, _pill, _anames, _snames, _xr)
{
    var _dx = _x;
    var _dy = _y;
    ui_rrect(_dx, _dy + 4, _dx + 56, _dy + 26, 11, global.TH.accent, global.TH.accent_dark, 1);
    ui_text(_dx + 28, _dy + 15, _pill, c_white, fa_center, fa_middle, global.f_small, 1);
    _dx += 66;
    set_val(_d, "act", ui_dropdown(_rid + "_act", _dx, _dy, LOGIC_DO_W, 30, global.DO_NAMES, _d.act, "DO|What happens when the WHEN part is true. AND DO lines happen too, in order, every time it fires."), _rid + "act");
    _dx += LOGIC_DO_W + 10;
    var _act = _d.act;
    if (_act == 4 || _act == 5 || _act == 6 || _act == 7 || _act == 11 || _act == 12 || _act == 14 || _act == 15 || _act == 16 || _act == 20)
    {
        set_val(_d, "target", ui_dropdown(_rid + "_t", _dx, _dy, LOGIC_ACTOR_W, 30, _anames, _d.target, "Which actor|The actor this action changes."), _rid + "t");
        _dx += LOGIC_ACTOR_W + 10;
    }
    if (_act == 22)
    {
        set_val(_d, "target", ui_dropdown(_rid + "_t", _dx, _dy, LOGIC_ACTOR_W, 30, _anames, _d.target, "Which shot|An actor with the behaviour 'Shot' (Actors page) - a laser, bullet or bomb. If it is still flying, the next Shot actor after it goes instead, so a few in a row give rapid fire."), _rid + "t");
        _dx += LOGIC_ACTOR_W + 10;
        var _frx = logic_word(_dx, _dy, "from");
        var _frw = max(100, min(LOGIC_ACTOR_W, _xr - _frx));
        set_val(_d, "value", ui_dropdown(_rid + "_from", _frx, _dy, _frw, 30, _anames, clamp(_d.value, 0, max(0, array_length(proj.actors) - 1)), "From which actor|The shot starts on this actor's middle and flies the way set on the shot (Actors page). WHEN 'Fire button is pressed' for the player; WHEN 'Every few seconds' or 'Actor is in view' for an enemy that fires back."), _rid + "from");
    }
    if (_act == 23)
    {
        set_val(_d, "value", ui_dropdown(_rid + "_pow", _dx, _dy, 220, 30, global.POWER_NAMES, clamp(_d.value, 0, 4), "Power-up|Firepower: each one adds shots to every volley (1, 2 side by side, a 3-way spread, then 4), up to 3 times. Speed: the player moves one step faster, up to 8. Add an option: the next hidden Option actor (Actors page) joins the player and fires with it. Lose all: back to the start (when the player is hit). Homing missiles: a Shoot rule firing a shot with the aim 'Homing missile' sends one missile, then two - they steer at the nearest enemy the shot can hit. Power-ups carry over to the next level."), _rid + "pow");
    }
    if (_act == 25)
    {
        set_val(_d, "target", ui_dropdown(_rid + "_t", _dx, _dy, LOGIC_ACTOR_W, 30, _anames, _d.target, "Which actor comes out|A copy of this actor that is not out yet comes out (give it Copies on the Actors page). A big enemy that splits into small ones, a hatch that lets out a fighter. It flies its pattern from there; each next one zigzags off the other way."), _rid + "t");
        _dx += LOGIC_ACTOR_W + 10;
        var _spx = logic_word(_dx, _dy, "at");
        var _spw = max(100, min(LOGIC_ACTOR_W, _xr - _spx));
        set_val(_d, "value", ui_dropdown(_rid + "_spat", _spx, _dy, _spw, 30, _anames, clamp(_d.value, 0, max(0, array_length(proj.actors) - 1)), "At which actor|It comes out centred on this actor - the one that was hit (WHEN 'Thrown or shot actor hits')."), _rid + "spat");
    }
    if (_act == 26)
    {
        set_val(_d, "target", ui_dropdown(_rid + "_t", _dx, _dy, LOGIC_ACTOR_W, 30, _anames, _d.target, "Which actor|It plays its Hit or Die animation (Animate page) once, from the first frame, then goes back to the others. WHEN 'An animation ends' fires when it has played."), _rid + "t");
        _dx += LOGIC_ACTOR_W + 10;
        set_val(_d, "value", ui_dropdown(_rid + "_hd", _dx, _dy, 110, 30, ["Hit", "Die"], clamp(_d.value, 0, 1), "Which animation|Hit: a flinch when it is struck. Die: its last moments - hide it or send it home when it ends (WHEN 'An animation ends')."), _rid + "hd");
    }
    if (_act == 27)
    {
        var _pln = palette_names();
        set_val(_d, "value", ui_dropdown(_rid + "_pal", _dx, _dy, 180, 30, _pln, clamp(_d.value, 0, array_length(_pln) - 1), "Which palette|The backdrop colours change to this palette (make palettes on the Backdrop page, Palettes tab). Its colours replace the main palette's; the rest are the main palette's. 'Main palette' goes back."), _rid + "pal");
        _dx += 190;
        var _fi = ui_dropdown(_rid + "_fade", _dx, _dy, max(100, min(150, _xr - _dx)), 30, global.PAL_FADE_NAMES, pal_fade_index(_d.target), "Fade|At once, or blend smoothly from the colours on screen over a moment - night falling, a red alert, lights going out.");
        set_val(_d, "target", global.PAL_FADES[_fi], _rid + "fade");
    }
    if (_act == 24)
    {
        set_val(_d, "target", ui_dropdown(_rid + "_t", _dx, _dy, LOGIC_ACTOR_W, 30, _anames, _d.target, "Which effect|An actor with the behaviour 'Effect' (Actors page) - an explosion or a sparkle. If it is already playing, the next Effect actor after it goes instead."), _rid + "t");
        _dx += LOGIC_ACTOR_W + 10;
        var _efx = logic_word(_dx, _dy, "at");
        var _efw = max(100, min(LOGIC_ACTOR_W, _xr - _efx));
        set_val(_d, "value", ui_dropdown(_rid + "_at", _efx, _dy, _efw, 30, _anames, clamp(_d.value, 0, max(0, array_length(proj.actors) - 1)), "At which actor|The effect starts centred on this actor - the enemy that was hit, or the player."), _rid + "at");
    }
    if (_act == 0)
    {
        set_val(_d, "value", ui_stepper(_rid + "_v", _dx, _dy, 150, _d.value, 1, 9999, "Points|How many points to add. Hold Shift for steps of 10."), _rid + "v");
        logic_word(_dx + 158, _dy, "points");
    }
    if (_act == 2)
    {
        var _si = ui_dropdown(_rid + "_snd", _dx, _dy, 180, 30, _snames.names, sfx_pick_index(_snames, _d.value), "Sound|Which of your sounds to play (listed by folder). Design them on the Sound page.");
        set_val(_d, "value", _snames.ids[_si], _rid + "snd");
        if (ui_button(_rid + "_play", _dx + 188, _dy, 60, 30, "Play", "Preview|Plays this sound so you can hear it.", BTN_GHOST))
        {
            sfx_preview_play(proj.sfx[clamp(_d.value, 0, array_length(proj.sfx) - 1)]);
        }
    }
    if (_act == 14)
    {
        var _tox = logic_word(_dx, _dy, "to");
        var _tow = max(100, min(LOGIC_ACTOR_W, _xr - _tox));
        set_val(_d, "value", ui_dropdown(_rid + "_to", _tox, _dy, _tow, 30, _anames, clamp(_d.value, 0, max(0, array_length(proj.actors) - 1)), "To which actor|The first actor jumps to where this one is - drop a gem from a moving cloud, or respawn an enemy at a portal."), _rid + "to");
    }
    if (_act == 18)
    {
        var _mnames = logic_song_names();
        if (array_length(_mnames) > 0)
        {
            set_val(_d, "value", ui_dropdown(_rid + "_song", _dx, _dy, 200, 30, _mnames, clamp(_d.value, 0, array_length(_mnames) - 1), "Song|Which song to play. It starts from the beginning, and sound effects still play over it. Make songs on the Music page."), _rid + "song");
        }
        else
        {
            ui_text(_dx, _dy + 15, ui_text_fit("No songs yet - make one on the Music page", global.f_small, _xr - _dx), global.TH.warn, fa_left, fa_middle, global.f_small, 1);
        }
    }
    if (_act == 20)
    {
        var _tnames = [];
        for (var tq = 0; tq < array_length(proj.tiles); tq++) { array_push(_tnames, string(tq) + ": " + proj.tiles[tq].name); }
        var _tlw = max(100, min(170, _xr - _dx));
        set_val(_d, "value", ui_dropdown(_rid + "_tile", _dx, _dy, _tlw, 30, _tnames, clamp(_d.value, 0, array_length(_tnames) - 1), "Tile|The tile put down where the actor is (its middle, else its feet or head) - only where nothing solid is. A ladder part to climb out of a hole, a block to stand on, a torch. Tile world games only (Tiles page)."), _rid + "tile");
        // the note only where it fits before the card's buttons (the help says it too)
        if (!proj.tiles_on && _xr - (_dx + _tlw + 8) >= 80)
        {
            ui_text(_dx + _tlw + 8, _dy + 15, "(tile worlds)", global.TH.warn, fa_left, fa_middle, global.f_small, 1);
        }
    }
    if (_act == 8)
    {
        set_val(_d, "value", ui_colour_drop(_rid + "_col", _dx, _dy, 180, 30, clamp(_d.value, 0, pal_count() - 1), "Colour|The backdrop palette colour that colour 0 (the background and border) changes to."), _rid + "col");
    }

}

/// The fade drop-down entry for DO 27's frames (the nearest one)
function pal_fade_index(_frames)
{
    var _best = 0;
    for (var i = 1; i < array_length(global.PAL_FADES); i++)
    {
        if (abs(global.PAL_FADES[i] - _frames) < abs(global.PAL_FADES[_best] - _frames)) { _best = i; }
    }
    return _best;
}

#macro LOGIC_DO_ROW_H 40         // each AND DO line makes a rule card this much taller
#macro LOGIC_WHEN_W 230          // the WHEN drop-down: room for 'Thrown actor hits actor'
#macro LOGIC_DO_W 270            // the DO drop-downs: room for 'Move actor to a random spot'
#macro LOGIC_ACTOR_W 150         // actor drop-downs on a card

/// A dim word between a card's controls, at _x; returns the x just after it (and a gap)
function logic_word(_x, _y, _text)
{
    draw_set_font(global.f_body);
    ui_text(_x, _y + 15, _text, global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
    return _x + ceil(ui_sw(_text)) + 8;
}

/// Height of rule _r's card: 128, plus a row for each AND DO line
function logic_card_h(_r)
{
    return 128 + array_length(_r.more) * LOGIC_DO_ROW_H;
}

/// One WHEN / DO card. Returns 0, or 1 = delete, 2 = up, 3 = down.
function logic_rule_card(_r, i, _cx, _cy, _cw, _anames, _snames, _gnames)
{
    var _res = 0;
    var _cardh = logic_card_h(_r);
    var _rid = "rule_" + string(i);
    var _alpha = 0.9;
    if (rule_disabled(_r)) { _alpha = 0.45; }
    ui_rrect(_cx, _cy, _cx + _cw, _cy + _cardh, 12, global.TH.btn_top, global.TH.panel_bot, _alpha);
    ui_rrect_line(_cx, _cy, _cx + _cw, _cy + _cardh, 12, global.TH.panel_edge, 0.6, 1);
    if (_r.group >= 0) { ui_rrect(_cx, _cy + 8, _cx + 5, _cy + _cardh - 8, 2, group_colour(_r.group), group_colour(_r.group), 1); }
    draw_circle_colour(_cx + 22, _cy + 22, 12, global.TH.accent, global.TH.accent_dark, false);
    ui_text(_cx + 22, _cy + 22, string(i + 1), c_white, fa_center, fa_middle, global.f_small, 1);

    // WHEN row
    var _wx = _cx + 46;
    var _wy = _cy + 10;
    ui_rrect(_wx, _wy + 4, _wx + 56, _wy + 26, 11, global.TH.accent2, make_colour_rgb(46, 140, 116), 1);
    ui_text(_wx + 28, _wy + 15, "WHEN", make_colour_rgb(16, 30, 28), fa_center, fa_middle, global.f_small, 1);
    _wx += 66;
    set_val(_r, "when", ui_dropdown(_rid + "_when", _wx, _wy, LOGIC_WHEN_W, 30, global.WHEN_NAMES, _r.when, "WHEN|The thing that has to happen for this rule to fire."), _rid + "w");
    _wx += LOGIC_WHEN_W + 10;
    var _aw = LOGIC_ACTOR_W;
    switch (_r.when)
    {
        case 0:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, _aw, 30, _anames, _r.a, "First actor|The actor that does the touching."), _rid + "a");
            _wx = logic_word(_wx + _aw + 8, _wy, "touches");
            set_val(_r, "b", ui_dropdown(_rid + "_b", _wx, _wy, _aw, 30, _anames, _r.b, "Second actor|The actor being touched. Pick the same actor twice for 'touches anything'."), _rid + "b");
            break;
        case 2:
            _wx = logic_word(_wx, _wy, "every");
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx, _wy, 120, _r.n, 1, 60, "Seconds|How many seconds between each time this rule fires."), _rid + "n");
            logic_word(_wx + 128, _wy, "seconds");
            break;
        case 6:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, _aw, 30, _anames, _r.a, "Which actor|The actor whose jump fires this rule - great for a jump sound."), _rid + "a");
            logic_word(_wx + _aw + 8, _wy, "jumps");
            break;
        case 8:
            _wx = logic_word(_wx, _wy, "for");
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx, _wy, 120, clamp(_r.n, 1, 100), 1, 100, "Hold time|How long fire is held, in tenths of a second (10 = one second), with the joystick left alone. Fires once per hold - hold again for another. Great for 'hold fire to build a ladder part'."), _rid + "n");
            logic_word(_wx + 128, _wy, "tenths of a second");
            break;
        case 9:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, _aw, 30, _anames, _r.a, "Which actor|While this actor is on the screen the rule fires every few seconds - a bell that rings only when you can see it, a waterfall you hear as you pass. Off the screen it waits, then fires a second after it comes back into view."), _rid + "a");
            _wx = logic_word(_wx + _aw + 8, _wy, "in view, every");
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx, _wy, 100, clamp(_r.n, 1, 60), 1, 60, "Seconds|How many seconds between each time, while it is in view."), _rid + "n");
            logic_word(_wx + 108, _wy, "s");
            break;
        case 10:
            _wx = logic_word(_wx, _wy, "the player strikes");
            set_val(_r, "b", ui_dropdown(_rid + "_b", _wx, _wy, _aw, 30, _anames, _r.b, "Which actor|Fires when the player's weapon (a Weapon tool - Tiles page, Tools tab) reaches this actor. Auto weapons swing by themselves only at actors that have a rule like this."), _rid + "b");
            break;
        case 11:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, _aw, 30, _anames, _r.a, "Thrown or shot actor|An actor with 'Can be carried' (Actors page) that the player has thrown, or a Shot actor fired by a Shoot rule (pick the one the Shoot rule names - its rapid-fire copies count as it)."), _rid + "a");
            _wx = logic_word(_wx + _aw + 8, _wy, "hits");
            set_val(_r, "b", ui_dropdown(_rid + "_b", _wx, _wy, _aw, 30, _anames, _r.b, "Which actor|The actor it hits while it flies. Pick the same actor twice for 'hits anything'. After a hit a thrown actor drops, harmless; a shot vanishes. A shot never hits the actor that fired it."), _rid + "b");
            break;
        case 12:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, _aw, 30, _anames, _r.a, "Which actor|Fires when the player picks this actor up (it needs 'Can be carried' on the Actors page)."), _rid + "a");
            logic_word(_wx + _aw + 8, _wy, "is picked up");
            break;
        case 16:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, _aw, 30, _anames, _r.a, "Which actor|Fires when this actor (or a copy of it) has played its Hit or Die animation through - after DO 'Play an animation'."), _rid + "a");
            _wx = logic_word(_wx + _aw + 8, _wy, "finishes");
            set_val(_r, "n", ui_dropdown(_rid + "_hd", _wx, _wy, 130, 30, global.HD_NAMES, clamp(_r.n, 0, 2), "Which animation|Hit, Die, or either of them."), _rid + "n");
            break;
        case 13:
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx, _wy, 120, clamp(_r.n, 1, 600), 1, 600, "Seconds|Fires once, this many seconds after each level starts - the boss arrives, a new wave comes in, the music changes."), _rid + "n");
            logic_word(_wx + 128, _wy, "seconds in");
            break;
        case 14:
            _wx = logic_word(_wx, _wy, "every");
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx, _wy, 120, clamp(_r.n, 1, 50), 1, 50, "Auto-fire rate|While fire is held the rule fires at once, then every this many 50ths of a second - 7 is a fast arcade auto-fire. Use it with DO 'Shoot' for the player's laser."), _rid + "n");
            logic_word(_wx + 128, _wy, "50ths of a second");
            break;
        case 3:
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx, _wy, 150, _r.n, 1, 9999, "Score target|The rule fires once when the score reaches this number. Hold Shift for steps of 10."), _rid + "n");
            logic_word(_wx + 158, _wy, "points");
            break;
    }

    // DO row, then the AND DO lines (each fires with the rule)
    logic_do_row(_r, _rid, _cx + 46, _cy + 50, "DO", _anames, _snames, _cx + _cw - 50);
    var _mdel = -1;
    for (var m = 0; m < array_length(_r.more); m++)
    {
        var _my = _cy + 50 + (m + 1) * LOGIC_DO_ROW_H;
        logic_do_row(_r.more[m], _rid + "_m" + string(m), _cx + 46, _my, "AND", _anames, _snames, _cx + _cw - 90);
        if (ui_button(_rid + "_mdel" + string(m), _cx + _cw - 80, _my, 30, 30, "x", "Remove this line|Takes this AND DO line off the rule. You can Undo this.", BTN_GHOST)) { _mdel = m; }
    }
    if (_mdel >= 0)
    {
        undo_mark("ruledodel" + string(current_time));
        array_delete(_r.more, _mdel, 1);
    }

    // sentence, group and tools
    var _gw = 170;
    var _gx = _cx + _cw - 48 - _gw;
    var _by = _cy + _cardh - 38;
    var _sx2 = _gx - 10;
    if (array_length(_r.more) < RULE_DOS_MAX - 1)
    {
        _sx2 = _gx - 112;
        if (ui_button(_rid + "_anddo", _gx - 102, _by, 92, 28, "+ AND DO", "Add an AND DO line|Something else that happens every time this rule fires - e.g. add to the score AND play a sound AND send the enemy home. Up to " + string(RULE_DOS_MAX) + " DO lines on one rule; they run in order.", BTN_GHOST))
        {
            undo_mark("ruledoadd" + string(current_time));
            array_push(_r.more, do_new());
        }
    }
    ui_text(_cx + 46, _by + 14, ui_text_fit(logic_sentence(_r), global.f_small, _sx2 - _cx - 46), global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
    var _ng = ui_dropdown(_rid + "_grp", _gx, _by, _gw, 28, _gnames, _r.group + 1, "Group|Move this rule into a group. Groups keep related rules together and can be collapsed or switched off.") - 1;
    if (_ng != _r.group)
    {
        undo_mark("rulegrp" + string(current_time));
        _r.group = _ng;
        logic_resort = true;
        var _og = _ng;                  // open the group it went into (and the groups that is inside)
        var _on = 0;
        while (_og >= 0 && _on < 64)
        {
            proj.groups[_og].collapsed = false;
            _og = group_parent_of(proj.groups, _og);
            _on += 1;
        }
    }
    var _tx = _cx + _cw - 40;
    if (ui_button(_rid + "_del", _tx, _cy + 10, 30, 30, "X", "Delete rule|Removes this rule. You can Undo this.", BTN_DANGER)) { _res = 1; }
    if (ui_button(_rid + "_up", _tx, _cy + 48, 30, 30, "^", "Move up|Rules higher up are checked first (moves within its group).", BTN_GHOST)) { _res = 2; }
    if (ui_button(_rid + "_dn", _tx, _cy + 86, 30, 30, "v", "Move down|Rules lower down are checked later (moves within its group).", BTN_GHOST)) { _res = 3; }
    return _res;
}

function ws_logic_draw(_x1, _y1, _x2, _y2)
{
    var _rw = 320;
    var _lx2 = _x2 - _rw - 12;
    ui_panel(_x1, _y1, _lx2, _y2, "");
    logic_tabs(_x1, _y1, _lx2);
    if (logic_tab == 1)
    {
        logic_items_draw(_x1, _y1, _lx2, _y2);
        logic_item_ideas_draw(_x2 - _rw, _y1, _x2, _y2);
        return;
    }
    logic_drag_item = -1;
    var _nr = array_length(proj.rules);
    var _ngr = array_length(proj.groups);
    var _subr = _lx2 - 306;                 // stop before '+ Add group' (or 'Collapse all' when there are groups)
    if (_ngr > 0) { _subr = _lx2 - 422; }
    ui_text(_x1 + 200, _y1 + 15, ui_text_fit(string(_nr) + " rule(s) in " + string(_ngr) + " group(s). Checked every frame, top to bottom.", global.f_small, _subr - _x1 - 200), global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
    if (ui_button("logic_add", _lx2 - 150, _y1 + 8, 136, 30, "+ Add rule", "Add rule|Adds a new WHEN / DO rule (outside any group). Use the + Rule button on a group to add straight into it.", BTN_ACCENT))
    {
        if (_nr < 100)
        {
            undo_mark("ruleadd" + string(current_time));
            var _nrule = rule_new();
            _nrule.a = logic_find_role([0, 6], 0);
            _nrule.b = min(1, max(0, array_length(proj.actors) - 1));
            array_push(proj.rules, _nrule);
            logic_sort_rules();
            logic_reveal = _nrule;
        }
        else { toast("100 rules is the limit", 1); }
    }
    if (ui_button("logic_addgroup", _lx2 - 296, _y1 + 8, 136, 30, "+ Add group", "Add group|Makes a new named group. Put rules in it with the Group drop-down on each rule, put groups inside groups (+ Group, or 'In:' on a group), fold it to tidy up, or switch it off to test without those rules.", BTN_NORMAL))
    {
        undo_mark("grpadd" + string(current_time));
        array_push(proj.groups, group_new("Group " + string(_ngr + 1)));
    }
    if (_ngr > 0)
    {
        var _allc = true;
        for (var gc = 0; gc < _ngr; gc++)
        {
            if (!proj.groups[gc].collapsed) { _allc = false; }
        }
        var _clab = "Collapse all";
        if (_allc) { _clab = "Expand all"; }
        if (ui_button("logic_collapse_all", _lx2 - 412, _y1 + 8, 110, 30, _clab, "Collapse / expand all|Folds every group down to its title bar, or opens them all again.", BTN_GHOST))
        {
            for (var gx = 0; gx < _ngr; gx++) { proj.groups[gx].collapsed = !_allc; }
            proj_dirty = true;
        }
    }

    var _lx = _x1 + 14;
    var _ly1 = _y1 + 52;
    var _ly2 = _y2 - 12;
    var _hdrh = 44;
    var _anames = actor_names();
    var _snames = sfx_names();
    var _gnames = group_names();
    var _cw = _lx2 - 14 - _lx - 10;

    // layout: [kind, index] with kind 0 = rule, 1 = group header; groups in tree order
    var _items = [];
    for (var i0 = 0; i0 < _nr; i0++)
    {
        if (proj.rules[i0].group < 0) { array_push(_items, [0, i0]); }
    }
    var _gorder = group_order();
    for (var go = 0; go < array_length(_gorder); go++)
    {
        var g = _gorder[go];
        if (group_hidden(g)) { continue; }
        array_push(_items, [1, g]);
        if (!proj.groups[g].collapsed)
        {
            for (var i1 = 0; i1 < _nr; i1++)
            {
                if (proj.rules[i1].group == g) { array_push(_items, [0, i1]); }
            }
        }
    }
    var _content = 10;
    for (var k = 0; k < array_length(_items); k++)
    {
        if (_items[k][0] == 0) { _content += logic_card_h(proj.rules[_items[k][1]]) + 10; }
        else { _content += _hdrh + 10; }
    }
    // a rule was just added: scroll so its whole card is in view
    if (is_struct(logic_reveal))
    {
        var _ry2 = 10;
        for (var k3 = 0; k3 < array_length(_items); k3++)
        {
            if (_items[k3][0] == 0 && proj.rules[_items[k3][1]] == logic_reveal)
            {
                var _view = _ly2 - _ly1;
                var _cur = ds_map_find_value(ui_scroll, "logic_list");
                if (is_undefined(_cur)) { _cur = 0; }
                if (_ry2 - 10 < _cur) { _cur = _ry2 - 10; }
                if (_ry2 + logic_card_h(logic_reveal) + 10 > _cur + _view) { _cur = _ry2 + logic_card_h(logic_reveal) + 10 - _view; }
                ds_map_replace(ui_scroll, "logic_list", max(0, _cur));
                break;
            }
            if (_items[k3][0] == 0) { _ry2 += logic_card_h(proj.rules[_items[k3][1]]) + 10; }
            else { _ry2 += _hdrh + 10; }
        }
        logic_reveal = -1;
    }
    var _off = ui_scroll_begin("logic_list", _lx, _ly1, _lx2 - 10, _ly2, _content);
    if (_nr == 0 && _ngr == 0)
    {
        ui_text_wrap(_lx + 20, _ly1 + 20, "No rules yet. Rules make your game a game! Press '+ Add rule' or pick a quick recipe on the right, e.g. 'Player touches enemy: lose a life'. Use groups to keep related rules together.", global.TH.text_dim, _cw - 40, global.f_body, 1);
    }
    var _del = -1;
    var _move = 0;
    var _movei = -1;
    var _gact = -1;
    var _gop = "";
    var _gpar = -1;
    var _y = _ly1 + 10 - _off;
    for (var k2 = 0; k2 < array_length(_items); k2++)
    {
        var _it = _items[k2];
        if (_it[0] == 1)
        {
            var _g = _it[1];
            var _gr = proj.groups[_g];
            var _gin = min(group_depth(_g) * 20, max(0, _cw - 816));     // groups inside groups step in (cards keep 800 px)
            var _gx0 = _lx + _gin;
            var _gw0 = _cw - _gin;
            if (_y + _hdrh >= _ly1 - 10 && _y <= _ly2 + 10)
            {
                var _gid = "grp_" + string(_g);
                var _count = 0;
                for (var c = 0; c < _nr; c++)
                {
                    if (proj.rules[c].group == _g) { _count += 1; }
                }
                var _nsub = 0;
                for (var cg = 0; cg < _ngr; cg++)
                {
                    if (group_parent_of(proj.groups, cg) == _g) { _nsub += 1; }
                }
                var _gcol = group_colour(_g);
                var _ga = 0.95;
                if (group_off_in(proj.groups, _g)) { _ga = 0.5; }
                ui_rrect(_gx0, _y, _gx0 + _gw0, _y + _hdrh, 10, merge_colour(global.TH.btn_hot_top, _gcol, 0.18), global.TH.btn_bot, _ga);
                ui_rrect(_gx0, _y, _gx0 + 8, _y + _hdrh, 4, _gcol, _gcol, 1);
                ui_rrect_line(_gx0, _y, _gx0 + _gw0, _y + _hdrh, 10, _gcol, 0.6, 1);
                // collapse / expand
                var _chot = ui_register(_gid + "_fold", _gx0 + 12, _y + 6, _gx0 + 44, _y + _hdrh - 6, "Collapse / expand|Folds this group down to its title (and the groups inside it), or opens it.");
                ui_chevron(_gx0 + 28, _y + _hdrh * 0.5, 6, c_white, !_gr.collapsed);
                if (_chot && ui_pressed)
                {
                    ui_take_click();
                    _gr.collapsed = !_gr.collapsed;
                    proj_dirty = true;
                }
                var _rt = string(_count) + " rule";
                if (_count != 1) { _rt += "s"; }
                if (_nsub > 0) { _rt += ", " + string(_nsub) + " group"; }
                if (_nsub > 1) { _rt += "s"; }
                // name box and count share the room left of the On toggle (at _gw0 - 532)
                draw_set_font(global.f_small);
                var _nmw = max(100, min(260, _gw0 - 532 - 10 - ceil(ui_sw(_rt)) - 10 - 48));
                var _nm = ui_textfield(_gid + "_name", _gx0 + 48, _y + 7, _nmw, 30, _gr.name, 28, "Group name|Call it what the rules do, e.g. 'Hoppers hit the hero' or 'Collecting gems'.");
                set_val(_gr, "name", _nm, _gid + "name");
                ui_text(_gx0 + 48 + _nmw + 10, _y + _hdrh * 0.5, ui_text_fit(_rt, global.f_small, _gw0 - 532 - 10 - 48 - _nmw - 10), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
                var _bx = _gx0 + _gw0 - 8;
                _bx -= 30;
                if (ui_button(_gid + "_del", _bx, _y + 7, 30, 30, "X", "Remove group|Removes the group. Its rules are kept and move out of the group. You can Undo this.", BTN_DANGER)) { _gact = _g; _gop = "del"; }
                _bx -= 36;
                if (ui_button(_gid + "_dn", _bx, _y + 7, 30, 30, "v", "Move group down|The whole group runs later.", BTN_GHOST)) { _gact = _g; _gop = "dn"; }
                _bx -= 36;
                if (ui_button(_gid + "_up", _bx, _y + 7, 30, 30, "^", "Move group up|The whole group runs earlier.", BTN_GHOST)) { _gact = _g; _gop = "up"; }
                _bx -= 86;
                if (ui_button(_gid + "_add", _bx, _y + 7, 80, 30, "+ Rule", "Add rule to this group|Adds a new rule at the end of this group.", BTN_NORMAL)) { _gact = _g; _gop = "add"; }
                _bx -= 86;
                if (ui_button(_gid + "_sub", _bx, _y + 7, 80, 30, "+ Group", "Add a group inside|Makes a new group inside this one - group your groups, e.g. 'Enemies' holding 'Bats' and 'Slimes'.", BTN_GHOST)) { _gact = _g; _gop = "sub"; }
                _bx -= 166;
                var _pn = ["In: (top level)"];
                for (var pg = 0; pg < _ngr; pg++) { array_push(_pn, "In: " + group_path(pg)); }
                var _np = ui_dropdown(_gid + "_par", _bx, _y + 7, 160, 30, _pn, group_parent_of(proj.groups, _g) + 1, "Inside group|Which group this group sits in. Its rules run with that group's, and switching that group off switches this one off too.") - 1;
                if (_np != group_parent_of(proj.groups, _g))
                {
                    if (_np >= 0 && group_inside(_np, _g)) { toast("A group cannot go inside itself or a group inside it", 1); }
                    else { _gact = _g; _gop = "par"; _gpar = _np; }
                }
                _bx -= 84;      // toggle (44) + gap + "On" (23) = 77, clear of the In: drop-down
                set_val(_gr, "enabled", ui_toggle(_gid + "_on", _bx, _y + 10, "On", _gr.enabled, "Group on / off|Switch a group off to leave its rules - and the groups inside it - out of the game while you test. They are kept, just not built."), _gid + "on");
            }
            _y += _hdrh + 10;
        }
        else
        {
            var _i = _it[1];
            var _ch = logic_card_h(proj.rules[_i]);
            if (_y + _ch >= _ly1 - 10 && _y <= _ly2 + 10)
            {
                var _ind = 0;
                if (proj.rules[_i].group >= 0) { _ind = min(16 + group_depth(proj.rules[_i].group) * 20, max(16, _cw - 800)); }   // a card needs 800 px
                var _res = logic_rule_card(proj.rules[_i], _i, _lx + _ind, _y, _cw - _ind, _anames, _snames, _gnames);
                if (_res == 1) { _del = _i; }
                if (_res == 2) { _movei = _i; _move = -1; }
                if (_res == 3) { _movei = _i; _move = 1; }
            }
            _y += _ch + 10;
        }
    }
    ui_scroll_end("logic_list", _lx, _ly1, _lx2 - 10, _ly2, _content);
    if (logic_resort)
    {
        logic_resort = false;
        logic_sort_rules();
    }

    if (_del >= 0)
    {
        undo_mark("ruledel" + string(current_time));
        array_delete(proj.rules, _del, 1);
    }
    if (_movei >= 0)
    {
        // swap with the nearest rule in the same group
        var _grp = proj.rules[_movei].group;
        var _j = _movei + _move;
        while (_j >= 0 && _j < array_length(proj.rules) && proj.rules[_j].group != _grp) { _j += _move; }
        if (_j >= 0 && _j < array_length(proj.rules))
        {
            undo_mark("rulemove" + string(current_time));
            var _tmp = proj.rules[_movei];
            proj.rules[_movei] = proj.rules[_j];
            proj.rules[_j] = _tmp;
        }
    }
    if (_gact >= 0)
    {
        if (_gop == "del")
        {
            undo_mark("grpdel" + string(current_time));
            group_delete(_gact);
        }
        if (_gop == "up" && group_sibling(_gact, -1) >= 0)
        {
            undo_mark("grpmove" + string(current_time));
            group_swap(_gact, group_sibling(_gact, -1));
        }
        if (_gop == "dn" && group_sibling(_gact, 1) >= 0)
        {
            undo_mark("grpmove" + string(current_time));
            group_swap(_gact, group_sibling(_gact, 1));
        }
        if (_gop == "par")
        {
            undo_mark("grppar" + string(current_time));
            proj.groups[_gact].parent = _gpar;
            logic_sort_rules();
        }
        if (_gop == "sub")
        {
            undo_mark("grpsub" + string(current_time));
            var _sg = group_new("Group " + string(array_length(proj.groups) + 1));
            _sg.parent = _gact;
            array_push(proj.groups, _sg);
            proj.groups[_gact].collapsed = false;
            logic_sort_rules();
        }
        if (_gop == "add")
        {
            if (array_length(proj.rules) < 100)
            {
                undo_mark("ruleadd" + string(current_time));
                var _nr2 = rule_new();
                _nr2.a = logic_find_role([0, 6], 0);
                _nr2.b = min(1, max(0, array_length(proj.actors) - 1));
                _nr2.group = _gact;
                array_push(proj.rules, _nr2);
                proj.groups[_gact].collapsed = false;
                var _op = group_parent_of(proj.groups, _gact);       // open the groups it is inside too
                var _on2 = 0;
                while (_op >= 0 && _on2 < 64)
                {
                    proj.groups[_op].collapsed = false;
                    _op = group_parent_of(proj.groups, _op);
                    _on2 += 1;
                }
                logic_sort_rules();
                logic_reveal = _nr2;
            }
            else { toast("100 rules is the limit", 1); }
        }
    }

    // ---------------- recipes ----------------
    var _px = _x2 - _rw;
    ui_panel(_px, _y1, _x2, _y2, "Quick recipes");
    var _ry = _y1 + 56;
    var _rintro = "One click adds ready-made rules. They use your first Player, enemy and Still actor.";
    ui_text_wrap(_px + 20, _ry, _rintro, global.TH.text_dim, _rw - 40, global.f_small, 1);
    draw_set_font(global.f_small);
    _ry += max(50, ceil(ui_sh_ext(_rintro, _rw - 40)) + 14);
    var _rhelp = [
        "Enemy hit|Adds 4 rules: when the player touches an enemy, lose a life, go back to the start, flash the screen and flash the player for 3 safe seconds.",
        "Pickup|Adds 3 rules: when the player touches a pickup, add 10 points, move the pickup somewhere random and play the Coin sound.",
        "Win condition|Adds a rule: when the score reaches 100, you win.",
        "Lose condition|Adds a rule: when lives run out, it's game over.",
        "Getting harder|Adds a rule: every 10 seconds the enemy speeds up.",
        "Fire sound|Adds a rule: pressing fire plays sound 2."
    ];
    for (var t = 0; t < array_length(global.TEMPLATE_NAMES); t++)
    {
        if (ui_button("logic_tpl_" + string(t), _px + 20, _ry, _rw - 40, 38, global.TEMPLATE_NAMES[t], _rhelp[t], BTN_NORMAL))
        {
            logic_add_template(t);
        }
        _ry += 46;
    }
}

// ---------------------------------------------------------------------------
// Items (Logic page, Items tab): things the player picks up and carries, and
// recipes that make an item from two others
// ---------------------------------------------------------------------------

#macro ITEM_CARD_H 132
#macro RECIPE_ROW_H 48

/// A new item. actor: the actor picked up as it (-1 = only rules give it); spr: its picture
/// (-1 = the actor's sprite); use: 0 used up, 1 kept, 2 a few uses (uses); max: the most
/// carried; start: carried when the game starts; keep_level: kept on the next level;
/// lose_life: lost when the player loses a life
function item_new(_name)
{
    return { name : _name, actor : -1, spr : -1, use : 0, uses : 3, max : 9, start : 0, keep_level : true, lose_life : false };
}

/// A new recipe: item a + item b make n of item out (-1 = not picked yet); keep_a / keep_b: that one is kept
function recipe_new()
{
    return { a : -1, b : -1, out : -1, keep_a : false, keep_b : false, n : 1 };
}

function item_names()
{
    var _n = [];
    for (var i = 0; i < array_length(proj.items); i++) { array_push(_n, proj.items[i].name); }
    return _n;
}

/// A name no item has yet: ITEM1, ITEM2, ...
function item_free_name()
{
    var _k = array_length(proj.items) + 1;
    var _taken = true;
    while (_taken)
    {
        _taken = false;
        for (var i = 0; i < array_length(proj.items); i++)
        {
            if (proj.items[i].name == "ITEM" + string(_k)) { _taken = true; }
        }
        if (_taken) { _k += 1; }
    }
    return "ITEM" + string(_k);
}

/// A true / false from a file (_def when it is missing)
function item_bool(_v, _def)
{
    if (is_bool(_v)) { return _v; }
    if (is_numeric(_v)) { return (_v != 0); }
    return _def;
}

/// An item number from a file: -1 .. _n - 1
function item_ref(_v, _n)
{
    if (!is_numeric(_v)) { return -1; }
    var _k = floor(_v);
    if (_k < 0 || _k >= _n) { return -1; }
    return _k;
}

/// Loader: items and recipes (older files have none)
function items_fix(_p, _raw)
{
    var _its = [];
    var _ri = _raw[$ "items"];
    if (is_array(_ri))
    {
        for (var i = 0; i < min(ITEM_MAX, array_length(_ri)); i++)
        {
            var _src = _ri[i];
            var _it = item_new("ITEM" + string(i + 1));
            if (is_struct(_src))
            {
                if (is_string(_src[$ "name"]) && _src[$ "name"] != "") { _it.name = string_upper(string_copy(_src[$ "name"], 1, ITEM_NAME_LEN)); }
                _it.actor = item_ref(_src[$ "actor"], array_length(_p.actors));
                if (is_numeric(_src[$ "spr"])) { _it.spr = clamp(floor(_src[$ "spr"]), -1, SPR_COUNT - 1); }
                if (is_numeric(_src[$ "use"])) { _it.use = clamp(floor(_src[$ "use"]), 0, 2); }
                if (is_numeric(_src[$ "uses"])) { _it.uses = clamp(floor(_src[$ "uses"]), 1, ITEM_CARRY_MAX); }
                if (is_numeric(_src[$ "max"])) { _it.max = clamp(floor(_src[$ "max"]), 1, ITEM_CARRY_MAX); }
                if (is_numeric(_src[$ "start"])) { _it.start = clamp(floor(_src[$ "start"]), 0, _it.max); }
                _it.keep_level = item_bool(_src[$ "keep_level"], true);
                _it.lose_life = item_bool(_src[$ "lose_life"], false);
            }
            array_push(_its, _it);
        }
    }
    _p.items = _its;
    var _ni = array_length(_its);
    var _rcs = [];
    var _rr = _raw[$ "recipes"];
    if (is_array(_rr))
    {
        for (var r = 0; r < min(RECIPE_MAX, array_length(_rr)); r++)
        {
            var _sr = _rr[r];
            var _rc = recipe_new();
            if (is_struct(_sr))
            {
                _rc.a = item_ref(_sr[$ "a"], _ni);
                _rc.b = item_ref(_sr[$ "b"], _ni);
                _rc.out = item_ref(_sr[$ "out"], _ni);
                _rc.keep_a = item_bool(_sr[$ "keep_a"], false);
                _rc.keep_b = item_bool(_sr[$ "keep_b"], false);
                if (is_numeric(_sr[$ "n"])) { _rc.n = clamp(floor(_sr[$ "n"]), 1, 9); }
            }
            array_push(_rcs, _rc);
        }
    }
    _p.recipes = _rcs;
}

/// Removes item _k: recipes that used it go, the others are renumbered
function item_delete(_k)
{
    array_delete(proj.items, _k, 1);
    for (var r = array_length(proj.recipes) - 1; r >= 0; r--)
    {
        var _rc = proj.recipes[r];
        if (_rc.a == _k || _rc.b == _k || _rc.out == _k)
        {
            array_delete(proj.recipes, r, 1);
            continue;
        }
        if (_rc.a > _k) { _rc.a -= 1; }
        if (_rc.b > _k) { _rc.b -= 1; }
        if (_rc.out > _k) { _rc.out -= 1; }
    }
}

/// The sprite item _it shows as: its picture, or its actor's sprite (-1 = none)
function item_sprite(_it)
{
    if (_it.spr >= 0) { return _it.spr; }
    if (_it.actor >= 0 && _it.actor < array_length(proj.actors)) { return actor_preview_sprite(proj.actors[_it.actor]); }
    return -1;
}

/// Draws item _k's picture fitted into the _box-pixel square at (_x, _y) ("?" when it has none)
function item_icon_draw(_k, _x, _y, _box, _alpha)
{
    ui_inset(_x, _y, _x + _box, _y + _box, 8);
    if (_k < 0 || _k >= array_length(proj.items)) { return; }
    var _s = item_sprite(proj.items[_k]);
    if (_s < 0 || _s >= SPR_COUNT)
    {
        ui_text(_x + _box * 0.5, _y + _box * 0.5, "?", global.TH.text_faint, fa_center, fa_middle, global.f_bold, _alpha);
        return;
    }
    var _sp = proj.sprites[_s];
    var _sc = (_box - 8) / max(_sp.w, _sp.h);
    if (_sc >= 1) { _sc = floor(_sc); }
    draw_sprite_amiga(_s, floor(_x + (_box - _sp.w * _sc) * 0.5), floor(_y + (_box - _sp.h * _sc) * 0.5), _sc, _alpha);
}

/// The Rules / Items tabs at the top of the Logic page's left panel
function logic_tabs(_x1, _y1, _x2)
{
    if (ui_tab("logic_tab_rules", _x1 + 16, _y1 + 8, 84, 30, "Rules", logic_tab == 0, "Rules|WHEN something happens, DO something: the rules that make your game work."))
    {
        logic_tab = 0;
    }
    if (ui_tab("logic_tab_items", _x1 + 106, _y1 + 8, 84, 30, "Items", logic_tab == 1, "Items|Things the player picks up and carries - keys, coins, a lantern - and recipes that make one item from two others."))
    {
        logic_tab = 1;
    }
    draw_line_colour(_x1 + 14, _y1 + 44, _x2 - 14, _y1 + 44, global.TH.panel_edge, global.TH.panel_edge);
}

/// A recipe slot: the item's picture and a drop-down, and a drop target for an item dragged
/// from the list. Sets _rc[$ _key]; returns the x just after it.
function logic_recipe_slot(_id, _rc, _key, _x, _y, _names, _help)
{
    var _x2 = _x + 42 + 150;
    var _k = _rc[$ _key];
    item_icon_draw(_k, _x, _y - 1, 32, 1);
    var _nk = ui_dropdown(_id, _x + 40, _y, 152, 30, _names, _k + 1, _help) - 1;
    set_val(_rc, _key, _nk, _id);
    if (logic_drag_item >= 0 && ui_hit(_x - 4, _y - 5, _x2 + 4, _y + 35))
    {
        ui_rrect_line(_x - 4, _y - 5, _x2 + 4, _y + 35, 10, global.TH.accent, 1, 2);
        if (ui_released)
        {
            set_val(_rc, _key, logic_drag_item, _id + "drop" + string(current_time));
            logic_drag_item = -1;
        }
    }
    return _x2;
}

/// The Items tab: the item cards, then the recipes
function logic_items_draw(_x1, _y1, _x2, _y2)
{
    var _ni = array_length(proj.items);
    var _nrc = array_length(proj.recipes);
    var _sum = string(_ni) + " item";
    if (_ni != 1) { _sum += "s"; }
    _sum += ", " + string(_nrc) + " recipe";
    if (_nrc != 1) { _sum += "s"; }
    _sum += ". Drag an item's picture onto a recipe slot.";
    ui_text(_x1 + 200, _y1 + 15, ui_text_fit(_sum, global.f_small, _x2 - 170 - _x1 - 200), global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
    if (ui_button("item_add", _x2 - 150, _y1 + 8, 136, 30, "+ Add item", "Add item|A new thing the player can carry. Pick the actor that is picked up as it, and what using it does: used up (a key), kept (a lantern) or a few uses (a torch). Up to " + string(ITEM_MAX) + " items.", BTN_ACCENT))
    {
        if (_ni < ITEM_MAX)
        {
            undo_mark("itemadd" + string(current_time));
            array_push(proj.items, item_new(item_free_name()));
        }
        else { toast(string(ITEM_MAX) + " items is the limit", 1); }
    }
    _ni = array_length(proj.items);

    var _lx = _x1 + 14;
    var _ly1 = _y1 + 52;
    var _ly2 = _y2 - 12;
    var _cw = _x2 - 14 - _lx - 10;
    var _content = 10;
    if (_ni == 0) { _content += 70; }
    else { _content += _ni * (ITEM_CARD_H + 10); }
    _content += 50;
    if (_nrc == 0) { _content += 50; }
    else { _content += _nrc * (RECIPE_ROW_H + 8); }
    _content += 20;

    var _anames = ["(none - rules give it)"];
    for (var a = 0; a < array_length(proj.actors); a++) { array_push(_anames, proj.actors[a].name); }
    var _snames = ["(the actor's sprite)"];
    var _sl = sprite_names();
    for (var s = 0; s < array_length(_sl); s++) { array_push(_snames, _sl[s]); }
    var _inames = ["(pick an item)"];
    var _il = item_names();
    for (var n = 0; n < array_length(_il); n++) { array_push(_inames, _il[n]); }

    var _off = ui_scroll_begin("item_list", _lx, _ly1, _x2 - 10, _ly2, _content);
    var _y = _ly1 + 10 - _off;
    var _del = -1;
    if (_ni == 0)
    {
        ui_text_wrap(_lx + 20, _y + 10, "No items yet. Items are things the player picks up and carries - a key for a door, coins for a shop, a lantern for a dark cave. Press '+ Add item', or pick an idea on the right.", global.TH.text_dim, _cw - 40, global.f_body, 1);
        _y += 70;
    }
    for (var i = 0; i < _ni; i++)
    {
        if (_y + ITEM_CARD_H < _ly1 - 10 || _y > _ly2 + 10)
        {
            _y += ITEM_CARD_H + 10;
            continue;
        }
        var _it = proj.items[i];
        var _iid = "item_" + string(i);
        var _cx = _lx;
        ui_rrect(_cx, _y, _cx + _cw, _y + ITEM_CARD_H, 12, global.TH.btn_top, global.TH.panel_bot, 0.9);
        ui_rrect_line(_cx, _y, _cx + _cw, _y + ITEM_CARD_H, 12, global.TH.panel_edge, 0.6, 1);

        // its picture: drag it onto a recipe slot
        var _ix = _cx + 14;
        var _iy = _y + 14;
        var _ihot = ui_register(_iid + "_icon", _ix, _iy, _ix + 56, _iy + 56, "Drag me|Drag this item's picture onto a recipe slot below to put it in the recipe.");
        item_icon_draw(i, _ix, _iy, 56, 1);
        if (_ihot || logic_drag_item == i) { ui_rrect_line(_ix, _iy, _ix + 56, _iy + 56, 8, global.TH.accent, 0.9, 1); }
        if (_ihot && ui_pressed)
        {
            ui_take_click();
            logic_drag_item = i;
        }

        // name, the actor picked up as it, its picture
        var _fx = _cx + 84;
        var _ry = _y + 10;
        var _wx = logic_word(_fx, _ry, "Name");
        set_val(_it, "name", string_upper(ui_textfield(_iid + "_name", _wx, _ry, 130, 30, _it.name, ITEM_NAME_LEN, "Item name|Up to " + string(ITEM_NAME_LEN) + " letters - it is shown in the game's space bar menu, e.g. KEY, COINS, LANTERN.")), _iid + "name");
        _wx = logic_word(_wx + 140, _ry, "found as");
        set_val(_it, "actor", ui_dropdown(_iid + "_actor", _wx, _ry, 200, 30, _anames, _it.actor + 1, "Found as|The actor the player picks up as this item: touching it puts the item in the player's pockets and hides the actor. '(none)' = only rules give it out.") - 1, _iid + "actor");
        _wx = logic_word(_wx + 210, _ry, "picture");
        set_val(_it, "spr", ui_dropdown(_iid + "_spr", _wx, _ry, 220, 30, _snames, clamp(_it.spr + 1, 0, array_length(_snames) - 1), "Picture|The sprite shown for this item in recipes and the game's menus. '(the actor's sprite)' uses the look of the actor it is found as.") - 1, _iid + "spr");
        if (ui_button(_iid + "_del", _cx + _cw - 40, _y + 10, 30, 30, "X", "Delete item|Removes this item, and the recipes that use it. You can Undo this.", BTN_DANGER)) { _del = i; }

        // what using it does, how many are carried
        _ry = _y + 50;
        _wx = logic_word(_fx, _ry, "When used");
        set_val(_it, "use", ui_dropdown(_iid + "_use", _wx, _ry, 150, 30, global.ITEM_USE_NAMES, _it.use, "When used|What happens to the item when a rule uses it: Used up (a key opens one door), Kept (a lantern, a pass card) or A few uses (a torch that burns out after some uses)."), _iid + "use");
        _wx += 160;
        if (_it.use == 2)
        {
            set_val(_it, "uses", ui_stepper(_iid + "_uses", _wx, _ry, 100, _it.uses, 1, ITEM_CARRY_MAX, "Uses|How many times one of these can be used before it is gone."), _iid + "uses");
            _wx = logic_word(_wx + 108, _ry, "uses");
        }
        _wx = logic_word(_wx + 8, _ry, "carry up to");
        set_val(_it, "max", ui_stepper(_iid + "_max", _wx, _ry, 100, _it.max, 1, ITEM_CARRY_MAX, "Carry up to|The most of this item the player can hold. Picking up more when full leaves it where it is. Hold Shift for steps of 10."), _iid + "max");
        _wx = logic_word(_wx + 108, _ry, "start with");
        set_val(_it, "start", ui_stepper(_iid + "_start", _wx, _ry, 100, min(_it.start, _it.max), 0, _it.max, "Start with|How many the player has when the game starts - a sword from the beginning, three bombs."), _iid + "start");
        if (_it.start > _it.max) { _it.start = _it.max; }

        // what happens to it between levels and lives
        _ry = _y + 92;
        set_val(_it, "keep_level", ui_toggle(_iid + "_keep", _fx, _ry + 3, "Kept on the next level", _it.keep_level, "Kept on the next level|On: the player still has it when the next level starts. Off: it is gone at the end of the level (a key for this level's door)."), _iid + "keep");
        draw_set_font(global.f_body);
        var _tx = _fx + 54 + ceil(ui_sw("Kept on the next level")) + 24;
        set_val(_it, "lose_life", ui_toggle(_iid + "_lose", _tx, _ry + 3, "Lost with a life", _it.lose_life, "Lost with a life|On: the player drops all of this item when they lose a life. Off: they keep it."), _iid + "lose");
        _y += ITEM_CARD_H + 10;
    }
    if (_del >= 0)
    {
        undo_mark("itemdel" + string(current_time));
        item_delete(_del);
        logic_drag_item = -1;
        _ni = array_length(proj.items);
        _nrc = array_length(proj.recipes);
    }

    // recipes
    ui_heading(_lx + 4, _y + 14, "Recipes - two items make another");
    if (ui_button("recipe_add", _lx + _cw - 150, _y + 4, 140, 30, "+ Add recipe", "Add recipe|Two items make a third: a stick and a cloth make a torch. Tick 'kept' for an ingredient that is not used up (a knife). What a recipe makes can go into another recipe. Up to " + string(RECIPE_MAX) + " recipes.", BTN_NORMAL))
    {
        if (_nrc < RECIPE_MAX)
        {
            undo_mark("recipeadd" + string(current_time));
            array_push(proj.recipes, recipe_new());
        }
        else { toast(string(RECIPE_MAX) + " recipes is the limit", 1); }
    }
    _nrc = array_length(proj.recipes);
    _y += 50;
    if (_nrc == 0)
    {
        ui_text_wrap(_lx + 20, _y, "No recipes yet. A recipe makes one item from two others - '+ Add recipe', then drag items onto its slots.", global.TH.text_dim, _cw - 40, global.f_body, 1);
    }
    var _rdel = -1;
    for (var r = 0; r < _nrc; r++)
    {
        var _rc = proj.recipes[r];
        var _rid = "recipe_" + string(r);
        if (_y + RECIPE_ROW_H >= _ly1 - 10 && _y <= _ly2 + 10)
        {
            ui_rrect(_lx, _y, _lx + _cw, _y + RECIPE_ROW_H, 10, global.TH.btn_top, global.TH.panel_bot, 0.9);
            ui_rrect_line(_lx, _y, _lx + _cw, _y + RECIPE_ROW_H, 10, global.TH.panel_edge, 0.6, 1);
            var _sy = _y + 9;
            var _rx = logic_recipe_slot(_rid + "_a", _rc, "a", _lx + 12, _sy, _inames, "First ingredient|One of the two items the recipe takes. Drag an item's picture here, or pick it.");
            set_val(_rc, "keep_a", ui_toggle(_rid + "_ka", _rx + 10, _sy + 3, "kept", _rc.keep_a, "Kept|On: making the recipe does not use this ingredient up (a knife, a hammer)."), _rid + "ka");
            _rx = logic_word(_rx + 118, _sy, "+");
            _rx = logic_recipe_slot(_rid + "_b", _rc, "b", _rx, _sy, _inames, "Second ingredient|The other item the recipe takes. Drag an item's picture here, or pick it.");
            set_val(_rc, "keep_b", ui_toggle(_rid + "_kb", _rx + 10, _sy + 3, "kept", _rc.keep_b, "Kept|On: making the recipe does not use this ingredient up."), _rid + "kb");
            _rx = logic_word(_rx + 118, _sy, "make");
            set_val(_rc, "n", ui_stepper(_rid + "_n", _rx, _sy, 90, _rc.n, 1, 9, "How many|How many of the new item one go makes."), _rid + "n");
            logic_recipe_slot(_rid + "_out", _rc, "out", _rx + 100, _sy, _inames, "What it makes|The item the player gets. It can be an ingredient of another recipe too.");
            if (ui_button(_rid + "_del", _lx + _cw - 40, _sy, 30, 30, "X", "Delete recipe|Removes this recipe (its items stay). You can Undo this.", BTN_DANGER)) { _rdel = r; }
        }
        _y += RECIPE_ROW_H + 8;
    }
    if (_rdel >= 0)
    {
        undo_mark("recipedel" + string(current_time));
        array_delete(proj.recipes, _rdel, 1);
    }
    ui_scroll_end("item_list", _lx, _ly1, _x2 - 10, _ly2, _content);

    // the item being dragged follows the mouse
    if (logic_drag_item >= 0 && logic_drag_item < array_length(proj.items))
    {
        item_icon_draw(logic_drag_item, ui_mx - 20, ui_my - 20, 40, 0.85);
    }
    if (!ui_held) { logic_drag_item = -1; }
}

/// Item ideas (right panel on the Items tab): one click adds a ready-made item
function logic_item_idea(_t)
{
    var _need = 1;
    if (_t == 5) { _need = 3; }
    if (array_length(proj.items) + _need > ITEM_MAX)
    {
        toast(string(ITEM_MAX) + " items is the limit", 1);
        return;
    }
    if (_t == 5 && array_length(proj.recipes) >= RECIPE_MAX)
    {
        toast(string(RECIPE_MAX) + " recipes is the limit", 1);
        return;
    }
    undo_mark("itemidea" + string(current_time));
    var _it;
    switch (_t)
    {
        case 0:
            _it = item_new("KEY");
            array_push(proj.items, _it);
            break;
        case 1:
            _it = item_new("LANTERN");
            _it.use = 1;
            _it.max = 1;
            array_push(proj.items, _it);
            break;
        case 2:
            _it = item_new("TORCH");
            _it.use = 2;
            _it.uses = 3;
            _it.max = 3;
            array_push(proj.items, _it);
            break;
        case 3:
            _it = item_new("COINS");
            _it.max = 99;
            array_push(proj.items, _it);
            break;
        case 4:
            _it = item_new("SWORD");
            _it.use = 1;
            _it.max = 1;
            _it.start = 1;
            array_push(proj.items, _it);
            break;
        case 5:
            var _k = array_length(proj.items);
            array_push(proj.items, item_new("STICK"));
            array_push(proj.items, item_new("CLOTH"));
            _it = item_new("TORCH");
            _it.use = 2;
            _it.uses = 3;
            _it.max = 3;
            array_push(proj.items, _it);
            var _rc = recipe_new();
            _rc.a = _k;
            _rc.b = _k + 1;
            _rc.out = _k + 2;
            array_push(proj.recipes, _rc);
            break;
    }
}

/// The right panel on the Items tab: ready-made items
function logic_item_ideas_draw(_px, _y1, _x2, _y2)
{
    var _rw = _x2 - _px;
    ui_panel(_px, _y1, _x2, _y2, "Item ideas");
    var _ry = _y1 + 56;
    var _intro = "Items are things the player carries. Touching an item's actor picks it up; rules check for an item, or use it, with IF lines.";
    ui_text_wrap(_px + 20, _ry, _intro, global.TH.text_dim, _rw - 40, global.f_small, 1);
    draw_set_font(global.f_small);
    _ry += max(50, ceil(ui_sh_ext(_intro, _rw - 40)) + 14);
    var _names = ["Key (used up)", "Lantern (kept)", "Torch (3 uses)", "Coins (carry 99)", "Sword (start with one)", "Stick + cloth make a torch"];
    var _help = [
        "Key|Adds a KEY that is used up when a rule uses it - one key, one door.",
        "Lantern|Adds a LANTERN that is kept when used - the player only needs one.",
        "Torch|Adds a TORCH that burns out after 3 uses.",
        "Coins|Adds COINS - the player can carry up to 99, to spend in a shop.",
        "Sword|Adds a SWORD the player has from the start and keeps.",
        "Stick + cloth|Adds a STICK, a CLOTH and a TORCH, and a recipe: a stick and a cloth make a torch."
    ];
    for (var t = 0; t < array_length(_names); t++)
    {
        if (ui_button("item_idea_" + string(t), _px + 20, _ry, _rw - 40, 38, _names[t], _help[t], BTN_NORMAL))
        {
            logic_item_idea(t);
        }
        _ry += 46;
    }
}
