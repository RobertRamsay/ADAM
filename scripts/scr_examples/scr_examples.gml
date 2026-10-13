/// ADAM - example games (complete projects in datafiles/examples)

function examples_init()
{
    global.EXAMPLES = [
        { file : "gem_hunter.adam", file_aga : "gem_hunter_a1200.adam",  name : "Gem Hunter",  pro : false, desc : "Collect gems under a copper sunset while two ghosts hunt you." },
        { file : "deep_dive.adam", file_aga : "deep_dive_a1200.adam",   name : "Deep Dive",   pro : false, desc : "Swim for pearls on the sea bed, dodging jellyfish and a shark." },
        { file : "star_catcher.adam", file_aga : "star_catcher_a1200.adam", name : "Star Catcher", pro : false, desc : "Blast asteroids and a UFO with your lasers, then catch the stars they drop - mind the bombs." },
        { file : "dodge_ball.adam", file_aga : "dodge_ball_a1200.adam",  name : "Dodge Ball",  pro : false, desc : "Survive the neon arena as the bouncing balls get faster and faster." },
        { file : "firefly_night.adam", file_aga : "firefly_night_a1200.adam", name : "Firefly Night", pro : true, desc : "An owl catches a swarm of 12 fireflies - BOBs - while bats hunt it." },
        { file : "dig_deep.adam", file_aga : "dig_deep_a1200.adam",    name : "Dig Deep",    pro : true,  desc : "Dig through a scrolling 128 x 64 tile world for 12 gold, Terraria style, past slimes, bats and a mole." }
    ];
}

/// The example's file for the machine picked: the A1200 has its own versions,
/// with up to 128 colours so gradients are smooth instead of dithered
function example_file(_e)
{
    if (machine_cur().id == "A1200") { return _e.file_aga; }
    return _e.file;
}

function example_names()
{
    var _n = [];
    for (var i = 0; i < array_length(global.EXAMPLES); i++)
    {
        var _e = global.EXAMPLES[i];
        var _s = _e.name + "  -  " + _e.desc;
        if (_e.pro && !pro_edition()) { _s = _e.name + " (ADAM Pro)  -  " + _e.desc; }
        array_push(_n, _s);
    }
    return _n;
}

/// Loads example _i, keeping the machine that is selected now
function example_load(_i)
{
    var _ex = global.EXAMPLES[clamp(_i, 0, array_length(global.EXAMPLES) - 1)];
    if (_ex.pro)
    {
        if (!pro_gate(_ex.name)) { return; }
    }
    if (proj_dirty)
    {
        confirm_open("Load the example?", confirm_unsaved_text("Loading the example"), "Load example", "Cancel", true, example_load_now, _i);
        return;
    }
    example_load_now(_i);
}

function example_load_now(_i)
{
    var _e = global.EXAMPLES[clamp(_i, 0, array_length(global.EXAMPLES) - 1)];
    var _txt = file_read_text(working_directory + "examples/" + example_file(_e));
    if (_txt == "")
    {
        toast("The example file is missing (datafiles/examples)", 2);
        return;
    }
    var _machine = proj.machine;
    try
    {
        proj = project_from_loaded(json_parse(_txt));
    }
    catch (_err)
    {
        toast("That example could not be read", 2);
        return;
    }
    proj.machine = _machine;
    groups_fold_all();
    proj_path = "";
    out_path = "";            // asked on the first build, so another game's disk is never overwritten
    proj_dirty = false;
    undo_clear_all();
    project_after_change();
    settings_save();
    toast(_e.name + " loaded - try Build & play (F5)!", 0);
}

/// Button that opens a menu. Returns the chosen index, or -1.
function ui_menu_button(_id, _x, _y, _w, _h, _label, _options, _help, _style)
{
    if (ui_popup_result_id == _id)
    {
        ui_popup_result_id = "";
        return ui_popup_result;
    }
    if (ui_button(_id, _x, _y, _w, _h, _label, _help, _style))
    {
        ui_popup_open = true;
        ui_popup_id = _id;
        ui_popup_kind = 0;
        ui_popup_x = _x;
        ui_popup_y = _y + _h + 4;
        // wide enough for the longest option (text inset + scrollbar gutter), so the
        // example descriptions are not cut short; ui_popup_draw keeps it on screen
        draw_set_font(global.f_body);
        var _ow = 0;
        for (var o = 0; o < array_length(_options); o++) { _ow = max(_ow, ui_sw(_options[o])); }
        ui_popup_w = max(_w, 520, ceil(_ow) + 40);
        ui_popup_opts = _options;
        ui_popup_index = -1;
        ui_popup_anchor_y = _y;
        ui_popup_scroll = 0;
    }
    return -1;
}
