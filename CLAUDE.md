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
`scr_ws_shell`): Home, Backdrop, Levels, Sprites, Actors, Logic, Sound, Build.

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
`0 'ADAM' | 4 version | 6 flags (bit0 AGA) | 8 depth | 10 nact | 12 nrule | 14 lives | 16 show score | 18 show lives | 20 hud row | 22 hud colour | 24 msg colour | 26 player actor (-1) | 28 game block | 32 palette | 36 planes (original) | 40 actors | 44 rules | 48 sfx table | 52 game-over text | 56 win text | 60 sprite pair colours | 64 display planes | 68 copper sky (256 x $0RGB; AGA: + 256 words of low nibbles, written with LOCT) | 72 painted ground (320 words) | 76 work planes (backdrop + hills) | 80 music table | 84 second display (BOBs) | 88 BOB background` — header is 92 bytes, version 5. Music table (`M_*`, see docs/MUSIC_CONTRACT.md): nsongs word, 10 level-song bytes ($FF none), then { offset, length } of each ProTracker MOD.

- BOBs (ADAM Pro): actors with `A_BOB` set are drawn by the blitter into a double-buffered display (`bob_draw` / `bob_flip`), wiped from the background buffer each frame; their images are the sprite's size (16-64 wide in steps of 16, 16-64 high; `A_BSIZE` = BLTSIZE), a mask then depth planes, in the nearest backdrop colours. A sprite bigger than 16 x 24 is always a BOB. Lite puts 8 actors on the disk, Pro up to 32 (actors after the 8th sprite become BOBs).
- Animations (version 5): `A_ANIM` (actor record offset 48) points at a table of 4 x 72 bytes (`AN_*`): Idle, Walk, Jump, Fall - each { frames 1..8, rate, mode 0 loop / 1 once / 2 ping-pong, 0, 8 longs facing right, 8 longs facing left }. ADAM fills empty animations in from the others (`anim_plan` in scr_project = `anim_plan` in adf_reference.py), and writes the two-frame animation of older projects as a table too. `place_sprites` picks the animation (Jump / Fall only for roles 6-8 in the air) and the frame from `v_anim - v_astart`; the frame offset goes in `v_fofs` (bob_draw draws BOBs from it). `A_SPR2` is now only a hopper's crouch frame.
- Actor record = 52 bytes (`A_*` equates; `A_XMAX` / `A_YMAX` = 320 - width / 256 - height are its screen limits), rule record = 16 bytes (`R_*`), sfx entry = 8 bytes (offset, length in words, Paula period), game block = `G_*` (levels, terrain colours, goal, title text, 320 heights per level).
- **Any layout change must be made in three places: `engine.s`, `scr_adf.gml`, `tools/reference/adf_reference.py`.**
- Roles: 0 player, 1 bouncer, 2 patrol L-R, 3 patrol U-D, 4 chaser, 5 still, 6 platform player, 7 hopper, 8 faller.
- WHEN: 0 touch, 1 fire, 2 every N s, 3 score reaches, 4 lives out, 5 game starts, 6 actor jumps, 7 level starts.
- DO: 0 score, 1 lose life, 2 sound, 3 flash, 4 home, 5 random spot, 6 hide, 7 show, 8 background colour, 9 game over, 10 win, 11 faster, 12 slower, 13 add life, 14 move to actor, 15 show for a moment, 16 safe for a while, 17 count toward goal, 18 play music (value = song), 19 stop music.

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
- **Sprite bank (128 slots) and the Animate page are in ADAM Lite and Pro** (Bob's call, 12 Oct 2026): `spr_bank_size()` is always 128 and `anim_can_edit()` is always true - gate them there again if that changes.
- **Animation editor - done:** Animate page (`scr_ws_animate`, `WS_ANIMATE`), engine data version 5. Still to do from Bob's spec: Hit / Die animations with a DO "play animation" action and a WHEN "animation ends" rule, onion skin in the sprite editor, a Pro example game and a Pro lesson. Original spec: Today an actor has two frames (`sprite`, `anim_sprite`, `anim_rate`, `anim_moving`; engine `A_SPR2`). Replace with:
  - New **Animate** page (or a tab on Sprites): named animations per actor - Idle, Walk, Jump, Fall, Hit, Die - each a strip of up to 8 frames picked from the sprite bank (128 slots in Pro, `spr_bank_size()`), a rate in 50ths of a second (per animation; per-frame delay optional), and a mode: Loop / Once / Ping-pong. Flip H for facing left (reuse right-facing frames). Live preview at real speed and onion skin in the sprite editor.
  - Actor state picks the animation automatically: still -> Idle, moving -> Walk, platform player in the air -> Jump / Fall. New rule bits: DO "play animation" (value = animation), WHEN "animation ends".
  - Data block: actor record gets an offset to an animation table instead of `A_SPR2` (bump version to 5, keep Lite's two-frame actors working by writing them as a 2-frame Loop). Frame images are written once per used sprite slot and shared. Change `engine.s`, `scr_adf.gml` and `adf_reference.py` together; old `.adam` files load with `anim_sprite` turned into a 2-frame Walk/Idle.
  - Lite keeps the current two-frame animation; the page shows the rest locked with `pro_gate("Animations")`. Ship a Pro example and a Pro lesson.
- Suggested order: `pro_on()` (done), BOBs (done, 16 x 16 up to 64 x 64 - size picker on the Sprites page), then scrolling (most other Pro features build on them), then the rest.
