# ADAM Pro — to-do

Pro extras queued up. Since 1.1.0 Lite and Pro have the same features and
Pro raises the limits (`lim_*()` in `scr_licence`); new Pro-only features are
gated with `pro_edition()` / `pro_gate()`, and each ships with a Pro example
game and a Pro lesson (see CLAUDE.md, Phase 4).

## Done

- **Expanded music editor** (1.1.0): Patch synth, up to 64 sounds in
  folders, the improved step editor.
- **Multi-frame animation** (1.1.0): the Animate page - Idle, Walk, Jump,
  Fall, Hit, Die, 8 directions, Fire animations, onion skin.
- **Scrolling playfields** (1.1.0): tile worlds (Dig Deep) and shoot 'em
  ups with scrolling backdrops and maps (Nebula Strike, Starfire, Jade
  Serpent).
- **Animated tiles** (1.2.0): step 1 of docs/ISO_LAYERS_PLAN.md.

## Next: isometric rooms, tile layers

- Plan: docs/ISO_LAYERS_PLAN.md (asked for by a buyer, Oct 2026).
- Order: back layer, front layer (dual playfield), depth-sorted BOBs, then
  isometric rooms (A500 speed spike first).

## Also asked for

- Fewer bitplanes as a memory saving; a Pro lesson for palette switching.
- Multi-disk games part 2: per-level maps and backdrops on disk 2.
- A big-BOB example and lesson.
- Parallax (reuses the front layer's dual playfield), colour cycling,
  IFF/ILBM import and export, high-score table, two players.
