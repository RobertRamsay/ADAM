/// ADAM - lessons: make a whole game from New, step by step, at four levels.
/// Unlike the page tours (scr_tutorial) a lesson step is a task: the card
/// sits in a corner, the page stays usable, the control to use is outlined,
/// and the step ticks itself off when its check() sees the job is done.
/// Info steps (no check) wait for Next. Every task can be skipped.

function les_step(_tab, _target, _title, _body, _check)
{
    return { tab : _tab, target : _target, title : _title, body : _body, check : _check };
}

/// ---------- checks (called from obj_app, so proj is in scope) ----------

/// Painted pixels in sprite _i
function les_spr_px(_i)
{
    if (_i >= array_length(proj.sprites)) { return 0; }
    var _px = proj.sprites[_i].px;
    var _n = 0;
    for (var i = 0; i < array_length(_px); i++)
    {
        if (_px[i] != 0) { _n += 1; }
    }
    return _n;
}

/// Is there a rule with this WHEN and DO? (-1 = any)
function les_rule_has(_when, _act)
{
    for (var i = 0; i < array_length(proj.rules); i++)
    {
        var _r = proj.rules[i];
        var _ok = true;
        if (_when >= 0 && _r.when != _when) { _ok = false; }
        if (_act >= 0 && _r.act != _act) { _ok = false; }
        if (_ok) { return true; }
    }
    return false;
}

/// Is there an actor with this behaviour?
function les_role_has(_role)
{
    for (var i = 0; i < array_length(proj.actors); i++)
    {
        if (proj.actors[i].role == _role) { return true; }
    }
    return false;
}

/// Roughly how many backdrop pixels are not colour 0 (every 8th pixel sampled)
function les_bd_painted()
{
    var _n = 0;
    var _len = array_length(proj.pixels);
    for (var i = 0; i < _len; i += 8)
    {
        if (proj.pixels[i] != 0) { _n += 8; }
    }
    return _n;
}

/// Backdrop colour at a pixel
function les_bd_at(_px, _py)
{
    return proj.pixels[_py * BD_W + _px];
}

/// Does song _s have at least _n bars filled on the timeline?
function les_song_bars(_s, _n)
{
    if (_s >= array_length(proj.songs)) { return false; }
    var _song = proj.songs[_s];
    if (_song.kind != 0) { return true; }
    var _c = 0;
    var _lanes = _song.arr.lanes;
    for (var l = 0; l < array_length(_lanes); l++)
    {
        for (var b = 0; b < array_length(_lanes[l]); b++)
        {
            if (_lanes[l][b] >= 0) { _c += 1; }
        }
    }
    return _c >= _n;
}

/// Has any loop in any song been edited (it is then no longer a library loop)?
function les_loop_edited()
{
    for (var s = 0; s < array_length(proj.songs); s++)
    {
        var _song = proj.songs[s];
        if (_song.kind == 0)
        {
            for (var i = 0; i < array_length(_song.arr.loops); i++)
            {
                if (_song.arr.loops[i].lib < 0) { return true; }
            }
        }
    }
    return false;
}

/// Was the game built since this step began?
function les_built()
{
    return build_ok && build_stamp > les_step_t;
}

/// ---------- the four lessons ----------

