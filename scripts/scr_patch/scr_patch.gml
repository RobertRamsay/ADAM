/// ADAM - Patch sounds (Sound page, kind 2): an elaborate synth that ADAM
/// renders into one 8-bit sample for Paula. Three oscillators (sync, ring,
/// FM, unison), a resonant filter with its own envelope, amp and pitch
/// envelopes, two LFOs and three modulation slots, chorus / drive / crush /
/// echo, and a one-shot or looped (sustaining) sample.
///
/// The sample is rendered at the Paula rate of the tracker note with the same
/// pitch class as the patch's note (C-2..B-2, or C-3..B-3 in high quality),
/// so it plays in tune both as a sound effect and as a Music page instrument.
/// The disk format does not change: a patch is just another sample.

#macro PATCH_MAX_SECONDS 6
#macro PATCH_BLOCK 16          // samples between envelope / LFO / filter updates

function patch_defs_init()
{
    var _waves = ["Saw", "Square", "Triangle", "Sine", "Noise"];
    var _lfo = ["Sine", "Triangle", "Square", "Saw", "Random"];
    var _src = ["None", "LFO 1", "LFO 2", "Filter env", "Amp env", "Pitch env"];
    var _dst = ["Pitch", "Osc 2 pitch", "Pulse width", "Cutoff", "Resonance", "Volume", "FM amount", "Osc 2 level"];
    // [name, min, max, kind (0 slider, 1 list, 2 toggle), label, help, list or format]
    // formats: 0 number, 1 %, 2 semitones, 3 cents, 4 env time, 5 LFO Hz, 6 seconds, 7 octaves, 8 echo ms, 9 note, 10 voices, 11 bits, 12 rate
    global.PATCH_DEF = [
        ["key", 0, 59, 0, "Note", "Note|The pitch the patch is made at. As a music instrument it plays in tune on every note; as a sound effect this is the note you hear.", 9],
        ["hq", 0, 1, 2, "High quality", "High quality|Renders at twice the sample rate (16-29 kHz). Brighter and cleaner, but it uses twice the chip RAM.", 0],
        ["o1_wave", 0, 4, 1, "Wave", "Oscillator 1 wave|Saw is bright and buzzy, square is the classic chip sound (set its pulse width), triangle and sine are soft, noise is for drums and effects.", _waves],
        ["o1_oct", -3, 3, 0, "Octave", "Octave|Moves this oscillator up or down by whole octaves.", 7],
        ["o1_semi", -12, 12, 0, "Semitones", "Semitones|Tunes this oscillator in semitones: +7 is a fifth above, +12 an octave.", 2],
        ["o1_fine", -50, 50, 0, "Fine tune", "Fine tune|Detunes slightly, in cents. Two oscillators a few cents apart sound thick and chorused.", 3],
        ["o1_lvl", 0, 100, 0, "Level", "Level|How loud this oscillator is in the mix. 0 switches it off (it can still modulate another).", 1],
        ["o1_pw", 5, 95, 0, "Pulse width", "Pulse width|For the square wave: 50% is hollow, small or large values are thin and nasal.", 1],
        ["o2_wave", 0, 4, 1, "Wave", "Oscillator 2 wave|The second oscillator. It can be synced to oscillator 1, ring-modulate it or FM it.", _waves],
        ["o2_oct", -3, 3, 0, "Octave", "Octave|Moves this oscillator up or down by whole octaves.", 7],
        ["o2_semi", -12, 12, 0, "Semitones", "Semitones|Tunes this oscillator in semitones.", 2],
        ["o2_fine", -50, 50, 0, "Fine tune", "Fine tune|Detunes slightly, in cents.", 3],
        ["o2_lvl", 0, 100, 0, "Level", "Level|How loud oscillator 2 is in the mix.", 1],
        ["o2_pw", 5, 95, 0, "Pulse width", "Pulse width|For the square wave.", 1],
        ["o3_wave", 0, 4, 1, "Wave", "Oscillator 3 wave|A third oscillator - noise here adds breath or a drum crack.", _waves],
        ["o3_oct", -3, 3, 0, "Octave", "Octave|Moves this oscillator up or down by whole octaves.", 7],
        ["o3_semi", -12, 12, 0, "Semitones", "Semitones|Tunes this oscillator in semitones.", 2],
        ["o3_fine", -50, 50, 0, "Fine tune", "Fine tune|Detunes slightly, in cents.", 3],
        ["o3_lvl", 0, 100, 0, "Level", "Level|How loud oscillator 3 is in the mix.", 1],
        ["o3_pw", 5, 95, 0, "Pulse width", "Pulse width|For the square wave.", 1],
        ["sync", 0, 1, 2, "Sync osc 2 to osc 1", "Hard sync|Oscillator 2 restarts every time oscillator 1 does. Tune osc 2 higher (or sweep its pitch) for the classic tearing sync lead.", 0],
        ["ring", 0, 1, 2, "Ring mod osc 2 by osc 1", "Ring modulation|Multiplies oscillator 2 by oscillator 1: metallic, bell-like and robotic tones.", 0],
        ["fm", 0, 100, 0, "FM amount", "Frequency modulation|Oscillator 2 bends the phase of oscillator 1. Sine waves with osc 2 an octave or a fifth up make bells and electric pianos. Osc 2 can stay at level 0.", 1],
        ["amp_a", 0, 100, 0, "Attack", "Attack|How quickly the sound fades in.", 4],
        ["amp_d", 0, 100, 0, "Decay", "Decay|How quickly it falls from full volume to the sustain level.", 4],
        ["amp_s", 0, 100, 0, "Sustain", "Sustain|The volume held while the note is on. 0 makes plucks and drums.", 1],
        ["amp_r", 0, 100, 0, "Release", "Release|How long it fades after the note ends (one-shot sounds).", 4],
        ["gate", 1, 400, 0, "Note length", "Note length|How long the note is held before the release, for one-shot sounds.", 6],
        ["vol", 0, 100, 0, "Volume", "Volume|Overall level. ADAM makes the loudest moment full scale first, so lower this only to balance it against other sounds.", 1],
        ["penv", -48, 48, 0, "Pitch drop", "Pitch envelope|The pitch starts this many semitones away and glides back to the note. Positive values fall (kicks, lasers), negative values rise (risers).", 2],
        ["pdec", 0, 100, 0, "Pitch time", "Pitch envelope time|How long the pitch takes to glide back.", 4],
        ["loop", 0, 1, 2, "Looped sustain", "Looped sustain|Keeps the attack, then loops a stretch of the held note so it sustains as long as a music note lasts - pads and organs - for little chip RAM. A sound effect plays the attack and one pass of the loop.", 0],
        ["loop_len", 5, 200, 0, "Loop length", "Loop length|How much of the held note is looped. Longer loops keep slow LFO movement and chorus smooth but use more chip RAM.", 6],
        ["flt", 0, 3, 1, "Filter", "Filter type|Low-pass makes it darker, high-pass thinner, band-pass keeps a band in the middle (vocal, telephone).", ["Off", "Low-pass", "High-pass", "Band-pass"]],
        ["cut", 0, 100, 0, "Cutoff", "Cutoff|Where the filter cuts, from deep bass to the top.", 1],
        ["res", 0, 100, 0, "Resonance", "Resonance|Boosts the cutoff frequency: squelchy and whistling when high.", 1],
        ["fenv", -100, 100, 0, "Env amount", "Filter envelope amount|How far the filter envelope opens (+) or closes (-) the cutoff, up to six octaves.", 1],
        ["ktrk", 0, 100, 0, "Key follow", "Key follow|How much the cutoff follows the note, so high notes are as bright as low ones.", 1],
        ["fa", 0, 100, 0, "Attack", "Filter attack|How quickly the filter envelope rises.", 4],
        ["fd", 0, 100, 0, "Decay", "Filter decay|How quickly it falls to its sustain level - short for plucks and acid basses.", 4],
        ["fs", 0, 100, 0, "Sustain", "Filter sustain|Where the filter envelope rests while the note is held.", 1],
        ["fr", 0, 100, 0, "Release", "Filter release|How quickly it falls after the note ends.", 4],
        ["l1_wave", 0, 4, 1, "LFO 1 shape", "LFO 1 shape|A slow wave that moves other settings (pick where it goes in the slots below).", _lfo],
        ["l1_rate", 0, 100, 0, "LFO 1 rate", "LFO 1 rate|From one wobble every 20 seconds to 25 a second.", 5],
        ["l1_dly", 0, 100, 0, "LFO 1 delay", "LFO 1 delay|The LFO fades in after this long - delayed vibrato.", 4],
        ["l2_wave", 0, 4, 1, "LFO 2 shape", "LFO 2 shape|A second slow wave.", _lfo],
        ["l2_rate", 0, 100, 0, "LFO 2 rate", "LFO 2 rate|From one wobble every 20 seconds to 25 a second.", 5],
        ["l2_dly", 0, 100, 0, "LFO 2 delay", "LFO 2 delay|The LFO fades in after this long.", 4],
        ["m1_src", 0, 5, 1, "Source", "Modulation source|What moves the setting: an LFO or one of the envelopes.", _src],
        ["m1_dst", 0, 7, 1, "Target", "Modulation target|The setting that is moved.", _dst],
        ["m1_amt", -100, 100, 0, "Amount", "Modulation amount|How far, and which way. Small amounts on pitch make vibrato.", 1],
        ["m2_src", 0, 5, 1, "Source", "Modulation source|What moves the setting.", _src],
        ["m2_dst", 0, 7, 1, "Target", "Modulation target|The setting that is moved.", _dst],
        ["m2_amt", -100, 100, 0, "Amount", "Modulation amount|How far, and which way.", 1],
        ["m3_src", 0, 5, 1, "Source", "Modulation source|What moves the setting.", _src],
        ["m3_dst", 0, 7, 1, "Target", "Modulation target|The setting that is moved.", _dst],
        ["m3_amt", -100, 100, 0, "Amount", "Modulation amount|How far, and which way.", 1],
        ["uni", 1, 4, 0, "Unison", "Unison|Stacks up to four detuned copies of every oscillator for a huge, wide sound.", 10],
        ["udet", 0, 50, 0, "Spread", "Unison spread|How far apart the unison copies are, in cents.", 3],
        ["cho", 0, 100, 0, "Chorus", "Chorus|Mixes in a slowly wobbling copy: shimmer for pads, strings and pianos.", 1],
        ["drive", 0, 100, 0, "Drive", "Drive|Soft distortion after the filter: warmth at first, then grit.", 1],
        ["bits", 2, 8, 0, "Bits", "Bit crush|Throws away detail: 8 is Paula's full quality, fewer bits are lo-fi.", 11],
        ["srd", 1, 8, 0, "Rate crush", "Rate crush|Holds each sample for longer: 1 is off, higher numbers are crunchier and more metallic.", 12],
        ["dtime", 0, 100, 0, "Echo time", "Echo time|The gap between echoes, from 10 to 500 ms.", 8],
        ["dfb", 0, 90, 0, "Echo repeats", "Echo feedback|How much of each echo comes back again.", 1],
        ["dmix", 0, 100, 0, "Echo mix", "Echo mix|How loud the echoes are. 0 switches the echo off.", 1]
    ];
    global.PATCH_IDX = {};
    for (var i = 0; i < array_length(global.PATCH_DEF); i++) { global.PATCH_IDX[$ global.PATCH_DEF[i][0]] = global.PATCH_DEF[i]; }

    // Preset patches: [name, settings that differ from patch_new()]
    global.PATCH_PRESETS = [
        ["Init", {}],
        ["Acid bass", { key : 12, o1_wave : 0, flt : 1, cut : 30, res : 78, fenv : 60, fd : 30, fs : 0, amp_d : 40, amp_s : 60, amp_r : 10, gate : 25, drive : 35 }],
        ["Sub bass", { key : 12, o1_wave : 3, o2_wave : 2, o2_oct : 1, o2_lvl : 25, flt : 0, amp_a : 3, amp_d : 50, amp_s : 90, amp_r : 20, gate : 50 }],
        ["Pluck bass", { key : 12, o1_wave : 1, o1_pw : 30, flt : 1, cut : 38, res : 30, fenv : 50, fd : 25, fs : 0, amp_d : 35, amp_s : 0, amp_r : 15, gate : 25 }],
        ["Fat saw bass", { key : 12, o1_wave : 0, o2_wave : 0, o2_fine : 14, o2_lvl : 100, o2_oct : -1, flt : 1, cut : 45, res : 20, fenv : 25, fd : 40, fs : 20, amp_s : 80, gate : 40 }],
        ["Square lead", { key : 36, o1_wave : 1, o2_wave : 1, o2_oct : 1, o2_lvl : 25, o2_fine : 5, flt : 1, cut : 80, l1_rate : 56, l1_dly : 35, m1_src : 1, m1_dst : 0, m1_amt : 14, amp_a : 3, amp_d : 30, amp_s : 80, amp_r : 25, gate : 60 }],
        ["Saw lead", { key : 36, o1_wave : 0, o2_wave : 0, o2_fine : 10, o2_lvl : 80, flt : 1, cut : 72, res : 22, l1_rate : 55, l1_dly : 40, m1_src : 1, m1_dst : 0, m1_amt : 12, amp_a : 2, amp_s : 85, amp_r : 25, gate : 60, cho : 25 }],
        ["Sync lead", { key : 36, o1_lvl : 0, o2_wave : 0, o2_lvl : 100, o2_oct : 1, sync : 1, m1_src : 3, m1_dst : 1, m1_amt : 75, fa : 0, fd : 45, fs : 20, flt : 1, cut : 85, amp_s : 85, gate : 60 }],
        ["FM bell", { key : 36, o1_wave : 3, o2_wave : 3, o2_oct : 1, o2_semi : 7, o2_lvl : 0, fm : 55, m1_src : 4, m1_dst : 6, m1_amt : 50, flt : 0, amp_a : 0, amp_d : 75, amp_s : 0, amp_r : 60, gate : 30, dmix : 20, dtime : 40 }],
        ["E-piano", { key : 24, o1_wave : 3, o2_wave : 3, o2_oct : 2, o2_lvl : 0, fm : 30, m1_src : 4, m1_dst : 6, m1_amt : 45, flt : 0, amp_d : 62, amp_s : 30, amp_r : 40, gate : 60, cho : 35 }],
        ["Organ", { key : 24, o1_wave : 3, o2_wave : 3, o2_oct : 1, o2_lvl : 60, o3_wave : 3, o3_oct : 2, o3_lvl : 40, flt : 0, amp_a : 2, amp_d : 10, amp_s : 100, amp_r : 10, loop : 1, loop_len : 25, cho : 30 }],
        ["Warm pad", { key : 24, o1_wave : 0, o2_wave : 0, o2_fine : 15, o2_lvl : 100, uni : 3, udet : 15, flt : 1, cut : 48, res : 10, l1_rate : 18, m1_src : 1, m1_dst : 3, m1_amt : 25, amp_a : 55, amp_d : 60, amp_s : 80, amp_r : 60, loop : 1, loop_len : 80, cho : 40 }],
        ["Strings", { key : 24, o1_wave : 0, o2_wave : 0, o2_fine : -10, o2_lvl : 100, uni : 4, udet : 20, flt : 1, cut : 60, amp_a : 45, amp_d : 40, amp_s : 90, amp_r : 50, loop : 1, loop_len : 80, cho : 50, l1_rate : 55, l1_dly : 50, m1_src : 1, m1_dst : 0, m1_amt : 8 }],
        ["Choir", { key : 24, o1_wave : 0, o2_wave : 1, o2_pw : 30, o2_fine : 8, o2_lvl : 70, flt : 3, cut : 58, res : 45, l1_rate : 30, m1_src : 1, m1_dst : 3, m1_amt : 12, amp_a : 40, amp_s : 90, amp_r : 45, loop : 1, loop_len : 60, cho : 45 }],
        ["Glass pad", { key : 36, o1_wave : 2, o2_wave : 3, o2_oct : 1, o2_lvl : 50, ring : 0, flt : 1, cut : 75, amp_a : 50, amp_s : 80, amp_r : 50, loop : 1, loop_len : 60, cho : 45, l1_rate : 20, m1_src : 1, m1_dst : 7, m1_amt : 40 }],
        ["Pluck", { key : 36, o1_wave : 1, o1_pw : 25, flt : 1, cut : 50, fenv : 50, fd : 20, fs : 0, amp_d : 30, amp_s : 0, amp_r : 20, gate : 20, dmix : 25, dtime : 35, dfb : 30 }],
        ["Harp", { key : 36, o1_wave : 2, o2_wave : 0, o2_oct : 1, o2_lvl : 20, flt : 1, cut : 65, amp_d : 55, amp_s : 0, amp_r : 50, gate : 30, dmix : 20, dtime : 30 }],
        ["Chip arp", { key : 36, o1_wave : 1, o1_pw : 12, l1_wave : 2, l1_rate : 70, m1_src : 1, m1_dst : 2, m1_amt : 60, flt : 0, amp_d : 25, amp_s : 60, amp_r : 10, gate : 30, bits : 6 }],
        ["Kick", { key : 12, o1_wave : 3, penv : 36, pdec : 18, flt : 0, amp_a : 0, amp_d : 32, amp_s : 0, amp_r : 10, gate : 15, drive : 25 }],
        ["Snare", { key : 24, o1_wave : 2, o1_lvl : 60, penv : 12, pdec : 10, o3_wave : 4, o3_lvl : 100, flt : 3, cut : 72, res : 10, amp_d : 25, amp_s : 0, amp_r : 15, gate : 12 }],
        ["Hi-hat", { key : 48, o1_lvl : 0, o3_wave : 4, o3_lvl : 100, flt : 2, cut : 86, res : 20, amp_d : 12, amp_s : 0, amp_r : 8, gate : 4 }],
        ["Clap", { key : 36, o1_lvl : 0, o3_wave : 4, o3_lvl : 100, flt : 3, cut : 68, res : 30, amp_d : 20, amp_s : 0, amp_r : 18, gate : 6, dmix : 35, dtime : 3, dfb : 40 }],
        ["Tom", { key : 19, o1_wave : 3, penv : 12, pdec : 30, flt : 0, amp_d : 40, amp_s : 0, amp_r : 20, gate : 15 }],
        ["Laser", { key : 48, o1_wave : 1, penv : 36, pdec : 26, flt : 0, amp_d : 35, amp_s : 0, amp_r : 10, gate : 15, dmix : 25, dtime : 20 }],
        ["Zap", { key : 40, o1_wave : 0, o2_wave : 3, o2_oct : 1, o2_lvl : 0, fm : 40, penv : -30, pdec : 12, flt : 0, amp_d : 25, amp_s : 0, amp_r : 10, gate : 10 }],
        ["Riser", { key : 24, o1_wave : 0, o2_wave : 0, o2_fine : 15, o2_lvl : 100, o3_wave : 4, o3_lvl : 30, penv : -24, pdec : 80, flt : 1, cut : 30, fenv : 70, fa : 80, fs : 100, amp_a : 80, amp_s : 100, amp_r : 30, gate : 150 }],
        ["Explosion", { key : 12, o1_lvl : 0, o3_wave : 4, o3_lvl : 100, flt : 1, cut : 55, fenv : 50, fa : 0, fd : 60, fs : 0, amp_d : 75, amp_s : 0, amp_r : 50, gate : 20, drive : 40, srd : 3 }],
        ["Wind", { key : 24, o1_lvl : 0, o3_wave : 4, o3_lvl : 100, flt : 3, cut : 45, res : 60, l1_rate : 10, m1_src : 1, m1_dst : 3, m1_amt : 60, amp_a : 60, amp_s : 100, amp_r : 60, gate : 200 }]
    ];
    global.PATCH_PRESET_NAMES = [];
    global.PATCH_PRESET_MENU = ["Choose a preset..."];
    for (var p = 0; p < array_length(global.PATCH_PRESETS); p++)
    {
        array_push(global.PATCH_PRESET_NAMES, global.PATCH_PRESETS[p][0]);
        array_push(global.PATCH_PRESET_MENU, global.PATCH_PRESETS[p][0]);
    }
}

