/// ADAM - levels: hills made from a seed (then hand-shaped), goal counter, title

#macro LEVEL_MAX 10

/// Rolling hills from a seed. Same maths as ADAM's example generator, so a
/// seed always gives the same hills. Returns 320 ground heights.
function terrain_generate(_seed, _hilly, _base)
{
    var _st = _seed & 0x7fffffff;
    var _lo = [45, 20, 9];
    var _hi = [70, 30, 14];
    var _amp = [14, 7, 3];
    var _f = [0, 0, 0];
    var _ph = [0, 0, 0];
    var _a = [0, 0, 0];
    for (var k = 0; k < 3; k++)
    {
        _st = (_st * 1103515245 + 12345) mod 2147483648;
        var _r1 = _st / 2147483648;
        _st = (_st * 1103515245 + 12345) mod 2147483648;
        var _r2 = _st / 2147483648;
        _f[k] = 1 / (_lo[k] + _r1 * (_hi[k] - _lo[k]));
        _ph[k] = _r2 * 6.283185307179586;
        _a[k] = _amp[k] * _hilly / 100;
    }
    var _out = array_create(BD_W, 200);
    for (var x0 = 0; x0 < BD_W; x0++)
    {
        var _y = _base;
        for (var t = 0; t < 3; t++) { _y += sin(x0 * _f[t] + _ph[t]) * _a[t]; }
        _out[x0] = clamp(floor(_y + 0.5), 100, 240);
    }
    return _out;
}

function level_new(_seed)
{
    return { seed : _seed, hilly : 60, base : 200, heights : terrain_generate(_seed, 60, 200) };
}

function level_names()
{
    var _n = [];
    for (var i = 0; i < array_length(proj.levels); i++) { array_push(_n, "Level " + string(i + 1)); }
    if (array_length(_n) == 0) { array_push(_n, "(no levels)"); }
    return _n;
}

/// Heights of the level shown in the editors, or undefined
function level_heights_shown()
{
    if (!proj.levels_on || array_length(proj.levels) == 0) { return undefined; }
    return proj.levels[clamp(lvl_sel, 0, array_length(proj.levels) - 1)].heights;
}

/// The colour the engine paints at (x, y) below a ground top _h
function terrain_colour(_x, _y, _h)
{
    var _d = _y - _h;
    if (_d < 2) { return proj.terrain_cols[0]; }
    if (_d < 10) { return proj.terrain_cols[1]; }
    var _t = (_x * 97 + _y * 57) & 0xffff;
    if ((((_t * _t) >> 7) & 31) == 0) { return proj.terrain_cols[3]; }
    return proj.terrain_cols[2];
}

/// Index surface of the selected level's hills (clear above the ground)
function terrain_surface()
{
    var _h = level_heights_shown();
    if (is_undefined(_h)) { return -1; }
    var _key = string(lvl_sel) + "|" + string(proj.terrain_cols) + "|" + string(terr_version);
    if (!surface_exists(terr_surf))
    {
        terr_surf = surface_create(BD_W, BD_H);
        terr_key = "";
    }
    if (_key != terr_key)
    {
        var _buf = buffer_create(BD_W * BD_H * 4, buffer_fixed, 1);
        for (var py = 0; py < BD_H; py++)
        {
            for (var px = 0; px < BD_W; px++)
            {
                if (py >= _h[px] && _h[px] < 256) { buffer_write(_buf, buffer_u32, 0xff000000 | terrain_colour(px, py, _h[px])); }
                else { buffer_write(_buf, buffer_u32, 0); }
            }
        }
        buffer_set_surface(_buf, terr_surf, 0);
        buffer_delete(_buf);
        terr_key = _key;
    }
    return terr_surf;
}

/// Draws the hills over the backdrop through the palette shader
function terrain_draw(_x, _y, _scale)
{
    var _s = terrain_surface();
    if (_s == -1) { return; }
    backdrop_shader_begin();
    draw_surface_ext(_s, _x, _y, _scale, _scale, 0, c_white, 1);
    backdrop_shader_end();
}

/// Marks the hills as changed so the preview is rebuilt
function terrain_changed()
{
    terr_version += 1;
    ground_cache_time = -10000;
    proj_dirty = true;
}

