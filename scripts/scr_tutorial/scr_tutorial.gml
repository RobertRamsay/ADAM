/// ADAM - tutorials: a full guided tour plus a mini tour per page

function tut_step(_tab, _target, _title, _body)
{
    return { tab : _tab, target : _target, title : _title, body : _body };
}

function tut_init()
{
    tut_steps = [
        // ---------- HOME ----------
        tut_step(WS_HOME, "", "Welcome to ADAM", "You are going to make a real Amiga game without writing a single line of code. This tour visits every page. Use Next and Back, or the arrow keys. Press Esc to leave at any time."),
        tut_step(WS_HOME, "top_machine", "Your Amiga", "This is the machine your game is made for: the Amiga 500/600 (OCS/ECS, 1MB) or the Amiga 1200 (AGA, 2MB). Click it any time to switch. The 1200 allows many more colours."),
        tut_step(WS_HOME, "home_example", "Try an example first", "Pick one of four finished games - Gem Hunter, Deep Dive, Star Catcher or Dodge Ball. They are a great way to see how everything fits together. You can start a New project any time."),
        tut_step(WS_HOME, "home_card_0", "Six simple steps", "Every game is made the same way: paint a backdrop, draw sprites, place actors, write rules, add sounds, then build. Click any card to jump to that page."),
        tut_step(WS_HOME, "home_name", "Name your game", "Give your game a name. It is also used for the file names when you save and build."),
        tut_step(WS_HOME, "home_lives", "Lives and score", "Choose how many lives the player gets and where the score and lives are shown. A rule on the Logic page takes lives away."),
        tut_step(WS_HOME, "home_over", "Messages", "These messages appear when the game ends. The player presses fire to play again."),
        tut_step(WS_HOME, "home_helpers", "Hover helpers", "Rest your mouse on anything and a helper line points to a bubble that explains it. Switch them off here (or with Helpers at the top) once you know your way around."),
        tut_step(WS_HOME, "top_learn", "Learn ADAM", "Up here any time: the tutorial for the page you are on (or press F1), this tour, and lessons that build a whole game with you step by step."),
        tut_step(WS_HOME, "top_play", "Build and play", "When you want to try your game, click Build & play (or press F5) on any page. ADAM makes the Amiga disk and starts it in FS-UAE."),
        tut_step(WS_HOME, "top_undo", "Undo and Redo", "Made a mistake? Undo (Ctrl+Z) takes it back and Redo (Ctrl+Y) puts it back again. Every page keeps its own history, so undoing on one page never touches the others."),
        // ---------- BACKDROP ----------
        tut_step(WS_BACKDROP, "bd_canvas", "The backdrop", "This is your game's background: 320 x 256 pixels, the classic PAL Amiga low-res screen. Actors move on top of it. Left-click paints, right-click paints colour 0."),
        tut_step(WS_BACKDROP, "bd_tool_0", "Painting tools", "Brush, line, box, flood fill, text and colour pick. Alt-click picks a colour with any tool. The mouse wheel zooms in for detail."),
        tut_step(WS_BACKDROP, "bd_depth", "How many colours", "Every extra bitplane doubles the colours: 16 on the Amiga 500/600, up to 128 on the 1200. Colour 0 is also the border."),
        tut_step(WS_BACKDROP, "bd_pal", "The palette", "Click a colour to paint with it. The sliders below mix it from red, green and blue - 4096 colours on the 500/600 and 16.8 million on the 1200."),
        tut_step(WS_BACKDROP, "bd_import", "Import a picture", "Got artwork already? Import a PNG or JPG. ADAM fits it to the screen and chooses the best colours for it, with optional dithering."),
        tut_step(WS_BACKDROP, "bd_solid", "Ground colours", "Mark the colours of your grass, floors and platforms as ground. Platform players, hoppers and fallers walk along the top of them - up and down every hill."),
        tut_step(WS_BACKDROP, "bd_tab_sky", "Copper sky", "The classic Amiga trick: the copper chip changes colour 0 on every line, painting a smooth sunset, sea or night sky behind your backdrop for free. Paint the sky areas in colour 0 to let it show."),
        // ---------- LEVELS ----------
        tut_step(WS_LEVELS, "lvl_on", "Levels", "Switch levels on for a game of up to 10 levels. Each one has its own hills for platform players, hoppers and fallers to walk on."),
        tut_step(WS_LEVELS, "lvl_canvas", "Shape the ground", "Drag across the picture to draw where the ground is, or right-drag to smooth it. The hills are drawn by the Amiga at the start of each level, so they cost almost no memory."),
        tut_step(WS_LEVELS, "lvl_gen", "Grow hills from a seed", "Every level starts from a seed number. The same seed always grows the same hills - change it and press Generate for a new shape."),
        tut_step(WS_LEVELS, "lvl_goal_on", "The level goal", "Show a counter like GEMS 00/20. The 'Count towards the level goal' action adds one, and reaching the target moves on to the next level."),
        tut_step(WS_LEVELS, "lvl_title_on", "Title and level cards", "A title screen before the game, a 'LEVEL 2 - PRESS FIRE' card between levels, and your Win message after the last one."),
        // ---------- SPRITES ----------
        tut_step(WS_SPRITES, "spr_slot_0", "Your sprites", "Sprites are the pictures for the things that move. Each one is an Amiga hardware sprite: 16 pixels wide, 24 tall, 3 colours plus see-through."),
        tut_step(WS_SPRITES, "spr_grid", "Draw pixels", "Left-click draws with the selected pen, right-click rubs out."),
        tut_step(WS_SPRITES, "spr_pen_0", "Three colours", "Pick a pen, then mix its colour with the sliders below. Every sprite has its own three colours."),
        tut_step(WS_SPRITES, "spr_name", "Name it", "Give each sprite a name - you will pick sprites by name on the Actors page."),
        tut_step(WS_SPRITES, "spr_op_fliph", "Quick changes", "Flip, shift, copy and paste the whole sprite with one click. Flip H makes a character face the other way."),
        // ---------- ACTORS ----------
        tut_step(WS_ACTORS, "act_add", "Add actors", "Actors are the things in your game: the player, enemies, pickups. Each one is one of the Amiga's 8 hardware sprites. The first actor you add is your player."),
        tut_step(WS_ACTORS, "act_stage", "Place them", "Drag actors around the stage to choose where they start. Guide lines show the exact position while you drag."),
        tut_step(WS_ACTORS, "act_role", "Choose a behaviour", "This is the magic part: a Player follows the joystick, a Chaser hunts the player, Bouncers bounce and Still things stay put. No code needed."),
        tut_step(WS_ACTORS, "act_speed", "Speed", "How fast this actor moves. Try 1 or 2 for enemies to start with - you can always speed them up with a rule."),
        tut_step(WS_ACTORS, "act_vis", "Hidden actors", "Actors can start hidden and appear later using the 'Show actor' action."),
        tut_step(WS_ACTORS, "act_anim", "Animation", "Give an actor a second sprite and it flips between the two - a walk cycle, a flapping fin or a twinkling star. 'Only when moving' is perfect for walking."),
        // ---------- LOGIC ----------
        tut_step(WS_LOGIC, "", "Rules make it a game", "Each rule is a sentence: WHEN something happens, DO something. For example: WHEN Hero touches Gem, DO add 10 to the score."),
        tut_step(WS_LOGIC, "logic_add", "Add a rule", "Press this to add a new rule, then change its parts with the drop-down menus."),
        tut_step(WS_LOGIC, "rule_0_when", "The WHEN part", "Choose what triggers the rule: two actors touching, the fire button, a timer, a score target, running out of lives or the game starting. (Add a rule first if the list is empty.)"),
        tut_step(WS_LOGIC, "rule_0_act", "The DO part", "Choose what happens: add score, lose or gain a life, play a sound, move or hide actors, change the background colour, win or game over."),
        tut_step(WS_LOGIC, "logic_addgroup", "Groups", "Keep related rules together in named groups, like 'Hoppers hit the hero'. Collapse a group to tidy the list, or switch it off to test your game without those rules."),
        tut_step(WS_LOGIC, "logic_tpl_0", "Quick recipes", "Not sure where to start? These buttons add complete, ready-made rules for the most common game ideas."),
        // ---------- SOUND ----------
        tut_step(WS_SOUND, "snd_slot_0", "Eight sound effects", "Your game has 8 sound slots. Pick one to edit it, or press Play to hear it."),
        tut_step(WS_SOUND, "snd_preset_0", "Start from a preset", "The quickest way to a good sound: pick a preset like Coin or Explosion, then tweak it."),
        tut_step(WS_SOUND, "snd_wave", "Waveform", "The basic tone: soft triangle, buzzy sawtooth, classic square or crunchy noise."),
        tut_step(WS_SOUND, "snd_sweep", "Pitch slide", "Make the pitch rise or fall. Falling slides sound like lasers, rising slides like coins and power-ups."),
        tut_step(WS_SOUND, "snd_preview", "Listen", "ADAM turns the sound into a sample for the Amiga's Paula chip, so what you hear here is exactly what the game plays."),
        tut_step(WS_SOUND, "snd_kind_1", "Your own samples", "Switch a sound to Sample to import a WAV file. Lower the sample rate and the bits for that crunchy Amiga sound - and to save chip RAM."),
        // ---------- MUSIC ----------
        tut_step(WS_MUSIC, "", "Make some music", "Songs are built from 1-bar loops, like a music maker: pick a loop on the left, paint it onto the timeline, press Play. The Amiga plays your song as a real ProTracker module."),
        tut_step(WS_MUSIC, "mus_song", "Your songs", "A game can have up to 4 songs. Press New to start one, or Import .mod to bring in a module made in ProTracker or OpenMPT."),
        tut_step(WS_MUSIC, "mus_cat_0", "The loop library", "Drums, bass, chords, lead and effects. Every loop is one bar long and ready to use. Loops you edit are kept under Mine."),
        tut_step(WS_MUSIC, "mus_lib_item_0", "Hear a loop", "Click a loop to hear it - it also becomes your brush. Drag it onto a bar, or click and drag along a lane to paint it."),
        tut_step(WS_MUSIC, "mus_grid", "The timeline", "Four lanes - one for each of Paula's sound channels - and one box per bar. Right-click rubs out, drag a box to copy it, and double-click a box to edit its notes."),
        tut_step(WS_MUSIC, "mus_play", "Play it", "Hear the whole song exactly as the Amiga will play it, with a moving playhead. The Space bar plays and stops too. Click a bar number to play from there."),
        tut_step(WS_MUSIC, "mus_bpm", "Tempo and swing", "Set the speed in beats per minute, and add swing to push every second 16th note late for a shuffle."),
        tut_step(WS_MUSIC, "mus_loopbar", "Loop point", "When the song reaches its end it jumps back to this bar, so an intro can play once and the rest repeats. Right-click a bar number to set it as well."),
        tut_step(WS_MUSIC, "mus_lvl_0", "Where the music plays", "Choose the song for each level, or for the whole game if it has a single screen. Music shares the 4 channels with your sound effects."),
        // ---------- BUILD ----------
        tut_step(WS_BUILD, "", "Time to play", "This page turns your project into a bootable Amiga floppy disk. The checklist warns you about anything that might be missing."),
        tut_step(WS_BUILD, "build_adf", "Build", "Press Build to create an .ADF disk image. It boots in FS-UAE or WinUAE, on a Gotek drive, or written to a real floppy."),
        tut_step(WS_BUILD, "build_fsuae", "Set up FS-UAE", "FS-UAE is a free Amiga emulator. Point ADAM at fs-uae.exe once and it will remember. No Kickstart ROM is needed - FS-UAE's free AROS ROM boots ADAM games."),
        tut_step(WS_BUILD, "build_run", "Build and play", "Builds your game and boots it straight away on a stock Amiga of the type you picked."),
        tut_step(WS_BUILD, "build_showasm", "Peek under the hood", "Curious? This shows the 68000 engine your game runs on. ADAM never writes code: your game is data that the engine reads."),
        tut_step(WS_BUILD, "", "You're ready!", "That's everything. Load the example, change something, build it and see what happens. Have fun making Amiga games!")
    ];
    tut_active = false;
    tut_list = [];
    tut_index = 0;
    tut_anim = 0;
    tut_target_rect = [];
    tut_card_rect = [0, 0, 0, 0];
    tut_allow_target = true;
}

