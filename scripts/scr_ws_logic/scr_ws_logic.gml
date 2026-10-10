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
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _en; _r.act = 1; array_push(proj.rules, _r);
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _en; _r.act = 4; _r.target = _pl; array_push(proj.rules, _r);
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _en; _r.act = 3; array_push(proj.rules, _r);
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _en; _r.act = 16; _r.target = _pl; array_push(proj.rules, _r);
            break;
        case 1:
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _pk; _r.act = 0; _r.value = 10; array_push(proj.rules, _r);
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _pk; _r.act = 5; _r.target = _pk; array_push(proj.rules, _r);
            _r = rule_new(); _r.when = 0; _r.a = _pl; _r.b = _pk; _r.act = 2; _r.value = 0; array_push(proj.rules, _r);
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

function sfx_names()
{
    var _n = [];
    for (var i = 0; i < 8; i++) { array_push(_n, string(i + 1) + ": " + proj.sfx[i].name); }
    return _n;
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
    }
    var _tn = "?";
    if (_r.target < _na) { _tn = _names[_r.target]; }
    _s += ", ";
    switch (_r.act)
    {
        case 0: _s += "add " + string(_r.value) + " to the score"; break;
        case 1: _s += "lose a life"; break;
        case 2: _s += "play sound '" + proj.sfx[clamp(_r.value, 0, 7)].name + "'"; break;
        case 3: _s += "flash the screen"; break;
        case 4: _s += "send " + _tn + " back to its start"; break;
        case 5: _s += "move " + _tn + " to a random spot"; break;
        case 6: _s += "hide " + _tn; break;
        case 7: _s += "show " + _tn; break;
        case 8: _s += "make the background colour " + string(clamp(_r.value, 0, pal_count() - 1)); break;
        case 9: _s += "it's game over"; break;
        case 10: _s += "the player wins"; break;
        case 11: _s += "speed up " + _tn; break;
        case 12: _s += "slow down " + _tn; break;
        case 13: _s += "add a life"; break;
        case 14:
            var _vn = "?";
            if (_r.value < _na) { _vn = _names[_r.value]; }
            _s += "move " + _tn + " to " + _vn;
            break;
        case 15: _s += "show " + _tn + " for a moment"; break;
        case 16: _s += "make " + _tn + " safe for a while (it flashes)"; break;
        case 17: _s += "count one towards the " + string_lower(proj.goal_label) + " goal"; break;
        case 18: _s += "play the music '" + logic_song_name(_r.value) + "' from the start"; break;
        case 19: _s += "stop the music"; break;
    }
    return _s + ".";
}

// ---------------------------------------------------------------------------
// Groups: named, collapsible sets of rules. proj.rules stays in run order and
// is kept sorted by group (rules outside any group first, then each group in
// order), so what you see top to bottom is exactly the order the Amiga checks.
// ---------------------------------------------------------------------------

function group_new(_name)
{
    return { name : _name, collapsed : false, enabled : true };
}

function group_colour(_g)
{
    return make_colour_hsv((_g * 47 + 140) mod 255, 150, 230);
}

/// Stable sort of the rules by group (-1 = no group comes first)
function logic_sort_rules()
{
    var _out = [];
    var _ng = array_length(proj.groups);
    for (var g = -1; g < _ng; g++)
    {
        for (var i = 0; i < array_length(proj.rules); i++)
        {
            if (proj.rules[i].group == g) { array_push(_out, proj.rules[i]); }
        }
    }
    proj.rules = _out;
}

function group_names()
{
    var _n = ["(no group)"];
    for (var g = 0; g < array_length(proj.groups); g++) { array_push(_n, proj.groups[g].name); }
    return _n;
}

function group_delete(_g)
{
    for (var i = 0; i < array_length(proj.rules); i++)
    {
        var _r = proj.rules[i];
        if (_r.group == _g) { _r.group = -1; }
        else { if (_r.group > _g) { _r.group -= 1; } }
    }
    array_delete(proj.groups, _g, 1);
    logic_sort_rules();
}

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
    logic_sort_rules();
}

