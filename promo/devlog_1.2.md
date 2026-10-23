# ADAM 1.2 - a new Home page, animated tiles and faster BOBs

ADAM 1.2 is a smaller update than 1.1, but it's one you'll see as soon as it opens. Here's what changed since 1.1.0.

## Added

**A new Home page.** *How it works* and the *Example games* now sit side by side as two lists, and every example game has a picture of its first screen (the A1200 version's picture when you've picked the A1200). Click a game to load it, or double-click it to build a disk and play it in FS-UAE straight away.

**Animated tiles (Pro).** Tiles in a tile world can now animate: water, lava, torches, flickering lights. On the Tiles page, give a tile 2 to 8 pictures in its new Animation box, pick a speed and Loop or Ping-pong, and watch the preview. The tile keeps behaving as itself (solid, dig, ladder and so on), only its picture changes. The water and torches in Dig Deep show how it looks.

## Improved

- **Faster BOBs.** The blitter now draws only the part of each BOB that actually has pixels in it, and draws planes that are empty or solid more cheaply. Busy games with lots of BOBs drop far fewer frames: Starfire on the A1200 now keeps up almost all the time.
- ***Flash the screen* is now *Flash the player*.** A flashing screen wasn't pleasant to play, so this DO now makes the player blink instead, the same blink a hit gives. Your rules keep working as they are. It's also quicker for the Amiga, especially in games with a copper sky.
- **Small screens.** On a smaller laptop (1366 x 768, or 1080p with Windows set to 150%) ADAM's window could run off the bottom of the screen. Now, when the window is smaller than 1280 x 720, the whole interface shrinks to fit and every page keeps the same layout. The smallest window is 960 x 540.

## Fixed

- The Sound page's *Play sound* button could end up half off the bottom of the panel on a 1280 x 720 screen. The settings above it now scroll instead, and the button stays in view.
- On the Tiles page, the white first-screen box and the actors no longer draw past the edge of the map.
- The tip under the Music page's loop list no longer runs out of its panel.
- Lowering the bitplanes on the Backdrop page, or switching an A1200 project to the A500 / A600, no longer leaves a custom HUD's frame and text in colours that are gone (they showed as a flat bar).

## Known issue

- Starfire still drops frames on the A500 / A600 when the screen is very busy: there's simply more going on than a 7 MHz 68000 can keep up with at 50 frames a second. The A1200 version is fine.

## Getting it

Download the installer (`_Setup.exe`) or the zip from this page. FS-UAE still comes with ADAM, so Build & play works straight away. Projects from earlier versions open as they are.

## What's next

I'm working on more for tile worlds - a back layer for scenery behind the play area and a front layer that actors can walk behind - on the way to isometric rooms.

Thanks again to everyone who has tried ADAM and sent feedback. If something doesn't work the way you expect, please tell me in the comments.

- Robert
