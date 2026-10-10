/// ADAM - turns the project into a bootable Amiga disk (.ADF)
///
/// ADAM never writes code. The fixed 68000 engine (datafiles/engine/engine.bin,
/// source in engine.s) reads a game data block that is appended straight after
/// it. The bootblock (boot.bin) loads engine + data into chip RAM and runs it.
/// The data block layout is documented at the top of engine.s.

#macro ADF_SIZE 901120
#macro ADF_HDR 80
#macro OS_RESERVE_KB 160

function be16(_b, _v)
{
    var _w = floor(_v) & 0xffff;
    buffer_write(_b, buffer_u8, (_w >> 8) & 255);
    buffer_write(_b, buffer_u8, _w & 255);
}

function be32(_b, _v)
{
    var _l = floor(_v) & 0xffffffff;
    buffer_write(_b, buffer_u8, (_l >> 24) & 255);
    buffer_write(_b, buffer_u8, (_l >> 16) & 255);
    buffer_write(_b, buffer_u8, (_l >> 8) & 255);
    buffer_write(_b, buffer_u8, _l & 255);
}

function poke16(_b, _o, _v)
{
    var _w = floor(_v) & 0xffff;
    buffer_poke(_b, _o, buffer_u8, (_w >> 8) & 255);
    buffer_poke(_b, _o + 1, buffer_u8, _w & 255);
}

function poke32(_b, _o, _v)
{
    var _l = floor(_v) & 0xffffffff;
    buffer_poke(_b, _o, buffer_u8, (_l >> 24) & 255);
    buffer_poke(_b, _o + 1, buffer_u8, (_l >> 16) & 255);
    buffer_poke(_b, _o + 2, buffer_u8, (_l >> 8) & 255);
    buffer_poke(_b, _o + 3, buffer_u8, _l & 255);
}

function peek32(_b, _o)
{
    return (buffer_peek(_b, _o, buffer_u8) << 24) | (buffer_peek(_b, _o + 1, buffer_u8) << 16) | (buffer_peek(_b, _o + 2, buffer_u8) << 8) | buffer_peek(_b, _o + 3, buffer_u8);
}

function buf_align(_b, _n)
{
    while ((buffer_tell(_b) mod _n) != 0) { buffer_write(_b, buffer_u8, 0); }
}

function buf_zeros(_b, _n)
{
    var _l = _n div 4;
    for (var i = 0; i < _l; i++) { buffer_write(_b, buffer_u32, 0); }
    for (var k = 0; k < (_n mod 4); k++) { buffer_write(_b, buffer_u8, 0); }
}

/// Text in a fixed-size, zero-padded field (upper case, font characters only)
function buf_fixed_text(_b, _s, _n)
{
    var _t = string_upper(string_copy(_s, 1, _n - 1));
    for (var i = 1; i <= _n; i++)
    {
        var _c = 0;
        if (i <= string_length(_t))
        {
            _c = ord(string_char_at(_t, i));
            if (_c < 32 || _c > 95) { _c = 32; }
        }
        buffer_write(_b, buffer_u8, _c);
    }
}

/// Upper-case ASCII the engine font can draw, zero terminated
function buf_text(_b, _s)
{
    var _t = string_upper(string_copy(_s, 1, 36));
    for (var i = 1; i <= string_length(_t); i++)
    {
        var _c = ord(string_char_at(_t, i));
        if (_c < 32 || _c > 95) { _c = 32; }
        buffer_write(_b, buffer_u8, _c);
    }
    buffer_write(_b, buffer_u8, 0);
}

/// Ground height per column (first ground-colour pixel from the top, 256 = none)
function ground_table(_p)
{
    var _out = array_create(BD_W, 256);
    for (var gx = 0; gx < BD_W; gx++)
    {
        for (var gy = 0; gy < BD_H; gy++)
        {
            if (_p.solid[_p.pixels[gy * BD_W + gx]] != 0)
            {
                _out[gx] = gy;
                break;
            }
        }
    }
    return _out;
}

