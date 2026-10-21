# ADAM Pro — isometric rooms, tile layers, animated tiles (plan)

Asked for by a buyer (Oct 2026): isometric games with runtime depth sorting
(actors go in front of and behind objects), elevations, isometric collision,
an isometric tile editor; multi-layered tile maps; animated tiles.

Status: planning. Nothing here is built yet. Bob's decisions (21 Oct 2026)
are at the end and folded into the sections below.

**Pro only:** these are ADAM Pro features - the first real Pro-only features
since Lite and Pro got the same features. Gate them with `pro_edition()` (a
new `pro_feature("Isometric rooms")` helper beside `pro_gate`, so the button
shows locked with a short "Pro" note in Lite, as CLAUDE.md asks). A Pro
project opened in Lite keeps its data; `lite_trim` drops layers, tile
animations and isometric rooms from the disk copy with a Build-page warning.

## What ADAM already has to build on

- **BOBs** (`bob_draw` / `bob_flip`): double-buffered display, a background
  buffer each BOB is wiped from, trimmed frames (`BI_*`). An isometric room is
  a picture drawn once into that background, so the wipe / draw / flip cycle
  stays as it is. Today BOBs are drawn in actor order; isometric needs a
  sorted order and some scenery redrawn over them.
- **8-direction animations** (`anim_dirs`, entries N..NW): isometric characters
  face NE / SE / SW / NW, so they use the compass layout as it is.
- **Tile world** (`T_*`, `draw_cell`, `cam_window`, `cop_scroll`): a scrolling
  ring of tiles under a copper HUD split. Layers and animated tiles add to
  this, not replace it.
- **Shoot 'em up maps** (`MP_*`) already split tile *types* from tile
  *pictures*; animated tiles use the same split.
- **Copies** (`actor.copies`, `A_TYPE`): one actor written N times. Rooms use
  the same idea to place many copies of a few actor types.
- Rules, items, HUD, palettes, music: unchanged, they work in any world type.

## Order of work

Smallest and most reusable first. Each step is one commit (or a few), ends
with a clean Igor compile, engine reassembled, `adf_reference.py` matching,
examples regenerated, and a "how to verify" note.

1. **Animated tiles** (tile world) — small, visible win, no colour cost.
2. **Back layer** (tile world) — decoration behind the main layer.
3. **Front layer** (tile world, dual playfield) — decoration in front of actors.
4. **Depth-sorted BOBs** (any BOB game) — draw BOBs by the line their feet
   are on. Useful by itself (top-down / beat 'em up games) and the base of
   isometric sorting.
5. **Isometric rooms** — engine spike first (speed on an A500), then data,
   editor, rules, example, lesson.

Steps 1-3 and step 4 touch different code and can run side by side.

---

## 1. Animated tiles

**Player sees:** water, lava, torches, conveyor belts that move on their own.

**Editor (Tiles page, tile panel):** an *Animation* box per tile type: a strip
of up to 8 frames picked from the tile pictures, a rate (50ths of a second per
frame), Loop / Ping-pong, a live preview. The tile keeps its own flags
(solid, dig, goal, ladder); frames are pictures only.

**Data:** `tile.anim = { frames : [], rate : 8, mode : 0 }` (initialised in
`project_new` and `obj_app` Create; the loader fills it in for old projects).
On the disk, tile pictures become `NT + extra frames`; a `TA_*` table lists
for each animated type its frames, rate and mode. `T_*` header grows (fields
move `T_PROPS` on), data version 15.

**Engine:**
- `v_timg` indexing goes through a word table `tile -> picture` (`v_tpic`,
  BSS). `draw_cell` reads the picture from there; physics still reads the
  tile type from the map, so digging / ladders / goals are unchanged.
- `tile_anim` each frame: counts down each animated type; on a step it
  writes the new picture into `v_tpic` and redraws the cells of that type in
  view (`v_tx0..+NCOL`, `v_ty0..+NROW`) with a byte table `animated[type]` for
  a fast scan. Skipped completely when no animated type is in the game.
- Cost estimate: scanning ~380 cells is ~25-30 raster lines, plus ~10 lines
  per cell redrawn. Steps every 4-8 frames, so fine on an A500 for a handful
  of animated cells in view. Measure with a `dbg5.py`-style wrapper.
- Shoot 'em up maps: not in the first version (map lines are drawn once
  into 2-3 buffers). Colour cycling is the cheap alternative there.

