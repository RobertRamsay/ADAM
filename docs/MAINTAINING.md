# Looking after ADAM on your own

A guide for finding your way round ADAM's source when something goes wrong: where each
part lives, the tools that show what is happening, and where to look for the usual
problems. CLAUDE.md has the full detail of the data layout; this is the map.

## 1. How a game gets from the editor to the Amiga

1. **The editor** (GameMaker, `obj_app`) keeps everything in one struct, `proj`.
   Each page (`scr_ws_*`) edits part of it. Saving writes `json_stringify(proj)` with the
   big arrays packed (`project_to_json`, `scr_project`); loading runs the file back through
   `project_from_loaded`, which fills in missing fields and clamps bad values (the
   `*_fix` functions), so old files keep loading.
2. **Build** (`build_adf`, `scr_adf`) asks `adam_data_block` for the game's data: a block
   of bytes whose layout the engine knows (the `H_*` header, then actors `A_*`, rules `R_*`,
   tiles `T_*`, music `M_*`, disk 2 `D2_*` ...). ADAM never writes 68000 code.
3. **The disk**: `[bootblock][loading screen block (Pro)][engine.bin][data]`, plus
   `<name>_disk2.adf` when level music or maps go on a second disk.
4. **On the Amiga**: `boot.s` allocates chip RAM, loads the engine and data with
   trackdisk, and jumps in. `engine.s` takes over the machine and runs the game from the
   data (`game_restart` -> `level_card` -> `level_start` -> `mainloop` -> `frame` every
   50th of a second).

**The one rule that matters most:** a change to the data layout must be made in three
places - `datafiles/engine/engine.s`, `scripts/scr_adf/scr_adf.gml` and
`tools/reference/adf_reference.py` - and the version word bumped (`poke16(_b, 4, ...)` in
scr_adf, the same number in adf_reference). If the editor and the engine disagree about a
single byte the game crashes or behaves strangely, usually with no message.

## 2. Where things live

| You want to change... | Look in |
|---|---|
| What a page shows / its controls | `scripts/scr_ws_<page>/` (`ws_<page>_draw`) |
| Buttons, toggles, dropdowns, scrolling panels | `scr_ui_widgets`, `scr_ui_draw` (immediate-mode UI: each control registers its rectangle and id every frame) |
| Hover help text | the last string argument of each `ui_*` call (`"Title|Body"`) |
| Tutorials (F1) and lessons | `scr_tutorial` (`tut_step(page, control id, title, text)`), `scr_lessons` |
| Project fields, loading, saving, undo | `scr_project` (`project_new`, `project_from_loaded`, `undo_keys`) |
| What goes on the disk | `scr_adf` (`adam_data_block_raw`) |
| Lite / Pro limits | `scr_licence` (`lim_*`, `lite_trim`) |
| Sounds, the synth, samples | `scr_sfx`, `scr_patch`, `scr_ws_sound` |
| Music page, MOD export / import | `scr_music`, `scr_ws_music`, `scr_mod`, `docs/MUSIC_CONTRACT.md` |
| Tile worlds and shoot 'em up maps | `scr_tiles` |
| Loading screen | `scr_loadscr`, `datafiles/engine/loadscr.s` |
| How the game plays on the Amiga | `datafiles/engine/engine.s` (the map of the file is at its top) |
| The example games | `tools/reference/gen_examples.py` and `ex_*.py` (they write `datafiles/examples/*.adam`) |
| What's new text, version | `scr_whatsnew`, `scr_about` (`ADAM_VERSION`), `docs/RELEASE.md` |

## 3. Tools that show you what is happening

- **Compile without the IDE** (shows every error with its line): Igor -
  `C:\ProgramData\GameMakerStudio2-LTS2026\Cache\runtimes\runtime-2026.0.0.23\bin\igor\windows\x64\Igor.exe --project=D:\POLYTRICITY\ADAM\ADAM.yyp --user=%APPDATA%\GameMakerStudio2-LTS2026\me_1710 --runtime=VM --of=<a temp folder> --tf=ADAM.zip -- Windows PackageZip`.
  Errors come after "Compile Scripts...". Afterwards delete the `ADAM.zip` it drops in
  the repo and `git checkout -- cache` (the cache folder is tracked).
- **Assemble the engine:** `powershell -File tools\assemble_engine.ps1 -Vasm <path to vasmm68k_mot.exe>`.
  vasm prints the line of any error. Common ones: a short branch (`beq.s`) out of range -
  make it `beq`; a local label (`.x`) used in two routines.
- **Build a disk without the UI:** `ADAM.exe -adam_build in.adam out.adf` (dev builds;
  `ADAM_DEV_TOOLS true`). The result and any warnings go to `out.adf.log`.
- **Screenshots of every page:** `ADAM.exe -adam_shots in.adam outdir -adam_shots_w 1280 -adam_shots_h 720`
  (add `-adam_shots_tut` to show a tutorial step on each). Good for checking a layout
  change at a small window size.
- **Play a disk in FS-UAE:** `powershell -File tools\run_adf.ps1 -Adf game.adf [-Model A1200]`.
- **God mode** (Build page): Build and play makes a test copy where lives never run out
  and F8 skips a level; each level's **Test** button (Levels page) starts on that level.
  Use these to reach a problem on level 7 quickly.