/// Ground table for previews: all 256 (no line) when no colour is ground
function ground_table_cached(_p)
{
    for (var sc = 0; sc < PAL_MAX; sc++)
    {
        if (_p.solid[sc] != 0) { return ground_table(_p); }
    }
    return array_create(BD_W, 256);
}

/// Writes one hardware sprite block (POS, CTL, 24 lines x 2 words, end). Returns its offset.
function adf_sprite_block(_b, _img)
{
    buf_align(_b, 8);
    var _o = buffer_tell(_b);
    be32(_b, 0);
    for (var sy = 0; sy < SPR_H; sy++)
    {
        var _w0 = 0;
        var _w1 = 0;
        for (var sx = 0; sx < SPR_W; sx++)
        {
            var _sv = _img[sy * SPR_W + sx];
            if ((_sv & 1) != 0) { _w0 = _w0 | (0x8000 >> sx); }
            if ((_sv & 2) != 0) { _w1 = _w1 | (0x8000 >> sx); }
        }
        be16(_b, _w0);
        be16(_b, _w1);
    }
    be32(_b, 0);
    return _o;
}

/// Builds the game data block. Returns { buf, size, warnings[], sound_bytes, plane_bytes }.
function adam_data_block(_p)
{
    var _warn = [];
    var _m = machine_get(_p.machine);
    var _depth = clamp(_p.depth, 1, _m.max_depth);
    var _ncol = 1 << _depth;
    var _acts = _p.actors;
    var _na = min(8, array_length(_acts));
    var _rules = [];
    for (var ru = 0; ru < array_length(_p.rules); ru++)
    {
        var _rr = _p.rules[ru];
        var _off_grp = false;
        if (_rr.group >= 0 && _rr.group < array_length(_p.groups))
        {
            if (!_p.groups[_rr.group].enabled) { _off_grp = true; }
        }
        if (!_off_grp) { array_push(_rules, _rr); }
    }
    var _nr = min(100, array_length(_rules));
    var _b = buffer_create(262144, buffer_grow, 1);
    buf_zeros(_b, ADF_HDR);
    buf_align(_b, 8);

    // palette
    var _off_pal = buffer_tell(_b);
    for (var c = 0; c < _ncol; c++) { be32(_b, rgb_machine(_p.pal[c])); }
    buf_align(_b, 8);

    // backdrop bitplanes (pristine copy)
    var _off_planes = buffer_tell(_b);
    for (var pl = 0; pl < _depth; pl++)
    {
        for (var _iy = 0; _iy < BD_H; _iy++)
        {
            var _row = _iy * BD_W;
            for (var xb = 0; xb < 40; xb++)
            {
                var _v = 0;
                var _base = _row + xb * 8;
                for (var bit = 0; bit < 8; bit++)
                {
                    if (((_p.pixels[_base + bit] >> pl) & 1) != 0) { _v = _v | (128 >> bit); }
                }
                buffer_write(_b, buffer_u8, _v);
            }
        }
    }
    buf_align(_b, 8);

    // hardware sprite blocks per actor (and a second one when it animates)
    var _spr_off = array_create(_na, 0);
    var _spr2_off = array_create(_na, 0);
    for (var a = 0; a < _na; a++)
    {
        _spr_off[a] = adf_sprite_block(_b, _p.sprites[clamp(_acts[a].sprite, 0, SPR_COUNT - 1)].px);
        if (_acts[a].anim_sprite >= 0 && _acts[a].anim_sprite < SPR_COUNT)
        {
            _spr2_off[a] = adf_sprite_block(_b, _p.sprites[_acts[a].anim_sprite].px);
        }
    }
    buf_align(_b, 8);

    // actor records
    var _alloc = actors_alloc_channels();
    var _off_act = buffer_tell(_b);
    var _player = -1;
    for (var a2 = 0; a2 < _na; a2++)
    {
        var _ac = _acts[a2];
        if ((_ac.role == 0 || _ac.role == 6) && _player < 0) { _player = a2; }
        var _img2 = _p.sprites[clamp(_ac.sprite, 0, SPR_COUNT - 1)].px;
        var _bx0 = 99;
        var _by0 = 99;
        var _bx1 = -1;
        var _by1 = -1;
        for (var q = 0; q < SPR_W * SPR_H; q++)
        {
            if (_img2[q] != 0)
            {
                _bx0 = min(_bx0, q mod SPR_W);
                _bx1 = max(_bx1, q mod SPR_W);
                _by0 = min(_by0, q div SPR_W);
                _by1 = max(_by1, q div SPR_W);
            }
        }
        if (_bx1 < 0)
        {
            _bx0 = 0; _by0 = 0; _bx1 = SPR_W - 1; _by1 = SPR_H - 1;
            array_push(_warn, "Actor '" + _ac.name + "' uses an empty sprite - it will be invisible.");
        }
        var _vis = 0;
        if (_ac.visible) { _vis = 1; }
        var _left = 0;
        if (_ac.start_left) { _left = 1; }
        var _up = 0;
        if (_ac.start_up) { _up = 1; }
        be16(_b, clamp(_ac.x, 0, ACT_XMAX));
        be16(_b, clamp(_ac.y, 0, ACT_YMAX));
        be16(_b, clamp(_ac.role, 0, 8));
        be16(_b, clamp(_ac.speed, 1, 8));
        be16(_b, _vis);
        be16(_b, _left);
        be16(_b, _up);
        be16(_b, _bx0);
        be16(_b, _by0);
        be16(_b, _bx1);
        be16(_b, _by1);
        be32(_b, _spr_off[a2]);
        be16(_b, _alloc.chan[a2]);
        be32(_b, _spr2_off[a2]);
        be16(_b, clamp(_ac.anim_rate, 2, 30));
        var _am = 0;
        if (_ac.anim_moving) { _am = 1; }
        be16(_b, _am);
        be16(_b, clamp(_ac.from_level, 1, LEVEL_MAX));
        be16(_b, clamp(_ac.faster_every, 0, LEVEL_MAX));
        buf_zeros(_b, 8);
        if (_alloc.conflict[a2]) { array_push(_warn, "Actor '" + _ac.name + "' shares a sprite colour pair with different colours - it will borrow its partner's colours."); }
    }
    buf_align(_b, 8);

    // rules
    var _off_rules = buffer_tell(_b);
    for (var r = 0; r < _nr; r++)
    {
        var _ru = _rules[r];
        var _val = _ru.value;
        if (_ru.act == 8) { _val = clamp(_val, 0, _ncol - 1); }
        if (_ru.act == 2) { _val = clamp(_val, 0, 7); }
        be16(_b, clamp(_ru.when, 0, 7));
        be16(_b, clamp(_ru.a, 0, 7));
        be16(_b, clamp(_ru.b, 0, 7));
        be16(_b, clamp(_ru.n, 1, 65535));
        be16(_b, clamp(_ru.act, 0, 17));
        be16(_b, clamp(_ru.target, 0, 7));
        be16(_b, clamp(_val, 0, 65535));
        be16(_b, 0);
    }
    buf_align(_b, 8);

    // sprite pair colours
    var _off_sprcol = buffer_tell(_b);
    for (var pr = 0; pr < 4; pr++)
    {
        for (var k = 0; k < 3; k++) { be32(_b, rgb_machine(_alloc.pair_cols[pr][k])); }
    }

    // messages
    var _off_over = buffer_tell(_b);
    buf_text(_b, _p.over_text);
    var _off_win = buffer_tell(_b);
    buf_text(_b, _p.win_text);
    buf_align(_b, 8);

    // sound samples, then their table
    var _snd_off = array_create(8, 0);
    var _snd_len = array_create(8, 0);
    var _snd_per = array_create(8, 0);
    var _snd_bytes = 0;
    for (var s = 0; s < 8; s++)
    {
        buf_align(_b, 8);
        _snd_off[s] = buffer_tell(_b);
        var _r = sfx_render_ex(_p.sfx[s]);
        var _smp = _r.smp;
        for (var i = 0; i < array_length(_smp); i++) { buffer_write(_b, buffer_s8, _smp[i]); }
        _snd_len[s] = array_length(_smp) div 2;
        _snd_per[s] = _r.period;
        _snd_bytes += array_length(_smp);
    }
    buf_align(_b, 8);
    var _off_sfx = buffer_tell(_b);
    for (var s2 = 0; s2 < 8; s2++)
    {
        be32(_b, _snd_off[s2]);
        be16(_b, _snd_len[s2]);
        be16(_b, _snd_per[s2]);
    }
    buf_align(_b, 8);

    // copper sky: one $0RGB colour per display line
    var _off_grad = 0;
    if (_p.sky_on)
    {
        _off_grad = buffer_tell(_b);
        var _sky = sky_table(_p);
        for (var g = 0; g < 256; g++) { be16(_b, _sky[g]); }
        buf_align(_b, 8);
    }

    // ground: for each column, the first pixel from the top in a ground colour
    var _off_ground = 0;
    var _any_solid = false;
    for (var sc = 0; sc < PAL_MAX; sc++)
    {
        if (_p.solid[sc] != 0) { _any_solid = true; }
    }
    if (_any_solid)
    {
        _off_ground = buffer_tell(_b);
        var _gt = ground_table(_p);
        for (var gx = 0; gx < BD_W; gx++) { be16(_b, _gt[gx]); }
        buf_align(_b, 8);
    }

    // game block: levels and their hills, goal counter, title screen
    var _off_game = 0;
    var _lv_on = (_p.levels_on && array_length(_p.levels) > 0);
    if (_lv_on || _p.goal_on || _p.title_on)
    {
        _off_game = buffer_tell(_b);
        var _nlv = 1;
        if (_lv_on) { _nlv = array_length(_p.levels); }
        var _terr = 0;
        if (_lv_on) { _terr = 1; }
        var _goal = 0;
        if (_p.goal_on) { _goal = clamp(_p.goal, 1, 99); }
        var _tit = 0;
        if (_p.title_on) { _tit = 1; }
        be16(_b, _nlv);
        be16(_b, _terr);
        for (var tc = 0; tc < 4; tc++) { be16(_b, clamp(_p.terrain_cols[tc], 0, _ncol - 1)); }
        be16(_b, _goal);
        be16(_b, _tit);
        buf_fixed_text(_b, _p.goal_label, 8);
        buf_fixed_text(_b, _p.title1, 40);
        buf_fixed_text(_b, _p.title2, 40);
        buf_fixed_text(_b, _p.lev_text, 16);
        for (var lv = 0; lv < _nlv; lv++)
        {
            for (var hx = 0; hx < BD_W; hx++)
            {
                var _hv = 256;
                if (_lv_on) { _hv = clamp(_p.levels[lv].heights[hx], 100, 240); }
                be16(_b, _hv);
            }
        }
        buf_align(_b, 8);
    }

    // the backdrop + hills working copy (score text is restored from it)
    var _off_work = buffer_tell(_b);
    buf_zeros(_b, _depth * 10240);
    buf_align(_b, 8);

    // the display bitplanes the game draws into
    var _off_disp = buffer_tell(_b);
    buf_zeros(_b, _depth * 10240);
    var _size = buffer_tell(_b);

    // header
    buffer_poke(_b, 0, buffer_u8, ord("A"));
    buffer_poke(_b, 1, buffer_u8, ord("D"));
    buffer_poke(_b, 2, buffer_u8, ord("A"));
    buffer_poke(_b, 3, buffer_u8, ord("M"));
    var _flags = 0;
    if (_m.aga) { _flags = 1; }
    var _sc = 0;
    if (_p.show_score) { _sc = 1; }
    var _lv = 0;
    if (_p.show_lives) { _lv = 1; }
    poke16(_b, 4, 1);
    poke16(_b, 6, _flags);
    poke16(_b, 8, _depth);
    poke16(_b, 10, _na);
    poke16(_b, 12, _nr);
    poke16(_b, 14, clamp(_p.lives, 0, 9));
    poke16(_b, 16, _sc);
    poke16(_b, 18, _lv);
    poke16(_b, 20, clamp(_p.hud_row, 0, 31));
    poke16(_b, 22, clamp(_p.hud_colour, 0, _ncol - 1));
    poke16(_b, 24, clamp(_p.msg_colour, 0, _ncol - 1));
    poke16(_b, 26, _player);
    poke32(_b, 32, _off_pal);
    poke32(_b, 36, _off_planes);
    poke32(_b, 40, _off_act);
    poke32(_b, 44, _off_rules);
    poke32(_b, 48, _off_sfx);
    poke32(_b, 52, _off_over);
    poke32(_b, 56, _off_win);
    poke32(_b, 60, _off_sprcol);
    poke32(_b, 64, _off_disp);
    poke32(_b, 68, _off_grad);
    poke32(_b, 72, _off_ground);
    poke32(_b, 76, _off_work);
    poke32(_b, 28, _off_game);

    if (_na == 0) { array_push(_warn, "There are no actors yet - the game will just show your backdrop."); }
    if (_player < 0 && _na > 0) { array_push(_warn, "No actor is set as Player, so the joystick will not move anything."); }
    return { buf : _b, size : _size, warnings : _warn, sound_bytes : _snd_bytes, plane_bytes : _depth * 10240 * 3 };
}

