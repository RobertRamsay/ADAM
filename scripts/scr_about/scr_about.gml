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
    about_page = 0;
}

/// Opens the same screen on the ADAM Pro (licence key) tab
function about_open_pro()
{
    about_open();
    about_page = 1;
    licence_entry = "";
    licence_msg = "";
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
    var _tabw = 130;
    if (ui_tab("about_tab_lic", _x2 - 24 - _tabw * 2, _y1 + 30, _tabw - 2, 32, "Licences", about_page == 0, "Licences|The fonts and programs ADAM uses and their licences.")) { about_page = 0; }
    if (ui_tab("about_tab_pro", _x2 - 24 - _tabw, _y1 + 30, _tabw - 2, 32, "ADAM Pro", about_page == 1, "ADAM Pro|Enter your licence key to unlock the Pro features.")) { about_page = 1; }

    var _tx1 = _x1 + 20;
    var _ty1 = _y1 + 96;
    var _tx2 = _x2 - 20;
    var _ty2 = _y2 - 66;
    if (about_page == 1)
    {
        about_pro_page(_tx1, _ty1, _tx2, _ty2, _a);
    }
    else
    {
        about_licence_text(_tx1, _ty1, _tx2, _ty2, _a);
    }

    // ---------- buttons ----------
    if (ui_button("about_close", _x2 - 140, _y2 - 52, 120, 36, "Close", "Close|Goes back to ADAM. Esc does the same.", BTN_ACCENT))
    {
        about_active = false;
    }
    ui_text(_x1 + 24, _y2 - 34, "Press Esc to close.", global.TH.text_faint, fa_left, fa_middle, global.f_small, _a);
    if (keyboard_check_pressed(vk_escape) && ui_focus == "")
    {
        about_active = false;
    }
    ui_force_input = false;
}

/// The licences text (LICENCES.txt + the font licence), scrolling
function about_licence_text(_tx1, _ty1, _tx2, _ty2, _a)
{
    ui_inset(_tx1, _ty1, _tx2, _ty2, 8);
    ui_register("about_text", _tx1, _ty1, _tx2, _ty2, "Licences|The fonts and programs ADAM uses, who made them and their licences. Scroll with the mouse wheel or drag the bar on the right. The same text is in LICENCES.txt and fonts/OFL.txt next to ADAM.exe.");
    var _tw = _tx2 - _tx1 - 44;
    draw_set_font(global.f_small);
    var _ch = ui_sh_ext(about_text, _tw) + 32;
    var _off = ui_scroll_begin("about_scroll", _tx1, _ty1, _tx2, _ty2, _ch);
    ui_text_wrap(_tx1 + 16, _ty1 + 16 - _off, about_text, global.TH.text, _tw, global.f_small, _a);
    ui_scroll_end("about_scroll", _tx1, _ty1, _tx2, _ty2, _ch);
}

/// ADAM Pro tab: which edition this is, and the licence key box
function about_pro_page(_tx1, _ty1, _tx2, _ty2, _a)
{
    ui_inset(_tx1, _ty1, _tx2, _ty2, 8);
    var _x = _tx1 + 24;
    var _w = _tx2 - _tx1 - 48;
    var _y = _ty1 + 24;
    if (pro_on())
    {
        ui_text(_x, _y, "ADAM Pro is unlocked", global.TH.accent2, fa_left, fa_top, global.f_title, _a);
        _y += 44;
        var _thanks = "Thank you for supporting ADAM! All the Pro features are on for this computer.";
        if (ADAM_PRO_OVERRIDE == 1) { _thanks = "Pro is switched on for testing (ADAM_PRO_OVERRIDE in scr_licence)."; }
        ui_text_wrap(_x, _y, _thanks, global.TH.text, _w, global.f_body, _a);
        _y += ceil(ui_sh_ext(_thanks, _w)) + 24;
        if (licence_key != "")
        {
            ui_heading(_x, _y, "Licence key");
            ui_text(_x, _y + 30, licence_key, c_white, fa_left, fa_middle, global.f_bold, _a);
            _y += 64;
            if (ui_button("lic_remove", _x, _y, 200, 36, "Remove key", "Remove key|Takes the key off this computer and goes back to ADAM Lite - for example before passing the PC on. You can enter the key again any time.", BTN_GHOST))
            {
                licence_remove();
            }
        }
        return;
    }

    ui_text(_x, _y, "This is ADAM Lite", c_white, fa_left, fa_top, global.f_title, _a);
    _y += 44;
    var _intro = "ADAM Lite is free and makes complete games - backdrops, copper skies, sprites, rules, levels, sounds and music, on a real bootable disk. ADAM Pro adds more: dither drawing and gradients, BOBs (more moving things), scrolling, shooting, tracker effects, play-in-browser export and more. Pro features show a Pro label in ADAM Lite.";
    ui_text_wrap(_x, _y, _intro, global.TH.text, _w, global.f_body, _a);
    _y += ceil(ui_sh_ext(_intro, _w)) + 24;

    ui_heading(_x, _y, "Licence key");
    _y += 20;
    var _bw = 140;
    var _typing = ui_focus == "lic_key";
    licence_entry = ui_textfield("lic_key", _x, _y, _w - _bw - 12, 40, licence_entry, 32, "Licence key|Type or paste the key from your ADAM Pro purchase on itch.io, like ADAM-ABCD-EFGH-JKLM-NPQR. Dashes and spaces don't matter.");
    var _go = ui_button("lic_unlock", _x + _w - _bw, _y, _bw, 40, "Unlock", "Unlock|Checks the key and turns on ADAM Pro.", BTN_ACCENT);
    if (_typing && keyboard_check_pressed(vk_enter)) { _go = true; }
    if (_go) { licence_enter(licence_entry); }
    _y += 52;
    if (licence_msg != "")
    {
        ui_text_wrap(_x, _y, licence_msg, global.TH.warn, _w, global.f_small, _a);
        _y += 28;
    }
    if (ADAM_PRO_URL != "")
    {
        if (ui_button("lic_get", _x, _y + 8, 200, 36, "Get ADAM Pro", "Get ADAM Pro|Opens the ADAM Pro page on itch.io in your web browser.", BTN_NORMAL))
        {
            url_open(ADAM_PRO_URL);
        }
    }
}