function lessons_init()
{
    les_defs = [
        {
            name : "Basics - Walkabout", short : "Basics", mins : 5, pro : false,
            steps : [
                les_step(WS_HOME, "", "Lesson 1: Basics", "You'll make the smallest possible Amiga game: a hero you walk around a picture you painted. A fresh project has been started for you. Each card tells you what to do and ticks itself off when it's done - or press Skip.", undefined),
                les_step(WS_HOME, "home_name", "Name your game", "Click the name box and type a name for your game.", function() { return proj.name != "My Amiga Game"; }),
                les_step(WS_BACKDROP, "bd_clear", "Paint the sky", "This is the backdrop. Click a blue in the palette, then press this button to fill the whole picture with it.", function() { return les_bd_at(0, 0) != 0; }),
                les_step(WS_BACKDROP, "bd_tool_2", "Draw the ground", "Pick the Box tool, choose a green, then drag a box along the bottom of the picture.", function() { return les_bd_at(160, 250) != les_bd_at(160, 20); }),
                les_step(WS_SPRITES, "spr_grid", "Draw your hero", "Sprites are the pictures that move. Draw your hero with the left mouse button (right-click rubs out). Fill at least 20 squares.", function() { return les_spr_px(0) >= 20; }),
                les_step(WS_SPRITES, "spr_name", "Name the sprite", "Call it Hero - you'll pick sprites by name on the next page.", function() { return proj.sprites[0].name != "Sprite 1"; }),
                les_step(WS_ACTORS, "act_add", "Add your hero", "Actors are the things in your game. Add one - the first actor is always set up as the player, using sprite 1.", function() { return array_length(proj.actors) >= 1; }),
                les_step(WS_ACTORS, "act_stage", "Stand on the ground", "Drag your hero down so it stands on the ground you painted.", function() { return array_length(proj.actors) >= 1 && proj.actors[0].y >= 170; }),
                les_step(WS_BUILD, "build_run", "Build and play", "Press Build and play. ADAM writes a bootable Amiga disk and starts it in FS-UAE. (No FS-UAE yet? Use Build .ADF disk - that counts too.) Move with the joystick or arrow keys.", function() { return les_built(); }),
                les_step(WS_BUILD, "", "You made an Amiga game!", "That's the whole idea: picture, sprite, actor, build. Next, the Beginner lesson adds something to collect, rules, a score and a sound.", undefined)
            ]
        },
        {
            name : "Beginner - Star Catcher", short : "Beginner", mins : 10, pro : false,
            steps : [
                les_step(WS_HOME, "", "Lesson 2: Beginner", "Catch the bouncing star to score points, and reach 100 to win. You'll meet rules - the WHEN / DO sentences that turn pictures into a game. A fresh project has been started for you.", undefined),
                les_step(WS_BACKDROP, "bd_canvas", "A quick backdrop", "Paint a sky and some ground, like in Basics: pick a colour, fill the picture, then box in the ground with a second colour.", function() { return les_bd_at(0, 0) != 0 && les_bd_at(160, 250) != les_bd_at(160, 20); }),
                les_step(WS_SPRITES, "spr_grid", "Draw the catcher", "Draw your player in sprite 1 - 20 squares or more.", function() { return les_spr_px(0) >= 20; }),
                les_step(WS_SPRITES, "spr_slot_1", "Draw a star", "Click sprite 2 in the list, then draw a star. Pick its colours with the pens and sliders on the right.", function() { return les_spr_px(1) >= 8; }),
                les_step(WS_ACTORS, "act_add", "Add the player", "Add the first actor - it becomes the player.", function() { return array_length(proj.actors) >= 1; }),
                les_step(WS_ACTORS, "act_add", "Add the star", "Add a second actor for the star. A new actor picks the next sprite, so it is already your star (sprite 2).", function() { return array_length(proj.actors) >= 2; }),
                les_step(WS_ACTORS, "act_role", "Make it bounce", "Behaviour is how an actor moves on its own. Set the star to Bouncer.", function() { return array_length(proj.actors) >= 2 && proj.actors[1].role == 1; }),
                les_step(WS_LOGIC, "logic_tpl_1", "Catch it", "Rules are sentences: WHEN something happens, DO something. Press this quick recipe: when the player touches the pickup, add 10 to the score, move the pickup somewhere new and play a sound.", function() { return les_rule_has(0, 0) && les_rule_has(0, 5); }),
                les_step(WS_LOGIC, "logic_add", "Write a rule yourself", "Press Add rule, then use its drop-downs: set WHEN to 'Fire button is pressed' and DO to 'Play a sound'.", function() { return les_rule_has(1, 2); }),
                les_step(WS_LOGIC, "logic_tpl_2", "A way to win", "This recipe adds: WHEN the score reaches 100, DO You win!", function() { return les_rule_has(3, 10); }),
                les_step(WS_SOUND, "snd_preset_0", "Choose the sound", "Sound 1 plays when you catch the star. Try the presets and press Play to hear them - Coin is a good one.", undefined),
                les_step(WS_BUILD, "build_run", "Build and play", "Build it and catch ten stars!", function() { return les_built(); }),
                les_step(WS_BUILD, "", "Nice work!", "You used actors that move by themselves, rules, a score, a sound and a win. Next, Intermediate builds a platform game with enemies, lives and levels.", undefined)
            ]
        },
        {
            name : "Intermediate - Hill Hopper", short : "Intermediate", mins : 20, pro : false,
            steps : [
                les_step(WS_HOME, "", "Lesson 3: Intermediate", "A platform game: run and jump over hills, collect gems, dodge hoppers, and get through three levels. A fresh project has been started for you.", undefined),
                les_step(WS_LEVELS, "lvl_on", "Switch levels on", "Levels give every stage its own hills that the Amiga draws at the start of the level.", function() { return proj.levels_on; }),
                les_step(WS_LEVELS, "lvl_add", "Three levels", "Add levels until you have three. Click one in the list and press Generate (or drag on the picture) to change its hills.", function() { return array_length(proj.levels) >= 3; }),
                les_step(WS_BACKDROP, "bd_tab_sky", "A copper sky", "Open Copper sky and pick a ready-made sky. The copper chip changes colour 0 on every line - a smooth sky for free.", function() { return proj.sky_on; }),
                les_step(WS_SPRITES, "spr_grid", "Hero, enemy, gem", "Draw three sprites: your hero in sprite 1, an enemy in sprite 2 and a gem in sprite 3.", function() { return les_spr_px(0) >= 20 && les_spr_px(1) >= 12 && les_spr_px(2) >= 6; }),
                les_step(WS_SPRITES, "spr_op_copy", "A walking frame", "Select sprite 1, press Copy, select sprite 4, press Paste, then move the legs a little. That's frame two of a walk.", function() { return les_spr_px(3) >= 20; }),
                les_step(WS_ACTORS, "act_add", "The hero", "Add the player.", function() { return array_length(proj.actors) >= 1; }),
                les_step(WS_ACTORS, "act_role", "Run and jump", "Set its behaviour to 'Platform player' - it walks on the hills and jumps with fire.", function() { return array_length(proj.actors) >= 1 && proj.actors[0].role == 6; }),
                les_step(WS_ACTORS, "act_anim", "Animate it", "Choose sprite 4 as the second frame, and switch on 'Only when moving'.", function() { return array_length(proj.actors) >= 1 && proj.actors[0].anim_sprite >= 0; }),
                les_step(WS_ACTORS, "act_add", "An enemy", "Add an actor, give it sprite 2 and the 'Hopper' behaviour.", function() { return les_role_has(7); }),
                les_step(WS_ACTORS, "act_add", "A gem", "Add one more actor with sprite 3 and the 'Faller' behaviour - it drops onto the hills.", function() { return les_role_has(8); }),
                les_step(WS_LOGIC, "logic_addgroup", "Tidy rules with groups", "Add a group. You can name it, fold it away, or switch it off while testing.", function() { return array_length(proj.groups) >= 1; }),
                les_step(WS_LOGIC, "logic_tpl_0", "Ouch", "This recipe adds a group of rules for when the player touches an enemy: lose a life, go back to the start, flash, and stay safe for a moment so one hop can't take every life.", function() { return les_rule_has(0, 1); }),
                les_step(WS_LOGIC, "logic_add", "A jump sound", "Add a rule: WHEN 'Actor jumps' (your hero), DO 'Play a sound'. Pick sound 4 - Jump.", function() { return les_rule_has(6, 2); }),
                les_step(WS_LOGIC, "logic_add", "Collect gems", "Add a rule: WHEN player touches the gem, DO 'Count towards the level goal'. Add another: same WHEN, DO 'Move actor to a random spot' (the gem).", function() { return les_rule_has(0, 17) && les_rule_has(0, 5); }),
                les_step(WS_LOGIC, "logic_tpl_3", "Game over", "This recipe ends the game when the lives run out.", function() { return les_rule_has(4, 9); }),
                les_step(WS_LEVELS, "lvl_goal_on", "The level goal", "Switch on the goal counter and set how many gems finish a level.", function() { return proj.goal_on; }),
                les_step(WS_LEVELS, "lvl_title_on", "Title screen", "Switch on the title screen and type your game's title.", function() { return proj.title_on; }),
                les_step(WS_HOME, "home_lives", "Lives", "Choose how many lives the player starts with.", undefined),
                les_step(WS_BUILD, "build_run", "Build and play", "Build it and get through all three levels.", function() { return les_built(); }),
                les_step(WS_BUILD, "", "That's a real platformer!", "Levels, hills, animation, enemies, lives, a goal and a title. Experienced adds the A1200, imported art, timed rules, samples and music.", undefined)
            ]
        },
        {
            name : "Experienced - The full suite", short : "Experienced", mins : 35, pro : false,
            steps : [
                les_step(WS_HOME, "", "Lesson 4: Experienced", "Everything ADAM can do, for the Amiga 1200: imported art, more colours, timed and level rules, your own samples, songs for each level, and checking memory. A fresh project has been started for you.", undefined),
                les_step(WS_HOME, "top_machine", "The Amiga 1200", "Click the machine button and choose the Amiga 1200 (AGA, 2MB chip RAM).", function() { return proj.machine == "A1200"; }),
                les_step(WS_BACKDROP, "bd_depth", "More colours", "The 1200 allows up to 128 backdrop colours. Choose 32 or more.", function() { return proj.depth >= 5; }),
                les_step(WS_BACKDROP, "bd_import", "Import a picture", "Import a PNG or JPG - ADAM fits it to 320 x 256 and picks the best colours. No picture handy? Paint a full backdrop instead.", function() { return les_bd_painted() >= 20000; }),
                les_step(WS_BACKDROP, "bd_solid", "Ground colours", "Click the colours your platforms are made of and tick 'Ground colour' for each. Platform players walk along the top of them.", function() { var _s = false; for (var i = 0; i < array_length(proj.solid); i++) { if (proj.solid[i] != 0) { _s = true; } } return _s; }),
                les_step(WS_SPRITES, "spr_pen_0", "Sprites and colour pairs", "The Amiga has 8 hardware sprites in 4 colour pairs. Actors whose sprites share the same 3 colours are paired for free - so reuse colours where you can.", undefined),
                les_step(WS_SPRITES, "spr_grid", "Draw the cast", "Draw a hero, two kinds of enemy, a pickup and a bonus: five sprites in all.", function() { return les_spr_px(0) >= 20 && les_spr_px(1) >= 12 && les_spr_px(2) >= 12 && les_spr_px(3) >= 6 && les_spr_px(4) >= 6; }),
                les_step(WS_ACTORS, "act_add", "Place the cast", "Add a Platform player, a Chaser and a Patrol enemy, and a Still pickup.", function() { return les_role_has(6) && les_role_has(4) && (les_role_has(2) || les_role_has(3)) && les_role_has(5); }),
                les_step(WS_ACTORS, "act_vis", "A hidden bonus", "Add one more actor for the bonus and switch 'Visible at start' off. A rule will show it later.", function() { var _h = false; for (var i = 0; i < array_length(proj.actors); i++) { if (!proj.actors[i].visible) { _h = true; } } return _h; }),
                les_step(WS_LEVELS, "lvl_on", "Levels", "Switch levels on and make at least three.", function() { return proj.levels_on && array_length(proj.levels) >= 3; }),
                les_step(WS_ACTORS, "act_from", "Harder later", "Pick an enemy and set 'Joins on level' to 2, so it only turns up from level 2. '+1 speed every' makes it faster on later levels.", function() { var _f = false; for (var i = 0; i < array_length(proj.actors); i++) { if (proj.actors[i].from_level >= 2) { _f = true; } } return _f; }),
                les_step(WS_LOGIC, "logic_add", "Timed rules", "Add: WHEN 'Every few seconds', DO 'Show actor for a moment' (the bonus).", function() { return les_rule_has(2, 15); }),
                les_step(WS_LOGIC, "logic_add", "Level rules", "Add a rule that uses WHEN 'A level starts' - for example, flash the screen or send the chaser back to its start.", function() { return les_rule_has(7, -1); }),
                les_step(WS_LOGIC, "logic_addgroup", "Organise", "Put your rules into at least two named groups.", function() { return array_length(proj.groups) >= 2; }),
                les_step(WS_SOUND, "snd_kind_1", "Your own sample", "Switch a sound to Sample and import a WAV. Lower the rate and bits for a crunchier sound that uses less chip RAM. (No WAV? Skip this.)", function() { for (var i = 0; i < array_length(proj.sfx); i++) { if (proj.sfx[i].kind == 1 && proj.sfx[i].smp != "") { return true; } } return false; }),
                les_step(WS_MUSIC, "mus_first", "A song", "Make a song and paint drums and bass onto at least 8 bars.", function() { return les_song_bars(0, 8); }),
                les_step(WS_MUSIC, "mus_grid", "Make a loop your own", "Double-click a bar to open its notes and change a few. It becomes your own loop under Mine.", function() { return les_loop_edited(); }),
                les_step(WS_MUSIC, "mus_new", "A second song", "Make a second song, then under 'Where the music plays' give level 2 the new song.", function() { return array_length(proj.songs) >= 2 && proj.level_song[1] == 1; }),
                les_step(WS_LOGIC, "logic_add", "Music rules", "Add a rule with DO 'Stop music' or 'Play music' - for example, stop the music when the player touches the chaser.", function() { return les_rule_has(-1, 18) || les_rule_has(-1, 19); }),
                les_step(WS_BUILD, "build_adf", "Build and check memory", "Build the disk, then hover the chip RAM bar: engine, backdrop, sounds and music must all fit in chip RAM.", function() { return les_built(); }),
                les_step(WS_BUILD, "build_run", "Play it on the 1200", "Build and play. Try every level, and listen for the songs changing.", function() { return les_built(); }),
                les_step(WS_BUILD, "", "You've used it all!", "Machine choice, imported art, colour depth, sprite pairs, every kind of actor, timed and level rules, samples, songs, levels and memory. Over to you - make something great.", undefined)
            ]
        },
        {
            name : "Pro - BOBs: Swarm", short : "Pro BOBs", mins : 15, pro : true,
            steps : [
                les_step(WS_HOME, "", "Lesson 5: BOBs (ADAM Pro)", "The Amiga has only 8 hardware sprites. BOBs - blitter objects - are drawn into the picture by the Amiga's blitter chip instead, so a game can have up to 32 actors. You'll make Swarm: dodge a cloud of buzzing bugs for as long as you can. A fresh project has been started for you.", undefined),
                les_step(WS_BACKDROP, "bd_clear", "Paint the sky", "Pick a dark colour in the palette and fill the backdrop with it - the bugs will show up best on a dark sky.", function() { return les_bd_at(0, 0) != 0; }),
                les_step(WS_SPRITES, "spr_grid", "Draw yourself", "Draw your hero in sprite 1 - 20 squares or more.", function() { return les_spr_px(0) >= 20; }),
                les_step(WS_SPRITES, "spr_slot_1", "Draw a bug", "Click sprite 2 and draw a small bug. BOBs use the nearest backdrop colours, so pick bright pens that stand out.", function() { return les_spr_px(1) >= 8; }),
                les_step(WS_ACTORS, "act_add", "Add yourself", "Add the first actor - it becomes the player.", function() { return array_length(proj.actors) >= 1; }),
                les_step(WS_ACTORS, "act_add", "Add a bug", "Add a second actor. It picks the next sprite, so it is already your bug.", function() { return array_length(proj.actors) >= 2; }),
                les_step(WS_ACTORS, "act_role", "Make it buzz", "Set the bug's behaviour to Bouncer.", function() { return array_length(proj.actors) >= 2 && proj.actors[1].role == 1; }),
                les_step(WS_ACTORS, "act_bob", "Make it a BOB", "Switch on 'Draw as a BOB'. The bug no longer needs one of the 8 hardware sprites - the blitter draws it into the backdrop every frame.", function() { return array_length(proj.actors) >= 2 && proj.actors[1].bob; }),
                les_step(WS_ACTORS, "act_dup", "A swarm", "With the bug selected, press Duplicate until there are 12 bugs. Twelve flying things at once is more than the sprites could ever do.", function() { return les_bob_count() >= 12; }),
                les_step(WS_ACTORS, "act_stage", "Spread them out", "Drag some bugs to new places, and set a few to start moving left or up, so the swarm comes from everywhere.", undefined),
                les_step(WS_LOGIC, "logic_add", "Don't get stung", "Add a rule: WHEN the player touches the player - the same actor twice means 'touches anything' - DO 'Lose a life'. One rule covers every bug.", function() { return les_touch_any(1); }),
                les_step(WS_LOGIC, "logic_add", "Shake them off", "Add two more rules with the same WHEN: 'Move actor back to its start' (the player) and 'Safe for a while' (the player), so one bug can't take every life.", function() { return les_touch_any(4) && les_touch_any(16); }),
                les_step(WS_LOGIC, "logic_add", "Score for surviving", "Add: WHEN 'Every few seconds' (1 second), DO 'Add to score'.", function() { return les_rule_has(2, 0); }),
                les_step(WS_LOGIC, "logic_tpl_3", "Game over", "This recipe ends the game when the lives run out.", function() { return les_rule_has(4, 9); }),
                les_step(WS_BUILD, "build_run", "Build and play", "Build and play. The Build checklist counts your sprites and BOBs. Each BOB costs blitter time every frame: on the A500 about 20 is plenty, the A1200 copes with more.", function() { return les_built(); }),
                les_step(WS_BUILD, "", "That's a swarm!", "BOBs give you as many moving things as a real Amiga game. To see them in a finished game, load the Firefly Night example: 12 fireflies are BOBs, the owl and the bats are sprites.", undefined)
            ]
        }
    ];
}

