/// ADAM - "What's new" panel, shown once per version after the launch machine picker
/// (people who used ADAM before), and any time from the Learn ADAM menu.
///
/// For each release: add an entry at the TOP of whatsnew_entries() with the new
/// ADAM_VERSION (scr_about). If there is no entry for ADAM_VERSION the panel
/// does not pop up by itself.

function whatsnew_entries()
{
    return [
        {
            ver : "1.0.1",
            items : [
                "FS-UAE, the free Amiga emulator, now comes with ADAM: Build & play works straight after installing. On Windows it is included; on a Mac, ADAM downloads the right one for your Mac the first time. (If you picked your own FS-UAE with Find, ADAM keeps using it.)",
                "Quit from full screen: rest the mouse on the ADAM ball (top left) and it turns into an X - click it to close ADAM. Your work is kept and opens again next time.",
                "Questions such as \"Quit ADAM?\" and \"Start a new project?\" now appear in ADAM's own panel, with Enter for yes and Esc for cancel.",
                "Fixed: on some older graphics cards ADAM could go black when you came back to it from a game running full screen.",
                "ADAM uses far less graphics memory (about half on a 4K screen), so it runs better on older PCs.",
                "ADAM now tells you when a new version is out, with a small card and a link to it. Turn it off on Home > Game settings > Check for updates.",
                "This What's new panel. Open it again any time from the Learn ADAM menu."
            ]
        },
        {
            ver : "1.0.0",
            items : [
                "The first release of ADAM: paint a backdrop and copper sky, draw sprites, place actors, write WHEN / DO rules, make sounds, music and levels, then build a bootable Amiga disk for the A500/600 or A1200."
            ]
        }
    ];
}

/// True when there are notes for the version that is running
function whatsnew_has_current()
{
    var _e = whatsnew_entries();
    for (var i = 0; i < array_length(_e); i++)
    {
        if (_e[i].ver == ADAM_VERSION) { return true; }
    }
    return false;
}

/// After the launch machine picker: new users get the tour instead; people who
/// used an earlier version see the notes once (until "Don't show again")
function whatsnew_after_launch(_new_user)
{
    if (_new_user)
    {
        whatsnew_seen = ADAM_VERSION;
        settings_save();
        return;
    }
    if (whatsnew_seen != ADAM_VERSION && whatsnew_has_current())
    {
        whatsnew_open(false);
    }
}

/// _manual: opened from the Learn ADAM menu (just a Close button)
function whatsnew_open(_manual)
{
    whatsnew_active = true;
    whatsnew_manual = _manual;
    whatsnew_anim = 0;
    ui_popup_open = false;
    ui_focus = "";
    tut_offer_on = false;
    ds_map_replace(ui_scroll, "whatsnew_scroll", 0);
}

