/// ADAM - Amiga no-code game maker - app controller

// ---------- display ----------
var _aa = 0;
if ((display_aa & 8) != 0) { _aa = 8; }
else
{
    if ((display_aa & 4) != 0) { _aa = 4; }
    else
    {
        if ((display_aa & 2) != 0) { _aa = 2; }
    }
}
display_reset(_aa, true);
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

// ---------- systems ----------
theme_init();
machine_defs_init();
project_defs_init();
music_defs_init();
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
kick_path = "";
fsuae_light = true;
app_focused = true;
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
bd_dither = true;
bd_panel = 0;
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
spr_surf = [];
for (var i = 0; i < SPR_COUNT; i++) { array_push(spr_surf, [-1, -1, -1]); }
spr_dirty = array_create(SPR_COUNT, true);

// actors
sel_actor = 0;
act_drag = false;
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
snd_cache = {};
snd_cache_count = 0;

// music (Phase 2 Track B)
mus_song = 0;                // song being edited
mus_cat = 0;                 // library category shown (5 = Mine)
mus_brush = [-1, -1];        // [0, library loop] or [1, song loop] painted on the timeline
mus_scroll_bar = 0;          // first bar shown on the timeline
mus_cursor_bar = 0;          // Play starts from this bar
mus_hover = [-1, -1];        // [lane, bar] under the mouse
mus_hsb_grab = 0;
mus_edit = -1;               // song loop open in the step editor
mus_edit_cell = [-1, -1];    // [lane, bar] that was double-clicked
mus_click_time = 0;
mus_click_cell = [-1, -1];
mus_painting = false;
mus_erasing = false;
mus_paint_tag = "";
mus_drag_arm = false;
mus_drag = false;
mus_drag_src = [-1, -1];
mus_drag_mx = 0;
mus_drag_my = 0;
mus_ed_mode = 1;
mus_ed_painting = false;
mus_ed_rclear = false;
mus_ed_tag = "";
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
les_done = array_create(4, false);  // lessons finished (saved in the settings)
les_defs = [];
lessons_init();
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

// lessons: every step check() runs once on a new project and each example (IDE Output window)
if (ADAM_DEV_TOOLS) { lessons_selftest(); }

// pick the Amiga before anything else (the Home tutorial follows it)
machine_pick_open(true);