/// How many actors are set to BOB
function les_bob_count()
{
    var _n = 0;
    for (var i = 0; i < array_length(proj.actors); i++)
    {
        if (proj.actors[i].bob) { _n += 1; }
    }
    return _n;
}

/// Is there a 'touches anything' rule (same actor twice) with this DO?
function les_touch_any(_act)
{
    for (var i = 0; i < array_length(proj.rules); i++)
    {
        var _r = proj.rules[i];
        if (_r.when == 0 && _r.a == _r.b && _r.act == _act) { return true; }
    }
    return false;
}

/// Starts lesson _i on a fresh project
function lesson_start(_i)
{
    if (les_defs[_i].pro)
    {
        if (!pro_gate("The " + les_defs[_i].short + " lesson")) { return; }
    }
    if (proj_dirty)
    {
        confirm_open("Start the lesson?", confirm_unsaved_text("A lesson starts a new project, which"), "Start lesson", "Cancel", true, lesson_start_now, _i);
        return;
    }
    lesson_start_now(_i);
}

function lesson_start_now(_i)
{
    var _machine = proj.machine;
    proj = project_new();
    proj.machine = _machine;
    proj_path = "";
    proj_dirty = false;
    undo_clear_all();
    project_after_change();
    tut_active = false;
    tut_offer_on = false;
    // the lesson game gets its own disk (the disk path follows the project)
    out_path = game_save_id + "Lesson_" + les_defs[_i].short + ".adf";
    les_active = true;
    les_id = _i;
    les_steps = les_defs[_i].steps;
    lesson_go(0);
}

