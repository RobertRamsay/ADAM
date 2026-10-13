# ADAM Pro — to-do

Pro-only features queued up. Each one is gated with `pro_on()` / `pro_gate()`
in `scr_licence`, and ships with a Pro example game and a Pro lesson (see
CLAUDE.md, Phase 4).

## 1. Expanded music editor

- Being worked on in a separate session.
- Builds on the Lite Music page (loop library, step editor, .mod import/export).
- Likely scope: instrument editor (synth envelopes, sample loop points),
  tracker effects in the step editor (slides, vibrato, arpeggio, volume).

## 2. Multi-frame animation for players and enemies

- Today: two frames per actor (`A_SPR` / `A_SPR2`, rate `A_ARATE`, `v_frame`).
- Goal: several frames per sprite, and separate animations per state —
  e.g. walk left / walk right, jump, idle, hit / die.
- Questions to settle: max frames per sprite (chip RAM budget), whether
  hardware sprites and BOBs both get it, flipping (mirror at build time so
  one drawn walk cycle covers both directions).
- Touches: Sprites page (frame strip, onion skin, animated preview), actor
  record layout (frame table offset + count), engine frame pick, so
  **engine.s, scr_adf.gml and adf_reference.py** all change together.

## 3. Scrolling playfields

- Horizontal (left / right), vertical (up / down), maybe both.
- Needs a tile-based level editor (a backdrop bigger than 320 x 256 won't
  fit in chip RAM as one bitmap for long levels).
- Engine: hardware scroll (BPLCON1 fine scroll + bitplane pointers), new
  tile column / row drawn by the blitter as the camera moves; actors in
  world coordinates, camera follows the player.
- Rules to add: e.g. WHEN reaches end of level, DO stop / start scrolling.
- Foundation for later Pro items: parallax / dual playfield, rooms.

## Order

Music editor (in progress) → multi-frame animation → scrolling.
Animation first because it is smaller and scrolling games will want it.
