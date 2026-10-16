/// ADAM - Amiga no-code game maker - app controller

// ---------- display ----------
// 2x anti-aliasing at most: it smooths the rounded corners just as well as
// 8x, and 8x kept eight copies of every screen pixel - about 450 MB of
// graphics memory on a 4K screen (2x: about 210 MB), too much for older cards
app_aa = 0;
if ((display_aa & 2) != 0) { app_aa = 2; }
display_reset(app_aa, true);
draw_set_circle_precision(48);
window_set_min_width(1280);
window_set_min_height(760);
application_surface_draw_enable(false);
gui_w = max(1280, window_get_width());
gui_h = max(720, window_get_height());
display_set_gui_size(gui_w, gui_h);
caption_last = "";
win_w = 0;
win_h = 0;
startup_frames = 0;
ui_scale_pref = 0;
start_fullscreen = true;
wsave_x = -1;
wsave_y = -1;
wsave_w = -1;
wsave_h = -1;
wsave_timer = 0;
global.UI_SCALE_NAMES = ["Auto (fits your screen)", "100%", "125%", "150%", "175%", "200%", "250%", "300%"];
global.UI_SCALE_VALUES = [0, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];
global.pro_preview = ADAM_PRO;  // edition the editor acts as; Shift+F12 flips it in dev builds (pro_preview_toggle)

// ---------- systems ----------
theme_init();
machine_defs_init();
project_defs_init();
music_defs_init();
patch_defs_init();
font_init();
pixel_sprite_init();
boing_init();
examples_init();

// ---------- UI state ----------
ui_mx = 0;
ui_my = 0;
ui_pressed = false;
ui_pressed_raw = false;
ui_held = false;
ui_repeat_id = "";
ui_repeat_next = 0;
ui_repeat_seen = false;
ui_released = false;
ui_rpressed = false;
ui_rheld = false;
ui_wheel = 0;
ui_input_ok = true;
ui_force_input = false;
ui_hot = "";
ui_hot_prev = "";
ui_hot_time = 0;
ui_hot_rect = [];
ui_help_title = "";
ui_help_body = "";
ui_rects = ds_map_create();
ui_anim = ds_map_create();
ui_scroll = ds_map_create();
ui_focus = "";
ui_focus_claimed = false;
ui_drag_id = "";
ui_clip = [0, 0, 0, 0];
ui_clip_on = false;
ui_popup_open = false;
ui_popup_id = "";
ui_popup_kind = 0;
ui_popup_x = 0;
ui_popup_y = 0;
ui_popup_w = 0;
ui_popup_opts = [];
ui_popup_index = 0;
ui_popup_anchor_y = 0;
ui_popup_scroll = 0;
ui_popup_rect = [0, 0, 0, 0];
ui_popup_result_id = "";
ui_popup_result = 0;

help_alpha = 0;
help_last_rect = [];
help_last_title = "";
help_last_body = "";
toasts = [];

// ---------- machine picker ----------
machine_pick_active = false;
machine_pick_launch = false;
machine_pick_anim = 0;
machine_pick_index = 0;
last_machine = "A1200";

// ---------- about & licences screen (Track D) ----------
about_active = false;
about_anim = 0;
about_text = "";
about_page = 0;             // 0 = licences, 1 = ADAM Pro (which edition)

// ---------- workspaces ----------
ws = WS_HOME;
ws_seen = array_create(WS_COUNT, false);
helpers_on = true;
auto_tutorials = true;
tut_offer_on = false;       // "Show me around?" card for a page seen for the first time
tut_offer_tab = 0;          // page it offers (-1 = the guided tour)
tut_offer_anim = 0;
tut_offer_rect = [0, 0, 0, 0];
fsuae_path = "";
kick_paths = array_create(array_length(global.MACHINES), "");  // Kickstart ROM per machine ("" = FS-UAE's AROS)
fsuae_light = true;
fsuae_pad = 0;              // FS-UAE joystick: 0 keyboard (cursors + right Ctrl), 1 gamepad
global.FSUAE_PAD_NAMES = ["Keyboard", "Gamepad"];
app_focused = true;
logo_quit_k = 0;            // top-left ball fading into the quit X (0 ball - 1 X)
confirm_active = false;     // "Are you sure?" panel (scr_confirm)
confirm_anim = 0;
confirm_title = "";
confirm_body = "";
confirm_yes = "";
confirm_no = "";
confirm_danger = false;
confirm_func = app_quit_now;  // run with confirm_arg when the answer is yes
confirm_arg = 0;
out_path = "";