/// _tab = -1 for the full tour, otherwise just that page
function tut_start(_tab)
{
    tut_list = [];
    var _tabs = ws_tabs();
    for (var i = 0; i < array_length(tut_steps); i++)
    {
        var _visible = false;
        for (var t = 0; t < array_length(_tabs); t++)
        {
            if (_tabs[t] == tut_steps[i].tab) { _visible = true; }
        }
        if (_tab < 0 && _visible) { array_push(tut_list, i); }
        if (_tab >= 0 && tut_steps[i].tab == _tab) { array_push(tut_list, i); }
    }
    if (array_length(tut_list) == 0) { return; }
    tut_index = 0;
    tut_active = true;
    tut_offer_on = false;
    tut_anim = 0;
    ui_popup_open = false;
    ui_focus = "";
    if (_tab >= 0)
    {
        ws_seen[_tab] = true;
        settings_save();
    }
}

function tut_draw(_gw, _gh)
{
    if (!tut_active) { return; }
    var _step = tut_steps[tut_list[tut_index]];
    if (_step.tab != ws)
    {
        ws = _step.tab;
        ui_popup_open = false;
        tut_target_rect = [];
        return;
    }
    tut_anim = lerp(tut_anim, 1, 0.15);
    var _a = tut_anim;
    var _r = undefined;
    if (_step.target != "") { _r = ds_map_find_value(ui_rects, _step.target); }
    var _dim = 0.62 * _a;
    if (is_undefined(_r))
    {
        tut_target_rect = [];
        draw_set_alpha(_dim);
        draw_rectangle_colour(0, 0, _gw, _gh, c_black, c_black, c_black, c_black, false);
        draw_set_alpha(1);
    }
    else
    {
        var _p = 8;
        var _x1 = _r[0] - _p;
        var _y1 = _r[1] - _p;
        var _x2 = _r[2] + _p;
        var _y2 = _r[3] + _p;
        tut_target_rect = [_r[0], _r[1], _r[2], _r[3]];
        draw_set_alpha(_dim);
        draw_set_colour(c_black);
        draw_rectangle(0, 0, _gw, _y1, false);
        draw_rectangle(0, _y2, _gw, _gh, false);
        draw_rectangle(0, _y1, _x1, _y2, false);
        draw_rectangle(_x2, _y1, _gw, _y2, false);
        draw_set_alpha(1);
        var _pulse = 2 + sin(current_time / 220) * 3;
        ui_rrect_line(_x1 - _pulse, _y1 - _pulse, _x2 + _pulse, _y2 + _pulse, 12, global.TH.warn, 0.9 * _a, 2);
        ui_glow(_x1, _y1, _x2, _y2, 10, global.TH.warn, _a);
    }

    // card
    var _cw = 420;
    draw_set_font(global.f_body);
    var _bh = ui_sh_ext(_step.body, _cw - 48);
    var _ch = 144 + _bh;
    var _cx = (_gw - _cw) / 2;
    var _cy = (_gh - _ch) / 2;
    if (!is_undefined(_r))
    {
        _cx = clamp((_r[0] + _r[2]) / 2 - _cw / 2, 16, _gw - _cw - 16);
        if (_r[3] + 40 + _ch < _gh - 44)
        {
            _cy = _r[3] + 40;
        }
        else
        {
            if (_r[1] - 40 - _ch > 66)
            {
                _cy = _r[1] - 40 - _ch;
            }
            else
            {
                _cy = clamp((_r[1] + _r[3]) / 2 - _ch / 2, 70, _gh - _ch - 44);
                if (_r[2] + 40 + _cw < _gw - 16) { _cx = _r[2] + 40; }
                else { _cx = max(16, _r[0] - 40 - _cw); }
            }
        }
        var _tx = clamp((_r[0] + _r[2]) / 2, _cx + 20, _cx + _cw - 20);
        var _ty = _cy;
        var _sx = (_r[0] + _r[2]) / 2;
        var _sy = _r[3] + 10;
        if (_cy < _r[1])
        {
            _ty = _cy + _ch;
            _sy = _r[1] - 10;
        }
        if (_cx >= _r[2] || _cx + _cw <= _r[0])
        {
            _sy = (_r[1] + _r[3]) / 2;
            _ty = _cy + _ch / 2;
            if (_cx >= _r[2]) { _sx = _r[2] + 10; _tx = _cx; }
            else { _sx = _r[0] - 10; _tx = _cx + _cw; }
        }
        ui_leader(_sx, _sy, _tx, _ty, global.TH.warn, _a);
    }
    _cy += (1 - _a) * 20;
    tut_card_rect = [_cx, _cy, _cx + _cw, _cy + _ch];
    ui_shadow(_cx, _cy, _cx + _cw, _cy + _ch, 16, 2);
    ui_rrect(_cx, _cy, _cx + _cw, _cy + _ch, 16, global.TH.btn_top, global.TH.panel_bot, _a);
    ui_rrect_line(_cx, _cy, _cx + _cw, _cy + _ch, 16, global.TH.warn, 0.8 * _a, 1);

    var _n = array_length(tut_list);
    ui_text(_cx + 24, _cy + 18, "STEP " + string(tut_index + 1) + " OF " + string(_n), global.TH.warn, fa_left, fa_top, global.f_small, _a);
    ui_rrect(_cx + 24, _cy + 38, _cx + _cw - 24, _cy + 42, 2, c_black, c_black, 0.3 * _a);
    ui_rrect(_cx + 24, _cy + 38, _cx + 24 + (_cw - 48) * ((tut_index + 1) / _n), _cy + 42, 2, global.TH.warn, global.TH.warn, _a);
    ui_text(_cx + 24, _cy + 52, _step.title, c_white, fa_left, fa_top, global.f_title, _a);
    ui_text_wrap(_cx + 24, _cy + 80, _step.body, global.TH.text_dim, _cw - 48, global.f_body, _a);

    ui_force_input = true;
    var _by = _cy + _ch - 44;
    var _last = (tut_index >= _n - 1);
    var _next_lab = "Next";
    if (_last) { _next_lab = "Finish"; }
    if (ui_button("tut_next", _cx + _cw - 124, _by, 100, 32, _next_lab, "Next step|Or press the right arrow key.", BTN_ACCENT) || keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_enter))
    {
        if (_last) { tut_active = false; }
        else
        {
            tut_index += 1;
            tut_anim = 0.3;
        }
    }
    if (tut_index > 0)
    {
        if (ui_button("tut_back", _cx + _cw - 232, _by, 100, 32, "Back", "Previous step|Or press the left arrow key.", BTN_GHOST) || keyboard_check_pressed(vk_left))
        {
            tut_index = max(0, tut_index - 1);
            tut_anim = 0.3;
        }
    }
    if (ui_button("tut_close", _cx + 24, _by, 100, 32, "Close", "Close tutorial|Or press Esc. Start it again with F1.", BTN_GHOST) || keyboard_check_pressed(vk_escape))
    {
        tut_active = false;
    }
    ui_force_input = false;
    if (!tut_active)
    {
        tut_target_rect = [];
        tut_card_rect = [0, 0, 0, 0];
    }
}

