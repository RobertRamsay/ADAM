# ADAM release checklist (Windows, itch.io)

Work down the list in order. Do the release on a branch or a clean checkout of
`main`; the only source changes a release makes are the version number and
`ADAM_DEV_TOOLS`.

## 1. Version

The version lives in one place: `#macro ADAM_VERSION` in
`scripts/scr_about/scr_about.gml`. It shows in the window title
("ADAM Lite 1.0.0 - ..." or "ADAM Pro 1.0.0 - ...") and on Home > About ADAM & licences.

GameMaker's exe metadata cannot read a macro, so when the version changes also
set, in `options/windows/options_windows.yy` (IDE: Game Options > Windows):

- `option_windows_display_name` - e.g. `ADAM_V1.0.0`
- `option_windows_version` - e.g. `1.0.0.0`

Commit: `Version x.y.z`.

## 2. Turn the dev tools off (release build only)

In `scripts/scr_adf/scr_adf.gml` set

    #macro ADAM_DEV_TOOLS false

This removes the "Get test copy" FS-UAE download from the Build page; users
point ADAM at their own FS-UAE. Do **not** commit this to `main` - day-to-day
development runs with it `true`. Keep it on the release branch or revert it
after the build.

## 2b. Lite and Pro: two builds

ADAM Lite (free) and ADAM Pro (paid) are two zips from the same project. The
switch is `#macro ADAM_PRO` in `scripts/scr_licence/scr_licence.gml`:

    #macro ADAM_PRO 0    // ADAM Lite
    #macro ADAM_PRO 1    // ADAM Pro

Do steps 3-6 once with `0` (zip `ADAM_1.0.0_LITE.zip`) and once with `1`
(zip `ADAM_1.0.0_PRO.zip`). The window title and the LITE/PRO chip in the top
bar show which one you built. Upload Lite to the free itch.io page and Pro to
the paid one.

## 3. Check

    powershell -File tools\release_check.ps1

It must end with "Ready to release". It checks `ADAM_DEV_TOOLS` is false, that
the version in `scr_about`, the display name and the exe version agree, and
that the licence files exist and are registered as Included Files.

If the engine changed since the last release: `powershell -File
tools\assemble_engine.ps1`, then `python tools\reference\gen_examples.py` and
make sure `datafiles/examples/*.adam` only changed if they were meant to.

## 4. Build the Windows zip

Either the IDE: target Windows, VM, **Create Executable > Package as Zip**, or
Igor from the command line (scratch folder outside the repo; keep `--temp`
and `--of` apart from where the log is written):

    $rt="C:\ProgramData\GameMakerStudio2-LTS2026\Cache\runtimes\runtime-2026.0.0.23"
    & "$rt\bin\igor\windows\x64\Igor.exe" -j=8 --project="D:\POLYTRICITY\ADAM\ADAM.yyp" `
      --user="C:\Users\Robert\AppData\Roaming\GameMakerStudio2-LTS2026\me_1710" `
      --runtimePath="$rt" --temp="$env:TEMP\adam_rel\tmp" --cache="$env:TEMP\adam_rel\cache" `
      --of="$env:TEMP\adam_rel\out" --tf="ADAM_1.0.0_LITE.zip" --runtime=VM -- Windows PackageZip

(`_PRO.zip` for the Pro build.) Zero compile errors. Then check the zip:

    powershell -File tools\release_check.ps1 -Zip <path>\ADAM_1.0.0_LITE.zip

## 5. What goes in the zip

GameMaker copies every Included File next to `ADAM.exe`. The zip must contain:

| File | Why |
|---|---|
| `ADAM.exe`, `data.win`, `options.ini` | the app |
| `execute_shell_simple_ext_x64.dll` | starts FS-UAE |
| `LICENCES.txt` | ADAM copyright + third-party notices (also shown in the app) |
| `fonts/Poppins-Regular.ttf`, `-Medium.ttf`, `-Bold.ttf` | interface font |
| `fonts/OFL.txt`, `fonts/Poppins-OFL.txt` | **required** by the SIL OFL: the copyright notice and licence must travel with the fonts |
| `engine/engine.bin`, `engine/boot.bin` | the Amiga engine and bootblock |
| `engine/engine.s`, `engine/boot.s`, `engine/font.inc` | engine source (included today; drop them from Included Files if they should not ship) |
| `examples/*.adam` | the four example games |

Nothing from `tools/`, no FS-UAE, no Kickstart ROMs, no `.patch` files.

## 6. Smoke test (on the zipped build, unzipped to a fresh folder)

Use a clean save folder (rename `%LOCALAPPDATA%\ADAM` first) so it behaves like a
first run.

1. Launch: the machine picker appears; pick **Amiga 500/600**. Window title reads "ADAM Lite 1.0.0 - ..." (or Pro).
2. **Home**: guided tour starts and can be closed; Example games > Gem Hunter loads; New / Open / Save / Save as work; **About ADAM & licences** opens, scrolls to the end of the OFL text, closes with Close and with Esc.
3. **Backdrop**: paint, fill, text, import a PNG, undo/redo.
4. **Levels**: change the seed, shape a hill, set title and goal.
5. **Sprites**: draw, copy/paste, change colours.
6. **Actors**: add one of each role, drag them, check the colour pair warning.
7. **Logic**: add a WHEN/DO rule and a group; undo.
8. **Sound**: make a synth sound and import a WAV; preview both.
9. **Build**: with `ADAM_DEV_TOOLS false` there is no "Get test copy" button; use **Find** to point at an installed FS-UAE. Build an ADF - no warnings beyond expected ones.
10. **Boot as A600**: Build and play - the loading bar shows, the game runs, joystick in port 2 moves the player, score/lives show, game over and fire to restart work.
11. Change machine to **Amiga 1200** (top bar), build and play again - boots as A1200 (AGA); a 128-colour backdrop shows correctly.
12. Load each example game and build it for both machines.
13. Quit and relaunch: the last session is restored, window size/place remembered.

## 7. Publish on itch.io

- **butler** (recommended, keeps patch downloads small):

      butler push ADAM_1.0.0_LITE.zip <itch-user>/<lite-game>:windows --userversion 1.0.0
      butler push ADAM_1.0.0_PRO.zip <itch-user>/<pro-game>:windows --userversion 1.0.0

- or the web: Edit game > Uploads > Upload files, tick **Windows**, and
  delete/hide the old upload.

Update the itch page: version and changelog, minimum spec, "needs FS-UAE
(free, fs-uae.net) to play the games", and a line crediting Poppins (SIL OFL)
and font8x8 (public domain).

## 8. After the release

- Tag the commit: `git tag v1.0.0` and push the tag.
- Set `ADAM_DEV_TOOLS` back to `true` on the development branch.