// backdrop
backdrop_gfx_init();
bd_tool = 0;
bd_sel = 1;
bd_brush = 1;
bd_zoom = 0;
bd_pan_x = 0;
bd_pan_y = 0;
bd_panning = false;
bd_pan_mx = 0;
bd_pan_my = 0;
bd_drawing = false;
bd_paint_v = 0;
bd_line_x = 0;
bd_line_y = 0;
bd_text_on = false;
bd_text_x = 0;
bd_text_y = 0;
bd_text_start_x = 0;
bd_show_actors = true;
bd_show_hud = true;
bd_dither = 1;              // picture import: 0 none, 1 smooth (Floyd-Steinberg), 2 pattern (Bayer)
bd_pattern = 0;             // ADAM Pro: index into BD_PATTERN_LEVELS (0 = solid)
bd_grad_to = 0;             // ADAM Pro: gradient tool's end colour
bd_grad_range = false;      // ADAM Pro: gradient goes through the palette colours in between
bd_panel = 0;
bd_pview = 0;               // Palettes tab: the palette being edited / shown (0 = the main one)
bd_pal_look = 0;            // its Quick look drop-down
// 8 x 8 Bayer matrix for ordered dithering (values 0-63)
global.BAYER8 = [
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
];
global.BD_PATTERN_LEVELS = [64, 48, 32, 16, 8];
global.BD_PATTERN_NAMES = ["Solid", "75%", "50%", "25%", "12%"];
bd_show_hills = true;
terr_surf = -1;
terr_key = "";
terr_version = 0;
lvl_sel = 0;
lvl_drawing = false;
lvl_last_x = -1;
sky_stop = 0;

// sprites
spr_sel = 0;
spr_pen = 1;
spr_drawing = false;
spr_last_x = 0;             // last cell painted in this stroke (strokes are joined up)
spr_last_y = 0;
spr_clip = "";
spr_onion = 0;              // onion skin: 0 off, 1 the frame before, 2 before and after
spr_surf = [];
for (var i = 0; i < SPR_COUNT; i++) { array_push(spr_surf, [-1, -1, -1]); }
spr_dirty = array_create(SPR_COUNT, true);

// actors
sel_actor = 0;

// Tiles page
tile_page = 0;              // 0 = Map, 1 = Tile set, 2 = Tools
tile_sel = 1;               // tile picked
tile_pen = 1;               // colour the tile editor draws with
tile_tool = 0;              // map: 0 paint, 1 box, 2 pick, 3 stamp, 4 spawn (shoot 'em up map)
tile_stamp = { name : "", w : 0, h : 0, cells : [] };    // the Stamp tool's block of cells (w 0 = none yet: drag a box to copy one)
tile_spawn_sel = -1;        // the spawner picked (Spawn tool)
tile_spawn_drag = false;    // dragging it
tile_spawn_dx = 0;          // where it was grabbed
tile_spawn_dy = 0;
tile_spawn_act = -1;        // the actor a new spawner sends out (-1: the first flyer)
tile_zoom = 2;              // map view: 0.25, 0.5, 1, 2, 3 or 4
tile_camx = 0;              // map pixel at the top left of the map view
tile_camy = 0;
tile_drawing = false;       // a stroke on the tile editor
tile_painting = false;      // a stroke on the map
tile_paint_v = 0;
tile_box_c = 0;             // where a box started
tile_box_r = 0;
tile_pan = false;           // moving the map view
tile_pan_mx = 0;
tile_pan_my = 0;
tile_pan_cx = 0;
tile_pan_cy = 0;
tile_drag_actor = -1;       // actor being dragged on the map
tile_drag_dx = 0;
tile_drag_dy = 0;
tile_atlas_surf = -1;       // index pictures of the tiles side by side
tile_atlas_buf = -1;
tile_atlas_dirty = true;
tile_map_surf = -1;         // the part of the map in view, drawn from the atlas (a cache)
tile_map_dirty = true;
tile_view_mx = 0;           // map pixel at the top left of that cache
tile_view_my = 0;

