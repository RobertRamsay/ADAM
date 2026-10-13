# ADAM — Claude Code guide

ADAM ("Amiga Dev and Art Machine") is a no-code Amiga game maker written in
GameMaker (GML), by Bob / Polytricity Ltd. It is modelled on Bob's C64 No-Code
tool (github.com/RobertRamsay/C64_NOCODE) and is a separate product from the
older AMIGA_DEV_MACHINE_Git node editor.

Users paint a backdrop, draw sprites, place actors, write WHEN/DO rules, make
sounds and levels, then ADAM writes a **bootable .ADF** for a stock
**Amiga 500/600 (OCS/ECS, 1MB chip, FS-UAE model A600)** or **Amiga 1200
(AGA, 2MB chip)**, picked at launch.

## Golden rules (Bob's conventions — always follow)

- **Initialise every instance variable in `obj_app` Create** (arrays, structs, flags). Never rely on `variable_struct_exists` / `variable_instance_exists` checks. For data read from JSON, use `struct[$ "key"]` and `is_undefined` / `is_array` / `is_string`.
- **No ternary / shorthand if** (`a ? b : c`). Always full `if { } else { }`.
- **Never write hex as `$ff` at the start of an array literal** — `[$ff...]` parses as a struct accessor. Use `0xff` everywhere.
- **Never name a local `x` or `y`** (built-in instance variables). Use `_px`, `_iy`, etc.
- Brace style: Allman, 4-space indent, `_underscore` locals, as in the existing scripts.
- Bob reviews changes as diffs/patches. Keep changes focused, one feature per commit, with a clear message. If you hand him something to paste instead, use **FIND:** / **REPLACE with:** blocks.
- `#macro ADAM_DEV_TOOLS true` (scr_adf) enables the FS-UAE test-copy download. It must be `false` for public itch.io builds.

## How to build and check