/// Builds the ADF file. Returns true on success and fills build_* fields.
function build_adf(_path)
{
    var _dir = working_directory + "engine/";
    if (!file_exists(_dir + "engine.bin") || !file_exists(_dir + "boot.bin"))
    {
        build_ok = false;
        build_msg = "Build failed - the engine files are missing (datafiles/engine).";
        return false;
    }
    var _eng = buffer_load(_dir + "engine.bin");
    var _boot = buffer_load(_dir + "boot.bin");
    var _esize = buffer_get_size(_eng);
    var _bsize = buffer_get_size(_boot);
    var _data = adam_data_block(proj);
    var _game = _esize + _data.size;
    var _load = ceil(_game / 512) * 512;
    build_warnings = _data.warnings;
    if (_load > ADF_SIZE - 1024)
    {
        buffer_delete(_eng);
        buffer_delete(_boot);
        buffer_delete(_data.buf);
        build_ok = false;
        build_msg = "Build failed - the game is " + string(_game div 1024) + " KB and does not fit on one floppy disk.";
        return false;
    }
    var _m = machine_cur();
    var _chip_free = (_m.chip_kb - OS_RESERVE_KB) * 1024;
    if (_game > _chip_free)
    {
        buffer_delete(_eng);
        buffer_delete(_boot);
        buffer_delete(_data.buf);
        build_ok = false;
        build_msg = "Build failed - the game needs " + string(_game div 1024) + " KB of chip RAM; the " + _m.name + " has about " + string(_chip_free div 1024) + " KB free. Use fewer colours or shorter sounds.";
        return false;
    }

    var _adf = buffer_create(ADF_SIZE, buffer_fixed, 1);
    buffer_fill(_adf, 0, buffer_u8, 0, ADF_SIZE);
    buffer_copy(_boot, 0, _bsize, _adf, 0);
    poke32(_adf, _bsize - 4, _load);
    // bootblock checksum: add-with-carry over 256 longwords, then invert
    var _sum = 0;
    for (var i = 0; i < 256; i++)
    {
        if (i == 1) { continue; }
        _sum += peek32(_adf, i * 4);
        if (_sum > 0xffffffff) { _sum = (_sum & 0xffffffff) + 1; }
    }
    poke32(_adf, 4, 0xffffffff - _sum);
    buffer_copy(_eng, 0, _esize, _adf, 1024);
    buffer_copy(_data.buf, 0, _data.size, _adf, 1024 + _esize);
    buffer_save(_adf, _path);
    buffer_delete(_adf);
    buffer_delete(_eng);
    buffer_delete(_boot);
    buffer_delete(_data.buf);

    build_ok = true;
    build_size = _game;
    build_engine_size = _esize;
    build_plane_size = _data.plane_bytes;
    build_sound_size = _data.sound_bytes;
    build_chip_free = _chip_free;
    build_msg = "Built " + filename_name(_path) + " for the " + _m.name + " - " + string(ceil(_game / 1024)) + " KB of chip RAM";
    return true;
}