function patch_new()
{
    return {
        key : 24, hq : 0,
        o1_wave : 0, o1_oct : 0, o1_semi : 0, o1_fine : 0, o1_lvl : 100, o1_pw : 50,
        o2_wave : 1, o2_oct : 0, o2_semi : 0, o2_fine : 7, o2_lvl : 0, o2_pw : 50,
        o3_wave : 4, o3_oct : 0, o3_semi : 0, o3_fine : 0, o3_lvl : 0, o3_pw : 50,
        sync : 0, ring : 0, fm : 0,
        amp_a : 2, amp_d : 30, amp_s : 70, amp_r : 25, gate : 40, vol : 80,
        penv : 0, pdec : 20, loop : 0, loop_len : 25,
        flt : 1, cut : 70, res : 15, fenv : 0, ktrk : 50, fa : 0, fd : 35, fs : 0, fr : 30,
        l1_wave : 0, l1_rate : 40, l1_dly : 0, l2_wave : 0, l2_rate : 20, l2_dly : 0,
        m1_src : 0, m1_dst : 0, m1_amt : 0, m2_src : 0, m2_dst : 3, m2_amt : 0, m3_src : 0, m3_dst : 5, m3_amt : 0,
        uni : 1, udet : 12, cho : 0, drive : 0, bits : 8, srd : 1, dtime : 30, dfb : 30, dmix : 0
    };
}

