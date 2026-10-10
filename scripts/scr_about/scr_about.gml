/// ADAM - version number and the About & licences screen

// The one place the version lives. The window title and the About screen use
// it. When it changes, also change option_windows_display_name and
// option_windows_version in options/windows/options_windows.yy
// (tools/release_check.ps1 checks they match).
#macro ADAM_VERSION "1.0.0"
#macro ADAM_COPYRIGHT "(c) 2026 Polytricity Ltd"

/// Opens the About & licences screen over everything
function about_open()
{
    about_active = true;
    about_anim = 0;
    ui_popup_open = false;
    ui_focus = "";
    ds_map_replace(ui_scroll, "about_scroll", 0);
    about_text = about_load_text();
}

/// LICENCES.txt and the full font licence (fonts/OFL.txt), both shipped next to ADAM.exe
function about_load_text()
{
    var _s = file_read_text(working_directory + "LICENCES.txt");
    if (_s == "")
    {
        _s = "LICENCES.txt is missing from the ADAM folder. Please download ADAM again.";
    }
    var _ofl = file_read_text(working_directory + "fonts/OFL.txt");
    if (_ofl != "")
    {
        _s += "\n\n\nTHE POPPINS FONT LICENCE (fonts/OFL.txt)\n\n" + _ofl;
    }
    _s = string_replace_all(_s, "\r", "");
    _s = string_replace_all(_s, "\t", "    ");
    return _s;
}

/// The About & licences screen, drawn over the page while about_active
function about_draw(_gw, _gh)
{
    if (!about_active) { return; }
    about_anim = lerp(about_anim, 1, 0.15);
    var _a = about_anim;
    ui_force_input = true;

    draw_set_alpha(0.8 * _a);
    draw_rectangle_colour(0, 0, _gw, _gh, c_black, c_black, global.TH.bg_bot, global.TH.bg_bot, false);
    draw_set_alpha(1);

    var _w = min(860, _gw - 80);
    var _h = min(720, _gh - 100);
    var _x1 = floor((_gw - _w) / 2);
    var _y1 = floor((_gh - _h) / 2) + round((1 - _a) * 20);
    var _x2 = _x1 + _w;
    var _y2 = _y1 + _h;
    ui_panel(_x1, _y1, _x2, _y2, "");

    // ---------- header ----------
    draw_boing(_x1 + 24, _y1 + 20, 56, _a);
    ui_text(_x1 + 96, _y1 + 18, "ADAM", c_white, fa_left, fa_top, global.f_hero, _a);
    ui_text(_x1 + 96, _y1 + 56, "Version " + ADAM_VERSION + "   " + ADAM_COPYRIGHT, global.TH.text_dim, fa_left, fa_top, global.f_body, _a);
    ui_text(_x2 - 24, _y1 + 28, "About & licences", global.TH.text, fa_right, fa_top, global.f_title, _a);

    // ---------- licence text ----------
    var _tx1 = _x1 + 20;
    var _ty1 = _y1 + 96;
    var _tx2 = _x2 - 20;
    var _ty2 = _y2 - 66;
    ui_inset(_tx1, _ty1, _tx2, _ty2, 8);
    ui_register("about_text", _tx1, _ty1, _tx2, _ty2, "Licences|The fonts and programs ADAM uses, who made them and their licences. Scroll with the mouse wheel or drag the bar on the right. The same text is in LICENCES.txt and fonts/OFL.txt next to ADAM.exe.");
    var _tw = _tx2 - _tx1 - 44;
    draw_set_font(global.f_small);
    var _ch = ui_sh_ext(about_text, _tw) + 32;
    var _off = ui_scroll_begin("about_scroll", _tx1, _ty1, _tx2, _ty2, _ch);
    ui_text_wrap(_tx1 + 16, _ty1 + 16 - _off, about_text, global.TH.text, _tw, global.f_small, _a);
    ui_scroll_end("about_scroll", _tx1, _ty1, _tx2, _ty2, _ch);

    // ---------- buttons ----------
    if (ui_button("about_close", _x2 - 140, _y2 - 52, 120, 36, "Close", "Close|Goes back to ADAM. Esc does the same.", BTN_ACCENT))
    {
        about_active = false;
    }
    ui_text(_x1 + 24, _y2 - 34, "Press Esc to close.", global.TH.text_faint, fa_left, fa_middle, global.f_small, _a);
    if (keyboard_check_pressed(vk_escape))
    {
        about_active = false;
    }
    ui_force_input = false;
}
