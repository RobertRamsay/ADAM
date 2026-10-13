/// ADAM - UI page (Lite and Pro): a custom HUD for the game - a panel strip at the
/// top or bottom of the screen (1 to 6 text rows), drawn with a 9-slice frame
/// (24 x 24 pixels: corners, edges and a fill that repeats), a font style (or
/// a font drawn here) and the fields: score, lives, goal, the tile carried,
/// the level and plain text, each with its own place, colour and shadow.
///
/// Engine side: data block version 7, H_UI / UI_* / F_* in engine.s. The same
/// rules are in tools/reference/ui_ref.py (font styles, frame presets, panel).

#macro UI_ROWS_MAX 6
#macro UI_LABEL_MAX 19

function ui_font_styles()
{
    return ["ADAM", "Bold", "Thin", "Italic", "Bold italic", "Custom (drawn here)"];
}

function ui_frame_styles()
{
    return ["Metal", "Wood", "Stone", "Neon", "Parchment", "Window"];
}

function ui_field_types()
{
    return ["Text", "Score", "Lives", "Goal", "Tile carried", "Level", "Tool"];
}

/// The custom HUD of a new project: off (the standard HUD is used)
function ui_new()
{
    return {
        on : false,                         // use the custom HUD
        bottom : false,                     // the panel at the bottom (a tile world always has it at the top)
        rows : 1,                           // text rows, 8 lines each
        frame_on : true,                    // draw the 9-slice frame
        style : "Metal",                    // the preset the frame came from ("Custom" once drawn on)
        frame : array_create(576, 0),       // 24 x 24 colour numbers, 0 = see-through
        font_style : 0,                     // ui_font_styles()
        font : [],                          // 64 x 8 bytes when font_style is Custom
        fields : []                         // ui_field_new()
    };
}

function ui_field_new(_type)
{
    return { type : _type, label : "", col : 1, row : 0, colour : 1, shadow : -1, digits : 5 };
}

/// The custom HUD of a loaded project, made safe
function ui_from_loaded(_raw)
{
    var _u = ui_new();
    if (!is_struct(_raw)) { return _u; }
    struct_overlay(_u, _raw);
    if (!is_bool(_u.on)) { _u.on = (is_numeric(_u.on) && _u.on != 0); }
    if (!is_bool(_u.bottom)) { _u.bottom = (is_numeric(_u.bottom) && _u.bottom != 0); }
    if (!is_bool(_u.frame_on)) { _u.frame_on = (is_numeric(_u.frame_on) && _u.frame_on != 0); }
    if (!is_numeric(_u.rows)) { _u.rows = 1; }
    _u.rows = clamp(floor(_u.rows), 1, UI_ROWS_MAX);
    if (!is_string(_u.style)) { _u.style = "Metal"; }
    if (!is_array(_u.frame) || array_length(_u.frame) != 576) { _u.frame = array_create(576, 0); }
    for (var i = 0; i < 576; i++)
    {
        if (!is_numeric(_u.frame[i])) { _u.frame[i] = 0; }
        _u.frame[i] = clamp(floor(_u.frame[i]), 0, PAL_MAX - 1);
    }
    if (!is_numeric(_u.font_style)) { _u.font_style = 0; }
    _u.font_style = clamp(floor(_u.font_style), 0, 5);
    if (!is_array(_u.font) || array_length(_u.font) != 512) { _u.font = []; }
    if (_u.font_style == 5 && array_length(_u.font) != 512) { _u.font_style = 0; }
    var _fl = [];
    if (is_array(_u.fields))
    {
        for (var f = 0; f < min(16, array_length(_u.fields)); f++)
        {
            var _src = _u.fields[f];
            if (!is_struct(_src)) { continue; }
            var _fd = struct_overlay(ui_field_new(0), _src);
            if (!is_numeric(_fd.type)) { _fd.type = 0; }
            _fd.type = clamp(floor(_fd.type), 0, 6);
            if (!is_string(_fd.label)) { _fd.label = ""; }
            _fd.label = string_upper(string_copy(_fd.label, 1, UI_LABEL_MAX));
            if (!is_numeric(_fd.col)) { _fd.col = 0; }
            _fd.col = clamp(floor(_fd.col), 0, 39);
            if (!is_numeric(_fd.row)) { _fd.row = 0; }
            _fd.row = clamp(floor(_fd.row), 0, UI_ROWS_MAX - 1);
            if (!is_numeric(_fd.colour)) { _fd.colour = 1; }
            _fd.colour = clamp(floor(_fd.colour), 0, PAL_MAX - 1);
            if (!is_numeric(_fd.shadow)) { _fd.shadow = -1; }
            _fd.shadow = clamp(floor(_fd.shadow), -1, PAL_MAX - 1);
            if (!is_numeric(_fd.digits)) { _fd.digits = 5; }
            _fd.digits = clamp(floor(_fd.digits), 1, 6);
            array_push(_fl, _fd);
        }
    }
    _u.fields = _fl;
    return _u;
}