/// A patch read from a file: every known setting, clamped; anything else ignored
function patch_from_loaded(_raw)
{
    var _p = patch_new();
    if (!is_struct(_raw)) { return _p; }
    for (var i = 0; i < array_length(global.PATCH_DEF); i++)
    {
        var _d = global.PATCH_DEF[i];
        var _v = _raw[$ _d[0]];
        if (is_numeric(_v)) { _p[$ _d[0]] = clamp(round(_v), _d[1], _d[2]); }
    }
    return _p;
}

function patch_apply_preset(_p, _i)
{
    var _fresh = patch_new();
    var _over = global.PATCH_PRESETS[clamp(_i, 0, array_length(global.PATCH_PRESETS) - 1)][1];
    var _names = variable_struct_get_names(_fresh);
    for (var i = 0; i < array_length(_names); i++) { _p[$ _names[i]] = _fresh[$ _names[i]]; }
    var _on = variable_struct_get_names(_over);
    for (var k = 0; k < array_length(_on); k++) { _p[$ _on[k]] = _over[$ _on[k]]; }
}

/// Randomise (_amount 1) or mutate (_amount < 1: nudge some settings)
function patch_randomise(_p, _amount)
{
    for (var i = 0; i < array_length(global.PATCH_DEF); i++)
    {
        var _d = global.PATCH_DEF[i];
        if (_d[0] == "key" || _d[0] == "hq" || _d[0] == "vol" || _d[0] == "loop") { continue; }
        if (_amount >= 1)
        {
            _p[$ _d[0]] = irandom_range(_d[1], _d[2]);
        }
        else if (random(1) < 0.35 && _d[3] == 0)
        {
            var _span = (_d[2] - _d[1]) * _amount;
            _p[$ _d[0]] = clamp(round(_p[$ _d[0]] + random_range(-_span, _span)), _d[1], _d[2]);
        }
    }
    if (_amount >= 1)
    {
        // keep it playable: something audible, not too long, not too crushed
        _p.o1_lvl = irandom_range(60, 100);
        _p.amp_s = irandom_range(0, 100);
        _p.gate = irandom_range(10, 120);
        _p.amp_a = irandom_range(0, 50);
        _p.amp_r = irandom_range(5, 60);
        _p.bits = choose(8, 8, 8, 7, 6);
        _p.srd = choose(1, 1, 1, 2);
        _p.res = irandom_range(0, 70);
        _p.cut = irandom_range(25, 100);
        _p.uni = choose(1, 1, 2, 3);
        _p.dfb = irandom_range(0, 60);
        if (_p.flt == 2) { _p.cut = irandom_range(10, 60); }
    }
}

