/// ADAM - ProTracker MOD export / import (Phase 2, Track C).
/// Everything goes through the neutral "modsong" struct (docs/MUSIC_CONTRACT.md):
///   mod_write(_modsong) -> buffer   (caller deletes it)
///   mod_read(_path)     -> modsong or undefined (toast on failure)
///   mod_size(_modsong)  -> bytes mod_write would produce
///   mod_save_file(_modsong, _path) -> true / false
///
/// File layout written (standard 4-channel 31-sample ProTracker module, big-endian):
///   0     20 bytes  title (ASCII, zero padded)
///   20    31 x 30   sample headers: 22 name, word length (words), byte finetune
///                   (low nibble, two's complement -8..7), byte volume 0..64,
///                   word loop start (words), word loop length (words, 1 = no loop)
///   950   byte      song length (1..128)
///   951   byte      restart: the modsong restart position when it is 1..songlen-1,
///                   otherwise 127 (what ProTracker itself writes; restart 0)
///   952   128 bytes order table (unused entries 0)
///   1080  "M.K."    ("M!K!" only if more than 64 patterns are needed)
///   1084  patterns  64 rows x 4 channels x 4 bytes:
///                   [sample hi nibble | period bits 11-8] [period bits 7-0]
///                   [sample lo nibble | effect] [param]
///   then  samples   signed 8-bit, in sample order
///
/// Conventions:
///   - Pattern count = highest pattern index in the order table + 1 (that is how
///     ProTracker and every player count them); patterns not in the order table
///     beyond that are not written, missing ones are written empty.
///   - Sample lengths are padded to an even byte count with 0 and capped at
///     65535 words (131070 bytes).
///   - A sample with no loop is written with loop start 0, loop length 1 word,
///     and its first two bytes forced to 0: Paula keeps repeating that first word
///     after a one-shot sample ends, so it must be silent. A loop must be at least
///     2 words (4 bytes) long - a 1-word loop means "no loop" in a MOD.
///   - Notes 1..36 = C-1..B-3 at finetune 0 (periods 856..113). Reading maps any
///     period to the nearest of those 36 (so finetuned periods and the odd
///     out-of-range period still land on a sensible note). Effects and params are
///     kept exactly as stored.

#macro MOD_HEADER_SIZE 1084
#macro MOD_PATTERN_SIZE 1024
#macro MOD_MAX_PATTERNS 100
#macro MOD_MAX_SAMPLE_BYTES 131070

/// ProTracker periods for C-1..B-3, finetune 0
function mod_periods()
{
    static _tab = [
        856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
        428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
        214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113
    ];
    return _tab;
}

/// Note 1..36 -> period (0 for no note)
function mod_note_to_period(_note)
{
    if (_note < 1 || _note > 36) { return 0; }
    var _tab = mod_periods();
    return _tab[_note - 1];
}

/// Period -> nearest note 1..36 (0 for period 0)
function mod_period_to_note(_period)
{
    if (_period <= 0) { return 0; }
    var _tab = mod_periods();
    var _best = 1;
    var _best_d = 1000000;
    for (var i = 0; i < 36; i++)
    {
        var _d = abs(ln(_period / _tab[i]));
        if (_d < _best_d)
        {
            _best_d = _d;
            _best = i + 1;
        }
    }
    return _best;
}

/// Reads a number field from a struct (modsong data may come from JSON)
function mod_num(_s, _key, _def)
{
    if (!is_struct(_s)) { return _def; }
    var _v = _s[$ _key];
    if (is_undefined(_v) || !is_numeric(_v)) { return _def; }
    return _v;
}

function mod_int(_v, _lo, _hi)
{
    return clamp(floor(_v), _lo, _hi);
}

/// The order table as written: 1..128 entries, each 0..MOD_MAX_PATTERNS-1
function mod_song_order(_ms)
{
    var _out = [];
    var _src = undefined;
    if (is_struct(_ms)) { _src = _ms[$ "order"]; }
    if (is_array(_src))
    {
        var _n = min(array_length(_src), 128);
        for (var i = 0; i < _n; i++)
        {
            var _v = _src[i];
            if (!is_numeric(_v)) { _v = 0; }
            array_push(_out, mod_int(_v, 0, MOD_MAX_PATTERNS - 1));
        }
    }
    if (array_length(_out) == 0) { array_push(_out, 0); }
    return _out;
}

