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
    var _preview = music_loop_song(_lp, _bpm, _swing);
    if (_what == "edit" && !is_undefined(_song) && _song.kind == 0 && mus_edit_cell[0] >= 0)
    {
        _preview.arr.volumes[0] = _song.arr.volumes[mus_edit_cell[0]];
    }
    var _ms = song_to_modsong(_preview);
    music_preview_start(_ms, true, 0, 0, _what);
}

/// Hear one note of an instrument (not while a song is playing)
function music_preview_note(_inst, _note, _fx = 0, _param = 0)
{
    if (mus_playing && mus_play_what == "song") { return; }
    var _l = loop_new("Note", 1, _inst);
    _l.notes[0] = clamp(_note, 1, 36);
    if (_fx > 0)
    {
        _l.fx[0] = clamp(_fx, 0, 4);
        if (_fx == 12) { _l.fx[0] = 12; }
        _l.fxp[0] = clamp(_param, 0, 255);
    }
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
    mus_play_bar = 0;
    if (_song.kind == 0) { mus_play_bar = clamp(mus_cursor_bar, 0, _song.arr.bars - 1); }
    var _preview = music_scope_song(_song, mus_play_mode, mus_play_bar);
    var _ms = song_to_modsong(_preview);
    if (array_length(mus_warnings) > 0) { toast(mus_warnings[0], 1); }
    var _ord = 0;
    var _row = 0;
    if (_song.kind == 0)
    {
        mus_ord_bar = music_order_bars(_preview);
        var _cb = clamp(mus_cursor_bar, 0, _song.arr.bars - 1);
        if (mus_play_mode == 2)
        {
            for (var i = 0; i < array_length(mus_ord_bar); i++)
            {
                if (mus_ord_bar[i] <= _cb)
                {
                    _ord = i;
                    _row = (_cb - mus_ord_bar[i]) * MUS_STEPS;
                }
            }
        }
        else
        {
            for (var i = 0; i < array_length(mus_ord_bar); i++) { mus_ord_bar[i] += mus_play_bar; }
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

function music_loop_add()
{
    var _song = music_cur_song();
    if (is_undefined(_song) || _song.kind != 0)
    {
        music_song_add();
        _song = music_cur_song();
        if (is_undefined(_song) || _song.kind != 0) { return; }
    }
    var _li = array_length(_song.arr.loops);
    if (_li >= MUS_LOOP_MAX)
    {
        toast("This song has " + string(MUS_LOOP_MAX) + " different loops already", 1);
        return;
    }
    var _cat = mus_cat;
    if (_cat >= MUS_CAT_MINE) { _cat = 3; }
    var _defaults = [0, 6, 8, 10, 13];
    undo_mark("musnewloop" + string(current_time));
    array_push(_song.arr.loops, loop_new("Loop " + string(_li + 1), _cat, _defaults[_cat]));
    if (mus_group_selected >= 0 && mus_group_selected < array_length(_song.arr.loop_groups))
    {
        _song.arr.loops[_li].group = mus_group_selected;
        _song.arr.loop_groups[mus_group_selected].open = true;
    }
    else { mus_ungrouped_open = true; }
    mus_cat = MUS_CAT_MINE;
    mus_brush = [1, _li];
    mus_drag_arm = false;
    mus_drag = false;
    music_touch();
    music_open_editor(_li, 0, clamp(mus_cursor_bar, 0, _song.arr.bars - 1));
    var _rows = music_loop_group_rows(_song, true);
    var _offset = 4;
    for (var _row = 0; _row < array_length(_rows); _row++)
    {
        if (_rows[_row].kind == 0 && _rows[_row].it[1] == _li)
        {
            ds_map_replace(ui_scroll, "mus_lib", max(0, _offset - 4));
            break;
        }
        _offset += _rows[_row].h;
    }
}

function music_group_add()
{
    var _song = music_cur_song();
    if (is_undefined(_song) || _song.kind != 0)
    {
        music_song_add();
        _song = music_cur_song();
        if (is_undefined(_song) || _song.kind != 0) { return; }
    }
    var _gi = array_length(_song.arr.loop_groups);
    if (_gi >= MUS_LOOP_MAX) { toast("This song has too many loop groups", 1); return; }
    undo_mark("musnewgroup" + string(current_time));
    var _name = "Group " + string(_gi + 1);
    array_push(_song.arr.loop_groups, { name : _name, open : true });
    mus_cat = MUS_CAT_MINE;
    mus_group_selected = _gi;
    ds_map_replace(ui_scroll, "mus_lib", 100000);
    ui_focus = "mus_group_name_" + string(_gi);
    keyboard_string = _name;
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
    mus_group_selected = -1;
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

function music_loop_clear_now(_arg)
{
    if (_arg.song < 0 || _arg.song >= array_length(proj.songs)) { return; }
    var _song = proj.songs[_arg.song];
    if (_song.kind != 0 || _arg.loop < 0 || _arg.loop >= array_length(_song.arr.loops)) { return; }
    music_loop_edit_begin(_song, _arg.loop, "museditclear" + string(current_time));
    var _lp = _song.arr.loops[_arg.loop];
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        _lp.notes[_step] = 0;
        _lp.lengths[_step] = 0;
        _lp.arps[_step] = 0;
        _lp.fx[_step] = 0;
        _lp.fxp[_step] = 0;
        _lp.fx_end[_step] = -1;
        _lp.glide_to[_step] = -1;
    }
    mus_ed_note_drag = false;
    mus_ed_resize_step = -1;
    mus_ed_note_glide = false;
    mus_ed_fx_drag = false;
    mus_ed_painting = false;
    mus_ed_selected = array_create(MUS_STEPS, false);
    mus_ed_select_drag = false;
    if (mus_playing && mus_play_what == "edit") { music_preview_stop(); }
}

function music_open_editor(_li, _lane, _bar)
{
    mus_edit = _li;
    mus_edit_cell = [_lane, _bar];
    mus_ed_fx_drag = false;
    if (_bar >= 0) { mus_cursor_bar = _bar; }
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
/// Timeline cells [lane, bar] on a line from (_l0, _b0) to (_l1, _b1), both ends included
function music_stroke_cells(_l0, _b0, _l1, _b1)
{
    var _out = [];
    var _dx = abs(_b1 - _b0);
    var _dy = -abs(_l1 - _l0);
    var _sx = 1;
    if (_b0 > _b1) { _sx = -1; }
    var _sy = 1;
    if (_l0 > _l1) { _sy = -1; }
    var _err = _dx + _dy;
    var _cb = _b0;
    var _cl = _l0;
    while (true)
    {
        array_push(_out, [_cl, _cb]);
        if (_cb == _b1 && _cl == _l1) { break; }
        var _e2 = 2 * _err;
        if (_e2 >= _dy)
        {
            _err += _dy;
            _cb += _sx;
        }
        if (_e2 <= _dx)
        {
            _err += _dx;
            _cl += _sy;
        }
    }
    return _out;
}

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
    _song = music_cur_song();

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
            else if (mus_drag && mus_group_hover >= -1 && !is_undefined(_song) && _song.kind == 0)
            {
                if (mus_drag_src[0] == 0 && array_length(_song.arr.loops) >= MUS_LOOP_MAX)
                {
                    toast("This song has too many different loops", 1);
                }
                else
                {
                    undo_mark("musgroupdrop" + string(current_time));
                    var _li = music_loop_group_assign(_song, mus_drag_src, mus_group_hover);
                    if (_li >= 0) { mus_brush = [1, _li]; mus_group_selected = mus_group_hover; music_touch(); }
                }
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

    if (keyboard_check_pressed(vk_space) && ui_focus == "" && !tut_active && !ui_popup_open && !machine_pick_active && !about_active && !confirm_active)
    {
        if (mus_edit >= 0 && !is_undefined(_song) && _song.kind == 0 && mus_edit < array_length(_song.arr.loops))
        {
            music_preview_loop(_song.arr.loops[mus_edit], "edit");
        }
        else { music_play_toggle(); }
    }
}

function music_library_panel(_x1, _y1, _x2, _y2)
{
    mus_group_hover = -2;
    ui_panel(_x1, _y1, _x2, _y2, "Loops");
    var _helps = [
        "Drums|Beats made from kick, snare, hi-hats, toms and claps.",
        "Bass|Low notes that drive the song along.",
        "Chords|Chip-music chords: the Amiga plays them as fast arpeggios on one channel.",
        "Lead|Melodies and arpeggios that sit on top.",
        "FX|Zaps, risers and swells for builds and drops.",
        "Mine|Your loops and named groups. Drag loops onto a group to organise them; hover Mine during a drag to bring groups into view. Click a group name to rename it, or its arrow to open and close it."
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
        if (mus_drag && c == MUS_CAT_MINE && ui_hit(_bx, _by, _bx + _bw, _by + 28)) { mus_cat = c; }
    }
    var _ly1 = _y1 + 58 + ceil(6 / _ncol) * 34;
    if (ui_button("mus_new_loop", _x1 + 16, _ly1, _x2 - _x1 - 32, 30, "+ New loop", "New loop|Opens a blank loop in the note editor and selects it for painting onto the timeline. Uses the selected category, or Lead from Mine. Creates an editable song first if needed.", BTN_ACCENT))
    {
        music_loop_add();
    }
    _ly1 += 40;
    if (mus_cat == MUS_CAT_MINE)
    {
        if (ui_button("mus_new_group", _x1 + 16, _ly1, _x2 - _x1 - 32, 28, "+ New group", "New group|Adds a named group to Mine. Click its name to rename it, and drag loops onto it. Groups are saved in this song.", BTN_NORMAL)) { music_group_add(); }
        _ly1 += 36;
    }
    var _tip = "Click a loop to hear it. Click or drag on the timeline to paint it in, right-click to rub out, double-click a bar to edit its notes.";
    draw_set_font(global.f_small);
    var _ly2 = _y2 - 72;
    if (mus_edit >= 0) { _ly2 = _y2 - 108; }
    var _items = music_lib_items(mus_cat);
    var _song = music_cur_song();
    var _rows = [];
    if (mus_cat == MUS_CAT_MINE && !is_undefined(_song) && _song.kind == 0)
    {
        if (mus_group_selected >= array_length(_song.arr.loop_groups)) { mus_group_selected = -1; }
        _rows = music_loop_group_rows(_song, mus_ungrouped_open);
    }
    else
    {
        for (var _item = 0; _item < array_length(_items); _item++)
        {
            array_push(_rows, { kind : 0, group : -1, count : 0, h : 44, it : _items[_item] });
        }
    }
    var _ih = 40;
    var _offsets = [];
    var _content = 4;
    for (var _ri = 0; _ri < array_length(_rows); _ri++) { array_push(_offsets, _content); _content += _rows[_ri].h; }
    var _off = ui_scroll_begin("mus_lib", _x1 + 8, _ly1, _x2 - 8, _ly2, _content);
    if (mus_drag && ui_hit(_x1 + 8, _ly1, _x2 - 22, _ly2))
    {
        if (ui_my < _ly1 + 22) { _off -= 6; }
        if (ui_my > _ly2 - 22) { _off += 6; }
        _off = clamp(_off, 0, max(0, _content - (_ly2 - _ly1)));
        ds_map_replace(ui_scroll, "mus_lib", _off);
    }
    for (var i = 0; i < array_length(_rows); i++)
    {
        var _row = _rows[i];
        var _iy = _ly1 + _offsets[i] - _off;
        if (_iy + _row.h < _ly1 || _iy > _ly2) { continue; }
        var _ix2 = _x2 - 22;
        if (mus_cat == MUS_CAT_MINE && ui_hit(_x1 + 12, _iy, _ix2, _iy + _row.h - 4))
        {
            if (mus_drag) { mus_group_hover = _row.group; }
            if (ui_pressed_raw) { mus_group_selected = _row.group; }
        }
        if (_row.kind == 1)
        {
            var _gi = _row.group;
            var _open = mus_ungrouped_open;
            var _gname = "Ungrouped";
            if (_gi >= 0) { _open = _song.arr.loop_groups[_gi].open; _gname = _song.arr.loop_groups[_gi].name; }
            ui_rrect(_x1 + 12, _iy, _ix2, _iy + 30, 6, global.TH.btn_top, global.TH.btn_bot, 1);
            if (mus_drag && mus_group_hover == _gi) { ui_rrect_line(_x1 + 12, _iy, _ix2, _iy + 30, 6, global.TH.accent, 1, 2); }
            var _arrow = ">";
            if (_open) { _arrow = "v"; }
            if (ui_button("mus_group_open_" + string(_gi), _x1 + 14, _iy + 2, 26, 26, _arrow, "Open / close group|Shows or hides the loops in this group.", BTN_GHOST))
            {
                if (_gi < 0) { mus_ungrouped_open = !_open; }
                else { undo_mark("musgroupopen" + string(current_time)); _song.arr.loop_groups[_gi].open = !_open; }
            }
            if (_gi >= 0)
            {
                var _renamed = ui_textfield("mus_group_name_" + string(_gi), _x1 + 44, _iy + 2, _ix2 - _x1 - 74, 26, _gname, 24, "Group name|Type a new name. Drag a loop onto this header to put it in the group.");
                if (_renamed != _gname) { undo_mark("musgrouprename" + string(_gi)); _song.arr.loop_groups[_gi].name = _renamed; }
            }
            else { ui_text(_x1 + 48, _iy + 15, _gname, global.TH.text_dim, fa_left, fa_middle, global.f_small, 1); }
            ui_text(_ix2 - 6, _iy + 15, string(_row.count), global.TH.text_faint, fa_right, fa_middle, global.f_small, 1);
            continue;
        }
        var _it = _row.it;
        var _lp = music_item_loop(_it);
        var _id = "mus_lib_item_" + string(i);
        var _what = "lib_" + string(_it[0]) + "_" + string(_it[1]);
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
            if (_it[0] == 1 && mus_lib_click_loop == _it[1] && current_time - mus_lib_click_time < 350)
            {
                music_open_editor(_it[1], 0, clamp(mus_cursor_bar, 0, _song.arr.bars - 1));
                mus_lib_click_loop = -1;
            }
            else
            {
                music_preview_loop(_lp, _what);
                mus_lib_click_loop = -1;
                if (_it[0] == 1) { mus_lib_click_loop = _it[1]; }
                mus_lib_click_time = current_time;
            }
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
    if (array_length(_rows) == 0)
    {
        ui_text_wrap(_x1 + 20, _ly1 + 10, "Press New loop to start from scratch. Your new and edited loops appear here; paint them onto the timeline to use them.", global.TH.text_faint, _x2 - _x1 - 40, global.f_small, 1);
    }
    ui_scroll_end("mus_lib", _x1 + 8, _ly1, _x2 - 8, _ly2, _content);
    if (mus_edit >= 0)
    {
        var _help_y = _y2 - 102;
        ui_rrect(_x1 + 10, _help_y, _x2 - 10, _y2 - 8, 7, global.TH.btn_top, global.TH.panel_bot, 0.9);
        ui_text(_x1 + 20, _help_y + 11, "NOTE SHORTCUTS", global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
        ui_text(_x1 + 20, _help_y + 28, "Drag: move note   Alt: audition", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        ui_text(_x1 + 20, _help_y + 45, "Circle: bend   Space: Listen", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        ui_text(_x1 + 20, _help_y + 62, "Ctrl-drag: copy note / select box", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        ui_text(_x1 + 20, _help_y + 79, "Ctrl+C: copy   Ctrl+V: paste", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    }
    else
    {
        ui_text_wrap(_x1 + 16, _y2 - 42, _tip, global.TH.text_faint, _x2 - _x1 - 32, global.f_small, 1);
    }
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
            mus_group_selected = -1;
            mus_lib_click_loop = -1;
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
    if (ui_button("mus_import", _bx, _ty, 140, 32, "Import .mod...", "Import a module|Loads a 4-channel ProTracker .mod made in ProTracker, OpenMPT or MilkyTracker as a new song. It plays as it is; to change it, edit it there and import it again.", BTN_NORMAL))
    {
        music_import_mod();
        _song = music_cur_song();
    }
    _bx += 148;
    if (!is_undefined(_song))
    {
        if (ui_button("mus_export", _bx, _ty, 124, 32, "Save .mod...", "Save as a module|Writes this song as a standard ProTracker .mod - exactly what goes on the disk - so you can open it in OpenMPT or ProTracker.", BTN_GHOST))
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
    if (ui_button("mus_play", _fx, _ry + 16, 96, 32, _plab, "Play / stop|Plays the selected range from the yellow bar marker. Space controls this playback when the loop editor is closed; in the editor, Space controls Listen instead.", _pst))
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
        ui_heading(_x, _ry, "Playback");
        var _mode = ui_dropdown("mus_play_mode", _x, _ry + 16, 110, 32, ["Bar", "4 bars", "Song"], mus_play_mode, "Playback range|Bar repeats the current bar on all four lanes. 4 bars repeats up to four bars starting at the yellow marker. Song plays the complete arrangement with its song loop point. This only changes preview playback; MOD and ADF exports use the full song.");
        if (_mode != mus_play_mode)
        {
            var _was_playing = (mus_playing && mus_play_what == "song");
            if (_was_playing) { music_preview_stop(); }
            mus_play_mode = _mode;
            if (_was_playing) { music_play_toggle(); }
        }
        _x += 122;
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
    var _sx = _x2 - 270;
    ui_register("mus_size", _sx, _y1 + 10, _x2 - 20, _y1 + 45, "Chip RAM|The song becomes a ProTracker module of this size, stored in chip RAM with the rest of your game. Instruments that are not used take no room.");
    ui_text(_x2 - 20, _y1 + 22, "Song: " + _kb + " KB chip RAM", global.TH.text_dim, fa_right, fa_middle, global.f_small, 1);
    if (array_length(mus_size_warn) > 0)
    {
        ui_register("mus_warn", _sx, _y1 + 32, _x2 - 20, _y1 + 46, "Music warning|" + mus_size_warn[0]);
        ui_text(_x2 - 20, _y1 + 39, ui_text_fit(mus_size_warn[0], global.f_small, _x2 - 20 - _sx), global.TH.warn, fa_right, fa_middle, global.f_small, 1);
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
/// Compact volume slider fits beside a lane even with the note editor open.
function music_lane_volume(_song, _lane, _px, _py, _width)
{
    var _id = "mus_lane_volume_" + string(_lane);
    var _value = _song.arr.volumes[_lane];
    var _hot = ui_register(_id, _px - 4, _py - 7, _px + _width + 4, _py + 7, "Lane " + string(_lane + 1) + " volume|Drag from silent (0) to full volume (64). This level applies to the whole lane in preview and the exported song.");
    if (_hot && ui_pressed) { ui_drag_id = _id; ui_take_click(); }
    if (ui_drag_id == _id && ui_held)
    {
        var _next = clamp(round((ui_mx - _px) / max(1, _width) * 64), 0, 64);
        if (_next != _value)
        {
            undo_mark("muslanevolume" + string(_lane));
            _song.arr.volumes[_lane] = _next;
            _value = _next;
            music_touch();
            if (mus_playing && mus_play_what == "song" && mus_play_song == mus_song)
            {
                mus_pl.ch[_lane].vol = clamp(round(mus_pl.ch[_lane].base_volume * _value / 64), 0, 64);
            }
            if (mus_playing && mus_play_what == "edit" && mus_edit_cell[0] == _lane)
            {
                mus_pl.ch[0].vol = clamp(round(mus_pl.ch[0].base_volume * _value / 64), 0, 64);
            }
        }
    }
    var _knob = _px + _width * _value / 64;
    draw_line_width_colour(_px, _py, _px + _width, _py, 3, global.TH.text_faint, global.TH.text_faint);
    draw_line_width_colour(_px, _py, _knob, _py, 3, global.TH.accent, global.TH.accent);
    draw_circle_colour(_knob, _py, 4, c_white, c_white, false);
}

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
        if (!_imported)
        {
            ui_text(_tx1 + 14, _ly + 12, string(l + 1) + " " + string_char_at(_side[l], 1), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
            ui_text(_gx1 - 10, _ly + 12, string(round(_song.arr.volumes[l] * 100 / 64)) + "%", global.TH.text_dim, fa_right, fa_middle, global.f_small, 1);
            music_lane_volume(_song, l, _tx1 + 14, _ly + _lane_h - 11, _gx1 - _tx1 - 28);
        }
        else
        {
            ui_text(_tx1 + 14, _ly + _lane_h * 0.5 - 7, "Lane " + string(l + 1), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
            ui_text(_tx1 + 14, _ly + _lane_h * 0.5 + 8, _side[l], global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);
        }
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
        // the loop bar's number sits right of the green loop flag, so the flag never covers it
        var _lx = _bx + 5;
        if (!_imported && _b == _song.loop_bar) { _lx = _bx + 18; }
        ui_text(_lx, _ty1 + 13, _lab, global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
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
                    mus_stroke_cell = [_hl, _hb];
                    music_paint_cell(_song, mus_brush, _hl, _hb, mus_paint_tag);
                }
                else { toast("Pick a loop on the left first, then paint it here", 1); }
            }
        }
        else
        {
            if (mus_painting && ui_held && mus_brush[0] >= 0)
            {
                // fill every empty cell between the last one and this one, so a fast drag doesn't skip bars
                var _cells = music_stroke_cells(mus_stroke_cell[0], mus_stroke_cell[1], _hl, _hb);
                for (var c = 0; c < array_length(_cells); c++)
                {
                    if (_song.arr.lanes[_cells[c][0]][_cells[c][1]] < 0)
                    {
                        music_paint_cell(_song, mus_brush, _cells[c][0], _cells[c][1], mus_paint_tag);
                    }
                }
                mus_stroke_cell = [_hl, _hb];
            }
        }
        if (ui_rpressed)
        {
            mus_erasing = true;
            mus_paint_tag = "museras" + string(current_time);
            mus_stroke_cell = [_hl, _hb];
        }
        if (mus_erasing && ui_rheld)
        {
            var _ecells = music_stroke_cells(mus_stroke_cell[0], mus_stroke_cell[1], _hl, _hb);
            for (var c = 0; c < array_length(_ecells); c++)
            {
                if (_song.arr.lanes[_ecells[c][0]][_ecells[c][1]] >= 0)
                {
                    undo_mark(mus_paint_tag);
                    _song.arr.lanes[_ecells[c][0]][_ecells[c][1]] = -1;
                    music_touch();
                }
            }
            mus_stroke_cell = [_hl, _hb];
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
    if (mus_ed_select_ref != _lp)
    {
        mus_ed_resize_step = -1;
        mus_ed_select_ref = _lp;
        mus_ed_selected = array_create(MUS_STEPS, false);
        mus_ed_select_drag = false;
    }
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
    if (ui_button("mus_ed_listen", _hx, _hy, 80, 30, "Listen", "Listen|Plays this loop once at the song's tempo and swing. Space does the same while the loop editor is open; press again to stop.", _lst))
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
    if (ui_button("mus_ed_clear", _ex2 - 170, _hy, 70, 30, "Clear", "Clear loop|Asks before removing every note, chord, effect and bend connection from this loop. You can Undo the clear.", BTN_GHOST))
    {
        var _body = "Remove all notes, chords, effects and bend connections from " + _lp.name + "? You can Undo this.";
        if (_uses > 1)
        {
            _body += " This loop is used in " + string(_uses) + " bars, so all of those bars will be cleared.";
        }
        confirm_open("Clear this loop?", _body, "Clear loop", "Cancel", true, music_loop_clear_now, { song : mus_song, loop : _li });
    }
    if (ui_button("mus_ed_close", _ex2 - 92, _hy, 80, 30, "Close", "Close the editor|Back to the level music settings. Double-click any bar to edit again.", BTN_GHOST))
    {
        mus_edit = -1;
        return;
    }
    var _tip = "Used in " + string(_uses) + " bar";
    if (_uses != 1) { _tip += "s"; }
    if (_drums) { _tip += "  -  one hit per step: click to add or remove, drag to paint, right-click to rub out."; }
    else { _tip += "  -  one note per step: click to place, drag to move; drag the blue handle to a later note to link a glide. Chords play as ProTracker arpeggios."; }
    ui_text(_ex1 + 14, _hy + 44, ui_text_fit(_tip, global.f_small, _ex2 - _ex1 - 28), global.TH.text_faint, fa_left, fa_middle, global.f_small, 1);

    var _res_x = _ex2 - 112;
    var _res_y = _ey1 + 58;
    var _res_label = "Snap 1/" + string(mus_ed_resolution);
    if (keyboard_check(vk_alt)) { _res_label = "No snap"; }
    var _res_tip = "Grid snap|Choose 4, 8, 16 or 32 trigger positions across the bar; new notes last one snap step. Click for coarser, right-click for finer. Keys 1-4 pick 1/32, 1/16, 1/8 or 1/4 while the mouse is over the editor. Hold Alt to place, move or resize without snap.";
    if (!_drums && ui_hit(_ex1, _ey1, _ex2, _ey2))
    {
        mus_ed_keys_hover = true;
        if (ui_focus == "" && !keyboard_check(vk_control))
        {
            var _key_snaps = [32, 16, 8, 4];   // 1 = shortest step ... 4 = longest
            for (var _ks = 0; _ks < 4; _ks++)
            {
                if (keyboard_check_pressed(ord(string(_ks + 1))) && pro_gate("Music grid snap")) { mus_ed_resolution = _key_snaps[_ks]; }
            }
        }
    }
    // Click steps coarser, right-click steps finer
    var _snap_dir = 0;
    if (!_drums && ui_button("mus_ed_resolution", _res_x, _res_y, 100, 24, _res_label, _res_tip, BTN_GHOST)) { _snap_dir = -1; }
    if (!_drums && ui_rpressed && ui_hit(_res_x, _res_y, _res_x + 100, _res_y + 24)) { _snap_dir = 1; }
    if (_snap_dir != 0)
    {
        if (!pro_gate("Music grid snap"))
        {
            mus_ed_resolution = 16;
        }
        else
        {
            var _snap_values = [4, 8, 16, 32];
            var _snap_n = array_length(_snap_values);
            var _snap_idx = 0;
            for (var si = 0; si < _snap_n; si++)
            {
                if (_snap_values[si] == mus_ed_resolution) { _snap_idx = si; }
            }
            mus_ed_resolution = _snap_values[(_snap_idx + _snap_dir + _snap_n) mod _snap_n];
        }
    }

    // ---------- grid ----------
    var _gx1 = _ex1 + 10;
    var _gx2 = _ex2 - 10;
    var _gy1 = _ey1 + 88;
    var _gy2 = _ey2 - 8;
    if (!_drums) { _gy2 -= 88; }
    else { _gy2 -= 58; }
    if (_gy2 - _gy1 < 30) { return; }
    var _lab = 92;
    var _view_steps = MUS_STEPS;
    var _step_stride = 1;
    var _snap_stride = 2;
    if (!_drums)
    {
        _snap_stride = MUS_STEPS div mus_ed_resolution;
    }
    else
    {
        _snap_stride = 2;
    }
    // Alt: no snap - place, move and resize on any step (new notes 1 step)
    if (keyboard_check(vk_alt)) { _snap_stride = 1; }
    // New notes last one snap step (drums keep the default length)
    var _new_len = 0;
    if (!_drums) { _new_len = _snap_stride; }
    var _cw = max(6, (_gx2 - _gx1 - _lab - 16) / MUS_STEPS);
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
    var _sx2 = _sx + _cw * _view_steps;
    if (mus_ed_select_drag && ui_held && ui_mx >= _sx && ui_mx <= _sx2)
    {
        if (ui_my < _gy1 + 12) { _off -= 6; }
        if (ui_my > _gy2 - 12) { _off += 6; }
        _off = clamp(_off, 0, max(0, _content - (_gy2 - _gy1)));
        ds_map_replace(ui_scroll, _sid, _off);
    }
    var _grid_note = "Snap sets where new notes go and how long they last (keys 1-4; hold Alt for no snap). Shift-drag a note's right edge to resize; Ctrl+D deselects.";
    ui_register("mus_ed_grid", _sx, _gy1, _sx2, _gy2, "Notes|" + _grid_note + " Ctrl-drag a box to select touched notes, Ctrl+C to copy them (or the note under the mouse), Ctrl-drag a note to clone it, Ctrl+V to paste at the mouse. Paste replaces occupied time slots. Drag a note to move it or its circle to connect a bend.");
    var _hr = -1;
    var _hs = -1;
    if (ui_hit(_sx, _gy1, _sx2, _gy2))
    {
        _hr = floor((ui_my - _gy1 + _off) / _rh);
        var _view_step = floor((ui_mx - _sx) / _cw);
        _hs = _view_step * _step_stride;
        if (_hr < 0 || _hr >= _nr || _view_step < 0 || _view_step >= _view_steps)
        {
            _hr = -1;
            _hs = -1;
        }
    }
    if (_hr >= 0)
    {
        var _raw_hit = _hs;
        _hs = (_raw_hit div _snap_stride) * _snap_stride;
        for (var _note_hit = 0; _note_hit < MUS_STEPS; _note_hit++)
        {
            if (_lp.notes[_note_hit] <= 0 || music_note_row(_lp, _note_hit, _drums) != _hr) { continue; }
            if (ui_mx >= _sx + _note_hit * _cw && ui_mx < _sx + (_note_hit + music_note_length(_lp, _note_hit)) * _cw) { _hs = _note_hit; }
        }
    }
    var _select_this_frame = mus_ed_select_drag;
    var _on_note = false;
    if (_hr >= 0 && _hs >= 0)
    {
        if (_drums) { _on_note = (_lp.notes[_hs] > 0 && _lp.insts[_hs] == _rows[_hr]); }
        else { _on_note = (_lp.notes[_hs] == _rows[_hr]); }
    }
    if (ui_pressed && keyboard_check(vk_control) && _hr >= 0 && !_on_note)
    {
        ui_take_click();
        ui_focus = "";
        mus_ed_select_drag = true;
        _select_this_frame = true;
        mus_ed_selected = array_create(MUS_STEPS, false);
        mus_ed_select_start = [ui_mx - _sx, ui_my - _gy1 + _off];
        mus_ed_select_end = mus_ed_select_start;
        mus_ed_note_drag = false;
        mus_ed_note_glide = false;
        mus_ed_fx_drag = false;
        mus_ed_painting = false;
        mus_ed_rclear = false;
    }
    if (mus_ed_select_drag)
    {
        mus_ed_select_end = [clamp(ui_mx - _sx, 0, _sx2 - _sx), clamp(ui_my, _gy1, _gy2) - _gy1 + _off];
        mus_ed_selected = music_notes_in_box(_lp, _drums, _step_stride, _cw, _rh,
            [mus_ed_select_start[0], mus_ed_select_start[1], mus_ed_select_end[0], mus_ed_select_end[1]]);
        if (!ui_held) { mus_ed_select_drag = false; }
    }
    if (!_select_this_frame && ui_focus == "" && ui_can_input() && keyboard_check(vk_control))
    {
        if (keyboard_check_pressed(ord("D")) && !mus_ed_note_drag) { mus_ed_selected = array_create(MUS_STEPS, false); }
        if (keyboard_check_pressed(ord("C")))
        {
            // The note under the mouse, unless it is part of the selection
            var _copy_sel = mus_ed_selected;
            if (_on_note && !mus_ed_selected[_hs])
            {
                _copy_sel = array_create(MUS_STEPS, false);
                _copy_sel[_hs] = true;
            }
            var _copied = music_notes_copy(_lp, _copy_sel, _drums);
            if (array_length(_copied.notes) == 1) { mus_ed_clip = _copied; toast("Copied 1 note", 0); }
            else if (array_length(_copied.notes) > 1)
            {
                mus_ed_clip = _copied;
                toast("Copied " + string(array_length(_copied.notes)) + " notes", 0);
            }
            else { toast("Hover a note or Ctrl-drag a box over some notes first", 0); }
        }
        if (keyboard_check_pressed(ord("V")) && _hr >= 0)
        {
            if (mus_ed_clip.drums != _drums) { toast("Paste into the same kind of grid: notes or drums", 1); }
            else
            {
                var _preview = music_notes_paste(_lp, mus_ed_clip, _hs, _hr, _drums, false);
                if (_preview.count > 0)
                {
                    music_loop_edit_begin(_song, _li, "musnotepaste" + string(current_time));
                    var _pasted = music_notes_paste(_lp, mus_ed_clip, _hs, _hr, _drums);
                    mus_ed_selected = _pasted.selected;
                }
                else { toast("Copy some selected notes first, then paste where they fit", 0); }
            }
        }
    }
    var _play_step = -1;
    var _hit_handle_step = -1;
    var _hit_handle_row = -1;
    var _hit_handle_distance = 9;
    var _hit_resize_step = -1;
    var _glide_col = make_colour_rgb(80, 220, 120);
    var _glide_drop_step = -1;
    var _glide_drop_row = -1;
    if (mus_ed_note_glide && !_drums && ui_my >= _gy1 && ui_my < _gy2)
    {
        for (var _target_cell = 0; _target_cell < _view_steps; _target_cell++)
        {
            var _target_step = _target_cell * _step_stride;
            if (_target_step <= mus_ed_note_src[0] || _lp.notes[_target_step] <= 0) { continue; }
            var _target_row = 36 - _lp.notes[_target_step];
            var _target_x = _sx + _target_cell * _cw;
            var _target_y = _gy1 + _target_row * _rh - _off;
            if (ui_hit(_target_x + 2, _target_y + 2, _target_x + music_note_length(_lp, _target_step) * _cw - 2, _target_y + _rh - 2)
                || point_distance(ui_mx, ui_my, _target_x + 2, _target_y + _rh * 0.5) <= 7)
            {
                _glide_drop_step = _target_step;
                _glide_drop_row = _target_row;
                break;
            }
        }
    }
    if (mus_playing && mus_play_what != "note")
    {
        var _pos = music_preview_pos();
        if (!is_undefined(_pos)) { _play_step = floor((_pos[1] mod MUS_STEPS) / _step_stride); }
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
        // Cells and grid lines first, so long notes are drawn over them
        var _beat_cells = max(1, _view_steps div 4);
        for (var _gst = 0; _gst < _view_steps; _gst++)
        {
            var _gcx = _sx + _gst * _cw;
            var _ba = 0.10;
            if ((_gst div _beat_cells) mod 2 == 1) { _ba = 0.05; }
            if (_black) { _ba *= 0.5; }
            if (_gst == _play_step) { _ba += 0.12; }
            draw_set_alpha(_ba);
            draw_rectangle_colour(_gcx + 1, _ry + 1, _gcx + _cw - 1, _ry + _rh - 1, c_white, c_white, c_white, c_white, false);
            // Beat lines brightest, snap lines clear, other steps faint
            var _la = 0.06;
            if (_gst mod _snap_stride == 0) { _la = 0.30; }
            if (_gst mod _beat_cells == 0) { _la = 0.55; }
            draw_set_alpha(_la);
            draw_line_colour(_gcx, _ry, _gcx, _ry + _rh, c_white, c_white);
            draw_set_alpha(1);
        }
        for (var st = 0; st < _view_steps; st++)
        {
            var _cx = _sx + st * _cw;
            var _data_step = st * _step_stride;
            var _on = false;
            if (_drums) { _on = (_lp.notes[_data_step] > 0 && _lp.insts[_data_step] == _rv); }
            else { _on = (_lp.notes[_data_step] == _rv); }
            if (_on)
            {
                var _note_w = music_note_length(_lp, _data_step) * _cw;
                if (_drums && keyboard_check(vk_shift) && point_distance(ui_mx, ui_my, _cx + _note_w - 2, _ry + _rh * 0.5) <= 9 && ui_my >= _gy1 && ui_my < _gy2) { _hit_resize_step = _data_step; }
                ui_rrect(_cx + 2, _ry + 2, _cx + _note_w - 2, _ry + _rh - 2, 4, merge_colour(_col, c_white, 0.15), _col, 1);
                if (mus_ed_selected[_data_step])
                {
                    ui_rrect_line(_cx + 1, _ry + 1, _cx + _note_w - 1, _ry + _rh - 1, 4, c_white, 1, 2);
                }
                if (!_drums)
                {
                    var _handle_x = _cx + _note_w - 2;
                    var _handle_y = _ry + _rh * 0.5;
                    var _handle_hot = (point_distance(ui_mx, ui_my, _handle_x, _handle_y) <= 9);
                    var _handle_distance = point_distance(ui_mx, ui_my, _handle_x, _handle_y);
                    if (keyboard_check(vk_shift) && _handle_hot && ui_my >= _gy1 && ui_my < _gy2) { _hit_resize_step = _data_step; }
                    if (!keyboard_check(vk_shift) && _handle_hot && _handle_distance <= _hit_handle_distance && ui_my >= _gy1 && ui_my < _gy2)
                    {
                        _hit_handle_step = _data_step;
                        _hit_handle_row = r;
                        _hit_handle_distance = _handle_distance;
                    }
                    var _handle_colour = global.TH.accent;
                    var _handle_radius = 4;
                    if (_handle_hot || (mus_ed_note_glide && _data_step == mus_ed_note_src[0]))
                    {
                        _handle_colour = c_white;
                        _handle_radius = 6;
                    }
                    if (!keyboard_check(vk_shift))
                    {
                        draw_circle_colour(_handle_x, _handle_y, _handle_radius + 1, global.TH.panel_bot, global.TH.panel_bot, false);
                        draw_circle_colour(_handle_x, _handle_y, _handle_radius, _handle_colour, _handle_colour, false);
                    }
                    else { draw_line_width_colour(_handle_x, _ry + 3, _handle_x, _ry + _rh - 3, 2, c_white, c_white); }
                }
            }
            var _glide_target_hot = false;
            if (_on && mus_ed_note_glide && ui_held && _data_step > mus_ed_note_src[0])
            {
                draw_circle_colour(_cx + 2, _ry + _rh * 0.5, 5, global.TH.panel_bot, global.TH.panel_bot, false);
                draw_circle_colour(_cx + 2, _ry + _rh * 0.5, 4, _glide_col, _glide_col, false);
                _glide_target_hot = (_glide_drop_step == _data_step && _glide_drop_row == r);
            }
            if (_glide_target_hot)
            {
                var _flash_alpha = 0.55 + 0.45 * abs(sin(current_time / 120));
                draw_set_alpha(_flash_alpha * 0.3);
                draw_rectangle_colour(_cx + 2, _ry + 2, _cx + _cw - 2, _ry + _rh - 2, _glide_col, _glide_col, _glide_col, _glide_col, false);
                draw_set_alpha(1);
                ui_rrect_line(_cx + 1, _ry + 1, _cx + _cw - 1, _ry + _rh - 1, 4, _glide_col, _flash_alpha, 2);
            }
        }
    }
    // Hover outline: the note under the mouse, or the note a click would place
    if (_hr >= 0 && _hs >= 0 && !mus_ed_note_drag && !_select_this_frame && mus_ed_resize_step < 0)
    {
        var _hov_len = 0;
        var _hov_on = false;
        if (_drums) { _hov_on = (_lp.notes[_hs] > 0 && _lp.insts[_hs] == _rows[_hr]); }
        else { _hov_on = (_lp.notes[_hs] == _rows[_hr]); }
        if (_hov_on) { _hov_len = music_note_length(_lp, _hs); }
        else
        {
            _hov_len = _new_len;
            if (_hov_len <= 0) { _hov_len = 2; }
            _hov_len = min(_hov_len, MUS_STEPS - _hs);
        }
        var _hov_x = _sx + (_hs div _step_stride) * _cw;
        var _hov_y = _gy1 + _hr * _rh - _off;
        if (!_hov_on)
        {
            draw_set_alpha(0.18);
            draw_rectangle_colour(_hov_x + 2, _hov_y + 2, _hov_x + _hov_len * _cw - 2, _hov_y + _rh - 2, global.TH.accent, global.TH.accent, global.TH.accent, global.TH.accent, false);
            draw_set_alpha(1);
        }
        ui_rrect_line(_hov_x + 1, _hov_y + 1, _hov_x + _hov_len * _cw - 1, _hov_y + _rh - 1, 4, global.TH.accent, 0.9, 1);
    }
    // Ctrl-drag clone: a ghost of the copy where it will land when let go
    if (mus_ed_note_drag && mus_ed_note_copy && mus_ed_note_last[0] >= 0)
    {
        var _ghost_len = min(music_note_length(_lp, mus_ed_note_src[0]), MUS_STEPS - mus_ed_note_last[0]);
        var _ghost_x = _sx + (mus_ed_note_last[0] div _step_stride) * _cw;
        var _ghost_y = _gy1 + mus_ed_note_last[1] * _rh - _off;
        ui_rrect(_ghost_x + 2, _ghost_y + 2, _ghost_x + _ghost_len * _cw - 2, _ghost_y + _rh - 2, 4, merge_colour(_col, c_white, 0.15), _col, 0.45);
        ui_rrect_line(_ghost_x + 1, _ghost_y + 1, _ghost_x + _ghost_len * _cw - 1, _ghost_y + _rh - 1, 4, c_white, 0.9, 1);
    }
    // Dragging a selection: ghosts of every selected note where they will land
    if (mus_ed_note_drag && mus_ed_note_group && mus_ed_note_last[0] >= 0)
    {
        var _gd_steps = mus_ed_note_last[0] - mus_ed_note_src[0];
        var _gd_rows = mus_ed_note_last[1] - mus_ed_note_src[1];
        for (var _gn = 0; _gn < MUS_STEPS; _gn++)
        {
            if (!mus_ed_selected[_gn] || _lp.notes[_gn] <= 0) { continue; }
            var _gn_to = _gn + _gd_steps;
            if (_gn_to < 0 || _gn_to >= MUS_STEPS) { continue; }
            var _gn_len = min(music_note_length(_lp, _gn), MUS_STEPS - _gn_to);
            var _gn_x = _sx + (_gn_to div _step_stride) * _cw;
            var _gn_y = _gy1 + (music_note_row(_lp, _gn, _drums) + _gd_rows) * _rh - _off;
            ui_rrect(_gn_x + 2, _gn_y + 2, _gn_x + _gn_len * _cw - 2, _gn_y + _rh - 2, 4, merge_colour(_col, c_white, 0.15), _col, 0.45);
            ui_rrect_line(_gn_x + 1, _gn_y + 1, _gn_x + _gn_len * _cw - 1, _gn_y + _rh - 1, 4, c_white, 0.9, 1);
        }
    }
    if (!_drums)
    {
        for (var _glide_src = 0; _glide_src < MUS_STEPS; _glide_src++)
        {
            if (!music_glide_valid(_lp, _glide_src)) { continue; }
            var _glide_target = _lp.glide_to[_glide_src];
            var _line_x1 = _sx + (_glide_src + music_note_length(_lp, _glide_src)) * _cw - 2;
            var _line_x2 = _sx + (_glide_target div _step_stride) * _cw + 2;
            var _line_y1 = _gy1 + (36 - _lp.notes[_glide_src]) * _rh - _off + _rh * 0.5;
            var _line_y2 = _gy1 + (36 - _lp.notes[_glide_target]) * _rh - _off + _rh * 0.5;
            draw_line_width_colour(_line_x1, _line_y1, _line_x2, _line_y2, 3, _glide_col, _glide_col);
            if (!keyboard_check(vk_shift))
            {
                draw_circle_colour(_line_x1, _line_y1, 4, _glide_col, _glide_col, false);
                draw_circle_colour(_line_x2, _line_y2, 4, _glide_col, _glide_col, false);
            }
        }
    }
    if (mus_ed_note_glide && ui_held) { mus_ed_note_glide_end = [-1, -1]; }
    if (mus_ed_note_glide && ui_held && _glide_drop_step >= 0)
    {
        mus_ed_note_glide_end = [_glide_drop_step, _glide_drop_row];
    }
    if (mus_ed_note_glide && ui_held)
    {
        var _src_x = _sx + (mus_ed_note_src[0] + music_note_length(_lp, mus_ed_note_src[0])) * _cw - 2;
        var _src_y = _gy1 + mus_ed_note_src[1] * _rh - _off + _rh * 0.5;
        draw_line_width_colour(_src_x, _src_y, ui_mx, ui_my, 2, _glide_col, _glide_col);
    }
    if (_select_this_frame)
    {
        var _box_x1 = _sx + min(mus_ed_select_start[0], mus_ed_select_end[0]);
        var _box_x2 = _sx + max(mus_ed_select_start[0], mus_ed_select_end[0]);
        var _box_y1 = _gy1 - _off + min(mus_ed_select_start[1], mus_ed_select_end[1]);
        var _box_y2 = _gy1 - _off + max(mus_ed_select_start[1], mus_ed_select_end[1]);
        draw_set_alpha(0.15);
        draw_rectangle_colour(_box_x1, _box_y1, _box_x2, _box_y2, global.TH.accent, global.TH.accent, global.TH.accent, global.TH.accent, false);
        draw_set_alpha(1);
        draw_rectangle_colour(_box_x1, _box_y1, _box_x2, _box_y2, global.TH.accent, global.TH.accent, global.TH.accent, global.TH.accent, true);
    }
    ui_scroll_end(_sid, _gx1, _gy1, _gx2, _gy2, _content);
    if (ui_pressed && _hit_resize_step >= 0 && !mus_ed_note_drag)
    {
        ui_take_click();
        mus_ed_resize_step = _hit_resize_step;
        mus_ed_resize_changed = false;
        mus_ed_tag = "musresize" + string(current_time);
        mus_ed_painting = false;
    }
    if (mus_ed_resize_step >= 0)
    {
        if (ui_held)
        {
            var _resize_end = round((ui_mx - _sx) / (_cw * _snap_stride)) * _snap_stride;
            var _resize_len = clamp(_resize_end - mus_ed_resize_step, 1, MUS_STEPS - mus_ed_resize_step);
            if (_resize_len != music_note_length(_lp, mus_ed_resize_step))
            {
                if (!mus_ed_resize_changed) { music_loop_edit_begin(_song, _li, mus_ed_tag); }
                else { music_touch(); }
                _lp.lengths[mus_ed_resize_step] = _resize_len;
                // Resizing a selected note gives every selected note that length
                if (mus_ed_selected[mus_ed_resize_step])
                {
                    for (var _rs = 0; _rs < MUS_STEPS; _rs++)
                    {
                        if (mus_ed_selected[_rs] && _lp.notes[_rs] > 0) { _lp.lengths[_rs] = min(_resize_len, MUS_STEPS - _rs); }
                    }
                }
                mus_ed_resize_changed = true;
            }
        }
        else { mus_ed_resize_step = -1; }
    }

    // The circle extends beyond its cell. Capture its whole hit area before
    // considering an empty cell, so grabbing its outer edge cannot paint a note.
    if (ui_pressed && !mus_ed_note_drag && !keyboard_check(vk_control) && _hit_handle_step >= 0)
    {
        _hs = _hit_handle_step;
        _hr = _hit_handle_row;
    }
    if (mus_ed_note_glide && _glide_drop_step >= 0)
    {
        _hs = _glide_drop_step;
        _hr = _glide_drop_row;
    }

    // Alt-hover auditions each existing note cell once, until the pointer leaves it.
    var _alt_note_on = false;
    if (!_select_this_frame && keyboard_check(vk_alt) && _hr >= 0 && _hs >= 0)
    {
        var _alt_row_value = _rows[_hr];
        var _alt_pitch = _lp.notes[_hs];
        var _alt_inst = _lp.insts[_hs];
        if (_drums)
        {
            _alt_note_on = (_alt_pitch > 0 && _alt_inst == _alt_row_value);
            _alt_pitch = music_inst_root(_alt_row_value);
            _alt_inst = _alt_row_value;
        }
        else
        {
            _alt_note_on = (_alt_pitch == _alt_row_value);
        }
        if (_alt_note_on)
        {
            if (_hs != mus_ed_alt_preview_step || _hr != mus_ed_alt_preview_row)
            {
                if (_drums) { music_preview_note(_alt_inst, _alt_pitch); }
                else { music_preview_note(_alt_inst, _alt_pitch, _lp.fx[_hs], _lp.fxp[_hs]); }
            }
            mus_ed_alt_preview_step = _hs;
            mus_ed_alt_preview_row = _hr;
        }
        else
        {
            mus_ed_alt_preview_step = -1;
            mus_ed_alt_preview_row = -1;
        }
    }
    else
    {
        mus_ed_alt_preview_step = -1;
        mus_ed_alt_preview_row = -1;
    }

    if (_hr >= 0 && !_select_this_frame && mus_ed_resize_step < 0)
    {
        mus_ed_fx_step = _hs;
        var _rv2 = _rows[_hr];
        var _on2 = false;
        if (_drums) { _on2 = (_lp.notes[_hs] > 0 && _lp.insts[_hs] == _rv2); }
        else { _on2 = (_lp.notes[_hs] == _rv2); }
        if (ui_pressed && !mus_ed_note_drag)
        {
            ui_take_click();
            mus_ed_tag = "musstep" + string(current_time);
            mus_ed_mode = 1;
            if (_on2) { mus_ed_mode = 0; }
            if (_on2)
            {
                mus_ed_note_drag = true;
                mus_ed_note_copy = keyboard_check(vk_control);
                mus_ed_note_group = (mus_ed_selected[_hs] && !mus_ed_note_copy);
                mus_ed_note_src = [_hs, _hr];
                mus_ed_note_pitch = _lp.notes[_hs];
                mus_ed_note_inst = _lp.insts[_hs];
                mus_ed_note_fx = _lp.fx[_hs];
                mus_ed_note_fxp = _lp.fxp[_hs];
                mus_ed_note_arp = _lp.arps[_hs];
                mus_ed_note_moved = false;
                mus_ed_note_last = [-1, -1];
                mus_ed_note_preview_pitch = mus_ed_note_pitch;
                var _note_cell_x = _sx + (_hs div _step_stride) * _cw;
                var _note_cell_y = _gy1 + _hr * _rh - _off;
                mus_ed_note_glide = (!_drums && !keyboard_check(vk_shift) && !mus_ed_note_copy && point_distance(ui_mx, ui_my, _note_cell_x + music_note_length(_lp, _hs) * _cw - 2, _note_cell_y + _rh * 0.5) <= 9);
                mus_ed_painting = false;
                mus_ed_note_glide_end = [-1, -1];
            }
            else
            {
                mus_ed_selected = array_create(MUS_STEPS, false);
                mus_ed_painting = true;
                music_ed_apply(_song, _li, _hs, _rv2, _drums, mus_ed_mode, _new_len);
                if (mus_ed_mode == 1)
                {
                    if (_drums) { music_preview_note(_rv2, music_inst_root(_rv2)); }
                    else { music_preview_note(_lp.inst, _rv2, _lp.fx[_hs], _lp.fxp[_hs]); }
                }
            }
        }
        if (mus_ed_note_drag && !mus_ed_note_glide && ui_held && _hr >= 0 && _hs >= 0)
        {
            var _dst_step = clamp(floor((ui_mx - _sx) / (_cw * _snap_stride)) * _snap_stride, 0, MUS_STEPS - 1);
            var _dst_row = _hr;
            var _dst_pitch = clamp(mus_ed_note_pitch + mus_ed_note_src[1] - _dst_row, 1, 36);
            if (_drums) { _dst_pitch = mus_ed_note_pitch; }
            var _dst = [_dst_step, _dst_row];
            if (mus_ed_note_copy)
            {
                // Ctrl-drag clone: only a ghost follows the mouse, nothing is
                // written until the button is let go (see the release below)
                if (_dst_step != mus_ed_note_src[0])
                {
                    mus_ed_note_last = _dst;
                    mus_ed_note_moved = true;
                }
                else { mus_ed_note_last = [-1, -1]; }
                if (_dst_pitch != mus_ed_note_preview_pitch)
                {
                    mus_ed_note_preview_pitch = _dst_pitch;
                    music_preview_note(mus_ed_note_inst, _dst_pitch, mus_ed_note_fx, mus_ed_note_fxp);
                }
            }
            else if (mus_ed_note_group)
            {
                // Dragging a selection: ghosts follow the mouse; the move (moved
                // notes win) is made once, when the button is let go
                var _grp_steps = _dst_step - mus_ed_note_src[0];
                var _grp_rows = _dst_row - mus_ed_note_src[1];
                if (_grp_steps == 0 && _grp_rows == 0) { mus_ed_note_last = [-1, -1]; }
                else if (!is_undefined(music_notes_move(_lp, mus_ed_selected, _grp_steps, _grp_rows, _drums, false)))
                {
                    mus_ed_note_last = _dst;
                    mus_ed_note_moved = true;
                }
                if (_dst_pitch != mus_ed_note_preview_pitch && (mus_ed_note_last[0] >= 0 || (_grp_steps == 0 && _grp_rows == 0)))
                {
                    mus_ed_note_preview_pitch = _dst_pitch;
                    music_preview_note(mus_ed_note_inst, _dst_pitch, mus_ed_note_fx, mus_ed_note_fxp);
                }
            }
            else if (_dst_step != mus_ed_note_src[0] || _dst_pitch != mus_ed_note_pitch || (_drums && _dst_row != mus_ed_note_src[1]) || mus_ed_note_moved)
            {
                var _from_step = mus_ed_note_src[0];
                if (mus_ed_note_moved) { _from_step = mus_ed_note_last[0]; }
                var _first_copy = (mus_ed_note_copy && !mus_ed_note_moved);
                var _can_move = music_note_can_move(_lp, _from_step, _dst_step);
                var _group_row = mus_ed_note_src[1];
                if (mus_ed_note_moved) { _group_row = mus_ed_note_last[1]; }
                if (mus_ed_note_group) { _can_move = !is_undefined(music_notes_move(_lp, mus_ed_selected, _dst_step - _from_step, _dst_row - _group_row, _drums, false)); }
                if (_first_copy) { _can_move = (_dst_step != mus_ed_note_src[0]); }
                if (mus_ed_note_copy && _dst_step == mus_ed_note_src[0]) { _can_move = false; }
                if (_can_move)
                {
                    if (!mus_ed_note_moved) { music_loop_edit_begin(_song, _li, mus_ed_tag); }
                    else { music_touch(); }
                    var _was_selected = mus_ed_selected[_from_step];
                    if (mus_ed_note_group)
                    {
                        mus_ed_selected = music_notes_move(_lp, mus_ed_selected, _dst_step - _from_step, _dst_row - _group_row, _drums);
                    }
                    else
                    {
                        if (_first_copy) { music_note_duplicate(_lp, _from_step, _dst_step, _dst_pitch); }
                        else { music_note_move(_lp, _from_step, _dst_step, _dst_pitch); }
                        if (_drums) { _lp.insts[_dst_step] = _rows[_dst_row]; }
                        if (!_first_copy) { mus_ed_selected[_from_step] = false; }
                        mus_ed_selected[_dst_step] = _was_selected;
                    }
                    mus_ed_note_last = _dst;
                    mus_ed_note_moved = true;
                    if (_dst_pitch != mus_ed_note_preview_pitch)
                    {
                        mus_ed_note_preview_pitch = _dst_pitch;
                        music_preview_note(mus_ed_note_inst, _dst_pitch, mus_ed_note_fx, mus_ed_note_fxp);
                    }
                }
            }
        }
        if (mus_ed_note_drag && !ui_held)
        {
            if (mus_ed_note_glide)
            {
                var _glide_step = _glide_drop_step;
                if (_glide_step > mus_ed_note_src[0])
                {
                    music_loop_edit_begin(_song, _li, mus_ed_tag);
                    music_glide_connect(_lp, mus_ed_note_src[0], _glide_step);
                    mus_ed_fx_step = _glide_step;
                    mus_ed_note_moved = true;
                }
            }
            else if (mus_ed_note_copy)
            {
                if (mus_ed_note_last[0] >= 0 && mus_ed_note_last[0] != mus_ed_note_src[0])
                {
                    var _copy_to = mus_ed_note_last[0];
                    var _copy_row = mus_ed_note_last[1];
                    var _copy_pitch = clamp(mus_ed_note_pitch + mus_ed_note_src[1] - _copy_row, 1, 36);
                    if (_drums) { _copy_pitch = mus_ed_note_pitch; }
                    music_loop_edit_begin(_song, _li, mus_ed_tag);
                    music_note_duplicate(_lp, mus_ed_note_src[0], _copy_to, _copy_pitch);
                    if (_drums) { _lp.insts[_copy_to] = _rows[_copy_row]; }
                    mus_ed_selected[_copy_to] = mus_ed_selected[mus_ed_note_src[0]];
                }
            }
            else if (mus_ed_note_group)
            {
                if (mus_ed_note_last[0] >= 0)
                {
                    var _grp_to_steps = mus_ed_note_last[0] - mus_ed_note_src[0];
                    var _grp_to_rows = mus_ed_note_last[1] - mus_ed_note_src[1];
                    if (!is_undefined(music_notes_move(_lp, mus_ed_selected, _grp_to_steps, _grp_to_rows, _drums, false)))
                    {
                        music_loop_edit_begin(_song, _li, mus_ed_tag);
                        music_notes_move(_lp, mus_ed_selected, _grp_to_steps, _grp_to_rows, _drums);
                        mus_ed_selected = array_create(MUS_STEPS, false);   // dropped: deselect
                    }
                }
            }
            else if (!mus_ed_note_moved)
            {
                music_loop_edit_begin(_song, _li, mus_ed_tag);
                music_glide_unlink(_lp, mus_ed_note_src[0]);
                _lp.notes[mus_ed_note_src[0]] = 0;
                mus_ed_selected[mus_ed_note_src[0]] = false;
                _lp.arps[mus_ed_note_src[0]] = 0;
                _lp.fx[mus_ed_note_src[0]] = 0;
                _lp.fxp[mus_ed_note_src[0]] = 0;
                _lp.fx_end[mus_ed_note_src[0]] = -1;
            }
            mus_ed_note_drag = false;
            mus_ed_note_glide = false;
            mus_ed_note_glide_end = [-1, -1];
        }
        if (mus_ed_painting && !mus_ed_note_drag && !mus_ed_note_glide && ui_held && _hr >= 0 && _hs >= 0)
        {
            if (_drums || !_on2) { music_ed_apply(_song, _li, _hs, _rv2, _drums, 1, _new_len); }
        }
        if (ui_rpressed && !mus_ed_note_drag)
        {
            mus_ed_rclear = true;
            mus_ed_tag = "musstepclr" + string(current_time);
        }
        if (mus_ed_rclear && !mus_ed_note_drag && ui_rheld && _lp.notes[_hs] > 0)
        {
            music_loop_edit_begin(_song, _li, mus_ed_tag);
            music_glide_unlink(_lp, _hs);
            _lp.notes[_hs] = 0;
            mus_ed_selected[_hs] = false;
            _lp.arps[_hs] = 0;
            _lp.fx[_hs] = 0;
            _lp.fxp[_hs] = 0;
            _lp.fx_end[_hs] = -1;
        }
    }
    if (_hr < 0 && mus_ed_note_drag && !ui_held)
    {
        mus_ed_note_drag = false;
        mus_ed_note_glide = false;
        mus_ed_note_glide_end = [-1, -1];
    }
    if (!ui_held) { mus_ed_painting = false; }
    if (!ui_rheld) { mus_ed_rclear = false; }

    // ---------- chord and tracker effect rows ----------
    var _effect_names = ["--", "Up", "Down", "Link", "Vib", "Vol"];
    var _effect_help = [
        "No tracker effect.",
        "ProTracker 1xx: bend pitch up. The low byte is the slide speed.",
        "ProTracker 2xx: bend pitch down. The low byte is the slide speed.",
        "Legacy slide from an older loop. Use the note's circle to connect bends now.",
        "ProTracker 4xy: vibrato. x is speed, y is depth.",
        "ProTracker Cxx: set volume from 0 (silent) to 64 (full). The lane's master volume also applies."
    ];
    var _fx_y = _gy2 + 2;
    if (!_drums) { _fx_y = _gy2 + 30; }
    var _fx_handle_hot = -1;
    var _fx_handle_distance = 7;
    for (var _handle_col = 0; _handle_col < _view_steps; _handle_col++)
    {
        var _handle_step = _handle_col * _step_stride;
        var _handle_kind = _lp.fx[_handle_step];
        if (_handle_kind != 1 && _handle_kind != 2 && _handle_kind != 4 && _handle_kind != 12) { continue; }
        var _distance = point_distance(ui_mx, ui_my, _sx + (_handle_col + 1) * _cw - 2, _fx_y + 12);
        if (_distance <= _fx_handle_distance)
        {
            _fx_handle_hot = _handle_step;
            _fx_handle_distance = _distance;
        }
    }
    if (ui_pressed && _fx_handle_hot >= 0 && !mus_ed_note_drag)
    {
        ui_take_click();
        mus_ed_fx_drag = true;
        mus_ed_fx_src = _fx_handle_hot;
        mus_ed_fx_step = _fx_handle_hot;
    }
    if (mus_ed_fx_drag)
    {
        var _end_col = clamp(floor((ui_mx - _sx) / _cw), 0, _view_steps - 1);
        mus_ed_fx_end = clamp((_end_col + 1) * _step_stride - 1, mus_ed_fx_src, MUS_STEPS - 1);
        if (!ui_held)
        {
            if (ui_hit(_sx - 7, _fx_y - 7, _sx2 + 7, _fx_y + 31) && _lp.fx[mus_ed_fx_src] > 0)
            {
                music_loop_edit_begin(_song, _li, "musfxlength" + string(current_time));
                _lp.fx_end[mus_ed_fx_src] = mus_ed_fx_end;
            }
            mus_ed_fx_drag = false;
        }
    }
    ui_text(_gx1 + 6, _fx_y + 12, "FX", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    // One text size for every effect label, small enough for the longest to fit
    draw_set_font(global.f_bold);
    var _fx_text_w = 1;
    for (var _fn = 0; _fn < array_length(_effect_names); _fn++) { _fx_text_w = max(_fx_text_w, ui_sw(_effect_names[_fn])); }
    var _fx_text_k = min(1, (_cw - 6) / _fx_text_w) / global.ui_scale;
    for (var fx_col = 0; fx_col < _view_steps; fx_col++)
    {
        var fx_step = fx_col * _step_stride;
        var _fx_x = _sx + fx_col * _cw + 1;
        var _fx_kind = _lp.fx[fx_step];
        var _active_step = music_fx_active_step(_lp, fx_step);
        var _display_kind = _fx_kind;
        if (_active_step >= 0) { _display_kind = _lp.fx[_active_step]; }
        var _fx_style = BTN_GHOST;
        if (_display_kind > 0) { _fx_style = BTN_ON; }
        var _fx_tip = "Step " + string(fx_step + 1) + " effect|" + _effect_help[music_fx_ui_index(_display_kind)] + " Click to cycle effect; right-click to clear. Drag the effect's circle to the right to extend it.";
        if (!mus_ed_fx_drag && ui_hit(_fx_x, _fx_y, _fx_x + _cw - 2, _fx_y + 24))
        {
            mus_ed_fx_step = fx_step;
            if (_active_step >= 0) { mus_ed_fx_step = _active_step; }
        }
        var _fx_pressed = ui_button("mus_fx_" + string(fx_step), _fx_x, _fx_y, _cw - 2, 24, "", _fx_tip, _fx_style);
        var _fx_text_col = global.TH.text;
        if (_fx_style == BTN_ON) { _fx_text_col = make_colour_rgb(16, 30, 28); }
        draw_set_font(global.f_bold);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_colour(_fx_text_col);
        draw_text_transformed(_fx_x + (_cw - 2) * 0.5, _fx_y + 12, _effect_names[music_fx_ui_index(_display_kind)], _fx_text_k, _fx_text_k, 0);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        if (_fx_pressed)
        {
            music_loop_edit_begin(_song, _li, "musfx" + string(current_time));
            mus_ed_fx_step = fx_step;
            _fx_kind = music_fx_next_kind(_fx_kind);
            _lp.fx[fx_step] = _fx_kind;
            if (_fx_kind == 1 || _fx_kind == 2) { _lp.fxp[fx_step] = 0x20; }
            if (_fx_kind == 4) { _lp.fxp[fx_step] = 0x47; }
            if (_fx_kind == 12) { _lp.fxp[fx_step] = 64; }
            if (_fx_kind == 0) { _lp.fxp[fx_step] = 0; _lp.fx_end[fx_step] = -1; }
        }
        if (!mus_ed_fx_drag && ui_rpressed && _active_step >= 0 && ui_hit(_fx_x, _fx_y, _fx_x + _cw - 2, _fx_y + 24))
        {
            music_loop_edit_begin(_song, _li, "musfxclear" + string(current_time));
            _lp.fx[_active_step] = 0;
            _lp.fxp[_active_step] = 0;
            _lp.fx_end[_active_step] = -1;
        }
    }
    // Draw span markers after the buttons, so later cells cannot cover them.
    for (var _node_cell = 0; _node_cell < _view_steps; _node_cell++)
    {
        var _node_step = _node_cell * _step_stride;
        var _node_kind = _lp.fx[_node_step];
        if (_node_kind == 1 || _node_kind == 2 || _node_kind == 4 || _node_kind == 12)
        {
            var _node_x = _sx + (_node_cell + 1) * _cw - 2;
            var _effect_end = _lp.fx_end[_node_step];
            if (mus_ed_fx_drag && mus_ed_fx_src == _node_step) { _effect_end = mus_ed_fx_end; }
            if (_effect_end >= _node_step)
            {
                var _end_x = _sx + ((_effect_end div _step_stride) + 1) * _cw - 2;
                draw_line_width_colour(_node_x, _fx_y + 23, _end_x, _fx_y + 23, 3, global.TH.accent, global.TH.accent);
                draw_circle_colour(_end_x, _fx_y + 23, 3, global.TH.accent, global.TH.accent, false);
            }
            var _radius = 4;
            var _node_col = global.TH.accent;
            if (_fx_handle_hot == _node_step || (mus_ed_fx_drag && mus_ed_fx_src == _node_step)) { _radius = 6; _node_col = c_white; }
            draw_circle_colour(_node_x, _fx_y + 12, _radius + 1, global.TH.panel_bot, global.TH.panel_bot, false);
            draw_circle_colour(_node_x, _fx_y + 12, _radius, _node_col, _node_col, false);
        }
    }
    if (mus_ed_fx_drag)
    {
        var _src_x = _sx + ((mus_ed_fx_src div _step_stride) + 1) * _cw - 2;
        draw_line_width_colour(_src_x, _fx_y + 12, clamp(ui_mx, _src_x, _sx2 - 2), _fx_y + 12, 2, global.TH.accent, global.TH.accent);
    }

    // ---------- selected effect parameter ----------
    var _param_y = _gy2 + 57;
    if (_drums) { _param_y = _gy2 + 29; }
    var _param_step = clamp(mus_ed_fx_step, 0, MUS_STEPS - 1);
    var _param_fx = _lp.fx[_param_step];
    if (_param_fx == 1 || _param_fx == 2 || _param_fx == 4 || _param_fx == 12)
    {
        var _param_w = 190;
        if (_param_fx == 4) { _param_w = 252; }
        var _param_cx = _sx + (_param_step div _step_stride) * _cw + _cw * 0.5;
        var _param_x = clamp(_param_cx - _param_w * 0.5, _ex1 + 12, _ex2 - 12 - _param_w);
        ui_text(_param_x, _param_y + 13, "Step " + string(_param_step + 1), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        if (_param_fx == 12)
        {
            var _volume = clamp(_lp.fxp[_param_step], 0, 64);
            ui_text(_param_x + 44, _param_y + 13, "Volume", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
            var _new_volume = ui_stepper("mus_fx_volume", _param_x + 94, _param_y, 94, _volume, 0, 64, "Pattern volume|0 is silent, 64 is full volume. The lane's master volume also applies. Extend the effect to carry this level across later steps.");
            if (_new_volume != _volume)
            {
                music_loop_edit_begin(_song, _li, "musfxparam" + string(_param_step));
                _lp.fxp[_param_step] = _new_volume;
            }
        }
        else if (_param_fx == 4)
        {
            var _vib_spd = (_lp.fxp[_param_step] >> 4) & 15;
            var _vib_dep = _lp.fxp[_param_step] & 15;
            if (_vib_spd < 1) { _vib_spd = 4; }
            if (_vib_dep < 1) { _vib_dep = 7; }
            ui_text(_param_x + 44, _param_y + 13, "Speed", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
            var _nvs = ui_stepper("mus_fx_vspeed", _param_x + 82, _param_y, 64, _vib_spd, 1, 15, "Vibrato speed|ProTracker 4xy: x controls how quickly the pitch oscillates.");
            ui_text(_param_x + 148, _param_y + 13, "Depth", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
            var _nvd = ui_stepper("mus_fx_vdepth", _param_x + 188, _param_y, 64, _vib_dep, 1, 15, "Vibrato depth|ProTracker 4xy: y controls how far the pitch bends.");
            if (_nvs != _vib_spd || _nvd != _vib_dep)
            {
                music_loop_edit_begin(_song, _li, "musfxparam" + string(_param_step));
                _lp.fxp[_param_step] = (_nvs << 4) | _nvd;
            }
        }
        else
        {
            var _speed = max(1, _lp.fxp[_param_step] & 255);
            ui_text(_param_x + 48, _param_y + 13, "Speed", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
            var _nsp = ui_stepper("mus_fx_speed", _param_x + 88, _param_y, 100, _speed, 1, 255, "Effect speed|ProTracker 1xx / 2xx: pitch movement per tick. Drag the effect's circle to extend its duration over later steps.");
            if (_nsp != _speed)
            {
                music_loop_edit_begin(_song, _li, "musfxparam" + string(_param_step));
                _lp.fxp[_param_step] = _nsp;
            }
        }
    }

    // ---------- chord row ----------
    if (!_drums)
    {
        var _cy = _gy2 + 6;
        ui_text(_gx1 + 6, _cy + 13, "Chord", global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        var _codes = global.MUS_CHORD_CODES;
        for (var chord_col = 0; chord_col < _view_steps; chord_col++)
        {
            var st2 = chord_col * _step_stride;
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
            var _bx = _sx + chord_col * _cw + 1;
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
/// _length: steps a new note lasts (0 = the default); existing notes keep theirs
function music_ed_apply(_song, _li, _st, _rv, _drums, _mode, _length)
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
        _lp.lengths[_st] = clamp(_length, 0, MUS_STEPS - _st);
        _lp.insts[_st] = _inst;
    }
    else
    {
        var _match = false;
        if (_drums) { _match = (_lp.notes[_st] > 0 && _lp.insts[_st] == _rv); }
        else { _match = (_lp.notes[_st] == _rv); }
        if (!_match) { return; }
        music_loop_edit_begin(_song, _li, mus_ed_tag);
        music_glide_unlink(_lp, _st);
        _lp.notes[_st] = 0;
        _lp.arps[_st] = 0;
        _lp.fx[_st] = 0;
        _lp.fxp[_st] = 0;
        _lp.fx_end[_st] = -1;
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
        var _nv2 = ui_dropdown("mus_lvl_0", _fx + 116, _y, 240, 30, _opts, _cur2, "Game music|The song that plays while your game runs. Switch on Levels on the Levels page to choose a song for each level.");
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