// UI page (ADAM Pro custom HUD)
ui_sel_field = 0;           // the field picked
ui_edit_tab = 0;            // 0 = panel frame editor, 1 = font editor
ui_pen = 1;                 // colour the frame editor draws with
ui_font_char = 33;          // character the font editor draws ('A')
ui_drawing = false;         // a stroke on the frame or font editor
ui_drag_field = -1;         // field being dragged on the preview
ui_drag_dx = 0;
ui_drag_dy = 0;
ui_prev_surf = -1;          // the preview: backdrop + panel + fields (index surface)
ui_prev_buf = -1;
ui_prev_key = "";           // what it was drawn from
ui_prev_tick = 0;
ui_page_tab = 0;            // 0 = custom HUD, 1 = loading screen (ADAM Pro)
ls_surf_empty = -1;         // loading screen preview: the picture with the empty bar (RGB)
ls_surf_full = -1;          // ... and with the full bar
ls_buf = -1;
ls_key = "";                // what the preview was drawn from
ls_prog = 1;                // preview progress 0..1
ls_playing = false;         // Play: the bar fills like a real load
ls_piece = 1;               // piece being drawn: 0 left cap, 1 middle tile, 2 right cap
ls_pen = 1;                 // colour the piece editor draws with
ls_drawing = false;         // a stroke on the piece editor
ls_drag = 0;                // bar on the preview: 0 none, 1 moving, 2 resizing
ls_drag_dx = 0;
ls_drag_dy = 0;
ls_pic = { pixels : [], pal : [0, 0], depth : 1, ncol : 2 };  // loadscr_picture() the preview was drawn from
ls_pc = { left : [], mid : [], right : [] };                   // the bar pieces it was drawn with
ls_pic_surfs = [];          // the preview's pictures at a percentage: { surf, x, y, w, h, thr }
ls_psel = 0;                // the picture picked on the Loading screen tab
ls_pdrag = false;           // dragging it on the preview
ls_pdrag_dx = 0;
ls_pdrag_dy = 0;

// Animate page
anim_sel = 0;               // 0 Idle, 1 Walk, 2 Jump, 3 Fall
anim_slot = 0;              // selected frame; the one after the last adds a frame
anim_t0 = 0;                // current_time the preview started
anim_face_left = false;     // preview the frames turned round
anim_test = false;          // drive the preview with arrow keys / WASD / gamepad
anim_test_source = 0;       // 0 = keyboard, 1 = gamepad
anim_test_entry = -1;       // animation the test is playing
anim_test_t0 = 0;           // current_time it started
anim_test_dir = 2;          // 8 directions: last way it moved (0 N .. 7 NW)
anim_test_face = false;     // last moved left
anim_click_id = "";         // double-click: the control clicked last, and when
anim_click_time = 0;
anim_click_added = false;   // that click added a frame (a double-click takes it back)
anim_lib_tab = 0;           // right panel: 0 the sprite bank, 1 the animation library
anim_drag_armed = false;    // an animation was pressed: it is dragged once the mouse moves
anim_drag_on = false;
anim_drag_x0 = 0;
anim_drag_y0 = 0;
anim_drag_frames = [];      // what is dragged: frames, speed, how it plays, turned round, colours, name
anim_drag_rate = 8;
anim_drag_mode = 0;
anim_drag_flip = false;
anim_drag_cols = [0, 0, 0];
anim_drag_label = "";
anim_drag_src = -1;         // the joystick slot it came from (-1 = the library)
anim_drop_k = -1;           // the slot it is over this frame (-1 = none)
act_drag = false;
act_camx = 0;                // tile world: the screen of the map the Actors stage shows
act_camy = 0;
act_drag_dx = 0;
act_drag_dy = 0;
logic_resort = false;
logic_reveal = -1;          // rule struct to scroll into view next frame (-1 = none)
ground_cache = array_create(BD_W, 256);
ground_cache_time = -10000;

// sound
snd_sel = 0;
preview_sound = -1;
preview_buffer = -1;
preview_inst = -1;
preview_source = {};
preview_render = {};
preview_duration = 0;
preview_loop_start = 0;
preview_loop_end = 0;
preview_note_end = 0;
snd_jam_note = -1;
snd_jam_key = -1;
snd_jam_mouse = false;
snd_cache = {};
snd_cache_count = 0;
snd_patch_tab = 0;                    // Patch editor tab: 0 Osc, 1 Filter, 2 Amp, 3 Mod, 4 FX
snd_patch_osc = 0;                    // oscillator shown on the Osc tab
snd_patch_content_h = 0;              // height of the tab's settings last frame (scroll region)
snd_patch_last = array_create(SFX_MAX, 0);  // last render of each patch sound, kept while a slider is dragged
snd_drag = -1;                        // Sound page: sound pressed in the list (dragged onto a folder), -1 = none
snd_drag_y0 = 0;
snd_dragging = false;
snd_ungrouped_open = true;            // the "No folder" header is open

