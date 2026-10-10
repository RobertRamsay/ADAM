/// ADAM - Music workspace (Phase 2 Track B): loop library, 4-lane timeline,
/// step / piano-roll loop editor, songs and the music for each level.
/// Data layout, ProTracker mapping and the preview player are in scr_music.

/// Call after any change to the music (after undo_mark): the preview follows it
function music_touch()
{
    mus_rev += 1;
}

/// The song being edited, or undefined when there are none
function music_cur_song()
{
    var _n = array_length(proj.songs);
    if (_n == 0) { return undefined; }
    mus_song = clamp(mus_song, 0, _n - 1);
    return proj.songs[mus_song];
}

/// Library entries for a category: [0, library index] or [1, song loop index]
function music_lib_items(_cat)
{
    var _out = [];
    if (_cat < MUS_CAT_MINE)
    {
        for (var i = 0; i < array_length(global.MUS_LIB); i++)
        {
            if (global.MUS_LIB[i].cat == _cat) { array_push(_out, [0, i]); }
        }
        return _out;
    }
    var _song = music_cur_song();
    if (is_undefined(_song)) { return _out; }
    if (_song.kind != 0) { return _out; }
    for (var k = 0; k < array_length(_song.arr.loops); k++)
    {
        if (_song.arr.loops[k].lib < 0) { array_push(_out, [1, k]); }
    }
    return _out;
}

function music_item_loop(_it)
{
    if (_it[0] == 0) { return global.MUS_LIB[_it[1]]; }
    return music_cur_song().arr.loops[_it[1]];
}

function music_inst_short(_id)
{
    if (_id >= MUS_INST_USER) { return "Sound " + string(_id - MUS_INST_USER + 1); }
    return music_inst_name(_id);
}

/// Hear one loop on its own (click again to stop)
function music_preview_loop(_lp, _what)
{
    if (mus_playing && mus_play_what == _what)
    {
        music_preview_stop();
        return;
    }
    var _bpm = 125;
    var _swing = 0;
    var _song = music_cur_song();
    if (!is_undefined(_song))
    {
        _bpm = _song.bpm;
        _swing = _song.swing;
    }
    var _ms = song_to_modsong(music_loop_song(_lp, _bpm, _swing));
    music_preview_start(_ms, true, 0, 0, _what);
}

/// Hear one note of an instrument (not while a song is playing)
function music_preview_note(_inst, _note)
{
    if (mus_playing && mus_play_what == "song") { return; }
    var _l = loop_new("Note", 1, _inst);
    _l.notes[0] = clamp(_note, 1, 36);
    var _ms = song_to_modsong(music_loop_song(_l, 125, 0));
    music_preview_start(_ms, true, 0, 0, "note");
}

function music_play_toggle()
{
    if (mus_playing && mus_play_what == "song")
    {
        music_preview_stop();
        return;
    }
    var _song = music_cur_song();
    if (is_undefined(_song)) { return; }
    var _ms = song_to_modsong(_song);
    if (array_length(mus_warnings) > 0) { toast(mus_warnings[0], 1); }
    var _ord = 0;
    var _row = 0;
    if (_song.kind == 0)
    {
        mus_ord_bar = music_order_bars(_song);
        var _cb = clamp(mus_cursor_bar, 0, _song.arr.bars - 1);
        for (var i = 0; i < array_length(mus_ord_bar); i++)
        {
            if (mus_ord_bar[i] <= _cb)
            {
                _ord = i;
                _row = (_cb - mus_ord_bar[i]) * MUS_STEPS;
            }
        }
    }
    music_preview_start(_ms, false, _ord, _row, "song");
    mus_play_song = mus_song;
    mus_play_ref = _song;
    mus_play_rev = mus_rev;
    mus_play_rebuild_t = current_time;
}

function music_song_add()
{
    if (array_length(proj.songs) >= MUS_SONG_MAX)
    {
        toast("A game can have up to " + string(MUS_SONG_MAX) + " songs - delete one first", 1);
        return;
    }
    undo_mark("musnew" + string(current_time));
    array_push(proj.songs, song_new("Song " + string(array_length(proj.songs) + 1)));
    music_song_added();
}

/// After a song was added: select it, and let the first song play in the game
function music_song_added()
{
    var _n = array_length(proj.songs);
    mus_song = _n - 1;
    mus_edit = -1;
    mus_brush = [-1, -1];
    mus_scroll_bar = 0;
    mus_cursor_bar = 0;
    if (_n == 1 && proj.level_song[0] < 0)
    {
        proj.level_song[0] = 0;
        toast("Your first song plays in the game - change that under Where the music plays", 0);
    }
    music_touch();
}

function music_import_mod()
{
    if (array_length(proj.songs) >= MUS_SONG_MAX)
    {
        toast("A game can have up to " + string(MUS_SONG_MAX) + " songs - delete one first", 1);
        return;
    }
    var _f = get_open_filename("ProTracker module|*.mod", "");
    if (_f == "") { return; }
    var _raw = mod_read(_f);
    if (is_undefined(_raw)) { return; }
    var _ms = modsong_sanitize(_raw);
    if (is_undefined(_ms))
    {
        toast("That module has no patterns to play", 2);
        return;
    }
    undo_mark("musimport" + string(current_time));
    var _name = _ms.title;
    if (string_length(string_trim(_name)) == 0) { _name = filename_change_ext(filename_name(_f), ""); }
    var _s = song_new(string_copy(_name, 1, 20));
    _s.kind = 1;
    _s[$ "mod"] = _ms;
    array_push(proj.songs, _s);
    music_song_added();
    toast("Imported " + filename_name(_f), 0);
}

function music_export_mod(_song)
{
    var _f = get_save_filename("ProTracker module|*.mod", _song.name + ".mod");
    if (_f == "") { return; }
    var _ms = song_to_modsong(_song);
    if (is_undefined(_ms)) { return; }
    var _b = mod_write(_ms);
    if (is_undefined(_b)) { return; }
    if (!buffer_exists(_b)) { return; }
    buffer_save(_b, _f);
    buffer_delete(_b);
    toast("Saved " + filename_name(_f), 0);
}

/// First change to a loop: undo point, and a library loop becomes your own
function music_loop_edit_begin(_song, _li, _tag)
{
    undo_mark(_tag);
    music_touch();
    var _lp = _song.arr.loops[_li];
    if (_lp.lib >= 0)
    {
        _lp.lib = -1;
        if (string_copy(_lp.name, 1, 3) != "My ") { _lp.name = string_copy("My " + _lp.name, 1, 24); }
    }
}

function music_open_editor(_li, _lane, _bar)
{
    mus_edit = _li;
    mus_edit_cell = [_lane, _bar];
    var _lp = music_cur_song().arr.loops[_li];
    if (_lp.cat != 0)
    {
        // centre the piano roll on the loop's notes
        var _sum = 0;
        var _cnt = 0;
        for (var s = 0; s < MUS_STEPS; s++)
        {
            if (_lp.notes[s] > 0)
            {
                _sum += _lp.notes[s];
                _cnt += 1;
            }
        }
        var _mid = MUS_ROOT;
        if (_cnt > 0) { _mid = _sum / _cnt; }
        ds_map_replace(ui_scroll, "mus_ed_roll", max(0, round((36 - _mid) * 16 - 60)));
    }
}