/// The font the HUD is drawn with: 64 characters (32..95) x 8 rows of 8 pixels
function ui_font_bytes(_u)
{
    var _st = _u.font_style;
    if (_st == 5 && array_length(_u.font) == 512) { return _u.font; }
    var _out = array_create(512, 0);
    for (var c = 0; c < 64; c++)
    {
        for (var i = 0; i < 8; i++)
        {
            var _r = global.FONT8[c * 8 + i];
            if (_st == 1 || _st == 4) { _r = (_r | (_r >> 1)) & 255; }
            if (_st == 2) { _r = _r & ~(_r >> 1) & 255; }
            if (_st == 3 || _st == 4)
            {
                if (i < 3) { _r = _r >> 1; }
                else if (i >= 5) { _r = (_r << 1) & 255; }
            }
            _out[c * 8 + i] = _r;
        }
    }
    return _out;
}

/// Colour (0xRRGGBB) of pixel (_x, _y) of a frame preset's 24 x 24 picture, or -1 = see-through
function ui_frame_rgb(_style, _x, _y)
{
    var _d = min(_x, _y, 23 - _x, 23 - _y);
    var _lt = (min(_x, _y) <= min(23 - _x, 23 - _y));     // the top / left side: the lit bevel
    var _mx = _x mod 8;
    var _my = _y mod 8;
    switch (_style)
    {
        case "Metal":
            if (_d == 0) { return 0x202430; }
            if (_d == 1)
            {
                if (_lt) { return 0xd0d8e8; }
                return 0x404858;
            }
            if ((_x == 4 || _x == 19) && (_y == 4 || _y == 19)) { return 0xe8f0ff; }
            if ((_x == 5 || _x == 20) && (_y == 5 || _y == 20)) { return 0x303440; }
            if ((_mx + _my) mod 4 != 0) { return 0x687080; }
            return 0x5c6474;
        case "Wood":
            if (_d == 0) { return 0x301808; }
            if (_d == 1)
            {
                if (_lt) { return 0xb07840; }
                return 0x583018;
            }
            if ((_my * 3 + _mx div 3) mod 7 == 0) { return 0x6a3c1c; }
            return 0x8a5228;
        case "Stone":
            if (_d == 0) { return 0x282830; }
            if (_d == 1)
            {
                if (_lt) { return 0x9c9ca8; }
                return 0x48484f;
            }
            var _off = 0;
            if ((_y div 4) mod 2 == 1) { _off = 4; }
            if (_y mod 4 == 3 || (_mx + _off) mod 8 == 7) { return 0x4a4a52; }
            return 0x7a7a84;
        case "Neon":
            if (_d == 0) { return 0xc020d0; }
            if (_d == 2) { return 0x40f0ff; }
            return 0x100820;
        case "Parchment":
            if (_d <= 1) { return 0x704018; }
            if (_d == 2) { return 0xa07040; }
            if ((_x * 7 + _y * 13) mod 11 == 0) { return 0xd4c08c; }
            return 0xecdcaa;
        case "Window":
            if (_d == 0) { return 0xffffff; }
            if (_d == 1) { return 0x6080b0; }
            return -1;
    }
    return -1;
}

/// A frame preset in the project's own colours (the nearest backdrop colours)
function ui_frame_preset(_style)
{
    var _ncol = 1 << clamp(proj.depth, 1, machine_cur().max_depth);
    var _out = array_create(576, 0);
    for (var _py = 0; _py < 24; _py++)
    {
        for (var _px = 0; _px < 24; _px++)
        {
            var _c = ui_frame_rgb(_style, _px, _py);
            if (_c >= 0) { _out[_py * 24 + _px] = pal_nearest(proj, _c, _ncol); }
        }
    }
    return _out;
}

/// First text row of the panel on the screen (32 rows of 8 lines)
function ui_row0(_u)
{
    if (_u.bottom && !proj.tiles_on) { return 32 - _u.rows; }
    return 0;
}

/// The HUD strip as the Amiga shows it before any text: the backdrop's rows
/// with the 9-slice frame on top (0 in the frame lets the backdrop through)
function ui_panel_pixels(_u, _pixels)
{
    var _h = _u.rows * 8;
    var _y0 = ui_row0(_u) * 8;
    var _out = array_create(320 * _h, 0);
    array_copy(_out, 0, _pixels, _y0 * 320, 320 * _h);
    if (!_u.frame_on) { return _out; }
    for (var _py = 0; _py < _h; _py++)
    {
        var _fy = 8 + _py;
        if (_h >= 16)
        {
            if (_py < 8) { _fy = _py; }
            else if (_py >= _h - 8) { _fy = 16 + _py - (_h - 8); }
            else { _fy = 8 + (_py - 8) mod 8; }
        }
        for (var _px = 0; _px < 320; _px++)
        {
            var _fx = 8 + (_px - 8) mod 8;
            if (_px < 8) { _fx = _px; }
            else if (_px >= 312) { _fx = 16 + _px - 312; }
            var _v = _u.frame[_fy * 24 + _fx];
            if (_v != 0) { _out[_py * 320 + _px] = _v; }
        }
    }
    return _out;
}

/// Fields like the standard HUD (score, goal, lives; the tile carried when digging)
function ui_default_fields()
{
    var _f = [];
    var _hc = clamp(proj.hud_colour, 1, max(1, pal_count() - 1));
    if (proj.show_score)
    {
        var _s = ui_field_new(1);
        _s.label = "SCORE ";
        _s.col = 1;
        _s.colour = _hc;
        array_push(_f, _s);
    }
    if (proj.goal_on)
    {
        var _g = ui_field_new(3);
        _g.col = 15;
        _g.colour = _hc;
        array_push(_f, _g);
    }
    if (proj.tiles_on && proj.tile_dig)
    {
        var _t = ui_field_new(4);
        _t.col = 24;
        _t.colour = _hc;
        array_push(_f, _t);
    }
    if (proj.show_lives)
    {
        var _l = ui_field_new(2);
        _l.label = "LIVES ";
        _l.col = 31;
        _l.digits = 1;
        _l.colour = _hc;
        array_push(_f, _l);
    }
    return _f;
}

