/// ADAM - sound effects: rendered once into 8-bit samples for Paula.
/// The preview plays exactly the same samples the Amiga will play.

#macro SFX_RATE 11015
#macro SFX_MAX_SECONDS 1.5

/// Returns an array of signed 8-bit sample values (-127..127)
function sfx_render(_s)
{
    var _atk_ms = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000];
    var _dr_ms  = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000];
    var _rate = SFX_RATE;
    var _gate_s = clamp(_s.len, 1, 100) / 50;
    var _rel_s = min(_dr_ms[clamp(_s.rel, 0, 15)] / 1000, SFX_MAX_SECONDS);
    var _total = min(_gate_s + _rel_s, SFX_MAX_SECONDS);
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
    for (var i = 0; i < _n; i++)
    {
        var _t = i / _rate;
        var _f = floor(i / _spf);
        if (_f != _frame)
        {
            _frame = _f;
            if (_t < _gate_s) { _hi = (_hi + _s.sweep + 256) mod 256; }
        }
        var _hz = (_hi * 256) * 985248 / 16777216;
        _phase += _hz / _rate;
        _phase -= floor(_phase);
        var _v = 0;
        switch (_s.wave)
        {
            case 0: _v = 1 - 4 * abs(_phase - 0.5); break;
            case 1: _v = _phase * 2 - 1; break;
            case 2:
                if (_phase < 0.5) { _v = 1; }
                else { _v = -1; }
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
        _out[i] = round(clamp(_v * _env * 0.9, -1, 1) * 127);
    }
    return _out;
}

function sfx_preview_stop()
{
    if (preview_sound != -1)
    {
        audio_stop_sound(preview_inst);
        audio_free_buffer_sound(preview_sound);
        preview_sound = -1;
    }
    if (preview_buffer != -1)
    {
        buffer_delete(preview_buffer);
        preview_buffer = -1;
    }
}

#macro PAULA_CLOCK 3546895
#macro SMP_SRC_MAX_RATE 22050
#macro SMP_SRC_MAX_SECONDS 5
#macro SMP_OUT_MAX_SECONDS 3

/// Renders any sound. Returns { smp : signed 8-bit array, rate : Hz, period : Paula period, capped : bool }.
/// Results are cached until a setting changes.
function sfx_render_ex(_s)
{
    var _key = string(_s.kind) + "|" + string(_s.wave) + "|" + string(_s.pitch) + "|" + string(_s.sweep) + "|" + string(_s.len) + "|"
        + string(_s.atk) + string(_s.dec) + string(_s.sus) + string(_s.rel) + "|" + string(_s.rate) + "|" + string(_s.bits) + "|"
        + string(_s.gain) + "|" + string(_s.trim_a) + "|" + string(_s.trim_b) + "|" + string(_s.smp_len) + "|" + _s.smp_file + "|" + string(string_length(_s.smp));
    var _hit = snd_cache[$ _key];
    if (!is_undefined(_hit)) { return _hit; }
    var _res;
    if (_s.kind == 1) { _res = sfx_sample_render(_s); }
    else { _res = { smp : sfx_render(_s), rate : PAULA_CLOCK / 322, period : 322, capped : false }; }
    snd_cache_count += 1;
    if (snd_cache_count > 24)
    {
        snd_cache = {};
        snd_cache_count = 1;
    }
    snd_cache[$ _key] = _res;
    return _res;
}

/// Trims, resamples and crunches an imported sample
function sfx_sample_render(_s)
{
    var _out = [];
    var _period = clamp(round(PAULA_CLOCK / max(1000, _s.rate)), 124, 65535);
    var _rate = PAULA_CLOCK / _period;
    var _res = { smp : _out, rate : _rate, period : _period, capped : false };
    if (_s.smp == "" || _s.smp_len < 2) { return _res; }
    var _buf = buffer_base64_decode(_s.smp);
    var _n = min(_s.smp_len, buffer_get_size(_buf));
    var _a = floor(_n * clamp(_s.trim_a, 0, 1000) / 1000);
    var _b = floor(_n * clamp(_s.trim_b, 0, 1000) / 1000);
    if (_b <= _a + 1)
    {
        buffer_delete(_buf);
        return _res;
    }
    var _step = _s.smp_rate / _rate;
    var _len = floor((_b - _a) / _step);
    var _max = floor(SMP_OUT_MAX_SECONDS * _rate);
    if (_len > _max)
    {
        _len = _max;
        _res.capped = true;
    }
    _len = _len - (_len mod 2);
    _out = array_create(_len, 0);
    var _gain = _s.gain / 100;
    var _q = 1 << (8 - clamp(_s.bits, 1, 8));
    for (var i = 0; i < _len; i++)
    {
        var _pos = _a + i * _step;
        var _i0 = floor(_pos);
        var _f = _pos - _i0;
        var _v0 = buffer_peek(_buf, min(_i0, _n - 1), buffer_s8);
        var _v1 = buffer_peek(_buf, min(_i0 + 1, _n - 1), buffer_s8);
        var _v = (_v0 + (_v1 - _v0) * _f) * _gain;
        _v = clamp(round(_v), -128, 127);
        if (_q > 1) { _v = floor(_v / _q) * _q; }
        _out[i] = clamp(_v, -128, 127);
    }
    buffer_delete(_buf);
    _res.smp = _out;
    return _res;
}

