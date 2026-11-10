/// The whole studio is drawn here in GUI space
/// Runs every frame after Step_0 (which has already set the UI scale and
/// GUI size, autosaved and handled shortcuts). Order matters:
///  1. ui_frame_begin - read the mouse, clear hover / rects, decide ui_input_ok.
///  2. the current page's ws_*_draw inside the area between top bar and status bar
///     (16 px side margins, top at 76, bottom 46 above the window edge).
///  3. top bar and status bar, then the popup list, cards and modals, each on
///     top of the last; the modals block page input through ui_input_ok, which
///     was already worked out in step 1.
///  4. hover help last so it is never hidden, then ui_frame_end.
/// A control drawn later wins ui_hot when rects overlap, and the first control
/// that takes the click (ui_take_click) stops later ones reacting.

ui_frame_begin();
var _shot = dev_shots_begin();
ui_background(gui_w, gui_h);

var _x1 = 16;
var _y1 = 76;
var _x2 = gui_w - 16;
var _y2 = gui_h - 46;

switch (ws)
{
    case WS_HOME:     ws_home_draw(_x1, _y1, _x2, _y2);     break;
    case WS_BACKDROP: ws_backdrop_draw(_x1, _y1, _x2, _y2); break;
    case WS_SPRITES:  ws_sprites_draw(_x1, _y1, _x2, _y2);  break;
    case WS_ACTORS:   ws_actors_draw(_x1, _y1, _x2, _y2);   break;
    case WS_ANIMATE:  ws_animate_draw(_x1, _y1, _x2, _y2);  break;
    case WS_TILES:    ws_tiles_draw(_x1, _y1, _x2, _y2);    break;
    case WS_UI:       ws_ui_draw(_x1, _y1, _x2, _y2);       break;
    case WS_LOGIC:    ws_logic_draw(_x1, _y1, _x2, _y2);    break;
    case WS_SOUND:    ws_sound_draw(_x1, _y1, _x2, _y2);    break;
    case WS_MUSIC:    ws_music_draw(_x1, _y1, _x2, _y2);    break;
    case WS_BUILD:    ws_build_draw(_x1, _y1, _x2, _y2);    break;
    case WS_LEVELS:   ws_levels_draw(_x1, _y1, _x2, _y2);   break;
}

draw_topbar(gui_w);
ui_status_bar(gui_w, gui_h);
ui_popup_draw(gui_w, gui_h);
about_draw(gui_w, gui_h);
toasts_draw(gui_w, gui_h);
tut_offer_draw(gui_w, gui_h);
update_card_draw(gui_w, gui_h);
tut_draw(gui_w, gui_h);
lesson_draw(gui_w, gui_h);
whatsnew_draw(gui_w, gui_h);
machine_pick_draw(gui_w, gui_h);
confirm_draw(gui_w, gui_h);
// last, so a help bubble is never hidden under the corner cards or panels
// (and the controls on those cards and panels get their bubbles too)
ui_help_draw(gui_w, gui_h);
ui_frame_end();
if (_shot) { dev_shots_end(); }

draw_set_colour(c_white);
draw_set_alpha(1);
