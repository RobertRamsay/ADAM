/// ADAM - music (Phase 2 Track B): loop library, chip-synth instruments,
/// songs, song_to_modsong and the GML preview player.
///
/// Arrangement (song.arr, kind 0):
///   arr = { bars, lanes, loops }
///   bars  : song length in bars (1..128)
///   lanes : 4 arrays (one per Paula channel) of MUS_BAR_MAX entries,
///           each an index into arr.loops, or -1 for an empty bar
///   loops : the song's 1-bar loops = { name, cat, lib, inst, notes, insts, arps, fx, fxp }
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

function mus_inst_def(_name, _drum, _p, _hz, _vol)
{
    return { name : _name, drum : _drum, p : _p, hz : _hz, vol : _vol };
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
    // [wave, pitch, slide, length, attack, decay, sustain, release].
    // hz > 0: a tuned instrument, F-2 plays this frequency (an F).
    global.MUS_INST = [
        mus_inst_def("Kick",        true,  [0, 12, -1, 7, 0, 4, 0, 3], 0, 64),
        mus_inst_def("Snare",       true,  [3, 70, -2, 5, 0, 4, 0, 4], 0, 56),
        mus_inst_def("Hi-hat",      true,  [3, 250, 0, 1, 0, 2, 0, 2], 0, 40),
        mus_inst_def("Open hat",    true,  [3, 250, 0, 6, 0, 6, 3, 5], 0, 36),
        mus_inst_def("Tom",         true,  [0, 20, -1, 8, 0, 5, 0, 4], 0, 60),
        mus_inst_def("Clap",        true,  [3, 110, 0, 3, 0, 3, 2, 4], 0, 52),
        mus_inst_def("Square bass", false, [2, 1, 0, 10, 0, 6, 6, 4], 87.307, 56),
        mus_inst_def("Saw bass",    false, [1, 1, 0, 10, 0, 5, 5, 4], 87.307, 56),
        mus_inst_def("Organ",       false, [2, 1, 0, 25, 1, 8, 10, 6], 349.228, 40),
        mus_inst_def("Soft pad",    false, [0, 1, 0, 40, 6, 9, 12, 8], 349.228, 44),
        mus_inst_def("Square lead", false, [2, 1, 0, 12, 0, 6, 9, 5], 698.456, 44),
        mus_inst_def("Saw lead",    false, [1, 1, 0, 12, 0, 6, 9, 5], 698.456, 44),
        mus_inst_def("Pluck",       false, [2, 1, 0, 4, 0, 4, 0, 4], 698.456, 48),
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
        inst : _inst,
        notes : array_create(MUS_STEPS, 0),
        insts : array_create(MUS_STEPS, _inst),
        arps : array_create(MUS_STEPS, 0),
        fx : array_create(MUS_STEPS, 0),
        fxp : array_create(MUS_STEPS, 0)
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
    array_copy(_c.notes, 0, _l.notes, 0, MUS_STEPS);
    array_copy(_c.insts, 0, _l.insts, 0, MUS_STEPS);
    array_copy(_c.arps, 0, _l.arps, 0, MUS_STEPS);
    array_copy(_c.fx, 0, _l.fx, 0, MUS_STEPS);
    array_copy(_c.fxp, 0, _l.fxp, 0, MUS_STEPS);
    return _c;
}

function music_inst_valid(_id)
{
    if (!is_numeric(_id)) { return false; }
    if (_id >= 0 && _id < array_length(global.MUS_INST)) { return true; }
    if (_id >= MUS_INST_USER && _id < MUS_INST_USER + 8) { return true; }
    return false;
}

function music_inst_name(_id)
{
    if (_id >= MUS_INST_USER)
    {
        var _k = _id - MUS_INST_USER;
        if (_k >= 0 && _k < array_length(proj.sfx)) { return "Sound " + string(_k + 1) + ": " + proj.sfx[_k].name; }
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
    for (var k = 0; k < 8; k++) { array_push(_out, MUS_INST_USER + k); }
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
    var _a = { bars : 8, lanes : [], loops : [] };
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
    if (music_inst_valid(_raw[$ "inst"])) { _l.inst = floor(_raw.inst); }
    var _n = _raw[$ "notes"];
    var _i = _raw[$ "insts"];
    var _a = _raw[$ "arps"];
    var _fx = _raw[$ "fx"];
    var _fxp = _raw[$ "fxp"];
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
        if (is_array(_fx) && _src_step < array_length(_fx) && is_numeric(_fx[_src_step])) { _l.fx[s] = clamp(floor(_fx[_src_step]), 0, 4); }
        if (is_array(_fxp) && _src_step < array_length(_fxp) && is_numeric(_fxp[_src_step])) { _l.fxp[s] = clamp(floor(_fxp[_src_step]), 0, 255); }
    }
    return _l;
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
        if (is_numeric(_ra[$ "bars"])) { _s.arr.bars = clamp(floor(_ra.bars), 1, MUS_BAR_MAX); }
        var _rl = _ra[$ "loops"];
        if (is_array(_rl))
        {
            for (var i = 0; i < min(MUS_LOOP_MAX, array_length(_rl)); i++) { array_push(_s.arr.loops, loop_from_loaded(_rl[i])); }
        }
        var _nl = array_length(_s.arr.loops);
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
    return { note : 0, sample : 0, effect : 0, param : 0 };
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
    return { name : "", data : [], volume : 0, finetune : 0, loop_start : 0, loop_len : 0 };
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
function music_inst_sample(_id)
{
    if (_id >= MUS_INST_USER)
    {
        var _k = _id - MUS_INST_USER;
        if (_k < 0 || _k >= array_length(proj.sfx)) { return { data : [], volume : 0, root : MUS_ROOT, src : 0 }; }
        var _r = sfx_render_ex(proj.sfx[_k]);
        var _key = "u" + string(_k);
        var _hit = mus_inst_cache[$ _key];
        if (!is_undefined(_hit))
        {
            if (_hit.src == _r) { return _hit; }
        }
        var _root = music_note_for_period(_r.period);
        var _data = music_resample(_r.smp, global.MUS_PERIODS[_root] / max(1, _r.period));
        var _res = { data : _data, volume : 64, root : _root, src : _r };
        mus_inst_cache[$ _key] = _res;
        return _res;
    }
    var _key2 = "b" + string(_id);
    var _hit2 = mus_inst_cache[$ _key2];
    if (!is_undefined(_hit2)) { return _hit2; }
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
    var _unit = 256 * 985248 / 16777216;     // Hz per step of the Sound page pitch
    if (_def.hz > 0) { _s.pitch = clamp(round(_def.hz / _unit), 1, 255); }
    var _smp = sfx_render(_s);
    if (_def.hz > 0)
    {
        // retune so F-2 (played at PAULA_CLOCK / 320) sounds exactly _def.hz
        var _got = _s.pitch * _unit;
        var _rate_root = PAULA_CLOCK / global.MUS_PERIODS[MUS_ROOT];
        _smp = music_resample(_smp, (_def.hz / _rate_root) / (_got / SFX_RATE));
    }
    if (array_length(_smp) mod 2 == 1) { array_pop(_smp); }
    var _res2 = { data : _smp, volume : _def.vol, root : MUS_ROOT, src : 0 };
    mus_inst_cache[$ _key2] = _res2;
    return _res2;
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
                    if (_nt > 0)
                    {
                        var _iid = _lp.insts[st];
                        var _ik = string(_iid);
                        var _sn = _map[$ _ik];
                        if (is_undefined(_sn))
                        {
                            _sn = 0;
                            if (_nsmp < 31)
                            {
                                var _is = music_inst_sample(_iid);
                                if (array_length(_is.data) >= 2)
                                {
                                    _nsmp += 1;
                                    _sn = _nsmp;
                                    var _smp = _ms.samples[_sn - 1];
                                    _smp.name = string_copy(music_inst_name(_iid), 1, 22);
                                    _smp.data = _is.data;
                                    _smp.volume = _is.volume;
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
                    if (_lp.fx[st] > 0)
                    {
                        if (_cell.effect != 0 || _cell.param != 0) { array_push(mus_warnings, "Tracker effect replaced a chord or swing effect on step " + string(st + 1) + "."); }
                        _cell.effect = _lp.fx[st];
                        _cell.param = _lp.fxp[st];
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
        next_ord : -1, next_row : 0, frame : 0, marks : [], ch : []
    };
    for (var c = 0; c < 4; c++)
    {
        array_push(_pl.ch, {
            on : false, smp : 0, data : [], len : 0, pos : 0, inc : 0, vol : 0,
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
    for (var j = 0; j < _n; j++)
    {
        buffer_write(_buf, buffer_s16, clamp(_ml[j] * 2, -32767, 32767));
        buffer_write(_buf, buffer_s16, clamp(_mr[j] * 2, -32767, 32767));
    }
}

/// Starts playing a modsong. _what names what is playing (for highlights).
function music_preview_start(_ms, _once, _ord, _row, _what)
{
    music_preview_stop();
    sfx_preview_stop();
    if (!is_struct(_ms) || array_length(_ms.order) == 0) { return; }
    mus_pl = music_player_new(_ms, _once, _ord, _row);
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
            var _ms = song_to_modsong(_s);
            mus_pl.ms = _ms;
            mus_pl.ord = clamp(mus_pl.ord, 0, array_length(_ms.order) - 1);
            mus_pl.next_ord = -1;
            mus_pl.tempo = clamp(_s.bpm, 32, 255);
            if (_s.kind == 0) { mus_ord_bar = music_order_bars(_s); }
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
