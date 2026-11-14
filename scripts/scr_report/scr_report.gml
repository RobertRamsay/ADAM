/// ADAM - 'Submit your game' and crash reports (run in obj_app scope), as in
/// Amiga Dev Machine's scr_community_submit / scr_crash_report.
///
/// Both post a short text message to one Discord channel webhook for the developer
/// to read, and only when the user presses Send:
/// - Submit your game (Home page > Community > 'Submit your game'): the user puts
///   their .adam project somewhere it can be downloaded and types a title, who made
///   it, the link, and optionally how to reach them and a note. Only those lines and
///   the ADAM version are sent - never a file, a path or anything from the project.
/// - Crash reports: when ADAM hits an error it cannot recover from, the
///   unhandled-exception handler writes a small text file (nothing goes over the
///   network from a dying program). The next start finds it and ASKS whether to send
///   it, with room for a note. Either way the file is gone afterwards. The report
///   holds the error and where in ADAM it happened, the version, edition, platform,
///   chosen Amiga, the page that was open and how many actors and rules there were -
///   nothing else from the project, no file names, nothing about the person.
///   'Ask me after a crash' on the panel ([ui] crash_ask in adam_settings.ini) switches it off.
///
/// THE WEBHOOK URL IS PUBLIC once shipped (it is in the exe). Give it a channel of
/// its own; if it is abused, delete the webhook in Discord and paste a new one.
/// ADAM_WEBHOOK_URL lives in scr_webhook_secret (committed empty). An
/// adam_webhook.txt beside the exe overrides it (to test against a private channel).
/// Empty = nothing is ever sent.

#macro REPORT_GAP_MS 60000          // one submission a minute
#macro REPORT_MAX 1800              // Discord's limit is 2000 characters
#macro CRASH_NOTE_MAX 400
#macro CRASH_FILE "adam_crash_report.txt"
#macro SUBMIT_FIELDS 5

/// The webhook to post to ("" = sending is off in this copy)
function report_webhook_url()
{
    var _txt = file_read_text(program_directory + "adam_webhook.txt");
    if (_txt != "")
    {
        _txt = string_replace_all(_txt, "\r", "\n");
        var _nl = string_pos("\n", _txt);
        if (_nl > 0) { _txt = string_copy(_txt, 1, _nl - 1); }
        _txt = string_trim(_txt);
        if (string_pos("https://", _txt) == 1) { return _txt; }
    }
    return ADAM_WEBHOOK_URL;
}

/// Posts _content to the webhook under the name _username. Returns the http
/// request id (-1: not sent); the answer arrives in report_async.
function report_post(_username, _content)
{
    var _url = report_webhook_url();
    if (_url == "") { return -1; }
    // no allowed mentions: a typed @everyone stays plain text
    var _body = { username : _username, content : _content, allowed_mentions : { parse : [] } };
    var _headers = ds_map_create();
    ds_map_add(_headers, "Content-Type", "application/json");
    ds_map_add(_headers, "Accept", "application/json");
    ds_map_add(_headers, "User-Agent", "ADAM/" + ADAM_VERSION);     // Discord refuses a request without one
    var _req = http_request(_url, "POST", _headers, json_stringify(_body));
    ds_map_destroy(_headers);
    return _req;
}

/// One typed value made safe for a Discord message: one line, no code fence, at most _max long
function report_clean(_text, _max)
{
    var _t = string(_text);
    _t = string_replace_all(_t, "\r", " ");
    _t = string_replace_all(_t, "\n", " ");
    _t = string_replace_all(_t, "```", "'''");
    _t = string_trim(_t);
    if (string_length(_t) > _max) { _t = string_copy(_t, 1, _max); }
    return _t;
}

/// "Pro" or "Lite"
function report_edition()
{
    if (pro_edition()) { return "Pro"; }
    return "Lite";
}