function patch_env_ms(_v) { return 1 + 0.8 * _v * _v; }
function patch_lfo_hz(_v) { return 0.05 * power(2, _v / 100 * 9); }

/// The frequency of patch note _key (0 = C1 ... 59 = B5)
function patch_key_hz(_key) { return 32.7032 * power(2, _key / 12); }

function patch_key_name(_key)
{
    var _k = clamp(round(_key), 0, 59);
    return global.MUS_NOTE_NAMES[_k mod 12] + string(_k div 12 + 1);
}

/// The tracker note whose rate the patch is rendered at (same pitch class)
function patch_root(_p)
{
    var _r = 13 + (clamp(_p.key, 0, 59) mod 12);
    if (_p.hq && global.MUS_PERIODS[_r + 12] >= 124) { _r += 12; }
    return _r;
}

/// One ADSR value at time _t (seconds) for a note held _gate seconds (-1 = held forever)
function patch_adsr(_t, _a, _d, _s, _r, _gate)
{
    var _lvl = 0;
    var _held = _t;
    if (_gate >= 0) { _held = min(_t, _gate); }
    if (_held < _a) { _lvl = _held / _a; }
    else
    {
        var _x = min(1, (_held - _a) / _d);
        _lvl = _s + (1 - _s) * (1 - _x) * (1 - _x);
    }
    if (_gate >= 0 && _t > _gate)
    {
        var _xr = min(1, (_t - _gate) / _r);
        _lvl *= (1 - _xr) * (1 - _xr);
    }
    return _lvl;
}

/// An LFO value in -1..1 (S&H takes a held random value per cycle)
function patch_lfo(_wave, _ph, _rnd)
{
    switch (_wave)
    {
        case 1: return 1 - 4 * abs(_ph - 0.5);
        case 2:
            if (_ph < 0.5) { return 1; }
            return -1;
        case 3: return _ph * 2 - 1;
        case 4: return _rnd;
    }
    return sin(_ph * 2 * pi);
}

/// One oscillator sample (band-limited saw and square)
function patch_wave(_wave, _ph, _dt, _pw, _noise)
{
    switch (_wave)
    {
        case 0: return _ph * 2 - 1 - music_polyblep(_ph, _dt);
        case 1:
            var _v = -1;
            if (_ph < _pw) { _v = 1; }
            var _ph2 = _ph + 1 - _pw;
            _ph2 -= floor(_ph2);
            return _v + music_polyblep(_ph, _dt) - music_polyblep(_ph2, _dt);
        case 2: return 1 - 4 * abs(_ph - 0.5);
        case 3: return sin(_ph * 2 * pi);
    }
    return _noise;
}

