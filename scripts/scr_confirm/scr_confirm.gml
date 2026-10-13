/// ADAM - "Are you sure?" panel, drawn in ADAM's own style
/// (show_question is a plain system box on Windows and does not work on macOS)

/// Asks a question over everything. _func(_arg) runs when the yes button is
/// clicked (or Enter pressed); No, Esc or a click outside the panel cancel.
/// _danger makes the yes button red (for things that lose or close something).
function confirm_open(_title, _body, _yes, _no, _danger, _func, _arg)
{
    confirm_active = true;
    confirm_anim = 0;
    confirm_title = _title;
    confirm_body = _body;
    confirm_yes = _yes;
    confirm_no = _no;
    confirm_danger = _danger;
    confirm_func = _func;
    confirm_arg = _arg;
    ui_popup_open = false;
    ui_focus = "";
}

/// The panel, drawn over the page while confirm_active
function confirm_draw(_gw, _gh)
{
    if (!confirm_active) { return; }
    confirm_anim = lerp(confirm_anim, 1, 0.2);
    var _a = confirm_anim;
    ui_force_input = true;

    draw_set_alpha(0.6 * _a);
    draw_rectangle_colour(0, 0, _gw, _gh, c_black, c_black, global.TH.bg_bot, global.TH.bg_bot, false);
    draw_set_alpha(1);

    // buttons sized from their labels; the panel grows (up to the window) so the
    // "Enter = ...   Esc = ..." hint on the left never runs under the buttons
    draw_set_font(global.f_bold);
    var _yw = max(110, ceil(ui_sw(confirm_yes)) + 32);
    var _nw = max(100, ceil(ui_sw(confirm_no)) + 32);
    var _keys = "Enter = " + confirm_yes + "   Esc = " + confirm_no;
    draw_set_font(global.f_small);
    var _kw = ceil(ui_sw(_keys));
    var _w = min(max(520, 24 + _kw + 20 + _nw + 10 + _yw + 24), _gw - 80);
    var _tw = _w - 48;
    draw_set_font(global.f_body);
    var _bh = ceil(ui_sh_ext(confirm_body, _tw));
    if (confirm_body == "") { _bh = 0; }
    var _h = 24 + 34 + 14 + _bh + 28 + 36 + 22;
    var _x1 = floor((_gw - _w) / 2);
    var _y1 = floor((_gh - _h) / 2) + round((1 - _a) * 16);
    var _x2 = _x1 + _w;
    var _y2 = _y1 + _h;
    ui_panel(_x1, _y1, _x2, _y2, "");

    draw_boing(_x1 + 24, _y1 + 24, 30, _a);
    ui_text(_x1 + 66, _y1 + 24 + 15, ui_text_fit(confirm_title, global.f_title, _w - 66 - 24), c_white, fa_left, fa_middle, global.f_title, _a);
    if (_bh > 0)
    {
        ui_text_wrap(_x1 + 24, _y1 + 24 + 34 + 14, confirm_body, global.TH.text, _tw, global.f_body, _a);
    }

    var _by = _y2 - 22 - 36;
    var _style = BTN_ACCENT;
    if (confirm_danger) { _style = BTN_DANGER; }
    var _yes = ui_button("confirm_yes", _x2 - 24 - _yw, _by, _yw, 36, confirm_yes, confirm_yes + "|Or press Enter.", _style);
    var _no = ui_button("confirm_no", _x2 - 24 - _yw - 10 - _nw, _by, _nw, 36, confirm_no, confirm_no + "|Goes back without doing anything. Esc does the same.", BTN_NORMAL);
    ui_text(_x1 + 24, _by + 18, ui_text_fit(_keys, global.f_small, _w - 24 - 20 - _nw - 10 - _yw - 24), global.TH.text_faint, fa_left, fa_middle, global.f_small, _a);

    // a click outside the panel cancels too
    if (ui_pressed && !point_in_rectangle(ui_mx, ui_my, _x1, _y1, _x2, _y2))
    {
        ui_take_click();
        _no = true;
    }
    if (keyboard_check_pressed(vk_escape)) { _no = true; }
    if (keyboard_check_pressed(vk_enter)) { _yes = true; }
    ui_force_input = false;

    if (_yes)
    {
        confirm_active = false;
        confirm_func(confirm_arg);
    }
    else if (_no)
    {
        confirm_active = false;
    }
}

/// Asked by the top-left ball (the quit X)
function app_quit_ask()
{
    var _body = "Your work is kept: it opens again next time you start ADAM.";
    if (proj_dirty)
    {
        _body = "\"" + proj.name + "\" has changes that are not saved to a project file yet. "
            + "ADAM keeps them and brings them back next time you start it - but to keep your own copy, "
            + "click Cancel and use Save on the Home page first.";
    }
    confirm_open("Quit ADAM?", _body, "Quit", "Cancel", true, app_quit_now, 0);
}

function app_quit_now(_unused)
{
    game_end();     // the Game End event autosaves the project and settings
}

/// The body text for "you have unsaved changes" questions
function confirm_unsaved_text(_what)
{
    return "\"" + proj.name + "\" has changes that are not saved to a project file. "
        + _what + " replaces them. To keep them, click Cancel and use Save on the Home page first.";
}