/// Async HTTP event: the webhook's answer to a submission or a crash report
function report_async()
{
    var _id = async_load[? "id"];
    if (submit_req >= 0 && _id == submit_req)
    {
        if (async_load[? "status"] == 1) { return; }     // still on its way
        submit_req = -1;
        var _http = async_load[? "http_status"];
        if (async_load[? "status"] == 0 && is_real(_http) && _http >= 200 && _http < 300)
        {
            submit_state = 2;
            submit_msg_good = true;
            submit_msg = "Thank you - your game was sent. If it is chosen it will come with a later version of ADAM, with your credit.";
        }
        else
        {
            submit_state = 0;
            submit_msg_good = false;
            submit_msg = "Could not send (" + string(_http) + "). Please try again later.";
            submit_last = -REPORT_GAP_MS;      // a failed try does not count
        }
        return;
    }
    if (crash_req >= 0 && _id == crash_req)
    {
        if (async_load[? "status"] == 1) { return; }
        crash_req = -1;
        var _http2 = async_load[? "http_status"];
        if (async_load[? "status"] == 0 && is_real(_http2) && _http2 >= 200 && _http2 < 300)
        {
            crash_state = 2;
            crash_msg_good = true;
            crash_msg = "Thank you - the report was sent.";
        }
        else
        {
            crash_state = 0;
            crash_msg_good = false;
            crash_msg = "Could not send (" + string(_http2) + "). You can try again, or choose Don't send.";
        }
    }
}

// ---------------------------------------------------------------------------
// Submit your game
// ---------------------------------------------------------------------------

/// Field _i of the form: { label, hint, max, need }
function submit_field(_i)
{
    switch (_i)
    {
        case 0: return { label : "Game title", hint : "What the game is called.", max : 60, need : true };
        case 1: return { label : "Made by", hint : "Your name or your team's, as it should be credited.", max : 60, need : true };
        case 2: return { label : "Link to your files", hint : "https://... where your .adam project file (and a picture of the game, if you have one) can be downloaded. Ctrl+V pastes.", max : 300, need : true };
        case 3: return { label : "How to reach you (optional)", hint : "An e-mail address or a Discord name, if you want an answer.", max : 100, need : false };
    }
    return { label : "Anything else (optional)", hint : "What kind of game it is, the controls, which Amiga it is for.", max : 400, need : false };
}

/// Opens the form (Home page, Community panel)
function submit_open()
{
    submit_active = true;
    submit_anim = 0;
    submit_state = 0;
    submit_msg = "";
    submit_msg_good = false;
    submit_agree = false;
    ui_popup_open = false;
    tut_offer_on = false;
    ui_focus = "submit_f0";
    keyboard_string = submit_vals[0];
}

/// "" when the form can be sent, else what is missing (_vals: the SUBMIT_FIELDS strings)
function submit_problem(_vals)
{
    for (var i = 0; i < SUBMIT_FIELDS; i++)
    {
        var _f = submit_field(i);
        if (_f.need && report_clean(_vals[i], _f.max) == "") { return "Please fill in '" + _f.label + "'."; }
    }
    var _link = report_clean(_vals[2], 300);
    if (string_pos("https://", _link) != 1 && string_pos("http://", _link) != 1) { return "The link must start with https:// - paste the address of the page or file."; }
    if (string_pos(" ", _link) > 0 || string_pos(".", _link) == 0) { return "That link does not look complete - paste the whole address."; }
    return "";
}

/// The message that goes to the channel
function submit_text(_vals)
{
    var _t = "**COMMUNITY GAME SUBMITTED** - ADAM " + report_edition() + " v" + ADAM_VERSION;
    _t += "\nTitle: " + report_clean(_vals[0], 60);
    _t += "\nBy: " + report_clean(_vals[1], 60);
    // <...> keeps Discord from fetching a preview of a link nobody has looked at yet
    _t += "\nLink: <" + report_clean(_vals[2], 300) + ">";
    var _contact = report_clean(_vals[3], 100);
    if (_contact != "") { _t += "\nContact: " + _contact; }
    var _note = report_clean(_vals[4], 400);
    if (_note != "") { _t += "\nNote: " + _note; }
    _t += "\nAgreed: the whole project will be open to everyone";
    if (string_length(_t) > REPORT_MAX) { _t = string_copy(_t, 1, REPORT_MAX); }
    return _t;
}