/// The text a field shows, with sample values (as the Amiga draws it)
function ui_field_text(_f)
{
    var _lab = _f.label;
    switch (_f.type)
    {
        case 0: return _lab;
        case 1: return _lab + string_replace_all(string_format(1230 mod power(10, _f.digits), _f.digits, 0), " ", "0");
        case 2: return _lab + string_replace_all(string_format(3, _f.digits, 0), " ", "0");
        case 3:
            if (!proj.goal_on) { return ""; }       // (the Amiga leaves it out too)
            if (_lab == "") { _lab = string_upper(proj.goal_label) + " "; }
            return _lab + "05/" + string_replace_all(string_format(proj.goal mod 100, 2, 0), " ", "0");
        case 4:
            if (!(proj.tiles_on && proj.tile_dig)) { return ""; }
            var _tn = "DIRT";
            if (array_length(proj.tiles) > 1) { _tn = string_copy(proj.tiles[1].name + "    ", 1, 4); }
            return _lab + _tn + " 03";
        case 5: return _lab + string_replace_all(string_format(1, _f.digits, 0), " ", "0");
        case 6:
            if (!(proj.tiles_on && proj.tile_dig) || array_length(proj.tools) == 0) { return ""; }
            return _lab + string_copy(proj.tools[0].name + "        ", 1, 8);
    }
    return _lab;
}

/// Draws text into a 320 x 256 index buffer the way engine.s draw_char does:
/// whole 8 x 8 cells, the shadow one pixel down and right inside the cell
function ui_text_into(_buf, _font, _str, _col, _row, _colour, _shadow)
{
    var _n = string_length(_str);
    for (var k = 0; k < _n; k++)
    {
        var _cx = _col + k;
        if (_cx >= 40) { break; }
        var _c = ord(string_upper(string_char_at(_str, k + 1)));
        if (_c < 32 || _c > 95) { _c = 32; }
        var _g = (_c - 32) * 8;
        for (var i = 0; i < 8; i++)
        {
            var _gb = _font[_g + i];
            var _sb = 0;
            if (_shadow >= 0 && i > 0) { _sb = _font[_g + i - 1] >> 1; }
            var _ly = _row * 8 + i;
            for (var b = 0; b < 8; b++)
            {
                var _m = 0x80 >> b;
                var _o = (_ly * 320 + _cx * 8 + b) * 4;
                if ((_gb & _m) != 0) { buffer_poke(_buf, _o, buffer_u32, 0xff000000 | _colour); }
                else if ((_sb & _m) != 0) { buffer_poke(_buf, _o, buffer_u32, 0xff000000 | _shadow); }
            }
        }
    }
}

/// The preview: the backdrop with the panel and the fields on it, as an index surface
function ui_preview_surface()
{
    var _u = proj.ui;
    var _key = json_stringify(_u) + "|" + string(proj.tiles_on) + string(proj.goal_on) + string(proj.goal) + proj.goal_label + "|" + string(ui_prev_tick div 60);
    ui_prev_tick += 1;
    if (!surface_exists(ui_prev_surf))
    {
        ui_prev_surf = surface_create(BD_W, BD_H);
        ui_prev_key = "";
    }
    if (_key != ui_prev_key)
    {
        ui_prev_key = _key;
        if (!buffer_exists(ui_prev_buf)) { ui_prev_buf = buffer_create(BD_W * BD_H * 4, buffer_fixed, 1); }
        buffer_seek(ui_prev_buf, buffer_seek_start, 0);
        for (var i = 0; i < BD_W * BD_H; i++) { buffer_write(ui_prev_buf, buffer_u32, 0xff000000 | proj.pixels[i]); }
        var _r0 = ui_row0(_u);
        if (_u.on)
        {
            var _pp = ui_panel_pixels(_u, proj.pixels);
            for (var q = 0; q < array_length(_pp); q++) { buffer_poke(ui_prev_buf, (_r0 * 8 * 320 + q) * 4, buffer_u32, 0xff000000 | _pp[q]); }
            var _font = ui_font_bytes(_u);
            for (var f = 0; f < array_length(_u.fields); f++)
            {
                var _fd = _u.fields[f];
                if (_fd.row >= _u.rows) { continue; }
                ui_text_into(ui_prev_buf, _font, ui_field_text(_fd), _fd.col, _r0 + _fd.row, _fd.colour, _fd.shadow);
            }
        }
        buffer_set_surface(ui_prev_buf, ui_prev_surf, 0);
    }
    return ui_prev_surf;
}

function ui_gfx_free()
{
    if (surface_exists(ui_prev_surf)) { surface_free(ui_prev_surf); }
    if (buffer_exists(ui_prev_buf)) { buffer_delete(ui_prev_buf); }
    loadscr_gfx_free();
}

