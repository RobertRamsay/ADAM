/// ADAM - Lite / Pro edition
///
/// ADAM Lite is free; ADAM Pro is a separate paid download on itch.io. Both
/// come from this one project: set ADAM_PRO below and build each one
/// (ADAM_..._LITE and ADAM_..._PRO, see docs/RELEASE.md).
/// Every Pro feature asks pro_on() (or pro_gate() for a button press).

#macro ADAM_PRO 0               // 0 = build ADAM Lite, 1 = build ADAM Pro
#macro ADAM_PRO_URL "https://polytricity.itch.io/adam-amiga-developmental-machine"          // the ADAM Pro page on itch.io ("" hides the 'Get ADAM Pro' button)

/// True when Pro features may be used
function pro_on()
{
    return ADAM_PRO == 1;
}

/// For a Pro button or action: true if Pro is on, otherwise a friendly
/// message saying it is in ADAM Pro. _what names the feature.
function pro_gate(_what)
{
    if (pro_on()) { return true; }
    toast(_what + " is part of ADAM Pro - click LITE at the top to find out more", 1);
    return false;
}