/// Reads a .WAV file into sound _s (kept as an 8-bit mono source, up to 5 s at up to 22 kHz)
function sfx_import_wav(_s, _path)
{
    var _b = buffer_load(_path);
    if (_b == -1) { return false; }
    var _size = buffer_get_size(_b);
    if (_size < 44)
    {
        buffer_delete(_b);
        return false;
    }
    var _riff = chr(buffer_peek(_b, 0, buffer_u8)) + chr(buffer_peek(_b, 1, buffer_u8)) + chr(buffer_peek(_b, 2, buffer_u8)) + chr(buffer_peek(_b, 3, buffer_u8));
    var _wave = chr(buffer_peek(_b, 8, buffer_u8)) + chr(buffer_peek(_b, 9, buffer_u8)) + chr(buffer_peek(_b, 10, buffer_u8)) + chr(buffer_peek(_b, 11, buffer_u8));
    if (_riff != "RIFF" || _wave != "WAVE")
    {
        buffer_delete(_b);
        return false;
    }
    var _fmt = 0;
    var _ch = 0;
    var _rate = 0;
    var _bits = 0;
    var _data = -1;
    var _dlen = 0;
    var _o = 12;
    while (_o + 8 <= _size)
    {
        var _id = chr(buffer_peek(_b, _o, buffer_u8)) + chr(buffer_peek(_b, _o + 1, buffer_u8)) + chr(buffer_peek(_b, _o + 2, buffer_u8)) + chr(buffer_peek(_b, _o + 3, buffer_u8));
        var _len = buffer_peek(_b, _o + 4, buffer_u32);
        if (_id == "fmt ")
        {
            _fmt = buffer_peek(_b, _o + 8, buffer_u16);
            _ch = buffer_peek(_b, _o + 10, buffer_u16);
            _rate = buffer_peek(_b, _o + 12, buffer_u32);
            _bits = buffer_peek(_b, _o + 22, buffer_u16);
            if (_fmt == 65534 && _len >= 26) { _fmt = buffer_peek(_b, _o + 32, buffer_u16); }
        }
        if (_id == "data")
        {
            _data = _o + 8;
            _dlen = min(_len, _size - _data);
        }
        _o += 8 + _len + (_len mod 2);
    }
    var _bps = _bits div 8;
    if (_data < 0 || _ch < 1 || _rate < 1000 || _bps < 1 || _bps > 4 || (_fmt != 1 && _fmt != 3))
    {
        buffer_delete(_b);
        return false;
    }
    var _frames = _dlen div (_bps * _ch);
    // mono float source
    var _src = array_create(_frames, 0);
    var _peak = 0.0001;
    for (var f = 0; f < _frames; f++)
    {
        var _sum = 0;
        for (var c = 0; c < _ch; c++)
        {
            var _p = _data + (f * _ch + c) * _bps;
            var _v = 0;
            switch (_bps)
            {
                case 1: _v = (buffer_peek(_b, _p, buffer_u8) - 128) / 128; break;
                case 2: _v = buffer_peek(_b, _p, buffer_s16) / 32768; break;
                case 3:
                    var _w = buffer_peek(_b, _p, buffer_u8) | (buffer_peek(_b, _p + 1, buffer_u8) << 8) | (buffer_peek(_b, _p + 2, buffer_u8) << 16);
                    if (_w >= 8388608) { _w -= 16777216; }
                    _v = _w / 8388608;
                    break;
                case 4:
                    if (_fmt == 3) { _v = buffer_peek(_b, _p, buffer_f32); }
                    else { _v = buffer_peek(_b, _p, buffer_s32) / 2147483648; }
                    break;
            }
            _sum += _v;
        }
        _src[f] = _sum / _ch;
        _peak = max(_peak, abs(_src[f]));
    }
    buffer_delete(_b);
    // resample to at most 22 kHz, keep 5 seconds, normalise to full 8-bit
    var _nrate = min(_rate, SMP_SRC_MAX_RATE);
    var _step = _rate / _nrate;
    var _n = min(floor(_frames / _step), SMP_SRC_MAX_SECONDS * _nrate);
    if (_n < 2) { return false; }
    var _ob = buffer_create(_n, buffer_fixed, 1);
    for (var i = 0; i < _n; i++)
    {
        var _pos = i * _step;
        var _i0 = floor(_pos);
        var _fr = _pos - _i0;
        var _a0 = _src[min(_i0, _frames - 1)];
        var _a1 = _src[min(_i0 + 1, _frames - 1)];
        var _val = (_a0 + (_a1 - _a0) * _fr) / _peak;
        buffer_write(_ob, buffer_s8, clamp(round(_val * 127), -127, 127));
    }
    _s.smp = buffer_base64_encode(_ob, 0, _n);
    buffer_delete(_ob);
    _s.smp_rate = _nrate;
    _s.smp_len = _n;
    _s.smp_file = filename_name(_path);
    _s.kind = 1;
    _s.trim_a = 0;
    _s.trim_b = 1000;
    _s.gain = 100;
    var _nm = filename_change_ext(filename_name(_path), "");
    _s.name = string_copy(_nm, 1, 16);
    return true;
}

function sfx_preview_play(_s)
{
    sfx_preview_stop();
    var _r = sfx_render_ex(_s);
    var _smp = _r.smp;
    var _n = array_length(_smp);
    if (_n < 2) { return; }
    preview_buffer = buffer_create(_n * 2, buffer_fixed, 2);
    for (var i = 0; i < _n; i++)
    {
        buffer_write(preview_buffer, buffer_s16, _smp[i] * 200);
    }
    preview_sound = audio_create_buffer_sound(preview_buffer, buffer_s16, clamp(round(_r.rate), 1000, 48000), 0, _n * 2, audio_mono);
    preview_inst = audio_play_sound(preview_sound, 1, false);
}