**Example:** add a waterfall / lava to Dig Deep or a new small Pro example.

## 2. Back layer (tile world)

**Player sees:** pipes, windows, vines, cave walls behind the solid tiles,
with no effect on play.

**Editor:** a layer picker on the Tiles page — *Back / Main / Front* — with
eye toggles and "dim the other layers". Any tile picture can be painted on any
layer; tile flags only count on Main. Colour 0 of a Main tile is see-through
to the Back layer.

**Design (recommended: compose at build time):**
- The writer composes Back + Main into combined pictures per cell, drops
  duplicates, and writes a *picture map* beside the tile map. `draw_cell`
  copies one picture exactly as now — no extra cost while scrolling.
- When a cell changes in the game (dig, place, DO 20), its picture-map entry
  is set to "compose" ($FFFF) and `draw_cell` draws Back then Main with a
  mask for that cell (CPU, one cell, rare). Animated tiles on a Back or Main
  cell use the same compose path.
- The Tiles page shows "tile pictures on the disk: N" so a busy back layer
  that makes many combinations is visible before it fills memory.
- Rejected: composing every cell at run time (doubles the cost of each new
  column / row — too slow on an A500 when scrolling fast).

## 3. Front layer (tile world)

**Player sees:** actors walk behind grass, pillars, foreground arches.

**How:** hardware sprites can only go behind a playfield's pixels in **dual
playfield** mode, so a Front layer switches the tile world to dual playfield:
- Playfield 1 (odd planes, colours 0-7) = Front layer, in front of sprites.
- Playfield 2 (even planes, colours 8-15) = Back + Main, behind sprites.
- BPLCON2 puts the sprites between them; the copper turns dual playfield on
  at the HUD split, so the HUD keeps its colours.
- A second ring buffer for the Front layer, scrolled with the same pointers
  and BPLCON1 (both playfields move together).

