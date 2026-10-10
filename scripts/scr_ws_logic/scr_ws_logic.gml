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
    toast("Rules added - check the actors are the ones you meant", 0);
}

function sfx_names()
{
    var _n = [];
    for (var i = 0; i < 8; i++) { array_push(_n, string(i + 1) + ": " + proj.sfx[i].name); }
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
    }
    return _s + ".";
}

function ws_logic_draw(_x1, _y1, _x2, _y2)
{
    var _rw = 320;
    var _lx2 = _x2 - _rw - 12;
    ui_panel(_x1, _y1, _lx2, _y2, "Rules");
    var _nr = array_length(proj.rules);
    ui_text(_x1 + 100, _y1 + 15, string(_nr) + " rule(s). Rules are checked every frame, top to bottom.", global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
    if (ui_button("logic_add", _lx2 - 150, _y1 + 8, 136, 30, "+ Add rule", "Add rule|Adds a new WHEN / DO rule at the bottom of the list. Change its parts with the drop-downs.", BTN_ACCENT))
    {
        if (_nr < 100)
        {
            undo_mark("ruleadd" + string(current_time));
            var _nrule = rule_new();
            _nrule.a = logic_find_role([0, 6], 0);
            _nrule.b = min(1, max(0, array_length(proj.actors) - 1));
            array_push(proj.rules, _nrule);
            ds_map_replace(ui_scroll, "logic_list", 999999);
        }
    }

    var _lx = _x1 + 14;
    var _ly1 = _y1 + 52;
    var _ly2 = _y2 - 12;
    var _cardh = 128;
    var _content = _nr * (_cardh + 10) + 10;
    var _off = ui_scroll_begin("logic_list", _lx, _ly1, _lx2 - 10, _ly2, _content);
    var _anames = actor_names();
    var _snames = sfx_names();
    var _cw = _lx2 - 14 - _lx - 10;
    if (_nr == 0)
    {
        ui_text_wrap(_lx + 20, _ly1 + 20, "No rules yet. Rules make your game a game! Press '+ Add rule' or pick a quick recipe on the right, e.g. 'Player touches enemy: lose a life'.", global.TH.text_dim, _cw - 40, global.f_body, 1);
    }
    var _del = -1;
    var _move = 0;
    var _movei = -1;
    for (var i = 0; i < _nr; i++)
    {
        var _r = proj.rules[i];
        var _cx = _lx;
        var _cy = _ly1 + 10 + i * (_cardh + 10) - _off;
        if (_cy + _cardh < _ly1 - 10 || _cy > _ly2 + 10) { continue; }
        var _rid = "rule_" + string(i);
        ui_rrect(_cx, _cy, _cx + _cw, _cy + _cardh, 12, global.TH.btn_top, global.TH.panel_bot, 0.9);
        ui_rrect_line(_cx, _cy, _cx + _cw, _cy + _cardh, 12, global.TH.panel_edge, 0.6, 1);
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
        if (_act == 4 || _act == 5 || _act == 6 || _act == 7 || _act == 11 || _act == 12 || _act == 14)
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
        if (_act == 8)
        {
            set_val(_r, "value", ui_colour_drop(_rid + "_col", _dx, _dy, 180, 30, clamp(_r.value, 0, pal_count() - 1), "Colour|The backdrop palette colour that colour 0 (the background and border) changes to."), _rid + "col");
        }

        // sentence + tools
        ui_text(_cx + 46, _cy + 102, ui_text_fit(logic_sentence(_r), global.f_small, _cw - 200), global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
        var _tx = _cx + _cw - 40;
        if (ui_button(_rid + "_del", _tx, _cy + 10, 30, 30, "X", "Delete rule|Removes this rule. You can Undo this.", BTN_DANGER)) { _del = i; }
        if (ui_button(_rid + "_up", _tx, _cy + 48, 30, 30, "^", "Move up|Rules higher up are checked first.", BTN_GHOST)) { _movei = i; _move = -1; }
        if (ui_button(_rid + "_dn", _tx, _cy + 86, 30, 30, "v", "Move down|Rules lower down are checked later.", BTN_GHOST)) { _movei = i; _move = 1; }
    }
    ui_scroll_end("logic_list", _lx, _ly1, _lx2 - 10, _ly2, _content);

    if (_del >= 0)
    {
        undo_mark("ruledel" + string(current_time));
        array_delete(proj.rules, _del, 1);
    }
    if (_movei >= 0)
    {
        var _j = _movei + _move;
        if (_j >= 0 && _j < array_length(proj.rules))
        {
            undo_mark("rulemove" + string(current_time));
            var _tmp = proj.rules[_movei];
            proj.rules[_movei] = proj.rules[_j];
            proj.rules[_j] = _tmp;
        }
    }

    // ---------------- recipes ----------------
    var _px = _x2 - _rw;
    ui_panel(_px, _y1, _x2, _y2, "Quick recipes");
    var _ry = _y1 + 56;
    ui_text_wrap(_px + 20, _ry, "One click adds ready-made rules. They use your first Player, enemy and Still actor.", global.TH.text_dim, _rw - 40, global.f_small, 1);
    _ry += 50;
    var _rhelp = [
        "Enemy hit|Adds 3 rules: when the player touches an enemy, lose a life, go back to the start and flash the screen.",
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