/// Is rule _r switched off by its group?
function rule_disabled(_r)
{
    if (_r.group < 0 || _r.group >= array_length(proj.groups)) { return false; }
    return !proj.groups[_r.group].enabled;
}

/// One WHEN / DO card. Returns 0, or 1 = delete, 2 = up, 3 = down.
function logic_rule_card(_r, i, _cx, _cy, _cw, _anames, _snames, _gnames)
{
    var _res = 0;
    var _cardh = 128;
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
    set_val(_r, "when", ui_dropdown(_rid + "_when", _wx, _wy, 210, 30, global.WHEN_NAMES, _r.when, "WHEN|The thing that has to happen for this rule to fire."), _rid + "w");
    _wx += 220;
    switch (_r.when)
    {
        case 0:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, 150, 30, _anames, _r.a, "First actor|The actor that does the touching."), _rid + "a");
            ui_text(_wx + 158, _wy + 15, "touches", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
            set_val(_r, "b", ui_dropdown(_rid + "_b", _wx + 222, _wy, 150, 30, _anames, _r.b, "Second actor|The actor being touched. Pick the same actor twice for 'touches anything'."), _rid + "b");
            break;
        case 2:
            ui_text(_wx, _wy + 15, "every", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx + 48, _wy, 120, _r.n, 1, 60, "Seconds|How many seconds between each time this rule fires."), _rid + "n");
            ui_text(_wx + 176, _wy + 15, "seconds", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
            break;
        case 6:
            set_val(_r, "a", ui_dropdown(_rid + "_a", _wx, _wy, 150, 30, _anames, _r.a, "Which actor|The actor whose jump fires this rule - great for a jump sound."), _rid + "a");
            ui_text(_wx + 158, _wy + 15, "jumps", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
            break;
        case 3:
            set_val(_r, "n", ui_stepper(_rid + "_n", _wx, _wy, 150, _r.n, 1, 9999, "Score target|The rule fires once when the score reaches this number. Hold Shift for steps of 10."), _rid + "n");
            ui_text(_wx + 158, _wy + 15, "points", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
            break;
    }

    // DO row
    var _dx = _cx + 46;
    var _dy = _cy + 50;
    ui_rrect(_dx, _dy + 4, _dx + 56, _dy + 26, 11, global.TH.accent, global.TH.accent_dark, 1);
    ui_text(_dx + 28, _dy + 15, "DO", c_white, fa_center, fa_middle, global.f_small, 1);
    _dx += 66;
    set_val(_r, "act", ui_dropdown(_rid + "_act", _dx, _dy, 210, 30, global.DO_NAMES, _r.act, "DO|What happens when the WHEN part is true."), _rid + "act");
    _dx += 220;
    var _act = _r.act;
    if (_act == 4 || _act == 5 || _act == 6 || _act == 7 || _act == 11 || _act == 12 || _act == 14 || _act == 15 || _act == 16)
    {
        set_val(_r, "target", ui_dropdown(_rid + "_t", _dx, _dy, 150, 30, _anames, _r.target, "Which actor|The actor this action changes."), _rid + "t");
        _dx += 160;
    }
    if (_act == 0)
    {
        set_val(_r, "value", ui_stepper(_rid + "_v", _dx, _dy, 150, _r.value, 1, 9999, "Points|How many points to add. Hold Shift for steps of 10."), _rid + "v");
        ui_text(_dx + 158, _dy + 15, "points", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
    }
    if (_act == 2)
    {
        set_val(_r, "value", ui_dropdown(_rid + "_snd", _dx, _dy, 180, 30, _snames, clamp(_r.value, 0, 7), "Sound|Which of your 8 sound effects to play. Design them on the Sound page."), _rid + "snd");
        if (ui_button(_rid + "_play", _dx + 188, _dy, 60, 30, "Play", "Preview|Plays this sound so you can hear it.", BTN_GHOST))
        {
            sfx_preview_play(proj.sfx[clamp(_r.value, 0, 7)]);
        }
    }
    if (_act == 14)
    {
        ui_text(_dx, _dy + 15, "to", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
        set_val(_r, "value", ui_dropdown(_rid + "_to", _dx + 24, _dy, 150, 30, _anames, clamp(_r.value, 0, max(0, array_length(proj.actors) - 1)), "To which actor|The first actor jumps to where this one is - drop a gem from a moving cloud, or respawn an enemy at a portal."), _rid + "to");
    }
    if (_act == 18)
    {
        var _mnames = logic_song_names();
        if (array_length(_mnames) > 0)
        {
            set_val(_r, "value", ui_dropdown(_rid + "_song", _dx, _dy, 200, 30, _mnames, clamp(_r.value, 0, array_length(_mnames) - 1), "Song|Which song to play. It starts from the beginning, and sound effects still play over it. Make songs on the Music page."), _rid + "song");
        }
        else
        {
            ui_text(_dx, _dy + 15, "No songs yet - make one on the Music page", global.TH.warn, fa_left, fa_middle, global.f_body, 1);
        }
    }
    if (_act == 8)
    {
        set_val(_r, "value", ui_colour_drop(_rid + "_col", _dx, _dy, 180, 30, clamp(_r.value, 0, pal_count() - 1), "Colour|The backdrop palette colour that colour 0 (the background and border) changes to."), _rid + "col");
    }

    // sentence, group and tools
    var _gw = 170;
    var _gx = _cx + _cw - 48 - _gw;
    ui_text(_cx + 46, _cy + 104, ui_text_fit(logic_sentence(_r), global.f_small, _gx - _cx - 56), global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
    var _ng = ui_dropdown(_rid + "_grp", _gx, _cy + 90, _gw, 28, _gnames, _r.group + 1, "Group|Move this rule into a group. Groups keep related rules together and can be collapsed or switched off.") - 1;
    if (_ng != _r.group)
    {
        undo_mark("rulegrp" + string(current_time));
        _r.group = _ng;
        logic_resort = true;
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
    ui_panel(_x1, _y1, _lx2, _y2, "Rules");
    var _nr = array_length(proj.rules);
    var _ngr = array_length(proj.groups);
    ui_text(_x1 + 100, _y1 + 15, string(_nr) + " rule(s) in " + string(_ngr) + " group(s). Checked every frame, top to bottom.", global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
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
    if (ui_button("logic_addgroup", _lx2 - 296, _y1 + 8, 136, 30, "+ Add group", "Add group|Makes a new named group. Put rules in it with the Group drop-down on each rule, collapse it to tidy up, or switch it off to test without those rules.", BTN_NORMAL))
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
    var _cardh = 128;
    var _hdrh = 44;
    var _anames = actor_names();
    var _snames = sfx_names();
    var _gnames = group_names();
    var _cw = _lx2 - 14 - _lx - 10;

    // layout: [kind, index] with kind 0 = rule, 1 = group header
    var _items = [];
    for (var i0 = 0; i0 < _nr; i0++)
    {
        if (proj.rules[i0].group < 0) { array_push(_items, [0, i0]); }
    }
    for (var g = 0; g < _ngr; g++)
    {
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
        if (_items[k][0] == 0) { _content += _cardh + 10; }
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
                if (_ry2 + _cardh + 10 > _cur + _view) { _cur = _ry2 + _cardh + 10 - _view; }
                ds_map_replace(ui_scroll, "logic_list", max(0, _cur));
                break;
            }
            if (_items[k3][0] == 0) { _ry2 += _cardh + 10; }
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
    var _y = _ly1 + 10 - _off;
    for (var k2 = 0; k2 < array_length(_items); k2++)
    {
        var _it = _items[k2];
        if (_it[0] == 1)
        {
            var _g = _it[1];
            var _gr = proj.groups[_g];
            if (_y + _hdrh >= _ly1 - 10 && _y <= _ly2 + 10)
            {
                var _gid = "grp_" + string(_g);
                var _count = 0;
                for (var c = 0; c < _nr; c++)
                {
                    if (proj.rules[c].group == _g) { _count += 1; }
                }
                var _gcol = group_colour(_g);
                var _ga = 0.95;
                if (!_gr.enabled) { _ga = 0.5; }
                ui_rrect(_lx, _y, _lx + _cw, _y + _hdrh, 10, merge_colour(global.TH.btn_hot_top, _gcol, 0.18), global.TH.btn_bot, _ga);
                ui_rrect(_lx, _y, _lx + 8, _y + _hdrh, 4, _gcol, _gcol, 1);
                ui_rrect_line(_lx, _y, _lx + _cw, _y + _hdrh, 10, _gcol, 0.6, 1);
                // collapse / expand
                var _chot = ui_register(_gid + "_fold", _lx + 12, _y + 6, _lx + 44, _y + _hdrh - 6, "Collapse / expand|Folds this group down to its title, or opens it.");
                ui_chevron(_lx + 28, _y + _hdrh * 0.5, 6, c_white, !_gr.collapsed);
                if (_chot && ui_pressed)
                {
                    ui_take_click();
                    _gr.collapsed = !_gr.collapsed;
                    proj_dirty = true;
                }
                var _nmw = max(120, min(300, _cw - 470));
                var _nm = ui_textfield(_gid + "_name", _lx + 48, _y + 7, _nmw, 30, _gr.name, 28, "Group name|Call it what the rules do, e.g. 'Hoppers hit the hero' or 'Collecting gems'.");
                set_val(_gr, "name", _nm, _gid + "name");
                var _rt = string(_count) + " rule";
                if (_count != 1) { _rt += "s"; }
                ui_text(_lx + 48 + _nmw + 12, _y + _hdrh * 0.5, _rt, global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
                var _bx = _lx + _cw - 8;
                _bx -= 30;
                if (ui_button(_gid + "_del", _bx, _y + 7, 30, 30, "X", "Remove group|Removes the group. Its rules are kept and move out of the group. You can Undo this.", BTN_DANGER)) { _gact = _g; _gop = "del"; }
                _bx -= 36;
                if (ui_button(_gid + "_dn", _bx, _y + 7, 30, 30, "v", "Move group down|The whole group runs later.", BTN_GHOST)) { _gact = _g; _gop = "dn"; }
                _bx -= 36;
                if (ui_button(_gid + "_up", _bx, _y + 7, 30, 30, "^", "Move group up|The whole group runs earlier.", BTN_GHOST)) { _gact = _g; _gop = "up"; }
                _bx -= 86;
                if (ui_button(_gid + "_add", _bx, _y + 7, 80, 30, "+ Rule", "Add rule to this group|Adds a new rule at the end of this group.", BTN_NORMAL)) { _gact = _g; _gop = "add"; }
                _bx -= 110;
                set_val(_gr, "enabled", ui_toggle(_gid + "_on", _bx, _y + 10, "On", _gr.enabled, "Group on / off|Switch a group off to leave its rules out of the game while you test - they are kept, just not built."), _gid + "on");
            }
            _y += _hdrh + 10;
        }
        else
        {
            var _i = _it[1];
            if (_y + _cardh >= _ly1 - 10 && _y <= _ly2 + 10)
            {
                var _ind = 0;
                if (proj.rules[_i].group >= 0) { _ind = 16; }
                var _res = logic_rule_card(proj.rules[_i], _i, _lx + _ind, _y, _cw - _ind, _anames, _snames, _gnames);
                if (_res == 1) { _del = _i; }
                if (_res == 2) { _movei = _i; _move = -1; }
                if (_res == 3) { _movei = _i; _move = 1; }
            }
            _y += _cardh + 10;
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
        if (_gop == "up" && _gact > 0)
        {
            undo_mark("grpmove" + string(current_time));
            group_swap(_gact, _gact - 1);
        }
        if (_gop == "dn" && _gact < array_length(proj.groups) - 1)
        {
            undo_mark("grpmove" + string(current_time));
            group_swap(_gact, _gact + 1);
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
    ui_text_wrap(_px + 20, _ry, "One click adds ready-made rules. They use your first Player, enemy and Still actor.", global.TH.text_dim, _rw - 40, global.f_small, 1);
    _ry += 50;
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