/// Moves to step _n and opens its page
function lesson_go(_n)
{
    les_index = clamp(_n, 0, array_length(les_steps) - 1);
    les_anim = 0;
    les_done_t = -1;
    les_step_t = current_time;
    les_check_timer = 0;
    var _st = les_steps[les_index];
    lesson_show_step(_st);
}

/// Opens the page a step is on, with the part of the page that holds its target
function lesson_show_step(_st)
{
    if (ws != _st.tab) { ws_set(_st.tab); }
    // the Backdrop page remembers Paint / Copper sky - its paint steps need Paint
    if (_st.tab == WS_BACKDROP && _st.target != "bd_tab_sky") { bd_panel = 0; }
}

function lesson_finish()
{
    les_done[les_id] = true;
    lesson_stop();
    toast("Lesson complete: " + les_defs[les_id].short, 0);
}

/// Ends the lesson; the project (and its disk path) stays
function lesson_stop()
{
    les_active = false;
    settings_save();
}

/// Names for the Learn menu, with the guided tour first
/// The Learn ADAM menu (top bar): this page's tutorial, then lesson_menu_names()
function learn_menu_names()
{
    var _n = ["Tutorial for this page: " + ws_name(ws) + "  (F1)"];
    var _l = lesson_menu_names();
    for (var i = 0; i < array_length(_l); i++) { array_push(_n, _l[i]); }
    array_push(_n, "What's new in ADAM " + ADAM_VERSION);
    return _n;
}

