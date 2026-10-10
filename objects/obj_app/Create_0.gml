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
global.UI_SCALE_NAMES = ["Auto (fits your screen)", "100%", "125%", "150%", "175%", "200%", "250%", "300%"];
global.UI_SCALE_VALUES = [0, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];

// ---------- systems ----------
theme_init();
machine_defs_init();
project_defs_init();
font_init();
pixel_sprite_init();
boing_init();

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

// ---------- workspaces ----------
ws = WS_HOME;
ws_seen = array_create(WS_COUNT, false);
helpers_on = true;
auto_tutorials = true;
fsuae_path = "";
kick_path = "";
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

// sprites
spr_sel = 0;
spr_pen = 1;
spr_drawing = false;
spr_clip = "";
spr_surf = [];
for (var i = 0; i < SPR_COUNT; i++) { array_push(spr_surf, [-1, -1, -1]); }
spr_dirty = array_create(SPR_COUNT, true);

// actors
sel_actor = 0;
act_drag = false;
act_drag_dx = 0;
act_drag_dy = 0;

// sound
snd_sel = 0;
preview_sound = -1;
preview_buffer = -1;
preview_inst = -1;

// build
build_log = [];
build_listing = [];
build_warnings = [];
build_ok = false;
build_msg = "";
build_size = 0;
build_engine_size = 0;
build_plane_size = 0;
build_sound_size = 0;
build_chip_free = 1;
build_show_asm = false;
launch_pending = "";
launch_timer = 0;

// ---------- tutorials + settings ----------
tut_init();
settings_load();

// ---------- project ----------
proj = project_new();
proj_dirty = false;
undo_stack = [];
redo_stack = [];
undo_last_tag = "";
undo_last_time = 0;
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
fsuae_autodetect();

// pick the Amiga before anything else (the Home tutorial follows it)
machine_pick_open(true);