/// Send: checks the form, then posts it
function submit_send()
{
    if (submit_state != 0) { return; }
    submit_msg_good = false;
    var _problem = submit_problem(submit_vals);
    if (_problem != "")
    {
        submit_msg = _problem;
        return;
    }
    if (!submit_agree)
    {
        submit_msg = "Please switch on 'I understand' first: everything in your game will be open for everyone.";
        return;
    }
    if (report_webhook_url() == "")
    {
        submit_msg = "Submissions are not set up in this copy of ADAM. Please post your link on the ADAM page on itch.io instead.";
        return;
    }
    if (current_time - submit_last < REPORT_GAP_MS)
    {
        submit_msg = "A submission was sent a moment ago - please try again in a minute.";
        return;
    }
    submit_req = report_post("ADAM community", submit_text(submit_vals));
    if (submit_req < 0)
    {
        submit_req = -1;
        submit_msg = "Could not send - is this computer on the internet?";
        return;
    }
    submit_last = current_time;
    submit_state = 1;
    submit_msg = "Sending...";
    ui_focus = "";
}

/// The form, drawn over the page while submit_active
function submit_draw(_gw, _gh)
{
    if (!submit_active) { return; }
    submit_anim = lerp(submit_anim, 1, 0.2);
    var _a = submit_anim;
    ui_force_input = true;

    draw_set_alpha(0.7 * _a);
    draw_rectangle_colour(0, 0, _gw, _gh, c_black, c_black, global.TH.bg_bot, global.TH.bg_bot, false);
    draw_set_alpha(1);

    var _w = min(700, _gw - 80);
    var _tw = _w - 48;
    var _intro = "Offer a game you made with ADAM for the Community list. Put your .adam project file somewhere it can be downloaded, then paste the link here. Only what you type below is sent, when you click Send.";
    var _warn = "Everything in it will be open: anyone with ADAM can load your game and look at, copy and change all of its art, rules, sounds and music. Only send a game that is yours to share. That choice is yours, and so is the responsibility for it.";
    draw_set_font(global.f_body);
    var _ih = ceil(ui_sh_ext(_intro, _tw));
    var _wh = ceil(ui_sh_ext(_warn, _tw - 24));
    var _mh = 0;
    if (submit_msg != "") { _mh = ceil(ui_sh_ext(submit_msg, _tw)) + 8; }
    var _row = 52;
    var _h = 20 + 40 + 8 + _ih + 10 + (_wh + 16) + 12 + SUBMIT_FIELDS * _row + 4 + 24 + 10 + _mh + 36 + 20;
    var _x1 = floor((_gw - _w) / 2);
    var _y1 = max(8, floor((_gh - _h) / 2)) + round((1 - _a) * 16);
    var _x2 = _x1 + _w;
    var _y2 = _y1 + _h;
    ui_panel(_x1, _y1, _x2, _y2, "");

    draw_boing(_x1 + 24, _y1 + 20, 34, _a);
    ui_text(_x1 + 70, _y1 + 37, "Submit your game", c_white, fa_left, fa_middle, global.f_title, _a);
    var _cy = _y1 + 20 + 40 + 8;
    ui_text_wrap(_x1 + 24, _cy, _intro, global.TH.text_dim, _tw, global.f_body, _a);
    _cy += _ih + 10;
    var _amber = make_colour_rgb(255, 196, 96);
    ui_inset(_x1 + 24, _cy, _x2 - 24, _cy + _wh + 16, 8);
    ui_rrect_line(_x1 + 24, _cy, _x2 - 24, _cy + _wh + 16, 8, _amber, 0.7 * _a, 1);
    ui_text_wrap(_x1 + 36, _cy + 8, _warn, _amber, _tw - 24, global.f_body, _a);
    _cy += _wh + 16 + 12;

    // ---------- the fields: label on the left, box on the right ----------
    var _foc = -1;
    for (var q = 0; q < SUBMIT_FIELDS; q++)
    {
        if (ui_focus == "submit_f" + string(q)) { _foc = q; }
    }
    var _lw = 210;
    for (var i = 0; i < SUBMIT_FIELDS; i++)
    {
        var _f = submit_field(i);
        var _fy = _cy + i * _row;
        ui_text(_x1 + 24, _fy + 16, _f.label, global.TH.text, fa_left, fa_middle, global.f_body, _a);
        if (submit_state == 0)
        {
            submit_vals[i] = ui_textfield("submit_f" + string(i), _x1 + 24 + _lw, _fy, _tw - _lw, 32, submit_vals[i], _f.max, _f.label + "|" + _f.hint);
        }
        else
        {
            ui_inset(_x1 + 24 + _lw, _fy, _x2 - 24, _fy + 32, 8);
            ui_text(_x1 + 34 + _lw, _fy + 16, ui_text_fit(submit_vals[i], global.f_body, _tw - _lw - 20), global.TH.text_dim, fa_left, fa_middle, global.f_body, _a);
        }
        ui_text(_x1 + 24 + _lw + 2, _fy + 35, ui_text_fit(_f.hint, global.f_small, _tw - _lw - 4), global.TH.text_faint, fa_left, fa_top, global.f_small, _a);
    }
    // Tab / Enter go to the next field, Shift+Tab to the one before (Enter on the last ends typing)
    if (submit_state == 0 && _foc >= 0)
    {
        var _to = -1;
        if (keyboard_check_pressed(vk_tab))
        {
            if (keyboard_check(vk_shift)) { _to = (_foc + SUBMIT_FIELDS - 1) mod SUBMIT_FIELDS; }
            else { _to = (_foc + 1) mod SUBMIT_FIELDS; }
        }
        else if (keyboard_check_pressed(vk_enter) && _foc < SUBMIT_FIELDS - 1)
        {
            _to = _foc + 1;
        }
        if (_to >= 0)
        {
            submit_vals[_foc] = string_replace_all(submit_vals[_foc], chr(9), "");
            ui_focus = "submit_f" + string(_to);
            keyboard_string = submit_vals[_to];
        }
    }
    _cy += SUBMIT_FIELDS * _row + 4;

    if (submit_state == 0)
    {
        submit_agree = ui_toggle("submit_agree", _x1 + 24, _cy, "I understand: my whole game will be open for everyone", submit_agree, "I understand|Switch this on to send. A community game is shared as its project, so everybody can open it in ADAM and see and reuse everything in it.");
    }
    _cy += 24 + 10;
    if (submit_msg != "")
    {
        var _mc = make_colour_rgb(255, 160, 90);
        if (submit_msg_good) { _mc = make_colour_rgb(120, 230, 140); }
        if (submit_state == 1) { _mc = global.TH.text; }
        ui_text_wrap(_x1 + 24, _cy, submit_msg, _mc, _tw, global.f_body, _a);
    }

    // ---------- buttons ----------
    var _by = _y2 - 20 - 36;
    var _close = false;
    var _cancel = "Cancel";
    if (submit_state == 2) { _cancel = "Close"; }
    if (submit_state == 0)
    {
        if (ui_button("submit_send", _x2 - 24 - 130, _by, 130, 36, "Send", "Send|Sends the lines above to the people who make ADAM. Nothing else is sent.", BTN_ACCENT)) { submit_send(); }
    }
    if (submit_state != 1)
    {
        var _cx = _x2 - 24 - 130 - 10 - 110;
        if (submit_state == 2) { _cx = _x2 - 24 - 110; }
        if (ui_button("submit_cancel", _cx, _by, 110, 36, _cancel, _cancel + "|Goes back to ADAM. Esc does the same. What you typed is kept until you close ADAM.", BTN_NORMAL)) { _close = true; }
        // Esc first ends typing in a field, then closes
        if (keyboard_check_pressed(vk_escape) && _foc < 0) { _close = true; }
    }
    ui_force_input = false;

    if (_close)
    {
        submit_active = false;
        ui_focus = "";
        if (submit_state == 2)
        {
            // sent: the next one starts empty
            submit_vals = array_create(SUBMIT_FIELDS, "");
            submit_state = 0;
        }
    }
}

