/// ADAM - music (Phase 2 Track B): loop library, chip-synth instruments,
/// songs, song_to_modsong and the GML preview player.
///
/// Arrangement (song.arr, kind 0):
///   arr = { bars, lanes, loops }
///   bars  : song length in bars (1..128)
///   lanes : 4 arrays (one per Paula channel) of MUS_BAR_MAX entries,
///           each an index into arr.loops, or -1 for an empty bar
///   loops : the song's 1-bar loops = { name, cat, lib, inst, notes, insts, arps, fx, fxp, glide_to }
///           glide_to : explicit source -> later destination step, -1 = unlinked
///           cat   : 0 drums, 1 bass, 2 chords, 3 lead, 4 fx
///           lib   : built-in library loop it was copied from, -1 = edited (user loop)
///           inst  : instrument new notes use
///           notes : 16 steps, 0 = none, 1..36 = C-1..B-3 (ProTracker notes)
///           insts : 16 steps, instrument per step (0.. built-in, 100+k = Sound page sound k)
///           arps  : 16 steps, ProTracker arpeggio 0xy (chords); a chord keeps
///                   playing on the empty steps after its note
///
/// Mapping to ProTracker (song_to_modsong):
///   1 step = 1 row, speed 6 (F06), tempo = BPM (Fxx), so 4 rows = 1 beat.
///   A pattern holds up to 4 bars (64 rows). Patterns start again at the loop
///   bar so the song can jump back there; a shorter pattern ends with D00 and
///   the last one ends with Bxx (jump to the loop bar's order position, also
///   stored as modsong.restart). Identical patterns are shared.
///   Swing delays every odd step's note by EDx, x = swing% of a row's ticks.
///   Instruments become samples (31 max), played at F-2 for their own pitch.

#macro MUS_SONG_MAX 4
#macro MUS_LANES 4
#macro MUS_STEPS 32
#macro MUS_BAR_MAX 128
#macro MUS_LOOP_MAX 64
#macro MUS_RATE 22050
#macro MUS_INST_USER 100
#macro MUS_ROOT 18
#macro MUS_CAT_MINE 5

/// _f: Sound page low-pass [filt, fspeed, fdepth] ([0, 0, 0] = off)
function mus_inst_def(_name, _drum, _p, _hz, _vol, _f = [0, 0, 0])
{
    return { name : _name, drum : _drum, p : _p, hz : _hz, vol : _vol, f : _f };
}

function music_defs_init()
{
    // ProTracker periods (finetune 0); index 1 = C-1 ... 36 = B-3
    global.MUS_PERIODS = [0,
        856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
        428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
        214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113];
    global.MUS_NOTE_NAMES = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"];
    global.MUS_CAT_NAMES = ["Drums", "Bass", "Chords", "Lead", "FX", "Mine"];
    global.MUS_CAT_COLS = [make_colour_rgb(232, 96, 84), make_colour_rgb(240, 170, 60), make_colour_rgb(110, 196, 110),
                           make_colour_rgb(88, 158, 240), make_colour_rgb(186, 120, 232), make_colour_rgb(200, 206, 214)];
    global.MUS_CHORD_NAMES = ["-", "min", "maj", "7th", "sus", "oct"];
    global.MUS_CHORD_CODES = [0, 0x37, 0x47, 0x4a, 0x57, 0xc0];

    // Built-in chip-synth instruments: Sound page synth settings
    // [wave, pitch, slide, length, attack, decay, sustain, release],
    // optional low-pass [filt, fspeed, fdepth]. Rendered by music_synth_render.
    // hz > 0: a tuned instrument, F-2 plays this frequency (an F).
    global.MUS_INST = [
        mus_inst_def("Kick",        true,  [0, 12, -1, 7, 0, 4, 0, 3], 0, 64),
        mus_inst_def("Snare",       true,  [3, 70, -2, 5, 0, 4, 0, 4], 0, 56),
        mus_inst_def("Hi-hat",      true,  [3, 250, 0, 1, 0, 2, 0, 2], 0, 40),
        mus_inst_def("Open hat",    true,  [3, 250, 0, 6, 0, 6, 3, 5], 0, 36),
        mus_inst_def("Tom",         true,  [0, 20, -1, 8, 0, 5, 0, 4], 0, 60),
        mus_inst_def("Clap",        true,  [3, 110, 0, 3, 0, 3, 2, 4], 0, 52),
        mus_inst_def("Square bass", false, [2, 1, 0, 10, 0, 6, 6, 4], 87.307, 56, [11, 0, 0]),
        mus_inst_def("Saw bass",    false, [1, 1, 0, 10, 0, 5, 5, 4], 87.307, 56, [10, 0, 0]),
        mus_inst_def("Organ",       false, [2, 1, 0, 25, 1, 8, 10, 6], 349.228, 40, [14, 0, 0]),
        mus_inst_def("Soft pad",    false, [0, 1, 0, 40, 6, 9, 12, 8], 349.228, 44, [11, 2, 4]),
        mus_inst_def("Square lead", false, [2, 1, 0, 12, 0, 6, 9, 5], 698.456, 44),
        mus_inst_def("Saw lead",    false, [1, 1, 0, 12, 0, 6, 9, 5], 698.456, 44, [14, 0, 0]),
        mus_inst_def("Pluck",       false, [2, 1, 0, 4, 0, 4, 0, 4], 698.456, 48, [13, 0, 0]),
        mus_inst_def("Zap",         true,  [1, 140, -8, 14, 0, 7, 0, 4], 0, 44),
        mus_inst_def("Riser",       true,  [2, 20, 4, 30, 4, 9, 10, 5], 0, 40),
        mus_inst_def("Noise sweep", true,  [3, 30, 2, 40, 8, 10, 8, 8], 0, 36)
    ];
    global.MUS_DRUM_ROWS = [0, 1, 2, 3, 4, 5, 13, 14, 15, 100, 101, 102, 103, 104, 105, 106, 107];

    // ---------- the built-in loop library (deterministic data) ----------
    var _z = array_create(MUS_STEPS, 0);
    var _min = 0x37;
    var _maj = 0x47;
    global.MUS_LIB = [
        // drums: K kick, S snare, H hi-hat, O open hat, T tom, C clap
        mus_lib_drums("Four on the floor", "K.H.K.H.K.H.K.H."),
        mus_lib_drums("Rock beat",         "K.H.S.H.K.KHS.H."),
        mus_lib_drums("Breakbeat",         "K.H.S..KK.H.S.HC"),
        mus_lib_drums("Half time",         "K...H...S...H..."),
        mus_lib_drums("Disco claps",       "K.H.C.H.K.H.C.HO"),
        mus_lib_drums("Busy hats",         "HHHHHHHHHHHHHHO."),
        mus_lib_drums("Tom fill",          "T.T.TT.TS.S.SSSC"),
        // bass (C minor)
        mus_lib_tone("Root pulse",    1, 6, [13, 0, 0, 0, 13, 0, 0, 0, 13, 0, 0, 0, 13, 0, 0, 0], _z),
        mus_lib_tone("Octave bounce", 1, 7, [13, 0, 25, 0, 13, 0, 25, 0, 13, 0, 25, 0, 13, 0, 25, 0], _z),
        mus_lib_tone("Walking bass",  1, 6, [13, 0, 0, 0, 16, 0, 0, 0, 18, 0, 0, 0, 20, 0, 18, 0], _z),
        mus_lib_tone("Offbeat bass",  1, 6, [0, 0, 13, 0, 0, 0, 13, 0, 0, 0, 13, 0, 0, 0, 13, 0], _z),
        mus_lib_tone("Acid line",     1, 7, [13, 13, 25, 13, 0, 13, 23, 13, 13, 0, 25, 0, 16, 13, 18, 13], _z),
        mus_lib_tone("Driving eighths", 1, 7, [13, 0, 13, 0, 13, 0, 13, 0, 21, 0, 21, 0, 23, 0, 23, 0], _z),
        // chords (arpeggio chords)
        mus_lib_tone("Minor stabs",   2, 8, [13, 0, 0, 13, 0, 0, 13, 0, 0, 0, 13, 0, 0, 0, 0, 0],
                                            [_min, 0, 0, _min, 0, 0, _min, 0, 0, 0, _min, 0, 0, 0, 0, 0]),
        mus_lib_tone("Minor to major", 2, 9, [13, 0, 0, 0, 0, 0, 0, 0, 21, 0, 0, 0, 0, 0, 0, 0],
                                             [_min, 0, 0, 0, 0, 0, 0, 0, _maj, 0, 0, 0, 0, 0, 0, 0]),
        mus_lib_tone("Offbeat skank", 2, 8, [0, 0, 13, 0, 0, 0, 13, 0, 0, 0, 13, 0, 0, 0, 13, 0],
                                            [0, 0, _min, 0, 0, 0, _min, 0, 0, 0, _min, 0, 0, 0, _min, 0]),
        mus_lib_tone("Rising chords", 2, 9, [13, 0, 0, 0, 16, 0, 0, 0, 18, 0, 0, 0, 20, 0, 0, 0],
                                            [_min, 0, 0, 0, _maj, 0, 0, 0, _min, 0, 0, 0, _min, 0, 0, 0]),
        mus_lib_tone("Long minor",    2, 9, [13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                                            [_min, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        // lead
        mus_lib_tone("Arp up",        3, 12, [13, 16, 20, 25, 13, 16, 20, 25, 13, 16, 20, 25, 13, 16, 20, 25], _z),
        mus_lib_tone("Arp down",      3, 12, [25, 20, 16, 13, 25, 20, 16, 13, 25, 20, 16, 13, 25, 20, 16, 13], _z),
        mus_lib_tone("Hook one",      3, 10, [13, 0, 0, 16, 0, 0, 20, 0, 18, 0, 16, 0, 15, 0, 13, 0], _z),
        mus_lib_tone("Hook two",      3, 11, [25, 0, 23, 0, 20, 0, 0, 0, 18, 0, 20, 0, 23, 0, 0, 0], _z),
        mus_lib_tone("Long notes",    3, 10, [20, 0, 0, 0, 0, 0, 0, 0, 18, 0, 0, 0, 0, 0, 0, 0], _z),
        mus_lib_tone("Trill",         3, 12, [25, 27, 25, 27, 25, 27, 25, 27, 23, 25, 23, 25, 23, 25, 23, 25], _z),
        // fx
        mus_lib_tone("Zap hits",      4, 13, [18, 0, 0, 0, 0, 0, 0, 0, 18, 0, 0, 0, 0, 0, 0, 0], _z),
        mus_lib_tone("Laser rain",    4, 13, [25, 0, 0, 23, 0, 0, 20, 0, 0, 0, 18, 0, 0, 16, 0, 0], _z),
        mus_lib_tone("Riser",         4, 14, [13, 0, 0, 0, 18, 0, 0, 0, 20, 0, 0, 0, 25, 0, 0, 0], _z),
        mus_lib_tone("Noise swell",   4, 15, [18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], _z),
        mus_lib_tone("Blips",         4, 12, [0, 0, 32, 0, 0, 30, 0, 0, 0, 32, 0, 0, 28, 0, 0, 0], _z)
    ];
    for (var i = 0; i < array_length(global.MUS_LIB); i++) { global.MUS_LIB[i].lib = i; }
}

function loop_new(_name, _cat, _inst)
{
    return {
        name : _name,
        cat : _cat,
        lib : -1,
        group : -1,
        inst : _inst,
        notes : array_create(MUS_STEPS, 0),
        lengths : array_create(MUS_STEPS, 0),
        insts : array_create(MUS_STEPS, _inst),
        arps : array_create(MUS_STEPS, 0),
        fx : array_create(MUS_STEPS, 0),
        fxp : array_create(MUS_STEPS, 0),
        glide_to : array_create(MUS_STEPS, -1),
        fx_end : array_create(MUS_STEPS, -1)
    };
}

/// Drum loop from a 16-letter pattern: K kick, S snare, H hat, O open hat, T tom, C clap, . rest
function mus_lib_drums(_name, _pat)
{
    var _l = loop_new(_name, 0, 0);
    var _keys = "KSHOTC";
    for (var i = 0; i < string_length(_pat); i++)
    {
        var _k = string_pos(string_char_at(_pat, i + 1), _keys);
        if (_k > 0)
        {
            _l.notes[i * 2] = MUS_ROOT;
            _l.insts[i * 2] = _k - 1;
        }
    }
    return _l;
}

function mus_lib_tone(_name, _cat, _inst, _notes, _chords)
{
    var _l = loop_new(_name, _cat, _inst);
    for (var i = 0; i < array_length(_notes); i++)
    {
        _l.notes[i * 2] = _notes[i];
        if (i < array_length(_chords)) { _l.arps[i * 2] = _chords[i]; }
    }
    return _l;
}

function loop_copy(_l)
{
    var _c = loop_new(_l.name, _l.cat, _l.inst);
    _c.lib = _l.lib;
    _c.group = _l.group;
    array_copy(_c.notes, 0, _l.notes, 0, MUS_STEPS);
    array_copy(_c.lengths, 0, _l.lengths, 0, MUS_STEPS);
    array_copy(_c.insts, 0, _l.insts, 0, MUS_STEPS);
    array_copy(_c.arps, 0, _l.arps, 0, MUS_STEPS);
    array_copy(_c.fx, 0, _l.fx, 0, MUS_STEPS);
    array_copy(_c.fxp, 0, _l.fxp, 0, MUS_STEPS);
    array_copy(_c.glide_to, 0, _l.glide_to, 0, MUS_STEPS);
    array_copy(_c.fx_end, 0, _l.fx_end, 0, MUS_STEPS);
    return _c;
}

function music_inst_valid(_id)
{
    if (!is_numeric(_id)) { return false; }
    if (_id >= 0 && _id < array_length(global.MUS_INST)) { return true; }
    if (_id >= MUS_INST_USER && _id < MUS_INST_USER + SFX_MAX) { return true; }
    return false;
}

function music_inst_name(_id)
{
    if (_id >= MUS_INST_USER)
    {
        var _k = _id - MUS_INST_USER;
        if (_k >= 0 && _k < array_length(proj.sfx))
        {
            var _sg = proj.sfx[_k].group;
            if (_sg >= 0 && _sg < array_length(proj.sound_groups)) { return proj.sound_groups[_sg].name + " / " + string(_k + 1) + ": " + proj.sfx[_k].name; }
            return "Sound " + string(_k + 1) + ": " + proj.sfx[_k].name;
        }
        return "Sound";
    }
    if (_id >= 0 && _id < array_length(global.MUS_INST)) { return global.MUS_INST[_id].name; }
    return "?";
}

/// Every instrument id, in the order the menus show them
function music_inst_ids()
{
    var _out = [];
    for (var i = 0; i < array_length(global.MUS_INST); i++) { array_push(_out, i); }
    // the project's sounds, in Sound page order (by folder)
    var _sl = sfx_pick_list(false);
    for (var k = 0; k < array_length(_sl.ids); k++) { array_push(_out, MUS_INST_USER + _sl.ids[k]); }
    return _out;
}

function music_note_name(_n)
{
    if (_n < 1) { return "---"; }
    return global.MUS_NOTE_NAMES[(_n - 1) mod 12] + string(1 + (_n - 1) div 12);
}

/// The note whose period is nearest _period
function music_note_for_period(_period)
{
    var _best = MUS_ROOT;
    var _bd = 1000000;
    for (var n = 1; n <= 36; n++)
    {
        var _d = abs(ln(global.MUS_PERIODS[n] / max(1, _period)));
        if (_d < _bd)
        {
            _bd = _d;
            _best = n;
        }
    }
    return _best;
}

/// Song data ----------------------------------------------------------------

function arr_new()
{
    var _a = { bars : 8, lanes : [], loops : [], loop_groups : [], volumes : [64, 64, 64, 64] };
    for (var l = 0; l < MUS_LANES; l++) { array_push(_a.lanes, array_create(MUS_BAR_MAX, -1)); }
    return _a;
}

function song_new(_name)
{
    var _s = { name : _name, kind : 0, bpm : 125, speed : 6, swing : 0, loop_bar : 0, arr : arr_new() };
    _s[$ "mod"] = undefined;
    return _s;
}

function loop_from_loaded(_raw)
{
    var _l = loop_new("Loop", 0, 0);
    if (!is_struct(_raw)) { return _l; }
    if (is_string(_raw[$ "name"])) { _l.name = string_copy(_raw.name, 1, 24); }
    if (is_numeric(_raw[$ "cat"])) { _l.cat = clamp(floor(_raw.cat), 0, 4); }
    if (is_numeric(_raw[$ "lib"])) { _l.lib = clamp(floor(_raw.lib), -1, array_length(global.MUS_LIB) - 1); }
    if (is_numeric(_raw[$ "group"])) { _l.group = clamp(floor(_raw.group), -1, MUS_LOOP_MAX - 1); }
    if (music_inst_valid(_raw[$ "inst"])) { _l.inst = floor(_raw.inst); }
    var _n = _raw[$ "notes"];
    var _i = _raw[$ "insts"];
    var _a = _raw[$ "arps"];
    var _fx = _raw[$ "fx"];
    var _fxp = _raw[$ "fxp"];
    var _links = _raw[$ "glide_to"];
    var _ends = _raw[$ "fx_end"];
    var _lengths = _raw[$ "lengths"];
    var _legacy = is_array(_n) && array_length(_n) <= 16;
    for (var s = 0; s < MUS_STEPS; s++)
    {
        _l.insts[s] = _l.inst;
        if (_legacy && (s mod 2) == 1) { continue; }
        var _src_step = s;
        if (_legacy) { _src_step = s div 2; }
        if (is_array(_n) && _src_step < array_length(_n) && is_numeric(_n[_src_step])) { _l.notes[s] = clamp(floor(_n[_src_step]), 0, 36); }
        if (is_array(_i) && _src_step < array_length(_i) && music_inst_valid(_i[_src_step])) { _l.insts[s] = floor(_i[_src_step]); }
        if (is_array(_a) && _src_step < array_length(_a) && is_numeric(_a[_src_step])) { _l.arps[s] = clamp(floor(_a[_src_step]), 0, 255); }
        if (is_array(_fx) && _src_step < array_length(_fx) && is_numeric(_fx[_src_step]))
        {
            _l.fx[s] = clamp(floor(_fx[_src_step]), 0, 4);
            if (_fx[_src_step] == 12) { _l.fx[s] = 12; }
        }
        if (is_array(_fxp) && _src_step < array_length(_fxp) && is_numeric(_fxp[_src_step])) { _l.fxp[s] = clamp(floor(_fxp[_src_step]), 0, 255); }
        if (_l.fx[s] == 12) { _l.fxp[s] = clamp(_l.fxp[s], 0, 64); }
        if (is_array(_links) && _src_step < array_length(_links) && is_numeric(_links[_src_step]))
        {
            var _target = floor(_links[_src_step]);
            if (_legacy) { _target *= 2; }
            if (_target > s && _target < MUS_STEPS) { _l.glide_to[s] = _target; }
        }
        if (is_array(_ends) && _src_step < array_length(_ends) && is_numeric(_ends[_src_step]))
        {
            var _end = floor(_ends[_src_step]);
            if (_legacy) { _end = _end * 2 + 1; }
            if (_end >= s && _end < MUS_STEPS) { _l.fx_end[s] = _end; }
        }
        if (is_array(_lengths) && _src_step < array_length(_lengths) && is_numeric(_lengths[_src_step])) { _l.lengths[s] = clamp(floor(_lengths[_src_step]), 0, MUS_STEPS - s); }
    }
    return _l;
}

/// Explicit connections are independent of manually selected tracker effects.
function music_note_length(_lp, _step)
{
    var _length = _lp.lengths[_step];
    if (_length <= 0) { _length = 2; }
    return min(_length, MUS_STEPS - _step);
}

function music_note_row(_lp, _step, _drums)
{
    if (!_drums) { return 36 - _lp.notes[_step]; }
    for (var _row = 0; _row < array_length(global.MUS_DRUM_ROWS); _row++)
    {
        if (global.MUS_DRUM_ROWS[_row] == _lp.insts[_step]) { return _row; }
    }
    return -1;
}

/// Select by intersection with the visible note body, including partial touches.
function music_notes_in_box(_lp, _drums, _stride, _cw, _rh, _box)
{
    var _selected = array_create(MUS_STEPS, false);
    var _left = min(_box[0], _box[2]);
    var _right = max(_box[0], _box[2]);
    var _top = min(_box[1], _box[3]);
    var _bottom = max(_box[1], _box[3]);
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        if (_lp.notes[_step] <= 0) { continue; }
        var _row = music_note_row(_lp, _step, _drums);
        if (_row < 0) { continue; }
        var _px = _step * _cw;
        var _py = _row * _rh;
        _selected[_step] = (_left <= _px + music_note_length(_lp, _step) * _cw - 2 && _right >= _px + 2 && _top <= _py + _rh - 2 && _bottom >= _py + 2);
    }
    return _selected;
}

function music_notes_copy(_lp, _selected, _drums)
{
    var _clip = { notes : [], drums : _drums };
    var _first = MUS_STEPS;
    var _top = 1000;
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        if (!_selected[_step] || _lp.notes[_step] <= 0) { continue; }
        var _row = music_note_row(_lp, _step, _drums);
        if (_row < 0) { continue; }
        _first = min(_first, _step);
        _top = min(_top, _row);
    }
    if (_first == MUS_STEPS) { return _clip; }
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        if (!_selected[_step] || _lp.notes[_step] <= 0) { continue; }
        var _row = music_note_row(_lp, _step, _drums);
        if (_row < 0) { continue; }
        var _link = -1;
        if (music_glide_valid(_lp, _step) && _selected[_lp.glide_to[_step]]) { _link = _lp.glide_to[_step] - _first; }
        var _end = -1;
        if (_lp.fx_end[_step] >= _step) { _end = _lp.fx_end[_step] - _first; }
        array_push(_clip.notes, {
            step : _step - _first, row : _row - _top, pitch : _lp.notes[_step], length : _lp.lengths[_step],
            inst : _lp.insts[_step], arp : _lp.arps[_step], fx : _lp.fx[_step],
            fxp : _lp.fxp[_step], fx_end : _end, glide_to : _link
        });
    }
    return _clip;
}