function lesson_menu_names()
{
    var _n = ["Guided tour - what every page does (5 min)"];
    for (var i = 0; i < array_length(les_defs); i++)
    {
        var _s = string(i + 1) + ". " + les_defs[i].name + "  (" + string(les_defs[i].mins) + " min)";
        if (les_defs[i].pro && !pro_edition()) { _s += "  - Pro"; }
        if (les_done[i]) { _s += "  - done"; }
        array_push(_n, _s);
    }
    return _n;
}

/// The lesson card (drawn after the page so ui_rects holds this frame's controls)
function lesson_draw(_gw, _gh)
{
    if (!les_active || tut_active || machine_pick_active || about_active || whatsnew_active)
    {
        les_card_rect = [0, 0, 0, 0];
        return;
    }
    var _st = les_steps[les_index];
    les_anim = lerp(les_anim, 1, 0.15);
    var _a = les_anim;
    var _has_check = !is_undefined(_st.check);
    var _on_page = (ws == _st.tab);

    // tick the task off (checked a few times a second, not every frame)
    if (_has_check && les_done_t < 0 && _on_page)
    {
        les_check_timer -= 1;
        if (les_check_timer <= 0)
        {
            les_check_timer = 8;
            if (_st.check()) { les_done_t = current_time; }
        }
    }
    if (les_done_t >= 0 && current_time - les_done_t > 900)
    {
        if (les_index >= array_length(les_steps) - 1) { lesson_finish(); return; }
        lesson_go(les_index + 1);
        return;
    }

    // outline the control to use
    var _r = undefined;
    if (_on_page && _st.target != "") { _r = ds_map_find_value(ui_rects, _st.target); }
    if (!is_undefined(_r))
    {
        var _pulse = 3 + sin(current_time / 220) * 3;
        ui_rrect_line(_r[0] - 6 - _pulse, _r[1] - 6 - _pulse, _r[2] + 6 + _pulse, _r[3] + 6 + _pulse, 10, global.TH.warn, 0.9 * _a, 2);
        ui_glow(_r[0] - 6, _r[1] - 6, _r[2] + 6, _r[3] + 6, 10, global.TH.warn, 0.7 * _a);
    }

    // card: in the bottom corner away from the target
    var _cw = 400;
    var _body = _st.body;
    if (!_on_page) { _body = "This step is on the " + ws_name(_st.tab) + " page."; }
    draw_set_font(global.f_body);
    var _bh = ui_sh_ext(_body, _cw - 48);
    var _ch = 128 + _bh;
    var _cx = _gw - _cw - 20;
    if (!is_undefined(_r))
    {
        if ((_r[0] + _r[2]) * 0.5 > _gw * 0.5) { _cx = 20; }
    }
    var _cy = _gh - 46 - _ch - 14 + (1 - _a) * 20;
    les_card_rect = [_cx, _cy, _cx + _cw, _cy + _ch];
    ui_shadow(_cx, _cy, _cx + _cw, _cy + _ch, 16, 2);
    ui_rrect(_cx, _cy, _cx + _cw, _cy + _ch, 16, global.TH.btn_top, global.TH.panel_bot, _a);
    var _edge = global.TH.warn;
    if (les_done_t >= 0) { _edge = global.TH.accent2; }
    ui_rrect_line(_cx, _cy, _cx + _cw, _cy + _ch, 16, _edge, 0.85 * _a, 1);

    var _n = array_length(les_steps);
    var _head = string_upper(les_defs[les_id].short) + "  -  STEP " + string(les_index + 1) + " OF " + string(_n);
    ui_text(_cx + 24, _cy + 16, _head, global.TH.warn, fa_left, fa_top, global.f_small, _a);
    ui_rrect(_cx + 24, _cy + 36, _cx + _cw - 24, _cy + 40, 2, c_black, c_black, 0.3 * _a);
    ui_rrect(_cx + 24, _cy + 36, _cx + 24 + (_cw - 48) * ((les_index + 1) / _n), _cy + 40, 2, global.TH.warn, global.TH.warn, _a);
    var _title = _st.title;
    if (les_done_t >= 0) { _title = "Done!  " + _title; }
    ui_text(_cx + 24, _cy + 50, _title, c_white, fa_left, fa_top, global.f_title, _a);
    ui_text_wrap(_cx + 24, _cy + 80, _body, global.TH.text_dim, _cw - 48, global.f_body, _a);

    // buttons
    ui_force_input = true;
    var _by = _cy + _ch - 44;
    draw_set_font(global.f_bold);
    var _last = (les_index >= _n - 1);
    var _next_lab = "Next";
    var _next_st = BTN_ACCENT;
    if (_has_check && les_done_t < 0)
    {
        _next_lab = "Skip";
        _next_st = BTN_GHOST;
    }
    if (_last) { _next_lab = "Finish"; }
    if (!_on_page)
    {
        _next_lab = "Go there";
        _next_st = BTN_ACCENT;
    }
    var _nw = max(90, ceil(ui_sw(_next_lab)) + 28);
    if (ui_button("les_next", _cx + _cw - 24 - _nw, _by, _nw, 32, _next_lab, "Next|Skip moves on even if the task isn't done yet.", _next_st))
    {
        if (!_on_page) { lesson_show_step(_st); }
        else
        {
            if (_last) { lesson_finish(); }
            else { lesson_go(les_index + 1); }
        }
    }
    if (les_index > 0)
    {
        if (ui_button("les_back", _cx + _cw - 32 - _nw - 80, _by, 80, 32, "Back", "Back|The previous step.", BTN_GHOST))
        {
            lesson_go(les_index - 1);
        }
    }
    var _qw = ceil(ui_sw("Stop lesson")) + 28;
    if (ui_button("les_quit", _cx + 24, _by, _qw, 32, "Stop lesson", "Stop the lesson|Your project stays as it is. Start the lesson again from Learn ADAM at the top right.", BTN_GHOST))
    {
        lesson_stop();
    }
    ui_force_input = false;
    if (!les_active) { les_card_rect = [0, 0, 0, 0]; }
}

