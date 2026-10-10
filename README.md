# ADAM

Make Commodore Amiga games without writing code. A GameMaker project by Polytricity.

ADAM works like C64 No-Code: paint a backdrop, draw sprites, place actors, write
WHEN / DO rules, design sounds, then build. The result is a bootable `.ADF`
floppy for a stock **Amiga 500/600 (OCS/ECS, 1MB)** or **Amiga 1200 (AGA, 2MB)**,
chosen when ADAM starts.

## How a game is built

ADAM does not generate code. `datafiles/engine/engine.bin` is a fixed,
position-independent 68000 engine (source: `engine.s`). ADAM appends the game
as a data block (header, palette, bitplanes, sprites, actors, rules, Paula
samples), writes `boot.bin` as the bootblock and saves an 880 KB ADF.
The bootblock allocates chip RAM, reads the game with trackdisk and jumps in.

Reassembling the engine (only needed when editing it):

    vasmm68k_mot -Fbin -pic -m68000 -no-opt -o engine.bin engine.s
    vasmm68k_mot -Fbin -pic -m68000 -no-opt -o boot.bin boot.s

## Hardware limits ADAM works within

| | Amiga 500/600 | Amiga 1200 |
|---|---|---|
| Backdrop | 320 x 256, up to 16 colours | 320 x 256, up to 128 colours |
| Palette | 4096 (12-bit) | 16.8 million (24-bit) |
| Actors | 8 hardware sprites, 16 x 24, 3 colours | same |
| Sprite colours | registers 17-31 | registers 241-255 (BPLCON4) |
| Sounds | 8 one-shot samples, 4 Paula channels | same |

Sprites come in pairs that share colours; ADAM puts actors with matching
colours on the same pair automatically.

## Extras

- **Copper sky** - colour 0 changes on every display line (three colour stops,
  12-bit, works on OCS/ECS and AGA). The border follows it.
- **Two-frame animation** - an actor can flip between two sprites, always or
  only while it moves.
- **Sampled sounds** - import a WAV, then choose Paula's playback rate
  (4-28.8 kHz) and a bit crunch (8 down to 2 bits).
- **Levels** - up to 10 levels; each has hills grown from a seed and shaped by
  hand, drawn by the engine at the start of the level. Goal counter
  (e.g. GEMS 00/20), title screen, level cards, enemies that join on later
  levels and get faster.
- **Platform behaviours** - platform player (walk + jump), hopper, faller,
  ground colours, flashing immunity, show-for-a-moment pops.
- **Example games** - Gem Hunter, Deep Dive, Star Catcher and Dodge Ball in
  `datafiles/examples`, loaded from Home.

## Playing

Set the FS-UAE path on the Build page. No Kickstart ROM is needed - games boot
on FS-UAE's built-in AROS ROM. Joystick in port 2, fire to restart after
game over.

The 8 x 8 font is font8x8 by Daniel Hepper (public domain). Poppins is under
the SIL Open Font License (datafiles/fonts/Poppins-OFL.txt).