/// Asks before starting a page's tutorial (_tab = -1 offers the guided tour)
function tut_offer(_tab)
{
    tut_offer_on = true;
    tut_offer_tab = _tab;
    tut_offer_anim = 0;
}

/// Small "Show me around?" card in the bottom-right corner. The page stays
/// usable; only clicks on the card itself are taken (see ui_frame_begin).
function tut_offer_draw(_gw, _gh)
{
    if (!tut_offer_on || tut_active || les_active || machine_pick_active || about_active || whatsnew_active)
    {
        tut_offer_rect = [0, 0, 0, 0];
        return;
    }
    tut_offer_anim = lerp(tut_offer_anim, 1, 0.15);
    var _a = tut_offer_anim;
    var _title = "Take the guided tour?";
    var _body = "A quick walk through every page, from painting the backdrop to building a disk.";
    if (tut_offer_tab >= 0)
    {
        _title = "Show me around the " + ws_name(tut_offer_tab) + " page?";
        _body = "A few quick steps point out what each part of this page does.";
    }
    // buttons sized from their labels; the card is at least wide enough for them
    draw_set_font(global.f_bold);
    var _yw = max(90, ceil(ui_sw("Show me")) + 28);
    var _nw = max(90, ceil(ui_sw("Not now")) + 28);
    var _dw = ceil(ui_sw("Don't ask again")) + 28;
    var _cw = max(400, 24 + _dw + 24 + _nw + 8 + _yw + 24);
    draw_set_font(global.f_body);
    var _bh = ui_sh_ext(_body, _cw - 48);
    var _ch = 108 + _bh;
    var _cx = _gw - _cw - 20;
    var _cy = _gh - 46 - _ch - 14 + (1 - _a) * 20;
    tut_offer_rect = [_cx, _cy, _cx + _cw, _cy + _ch];
    ui_shadow(_cx, _cy, _cx + _cw, _cy + _ch, 16, 2);
    ui_rrect(_cx, _cy, _cx + _cw, _cy + _ch, 16, global.TH.btn_top, global.TH.panel_bot, _a);
    ui_rrect_line(_cx, _cy, _cx + _cw, _cy + _ch, 16, global.TH.warn, 0.8 * _a, 1);
    ui_text(_cx + 24, _cy + 18, _title, c_white, fa_left, fa_top, global.f_bold, _a);
    ui_text_wrap(_cx + 24, _cy + 44, _body, global.TH.text_dim, _cw - 48, global.f_body, _a);

    ui_force_input = true;
    var _by = _cy + _ch - 44;
    if (ui_button("tut_offer_yes", _cx + _cw - 24 - _yw, _by, _yw, 32, "Show me", "Start the tutorial|You can start it again any time with F1 or the Tutorial button.", BTN_ACCENT))
    {
        tut_offer_on = false;
        tut_start(tut_offer_tab);
    }
    if (ui_button("tut_offer_no", _cx + _cw - 32 - _yw - _nw, _by, _nw, 32, "Not now", "Not now|Hides this. F1, or Learn ADAM at the top right, still starts it.", BTN_GHOST))
    {
        tut_offer_on = false;
    }
    if (ui_button("tut_offer_never", _cx + 24, _by, _dw, 32, "Don't ask again", "Stop offering tutorials|Turns off 'Offer a tutorial on each new page' (Home page, Studio). Tutorial (F1) still works.", BTN_GHOST))
    {
        tut_offer_on = false;
        auto_tutorials = false;
        settings_save();
    }
    ui_force_input = false;
    if (!tut_offer_on) { tut_offer_rect = [0, 0, 0, 0]; }
}
