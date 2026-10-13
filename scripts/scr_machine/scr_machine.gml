/// ADAM - stock target machines and the launch machine picker
///
/// Two stock machines, picked when ADAM starts and stored in each project:
///   A500_600 : OCS/ECS, MC68000 @ 7 MHz, 1MB chip RAM  (FS-UAE model A600)
///   A1200    : AGA, MC68EC020 @ 14 MHz, 2MB chip RAM    (FS-UAE model A1200)
/// A500s with only 512KB of chip RAM are not a target, but the Build page warns
/// (amber, never blocks) when an A500/600 game would not fit in one (mem_note).
/// Everything that depends on the hardware (colour depth, colour precision,
/// emulator model, memory budget) reads it from machine_cur().

function machine_defs_init()
{
    global.MACHINES = [
        {
            id          : "A500_600",
            name        : "AMIGA 500/600",
            short_name  : "A500/600 1MB",
            chipset     : "OCS / ECS",
            aga         : false,
            cpu         : "MC68000 @ 7.09 MHz",
            chip_kb     : 1024,
            ram_label   : "1MB chip RAM",
            mem_note    : "Made for 1MB of chip RAM (A500+, A600, or an A500 upgraded to 1MB chip). An A500 with 512KB of chip RAM (even with a trapdoor slow-RAM card) only fits small games - the Build page warns when a game is too big for one.",
            max_depth   : 4,
            gun_label   : "4096-colour palette (12-bit)",
            fsuae_model : "A600"
        },
        {
            id          : "A1200",
            name        : "AMIGA 1200",
            short_name  : "A1200 2MB",
            chipset     : "AGA",
            aga         : true,
            cpu         : "MC68EC020 @ 14.18 MHz",
            chip_kb     : 2048,
            ram_label   : "2MB chip RAM",
            mem_note    : "Plenty of chip RAM for any ADAM game.",
            max_depth   : 7,
            gun_label   : "16.8 million-colour palette (24-bit)",
            fsuae_model : "A1200"
        }
    ];
}

/// Profile for an id. Unknown ids fall back to the first machine.
function machine_get(_id)
{
    for (var i = 0; i < array_length(global.MACHINES); i++)
    {
        if (global.MACHINES[i].id == _id) { return global.MACHINES[i]; }
    }
    return global.MACHINES[0];
}

/// Profile of the current project's machine
function machine_cur()
{
    return machine_get(proj.machine);
}

/// Index of an id in global.MACHINES
function machine_index(_id)
{
    for (var i = 0; i < array_length(global.MACHINES); i++)
    {
        if (global.MACHINES[i].id == _id) { return i; }
    }
    return 0;
}

/// Switches the project to another machine and fits the project to it
function machine_set(_id, _with_undo)
{
    var _m = machine_get(_id);
    if (_m.id == proj.machine) { return; }
    if (_with_undo) { undo_mark_full("machine" + string(current_time)); }
    proj.machine = _m.id;
    if (proj.depth > _m.max_depth)
    {
        backdrop_set_depth(_m.max_depth);
        toast("The " + _m.name + " shows up to " + string(1 << _m.max_depth) + " backdrop colours - the backdrop was reduced", 1);
    }
    last_machine = _m.id;
    settings_save();
    project_after_change();
}

/// Opens the full-screen machine picker
function machine_pick_open(_is_launch)
{
    machine_pick_active = true;
    machine_pick_launch = _is_launch;
    machine_pick_anim = 0;
    machine_pick_index = machine_index(proj.machine);
    if (_is_launch) { machine_pick_index = machine_index(last_machine); }
    ui_popup_open = false;
    ui_focus = "";
}

function machine_pick_choose(_i)
{
    var _m = global.MACHINES[_i];
    var _was_launch = machine_pick_launch;
    machine_pick_active = false;
    if (_was_launch)
    {
        // the launch choice applies to whatever project is open (including a
        // restored autosave) without an undo step
        if (_m.id != proj.machine) { machine_set(_m.id, false); }
        last_machine = _m.id;
        settings_save();
        if (auto_tutorials && !ws_seen[WS_HOME])
        {
            ws_seen[WS_HOME] = true;
            settings_save();
            tut_offer(-1);
        }
        whatsnew_after_launch(settings_first_run);
    }
    else
    {
        machine_set(_m.id, true);
    }
    toast("Target machine: " + _m.name + "  (" + _m.chipset + ", " + _m.ram_label + ")", 0);
}