// ---------------------------------------------------------------------------
// FS-UAE.  Order of preference:
//   1. the fs-uae.exe the user chose with Find (always allowed)
//   2. ADAM's own test copy, downloaded on demand from the official FS-UAE
//      release into the save folder (only while ADAM_DEV_TOOLS is true)
//   3. a normal FS-UAE install in the usual places
// Set ADAM_DEV_TOOLS to false for public (itch.io) builds: users then locate
// their own FS-UAE and nothing is downloaded or bundled.
// ---------------------------------------------------------------------------
#macro ADAM_DEV_TOOLS true
#macro FSUAE_ZIP_URL "https://github.com/FrodeSolheim/fs-uae/releases/download/v3.1.66/FS-UAE_3.1.66_Windows_x86-64.zip"

function fsuae_test_dir()
{
    return game_save_id + "fs-uae/";
}

function fsuae_test_exe()
{
    return fsuae_test_dir() + "FS-UAE/Windows/x86-64/fs-uae.exe";
}

/// An installed FS-UAE in the usual places, or ""
function fsuae_find_installed()
{
    var _cands = [
        "C:/Program Files/FS-UAE/Windows/x86-64/fs-uae.exe",
        "C:/Program Files (x86)/FS-UAE/Windows/x86-64/fs-uae.exe",
        environment_get_variable("LOCALAPPDATA") + "/Programs/FS-UAE/Windows/x86-64/fs-uae.exe",
        environment_get_variable("USERPROFILE") + "/Documents/FS-UAE/Windows/x86-64/fs-uae.exe"
    ];
    for (var i = 0; i < array_length(_cands); i++)
    {
        if (file_exists(_cands[i])) { return _cands[i]; }
    }
    return "";
}