function mod_pattern_count(_order)
{
    var _top = 0;
    for (var i = 0; i < array_length(_order); i++)
    {
        _top = max(_top, _order[i]);
    }
    return _top + 1;
}

/// Sample _i (0..30) normalised for writing: even byte length, loop in bytes
function mod_sample_info(_ms, _i)
{
    var _inf = { name : "", data : undefined, bytes : 0, volume : 0, finetune : 0, loop_start : 0, loop_len : 0 };
    var _list = undefined;
    if (is_struct(_ms)) { _list = _ms[$ "samples"]; }
    if (!is_array(_list) || _i >= array_length(_list)) { return _inf; }
    var _s = _list[_i];
    if (!is_struct(_s)) { return _inf; }
    var _name = _s[$ "name"];
    if (is_string(_name)) { _inf.name = _name; }
    var _data = _s[$ "data"];
    if (is_array(_data))
    {
        _inf.data = _data;
        var _n = min(array_length(_data), MOD_MAX_SAMPLE_BYTES);
        _inf.bytes = _n + (_n mod 2);
    }
    _inf.volume = mod_int(mod_num(_s, "volume", 64), 0, 64);
    _inf.finetune = mod_int(mod_num(_s, "finetune", 0), -8, 7);
    var _ls = mod_int(mod_num(_s, "loop_start", 0), 0, _inf.bytes);
    _ls = _ls - (_ls mod 2);
    var _ll = mod_int(mod_num(_s, "loop_len", 0), 0, _inf.bytes - _ls);
    _ll = _ll - (_ll mod 2);
    if (_ll < 4)
    {
        _ls = 0;
        _ll = 0;
    }
    _inf.loop_start = _ls;
    _inf.loop_len = _ll;
    return _inf;
}

/// Bytes mod_write would produce
function mod_size(_ms)
{
    var _total = MOD_HEADER_SIZE + mod_pattern_count(mod_song_order(_ms)) * MOD_PATTERN_SIZE;
    for (var s = 0; s < 31; s++)
    {
        _total += mod_sample_info(_ms, s).bytes;
    }
    return _total;
}

function mod_poke16(_b, _pos, _v)
{
    buffer_poke(_b, _pos, buffer_u8, (_v >> 8) & 0xff);
    buffer_poke(_b, _pos + 1, buffer_u8, _v & 0xff);
}

function mod_peek16(_b, _pos)
{
    return (buffer_peek(_b, _pos, buffer_u8) << 8) | buffer_peek(_b, _pos + 1, buffer_u8);
}

/// Writes up to _len ASCII bytes of _str (other characters become '?'); rest stays 0
function mod_put_text(_b, _pos, _str, _len)
{
    var _n = min(string_length(_str), _len);
    for (var i = 0; i < _n; i++)
    {
        var _c = ord(string_char_at(_str, i + 1));
        if (_c < 32 || _c > 126) { _c = 63; }
        buffer_poke(_b, _pos + i, buffer_u8, _c);
    }
}

/// Reads a zero-terminated text field, keeping printable ASCII only
function mod_get_text(_b, _pos, _len)
{
    var _s = "";
    for (var i = 0; i < _len; i++)
    {
        var _c = buffer_peek(_b, _pos + i, buffer_u8);
        if (_c == 0) { break; }
        if (_c >= 32 && _c <= 126) { _s += chr(_c); }
    }
    return _s;
}

