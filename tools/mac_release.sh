#!/bin/sh
# Builds the macOS release of ADAM: signed, notarised .app.zip and .dmg for Lite and Pro
# (modelled on Amiga Dev Machine's and C64 Engine's tools/mac_release.sh).
#
#   sh tools/mac_release.sh            both editions
#   sh tools/mac_release.sh lite       just one (lite | pro)
#
# Each edition is built from a copy of the project, so the repo is never touched: in the copy
# ADAM_PRO (scr_licence) is set to the edition, ADAM_DEV_TOOLS (scr_adf) to false, and the
# webhook secret is filled in from $WEBHOOK_FILE. Then Igor (VM, Mac), sign the dylibs and the
# app (Developer ID, hardened runtime, timestamp), notarise and staple the app, then a DMG with
# an Applications link (signed, notarised, stapled).
# The version is option_mac_version in options/mac/options_mac.yy; it must match ADAM_VERSION.
# Output: ~/gamemakerstudio2/GM_MAC/ADAM/RELEASE_<ver>/ADAM_<ver>_LITE|PRO_macOS.app.zip / .dmg
#
# Needs: GameMaker LTS 2026 signed in (its user folder has a licence), the Developer ID
# certificate in the keychain (unlocked), and notarytool credentials saved as a keychain profile:
#   xcrun notarytool store-credentials polytricity-notary --apple-id <id> --team-id 6N9SMK537V
# (never put the password on the command line). WEBHOOK_FILE is a copy of
# scripts/scr_webhook_secret/scr_webhook_secret.gml with the real URL; it lives outside the repo
# (the repo is public). Without it 'Submit your game' and crash reports send nothing.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RT="${GM_RUNTIME:-/Users/Shared/GameMakerStudio2-LTS2026/Cache/runtimes/runtime-2026.0.0.23}"
GMUSER="${GM_USER:-$(ls -d "$HOME/Library/Application Support/GameMakerStudio2-LTS2026"/*_* 2>/dev/null | grep -v unknownUser | head -1)}"
IDENTITY="${SIGN_ID:-Developer ID Application: Robert Ramsay (6N9SMK537V)}"
PROFILE="${NOTARY_PROFILE:-polytricity-notary}"
WEBHOOK_FILE="${WEBHOOK_FILE:-$HOME/.adam_private/scr_webhook_secret.gml}"
APPNAME="ADAM"

VER=$(sed -n -E 's/.*"option_mac_version":"([^"]+)".*/\1/p' "$ROOT/options/mac/options_mac.yy")
APPVER=$(sed -n -E 's/^#macro ADAM_VERSION "([^"]+)".*/\1/p' "$ROOT/scripts/scr_about/scr_about.gml")
OUT="${OUT_DIR:-$HOME/gamemakerstudio2/GM_MAC/ADAM/RELEASE_$VER}"

case "$1" in
    "") EDITIONS="lite pro" ;;
    lite|pro) EDITIONS="$1" ;;
    *) echo "usage: sh tools/mac_release.sh [lite|pro]"; exit 1 ;;
esac

fail() { echo "mac_release: $*" >&2; exit 1; }
step() { echo; echo "==== $*"; }

[ -x "$RT/bin/igor/osx/x64/Igor" ] || fail "no Igor in $RT (set GM_RUNTIME)"
[ -f "$GMUSER/licence.plist" ] || fail "no GameMaker licence in '$GMUSER' (sign in to GameMaker, or set GM_USER)"
security find-identity -v -p codesigning | grep -q "$IDENTITY" || fail "signing identity not in the keychain: $IDENTITY"
[ "$VER" = "$APPVER" ] || fail "option_mac_version $VER and ADAM_VERSION $APPVER disagree"
[ -f "$WEBHOOK_FILE" ] || fail "no webhook secret at $WEBHOOK_FILE (set WEBHOOK_FILE)"
grep -q '^#macro ADAM_WEBHOOK_URL "https://' "$WEBHOOK_FILE" || fail "$WEBHOOK_FILE has no webhook URL"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/adam_release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
echo "ADAM $VER for macOS: $EDITIONS -> $OUT"

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait > "$WORK/notary.log" 2>&1 || true
    cat "$WORK/notary.log"
    if ! grep -q "status: Accepted" "$WORK/notary.log"; then
        id=$(sed -n -E 's/^ *id: ([0-9a-f-]+).*/\1/p' "$WORK/notary.log" | head -1)
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$PROFILE"
        fail "notarisation of $(basename "$1") was not accepted"
    fi
}