/// The tabs at the top of the left panel: Custom HUD / Loading screen (ADAM Pro)
function ui_page_tabs(_x1, _y1, _lw)
{
    var _tw = 76;
    var _tw2 = _lw - 32 - 6 - _tw;
    var _lab = "Loading screen";
    if (!pro_edition()) { _lab = "Loading (Pro)"; }
    if (ui_tab("ui_page_0", _x1 + 16, _y1 + 10, _tw, 30, "HUD", ui_page_tab == 0, "Custom HUD|Your own panel, font and fields for the game's score, lives and so on."))
    {
        ui_page_tab = 0;
    }
    if (ui_tab("ui_page_1", _x1 + 16 + _tw + 6, _y1 + 10, _tw2, 30, _lab, ui_page_tab == 1, "Loading screen (ADAM Pro)|A picture shown while the game loads, with a loading bar made of a left cap, a repeating middle and a right cap."))
    {
        if (pro_gate("The loading screen")) { ui_page_tab = 1; }
    }
    draw_line_colour(_x1 + 14, _y1 + 46, _x1 + _lw - 14, _y1 + 46, global.TH.panel_edge, global.TH.panel_edge);
}

/// Switches the custom HUD on, starting from fields like the standard HUD and a metal frame
function ui_switch_on()
{
    var _u = proj.ui;
    _u.on = true;
    if (array_length(_u.fields) == 0) { _u.fields = ui_default_fields(); }
    var _blank = true;
    for (var i = 0; i < 576; i++)
    {
        if (_u.frame[i] != 0) { _blank = false; }
    }
    if (_blank) { _u.frame = ui_frame_preset(_u.style); }
    if (_u.rows < 2 && _u.frame_on) { _u.rows = 2; }
    ui_sel_field = 0;
}