/// A dry run gives the UI an undo point only when at least one note fits.
function music_notes_paste(_lp, _clip, _step, _row, _drums, _apply = true)
{
    var _result = { count : 0, selected : array_create(MUS_STEPS, false) };
    if (_clip.drums != _drums) { return _result; }
    var _max_row = 36;
    if (_drums) { _max_row = array_length(global.MUS_DRUM_ROWS); }
    for (var _i = 0; _i < array_length(_clip.notes); _i++)
    {
        var _note = _clip.notes[_i];
        var _to = _step + _note.step;
        var _to_row = _row + _note.row;
        if (_to < 0 || _to >= MUS_STEPS || _to_row < 0 || _to_row >= _max_row) { continue; }
        _result.selected[_to] = true;
        _result.count += 1;
        if (_apply) { music_glide_unlink(_lp, _to); }
    }
    if (!_apply) { return _result; }
    for (var _i = 0; _i < array_length(_clip.notes); _i++)
    {
        var _note = _clip.notes[_i];
        var _to = _step + _note.step;
        if (_to < 0 || _to >= MUS_STEPS || !_result.selected[_to]) { continue; }
        var _pitch = 36 - (_row + _note.row);
        var _inst = _note.inst;
        if (_drums) { _pitch = _note.pitch; _inst = global.MUS_DRUM_ROWS[_row + _note.row]; }
        _lp.notes[_to] = _pitch;
        _lp.lengths[_to] = min(_note.length, MUS_STEPS - _to);
        _lp.insts[_to] = _inst;
        _lp.arps[_to] = _note.arp;
        _lp.fx[_to] = _note.fx;
        _lp.fxp[_to] = _note.fxp;
        _lp.fx_end[_to] = -1;
        if (_note.fx_end >= _note.step) { _lp.fx_end[_to] = min(MUS_STEPS - 1, _step + _note.fx_end); }
    }
    for (var _i = 0; _i < array_length(_clip.notes); _i++)
    {
        var _note = _clip.notes[_i];
        var _from = _step + _note.step;
        var _to = _step + _note.glide_to;
        if (_note.glide_to < 0 || _from < 0 || _from >= MUS_STEPS || _to < 0 || _to >= MUS_STEPS) { continue; }
        if (_result.selected[_from] && _result.selected[_to]) { _lp.glide_to[_from] = _to; }
    }
    return _result;
}

function music_notes_clipboard_selftest()
{
    var _ok = true;
    var _loop = loop_new("Copy test", 3, 10);
    _loop.notes[0] = 18;
    _loop.notes[4] = 22;
    _loop.glide_to[0] = 4;
    _loop.fx[0] = 4;
    _loop.fxp[0] = 0x47;
    _loop.fx_end[0] = 6;
    var _touch = music_notes_in_box(_loop, false, 2, 20, 16, [17, 291, 19, 292]);
    if (!_touch[0] || _touch[4]) { _ok = false; }
    var _selected = array_create(MUS_STEPS, false);
    _selected[0] = true;
    _selected[4] = true;
    var _clip = music_notes_copy(_loop, _selected, false);
    var _remember = json_stringify(_clip);
    _loop.notes[2] = 20;
    _loop.notes[8] = 17;
    _loop.notes[10] = 16;
    _loop.glide_to[2] = 8;
    var _preview = music_notes_paste(_loop, _clip, 8, 10, false, false);
    if (_preview.count != 2 || _loop.notes[8] != 17) { _ok = false; }
    var _pasted = music_notes_paste(_loop, _clip, 8, 10, false);
    if (_pasted.count != 2 || _loop.notes[8] != 22 || _loop.notes[12] != 26 || _loop.notes[10] != 16) { _ok = false; }
    if (_loop.glide_to[8] != 12 || _loop.glide_to[2] != -1 || _loop.fx_end[8] != 14 || _loop.fxp[8] != 0x47) { _ok = false; }
    music_notes_paste(_loop, _clip, 16, 12, false);
    if (_loop.notes[16] != 20 || _loop.notes[20] != 24 || _loop.glide_to[16] != 20 || json_stringify(_clip) != _remember) { _ok = false; }
    var _edge = music_notes_paste(_loop, _clip, 30, 10, false);
    if (_edge.count != 1 || _loop.glide_to[30] != -1) { _ok = false; }
    if (music_notes_paste(_loop, _clip, 0, 0, true).count != 0) { _ok = false; }
    var _drag = loop_new("Drag test", 3, 10);
    _drag.notes[0] = 18;
    _drag.fx[0] = 4;
    _drag.fxp[0] = 0x47;
    _drag.fx_end[0] = 4;
    _drag.notes[8] = 24;
    _drag.notes[12] = 26;
    _drag.glide_to[8] = 12;
    if (!music_note_duplicate(_drag, 0, 8, 20)) { _ok = false; }
    if (_drag.notes[0] != 18 || _drag.notes[8] != 20 || _drag.fx[8] != 4 || _drag.fxp[8] != 0x47 || _drag.fx_end[8] != 12 || _drag.glide_to[8] != -1) { _ok = false; }
    if (!music_note_move(_drag, 8, 12, 22)) { _ok = false; }
    if (_drag.notes[8] != 0 || _drag.notes[12] != 22 || _drag.fx[12] != 4 || _drag.fxp[12] != 0x47 || _drag.notes[0] != 18) { _ok = false; }
    var _group = loop_new("Group move", 3, 10);
    _group.notes[0] = 18;
    _group.lengths[0] = 3;
    _group.notes[4] = 22;
    _group.notes[8] = 30;
    _group.fx[0] = 4;
    _group.fxp[0] = 0x47;
    _group.fx_end[0] = 6;
    _group.glide_to[0] = 4;
    var _group_selection = array_create(MUS_STEPS, false);
    _group_selection[0] = true;
    _group_selection[4] = true;
    _group_selection = music_notes_move(_group, _group_selection, 4, -2, false);
    if (_group.notes[0] != 0 || _group.notes[4] != 20 || _group.notes[8] != 24 || !_group_selection[4] || !_group_selection[8]) { _ok = false; }
    if (_group.glide_to[4] != 8 || _group.fx[4] != 4 || _group.fxp[4] != 0x47 || _group.fx_end[4] != 10) { _ok = false; }
    if (_group.lengths[4] != 3 || loop_from_loaded(json_parse(json_stringify(_group))).lengths[4] != 3) { _ok = false; }
    var _group_before = json_stringify(_group);
    if (!is_undefined(music_notes_move(_group, _group_selection, 30, 0, false)) || json_stringify(_group) != _group_before) { _ok = false; }
    if (!is_undefined(music_notes_move(_group, _group_selection, 0, -20, false)) || json_stringify(_group) != _group_before) { _ok = false; }
    var _short = loop_new("Length test", 3, 10);
    _short.notes[1] = 18;
    _short.lengths[1] = 1;
    var _length_selected = array_create(MUS_STEPS, false);
    _length_selected[1] = true;
    var _length_clip = music_notes_copy(_short, _length_selected, false);
    music_notes_paste(_short, _length_clip, 5, 18, false);
    if (_short.lengths[5] != 1 || music_note_length(_short, 1) != 1 || music_note_length(_short, 0) != 2) { _ok = false; }
    var _length_warnings = mus_warnings;
    var _length_mod = song_to_modsong(music_loop_song(_short, 125, 0));
    var _cut_cell = _length_mod.patterns[_length_mod.order[0]][2][0];
    if (_cut_cell.effect != 12 || _cut_cell.param != 0) { _ok = false; }
    var _length_bytes = mod_write(_length_mod);
    var _length_roundtrip = mod_parse(_length_bytes);
    if (is_undefined(_length_roundtrip.song) || _length_roundtrip.song.patterns[0][2][0].effect != 12) { _ok = false; }
    buffer_delete(_length_bytes);
    mus_warnings = _length_warnings;
    if (_ok) { show_debug_message("ADAM note selection / clipboard self-test: PASS"); }
    else { show_debug_message("ADAM note selection / clipboard self-test: FAIL"); }
}

