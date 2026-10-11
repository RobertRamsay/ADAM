/// ADAM - example games (complete projects in datafiles/examples)

function examples_init()
{
    global.EXAMPLES = [
        { file : "gem_hunter.adam",  name : "Gem Hunter",  pro : false, desc : "Collect gems under a copper sunset while two ghosts hunt you." },
        { file : "deep_dive.adam",   name : "Deep Dive",   pro : false, desc : "Swim for pearls on the sea bed, dodging jellyfish and a shark." },
        { file : "star_catcher.adam", name : "Star Catcher", pro : false, desc : "Fly through an asteroid belt catching stars, chased by a UFO." },
        { file : "dodge_ball.adam",  name : "Dodge Ball",  pro : false, desc : "Survive the neon arena as the bouncing balls get faster and faster." },
        { file : "firefly_night.adam", name : "Firefly Night", pro : true, desc : "An owl catches a swarm of 12 fireflies - BOBs - while bats hunt it." }
    ];
}

function example_names()
{
    var _n = [];
    for (var i = 0; i < array_length(global.EXAMPLES); i++)
    {
        var _e = global.EXAMPLES[i];
        var _s = _e.name + "  -  " + _e.desc;
        if (_e.pro) { _s = _e.name + " (Pro)  -  " + _e.desc; }
        array_push(_n, _s);
    }
    return _n;
}

/// Loads example _i, keeping the machine that is selected now
function example_load(_i)
{
    if (proj_dirty)
    {
        if (!show_question("You have unsaved changes. Load the example anyway?")) { return; }
    }
    var _e = global.EXAMPLES[clamp(_i, 0, array_length(global.EXAMPLES) - 1)];
    var _txt = file_read_text(working_directory + "examples/" + _e.file);
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
    proj_path = "";
    out_path = "";            // asked on the first build, so another game's disk is never overwritten
    proj_dirty = false;
    undo_clear_all();
    project_after_change();
    settings_save();
    if (_e.pro && !pro_on())
    {
        // Lite can look round a Pro example; its disk only gets the first 8 actors, as sprites
        toast(_e.name + " uses BOBs, part of ADAM Pro - ADAM Lite puts only its first 8 actors on the disk", 1);
    }
    else
    {
        toast(_e.name + " loaded - try Build to play it!", 0);
    }
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
        ui_popup_w = max(_w, 520);
        ui_popup_opts = _options;
        ui_popup_index = -1;
        ui_popup_anchor_y = _y;
        ui_popup_scroll = 0;
    }
    return -1;
}