/// Renders a patch: { smp (signed 8-bit), rate, period, capped, loop_start, loop_len, spec }
function patch_render(_p)
{
    var _root = patch_root(_p);
    var _period = global.MUS_PERIODS[_root];
    var _rate = PAULA_CLOCK / _period;
    var _hz0 = patch_key_hz(_p.key);
    var _loop = (_p.loop != 0);

    var _aa = patch_env_ms(_p.amp_a) / 1000;
    var _ad = patch_env_ms(_p.amp_d) / 1000;
    var _as = _p.amp_s / 100;
    var _ar = patch_env_ms(_p.amp_r) / 1000;
    var _gate = _p.gate / 100;
    var _total = _gate + _ar;
    var _env_gate = _gate;
    var _loop_s = _p.loop_len / 100;
    if (_loop)
    {
        _env_gate = -1;
        _total = _aa + _ad + 0.05 + _loop_s;
    }
    _total = min(_total, PATCH_MAX_SECONDS);
    var _n = floor(_total * _rate);
    var _capped = false;
    if (_n > SMP_OUT_MAX_BYTES) { _n = SMP_OUT_MAX_BYTES; _capped = true; }
    _n -= _n mod 2;
    _n = max(_n, 4);

    // settings into locals (the inner loop must not look up struct fields)
    var _w = [_p.o1_wave, _p.o2_wave, _p.o3_wave];
    var _lv = [_p.o1_lvl / 100, _p.o2_lvl / 100, _p.o3_lvl / 100];
    var _pwb = [_p.o1_pw / 100, _p.o2_pw / 100, _p.o3_pw / 100];
    var _tune = [_p.o1_oct * 12 + _p.o1_semi + _p.o1_fine / 100, _p.o2_oct * 12 + _p.o2_semi + _p.o2_fine / 100, _p.o3_oct * 12 + _p.o3_semi + _p.o3_fine / 100];
    var _sync = (_p.sync != 0);
    var _ring = (_p.ring != 0);
    var _fm_base = _p.fm / 100;
    var _uni = clamp(_p.uni, 1, 4);
    var _udet = _p.udet;
    var _ugain = 1 / sqrt(_uni);
    var _ucents = array_create(4, 0);
    for (var u0 = 0; u0 < _uni; u0++)
    {
        if (_uni > 1) { _ucents[u0] = _udet * (u0 / (_uni - 1) * 2 - 1); }
    }
    var _flt = _p.flt;
    var _cut = _p.cut / 100;
    var _res = _p.res / 100;
    var _fenv = _p.fenv / 100;
    var _ktrk = _p.ktrk / 100;
    var _fa = patch_env_ms(_p.fa) / 1000;
    var _fd = patch_env_ms(_p.fd) / 1000;
    var _fs = _p.fs / 100;
    var _fr = patch_env_ms(_p.fr) / 1000;
    var _penv = _p.penv;
    var _pdec = patch_env_ms(_p.pdec) / 1000;
    var _l_wave = [_p.l1_wave, _p.l2_wave];
    var _l_hz = [patch_lfo_hz(_p.l1_rate), patch_lfo_hz(_p.l2_rate)];
    var _l_dly = [(patch_env_ms(_p.l1_dly) - 1) / 1000, (patch_env_ms(_p.l2_dly) - 1) / 1000];
    var _m_src = [_p.m1_src, _p.m2_src, _p.m3_src];
    var _m_dst = [_p.m1_dst, _p.m2_dst, _p.m3_dst];
    var _m_amt = [_p.m1_amt / 100, _p.m2_amt / 100, _p.m3_amt / 100];
    var _drive = _p.drive / 100;
    var _cho = _p.cho / 100;
    var _dmix = _p.dmix / 100;
    var _dfb = _p.dfb / 100;
    var _dtime = (10 + _p.dtime * 4.9) / 1000;
    var _need2 = (_lv[1] > 0 || _fm_base > 0 || _ring);
    for (var m0 = 0; m0 < 3; m0++)
    {
        if (_m_src[m0] > 0 && _m_amt[m0] != 0 && (_m_dst[m0] == 6 || _m_dst[m0] == 7)) { _need2 = true; }
    }

    var _out = array_create(_n, 0);
    var _ph = array_create(12, 0);
    var _dtv = array_create(12, 0);
    var _wrap1 = array_create(4, false);
    var _rnd = 22222;
    var _lph = [0, 0];
    var _lrnd = [0, 0];
    var _ic1 = 0;
    var _ic2 = 0;
    var _a1 = 1;
    var _a2 = 0;
    var _a3 = 0;
    var _fk = 2;
    var _amp = 0;
    var _pw = [0.5, 0.5, 0.5];
    var _fm = 0;
    var _lv2 = _lv[1];
    var _dmod = array_create(8, 0);
    var _dt_blk = PATCH_BLOCK / _rate;
    // chorus and echo delay lines
    var _cn = ceil(_rate * 0.04) + 4;
    var _cbuf = array_create(_cn, 0);
    var _cw = 0;
    var _en = ceil(_rate * 0.52) + 4;
    var _ebuf = array_create(_en, 0);
    var _ew = 0;
    var _edel = clamp(round(_dtime * _rate), 1, _en - 2);
    var _peak = 0;

    for (var i = 0; i < _n; i++)
    {
        var _t = i / _rate;
        if (i mod PATCH_BLOCK == 0)
        {
            // ---- control rate: envelopes, LFOs, modulation, filter ----
            var _e_amp = patch_adsr(_t, _aa, _ad, _as, _ar, _env_gate);
            var _e_flt = patch_adsr(_t, _fa, _fd, _fs, _fr, _env_gate);
            var _e_pit = 0;
            if (_t < _pdec) { _e_pit = (1 - _t / _pdec) * (1 - _t / _pdec); }
            var _lval = [0, 0];
            for (var l = 0; l < 2; l++)
            {
                _lph[l] += _l_hz[l] * _dt_blk;
                if (_lph[l] >= 1)
                {
                    _lph[l] -= floor(_lph[l]);
                    _rnd = (_rnd * 1103515245 + 12345) & 0x7fffffff;
                    _lrnd[l] = (_rnd / 0x3fffffff) - 1;
                }
                if (i == 0)
                {
                    _rnd = (_rnd * 1103515245 + 12345) & 0x7fffffff;
                    _lrnd[l] = (_rnd / 0x3fffffff) - 1;
                }
                var _fade = 1;
                if (_l_dly[l] > 0) { _fade = clamp(_t / _l_dly[l], 0, 1); }
                _lval[l] = patch_lfo(_l_wave[l], _lph[l], _lrnd[l]) * _fade;
            }
            for (var d0 = 0; d0 < 8; d0++) { _dmod[d0] = 0; }
            for (var m = 0; m < 3; m++)
            {
                if (_m_src[m] == 0 || _m_amt[m] == 0) { continue; }
                var _sv = 0;
                switch (_m_src[m])
                {
                    case 1: _sv = _lval[0]; break;
                    case 2: _sv = _lval[1]; break;
                    case 3: _sv = _e_flt; break;
                    case 4: _sv = _e_amp; break;
                    case 5: _sv = _e_pit; break;
                }
                _dmod[_m_dst[m]] += _sv * _m_amt[m];
            }
            // pitch: squared amount so small settings give gentle vibrato
            var _pmain = _penv * _e_pit + 12 * _dmod[0] * abs(_dmod[0]);
            var _pos2 = 12 * _dmod[1] * abs(_dmod[1]);
            for (var o = 0; o < 3; o++)
            {
                var _semis = _tune[o] + _pmain;
                if (o == 1) { _semis += _pos2; }
                for (var u = 0; u < _uni; u++)
                {
                    var _f = _hz0 * power(2, (_semis + _ucents[u] / 100) / 12);
                    _dtv[o * 4 + u] = clamp(_f / _rate, 0, 0.49);
                }
                _pw[o] = clamp(_pwb[o] + _dmod[2] * 0.45, 0.05, 0.95);
            }
            _fm = max(0, _fm_base + _dmod[6]);
            _lv2 = clamp(_lv[1] + _dmod[7], 0, 1);
            _amp = _e_amp * clamp(1 + _dmod[5], 0, 2);
            if (_flt > 0)
            {
                var _fc = 20 * power(2, _cut * 10);
                _fc *= power(_hz0 / 261.63, _ktrk);
                _fc *= power(2, _fenv * _e_flt * 6 + _dmod[3] * 5);
                _fc = clamp(_fc, 20, _rate * 0.45);
                var _rq = clamp(_res + _dmod[4], 0, 1);
                var _g = tan(pi * _fc / _rate);
                _fk = 2 - 1.96 * _rq;
                _a1 = 1 / (1 + _g * (_g + _fk));
                _a2 = _g * _a1;
                _a3 = _g * _a2;
            }
        }

        // ---- oscillators ----
        _rnd = (_rnd * 1103515245 + 12345) & 0x7fffffff;
        var _noise = (_rnd / 0x3fffffff) - 1;
        var _mix = 0;
        for (var v = 0; v < _uni; v++)
        {
            var _v2 = 0;
            if (_need2)
            {
                var _p2 = _ph[4 + v] + _dtv[4 + v];
                _p2 -= floor(_p2);
                if (_sync && _wrap1[v]) { _p2 = 0; }
                _ph[4 + v] = _p2;
                _v2 = patch_wave(_w[1], _p2, _dtv[4 + v], _pw[1], _noise);
            }
            var _p1 = _ph[v] + _dtv[v];
            _wrap1[v] = (_p1 >= 1);
            _p1 -= floor(_p1);
            _ph[v] = _p1;
            var _q1 = _p1;
            if (_fm > 0)
            {
                _q1 = _p1 + _fm * _v2;
                _q1 -= floor(_q1);
            }
            var _v1 = patch_wave(_w[0], _q1, _dtv[v], _pw[0], _noise);
            if (_ring) { _v2 *= _v1; }
            var _s = _v1 * _lv[0] + _v2 * _lv2;
            if (_lv[2] > 0)
            {
                var _p3 = _ph[8 + v] + _dtv[8 + v];
                _p3 -= floor(_p3);
                _ph[8 + v] = _p3;
                _s += patch_wave(_w[2], _p3, _dtv[8 + v], _pw[2], _noise) * _lv[2];
            }
            _mix += _s;
        }
        _mix *= _ugain;

        // ---- filter (state-variable, zero-delay feedback) ----
        if (_flt > 0)
        {
            var _v3 = _mix - _ic2;
            var _f1 = _a1 * _ic1 + _a2 * _v3;
            var _f2 = _ic2 + _a2 * _ic1 + _a3 * _v3;
            _ic1 = 2 * _f1 - _ic1;
            _ic2 = 2 * _f2 - _ic2;
            if (_flt == 1) { _mix = _f2; }
            else if (_flt == 2) { _mix = _mix - _fk * _f1 - _f2; }
            else { _mix = _f1; }
        }

        // ---- drive (soft clip) and amp ----
        if (_drive > 0)
        {
            var _dx = clamp(_mix * (1 + _drive * 6), -3, 3);
            _mix = _dx * (27 + _dx * _dx) / (27 + 9 * _dx * _dx);
        }
        _mix *= _amp;

        // ---- chorus ----
        if (_cho > 0)
        {
            _cbuf[_cw] = _mix;
            var _cd = (0.012 + 0.006 * sin(2 * pi * 0.7 * _t)) * _rate;
            var _cr = _cw - _cd;
            while (_cr < 0) { _cr += _cn; }
            var _ci = floor(_cr);
            var _cfr = _cr - _ci;
            var _cv = _cbuf[_ci mod _cn] * (1 - _cfr) + _cbuf[(_ci + 1) mod _cn] * _cfr;
            _mix = _mix * (1 - _cho * 0.5) + _cv * _cho * 0.7;
            _cw = (_cw + 1) mod _cn;
        }

        // ---- echo ----
        if (_dmix > 0)
        {
            var _er = _ew - _edel;
            if (_er < 0) { _er += _en; }
            var _ev = _ebuf[_er];
            _ebuf[_ew] = _mix + _ev * _dfb;
            _mix += _ev * _dmix;
            _ew = (_ew + 1) mod _en;
        }
        _out[i] = _mix;
    }

    // ---- rate crush (sample and hold) ----
    var _srd = clamp(_p.srd, 1, 8);
    if (_srd > 1)
    {
        for (var h = 0; h < _n; h++)
        {
            if (h mod _srd != 0) { _out[h] = _out[h - (h mod _srd)]; }
        }
    }

    // ---- looped sustain: whole cycles, crossfaded so the seam is silent ----
    var _ls = 0;
    var _ll = 0;
    if (_loop)
    {
        var _cyc = _rate / _hz0;
        var _len = max(_cyc, round(_loop_s * _rate / _cyc) * _cyc);
        _ll = round(_len);
        _ll -= _ll mod 2;
        _ll = clamp(_ll, 4, _n - 4);
        _ls = _n - _ll;
        _ls -= _ls mod 2;
        _ll = _n - _ls;
        var _xf = min(floor(_ll / 2), _ls, round(_rate * 0.03));
        for (var xf = 0; xf < _xf; xf++)
        {
            var _tx = xf / _xf;
            var _di = _ls + _ll - _xf + xf;
            _out[_di] = _out[_di] * (1 - _tx) + _out[_ls - _xf + xf] * _tx;
        }
    }

    // ---- full scale, then volume and bit crush ----
    for (var pk = 0; pk < _n; pk++) { _peak = max(_peak, abs(_out[pk])); }
    var _gain = 0;
    if (_peak > 0) { _gain = 0.95 / _peak * (_p.vol / 100); }
    var _q = 1 << (8 - clamp(_p.bits, 2, 8));
    var _smp = array_create(_n, 0);
    for (var k = 0; k < _n; k++)
    {
        var _sv8 = round(clamp(_out[k] * _gain, -1, 1) * 127);
        if (_q > 1) { _sv8 = floor(_sv8 / _q) * _q; }
        _smp[k] = clamp(_sv8, -128, 127);
    }

    var _spec_at = 0;
    if (_n > 512) { _spec_at = clamp(floor((_aa + _ad * 0.5) * _rate), 0, _n - 512); }
    return {
        smp : _smp, rate : _rate, period : _period, capped : _capped,
        loop_start : _ls, loop_len : _ll, spec : patch_spectrum(_smp, _spec_at)
    };
}