// ---------------------------------------------------------------------------
// Crash reports
// ---------------------------------------------------------------------------

/// Where the crash file lives
function crash_path()
{
    return game_save_id + CRASH_FILE;
}

/// True when ADAM was started with one of its dev command lines (-adam_build,
/// -adam_shots...): those must fail loudly, with no handler in the way
function crash_dev_run()
{
    for (var i = 1; i < parameter_count(); i++)
    {
        if (string_pos("-adam_", parameter_string(i)) == 1) { return true; }
    }
    return false;
}

/// Called once from Create, after settings_load: installs the handler and picks up
/// a crash left by the last run (crash_active = the question is up)
function crash_init()
{
    global.crash_writing = false;
    if (crash_dev_run()) { return; }
    exception_unhandled_handler(function(_ex)
    {
        show_debug_message("FATAL: " + string(_ex));
        var _text = "";
        try
        {
            _text = crash_report_text(_ex);
            crash_write(_text);
        }
        catch (_e)
        {
            show_debug_message("crash report not written: " + string(_e));
        }
        if (_text == "") { _text = string(_ex); }
        show_message("ADAM hit an error and has to close.\n\nYour work is saved by itself every 30 seconds and opens again next time you start ADAM.\nNext time you start you can send this error to the people who make ADAM.\n\n" + _text);
        return 0;
    });
    crash_check_previous();
}