/// Builds the MOD. Returns a buffer_fixed buffer of exactly mod_size(_ms) bytes.
function mod_write(_ms)
{
    var _order = mod_song_order(_ms);
    var _nord = array_length(_order);
    var _npat = mod_pattern_count(_order);
    var _size = mod_size(_ms);
    var _b = buffer_create(_size, buffer_fixed, 1);
    buffer_fill(_b, 0, buffer_u8, 0, _size);

    var _title = "";
    if (is_struct(_ms) && is_string(_ms[$ "title"])) { _title = _ms[$ "title"]; }
    mod_put_text(_b, 0, _title, 20);

    // sample headers
    var _infos = array_create(31, undefined);
    for (var s = 0; s < 31; s++)
    {
        var _inf = mod_sample_info(_ms, s);
        _infos[s] = _inf;
        var _p = 20 + s * 30;
        mod_put_text(_b, _p, _inf.name, 22);
        mod_poke16(_b, _p + 22, _inf.bytes div 2);
        buffer_poke(_b, _p + 24, buffer_u8, _inf.finetune & 0x0f);
        buffer_poke(_b, _p + 25, buffer_u8, _inf.volume);
        if (_inf.loop_len > 0)
        {
            mod_poke16(_b, _p + 26, _inf.loop_start div 2);
            mod_poke16(_b, _p + 28, _inf.loop_len div 2);
        }
        else
        {
            mod_poke16(_b, _p + 26, 0);
            mod_poke16(_b, _p + 28, 1);
        }
    }

    // song length, restart, order table, tag
    buffer_poke(_b, 950, buffer_u8, _nord);
    var _restart = floor(mod_num(_ms, "restart", 0));
    if (_restart > 0 && _restart < _nord) { buffer_poke(_b, 951, buffer_u8, _restart); }
    else { buffer_poke(_b, 951, buffer_u8, 127); }
    for (var o = 0; o < _nord; o++)
    {
        buffer_poke(_b, 952 + o, buffer_u8, _order[o]);
    }
    if (_npat > 64) { mod_put_text(_b, 1080, "M!K!", 4); }
    else { mod_put_text(_b, 1080, "M.K.", 4); }

    // patterns
    var _pats = undefined;
    if (is_struct(_ms)) { _pats = _ms[$ "patterns"]; }
    if (!is_array(_pats)) { _pats = []; }
    for (var _pn = 0; _pn < _npat; _pn++)
    {
        if (_pn >= array_length(_pats)) { break; }
        var _pat = _pats[_pn];
        if (!is_array(_pat)) { continue; }
        var _rows = min(array_length(_pat), 64);
        for (var r = 0; r < _rows; r++)
        {
            var _row = _pat[r];
            if (!is_array(_row)) { continue; }
            var _chans = min(array_length(_row), 4);
            for (var c = 0; c < _chans; c++)
            {
                var _cell = _row[c];
                if (!is_struct(_cell)) { continue; }
                var _per = mod_note_to_period(floor(mod_num(_cell, "note", 0)));
                var _smp = mod_int(mod_num(_cell, "sample", 0), 0, 31);
                var _eff = mod_int(mod_num(_cell, "effect", 0), 0, 15);
                var _par = mod_int(mod_num(_cell, "param", 0), 0, 255);
                var _pos = MOD_HEADER_SIZE + _pn * MOD_PATTERN_SIZE + r * 16 + c * 4;
                buffer_poke(_b, _pos, buffer_u8, (_smp & 0xf0) | ((_per >> 8) & 0x0f));
                buffer_poke(_b, _pos + 1, buffer_u8, _per & 0xff);
                buffer_poke(_b, _pos + 2, buffer_u8, ((_smp & 0x0f) << 4) | _eff);
                buffer_poke(_b, _pos + 3, buffer_u8, _par);
            }
        }
    }

    // sample data (signed 8-bit)
    buffer_seek(_b, buffer_seek_start, MOD_HEADER_SIZE + _npat * MOD_PATTERN_SIZE);
    for (var sd = 0; sd < 31; sd++)
    {
        var _di = _infos[sd];
        if (_di.bytes == 0) { continue; }
        var _start = buffer_tell(_b);
        var _data = _di.data;
        var _n = min(array_length(_data), _di.bytes);
        for (var i = 0; i < _n; i++)
        {
            var _v = _data[i];
            if (!is_numeric(_v)) { _v = 0; }
            buffer_write(_b, buffer_u8, mod_int(_v, -128, 127) & 0xff);
        }
        if (_n < _di.bytes) { buffer_write(_b, buffer_u8, 0); }
        if (_di.loop_len == 0)
        {
            buffer_poke(_b, _start, buffer_u8, 0);
            buffer_poke(_b, _start + 1, buffer_u8, 0);
        }
    }
    return _b;
}