function music_fx_active_step(_lp, _step)
{
    var _active = -1;
    for (var _source = 0; _source <= _step; _source++)
    {
        if (_lp.fx[_source] > 0 && (_source == _step || _lp.fx_end[_source] >= _step)) { _active = _source; }
    }
    return _active;
}

function music_fx_next_kind(_kind)
{
    if (_kind == 0) { return 1; }
    if (_kind == 1) { return 2; }
    if (_kind == 2 || _kind == 3) { return 4; }
    if (_kind == 4) { return 12; }
    return 0;
}

function music_fx_ui_index(_kind)
{
    if (_kind == 12) { return 5; }
    return clamp(_kind, 0, 4);
}

function music_library_effect_selftest()
{
    var _ok = true;
    var _warnings = mus_warnings;
    var _song = song_new("Library test");
    _song.arr.bars = 1;
    _song.arr.loop_groups = [{ name : "Leads", open : false }, { name : "Rhythm", open : true }];
    var _loop = loop_new("Lead", 3, 10);
    _loop.group = 0;
    _loop.notes[0] = MUS_ROOT;
    _loop.fx[0] = 4;
    _loop.fxp[0] = 0x47;
    _loop.fx_end[0] = 5;
    array_push(_song.arr.loops, _loop);
    array_push(_song.arr.loops, loop_new("Loose", 1, 6));
    _song.arr.lanes[0][0] = 0;
    if (array_length(music_loop_group_rows(_song, true)) != 4) { _ok = false; }
    _song.arr.loop_groups[0].open = true;
    if (array_length(music_loop_group_rows(_song, true)) != 5) { _ok = false; }
    var _loaded = song_from_loaded(json_parse(json_stringify(_song)));
    if (_loaded.arr.loop_groups[0].name != "Leads" || !_loaded.arr.loop_groups[0].open || _loaded.arr.loops[0].group != 0 || _loaded.arr.loops[0].fx_end[0] != 5) { _ok = false; }
    if (loop_copy(_loop).group != 0 || loop_copy(_loop).fx_end[0] != 5) { _ok = false; }
    music_loop_group_assign(_loaded, [1, 0], 1);
    if (_loaded.arr.loops[0].group != 1 || _loaded.arr.lanes[0][0] != 0) { _ok = false; }
    var _copy = music_loop_group_assign(_loaded, [0, 0], 1);
    if (_copy != 2 || _loaded.arr.loops[_copy].lib != -1 || _loaded.arr.loops[_copy].group != 1 || global.MUS_LIB[0].lib != 0) { _ok = false; }
    var _ms = song_to_modsong(_song);
    var _pattern = _ms.patterns[_ms.order[0]];
    for (var _step = 0; _step <= 5; _step++)
    {
        if (_pattern[_step][0].effect != 4 || _pattern[_step][0].param != 0x47) { _ok = false; }
    }
    if (_pattern[6][0].effect != 0 || music_fx_active_step(_loop, 6) != -1) { _ok = false; }
    var _bytes = mod_write(_ms);
    var _roundtrip = mod_parse(_bytes);
    if (is_undefined(_roundtrip.song)) { _ok = false; }
    else
    {
        var _cell = _roundtrip.song.patterns[_roundtrip.song.order[0]][5][0];
        if (_cell.effect != 4 || _cell.param != 0x47) { _ok = false; }
    }
    buffer_delete(_bytes);
    _loop.fx[0] = 2;
    _loop.fxp[0] = 3;
    _ms = song_to_modsong(_song);
    if (_ms.patterns[_ms.order[0]][5][0].effect != 2) { _ok = false; }
    if (music_fx_next_kind(2) != 4 || music_fx_next_kind(4) != 12 || music_fx_next_kind(12) != 0) { _ok = false; }
    music_note_move(_loop, 0, 2, MUS_ROOT);
    if (_loop.fx_end[2] != 7 || _loop.fx_end[0] != -1) { _ok = false; }
    mus_warnings = _warnings;
    if (_ok) { show_debug_message("ADAM loop groups / effect spans self-test: PASS"); }
    else { show_debug_message("ADAM loop groups / effect spans self-test: FAIL"); }
}

/// Headers and visible loops share one scrolling list; closing a group removes its rows.
function music_loop_group_rows(_song, _ungrouped_open)
{
    var _rows = [];
    var _ng = array_length(_song.arr.loop_groups);
    for (var _group = -1; _group < _ng; _group++)
    {
        var _count = 0;
        for (var _li = 0; _li < array_length(_song.arr.loops); _li++)
        {
            if (_song.arr.loops[_li].lib < 0 && _song.arr.loops[_li].group == _group) { _count += 1; }
        }
        var _open = _ungrouped_open;
        if (_group >= 0) { _open = _song.arr.loop_groups[_group].open; }
        if (_ng > 0) { array_push(_rows, { kind : 1, group : _group, count : _count, h : 36, it : [-1, -1] }); }
        else { _open = true; }
        if (!_open) { continue; }
        for (var _li = 0; _li < array_length(_song.arr.loops); _li++)
        {
            if (_song.arr.loops[_li].lib < 0 && _song.arr.loops[_li].group == _group)
            {
                array_push(_rows, { kind : 0, group : _group, count : 0, h : 44, it : [1, _li] });
            }
        }
    }
    return _rows;
}

/// Library presets become personal copies; existing personal loops keep their indices.
function music_loop_group_assign(_song, _src, _group)
{
    if (_group < -1 || _group >= array_length(_song.arr.loop_groups)) { return -1; }
    var _li = _src[1];
    if (_src[0] == 0)
    {
        if (_li < 0 || _li >= array_length(global.MUS_LIB) || array_length(_song.arr.loops) >= MUS_LOOP_MAX) { return -1; }
        var _copy = loop_copy(global.MUS_LIB[_li]);
        _copy.lib = -1;
        _li = array_length(_song.arr.loops);
        array_push(_song.arr.loops, _copy);
    }
    if (_li < 0 || _li >= array_length(_song.arr.loops)) { return -1; }
    _song.arr.loops[_li].group = _group;
    if (_group >= 0) { _song.arr.loop_groups[_group].open = true; }
    return _li;
}

function music_glide_valid(_lp, _source)
{
    var _target = _lp.glide_to[_source];
    if (_target <= _source || _target >= MUS_STEPS || _lp.notes[_source] <= 0) { return false; }
    return (_lp.notes[_target] > 0);
}

/// One Paula lane carries one bend at a time; endpoints may chain connections.
function music_glide_connect(_lp, _source, _target)
{
    for (var _other = 0; _other < MUS_STEPS; _other++)
    {
        if (music_glide_valid(_lp, _other) && _other < _target && _lp.glide_to[_other] > _source)
        {
            _lp.glide_to[_other] = -1;
        }
    }
    _lp.glide_to[_source] = _target;
}

function music_glide_unlink(_lp, _step)
{
    _lp.glide_to[_step] = -1;
    for (var _source = 0; _source < MUS_STEPS; _source++)
    {
        if (_lp.glide_to[_source] == _step) { _lp.glide_to[_source] = -1; }
    }
}

/// Moving a connected endpoint keeps its identity and its forward timing.
function music_note_can_move(_lp, _from, _to)
{
    if (_from == _to) { return true; }
    if (_lp.glide_to[_from] >= 0 && _to >= _lp.glide_to[_from]) { return false; }
    for (var _source = 0; _source < MUS_STEPS; _source++)
    {
        if (_lp.glide_to[_source] == _from && _to <= _source) { return false; }
    }
    return true;
}

function music_note_move(_lp, _from, _to, _pitch)
{
    if (!music_note_can_move(_lp, _from, _to)) { return false; }
    if (_from != _to)
    {
        music_glide_unlink(_lp, _to);
        _lp.notes[_to] = _lp.notes[_from];
        _lp.lengths[_to] = min(_lp.lengths[_from], MUS_STEPS - _to);
        _lp.insts[_to] = _lp.insts[_from];
        _lp.fx[_to] = _lp.fx[_from];
        _lp.fxp[_to] = _lp.fxp[_from];
        _lp.arps[_to] = _lp.arps[_from];
        _lp.glide_to[_to] = _lp.glide_to[_from];
        _lp.fx_end[_to] = -1;
        if (_lp.fx_end[_from] >= _from) { _lp.fx_end[_to] = clamp(_lp.fx_end[_from] + _to - _from, _to, MUS_STEPS - 1); }
        _lp.notes[_from] = 0;
        _lp.lengths[_from] = 0;
        _lp.insts[_from] = _lp.inst;
        _lp.fx[_from] = 0;
        _lp.fxp[_from] = 0;
        _lp.arps[_from] = 0;
        _lp.glide_to[_from] = -1;
        _lp.fx_end[_from] = -1;
        for (var _source = 0; _source < MUS_STEPS; _source++)
        {
            if (_lp.glide_to[_source] == _from) { _lp.glide_to[_source] = _to; }
        }
    }
    _lp.notes[_to] = _pitch;
    return true;
}

/// Move a selection atomically so overlapping destinations keep every selected note.
function music_notes_move(_lp, _selected, _steps, _rows, _drums, _apply = true)
{
    var _result = array_create(MUS_STEPS, false);
    var _max_row = 36;
    if (_drums) { _max_row = array_length(global.MUS_DRUM_ROWS); }
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        if (!_selected[_step] || _lp.notes[_step] <= 0) { continue; }
        var _to = _step + _steps;
        var _row = music_note_row(_lp, _step, _drums) + _rows;
        if (_to < 0 || _to >= MUS_STEPS || _row < 0 || _row >= _max_row) { return undefined; }
        _result[_to] = true;
    }
    if (!_apply) { return _result; }
    var _before = loop_copy(_lp);
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        if (!_selected[_step] && !_result[_step]) { continue; }
        _lp.notes[_step] = 0;
        _lp.insts[_step] = _lp.inst;
        _lp.fx[_step] = 0;
        _lp.fxp[_step] = 0;
        _lp.arps[_step] = 0;
        _lp.fx_end[_step] = -1;
        _lp.glide_to[_step] = -1;
    }
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        if (!_selected[_step] || _before.notes[_step] <= 0) { continue; }
        var _to = _step + _steps;
        _lp.notes[_to] = _before.notes[_step] - _rows;
        _lp.lengths[_to] = min(_before.lengths[_step], MUS_STEPS - _to);
        _lp.insts[_to] = _before.insts[_step];
        if (_drums)
        {
            _lp.notes[_to] = _before.notes[_step];
            _lp.insts[_to] = global.MUS_DRUM_ROWS[music_note_row(_before, _step, true) + _rows];
        }
        _lp.fx[_to] = _before.fx[_step];
        _lp.fxp[_to] = _before.fxp[_step];
        _lp.arps[_to] = _before.arps[_step];
        if (_before.fx_end[_step] >= _step) { _lp.fx_end[_to] = clamp(_before.fx_end[_step] + _steps, _to, MUS_STEPS - 1); }
    }
    _lp.glide_to = array_create(MUS_STEPS, -1);
    for (var _step = 0; _step < MUS_STEPS; _step++)
    {
        var _target = _before.glide_to[_step];
        if (_target < 0) { continue; }
        if ((!_selected[_step] && _result[_step]) || (!_selected[_target] && _result[_target])) { continue; }
        var _from = _step;
        if (_selected[_step]) { _from += _steps; }
        if (_selected[_target]) { _target += _steps; }
        if (_target > _from && _lp.notes[_from] > 0 && _lp.notes[_target] > 0) { _lp.glide_to[_from] = _target; }
    }
    return _result;
}

function music_note_duplicate(_lp, _from, _to, _pitch)
{
    if (_from == _to) { return false; }
    music_glide_unlink(_lp, _to);
    _lp.notes[_to] = _pitch;
    _lp.lengths[_to] = min(_lp.lengths[_from], MUS_STEPS - _to);
    _lp.insts[_to] = _lp.insts[_from];
    _lp.fx[_to] = _lp.fx[_from];
    _lp.fxp[_to] = _lp.fxp[_from];
    _lp.arps[_to] = _lp.arps[_from];
    _lp.fx_end[_to] = -1;
    if (_lp.fx_end[_from] >= _from) { _lp.fx_end[_to] = clamp(_lp.fx_end[_from] + _to - _from, _to, MUS_STEPS - 1); }
    _lp.glide_to[_to] = -1;
    if (_lp.glide_to[_from] > _to) { _lp.glide_to[_to] = _lp.glide_to[_from]; }
    return true;
}

