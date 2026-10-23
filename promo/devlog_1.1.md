# ADAM 1.1 - shoot 'em ups, tile worlds, items and a lot more

ADAM 1.1 is out, and it's the biggest update since launch. Here's what changed since 1.0.1.

## Added

**Shoot 'em ups.** Games can now scroll up, down, left or right. Flyers come in with flight patterns (waves, zigzags, homing, turrets that move with the scenery, bosses that fly in and patrol), enemies fire back, and you can collect power-ups: more firepower, speed, homing missiles and options that follow your ship. Scrolling maps are built from tiles, with spawners that send out waves.

**Tile worlds.** A new Tiles page for big scrolling worlds made of tiles. Players can dig, build, climb ladders, swing a sword, throw things and switch tools with the space bar.

**Items and recipes.** A new Items tab on the Logic page for keys, potions, torches, anything the player picks up. An item can be used up, kept, or last a few uses, and two items can be combined into a new one. Rule cards can now have IF lines, such as *IF the player has the KEY*.

**The Animate page.** Named animations for every actor: Idle, Walk, Jump, Fall, Hit and Die. Each one loops, plays once or ping-pongs, with 8 directions, separate animations for firing, a library to drag animations between actors, and a Test mode. The sprite editor has onion skin.

**The UI page.** Design your own HUD: a framed panel in your game's colours, a font and fields for score, lives, level, items and more. Its Loading screen tab makes a loading picture with a progress bar, and pictures can appear as the game loads.

**Named palettes.** Switch or fade the whole picture to another palette from a rule (nightfall, a red alert), and choose the palette each level starts with.

**Patch synth.** A new kind of sound on the Sound page, with three oscillators, a filter, envelopes, LFOs and effects.

**Second disk.** Level music can go on a second disk when a game doesn't fit on one.

**New rule parts.** DOs: shoot, spawn, power up, play an animation, switch palette, give / take / make / drop items. WHENs: a shot hits, a weapon strikes, an animation ends, the player gets or uses an item, fire held (auto-fire), the map reaches its end, and more.

**New example games (Pro):** Nebula Strike, Starfire and Jade Serpent (shoot 'em ups), Dig Deep (a tile world) and Torchlight (items).

**New lessons (Pro):** Lesson 6 *Sky Raid* (a shoot 'em up), Lesson 7 (a loading screen) and Lesson 8 *The locked door* (items).

## Improved

- **Lite and Pro have the same features now.** In 1.0.1 some tools were Pro only: BOBs, the Gradient tool, Pattern brushes and big sprites. They're all in Lite now. Pro raises the limits and adds the extra examples and lessons:

  | | Lite | Pro |
  |---|---|---|
  | Frames per animation | 6 | 16 |
  | Biggest sprite / BOB | 32 x 32 | 64 x 64 |
  | Actors on the disk | 12 | 32 |
  | Sprite bank | 64 (was 32) | 128 |
  | Sounds | 8 | 64 |
  | Tile types | 96 | 512 |

- **Sounds:** up to 64 in Pro, sorted into folders, and only the sounds your game actually uses go on the disk, which leaves more room.
- **Music editor:** new notes take the snap length, keys 1-4 pick the snap, hold Alt to place without snap, Ctrl-drag copies notes, selected notes resize together, drags show a ghost of where the notes will land, and drum hits play as you drag them. The built-in instruments sound cleaner, and the preview is filtered like a real A500.
- **Build & play** no longer asks where to save when you try an example or a new game: it plays a test disk straight away. Build on its own still asks.
- **A1200 versions of the examples** use the A1200's extra colours for smooth gradients instead of dithering. The shoot 'em ups use 64 colours there.
- ***Flash the screen*** flashes mid red instead of white, which is much easier on the eyes.

## Fixed

- High notes on the music editor's synth instruments no longer turn into a harsh buzz.
- The music editor's effect labels are no longer cut short (such as "Down" showing as "D...").
- Dragging a single note no longer moves it before you let go. It now moves on release, and letting go where it started changes nothing.

## Known issue

- Starfire can slow down on the A1200 when the screen is very busy. I'm working on it for the next update.

## Getting it

Download the installer (`_Setup.exe`) or the zip from this page. FS-UAE, the free Amiga emulator, still comes with ADAM, so Build & play works straight away. Your projects from 1.0 open as they are.

Thanks to everyone who has tried ADAM, sent feedback or shared a game. If something doesn't work the way you expect, please tell me in the comments.

- Robert