/// Boing-ball logo sprites (red and white halves, tinted when drawn)
function boing_init()
{
    var _s = 48;
    var _red = array_create(_s * _s, 0);
    var _white = array_create(_s * _s, 0);
    var _rr = _s * 0.5 - 0.5;
    for (var _py = 0; _py < _s; _py++)
    {
        for (var _px = 0; _px < _s; _px++)
        {
            var _nx = (_px - _rr) / _rr;
            var _ny = (_py - _rr) / _rr;
            var _d = _nx * _nx + _ny * _ny;
            if (_d > 1) { continue; }
            var _nz = sqrt(1 - _d);
            // tilted sphere: rotate around z by 20 degrees
            var _ang = degtorad(20);
            var _tx = _nx * cos(_ang) - _ny * sin(_ang);
            var _ty = _nx * sin(_ang) + _ny * cos(_ang);
            var _lon = arctan2(_tx, _nz);
            var _lat = arcsin(clamp(_ty, -1, 1));
            var _cu = floor((_lon + pi) / (pi / 4));
            var _cv = floor((_lat + pi / 2) / (pi / 8));
            if (((_cu + _cv) mod 2) == 0) { _red[_py * _s + _px] = 1; }
            else { _white[_py * _s + _px] = 1; }
        }
    }
    var _surf = surface_create(_s, _s);
    mask_to_surface(_surf, _s, _s, _red);
    global.spr_boing_red = sprite_create_from_surface(_surf, 0, 0, _s, _s, false, false, 0, 0);
    mask_to_surface(_surf, _s, _s, _white);
    global.spr_boing_white = sprite_create_from_surface(_surf, 0, 0, _s, _s, false, false, 0, 0);
    surface_free(_surf);
}

function draw_boing(_x, _y, _size, _alpha)
{
    var _k = _size / 48;
    draw_sprite_ext(global.spr_boing_red, 0, _x, _y, _k, _k, 0, make_colour_rgb(225, 30, 40), _alpha);
    draw_sprite_ext(global.spr_boing_white, 0, _x, _y, _k, _k, 0, c_white, _alpha);
}