/// "v1.3.2 Pro windows A1200"
function crash_who()
{
    var _os = "other";
    if (os_type == os_windows) { _os = "windows"; }
    if (os_type == os_macosx) { _os = "macos"; }
    if (os_type == os_linux) { _os = "linux"; }
    var _who = "v" + ADAM_VERSION;
    try
    {
        _who += " " + report_edition() + " " + _os;
        _who += " " + string(obj_app.proj.machine);
    }
    catch (_e)
    {
        _who += " " + _os;
    }
    return _who;
}

/// The report for exception _ex (a struct from GameMaker, or anything else)
function crash_report_text(_ex)
{
    var _t = "ADAM crash\n" + crash_who();
    try
    {
        _t += "\npage " + ws_name(obj_app.ws) + ", actors " + string(array_length(obj_app.proj.actors)) + ", rules " + string(array_length(obj_app.proj.rules));
    }
    catch (_e0)
    {
        _t += "\n(state unreadable)";
    }
    _t += "\n\n--- error ---";
    try
    {
        if (is_struct(_ex))
        {
            var _m = _ex[$ "message"];
            if (!is_undefined(_m)) { _t += "\n" + string(_m); }
            var _sc = _ex[$ "script"];
            var _ln = _ex[$ "line"];
            if (is_undefined(_sc)) { _sc = "?"; }
            if (is_undefined(_ln)) { _ln = "?"; }
            _t += "\nin " + string(_sc) + " line " + string(_ln);
            var _long = _ex[$ "longMessage"];
            if (!is_undefined(_long) && string(_long) != "") { _t += "\n" + string(_long); }
            var _stack = _ex[$ "stacktrace"];
            if (is_array(_stack))
            {
                _t += "\n\n--- stack ---";
                for (var i = 0; i < array_length(_stack); i++)
                {
                    _t += "\n" + string(_stack[i]);
                }
            }
        }
        else
        {
            _t += "\n" + string(_ex);
        }
    }
    catch (_e1)
    {
        _t += "\n(error unreadable)";
    }
    return _t;
}

/// From the unhandled-exception handler: writes the report file, nothing else
function crash_write(_text)
{
    if (global.crash_writing) { return; }
    global.crash_writing = true;
    file_write_text(crash_path(), _text);
    global.crash_writing = false;
}

/// Picks up (and deletes) the file a crash left; the question opens when sending is possible
function crash_check_previous()
{
    var _path = crash_path();
    if (!file_exists(_path)) { return; }
    var _text = file_read_text(_path);
    file_delete(_path);
    if (string_trim(_text) == "") { return; }
    if (!crash_ask) { return; }
    if (report_webhook_url() == "") { return; }
    crash_text = _text;
    crash_note = "";
    crash_state = 0;
    crash_msg = "";
    crash_anim = 0;
    crash_active = true;
}

/// The message for the channel: the report (cut to fit) in a code fence, the user's note above it
function crash_message(_text, _note)
{
    var _n = report_clean(_note, CRASH_NOTE_MAX);
    var _t = string_replace_all(string(_text), "```", "'''");
    var _room = REPORT_MAX - string_length(_n) - 80;
    if (string_length(_t) > _room) { _t = string_copy(_t, 1, max(200, _room)) + "\n... trimmed"; }
    var _head = "**CRASH** - ADAM " + crash_who();
    if (_n != "") { _head += "\n> " + _n; }
    return _head + "\n```\n" + _t + "\n```";
}