/// Writes the MOD to a file. Returns true on success.
function mod_save_file(_ms, _path)
{
    var _b = mod_write(_ms);
    var _ok = true;
    try
    {
        buffer_save(_b, _path);
    }
    catch (_e)
    {
        _ok = false;
    }
    buffer_delete(_b);
    if (_ok) { _ok = file_exists(_path); }
    return _ok;
}

/// Parses a MOD held in a buffer. Never reads past the end.
/// Returns { song : modsong or undefined, err : "", warn : "" }.
function mod_parse(_b)
{
    var _res = { song : undefined, err : "", warn : "" };
    var _size = buffer_get_size(_b);
    if (_size < MOD_HEADER_SIZE + MOD_PATTERN_SIZE)
    {
        _res.err = "That file is too small to be a MOD";
        return _res;
    }

    var _tag = "";
    for (var i = 0; i < 4; i++)
    {
        var _c = buffer_peek(_b, 1080 + i, buffer_u8);
        if (_c < 32 || _c > 126) { _c = 63; }
        _tag += chr(_c);
    }
    if (_tag != "M.K." && _tag != "M!K!" && _tag != "FLT4" && _tag != "4CHN")
    {
        var _chn = string_copy(_tag, 2, 3) == "CHN" && string_digits(string_char_at(_tag, 1)) != "";
        var _ch2 = string_copy(_tag, 3, 2) == "CH" && string_digits(string_copy(_tag, 1, 2)) == string_copy(_tag, 1, 2);
        if (_chn || _ch2 || _tag == "FLT8" || _tag == "CD81" || _tag == "OKTA" || _tag == "OCTA" || _tag == "TDZ8")
        {
            _res.err = "This MOD has more than 4 channels (" + _tag + ") - the Amiga plays 4-channel MODs only";
        }
        else
        {
            _res.err = "Not a 31-sample ProTracker MOD (old 15-sample Soundtracker files: re-save as MOD in OpenMPT)";
        }
        return _res;
    }

    var _nord = buffer_peek(_b, 950, buffer_u8);
    if (_nord < 1 || _nord > 128)
    {
        _res.err = "That MOD is damaged (bad song length)";
        return _res;
    }
    // pattern count: highest entry in the whole order table, like ProTracker
    var _top = 0;
    for (var o = 0; o < 128; o++)
    {
        _top = max(_top, buffer_peek(_b, 952 + o, buffer_u8));
    }
    if (_top >= MOD_MAX_PATTERNS)
    {
        // junk past the song end: count the used entries only
        _top = 0;
        for (var u = 0; u < _nord; u++)
        {
            _top = max(_top, buffer_peek(_b, 952 + u, buffer_u8));
        }
    }
    if (_top >= MOD_MAX_PATTERNS)
    {
        _res.err = "That MOD is damaged (too many patterns)";
        return _res;
    }
    var _npat = _top + 1;
    var _data_at = MOD_HEADER_SIZE + _npat * MOD_PATTERN_SIZE;
    if (_data_at > _size)
    {
        _res.err = "That MOD is cut short (patterns missing)";
        return _res;
    }

    var _ms = {
        title : mod_get_text(_b, 0, 20),
        samples : array_create(31, undefined),
        order : array_create(_nord, 0),
        restart : 0,
        patterns : array_create(_npat, undefined)
    };
    var _rs = buffer_peek(_b, 951, buffer_u8);
    if (_rs < _nord) { _ms.restart = _rs; }
    for (var k = 0; k < _nord; k++)
    {
        _ms.order[k] = min(buffer_peek(_b, 952 + k, buffer_u8), _npat - 1);
    }

    for (var _pn = 0; _pn < _npat; _pn++)
    {
        var _pat = array_create(64, undefined);
        for (var r = 0; r < 64; r++)
        {
            var _row = array_create(4, undefined);
            for (var c = 0; c < 4; c++)
            {
                var _pos = MOD_HEADER_SIZE + _pn * MOD_PATTERN_SIZE + r * 16 + c * 4;
                var _b0 = buffer_peek(_b, _pos, buffer_u8);
                var _b1 = buffer_peek(_b, _pos + 1, buffer_u8);
                var _b2 = buffer_peek(_b, _pos + 2, buffer_u8);
                var _b3 = buffer_peek(_b, _pos + 3, buffer_u8);
                _row[c] = {
                    note : mod_period_to_note(((_b0 & 0x0f) << 8) | _b1),
                    sample : (_b0 & 0xf0) | (_b2 >> 4),
                    effect : _b2 & 0x0f,
                    param : _b3
                };
            }
            _pat[r] = _row;
        }
        _ms.patterns[_pn] = _pat;
    }

    var _at = _data_at;
    for (var s = 0; s < 31; s++)
    {
        var _p = 20 + s * 30;
        var _len = mod_peek16(_b, _p + 22) * 2;
        var _ft = buffer_peek(_b, _p + 24, buffer_u8) & 0x0f;
        if (_ft > 7) { _ft -= 16; }
        var _ls = mod_peek16(_b, _p + 26) * 2;
        var _ll = mod_peek16(_b, _p + 28) * 2;
        var _avail = max(0, _size - _at);
        if (_len > _avail)
        {
            _res.warn = "Some sample data was missing from the end of that MOD";
            _len = _avail - (_avail mod 2);
        }
        if (_ll <= 2 || _ls >= _len)
        {
            _ls = 0;
            _ll = 0;
        }
        else if (_ls + _ll > _len)
        {
            _ll = _len - _ls;
            if (_ll < 4)
            {
                _ls = 0;
                _ll = 0;
            }
        }
        var _data = array_create(_len, 0);
        if (_len > 0)
        {
            buffer_seek(_b, buffer_seek_start, _at);
            for (var j = 0; j < _len; j++)
            {
                _data[j] = buffer_read(_b, buffer_s8);
            }
        }
        _at += _len;
        _ms.samples[s] = {
            name : mod_get_text(_b, _p, 22),
            data : _data,
            volume : min(buffer_peek(_b, _p + 25, buffer_u8), 64),
            finetune : _ft,
            loop_start : _ls,
            loop_len : _ll
        };
    }
    _res.song = _ms;
    return _res;
}

