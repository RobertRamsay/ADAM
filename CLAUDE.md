# ADAM — Claude Code guide

ADAM ("Amiga Developmental Machine") is a no-code Amiga game maker written in
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
| `scr_examples`, `scr_intro`, `scr_tutorial` | Example loader, launch intro, tutorials. |

Project data (`proj`) is plain JSON-able structs/arrays; `.adam` files are `json_stringify(proj)`.

### Runtime (68000)
`datafiles/engine/engine.s` is a **fixed, position-independent** engine
(`vasm -pic`). ADAM never generates code: it appends a **data block** right
after `engine.bin`; `boot.s` (bootblock) AllocMem's chip RAM, reads engine+data
with trackdisk (showing a copper loading bar) and jumps in. Registers held:
`a4` = data block, `a5` = V+128 (variables; per-actor tables must stay within
the signed 8-bit displacement), `a6` = $dff000.

**Data block header** (offsets from data start; longs are offsets from data start, 0 = absent):
`0 'ADAM' | 4 version | 6 flags (bit0 AGA) | 8 depth | 10 nact | 12 nrule | 14 lives | 16 show score | 18 show lives | 20 hud row | 22 hud colour | 24 msg colour | 26 player actor (-1) | 28 game block | 32 palette | 36 planes (original) | 40 actors | 44 rules | 48 sfx table | 52 game-over text | 56 win text | 60 sprite pair colours | 64 display planes | 68 copper sky (256 x $0RGB; AGA: + 256 words of low nibbles, written with LOCT) | 72 painted ground (320 words) | 76 work planes (backdrop + hills) | 80 music table` — header is 84 bytes, version 2. Music table (`M_*`, see docs/MUSIC_CONTRACT.md): nsongs word, 10 level-song bytes ($FF none), then { offset, length } of each ProTracker MOD.

- Actor record = 48 bytes (`A_*` equates), rule record = 16 bytes (`R_*`), sfx entry = 8 bytes (offset, length in words, Paula period), game block = `G_*` (levels, terrain colours, goal, title text, 320 heights per level).
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
- **Pro** = the Phase 4 features below. Planned unlock: one build + licence key (itch.io keys), checked like the `ADAM_DEV_TOOLS` switch - not two separate builds. Optional "Made with ADAM" card in Lite games that Pro removes.
- Gate a Pro feature in one place (a `pro_on()` check) so the UI shows it locked with a short "Pro" note rather than hiding it.

### Phase 3 — Should-fix features (Lite)
- Sprite editor animated preview and PNG import; more genre examples.

### Phase 4 — ADAM Pro
- **Graphics:** dither gradients and drawing with dither patterns; BOBs (blitter objects) beyond the 8 hardware sprites; scrolling playfields (horizontal / vertical) with a tile level editor; parallax / dual playfield; colour cycling, raster bars and per-level copper effects (build on `copper_blend_lines`); IFF/ILBM import and export (Deluxe Paint / PPaint); attached sprites (15 colours), more animation frames, flipping.
- **Gameplay:** bullets / "fire shoots" for player and enemies; variables and counters in rules; rooms / multiple screens per level; two players; pause and second fire button / CD32 pad; high-score table saved to disk.
- **Sound and music:** instrument editor (synth envelopes, sample loop points); tracker effects in the step editor (slides, vibrato, arpeggio, volume); sample compression for more sound per disk.
- **Output:** play-in-browser export for itch.io (web Amiga emulator); hard-drive install (WHDLoad slave) and CD32 image; custom boot / loading screens and an intro maker; proper DOS disk so the ADF shows a named disk with an icon on Workbench.
- **Workflow:** genre templates and asset packs; play the game inside the editor without FS-UAE; 68000 source export for learning.
- Suggested order: licence check + `pro_on()` first, then BOBs and scrolling (most other Pro features build on them), then the rest.