function ws_ui_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 270;
    var _rw = 300;
    var _u = proj.ui;
    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;
    var _nf = array_length(_u.fields);
    ui_sel_field = clamp(ui_sel_field, 0, max(0, _nf - 1));
    var _pro = pro_edition();
    if (!_pro) { ui_page_tab = 0; }
    if (ui_page_tab == 1)
    {
        loadscr_page_draw(_x1, _y1, _x2, _y2, _lw, _rw);
        return;
    }

    // ---------------- left: the panel, the frame, the font, the fields ----------------
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "");
    ui_page_tabs(_x1, _y1, _lw);
    var _fx = _x1 + 16;
    var _fw = _lw - 32;
    var _y = _y1 + 58;
    var _on = ui_toggle("ui_on", _fx, _y, "Use a custom HUD", _u.on, "Custom HUD|Replaces the standard one-line HUD with your own panel, font and fields. Switch it off to go back to the standard HUD (your design is kept).");
    if (_on != _u.on)
    {
        undo_mark("uion" + string(current_time));
        if (_on) { ui_switch_on(); }
        else { _u.on = false; }
    }
    _y += 36;
    var _half = floor((_fw - 8) / 2);
    ui_heading(_fx, _y, "Where");
    ui_heading(_fx + _half + 8, _y, "Height (rows)");
    var _pos = 0;
    if (_u.bottom) { _pos = 1; }
    var _np = ui_dropdown("ui_pos", _fx, _y + 18, _half, 30, ["Top", "Bottom"], _pos, "Where|The panel's place on the screen. A tile world always has it at the top (the map scrolls below it).");
    if (_np != _pos) { set_val(_u, "bottom", (_np == 1), "uipos"); }
    set_val(_u, "rows", ui_stepper("ui_rows", _fx + _half + 8, _y + 18, _half, _u.rows, 1, UI_ROWS_MAX, "Height|Text rows of 8 lines: 1 is a slim strip, 2 room for a frame round one line of text, up to 6. Fields on rows below the panel are not shown."), "uirows");
    if (_u.bottom && proj.tiles_on) { ui_text(_fx, _y + 52, "Tile world: shown at the top", global.TH.warn, fa_left, fa_top, global.f_small, 1); }
    _y += 76;                               // room for that line (20 px) above the toggle
    set_val(_u, "frame_on", ui_toggle("ui_frame_on", _fx, _y, "Panel frame", _u.frame_on, "Panel frame|Draws the 9-slice frame: corners, edges and a fill that stretch to the panel's size. Off: the backdrop shows behind the text."), "uiframeon");
    _y += 32;
    ui_heading(_fx, _y, "Frame style");
    var _styles = ui_frame_styles();
    var _si = -1;
    for (var s = 0; s < array_length(_styles); s++)
    {
        if (_styles[s] == _u.style) { _si = s; }
    }
    var _snames = [];
    for (var s2 = 0; s2 < array_length(_styles); s2++) { array_push(_snames, _styles[s2]); }
    var _shown = _si;
    if (_si < 0)
    {
        array_push(_snames, "Custom (drawn)");
        _shown = array_length(_snames) - 1;
    }
    var _ns = ui_dropdown("ui_style", _fx, _y + 18, _fw, 30, _snames, _shown, "Frame style|A ready-made frame in your game's colours (the nearest backdrop colours). Then draw on it below to make it your own.");
    if (_ns != _shown && _ns < array_length(_styles))
    {
        undo_mark("uistyle" + string(current_time));
        _u.style = _styles[_ns];
        _u.frame = ui_frame_preset(_u.style);
    }
    _y += 58;
    ui_heading(_fx, _y, "Font");
    var _font_names = ui_font_styles();
    if (!_pro) { _font_names[5] = "Custom (Pro)"; }
    var _nfs = ui_dropdown("ui_font", _fx, _y + 18, _fw, 30, _font_names, _u.font_style, "Font|The letters the HUD uses (and the game's messages). Custom (Pro): draw your own on the Font tab below.");
    if (_nfs != _u.font_style && (_nfs != 5 || pro_gate("Drawing your own font")))
    {
        undo_mark("uifont" + string(current_time));
        if (_nfs == 5 && array_length(_u.font) != 512) { _u.font = ui_font_bytes(_u); }
        _u.font_style = _nfs;
    }
    _y += 58;
    ui_heading(_fx, _y, "Fields (" + string(_nf) + ")");
    _y += 18;
    var _types = ui_field_types();
    var _listh = max(60, _y2 - 60 - _y);
    var _rowh = 30;
    var _content = _nf * _rowh + 4;
    var _off = ui_scroll_begin("ui_fields", _fx - 4, _y, _fx + _fw + 4, _y + _listh, _content);
    for (var f = 0; f < _nf; f++)
    {
        var _fy = _y + f * _rowh - _off;
        if (_fy < _y - _rowh || _fy > _y + _listh) { continue; }
        var _fd = _u.fields[f];
        var _hot = ui_register("ui_field_" + string(f), _fx, _fy, _fx + _fw, _fy + _rowh - 4, "Field|Click to change it on the right, or drag it on the preview.");
        if (ui_sel_field == f) { ui_rrect(_fx, _fy, _fx + _fw, _fy + _rowh - 4, 6, global.TH.accent, global.TH.accent_dark, 0.9); }
        else if (_hot) { ui_rrect(_fx, _fy, _fx + _fw, _fy + _rowh - 4, 6, global.TH.btn_hot_top, global.TH.btn_hot_bot, 0.6); }
        ui_rrect(_fx + 6, _fy + 6, _fx + 20, _fy + _rowh - 10, 3, pal_col(_fd.colour), pal_col(_fd.colour), 1);
        var _ft = _types[_fd.type];
        if (_fd.label != "") { _ft += ": " + _fd.label; }
        ui_text(_fx + 28, _fy + (_rowh - 4) / 2, ui_text_fit(_ft, global.f_small, _fw - 36), global.TH.text, fa_left, fa_middle, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            ui_take_click();
            ui_sel_field = f;
        }
    }
    ui_scroll_end("ui_fields", _fx - 4, _y, _fx + _fw + 4, _y + _listh, _content);
    var _add = ui_menu_button("ui_add", _fx, _y2 - 46, floor((_fw - 8) / 2), 32, "+ Field", _types, "Add a field|Score, lives, the level goal, the tile the player carries, the level number, or a line of text.", BTN_NORMAL);
    if (_add >= 0 && _nf < 16)
    {
        undo_mark("uiadd" + string(current_time));
        var _nfd = ui_field_new(_add);
        _nfd.colour = clamp(proj.hud_colour, 1, max(1, pal_count() - 1));
        if (_add == 0) { _nfd.label = "TEXT"; }
        if (_add == 1) { _nfd.label = "SCORE "; }
        if (_add == 2)
        {
            _nfd.label = "LIVES ";
            _nfd.digits = 1;
        }
        if (_add == 5)
        {
            _nfd.label = "LEVEL ";
            _nfd.digits = 2;
        }
        _nfd.row = min(_u.rows - 1, 0);
        array_push(_u.fields, _nfd);
        ui_sel_field = array_length(_u.fields) - 1;
    }
    var _dst = BTN_DANGER;
    if (_nf == 0) { _dst = BTN_GHOST; }
    if (ui_button("ui_del", _fx + floor((_fw - 8) / 2) + 8, _y2 - 46, floor((_fw - 8) / 2), 32, "Remove", "Remove field|Takes the picked field off the HUD. You can Undo this.", _dst) && _nf > 0)
    {
        undo_mark("uidel" + string(current_time));
        array_delete(_u.fields, ui_sel_field, 1);
        ui_sel_field = max(0, ui_sel_field - 1);
    }
    _nf = array_length(_u.fields);          // a field was just added or removed
    ui_sel_field = clamp(ui_sel_field, 0, max(0, _nf - 1));

    // ---------------- centre: the preview, then the frame / font editors ----------------
    ui_panel(_cx1, _y1, _cx2, _y2, "Preview");
    var _pw = _cx2 - _cx1 - 32;
    var _ph = floor((_y2 - _y1) * 0.5);
    var _sc = max(1, floor(min(_pw / BD_W, (_ph - 10) / BD_H) * 2) / 2);
    var _vx = floor((_cx1 + _cx2 - BD_W * _sc) / 2);
    var _vy = _y1 + 50;
    ui_rrect(_vx - 6, _vy - 6, _vx + BD_W * _sc + 6, _vy + BD_H * _sc + 6, 10, c_black, c_black, 0.35);
    var _ps = ui_preview_surface();
    backdrop_shader_begin();
    draw_surface_ext(_ps, _vx, _vy, _sc, _sc, 0, c_white, 1);
    backdrop_shader_end();
    var _r0 = ui_row0(_u);
    ui_register("ui_preview", _vx, _vy, _vx + BD_W * _sc, _vy + BD_H * _sc, "Preview|The game screen with your HUD, using sample values. Drag a field to move it (it snaps to the 8 x 8 text grid).");
    if (_u.on)
    {
        // the panel's outline, and the fields: click to pick, drag to move
        draw_set_alpha(0.5);
        draw_rectangle_colour(_vx, _vy + _r0 * 8 * _sc, _vx + BD_W * _sc - 1, _vy + (_r0 + _u.rows) * 8 * _sc - 1, global.TH.accent2, global.TH.accent2, global.TH.accent2, global.TH.accent2, true);
        draw_set_alpha(1);
        var _hov = -1;
        for (var f2 = 0; f2 < _nf; f2++)
        {
            var _fd2 = _u.fields[f2];
            var _len = max(1, string_length(ui_field_text(_fd2)));
            var _rx1 = _vx + _fd2.col * 8 * _sc;
            var _ry1 = _vy + (_r0 + _fd2.row) * 8 * _sc;
            var _rx2 = _rx1 + _len * 8 * _sc;
            var _ry2 = _ry1 + 8 * _sc;
            if (point_in_rectangle(ui_mx, ui_my, _rx1, _ry1, _rx2, _ry2) && ui_drag_field < 0) { _hov = f2; }
            if (f2 == ui_sel_field) { draw_rectangle_colour(_rx1 - 1, _ry1 - 1, _rx2, _ry2, global.TH.accent, global.TH.accent, global.TH.accent, global.TH.accent, true); }
            else if (f2 == _hov) { draw_rectangle_colour(_rx1 - 1, _ry1 - 1, _rx2, _ry2, c_white, c_white, c_white, c_white, true); }
        }
        if (_hov >= 0 && ui_pressed)
        {
            ui_take_click();
            ui_sel_field = _hov;
            ui_drag_field = _hov;
            ui_drag_dx = ui_mx - (_vx + _u.fields[_hov].col * 8 * _sc);
            ui_drag_dy = ui_my - (_vy + (_r0 + _u.fields[_hov].row) * 8 * _sc);
            undo_mark("uidrag" + string(current_time));
        }
        if (ui_drag_field >= 0)
        {
            if (!ui_held || ui_drag_field >= _nf) { ui_drag_field = -1; }
            else
            {
                var _df = _u.fields[ui_drag_field];
                _df.col = clamp(round((ui_mx - ui_drag_dx - _vx) / (8 * _sc)), 0, 39);
                _df.row = clamp(round((ui_my - ui_drag_dy - _vy) / (8 * _sc)) - _r0, 0, _u.rows - 1);
                proj_dirty = true;
            }
        }
    }

    // editors: the frame (24 x 24, 9-slice) or the font
    var _ey = _vy + BD_H * _sc + 18;
    if (_u.on)
    {
        var _etabs = ["Panel frame", "Font"];
        if (!_pro) { _etabs[1] = "Font (Pro)"; }
        var _ehelp = ["Panel frame|Draw the frame: the 3 x 3 squares of 8 x 8 pixels are the corners, the edges (repeated along the panel) and the fill (repeated inside). Right-click: see-through.", "Font|Draw the letters: pick a character, then draw it. The first change makes the font Custom."];
        for (var et = 0; et < 2; et++)
        {
            if (ui_tab("ui_etab_" + string(et), _cx1 + 16 + et * 130, _ey, 124, 30, _etabs[et], ui_edit_tab == et, _ehelp[et]))
            {
                if (et == 0 || pro_gate("Drawing your own font")) { ui_edit_tab = et; }
            }
        }
        _ey += 40;
        var _eh = _y2 - 16 - _ey;
        if (ui_edit_tab == 0) { ui_frame_editor(_cx1 + 16, _ey, _cx2 - 16, _ey + _eh); }
        else if (_pro) { ui_font_editor(_cx1 + 16, _ey, _cx2 - 16, _ey + _eh); }
        else
        {
            ui_text_wrap(_cx1 + 16, _ey, "Drawing your own font comes with ADAM Pro. Choose a built-in font on the left, or use the Panel frame tab to draw your frame.", global.TH.text_dim, _cx2 - _cx1 - 32, global.f_body, 1);
        }
    }

    // ---------------- right: the picked field ----------------
    var _rx = _x2 - _rw;
    ui_panel(_rx, _y1, _x2, _y2, "Field");
    var _gx = _rx + 20;
    var _gw = _rw - 40;
    var _gy = _y1 + 56;
    if (!_u.on || _nf == 0)
    {
        var _msg = "Add a field on the left.";
        if (!_u.on) { _msg = "Switch on 'Use a custom HUD' on the left to design your own."; }
        ui_text_wrap(_gx, _gy, _msg, global.TH.text_dim, _gw, global.f_body, 1);
        return;
    }
    var _sf = _u.fields[ui_sel_field];
    ui_heading(_gx, _gy, "Shows");
    set_val(_sf, "type", ui_dropdown("ui_ftype", _gx, _gy + 18, _gw, 30, ui_field_types(), _sf.type, "Shows|Text: just the label. Score, Lives, Level: the label then the number. Goal: the label (or the goal's name) and 'got / needed'. Tile carried: the tile's name and how many (tile worlds where the player digs). Tool: the label then the tool in use (8 letters; tile worlds with tools - Tiles page, Tools tab)."), "uiftype");
    _gy += 58;
    ui_heading(_gx, _gy, "Label (up to " + string(UI_LABEL_MAX) + " letters)");
    // each field has its own label box: picking another field drops the typing in the old one
    var _lid = "ui_flabel" + string(ui_sel_field);
    if (string_pos("ui_flabel", ui_focus) == 1 && ui_focus != _lid) { ui_focus = ""; }
    var _nl = ui_textfield(_lid, _gx, _gy + 18, _gw, 32, _sf.label, UI_LABEL_MAX, "Label|Drawn before the value, e.g. 'SCORE ' (end it with a space). For Text it is the whole text.");
    set_val(_sf, "label", string_upper(_nl), "uiflabel" + string(ui_sel_field));
    _gy += 62;
    var _gh = floor((_gw - 10) / 2);
    ui_heading(_gx, _gy, "Column (0-39)");
    ui_heading(_gx + _gh + 10, _gy, "Row (0-" + string(_u.rows - 1) + ")");
    set_val(_sf, "col", ui_stepper("ui_fcol", _gx, _gy + 18, _gh, _sf.col, 0, 39, "Column|Where the field starts across the screen, in 8-pixel steps (or drag it on the preview)."), "uifcol");
    set_val(_sf, "row", ui_stepper("ui_frow", _gx + _gh + 10, _gy + 18, _gh, _sf.row, 0, _u.rows - 1, "Row|Which text row of the panel."), "uifrow");
    _gy += 58;
    ui_heading(_gx, _gy, "Colour");
    set_val(_sf, "colour", ui_colour_drop("ui_fcolour", _gx, _gy + 18, _gw, 30, clamp(_sf.colour, 0, pal_count() - 1), "Colour|The letters' colour (a backdrop colour)."), "uifcolour");
    _gy += 58;
    var _shon = ui_toggle("ui_fshadow", _gx, _gy, "Shadow", _sf.shadow >= 0, "Shadow|A shadow one pixel down and to the right, in its own colour - it makes text stand out on a busy panel.");
    if (_shon != (_sf.shadow >= 0))
    {
        undo_mark("uifsh" + string(current_time));
        if (_shon) { _sf.shadow = pal_nearest(proj, 0x101010, max(2, pal_count())); }
        else { _sf.shadow = -1; }
    }
    _gy += 32;
    if (_sf.shadow >= 0)
    {
        set_val(_sf, "shadow", ui_colour_drop("ui_fshcol", _gx, _gy, _gw, 30, clamp(_sf.shadow, 0, pal_count() - 1), "Shadow colour|The shadow's colour."), "uifshcol");
        _gy += 40;
    }
    if (_sf.type == 1 || _sf.type == 2 || _sf.type == 5)
    {
        ui_heading(_gx, _gy, "Digits");
        set_val(_sf, "digits", ui_stepper("ui_fdig", _gx, _gy + 18, _gh, _sf.digits, 1, 6, "Digits|How many digits the number has, with leading zeros (score up to 99999)."), "uifdig");
        _gy += 58;
    }
    ui_text_wrap(_gx, _gy + 8, "Shows: " + ui_field_text(_sf), global.TH.text_faint, _gw, global.f_small, 1);
}