**Cost:** OCS: Main drops to 7 colours + see-through (3 planes), Front gets 7.
AGA: 15 + 15 (4 + 4 planes, BPLCON3 PF2OF). The editor shows it plainly when
the box is ticked ("Front layer: the map uses 7 colours, the front layer 7
more") and remaps tile pictures to the nearest colours.

**Later, same plumbing:** parallax (Playfield 2 scrolls at half speed behind
Main) is on the Pro list; it uses this dual-playfield mode with the layers
swapped. A game can have a Front layer *or* parallax, not both.

**Decided:** on both machines (the dual-playfield code is the same; holding
the A500 back would save no work). The Front layer tick box shows the colour
cost for the machine picked before it is switched on.

## 4. Depth-sorted BOBs

**Player sees:** in a top-down or beat 'em up game with BOBs, the actor
lower on the screen is drawn in front.

- Actor setting / game setting "Draw BOBs in depth order" (on for isometric).
- `bob_draw` builds a list of visible BOBs and insertion-sorts it by feet
  line each frame (the list is nearly sorted from last frame, so it is cheap
  for up to 32 actors). The wipe list is unchanged.
- No data layout change beyond one flag bit.

---

## 5. Isometric rooms

### The game shape

Flip-screen isometric rooms, as in Head Over Heels, Cadaver, Knight Lore
and Fairlight: each room fits the screen, walking off an edge enters the next
room. A scrolling isometric world is not planned for the first version — on
an A500 the redraw of a moving isometric picture plus depth sorting would not
keep 50 fps; flip-screen rooms fit the BOB system we already have.

### Geometry

- Tiles are 2:1: a floor cell is a **32 x 16** diamond. World units: a cell
  is 16 x 16 on the floor; height `z` in pixels.
- Screen: `sx = ox + (wx - wy)`, `sy = oy + (wx + wy) / 2 - wz`. A full block
  is 32 x 32 (16 top + 16 sides), a half block 32 x 24. Heights in steps of 8
  pixels (half blocks make stairs).
- A room's floor is **8 x 8 cells** (first version, to test): a 256 x 128
  diamond. Under a 16-line HUD that leaves room for blocks stacked 6 high
  (96 pixels) at the back. Other sizes later if the test says so.
- Room origin `ox` is a multiple of 16, so **every block lands on a word
  boundary** - block blits need no shift and clip to whole words, which keeps
  the redraws cheap.

### Storeys (Bob's stairwells)

- Rooms sit on **5 storeys**: the game starts on the middle one, storey 0
  (the "start tile grid"), with storeys +1 / +2 above and -1 / -2 below.
- Each storey is a grid of rooms; the same grid position on the storey above
  is the room overhead.
- Going up: climbing stairs (half blocks) or a stack to the top of the room
  (above the 6th block) enters the room overhead, standing on its floor at
  the same x / y. Going down: a hole in the floor (a cell with no floor tile)
  drops the player into the room below, landing from the top.
- Stairwell check in the editor: a hole or an "up" spot with no room on the
  other side is marked in red.

### Engine

- **Room picture:** on entering a room, floor diamonds then blocks back to
  front (by `cx + cy`, then level) are blitted into the BOB background, then
  copied to both displays (screen blanked or faded meanwhile).
- **Actors:** `x, y` are world floor coordinates (most roles move in x / y
  already: patrol L-R = along x, patrol U-D = along y, chaser, bouncer, still
  work in world space), plus `v_z` / `v_vz` for height and gravity.
  `place_sprites` projects to the screen. All actors in an isometric game are
  BOBs (a hardware sprite cannot go behind scenery).
- **Collision in world space:** a block is a box (cell x height). Moving in x
  then y against blocks at the actor's height, stepping up 8 pixels or less
  (like `tile_hres`), gravity in z, standing on the highest block top under
  the footprint. Actor footprints are at most one cell. Touch (WHEN 0),
  weapon strikes, shots and items use 3D box overlap instead of screen boxes.
- **Depth sorting:** the list from step 4, ordered by `wx + wy` then `z`. For
  each BOB drawn, the blocks that overlap its screen box and are *in front of
  it* are redrawn over it with their mask, clipped to its box. "In front" is
  the box separation test (A is behind B when A ends before B starts in x, y
  or z), which is exact for one-cell blocks and footprints. Only blocks
  within 2 cells in front of the actor are checked.
- Known edge case: two actors overlapping each other *and* a block between
  them in depth can draw wrongly for a frame. If it shows in testing, the fix
  is to sort the nearby blocks into the same list (topological order).
- **Controls:** setting "Joystick up = up the screen / up-right (along the
  room)". Up-right is what Head Over Heels does and maps the 4 diagonal
  directions to the 4 world axes.
- **Rooms:** 5 storeys, each a grid of rooms (proposed 8 x 8 grid per
  storey, up to 64 rooms in the whole game - memory, not the grid, is the
  limit). Exits are gaps in the walls; the player leaves at one edge and
  arrives at the opposite edge of the neighbour, keeping height. Up / down
  between storeys as above.
- **Actors in rooms:** actor *types* are global (up to 32 as now); each room
  lists placements (type, x, y, z). On entering a room the engine fills actor
  slots from its list. A "gone" bit per placement keeps picked-up items and
  defeated enemies gone when the player comes back.

### Speed (the main risk - spike before anything else)