/// Checks connection persistence and the actual MOD rows used by preview/export.
function music_glide_selftest()
{
    var _ok = true;
    var _saved_warnings = mus_warnings;
    var _loop = loop_new("Glide test", 1, 6);
    _loop.notes[0] = 18;
    _loop.notes[8] = 26;
    var _song = music_loop_song(_loop, 125, 0);
    var _plain = song_to_modsong(_song);
    if (_plain.patterns[_plain.order[0]][0][0].effect != 0) { _ok = false; }
    _loop.fx[8] = 3;
    if (music_glide_valid(_loop, 0)) { _ok = false; }
    _loop.fx[8] = 0;
    _loop.glide_to[0] = 8;
    var _loaded = loop_from_loaded(json_parse(json_stringify(_loop)));
    if (!music_glide_valid(_loaded, 0) || loop_copy(_loaded).glide_to[0] != 8) { _ok = false; }
    // Placing a note inside a connection must not erase it or restart the bend.
    _loaded.notes[4] = 30;
    if (!music_glide_valid(_loaded, 0)) { _ok = false; }
    _song = music_loop_song(_loaded, 125, 0);
    var _linked = song_to_modsong(_song);
    var _pattern = _linked.patterns[_linked.order[0]];
    var _slide = 0;
    for (var _row = 0; _row < 8; _row++)
    {
        var _cell = _pattern[_row][0];
        if (_cell.effect != 1) { _ok = false; }
        if (_row > 0 && (_cell.note != 0 || _cell.sample != 0)) { _ok = false; }
        _slide += _cell.param * (floor(_song.speed * 0.5) - 1);
    }
    if (abs(_slide - (global.MUS_PERIODS[18] - global.MUS_PERIODS[26])) > 1) { _ok = false; }
    if (_pattern[8][0].note != 26 || _pattern[8][0].sample != 0 || _pattern[8][0].effect != 3) { _ok = false; }
    // The endpoint updates the pitch without restarting the source sample.
    var _player = music_player_new(_linked, true, 0, 8);
    _player.ch[0].smp = _pattern[0][0].sample;
    _player.ch[0].base = global.MUS_PERIODS[18] - _slide;
    _player.ch[0].pos = 123;
    _player.ch[0].vol = 37;
    music_player_row(_player);
    if (_player.ch[0].pos != 123 || _player.ch[0].vol != 37 || _player.ch[0].smp != _pattern[0][0].sample) { _ok = false; }
    _player.tick = 1;
    music_player_effects(_player);
    if (_player.ch[0].period != global.MUS_PERIODS[26]) { _ok = false; }
    var _bytes = mod_write(_linked);
    var _parsed = mod_parse(_bytes);
    if (is_undefined(_parsed.song)) { _ok = false; }
    else if (_parsed.song.patterns[_parsed.song.order[0]][1][0].effect != 1) { _ok = false; }
    buffer_delete(_bytes);
    if (_loaded.notes[4] != 30) { _ok = false; }
    // Retune both endpoints, then move each in time: the same link must follow.
    music_note_move(_loaded, 0, 0, 22);
    music_note_move(_loaded, 8, 8, 14);
    if (!music_glide_valid(_loaded, 0) || _loaded.glide_to[0] != 8) { _ok = false; }
    var _retuned = song_to_modsong(music_loop_song(_loaded, 125, 0));
    var _retuned_pattern = _retuned.patterns[_retuned.order[0]];
    if (_retuned_pattern[0][0].note != 22 || _retuned_pattern[0][0].effect != 2) { _ok = false; }
    if (_retuned_pattern[8][0].note != 14 || _retuned_pattern[8][0].sample != 0 || _retuned_pattern[8][0].effect != 3) { _ok = false; }
    music_note_move(_loaded, 0, 2, 22);
    music_note_move(_loaded, 8, 10, 14);
    if (!music_glide_valid(_loaded, 2) || _loaded.glide_to[2] != 10 || _loaded.glide_to[0] != -1) { _ok = false; }
    if (music_note_move(_loaded, 2, 12, 22) || _loaded.glide_to[2] != 10) { _ok = false; }
    music_note_move(_loaded, 10, 8, 14);
    music_note_move(_loaded, 2, 0, 22);
    music_glide_unlink(_loaded, 8);
    if (music_glide_valid(_loaded, 0) || _loaded.glide_to[0] != -1) { _ok = false; }
    mus_warnings = _saved_warnings;
    if (_ok) { show_debug_message("ADAM glide self-test: PASS"); }
    else { show_debug_message("ADAM glide self-test: FAIL"); }
}

function song_from_loaded(_raw)
{
    var _s = song_new("Song");
    if (!is_struct(_raw)) { return _s; }
    if (is_string(_raw[$ "name"])) { _s.name = string_copy(_raw.name, 1, 20); }
    if (is_numeric(_raw[$ "kind"])) { _s.kind = clamp(floor(_raw.kind), 0, 1); }
    if (is_numeric(_raw[$ "bpm"])) { _s.bpm = clamp(floor(_raw.bpm), 32, 255); }
    if (is_numeric(_raw[$ "speed"])) { _s.speed = clamp(floor(_raw.speed), 1, 31); }
    if (is_numeric(_raw[$ "swing"])) { _s.swing = clamp(floor(_raw.swing), 0, 50); }
    if (is_numeric(_raw[$ "loop_bar"])) { _s.loop_bar = clamp(floor(_raw.loop_bar), 0, MUS_BAR_MAX - 1); }
    var _ra = _raw[$ "arr"];
    if (is_struct(_ra))
    {
        var _volumes = _ra[$ "volumes"];
        if (is_array(_volumes))
        {
            for (var _lane = 0; _lane < min(MUS_LANES, array_length(_volumes)); _lane++)
            {
                if (is_numeric(_volumes[_lane])) { _s.arr.volumes[_lane] = clamp(round(_volumes[_lane]), 0, 64); }
            }
        }
        var _groups = _ra[$ "loop_groups"];
        if (is_array(_groups))
        {
            for (var _gi = 0; _gi < min(MUS_LOOP_MAX, array_length(_groups)); _gi++)
            {
                var _group = { name : "Group " + string(_gi + 1), open : true };
                var _raw_group = _groups[_gi];
                if (is_struct(_raw_group))
                {
                    if (is_string(_raw_group[$ "name"])) { _group.name = string_copy(_raw_group.name, 1, 24); }
                    var _open = _raw_group[$ "open"];
                    if (!is_undefined(_open)) { _group.open = (_open == true); }
                }
                array_push(_s.arr.loop_groups, _group);
            }
        }
        if (is_numeric(_ra[$ "bars"])) { _s.arr.bars = clamp(floor(_ra.bars), 1, MUS_BAR_MAX); }
        var _rl = _ra[$ "loops"];
        if (is_array(_rl))
        {
            for (var i = 0; i < min(MUS_LOOP_MAX, array_length(_rl)); i++) { array_push(_s.arr.loops, loop_from_loaded(_rl[i])); }
        }
        var _nl = array_length(_s.arr.loops);
        for (var _li = 0; _li < _nl; _li++)
        {
            if (_s.arr.loops[_li].group >= array_length(_s.arr.loop_groups)) { _s.arr.loops[_li].group = -1; }
        }
        var _lanes = _ra[$ "lanes"];
        if (is_array(_lanes))
        {
            for (var l = 0; l < min(MUS_LANES, array_length(_lanes)); l++)
            {
                var _src = _lanes[l];
                if (!is_array(_src)) { continue; }
                for (var b = 0; b < min(MUS_BAR_MAX, array_length(_src)); b++)
                {
                    var _v = _src[b];
                    if (is_numeric(_v) && _v >= 0 && _v < _nl) { _s.arr.lanes[l][b] = floor(_v); }
                }
            }
        }
    }
    _s.loop_bar = min(_s.loop_bar, _s.arr.bars - 1);
    if (_s.kind == 1)
    {
        var _ms = modsong_sanitize(_raw[$ "mod"]);
        if (is_undefined(_ms)) { _s.kind = 0; }
        else { _s[$ "mod"] = _ms; }
    }
    return _s;
}

function music_empty_cell()
{
    return { note : 0, sample : 0, effect : 0, param : 0, volume_base : -1 };
}

function music_empty_pattern()
{
    var _p = array_create(64, 0);
    for (var r = 0; r < 64; r++)
    {
        _p[r] = [music_empty_cell(), music_empty_cell(), music_empty_cell(), music_empty_cell()];
    }
    return _p;
}

function music_empty_sample()
{
    return { name : "", data : [], volume : 0, base_volume : 0, finetune : 0, loop_start : 0, loop_len : 0 };
}

/// A clean copy of a modsong (from mod_read or a file): 31 samples, 64 x 4
/// cells per pattern, orders inside the pattern list. undefined if unusable.
function modsong_sanitize(_ms)
{
    if (!is_struct(_ms)) { return undefined; }
    var _out = { title : "", samples : [], order : [], restart : 0, patterns : [] };
    if (is_string(_ms[$ "title"])) { _out.title = string_copy(_ms.title, 1, 20); }
    var _ls = _ms[$ "samples"];
    for (var i = 0; i < 31; i++)
    {
        var _smp = music_empty_sample();
        if (is_array(_ls) && i < array_length(_ls) && is_struct(_ls[i]))
        {
            var _r = _ls[i];
            if (is_string(_r[$ "name"])) { _smp.name = string_copy(_r.name, 1, 22); }
            if (is_array(_r[$ "data"])) { _smp.data = _r.data; }
            if (is_numeric(_r[$ "volume"])) { _smp.volume = clamp(floor(_r.volume), 0, 64); }
            if (is_numeric(_r[$ "finetune"])) { _smp.finetune = clamp(floor(_r.finetune), -8, 7); }
            if (is_numeric(_r[$ "loop_start"])) { _smp.loop_start = max(0, floor(_r.loop_start)); }
            if (is_numeric(_r[$ "loop_len"])) { _smp.loop_len = max(0, floor(_r.loop_len)); }
        }
        array_push(_out.samples, _smp);
    }
    var _lp = _ms[$ "patterns"];
    if (!is_array(_lp) || array_length(_lp) == 0) { return undefined; }
    for (var p = 0; p < array_length(_lp); p++)
    {
        var _pat = music_empty_pattern();
        var _src = _lp[p];
        if (is_array(_src))
        {
            for (var r = 0; r < min(64, array_length(_src)); r++)
            {
                var _row = _src[r];
                if (!is_array(_row)) { continue; }
                for (var c = 0; c < min(4, array_length(_row)); c++)
                {
                    var _cell = _row[c];
                    if (!is_struct(_cell)) { continue; }
                    var _d = _pat[r][c];
                    if (is_numeric(_cell[$ "note"])) { _d.note = clamp(floor(_cell.note), 0, 36); }
                    if (is_numeric(_cell[$ "sample"])) { _d.sample = clamp(floor(_cell.sample), 0, 31); }
                    if (is_numeric(_cell[$ "effect"])) { _d.effect = clamp(floor(_cell.effect), 0, 15); }
                    if (is_numeric(_cell[$ "param"])) { _d.param = clamp(floor(_cell.param), 0, 255); }
                }
            }
        }
        array_push(_out.patterns, _pat);
    }
    var _np = array_length(_out.patterns);
    var _lo = _ms[$ "order"];
    if (is_array(_lo))
    {
        for (var o = 0; o < min(128, array_length(_lo)); o++)
        {
            if (is_numeric(_lo[o])) { array_push(_out.order, clamp(floor(_lo[o]), 0, _np - 1)); }
        }
    }
    if (array_length(_out.order) == 0) { array_push(_out.order, 0); }
    if (is_numeric(_ms[$ "restart"])) { _out.restart = clamp(floor(_ms.restart), 0, array_length(_out.order) - 1); }
    return _out;
}

// ---------------------------------------------------------------------------
// Packing (Phase 2 contract): an imported song's sample bytes and pattern
// cells are stored as pack_u8 text ("data_z", "patterns_z") in .adam files
// and undo snapshots. Arranged songs hold no sample data (instruments are
// rendered when needed), so they are stored as they are.
// ---------------------------------------------------------------------------

function songs_pack(_songs)
{
    var _out = [];
    for (var i = 0; i < array_length(_songs); i++)
    {
        var _s = _songs[i];
        if (is_struct(_s) && is_struct(_s[$ "mod"]))
        {
            var _c = struct_overlay({}, _s);
            _c[$ "mod"] = modsong_pack(_s[$ "mod"]);
            _s = _c;
        }
        array_push(_out, _s);
    }
    return _out;
}

function modsong_pack(_ms)
{
    var _m = struct_overlay({}, _ms);
    var _ls = _ms[$ "samples"];
    if (is_array(_ls))
    {
        var _ns = [];
        for (var i = 0; i < array_length(_ls); i++)
        {
            var _smp = _ls[i];
            if (is_struct(_smp) && is_array(_smp[$ "data"]))
            {
                var _c = struct_overlay({}, _smp);
                var _d = _smp.data;
                var _n = array_length(_d);
                var _u = array_create(_n, 0);
                for (var k = 0; k < _n; k++) { _u[k] = (floor(_d[k]) + 256) & 0xff; }
                variable_struct_remove(_c, "data");
                _c.data_z = pack_u8(_u);
                _c.data_n = _n;
                _smp = _c;
            }
            array_push(_ns, _smp);
        }
        _m.samples = _ns;
    }
    var _lp = _ms[$ "patterns"];
    if (is_array(_lp))
    {
        var _np = array_length(_lp);
        var _u2 = array_create(_np * 1024, 0);
        var _o = 0;
        for (var p = 0; p < _np; p++)
        {
            for (var r = 0; r < 64; r++)
            {
                for (var ch = 0; ch < 4; ch++)
                {
                    var _cell = _lp[p][r][ch];
                    _u2[_o] = _cell.note;
                    _u2[_o + 1] = _cell.sample;
                    _u2[_o + 2] = _cell.effect;
                    _u2[_o + 3] = _cell.param;
                    _o += 4;
                }
            }
        }
        variable_struct_remove(_m, "patterns");
        _m.patterns_z = pack_u8(_u2);
        _m.patterns_n = _np;
    }
    return _m;
}

/// Unpacks songs in a freshly parsed file or snapshot, in place
function songs_unpack(_songs)
{
    if (!is_array(_songs)) { return; }
    for (var i = 0; i < array_length(_songs); i++)
    {
        var _s = _songs[i];
        if (is_struct(_s) && is_struct(_s[$ "mod"])) { modsong_unpack(_s[$ "mod"]); }
    }
}

