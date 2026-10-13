/// ADAM - "a new version is out" check.
///
/// At start-up ADAM fetches latest.json from the public repo (one small GET,
/// nothing about the user is sent) and, when its version is newer than
/// ADAM_VERSION, shows a card in the bottom-right corner with a link to the
/// itch.io page. Off with Home > Game settings > "Check for updates".
/// latest.json is updated (and pushed) only AFTER a release is on itch.io -
/// see docs/RELEASE.md. It holds:
///   { "version" : "1.0.2", "lite_url" : "https://...", "pro_url" : "https://...",
///     "notes" : "One line about what is new" }

#macro ADAM_UPDATE_URL "https://raw.githubusercontent.com/RobertRamsay/ADAM/main/latest.json"

/// Starts the check (from Create, after the settings are loaded)
function update_check_start()
{
    if (!update_check_on) { return; }
    if (ADAM_UPDATE_URL == "") { return; }
    update_req = http_get(ADAM_UPDATE_URL);
}

/// True when version string _a is newer than _b ("1.0.10" > "1.0.9")
function version_newer(_a, _b)
{
    var _pa = string_split(_a, ".");
    var _pb = string_split(_b, ".");
    var _n = max(array_length(_pa), array_length(_pb));
    for (var i = 0; i < _n; i++)
    {
        var _va = 0;
        var _vb = 0;
        if (i < array_length(_pa)) { _va = real(string_digits(_pa[i])); }
        if (i < array_length(_pb)) { _vb = real(string_digits(_pb[i])); }
        if (_va > _vb) { return true; }
        if (_va < _vb) { return false; }
    }
    return false;
}

/// Async HTTP event: the reply to update_check_start
function update_async()
{
    if (update_req < 0) { return; }
    if (async_load[? "id"] != update_req) { return; }
    if (async_load[? "status"] == 1) { return; }
    update_req = -1;
    if (async_load[? "status"] != 0 || async_load[? "http_status"] != 200) { return; }   // offline: say nothing
    var _data = undefined;
    try
    {
        _data = json_parse(async_load[? "result"]);
    }
    catch (_e)
    {
        return;
    }
    if (!is_struct(_data)) { return; }
    var _ver = _data[$ "version"];
    if (!is_string(_ver)) { return; }
    if (!version_newer(_ver, ADAM_VERSION)) { return; }
    var _url = _data[$ "lite_url"];
    if (pro_edition()) { _url = _data[$ "pro_url"]; }
    if (!is_string(_url) || _url == "") { _url = ADAM_PRO_URL; }
    var _notes = _data[$ "notes"];
    if (!is_string(_notes)) { _notes = ""; }
    update_latest = _ver;
    update_url = _url;
    update_notes = _notes;
    update_card_on = true;
    update_card_anim = 0;
}

/// The card, bottom right. The page stays usable; only clicks on the card are
/// taken (see ui_frame_begin). Waits while a bigger panel or the tour offer is up.
function update_card_draw(_gw, _gh)
{
    if (!update_card_on || tut_offer_on || tut_active || les_active || machine_pick_active || about_active || whatsnew_active || confirm_active)
    {
        update_card_rect = [0, 0, 0, 0];
        return;
    }
    update_card_anim = lerp(update_card_anim, 1, 0.15);
    var _a = update_card_anim;
    var _w = 380;
    var _body = "A new version of ADAM is ready to download on itch.io.";
    if (update_notes != "") { _body = update_notes; }
    draw_set_font(global.f_body);
    var _bh = ceil(ui_sh_ext(_body, _w - 40));
    var _h = 20 + 26 + 8 + _bh + 16 + 34 + 18;
    var _x1 = _gw - _w - 20;
    var _y1 = _gh - 46 - _h - 14 + round((1 - _a) * 20);
    var _x2 = _x1 + _w;
    var _y2 = _y1 + _h;
    update_card_rect = [_x1, _y1, _x2, _y2];
    ui_force_input = true;
    ui_panel(_x1, _y1, _x2, _y2, "");
    draw_boing(_x1 + 20, _y1 + 20, 26, _a);
    ui_text(_x1 + 56, _y1 + 33, ui_text_fit("ADAM " + update_latest + " is out", global.f_title, _w - 56 - 20), c_white, fa_left, fa_middle, global.f_title, _a);
    ui_text_wrap(_x1 + 20, _y1 + 20 + 26 + 8, _body, global.TH.text, _w - 40, global.f_body, _a);
    var _by = _y2 - 18 - 34;
    var _close = false;
    if (ui_button("update_get", _x2 - 20 - 120, _by, 120, 34, "Get it", "Get it|Opens the ADAM page on itch.io, where the new version is. Install it over this one - your projects are kept.", BTN_ACCENT))
    {
        url_open(update_url);
        _close = true;
    }
    if (ui_button("update_later", _x2 - 20 - 120 - 10 - 110, _by, 110, 34, "Not now", "Not now|Hides this until you next start ADAM. Turn the check off on Home > Game settings.", BTN_NORMAL)) { _close = true; }
    ui_force_input = false;
    if (_close)
    {
        update_card_on = false;
        update_card_rect = [0, 0, 0, 0];
    }
}