/// Loads a MOD file. Returns a modsong, or undefined (with a toast) on failure.
function mod_read(_path)
{
    if (!file_exists(_path))
    {
        toast("Can't find " + filename_name(_path), 2);
        return undefined;
    }
    var _b = buffer_load(_path);
    if (!buffer_exists(_b))
    {
        toast("Couldn't read " + filename_name(_path), 2);
        return undefined;
    }
    var _res;
    try
    {
        _res = mod_parse(_b);
    }
    catch (_e)
    {
        _res = { song : undefined, err : "That MOD is damaged", warn : "" };
    }
    buffer_delete(_b);
    if (is_undefined(_res.song))
    {
        toast(_res.err, 2);
        return undefined;
    }
    if (_res.warn != "") { toast(_res.warn, 1); }
    return _res.song;
}

/// 64 x 4 empty cells
function mod_empty_pattern()
{
    var _pat = array_create(64, undefined);
    for (var r = 0; r < 64; r++)
    {
        var _row = array_create(4, undefined);
        for (var c = 0; c < 4; c++)
        {
            _row[c] = { note : 0, sample : 0, effect : 0, param : 0 };
        }
        _pat[r] = _row;
    }
    return _pat;
}

function mod_set_cell(_pat, _row, _ch, _note, _smp, _eff, _par)
{
    var _cells = _pat[_row];
    _cells[@ _ch] = { note : _note, sample : _smp, effect : _eff, param : _par };
}