/// The fs-uae.exe ADAM will run, or "" when there is none
function fsuae_exe()
{
    if (fsuae_path != "" && file_exists(fsuae_path)) { return fsuae_path; }
    if (ADAM_DEV_TOOLS && file_exists(fsuae_test_exe())) { return fsuae_test_exe(); }
    return fsuae_find_installed();
}

/// Text for the Build page: where FS-UAE comes from
function fsuae_source_label()
{
    if (fsuae_path != "" && file_exists(fsuae_path)) { return fsuae_path; }
    if (ADAM_DEV_TOOLS && file_exists(fsuae_test_exe())) { return "ADAM's test copy (FS-UAE 3.1.66)"; }
    var _inst = fsuae_find_installed();
    if (_inst != "") { return _inst + "  (found)"; }
    return "";
}

/// Downloads the official FS-UAE Windows release for testing.
/// _then_run = an ADF to boot when it is ready, or "".
function fsuae_download(_then_run)
{
    if (!ADAM_DEV_TOOLS) { return; }
    if (fsuae_dl_id >= 0) { return; }
    if (os_type != os_windows)
    {
        toast("The FS-UAE test copy is for Windows - use Find on other systems", 1);
        return;
    }
    fsuae_dl_zip = game_save_id + "fsuae_download.zip";
    if (file_exists(fsuae_dl_zip)) { file_delete(fsuae_dl_zip); }
    fsuae_dl_got = 0;
    fsuae_dl_total = 0;
    fsuae_dl_then_run = _then_run;
    fsuae_dl_id = http_get_file(FSUAE_ZIP_URL, fsuae_dl_zip);
    build_log_add("Downloading FS-UAE 3.1.66 for testing (about 9 MB)...", 0);
    toast("Downloading FS-UAE for testing...", 0);
}