- **The examples as a test suite:** `python tools\reference\gen_examples.py` rebuilds
  every example with the reference builder (`tools/reference/out/*.adf`). It must not
  change `datafiles/examples/*.adam` unless you changed an example - `git status` tells you.
- **Two writers, one layout:** for a project built by both `-adam_build` and
  `gen_examples.to_builder` + `adf_reference.build`, the data blocks should match byte
  for byte in the parts you changed. Comparing them section by section (the `H_*`
  offsets in the first 116 bytes) shows where they disagree.
- **Comments-only check:** `python tools\check_comments_only.py` proves a change since
  the last commit only touched comments (it strips them and compares the code).
- **Debug output:** in a dev build, ADAM prints its self-tests at start-up, and timings
  such as `ADAM undo mark (...): N ms` to GameMaker's output window.
- **Seeing a value inside the engine:** the quickest way is to copy a value into
  `v_score(a5)` and call `draw_hud` - the number shows in the score. For timing, read
  the raster line (`$dff006`) before and after a routine and put the difference there.

## 4. Where to look when...

| Symptom | Likely cause / where to look |
|---|---|
| Igor reports an error | The line it names. GML traps: `[$ff...]` at the start of an array literal (use `0xff`), a local called `x` or `y`, a ternary (Bob's rule: always `if / else`). |
| The game shows a red screen at boot | The bootblock could not get the chip RAM (`boot.s`). The Build page's memory bar and its 512KB-A500 warning say how much the game needs. |
| The game shows a yellow screen at boot | The bootblock could not read part of the disk after three tries (`boot.s` `.rderr`): a damaged floppy, or a bad write to it. |
| Black screen, garbage or a crash after loading | The editor and the engine disagree about the data layout: compare the version word and the structure you changed in all three places (section 1). |
| An actor shows the wrong picture or animation | `anim_plan` exists twice (scr_project and adf_reference) and must agree; the engine picks the entry in `place_sprites`. |
| An actor has the wrong colours | Hardware sprites share colours in pairs: `actors_alloc_channels` (scr_ws_actors) pairs actors with matching colours; the Build checklist lists actors that borrow colours. BOBs use the nearest backdrop colours (`pal_nearest`). |
| A rule never fires (or fires once only) | Each rule has one latch (`run_rules`, `clear_latches`): touch rules fire once per touch. Check the rule's group is switched on (`group_off_in`) and any IF lines (`if_check`). |
| Health or the time limit does not show | The standard HUD has room for TIME / HEALTH only without a goal counter or digging (`draw_hud`); otherwise add Health / Time left fields on a custom HUD (`ui_hud` types 8 / 9). Both are in the logic block (`H_LOGIC`), written only when set. |
| An edge / scenery / counter rule never fires | WHEN 19 / 20 check the actor and its copies only while shown and on this level (`copy_find`, `edge_test`, `scen_test`); WHEN 21 needs 'Add one to the counter' (it resets each level). |
| A rule fires but its AND DO lines don't | `fire_action` runs the DO, then each AND DO line (`R_NAND`); an IF line that says no stops the lot. |
| No sound | Only sounds a rule or a dug tile plays go on the disk (`sfx_used_on_disk`); ADAM Lite plays the first 8. A song that could not become a MOD is a Build warning. |
| 'PLEASE INSERT DISK 2' never goes away | Disk 2 does not match the game disk (its id, `D2_ID`, comes from the songs and maps on it). Rebuild and use both new disks together; FS-UAE gets disk 2 in DF1. |
| A level plays on the wrong tile map | `level_maps` (Tiles page, Map for), written as a table when `T_FLAGS` bit 2 is set; the engine picks the entry in `tiles_start` / `lmap_entry`, a disk 2 map is read by `map_fetch`. |
| The player falls through a moving platform | The platform needs 'Can be stood on'; its top is the top row of its drawn pixels (`plat_stand`); a faller more than `PLAT_GRAB` pixels below the top passes through. |
| A patroller goes too far or not far enough | `patrol` x 8 pixels from where it starts, the way it starts moving (`pat_lim` in the engine, `act_patrol_range` draws the same on the Actors page). |
| A control on a page does nothing when clicked | Two controls overlapping: the last one registered wins `ui_hot`, and a click is used up by `ui_take_click`. Inside a scrolling panel, the control must be drawn between `ui_scroll_begin` and `ui_scroll_end`. |
| A tutorial step points at nothing | Its control id is wrong or the control is not on screen in that state (`tut_show_step` opens the right tab for most steps). |
| Undo is slow | Each page's undo saves the fields in `undo_keys`; big tile maps (several levels' own maps) make the Tiles page's snapshots bigger. Dev builds print the time of each. |
| A Pro project behaves differently in Lite | `lite_trim` makes a cut-down copy for the disk; the Build page lists what it cut. |
| An example changed when you did not mean it to | `gen_examples.py` is meant to be repeatable: a change in a shared helper (art, shading, `to_builder`) changes every example that uses it. |

## 5. Before you commit

1. Igor compiles with no errors.
2. If you touched `engine.s`: it assembles, and the examples still play.
3. If you touched the layout: all three places, the version word, and an example played
   in FS-UAE on the A600 and the A1200.
4. `gen_examples.py` leaves the examples unchanged (unless you meant to change one).
5. One feature per commit, with a message that says what changed and how you tested it.
