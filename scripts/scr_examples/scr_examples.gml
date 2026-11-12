/// ADAM - example games (complete projects in datafiles/examples)

function examples_init()
{
    global.EXAMPLES = [
        { file : "gem_hunter.adam", file_aga : "gem_hunter_a1200.adam",  name : "Gem Hunter",  pro : false, desc : "Collect gems under a copper sunset while two ghosts hunt you." },
        { file : "deep_dive.adam", file_aga : "deep_dive_a1200.adam",   name : "Deep Dive",   pro : false, desc : "Swim for pearls on the sea bed, dodging jellyfish and a shark." },
        { file : "star_catcher.adam", file_aga : "star_catcher_a1200.adam", name : "Star Catcher", pro : false, desc : "Blast asteroids and a UFO with your lasers, then catch the stars they drop - mind the bombs." },
        { file : "dodge_ball.adam", file_aga : "dodge_ball_a1200.adam",  name : "Dodge Ball",  pro : false, desc : "Survive the neon arena as the bouncing balls get faster and faster." },
        { file : "firefly_night.adam", file_aga : "firefly_night_a1200.adam", name : "Firefly Night", pro : true, desc : "An owl catches a swarm of 12 fireflies - BOBs - while bats hunt it." },
        { file : "dig_deep.adam", file_aga : "dig_deep_a1200.adam",    name : "Dig Deep",    pro : true,  desc : "Dig through a scrolling 128 x 64 tile world for 12 gold, Terraria style, past slimes, bats and a mole." },
        { file : "nebula_strike.adam", file_aga : "nebula_strike_a1200.adam", name : "Nebula Strike", pro : true, desc : "A side-scrolling shoot 'em up: grab Power, Speed and Multiple capsules, then take on the battleship guarding the warp gate." },
        { file : "starfire.adam", file_aga : "starfire_a1200.adam",    name : "Starfire",    pro : true,  desc : "A vertical shoot 'em up down a space station's trench: power up your fighter, pick up options and break the mothership." },
        { file : "jade_serpent.adam", file_aga : "jade_serpent_a1200.adam", name : "Jade Serpent", pro : true, desc : "Fly a jade glider up a jungle river, over moss-grown ruins and a step pyramid to the serpent temple: waves from spawners, totems that split, homing missiles and a feathered serpent boss." },
        { file : "torchlight.adam", file_aga : "torchlight_a1200.adam", name : "Torchlight", pro : true, desc : "Items: find the key for the cave door, make a torch from a stick and a cloth (space bar), and light the dark cave to find the crown." },
        { file : "piston_pass.adam", file_aga : "piston_pass_a1200.adam", name : "Piston Pass", pro : false, desc : "A template for 'set it up, then cross' games: fire stops each rising piston in turn, then walk across to the exit. A fall starts the floor again." }
    ];
}

/// Community games (internal builds only): finished Amiga games by other people,
/// listed in datafiles/community/community.json:
///   { "games" : [ { "name", "by", "desc", "adf", "shot", "machine" } ] }
/// adf / shot = file names in the same folder (shot = a 320 x 256 PNG, may be ""),
/// machine = "A500_600" (default) or "A1200" - the FS-UAE model it boots on.
/// The folder is not in git: tools/release_build.ps1 -Community <folder> adds it to a
/// build. Without it global.COMMUNITY is empty and the Community panel says "No community games yet".
function community_init()
{
    global.COMMUNITY = [];
    var _txt = file_read_text(working_directory + "community/community.json");
    if (_txt == "") { return; }
    var _d = undefined;
    try
    {
        _d = json_parse(_txt);
    }
    catch (_err)
    {
        return;
    }
    if (!is_struct(_d)) { return; }
    var _g = _d[$ "games"];
    if (!is_array(_g)) { return; }
    for (var i = 0; i < array_length(_g); i++)
    {
        var _e = _g[i];
        if (!is_struct(_e)) { continue; }
        if (!is_string(_e[$ "name"]) || !is_string(_e[$ "adf"])) { continue; }
        var _c = { name : _e.name, by : "", desc : "", adf : _e.adf, machine : "A500_600", spr : -1 };
        if (is_string(_e[$ "by"])) { _c.by = _e.by; }
        if (is_string(_e[$ "desc"])) { _c.desc = _e.desc; }
        if (is_string(_e[$ "machine"])) { _c.machine = machine_get(_e.machine).id; }
        if (is_string(_e[$ "shot"]) && _e.shot != "")
        {
            var _sp = working_directory + "community/" + _e.shot;
            if (file_exists(_sp)) { _c.spr = sprite_add(_sp, 1, false, false, 0, 0); }
        }
        array_push(global.COMMUNITY, _c);
    }
}

/// Plays community game _i in FS-UAE on its own machine (not the project's). The disk
/// is copied to the save area first, so FS-UAE never touches the copy in ADAM's folder.
function community_play(_i)
{
    if (_i < 0 || _i >= array_length(global.COMMUNITY)) { return; }
    var _c = global.COMMUNITY[_i];
    var _src = working_directory + "community/" + _c.adf;
    if (!file_exists(_src))
    {
        toast("That game's disk is missing (datafiles/community)", 2);
        return;
    }
    var _dir = game_save_id + "community/";
    if (!directory_exists(_dir)) { directory_create(_dir); }
    var _dst = _dir + _c.adf;
    if (file_exists(_dst)) { file_delete(_dst); }
    file_copy(_src, _dst);
    if (!file_exists(_dst))
    {
        toast("Could not copy that game's disk", 2);
        return;
    }
    launch_fsuae(_dst, _c.machine);
}

/// The example's file for the machine picked: the A1200 has its own versions,
/// with up to 128 colours so gradients are smooth instead of dithered
function example_file(_e)
{
    if (machine_cur().id == "A1200") { return _e.file_aga; }
    return _e.file;
}

/// One menu line per entry of global.EXAMPLES ("Name  -  description"), with
/// "(ADAM Pro)" after Pro extras in Lite. Same order as global.EXAMPLES.
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

/// Loads example _i without asking (example_load asks first when there are
/// unsaved changes): reads example_file() from datafiles/examples, runs it
/// through project_from_loaded, keeps the machine picked now, clears undo and
/// out_path (so the first Build asks where to save). Toasts on a missing or bad file.
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
    example_last = _i;
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