/// Async HTTP event handler for the download
function fsuae_download_async()
{
    if (fsuae_dl_id < 0) { return; }
    if (async_load[? "id"] != fsuae_dl_id) { return; }
    var _status = async_load[? "status"];
    if (_status == 1)
    {
        fsuae_dl_got = async_load[? "sizeDownloaded"];
        fsuae_dl_total = async_load[? "contentLength"];
        return;
    }
    fsuae_dl_id = -1;
    var _ok = false;
    if (_status == 0 && async_load[? "http_status"] == 200 && file_exists(fsuae_dl_zip))
    {
        zip_unzip(fsuae_dl_zip, fsuae_test_dir());
        file_delete(fsuae_dl_zip);
        _ok = file_exists(fsuae_test_exe());
    }
    if (_ok)
    {
        build_log_add("FS-UAE test copy ready (GPL - its licences are in the FS-UAE/Licenses folder)", 0);
        toast("FS-UAE is ready", 0);
        if (fsuae_dl_then_run != "") { launch_fsuae(fsuae_dl_then_run); }
    }
    else
    {
        build_log_add("Could not download FS-UAE - check the internet connection, or use Find", 2);
        toast("FS-UAE download failed", 2);
    }
    fsuae_dl_then_run = "";
}

/// Starts FS-UAE on the built disk (after closing an old copy - see Step)
function launch_fsuae(_adf)
{
    if (os_type != os_windows)
    {
        toast("Open " + filename_name(_adf) + " in FS-UAE to play", 1);
        return false;
    }
    if (fsuae_exe() == "")
    {
        if (ADAM_DEV_TOOLS)
        {
            fsuae_download(_adf);
            return false;
        }
        toast("Find fs-uae.exe on the Build page first", 1);
        return false;
    }
    execute_shell_simple("taskkill.exe", "/F /IM fs-uae.exe", "open", 0);
    launch_pending = _adf;
    launch_timer = 20;
    toast("Launching FS-UAE...", 0);
    return true;
}