/// 256 spectrum bins (0..1, 60 dB range) of 512 samples from _at (Hann window)
function patch_spectrum(_smp, _at)
{
    var _nn = 512;
    var _re = array_create(_nn, 0);
    var _im = array_create(_nn, 0);
    var _len = array_length(_smp);
    for (var i = 0; i < _nn; i++)
    {
        var _src = _at + i;
        var _v = 0;
        if (_src < _len) { _v = _smp[_src]; }
        // bit-reversed order for the in-place FFT
        var _r = 0;
        var _b = i;
        for (var bit = 0; bit < 9; bit++)
        {
            _r = (_r << 1) | (_b & 1);
            _b = _b >> 1;
        }
        _re[_r] = _v * (0.5 - 0.5 * cos(2 * pi * i / (_nn - 1)));
    }
    var _size = 2;
    while (_size <= _nn)
    {
        var _half = _size div 2;
        var _ang = -2 * pi / _size;
        for (var j = 0; j < _half; j++)
        {
            var _wr = cos(_ang * j);
            var _wi = sin(_ang * j);
            for (var s = j; s < _nn; s += _size)
            {
                var _o = s + _half;
                var _tr = _wr * _re[_o] - _wi * _im[_o];
                var _ti = _wr * _im[_o] + _wi * _re[_o];
                _re[_o] = _re[s] - _tr;
                _im[_o] = _im[s] - _ti;
                _re[s] += _tr;
                _im[s] += _ti;
            }
        }
        _size *= 2;
    }
    var _out = array_create(256, 0);
    var _top = 0;
    for (var k = 0; k < 256; k++)
    {
        _out[k] = sqrt(_re[k] * _re[k] + _im[k] * _im[k]);
        _top = max(_top, _out[k]);
    }
    for (var k2 = 0; k2 < 256; k2++)
    {
        var _db = -60;
        if (_top > 0 && _out[k2] > 0) { _db = 20 * log10(_out[k2] / _top); }
        _out[k2] = clamp((_db + 60) / 60, 0, 1);
    }
    return _out;
}

/// Renders every preset (dev builds): sane lengths, loops, levels and timing
function patch_selftest()
{
    var _ok = true;
    var _worst = 0;
    var _worst_name = "";
    for (var i = 0; i < array_length(global.PATCH_PRESETS); i++)
    {
        var _p = patch_new();
        patch_apply_preset(_p, i);
        var _t0 = get_timer();
        var _r = patch_render(_p);
        var _ms = (get_timer() - _t0) / 1000;
        if (_ms > _worst) { _worst = _ms; _worst_name = global.PATCH_PRESETS[i][0]; }
        var _n = array_length(_r.smp);
        if (_n < 4 || _n mod 2 != 0 || _n > SMP_OUT_MAX_BYTES) { _ok = false; show_debug_message("patch length bad: " + global.PATCH_PRESETS[i][0]); }
        var _peak = 0;
        for (var k = 0; k < _n; k++) { _peak = max(_peak, abs(_r.smp[k])); }
        if (_peak < 40 || _peak > 128) { _ok = false; show_debug_message("patch level bad: " + global.PATCH_PRESETS[i][0] + " " + string(_peak)); }
        if (_p.loop != 0)
        {
            if (_r.loop_len < 4 || _r.loop_start mod 2 != 0 || _r.loop_len mod 2 != 0 || _r.loop_start + _r.loop_len != _n) { _ok = false; show_debug_message("patch loop bad: " + global.PATCH_PRESETS[i][0]); }
        }
        else if (_r.loop_len != 0) { _ok = false; }
        if (music_note_for_period(_r.period) != patch_root(_p)) { _ok = false; }
        if (array_length(_r.spec) != 256) { _ok = false; }
    }
    var _back = patch_from_loaded(json_parse(json_stringify({ key : 99, cut : 40.4, sync : true, junk : "x" })));
    if (_back.key != 59 || _back.cut != 40 || _back.sync != 1 || _back.o1_lvl != 100) { _ok = false; }
    var _msg = "ADAM patch self-test: ";
    if (_ok) { _msg += "PASS"; }
    else { _msg += "FAIL"; }
    show_debug_message(_msg + " (slowest preset " + _worst_name + " " + string(round(_worst)) + " ms)");
}