/// The machine picker, drawn over everything while machine_pick_active
function machine_pick_draw(_gw, _gh)
{
    if (!machine_pick_active) { return; }
    machine_pick_anim = lerp(machine_pick_anim, 1, 0.12);
    var _a = machine_pick_anim;
    ui_force_input = true;

    draw_set_alpha(0.86 * _a);
    draw_rectangle_colour(0, 0, _gw, _gh, c_black, c_black, global.TH.bg_bot, global.TH.bg_bot, false);
    draw_set_alpha(1);

    var _n = array_length(global.MACHINES);
    var _cw = min(440, floor((_gw - 120) / _n));
    var _ch = 380;
    var _gap = 40;
    var _total = _cw * _n + _gap * (_n - 1);
    var _x0 = floor((_gw - _total) / 2);
    var _cy = floor((_gh - _ch) / 2) + 30 + (1 - _a) * 30;

    draw_boing(_gw * 0.5 - 150, _cy - 118, 56, _a);
    ui_text(_gw * 0.5 - 80, _cy - 112, "ADAM", c_white, fa_left, fa_top, global.f_hero, _a);
    ui_text(_gw * 0.5 - 80, _cy - 78, "Amiga games, no code needed", global.TH.text_dim, fa_left, fa_top, global.f_body, _a);
    ui_text(_gw * 0.5, _cy - 34, "Choose the Amiga your game is for", global.TH.text, fa_center, fa_top, global.f_title, _a);

    for (var i = 0; i < _n; i++)
    {
        var _m = global.MACHINES[i];
        var _x = _x0 + i * (_cw + _gap);
        var _id = "machine_card_" + string(i);
        var _hot = ui_register(_id, _x, _cy, _x + _cw, _cy + _ch, _m.name + "|" + _m.chipset + ", " + _m.cpu + ", " + _m.ram_label + ". " + _m.mem_note + " Click to make games for this machine.");
        if (_hot) { machine_pick_index = i; }
        var _sel = 0;
        if (machine_pick_index == i) { _sel = 1; }
        var _h = ui_anim_to(_id, _sel);
        ui_shadow(_x, _cy, _x + _cw, _cy + _ch, 16, 1.5 * _a);
        ui_rrect(_x, _cy, _x + _cw, _cy + _ch, 16, merge_colour(global.TH.panel_top, global.TH.btn_hot_top, _h * 0.6), global.TH.panel_bot, _a);
        var _band = make_colour_rgb(0, 85, 170);
        if (_m.aga) { _band = make_colour_rgb(230, 120, 20); }
        ui_rrect(_x, _cy, _x + _cw, _cy + 64, 16, merge_colour(_band, c_white, 0.12), _band, _a);
        ui_rrect(_x, _cy + 40, _x + _cw, _cy + 64, 0, _band, _band, _a);
        ui_rrect_line(_x, _cy, _x + _cw, _cy + _ch, 16, merge_colour(global.TH.panel_edge, c_white, _h), 0.6 + 0.4 * _h, 1 + round(_h));
        ui_glow(_x, _cy, _x + _cw, _cy + _ch, 16, global.TH.accent2, _h * 0.8);
        ui_text(_x + 22, _cy + 18, string(i + 1) + "   " + _m.name, c_white, fa_left, fa_top, global.f_title, _a);
        if (!machine_pick_launch && _m.id == proj.machine)
        {
            ui_text(_x + _cw - 22, _cy + 22, "CURRENT", c_white, fa_right, fa_top, global.f_small, _a);
        }
        var _labels = ["Chipset", "Processor", "Memory", "Backdrop", "Colours", "Sprites", "Emulator"];
        var _vals = [_m.chipset, _m.cpu, _m.ram_label + ", no fast RAM", "Up to " + string(1 << _m.max_depth) + " colours, 320 x 256",
                     _m.gun_label, "8 hardware sprites, 3 colours each", "FS-UAE " + _m.fsuae_model];
        var _ry = _cy + 84;
        for (var r = 0; r < array_length(_labels); r++)
        {
            // the small label sits 2 px lower so it shares the value's baseline
            ui_text(_x + 22, _ry + 2, _labels[r], global.TH.text_faint, fa_left, fa_top, global.f_small, _a);
            ui_text(_x + 120, _ry, ui_text_fit(_vals[r], global.f_body, _cw - 140), global.TH.text, fa_left, fa_top, global.f_body, _a);
            _ry += 34;
        }
        var _bst = BTN_NORMAL;
        if (machine_pick_index == i) { _bst = BTN_ACCENT; }
        if (ui_button(_id + "_go", _x + 22, _cy + _ch - 56, _cw - 44, 38, "Make games for the " + _m.name, "Choose|Sets this as the target machine. You can change it later from the machine button in the top bar.", _bst))
        {
            machine_pick_choose(i);
            ui_force_input = false;
            return;
        }
        if (_hot && ui_pressed)
        {
            ui_take_click();
            machine_pick_choose(i);
            ui_force_input = false;
            return;
        }
    }

    var _hint = "Click a machine, or press 1 / 2.  Arrow keys + Enter also work.";
    if (!machine_pick_launch) { _hint += "  Esc keeps the current machine."; }
    ui_text(_gw * 0.5, _cy + _ch + 26, _hint, global.TH.text_faint, fa_center, fa_top, global.f_small, _a);

    if (keyboard_check_pressed(ord("1"))) { machine_pick_choose(0); }
    else
    {
        if (keyboard_check_pressed(ord("2")) && _n > 1) { machine_pick_choose(1); }
        else
        {
            if (keyboard_check_pressed(vk_left)) { machine_pick_index = max(0, machine_pick_index - 1); }
            if (keyboard_check_pressed(vk_right)) { machine_pick_index = min(_n - 1, machine_pick_index + 1); }
            if (keyboard_check_pressed(vk_enter)) { machine_pick_choose(machine_pick_index); }
            else
            {
                if (keyboard_check_pressed(vk_escape) && !machine_pick_launch) { machine_pick_active = false; }
            }
        }
    }
    ui_force_input = false;
}
