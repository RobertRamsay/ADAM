/// ADAM - theme, fonts and Amiga colour helpers

function theme_init()
{
    global.TH = {
        bg_top      : make_colour_rgb(44, 52, 66),
        bg_bot      : make_colour_rgb(17, 21, 29),
        bar_top     : make_colour_rgb(56, 66, 82),
        bar_bot     : make_colour_rgb(36, 43, 55),
        panel_top   : make_colour_rgb(53, 62, 77),
        panel_bot   : make_colour_rgb(35, 41, 52),
        panel_edge  : make_colour_rgb(80, 93, 112),
        inset_top   : make_colour_rgb(25, 30, 38),
        inset_bot   : make_colour_rgb(32, 38, 47),
        btn_top     : make_colour_rgb(76, 88, 106),
        btn_bot     : make_colour_rgb(55, 64, 78),
        btn_hot_top : make_colour_rgb(96, 110, 131),
        btn_hot_bot : make_colour_rgb(67, 78, 94),
        accent      : make_colour_rgb(84, 150, 255),
        accent_dark : make_colour_rgb(30, 92, 196),
        accent2     : make_colour_rgb(255, 150, 40),
        warn        : make_colour_rgb(255, 204, 87),
        danger      : make_colour_rgb(255, 107, 107),
        danger_dark : make_colour_rgb(176, 62, 62),
        text        : make_colour_rgb(230, 235, 242),
        text_dim    : make_colour_rgb(154, 165, 180),
        text_faint  : make_colour_rgb(104, 114, 130),
        shadow      : c_black,
        radius      : 10
    };

    global.ui_scale = 1;
    global.ui_sx = 1;
    global.ui_sy = 1;
    global.f_body  = -1;
    global.f_bold  = -1;
    global.f_small = -1;
    global.f_title = -1;
    global.f_hero  = -1;
    fonts_load(1);
}

/// (Re)creates the fonts rasterised for the given interface scale
function fonts_load(_scale)
{
    theme_free();
    global.f_body  = -1;
    global.f_bold  = -1;
    global.f_small = -1;
    global.f_title = -1;
    global.f_hero  = -1;
    var _dir = working_directory + "fonts/";
    if (file_exists(_dir + "Poppins-Regular.ttf"))
    {
        global.f_body  = font_add(_dir + "Poppins-Regular.ttf", round(12 * _scale), false, false, 32, 255);
        global.f_small = font_add(_dir + "Poppins-Regular.ttf", round(10 * _scale), false, false, 32, 255);
    }
    if (file_exists(_dir + "Poppins-Medium.ttf"))
    {
        global.f_bold  = font_add(_dir + "Poppins-Medium.ttf", round(12 * _scale), false, false, 32, 255);
        global.f_title = font_add(_dir + "Poppins-Medium.ttf", round(16 * _scale), false, false, 32, 255);
    }
    if (file_exists(_dir + "Poppins-Bold.ttf"))
    {
        global.f_hero = font_add(_dir + "Poppins-Bold.ttf", round(26 * _scale), false, false, 32, 255);
    }
    if (global.f_body == -1)  { global.f_body  = -1; }
    if (global.f_bold == -1)  { global.f_bold  = global.f_body; }
    if (global.f_title == -1) { global.f_title = global.f_bold; }
    if (global.f_hero == -1)  { global.f_hero  = global.f_title; }
    if (global.f_small == -1) { global.f_small = global.f_body; }
}

function theme_free()
{
    if (is_undefined(global.f_body)) { return; }
    var _list = [global.f_body, global.f_bold, global.f_small, global.f_title, global.f_hero];
    var _done = [];
    for (var i = 0; i < array_length(_list); i++)
    {
        var _f = _list[i];
        if (_f != -1 && font_exists(_f))
        {
            var _already = false;
            for (var j = 0; j < array_length(_done); j++)
            {
                if (_done[j] == _f) { _already = true; }
            }
            if (!_already)
            {
                font_delete(_f);
                array_push(_done, _f);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Amiga colours are stored as 24-bit $RRGGBB numbers. The A500/600 profile
// (OCS/ECS) only has 4 bits per gun, so colours are rounded to the nearest
// of its 4096 when shown or built. The A1200 (AGA) keeps all 24 bits.
// ---------------------------------------------------------------------------

function rgb_r(_c) { return (_c >> 16) & 255; }
function rgb_g(_c) { return (_c >> 8) & 255; }
function rgb_b(_c) { return _c & 255; }
function rgb_make(_r, _g, _b) { return (clamp(round(_r), 0, 255) << 16) | (clamp(round(_g), 0, 255) << 8) | clamp(round(_b), 0, 255); }

/// Rounds one 8-bit gun to the nearest 4-bit Amiga OCS level (n * 17)
function gun12(_v)
{
    return round(clamp(_v, 0, 255) / 17) * 17;
}

/// The colour the selected machine will really show
function rgb_machine(_c)
{
    if (machine_cur().aga) { return _c & $ffffff; }
    return rgb_make(gun12(rgb_r(_c)), gun12(rgb_g(_c)), gun12(rgb_b(_c)));
}

/// GameMaker colour for an Amiga $RRGGBB value, as the machine shows it
function amiga_col(_c)
{
    var _m = rgb_machine(_c);
    return make_colour_rgb(rgb_r(_m), rgb_g(_m), rgb_b(_m));
}

/// GameMaker colour for backdrop palette entry _i
function pal_col(_i)
{
    var _n = array_length(proj.pal);
    var _k = clamp(floor(_i), 0, _n - 1);
    return amiga_col(proj.pal[_k]);
}

/// Number of usable backdrop colours (2 ^ depth)
function pal_count()
{
    return 1 << clamp(proj.depth, 1, 7);
}

/// Short text like "#F80" (OCS) or "#FF8800" (AGA)
function rgb_hex(_c)
{
    var _m = rgb_machine(_c);
    var _h = "0123456789ABCDEF";
    if (machine_cur().aga)
    {
        var _s = "#";
        var _gun = [rgb_r(_m), rgb_g(_m), rgb_b(_m)];
        for (var i = 0; i < 3; i++)
        {
            _s += string_char_at(_h, (_gun[i] div 16) + 1) + string_char_at(_h, (_gun[i] mod 16) + 1);
        }
        return _s;
    }
    return "#" + string_char_at(_h, (rgb_r(_m) div 17) + 1) + string_char_at(_h, (rgb_g(_m) div 17) + 1) + string_char_at(_h, (rgb_b(_m) div 17) + 1);
}