/// A setting's value as the editor shows it
function patch_fmt(_d, _v)
{
    switch (_d[6])
    {
        case 1: return string(_v) + "%";
        case 2:
            if (_v > 0) { return "+" + string(_v); }
            return string(_v);
        case 3:
            if (_v > 0) { return "+" + string(_v) + " ct"; }
            return string(_v) + " ct";
        case 4:
            var _ms = patch_env_ms(_v);
            if (_ms >= 1000) { return string_format(_ms / 1000, 1, 1) + " s"; }
            return string(round(_ms)) + " ms";
        case 5:
            var _hz = patch_lfo_hz(_v);
            if (_hz < 1) { return string_format(_hz, 1, 2) + " Hz"; }
            return string_format(_hz, 1, 1) + " Hz";
        case 6: return string_format(_v / 100, 1, 2) + " s";
        case 7:
            if (_v > 0) { return "+" + string(_v); }
            return string(_v);
        case 8: return string(round(10 + _v * 4.9)) + " ms";
        case 9: return patch_key_name(_v);
        case 10: return string(_v) + "x";
        case 11: return string(_v) + "-bit";
        case 12:
            if (_v <= 1) { return "Off"; }
            return "x" + string(_v);
    }
    return string(_v);
}

/// One setting row in the editor; returns its height
function patch_row(_p, _name, _px, _py, _w)
{
    var _d = global.PATCH_IDX[$ _name];
    var _id = "snd_patch_" + _name;
    var _lw = 96;
    if (_d[3] == 2)
    {
        var _on = ui_toggle(_id, _px, _py + 2, _d[4], (_p[$ _name] != 0), _d[5]);
        var _nv = 0;
        if (_on) { _nv = 1; }
        set_val(_p, _name, _nv, "sndp" + _name);
        return 32;
    }
    ui_text(_px, _py + 14, _d[4], global.TH.text_dim, fa_left, fa_middle, global.f_small, 1);
    if (_d[3] == 1)
    {
        var _ni = ui_dropdown(_id, _px + _lw, _py, _w - _lw, 28, _d[6], clamp(_p[$ _name], 0, array_length(_d[6]) - 1), _d[5]);
        set_val(_p, _name, _ni, "sndp" + _name);
        return 34;
    }
    var _sv = ui_slider(_id, _px + _lw, _py + 1, _w - _lw - 64, _p[$ _name], _d[1], _d[2], _d[5]);
    set_val(_p, _name, _sv, "sndp" + _name);
    ui_text(_px + _w, _py + 14, patch_fmt(_d, _p[$ _name]), global.TH.text, fa_right, fa_middle, global.f_bold, 1);
    return 32;
}

/// Two list settings side by side (modulation source and target); returns its height
function patch_row_pair(_p, _name_a, _name_b, _px, _py, _w)
{
    var _da = global.PATCH_IDX[$ _name_a];
    var _db = global.PATCH_IDX[$ _name_b];
    var _half = floor((_w - 8) / 2);
    var _na = ui_dropdown("snd_patch_" + _name_a, _px, _py, _half, 28, _da[6], clamp(_p[$ _name_a], 0, array_length(_da[6]) - 1), _da[5]);
    set_val(_p, _name_a, _na, "sndp" + _name_a);
    var _nb = ui_dropdown("snd_patch_" + _name_b, _px + _half + 8, _py, _half, 28, _db[6], clamp(_p[$ _name_b], 0, array_length(_db[6]) - 1), _db[5]);
    set_val(_p, _name_b, _nb, "sndp" + _name_b);
    return 34;
}