/// The tiny song the self-test writes (2 samples, 2 patterns)
function mod_selftest_song()
{
    var _samples = array_create(31, undefined);
    for (var s = 0; s < 31; s++)
    {
        _samples[s] = { name : "", data : [], volume : 0, finetune : 0, loop_start : 0, loop_len : 0 };
    }
    var _sq = array_create(32, 0);
    for (var i = 0; i < 32; i++)
    {
        if (i < 16) { _sq[i] = 100; }
        else { _sq[i] = -100; }
    }
    _samples[0] = { name : "ADAM square", data : _sq, volume : 64, finetune : 0, loop_start : 0, loop_len : 32 };
    var _blip = array_create(40, 0);
    for (var j = 2; j < 40; j++)
    {
        _blip[j] = ((j * 37) mod 255) - 127;
    }
    _samples[1] = { name : "ADAM blip", data : _blip, volume : 48, finetune : -3, loop_start : 0, loop_len : 0 };

    var _p0 = mod_empty_pattern();
    mod_set_cell(_p0, 0, 0, 13, 1, 0x0c, 0x40);
    mod_set_cell(_p0, 4, 1, 1, 2, 0, 0);
    mod_set_cell(_p0, 8, 2, 36, 1, 0x0a, 0x04);
    mod_set_cell(_p0, 16, 3, 25, 2, 0x0f, 0x06);
    mod_set_cell(_p0, 63, 0, 0, 0, 0x0d, 0x00);
    var _p1 = mod_empty_pattern();
    mod_set_cell(_p1, 0, 0, 20, 2, 0x01, 0x03);
    mod_set_cell(_p1, 32, 3, 12, 1, 0, 0);
    mod_set_cell(_p1, 63, 1, 0, 0, 0x0b, 0x00);

    return {
        title : "ADAM self-test",
        samples : _samples,
        order : [0, 1, 1, 0],
        restart : 1,
        patterns : [_p0, _p1]
    };
}

/// First difference between two modsongs, or "" when they match
function mod_compare(_a, _b)
{
    if (_a.title != _b.title) { return "title"; }
    if (_a.restart != _b.restart) { return "restart"; }
    if (!array_equals(_a.order, _b.order)) { return "order"; }
    for (var s = 0; s < 31; s++)
    {
        var _sa = _a.samples[s];
        var _sb = _b.samples[s];
        if (_sa.name != _sb.name) { return "sample " + string(s + 1) + " name"; }
        if (_sa.volume != _sb.volume) { return "sample " + string(s + 1) + " volume"; }
        if (_sa.finetune != _sb.finetune) { return "sample " + string(s + 1) + " finetune"; }
        if (_sa.loop_start != _sb.loop_start) { return "sample " + string(s + 1) + " loop start"; }
        if (_sa.loop_len != _sb.loop_len) { return "sample " + string(s + 1) + " loop length"; }
        if (!array_equals(_sa.data, _sb.data)) { return "sample " + string(s + 1) + " data"; }
    }
    if (array_length(_a.patterns) != array_length(_b.patterns)) { return "pattern count"; }
    for (var _pn = 0; _pn < array_length(_a.patterns); _pn++)
    {
        for (var r = 0; r < 64; r++)
        {
            for (var c = 0; c < 4; c++)
            {
                var _ca = _a.patterns[_pn][r][c];
                var _cb = _b.patterns[_pn][r][c];
                if (_ca.note != _cb.note || _ca.sample != _cb.sample || _ca.effect != _cb.effect || _ca.param != _cb.param)
                {
                    return "pattern " + string(_pn) + " row " + string(r) + " channel " + string(c);
                }
            }
        }
    }
    return "";
}

/// Copies the first _n bytes of a buffer into a new fixed buffer
function mod_buffer_head(_src, _n)
{
    var _dst = buffer_create(_n, buffer_fixed, 1);
    buffer_copy(_src, 0, _n, _dst, 0);
    return _dst;
}