function ws_levels_draw(_x1, _y1, _x2, _y2)
{
    var _lw = 210;
    var _rw = 340;
    var _nl = array_length(proj.levels);

    // ---------------- level list ----------------
    ui_panel(_x1, _y1, _x1 + _lw, _y2, "Levels (" + string(_nl) + " / " + string(LEVEL_MAX) + ")");
    var _on = ui_toggle("lvl_on", _x1 + 16, _y1 + 54, "Levels and hills", proj.levels_on, "Levels|Turn on to make a game of up to 10 levels. Each level has its own hills, made from a seed and shaped by hand. Collecting the goal moves on to the next level.");
    if (_on != proj.levels_on)
    {
        undo_mark("lvlon" + string(current_time));
        proj.levels_on = _on;
        if (_on && array_length(proj.levels) == 0) { array_push(proj.levels, level_new(1000)); }
        terrain_changed();
    }
    var _ly = _y1 + 92;
    for (var i = 0; i < _nl; i++)
    {
        var _ry = _ly + i * 40;
        var _id = "lvl_slot_" + string(i);
        var _hot = ui_register(_id, _x1 + 10, _ry, _x1 + _lw - 10, _ry + 34, "Level " + string(i + 1) + "|Click to edit this level's hills.");
        var _tgt = 0;
        if (_hot) { _tgt = 1; }
        var _a = ui_anim_to(_id, _tgt);
        if (lvl_sel == i) { ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + 34, 9, global.TH.accent, global.TH.accent_dark, 0.9); }
        else { ui_rrect(_x1 + 10, _ry, _x1 + _lw - 10, _ry + 34, 9, global.TH.btn_hot_top, global.TH.btn_hot_bot, 0.25 + _a * 0.75); }
        // little hill thumbnail
        var _hh = proj.levels[i].heights;
        draw_set_colour(pal_col(proj.terrain_cols[1]));
        for (var t = 0; t < 64; t++)
        {
            var _hy = (_hh[t * 5] - 100) / 140 * 22;
            draw_line(_x1 + 18 + t, _ry + 6 + _hy, _x1 + 18 + t, _ry + 29);
        }
        ui_text(_x1 + 92, _ry + 11, "Level " + string(i + 1), global.TH.text, fa_left, fa_middle, global.f_bold, 1);
        var _en = 0;
        for (var a = 0; a < array_length(proj.actors); a++)
        {
            if (proj.actors[a].from_level <= i + 1) { _en += 1; }
        }
        var _acol = global.TH.text_dim;
        if (lvl_sel == i) { _acol = global.TH.text; }
        var _atxt = string(_en) + " actors";
        if (_en == 1) { _atxt = "1 actor"; }
        ui_text(_x1 + 92, _ry + 25, _atxt, _acol, fa_left, fa_middle, global.f_small, 1);
        if (_hot && ui_pressed)
        {
            lvl_sel = i;
            ui_take_click();
        }
    }
    lvl_sel = clamp(lvl_sel, 0, max(0, _nl - 1));
    var _by = _y2 - 88;
    var _bw = _lw - 32;
    var _ast = BTN_ACCENT;
    if (_nl >= LEVEL_MAX) { _ast = BTN_GHOST; }
    if (ui_button("lvl_add", _x1 + 16, _by, _bw, 34, "Add level", "Add level|Adds a level after the last one with new hills from the next seed.", _ast))
    {
        if (_nl < LEVEL_MAX)
        {
            undo_mark("lvladd" + string(current_time));
            var _seed = 1000 + _nl * 37;
            var _new = level_new(_seed);
            if (_nl > 0)
            {
                _new.hilly = min(150, proj.levels[_nl - 1].hilly + 8);
                _new.base = proj.levels[_nl - 1].base;
                _new.heights = terrain_generate(_new.seed, _new.hilly, _new.base);
            }
            array_push(proj.levels, _new);
            proj.levels_on = true;
            lvl_sel = _nl;
            terrain_changed();
        }
        else { toast("10 levels is the maximum", 1); }
    }
    if (ui_button("lvl_del", _x1 + 16, _by + 42, _bw, 34, "Remove level", "Remove level|Deletes the selected level. You can Undo this.", BTN_DANGER))
    {
        if (_nl > 1)
        {
            undo_mark("lvldel" + string(current_time));
            array_delete(proj.levels, lvl_sel, 1);
            lvl_sel = max(0, lvl_sel - 1);
            terrain_changed();
        }
        else { toast("Keep at least one level - or switch levels off", 1); }
    }

    // ---------------- canvas ----------------
    var _cx1 = _x1 + _lw + 12;
    var _cx2 = _x2 - _rw - 12;
    ui_panel(_cx1, _y1, _cx2, _y2, "");
    var _scale = min((_cx2 - _cx1 - 32) / BD_W, (_y2 - _y1 - 80) / BD_H);
    if (_scale >= 2) { _scale = floor(_scale); }
    var _fw = BD_W * _scale;
    var _fh = BD_H * _scale;
    var _fx = floor((_cx1 + _cx2 - _fw) / 2);
    var _fy = floor((_y1 + _y2 - _fh) / 2) - 10;
    ui_rrect(_fx - 6, _fy - 6, _fx + _fw + 6, _fy + _fh + 6, 10, c_black, c_black, 0.35);
    backdrop_draw(_fx, _fy, _scale);
    if (!proj.levels_on || _nl == 0)
    {
        ui_text_wrap(_fx + 20, _fy + 20, "Turn on 'Levels and hills' to give your game up to 10 levels, each with its own ground to walk on.", c_white, _fw - 40, global.f_body, 1);
        levels_side_panel(_x2 - _rw, _y1, _x2, _y2);
        return;
    }
    terrain_draw(_fx, _fy, _scale);
    var _lev = proj.levels[lvl_sel];
    // actors that are on this level
    var _alloc = actors_alloc_channels();
    for (var d = array_length(proj.actors) - 1; d >= 0; d--)
    {
        var _ac = proj.actors[d];
        if (_ac.from_level > lvl_sel + 1) { continue; }
        var _ay = _ac.y;
        if (_ac.role == 6 || _ac.role == 7 || _ac.role == 8)
        {
            var _bb = sprite_bottom(_ac.sprite);
            _ay = _lev.heights[clamp(_ac.x + 8, 0, BD_W - 1)] - _bb - 1;
        }
        draw_sprite_amiga_cols(_ac.sprite, _fx + _ac.x * _scale, _fy + _ay * _scale, _scale, actor_cols_from(_alloc, d), 0.9);
    }
    // shape the ground by drawing the hill line
    var _hot2 = ui_register("lvl_canvas", _fx, _fy, _fx + _fw, _fy + _fh, "Shape the hills|Drag with the left button to draw where the ground is. Right-drag smooths it. Generate on the right makes fresh hills from the seed.");
    if (_hot2 && (ui_pressed || ui_rpressed))
    {
        undo_mark("lvldraw" + string(current_time));
        lvl_drawing = true;
        lvl_last_x = -1;
        ui_take_click();
    }
    if (lvl_drawing)
    {
        if (ui_held || ui_rheld)
        {
            var _mx = clamp(floor((ui_mx - _fx) / _scale), 0, BD_W - 1);
            var _my = clamp(floor((ui_my - _fy) / _scale), 100, 240);
            var _ax = _mx;
            var _bx = _mx;
            if (lvl_last_x >= 0)
            {
                _ax = min(_mx, lvl_last_x);
                _bx = max(_mx, lvl_last_x);
            }
            for (var c = max(0, _ax - 3); c <= min(BD_W - 1, _bx + 3); c++)
            {
                if (ui_held)
                {
                    var _t = 1;
                    if (c < _ax) { _t = 1 - (_ax - c) / 4; }
                    if (c > _bx) { _t = 1 - (c - _bx) / 4; }
                    _lev.heights[c] = round(lerp(_lev.heights[c], _my, _t));
                }
                else
                {
                    var _l = _lev.heights[max(0, c - 2)];
                    var _r = _lev.heights[min(BD_W - 1, c + 2)];
                    _lev.heights[c] = round((_l + _lev.heights[c] * 2 + _r) / 4);
                }
            }
            lvl_last_x = _mx;
            terrain_changed();
        }
        else { lvl_drawing = false; }
    }
    ui_text((_cx1 + _cx2) / 2, _fy + _fh + 22, "Level " + string(lvl_sel + 1) + "  -  drag to draw the ground, right-drag to smooth it", global.TH.text_faint, fa_center, fa_middle, global.f_small, 1);

    levels_side_panel(_x2 - _rw, _y1, _x2, _y2);
}