/// Paints the brush (or _src) into a bar of the timeline
function music_paint_cell(_song, _src, _lane, _bar, _tag)
{
    var _li = -1;
    if (_src[0] == 0)
    {
        // reuse the song's copy of a library loop when it has one
        var _loops = _song.arr.loops;
        for (var i = 0; i < array_length(_loops); i++)
        {
            if (_loops[i].lib == _src[1]) { _li = i; }
        }
        if (_li >= 0 && _song.arr.lanes[_lane][_bar] == _li) { return; }
        undo_mark(_tag);
        if (_li < 0) { _li = music_song_loop_for_lib(_song, _src[1]); }
    }
    else
    {
        _li = _src[1];
        if (_li < 0 || _li >= array_length(_song.arr.loops)) { return; }
        if (_song.arr.lanes[_lane][_bar] == _li) { return; }
        undo_mark(_tag);
    }
    if (_li < 0)
    {
        toast("This song has " + string(MUS_LOOP_MAX) + " different loops already", 1);
        return;
    }
    _song.arr.lanes[_lane][_bar] = _li;
    if (_bar + 1 > _song.arr.bars) { _song.arr.bars = _bar + 1; }
    music_touch();
}

/// Little picture of a loop's steps
function music_draw_steps(_lp, _x1, _y1, _x2, _y2, _col, _alpha)
{
    var _w = (_x2 - _x1) / MUS_STEPS;
    var _h = _y2 - _y1;
    draw_set_alpha(_alpha);
    for (var s = 0; s < MUS_STEPS; s++)
    {
        if (_lp.notes[s] <= 0) { continue; }
        var _t = 0;
        if (_lp.cat == 0) { _t = clamp(_lp.insts[s], 0, 5) / 5; }
        else { _t = clamp((_lp.notes[s] - 1) / 35, 0, 1); }
        var _py = _y2 - 2 - _t * (_h - 5);
        draw_rectangle_colour(_x1 + s * _w + 1, _py - 2, _x1 + (s + 1) * _w - 1, _py + 1, _col, _col, _col, _col, false);
    }
    draw_set_alpha(1);
}

function ws_music_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 250;
    var _song = music_cur_song();
    if (is_undefined(_song) || _song.kind != 0) { mus_edit = -1; }
    else
    {
        if (mus_edit >= array_length(_song.arr.loops)) { mus_edit = -1; }
    }
    if (mus_brush[0] == 1)
    {
        if (is_undefined(_song)) { mus_brush = [-1, -1]; }
        else
        {
            if (_song.kind != 0 || mus_brush[1] >= array_length(_song.arr.loops)) { mus_brush = [-1, -1]; }
        }
    }

    music_library_panel(_x1, _y1, _x1 + _lw, _y2);

    var _cx1 = _x1 + _lw + 12;
    ui_panel(_cx1, _y1, _x2, _y2, "Music");
    music_toolbar(_cx1, _y1, _x2, _song);
    _song = music_cur_song();

    var _ty = _y1 + 158;
    var _bottom = _ty;
    if (is_undefined(_song))
    {
        ui_inset(_cx1 + 16, _ty, _x2 - 16, _ty + 150, 10);
        ui_text((_cx1 + _x2) / 2, _ty + 40, "No songs yet", global.TH.text, fa_center, fa_middle, global.f_title, 1);
        ui_text((_cx1 + _x2) / 2, _ty + 70, "Make a song, then paint loops from the left onto its 4 lanes.", global.TH.text_dim, fa_center, fa_middle, global.f_body, 1);
        if (ui_button("mus_first", (_cx1 + _x2) / 2 - 90, _ty + 96, 180, 38, "Make a song", "Make a song|Adds your first song. Up to 4 songs per game.", BTN_ACCENT))
        {
            music_song_add();
        }
        _bottom = _ty + 150;
    }
    else
    {
        var _lane_h = 50;
        if (mus_edit >= 0) { _lane_h = 38; }
        _bottom = music_timeline(_cx1 + 16, _ty, _x2 - 16, _song, _lane_h);
    }

    var _py1 = _bottom + 12;
    if (mus_edit >= 0) { music_editor(_cx1 + 16, _py1, _x2 - 16, _y2 - 14, _song); }
    else { music_level_panel(_cx1 + 16, _py1, _x2 - 16, _y2 - 14); }

    // drag and drop from the library or a bar
    if (mus_drag_arm)
    {
        if (ui_held)
        {
            if (!mus_drag && point_distance(ui_mx, ui_my, mus_drag_mx, mus_drag_my) > 6) { mus_drag = true; }
        }
        else
        {
            if (mus_drag && !is_undefined(_song) && mus_hover[0] >= 0 && mus_hover[1] >= 0)
            {
                if (_song.kind == 0) { music_paint_cell(_song, mus_drag_src, mus_hover[0], mus_hover[1], "musdrop" + string(current_time)); }
            }
            mus_drag_arm = false;
            mus_drag = false;
        }
    }
    if (mus_drag)
    {
        var _dl = undefined;
        if (mus_drag_src[0] == 0) { _dl = global.MUS_LIB[mus_drag_src[1]]; }
        else
        {
            if (!is_undefined(_song) && _song.kind == 0 && mus_drag_src[1] < array_length(_song.arr.loops)) { _dl = _song.arr.loops[mus_drag_src[1]]; }
        }
        if (!is_undefined(_dl))
        {
            var _gc = global.MUS_CAT_COLS[clamp(_dl.cat, 0, 5)];
            ui_rrect(ui_mx + 10, ui_my + 6, ui_mx + 120, ui_my + 36, 7, _gc, merge_colour(_gc, c_black, 0.4), 0.85);
            ui_text(ui_mx + 18, ui_my + 21, ui_text_fit(_dl.name, global.f_small, 96), c_white, fa_left, fa_middle, global.f_small, 1);
        }
    }

    if (keyboard_check_pressed(vk_space) && ui_focus == "" && !tut_active && !ui_popup_open && !machine_pick_active && !about_active)
    {
        music_play_toggle();
    }
}