for ed in $EDITIONS; do
    if [ "$ed" = pro ]; then ED=PRO; EDNAME=Pro; PRO=1; else ED=LITE; EDNAME=Lite; PRO=0; fi
    base="ADAM_${VER}_${ED}_macOS"
    w="$WORK/$ed"
    mkdir -p "$w/tmp" "$w/cache" "$w/out" "$w/gm"

    step "$EDNAME: build"
    cp -R "$ROOT" "$w/src"
    rm -rf "$w/src/.git"
    s="$w/src/scripts"
    sed -i '' -E "s/^#macro ADAM_PRO [01]/#macro ADAM_PRO $PRO/" "$s/scr_licence/scr_licence.gml"
    grep -q "^#macro ADAM_PRO $PRO" "$s/scr_licence/scr_licence.gml" || fail "could not set the edition"
    sed -i '' -E "s/^#macro ADAM_DEV_TOOLS true/#macro ADAM_DEV_TOOLS false/" "$s/scr_adf/scr_adf.gml"
    grep -q "^#macro ADAM_DEV_TOOLS false" "$s/scr_adf/scr_adf.gml" || fail "could not turn the dev tools off"
    cp "$WEBHOOK_FILE" "$s/scr_webhook_secret/scr_webhook_secret.gml"
    # App Oven puts the .app in <output dir>/GM_MAC/<project>; keep it in the work folder
    sed -i '' -E "s|\"option_mac_output_dir\":\"[^\"]*\"|\"option_mac_output_dir\":\"$w/gm\"|" "$w/src/options/mac/options_mac.yy"
    cd "$w"
    "$RT/bin/igor/osx/x64/Igor" -j=8 --project="$w/src/ADAM.yyp" --user="$GMUSER" \
        --runtimePath="$RT" --temp="$w/tmp" --cache="$w/cache" --of="$w/out" --tf="$base.zip" \
        --runtime=VM -- Mac PackageZip > "$OUT/${base}_build.log" 2>&1 || true
    built=$(find "$w/gm" -maxdepth 3 -name "$APPNAME.app" -type d | head -1)
    if ! grep -q "App Oven Result: 0" "$OUT/${base}_build.log" || [ -z "$built" ]; then
        tail -40 "$OUT/${base}_build.log"
        fail "the GameMaker build failed (log: $OUT/${base}_build.log)"
    fi
    cd "$ROOT"
    app="$w/$APPNAME $EDNAME.app"
    mv "$built" "$app"
    find "$app/Contents" -name 'libxprocess.dylib' | grep -q . || fail "libxprocess.dylib is missing from the app"
    [ -f "$app/Contents/Resources/engine/engine.bin" ] || fail "engine/engine.bin is missing from the app"

    step "$EDNAME: sign and notarise the app"
    find "$app/Contents" \( -name '*.dylib' -o -name '*.so' \) -type f | while read -r lib; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$lib"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$app"
    codesign --verify --deep --strict --verbose=2 "$app"
    ditto -c -k --keepParent "$app" "$w/upload.zip"
    notarize "$w/upload.zip"
    xcrun stapler staple "$app"
    rm -f "$OUT/$base.app.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$OUT/$base.app.zip"

    step "$EDNAME: DMG"
    mkdir -p "$w/dmg"
    ditto "$app" "$w/dmg/$(basename "$app")"
    ln -s /Applications "$w/dmg/Applications"
    rm -f "$OUT/$base.dmg"
    hdiutil create -volname "$APPNAME $EDNAME $VER" -srcfolder "$w/dmg" -ov -format UDZO "$OUT/$base.dmg"
    codesign --force --timestamp --sign "$IDENTITY" "$OUT/$base.dmg"
    notarize "$OUT/$base.dmg"
    xcrun stapler staple "$OUT/$base.dmg"

    step "$EDNAME: check"
    spctl -a -vv -t exec "$app"
    spctl -a -vv -t open --context context:primary-signature "$OUT/$base.dmg"
    xcrun stapler validate "$OUT/$base.dmg"
done

step "Done"
ls -l "$OUT"
