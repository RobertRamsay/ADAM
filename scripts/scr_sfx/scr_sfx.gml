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
                    _rnd = (_rnd * 1103515245 + 12345) & $7fffffff;
                    _noise = (_rnd / $3fffffff) - 1;
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

function sfx_preview_play(_s)
{
    sfx_preview_stop();
    var _smp = sfx_render(_s);
    var _n = array_length(_smp);
    if (_n < 2) { return; }
    preview_buffer = buffer_create(_n * 2, buffer_fixed, 2);
    for (var i = 0; i < _n; i++)
    {
        buffer_write(preview_buffer, buffer_s16, _smp[i] * 200);
    }
    preview_sound = audio_create_buffer_sound(preview_buffer, buffer_s16, SFX_RATE, 0, _n * 2, audio_mono);
    preview_inst = audio_play_sound(preview_sound, 1, false);
}