- **Compile GameMaker from the command line** with Igor (GameMaker's build CLI) so compile errors can be read and fixed. Locate the installed runtime (usually under `%ProgramData%\GameMakerStudio2\Cache\runtimes\runtime-*\bin\igor\windows\x64\Igor.exe`) and run a Windows VM build of `ADAM.yyp`. Iterate until there are **zero errors**; also clear Feather errors where possible.
- **Engine:** `powershell -File tools\assemble_engine.ps1` (needs vasmm68k_mot.exe).
- **Engine test without GameMaker:** `python tools\reference\gen_examples.py` then `powershell -File tools\run_adf.ps1 -Adf tools\reference\out\gem_hunter.adf` (or `-Model A1200`).
- `gen_examples.py` is deterministic: running it must not change `datafiles/examples/*.adam` unless the examples were meant to change.
- Bob does the hands-on UI checks in the running app; describe exactly what to click to verify each change.

## Architecture

### Editor (GameMaker)
One object, `obj_app`, draws everything in **Draw GUI** with an immediate-mode UI
(`scr_ui_widgets`, `scr_ui_draw`, `scr_ui_help`). Every control registers a rect
(`ui_register`) for hover help and tutorials. Pages ("workspaces", `WS_*` in
`scr_ws_shell`): Home, Backdrop, Levels, Sprites, Animate, Tiles, UI, Actors, Logic, Sound, Music, Build.

| Script | Role |
|---|---|
| `scr_project` | Data model (`project_new`, `project_from_loaded` = loader + validator), per-page undo (`undo_keys`, `undo_mark`, `undo_mark_full`), settings ini. |
| `scr_machine` | Machine profiles (`machine_cur()`), launch picker, boing ball. |
| `scr_gfx` | Backdrop index surface + `sh_palette` shader (palette & copper-sky preview), sprite caches, font, PNG import (median cut). Painting writes `bd_buf` then uploads — never draws into the surface. |
| `scr_levels` | Levels page, terrain generator (`terrain_generate`, LCG — must match `gen_examples.py`), title/goal settings. |
| `scr_adf` | **Game data block + ADF writer**, FS-UAE launch/test-copy download. |
| `scr_sfx` | Synth + WAV sample import, crunch (rate/bits), preview (exact Paula output). |
| `scr_ws_*` | One script per page. `scr_ws_logic` also owns rule groups. |
| `scr_examples`, `scr_tutorial` | Example loader, tutorials. (There is no in-app intro; the YouTube intro is rendered by `tools/intro`.) |

Project data (`proj`) is plain JSON-able structs/arrays; `.adam` files are `json_stringify(proj)`.

### Runtime (68000)
`datafiles/engine/engine.s` is a **fixed, position-independent** engine
(`vasm -pic`). ADAM never generates code: it appends a **data block** right
after `engine.bin`; `boot.s` (bootblock) AllocMem's chip RAM, reads engine+data
with trackdisk (showing a copper loading bar) and jumps in. Registers held:
`a4` = data block, `a5` = V+128 (variables; per-actor state is a 64-byte record per actor,
`v_xx(a5,Dn)` with Dn = actor << ACTV_SHIFT, up to MAX_ACT = 32 actors), `a6` = $dff000.

**Data block header** (offsets from data start; longs are offsets from data start, 0 = absent):
`0 'ADAM' | 4 version | 6 flags (bit0 AGA) | 8 depth | 10 nact | 12 nrule | 14 lives | 16 show score | 18 show lives | 20 hud row | 22 hud colour | 24 msg colour | 26 player actor (-1) | 28 game block | 32 palette | 36 planes (original) | 40 actors | 44 rules | 48 sfx table | 52 game-over text | 56 win text | 60 sprite pair colours | 64 display planes | 68 copper sky (256 x $0RGB; AGA: + 256 words of low nibbles, written with LOCT) | 72 painted ground (320 words) | 76 work planes (backdrop + hills) | 80 music table | 84 second display (BOBs) | 88 BOB background | 92 tile world | 96 custom HUD` — header is 100 bytes, version 7. Music table (`M_*`, see docs/MUSIC_CONTRACT.md): nsongs word, 10 level-song bytes ($FF none), then { offset, length } of each ProTracker MOD.

- BOBs (ADAM Pro): actors with `A_BOB` set are drawn by the blitter into a double-buffered display (`bob_draw` / `bob_flip`), wiped from the background buffer each frame; their images are the sprite's size (16-64 wide in steps of 16, 16-64 high; `A_BSIZE` = BLTSIZE), a mask then depth planes, in the nearest backdrop colours. A sprite bigger than 16 x 24 is always a BOB. Lite puts 8 actors on the disk, Pro up to 32 (actors after the 8th sprite become BOBs).
- Animations (version 5): `A_ANIM` (actor record offset 48) points at a table of 4 x 72 bytes (`AN_*`): Idle, Walk, Jump, Fall - each { frames 1..8, rate, mode 0 loop / 1 once / 2 ping-pong, 0, 8 longs facing right, 8 longs facing left }. ADAM fills empty animations in from the others (`anim_plan` in scr_project = `anim_plan` in adf_reference.py), and writes the two-frame animation of older projects as a table too. `place_sprites` picks the animation (Jump / Fall only for roles 6-8 in the air) and the frame from `v_anim - v_astart`; the frame offset goes in `v_fofs` (bob_draw draws BOBs from it). `A_SPR2` is now only a hopper's crouch frame. With 8 directions (`anim_dirs`, `A_AMODE` bit 0) the table has 12 entries (4..11 = N NE E SE S SW W NW, picked from the move each frame via `dir_tab`, last one in `v_dir`); ADAM bakes turning round into those entries (`flip` in the plan, `DIR_CHAINS` / `anim_dir_chains`), and an empty Idle is written as mode 3 = stand facing the last direction. Fire animations (`A_AMODE` bit 1, 21 entries: 12 Fire, 13..20 Fire + N..NW) play while the player holds fire, picked from the joystick direction; the Animate page shows them on a 'With Fire' layer.
- Tile world (version 6, `H_TILES`, `scr_tiles` / Tiles page `WS_TILES`): one tile size per game (`proj.tile_size` 8 / 16 / 32 / 64, `tile_geometry()`), up to 512 tile types (`TILE_MAX`; ADAM Lite 96) - `T_*` header 44 bytes (size, shift, line, ncol, nrow, ring), `TP_*` records 8 bytes (byte flags: bit0 solid, bit1 dig, bit2 goal; byte sound; words hard, points, becomes), 4-letter names; map up to 1024 x 1024 tiles (Lite 256 x 256) and never over 32640 pixels (`WORLD_PX_MAX`, engine words), cells are bytes or - with more than 256 tile types (`T_FLAGS` bit 1) - words. The engine copies the map to BSS (cleared memory after the data; the bootblock allocates `loadsize + bsssize`, both poked into the last 8 bytes of boot.bin). The scrolling picture is a ring of `NROW x S x LINE` bytes per plane, kept twice (so the display never wraps): map pixel (x, y) lives at `(y x LINE + x / 8 + 2) mod RING` and RING bytes on (`draw_cell`, `cam_window`, `cop_scroll`: BPLCON1 fine scroll, DDFSTRT $30, AGA FMODE 0), under a copper HUD split at line 8 with modulo LINE - 42. Its size does not depend on the map. Actor coordinates are world pixels; actors collide with solid tiles (`box_solid`, `tile_hres` - steps up tiles up to 16 high - `tile_vres`, `tile_phys`). Dig and place (player only): fire + direction digs, fire alone places the carried tile, up jumps; the HUD shows the carried tile and count. Tile worlds use 7 actors, all hardware sprites (no BOBs): DDFSTRT $30 (fine scroll) steals sprite 7's DMA, so pair 3 holds one actor (`ACT_MAX_TILE`, allocator caps). The editor draws the map through a view cache (`tile_view_surface`) snapped to tiles; the atlas holds 32 tiles a row. Example: Dig Deep (`ex_dig_deep.py`, 16 x 16, Pro extra). Multi-disk games (Bob, Oct 2026) are next: an 'insert disk 2' screen, levels / maps / music spread over disks.
- Actor record = 52 bytes (`A_*` equates; `A_XMAX` / `A_YMAX` = 320 - width / 256 - height are its screen limits), rule record = 16 bytes (`R_*`), sfx entry = 8 bytes (offset, length in words, Paula period), game block = `G_*` (levels, terrain colours, goal, title text, 320 heights per level).
- **Any layout change must be made in three places: `engine.s`, `scr_adf.gml`, `tools/reference/adf_reference.py`.**
- Roles: 0 player, 1 bouncer, 2 patrol L-R, 3 patrol U-D, 4 chaser, 5 still, 6 platform player, 7 hopper, 8 faller.
- WHEN: 0 touch, 1 fire, 2 every N s, 3 score reaches, 4 lives out, 5 game starts, 6 actor jumps, 7 level starts, 8 fire held with the stick still for N tenths of a second (once per hold), 9 every N s while actor a is on the screen (`on_screen`; out of view it fires a second after coming back), 10 the player's weapon strikes actor b (`v_struck`), 11 thrown actor a hits actor b (b = a: anything; `v_hits`), 12 the player picks actor a up (`v_picked`).
- DO: 0 score, 1 lose life, 2 sound, 3 flash, 4 home, 5 random spot, 6 hide, 7 show, 8 background colour, 9 game over, 10 win, 11 faster, 12 slower, 13 add life, 14 move to actor, 15 show for a moment, 16 safe for a while, 17 count toward goal, 18 play music (value = song), 19 stop music, 20 place tile (tile world: value = tile, at the target actor's middle / feet / head, only where nothing solid is), 21 drop what the player carries.
- AND DO: a rule card has up to `RULE_DOS_MAX` (5) DO lines (`rule.more` = `do_new()` structs; `rule_has_act` checks them all). On the disk a rule is 16 bytes with `R_NAND` (word 14) = its AND DO lines, each 8 bytes after it (act, target, value, 0; `AND_SIZE`). `fire_action` runs the DO then each AND DO line (a3 pointed 8 bytes before the line so `do_action` reads it), so every DO on a card fires together even when an earlier one changes what the WHEN looks at (e.g. send home, then safe / sound). `rule_next` steps past a rule and its lines (run_rules, run_when_rules, strike_mask). Up to `RULES_DISK_MAX` = engine `RULES_MAX` = 128 rules (one latch each). `merge_rules` in gen_examples.py merges back-to-back same-WHEN rules of the examples into cards.
- Pick up and throw: actor setting `carry` (`A_CARRY`, the old A_ARATE word). `carry_tick` (before move_actors): fire newly pressed while touching a carriable actor picks it up (`v_carry`), fire again throws it (`v_thr` 1, `v_tvx` THROW_VX the way the player faces, vy -THROW_VY, `physics` does gravity, tile walls and landing); each press is used up (`v_fwait`, checked on the button itself). `carry_follow` (after move_actors) stands it on the player's head. A flying actor's first hit (`throw_hits`, `overlap_pair`, not the player) goes in `v_hits` and it is spent (v_thr 2, drops). Teleports (`stop_fall`) end flights and carrying. The weapon does not swing while carrying. Dig Deep: a Rock (bat colours) to throw at baddies.
- Custom HUD (version 7, ADAM Pro UI page `scr_ws_ui`, `WS_UI`; `H_UI`, `UI_*` / `F_*`): a panel strip of 1-6 text rows at the top or bottom (always the top in a tile world: `v_hudlines` = rows x 8 is the copper split), its picture = the backdrop strip with a 24 x 24 9-slice frame baked in (`ui_panel_pixels` = `ui_ref.panel_pixels`; blitted into the work planes after the hills, `ui_panel_blit`), a font (64 x 8 bytes; styles ADAM / Bold / Thin / Italic / Bold italic / Custom - `ui_font_bytes` = `ui_ref.font_bytes`; `v_font` is used for all text, so messages and titles match) and up to 16 fields of 32 bytes (type 0 text, 1 score, 2 lives, 3 goal, 4 tile carried, 5 level; column, row, colour, shadow colour or -1, digits, 20-byte label). `draw_char` draws the shadow one pixel down-right inside the cell (`v_shadow`) and clips at column 40. Frame presets (`ui_frame_rgb` = `ui_ref.frame_rgb`): Metal, Wood, Stone, Neon, Parchment, Window, in the nearest backdrop colours. Lite builds use the standard HUD (`lite_trim`). Dressed examples: Firefly Night (wood, italic), Dig Deep (stone, bold).
- Tile flag bit 3 = ladder: a platform player on it climbs with up / down (no gravity) and lines up with the tile column (`on_ladder`, `snap_col`; digging straight up / down lines up too).
- Tools (Tiles page, Tools tab, `proj.tools`, `TOOL_MAX` 6): `T_NTOOL` (header word 38) tools of 12 bytes (`TL_*`: act word 0 dig / 1 build with the tile carried / 2 put tile `TL_TILE` where the player stands via `ptile_core`, 3 weapon - `TL_TILE` = reach in pixels, flags byte bit 0 = Auto; 8-letter name) after the tile names. Space (`read_key` polls the CIA-A serial port each frame, handshake on `$bfee01` bit 6; `v_key` = $100 + raw code) opens `tool_menu` in the HUD row (`menu_draw` / `menu_clear`, game frozen); left / right pick, fire or space take it (`v_fwait` swallows that fire). Fire then uses `v_tool` (`tile_dig` / `tool_rec`); pickaxe with fire alone digs the way the player faces. No tools = the old fire behaviour. HUD field type 6 = tool name. Weapons (`weapon_tick`, `strike_test`, `strike_mask`): fire swings (`v_swing` SWING_TIME, `v_swcool` SWING_COOL, Fire anim entry 12 facing `v_face`, which holds during a swing); Auto swings at actors named by a WHEN 10 rule within reach (front first, then behind - the player turns). The reach box runs from the player's middle to its edge + reach, and from reach above its head to its feet. With tools, the other tools' fire-alone animation is Fire + the way it faces (entry 12 is the weapon's swing). Fire with no direction (anim entry 12) turns round with `v_face` like Idle (writers flip it when Flip is on).
- Synth filter (`filt` 1-15 two-pole low-pass, `fspeed` LFO in 0.25 Hz steps, `fdepth` up to +-3 octaves; output normalised to peak 0.9): `sfx_render` = `adf_reference.render_sfx`; a sound with a filter sweep may last 3 s (`sfx_max_seconds`), else 1.5 s. Dig Deep: filtered wind on sound 1, the bell on its post (actor 6, the miner's sprite pair, swinging Idle) chimes sounds 2 and 7 via WHEN 9 only while on screen, sword (Auto, reach 20) strikes baddies: +25, Thwack (sound 5), home; no hold-fire ladder rules.
- Rule groups (`scr_ws_logic`): `parent` makes groups nest (tree order = run order, `group_order`, `logic_sort_rules`); a group switched off switches off the groups inside it (`group_off_in`, also used by the disk writer). Groups start folded (`group_new`, `groups_fold_all` when a project or example is opened).

### Hardware limits ADAM respects
- 8 hardware sprites (16 x 24, 3 colours), 4 colour pairs; actors with matching colours are paired automatically (`actors_alloc_channels`).
- Backdrop 320 x 256: up to 16 colours on A500/600 (sprites use colours 17-31), up to 128 on A1200 (sprites moved to 240-255 via BPLCON4).
- 4 Paula channels, driven by ptplayer (`datafiles/engine/ptplayer`, public domain) from CIA-B level-6 interrupts; the engine runs in supervisor mode. With no music, sound n plays on channel n & 3; while a song plays ptplayer picks the least disruptive channel.

### vasm pitfalls seen so far
- Local labels (`.x`) are scoped to the last global label — don't reuse names in one routine.
- `-no-opt`: short branches out of range are errors — widen to `bra`/`beq` (word). A `bra.s` to the very next instruction is invalid.
- `touch` is a mnemonic; avoid as a label.

## Phase plan

Work phases in order; within a phase, the listed tracks can run as parallel sub-agents.
Each task ends with: clean compile, engine reassembled if touched, reference builder updated if
the layout changed, examples regenerated if needed, and a short "how to verify" note for Bob.

### Phase 0 — Compile and stabilise (do first, single agent)
- Compile `ADAM.yyp` with Igor; fix every compile error and obvious runtime error. Most GML so far was written without a compiler.
- Smoke-test each page in code paths you can reach; list anything that needs Bob's eyes.

### Phase 1 — Launch must-fixes
- **Track A (engine/boot):** bootblock shows a red error screen when AllocMem fails; add a 512KB-chip A500 budget check (Build page warns / blocks; machine profile note). Test on Kickstart 1.3 and 3.1 if Bob provides ROMs.
- **Track B (macOS):** FS-UAE launch on Mac (`open -a "FS-UAE" --args ...` or the app binary), Mac test-copy download (dmg/tar.xz), guard Windows-only `execute_shell_simple`.
- **Track C (project files):** store `pixels` (RLE + base64) and sample data compactly in `.adam` files and undo snapshots; keep loading older files. Measure save/undo time before and after.
- **Track D (release):** release checklist — `ADAM_DEV_TOOLS false`, licences screen (Poppins OFL, font8x8 public domain, FS-UAE GPL mention), version number, itch build.

### Phase 2 — Music maker (horizontal, Dance eJay / FL Studio style)
- **Track A (engine):** integrate Frank Wille's **ptplayer** (verify its licence first) to play ProTracker MODs with sound effects mixed on the same channels. Needs CIA-B interrupts: enter supervisor before taking over the system, set up vectors (respect VBR on 68020). New data: `H_MUSIC` offset to an embedded MOD. New DO actions: play music, stop music; per-level music choice.
- **Track B (editor):** Music page — 4 lanes (Paula channels) x bars timeline; left loop library (Drums / Bass / Chords / Lead / FX) with preview; drag or paint 1-bar loops onto lanes; double-click opens a 16-step grid / piano roll; instruments from built-in chip synth presets (rendered like the Sound page) and the user's WAV samples; BPM, swing, loop point; whole-song preview by mixing in GML.
- **Track C (export/import):** write the arrangement as a standard 4-channel ProTracker MOD (so the engine plays it with ptplayer); import `.mod` files made in ProTracker / OpenMPT.

### Product: ADAM Lite (free) and ADAM Pro (paid)
- **Lite** makes and shares a complete small game: backdrop, copper sky, sprites, actors, rules, levels, Sound page (synth + WAV import), Music page (loop library, step editor, .mod import/export), lessons, bootable ADF. Never cripple Lite; Pro adds power and polish.
- **Lite / Pro limits (Bob, 12 Oct 2026):** same features, Pro raises the ceilings - `lim_*()` / `LITE_*` in `scr_licence`: frames per animation 4 / 8, With Fire joystick - / yes (`lim_fire`, `anims_fire_used` is false in Lite), sprites and BOBs 32 x 32 / 64 x 64, actors on disk 12 (8 sprites, the rest BOBs) / 32, sprite bank 64 / 128, tile types 96 / 512, maps 256 x 256 / 1024 x 1024 tiles (tile sizes 8-64 in both; memory is the real limit). A Pro project opened in Lite keeps its data; the editor marks what is over the limit ("Pro") and `adam_data_block` writes a copy trimmed by `lite_trim` (proj is swapped for the copy while writing) with Build-page warnings. The free examples fit the Lite limits.
- **Decision (Bob, Oct 2026): Lite and Pro have the same features; Pro adds extra example games and lessons.** `pro_on()` / `feature_gate()` are now always true (the switch for a feature), `pro_edition()` / `pro_gate()` gate the Pro extras (`pro : true` examples and lessons). The text below about Pro-only features is history.
- **Pro** = the Phase 4 features below. Two builds from one project: `#macro ADAM_PRO` in `scr_licence` (0 = Lite, 1 = Pro); Bob builds `_LITE` and `_PRO` zips himself (docs/RELEASE.md). No licence keys. Optional "Made with ADAM" card in Lite games that Pro removes.
- Gate a Pro feature in one place: `pro_on()` (or `pro_gate("Feature")` for a button) in `scr_licence`, so the UI shows it locked with a short "Pro" note rather than hiding it.

### Phase 3 — Should-fix features (Lite)
- Sprite editor animated preview and PNG import; more genre examples.

### Phase 4 — ADAM Pro
- **Graphics:** dither gradients and drawing with dither patterns (done: Gradient tool and Pattern brushes, Bayer 8 x 8); BOBs (blitter objects) beyond the 8 hardware sprites (done, with the Firefly Night example and Lesson 5); scrolling playfields (horizontal / vertical) with a tile level editor; parallax / dual playfield; colour cycling, raster bars and per-level copper effects (build on `copper_blend_lines`); IFF/ILBM import and export (Deluxe Paint / PPaint); attached sprites (15 colours), more animation frames, flipping.
- **Gameplay:** bullets / "fire shoots" for player and enemies; variables and counters in rules; rooms / multiple screens per level; two players; pause and second fire button / CD32 pad; high-score table saved to disk.
- **Sound and music:** instrument editor (synth envelopes, sample loop points); tracker effects in the step editor (slides, vibrato, arpeggio, volume); sample compression for more sound per disk.
- **Output:** play-in-browser export for itch.io (web Amiga emulator); hard-drive install (WHDLoad slave) and CD32 image; custom boot / loading screens and an intro maker; proper DOS disk so the ADF shows a named disk with an icon on Workbench.
- **Workflow:** genre templates and asset packs; play the game inside the editor without FS-UAE; 68000 source export for learning.
- Each Pro feature ships with a Pro example game and a Pro lesson (`pro : true` in `global.EXAMPLES` / `les_defs`; Lite shows them with a Pro label).
- **The Animate page is in ADAM Lite and Pro** (Bob's call, 12 Oct 2026): `anim_can_edit()` is always true. The sprite bank is 64 in Lite and 128 in Pro (`spr_bank_size()` = `lim_bank()`).
- **A1200 example versions:** every example also ships as `<name>_a1200.adam` (`file_aga` in `global.EXAMPLES`, picked by `example_file()` when the A1200 is selected). `gen_examples.py` draws each picture twice: in AGA mode `dmix` turns every dithered blend between two backdrop colours into a real in-between colour (16..127, `AGA` state), so gradients are smooth; blends with colour 0 (copper sky) stay dithered. Depth 7, 24-bit palette and sky.
- **Animate page joysticks:** each joystick is a 3 x 3 grid of square slots playing their animations live (`anim_slot_preview`); the right panel has Sprites / Animations tabs - the animation library (`anim_library_draw`) lists every animation of every actor, and dragging one (or a slot) onto a slot, or Walk / In air / Falling, copies it (`anim_drag_arm`, `anim_drop_zone`, `anim_drag_update`, `anim_drop_into`).
- **Animation editor - done:** Animate page (`scr_ws_animate`, `WS_ANIMATE`), engine data version 5, with an 8-direction movement layout (compass) and a Test mode (arrow keys / WASD / gamepad). The examples use 3-4 frames per animation (`animate()` in gen_examples.py makes the extra frames); Star Catcher's rocket uses 8 directions. Still to do from Bob's spec: Hit / Die animations with a DO "play animation" action and a WHEN "animation ends" rule, onion skin in the sprite editor, a Pro example game and a Pro lesson. Original spec: Today an actor has two frames (`sprite`, `anim_sprite`, `anim_rate`, `anim_moving`; engine `A_SPR2`). Replace with:
  - New **Animate** page (or a tab on Sprites): named animations per actor - Idle, Walk, Jump, Fall, Hit, Die - each a strip of up to 8 frames picked from the sprite bank (128 slots in Pro, `spr_bank_size()`), a rate in 50ths of a second (per animation; per-frame delay optional), and a mode: Loop / Once / Ping-pong. Flip H for facing left (reuse right-facing frames). Live preview at real speed and onion skin in the sprite editor.
  - Actor state picks the animation automatically: still -> Idle, moving -> Walk, platform player in the air -> Jump / Fall. New rule bits: DO "play animation" (value = animation), WHEN "animation ends".
  - Data block: actor record gets an offset to an animation table instead of `A_SPR2` (bump version to 5, keep Lite's two-frame actors working by writing them as a 2-frame Loop). Frame images are written once per used sprite slot and shared. Change `engine.s`, `scr_adf.gml` and `adf_reference.py` together; old `.adam` files load with `anim_sprite` turned into a 2-frame Walk/Idle.
  - Lite keeps the current two-frame animation; the page shows the rest locked with `pro_gate("Animations")`. Ship a Pro example and a Pro lesson.
- Suggested order: `pro_on()` (done), BOBs (done, 16 x 16 up to 64 x 64 - size picker on the Sprites page), then scrolling (most other Pro features build on them), then the rest.