/// Lowest drawn row of a sprite (feet)
function sprite_bottom(_si)
{
    var _px = proj.sprites[clamp(_si, 0, SPR_COUNT - 1)].px;
    for (var q = SPR_W * SPR_H - 1; q >= 0; q--)
    {
        if (_px[q] != 0) { return q div SPR_W; }
    }
    return SPR_H - 1;
}

function levels_side_panel(_px, _y1, _x2, _y2)
{
    ui_panel(_px, _y1, _x2, _y2, "Level settings");
    var _fx = _px + 20;
    var _fw = _x2 - _px - 40;
    var _half = floor((_fw - 12) / 2);
    var _y = _y1 + 56;
    var _nl = array_length(proj.levels);
    var _content = 980;
    var _off = ui_scroll_begin("lvl_side", _px + 4, _y1 + 46, _x2 - 4, _y2 - 6, _content);
    _y -= _off;
    if (proj.levels_on && _nl > 0)
    {
        var _lev = proj.levels[lvl_sel];
        ui_heading(_fx, _y, "Level " + string(lvl_sel + 1) + " hills");
        _y += 20;
        ui_heading(_fx, _y, "Seed");
        var _ns = ui_stepper("lvl_seed", _fx, _y + 18, _half, _lev.seed, 1, 99999, "Seed|The number the hills grow from. The same seed always gives the same hills. Change it, then press Generate.");
        if (_ns != _lev.seed)
        {
            undo_mark("lvlseed");
            _lev.seed = _ns;
        }
        if (ui_button("lvl_gen", _fx + _half + 12, _y + 18, _half, 30, "Generate", "Generate hills|Replaces this level's ground with fresh hills from the seed, hilliness and height. You can then reshape them by drawing.", BTN_ACCENT))
        {
            undo_mark("lvlgen" + string(current_time));
            _lev.heights = terrain_generate(_lev.seed, _lev.hilly, _lev.base);
            terrain_changed();
        }
        _y += 60;
        ui_heading(_fx, _y, "Hilliness  " + string(_lev.hilly) + "%");
        set_val(_lev, "hilly", ui_slider("lvl_hilly", _fx, _y + 18, _fw, _lev.hilly, 0, 150, "Hilliness|How steep and tall the hills are when you press Generate."), "lvlhilly");
        _y += 52;
        ui_heading(_fx, _y, "Ground height  " + string(256 - _lev.base));
        set_val(_lev, "base", ui_slider("lvl_base", _fx, _y + 18, _fw, _lev.base, 150, 230, "Ground height|Where the middle of the hills sits when you press Generate. Higher numbers here mean lower ground."), "lvlbase");
        _y += 62;
    }

    ui_heading(_fx, _y, "Hill colours (all levels)");
    _y += 18;
    var _tn = ["Edge", "Grass", "Soil", "Specks"];
    var _th = ["Edge colour|The top line of the ground.", "Grass colour|The band under the edge.", "Soil colour|Everything below the grass.", "Speck colour|Little stones scattered through the soil."];
    for (var k = 0; k < 4; k++)
    {
        var _cx = _fx + (k mod 2) * (_half + 12);
        var _cy = _y + (k div 2) * 56;
        ui_text(_cx, _cy, _tn[k], global.TH.text_faint, fa_left, fa_top, global.f_small, 1);
        var _v = ui_colour_drop("lvl_col_" + string(k), _cx, _cy + 16, _half, 30, proj.terrain_cols[k], _th[k]);
        if (_v != proj.terrain_cols[k])
        {
            undo_mark("lvlcol" + string(k));
            proj.terrain_cols[k] = _v;
            terrain_changed();
        }
    }
    _y += 122;

    ui_heading(_fx, _y, "Level goal");
    _y += 20;
    set_val(proj, "goal_on", ui_toggle("lvl_goal_on", _fx, _y, "Count things to collect", proj.goal_on, "Goal counter|Shows a counter like GEMS 00/20 at the top. The 'Count towards the level goal' action adds one; reaching the target finishes the level (or wins on the last one)."), "goalon");
    _y += 34;
    ui_heading(_fx, _y, "Label");
    set_val(proj, "goal_label", string_upper(ui_textfield("lvl_goal_label", _fx, _y + 18, _half, 30, proj.goal_label, 6, "Goal label|The word shown before the counter, e.g. GEMS, STARS or KEYS.")), "goallabel");
    ui_heading(_fx + _half + 12, _y, "How many per level");
    set_val(proj, "goal", ui_stepper("lvl_goal", _fx + _half + 12, _y + 18, _half, proj.goal, 1, 99, "Goal|How many to collect on each level."), "goal");
    _y += 62;

    ui_heading(_fx, _y, "Screens");
    _y += 20;
    set_val(proj, "title_on", ui_toggle("lvl_title_on", _fx, _y, "Title screen", proj.title_on, "Title screen|Shows your title in big letters before the game. The player presses fire to start."), "titleon");
    _y += 34;
    ui_heading(_fx, _y, "Title (big letters)");
    set_val(proj, "title1", string_upper(ui_textfield("lvl_title1", _fx, _y + 18, _fw, 30, proj.title1, 18, "Title|Up to 18 letters, shown twice the normal size.")), "title1");
    _y += 56;
    ui_heading(_fx, _y, "Line under the title");
    set_val(proj, "title2", string_upper(ui_textfield("lvl_title2", _fx, _y + 18, _fw, 30, proj.title2, 36, "Subtitle|A line under the title, e.g. PRESS FIRE TO START.")), "title2");
    _y += 56;
    ui_heading(_fx, _y, "Level card word");
    set_val(proj, "lev_text", string_upper(ui_textfield("lvl_levtxt", _fx, _y + 18, _half, 30, proj.lev_text, 10, "Level card|Between levels a card shows this word and the level number, e.g. LEVEL 3. The player presses fire to go on.")), "levtxt");
    _y += 60;
    ui_text_wrap(_fx, _y, "After the last level the Win message (Home page) is shown - make it a big congratulations!", global.TH.text_faint, _fw, global.f_small, 1);
    ui_scroll_end("lvl_side", _px + 4, _y1 + 46, _x2 - 4, _y2 - 6, _content);
}