/// Send report
function crash_send()
{
    if (crash_state != 0) { return; }
    crash_req = report_post("ADAM crash", crash_message(crash_text, crash_note));
    if (crash_req < 0)
    {
        crash_req = -1;
        crash_msg_good = false;
        crash_msg = "Could not send - is this computer on the internet? You can try again, or choose Don't send.";
        return;
    }
    crash_state = 1;
    crash_msg = "Sending...";
    ui_focus = "";
}

/// The question, drawn over everything (the machine picker waits) while crash_active
function crash_draw(_gw, _gh)
{
    if (!crash_active) { return; }
    crash_anim = lerp(crash_anim, 1, 0.2);
    var _a = crash_anim;
    ui_force_input = true;

    draw_set_alpha(0.86 * _a);
    draw_rectangle_colour(0, 0, _gw, _gh, c_black, c_black, global.TH.bg_bot, global.TH.bg_bot, false);
    draw_set_alpha(1);

    var _w = min(760, _gw - 80);
    var _tw = _w - 48;
    var _intro = "ADAM closed with an error last time. Sending the report below helps get it fixed. It holds the error and where in ADAM it happened, the version, which Amiga was picked and which page was open - nothing else from your game, no file names, nothing about you.";
    draw_set_font(global.f_body);
    var _ih = ceil(ui_sh_ext(_intro, _tw));
    var _mh = 0;
    if (crash_msg != "") { _mh = ceil(ui_sh_ext(crash_msg, _tw)) + 8; }
    var _rows = 9;
    var _lh = 18;
    var _rh = _rows * _lh + 16;
    var _h = 20 + 40 + 8 + _ih + 12 + _rh + 14 + 20 + 32 + 12 + 24 + 10 + _mh + 36 + 20;
    var _x1 = floor((_gw - _w) / 2);
    var _y1 = max(8, floor((_gh - _h) / 2)) + round((1 - _a) * 16);
    var _x2 = _x1 + _w;
    var _y2 = _y1 + _h;
    ui_panel(_x1, _y1, _x2, _y2, "");

    draw_boing(_x1 + 24, _y1 + 20, 34, _a);
    ui_text(_x1 + 70, _y1 + 37, "Send an error report?", c_white, fa_left, fa_middle, global.f_title, _a);
    var _cy = _y1 + 20 + 40 + 8;
    ui_text_wrap(_x1 + 24, _cy, _intro, global.TH.text_dim, _tw, global.f_body, _a);
    _cy += _ih + 12;

    // the report, as it will be sent
    ui_inset(_x1 + 24, _cy, _x2 - 24, _cy + _rh, 8);
    ui_register("crash_report", _x1 + 24, _cy, _x2 - 24, _cy + _rh, "The report|Exactly what is sent, apart from your note below. A long report is cut to fit one message.");
    var _lines = string_split(crash_text, "\n");
    var _nl = array_length(_lines);
    for (var i = 0; i < _nl && i < _rows; i++)
    {
        var _line = _lines[i];
        if (i == _rows - 1 && _nl > _rows) { _line = "... and " + string(_nl - _rows + 1) + " more lines"; }
        ui_text(_x1 + 36, _cy + 8 + i * _lh, ui_text_fit(_line, global.f_small, _tw - 24), global.TH.text, fa_left, fa_top, global.f_small, _a);
    }
    _cy += _rh + 14;

    // the note
    var _foc = (ui_focus == "crash_note");
    ui_text(_x1 + 24, _cy, "What were you doing when it closed? (optional)", global.TH.text, fa_left, fa_top, global.f_body, _a);
    _cy += 20;
    if (crash_state == 0)
    {
        crash_note = ui_textfield("crash_note", _x1 + 24, _cy, _tw, 32, crash_note, CRASH_NOTE_MAX, "Your note|A line about what you were doing helps a lot - which page, what you clicked. Leave it empty if you like.");
    }
    else
    {
        ui_inset(_x1 + 24, _cy, _x2 - 24, _cy + 32, 8);
        ui_text(_x1 + 34, _cy + 16, ui_text_fit(crash_note, global.f_body, _tw - 20), global.TH.text_dim, fa_left, fa_middle, global.f_body, _a);
    }
    _cy += 32 + 12;
    var _ask = ui_toggle("crash_ask", _x1 + 24, _cy, "Ask me after a crash", crash_ask, "Ask me after a crash|Switch this off and ADAM never asks to send an error report again. Nothing is ever sent without asking.");
    if (_ask != crash_ask)
    {
        crash_ask = _ask;
        settings_save();
    }
    _cy += 24 + 10;
    if (crash_msg != "")
    {
        var _mc = make_colour_rgb(255, 160, 90);
        if (crash_msg_good) { _mc = make_colour_rgb(120, 230, 140); }
        if (crash_state == 1) { _mc = global.TH.text; }
        ui_text_wrap(_x1 + 24, _cy, crash_msg, _mc, _tw, global.f_body, _a);
    }

    // ---------- buttons ----------
    var _by = _y2 - 20 - 36;
    var _close = false;
    if (crash_state == 0)
    {
        if (ui_button("crash_send", _x2 - 24 - 150, _by, 150, 36, "Send report", "Send report|Sends the report above and your note to the people who make ADAM.", BTN_ACCENT)) { crash_send(); }
    }
    if (crash_state != 1)
    {
        var _skip = "Don't send";
        var _cx = _x2 - 24 - 150 - 10 - 130;
        if (crash_state == 2)
        {
            _skip = "Close";
            _cx = _x2 - 24 - 130;
        }
        if (ui_button("crash_skip", _cx, _by, 130, 36, _skip, _skip + "|Goes on to ADAM. The report is thrown away. Esc does the same.", BTN_NORMAL)) { _close = true; }
        // Esc first ends typing in the note, then closes
        if (keyboard_check_pressed(vk_escape) && !_foc) { _close = true; }
    }
    ui_force_input = false;

    if (_close)
    {
        crash_active = false;
        crash_text = "";
        crash_note = "";
        ui_focus = "";
        io_clear();     // the Esc / click does not reach the machine picker underneath
    }
}