function modsong_unpack(_m)
{
    var _ls = _m[$ "samples"];
    if (is_array(_ls))
    {
        for (var i = 0; i < array_length(_ls); i++)
        {
            var _smp = _ls[i];
            if (!is_struct(_smp) || !is_string(_smp[$ "data_z"])) { continue; }
            var _n = 0;
            if (is_numeric(_smp[$ "data_n"])) { _n = floor(_smp.data_n); }
            var _u = unpack_u8(_smp.data_z, _n);
            var _d = [];
            if (is_array(_u))
            {
                _d = _u;
                for (var k = 0; k < _n; k++)
                {
                    if (_d[k] > 127) { _d[k] -= 256; }
                }
            }
            _smp.data = _d;
            variable_struct_remove(_smp, "data_z");
            variable_struct_remove(_smp, "data_n");
        }
    }
    if (is_string(_m[$ "patterns_z"]))
    {
        var _np = 0;
        if (is_numeric(_m[$ "patterns_n"])) { _np = floor(_m.patterns_n); }
        var _u2 = unpack_u8(_m.patterns_z, _np * 1024);
        var _pats = [];
        if (is_array(_u2))
        {
            var _o = 0;
            for (var p = 0; p < _np; p++)
            {
                var _pat = music_empty_pattern();
                for (var r = 0; r < 64; r++)
                {
                    for (var ch = 0; ch < 4; ch++)
                    {
                        var _cell = _pat[r][ch];
                        _cell.note = _u2[_o];
                        _cell.sample = _u2[_o + 1];
                        _cell.effect = _u2[_o + 2];
                        _cell.param = _u2[_o + 3];
                        _o += 4;
                    }
                }
                array_push(_pats, _pat);
            }
        }
        _m.patterns = _pats;
        variable_struct_remove(_m, "patterns_z");
        variable_struct_remove(_m, "patterns_n");
    }
}

// ---------------------------------------------------------------------------
// Instruments -> 8-bit samples
// ---------------------------------------------------------------------------

/// Linear resample of a signed 8-bit array, reading _step source samples per output sample. Even length.
function music_resample(_src, _step)
{
    var _n = array_length(_src);
    if (_n < 2 || _step <= 0) { return _src; }
    var _len = floor(_n / _step);
    _len -= _len mod 2;
    var _out = array_create(max(0, _len), 0);
    for (var i = 0; i < _len; i++)
    {
        var _pos = i * _step;
        var _i0 = floor(_pos);
        var _f = _pos - _i0;
        var _a = _src[min(_i0, _n - 1)];
        var _b = _src[min(_i0 + 1, _n - 1)];
        _out[i] = clamp(round(_a + (_b - _a) * _f), -128, 127);
    }
    return _out;
}

/// The sample an instrument plays: { data, volume, root, src }. F-2 (root for
/// built-ins) plays the sample at its own rate; Sound page sounds get the note
/// nearest their Paula period as root.
function music_sample_from_render(_r, _preview_root = -1)
{
    var _root = music_note_for_period(_r.period);
    if (_preview_root >= 1) { _root = _preview_root; }
    var _ratio = global.MUS_PERIODS[_root] / max(1, _r.period);
    var _data = music_resample(_r.smp, _ratio);
    var _capped = (array_length(_data) > MOD_MAX_SAMPLE_BYTES);
    if (_capped && _preview_root < 1) { array_resize(_data, MOD_MAX_SAMPLE_BYTES); }
    var _sample = { data : _data, volume : 64, root : _root, src : _r, loop_start : 0, loop_len : 0, capped : _capped };
    var _n = array_length(_data);
    if (_r.loop_len >= 4 && _n >= 4)
    {
        var _start = clamp(floor(_r.loop_start / _ratio), 0, _n - 4);
        _start -= _start mod 2;
        var _end = clamp(floor((_r.loop_start + _r.loop_len) / _ratio), _start + 4, _n);
        _end -= _end mod 2;
        // End the stored sample at the loop boundary for consistent Amiga and
        // editor playback, including ProTracker's loop-at-zero first pass.
        array_resize(_data, _end);
        _sample.data = _data;
        _sample.loop_start = _start;
        _sample.loop_len = _end - _start;
    }
    return _sample;
}

function music_sample_loop_volume_selftest()
{
    var _ok = true;
    var _warnings = mus_warnings;
    var _keep = proj.sfx[0];
    var _sound = sfx_new("Loop sample");
    _sound.kind = 1;
    _sound.smp_rate = 8000;
    _sound.rate = 8000;
    _sound.smp_len = 400;
    _sound.sample_loop = true;
    _sound.loop_a = 250;
    _sound.loop_b = 750;
    var _buffer = buffer_create(400, buffer_fixed, 1);
    for (var _i = 0; _i < 400; _i++) { buffer_write(_buffer, buffer_s8, round(sin(_i / 8) * 100)); }
    _sound.smp = buffer_base64_encode(_buffer, 0, 400);
    buffer_delete(_buffer);
    proj.sfx[0] = _sound;
    var _render = sfx_render_ex(_sound);
    var _sample = music_inst_sample(MUS_INST_USER);
    if (_sample.loop_len < 4 || _sample.loop_start mod 2 != 0 || _sample.loop_len mod 2 != 0) { _ok = false; }
    if (_sample.loop_start + _sample.loop_len != array_length(_sample.data)) { _ok = false; }
    var _loop = loop_new("Sustain", 3, MUS_INST_USER);
    _loop.notes[0] = _sample.root;
    var _song = music_loop_song(_loop, 125, 0);
    _song.arr.lanes[1][0] = 0;
    _song.arr.volumes[1] = 32;
    var _ms = song_to_modsong(_song);
    var _row = _ms.patterns[_ms.order[0]][0];
    var _first = _ms.samples[_row[0].sample - 1];
    var _second = _ms.samples[_row[1].sample - 1];
    if (_first.volume != 64 || _second.volume != 32 || _row[0].sample == _row[1].sample) { _ok = false; }
    if (_first.loop_start != _sample.loop_start || _second.loop_len != _sample.loop_len) { _ok = false; }
    var _bytes = mod_write(_ms);
    var _parsed = mod_parse(_bytes);
    if (is_undefined(_parsed.song)) { _ok = false; }
    else
    {
        var _restored = _parsed.song.samples[_row[0].sample - 1];
        if (_restored.loop_start != _sample.loop_start || _restored.loop_len != _sample.loop_len || _parsed.song.samples[_row[1].sample - 1].volume != 32) { _ok = false; }
    }
    buffer_delete(_bytes);
    var _player = music_player_new(_ms, false, 0, 0);
    var _mix = buffer_create(4410 * 4, buffer_fixed, 1);
    music_player_mix(_player, _mix, 4410);
    if (!_player.ch[0].on || _player.ch[0].pos < _sample.loop_start || _player.ch[0].pos >= array_length(_sample.data)) { _ok = false; }
    if (_player.ch[0].vol != 64 || _player.ch[1].vol != 32) { _ok = false; }
    buffer_delete(_mix);
    var _loaded = song_from_loaded(json_parse(json_stringify(_song)));
    if (_loaded.arr.volumes[1] != 32 || music_scope_song(_loaded, 0, 0).arr.volumes[1] != 32) { _ok = false; }
    if (song_from_loaded({}).arr.volumes[0] != 64) { _ok = false; }
    proj.sfx[0] = _keep;
    mus_warnings = _warnings;
    if (_ok) { show_debug_message("ADAM sample loops / lane volume self-test: PASS"); }
    else { show_debug_message("ADAM sample loops / lane volume self-test: FAIL"); }
}

function music_sampler_controls_selftest()
{
    var _ok = true;
    var _warnings = mus_warnings;
    var _loop = loop_new("Volume test", 1, 6);
    _loop.notes[0] = 18;
    _loop.fx[0] = 12;
    _loop.fxp[0] = 16;
    _loop.fx_end[0] = 2;
    var _song = music_loop_song(_loop, 125, 0);
    _song.arr.volumes[0] = 32;
    var _ms = song_to_modsong(_song);
    var _pattern = _ms.patterns[_ms.order[0]];
    if (_pattern[0][0].effect != 12 || _pattern[0][0].param != 8 || _pattern[2][0].param != 8) { _ok = false; }
    var _player = music_player_new(_ms, false, 0, 0);
    music_player_row(_player);
    if (_player.ch[0].vol != 8 || _player.ch[0].base_volume != 16) { _ok = false; }
    var _loaded = loop_from_loaded(json_parse(json_stringify(_loop)));
    if (_loaded.fx[0] != 12 || _loaded.fx_end[0] != 2 || _loaded.fxp[0] != 16) { _ok = false; }
    var _bytes = mod_write(_ms);
    var _parsed = mod_parse(_bytes);
    if (is_undefined(_parsed.song)) { _ok = false; }
    else if (_parsed.song.patterns[_parsed.song.order[0]][0][0].effect != 12) { _ok = false; }
    buffer_delete(_bytes);
    _loop.fx[0] = 0;
    _loop.fx_end[0] = -1;
    _loop.notes[8] = 26;
    _loop.glide_to[0] = 8;
    _loop.fx[4] = 12;
    _loop.fxp[4] = 16;
    _ms = song_to_modsong(_song);
    var _cell = _ms.patterns[_ms.order[0]][4][0];
    if (_cell.note != 0 || _cell.sample == 0 || _cell.effect != 1 || _ms.samples[_cell.sample - 1].volume != 8) { _ok = false; }
    _player = music_player_new(_ms, false, 0, 4);
    _player.ch[0].pos = 123;
    music_player_row(_player);
    if (_player.ch[0].pos != 123 || _player.ch[0].vol != 8) { _ok = false; }
    var _sound = sfx_new("Ten-second test");
    _sound.kind = 1;
    _sound.smp_rate = 11025;
    _sound.smp_len = 110250;
    var _input = buffer_create(_sound.smp_len, buffer_fixed, 1);
    for (var _byte = 0; _byte < _sound.smp_len; _byte++)
    {
        buffer_write(_input, buffer_s8, 0);
    }
    _sound.smp = buffer_base64_encode(_input, 0, _sound.smp_len);
    buffer_delete(_input);
    var _render = sfx_render_ex(_sound);
    if (array_length(_render.smp) / _render.rate < 9.99 || _render.capped) { _ok = false; }
    _sound.rate = 28867;
    _render = sfx_render_ex(_sound);
    if (!_render.capped || array_length(_render.smp) > SMP_OUT_MAX_BYTES) { _ok = false; }
    if (array_length(music_sample_from_render(_render).data) > MOD_MAX_SAMPLE_BYTES) { _ok = false; }
    _sound.rate = 11025;
    sfx_preview_note(_sound, 1);
    var _duration = preview_note_end;
    if (!mus_playing || mus_pl.ch[0].period != global.MUS_PERIODS[1]) { _ok = false; }
    sfx_preview_note(_sound, 13);
    if (!mus_playing || abs(preview_note_end * 2 - _duration) > 0.001 || abs(preview_note_end - 10) > 0.01 || mus_pl.ch[0].period != global.MUS_PERIODS[13]) { _ok = false; }
    sfx_preview_note(_sound, 29);
    if (!mus_playing || mus_pl.ch[0].period != global.MUS_PERIODS[29]) { _ok = false; }
    sfx_preview_stop();
    if (mus_playing) { _ok = false; }
    mus_warnings = _warnings;
    if (_ok) { show_debug_message("ADAM pattern volume / ten-second sampler / pitched audition self-test: PASS"); }
    else { show_debug_message("ADAM pattern volume / ten-second sampler / pitched audition self-test: FAIL"); }
}

#macro MUS_SYNTH_UNIT (256 * 985248 / 16777216)   // Hz per step of the Sound page pitch

function music_inst_sample(_id)
{
    if (_id >= MUS_INST_USER)
    {
        var _k = _id - MUS_INST_USER;
        if (_k < 0 || _k >= array_length(proj.sfx)) { return { data : [], volume : 0, root : MUS_ROOT, src : 0, loop_start : 0, loop_len : 0, capped : false }; }
        var _us = proj.sfx[_k];
        var _r = sfx_render_ex(_us);   // cached: tells us when the sound changed
        var _key = "u" + string(_k);
        var _hit = mus_inst_cache[$ _key];
        if (!is_undefined(_hit))
        {
            if (_hit.src == _r) { return _hit; }
        }
        var _res;
        if (_us.kind == 0)
        {
            // Synth sounds play through the clean renderer; a steady pitch is
            // snapped to the nearest semitone so it is in tune with the rest
            var _hz = 0;
            if (_us.wave != 3 && _us.sweep == 0) { _hz = music_semitone_hz(clamp(_us.pitch, 1, 255) * MUS_SYNTH_UNIT); }
            var _data = music_synth_render(_us, _hz);
            var _capped = (array_length(_data) > MOD_MAX_SAMPLE_BYTES);
            if (_capped) { array_resize(_data, MOD_MAX_SAMPLE_BYTES); }
            _res = { data : _data, volume : 64, root : MUS_ROOT, src : _r, loop_start : 0, loop_len : 0, capped : _capped };
        }
        else { _res = music_sample_from_render(_r); }
        mus_inst_cache[$ _key] = _res;
        return _res;
    }
    var _key2 = "b" + string(_id);
    var _hit2 = mus_inst_cache[$ _key2];
    if (!is_undefined(_hit2)) { return _hit2; }
    var _def = global.MUS_INST[clamp(_id, 0, array_length(global.MUS_INST) - 1)];
    var _smp = music_synth_render(music_inst_sfx(_id), _def.hz);
    var _res2 = { data : _smp, volume : _def.vol, root : MUS_ROOT, src : 0, loop_start : 0, loop_len : 0, capped : false };
    mus_inst_cache[$ _key2] = _res2;
    return _res2;
}

/// A built-in instrument as Sound page synth settings (for Edit sound)
function music_inst_sfx(_id)
{
    var _def = global.MUS_INST[clamp(_id, 0, array_length(global.MUS_INST) - 1)];
    var _s = sfx_new(_def.name);
    _s.wave = _def.p[0];
    _s.pitch = _def.p[1];
    _s.sweep = _def.p[2];
    _s.len = _def.p[3];
    _s.atk = _def.p[4];
    _s.dec = _def.p[5];
    _s.sus = _def.p[6];
    _s.rel = _def.p[7];
    _s.filt = _def.f[0];
    _s.fspeed = _def.f[1];
    _s.fdepth = _def.f[2];
    if (_def.hz > 0) { _s.pitch = clamp(round(_def.hz / MUS_SYNTH_UNIT), 1, 255); }
    return _s;
}