/// The 24 x 24 frame, magnified, with the 9-slice lines, and the colours to draw with
function ui_frame_editor(_x1, _y1, _x2, _y2)
{
    var _u = proj.ui;
    var _ncol = pal_count();
    var _pcols = 16;
    var _pcell = min(22, floor((_x2 - _x1 - (_pcols - 1) * 4) / _pcols));
    var _prow = ceil(_ncol / _pcols);
    var _ps = max(3, floor(min((_x2 - _x1) * 0.5, _y2 - _y1 - 10) / 24));
    var _gx = _x1;
    var _gy = _y1;
    var _gw = _ps * 24;
    ui_rrect(_gx - 4, _gy - 4, _gx + _gw + 4, _gy + _gw + 4, 6, pal_col(0), pal_col(0), 1);
    for (var _py = 0; _py < 24; _py++)
    {
        for (var _px = 0; _px < 24; _px++)
        {
            var _v = _u.frame[_py * 24 + _px];
            if (_v != 0) { draw_rectangle_colour(_gx + _px * _ps, _gy + _py * _ps, _gx + (_px + 1) * _ps - 1, _gy + (_py + 1) * _ps - 1, pal_col(_v), pal_col(_v), pal_col(_v), pal_col(_v), false); }
        }
    }
    draw_set_alpha(0.6);
    for (var l = 1; l < 3; l++)
    {
        draw_line_colour(_gx + l * 8 * _ps, _gy, _gx + l * 8 * _ps, _gy + _gw, c_white, c_white);
        draw_line_colour(_gx, _gy + l * 8 * _ps, _gx + _gw, _gy + l * 8 * _ps, c_white, c_white);
    }
    draw_set_alpha(1);
    var _hot = ui_register("ui_frame_canvas", _gx, _gy, _gx + _gw - 1, _gy + _gw - 1, "Frame|Left-click draws with the colour picked, right-click makes a pixel see-through. Corners stay put; the edges repeat along the panel and the fill repeats inside.");
    if (_hot)
    {
        var _hx = clamp(floor((ui_mx - _gx) / _ps), 0, 23);
        var _hy = clamp(floor((ui_my - _gy) / _ps), 0, 23);
        draw_rectangle_colour(_gx + _hx * _ps, _gy + _hy * _ps, _gx + (_hx + 1) * _ps - 1, _gy + (_hy + 1) * _ps - 1, c_white, c_white, c_white, c_white, true);
        if (ui_pressed || ui_rpressed)
        {
            ui_take_click();
            undo_mark("uiframe" + string(current_time));
            ui_drawing = true;
        }
        if (ui_drawing)
        {
            var _nv = -1;
            if (ui_held) { _nv = ui_pen; }
            if (ui_rheld) { _nv = 0; }
            if (_nv >= 0 && _u.frame[_hy * 24 + _hx] != _nv)
            {
                _u.frame[_hy * 24 + _hx] = _nv;
                _u.style = "Custom";
                proj_dirty = true;
            }
        }
    }
    if (!ui_held && !ui_rheld) { ui_drawing = false; }
    var _px2 = _gx + _gw + 24;
    ui_heading(_px2, _y1, "Colour " + string(ui_pen));
    // 8 across, or 16 across for the A1200's bigger palettes (128 colours 8 across ran far below the panel)
    var _fc = 8;
    if (_ncol > 32) { _fc = 16; }
    var _frows = ceil(_ncol / _fc);
    var _fcell = min(_pcell, floor((_x2 - _px2 - (_fc - 1) * 4) / _fc), floor((_y2 - _y1 - 18 + 4) / _frows) - 4);
    ui_pen = clamp(ui_palette_grid("ui_frame_pal", _px2, _y1 + 18, max(8, _fcell), _fc, ui_pen, "Colour|The backdrop colour to draw with."), 0, _ncol - 1);
}

