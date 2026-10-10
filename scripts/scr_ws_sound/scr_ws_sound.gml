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
        ui_text(_x1 + 24, _ry + 15, string(i + 1) + ". " + ui_text_fit(_f.name, global.f_bold, _lw - 120), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        ui_text(_x1 + 24, _ry + 33, global.WAVE_NAMES[clamp(_f.wave, 0, 3)], global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
        if (ui_button(_id + "_play", _x1 + _lw - 64, _ry + 8, 44, 30, "Play", "Play|Hear this sound.", BTN_GHOST))
        {
            sfx_preview_play(_f);
        }
        if (_hot && ui_pressed)
        {
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
    _y += 66;
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
        _y += 34;
    }
    _y += 10;
    if (ui_button("snd_preview", _fx, _y, _colw, 44, "Play sound", "Play|Hear the sound exactly as the Amiga will play it - ADAM turns it into an 8-bit sample for Paula.", BTN_ACCENT))
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
    ui_text_wrap(_gx, _py, "ADAM turns each sound into an 8-bit sample (about 11 kHz, up to 1.5 seconds) stored in chip RAM. Sounds play on Paula channel 1 to 4 (sound number 1 and 5 share channel 1, and so on).", global.TH.text_faint, _gw, global.f_small, 1);
}