/// The Sound page for a Patch sound
function sound_patch_panel(_s, _fx, _y, _colw, _cx1, _x2, _y1, _y2)
{
    var _p = _s.patch;
    _y += patch_row(_p, "key", _fx, _y, _colw) + 6;

    // ---- tabs ----
    var _tabs = ["Osc", "Filter", "Amp", "Mod", "FX"];
    var _tab_help = ["Oscillators|The three sound sources and how they combine (sync, ring, FM).",
                     "Filter|Shapes the tone over time with its own envelope.",
                     "Amp|Volume envelope, pitch envelope, note length and looped sustain.",
                     "Modulation|Two LFOs and three slots that route LFOs and envelopes to settings.",
                     "Effects|Unison, chorus, drive, bit and rate crush, echo."];
    var _tw = floor((_colw - 4 * 6) / 5);
    for (var t = 0; t < 5; t++)
    {
        if (ui_tab("snd_patch_tab_" + string(t), _fx + t * (_tw + 6), _y, _tw, 30, _tabs[t], snd_patch_tab == t, _tab_help[t])) { snd_patch_tab = t; }
    }
    _y += 40;

    // ---- the tab's settings, scrolling if the window is short ----
    var _play_y = _y2 - 56;
    var _sy1 = _y;
    var _sy2 = _play_y - 8;
    var _off = ui_scroll_begin("snd_patch_scroll", _fx - 4, _sy1, _fx + _colw + 18, _sy2, snd_patch_content_h);
    var _ry = _sy1 - _off;
    var _rw = _colw - 8;
    switch (snd_patch_tab)
    {
        case 0:
            var _ow = floor((_rw - 12) / 3);
            for (var o = 0; o < 3; o++)
            {
                var _lab = "Osc " + string(o + 1);
                if (_p[$ "o" + string(o + 1) + "_lvl"] <= 0) { _lab += " (off)"; }
                if (ui_tab("snd_patch_osc_" + string(o), _fx + o * (_ow + 6), _ry, _ow, 28, _lab, snd_patch_osc == o, "Oscillator " + string(o + 1) + "|Show this oscillator's settings.")) { snd_patch_osc = o; }
            }
            _ry += 38;
            var _pre = "o" + string(snd_patch_osc + 1) + "_";
            var _onames = ["wave", "oct", "semi", "fine", "lvl", "pw"];
            for (var k = 0; k < 6; k++) { _ry += patch_row(_p, _pre + _onames[k], _fx, _ry, _rw); }
            _ry += 8;
            ui_heading(_fx, _ry, "Between oscillators");
            _ry += 20;
            _ry += patch_row(_p, "sync", _fx, _ry, _rw);
            _ry += patch_row(_p, "ring", _fx, _ry, _rw);
            _ry += patch_row(_p, "fm", _fx, _ry, _rw);
            break;
        case 1:
            var _fnames = ["flt", "cut", "res", "fenv", "ktrk"];
            for (var k1 = 0; k1 < 5; k1++) { _ry += patch_row(_p, _fnames[k1], _fx, _ry, _rw); }
            _ry += 8;
            ui_heading(_fx, _ry, "Filter envelope");
            _ry += 20;
            var _fe = ["fa", "fd", "fs", "fr"];
            for (var k2 = 0; k2 < 4; k2++) { _ry += patch_row(_p, _fe[k2], _fx, _ry, _rw); }
            break;
        case 2:
            var _anames = ["gate", "amp_a", "amp_d", "amp_s", "amp_r", "vol"];
            for (var k3 = 0; k3 < 6; k3++) { _ry += patch_row(_p, _anames[k3], _fx, _ry, _rw); }
            _ry += 8;
            ui_heading(_fx, _ry, "Pitch envelope");
            _ry += 20;
            _ry += patch_row(_p, "penv", _fx, _ry, _rw);
            _ry += patch_row(_p, "pdec", _fx, _ry, _rw);
            _ry += 8;
            ui_heading(_fx, _ry, "Sustain and quality");
            _ry += 20;
            _ry += patch_row(_p, "loop", _fx, _ry, _rw);
            if (_p.loop != 0) { _ry += patch_row(_p, "loop_len", _fx, _ry, _rw); }
            _ry += patch_row(_p, "hq", _fx, _ry, _rw);
            break;
        case 3:
            for (var l = 1; l <= 2; l++)
            {
                ui_heading(_fx, _ry, "LFO " + string(l));
                _ry += 20;
                _ry += patch_row(_p, "l" + string(l) + "_wave", _fx, _ry, _rw);
                _ry += patch_row(_p, "l" + string(l) + "_rate", _fx, _ry, _rw);
                _ry += patch_row(_p, "l" + string(l) + "_dly", _fx, _ry, _rw);
                _ry += 6;
            }
            for (var m = 1; m <= 3; m++)
            {
                ui_heading(_fx, _ry, "Slot " + string(m) + ": source -> target");
                _ry += 20;
                _ry += patch_row_pair(_p, "m" + string(m) + "_src", "m" + string(m) + "_dst", _fx, _ry, _rw);
                _ry += patch_row(_p, "m" + string(m) + "_amt", _fx, _ry, _rw);
                _ry += 6;
            }
            break;
        case 4:
            var _xnames = ["uni", "udet", "cho", "drive", "bits", "srd"];
            for (var k4 = 0; k4 < 6; k4++) { _ry += patch_row(_p, _xnames[k4], _fx, _ry, _rw); }
            _ry += 8;
            ui_heading(_fx, _ry, "Echo");
            _ry += 20;
            _ry += patch_row(_p, "dtime", _fx, _ry, _rw);
            _ry += patch_row(_p, "dfb", _fx, _ry, _rw);
            _ry += patch_row(_p, "dmix", _fx, _ry, _rw);
            break;
    }
    snd_patch_content_h = _ry + _off - _sy1 + 8;
    ui_scroll_end("snd_patch_scroll", _fx - 4, _sy1, _fx + _colw + 18, _sy2, snd_patch_content_h);

    // ---- play ----
    var _r = sfx_render_ex(_s);
    var _playing = (mus_playing && (mus_play_what == "sound" || mus_play_what == "sound_note") && preview_source == _s);
    if (preview_inst != -1 && preview_source == _s && audio_is_playing(preview_inst)) { _playing = true; }
    var _play_label = "Play sound";
    if (_playing && _r.loop_len >= 4) { _play_label = "Stop sound"; }
    if (ui_button("snd_preview", _fx, _play_y, _colw, 44, _play_label, "Play|Hear the patch exactly as Paula will play it. A looped patch sustains until you stop it; use the keyboard on the right to play it at other notes.", BTN_ACCENT))
    {
        if (_playing && _r.loop_len >= 4) { sfx_preview_stop(); }
        else { sfx_preview_play(_s); }
    }

    // ---- right column: waveform, spectrum, presets, keyboard ----
    var _gx = _fx + _colw + 30;
    var _gw = _x2 - 20 - _gx;
    var _gy = _y1 + 74;
    ui_heading(_gx, _gy - 18, "As Paula will play it");
    sound_draw_wave(_s, _r, _gx, _gy, _gw, 150, "Waveform|The rendered 8-bit sample. Green is the looped part of a looped patch; the marker shows the playback position.");
    var _sy = _gy + 172;
    ui_heading(_gx, _sy - 18, "Spectrum (held part of the note)");
    ui_inset(_gx, _sy, _gx + _gw, _sy + 84, 10);
    ui_register("snd_patch_spec", _gx, _sy, _gx + _gw, _sy + 84, "Spectrum|Which frequencies are in the held part of the note, low on the left, high on the right (up to half the sample rate). Peaks are the harmonics.");
    var _cols = floor((_gw - 20) / 3);
    var _spec = _r.spec;
    for (var c = 0; c < _cols; c++)
    {
        var _b0 = floor(power(255, c / _cols));
        var _b1 = max(_b0 + 1, floor(power(255, (c + 1) / _cols)));
        var _mag = 0;
        for (var b = _b0; b < min(_b1, 256); b++) { _mag = max(_mag, _spec[b]); }
        var _bh = _mag * 70;
        var _bx = _gx + 10 + c * 3;
        if (_bh > 0.5) { draw_rectangle_colour(_bx, _sy + 78 - _bh, _bx + 1, _sy + 78, global.TH.accent2, global.TH.accent2, global.TH.accent, global.TH.accent, false); }
    }
    var _n = array_length(_r.smp);
    var _info = string(_n) + " bytes of chip RAM  -  " + string_format(_n / max(1, _r.rate), 1, 2) + " s at " + string(round(_r.rate)) + " Hz  -  " + patch_key_name(_p.key);
    if (_r.loop_len >= 4) { _info += ", looped"; }
    if (_r.capped) { _info += "  (cut to 128 KB)"; }
    ui_text(_gx, _sy + 92, ui_text_fit(_info, global.f_small, _gw), global.TH.text_dim, fa_left, fa_top, global.f_small, 1);

    var _py = _sy + 124;
    ui_heading(_gx, _py, "Start from a preset");
    _py += 20;
    var _bw = 104;
    var _dw = max(120, _gw - 2 * (_bw + 8));
    var _pi = ui_dropdown("snd_patch_preset", _gx, _py, _dw, 32, global.PATCH_PRESET_MENU, 0, "Preset|Replaces this patch with a ready-made one and plays it: basses, leads, pads, keys, drums and effects. Undo brings your patch back.");
    if (_pi > 0)
    {
        undo_mark("sndppreset" + string(current_time));
        patch_apply_preset(_p, _pi - 1);
        sfx_preview_play(_s);
        toast("Preset: " + global.PATCH_PRESET_NAMES[_pi - 1], 0);
    }
    if (ui_button("snd_patch_random", _gx + _dw + 8, _py, _bw, 32, "Randomise", "Randomise|Rolls a completely new patch (keeping its note and volume) and plays it. Undo brings the last one back.", BTN_NORMAL))
    {
        undo_mark("sndprandom" + string(current_time));
        patch_randomise(_p, 1);
        sfx_preview_play(_s);
    }
    if (ui_button("snd_patch_mutate", _gx + _dw + _bw + 16, _py, _bw, 32, "Mutate", "Mutate|Nudges about a third of the settings a little and plays the result - press again for more happy accidents.", BTN_NORMAL))
    {
        undo_mark("sndpmutate" + string(current_time));
        patch_randomise(_p, 0.15);
        sfx_preview_play(_s);
    }

    // a held looped note follows the edits
    if (_playing && !ui_held && preview_render != _r && _r.loop_len >= 4)
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