/// The font: a grid of the 64 characters, and the picked one magnified to draw on
function ui_font_editor(_x1, _y1, _x2, _y2)
{
    var _u = proj.ui;
    var _font = ui_font_bytes(_u);
    var _cs = max(14, min(24, floor((_x2 - _x1) * 0.5 / 16)));
    for (var c = 0; c < 64; c++)
    {
        var _cx = _x1 + (c mod 16) * (_cs + 2);
        var _cy = _y1 + (c div 16) * (_cs + 2);
        var _hot = ui_register("ui_char_" + string(c), _cx, _cy, _cx + _cs, _cy + _cs, "Character|Click to draw it on the right.");
        var _bg = make_colour_rgb(22, 24, 30);
        if (c == ui_font_char) { _bg = global.TH.accent_dark; }
        else if (_hot) { _bg = make_colour_rgb(44, 48, 58); }
        draw_rectangle_colour(_cx, _cy, _cx + _cs - 1, _cy + _cs - 1, _bg, _bg, _bg, _bg, false);
        var _pp = max(1, floor((_cs - 4) / 8));
        for (var i = 0; i < 8; i++)
        {
            for (var b = 0; b < 8; b++)
            {
                if ((_font[c * 8 + i] & (0x80 >> b)) != 0) { draw_rectangle_colour(_cx + 2 + b * _pp, _cy + 2 + i * _pp, _cx + 2 + (b + 1) * _pp - 1, _cy + 2 + (i + 1) * _pp - 1, c_white, c_white, c_white, c_white, false); }
            }
        }
        if (_hot && ui_pressed)
        {
            ui_take_click();
            ui_font_char = c;
        }
    }
    var _ex = _x1 + 16 * (_cs + 2) + 24;
    var _ps = max(6, floor(min(_x2 - _ex, _y2 - _y1 - 54) / 8));     // room for the help below it (2 lines)
    ui_rrect(_ex - 4, _y1 - 4, _ex + 8 * _ps + 4, _y1 + 8 * _ps + 4, 6, make_colour_rgb(22, 24, 30), make_colour_rgb(22, 24, 30), 1);
    for (var i2 = 0; i2 < 8; i2++)
    {
        for (var b2 = 0; b2 < 8; b2++)
        {
            var _set = ((_font[ui_font_char * 8 + i2] & (0x80 >> b2)) != 0);
            var _col = make_colour_rgb(40, 44, 54);
            if (_set) { _col = c_white; }
            draw_rectangle_colour(_ex + b2 * _ps + 1, _y1 + i2 * _ps + 1, _ex + (b2 + 1) * _ps - 1, _y1 + (i2 + 1) * _ps - 1, _col, _col, _col, _col, false);
        }
    }
    // 270 px of text: wrapped, as only 262 px fit beside the character grid at 1280 wide
    ui_text_wrap(_ex, _y1 + 8 * _ps + 12, "'" + chr(32 + ui_font_char) + "'  - left-click draws, right-click rubs out", global.TH.text_dim, max(60, _x2 - _ex), global.f_small, 1);
    var _hot2 = ui_register("ui_font_canvas", _ex, _y1, _ex + 8 * _ps - 1, _y1 + 8 * _ps - 1, "Character|Left-click sets a pixel, right-click clears it. The first change makes the font Custom (starting from the style you had).");
    if (_hot2)
    {
        var _hb = clamp(floor((ui_mx - _ex) / _ps), 0, 7);
        var _hr = clamp(floor((ui_my - _y1) / _ps), 0, 7);
        if (ui_pressed || ui_rpressed)
        {
            ui_take_click();
            undo_mark("uifontdraw" + string(current_time));
            if (_u.font_style != 5)
            {
                _u.font = ui_font_bytes(_u);
                _u.font_style = 5;
            }
            ui_drawing = true;
        }
        if (ui_drawing && _u.font_style == 5)
        {
            var _k = ui_font_char * 8 + _hr;
            var _m = 0x80 >> _hb;
            var _old = _u.font[_k];
            if (ui_held) { _u.font[_k] = _old | _m; }
            if (ui_rheld) { _u.font[_k] = _old & ~_m & 255; }
            if (_u.font[_k] != _old) { proj_dirty = true; }
        }
    }
    if (!ui_held && !ui_rheld) { ui_drawing = false; }
}
