# ADAM on macOS (the `mac` branch)

The Mac version lives on the `mac` branch of this repo. `main` stays the
Windows version; `mac` is `main` plus the Mac-only setup below, so new
features reach the Mac with one merge.

## What the branch adds

- `extensions/libxprocess` - Samuel Venable's libxprocess (MIT, credited in
  `datafiles/LICENCES.txt`), macOS target only (universal: Intel and Apple
  silicon). It gives GML `ProcessExecute` / `ProcessExecuteAsync`.
- FS-UAE starts like it does on Windows (`scr_adf`: `launch_fsuae`,
  `launch_fsuae_now`, `fsuae_args`): any old FS-UAE is closed
  (`killall fs-uae`), then `open -n -a FS-UAE.app --args ...` boots the disk
  with the same settings. A bare `fs-uae` binary picked with Find is run
  directly.
- Space fires as well as right Ctrl (`--keyboard_key_space=action_joy_1_fire_button`),
  because many Mac keyboards have no right Ctrl.
- `execute_shell_simple_ext.dll` is copied to Windows only; its GML wrapper
  stays so the (guarded) Windows calls still compile.
- macOS Game Options: app id `com.polytricity.adam`, copyright, sandbox off
  (ADAM must start FS-UAE and let it read disks you saved anywhere), Retina on,
  and the app icon `options/mac/icons/1024.png` (made by `tools/make_art.ps1`).

## Build on the Mac

1. `git fetch` then `git checkout mac` (first time) or `git pull` (after).
2. Open `ADAM.yyp` in GameMaker on the Mac.
3. Game Options > macOS: set your **Team ID** and **Signing Identity**
   (Developer ID Application: ...), as for the C64 Dev Machine. Keep
   certificates and notarisation passwords in the keychain - never in the
   repo (it is public).
4. For a release: `#macro ADAM_DEV_TOOLS false` (scr_adf) and
   `#macro ADAM_PRO 0` (Lite) or `1` (Pro) (scr_licence) - don't commit those.
5. Build: macOS target, Create Executable, signed and notarised.

## Test checklist

1. FS-UAE 3.1.66 (fs-uae.net) in Applications; ADAM's Build page shows it as found.
2. Load Gem Hunter, press **F5**: FS-UAE opens and the game boots.
3. Press F5 again: the old FS-UAE window closes and a new one boots.
4. Keyboard joystick: cursor keys move, **Space** and right Ctrl (if the
   keyboard has one) fire. Try a gamepad with Joystick = Gamepad.
5. A Kickstart ROM set on the Build page is used (A600 and A1200).
6. New / Open / Save / Save as, PNG import, WAV import, .mod import/export.
7. Lite and Pro builds: the top bar says LITE / PRO.

If FS-UAE does not start, the command ADAM ran is the `open -n -a ...` line in
`launch_fsuae_now`; try it in Terminal to see why.

## Keeping it up to date

    git checkout mac
    git merge main
    git push

Conflicts are rare: the Mac changes touch `options/mac`, the two extensions,
the FS-UAE launch functions in `scr_adf` and `LICENCES.txt`.