function music_library_panel(_x1, _y1, _x2, _y2)
{
    ui_panel(_x1, _y1, _x2, _y2, "Loops");
    var _helps = [
        "Drums|Beats made from kick, snare, hi-hats, toms and claps.",
        "Bass|Low notes that drive the song along.",
        "Chords|Chip-music chords: the Amiga plays them as fast arpeggios on one channel.",
        "Lead|Melodies and arpeggios that sit on top.",
        "FX|Zaps, risers and swells for builds and drops.",
        "Mine|Loops you have edited in this song. Right-click one that is not used anywhere to delete it."
    ];
    // three tabs a row when the names fit, otherwise two
    draw_set_font(global.f_bold);
    var _catw = 0;
    for (var cw = 0; cw < 6; cw++) { _catw = max(_catw, ui_sw(global.MUS_CAT_NAMES[cw])); }
    var _ncol = 3;
    var _bw = floor((_x2 - _x1 - 32 - 12) / 3);
    if (_bw < _catw + 16)
    {
        _ncol = 2;
        _bw = floor((_x2 - _x1 - 32 - 6) / 2);
    }
    for (var c = 0; c < 6; c++)
    {
        var _bx = _x1 + 16 + (c mod _ncol) * (_bw + 6);
        var _by = _y1 + 52 + (c div _ncol) * 34;
        var _st = BTN_GHOST;
        if (mus_cat == c) { _st = BTN_ACCENT; }
        if (ui_button("mus_cat_" + string(c), _bx, _by, _bw, 28, global.MUS_CAT_NAMES[c], _helps[c], _st)) { mus_cat = c; }
    }
    var _ly1 = _y1 + 58 + ceil(6 / _ncol) * 34;
    var _tip = "Click a loop to hear it. Click or drag on the timeline to paint it in, right-click to rub out, double-click a bar to edit its notes.";
    draw_set_font(global.f_small);
    var _ly2 = _y2 - ceil(ui_sh_ext(_tip, _x2 - _x1 - 32)) - 24;
    var _items = music_lib_items(mus_cat);
    var _ih = 40;
    var _content = array_length(_items) * (_ih + 4) + 4;
    var _off = ui_scroll_begin("mus_lib", _x1 + 8, _ly1, _x2 - 8, _ly2, _content);
    for (var i = 0; i < array_length(_items); i++)
    {
        var _it = _items[i];
        var _lp = music_item_loop(_it);
        var _iy = _ly1 + 4 + i * (_ih + 4) - _off;
        if (_iy + _ih < _ly1 || _iy > _ly2) { continue; }
        var _id = "mus_lib_item_" + string(i);
        var _what = "lib_" + string(_it[0]) + "_" + string(_it[1]);
        var _ix2 = _x2 - 22;
        var _hot = ui_register(_id, _x1 + 12, _iy, _ix2, _iy + _ih, _lp.name + "|Click to hear this loop and make it your brush, then click or drag along the timeline to paint it into bars. You can also drag it straight onto a bar.");
        var _tgt = 0;
        if (_hot) { _tgt = 1; }
        var _a = ui_anim_to(_id, _tgt);
        var _sel = (mus_brush[0] == _it[0] && mus_brush[1] == _it[1]);
        if (_sel) { ui_rrect(_x1 + 12, _iy, _ix2, _iy + _ih, 9, global.TH.accent, global.TH.accent_dark, 0.9); }
        else { ui_rrect(_x1 + 12, _iy, _ix2, _iy + _ih, 9, global.TH.btn_hot_top, global.TH.btn_hot_bot, 0.25 + _a * 0.75); }
        var _col = global.MUS_CAT_COLS[clamp(_lp.cat, 0, 5)];
        ui_rrect(_x1 + 16, _iy + 6, _x1 + 21, _iy + _ih - 6, 2, _col, _col, 1);
        var _nm = _lp.name;
        if (mus_playing && mus_play_what == _what) { _nm = "> " + _nm; }
        ui_text(_x1 + 28, _iy + 13, ui_text_fit(_nm, global.f_bold, _ix2 - _x1 - 120), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        ui_text(_x1 + 28, _iy + 29, ui_text_fit(music_inst_short(_lp.inst), global.f_small, _ix2 - _x1 - 120), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        ui_rrect(_ix2 - 78, _iy + 6, _ix2 - 6, _iy + _ih - 6, 5, c_black, c_black, 0.25);
        music_draw_steps(_lp, _ix2 - 76, _iy + 8, _ix2 - 8, _iy + _ih - 8, _col, 1);
        if (_hot && ui_pressed)
        {
            ui_take_click();
            mus_brush = [_it[0], _it[1]];
            mus_drag_arm = true;
            mus_drag = false;
            mus_drag_src = [_it[0], _it[1]];
            mus_drag_mx = ui_mx;
            mus_drag_my = ui_my;
            music_preview_loop(_lp, _what);
        }
        if (_hot && ui_rpressed && _it[0] == 1)
        {
            var _song = music_cur_song();
            var _uses = music_loop_uses(_song, _it[1]);
            if (_uses > 0) { toast("That loop is used in " + string(_uses) + " bars - rub them out first", 1); }
            else
            {
                undo_mark("musdelloop" + string(current_time));
                music_loop_remove(_song, _it[1]);
                mus_brush = [-1, -1];
                mus_edit = -1;
                music_touch();
                break;
            }
        }
    }
    if (array_length(_items) == 0)
    {
        ui_text_wrap(_x1 + 20, _ly1 + 10, "Loops you change in the editor show up here. Double-click a bar on the timeline to edit its loop.", global.TH.text_faint, _x2 - _x1 - 40, global.f_small, 1);
    }
    ui_scroll_end("mus_lib", _x1 + 8, _ly1, _x2 - 8, _ly2, _content);
    ui_text_wrap(_x1 + 16, _ly2 + 10, _tip, global.TH.text_faint, _x2 - _x1 - 32, global.f_small, 1);
}

function music_toolbar(_cx1, _y1, _x2, _song)
{
    var _fx = _cx1 + 20;
    var _ty = _y1 + 54;
    var _ns = array_length(proj.songs);
    if (_ns > 0)
    {
        var _sel = ui_dropdown("mus_song", _fx, _ty, 170, 32, music_song_names(), mus_song, "Song|Pick the song to work on. A game can have up to 4 songs; choose which one plays on each level under Where the music plays.");
        if (_sel != mus_song)
        {
            mus_song = _sel;
            mus_edit = -1;
            mus_brush = [-1, -1];
            mus_scroll_bar = 0;
            mus_cursor_bar = 0;
        }
    }
    else
    {
        ui_inset(_fx, _ty, _fx + 170, _ty + 32, 9);
        ui_register("mus_song", _fx, _ty, _fx + 170, _ty + 32, "Song|Your songs appear here. Press New to make one.");
        ui_text(_fx + 10, _ty + 16, "No songs", global.TH.text_faint, fa_left, fa_middle, global.f_body, 1);
    }
    var _bx = _fx + 178;
    var _nst = BTN_NORMAL;
    if (_ns >= MUS_SONG_MAX) { _nst = BTN_GHOST; }
    if (ui_button("mus_new", _bx, _ty, 64, 32, "New", "New song|Adds an empty song (up to " + string(MUS_SONG_MAX) + " per game).", _nst)) { music_song_add(); }
    _bx += 72;
    if (!is_undefined(_song))
    {
        var _nm = ui_textfield("mus_name", _bx, _ty, 160, 32, _song.name, 20, "Song name|Shown in the song lists here and on the Levels and Logic pages.");
        if (_nm != _song.name)
        {
            undo_mark("musname");
            _song.name = _nm;
        }
        _bx += 168;
        if (ui_button("mus_del", _bx, _ty, 72, 32, "Delete", "Delete song|Removes this song. Levels that played it go quiet. You can Undo this.", BTN_DANGER))
        {
            if (mus_playing) { music_preview_stop(); }
            undo_mark("musdel" + string(current_time));
            music_song_delete(mus_song);
            mus_song = max(0, mus_song - 1);
            mus_edit = -1;
            mus_brush = [-1, -1];
            music_touch();
            _song = music_cur_song();
        }
        _bx += 80;
    }
    if (ui_button("mus_import", _bx, _ty, 124, 32, "Import .mod...", "Import a module|Loads a 4-channel ProTracker .mod made in ProTracker, OpenMPT or MilkyTracker as a new song. It plays as it is; to change it, edit it there and import it again.", BTN_NORMAL))
    {
        music_import_mod();
        _song = music_cur_song();
    }
    _bx += 132;
    if (!is_undefined(_song))
    {
        if (ui_button("mus_export", _bx, _ty, 108, 32, "Save .mod...", "Save as a module|Writes this song as a standard ProTracker .mod - exactly what goes on the disk - so you can open it in OpenMPT or ProTracker.", BTN_GHOST))
        {
            music_export_mod(_song);
        }
    }
    if (is_undefined(_song)) { return; }

    // ---------- second row: transport, tempo, swing, loop, length ----------
    var _ry = _y1 + 100;
    var _plab = "Play";
    var _pst = BTN_ACCENT;
    if (mus_playing && mus_play_what == "song")
    {
        _plab = "Stop";
        _pst = BTN_ON;
    }
    if (ui_button("mus_play", _fx, _ry + 16, 96, 32, _plab, "Play the song|Plays the whole song as Paula will, from the yellow marker on the bar ruler. Space bar plays and stops too.", _pst))
    {
        music_play_toggle();
    }
    var _x = _fx + 108;
    if (_song.kind != 0)
    {
        var _ms = _song[$ "mod"];
        var _info = "Imported module";
        if (is_struct(_ms)) { _info += "  -  " + string(array_length(_ms.patterns)) + " patterns, " + string(array_length(_ms.order)) + " positions"; }
        ui_text(_x, _ry + 24, _info, global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
        ui_text(_x, _ry + 44, "Tempo, swing and loop come from the file itself.", global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
    }
    else
    {
        ui_heading(_x, _ry, "Tempo (BPM)");
        var _bpm = ui_stepper("mus_bpm", _x, _ry + 16, 124, _song.bpm, 32, 255, "Tempo|Beats per minute. 125 is ProTracker's standard; hold Shift for steps of 10.");
        if (set_val(_song, "bpm", _bpm, "musbpm")) { music_touch(); }
        _x += 136;
        ui_heading(_x, _ry, "Swing  " + string(_song.swing) + "%");
        var _sw = ui_slider("mus_swing", _x, _ry + 18, 130, _song.swing, 0, 50, "Swing|Pushes every second 16th note later for a shuffle feel. The Amiga does this with ProTracker's note-delay effect.");
        if (set_val(_song, "swing", _sw, "musswing")) { music_touch(); }
        _x += 142;
        ui_heading(_x, _ry, "Loop from bar");
        var _lb = ui_stepper("mus_loopbar", _x, _ry + 16, 112, _song.loop_bar + 1, 1, _song.arr.bars, "Loop point|When the song ends it jumps back to this bar and keeps playing. Right-click the bar ruler to set it too.");
        if (set_val(_song, "loop_bar", _lb - 1, "musloopbar")) { music_touch(); }
        _x += 124;
        ui_heading(_x, _ry, "Length (bars)");
        var _len = ui_stepper("mus_length", _x, _ry + 16, 112, _song.arr.bars, 1, MUS_BAR_MAX, "Song length|How many bars the song plays before it loops. Painting past the end makes the song longer.");
        if (set_val(_song.arr, "bars", _len, "muslength"))
        {
            _song.loop_bar = min(_song.loop_bar, _song.arr.bars - 1);
            music_touch();
        }
        _x += 124;
    }

    // chip RAM the song will take (and anything that will not fit)
    if (_song != mus_size_ref || mus_rev != mus_size_rev)
    {
        mus_size_ref = _song;
        mus_size_rev = mus_rev;
        var _m = song_to_modsong(_song);
        mus_size_bytes = music_modsong_bytes(_m);
        mus_size_warn = mus_warnings;
    }
    var _kb = string_format(mus_size_bytes / 1024, 1, 1);
    var _sx = max(_x + 4, _x2 - 190);
    ui_register("mus_size", _sx, _ry + 10, _x2 - 20, _ry + 50, "Chip RAM|The song becomes a ProTracker module of this size, stored in chip RAM with the rest of your game. Instruments that are not used take no room.");
    ui_text(_x2 - 20, _ry + 22, "Song: " + _kb + " KB chip RAM", global.TH.text_dim, fa_right, fa_middle, global.f_small, 1);
    if (array_length(mus_size_warn) > 0)
    {
        ui_register("mus_warn", _sx, _ry + 34, _x2 - 20, _ry + 50, "Music warning|" + mus_size_warn[0]);
        ui_text(_x2 - 20, _ry + 42, ui_text_fit(mus_size_warn[0], global.f_small, _x2 - 20 - _sx), global.TH.warn, fa_right, fa_middle, global.f_small, 1);
    }
}

function music_hscroll(_x1, _y1, _x2, _vis, _total)
{
    var _h = 10;
    ui_rrect(_x1, _y1, _x2, _y1 + _h, 4, c_black, c_black, 0.25);
    var _max = max(0, _total - _vis);
    if (_max <= 0) { return; }
    var _tw = _x2 - _x1;
    var _bw = max(30, _tw * _vis / _total);
    var _bx = _x1 + (_tw - _bw) * (mus_scroll_bar / _max);
    var _hot = ui_register("mus_hscroll", _x1, _y1 - 3, _x2, _y1 + _h + 3, "Scroll the song|Drag to move along the song. The mouse wheel over the timeline scrolls too.");
    if (_hot && ui_pressed)
    {
        mus_hsb_grab = ui_mx - _bx;
        if (mus_hsb_grab < 0 || mus_hsb_grab > _bw) { mus_hsb_grab = _bw * 0.5; }
        ui_drag_id = "mus_hsb";
        ui_take_click();
    }
    if (ui_drag_id == "mus_hsb" && ui_held)
    {
        mus_scroll_bar = clamp(round((ui_mx - mus_hsb_grab - _x1) / max(1, _tw - _bw) * _max), 0, _max);
        _bx = _x1 + (_tw - _bw) * (mus_scroll_bar / _max);
    }
    var _hl = 0;
    if (_hot || ui_drag_id == "mus_hsb") { _hl = 1; }
    var _ha = ui_anim_to("mus_hsb", _hl);
    ui_rrect(_bx, _y1 + 1, _bx + _bw, _y1 + _h - 1, 4, merge_colour(global.TH.text_dim, global.TH.accent, _ha), global.TH.text_faint, 0.8 + 0.2 * _ha);
}

/// The 4-lane timeline. Returns its bottom edge.
function music_timeline(_tx1, _ty1, _tx2, _song, _lane_h)
{
    var _hdr = 92;
    var _rul = 24;
    var _gx1 = _tx1 + _hdr;
    var _gx2 = _tx2 - 8;
    var _gy1 = _ty1 + _rul;
    var _gy2 = _gy1 + MUS_LANES * _lane_h;
    var _bw = 72;
    var _vis = max(1, floor((_gx2 - _gx1) / _bw));
    var _imported = (_song.kind != 0);
    var _ms = undefined;
    var _total = 0;
    if (_imported)
    {
        _ms = _song[$ "mod"];
        if (is_struct(_ms)) { _total = array_length(_ms.order); }
    }
    else { _total = min(MUS_BAR_MAX, max(_song.arr.bars + 8, _vis)); }
    mus_scroll_bar = clamp(mus_scroll_bar, 0, max(0, _total - _vis));

    // follow the playhead
    var _ph = -1;
    if (mus_playing && mus_play_what == "song" && mus_play_song == mus_song)
    {
        var _pos = music_preview_pos();
        if (!is_undefined(_pos))
        {
            if (_imported) { _ph = _pos[0] + _pos[1] / 64; }
            else
            {
                if (_pos[0] < array_length(mus_ord_bar)) { _ph = mus_ord_bar[_pos[0]] + _pos[1] / MUS_STEPS; }
            }
            if (_ph >= 0 && ui_drag_id != "mus_hsb")
            {
                if (_ph < mus_scroll_bar || _ph >= mus_scroll_bar + _vis) { mus_scroll_bar = clamp(floor(_ph), 0, max(0, _total - _vis)); }
            }
        }
    }

    ui_inset(_tx1, _ty1, _tx2, _gy2 + 22, 10);

    // lane names (Paula's channels: 1 and 4 left, 2 and 3 right)
    var _side = ["Left", "Right", "Right", "Left"];
    for (var l = 0; l < MUS_LANES; l++)
    {
        var _ly = _gy1 + l * _lane_h;
        ui_register("mus_lane_" + string(l), _tx1 + 6, _ly + 2, _gx1 - 6, _ly + _lane_h - 2, "Lane " + string(l + 1) + "|One of Paula's 4 sound channels - it plays one note at a time. Channels 1 and 4 come out of the left speaker, 2 and 3 out of the right. Sound effects in the game borrow channel (sound number) the same way.");
        ui_rrect(_tx1 + 6, _ly + 3, _gx1 - 6, _ly + _lane_h - 3, 7, global.TH.btn_top, global.TH.btn_bot, 0.6);
        // name with the speaker side under it, so the two never overlap
        ui_text(_tx1 + 14, _ly + _lane_h * 0.5 - 7, "Lane " + string(l + 1), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        ui_text(_tx1 + 14, _ly + _lane_h * 0.5 + 8, _side[l], global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
    }

    // ruler
    var _rhot = ui_register("mus_ruler", _gx1, _ty1 + 2, _gx2, _gy1, "Bar ruler|Click a bar number to play from there (the yellow marker). Right-click to make the song loop back to that bar. The green flag is the loop point and the line is the end of the song.");
    var _hb_r = -1;
    if (_rhot)
    {
        _hb_r = mus_scroll_bar + floor((ui_mx - _gx1) / _bw);
        if (_hb_r >= _total) { _hb_r = -1; }
    }
    if (_hb_r >= 0 && !_imported)
    {
        if (ui_pressed)
        {
            ui_take_click();
            mus_cursor_bar = min(_hb_r, _song.arr.bars - 1);
        }
        if (ui_rpressed && _hb_r < _song.arr.bars)
        {
            if (set_val(_song, "loop_bar", _hb_r, "musloopbar")) { music_touch(); }
        }
    }
    for (var vb = 0; vb <= _vis; vb++)
    {
        var _b = mus_scroll_bar + vb;
        if (_b >= _total) { break; }
        var _bx = _gx1 + vb * _bw;
        if (_bx >= _gx2) { break; }
        var _lab = string(_b + 1);
        ui_text(_bx + 5, _ty1 + 13, _lab, global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        draw_set_alpha(0.25);
        draw_line_colour(_bx, _ty1 + 4, _bx, _gy2, global.TH.text_faint, global.TH.text_faint);
        draw_set_alpha(1);
    }
    var _view_end = mus_scroll_bar + _vis;
    if (!_imported)
    {
        // loop flag, end of song, play-from marker
        var _lbx = _gx1 + (_song.loop_bar - mus_scroll_bar) * _bw;
        if (_song.loop_bar >= mus_scroll_bar && _song.loop_bar < _view_end)
        {
            draw_set_colour(make_colour_rgb(110, 210, 120));
            draw_triangle(_lbx + 2, _ty1 + 4, _lbx + 2, _ty1 + 20, _lbx + 14, _ty1 + 12, false);
        }
        var _ex = _gx1 + (_song.arr.bars - mus_scroll_bar) * _bw;
        if (_song.arr.bars >= mus_scroll_bar && _song.arr.bars <= _view_end)
        {
            draw_line_width_colour(_ex, _ty1 + 2, _ex, _gy2, 2, global.TH.text_dim, global.TH.text_dim);
        }
        var _cbx = _gx1 + (mus_cursor_bar - mus_scroll_bar) * _bw;
        if (mus_cursor_bar >= mus_scroll_bar && mus_cursor_bar < _view_end)
        {
            draw_set_colour(global.TH.warn);
            draw_triangle(_cbx + _bw - 16, _ty1 + 5, _cbx + _bw - 4, _ty1 + 5, _cbx + _bw - 10, _ty1 + 14, false);
        }
    }

    // grid
    var _ghelp = "Timeline|Each lane is one of Paula's 4 channels and each box is one bar. Click or drag to paint the loop you picked on the left, drag a bar to copy it, right-click to rub out and double-click a bar to edit its notes.";
    if (_imported) { _ghelp = "Imported song|This song came from a .mod file and plays exactly as it was made. To change it, edit it in ProTracker or OpenMPT and import it again."; }
    ui_register("mus_grid", _gx1, _gy1, _gx2, _gy2, _ghelp);
    var _hl = -1;
    var _hb = -1;
    if (ui_hit(_gx1, _gy1, _gx2, _gy2))
    {
        _hl = clamp(floor((ui_my - _gy1) / _lane_h), 0, MUS_LANES - 1);
        _hb = mus_scroll_bar + floor((ui_mx - _gx1) / _bw);
        if (_hb >= MUS_BAR_MAX || _hb >= _total)
        {
            _hl = -1;
            _hb = -1;
        }
    }
    mus_hover = [_hl, _hb];
    if (ui_hit(_tx1, _ty1, _tx2, _gy2) && ui_wheel != 0)
    {
        mus_scroll_bar = clamp(mus_scroll_bar - ui_wheel * 2, 0, max(0, _total - _vis));
        ui_wheel = 0;
    }

    ui_scissor(_gx1, _gy1, _gx2 - _gx1, _gy2 - _gy1);
    for (var vb2 = 0; vb2 <= _vis; vb2++)
    {
        var _b2 = mus_scroll_bar + vb2;
        if (_b2 >= _total) { break; }
        var _cx = _gx1 + vb2 * _bw;
        if (_imported)
        {
            if (!is_struct(_ms)) { break; }
            ui_rrect(_cx + 2, _gy1 + 3, _cx + _bw - 2, _gy2 - 3, 8, global.TH.btn_top, global.TH.btn_bot, 0.9);
            ui_rrect_line(_cx + 2, _gy1 + 3, _cx + _bw - 2, _gy2 - 3, 8, global.TH.panel_edge, 0.8, 1);
            ui_text(_cx + _bw * 0.5, _gy1 + 18, "Pos " + string(_b2), global.TH.text_dim, fa_center, fa_middle, global.f_small, 1);
            ui_text(_cx + _bw * 0.5, (_gy1 + _gy2) * 0.5, "Pat " + string(_ms.order[_b2]), global.TH.text, fa_center, fa_middle, global.f_bold, 1);
            continue;
        }
        var _past = (_b2 >= _song.arr.bars);
        for (var l2 = 0; l2 < MUS_LANES; l2++)
        {
            var _cy = _gy1 + l2 * _lane_h;
            var _li = _song.arr.lanes[l2][_b2];
            if (_li >= 0 && _li < array_length(_song.arr.loops))
            {
                var _lp = _song.arr.loops[_li];
                var _col = global.MUS_CAT_COLS[clamp(_lp.cat, 0, 5)];
                var _alpha = 0.92;
                if (_past) { _alpha = 0.35; }
                ui_rrect(_cx + 2, _cy + 3, _cx + _bw - 2, _cy + _lane_h - 3, 7, merge_colour(_col, c_white, 0.08), merge_colour(_col, c_black, 0.35), _alpha);
                if (mus_edit == _li) { ui_rrect_line(_cx + 2, _cy + 3, _cx + _bw - 2, _cy + _lane_h - 3, 7, c_white, 0.9, 2); }
                ui_text(_cx + 8, _cy + 12, ui_text_fit(_lp.name, global.f_small, _bw - 14), c_white, fa_left, fa_middle, global.f_small, _alpha);
                music_draw_steps(_lp, _cx + 6, _cy + 18, _cx + _bw - 6, _cy + _lane_h - 6, c_white, 0.7 * _alpha);
            }
            else
            {
                var _ea = 0.12;
                if (_past) { _ea = 0.04; }
                ui_rrect(_cx + 2, _cy + 3, _cx + _bw - 2, _cy + _lane_h - 3, 7, c_white, c_white, _ea);
            }
            if (l2 == _hl && _b2 == _hb)
            {
                ui_rrect_line(_cx + 2, _cy + 3, _cx + _bw - 2, _cy + _lane_h - 3, 7, global.TH.accent, 0.9, 2);
            }
        }
    }
    if (_ph >= mus_scroll_bar && _ph < _view_end)
    {
        var _phx = _gx1 + (_ph - mus_scroll_bar) * _bw;
        draw_line_width_colour(_phx, _gy1, _phx, _gy2, 2, global.TH.warn, global.TH.warn);
    }
    ui_scissor_reset();
    if (_ph >= mus_scroll_bar && _ph < _view_end)
    {
        var _phx2 = _gx1 + (_ph - mus_scroll_bar) * _bw;
        draw_set_colour(global.TH.warn);
        draw_triangle(_phx2 - 6, _ty1 + 16, _phx2 + 6, _ty1 + 16, _phx2, _gy1, false);
    }

    // painting, rubbing out, double-click to edit, drag to copy
    if (!_imported && _hl >= 0)
    {
        var _cur = _song.arr.lanes[_hl][_hb];
        if (ui_pressed)
        {
            ui_take_click();
            if (_cur >= 0)
            {
                if (current_time - mus_click_time < 400 && mus_click_cell[0] == _hl && mus_click_cell[1] == _hb)
                {
                    music_open_editor(_cur, _hl, _hb);
                    mus_click_time = 0;
                }
                else
                {
                    mus_click_time = current_time;
                    mus_click_cell = [_hl, _hb];
                    mus_brush = [1, _cur];
                    mus_drag_arm = true;
                    mus_drag = false;
                    mus_drag_src = [1, _cur];
                    mus_drag_mx = ui_mx;
                    mus_drag_my = ui_my;
                }
            }
            else
            {
                if (mus_brush[0] >= 0)
                {
                    mus_painting = true;
                    mus_paint_tag = "muspaint" + string(current_time);
                    music_paint_cell(_song, mus_brush, _hl, _hb, mus_paint_tag);
                }
                else { toast("Pick a loop on the left first, then paint it here", 1); }
            }
        }
        else
        {
            if (mus_painting && ui_held && _cur < 0 && mus_brush[0] >= 0)
            {
                music_paint_cell(_song, mus_brush, _hl, _hb, mus_paint_tag);
            }
        }
        if (ui_rpressed)
        {
            mus_erasing = true;
            mus_paint_tag = "museras" + string(current_time);
        }
        if (mus_erasing && ui_rheld && _song.arr.lanes[_hl][_hb] >= 0)
        {
            undo_mark(mus_paint_tag);
            _song.arr.lanes[_hl][_hb] = -1;
            music_touch();
        }
    }
    if (!ui_held) { mus_painting = false; }
    if (!ui_rheld) { mus_erasing = false; }

    music_hscroll(_gx1, _gy2 + 6, _gx2, _vis, _total);
    return _gy2 + 22;
}

/// Step grid (drums) or piano roll (everything else) for the open loop
function music_editor(_ex1, _ey1, _ex2, _ey2, _song)
{
    var _li = mus_edit;
    var _lp = _song.arr.loops[_li];
    var _drums = (_lp.cat == 0);
    var _col = global.MUS_CAT_COLS[clamp(_lp.cat, 0, 5)];
    ui_inset(_ex1, _ey1, _ex2, _ey2, 10);

    // ---------- header ----------
    var _hx = _ex1 + 12;
    var _hy = _ey1 + 10;
    draw_circle_colour(_hx + 6, _hy + 15, 6, _col, _col, false);
    _hx += 20;
    var _nm = ui_textfield("mus_ed_name", _hx, _hy, 170, 30, _lp.name, 24, "Loop name|Name this loop. Edited loops are listed under Mine in the library.");
    if (_nm != _lp.name)
    {
        music_loop_edit_begin(_song, _li, "musedname");
        _lp.name = _nm;
    }
    _hx += 178;
    if (!_drums)
    {
        var _ids = music_inst_ids();
        var _names = [];
        var _cur = 0;
        for (var i = 0; i < array_length(_ids); i++)
        {
            array_push(_names, music_inst_name(_ids[i]));
            if (_ids[i] == _lp.inst) { _cur = i; }
        }
        var _ni = ui_dropdown("mus_ed_inst", _hx, _hy, 190, 30, _names, _cur, "Instrument|The sound this loop plays: a built-in chip-synth instrument, or one of your 8 sounds from the Sound page (synth or sample).");
        if (_ni != _cur)
        {
            music_loop_edit_begin(_song, _li, "museinst" + string(current_time));
            _lp.inst = _ids[_ni];
            for (var s = 0; s < MUS_STEPS; s++) { _lp.insts[s] = _lp.inst; }
            music_preview_note(_lp.inst, music_inst_root(_lp.inst));
        }
        _hx += 198;
    }
    var _lst = BTN_ACCENT;
    if (mus_playing && mus_play_what == "edit") { _lst = BTN_ON; }
    if (ui_button("mus_ed_listen", _hx, _hy, 80, 30, "Listen", "Listen|Plays this loop once at the song's tempo and swing.", _lst))
    {
        music_preview_loop(_lp, "edit");
    }
    _hx += 88;
    var _uses = music_loop_uses(_song, _li);
    if (_uses > 1)
    {
        draw_set_font(global.f_bold);
        var _cpw = ceil(ui_sw("Copy for this bar")) + 28;
        if (ui_button("mus_ed_copy", _hx, _hy, _cpw, 30, "Copy for this bar", "Make a copy|This loop is used in " + string(_uses) + " bars and edits change all of them. Press this to give the bar you double-clicked its own copy to change.", BTN_NORMAL))
        {
            var _cl = mus_edit_cell[0];
            var _cb = mus_edit_cell[1];
            if (array_length(_song.arr.loops) >= MUS_LOOP_MAX) { toast("This song has too many different loops", 1); }
            else
            {
                if (_song.arr.lanes[_cl][_cb] != _li) { toast("Double-click the bar again first", 1); }
                else
                {
                    undo_mark("museditcopy" + string(current_time));
                    var _c = loop_copy(_lp);
                    _c.lib = -1;
                    if (string_copy(_c.name, 1, 3) != "My ") { _c.name = string_copy("My " + _c.name, 1, 24); }
                    array_push(_song.arr.loops, _c);
                    mus_edit = array_length(_song.arr.loops) - 1;
                    _song.arr.lanes[_cl][_cb] = mus_edit;
                    music_touch();
                    return;
                }
            }
        }
        _hx += _cpw + 8;
    }
    if (ui_button("mus_ed_clear", _hx, _hy, 70, 30, "Clear", "Clear|Removes every note from this loop.", BTN_GHOST))
    {
        music_loop_edit_begin(_song, _li, "museditclear" + string(current_time));
        for (var s2 = 0; s2 < MUS_STEPS; s2++)
        {
            _lp.notes[s2] = 0;
            _lp.arps[s2] = 0;
        }
    }
    if (ui_button("mus_ed_close", _ex2 - 92, _hy, 80, 30, "Close", "Close the editor|Back to the level music settings. Double-click any bar to edit again.", BTN_GHOST))
    {
        mus_edit = -1;
        return;
    }
    var _tip = "Used in " + string(_uses) + " bar";
    if (_uses != 1) { _tip += "s"; }
    if (_drums) { _tip += "  -  one hit per step: click to add or remove, drag to paint, right-click to rub out."; }
    else { _tip += "  -  one note per step: click to place, click again to remove, right-click to rub out. Chords play as ProTracker arpeggios."; }
    ui_text(_ex1 + 14, _hy + 44, ui_text_fit(_tip, global.f_small, _ex2 - _ex1 - 28), global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);

    // ---------- grid ----------
    var _gx1 = _ex1 + 10;
    var _gx2 = _ex2 - 10;
    var _gy1 = _ey1 + 62;
    var _gy2 = _ey2 - 8;
    if (!_drums) { _gy2 -= 36; }
    if (_gy2 - _gy1 < 30) { return; }
    var _lab = 92;
    var _cw = max(14, min(48, floor((_gx2 - _gx1 - _lab - 16) / MUS_STEPS)));
    var _rows = [];
    var _rh = 16;
    if (_drums)
    {
        _rows = global.MUS_DRUM_ROWS;
        _rh = 22;
    }
    else
    {
        for (var n = 36; n >= 1; n--) { array_push(_rows, n); }
    }
    var _nr = array_length(_rows);
    var _sid = "mus_ed_roll";
    if (_drums) { _sid = "mus_ed_drums"; }
    var _content = _nr * _rh;
    var _off = ui_scroll_begin(_sid, _gx1, _gy1, _gx2, _gy2, _content);
    var _sx = _gx1 + _lab;
    var _sx2 = _sx + _cw * MUS_STEPS;
    ui_register("mus_ed_grid", _sx, _gy1, _sx2, _gy2, "Notes|Each column is a 16th-note step of the bar. Click a square to put a note there, click it again to take it away. Drag to paint, right-click to rub out.");
    var _hr = -1;
    var _hs = -1;
    if (ui_hit(_sx, _gy1, _sx2, _gy2))
    {
        _hr = floor((ui_my - _gy1 + _off) / _rh);
        _hs = floor((ui_mx - _sx) / _cw);
        if (_hr < 0 || _hr >= _nr || _hs < 0 || _hs >= MUS_STEPS)
        {
            _hr = -1;
            _hs = -1;
        }
    }
    var _play_step = -1;
    if (mus_playing && mus_play_what != "note")
    {
        var _pos = music_preview_pos();
        if (!is_undefined(_pos)) { _play_step = _pos[1] mod MUS_STEPS; }
    }
    for (var r = 0; r < _nr; r++)
    {
        var _ry = _gy1 + r * _rh - _off;
        if (_ry + _rh < _gy1 || _ry > _gy2) { continue; }
        var _rv = _rows[r];
        var _lname = "";
        var _black = false;
        if (_drums) { _lname = music_inst_short(_rv); }
        else
        {
            _lname = music_note_name(_rv);
            var _semi = (_rv - 1) mod 12;
            _black = (_semi == 1 || _semi == 3 || _semi == 6 || _semi == 8 || _semi == 10);
        }
        var _lc = global.TH.text_dim;
        if (!_drums && (_rv - 1) mod 12 == 0) { _lc = global.TH.text; }
        if (_black) { _lc = global.TH.text_faint; }
        ui_text(_gx1 + 6, _ry + _rh * 0.5, ui_text_fit(_lname, global.f_small, _lab - 12), _lc, fa_left, fa_middle, global.f_small, 1);
        for (var st = 0; st < MUS_STEPS; st++)
        {
            var _cx = _sx + st * _cw;
            var _on = false;
            if (_drums) { _on = (_lp.notes[st] > 0 && _lp.insts[st] == _rv); }
            else { _on = (_lp.notes[st] == _rv); }
            var _ba = 0.10;
            if ((st div 4) mod 2 == 1) { _ba = 0.05; }
            if (_black) { _ba *= 0.5; }
            if (st == _play_step) { _ba += 0.12; }
            draw_set_alpha(_ba);
            draw_rectangle_colour(_cx + 1, _ry + 1, _cx + _cw - 1, _ry + _rh - 1, c_white, c_white, c_white, c_white, false);
            draw_set_alpha(1);
            if (_on)
            {
                ui_rrect(_cx + 2, _ry + 2, _cx + _cw - 2, _ry + _rh - 2, 4, merge_colour(_col, c_white, 0.15), _col, 1);
            }
            if (r == _hr && st == _hs)
            {
                ui_rrect_line(_cx + 1, _ry + 1, _cx + _cw - 1, _ry + _rh - 1, 4, global.TH.accent, 0.9, 1);
            }
        }
    }
    ui_scroll_end(_sid, _gx1, _gy1, _gx2, _gy2, _content);

    if (_hr >= 0)
    {
        var _rv2 = _rows[_hr];
        var _on2 = false;
        if (_drums) { _on2 = (_lp.notes[_hs] > 0 && _lp.insts[_hs] == _rv2); }
        else { _on2 = (_lp.notes[_hs] == _rv2); }
        if (ui_pressed)
        {
            ui_take_click();
            mus_ed_mode = 1;
            if (_on2) { mus_ed_mode = 0; }
            mus_ed_painting = true;
            mus_ed_tag = "musstep" + string(current_time);
            music_ed_apply(_song, _li, _hs, _rv2, _drums, mus_ed_mode);
            if (mus_ed_mode == 1)
            {
                if (_drums) { music_preview_note(_rv2, music_inst_root(_rv2)); }
                else { music_preview_note(_lp.inst, _rv2); }
            }
        }
        else
        {
            if (mus_ed_painting && ui_held) { music_ed_apply(_song, _li, _hs, _rv2, _drums, mus_ed_mode); }
        }
        if (ui_rpressed)
        {
            mus_ed_rclear = true;
            mus_ed_tag = "musstepclr" + string(current_time);
        }
        if (mus_ed_rclear && ui_rheld && _lp.notes[_hs] > 0)
        {
            music_loop_edit_begin(_song, _li, mus_ed_tag);
            _lp.notes[_hs] = 0;
            _lp.arps[_hs] = 0;
        }
    }
    if (!ui_held) { mus_ed_painting = false; }
    if (!ui_rheld) { mus_ed_rclear = false; }

    // ---------- chord row ----------
    if (!_drums)
    {
        var _cy = _gy2 + 6;
        ui_text(_gx1 + 6, _cy + 13, "Chord", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        var _codes = global.MUS_CHORD_CODES;
        for (var st2 = 0; st2 < MUS_STEPS; st2++)
        {
            var _code = _lp.arps[st2];
            var _idx = -1;
            for (var k = 0; k < array_length(_codes); k++)
            {
                if (_codes[k] == _code) { _idx = k; }
            }
            var _clab = "?";
            if (_idx >= 0) { _clab = global.MUS_CHORD_NAMES[_idx]; }
            var _cst = BTN_GHOST;
            if (_code != 0) { _cst = BTN_ON; }
            var _bx = _sx + st2 * _cw + 1;
            if (ui_button("mus_chord_" + string(st2), _bx, _cy, _cw - 2, 26, _clab, "Chord|Click to turn this step's note into a chord: minor, major, 7th, sus or octave. The Amiga plays it as a fast ProTracker arpeggio on this one channel, and it keeps going on the empty steps after it. Right-click for no chord.", _cst))
            {
                music_loop_edit_begin(_song, _li, "muschord" + string(current_time));
                _lp.arps[st2] = _codes[(_idx + 1) mod array_length(_codes)];
            }
            if (ui_rpressed && _code != 0 && ui_hit(_bx, _cy, _bx + _cw - 2, _cy + 26))
            {
                music_loop_edit_begin(_song, _li, "muschord" + string(current_time));
                _lp.arps[st2] = 0;
            }
        }
    }
}

/// Puts (mode 1) or removes (mode 0) a note at a step of the open loop
function music_ed_apply(_song, _li, _st, _rv, _drums, _mode)
{
    var _lp = _song.arr.loops[_li];
    if (_mode == 1)
    {
        var _note = _rv;
        var _inst = _lp.inst;
        if (_drums)
        {
            _inst = _rv;
            _note = music_inst_root(_rv);
        }
        if (_lp.notes[_st] == _note && _lp.insts[_st] == _inst) { return; }
        music_loop_edit_begin(_song, _li, mus_ed_tag);
        _lp.notes[_st] = _note;
        _lp.insts[_st] = _inst;
    }
    else
    {
        var _match = false;
        if (_drums) { _match = (_lp.notes[_st] > 0 && _lp.insts[_st] == _rv); }
        else { _match = (_lp.notes[_st] == _rv); }
        if (!_match) { return; }
        music_loop_edit_begin(_song, _li, mus_ed_tag);
        _lp.notes[_st] = 0;
        _lp.arps[_st] = 0;
    }
}

/// Which song plays on each level (or in a single-screen game)
function music_level_panel(_px1, _py1, _px2, _py2)
{
    if (_py2 - _py1 < 60) { return; }
    ui_inset(_px1, _py1, _px2, _py2, 10);
    var _fx = _px1 + 16;
    var _y = _py1 + 14;
    ui_heading(_fx, _y, "Where the music plays");
    _y += 22;
    var _opts = music_song_options();
    var _nl = array_length(proj.levels);
    if (proj.levels_on && _nl > 0)
    {
        var _colw = 250;
        var _cols = max(1, floor((_px2 - _px1 - 32) / _colw));
        for (var i = 0; i < min(_nl, array_length(proj.level_song)); i++)
        {
            var _cx = _fx + (i mod _cols) * _colw;
            var _cy = _y + (i div _cols) * 40;
            if (_cy + 32 > _py2 - 6) { break; }
            ui_text(_cx, _cy + 15, "Level " + string(i + 1), global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
            var _cur = clamp(proj.level_song[i] + 1, 0, array_length(_opts) - 1);
            var _nv = ui_dropdown("mus_lvl_" + string(i), _cx + 66, _cy, _colw - 80, 30, _opts, _cur, "Level " + string(i + 1) + " music|The song that starts when this level begins. Logic rules can also start and stop music.");
            if (_nv != _cur)
            {
                undo_mark("muslvl" + string(i));
                proj.level_song[i] = _nv - 1;
            }
        }
        _y += ceil(min(_nl, 10) / _cols) * 40 + 6;
    }
    else
    {
        ui_text(_fx, _y + 15, "Game music", global.TH.text_dim, fa_left, fa_middle, global.f_body, 1);
        var _cur2 = clamp(proj.level_song[0] + 1, 0, array_length(_opts) - 1);
        var _nv2 = ui_dropdown("mus_lvl_0", _fx + 96, _y, 240, 30, _opts, _cur2, "Game music|The song that plays while your game runs. Switch on Levels on the Levels page to choose a song for each level.");
        if (_nv2 != _cur2)
        {
            undo_mark("muslvl0");
            proj.level_song[0] = _nv2 - 1;
        }
        _y += 46;
    }
    if (_y + 40 < _py2)
    {
        ui_text_wrap(_fx, _y, "Songs are stored as ProTracker modules and share Paula's 4 channels with your sound effects. Double-click a bar on the timeline to edit its notes; Save .mod lets you open the song in OpenMPT or ProTracker.", global.TH.text_faint, _px2 - _px1 - 32, global.f_small, 1);
    }
}
