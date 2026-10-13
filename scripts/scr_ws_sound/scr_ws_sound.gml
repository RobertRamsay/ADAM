/// ADAM - Sound workspace (Paula sample effects)

function ws_sound_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 240;
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "Sounds");
    var _ly = _y1 + 54;
    for (var i = 0; i < 8; i++)
    {
        var _ry = _ly + i * 52;
        var _id = "snd_slot_" + string(i);
        var _f = proj.sfx[i];
        var _hot = ui_register(_id, _x1 + 10, _ry, _x1 + _lw - 10, _ry + 46, _f.name + "|Click to edit this sound. Rules on the Logic page can play it.");
        var _tgt = 0;
        if (_hot) { _tgt = 1; }
        var _a = ui_anim_to(_id, _tgt);
        if (snd_sel == i) { ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + 46, 10, global.TH.accent, global.TH.accent_dark, 0.9); }
        else { ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + 46, 10, global.TH.btn_hot_top, global.TH.btn_hot_bot, 0.25 + _a * 0.75); }
        ui_text(_x1 + 24, _ry + 15, string(i + 1) + ". " + ui_text_fit(_f.name, global.f_bold, _lw - 140), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        var _sub = global.WAVE_NAMES[clamp(_f.wave, 0, 3)];
        if (_f.kind == 1) { _sub = "Sample: " + _f.smp_file; }
        ui_text(_x1 + 24, _ry + 33, ui_text_fit(_sub, global.f_small, _lw - 110), global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        if (ui_button(_id + "_play", _x1 + _lw - 76, _ry + 8, 56, 30, "Play", "Play|Hear this sound.", BTN_GHOST))
        {
            sfx_preview_play(_f);
        }
        if (_hot && ui_pressed)
        {
            if (mus_playing && (mus_play_what == "sound" || mus_play_what == "sound_note")) { sfx_preview_stop(); }
            snd_sel = i;
            ui_take_click();
        }
    }

    var _cx1 = _x1 + _lw + 12;
    var _s = proj.sfx[snd_sel];
    ui_panel(_cx1, _y1, _x2, _y2, "Sound " + string(snd_sel + 1));
    var _fx = _cx1 + 20;
    var _colw = min(420, floor((_x2 - _cx1 - 60) / 2));
    var _y = _y1 + 56;
    ui_heading(_fx, _y, "Name");
    set_val(_s, "name", ui_textfield("snd_name", _fx, _y + 18, _colw, 32, _s.name, 16, "Sound name|Shown in the Logic page when you pick a sound to play."), "sndname");
    _y += 62;
    ui_heading(_fx, _y, "Type of sound");
    var _kw = floor((_colw - 8) / 2);
    var _k0 = BTN_GHOST;
    var _k1 = BTN_GHOST;
    if (_s.kind == 0) { _k0 = BTN_ACCENT; }
    else { _k1 = BTN_ACCENT; }
    if (ui_button("snd_kind_0", _fx, _y + 18, _kw, 32, "Synth", "Synth sound|Built from a waveform, pitch slide and envelope. Tiny in memory.", _k0)) { set_val(_s, "kind", 0, "sndkind" + string(current_time)); }
    if (ui_button("snd_kind_1", _fx + _kw + 8, _y + 18, _kw, 32, "Sample", "Sampled sound|Import a WAV - a voice, a drum hit, a real explosion - then crunch it down for Paula with the rate and bit settings.", _k1)) { set_val(_s, "kind", 1, "sndkind" + string(current_time)); }
    _y += 62;
    if (keyboard_check_pressed(vk_space) && ui_focus == "" && ui_can_input() && !keyboard_check(vk_control)) { sfx_preview_play(_s); }
    if (_s.kind == 1)
    {
        sound_sample_panel(_s, _fx, _y, _colw, _cx1, _x2, _y1, _y2);
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
    ui_inset(_gx, _gy, _gx + _gw, _gy + 170, 10);
    ui_register("snd_graph", _gx, _gy, _gx + _gw, _gy + 170, "Waveform|The sample after trimming, resampling and bit crunch. The vertical marker shows its current playback position.");
    var _n = array_length(_r.smp);
    var _mid = _gy + 85;
    if (_r.loop_len >= 4 && _n > 0)
    {
        var _loop_x1 = _gx + 10 + (_gw - 20) * _r.loop_start / _n;
        var _loop_x2 = _gx + 10 + (_gw - 20) * (_r.loop_start + _r.loop_len) / _n;
        var _loop_col = make_colour_rgb(80, 220, 120);
        draw_set_alpha(0.15);
        draw_rectangle_colour(_loop_x1, _gy + 8, _loop_x2, _gy + 162, _loop_col, _loop_col, _loop_col, _loop_col, false);
        draw_set_alpha(1);
        draw_line_width_colour(_loop_x1, _gy + 8, _loop_x1, _gy + 162, 2, _loop_col, _loop_col);
        draw_line_width_colour(_loop_x2, _gy + 8, _loop_x2, _gy + 162, 2, _loop_col, _loop_col);
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
            draw_line(_gx + 10 + c, _mid - _hi / 128 * 75, _gx + 10 + c, _mid - _lo / 128 * 75 + 1);
        }
    }
    var _progress = sfx_preview_progress(_s, _r);
    if (_progress >= 0)
    {
        var _marker_x = _gx + 10 + _progress * max(1, _gw - 21);
        draw_line_width_colour(_marker_x, _gy + 8, _marker_x, _gy + 162, 2, global.TH.warn, global.TH.warn);
    }
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