/// The equal-tempered note frequency nearest _hz
function music_semitone_hz(_hz)
{
    if (_hz <= 0) { return 0; }
    return 440 * power(2, round(12 * log2(_hz / 440)) / 12);
}

/// PolyBLEP: smooths a wave's jump at phase 0 over one sample (band-limits it)
function music_polyblep(_t, _dt)
{
    if (_t < _dt)
    {
        var _a = _t / _dt;
        return _a + _a - _a * _a - 1;
    }
    if (_t > 1 - _dt)
    {
        var _b = (_t - 1) / _dt;
        return _b * _b + _b + _b + 1;
    }
    return 0;
}

/// Music page instruments: the Sound page synth (same envelope, slide and
/// filter as sfx_render), rendered straight at the root note's Paula rate with
/// band-limited saw and square waves, so high notes do not alias into a buzz.
/// _hz > 0 plays exactly that frequency with no slide; else the sound's own
/// pitch and slide. Returns signed 8-bit values, even length.
function music_synth_render(_s, _hz)
{
    var _atk_ms = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000];
    var _dr_ms  = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000];
    var _rate = PAULA_CLOCK / global.MUS_PERIODS[MUS_ROOT];
    var _gate_s = clamp(_s.len, 1, 100) / 50;
    var _cap = sfx_max_seconds(_s);
    var _rel_s = min(_dr_ms[clamp(_s.rel, 0, 15)] / 1000, _cap);
    var _total = min(_gate_s + _rel_s, _cap);
    var _n = floor(_total * _rate);
    _n = _n - (_n mod 2);
    var _out = array_create(_n, 0);
    var _phase = 0;
    var _hi = clamp(_s.pitch, 1, 255);
    var _noise = 0;
    var _last_q = 0;
    var _rnd = 12345;
    var _atk = max(0.001, _atk_ms[clamp(_s.atk, 0, 15)] / 1000);
    var _dec = max(0.001, _dr_ms[clamp(_s.dec, 0, 15)] / 1000);
    var _sus = clamp(_s.sus, 0, 15) / 15;
    var _rel = max(0.001, _dr_ms[clamp(_s.rel, 0, 15)] / 1000);
    var _env = 0;
    var _rel_start = 0;
    var _spf = _rate / 50;
    var _frame = 0;
    var _filt = clamp(_s.filt, 0, 15);
    var _fbase = (_filt / 16) * (_filt / 16);
    var _frate = clamp(_s.fspeed, 0, 15) * 0.25;
    var _fdep = clamp(_s.fdepth, 0, 15) / 15 * 3;
    var _lp1 = 0;
    var _lp2 = 0;
    var _peak = 0;
    var _f0 = _hz;
    for (var i = 0; i < _n; i++)
    {
        var _t = i / _rate;
        var _f = floor(i / _spf);
        if (_f != _frame)
        {
            _frame = _f;
            if (_t < _gate_s && _hz <= 0) { _hi = (_hi + _s.sweep + 256) mod 256; }
        }
        if (_hz <= 0) { _f0 = max(1, _hi) * MUS_SYNTH_UNIT; }
        var _dt = min(0.5, _f0 / _rate);
        _phase += _dt;
        _phase -= floor(_phase);
        var _v = 0;
        switch (_s.wave)
        {
            case 0: _v = 1 - 4 * abs(_phase - 0.5); break;
            case 1: _v = _phase * 2 - 1 - music_polyblep(_phase, _dt); break;
            case 2:
                if (_phase < 0.5) { _v = 1; }
                else { _v = -1; }
                var _ph2 = _phase + 0.5;
                _ph2 -= floor(_ph2);
                _v += music_polyblep(_phase, _dt) - music_polyblep(_ph2, _dt);
                break;
            default:
                var _q = floor(_phase * 4);
                if (_q != _last_q)
                {
                    _rnd = (_rnd * 1103515245 + 12345) & 0x7fffffff;
                    _noise = (_rnd / 0x3fffffff) - 1;
                    _last_q = _q;
                }
                _v = _noise;
                break;
        }
        if (_t < _gate_s)
        {
            if (_t < _atk) { _env = _t / _atk; }
            else { _env = _sus + (1 - _sus) * max(0, 1 - (_t - _atk) / _dec); }
            _rel_start = _env;
        }
        else
        {
            _env = _rel_start * max(0, 1 - (_t - _gate_s) / _rel);
        }
        if (_filt > 0)
        {
            var _c = _fbase;
            if (_frate > 0) { _c = _fbase * power(2, _fdep * sin(2 * pi * _frate * _t)); }
            _c = clamp(_c, 0.002, 1);
            _lp1 += _c * (_v - _lp1);
            _lp2 += _c * (_lp1 - _lp2);
            _v = _lp2;
        }
        _out[i] = _v * _env;
        _peak = max(_peak, abs(_out[i]));
    }
    // bring the loudest moment to 0.9 (filtering and band-limiting change the level)
    var _g = 0;
    if (_peak > 0) { _g = 0.9 / _peak; }
    for (var k = 0; k < _n; k++) { _out[k] = round(clamp(_out[k] * _g, -1, 1) * 127); }
    return _out;
}

/// The note an instrument plays at its own pitch
function music_inst_root(_id)
{
    if (_id >= MUS_INST_USER) { return music_inst_sample(_id).root; }
    return MUS_ROOT;
}

// ---------------------------------------------------------------------------
// song -> modsong
// ---------------------------------------------------------------------------

/// Bar ranges that become patterns: up to 4 bars each, starting again at the
/// loop bar. Returns an array of [first bar, bar count].
function music_chunks(_song)
{
    var _bars = clamp(_song.arr.bars, 1, MUS_BAR_MAX);
    var _lb = clamp(_song.loop_bar, 0, _bars - 1);
    var _out = [];
    var _b = 0;
    while (_b < _bars)
    {
        var _e = min(_b + 2, _bars);
        if (_b < _lb) { _e = min(_e, _lb); }
        array_push(_out, [_b, _e - _b]);
        _b = _e;
    }
    return _out;
}

/// Puts an effect in the first free effect column of a row (starting at
/// channel _prefer). If every column is busy, channel _prefer's is replaced.
function music_put_fx(_row, _fx, _prm, _prefer)
{
    for (var k = 0; k < 4; k++)
    {
        var _c = _row[(_prefer + k) mod 4];
        if (_c.effect == 0 && _c.param == 0)
        {
            _c.effect = _fx;
            _c.param = _prm;
            return true;
        }
    }
    _row[_prefer].effect = _fx;
    _row[_prefer].param = _prm;
    return false;
}

function music_pattern_key(_pat)
{
    var _s = "";
    for (var r = 0; r < 64; r++)
    {
        for (var c = 0; c < 4; c++)
        {
            var _cell = _pat[r][c];
            if (_cell.note != 0 || _cell.sample != 0 || _cell.effect != 0 || _cell.param != 0)
            {
                _s += string(r * 4 + c) + ":" + string(_cell.note) + "," + string(_cell.sample) + "," + string(_cell.effect) + "," + string(_cell.param) + ";";
            }
        }
    }
    return _s;
}

/// Contract: renders a song into a modsong (kind 1 returns the imported one).
/// Problems found on the way are left in mus_warnings.
/// An instrument-only row can set its sample volume while the effect column
/// carries a pitch bend. The copied waveform/loop keeps the same source voice.
function music_volume_sample(_ms, _map, _iid, _volume, _lane_volume)
{
    var _key = string(_iid) + "v" + string(_lane_volume) + "level" + string(_volume);
    var _existing = _map[$ _key];
    if (!is_undefined(_existing)) { return _existing; }
    var _instrument = music_inst_sample(_iid);
    if (array_length(_instrument.data) < 2) { return 0; }
    for (var _index = 0; _index < 31; _index++)
    {
        if (array_length(_ms.samples[_index].data) >= 2) { continue; }
        var _sample = _ms.samples[_index];
        _sample.name = string_copy(music_inst_name(_iid), 1, 22);
        _sample.data = _instrument.data;
        _sample.volume = clamp(round(_volume * _lane_volume / 64), 0, 64);
        _sample.base_volume = _volume;
        _sample.loop_start = _instrument.loop_start;
        _sample.loop_len = _instrument.loop_len;
        _map[$ _key] = _index + 1;
        return _index + 1;
    }
    return 0;
}

function song_to_modsong(_song)
{
    mus_warnings = [];
    if (_song.kind == 1)
    {
        var _im = _song[$ "mod"];
        if (is_struct(_im)) { return _im; }
    }
    var _ms = { title : string_copy(_song.name, 1, 20), samples : [], order : [], restart : 0, patterns : [] };
    for (var i = 0; i < 31; i++) { array_push(_ms.samples, music_empty_sample()); }
    if (_song.kind == 1)
    {
        array_push(_ms.patterns, music_empty_pattern());
        array_push(_ms.order, 0);
        return _ms;
    }
    var _arr = _song.arr;
    var _nloops = array_length(_arr.loops);
    var _map = {};
    var _nsmp = 0;
    var _dropped = 0;
    var _speed = clamp(floor(_song.speed * 0.5), 1, 31);
    var _swing = clamp(round(_song.swing * _speed / 100), 0, _speed - 1);
    var _chunks = music_chunks(_song);
    var _nc = array_length(_chunks);
    var _lb = clamp(_song.loop_bar, 0, clamp(_arr.bars, 1, MUS_BAR_MAX) - 1);
    var _restart = 0;
    for (var c = 0; c < _nc; c++)
    {
        if (_chunks[c][0] == _lb) { _restart = c; }
    }
    var _keys = {};
    for (var c2 = 0; c2 < _nc; c2++)
    {
        var _b0 = _chunks[c2][0];
        var _nb = _chunks[c2][1];
        var _pat = music_empty_pattern();
        for (var lane = 0; lane < MUS_LANES; lane++)
        {
            var _last_iid = -1;
            for (var b = 0; b < _nb; b++)
            {
                var _li = _arr.lanes[lane][_b0 + b];
                if (_li < 0 || _li >= _nloops) { continue; }
                var _lp = _arr.loops[_li];
                var _arp = 0;
                for (var st = 0; st < MUS_STEPS; st++)
                {
                    var _cell = _pat[b * MUS_STEPS + st][lane];
                    var _nt = _lp.notes[st];
                    var _bend_source = -1;
                    var _bend_arrival = -1;
                    for (var _candidate = 0; _candidate <= st; _candidate++)
                    {
                        if (music_glide_valid(_lp, _candidate) && st == _lp.glide_to[_candidate])
                        {
                            _bend_arrival = _candidate;
                        }
                        if (music_glide_valid(_lp, _candidate) && st < _lp.glide_to[_candidate])
                        {
                            _bend_source = _candidate;
                            break;
                        }
                    }
                    // A linked destination is a pitch target for the source voice.
                    // It must not start its own sample or reset the source's volume.
                    if ((_bend_source >= 0 && st > _bend_source) || _bend_arrival >= 0)
                    {
                        _nt = 0;
                        _arp = 0;
                    }
                    if (_nt > 0)
                    {
                        var _iid = _lp.insts[st];
                        _last_iid = _iid;
                        var _lane_volume = _song.arr.volumes[lane];
                        var _ik = string(_iid) + "v" + string(_lane_volume);
                        var _sn = _map[$ _ik];
                        if (is_undefined(_sn))
                        {
                            _sn = 0;
                            if (_nsmp < 31)
                            {
                                var _is = music_inst_sample(_iid);
                                if (_is.capped) { array_push(mus_warnings, music_inst_name(_iid) + " reached the MOD sample-size limit; lower its sample rate to retain more."); }
                                if (array_length(_is.data) >= 2)
                                {
                                    _nsmp += 1;
                                    _sn = _nsmp;
                                    var _smp = _ms.samples[_sn - 1];
                                    _smp.name = string_copy(music_inst_name(_iid), 1, 22);
                                    _smp.data = _is.data;
                                    _smp.volume = clamp(round(_is.volume * _lane_volume / 64), 0, 64);
                                    _smp.base_volume = _is.volume;
                                    _smp.loop_start = _is.loop_start;
                                    _smp.loop_len = _is.loop_len;
                                }
                                else
                                {
                                    array_push(mus_warnings, music_inst_name(_iid) + " is silent - import or design that sound on the Sound page.");
                                }
                            }
                            _map[$ _ik] = _sn;
                        }
                        if (_sn == 0)
                        {
                            _dropped += 1;
                            continue;
                        }
                        _cell.note = clamp(_nt, 1, 36);
                        _cell.sample = _sn;
                        _arp = _lp.arps[st];
                        if (_swing > 0 && (st mod 4) == 2)
                        {
                            _cell.effect = 14;
                            _cell.param = 0xd0 | _swing;
                        }
                        else
                        {
                            if (_arp != 0)
                            {
                                _cell.effect = 0;
                                _cell.param = _arp;
                            }
                        }
                    }
                    else
                    {
                        if (_arp != 0)
                        {
                            _cell.effect = 0;
                            _cell.param = _arp;
                        }
                    }
                    var _effect_step = music_fx_active_step(_lp, st);
                    if (_effect_step >= 0)
                    {
                        if (_cell.effect != 0 || _cell.param != 0) { array_push(mus_warnings, "Tracker effect replaced a chord or swing effect on step " + string(st + 1) + "."); }
                        _cell.effect = _lp.fx[_effect_step];
                        _cell.param = _lp.fxp[_effect_step];
                        if (_cell.effect == 12)
                        {
                            var _volume = clamp(_lp.fxp[_effect_step], 0, 64);
                            _cell.volume_base = _volume;
                            _cell.param = round(_volume * _song.arr.volumes[lane] / 64);
                            if ((_bend_source >= 0 || _bend_arrival >= 0) && _last_iid >= 0)
                            {
                                var _volume_sample = music_volume_sample(_ms, _map, _last_iid, _volume, _song.arr.volumes[lane]);
                                if (_volume_sample > 0)
                                {
                                    _cell.sample = _volume_sample;
                                    _nsmp = max(_nsmp, _volume_sample);
                                }
                                else { array_push(mus_warnings, "A volume change during a bend needs a free MOD sample slot (maximum 31)."); }
                            }
                        }
                    }
                    if (_bend_arrival >= 0 && _bend_source < 0)
                    {
                        // 3xx sets a target pitch without retriggering the sample.
                        // Resolve tracker period rounding, then hold that pitch.
                        _cell.note = _lp.notes[st];
                        // Leave an instrument-only volume update intact, if present.
                        _cell.effect = 3;
                        _cell.param = 1;
                    }
                    // Linked bends start with the source note and continue through
                    // every row before the destination, using standard MOD slides.
                    if (_bend_source >= 0)
                    {
                        var _source = _bend_source;
                        var _target = _lp.glide_to[_source];
                        var _from_period = global.MUS_PERIODS[_lp.notes[_source]];
                        var _to_period = global.MUS_PERIODS[_lp.notes[_target]];
                        var _delta = _to_period - _from_period;
                        var _ticks = max(1, _speed - 1);
                        var _span = _target - _source;
                        var _units = round(abs(_delta) / _ticks);
                        var _before = floor(_units * (st - _source) / _span);
                        var _after = floor(_units * (st - _source + 1) / _span);
                        _cell.effect = 2;
                        if (_delta < 0) { _cell.effect = 1; }
                        _cell.param = clamp(_after - _before, 0, 255);
                        // A zero slide parameter recalls the previous speed in ProTracker.
                        if (_cell.param == 0) { _cell.effect = 0; }
                    }
                    if (_nt == 0 && _bend_source < 0 && _bend_arrival < 0)
                    {
                        for (var _held_step = st - 1; _held_step >= 0; _held_step--)
                        {
                            if (_lp.notes[_held_step] <= 0) { continue; }
                            if (_lp.lengths[_held_step] > 0 && st == _held_step + _lp.lengths[_held_step] && !music_glide_valid(_lp, _held_step))
                            {
                                _cell.effect = 12;
                                _cell.param = 0;
                                _cell.volume_base = 0;
                            }
                            break;
                        }
                    }
                }
            }
        }
        var _rows = _nb * MUS_STEPS;
        if (c2 == 0)
        {
            music_put_fx(_pat[0], 15, _speed, 3);
            music_put_fx(_pat[0], 15, clamp(_song.bpm, 32, 255), 2);
        }
        if (c2 == _nc - 1)
        {
            music_put_fx(_pat[_rows - 1], 11, _restart, 3);
        }
        else
        {
            if (_rows < 64) { music_put_fx(_pat[_rows - 1], 13, 0, 3); }
        }
        var _txt = music_pattern_key(_pat);
        if (_txt == "") { _txt = "empty"; }
        var _pi = _keys[$ _txt];
        if (is_undefined(_pi))
        {
            _pi = array_length(_ms.patterns);
            array_push(_ms.patterns, _pat);
            _keys[$ _txt] = _pi;
        }
        array_push(_ms.order, _pi);
    }
    _ms.restart = _restart;
    if (_dropped > 0 && _nsmp >= 31)
    {
        array_push(mus_warnings, "This song uses more than 31 instruments - " + string(_dropped) + " notes were left out.");
    }
    if (array_length(_ms.patterns) > 64)
    {
        array_push(mus_warnings, "This song needs " + string(array_length(_ms.patterns)) + " patterns; ProTracker allows 64. Make it shorter or reuse more bars.");
    }
    if (array_length(_ms.order) > 128)
    {
        array_push(mus_warnings, "This song is longer than 128 order positions.");
    }
    return _ms;
}

