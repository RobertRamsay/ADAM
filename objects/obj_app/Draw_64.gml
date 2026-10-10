/// The whole studio is drawn here in GUI space

ui_frame_begin();
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
    case WS_LOGIC:    ws_logic_draw(_x1, _y1, _x2, _y2);    break;
    case WS_SOUND:    ws_sound_draw(_x1, _y1, _x2, _y2);    break;
    case WS_BUILD:    ws_build_draw(_x1, _y1, _x2, _y2);    break;
    case WS_LEVELS:   ws_levels_draw(_x1, _y1, _x2, _y2);   break;
}

draw_topbar(gui_w);
ui_status_bar(gui_w, gui_h);
ui_popup_draw(gui_w, gui_h);
about_draw(gui_w, gui_h);
ui_help_draw(gui_w, gui_h);
toasts_draw(gui_w, gui_h);
tut_offer_draw(gui_w, gui_h);
tut_draw(gui_w, gui_h);
machine_pick_draw(gui_w, gui_h);
ui_frame_end();

draw_set_colour(c_white);
draw_set_alpha(1);
