/// ADAM - Sound workspace (Paula sample effects)

function ws_sound_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 240;
    snd_sel = clamp(snd_sel, 0, array_length(proj.sfx) - 1);
    sound_list_draw(_x1, _y1, _x1 + _lw, _y2);

    var _cx1 = _x1 + _lw + 12;
    var _s = proj.sfx[snd_sel];
    var _title = "Sound " + string(snd_sel + 1);
    if (snd_sel >= lim_sounds()) { _title += "  (Pro - silent in ADAM Lite games)"; }
    ui_panel(_cx1, _y1, _x2, _y2, _title);
    var _fx = _cx1 + 20;
    var _colw = min(420, floor((_x2 - _cx1 - 60) / 2));
    var _y = _y1 + 56;
    var _nw = floor(_colw * 0.55);
    ui_heading(_fx, _y, "Name");
    set_val(_s, "name", ui_textfield("snd_name", _fx, _y + 18, _nw, 32, _s.name, 16, "Sound name|Shown in the Logic page when you pick a sound to play."), "sndname");
    ui_heading(_fx + _nw + 8, _y, "Folder");
    var _fnames = ["(none)"];
    for (var g = 0; g < array_length(proj.sound_groups); g++) { array_push(_fnames, proj.sound_groups[g].name); }
    var _fg = ui_dropdown("snd_folder", _fx + _nw + 8, _y + 18, _colw - _nw - 8, 32, _fnames, clamp(_s.group + 1, 0, array_length(_fnames) - 1), "Folder|Which Sound page folder this sound is in. Make folders with + Folder; you can also drag a sound onto a folder.");
    set_val(_s, "group", _fg - 1, "sndfolder");
    _y += 62;
    ui_heading(_fx, _y, "Type of sound");
    var _kw = floor((_colw - 16) / 3);
    var _k0 = BTN_GHOST;
    var _k1 = BTN_GHOST;
    var _k2 = BTN_GHOST;
    if (_s.kind == 0) { _k0 = BTN_ACCENT; }
    else if (_s.kind == 1) { _k1 = BTN_ACCENT; }
    else { _k2 = BTN_ACCENT; }
    if (ui_button("snd_kind_0", _fx, _y + 18, _kw, 32, "Synth", "Synth sound|Built from a waveform, pitch slide and envelope. Tiny in memory.", _k0)) { set_val(_s, "kind", 0, "sndkind" + string(current_time)); }
    if (ui_button("snd_kind_1", _fx + _kw + 8, _y + 18, _kw, 32, "Sample", "Sampled sound|Import a WAV - a voice, a drum hit, a real explosion - then crunch it down for Paula with the rate and bit settings.", _k1)) { set_val(_s, "kind", 1, "sndkind" + string(current_time)); }
    if (ui_button("snd_kind_2", _fx + (_kw + 8) * 2, _y + 18, _kw, 32, "Patch", "Patch synth|A big synth: three oscillators with sync, ring and FM, a resonant filter, envelopes, LFOs, modulation and effects. ADAM renders it into a sample - one-shot or with a looped sustain for music.", _k2)) { set_val(_s, "kind", 2, "sndkind" + string(current_time)); }
    _y += 62;
    if (keyboard_check_pressed(vk_space) && ui_focus == "" && ui_can_input() && !keyboard_check(vk_control)) { sfx_preview_play(_s); }
    if (_s.kind == 1)
    {
        sound_sample_panel(_s, _fx, _y, _colw, _cx1, _x2, _y1, _y2);
        return;
    }
    if (_s.kind == 2)
    {
        sound_patch_panel(_s, _fx, _y, _colw, _cx1, _x2, _y1, _y2);
        return;
    }
    ui_heading(_fx, _y, "Waveform");
    set_val(_s, "wave", ui_dropdown("snd_wave", _fx, _y + 18, _colw, 32, global.WAVE_NAMES, _s.wave, "Waveform|The basic tone. Triangle is soft and flute-like, sawtooth is buzzy, square is the classic chip sound and noise is for explosions and drums."), "sndwave");
    _y += 62;
    ui_heading(_fx, _y, "Pitch  " + string(_s.pitch));
    set_val(_s, "pitch", ui_slider("snd_pitch", _fx, _y + 18, _colw, _s.pitch, 1, 255, "Pitch|How high the sound starts. Low numbers are deep, high numbers are squeaky."), "sndpitch");
    _y += 54;
    var _half = floor((_colw - 12) / 2);
    ui_heading(_fx, _y, "Pitch slide");
    set_val(_s, "sweep", ui_stepper("snd_sweep", _fx, _y + 18, _half, _s.sweep, -8, 8, "Pitch slide|How much the pitch rises (+) or falls (-) every frame. Falling slides make lasers, rising slides make coins and power-ups."), "sndsweep");
    ui_heading(_fx + _half + 12, _y, "Length (frames)");
    set_val(_s, "len", ui_stepper("snd_len", _fx + _half + 12, _y + 18, _half, _s.len, 1, 100, "Length|How long the note is held, in 50ths of a second. The release then fades it out."), "sndlen");
    _y += 62;
    var _third = floor((_colw - 16) / 3);
    ui_heading(_fx, _y, "Filter");
    ui_heading(_fx + _third + 8, _y, "Sweep speed");
    ui_heading(_fx + (_third + 8) * 2, _y, "Sweep depth");
    set_val(_s, "filt", ui_stepper("snd_filt", _fx, _y + 18, _third, _s.filt, 0, 15, "Filter|Softens the sound: 0 is off, 1 is very dark and muffled, 15 is nearly open. Great on noise for wind, rain and surf."), "sndfilt");
    set_val(_s, "fspeed", ui_stepper("snd_fspeed", _fx + _third + 8, _y + 18, _third, _s.fspeed, 0, 15, "Sweep speed|How fast the filter sweeps up and down (0 = it stays put; 1 is one sweep every 4 seconds, 15 nearly 4 a second). A slow sweep on filtered noise is a gust of wind. With a sweep a sound can last up to 3 seconds."), "sndfspeed");
    set_val(_s, "fdepth", ui_stepper("snd_fdepth", _fx + (_third + 8) * 2, _y + 18, _third, _s.fdepth, 0, 15, "Sweep depth|How far the sweep opens and closes the filter (15 = three octaves each way)."), "sndfdepth");
    _y += 62;
    ui_heading(_fx, _y, "Envelope (attack, decay, sustain, release)");
    _y += 22;
    var _lab = ["Attack", "Decay", "Sustain", "Release"];
    var _keys = ["atk", "dec", "sus", "rel"];
    var _ehelp = ["Attack|How quickly the sound fades in. 0 is instant.",
                  "Decay|How quickly it drops from full volume to the sustain level.",
                  "Sustain|The volume held while the note is on. 0 makes short plucky sounds.",
                  "Release|How long the sound takes to fade away at the end."];
    for (var e = 0; e < 4; e++)
    {
        ui_text(_fx, _y + 13, _lab[e], global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        set_val(_s, _keys[e], ui_slider("snd_" + _keys[e], _fx + 70, _y, _colw - 110, _s[$ _keys[e]], 0, 15, _ehelp[e]), "snd" + _keys[e]);
        ui_text(_fx + _colw, _y + 13, string(_s[$ _keys[e]]), global.TH.text, fa_right, fa_middle, global.f_bold, 1);
        _y += 32;
    }
    _y += 10;
    if (ui_button("snd_preview", _fx, _y, _colw, 40, "Play sound", "Play|Hear the sound exactly as the Amiga will play it - ADAM turns it into an 8-bit sample for Paula.", BTN_ACCENT))
    {
        sfx_preview_play(_s);
    }

    // right column: envelope graph + presets
    var _gx = _fx + _colw + 30;
    var _gw = _x2 - 20 - _gx;
    var _gy = _y1 + 74;
    ui_heading(_gx, _gy - 18, "Shape");
    ui_inset(_gx, _gy, _gx + _gw, _gy + 150, 10);
    ui_register("snd_graph", _gx, _gy, _gx + _gw, _gy + 150, "Envelope shape|A picture of how loud the sound is over time: it rises (attack), falls (decay), holds (sustain) then fades (release).");
    var _a1 = 6 + _s.atk * 4;
    var _d1 = 6 + _s.dec * 5;
    var _hold = 10 + _s.len * 1.2;
    var _r1 = 6 + _s.rel * 5;
    var _tot = _a1 + _d1 + _hold + _r1;
    var _sc = (_gw - 30) / _tot;
    var _base = _gy + 135;
    var _top = _gy + 18;
    var _sus = _base - (_base - _top) * (_s.sus / 15);
    var _px0 = _gx + 15;
    var _px1 = _px0 + _a1 * _sc;
    var _px2 = _px1 + _d1 * _sc;
    var _px3 = _px2 + _hold * _sc;
    var _px4 = _px3 + _r1 * _sc;
    draw_set_alpha(0.25);
    draw_set_colour(global.TH.accent);
    draw_primitive_begin(pr_trianglestrip);
    draw_vertex(_px0, _base); draw_vertex(_px1, _top);
    draw_vertex(_px1, _base); draw_vertex(_px2, _sus);
    draw_vertex(_px2, _base); draw_vertex(_px3, _sus);
    draw_vertex(_px3, _base); draw_vertex(_px4, _base);
    draw_primitive_end();
    draw_set_alpha(1);
    draw_line_width_colour(_px0, _base, _px1, _top, 3, global.TH.accent, global.TH.accent);
    draw_line_width_colour(_px1, _top, _px2, _sus, 3, global.TH.accent, global.TH.accent);
    draw_line_width_colour(_px2, _sus, _px3, _sus, 3, global.TH.accent, global.TH.accent);
    draw_line_width_colour(_px3, _sus, _px4, _base, 3, global.TH.accent, global.TH.accent);
    var _progress = sfx_preview_progress(_s, sfx_render_ex(_s));
    if (_progress >= 0)
    {
        var _marker_x = lerp(_px0, _px4, _progress);
        draw_line_width_colour(_marker_x, _gy + 8, _marker_x, _base, 2, global.TH.warn, global.TH.warn);
    }
    ui_text((_px0 + _px1) / 2, _base + 2, "A", global.TH.text_faint, fa_center, fa_top, global.f_small, 1);
    ui_text((_px1 + _px2) / 2, _base + 2, "D", global.TH.text_faint, fa_center, fa_top, global.f_small, 1);
    ui_text((_px2 + _px3) / 2, _base + 2, "S", global.TH.text_faint, fa_center, fa_top, global.f_small, 1);
    ui_text((_px3 + _px4) / 2, _base + 2, "R", global.TH.text_faint, fa_center, fa_top, global.f_small, 1);

    var _py = _gy + 180;
    ui_heading(_gx, _py, "Start from a preset");
    _py += 20;
    var _bw = floor((_gw - 16) / 3);
    for (var p = 0; p < 8; p++)
    {
        var _bx = _gx + (p mod 3) * (_bw + 8);
        var _by = _py + (p div 3) * 42;
        if (ui_button("snd_preset_" + string(p), _bx, _by, _bw, 34, global.SFX_PRESET_NAMES[p], global.SFX_PRESET_NAMES[p] + " preset|Replaces this sound's settings with a ready-made " + string_lower(global.SFX_PRESET_NAMES[p]) + " sound and plays it.", BTN_NORMAL))
        {
            undo_mark("sndpreset" + string(current_time));
            sfx_apply_preset(_s, p);
            sfx_preview_play(_s);
        }
    }
    _py += 3 * 42 + 10;
    ui_text_wrap(_gx, _py, "ADAM turns synth sounds into 8-bit samples (about 11 kHz, up to 1.5 seconds, or 3 with a filter sweep) stored in chip RAM. Sounds play on Paula channel 1 to 4 (sound number 1 and 5 share channel 1, and so on).", global.TH.text_faint, _gw, global.f_small, 1);
}