/// Bytes of chip RAM a modsong takes as an M.K. file
function music_modsong_bytes(_ms)
{
    var _n = 1084 + 1024 * array_length(_ms.patterns);
    for (var i = 0; i < array_length(_ms.samples); i++)
    {
        var _len = array_length(_ms.samples[i].data);
        _n += _len + (_len mod 2);
    }
    return _n;
}

/// Bar where each order position starts (arranged songs), for the playhead
function music_order_bars(_song)
{
    var _out = [];
    var _ch = music_chunks(_song);
    for (var i = 0; i < array_length(_ch); i++) { array_push(_out, _ch[i][0]); }
    return _out;
}

/// A one-bar song that plays a single loop (library preview / Listen)
function music_loop_song(_loop, _bpm, _swing)
{
    var _s = song_new("Loop");
    _s.bpm = _bpm;
    _s.swing = _swing;
    _s.arr.bars = 1;
    array_push(_s.arr.loops, _loop);
    _s.arr.lanes[0][0] = 0;
    return _s;
}

// ---------------------------------------------------------------------------
// Song list helpers
// ---------------------------------------------------------------------------

function music_song_names()
{
    var _out = [];
    for (var i = 0; i < array_length(proj.songs); i++) { array_push(_out, proj.songs[i].name); }
    return _out;
}

/// ["No music", song names...] for the level music menus
function music_song_options()
{
    var _out = ["No music"];
    for (var i = 0; i < array_length(proj.songs); i++) { array_push(_out, string(i + 1) + ". " + proj.songs[i].name); }
    return _out;
}

/// Playback range is a temporary arrangement; saving/exporting keeps the full song.
function music_scope_song(_song, _mode, _start)
{
    if (_song.kind != 0 || _mode == 2) { return _song; }
    var _preview = song_new(_song.name);
    _preview.bpm = _song.bpm;
    _preview.speed = _song.speed;
    _preview.swing = _song.swing;
    _preview.loop_bar = 0;
    _start = clamp(_start, 0, _song.arr.bars - 1);
    var _count = 1;
    if (_mode == 1) { _count = 4; }
    _preview.arr.bars = min(_count, _song.arr.bars - _start);
    _preview.arr.loops = _song.arr.loops;
    array_copy(_preview.arr.volumes, 0, _song.arr.volumes, 0, MUS_LANES);
    for (var _lane = 0; _lane < MUS_LANES; _lane++)
    {
        for (var _bar = 0; _bar < _preview.arr.bars; _bar++)
        {
            _preview.arr.lanes[_lane][_bar] = _song.arr.lanes[_lane][_start + _bar];
        }
    }
    return _preview;
}

function music_scope_selftest()
{
    var _ok = true;
    var _warnings = mus_warnings;
    var _song = song_new("Scope test");
    _song.arr.bars = 7;
    _song.loop_bar = 2;
    for (var _bar = 0; _bar < 7; _bar++)
    {
        var _loop = loop_new("Bar " + string(_bar), 1, 6);
        _loop.notes[0] = 18 + _bar;
        array_push(_song.arr.loops, _loop);
        _song.arr.lanes[0][_bar] = _bar;
        _song.arr.lanes[1][_bar] = 6 - _bar;
    }
    var _one = music_scope_song(_song, 0, 3);
    var _four = music_scope_song(_song, 1, 2);
    var _tail = music_scope_song(_song, 1, 5);
    if (_one.arr.bars != 1 || _one.arr.lanes[0][0] != 3 || _one.arr.lanes[1][0] != 3) { _ok = false; }
    if (_four.arr.bars != 4 || _four.arr.lanes[0][3] != 5 || _four.arr.lanes[1][3] != 1 || _four.loop_bar != 0) { _ok = false; }
    if (_tail.arr.bars != 2 || _tail.arr.lanes[0][1] != 6) { _ok = false; }
    if (music_scope_song(_song, 2, 3) != _song || _song.arr.bars != 7 || _song.loop_bar != 2) { _ok = false; }
    var _one_mod = song_to_modsong(_one);
    var _four_mod = song_to_modsong(_four);
    if (_one_mod.patterns[_one_mod.order[0]][0][0].note != 21 || _one_mod.patterns[_one_mod.order[0]][MUS_STEPS][0].note != 0) { _ok = false; }
    if (array_length(_four_mod.order) != 2 || _four_mod.patterns[_four_mod.order[1]][MUS_STEPS][0].note != 23) { _ok = false; }
    var _end = _four_mod.patterns[_four_mod.order[1]][63][3];
    if (_end.effect != 11 || _end.param != 0) { _ok = false; }
    mus_warnings = _warnings;
    if (_ok) { show_debug_message("ADAM playback scope self-test: PASS"); }
    else { show_debug_message("ADAM playback scope self-test: FAIL"); }
}

/// Number of bars using song loop _li
function music_loop_uses(_song, _li)
{
    var _n = 0;
    for (var l = 0; l < MUS_LANES; l++)
    {
        for (var b = 0; b < MUS_BAR_MAX; b++)
        {
            if (_song.arr.lanes[l][b] == _li) { _n += 1; }
        }
    }
    return _n;
}

/// Removes song loop _li and fixes the lanes
function music_loop_remove(_song, _li)
{
    array_delete(_song.arr.loops, _li, 1);
    for (var l = 0; l < MUS_LANES; l++)
    {
        for (var b = 0; b < MUS_BAR_MAX; b++)
        {
            var _v = _song.arr.lanes[l][b];
            if (_v == _li) { _song.arr.lanes[l][b] = -1; }
            else
            {
                if (_v > _li) { _song.arr.lanes[l][b] = _v - 1; }
            }
        }
    }
}

/// Song loop index for library loop _lib (copies it in if needed), -1 if full
function music_song_loop_for_lib(_song, _lib)
{
    var _loops = _song.arr.loops;
    for (var i = 0; i < array_length(_loops); i++)
    {
        if (_loops[i].lib == _lib) { return i; }
    }
    if (array_length(_loops) >= MUS_LOOP_MAX)
    {
        // drop unused library copies to make room
        for (var k = array_length(_song.arr.loops) - 1; k >= 0; k--)
        {
            if (_song.arr.loops[k].lib >= 0 && music_loop_uses(_song, k) == 0) { music_loop_remove(_song, k); }
        }
        if (array_length(_song.arr.loops) >= MUS_LOOP_MAX) { return -1; }
    }
    array_push(_song.arr.loops, loop_copy(global.MUS_LIB[_lib]));
    return array_length(_song.arr.loops) - 1;
}

/// Deletes song _i and fixes the level music choices
function music_song_delete(_i)
{
    array_delete(proj.songs, _i, 1);
    for (var l = 0; l < array_length(proj.level_song); l++)
    {
        if (proj.level_song[l] == _i) { proj.level_song[l] = -1; }
        else
        {
            if (proj.level_song[l] > _i) { proj.level_song[l] -= 1; }
        }
    }
}

// ---------------------------------------------------------------------------
// Preview player: plays a modsong like Paula (8-bit samples, period pitch,
// channels 1 and 4 left, 2 and 3 right) into a GameMaker play queue.
// ---------------------------------------------------------------------------

function music_player_new(_ms, _once, _ord, _row)
{
    var _pl = {
        ms : _ms, once : _once, ord : _ord, row : _row, tick : 0,
        speed : 6, tempo : 125, tick_left : 0, ended : false, done : false, tail : 0,
        next_ord : -1, next_row : 0, frame : 0, marks : [], ch : [], preview_gain : 1,
        lpf : !machine_cur().aga, lpl : 0, lpr : 0   // A500/600 output filter (see music_player_mix)
    };
    for (var c = 0; c < 4; c++)
    {
        array_push(_pl.ch, {
            on : false, smp : 0, data : [], len : 0, pos : 0, inc : 0, vol : 0, base_volume : 0,
            period : 428, base : 428, fx : 0, prm : 0, porta_to : 0, porta_spd : 0, vib_phase : 0,
            ls : 0, ll : 0, dnote : 0, dtick : -1
        });
    }
    // pick up speed and tempo set before the starting row
    var _no = array_length(_ms.order);
    _pl.ord = clamp(_ord, 0, _no - 1);
    for (var o = 0; o <= _pl.ord; o++)
    {
        var _pat = _ms.patterns[_ms.order[o]];
        var _last = 63;
        if (o == _pl.ord) { _last = _row - 1; }
        for (var r = 0; r <= _last; r++)
        {
            for (var k = 0; k < 4; k++)
            {
                var _cell = _pat[r][k];
                if (_cell.effect == 15 && _cell.param > 0)
                {
                    if (_cell.param < 32) { _pl.speed = _cell.param; }
                    else { _pl.tempo = _cell.param; }
                }
            }
        }
    }
    return _pl;
}

function music_trigger(_pl, _ch, _per)
{
    if (_ch.smp < 1 || _ch.smp > 31) { return; }
    var _s = _pl.ms.samples[_ch.smp - 1];
    _ch.data = _s.data;
    _ch.len = array_length(_s.data);
    _ch.ls = _s.loop_start;
    _ch.ll = _s.loop_len;
    if (_ch.ls + _ch.ll > _ch.len) { _ch.ll = max(0, _ch.len - _ch.ls); }
    _ch.pos = 0;
    _ch.on = (_ch.len > 1);
    _ch.base = _per;
    _ch.period = _per;
}

function music_volslide(_ch, _prm)
{
    var _up = _prm >> 4;
    var _dn = _prm & 15;
    if (_up > 0) { _ch.vol = min(64, _ch.vol + _up); }
    else { _ch.vol = max(0, _ch.vol - _dn); }
}

function music_porta(_ch)
{
    if (_ch.porta_to <= 0) { return; }
    if (_ch.base < _ch.porta_to) { _ch.base = min(_ch.porta_to, _ch.base + _ch.porta_spd); }
    else { _ch.base = max(_ch.porta_to, _ch.base - _ch.porta_spd); }
    _ch.period = _ch.base;
}