// music (Phase 2 Track B)
mus_song = 0;                // song being edited
mus_cat = 0;                 // library category shown (5 = Mine)
mus_group_selected = -1;
mus_group_hover = -2;        // -2 no drop target, -1 Ungrouped
mus_ungrouped_open = true;
mus_brush = [-1, -1];        // [0, library loop] or [1, song loop] painted on the timeline
mus_scroll_bar = 0;          // first bar shown on the timeline
mus_cursor_bar = 0;          // Play starts from this bar
mus_play_mode = 2;           // 0 current bar, 1 four bars, 2 song
mus_play_bar = 0;            // original song bar where the preview range starts
mus_hover = [-1, -1];        // [lane, bar] under the mouse
mus_hsb_grab = 0;
mus_edit = -1;               // song loop open in the step editor
mus_edit_cell = [-1, -1];    // [lane, bar] that was double-clicked
mus_click_time = 0;
mus_click_cell = [-1, -1];
mus_painting = false;
mus_erasing = false;
mus_paint_tag = "";
mus_stroke_cell = [0, 0];    // [lane, bar] last painted / rubbed out (strokes are joined up)
mus_drag_arm = false;
mus_drag = false;
mus_drag_src = [-1, -1];
mus_drag_mx = 0;
mus_drag_my = 0;
mus_lib_click_loop = -1;
mus_lib_click_time = 0;
mus_ed_mode = 1;
mus_ed_painting = false;
mus_ed_rclear = false;
mus_ed_tag = "";
mus_ed_note_drag = false;
mus_ed_note_copy = false;
mus_ed_note_group = false;
mus_ed_resize_step = -1;
mus_ed_resize_changed = false;
mus_ed_note_glide = false;
mus_ed_note_glide_end = [-1, -1];
mus_ed_note_src = [-1, -1];
mus_ed_note_pitch = 0;
mus_ed_note_inst = 0;
mus_ed_note_moved = false;
mus_ed_note_last = [-1, -1];
mus_ed_note_preview_pitch = -1;
mus_ed_alt_preview_step = -1;
mus_ed_alt_preview_row = -1;
mus_ed_note_fx = 0;
mus_ed_note_fxp = 0;
mus_ed_note_arp = 0;
mus_ed_fx_step = 0;
mus_ed_fx_drag = false;
mus_ed_fx_src = -1;
mus_ed_fx_end = -1;
mus_ed_selected = array_create(MUS_STEPS, false);
mus_ed_select_drag = false;
mus_ed_select_start = [0, 0];
mus_ed_select_end = [0, 0];
mus_ed_select_ref = {};
mus_ed_clip = { notes : [], drums : false };
mus_ed_resolution = 16;
mus_ed_keys_hover = false;   // mouse over the melodic step editor: 1-4 pick the snap instead of a page
mus_rev = 0;                 // bumped on every music edit
mus_warnings = [];
mus_inst_cache = {};
mus_size_ref = {};
mus_size_rev = -1;
mus_size_bytes = 0;
mus_size_warn = [];
mus_pl = {};                 // preview player state
mus_playing = false;
mus_play_what = "";
mus_play_song = -1;
mus_play_ref = {};
mus_play_rev = 0;
mus_play_rebuild_t = 0;
mus_ord_bar = [];
mus_queue = -1;
mus_queue_inst = -1;
mus_bufs = [];
mus_dead_bufs = [];
mus_frames_queued = 0;
mus_play_t0 = 0;

// build
build_log = [];
build_listing = [];
build_warnings = [];
build_ok = false;
build_stamp = -1;           // current_time of the last good build (lessons check it)
build_msg = "";
build_size = 0;
build_engine_size = 0;
build_plane_size = 0;
build_sound_size = 0;
build_chip_free = 1;

// memory bar (bottom of the screen): the game measured again a moment after each change
mem_ok = false;
mem_stale = true;
mem_stale_time = 0;
mem_proj_ref = undefined;   // the project last measured (a new or loaded project re-measures)
mem_machine = "";
mem_size = 0;
mem_plane_size = 0;
mem_sound_size = 0;
mem_chip_free = 1;
mem_disk_free = 1;
mem_engine_size = mem_engine_bytes();
build_show_asm = false;
launch_pending = "";
launch_timer = 0;
fsuae_dl_id = -1;
fsuae_dl_zip = "";
fsuae_dl_got = 0;
fsuae_dl_total = 0;
fsuae_dl_then_run = "";

