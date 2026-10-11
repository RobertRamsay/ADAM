/// ADAM - Lite / Pro licence
///
/// ADAM Lite is free; ADAM Pro unlocks with a licence key bought on itch.io.
/// Keys look like ADAM-XXXX-XXXX-XXXX-XXXX: 8 characters of serial number and
/// 8 of signature (SHA-1 of LICENCE_SECRET + serial). They are checked here,
/// offline. The repo is public, so LICENCE_SECRET (scr_licence_secret) is a
/// placeholder there; release builds swap in the real one from outside the
/// repo (tools/licence_secret.ps1). Keys are made with tools/make_licence_keys.ps1
/// from that private file and uploaded to itch.io as external keys.
/// Every Pro feature asks pro_on() (or pro_gate() for a button press).

#macro LICENCE_DEV_SECRET "ADAM-DEV-PLACEHOLDER"   // the public placeholder in scr_licence_secret
#macro LICENCE_ALPHABET "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   // 32 characters, no 0/O or 1/I
#macro ADAM_PRO_OVERRIDE -1     // testing only: -1 = use the key, 0 = always Lite, 1 = always Pro. Must be -1 for public builds.
#macro ADAM_PRO_URL ""          // the ADAM Pro page on itch.io ("" hides the 'Get ADAM Pro' button)

/// True when Pro features may be used
function pro_on()
{
    if (ADAM_PRO_OVERRIDE >= 0) { return ADAM_PRO_OVERRIDE == 1; }
    return pro_unlocked;
}

/// For a Pro button or action: true if Pro is on, otherwise a friendly
/// message saying where to unlock it. _what names the feature.
function pro_gate(_what)
{
    if (pro_on()) { return true; }
    toast(_what + " is part of ADAM Pro - click LITE at the top to add a key", 1);
    return false;
}

/// Key with spaces, dashes and the ADAM prefix taken out, in capitals
function licence_normalise(_s)
{
    var _k = string_upper(_s);
    _k = string_replace_all(_k, " ", "");
    _k = string_replace_all(_k, "-", "");
    if (string_length(_k) == 20 && string_copy(_k, 1, 4) == "ADAM") { _k = string_delete(_k, 1, 4); }
    return _k;
}

/// The 8-character signature for an 8-character serial
function licence_sign(_serial)
{
    var _hex = "0123456789abcdef";
    var _h = string_lower(sha1_string_utf8(LICENCE_SECRET + _serial));
    var _out = "";
    for (var i = 0; i < 8; i++)
    {
        var _hi = string_pos(string_char_at(_h, i * 2 + 1), _hex) - 1;
        var _lo = string_pos(string_char_at(_h, i * 2 + 2), _hex) - 1;
        var _byte = _hi * 16 + _lo;
        _out += string_char_at(LICENCE_ALPHABET, (_byte mod 32) + 1);
    }
    return _out;
}

/// True if _s is a real ADAM Pro key (any spacing / dashes / case)
function licence_check(_s)
{
    // a public build still holding the placeholder secret takes no keys at
    // all - anyone could make keys for it (see scr_licence_secret)
    if (!ADAM_DEV_TOOLS && LICENCE_SECRET == LICENCE_DEV_SECRET) { return false; }
    var _k = licence_normalise(_s);
    if (string_length(_k) != 16) { return false; }
    for (var i = 1; i <= 16; i++)
    {
        if (string_pos(string_char_at(_k, i), LICENCE_ALPHABET) == 0) { return false; }
    }
    return licence_sign(string_copy(_k, 1, 8)) == string_copy(_k, 9, 8);
}

/// ADAM-XXXX-XXXX-XXXX-XXXX
function licence_format(_s)
{
    var _k = licence_normalise(_s);
    if (string_length(_k) != 16) { return _s; }
    return "ADAM-" + string_copy(_k, 1, 4) + "-" + string_copy(_k, 5, 4) + "-" + string_copy(_k, 9, 4) + "-" + string_copy(_k, 13, 4);
}

/// Tries to unlock Pro with _s; saves the key when it is good
function licence_enter(_s)
{
    if (!licence_check(_s))
    {
        licence_msg = "That key doesn't look right - check it against the one from itch.io.";
        return false;
    }
    licence_key = licence_format(_s);
    pro_unlocked = true;
    licence_msg = "";
    settings_save();
    toast("ADAM Pro unlocked - thank you!", 0);
    return true;
}

/// Back to Lite on this computer (the key can be entered again later)
function licence_remove()
{
    licence_key = "";
    pro_unlocked = false;
    licence_entry = "";
    licence_msg = "";
    settings_save();
    toast("Licence key removed - this is ADAM Lite again", 0);
}

/// Dev check (ADAM_DEV_TOOLS): a made-up serial signs and checks, a changed key fails
function licence_selftest()
{
    var _serial = "TESTKEYS";
    var _key = licence_format(_serial + licence_sign(_serial));
    var _ok = licence_check(_key) && licence_check(string_lower(string_replace_all(_key, "-", " ")));
    var _bad = string_copy(_key, 1, string_length(_key) - 1) + "Z";
    if (string_char_at(_key, string_length(_key)) == "Z") { _bad = string_copy(_key, 1, string_length(_key) - 1) + "Y"; }
    _ok = _ok && !licence_check(_bad) && !licence_check("ADAM-1234") && !licence_check("");
    if (_ok) { show_debug_message("ADAM licence self-test: PASS (" + _key + ")"); }
    else { show_debug_message("ADAM licence self-test: FAIL"); }
}