Rough A500 sums at 4 planes: a clipped block redraw over a 32 x 24 actor is
~10 raster lines; with 6 actors and up to 3 redraws each, plus BOB draws and
wipes, that is ~290 of 312 lines. So:
- Recommend 4 planes (16 colours) for isometric on the A500; the A1200 can
  take more.
- Spike: a scratch engine that draws one fixed room and moves 6 BOBs with
  redraws, timed in FS-UAE (A600 and A1200) before the data layout is fixed.
- If it does not fit: a 25 fps option for isometric games (logic every frame,
  drawing every second frame), which is what many Amiga isometric games did.
  **Decided:** the 25 fps fallback is fine. Build it as a game setting
  (Build page: "Isometric speed: 50 / 25 fps"), defaulting from the spike's
  result per machine.

### Data (data version 16)

- New header field `H_ISO` at 116 (header 120 bytes): `IS_*` block — room
  grid size per storey, start room, room index (storey -2..+2, grid x, y ->
  room or none), block types.
- Block types `IB_*`: picture (32 wide, mask + planes), height (0 floor /
  8 / 16), flags (solid, deadly, goal, ladder, pushable later), sound.
- Room `IR_*`: size, origin, floor tile per cell, block list
  (cell, level, type) - compact, ~250 bytes for a typical room - and the
  placement list. 64 rooms ~16 KB; 64 block types at 4 planes ~40 KB.
- Changed in three places as always: `engine.s`, `scr_adf.gml`,
  `tools/reference/adf_reference.py`.

### Editor

- **Its own page, `WS_ISO` ("Rooms")**, script `scr_ws_iso`, after Tiles in
  the page bar. The world dropdown on the Tiles page also lists "Isometric
  rooms" and jumps to it. Locked with a Pro note in Lite.
- **Block maker:** paint a top texture (16 x 16) and a side texture; ADAM
  shears them into an isometric block (left side darker, right side lighter,
  in the nearest palette colours). Or draw the 32 x 32 block by hand / import
  a PNG. Height: floor, half, full.
- **Room editor:** isometric view; click a cell to stack the chosen block,
  right-click to take the top one off; a height slider shows the levels above
  as outlines; floor painting; place actors in the room (drag, with a shadow
  on the floor so height is clear). "Fits the screen" indicator.
- **Room map:** a small grid of rooms with storey tabs (+2 / +1 / 0 / -1 /
  -2, 0 picked at first); click to edit one, arrows show exits, up / down
  marks show stairwells. Start room per level (storey 0 by default).
- **Test mode:** walk the player round the room in the editor (reusing the
  Animate page's Test input) so collision and heights can be checked without
  FS-UAE.
- Rules: WHEN the player enters room n; DO go to room n (at actor / door).

### Example and lesson

- Pro example: a short Head Over Heels-style castle - 6-9 rooms over
  storeys -1, 0 and +1 (a stairwell up, a hole down to a cellar), stacked
  blocks to climb, a key behind a wall (items), a guard patrolling behind a
  pillar to show the depth sorting. `ex_iso.py` in gen_examples, plus the
  `_a1200` version.
- Pro lesson: "Pro - Isometric: the castle" (blocks, a room, walk behind a
  pillar, a second room, a door).

---

## Decisions (Bob, 21 Oct 2026)

1. **Pro only** - gated with `pro_edition()`, shown locked in Lite (all three
   features: isometric rooms, tile layers, animated tiles).
2. **Front layer colours** - the recommendation: allowed on the A500 and the
   A1200, with the colour cost shown when it is switched on.
3. **Isometric gets its own page** (`WS_ISO`).
4. **5 storeys** for stairwells, starting on the middle one (storey 0, the
   start tile grid), +2 above and -2 below. Tiles 2:1 (32 x 16); a room floor
   of 8 x 8 cells to start with, to test.
5. **25 fps fallback** is acceptable.

Still open: rooms per storey (proposed 8 x 8 grid, 64 rooms in all) and
in-room stacking height (proposed 6 blocks) - settle after the speed spike.