/// Dev check of the form's rules and both messages (IDE Output window)
function report_selftest()
{
    var _v = ["My Game", "Me", "https://example.com/game.adam", "", ""];
    var _bad = "";
    if (submit_problem(_v) != "") { _bad = "a good form is refused"; }
    var _text = submit_text(_v);
    if (string_pos("Title: My Game", _text) == 0 || string_pos("Link: <https://example.com/game.adam>", _text) == 0) { _bad = "submit message wrong"; }
    if (string_pos("Contact:", _text) > 0 || string_pos("Note:", _text) > 0) { _bad = "empty optional fields were sent"; }
    _v[2] = "example.com/game";
    if (submit_problem(_v) == "") { _bad = "a link without https:// was accepted"; }
    _v[2] = "https://example.com/game.adam";
    _v[0] = "   ";
    if (submit_problem(_v) == "") { _bad = "an empty title was accepted"; }
    _v[0] = "A";
    _v[4] = "line one\nline ``` two";
    _text = submit_text(_v);
    if (string_pos("```", _text) > 0 || string_count("\n", _text) != 5) { _bad = "a note is not cleaned"; }
    var _ex = { message : "Variable <unknown_object>.foo not set", script : "gml_Object_obj_app_Step_0", line : 12, longMessage : "ERROR in action number 1", stacktrace : ["gml_Object_obj_app_Step_0 (line 12)", "gml_Script_ws_home_draw (line 3)"] };
    var _rep = crash_report_text(_ex);
    if (string_pos("foo not set", _rep) == 0 || string_pos("line 12", _rep) == 0 || string_pos("--- stack ---", _rep) == 0) { _bad = "crash report text wrong"; }
    if (string_pos("ADAM crash\nv", _rep) != 1) { _bad = "crash report has no version line"; }
    var _msg = crash_message(_rep, "I pressed F5\nwith ``` in it");
    if (string_pos("**CRASH** - ADAM v", _msg) != 1 || string_pos("> I pressed F5 with ''' in it", _msg) == 0) { _bad = "crash message head wrong"; }
    var _long = "";
    repeat (400) { _long += "0123456789"; }
    if (string_length(crash_message(_long, "note")) > 2000) { _bad = "a long report is not trimmed"; }
    if (string_pos("something odd", crash_report_text("something odd")) == 0) { _bad = "a plain error is lost"; }
    if (_bad == "") { show_debug_message("report selftest: OK"); }
    else { show_debug_message("report selftest: FAILED - " + _bad); }
}