// ---------- tutorials, lessons + settings ----------
tut_init();
les_active = false;         // a lesson (scr_lessons) is running
les_id = 0;
les_steps = [];
les_index = 0;
les_anim = 0;
les_done_t = -1;            // current_time when this step's task was done, -1 = not yet
les_step_t = 0;             // current_time when this step began
les_check_timer = 0;
les_card_rect = [0, 0, 0, 0];
les_done = array_create(16, false); // lessons finished (saved in the settings) - room for up to 16 entries in les_defs
les_defs = [];
lessons_init();
for (var _ld = array_length(les_done); _ld < array_length(les_defs); _ld++) { array_push(les_done, false); }
update_check_on = true;      // look for a newer ADAM at start-up (scr_update; Home > Game settings)
update_req = -1;
update_latest = "";
update_url = "";
update_notes = "";
update_card_on = false;
update_card_anim = 0;
update_card_rect = [0, 0, 0, 0];
home_set_h = 0;              // height of the Home page settings (they scroll in a short window)
whatsnew_active = false;    // "What's new" panel (scr_whatsnew)
whatsnew_manual = false;    // opened from the Learn ADAM menu (just Close)
whatsnew_anim = 0;
whatsnew_seen = "";         // version whose notes were dismissed with "Don't show again"
settings_first_run = false; // no settings file yet: a brand-new user
settings_load();

// ---------- project ----------
proj = project_new();
proj_dirty = false;
undo_stacks = [];
redo_stacks = [];
undo_last_tag = "";
undo_last_time = 0;
undo_clear_all();
autosave_timer = 0;

// restore the last session
var _keep_path = proj_path;
var _auto = autosave_path();
if (file_exists(_auto))
{
    var _txt = file_read_text(_auto);
    if (_txt != "")
    {
        try
        {
            proj = project_from_loaded(json_parse(_txt));
            toast("Welcome back - your last session was restored", 0);
        }
        catch (_e)
        {
            proj = project_new();
        }
    }
}
proj_path = _keep_path;
project_after_change();

// Track C: packed project files - dev-only round-trip check (IDE Output window)
if (ADAM_DEV_TOOLS) { project_pack_selftest(); }

// Phase 2 Track C: MOD export/import - dev-only round-trip check (IDE Output window),
// also leaves game_save_id + "adam_selftest.mod" to open in OpenMPT / ProTracker
if (ADAM_DEV_TOOLS) { mod_selftest(); }
if (ADAM_DEV_TOOLS) { music_glide_selftest(); }
if (ADAM_DEV_TOOLS) { music_scope_selftest(); }
if (ADAM_DEV_TOOLS) { music_library_effect_selftest(); }
if (ADAM_DEV_TOOLS) { music_notes_clipboard_selftest(); }
if (ADAM_DEV_TOOLS) { sfx_preview_selftest(); }
if (ADAM_DEV_TOOLS) { patch_selftest(); }
if (ADAM_DEV_TOOLS) { loadscr_selftest(); }
if (ADAM_DEV_TOOLS) { music_sample_loop_volume_selftest(); }
if (ADAM_DEV_TOOLS) { music_sampler_controls_selftest(); }

// lessons: every step check() runs once on a new project and each example (IDE Output window)
if (ADAM_DEV_TOOLS) { lessons_selftest(); }

// dev: -adam_build in.adam out.adf builds a disk without the UI, then quits
if (ADAM_DEV_TOOLS) { dev_cli_build(); }

// dev: -adam_shots in.adam outdir saves a PNG of every page, then quits
shot_on = false;
shot_dir = "";
shot_i = 0;
shot_wait = 0;
shot_w = 1920;
shot_h = 1080;
shot_surf = -1;
shot_pages = [
    { ws : WS_HOME,     panel : 0, name : "home" },
    { ws : WS_BACKDROP, panel : 0, name : "backdrop" },
    { ws : WS_BACKDROP, panel : 1, name : "copper_sky" },
    { ws : WS_TILES,    panel : 0, name : "tiles" },
    { ws : WS_UI,       panel : 0, name : "ui" },
    { ws : WS_UI,       panel : 1, name : "loading_screen" },
    { ws : WS_LEVELS,   panel : 0, name : "levels" },
    { ws : WS_SPRITES,  panel : 0, name : "sprites" },
    { ws : WS_ACTORS,   panel : 0, name : "actors" },
    { ws : WS_ANIMATE,  panel : 0, name : "animate" },
    { ws : WS_LOGIC,    panel : 0, name : "logic" },
    { ws : WS_SOUND,    panel : 0, name : "sound" },
    { ws : WS_MUSIC,    panel : 0, name : "music" },
    { ws : WS_BUILD,    panel : 0, name : "build" }
];
if (ADAM_DEV_TOOLS) { dev_cli_shots(); }

// pick the Amiga before anything else (the Home tutorial follows it)
machine_pick_open(true);

// a newer ADAM on itch.io? (a card shows if so)
if (!shot_on) { update_check_start(); }