/// Dev check (ADAM_DEV_TOOLS): runs every lesson step's check() on a new
/// project and on each example, so a check that throws shows up at startup
/// instead of in the middle of someone's lesson.
function lessons_selftest()
{
    var _keep = proj;
    var _bad = 0;
    var _runs = 0;
    var _projects = [project_new()];
    for (var e = 0; e < array_length(global.EXAMPLES); e++)
    {
        var _txt = file_read_text(working_directory + "examples/" + global.EXAMPLES[e].file);
        if (_txt != "") { array_push(_projects, project_from_loaded(json_parse(_txt))); }
    }
    for (var p = 0; p < array_length(_projects); p++)
    {
        proj = _projects[p];
        for (var l = 0; l < array_length(les_defs); l++)
        {
            var _steps = les_defs[l].steps;
            for (var s = 0; s < array_length(_steps); s++)
            {
                if (!is_undefined(_steps[s].check))
                {
                    _runs += 1;
                    try
                    {
                        _steps[s].check();
                    }
                    catch (_e)
                    {
                        _bad += 1;
                        show_debug_message("ADAM lesson self-test: " + les_defs[l].short + " step " + string(s + 1) + " threw: " + string(_e.message));
                    }
                }
            }
        }
    }
    proj = _keep;
    if (_bad == 0) { show_debug_message("ADAM lesson self-test: PASS (" + string(_runs) + " checks)"); }
    else { show_debug_message("ADAM lesson self-test: FAIL (" + string(_bad) + " of " + string(_runs) + ")"); }
}