/// Dev-only (ADAM_DEV_TOOLS): writes a tiny MOD, reads it back, checks bad files
/// are rejected, and prints PASS/FAIL to the IDE Output window. Leaves
/// game_save_id + "adam_selftest.mod" for opening in OpenMPT / ProTracker.
function mod_selftest()
{
    var _ok = true;
    var _ms = mod_selftest_song();

    // sizes
    var _b = mod_write(_ms);
    var _want = MOD_HEADER_SIZE + 2 * MOD_PATTERN_SIZE + 32 + 40;
    if (buffer_get_size(_b) != mod_size(_ms) || mod_size(_ms) != _want)
    {
        _ok = false;
        show_debug_message("ADAM mod self-test: size " + string(buffer_get_size(_b)) + " / " + string(mod_size(_ms)) + ", expected " + string(_want));
    }

    // round trip through a file
    var _tmp = game_save_id + "adam_selftest_tmp.mod";
    if (!mod_save_file(_ms, _tmp))
    {
        _ok = false;
        show_debug_message("ADAM mod self-test: could not write " + _tmp);
    }
    else
    {
        var _back = mod_read(_tmp);
        if (is_undefined(_back))
        {
            _ok = false;
            show_debug_message("ADAM mod self-test: read-back failed");
        }
        else
        {
            var _diff = mod_compare(_ms, _back);
            if (_diff != "")
            {
                _ok = false;
                show_debug_message("ADAM mod self-test: read-back differs at " + _diff);
            }
        }
        file_delete(_tmp);
    }
    if (!mod_save_file(_ms, game_save_id + "adam_selftest.mod")) { _ok = false; }

    // bad files must be rejected (or warned about) without crashing
    var _t = mod_buffer_head(_b, MOD_HEADER_SIZE + 512);
    if (!is_undefined(mod_parse(_t).song)) { _ok = false; show_debug_message("ADAM mod self-test: cut-short patterns not rejected"); }
    buffer_delete(_t);
    _t = mod_buffer_head(_b, 600);
    if (!is_undefined(mod_parse(_t).song)) { _ok = false; show_debug_message("ADAM mod self-test: tiny file not rejected"); }
    buffer_delete(_t);
    _t = mod_buffer_head(_b, buffer_get_size(_b) - 10);
    var _r = mod_parse(_t);
    if (is_undefined(_r.song) || _r.warn == "") { _ok = false; show_debug_message("ADAM mod self-test: cut-short samples not handled"); }
    buffer_delete(_t);
    _t = mod_buffer_head(_b, buffer_get_size(_b));
    mod_put_text(_t, 1080, "8CHN", 4);
    if (!is_undefined(mod_parse(_t).song)) { _ok = false; show_debug_message("ADAM mod self-test: 8CHN not rejected"); }
    buffer_poke(_t, 1080, buffer_u8, 0);
    buffer_poke(_t, 1081, buffer_u8, 0x41);
    if (!is_undefined(mod_parse(_t).song)) { _ok = false; show_debug_message("ADAM mod self-test: untagged (15-sample) file not rejected"); }
    mod_put_text(_t, 1080, "FLT4", 4);
    if (is_undefined(mod_parse(_t).song)) { _ok = false; show_debug_message("ADAM mod self-test: FLT4 rejected"); }
    buffer_delete(_t);
    buffer_delete(_b);

    // periods: exact, finetuned and out of range
    if (mod_period_to_note(856) != 1 || mod_period_to_note(850) != 1 || mod_period_to_note(113) != 36
        || mod_period_to_note(1712) != 1 || mod_period_to_note(57) != 36 || mod_period_to_note(0) != 0
        || mod_period_to_note(424) != 13 || mod_period_to_note(226) != 24)
    {
        _ok = false;
        show_debug_message("ADAM mod self-test: period to note mapping wrong");
    }

    if (_ok) { show_debug_message("ADAM mod self-test: PASS (" + game_save_id + "adam_selftest.mod)"); }
    else { show_debug_message("ADAM mod self-test: FAIL"); }
    return _ok;
}