/// Tick 0: read the row
function music_player_row(_pl)
{
    var _ms = _pl.ms;
    var _no = array_length(_ms.order);
    if (_pl.ord >= _no) { _pl.ord = 0; }
    var _pat = _ms.patterns[_ms.order[_pl.ord]];
    var _rowd = _pat[clamp(_pl.row, 0, 63)];
    array_push(_pl.marks, [_pl.frame, _pl.ord, _pl.row]);
    if (array_length(_pl.marks) > 256) { array_delete(_pl.marks, 0, 128); }
    for (var c = 0; c < 4; c++)
    {
        var _ch = _pl.ch[c];
        var _cell = _rowd[c];
        var _fx = _cell.effect;
        var _prm = _cell.param;
        _ch.fx = _fx;
        _ch.prm = _prm;
        _ch.period = _ch.base;
        _ch.dtick = -1;
        if (_cell.sample > 0)
        {
            _ch.smp = _cell.sample;
            _ch.vol = _ms.samples[_cell.sample - 1].volume;
            var _base_volume = _ms.samples[_cell.sample - 1][$ "base_volume"];
            if (is_undefined(_base_volume)) { _base_volume = _ch.vol; }
            _ch.base_volume = _base_volume;
        }
        if (_cell.note > 0)
        {
            var _per = global.MUS_PERIODS[_cell.note];
            if (_ch.smp > 0)
            {
                var _ft = _ms.samples[_ch.smp - 1].finetune;
                if (_ft != 0) { _per = _per * power(2, -_ft / 96); }
            }
            if (_fx == 3 || _fx == 5)
            {
                _ch.porta_to = _per;
                if (_ch.smp <= 0) { music_trigger(_pl, _ch, _per); }
            }
            else
            {
                if (_fx == 14 && (_prm >> 4) == 13 && (_prm & 15) > 0)
                {
                    _ch.dnote = _per;
                    _ch.dtick = _prm & 15;
                }
                else
                {
                    music_trigger(_pl, _ch, _per);
                    if (_fx == 9) { _ch.pos = _prm * 256; }
                }
            }
        }
        switch (_fx)
        {
            case 3:
                if (_prm > 0) { _ch.porta_spd = _prm; }
                break;
            case 11:
                _pl.next_ord = _prm;
                _pl.next_row = 0;
                break;
            case 12:
                _ch.vol = min(64, _prm);
                var _volume_base = _cell[$ "volume_base"];
                _ch.base_volume = _ch.vol;
                if (!is_undefined(_volume_base) && _volume_base >= 0) { _ch.base_volume = _volume_base; }
                break;
            case 13:
                if (_pl.next_ord < 0) { _pl.next_ord = _pl.ord + 1; }
                _pl.next_row = min(63, (_prm >> 4) * 10 + (_prm & 15));
                break;
            case 14:
                var _sub = _prm >> 4;
                var _v = _prm & 15;
                if (_sub == 1) { _ch.base = max(113, _ch.base - _v); }
                if (_sub == 2) { _ch.base = min(856, _ch.base + _v); }
                if (_sub == 10) { _ch.vol = min(64, _ch.vol + _v); }
                if (_sub == 11) { _ch.vol = max(0, _ch.vol - _v); }
                if (_sub == 12 && _v == 0) { _ch.vol = 0; }
                _ch.period = _ch.base;
                break;
            case 15:
                if (_prm > 0)
                {
                    if (_prm < 32) { _pl.speed = _prm; }
                    else { _pl.tempo = _prm; }
                }
                break;
        }
    }
}

/// Ticks 1..speed-1: running effects
function music_player_effects(_pl)
{
    var _t = _pl.tick;
    for (var c = 0; c < 4; c++)
    {
        var _ch = _pl.ch[c];
        var _prm = _ch.prm;
        switch (_ch.fx)
        {
            case 0:
                if (_prm != 0)
                {
                    var _k = _t mod 3;
                    var _semi = 0;
                    if (_k == 1) { _semi = _prm >> 4; }
                    if (_k == 2) { _semi = _prm & 15; }
                    _ch.period = _ch.base * power(2, -_semi / 12);
                }
                break;
            case 1:
                _ch.base = max(113, _ch.base - _prm);
                _ch.period = _ch.base;
                break;
            case 2:
                _ch.base = min(856, _ch.base + _prm);
                _ch.period = _ch.base;
                break;
            case 3:
                music_porta(_ch);
                break;
            case 4:
                var _vib_speed = _prm >> 4;
                var _vib_depth = _prm & 15;
                if (_vib_speed == 0) { _vib_speed = 4; }
                if (_vib_depth == 0) { _vib_depth = 7; }
                _ch.vib_phase = (_ch.vib_phase + _vib_speed * 4) mod 64;
                _ch.period = clamp(_ch.base + sin(_ch.vib_phase * 360 / 64) * _vib_depth * 2, 113, 856);
                break;
            case 5:
                music_porta(_ch);
                music_volslide(_ch, _prm);
                break;
            case 6:
                music_volslide(_ch, _prm);
                break;
            case 10:
                music_volslide(_ch, _prm);
                break;
            case 14:
                var _sub = _prm >> 4;
                var _v = _prm & 15;
                if (_sub == 12 && _t == _v) { _ch.vol = 0; }
                if (_sub == 13 && _t == _v && _ch.dtick >= 0)
                {
                    music_trigger(_pl, _ch, _ch.dnote);
                    _ch.dtick = -1;
                }
                if (_sub == 9 && _v > 0 && (_t mod _v) == 0)
                {
                    _ch.pos = 0;
                    _ch.on = (_ch.len > 1);
                }
                break;
        }
    }
}

function music_player_tick(_pl)
{
    if (_pl.tick == 0) { music_player_row(_pl); }
    else { music_player_effects(_pl); }
    _pl.tick += 1;
    if (_pl.tick >= _pl.speed)
    {
        _pl.tick = 0;
        var _old_ord = _pl.ord;
        var _old_row = _pl.row;
        if (_pl.next_ord >= 0)
        {
            _pl.ord = _pl.next_ord;
            _pl.row = _pl.next_row;
            _pl.next_ord = -1;
            _pl.next_row = 0;
        }
        else
        {
            _pl.row += 1;
            if (_pl.row >= 64)
            {
                _pl.row = 0;
                _pl.ord += 1;
            }
        }
        var _no = array_length(_pl.ms.order);
        var _wrapped = false;
        if (_pl.ord >= _no)
        {
            _pl.ord = clamp(_pl.ms.restart, 0, _no - 1);
            _wrapped = true;
        }
        if (_pl.ord < _old_ord || (_pl.ord == _old_ord && _pl.row <= _old_row)) { _wrapped = true; }
        if (_wrapped && _pl.once) { _pl.ended = true; }
    }
}

/// Mixes _n stereo frames (signed 16-bit) into _buf at its current position
function music_player_mix(_pl, _buf, _n)
{
    var _ml = array_create(_n, 0);
    var _mr = array_create(_n, 0);
    var _done = 0;
    var _clock = PAULA_CLOCK / MUS_RATE;
    while (_done < _n)
    {
        if (_pl.tick_left <= 0)
        {
            if (!_pl.ended) { music_player_tick(_pl); }
            for (var c = 0; c < 4; c++)
            {
                var _cc = _pl.ch[c];
                _cc.inc = _clock / clamp(_cc.period, 100, 2000);
            }
            _pl.tick_left += MUS_RATE * 2.5 / max(32, _pl.tempo);
        }
        var _k = min(_n - _done, ceil(_pl.tick_left));
        for (var c2 = 0; c2 < 4; c2++)
        {
            var _ch = _pl.ch[c2];
            if (!_ch.on) { continue; }
            var _d = _ch.data;
            var _len = _ch.len;
            var _pos = _ch.pos;
            var _inc = _ch.inc;
            var _v = _ch.vol;
            var _loop = (_ch.ll > 2);
            var _le = _ch.ls + _ch.ll;
            var _left = (c2 == 0 || c2 == 3);
            for (var i = _done; i < _done + _k; i++)
            {
                if (_loop)
                {
                    while (_pos >= _le) { _pos -= _ch.ll; }
                }
                else
                {
                    if (_pos >= _len)
                    {
                        _ch.on = false;
                        break;
                    }
                }
                var _s = _d[floor(_pos)] * _v;
                if (_left) { _ml[i] += _s; }
                else { _mr[i] += _s; }
                _pos += _inc;
            }
            _ch.pos = _pos;
        }
        _pl.tick_left -= _k;
        _pl.frame += _k;
        _done += _k;
        if (_pl.ended)
        {
            _pl.tail += _k;
            if (_pl.tail > MUS_RATE * 0.6) { _pl.done = true; }
        }
    }
    // The A500 / A600 have a fixed low-pass on the audio output (about 4.9 kHz,
    // one pole) that softens Paula's stepped samples; FS-UAE models it too.
    // The A1200's is far above hearing, so it plays unfiltered.
    var _a = 1 - exp(-2 * pi * 4900 / MUS_RATE);
    var _lpl = _pl.lpl;
    var _lpr = _pl.lpr;
    for (var j = 0; j < _n; j++)
    {
        var _ol = _ml[j];
        var _or = _mr[j];
        if (_pl.lpf)
        {
            _lpl += _a * (_ol - _lpl);
            _lpr += _a * (_or - _lpr);
            _ol = _lpl;
            _or = _lpr;
        }
        buffer_write(_buf, buffer_s16, clamp(_ol * 2 * _pl.preview_gain, -32767, 32767));
        buffer_write(_buf, buffer_s16, clamp(_or * 2 * _pl.preview_gain, -32767, 32767));
    }
    _pl.lpl = _lpl;
    _pl.lpr = _lpr;
}

/// Starts playing a modsong. _what names what is playing (for highlights).
function music_preview_start(_ms, _once, _ord, _row, _what, _gain = 1)
{
    music_preview_stop();
    sfx_preview_stop();
    if (!is_struct(_ms) || array_length(_ms.order) == 0) { return; }
    mus_pl = music_player_new(_ms, _once, _ord, _row);
    mus_pl.preview_gain = _gain;
    mus_queue = audio_create_play_queue(buffer_s16, MUS_RATE, audio_stereo);
    mus_frames_queued = 0;
    mus_playing = true;
    mus_play_what = _what;
    mus_play_t0 = get_timer();
    music_preview_fill(MUS_RATE * 0.25);
    mus_queue_inst = audio_play_sound(mus_queue, 1, false);
    mus_play_t0 = get_timer();
}

/// Mixes and queues audio until _ahead frames are waiting
function music_preview_fill(_ahead)
{
    var _elapsed = (get_timer() - mus_play_t0) / 1000000 * MUS_RATE;
    var _guard = 0;
    while (mus_frames_queued < _elapsed + _ahead && _guard < 12 && !mus_pl.done)
    {
        var _n = 1024;
        var _b = buffer_create(_n * 4, buffer_fixed, 1);
        music_player_mix(mus_pl, _b, _n);
        audio_queue_sound(mus_queue, _b, 0, _n * 4);
        array_push(mus_bufs, _b);
        mus_frames_queued += _n;
        _guard += 1;
    }
}

function music_preview_stop()
{
    if (mus_queue_inst != -1)
    {
        audio_stop_sound(mus_queue_inst);
        mus_queue_inst = -1;
    }
    if (mus_queue != -1)
    {
        audio_free_play_queue(mus_queue);
        mus_queue = -1;
    }
    for (var i = 0; i < array_length(mus_bufs); i++) { array_push(mus_dead_bufs, [mus_bufs[i], current_time]); }
    mus_bufs = [];
    mus_playing = false;
    mus_play_what = "";
    mus_play_song = -1;
}

/// Step: keeps the queue fed, rebuilds after edits, frees played buffers
function music_preview_step()
{
    for (var i = array_length(mus_dead_bufs) - 1; i >= 0; i--)
    {
        if (current_time - mus_dead_bufs[i][1] > 1500)
        {
            if (buffer_exists(mus_dead_bufs[i][0])) { buffer_delete(mus_dead_bufs[i][0]); }
            array_delete(mus_dead_bufs, i, 1);
        }
    }
    if (!mus_playing) { return; }
    // follow edits to the song that is playing
    if (mus_play_song >= 0)
    {
        if (mus_play_song >= array_length(proj.songs))
        {
            music_preview_stop();
            return;
        }
        var _s = proj.songs[mus_play_song];
        if ((_s != mus_play_ref || mus_rev != mus_play_rev) && current_time - mus_play_rebuild_t > 250)
        {
            mus_play_ref = _s;
            mus_play_rev = mus_rev;
            mus_play_rebuild_t = current_time;
            if (_s.kind == 0) { mus_play_bar = clamp(mus_play_bar, 0, _s.arr.bars - 1); }
            var _preview = music_scope_song(_s, mus_play_mode, mus_play_bar);
            var _ms = song_to_modsong(_preview);
            if (_s.kind == 0)
            {
                for (var _lane = 0; _lane < MUS_LANES; _lane++)
                {
                    mus_pl.ch[_lane].vol = clamp(round(mus_pl.ch[_lane].base_volume * _s.arr.volumes[_lane] / 64), 0, 64);
                }
            }
            mus_pl.ms = _ms;
            mus_pl.ord = clamp(mus_pl.ord, 0, array_length(_ms.order) - 1);
            mus_pl.next_ord = -1;
            mus_pl.tempo = clamp(_s.bpm, 32, 255);
            if (_s.kind == 0)
            {
                mus_ord_bar = music_order_bars(_preview);
                var _chunks = music_chunks(_preview);
                if (mus_pl.row >= _chunks[mus_pl.ord][1] * MUS_STEPS)
                {
                    mus_pl.row = 0;
                    mus_pl.tick = 0;
                }
                if (mus_play_mode != 2)
                {
                    for (var _order = 0; _order < array_length(mus_ord_bar); _order++) { mus_ord_bar[_order] += mus_play_bar; }
                }
            }
        }
    }
    var _elapsed = (get_timer() - mus_play_t0) / 1000000 * MUS_RATE;
    if (_elapsed > mus_frames_queued)
    {
        // the queue ran dry (window dragged, app paused): carry on from here
        mus_play_t0 = get_timer() - mus_frames_queued / MUS_RATE * 1000000;
        _elapsed = mus_frames_queued;
        if (mus_pl.done)
        {
            music_preview_stop();
            return;
        }
    }
    music_preview_fill(MUS_RATE * 0.3);
    if (mus_queue_inst == -1 || !audio_is_playing(mus_queue_inst))
    {
        mus_queue_inst = audio_play_sound(mus_queue, 1, false);
    }
}

/// Async Audio Playback event: a queued buffer has been played
function music_preview_async()
{
    var _b = async_load[? "buffer_id"];
    if (is_undefined(_b)) { return; }
    for (var i = 0; i < array_length(mus_bufs); i++)
    {
        if (mus_bufs[i] == _b)
        {
            array_delete(mus_bufs, i, 1);
            if (buffer_exists(_b)) { buffer_delete(_b); }
            return;
        }
    }
}

/// Position being heard now: [order, row], or undefined
function music_preview_pos()
{
    if (!mus_playing) { return undefined; }
    var _heard = (get_timer() - mus_play_t0) / 1000000 * MUS_RATE;
    var _m = mus_pl.marks;
    for (var i = array_length(_m) - 1; i >= 0; i--)
    {
        if (_m[i][0] <= _heard) { return [_m[i][1], _m[i][2]]; }
    }
    return undefined;
}

/// Frees everything (CleanUp)
function music_preview_free()
{
    music_preview_stop();
    for (var i = 0; i < array_length(mus_dead_bufs); i++)
    {
        if (buffer_exists(mus_dead_bufs[i][0])) { buffer_delete(mus_dead_bufs[i][0]); }
    }
    mus_dead_bufs = [];
}
