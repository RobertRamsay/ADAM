/// ADAM - Lite / Pro edition
///
/// ADAM Lite is free; ADAM Pro is a separate paid download on itch.io. Both
/// come from this one project: set ADAM_PRO below and build each one
/// (ADAM_..._LITE and ADAM_..._PRO, see docs/RELEASE.md).
/// Both editions have the same features (Bob, Oct 2026); ADAM Pro adds extra
/// example games and lessons. pro_edition() / pro_gate() decide those;
/// pro_on() and feature_gate() are the old feature switches, now always on -
/// the one place to make a feature Pro-only again.

#macro ADAM_PRO 1               // 0 = build ADAM Lite, 1 = build ADAM Pro
#macro ADAM_PRO_URL "https://polytricity.itch.io/adam-amiga-developmental-machine"          // the ADAM Pro page on itch.io ("" hides the 'Get ADAM Pro' button)

/// True when this is the ADAM Pro build (the extra example games and lessons)
function pro_edition()
{
    return ADAM_PRO == 1;
}

/// True when the editing features may be used: every edition
function pro_on()
{
    return true;
}

/// For a feature button: always allowed (see the note at the top)
function feature_gate(_what)
{
    return true;
}

/// For Pro extras (example games, lessons): true in ADAM Pro, otherwise a
/// friendly message saying it comes with ADAM Pro. _what names it.
function pro_gate(_what)
{
    if (pro_edition()) { return true; }
    toast(_what + " comes with ADAM Pro - click LITE at the top to find out more", 1);
    return false;
}