/// The Sound page's left panel: sounds in folders, scrolling, with add / copy / delete
function sound_list_draw(_x1, _y1, _x2, _y2)
{
    var _n = array_length(proj.sfx);
    var _lim = lim_sounds();
    ui_panel(_x1, _y1, _x2, _y2, "Sounds  (" + string(_n) + " / " + string(_lim) + ")");
    var _ng = array_length(proj.sound_groups);

    // rows: folder headers (kind 1) and sounds (kind 0); sounds in no folder come first
    var _rows = [];
    for (var g = -1; g < _ng; g++)
    {
        var _count = 0;
        for (var c = 0; c < _n; c++)
        {
            if (sound_folder_of(c) == g) { _count += 1; }
        }
        var _open = snd_ungrouped_open;
        if (g >= 0) { _open = proj.sound_groups[g].open; }
        if (g >= 0 || _ng > 0) { array_push(_rows, { kind : 1, group : g, count : _count, h : 36 }); }
        if (g == -1 && _ng == 0) { _open = true; }
        if (!_open) { continue; }
        for (var i = 0; i < _n; i++)
        {
            if (sound_folder_of(i) == g) { array_push(_rows, { kind : 0, idx : i, group : g, h : 52 }); }
        }
    }
    var _content = 8;
    var _offsets = [];
    for (var r = 0; r < array_length(_rows); r++)
    {
        array_push(_offsets, _content);
        _content += _rows[r].h;
    }
    var _ly1 = _y1 + 48;
    var _ly2 = _y2 - 88;
    var _off = ui_scroll_begin("snd_list", _x1 + 4, _ly1, _x2 - 4, _ly2, _content);
    var _ix1 = _x1 + 10;
    var _ix2 = _x2 - 22;
    var _hover_group = -2;
    for (var r2 = 0; r2 < array_length(_rows); r2++)
    {
        var _row = _rows[r2];
        var _ry = _ly1 + _offsets[r2] - _off;
        if (_ry + _row.h < _ly1 || _ry > _ly2) { continue; }
        if (_row.kind == 1)
        {
            var _gi = _row.group;
            var _gopen = snd_ungrouped_open;
            var _gname = "No folder";
            if (_gi >= 0) { _gopen = proj.sound_groups[_gi].open; _gname = proj.sound_groups[_gi].name; }
            ui_rrect(_ix1, _ry, _ix2, _ry + 30, 6, global.TH.btn_top, global.TH.btn_bot, 1);
            if (snd_drag >= 0 && ui_hit(_ix1, _ry, _ix2, _ry + 30))
            {
                _hover_group = _gi;
                ui_rrect_line(_ix1, _ry, _ix2, _ry + 30, 6, global.TH.accent, 1, 2);
            }
            var _arrow = ">";
            if (_gopen) { _arrow = "v"; }
            if (ui_button("snd_folder_open_" + string(_gi), _ix1 + 2, _ry + 2, 26, 26, _arrow, "Open / close folder|Shows or hides the sounds in this folder.", BTN_GHOST))
            {
                if (_gi < 0) { snd_ungrouped_open = !_gopen; }
                else { proj.sound_groups[_gi].open = !_gopen; }
            }
            if (_gi >= 0)
            {
                var _renamed = ui_textfield("snd_folder_name_" + string(_gi), _ix1 + 32, _ry + 2, _ix2 - _ix1 - 90, 26, _gname, 24, "Folder name|Type a new name. Drag a sound onto this header to put it in the folder.");
                if (_renamed != _gname) { undo_mark("sndfolderrename" + string(_gi)); proj.sound_groups[_gi].name = _renamed; }
                if (ui_button("snd_folder_del_" + string(_gi), _ix2 - 28, _ry + 2, 26, 26, "x", "Remove folder|Removes the folder. Its sounds are kept, in no folder.", BTN_GHOST))
                {
                    sound_folder_remove(_gi);
                    return;
                }
            }
            else { ui_text(_ix1 + 36, _ry + 15, _gname, global.TH.text_dim, fa_left, fa_middle, global.f_small, 1); }
            ui_text(_ix2 - 34, _ry + 15, string(_row.count), global.TH.text_faint, fa_right, fa_middle, global.f_small, 1);
            continue;
        }
        var _i = _row.idx;
        var _id = "snd_slot_" + string(_i);
        var _f = proj.sfx[_i];
        var _hot = ui_register(_id, _ix1, _ry, _ix2, _ry + 46, _f.name + "|Click to edit this sound. Rules on the Logic page, tiles and Music page loops can play it. Drag it onto a folder to move it.");
        if (snd_drag >= 0 && ui_hit(_ix1, _ry, _ix2, _ry + 46)) { _hover_group = _row.group; }
        var _tgt = 0;
        if (_hot) { _tgt = 1; }
        var _a = ui_anim_to(_id, _tgt);
        if (snd_sel == _i) { ui_rrect(_ix1, _ry, _ix2, _ry + 46, 10, global.TH.accent, global.TH.accent_dark, 0.9); }
        else { ui_rrect(_ix1, _ry, _ix2, _ry + 46, 10, global.TH.btn_hot_top, global.TH.btn_hot_bot, 0.25 + _a * 0.75); }
        var _label = string(_i + 1) + ". " + ui_text_fit(_f.name, global.f_bold, _ix2 - _ix1 - 110);
        ui_text(_ix1 + 14, _ry + 15, _label, global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        var _sub = global.WAVE_NAMES[clamp(_f.wave, 0, 3)];
        if (_f.kind == 1) { _sub = "Sample: " + _f.smp_file; }
        if (_f.kind == 2) { _sub = "Patch: " + patch_key_name(_f.patch.key); }
        if (_i >= _lim) { _sub = "Pro: silent in Lite games"; }
        ui_text(_ix1 + 14, _ry + 33, ui_text_fit(_sub, global.f_small, _ix2 - _ix1 - 86), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        if (ui_button(_id + "_play", _ix2 - 62, _ry + 8, 54, 30, "Play", "Play|Hear this sound.", BTN_GHOST))
        {
            sfx_preview_play(_f);
        }
        if (_hot && ui_pressed)
        {
            if (mus_playing && (mus_play_what == "sound" || mus_play_what == "sound_note")) { sfx_preview_stop(); }
            snd_sel = _i;
            snd_drag = _i;
            snd_drag_y0 = ui_my;
            snd_dragging = false;
            ui_take_click();
        }
    }
    ui_scroll_end("snd_list", _x1 + 4, _ly1, _x2 - 4, _ly2, _content);

    // drag a sound onto a folder (or onto "No folder")
    if (snd_drag >= 0)
    {
        if (ui_held)
        {
            if (abs(ui_my - snd_drag_y0) > 8) { snd_dragging = true; }
            if (snd_dragging)
            {
                if (ui_my < _ly1 + 20) { ds_map_replace(ui_scroll, "snd_list", max(0, _off - 6)); }
                if (ui_my > _ly2 - 20) { ds_map_replace(ui_scroll, "snd_list", clamp(_off + 6, 0, max(0, _content - (_ly2 - _ly1)))); }
                var _dn = proj.sfx[clamp(snd_drag, 0, _n - 1)].name;
                ui_rrect(ui_mx + 12, ui_my + 8, ui_mx + 160, ui_my + 34, 6, global.TH.accent, global.TH.accent_dark, 0.9);
                ui_text(ui_mx + 20, ui_my + 21, ui_text_fit(_dn, global.f_small, 132), c_white, fa_left, fa_middle, global.f_small, 1);
            }
        }
        else
        {
            if (snd_dragging && _hover_group > -2 && snd_drag < _n && proj.sfx[snd_drag].group != _hover_group)
            {
                undo_mark("sndfoldermove" + string(current_time));
                proj.sfx[snd_drag].group = _hover_group;
                if (_hover_group >= 0) { proj.sound_groups[_hover_group].open = true; }
            }
            snd_drag = -1;
            snd_dragging = false;
        }
    }

    // ---- add / folder / copy / delete ----
    var _bw = floor((_x2 - _x1 - 28) / 2);
    var _by = _y2 - 80;
    var _add_style = BTN_NORMAL;
    if (_n >= _lim) { _add_style = BTN_GHOST; }
    if (ui_button("snd_add", _x1 + 10, _by, _bw, 32, "+ Sound", "Add a sound|A new sound in the selected sound's folder. ADAM Lite has " + string(LITE_SOUNDS) + " sounds, ADAM Pro up to " + string(SFX_MAX) + ". Only sounds a rule or a tile plays go on the disk.", _add_style))
    {
        sound_add(sfx_new("Sound " + string(_n + 1)));
    }
    if (ui_button("snd_folder_add", _x1 + 18 + _bw, _by, _bw, 32, "+ Folder", "Add a folder|Groups sounds - player, enemies, music instruments... Drag sounds onto it.", BTN_NORMAL))
    {
        if (_ng >= SFX_MAX) { toast("That is a lot of folders already", 1); }
        else
        {
            undo_mark("sndfolderadd" + string(current_time));
            array_push(proj.sound_groups, { name : "Folder " + string(_ng + 1), open : true });
        }
    }
    if (ui_button("snd_copy", _x1 + 10, _by + 40, _bw, 32, "Duplicate", "Duplicate|A copy of the selected sound, to try changes on.", _add_style))
    {
        var _copy = json_parse(json_stringify(proj.sfx[snd_sel]));
        _copy.patch = patch_from_loaded(_copy.patch);
        _copy.name = string_copy("Copy " + _copy.name, 1, 16);
        sound_add(_copy);
    }
    if (ui_button("snd_delete", _x1 + 18 + _bw, _by + 40, _bw, 32, "Delete", "Delete|Removes the selected sound if nothing uses it. Later sounds are renumbered and every rule, tile and loop is fixed up.", BTN_GHOST))
    {
        sound_delete(snd_sel);
    }
}

/// The folder sound _i is shown in (-1 = none)
function sound_folder_of(_i)
{
    var _g = proj.sfx[_i].group;
    if (_g < 0 || _g >= array_length(proj.sound_groups)) { return -1; }
    return _g;
}

/// Adds sound _s after the others, in the selected sound's folder, and selects it
function sound_add(_s)
{
    var _n = array_length(proj.sfx);
    if (_n >= lim_sounds())
    {
        lim_toast("There are " + string(lim_sounds()) + " sounds", string(SFX_MAX) + " sounds");
        return;
    }
    undo_mark("sndadd" + string(current_time));
    _s.group = sound_folder_of(clamp(snd_sel, 0, _n - 1));
    array_push(proj.sfx, _s);
    snd_sel = _n;
    snd_patch_last = array_create(SFX_MAX, 0);
    if (_s.group >= 0) { proj.sound_groups[_s.group].open = true; }
    else { snd_ungrouped_open = true; }
}

/// Deletes sound _k when nothing plays it, renumbering the later sounds' users
function sound_delete(_k)
{
    var _n = array_length(proj.sfx);
    if (_n <= 1)
    {
        toast("A game keeps at least one sound", 1);
        return;
    }
    var _rules = 0;
    for (var r = 0; r < array_length(proj.rules); r++)
    {
        var _ru = proj.rules[r];
        if (_ru.act == 2 && _ru.value == _k) { _rules += 1; }
        for (var m = 0; m < array_length(_ru.more); m++)
        {
            if (_ru.more[m].act == 2 && _ru.more[m].value == _k) { _rules += 1; }
        }
    }
    var _tiles = 0;
    for (var t = 0; t < array_length(proj.tiles); t++)
    {
        if (proj.tiles[t].sound == _k) { _tiles += 1; }
    }
    var _loops = sfx_music_uses(proj, _k);
    if (_rules + _tiles + _loops > 0)
    {
        var _parts = [];
        if (_rules > 0) { array_push(_parts, string(_rules) + " rule line" + sound_plural(_rules)); }
        if (_tiles > 0) { array_push(_parts, string(_tiles) + " tile" + sound_plural(_tiles)); }
        if (_loops > 0) { array_push(_parts, string(_loops) + " music loop" + sound_plural(_loops)); }
        var _msg = "";
        for (var p = 0; p < array_length(_parts); p++)
        {
            if (p > 0 && p == array_length(_parts) - 1) { _msg += " and "; }
            else if (p > 0) { _msg += ", "; }
            _msg += _parts[p];
        }
        toast(proj.sfx[_k].name + " is used by " + _msg + " - change those first", 1);
        return;
    }
    undo_mark_full("snddelete" + string(current_time));
    sfx_preview_stop();
    var _name = proj.sfx[_k].name;
    array_delete(proj.sfx, _k, 1);
    sfx_refs_shift(proj, _k + 1, -1);
    snd_sel = clamp(_k, 0, array_length(proj.sfx) - 1);
    snd_patch_last = array_create(SFX_MAX, 0);
    music_touch();
    toast("Deleted " + _name, 0);
}

function sound_plural(_n)
{
    if (_n == 1) { return ""; }
    return "s";
}

/// Removes folder _g: its sounds stay, in no folder
function sound_folder_remove(_g)
{
    undo_mark("sndfolderdel" + string(current_time));
    for (var i = 0; i < array_length(proj.sfx); i++)
    {
        if (proj.sfx[i].group == _g) { proj.sfx[i].group = -1; }
        else if (proj.sfx[i].group > _g) { proj.sfx[i].group -= 1; }
    }
    array_delete(proj.sound_groups, _g, 1);
}

/// Sample controls (Sound page when the sound is a sample)
function sound_sample_keyboard(_s, _px, _py, _width, _height)
{
    var _keys = ["Z", "S", "X", "D", "C", "V", "G", "B", "H", "N", "J", "M", "Q", "2", "W", "3", "E", "R", "5", "T", "6", "Y", "7", "U", "I", "9", "O", "0", "P"];
    var _white = [0, 2, 4, 5, 7, 9, 11];
    var _black = [1, 3, 6, 8, 10];
    var _black_after = [0, 1, 3, 4, 5];
    var _white_width = _width / 17;
    var _black_width = _white_width * 0.62;
    var _black_height = _height * 0.60;
    var _hit_note = -1;
    var _active = -1;
    if (mus_playing && mus_play_what == "sound_note" && preview_source == _s) { _active = snd_jam_note; }
    for (var _octave = 0; _octave < 3; _octave++)
    {
        for (var _key = 0; _key < 7; _key++)
        {
            var _offset = _octave * 12 + _white[_key];
            if (_offset >= array_length(_keys)) { continue; }
            var _note = 1 + _offset;
            var _key_x = _px + (_octave * 7 + _key) * _white_width;
            var _colour = make_colour_rgb(228, 232, 238);
            if (_active == _note) { _colour = merge_colour(_colour, global.TH.accent, 0.55); }
            ui_rrect(_key_x + 1, _py, _key_x + _white_width - 1, _py + _height, 3, _colour, _colour, 1);
            ui_rrect_line(_key_x + 1, _py, _key_x + _white_width - 1, _py + _height, 3, c_black, 0.75, 1);
            ui_text(_key_x + _white_width * 0.5, _py + _height - 24, _keys[_offset], c_black, fa_center, fa_middle, global.f_bold, 1);
            ui_text(_key_x + _white_width * 0.5, _py + _height - 9, music_note_name(_note), c_black, fa_center, fa_middle, global.f_small, 1);
            if (ui_register("snd_piano_" + string(_note), _key_x, _py, _key_x + _white_width, _py + _height, music_note_name(_note) + "|Click or press " + _keys[_offset] + " to play this sample here. Q is natural speed; Z-M plays the lower octave and Q-P plays upwards, with number keys for sharps. Looping notes sustain while held.")) { _hit_note = _note; }
        }
    }
    for (var _octave = 0; _octave < 3; _octave++)
    {
        for (var _key = 0; _key < 5; _key++)
        {
            var _offset = _octave * 12 + _black[_key];
            if (_offset >= array_length(_keys)) { continue; }
            var _note = 1 + _offset;
            var _key_x = _px + (_octave * 7 + _black_after[_key] + 1) * _white_width - _black_width * 0.5;
            var _colour = global.TH.panel_bot;
            if (_active == _note) { _colour = global.TH.accent; }
            ui_rrect(_key_x, _py, _key_x + _black_width, _py + _black_height, 3, _colour, _colour, 1);
            ui_text(_key_x + _black_width * 0.5, _py + _black_height - 12, _keys[_offset], c_white, fa_center, fa_middle, global.f_small, 1);
            if (ui_register("snd_piano_" + string(_note), _key_x, _py, _key_x + _black_width, _py + _black_height, music_note_name(_note) + "|Click or press " + _keys[_offset] + " to play this sample here.")) { _hit_note = _note; }
        }
    }
    var _play_note = -1;
    var _play_key = -1;
    var _mouse = false;
    if (ui_focus == "" && ui_can_input() && !keyboard_check(vk_control) && !keyboard_check(vk_alt))
    {
        for (var _key = 0; _key < array_length(_keys); _key++)
        {
            if (keyboard_check_pressed(ord(_keys[_key]))) { _play_note = 1 + _key; _play_key = ord(_keys[_key]); }
        }
    }
    if (_hit_note >= 0 && (ui_pressed || (snd_jam_mouse && ui_held && _hit_note != snd_jam_note)))
    {
        ui_take_click();
        ui_focus = "";
        _play_note = _hit_note;
        _play_key = -1;
        _mouse = true;
    }
    if (_play_note >= 0)
    {
        sfx_preview_note(_s, _play_note);
        snd_jam_note = _play_note;
        snd_jam_key = _play_key;
        snd_jam_mouse = _mouse;
    }
    if (mus_playing && mus_play_what == "sound_note")
    {
        var _released = (snd_jam_mouse && !ui_held);
        if (snd_jam_key >= 0 && !keyboard_check(snd_jam_key)) { _released = true; }
        if (preview_loop_end > preview_loop_start)
        {
            if (_released) { sfx_preview_stop(); }
        }
        else if ((get_timer() - mus_play_t0) / 1000000 >= preview_note_end) { sfx_preview_stop(); }
    }
}

/// A rendered sound's waveform (min / max per column), its loop in green and the playback marker
function sound_draw_wave(_s, _r, _gx, _gy, _gw, _gh, _help)
{
    ui_inset(_gx, _gy, _gx + _gw, _gy + _gh, 10);
    ui_register("snd_graph", _gx, _gy, _gx + _gw, _gy + _gh, _help);
    var _n = array_length(_r.smp);
    var _mid = _gy + _gh * 0.5;
    var _amp = _gh * 0.5 - 10;
    if (_r.loop_len >= 4 && _n > 0)
    {
        var _loop_x1 = _gx + 10 + (_gw - 20) * _r.loop_start / _n;
        var _loop_x2 = _gx + 10 + (_gw - 20) * (_r.loop_start + _r.loop_len) / _n;
        var _loop_col = make_colour_rgb(80, 220, 120);
        draw_set_alpha(0.15);
        draw_rectangle_colour(_loop_x1, _gy + 8, _loop_x2, _gy + _gh - 8, _loop_col, _loop_col, _loop_col, _loop_col, false);
        draw_set_alpha(1);
        draw_line_width_colour(_loop_x1, _gy + 8, _loop_x1, _gy + _gh - 8, 2, _loop_col, _loop_col);
        draw_line_width_colour(_loop_x2, _gy + 8, _loop_x2, _gy + _gh - 8, 2, _loop_col, _loop_col);
    }
    if (_n > 1)
    {
        var _cols = floor(_gw - 20);
        draw_set_colour(global.TH.accent);
        for (var c = 0; c < _cols; c++)
        {
            var _a = floor(c * _n / _cols);
            var _e = max(_a + 1, floor((c + 1) * _n / _cols));
            var _lo = 0;
            var _hi = 0;
            for (var k = _a; k < min(_e, _n); k++)
            {
                _lo = min(_lo, _r.smp[k]);
                _hi = max(_hi, _r.smp[k]);
            }
            draw_line(_gx + 10 + c, _mid - _hi / 128 * _amp, _gx + 10 + c, _mid - _lo / 128 * _amp + 1);
        }
    }
    var _progress = sfx_preview_progress(_s, _r);
    if (_progress >= 0)
    {
        var _marker_x = _gx + 10 + _progress * max(1, _gw - 21);
        draw_line_width_colour(_marker_x, _gy + 8, _marker_x, _gy + _gh - 8, 2, global.TH.warn, global.TH.warn);
    }
}

function sound_sample_panel(_s, _fx, _y, _colw, _cx1, _x2, _y1, _y2)
{
    if (ui_button("snd_import", _fx, _y, _colw, 38, "Import WAV...", "Import sample|Loads a .WAV file (8, 16, 24 or 32-bit, mono or stereo, any rate). Up to 10 seconds are kept; stereo is mixed to mono.", BTN_ACCENT))
    {
        var _f = get_open_filename("WAV sound|*.wav", "");
        if (_f != "")
        {
            undo_mark("sndimport" + string(current_time));
            if (sfx_import_wav(_s, _f))
            {
                toast("Sample imported", 0);
                sfx_preview_play(_s);
            }
            else { toast("Could not read that WAV file", 2); }
        }
    }
    _y += 46;
    if (_s.smp == "")
    {
        ui_text_wrap(_fx, _y, "No sample yet. Import a WAV file, then choose how crunchy it should sound on the Amiga.", global.TH.text_dim, _colw, global.f_body, 1);
        return;
    }
    ui_text(_fx, _y, ui_text_fit(_s.smp_file + "  -  " + string_format(_s.smp_len / max(1, _s.smp_rate), 1, 2) + " s", global.f_small, _colw), global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
    _y += 24;

    var _rates = [4000, 5513, 8363, 11025, 16574, 22050, 28867];
    var _rnames = ["4000 Hz  (very crunchy)", "5513 Hz", "8363 Hz  (tracker C-2)", "11025 Hz", "16574 Hz", "22050 Hz", "28867 Hz  (Paula maximum)"];
    var _ri = 3;
    for (var r = 0; r < array_length(_rates); r++)
    {
        if (_rates[r] == _s.rate) { _ri = r; }
    }
    var _half = floor((_colw - 12) / 2);
    ui_heading(_fx, _y, "Sample rate");
    var _nri = ui_dropdown("snd_rate", _fx, _y + 18, _colw, 32, _rnames, _ri, "Sample rate|How many samples per second Paula plays. Lower rates take less chip RAM and sound grittier - the classic Amiga crunch.");
    if (_nri != _ri)
    {
        undo_mark("sndrate" + string(current_time));
        _s.rate = _rates[_nri];
        sfx_preview_play(_s);
    }
    _y += 62;
    var _bits = [8, 7, 6, 5, 4, 3, 2];
    var _bnames = ["8-bit  (clean)", "7-bit", "6-bit", "5-bit  (gritty)", "4-bit", "3-bit  (crushed)", "2-bit  (destroyed)"];
    var _bi = 0;
    for (var b = 0; b < array_length(_bits); b++)
    {
        if (_bits[b] == _s.bits) { _bi = b; }
    }
    ui_heading(_fx, _y, "Bit crunch");
    var _nbi = ui_dropdown("snd_bits", _fx, _y + 18, _colw, 32, _bnames, _bi, "Bit crunch|Throws away detail from every sample. 8-bit is Paula's full quality; fewer bits give a lo-fi, crunchy sound.");
    if (_nbi != _bi)
    {
        undo_mark("sndbits" + string(current_time));
        _s.bits = _bits[_nbi];
        sfx_preview_play(_s);
    }
    _y += 62;
    ui_heading(_fx, _y, "Volume  " + string(_s.gain) + "%");
    set_val(_s, "gain", ui_slider("snd_gain", _fx, _y + 18, _colw, _s.gain, 10, 300, "Volume|Makes the sample louder or quieter before it is crunched. Above 100% it clips, which can sound great on drums."), "sndgain");
    _y += 54;
    ui_heading(_fx, _y, "Start");
    set_val(_s, "trim_a", ui_slider("snd_trim_a", _fx, _y + 18, _half, _s.trim_a, 0, 990, "Trim start|Cuts silence or unwanted sound from the beginning."), "sndtrima");
    ui_heading(_fx + _half + 12, _y, "End");
    set_val(_s, "trim_b", ui_slider("snd_trim_b", _fx + _half + 12, _y + 18, _half, _s.trim_b, 10, 1000, "Trim end|Cuts the end off. Shorter samples use less chip RAM."), "sndtrimb");
    if (_s.trim_b <= _s.trim_a + 5) { _s.trim_b = min(1000, _s.trim_a + 10); }
    _y += 58;
    var _playing_loop = (mus_playing && (mus_play_what == "sound" || mus_play_what == "sound_note") && preview_source == _s);
    if (preview_inst != -1 && preview_source == _s && audio_is_playing(preview_inst)) { _playing_loop = true; }
    var _play_label = "Play sound";
    if (_playing_loop) { _play_label = "Stop sound"; }
    if (ui_button("snd_preview", _fx, _y, _colw, 44, _play_label, "Play / stop|Hear the processed sample. When a sample loop is enabled it sustains until you stop it.", BTN_ACCENT))
    {
        if (_playing_loop) { sfx_preview_stop(); }
        else { sfx_preview_play(_s); }
    }

    // right column: the crunched waveform and its cost
    var _r = sfx_render_ex(_s);
    var _gx = _fx + _colw + 30;
    var _gw = _x2 - 20 - _gx;
    var _gy = _y1 + 74;
    ui_heading(_gx, _gy - 18, "As Paula will play it");
    sound_draw_wave(_s, _r, _gx, _gy, _gw, 170, "Waveform|The sample after trimming, resampling and bit crunch. The vertical marker shows its current playback position.");
    var _n = array_length(_r.smp);
    var _info = string(_n) + " bytes of chip RAM  -  " + string_format(_n / max(1, _r.rate), 1, 2) + " seconds at " + string(round(_r.rate)) + " Hz";
    if (_r.capped)
    {
        if (_n >= SMP_OUT_MAX_BYTES - 2) { _info += "  (128 KB limit: lower the rate to keep more)"; }
        else { _info += "  (cut to 10 seconds)"; }
    }
    ui_text(_gx, _gy + 180, ui_text_fit(_info, global.f_small, _gw), global.TH.text_dim, fa_left, fa_top, global.f_small, 1);
    ui_text_wrap(_gx, _gy + 210, "Lower rates and fewer bits are the authentic Amiga sound - and they leave more chip RAM for your backdrop. Sounds play on Paula channel 1 to 4 (sound 1 and 5 share a channel, and so on).", global.TH.text_faint, _gw, global.f_small, 1);
    var _loop_y = _gy + 266;
    var _loop_label = "Sample loop: Off";
    var _loop_style = BTN_NORMAL;
    if (_s.sample_loop) { _loop_label = "Sample loop: On"; _loop_style = BTN_ON; }
    if (ui_button("snd_sample_loop", _gx, _loop_y, min(180, _gw), 30, _loop_label, "Sample loop|Repeats the green waveform region to sustain this sample as a music instrument. In-game sound effects still play once.", _loop_style))
    {
        undo_mark("sndsampleloop" + string(current_time));
        _s.sample_loop = !_s.sample_loop;
        if (_playing_loop) { sfx_preview_stop(); }
    }
    if (_s.sample_loop)
    {
        var _loop_width = (_gw - 12) * 0.5;
        ui_heading(_gx, _loop_y + 40, "Loop start  " + string_format(_s.loop_a / 10, 1, 1) + "%");
        set_val(_s, "loop_a", ui_slider("snd_loop_start", _gx, _loop_y + 56, _loop_width, _s.loop_a, 0, 999, "Loop start|Where repetition begins, within the trimmed sample."), "sndloopstart");
        ui_heading(_gx + _loop_width + 12, _loop_y + 40, "Loop end  " + string_format(_s.loop_b / 10, 1, 1) + "%");
        set_val(_s, "loop_b", ui_slider("snd_loop_end", _gx + _loop_width + 12, _loop_y + 56, _loop_width, _s.loop_b, _s.loop_a + 1, 1000, "Loop end|Where playback returns to the loop start. Only the sample up to this point is stored in the music instrument."), "sndloopend");
        if (_s.loop_b <= _s.loop_a) { _s.loop_b = min(1000, _s.loop_a + 1); }
    }
    if (_playing_loop && !ui_held && preview_render != sfx_render_ex(_s))
    {
        if (mus_play_what == "sound_note" && snd_jam_note >= 0)
        {
            var _note = snd_jam_note;
            var _key = snd_jam_key;
            var _mouse = snd_jam_mouse;
            sfx_preview_note(_s, _note);
            snd_jam_note = _note;
            snd_jam_key = _key;
            snd_jam_mouse = _mouse;
        }
        else { sfx_preview_play(_s); }
    }
    sound_sample_keyboard(_s, _gx, _y2 - 104, _gw, 92);
}