/// Called from the Step event once the old emulator has had time to close
function launch_fsuae_now(_adf)
{
    var _exe = fsuae_exe();
    if (_exe == "") { return; }
    var _m = machine_cur();
    var _args = "--amiga_model=" + _m.fsuae_model
        + " --chip_memory=" + string(_m.chip_kb)
        + " --slow_memory=0 --fast_memory=0"
        + " --floppy_drive_0=\"" + _adf + "\""
        + " --floppy_drive_speed=0"
        + " --fullscreen=0"
        + " --window_width=960 --window_height=720"
        + " --automatic_input_grab=0 --initial_input_grab=0";
    if (fsuae_light)
    {
        // light mode: no host vsync spin-wait and no smoothing filter - far less CPU/GPU load
        _args += " --video_sync=off --texture_filter=nearest";
    }
    if (kick_path != "" && file_exists(kick_path))
    {
        _args += " --kickstart_file=\"" + kick_path + "\"";
    }
    execute_shell_simple(_exe, _args, "open", 5, filename_dir(_exe));
}

/// Lines for the "show the engine" view: the engine source, then a data summary
function build_make_listing()
{
    build_listing = [];
    var _txt = file_read_text(working_directory + "engine/engine.s");
    if (_txt != "")
    {
        build_listing = string_split(string_replace_all(_txt, "\r", ""), "\n");
    }
    array_push(build_listing, "; ---------------------------------------------------------------");
    array_push(build_listing, "; game data appended after data_start for '" + proj.name + "'");
    array_push(build_listing, ";   machine " + machine_cur().name + ", " + string(pal_count()) + " colours, " + string(array_length(proj.actors)) + " actors, " + string(array_length(proj.rules)) + " rules, 8 sounds");
}