/// The panel, drawn over the page while whatsnew_active
function whatsnew_draw(_gw, _gh)
{
    if (!whatsnew_active) { return; }
    whatsnew_anim = lerp(whatsnew_anim, 1, 0.15);
    var _a = whatsnew_anim;
    ui_force_input = true;

    draw_set_alpha(0.7 * _a);
    draw_rectangle_colour(0, 0, _gw, _gh, c_black, c_black, global.TH.bg_bot, global.TH.bg_bot, false);
    draw_set_alpha(1);

    var _w = min(720, _gw - 80);
    var _h = min(600, _gh - 100);
    var _x1 = floor((_gw - _w) / 2);
    var _y1 = floor((_gh - _h) / 2) + round((1 - _a) * 20);
    var _x2 = _x1 + _w;
    var _y2 = _y1 + _h;
    ui_panel(_x1, _y1, _x2, _y2, "");

    // ---------- header ----------
    draw_boing(_x1 + 24, _y1 + 20, 48, _a);
    ui_text(_x1 + 88, _y1 + 12, "What's new", c_white, fa_left, fa_top, global.f_hero, _a);
    ui_text(_x1 + 90, _y1 + 62, "ADAM " + ADAM_VERSION, global.TH.text_dim, fa_left, fa_top, global.f_body, _a);

    // ---------- the notes, newest first, scrolling ----------
    var _tx1 = _x1 + 20;
    var _ty1 = _y1 + 90;
    var _tx2 = _x2 - 20;
    var _ty2 = _y2 - 70;
    ui_inset(_tx1, _ty1, _tx2, _ty2, 8);
    ui_register("whatsnew_text", _tx1, _ty1, _tx2, _ty2, "What's new|The changes in each version of ADAM, newest first. Scroll with the mouse wheel or drag the bar on the right.");
    var _entries = whatsnew_entries();
    var _bw = _tx2 - _tx1 - 44 - 22;
    draw_set_font(global.f_body);
    var _ch = 16;
    for (var i = 0; i < array_length(_entries); i++)
    {
        _ch += 34;
        for (var j = 0; j < array_length(_entries[i].items); j++)
        {
            _ch += ceil(ui_sh_ext(_entries[i].items[j], _bw)) + 10;
        }
        _ch += 14;
    }
    var _off = ui_scroll_begin("whatsnew_scroll", _tx1, _ty1, _tx2, _ty2, _ch);
    var _cy = _ty1 + 16 - _off;
    for (var n = 0; n < array_length(_entries); n++)
    {
        var _e = _entries[n];
        var _hc = global.TH.text_dim;
        if (_e.ver == ADAM_VERSION) { _hc = global.TH.accent2; }
        ui_text(_tx1 + 16, _cy, "ADAM " + _e.ver, _hc, fa_left, fa_top, global.f_title, _a);
        _cy += 34;
        for (var m = 0; m < array_length(_e.items); m++)
        {
            var _s = _e.items[m];
            draw_set_colour(global.TH.accent);
            draw_set_alpha(_a);
            draw_circle(_tx1 + 26, _cy + 10, 3, false);
            draw_set_alpha(1);
            ui_text_wrap(_tx1 + 38, _cy, _s, global.TH.text, _bw, global.f_body, _a);
            draw_set_font(global.f_body);
            _cy += ceil(ui_sh_ext(_s, _bw)) + 10;
        }
        _cy += 14;
    }
    ui_scroll_end("whatsnew_scroll", _tx1, _ty1, _tx2, _ty2, _ch);

    // ---------- buttons ----------
    var _by = _y2 - 54;
    var _later = false;
    var _never = false;
    if (whatsnew_manual)
    {
        if (ui_button("whatsnew_close", _x2 - 140, _by, 120, 36, "Close", "Close|Goes back to ADAM. Esc does the same.", BTN_ACCENT)) { _later = true; }
        ui_text(_x1 + 24, _by + 18, "Press Esc to close.", global.TH.text_faint, fa_left, fa_middle, global.f_small, _a);
    }
    else
    {
        if (ui_button("whatsnew_never", _x2 - 20 - 190, _by, 190, 36, "Don't show again", "Don't show again|Closes this, and it will not open by itself again until the next version of ADAM. It is always in the Learn ADAM menu.", BTN_ACCENT)) { _never = true; }
        if (ui_button("whatsnew_later", _x2 - 20 - 190 - 10 - 140, _by, 140, 36, "Read later", "Read later|Closes this for now. It opens again next time you start ADAM.", BTN_NORMAL)) { _later = true; }
        ui_text(_x1 + 24, _by + 18, "Esc = Read later", global.TH.text_faint, fa_left, fa_middle, global.f_small, _a);
    }
    if (keyboard_check_pressed(vk_escape)) { _later = true; }
    ui_force_input = false;

    if (_never)
    {
        whatsnew_active = false;
        whatsnew_seen = ADAM_VERSION;
        settings_save();
    }
    else if (_later)
    {
        whatsnew_active = false;
    }
}
