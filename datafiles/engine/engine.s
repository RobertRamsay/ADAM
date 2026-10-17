; ============================================================================
;  ADAM runtime engine  -  Polytricity 2026
;
;  A fixed, data-driven 68000 engine.  ADAM never generates code: it appends
;  the game data block (header, palette, backdrop, actors, rules, sounds)
;  straight after this binary and the engine reads it at data_start.
;
;  Position independent - loaded anywhere in chip RAM by the ADAM bootblock.
;  Assemble:  vasmm68k_mot -Fbin -pic -m68000 -no-opt -o engine.bin engine.s
;
;  Registers held for the whole run:
;     a4 = data_start (game data block)
;     a5 = V          (engine variables)
;     a6 = $dff000    (custom chips)
;
;  Music and sound effects are played by Frank Wille's ptplayer (public
;  domain, ptplayer/ptplayer.asm, included near the end). It runs from CIA-B
;  timer interrupts (level 6), so the engine runs in supervisor mode with only
;  the EXTER interrupt enabled. Sound effects go through _mt_playfx, which
;  mixes them into the music on the same 4 Paula channels.
; ============================================================================

; ptplayer options (see ptplayer/ptplayer.readme): the default single-section
; CIA-B version, with the word at address 0 used for idling channels (the
; engine clears it), so sound effects need no leading zero word.
NULL_IS_CLEARED equ 1

; ---------------- game data header (offsets from data_start) ----------------
H_MAGIC     equ 0
H_VERSION   equ 4
H_FLAGS     equ 6          ; bit 0 = AGA machine
H_DEPTH     equ 8          ; backdrop bitplanes 1..8
H_NACT      equ 10
H_NRULE     equ 12
H_LIVES     equ 14
H_SHOWSC    equ 16
H_SHOWLV    equ 18
H_HUDROW    equ 20         ; text row 0..31
H_HUDCOL    equ 22         ; palette index
H_MSGCOL    equ 24         ; palette index
H_PLAYER    equ 26         ; actor index or -1
H_GAME      equ 28         ; offset: levels / goal / title block, 0 = single screen
H_PAL       equ 32         ; offset: palette, (1<<depth) longs $00RRGGBB
H_PLANES    equ 36         ; offset: pristine backdrop, depth * 10240 bytes
H_ACTORS    equ 40         ; offset: actor records
H_RULES     equ 44         ; offset: rule records
H_SFX       equ 48         ; offset: sound entries (one per sound, up to 64; length 0 = not on the disk)
H_TOVER     equ 52         ; offset: game over text (0 terminated)
H_TWIN      equ 56         ; offset: win text (0 terminated)
H_SPRCOL    equ 60         ; offset: 4 sprite pairs x 3 longs $00RRGGBB
H_DISP      equ 64         ; offset: display bitplanes (depth * 10240 bytes)
H_GRAD      equ 68         ; offset: 256 copper sky colours ($0RGB words), 0 = none; AGA: + 256 words of low nibbles
H_GROUND    equ 72         ; offset: 320 ground heights (words), 0 = none
H_WORK      equ 76         ; offset: backdrop + terrain copy (depth * 10240 bytes)
H_MUSIC     equ 80         ; offset: music table, 0 = no music
H_DISP2     equ 84         ; offset: second display buffer for BOBs (depth * 10240 + 8), 0 = no BOBs
H_BACK      equ 88         ; offset: BOB background - backdrop + hills + HUD (depth * 10240 + 8), 0 = no BOBs
H_TILES     equ 92         ; offset: tile world, 0 = none (version 6)
H_UI        equ 96         ; offset: custom HUD (ADAM Pro UI editor), 0 = the standard HUD (version 7)
H_SCROLL    equ 100        ; offset: scrolling backdrop (shoot 'em ups), 0 = it stands still (version 9)
H_PALS      equ 104        ; offset: named palettes, 0 = none (version 11)
H_DISK2     equ 108        ; offset: disk 2 block, 0 = a one-disk game (version 12)
H_ITEMS     equ 112        ; offset: items and recipes, 0 = none (version 13)
HDR_SIZE    equ 116

; items block (H_ITEMS): IT_N items of IT_SIZE bytes, then IT_NR recipes of RC_SIZE bytes
IT_N        equ 0
IT_NR       equ 2
IT_RECS     equ 4
IT_ACT      equ 0          ; the actor picked up as it (a disk actor, its copies too), -1 = none
IT_USE      equ 2          ; byte: using it 0 uses it up, 1 keeps it, 2 uses up one of IT_USES uses
IT_FLAGS    equ 3          ; byte: bit 0 kept on the next level, bit 1 lost with a life
IT_USES     equ 4
IT_CARRY    equ 6          ; the most the player carries
IT_START    equ 8          ; carried when the game starts
IT_NAME     equ 10         ; 8 letters, 0 terminated (10 bytes)
IT_SIZE     equ 20
RC_A        equ 0          ; item + item make RC_N of item RC_OUT
RC_B        equ 2
RC_OUT      equ 4
RC_FLAGS    equ 6          ; byte: bit 0 RC_A is kept, bit 1 RC_B is kept
RC_N        equ 7          ; byte
RC_SIZE     equ 8
ITEM_MAX    equ 16
DROP_GAP    equ 24         ; DO 31: a dropped item comes out this far beside the player
MENU_MAX    equ 40        ; space bar menu entries: tools, items carried, recipes that can be made
IF_LINE     equ $8000      ; a rule line with this bit in its act word is an IF line:
                           ; act = IF_LINE + 0 has / 1 uses / 2 has none / 3 has at least, target = n, value = item

; disk 2 (version 12): level songs that did not go on the game disk. A song's
; music table offset with bit 31 set is a byte offset on disk 2 (a track start).
; Disk 2's first sector holds 'ADM2' and D2_ID. The engine reads it itself (the
; OS is gone): raw MFM tracks by disk DMA from DF1 or DF0, decoded here.
D2_ID       equ 0          ; long: the id disk 2 must carry
D2_RAW      equ 4          ; long: offset (cleared memory after the data) of the raw track buffer
D2_BUF      equ 8          ; long: offset of the song buffer (the biggest disk 2 song, whole tracks)
TRK_BYTES   equ 5632       ; 11 sectors of 512
RAW_WORDS   equ 6400       ; read a whole turn of the disk and a bit (12800 bytes)

; named palettes (version 11): each changes some of the backdrop colours of the
; main palette (H_PAL); DO 27 switches to one, fading over some frames, and each
; level can start with one. Palette 0 = the main palette.
PS_N        equ 0          ; word: named palettes
PS_LEVEL    equ 2          ; 10 bytes: the palette each level starts with
PS_OFFS     equ 12         ; PS_N longs: offset of each palette - a word count, then
                           ; { colour index word, 0 word, $00RRGGBB long } each
PAL_FADE    equ 128        ; colours a palette can change (the A1200 backdrop's 128)

; scrolling backdrop (version 9): the 320 x 256 picture (backdrop + hills) loops
; endlessly up, right, down or left behind the actors, under a HUD strip at the
; top (copper split at v_hudlines, as in a tile world). The picture is kept
; twice in each buffer, so moving it is only new bitplane pointers (and the fine
; scroll across): vertically 640 lines of 40 bytes - 64 spare lines, the picture
; at line 64 and again at 320, 64 spare; across 384 lines of 96 bytes - 64 spare
; lines, then lines of 8 spare bytes, the picture at byte 8 and again at 48, 8
; spare. The spare edges take BOBs that are partly off the screen.
SC_DIR      equ 0          ; the way the player flies: 1 up (the picture moves down), 2 right,
                           ; 3 down, 4 left
SC_SPEED    equ 2          ; quarter pixels a frame, 1..16
SC_BUF      equ 4          ; long offset: the buffers (cleared memory after the data), SC_NBUF of
                           ; depth x SCR_PLV (up / down) or SCR_PLH (across) + 16 bytes each
SC_NBUF     equ 8          ; 1, or 3 with BOBs: two displays and the background they are wiped from
SC_MAP      equ 12         ; long offset: a map that scrolls past once (MP_*; flying up), 0 = the
                           ; picture loops (version 10)
SC_SIZE     equ 16
SCR_PLV     equ 25600      ; bytes per plane of a scroll buffer: 640 lines x 40 (up / down)
SCR_PLH     equ 36864      ;                                     384 lines x 96 (across)
SCR_MARG    equ 64         ; spare pixels / lines before the first copy of the picture

; scrolling map (version 10, flying up): MP_COLS tiles of 16 x 16 across (12..20, even; the
; play area, in the middle of the screen - the sides stay black, so there is less to fetch
; and draw) and MP_H down. It scrolls past once, from its bottom to its top, then stops
; (WHEN 15: the boss). Each map line is drawn as it comes into view: map line y goes to ring
; line y & 255 of the picture, in both copies, in every scroll buffer (lines MP_COLS x 2
; bytes). Actor x is across the play area (0 = its left edge). Spawners bring the waves on.
MP_H        equ 0          ; rows of tiles (at least 16)
MP_NT       equ 2          ; tile pictures
MP_IMG      equ 4          ; long offset: NT x depth planes x 16 lines x 2 bytes
MP_MAP      equ 8          ; long offset: H x COLS cells (bytes, or words: MP_FLAGS), the top row first
MP_NSP      equ 12         ; spawners
MP_FLAGS    equ 14         ; bit 0 = map cells are words (more than 256 tiles), else bytes
MP_SP       equ 16         ; long offset: NSP x SP_SIZE, in the order they go off
MP_COLS     equ 20         ; tiles across: the play area (12..20, even)
MP_SIZE     equ 24
SP_TRIG     equ 0          ; it goes off when the view's top (map pixel line) reaches this
SP_X        equ 2          ; where the first one starts on the screen
SP_Y        equ 4
SP_ACT      equ 6          ; the actor (its copies come out in turn)
SP_N        equ 8          ; how many, one after another
SP_GAP      equ 10         ; frames between them
SP_PAT      equ 12         ; byte: flight pattern 0..5, $ff = the actor's own
SP_EDGE     equ 13         ; byte: the edge it comes in from, 0 top 1 right 2 bottom 3 left
SP_DX       equ 14         ; each next one starts this many pixels further along its edge
SP_SIZE     equ 16
SPQ_MAX     equ 8          ; waves going out at once

; custom HUD (UI_*): a panel strip of ROWS text rows at the top or bottom, its
; picture (the backdrop with the panel frame baked in), a font and the fields
UI_FLAGS    equ 0          ; bit 0 on, bit 1 at the bottom (the top in a tile world)
UI_ROWS     equ 2          ; height in text rows (8 lines each), 1..6
UI_NF       equ 4          ; number of fields
UI_FONT     equ 8          ; long offset: 64 x 8 bytes font (characters 32..95), 0 = the built-in one
UI_PANEL    equ 12         ; long offset: panel picture, depth planes x ROWS x 8 lines x 40 bytes, 0 = none
UI_FIELDS   equ 16         ; NF x 32 bytes (F_*)
F_TYPE      equ 0          ; 0 text, 1 score, 2 lives, 3 goal, 4 tile carried, 5 level, 6 tool
F_COL       equ 2          ; text column 0..39
F_ROW       equ 4          ; row in the panel
F_COLOUR    equ 6
F_SHADOW    equ 8          ; shadow colour (down and right one pixel), -1 = none
F_DIGITS    equ 10         ; digits of the number
F_LABEL     equ 12         ; 20 bytes: label before the value, or the text (0 ends it)
F_SIZE      equ 32

; tile world (version 6): a map of 16 x 16 tiles that scrolls both ways
; behind the actors, with a HUD strip at the top of the screen
T_W         equ 0          ; map width in tiles (at least T_NCOL)
T_H         equ 2          ; map height in tiles (at least T_NROW)
T_NT        equ 4          ; tile types 1..512 (tile 0 is empty air: colour 0, the sky shows)
T_FLAGS     equ 6          ; bit 0 = the player digs (fire + direction) and places tiles (fire);
                           ; bit 1 = map cells are words (more than 256 tile types), else bytes
T_IMG       equ 8          ; long offset: tile pictures, NT x depth planes x S lines x S/8 bytes
T_MAP       equ 12         ; long offset: the map as designed, W x H cells
T_WMAP      equ 16         ; long offset: the map as played (memory cleared at load, after the data)
T_BUF       equ 20         ; long offset: the scrolling picture, depth planes (cleared memory)
T_BUFPL     equ 24         ; long: bytes per plane of the scrolling picture (2 x T_RING)
T_SIZE      equ 28         ; tile size S in pixels: 8, 16, 32 or 64
T_SHIFT     equ 30         ; log2 S: 3..6
T_LINE      equ 32         ; bytes per line of the scrolling picture: NCOL x S / 8
T_NCOL      equ 34         ; tiles across the scrolling picture: 320 / S + 2
T_NROW      equ 36         ; tiles down it: 256 / S + 2
T_NTOOL     equ 38         ; tools in the space bar menu, 0 = none (fire + direction digs, fire places)
T_RING      equ 40         ; long: NROW x S x LINE - the picture is a ring this big, kept twice
T_PROPS     equ 44         ; NT x 8 bytes (TP_*), then NT x 4 bytes of names for the HUD,
                           ; then NTOOL x 12 bytes of tools (TL_*)
TL_ACT      equ 0          ; byte: flags - bit 0 = Auto (a weapon swings by itself at whatever it may strike)
                           ; byte +1: what fire does: 0 dig (pickaxe), 1 build with the tile carried (hammer),
                           ; 2 put tile TL_TILE where the player stands (ladder, torch), 3 weapon (sword)
TL_TILE     equ 2          ; the tile it puts down; a weapon: its reach in pixels
TL_NAME     equ 4          ; 8 bytes, 0 ends it early
TL_SIZE     equ 12
TP_FLAGS    equ 0          ; byte: bit 0 solid, bit 1 can be dug, bit 2 counts towards the level goal,
                           ; bit 3 ladder (a platform player climbs it)
TP_SOUND    equ 1          ; byte: sound 0..63, $ff = none
TP_HARD     equ 2          ; frames of digging it takes
TP_POINTS   equ 4          ; score for digging it
TP_BECOMES  equ 6          ; the tile left behind when it is dug
HUD_LINES   equ 8          ; the standard HUD strip above a tile world (v_hudlines: the custom one)
;  The scrolling picture is 22 x 18 tiles round the camera. Tile (c, r) is at
;  buf + r * 16 * 44 + (c + 1) * 2: moving right one tile only moves the
;  bitplane pointers on by 2 bytes, and the new column on the right lands on
;  the memory the column that just left on the left used (one line down), so
;  scrolling across the whole map needs only W x 2 bytes more. Moving down
;  works the same way with whole lines. Each step draws one new column or row.

; music table (offsets from data_start like every header long)
M_NSONGS    equ 0          ; word: number of songs 0..4
M_LEVEL     equ 4          ; 10 bytes: song per level, $ff = none (single screen: entry 0)
M_SONGS     equ 16         ; nsongs x { long offset of the MOD bytes, long length }

; actor record
A_X         equ 0
A_Y         equ 2
A_ROLE      equ 4
A_SPD       equ 6
A_VIS       equ 8
A_LEFT      equ 10
A_UP        equ 12         ; a shot (role 9): its aim - 0 the way the shooter goes, 1 up, 2 down,
                           ; 3 left, 4 right, 5 at the player, 6 a homing missile (seeks the
                           ; nearest thing it can hit; the player fires v_miss of them)
A_BX0       equ 14
A_BY0       equ 16
A_BX1       equ 18
A_BY1       equ 20
A_SPR       equ 22         ; long offset of this actor's hardware sprite block
A_CHAN      equ 26         ; hardware sprite channel 0..7 (colour pair = channel / 2)
A_SPR2      equ 28         ; long offset of a hopper's crouch frame, 0 = none
A_CARRY     equ 32         ; 1 = the player can pick it up (fire) and throw it (fire again)
A_AMODE     equ 34         ; animation flags: bit 0 = 8 directions (table has 12 entries),
                           ; bit 1 = Fire animations for the player (table has 21 entries),
                           ; bit 2 = Hit and Die: two more entries after those (DO 26)
A_FROM      equ 36         ; first level this actor appears on (1..10)
A_FAST      equ 38         ; +1 speed every N levels, 0 = never
A_BOB       equ 40         ; 1 = BOB: A_SPR / A_SPR2 / frames are BOB images, A_CHAN is unused
A_XMAX      equ 42         ; furthest right it goes: 320 - width
A_YMAX      equ 44         ; furthest down it goes: 256 - height
A_BSIZE     equ 46         ; BOB: BLTSIZE (height << 6) | (width in words + 1), 0 for a sprite
A_ANIM      equ 48         ; long offset of the animation table, 0 = one frame (A_SPR)
A_PAT       equ 52         ; a flyer (role 10): 0 straight, 1 wave, 2 zigzag, 3 homes in on the player,
                           ; 4 moves with the scenery, 5 flies in to its place, then patrols across (a boss)
A_ENTER     equ 54         ; a flyer: byte +1 = the edge it comes in from: 0 top, 1 right, 2 bottom, 3 left;
                           ; byte 0 bit 0 = it comes back in when it has flown off the far edge
A_HP        equ 56         ; hits a shot needs to destroy it (1 = one); until then it flashes and WHEN 11 waits
A_RANK      equ 58         ; an option (role 11): 1 = the first behind the player, 2 the next ...
A_TYPE      equ 60         ; the first of its copies (itself when it has none). Rules, spawners and
                           ; shots name the first; a rule acts on the copy that made it fire (v10)
A_FIRE      equ 62         ; the shot it fires by itself, -1 = none
A_FRATE     equ 64         ; frames between its volleys
A_FPAT      equ 66         ; its volley: 0 the shot's own aim, 1 at the player, 2 three at the
                           ; player, 3 a ring of 8, 4 three fanned the shot's own way
ACT_SIZE    equ 68

; animation table (data block version 8; version 5 introduced animations): 4 entries - 0 Idle (standing still),
; 1 Walk (moving), 2 Jump (in the air going up), 3 Fall (in the air coming
; down; Jump and Fall only for platform players, hoppers and fallers). ADAM
; fills empty animations in from the others, so every entry has 1..16 frames.
; With 8 directions (A_AMODE bit 0) 8 more follow: 4 N, 5 NE, 6 E, 7 SE, 8 S,
; 9 SW, 10 W, 11 NW, used instead of Walk; ADAM bakes any turning round into
; their frames. An entry with mode 3 ('stand facing') shows frame 1 of the
; direction the actor last moved in.
; With Fire animations (A_AMODE bit 1) 9 more follow: 12 Fire (no direction),
; 13..20 Fire + N .. NW. While the player holds fire they are picked from the
; joystick direction instead of the movement (digging, shooting, swinging).
AN_N        equ 0          ; number of frames 1..16
AN_RATE     equ 2          ; 50ths of a second per frame (2..30)
AN_MODE     equ 4          ; 0 = loop, 1 = once (stays on the last), 2 = ping-pong, 3 = stand facing (8 directions)
AN_RIGHT    equ 8          ; 16 longs: frame offsets facing right
AN_LEFT     equ 72         ; 16 longs: facing left (the same frames when not flipped)
ANIM_SIZE   equ 136

; BOB image (ADAM Pro): 16, 32, 48 or 64 pixels wide (w words) and h lines -
; w x h mask words, then depth x w x h words of bitplanes

; rule record
R_WHEN      equ 0
R_A         equ 2
R_B         equ 4
R_N         equ 6
R_ACT       equ 8
R_TGT       equ 10
R_VAL       equ 12
R_NAND      equ 14         ; AND DO lines that follow this rule (8 bytes each: act, target, value, 0)
RULE_SIZE   equ 16
AND_SIZE    equ 8
RULES_MAX   equ 128        ; rules (cards) on the disk - one latch each

; game block (levels, goal, title)
G_NLEVELS   equ 0          ; number of levels, 0 = no levels
G_TERRAIN   equ 2          ; 1 = draw the hills from the height maps
G_COLS      equ 4          ; 4 words: edge, grass, soil, speck colour
G_GOAL      equ 12         ; things to collect per level, 0 = no goal counter
G_TITLE     equ 14         ; 1 = title screen
G_LABEL     equ 16         ; 8 bytes, e.g. "GEMS"
G_TITLE1    equ 24         ; 40 bytes, big title line
G_TITLE2    equ 64         ; 40 bytes, small line under it
G_LEVTXT    equ 104        ; 16 bytes, e.g. "LEVEL"
G_HEIGHTS   equ 120        ; nlevels x 320 words

PLANE_SIZE  equ 10240      ; 320 x 256 / 8
SPR_H       equ 24
SFX_PERIOD  equ 322        ; ~11015 Hz on PAL
SCORE_MAX   equ 99999
GRAVITY     equ 4          ; 1/16 pixel per frame per frame
MAX_FALL    equ 96
JUMP_V      equ 59         ; platform player jump speed (1/16 px)
HOP_SQUAT   equ 14         ; frames a hopper crouches before it jumps
HOP_JUMP    equ 52         ; hopper jump speed (+8 per speed step)
HOP_GRAVITY equ 2
SAFE_TIME   equ 150        ; 3 seconds of flashing immunity
MOMENT      equ 25         ; 'show for a moment' = half a second
SWING_TIME  equ 14         ; a weapon swing lasts this many frames
SWING_COOL  equ 22         ; and the next can start this many frames after it began
THROW_VX    equ 4          ; a throw: pixels a frame across
THROW_VY    equ 44         ; and up (1/16 pixels a frame), then gravity brings it down
HIT_MAX     equ 8          ; thrown-actor and shot hits remembered in a frame (WHEN 11)
ROLE_SHOT   equ 9          ; a shot: hidden until a Shoot rule fires it, flies straight, hides when it
                           ; hits something or leaves the screen
SHOT_FLY    equ 3          ; v_thr of a shot in flight
ROLE_FLY    equ 10         ; a flyer: comes in from an edge and flies across the screen (shoot 'em up waves)
ROLE_OPT    equ 11         ; an option (multiple): hidden until a Power up rule adds it, then it follows
                           ; the player's trail and fires a shot whenever the player does
ROLE_FX     equ 12         ; an effect: hidden until DO 24 sets it off, plays its Idle animation once
                           ; where it was set off, then hides (explosions, sparks)
OPT_GAP     equ 10         ; trail steps between the player and each option
POWER_MAX   equ 3          ; firepower 0 one shot, 1 two side by side, 2 three spread, 3 four
HIT_FLASH   equ 8          ; frames a tough actor flashes white when a shot hits it
MISS_MAX    equ 2          ; homing missiles the player can fire at once

; ---------------- engine variables (offsets from V) ----------------
; Per-actor state is one ACTV_SIZE record per actor, starting at V. a5 =
; V+128, so a field is v_xx(a5,Dn) with Dn = actor * ACTV_SIZE (actor << ACTV_SHIFT):
; the field offsets (-128..-1) fit the signed 8-bit displacement and the
; index register carries the actor. Scalars follow the MAX_ACT records.
MAX_ACT     equ 32
ACTV_SIZE   equ 128
ACTV_SHIFT  equ 7
            rsset   -128
v_ax        rs.w 1
v_ay        rs.w 1
v_spd       rs.w 1
v_vis       rs.w 1
v_dx        rs.w 1
v_dy        rs.w 1
v_px        rs.w 1
v_py        rs.w 1
v_vy        rs.w 1         ; vertical speed in 1/16 pixels per frame
v_ysub      rs.w 1
v_tmr       rs.w 1
v_gnd       rs.w 1         ; 1 = standing on the ground
v_squat     rs.w 1         ; hopper squat countdown before a jump
v_life      rs.w 1         ; frames until a 'shown for a moment' actor hides
v_safe      rs.w 1         ; frames of flashing immunity left
v_fofs      rs.l 1         ; offset of the frame shown now (bob_draw draws it)
v_aset      rs.w 1         ; animation playing: 0 Idle, 1 Walk, 2 Jump, 3 Fall, -1 = none yet
v_astart    rs.w 1         ; v_anim when it started
v_face      rs.w 1         ; 1 = facing left
v_dir       rs.w 1         ; 8 directions: last direction moved, 0 N .. 7 NW
v_ox        rs.w 1         ; where it was at the start of this frame (tile walls)
v_oy        rs.w 1
v_thr       rs.w 1         ; thrown: 0 no, 1 flying, 2 flying but spent (it hit something), 3 a shot flying
v_tvx       rs.w 1         ; thrown: pixels a frame across
v_tvy       rs.w 1         ; a shot: pixels a frame down
v_owner     rs.w 1         ; a shot: the actor that fired it (it never hits that one)
v_pool      rs.w 1         ; a shot: the actor the Shoot rule names (WHEN 11 hits report this one)
v_mdx       rs.w 1         ; the way it last moved: -1 / 0 / 1 across (a shot's aim 0)
v_mdy       rs.w 1         ;                        -1 / 0 / 1 down
v_base      rs.w 1         ; a flyer: the line across it weaves round (wave), where it came in
v_hp        rs.w 1         ; shot hits it can still take (A_HP)
v_hitf      rs.w 1         ; frames of the white hit flash left
v_spd0      rs.w 1         ; its speed at the level start (the player: before speed power-ups)
v_pat       rs.w 1         ; a flyer: its pattern (A_PAT, or its spawner's)
v_edge      rs.w 1         ; a flyer: byte +1 its edge, bit 8 = it comes back (A_ENTER, or its spawner's)
v_ftmr      rs.w 1         ; frames until it fires by itself again
v_xsub      rs.w 1         ; a shot: 1/16 pixels owed across (v_ysub: down)
v_aplay     rs.w 1         ; DO 26: playing Hit (0) or Die (1) once, -1 = none
v_aendk     rs.w 1         ; which one it finished (WHEN 16)
v_ael       rs.w 1         ; its animation: 50ths counted since it started (place_sprites)
v_arem      rs.w 1         ;   50ths into this step
v_astep     rs.w 1         ;   steps since it started
v_afr       rs.w 1         ;   steps into its cycle (loop: n, ping-pong: 2n - 2)
            rsset   -128+MAX_ACT*ACTV_SIZE
v_anim      rs.w 1
v_joyprev   rs.w 1
v_jumped    rs.l 1         ; bit per actor that jumped this frame
v_aended    rs.l 1         ; bit per actor that finished its Hit / Die this frame (WHEN 16)
v_level     rs.w 1         ; 1..10
v_goal      rs.w 1
v_work      rs.l 1
v_game      rs.l 1         ; game block address, 0 = none
v_text      rs.b 32
v_gradfix   rs.w 1
v_joy       rs.w 1
v_fcount    rs.w 1
v_sectick   rs.w 1
v_lives     rs.w 1
v_score     rs.l 1
v_flash     rs.w 1
v_bg        rs.l 1
v_pfade     rs.w 1         ; palette fade: frames left, 0 = none
v_pftot     rs.w 1         ; and how many it takes
v_cophold   rs.w 1         ; setcol: the caller holds the copper (AGA with a copper sky)
v_d2song    rs.w 1         ; disk 2: the song in the buffer, -1 = none
v_d2drv     rs.w 1         ; the drive disk 2 was last found in, -1 = not yet
v_dcyl      rs.w 4         ; each drive's head: cylinder, -1 = not known
v_curpal    rs.l PAL_FADE  ; the backdrop colours shown now
v_frompal   rs.l PAL_FADE  ; a fade goes from these ...
v_tgtpal    rs.l PAL_FADE  ; ... to these
v_rand      rs.l 1
v_music     rs.l 1         ; music table address, 0 = no music
v_song      rs.w 1         ; song playing, -1 = none
v_sfx       rs.b 12        ; ptplayer sfx structure: ptr.l len.w per.w vol.w cha.b pri.b
v_disp      rs.l 1
v_digits    rs.b 8
v_opaque    rs.w 1
v_font      rs.l 1         ; the font text is drawn with
v_shadow    rs.w 1         ; shadow colour of the text drawn now, -1 = none
v_ui        rs.l 1         ; custom HUD block, 0 = the standard HUD
v_hudrow0   rs.w 1         ; text row of the HUD on the normal display
v_hudlines  rs.w 1         ; lines of the HUD strip above a tile world
v_latch     rs.w RULES_MAX
v_disp2     rs.l 1         ; BOBs: second display buffer, 0 = no BOBs (one display, v_disp)
v_back      rs.l 1         ; BOBs: backdrop + hills + HUD, copied back where a BOB was
v_dd2       rs.l 1         ; v_disp2 - v_disp (0 without BOBs): text goes to both displays
v_ddk       rs.l 1         ; v_back - v_disp  (0 without BOBs): and into the background
v_draw      rs.l 1         ; BOBs: the display being drawn (not on screen)
v_bobbuf    rs.w 1         ; 0 = v_draw is v_disp, 1 = v_disp2
v_drawn     rs.w 1         ; 1 = v_draw is ready to show
v_bobn      rs.w 2         ; BOBs drawn into each display
v_bobold    rs.w 4*MAX_ACT ; where they were (byte offset in a plane, BLTSIZE), to wipe them
v_tiles     rs.l 1         ; tile world block, 0 = none
v_wmap      rs.l 1         ; the map as played
v_tbuf      rs.l 1         ; scrolling picture, plane 0
v_tbufpl    rs.l 1         ; bytes per plane of it
v_timg      rs.l 1         ; tile pictures
v_tbytes    rs.w 1         ; bytes per tile picture (depth x S x S / 8)
v_tsz       rs.w 1         ; tile size S (8, 16, 32, 64)
v_tsh       rs.w 1         ; log2 S
v_tline     rs.w 1         ; bytes per line of the scrolling picture
v_tncol     rs.w 1         ; tiles across it
v_tnrow     rs.w 1         ; tiles down it
v_tring     rs.w 1         ; its ring size in bytes (one copy)
v_tcell     rs.w 1         ; 1 when map cells are words
v_tw        rs.w 1
v_th        rs.w 1
v_camx      rs.w 1         ; camera: map pixel at the top left of the screen
v_camy      rs.w 1
v_tx0       rs.w 1         ; tiles drawn in the scrolling picture: NCOL x NROW from here
v_ty0       rs.w 1
v_tmode     rs.w 1         ; 1 while the tile world is on screen
v_csplit    rs.l 1         ; copper moves at the HUD split (bitplane pointers, modulos, scroll)
v_hudrow    rs.w 1         ; text row of the HUD
v_sel       rs.w 1         ; tile the player places (the last one dug)
v_digt      rs.w 1         ; frames spent digging v_digc
v_digc      rs.l 1         ; map cell being dug, -1 = none
v_inv       rs.w 512       ; tiles the player carries
v_key       rs.w 1         ; key pressed this frame: $100 + raw key code, 0 = none
v_tool      rs.w 1         ; tool in use (T_NTOOL > 0)
v_menu      rs.w 1         ; 1 while the tool menu is open (the game waits)
v_msel      rs.w 1         ; tool picked in the menu
v_fwait     rs.w 1         ; 1 = fire chose a tool: it does nothing until let go
v_swing     rs.w 1         ; frames of the player's weapon swing left (Fire animation)
v_swcool    rs.w 1         ; frames until the weapon can swing again
v_struck    rs.l 1         ; bit per actor the player's weapon struck this frame (WHEN 10)
v_sbox      rs.w 4         ; the swing's reach: left, right, top, bottom (map pixels)
v_carry     rs.w 1         ; actor the player carries, -1 = none
v_picked    rs.w 1         ; actor picked up this frame, -1 = none (WHEN 12)
v_hitn      rs.w 1         ; thrown-actor hits this frame
v_hits      rs.b 2*HIT_MAX ; each: thrown actor, actor it hit
v_hitmask   rs.l MAX_ACT   ; per shot actor: bit per actor a WHEN 11 rule names it hitting (0 = any)
v_sblk      rs.l 1         ; scrolling backdrop block, 0 = none
v_scr       rs.w 1         ; the way it scrolls now (SC_DIR), 0 = not scrolling
v_sacc      rs.w 1         ; quarter pixels owed
v_spos      rs.w 1         ; the view's place in the picture: 0..255 down / 0..319 across
v_dpos      rs.w 1         ; BOBs: v_spos when v_draw was drawn (bob_flip shows it there)
v_sdx       rs.w 1         ; how far the scenery moved this frame, across
v_sdy       rs.w 1         ;                                       down
v_sbuf      rs.l 1         ; first scroll buffer
v_shbuf     rs.l 1         ; the buffer the split shows, and where (scroll_show)
v_shpos     rs.w 1
v_aimx      rs.w 1         ; act_shoot: the way the volley flies, -1 / 0 / 1 across
v_aimy      rs.w 1         ;                                              down
v_vside     rs.w 1         ; shoot_one: pixels to the side of the aim it starts
v_vspr      rs.w 1         ;            -1 / 0 / 1: it veers to that side (spread)
v_bstep     rs.l 1         ; bob_draw: bytes from one image plane to the next
v_bcon      rs.w 1         ;           the BOB's shift (BLTCON0 bits 15-12)
v_bflash    rs.w 1         ;           hit flash: BLTCON0 for the next plane, 0 = none
v_sstride   rs.l 1         ; bytes from one scroll buffer to the next
v_split     rs.w 1         ; 1 = the copper switches bitplanes under the HUD strip (tile world, scrolling)
v_smod      rs.w 1         ; the modulo below the split
v_bob       rs.w 1         ; 1 = BOBs are drawn now
v_bufa      rs.l 1         ; BOBs: the two displays taken in turn
v_bufb      rs.l 1
v_bpr       rs.w 1         ; BOB displays: bytes per line
v_plsz      rs.l 1         ;               bytes per plane
v_bx0       rs.w 1         ; pixel in the BOB display at the screen's top left (scrolling)
v_by0       rs.w 1
v_ltime     rs.w 1         ; seconds since the level started (WHEN 13)
v_power     rs.w 1         ; firepower 0..POWER_MAX (kept from level to level)
v_pspd      rs.w 1         ; speed power-ups the player has
v_nopt      rs.w 1         ; options the player has
v_trn       rs.w 1         ; the player's trail: the newest entry
v_trail     rs.l 64        ; x, y words
v_map       rs.l 1         ; scrolling map block, 0 = none
v_mimg      rs.l 1         ; its tile pictures
v_mmap      rs.l 1         ; its map
v_tbm       rs.w 1         ; bytes a tile picture (depth x 32)
v_mword     rs.w 1         ; 1 = map cells are words
v_mcols     rs.w 1         ; the map's tiles across
v_arec      rs.l MAX_ACT   ; each actor's record (actor_rec reads it: no multiply)
v_hbx0      rs.w 1         ; shot_hits: the shot's box
v_hbx1      rs.w 1
v_hby0      rs.w 1
v_hby1      rs.w 1
v_pw        rs.w 1         ; the play area's width in pixels (320, or a map's MP_COLS x 16)
v_xoff      rs.w 1         ; its left edge on the screen (sprites)
v_sbpr      rs.w 1         ; scroll buffers: bytes per line
v_splsz     rs.l 1         ;                 bytes per plane
v_ddfs      rs.w 1         ; a narrow map: DDFSTRT / DDFSTOP under the HUD split (0 = full width)
v_ddfe      rs.w 1
v_spn       rs.w 1         ; the next spawner to go off
v_spq       rs.l 2*SPQ_MAX ; waves going out: spawner address, then words left, frames to the next
v_mend      rs.w 1         ; 1 = the map has scrolled to its top (WHEN 15)
v_miss      rs.w 1         ; homing missiles the player fires at once (0..MISS_MAX)
v_aprec     rs.w 1         ; shoot_one: 1 = fly v_avx / v_avy, not v_aimx / v_aimy
v_avx       rs.w 1         ;            1/16 pixels a frame across
v_avy       rs.w 1         ;                                down
v_rta       rs.w 1         ; the rule firing: its actors a / b
v_rtb       rs.w 1
v_cta       rs.w 1         ; the copies of them that made it fire, -1 = none
v_ctb       rs.w 1
v_spalt     rs.w 1         ; DO 25: the way the next one breaks off
v_items     rs.l 1         ; items block, 0 = none
v_icnt      rs.w ITEM_MAX  ; how many of each item the player carries
v_iuse      rs.w ITEM_MAX  ; uses left on the one in use (IT_USE 2)
v_igot      rs.w 1         ; bit per item the player got this frame
v_igotp     rs.w 1         ; ... last frame (WHEN 17 sees these)
v_useit     rs.w 1         ; item picked in the space bar menu to use (WHEN 18), -1 = none
v_uspent    rs.w 1         ; 1 = that use has been spent (one WHEN 18 rule spends it)
v_mn        rs.w 1         ; space bar menu entries
v_ment      rs.b 2*MENU_MAX ; each: kind (0 tool, 1 item, 2 recipe), number
V_SIZE      rs.b 0

; ============================================================================
; Entered from the bootblock in user mode with the OS still running.
start:
            move.l  4.w,a6                  ; ExecBase
            moveq   #0,d0                   ; vector base: 0 on a 68000
            btst    #0,297(a6)              ; AttnFlags AFF_68010 (set on 68010 and up)
            beq.s   .vbr
            lea     get_vbr(pc),a5
            jsr     -30(a6)                 ; Supervisor(get_vbr) -> d0 = VBR
.vbr        move.l  d0,d7
            moveq   #0,d6                   ; CIA timers: NTSC clock unless PAL
            cmp.b   #50,530(a6)             ; VBlankFrequency
            bne.s   .ntsc
            moveq   #1,d6
.ntsc       lea     in_super(pc),a5
            jsr     -30(a6)                 ; Supervisor(in_super) - never returns

; d0 = VBR (68010 and up only - runs in supervisor mode)
get_vbr:    dc.l    $4e7a0801               ; movec vbr,d0
            rte

; Supervisor mode from here on. The OS is never returned to, so the
; exception frame Supervisor() left on the system stack is simply dropped.
in_super:   move.w  #$2700,sr               ; mask all CPU interrupts while taking over
            lea     start(pc),a5            ; (V is too far for a PC-relative lea)
            add.l   #V+128-start,a5
            lea     -128(a5),a7
            add.l   #stack_top-V,a7
            lea     -128(a5),a4
            add.l   #data_start-V,a4
            lea     $dff000,a6
            move.w  #$7fff,$9a(a6)          ; INTENA  - all interrupts off
            move.w  #$7fff,$9c(a6)          ; INTREQ  - clear pending
            move.w  #$7fff,$96(a6)          ; DMACON  - all DMA off
            clr.l   $0.w                    ; idle word for ptplayer (NULL_IS_CLEARED)
            move.l  #$2a5b7c19,v_rand(a5)
            move.l  d7,a0                   ; VBR
            move.l  d6,d0                   ; PAL flag
            bsr     _mt_install             ; level 6 vector, CIA-B timers A and B
            move.w  #$c000,$9a(a6)          ; INTENA master on (only EXTER is enabled)
            move.w  #$2000,sr               ; supervisor, CPU interrupts allowed
            bsr     init_music
            bsr     disk2_init
            bsr     init_display
            bsr     hit_masks

game_restart:
            lea     -128(a5),a7             ; a5 = V+128 (stack_top is too far for a PC-relative lea)
            add.l   #stack_top-V,a7
            bsr     music_stop              ; silence: music and effects
            move.w  #1,v_level(a5)
            bsr     init_palette
            bsr     clear_state
            bsr     items_reset             ; what the player carries at the start
            move.l  #0,v_score(a5)
            move.w  H_LIVES(a4),v_lives(a5)
            move.w  #0,v_power(a5)          ; a new game: no power-ups
            move.w  #0,v_pspd(a5)
            move.w  #0,v_nopt(a5)
            move.w  #0,v_miss(a5)
            bsr     scroll_off
            bsr     tiles_off
            bsr     hide_sprites
            bsr     restore_backdrop
            move.l  v_game(a5),d0           ; title screen
            beq.s   .notitle
            move.l  d0,a0
            tst.w   G_TITLE(a0)
            beq.s   .notitle
            lea     G_TITLE1(a0),a0
            moveq   #72,d2
            bsr     big_text
            move.l  v_game(a5),a0
            lea     G_TITLE2(a0),a0
            moveq   #16,d2
            bsr     centre_text
            bsr     wait_fire
.notitle    moveq   #5,d0                   ; 'the game starts' rules
            bsr     run_when_rules
            bra.s   level_card

; next level: show which one is coming, then play it
level_next: addq.w  #1,v_level(a5)
            bsr     items_level             ; items not kept on the next level are gone
level_card: lea     -128(a5),a7             ; a5 = V+128 (stack_top is too far for a PC-relative lea)
            add.l   #stack_top-V,a7
            bsr     scroll_off
            bsr     tiles_off
            bsr     hide_sprites
            bsr     restore_backdrop
            bsr     level_disk2             ; this level's song from disk 2, if it lives there
            move.l  v_game(a5),d0
            beq.s   level_start
            move.l  d0,a0
            cmp.w   #2,G_NLEVELS(a0)        ; only show cards when there are levels
            blt.s   level_start
            bsr     level_text              ; "LEVEL 3" in big letters
            lea     v_text(a5),a0
            moveq   #88,d2
            bsr     big_text
            lea     str_fire(pc),a0
            moveq   #16,d2
            bsr     centre_text
            bsr     wait_fire
            bsr     restore_backdrop
level_start:
            bsr     level_pal               ; this level's palette, at once
            bsr     init_actors
            bsr     clear_latches
            move.w  #0,v_goal(a5)
            move.w  #0,v_ltime(a5)
            move.w  #-1,v_useit(a5)
            bsr     trail_reset
            bsr     tiles_start
            bsr     scroll_on
            bsr     draw_hud
            bsr     place_sprites
            bsr     level_music             ; this level's song, before its rules
            moveq   #7,d0                   ; 'a level starts' rules
            bsr     run_when_rules
mainloop:
            bsr     wait_vbl
            bsr     frame
            bra     mainloop

; ============================================================================
;  display set-up
; ============================================================================
init_display:
            move.l  H_WORK(a4),d0
            add.l   a4,d0
            move.l  d0,v_work(a5)
            moveq   #0,d0
            move.l  H_GAME(a4),d1
            beq.s   .nog
            move.l  d1,d0
            add.l   a4,d0
.nog        move.l  d0,v_game(a5)
            lea     font(pc),a0                 ; text: the built-in font, no shadow
            move.l  a0,v_font(a5)
            move.w  #-1,v_shadow(a5)
            move.l  #0,v_ui(a5)
            move.w  H_HUDROW(a4),v_hudrow0(a5)
            move.w  #HUD_LINES,v_hudlines(a5)
            move.l  H_UI(a4),d1                 ; custom HUD (ADAM Pro)
            beq.s   .noui
            lea     0(a4,d1.l),a0
            btst    #0,UI_FLAGS+1(a0)
            beq.s   .noui
            move.l  a0,v_ui(a5)
            move.l  UI_FONT(a0),d1
            beq.s   .uif
            add.l   a4,d1
            move.l  d1,v_font(a5)
.uif        move.w  UI_ROWS(a0),d1
            lsl.w   #3,d1
            move.w  d1,v_hudlines(a5)
            move.w  #0,v_hudrow0(a5)
            btst    #1,UI_FLAGS+1(a0)
            beq.s   .noui
            moveq   #32,d1
            sub.w   UI_ROWS(a0),d1
            move.w  d1,v_hudrow0(a5)
.noui       move.l  #0,v_tiles(a5)          ; tile world
            move.w  #0,v_tmode(a5)
            move.w  v_hudrow0(a5),v_hudrow(a5)
            move.l  H_TILES(a4),d1
            beq.s   .notile
            lea     0(a4,d1.l),a0
            move.l  a0,v_tiles(a5)
            move.w  T_W(a0),v_tw(a5)
            move.w  T_H(a0),v_th(a5)
            move.l  T_IMG(a0),d1
            add.l   a4,d1
            move.l  d1,v_timg(a5)
            move.l  T_WMAP(a0),d1
            add.l   a4,d1
            move.l  d1,v_wmap(a5)
            move.l  T_BUF(a0),d1
            add.l   a4,d1
            move.l  d1,v_tbuf(a5)
            move.l  T_BUFPL(a0),v_tbufpl(a5)
            move.w  T_SIZE(a0),v_tsz(a5)
            move.w  T_SHIFT(a0),d2
            move.w  d2,v_tsh(a5)
            move.w  T_LINE(a0),v_tline(a5)
            move.w  T_NCOL(a0),v_tncol(a5)
            move.w  T_NROW(a0),v_tnrow(a5)
            move.w  T_RING+2(a0),v_tring(a5)
            moveq   #0,d1
            btst    #1,T_FLAGS+1(a0)
            beq.s   .tc1
            moveq   #1,d1
.tc1        move.w  d1,v_tcell(a5)
            move.w  H_DEPTH(a4),d1          ; depth x S x S / 8 bytes a tile
            add.w   d2,d2
            subq.w  #3,d2
            lsl.w   d2,d1
            move.w  d1,v_tbytes(a5)
.notile
            move.l  H_DISP(a4),d0
            add.l   a4,d0
            move.l  d0,v_disp(a5)
            move.l  d0,v_draw(a5)
            moveq   #0,d1                   ; BOBs: second display and background
            moveq   #0,d2
            move.l  #0,v_disp2(a5)
            move.l  #0,v_back(a5)
            move.l  H_DISP2(a4),d3
            beq.s   .nobob
            move.l  H_BACK(a4),d4
            beq.s   .nobob
            add.l   a4,d3
            add.l   a4,d4
            move.l  d3,v_disp2(a5)
            move.l  d4,v_back(a5)
            move.l  d3,d1
            sub.l   d0,d1
            move.l  d4,d2
            sub.l   d0,d2
.nobob      move.l  d1,v_dd2(a5)
            move.l  d2,v_ddk(a5)
            bsr     set_bpl                 ; bitplane pointers
            bsr     bob_plain               ; BOBs (if any) in the normal display
            move.w  #0,v_split(a5)
            move.w  #0,v_scr(a5)
            move.w  #320,v_pw(a5)           ; the play area: the whole screen
            move.w  #0,v_xoff(a5)
            move.w  #0,v_ddfs(a5)
            move.l  #0,v_sblk(a5)           ; scrolling backdrop
            move.l  #0,v_map(a5)
            move.l  H_SCROLL(a4),d1
            beq     .nosc
            lea     0(a4,d1.l),a0
            move.l  a0,v_sblk(a5)
            move.l  SC_BUF(a0),d1
            add.l   a4,d1
            move.l  d1,v_sbuf(a5)
            move.w  #SCR_PLV,d2             ; a buffer: depth planes + 16 spare bytes
            move.w  #40,v_sbpr(a5)
            btst    #0,SC_DIR+1(a0)
            bne.s   .plv
            move.w  #SCR_PLH,d2
            move.w  #96,v_sbpr(a5)
.plv        move.l  SC_MAP(a0),d1           ; a map: lines of MP_COLS words
            beq.s   .pls
            move.w  MP_COLS(a4,d1.l),d2
            add.w   d2,d2
            move.w  d2,v_sbpr(a5)
            mulu    #640,d2
.pls        and.l   #$ffff,d2
            move.l  d2,v_splsz(a5)
            move.w  H_DEPTH(a4),d1
            mulu    d2,d1
            add.l   #16,d1
            move.l  d1,v_sstride(a5)
            move.l  SC_MAP(a0),d1           ; a map that scrolls past
            beq.s   .nosc
            lea     0(a4,d1.l),a1
            move.l  a1,v_map(a5)
            move.w  MP_COLS(a1),v_mcols(a5)
            move.l  MP_IMG(a1),d1
            add.l   a4,d1
            move.l  d1,v_mimg(a5)
            move.l  MP_MAP(a1),d1
            add.l   a4,d1
            move.l  d1,v_mmap(a5)
            moveq   #1,d1
            and.w   MP_FLAGS(a1),d1
            move.w  d1,v_mword(a5)
            move.w  H_DEPTH(a4),d1
            lsl.w   #5,d1
            move.w  d1,v_tbm(a5)
.nosc

            lea     cop_spr-V-128(a5),a0          ; sprite pointers: all null first
            lea     null_spr-V-128(a5),a1
            move.l  a1,d0
            swap    d0
            moveq   #7,d7
.null       move.w  d0,2(a0)
            swap    d0
            move.w  d0,6(a0)
            swap    d0
            addq.l  #8,a0
            dbf     d7,.null
            move.w  H_NACT(a4),d6           ; then each actor on its channel
            beq.s   .sprdone
            subq.w  #1,d6
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
.spr        tst.w   A_BOB(a2)               ; BOBs use no sprite channel
            bne.s   .sprnx
            lea     cop_spr-V-128(a5),a0
            move.w  A_CHAN(a2),d1
            and.w   #7,d1
            lsl.w   #3,d1
            add.w   d1,a0
            move.l  A_SPR(a2),d0
            add.l   a4,d0
            swap    d0
            move.w  d0,2(a0)
            swap    d0
            move.w  d0,6(a0)
.sprnx      lea     ACT_SIZE(a2),a2
            dbf     d6,.spr
.sprdone
            move.w  #$2c81,$8e(a6)          ; DIWSTRT
            move.w  #$2cc1,$90(a6)          ; DIWSTOP  (320 x 256 PAL)
            move.w  #$0038,$92(a6)          ; DDFSTRT
            move.w  #$00d0,$94(a6)          ; DDFSTOP
            move.w  #$0000,$102(a6)         ; BPLCON1
            move.w  #$0024,$104(a6)         ; BPLCON2  - sprites in front
            move.w  #$0000,$108(a6)         ; BPL1MOD
            move.w  #$0000,$10a(a6)         ; BPL2MOD

            move.w  H_DEPTH(a4),d0          ; BPLCON0
            cmp.w   #8,d0
            bne.s   .not8
            move.w  #$0010,d1               ; 8 planes = BPU3 (AGA)
            bra.s   .bpu
.not8       move.w  d0,d1
            lsl.w   #8,d1
            lsl.w   #4,d1
.bpu        or.w    #$0200,d1               ; COLOR on
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            or.w    #$0001,d1               ; ECSENA for BPLCON3 on AGA
            move.w  d1,$100(a6)
            move.w  #$0003,$1fc(a6)         ; FMODE   - 64-bit bitplane fetch, sprites stay 16 wide
            move.w  #$00b8,$94(a6)          ; DDFSTOP - 5 fetches of 64 pixels
            move.w  #$0224,$104(a6)         ; BPLCON2 - KILLEHB: 6 planes are 64 real colours, not half-brite
            move.w  #$0c00,$106(a6)         ; BPLCON3
            move.w  #$00ff,$10c(a6)         ; BPLCON4 - sprite colours 240-255
            bra.s   .cop
.ocs        move.w  d1,$100(a6)
.cop        lea     copper-V-128(a5),a0
            move.l  a0,$80(a6)              ; COP1LC
            move.w  d0,$88(a6)              ; COPJMP1 strobe
            move.w  #$83e0,$96(a6)          ; DMAEN BPLEN COPEN BLTEN SPREN
            move.w  #$8040,$9c(a6)          ; INTREQ: BLIT set = "no blit running" (see bwait)
            rts

; BOBs in the normal display (not scrolling): the two displays, their background,
; and the text offsets that write the HUD into all three
bob_plain:  movem.l d0-d1,-(sp)
            move.l  v_disp(a5),v_bufa(a5)
            move.l  v_disp2(a5),v_bufb(a5)
            move.w  #0,v_bob(a5)
            moveq   #0,d0
            moveq   #0,d1
            tst.l   v_disp2(a5)
            beq.s   .n
            move.w  #1,v_bob(a5)
            move.l  H_BACK(a4),d0
            add.l   a4,d0
            move.l  d0,v_back(a5)
            sub.l   v_disp(a5),d0
            move.l  v_disp2(a5),d1
            sub.l   v_disp(a5),d1
.n          move.l  d1,v_dd2(a5)
            move.l  d0,v_ddk(a5)
            move.w  #40,v_bpr(a5)
            move.l  #PLANE_SIZE,v_plsz(a5)
            move.w  #0,v_bx0(a5)
            move.w  #0,v_by0(a5)
            movem.l (sp)+,d0-d1
            rts

; d0 = bitplane memory -> copper bitplane pointers
set_bpl:    movem.l d0/d7/a0,-(sp)
            lea     cop_bpl-V-128(a5),a0
            moveq   #7,d7
.b          swap    d0
            move.w  d0,2(a0)
            swap    d0
            move.w  d0,6(a0)
            add.l   #PLANE_SIZE,d0
            addq.l  #8,a0
            dbf     d7,.b
            movem.l (sp)+,d0/d7/a0
            rts

; ============================================================================
;  wait for the bottom of the frame (line 300)
;  Checks 'line 300 or later' rather than 'line 300 exactly': a music
;  interrupt can take longer than one raster line, and must not make the
;  game miss a frame.
; ============================================================================
wait_vbl:
.w1         move.l  $04(a6),d0              ; still at the bottom: wait for the next frame
            and.l   #$1ff00,d0
            cmp.l   #$12c00,d0
            bhs.s   .w1
.w2         move.l  $04(a6),d0              ; then wait for line 300
            and.l   #$1ff00,d0
            cmp.l   #$12c00,d0
            blo.s   .w2
            rts

; ============================================================================
;  game state
; ============================================================================
restore_backdrop:
            bsr     work_fresh              ; backdrop + this level's hills
            bsr     ui_panel_blit           ; the custom HUD panel over them
            move.l  v_work(a5),a0           ; work copy -> screen
            move.l  v_disp(a5),a1
            bsr.s   copy_planes
            tst.l   v_disp2(a5)
            beq.s   .r
            move.l  v_work(a5),a0           ; BOBs: -> background and the second display
            move.l  v_back(a5),a1
            bsr.s   copy_planes
            move.l  v_work(a5),a0
            move.l  v_disp2(a5),a1
            bsr.s   copy_planes
            move.l  #0,v_bobn(a5)           ; nothing to wipe in either display
            move.l  v_disp(a5),d0           ; show the first, draw into the second
            bsr     set_bpl
            move.l  v_disp2(a5),v_draw(a5)
            move.w  #1,v_bobbuf(a5)
            move.w  #0,v_drawn(a5)
.r          rts

; the original backdrop -> the work copy, with this level's hills
work_fresh: move.l  H_PLANES(a4),d0
            lea     0(a4,d0.l),a0
            move.l  v_work(a5),a1
            move.w  H_DEPTH(a4),d7
            mulu    #PLANE_SIZE/4,d7
            subq.l  #1,d7
.cp         move.l  (a0)+,(a1)+
            dbf     d7,.cp
            bra     draw_terrain

; a0 -> a1, depth bitplanes
copy_planes:
            move.w  H_DEPTH(a4),d7
            mulu    #PLANE_SIZE/4,d7
            subq.l  #1,d7
.cp         move.l  (a0)+,(a1)+
            dbf     d7,.cp
            rts

; a0 -> this level's 320 height words (needs a game block with terrain)
level_heights:
            move.l  v_game(a5),a0
            move.w  v_level(a5),d0
            subq.w  #1,d0
            mulu    #640,d0
            lea     G_HEIGHTS(a0,d0.l),a0
            rts

; paints the hills: edge, grass, then soil with specks, down to the bottom
draw_terrain:
            movem.l d0-d7/a0-a3,-(sp)
            move.l  v_game(a5),d0
            beq     .out
            move.l  d0,a3
            tst.w   G_TERRAIN(a3)
            beq     .out
            bsr     level_heights
            move.l  a0,a2                   ; heights
            moveq   #0,d4                   ; column
.col        move.w  (a2)+,d5                ; top of the ground
            cmp.w   #256,d5
            bhs     .ncol
.row        move.w  d5,d6
            sub.w   -2(a2),d6               ; depth below the edge
            move.w  G_COLS(a3),d3           ; edge
            cmp.w   #2,d6
            blt.s   .pix
            move.w  G_COLS+2(a3),d3         ; grass
            cmp.w   #10,d6
            blt.s   .pix
            move.w  G_COLS+4(a3),d3         ; soil, with the odd speck
            move.w  d4,d0                   ; scattered specks: (x*97 + y*57)^2
            mulu    #97,d0
            move.w  d5,d1
            mulu    #57,d1
            add.w   d1,d0
            mulu    d0,d0
            lsr.l   #7,d0
            and.w   #31,d0
            bne.s   .pix
            move.w  G_COLS+6(a3),d3
.pix        move.w  d5,d0                   ; plot (d4, d5) in colour d3
            mulu    #40,d0
            move.w  d4,d1
            lsr.w   #3,d1
            add.w   d1,d0
            move.l  v_work(a5),a1
            add.l   d0,a1
            move.w  d4,d1
            not.w   d1
            and.w   #7,d1                   ; bit number
            move.w  H_DEPTH(a4),d7
            subq.w  #1,d7
            moveq   #0,d2                   ; plane
.pl         btst    d2,d3
            beq.s   .clr
            bset    d1,(a1)
            bra.s   .nx
.clr        bclr    d1,(a1)
.nx         add.l   #PLANE_SIZE,a1
            addq.w  #1,d2
            dbf     d7,.pl
            addq.w  #1,d5
            cmp.w   #256,d5
            blt     .row
.ncol       addq.w  #1,d4
            cmp.w   #320,d4
            blt     .col
.out        movem.l (sp)+,d0-d7/a0-a3
            rts

init_palette:
            move.w  #0,v_pfade(a5)          ; the colours shown now: the main palette
            bsr     pal_ncol
            move.l  H_PAL(a4),d0
            lea     0(a4,d0.l),a2
            lea     v_curpal(a5),a0
            bra.s   .cc
.cp         move.l  (a2)+,(a0)+
.cc         dbf     d5,.cp
            move.l  H_PAL(a4),d0
            lea     0(a4,d0.l),a2
            move.l  (a2),v_bg(a5)
            move.w  H_DEPTH(a4),d6
            moveq   #1,d5
            lsl.w   d6,d5                   ; colour count
            moveq   #0,d0
.pal        move.l  (a2)+,d1
            bsr     setcol
            addq.w  #1,d0
            cmp.w   d5,d0
            blt.s   .pal

            move.l  H_SPRCOL(a4),d0         ; sprite pair colours
            lea     0(a4,d0.l),a2
            moveq   #16,d4
            btst    #0,H_FLAGS+1(a4)
            beq.s   .base
            move.w  #240,d4
.base       moveq   #3,d6                   ; 4 pairs
.pair       moveq   #2,d5                   ; 3 colours each
            move.w  d4,d0
            addq.w  #1,d0
.pc         move.l  (a2)+,d1
            bsr     setcol
            addq.w  #1,d0
            dbf     d5,.pc
            addq.w  #4,d4
            dbf     d6,.pair
            rts

init_actors:
            movem.l d0-d1/a0-a1,-(sp)       ; the record of each actor, once
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a0
            lea     v_arec(a5),a1
            moveq   #MAX_ACT-1,d1
.ar         move.l  a0,(a1)+
            lea     ACT_SIZE(a0),a0
            dbf     d1,.ar
            movem.l (sp)+,d0-d1/a0-a1
            move.w  H_NACT(a4),d6
            beq     .done
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            moveq   #0,d7
.a          move.w  d7,d5
            lsl.w   #ACTV_SHIFT,d5
            move.w  A_X(a2),v_ax(a5,d5.w)
            move.w  A_Y(a2),v_ay(a5,d5.w)
            move.w  A_SPD(a2),d0            ; faster on later levels
            move.w  A_FAST(a2),d1
            beq.s   .spd
            moveq   #0,d2
            move.w  v_level(a5),d2
            subq.w  #1,d2
            divu    d1,d2
            add.w   d2,d0
            cmp.w   #8,d0
            ble.s   .spd
            moveq   #8,d0
.spd        move.w  d0,v_spd(a5,d5.w)
            move.w  A_VIS(a2),v_vis(a5,d5.w)
            move.w  A_FROM(a2),d0           ; not on this level yet: hidden
            cmp.w   v_level(a5),d0
            ble.s   .here
            move.w  #0,v_vis(a5,d5.w)
.here       move.w  A_LEFT(a2),v_dx(a5,d5.w)
            move.w  A_UP(a2),v_dy(a5,d5.w)
            move.w  A_X(a2),v_px(a5,d5.w)
            move.w  A_Y(a2),v_py(a5,d5.w)
            move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
            move.w  #0,v_tmr(a5,d5.w)
            move.w  #0,v_gnd(a5,d5.w)
            move.w  #0,v_squat(a5,d5.w)
            move.w  #0,v_life(a5,d5.w)
            move.w  #0,v_safe(a5,d5.w)
            move.l  A_SPR(a2),v_fofs(a5,d5.w)
            move.w  #-1,v_aset(a5,d5.w)
            move.w  #-1,v_aplay(a5,d5.w)
            move.w  A_X(a2),v_ox(a5,d5.w)
            move.w  A_Y(a2),v_oy(a5,d5.w)
            move.w  A_LEFT(a2),v_face(a5,d5.w)
            move.w  #0,v_thr(a5,d5.w)
            move.w  #0,v_tvx(a5,d5.w)
            move.w  #0,v_tvy(a5,d5.w)
            move.w  #-1,v_carry(a5)
            move.w  #1,v_mdx(a5,d5.w)       ; last moved: right, or left when it starts moving left
            move.w  #0,v_mdy(a5,d5.w)
            move.w  #2,v_dir(a5,d5.w)       ; facing east, or west when it starts moving left
            tst.w   A_LEFT(a2)
            beq.s   .east
            move.w  #6,v_dir(a5,d5.w)
            move.w  #-1,v_mdx(a5,d5.w)
.east       cmp.w   #ROLE_SHOT,A_ROLE(a2)   ; shots wait, hidden, for a Shoot rule
            bne.s   .notshot
            move.w  #0,v_vis(a5,d5.w)
.notshot    move.w  A_HP(a2),d0             ; shot hits it can take
            bne.s   .hp
            moveq   #1,d0
.hp         move.w  d0,v_hp(a5,d5.w)
            move.w  #0,v_hitf(a5,d5.w)
            move.w  v_spd(a5,d5.w),v_spd0(a5,d5.w)
            move.w  A_PAT(a2),v_pat(a5,d5.w)
            move.w  A_ENTER(a2),v_edge(a5,d5.w)
            move.w  A_FRATE(a2),d0          ; its first volley a while after it comes on
            lsr.w   #1,d0
            move.w  d0,v_ftmr(a5,d5.w)
            move.w  #0,v_xsub(a5,d5.w)
            move.w  A_ROLE(a2),d0
            cmp.w   #ROLE_OPT,d0            ; options and effects wait, hidden
            beq.s   .wait
            cmp.w   #ROLE_FX,d0
            beq.s   .wait
            cmp.w   #ROLE_FLY,d0            ; flyers wait off the screen
            bne.s   .nx
            bsr     fly_start
            bra.s   .nx
.wait       move.w  #0,v_vis(a5,d5.w)
.nx         lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .a
            bsr     power_apply             ; power-ups carry on to the next level
.done       rts

; the player's power-ups at a level start: its extra speed and its options
power_apply:
            movem.l d0-d2/d5,-(sp)
            move.w  H_PLAYER(a4),d5
            bmi.s   .opt
            cmp.w   H_NACT(a4),d5
            bhs.s   .opt
            lsl.w   #ACTV_SHIFT,d5
            move.w  v_spd(a5,d5.w),d0
            add.w   v_pspd(a5),d0
            cmp.w   #8,d0
            ble.s   .s
            moveq   #8,d0
.s          move.w  d0,v_spd(a5,d5.w)
.opt        move.w  v_nopt(a5),d2
            moveq   #0,d1
            bra.s   .lc
.l          bsr     opt_add
            beq.s   .full
            addq.w  #1,d1
.lc         dbf     d2,.l
.full       move.w  d1,v_nopt(a5)           ; (a level with fewer options: the ones it has)
            movem.l (sp)+,d0-d2/d5
            rts

clear_latches:
            lea     v_latch(a5),a0
            move.w  #RULES_MAX-1,d7
.l          move.w  #0,(a0)+
            dbf     d7,.l
            rts

clear_state:
            move.w  #0,v_fcount(a5)
            move.w  #0,v_sectick(a5)
            move.w  #0,v_flash(a5)
            move.w  #-1,v_gradfix(a5)
            move.w  #-1,d1
            bsr     build_grad
            bsr     clear_latches
            move.w  $06(a6),d0              ; VHPOSR into the random seed
            eor.w   d0,v_rand+2(a5)
            tst.l   v_rand(a5)
            bne.s   .r
            move.l  #$2a5b7c19,v_rand(a5)
.r          rts

; ============================================================================
;  colour register write
;  d0.w = colour index 0..255   d1.l = $00RRGGBB
; ============================================================================
setcol:
            movem.l d0-d4,-(sp)
            move.w  d0,d2
            and.w   #31,d2
            add.w   d2,d2
            add.w   #$180,d2                ; COLORxx register offset
            move.l  d1,d3                   ; high nibbles -> $0RGB
            lsr.l   #8,d3
            lsr.l   #4,d3
            and.w   #$0f00,d3
            move.w  d3,d4
            move.l  d1,d3
            lsr.l   #8,d3
            and.w   #$00f0,d3
            or.w    d3,d4
            move.l  d1,d3
            lsr.l   #4,d3
            and.w   #$000f,d3
            or.w    d3,d4
            btst    #0,H_FLAGS+1(a4)
            bne.s   .aga
            move.w  d4,0(a6,d2.w)
            bra.s   .done
.aga        tst.l   H_GRAD(a4)              ; the copper sky writes BPLCON3 on every
            beq.s   .bank                   ; line: hold the copper while we use it
            tst.w   v_cophold(a5)
            bne.s   .bank
            move.w  #$0080,$96(a6)          ; DMACON: copper off (it keeps its place)
.bank       move.w  d0,d3                   ; bank select
            lsr.w   #5,d3
            and.w   #7,d3
            ror.w   #3,d3
            or.w    #$0c00,d3
            move.w  d3,$106(a6)
            move.w  d4,0(a6,d2.w)           ; high nibbles
            move.l  d1,d4                   ; low nibbles
            lsr.l   #8,d4
            and.w   #$0f00,d4
            move.l  d1,d0
            lsr.l   #4,d0
            and.w   #$00f0,d0
            or.w    d0,d4
            move.w  d1,d0
            and.w   #$000f,d0
            or.w    d0,d4
            or.w    #$0200,d3               ; LOCT
            move.w  d3,$106(a6)
            move.w  d4,0(a6,d2.w)
            move.w  #$0c00,$106(a6)
            tst.l   H_GRAD(a4)
            beq.s   .done
            tst.w   v_cophold(a5)
            bne.s   .done
            move.w  #$8080,$96(a6)          ; copper on again
.done       movem.l (sp)+,d0-d4
            rts

; ============================================================================
;  one frame of game
; ============================================================================
frame:
            bsr     bob_flip                ; BOBs: show last frame's drawing (copper idle here too)
            bsr     flash_tick              ; copper edits first, while the copper is idle
            bsr     pal_tick                ; a palette fading in
            addq.w  #1,v_anim(a5)
            move.l  #0,v_jumped(a5)
            move.l  #0,v_aended(a5)
            move.l  #0,v_struck(a5)
            move.w  #0,v_hitn(a5)
            bsr     read_joy
            bsr     read_key
            bsr     tool_menu               ; space bar: the tool menu - the game waits while it is open
            bne     .wait
            move.w  v_igot(a5),v_igotp(a5)  ; items got last frame: WHEN 17 sees them now
            move.w  #0,v_igot(a5)
            move.w  #0,v_sectick(a5)
            addq.w  #1,v_fcount(a5)
            cmp.w   #50,v_fcount(a5)
            blt.s   .f1
            move.w  #0,v_fcount(a5)
            move.w  #1,v_sectick(a5)
            addq.w  #1,v_ltime(a5)
.f1         bsr     scroll_tick             ; scrolling backdrop: the scenery moves on
            bsr     spawn_tick              ; a scrolling map's spawners
            bsr     carry_tick              ; fire picks up / throws
            bsr     move_actors
            bsr     carry_follow            ; what the player carries rides on its head
            bsr     opt_follow              ; options follow the player's trail
            move.w  v_joy(a5),v_joyprev(a5)
            bsr     cam_follow              ; tile world: camera, new tiles, scroll
            bsr     cam_window
            bsr     cop_scroll
            bsr     place_sprites
            bsr     bob_draw
            bsr     item_tick               ; the player picks up items it touches
            bsr     run_rules
.wait       rts

; keyboard: CIA-A serial port, read each frame (no interrupt). v_key = $100 + the
; raw code of a key pressed this frame ($140 = space), 0 = none
read_key:   move.w  #0,v_key(a5)
            btst    #3,$bfed01              ; SP: a key code came in (reading clears it)
            beq.s   .r
            movem.l d0-d2,-(sp)
            moveq   #0,d0
            move.b  $bfec01,d0
            bset    #6,$bfee01              ; handshake: hold KDAT low a moment
            not.b   d0
            ror.b   #1,d0                   ; bit 7 set = let go
            bmi.s   .hs
            or.w    #$100,d0
            move.w  d0,v_key(a5)
.hs         moveq   #3,d1                   ; 3 raster lines (the keyboard wants 85 us)
.w1         move.b  $06(a6),d2
.w2         cmp.b   $06(a6),d2
            beq.s   .w2
            dbf     d1,.w1
            bclr    #6,$bfee01
            movem.l (sp)+,d0-d2
.r          rts

; the space bar menu (a tile world with tools, or a game with items): space opens it in
; the HUD row, left / right choose, fire or space take it - a tool, an item to use (WHEN 18)
; or a recipe to make. Z clear while it is open (the game waits)
tool_menu:  movem.l d1-d3/a0,-(sp)
            bsr     menu_any
            beq     .none
            tst.w   v_fwait(a5)             ; fire chose a tool: ignore it until let go
            beq.s   .fw
            move.w  v_joy(a5),d2
            btst    #4,d2
            bne.s   .fh
            move.w  #0,v_fwait(a5)
            bra.s   .fw
.fh         and.w   #$ffef,v_joy(a5)
.fw         tst.w   v_menu(a5)
            bne.s   .open
            cmp.w   #$140,v_key(a5)
            bne     .none
            bsr     menu_build
            move.w  v_mn(a5),d1
            beq     .none                   ; nothing in it now
            move.w  #1,v_menu(a5)
            move.w  #0,v_msel(a5)
            move.w  v_tool(a5),d2           ; the tool in use (tools come first)
            cmp.w   d1,d2
            bhs.s   .sel
            tst.b   v_ment(a5)
            bne.s   .sel
            move.w  d2,v_msel(a5)
.sel        bsr     menu_draw
            bra     .yes
.open       move.w  v_mn(a5),d1
            move.w  v_joy(a5),d2            ; newly pressed
            move.w  v_joyprev(a5),d3
            not.w   d3
            and.w   d3,d2
            btst    #2,d2
            beq.s   .m1
            subq.w  #1,v_msel(a5)           ; left
            bpl.s   .md
            move.w  d1,v_msel(a5)
            subq.w  #1,v_msel(a5)
            bra.s   .md
.m1         btst    #3,d2
            beq.s   .m2
            addq.w  #1,v_msel(a5)           ; right
            cmp.w   v_msel(a5),d1
            bhi.s   .md
            move.w  #0,v_msel(a5)
.md         bsr     menu_draw
            bra.s   .yes
.m2         btst    #4,d2
            beq.s   .m3
            move.w  #1,v_fwait(a5)
            bra.s   .take
.m3         cmp.w   #$140,v_key(a5)
            bne.s   .yes
.take       bsr     menu_take
            move.w  #0,v_menu(a5)
            bsr     menu_clear
            bsr     draw_hud
.yes        move.w  v_joy(a5),v_joyprev(a5)
            movem.l (sp)+,d1-d3/a0
            moveq   #1,d0
            rts
.none       movem.l (sp)+,d1-d3/a0
            moveq   #0,d0
            rts

; Z clear when the game can have a space bar menu: a tile world with tools, or items
menu_any:   movem.l d0/a0,-(sp)
            moveq   #0,d0
            tst.w   v_tmode(a5)
            beq.s   .it
            move.l  v_tiles(a5),a0
            tst.w   T_NTOOL(a0)
            bne.s   .yes
.it         move.l  v_items(a5),d0
            beq.s   .o
            move.l  d0,a0
            moveq   #0,d0
            tst.w   IT_N(a0)
            beq.s   .o
.yes        moveq   #1,d0
.o          tst.w   d0
            movem.l (sp)+,d0/a0
            rts

; the menu's entries now (v_ment, v_mn): the tools, the items the player carries, then the
; recipes it can make
menu_build: movem.l d0-d2/a0-a1,-(sp)
            lea     v_ment(a5),a1
            moveq   #0,d1                   ; entries
            tst.w   v_tmode(a5)
            beq.s   .items
            move.l  v_tiles(a5),a0
            move.w  T_NTOOL(a0),d2
            moveq   #0,d0
            bra.s   .tc
.t          move.b  #0,(a1)+
            move.b  d0,(a1)+
            addq.w  #1,d1
            addq.w  #1,d0
.tc         dbf     d2,.t
.items      move.l  v_items(a5),d0
            beq.s   .o
            move.l  d0,a0
            move.w  IT_N(a0),d2
            moveq   #0,d0
            lea     v_icnt(a5),a0
            bra.s   .ic
.i          tst.w   (a0)+
            beq.s   .in
            cmp.w   #MENU_MAX,d1
            bhs.s   .o
            move.b  #1,(a1)+
            move.b  d0,(a1)+
            addq.w  #1,d1
.in         addq.w  #1,d0
.ic         dbf     d2,.i
            move.l  v_items(a5),a0
            move.w  IT_NR(a0),d2
            moveq   #0,d0
            bra.s   .rc
.r          move.l  a0,-(sp)
            bsr     recipe_can
            move.l  (sp)+,a0
            beq.s   .rn
            cmp.w   #MENU_MAX,d1
            bhs.s   .o
            move.b  #2,(a1)+
            move.b  d0,(a1)+
            addq.w  #1,d1
.rn         addq.w  #1,d0
.rc         dbf     d2,.r
.o          move.w  d1,v_mn(a5)
            movem.l (sp)+,d0-d2/a0-a1
            rts

; the entry picked (v_msel): take the tool, use the item (WHEN 18 rules see it), or make the recipe
menu_take:  movem.l d0-d1/a0,-(sp)
            move.w  v_msel(a5),d0
            cmp.w   v_mn(a5),d0
            bhs.s   .o
            add.w   d0,d0
            lea     v_ment(a5),a0
            moveq   #0,d1
            move.b  1(a0,d0.w),d1           ; its number
            move.b  0(a0,d0.w),d0           ; its kind
            beq.s   .tool
            cmp.b   #1,d0
            beq.s   .item
            move.w  d1,d0
            bsr     recipe_make
            bra.s   .o
.item       move.w  d1,v_useit(a5)
            move.w  #0,v_uspent(a5)
            bra.s   .o
.tool       move.w  d1,v_tool(a5)
            move.l  #-1,v_digc(a5)
.o          movem.l (sp)+,d0-d1/a0
            rts

; the HUD row as the menu. With items: the entry picked, '< USE KEY 2 >'; with tools only:
; each tool's name, the one picked in the message colour
menu_draw:  movem.l d0-d7/a0-a1,-(sp)
            bsr     menu_clear
            move.l  v_items(a5),d0
            beq.s   .tools
            move.l  d0,a0
            tst.w   IT_N(a0)
            bne     menu_entry
.tools
            move.w  #-1,v_shadow(a5)
            move.l  v_tiles(a5),a1
            move.w  T_NTOOL(a1),d7
            move.w  T_NT(a1),d0
            mulu    #12,d0
            lea     T_PROPS(a1,d0.l),a1     ; the tools
            move.w  v_hudrow(a5),d2
            moveq   #0,d1
            moveq   #0,d6
.t          move.w  H_HUDCOL(a4),d3
            moveq   #' ',d0
            cmp.w   v_msel(a5),d6
            bne.s   .mk
            move.w  H_MSGCOL(a4),d3
            moveq   #'>',d0
.mk         bsr     draw_char
            addq.w  #1,d1
            lea     TL_NAME(a1),a0
            moveq   #7,d5
.c          moveq   #0,d0
            move.b  (a0)+,d0
            beq.s   .e
            bsr     draw_char
            addq.w  #1,d1
            dbf     d5,.c
.e          addq.w  #1,d1
            lea     TL_SIZE(a1),a1
            addq.w  #1,d6
            cmp.w   d7,d6
            blt.s   .t
            movem.l (sp)+,d0-d7/a0-a1
            rts

; (menu_draw with items, its registers saved) the entry picked, centred in the message
; colour: '< PICKAXE >', '< USE KEY 2 >', '< MAKE TORCH >'
menu_entry: lea     v_text(a5),a1
            move.b  #'<',(a1)+
            move.b  #' ',(a1)+
            move.w  v_msel(a5),d0
            cmp.w   v_mn(a5),d0
            bhs     .end
            add.w   d0,d0
            lea     v_ment(a5),a0
            moveq   #0,d6
            move.b  1(a0,d0.w),d6           ; its number
            move.b  0(a0,d0.w),d7           ; its kind
            bne.s   .ni
            move.l  v_tiles(a5),a0          ; a tool: its name
            move.w  T_NT(a0),d0
            mulu    #12,d0
            lea     T_PROPS(a0,d0.l),a0
            move.w  d6,d0
            mulu    #TL_SIZE,d0
            add.l   d0,a0
            lea     TL_NAME(a0),a0
            moveq   #8,d1
            bsr     copyn
            bra.s   .end
.ni         cmp.b   #1,d7
            bne.s   .rcp
            lea     str_use(pc),a0          ; an item: its name and how many
            moveq   #8,d1
            bsr     copyn
            move.w  d6,d0
            bsr     item_rec
            beq.s   .end
            lea     IT_NAME(a0),a0
            moveq   #8,d1
            bsr     copyn
            move.b  #' ',(a1)+
            lea     v_icnt(a5),a0
            add.w   d6,d6
            moveq   #0,d0
            move.w  0(a0,d6.w),d0
            divu    #10,d0
            tst.w   d0
            beq.s   .units
            add.b   #'0',d0
            move.b  d0,(a1)+
.units      swap    d0
            add.b   #'0',d0
            move.b  d0,(a1)+
            bra.s   .end
.rcp        lea     str_make(pc),a0         ; a recipe: what it makes
            moveq   #8,d1
            bsr     copyn
            move.w  d6,d0
            bsr     recipe_rec
            beq.s   .end
            move.w  RC_OUT(a0),d0
            bsr     item_rec
            beq.s   .end
            lea     IT_NAME(a0),a0
            moveq   #8,d1
            bsr     copyn
.end        move.b  #' ',(a1)+
            move.b  #'>',(a1)+
            move.b  #0,(a1)
            lea     v_text(a5),a0
            move.l  a1,d1
            sub.l   a0,d1
            neg.w   d1
            add.w   #40,d1
            asr.w   #1,d1
            bpl.s   .col
            moveq   #0,d1
.col        move.w  v_hudrow(a5),d2
            move.w  H_MSGCOL(a4),d3
            move.w  #-1,v_shadow(a5)
            bsr     draw_text
            movem.l (sp)+,d0-d7/a0-a1
            rts

; copies up to d1 letters from a0 to a1 (stops at a 0; a1 moves on)
copyn:      movem.l d0-d1/a0,-(sp)
            bra.s   .lc
.c          move.b  (a0)+,d0
            beq.s   .e
            move.b  d0,(a1)+
.lc         dbf     d1,.c
.e          movem.l (sp)+,d0-d1/a0
            rts

; the HUD row back to its background (draw_hud then puts the HUD back)
menu_clear: movem.l d0-d3,-(sp)
            move.w  #-1,v_shadow(a5)
            move.w  v_hudrow(a5),d2
            moveq   #0,d3
            moveq   #39,d1
.c          moveq   #' ',d0
            bsr     draw_char
            dbf     d1,.c
            movem.l (sp)+,d0-d3
            rts

; a0 = tile world block -> a1 = the tool in use
tool_rec:   move.w  T_NT(a0),d4
            mulu    #12,d4
            lea     T_PROPS(a0,d4.l),a1
            move.w  v_tool(a5),d4
            mulu    #TL_SIZE,d4
            add.l   d4,a1
            rts

read_joy:
            move.w  $0c(a6),d0              ; JOY1DAT (port 2)
            moveq   #0,d2
            btst    #1,d0
            beq.s   .nr
            or.w    #8,d2                   ; right
.nr         btst    #9,d0
            beq.s   .nl
            or.w    #4,d2                   ; left
.nl         move.w  d0,d1
            lsr.w   #1,d1
            eor.w   d0,d1
            btst    #0,d1
            beq.s   .nd
            or.w    #2,d2                   ; down
.nd         btst    #8,d1
            beq.s   .nu
            or.w    #1,d2                   ; up
.nu         btst    #7,$bfe001
            bne.s   .nf
            or.w    #16,d2                  ; fire (port 2)
.nf         move.w  d2,v_joy(a5)
            rts

; ============================================================================
;  actor movement
; ============================================================================
move_actors:
            move.w  H_NACT(a4),d6
            beq     .done
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            moveq   #0,d7
.loop       move.w  d7,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)          ; a hidden shot, flyer or effect with nothing
            bne.s   .live                   ; counting down: nothing to do (most of a
            move.w  A_ROLE(a2),d0           ; shoot 'em up's actors, most of the time)
            cmp.w   #ROLE_SHOT,d0
            beq.s   .idle
            cmp.w   #ROLE_FLY,d0
            beq.s   .idle
            cmp.w   #ROLE_FX,d0
            bne.s   .live
.idle       tst.w   v_thr(a5,d5.w)
            bne.s   .live
            tst.w   v_life(a5,d5.w)
            bne.s   .live
            tst.w   v_safe(a5,d5.w)
            bne.s   .live
            tst.w   v_hitf(a5,d5.w)
            beq     .adv2
.live       move.w  v_ax(a5,d5.w),v_ox(a5,d5.w)
            move.w  v_ay(a5,d5.w),v_oy(a5,d5.w)
            tst.w   v_safe(a5,d5.w)         ; immunity counts down
            beq.s   .nosafe
            subq.w  #1,v_safe(a5,d5.w)
.nosafe     tst.w   v_hitf(a5,d5.w)         ; the white flash of a hit fades
            beq.s   .nohf
            subq.w  #1,v_hitf(a5,d5.w)
.nohf       tst.w   v_life(a5,d5.w)         ; shown-for-a-moment actors hide again
            beq.s   .nolife
            subq.w  #1,v_life(a5,d5.w)
            bne.s   .nolife
            move.w  #0,v_vis(a5,d5.w)
.nolife     move.w  A_FROM(a2),d0           ; not on this level yet
            cmp.w   v_level(a5),d0
            bgt     .next
            cmp.w   v_carry(a5),d7          ; carried: carry_follow places it
            beq     .adv
            tst.w   v_thr(a5,d5.w)          ; thrown: it flies
            bne     .fly
            move.w  A_ROLE(a2),d0
            beq     .player
            cmp.w   #ROLE_FLY,d0
            beq     .flyer
            cmp.w   #ROLE_FX,d0
            beq     .fx
            cmp.w   #ROLE_OPT,d0            ; options: opt_follow places them
            beq     .adv
            cmp.w   #6,d0
            beq     .platform
            cmp.w   #7,d0
            beq     .hopper
            cmp.w   #8,d0
            beq     .faller
            cmp.w   #4,d0
            beq     .chaser
            cmp.w   #3,d0
            beq     .vert
            cmp.w   #2,d0
            beq     .horiz
            cmp.w   #1,d0
            beq     .horiz
            bra     .next

.player     tst.w   v_tmode(a5)             ; tile world: fire digs / places instead of moving
            beq.s   .pmv
            bsr     weapon_tick
            bsr     tile_dig
            bne     .next
.pmv        move.w  v_spd(a5,d5.w),d1
            move.w  v_joy(a5),d2
            btst    #0,d2
            beq.s   .pu
            move.w  v_ay(a5,d5.w),d0
            sub.w   d1,d0
            bge.s   .pu1
            moveq   #0,d0
.pu1        move.w  d0,v_ay(a5,d5.w)
.pu         btst    #1,d2
            beq.s   .pd
            move.w  v_ay(a5,d5.w),d0
            add.w   d1,d0
            cmp.w   A_YMAX(a2),d0
            ble.s   .pd1
            move.w  A_YMAX(a2),d0
.pd1        move.w  d0,v_ay(a5,d5.w)
.pd         btst    #2,d2
            beq.s   .pl
            move.w  v_ax(a5,d5.w),d0
            sub.w   d1,d0
            bge.s   .pl1
            moveq   #0,d0
.pl1        move.w  d0,v_ax(a5,d5.w)
.pl         btst    #3,d2
            beq.s   .pr
            move.w  v_ax(a5,d5.w),d0
            add.w   d1,d0
            cmp.w   A_XMAX(a2),d0
            ble.s   .pr1
            move.w  A_XMAX(a2),d0
.pr1        move.w  d0,v_ax(a5,d5.w)
.pr         bra     .next

.horiz      move.w  v_spd(a5,d5.w),d1
            move.w  v_ax(a5,d5.w),d0
            tst.w   v_dx(a5,d5.w)
            bne.s   .hl
            add.w   d1,d0
            cmp.w   A_XMAX(a2),d0
            ble.s   .hs
            move.w  A_XMAX(a2),d0
            move.w  #1,v_dx(a5,d5.w)
            bra.s   .hs
.hl         sub.w   d1,d0
            bge.s   .hs
            moveq   #0,d0
            move.w  #0,v_dx(a5,d5.w)
.hs         move.w  d0,v_ax(a5,d5.w)
            cmp.w   #1,A_ROLE(a2)           ; bouncer also moves vertically
            bne     .next

.vert       move.w  v_spd(a5,d5.w),d1
            move.w  v_ay(a5,d5.w),d0
            tst.w   v_dy(a5,d5.w)
            bne.s   .vu
            add.w   d1,d0
            cmp.w   A_YMAX(a2),d0
            ble.s   .vs
            move.w  A_YMAX(a2),d0
            move.w  #1,v_dy(a5,d5.w)
            bra.s   .vs
.vu         sub.w   d1,d0
            bge.s   .vs
            moveq   #0,d0
            move.w  #0,v_dy(a5,d5.w)
.vs         move.w  d0,v_ay(a5,d5.w)
            bra     .next

.chaser     move.w  H_PLAYER(a4),d4
            bge.s   .ct
            moveq   #0,d4
.ct         cmp.w   d7,d4
            beq     .next
            lsl.w   #ACTV_SHIFT,d4
            move.w  v_spd(a5,d5.w),d3
            subq.w  #1,d3
            bmi     .next
.cl         move.w  v_ax(a5,d5.w),d0
            cmp.w   v_ax(a5,d4.w),d0
            beq.s   .cy
            blt.s   .cxi
            subq.w  #1,v_ax(a5,d5.w)
            bra.s   .cy
.cxi        addq.w  #1,v_ax(a5,d5.w)
.cy         move.w  v_ay(a5,d5.w),d0
            cmp.w   v_ay(a5,d4.w),d0
            beq.s   .cn
            blt.s   .cyi
            subq.w  #1,v_ay(a5,d5.w)
            bra.s   .cn
.cyi        addq.w  #1,v_ay(a5,d5.w)
.cn         dbf     d3,.cl
            bra     .next                   ; (it used to run on into the platform player's code)

.platform  tst.w   v_tmode(a5)             ; tile world: fire digs / places instead of walking
            beq.s   .plmv
            bsr     weapon_tick
            bsr     tile_dig
            bne     .pphys
.plmv       move.w  v_spd(a5,d5.w),d1      ; walk left / right
            move.w  v_joy(a5),d2
            btst    #2,d2
            beq.s   .wl
            move.w  v_ax(a5,d5.w),d0
            sub.w   d1,d0
            bge.s   .wl1
            moveq   #0,d0
.wl1        move.w  d0,v_ax(a5,d5.w)
.wl         btst    #3,d2
            beq.s   .wr
            move.w  v_ax(a5,d5.w),d0
            add.w   d1,d0
            cmp.w   A_XMAX(a2),d0
            ble.s   .wr1
            move.w  A_XMAX(a2),d0
.wr1        move.w  d0,v_ax(a5,d5.w)
.wr         tst.w   v_gnd(a5,d5.w)          ; jump: fire or up, just pressed
            beq.s   .pphys
            move.w  v_joyprev(a5),d0
            not.w   d0
            and.w   d2,d0
            moveq   #17,d3                  ; up or fire jumps (only up when fire digs)
            tst.w   v_tmode(a5)
            beq.s   .jk
            move.l  v_tiles(a5),a0
            btst    #0,T_FLAGS+1(a0)
            beq.s   .jk
            moveq   #1,d3
.jk         and.w   d3,d0
            beq.s   .pphys
            move.w  #-JUMP_V,v_vy(a5,d5.w)
            bsr     jumped
.pphys      bsr     physics
            bra     .next

.hopper     tst.w   v_gnd(a5,d5.w)
            beq.s   .hair
            tst.w   v_squat(a5,d5.w)        ; crouching, about to spring
            bne.s   .squat
            addq.w  #1,v_tmr(a5,d5.w)
            bsr     rand
            and.w   #31,d0
            add.w   #30,d0
            cmp.w   v_tmr(a5,d5.w),d0
            bgt     .hphys
            move.w  #0,v_tmr(a5,d5.w)
            move.w  #HOP_SQUAT,v_squat(a5,d5.w)
            bra     .hphys
.squat      subq.w  #1,v_squat(a5,d5.w)
            bne     .hphys
            move.w  v_spd(a5,d5.w),d0       ; jump height grows with speed
            mulu    #7,d0
            add.w   #HOP_JUMP,d0
            neg.w   d0
            move.w  d0,v_vy(a5,d5.w)
            bsr     jumped
            bsr     rand
            and.w   #3,d0
            bne     .hphys
            eor.w   #1,v_dx(a5,d5.w)        ; sometimes turn round
            bra     .hphys
.hair       btst    #0,v_anim+1(a5)         ; drift sideways every other frame
            beq     .hphys
            move.w  v_spd(a5,d5.w),d1
            move.w  v_ax(a5,d5.w),d0
            tst.w   v_dx(a5,d5.w)
            bne.s   .hjl
            add.w   d1,d0
            cmp.w   A_XMAX(a2),d0
            ble.s   .hjs
            move.w  A_XMAX(a2),d0
            move.w  #1,v_dx(a5,d5.w)
            bra.s   .hjs
.hjl        sub.w   d1,d0
            bge.s   .hjs
            moveq   #0,d0
            move.w  #0,v_dx(a5,d5.w)
.hjs        move.w  d0,v_ax(a5,d5.w)
.hphys      bsr     physics
            bra     .next

.faller     bsr     physics
            bra     .next

.flyer      tst.w   v_vis(a5,d5.w)          ; hidden: it waits where it is
            beq     .adv
            bsr     fly_move
            bra     .adv

.fx         tst.w   v_vis(a5,d5.w)          ; an effect drifts with the scenery
            beq     .adv
            move.w  v_sdx(a5),d0
            add.w   d0,v_ax(a5,d5.w)
            move.w  v_sdy(a5),d0
            add.w   d0,v_ay(a5,d5.w)
            bra     .adv

.fly        cmp.w   #SHOT_FLY,v_thr(a5,d5.w)
            beq     .shot
            move.w  v_ax(a5,d5.w),d0        ; across, stopped by the edges
            add.w   v_tvx(a5,d5.w),d0
            bpl.s   .fl0
            moveq   #0,d0
            move.w  #0,v_tvx(a5,d5.w)
.fl0        cmp.w   A_XMAX(a2),d0
            ble.s   .fl1
            move.w  A_XMAX(a2),d0
            move.w  #0,v_tvx(a5,d5.w)
.fl1        move.w  d0,v_ax(a5,d5.w)
            bsr     physics                 ; up and down (and tile walls)
            tst.w   v_tvx(a5,d5.w)          ; a wall stopped it: it drops
            beq.s   .fl2
            move.w  v_ax(a5,d5.w),d0
            cmp.w   v_ox(a5,d5.w),d0
            bne.s   .fl2
            move.w  #0,v_tvx(a5,d5.w)
.fl2        tst.w   v_gnd(a5,d5.w)          ; landed
            beq.s   .fl3
            tst.w   v_vy(a5,d5.w)
            bmi.s   .fl3
            move.w  #0,v_thr(a5,d5.w)
            move.w  #0,v_tvx(a5,d5.w)
            bra     .adv
.fl3        cmp.w   #1,v_thr(a5,d5.w)       ; still flying at things
            bne     .adv
            bsr     throw_hits
            bra     .adv

.shot       cmp.w   #6,A_UP(a2)             ; a homing missile turns towards its target
            bne.s   .shmv
            bsr     missile_steer
.shmv       move.w  v_tvx(a5,d5.w),d0       ; a shot flies straight, 1/16 pixels a frame
            add.w   v_xsub(a5,d5.w),d0
            move.w  d0,d1
            and.w   #15,d1
            move.w  d1,v_xsub(a5,d5.w)
            asr.w   #4,d0
            add.w   v_ax(a5,d5.w),d0
            move.w  v_tvy(a5,d5.w),d1
            add.w   v_ysub(a5,d5.w),d1
            move.w  d1,d2
            and.w   #15,d2
            move.w  d2,v_ysub(a5,d5.w)
            asr.w   #4,d1
            add.w   v_ay(a5,d5.w),d1
            move.w  d0,v_ax(a5,d5.w)
            move.w  d1,v_ay(a5,d5.w)
            tst.w   v_tmode(a5)
            bne.s   .sht
            tst.w   d0                      ; one screen: gone at its edges
            bmi.s   .shend
            cmp.w   A_XMAX(a2),d0
            bgt.s   .shend
            tst.w   d1
            bmi.s   .shend
            cmp.w   A_YMAX(a2),d1
            bgt.s   .shend
            bra.s   .shhit
.sht        bsr     box_solid               ; a tile world: gone in a wall or out of view
            bne.s   .shend
            move.w  d7,d0
            bsr     on_screen
            beq.s   .shend
.shhit      bsr     shot_hits
            beq     .adv
.shend      move.w  #0,v_vis(a5,d5.w)
            move.w  #0,v_thr(a5,d5.w)
            bra     .adv

.next       tst.w   v_tmode(a5)             ; tile world: walls stop it (gravity roles did it in physics)
            beq.s   .adv
            cmp.w   #6,A_ROLE(a2)
            bge.s   .adv
            bsr     tile_hres
            bsr     tile_vres
.adv        tst.w   A_FIRE(a2)              ; it fires by itself
            bmi.s   .adv2
            bsr     foe_fire
.adv2       lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .loop
.done       rts

; d7 = actor index -> sets its bit in v_jumped (d5 = actor offset)
jumped:     move.w  #0,v_gnd(a5,d5.w)
            move.l  v_jumped(a5),d0
            bset    d7,d0
            move.l  d0,v_jumped(a5)
            rts

; ground top under the middle of actor d5 -> d2 (256 when there is no ground)
ground_y:   move.l  v_game(a5),d2           ; level hills win over painted ground
            beq.s   .paint
            move.l  d2,a0
            tst.w   G_TERRAIN(a0)
            beq.s   .paint
            move.w  d0,-(sp)
            bsr     level_heights
            move.w  (sp)+,d0
            bra.s   .col
.paint      move.l  H_GROUND(a4),d2
            beq.s   .none
            lea     0(a4,d2.l),a0
.col
            move.w  #320,d1                 ; x + half the width
            sub.w   A_XMAX(a2),d1
            lsr.w   #1,d1
            move.w  v_ax(a5,d5.w),d2
            add.w   d1,d2
            cmp.w   #319,d2
            bls.s   .ok
            move.w  #319,d2
.ok         add.w   d2,d2
            move.w  0(a0,d2.w),d2
            rts
.none       move.w  #256,d2
            rts

; gravity and ground contact for actor d5 (record a2)
physics:    tst.w   v_tmode(a5)
            bne     tile_phys
            move.w  v_vy(a5,d5.w),d0
            cmp.w   #7,A_ROLE(a2)           ; hoppers float down more slowly
            beq.s   .light
            addq.w  #GRAVITY,d0
            bra.s   .g
.light      addq.w  #HOP_GRAVITY,d0
.g
            cmp.w   #MAX_FALL,d0
            ble.s   .v
            move.w  #MAX_FALL,d0
.v          move.w  d0,v_vy(a5,d5.w)
            add.w   v_ysub(a5,d5.w),d0
            move.w  d0,d1
            asr.w   #4,d1
            and.w   #15,d0
            move.w  d0,v_ysub(a5,d5.w)
            add.w   d1,v_ay(a5,d5.w)
            move.w  v_gnd(a5,d5.w),d4       ; was standing last frame?
            move.w  #0,v_gnd(a5,d5.w)
            bsr     ground_y
            move.w  v_ay(a5,d5.w),d3        ; feet = y + bottom of the drawn pixels
            add.w   A_BY1(a2),d3
            addq.w  #1,d3
            tst.w   d4                      ; walking downhill: stay stuck to the slope
            beq.s   .chk
            addq.w  #6,d3
.chk        cmp.w   d2,d3
            blt.s   .air
            tst.w   v_vy(a5,d5.w)
            bmi.s   .air
            sub.w   A_BY1(a2),d2            ; stand on the ground (follows the hills)
            subq.w  #1,d2
            move.w  d2,v_ay(a5,d5.w)
            move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
            move.w  #1,v_gnd(a5,d5.w)
.air        move.w  v_ay(a5,d5.w),d0
            cmp.w   A_YMAX(a2),d0
            ble.s   .top
            move.w  A_YMAX(a2),v_ay(a5,d5.w)
            move.w  #0,v_vy(a5,d5.w)
            move.w  #1,v_gnd(a5,d5.w)
            rts
.top        tst.w   d0
            bge.s   .ok
            move.w  #0,v_ay(a5,d5.w)
            move.w  #0,v_vy(a5,d5.w)
.ok         rts

; ============================================================================
;  write every actor's sprite control words

; ============================================================================
place_sprites:
            move.w  H_NACT(a4),d6
            beq     .done
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            moveq   #0,d7
.loop       move.w  d7,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)          ; a hidden BOB (a shot or a wave waiting): no frame to pick
            bne.s   .shown
            tst.w   A_BOB(a2)
            beq.s   .shown
            move.w  v_ax(a5,d5.w),v_px(a5,d5.w)
            move.w  v_ay(a5,d5.w),v_py(a5,d5.w)
            bra     .next
.shown      tst.w   v_swing(a5)             ; the player swinging: it keeps facing the way it struck
            beq.s   .fc
            cmp.w   H_PLAYER(a4),d7
            beq.s   .faced
.fc         move.w  v_ax(a5,d5.w),d0        ; which way it faces
            cmp.w   v_px(a5,d5.w),d0
            beq.s   .faced
            blt.s   .fleft
            move.w  #0,v_face(a5,d5.w)
            bra.s   .faced
.fleft      move.w  #1,v_face(a5,d5.w)
.faced      move.l  A_SPR(a2),d0            ; pick the animation frame
            cmp.w   #7,A_ROLE(a2)           ; hoppers show their crouch frame while squatting
            bne.s   .anim
            tst.l   A_SPR2(a2)
            beq.s   .anim
            tst.w   v_squat(a5,d5.w)
            beq.s   .anim
            move.l  A_SPR2(a2),d0
            bra     .frame
.anim       tst.w   v_aplay(a5,d5.w)        ; Hit / Die playing (DO 26)
            bmi.s   .anim2
            move.l  A_ANIM(a2),d1
            beq.s   .apnone
            btst    #2,A_AMODE+1(a2)
            beq.s   .apnone
            moveq   #4,d2                   ; they come after the 4 / 12 / 21 others
            btst    #1,A_AMODE+1(a2)
            beq.s   .apb
            moveq   #21,d2
            bra.s   .apc
.apb        btst    #0,A_AMODE+1(a2)
            beq.s   .apc
            moveq   #12,d2
.apc        add.w   v_aplay(a5,d5.w),d2
            bra     .got
.apnone     bsr     anim_ended              ; none drawn: it ends at once
.anim2      move.l  A_ANIM(a2),d1
            beq     .frame                  ; one frame
            btst    #1,A_AMODE+1(a2)        ; Fire animations: the player holding fire
            beq     .nofire
            cmp.w   H_PLAYER(a4),d7
            bne     .nofire
            tst.w   v_swing(a5)             ; a weapon swing: Fire on its own, the way it faces
            beq.s   .nsw
            moveq   #12,d2
            bra     .got
.nsw        move.w  v_joy(a5),d3
            btst    #4,d3
            beq     .nofire
            bsr     tool_kind               ; d4 = the tool in use (-1 = no tools)
            move.w  d0,d4
            cmp.w   #3,d0                   ; a weapon shows only its swing
            beq     .nofire
            moveq   #1,d0                   ; joystick -> 3 x (up 0, level 1, down 2) + (left 0, centre 1, right 2)
            btst    #0,d3
            beq.s   .fd1
            moveq   #0,d0
.fd1        btst    #1,d3
            beq.s   .fd2
            moveq   #2,d0
.fd2        mulu    #3,d0
            addq.w  #1,d0
            btst    #2,d3
            beq.s   .fd3
            subq.w  #1,d0
            move.w  #1,v_face(a5,d5.w)
.fd3        btst    #3,d3
            beq.s   .fd4
            addq.w  #1,d0
            move.w  #0,v_face(a5,d5.w)
.fd4        moveq   #12,d2                  ; Fire, no direction
            cmp.w   #4,d0
            bne.s   .fdir
            tst.w   d4                      ; tools: fire on its own works the way it faces (Fire + E / W);
            bmi     .got                    ; Fire on its own is the weapon's swing
            moveq   #5,d0
            tst.w   v_face(a5,d5.w)
            beq.s   .fdir
            moveq   #3,d0
.fdir       lea     dir_tab(pc),a0
            moveq   #0,d2
            move.b  0(a0,d0.w),d2
            move.w  d2,v_dir(a5,d5.w)
            add.w   #13,d2
            bra     .got
.nofire     moveq   #0,d2                   ; d2 = animation: 0 Idle
            move.w  A_ROLE(a2),d3
            cmp.w   #6,d3                   ; platform player, hopper, faller: Jump / Fall in the air
            blt.s   .walkq
            tst.w   v_gnd(a5,d5.w)
            bne.s   .walkq
            moveq   #2,d2
            tst.w   v_vy(a5,d5.w)
            blt.s   .got
            moveq   #3,d2
            bra.s   .got
.walkq      move.w  v_ax(a5,d5.w),d3        ; d3 / d4 = how far it moved this frame
            sub.w   v_px(a5,d5.w),d3
            move.w  v_ay(a5,d5.w),d4
            sub.w   v_py(a5,d5.w),d4
            move.w  d3,d0
            or.w    d4,d0
            beq.s   .got                    ; standing still: Idle
            moveq   #1,d2                   ; moving: Walk
            btst    #0,A_AMODE+1(a2)        ; or one of 8 directions
            beq.s   .got
            moveq   #1,d0                   ; d0 = 3 x (up 0, level 1, down 2) + (left 0, still 1, right 2)
            tst.w   d4
            beq.s   .dy0
            bmi.s   .dyn
            moveq   #2,d0
            bra.s   .dy0
.dyn        moveq   #0,d0
.dy0        mulu    #3,d0
            tst.w   d3
            beq.s   .dx0
            bmi.s   .dx1
            addq.w  #2,d0
            bra.s   .dx1
.dx0        addq.w  #1,d0
.dx1        lea     dir_tab(pc),a0
            moveq   #0,d2
            move.b  0(a0,d0.w),d2
            move.w  d2,v_dir(a5,d5.w)
            addq.w  #4,d2
.got        cmp.w   v_aset(a5,d5.w),d2      ; a new animation starts from its first frame
            beq.s   .same
            move.w  d2,v_aset(a5,d5.w)
            move.w  v_anim(a5),v_astart(a5,d5.w)
            move.w  #0,v_ael(a5,d5.w)
            move.w  #0,v_arem(a5,d5.w)
            move.w  #0,v_astep(a5,d5.w)
            move.w  #0,v_afr(a5,d5.w)
.same       mulu    #ANIM_SIZE,d2
            add.l   d2,d1
            lea     0(a4,d1.l),a0           ; a0 = this animation
            cmp.w   #3,AN_MODE(a0)          ; stand facing: first frame of the last direction
            bne.s   .tick
            move.w  v_dir(a5,d5.w),d2
            addq.w  #4,d2
            mulu    #ANIM_SIZE,d2
            move.l  A_ANIM(a2),d1
            add.l   d2,d1
            move.l  AN_RIGHT(a4,d1.l),d0
            bra     .frame
.tick       move.w  AN_RATE(a0),d4          ; d4 = 50ths a step
            bne.s   .rt
            moveq   #8,d4
.rt         move.w  AN_N(a0),d1             ; d1 = its cycle in steps: n (loop), 2n - 2
            cmp.w   #2,AN_MODE(a0)          ; (ping-pong)
            bne.s   .pd
            add.w   d1,d1
            subq.w  #2,d1
.pd         move.w  v_anim(a5),d3           ; the steps, counted as they come (no divide)
            sub.w   v_astart(a5,d5.w),d3    ; d3 = 50ths since it started
            sub.w   v_ael(a5,d5.w),d3       ; d3 = 50ths not counted yet
            beq.s   .cnt
            add.w   d3,v_ael(a5,d5.w)
            cmp.w   #255,d3                 ; (a long gap - the tool menu: it goes on from here)
            bhi.s   .cnt
            subq.w  #1,d3
.u1         addq.w  #1,v_arem(a5,d5.w)
            cmp.w   v_arem(a5,d5.w),d4
            bhi.s   .u2
            move.w  #0,v_arem(a5,d5.w)
            cmp.w   #$7fff,v_astep(a5,d5.w)
            bhs.s   .u3
            addq.w  #1,v_astep(a5,d5.w)
.u3         addq.w  #1,v_afr(a5,d5.w)
            cmp.w   v_afr(a5,d5.w),d1
            bhi.s   .u2
            move.w  #0,v_afr(a5,d5.w)
.u2         dbf     d3,.u1
.cnt        move.w  AN_N(a0),d4             ; frames 1..16
            tst.w   v_aplay(a5,d5.w)        ; Hit / Die: one pass, then it ends on its last frame
            bmi.s   .cnt2
            cmp.w   v_astep(a5,d5.w),d1
            bhi.s   .cnt2
            bsr     anim_ended
            move.w  d4,d3
            subq.w  #1,d3
            bra     .mfi
.cnt2       move.w  AN_MODE(a0),d2
            beq.s   .mloop
            cmp.w   #1,d2
            beq.s   .monce
            cmp.w   #1,d4                   ; ping-pong: 0 1 2 .. n-1 n-2 .. 1
            ble.s   .mf0
            move.w  v_afr(a5,d5.w),d3
            cmp.w   d4,d3
            blt.s   .mfi
            neg.w   d3
            add.w   d1,d3
            bra.s   .mfi
.monce      move.w  v_astep(a5,d5.w),d3     ; once: stays on the last frame
            cmp.w   d4,d3
            blo.s   .mfi
            move.w  d4,d3
            subq.w  #1,d3
            bra.s   .mfi
.mloop      move.w  v_afr(a5,d5.w),d3
            bra.s   .mfi
.mf0        moveq   #0,d3
.mfi        and.w   #15,d3
            lsl.w   #2,d3
            add.w   #AN_RIGHT,d3
            tst.w   v_face(a5,d5.w)
            beq.s   .rgt
            add.w   #AN_LEFT-AN_RIGHT,d3
.rgt        move.l  0(a0,d3.w),d0
.frame      move.l  d0,-(sp)                ; remember the way it moved (a shot's aim 0)
            move.w  v_ax(a5,d5.w),d0
            sub.w   v_px(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d3
            sub.w   v_py(a5,d5.w),d3
            move.w  d0,d4
            or.w    d3,d4
            beq.s   .mdk
            bsr     sign_w
            move.w  d0,v_mdx(a5,d5.w)
            move.w  d3,d0
            bsr     sign_w
            move.w  d0,v_mdy(a5,d5.w)
.mdk        move.l  (sp)+,d0
            move.w  v_ax(a5,d5.w),v_px(a5,d5.w)
            move.w  v_ay(a5,d5.w),v_py(a5,d5.w)
            move.l  d0,v_fofs(a5,d5.w)      ; BOBs: just note the frame, bob_draw draws it
            tst.w   A_BOB(a2)
            beq.s   .hw
            bra     .next
.hw         lea     0(a4,d0.l),a0           ; a0 = sprite block to show
            move.l  a0,d0                   ; point this channel at it
            lea     cop_spr-V-128(a5),a1
            move.w  A_CHAN(a2),d1
            and.w   #7,d1
            lsl.w   #3,d1
            add.w   d1,a1
            swap    d0
            move.w  d0,2(a1)
            swap    d0
            move.w  d0,6(a1)
            tst.w   v_vis(a5,d5.w)
            beq.s   .hid
            tst.w   v_hitf(a5,d5.w)         ; hit by a shot: it blinks
            beq.s   .nhf
            btst    #1,v_anim+1(a5)
            beq.s   .hid
.nhf        tst.w   v_safe(a5,d5.w)         ; flashing while immune
            beq.s   .show
            btst    #2,v_anim+1(a5)
            beq.s   .show
.hid        move.l  #0,(a0)
            bra     .next
.show       move.w  v_ay(a5,d5.w),d0
            move.w  v_ax(a5,d5.w),d1
            tst.w   v_tmode(a5)             ; tile world: where it is on the screen
            beq.s   .clip
            sub.w   v_camy(a5),d0
            sub.w   v_camx(a5),d1
.clip       cmp.w   #-24,d0                 ; (off the screen: flyers waiting to come in)
            ble     .hid
            cmp.w   #256,d0
            bge     .hid
            cmp.w   #-16,d1
            ble     .hid
            cmp.w   v_pw(a5),d1
            bge     .hid
.scr        add.w   #$2c,d0                 ; VSTART
            add.w   #128,d1                 ; HSTART (a narrow map's play area starts v_xoff in)
            add.w   v_xoff(a5),d1
            move.w  d0,d2
            add.w   #SPR_H,d2               ; VSTOP
            move.w  d0,d3
            lsl.w   #8,d3
            move.w  d1,d4
            lsr.w   #1,d4
            and.w   #$ff,d4
            or.w    d4,d3
            move.w  d3,(a0)                 ; SPRxPOS
            move.w  d2,d3
            lsl.w   #8,d3
            btst    #8,d0
            beq.s   .c1
            or.w    #4,d3
.c1         btst    #8,d2
            beq.s   .c2
            or.w    #2,d3
.c2         btst    #0,d1
            beq.s   .c3
            or.w    #1,d3
.c3         move.w  d3,2(a0)                ; SPRxCTL
.next       lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .loop
.done       rts

; ============================================================================
;  scrolling backdrop (version 9, shoot 'em ups)
; ============================================================================
; level start: the picture (backdrop + this level's hills, without the HUD
; panel) twice into each buffer, the HUD strip at the top of the normal
; display, and the copper split under it
scroll_on:  tst.l   v_sblk(a5)
            beq     .r
            movem.l d0-d7/a0-a3,-(sp)
            move.l  v_sblk(a5),a3
            move.w  SC_DIR(a3),v_scr(a5)
            move.w  #0,v_spos(a5)
            move.w  #0,v_dpos(a5)
            move.w  #0,v_sacc(a5)
            move.w  #1,v_split(a5)
            move.w  #0,v_hudrow(a5)
            move.l  v_splsz(a5),v_plsz(a5)
            move.w  v_sbpr(a5),v_bpr(a5)
            tst.l   v_map(a5)               ; a map: its play area in the middle of the screen
            beq.s   .pv
            move.w  v_mcols(a5),d0
            lsl.w   #4,d0
            move.w  d0,v_pw(a5)
            neg.w   d0
            add.w   #320,d0
            lsr.w   #1,d0
            move.w  d0,v_xoff(a5)           ; (20 - cols) x 8 pixels
            move.w  #0,v_ddfs(a5)
            lsr.w   #1,d0                   ; DDF: 8 per word of 16 pixels
            beq.s   .pv
            move.w  d0,d1
            add.w   #$0038,d1
            move.w  d1,v_ddfs(a5)
            neg.w   d0
            add.w   #$00d0,d0
            move.w  d0,v_ddfe(a5)
.pv         bsr     work_fresh
            tst.l   v_map(a5)               ; a map: its first screen, from its bottom
            beq.s   .pic
            bsr     map_start
            bra     .pdone
.pic        move.l  v_sbuf(a5),a1
            move.w  SC_NBUF(a3),d6
            subq.w  #1,d6
.buf        move.l  v_work(a5),a0
            move.l  a1,a2                   ; a2 = this plane
            move.w  H_DEPTH(a4),d5
            subq.w  #1,d5
.pl         btst    #0,v_scr+1(a5)
            beq.s   .acr
            lea     SCR_MARG*40(a2),a3      ; up / down: lines 64.. and 320..
            move.w  #PLANE_SIZE/4-1,d7
.v1         move.l  (a0),(a3)
            move.l  (a0)+,256*40(a3)
            addq.l  #4,a3
            dbf     d7,.v1
            bra.s   .pn
.acr        lea     SCR_MARG*96+8(a2),a3    ; across: lines 64..319, bytes 8.. and 48..
            move.w  #255,d7
.h1         moveq   #9,d4
.h2         move.l  (a0),(a3)
            move.l  (a0)+,40(a3)
            addq.l  #4,a3
            dbf     d4,.h2
            lea     96-40(a3),a3
            dbf     d7,.h1
.pn         add.l   v_plsz(a5),a2
            dbf     d5,.pl
            add.l   v_sstride(a5),a1
            dbf     d6,.buf
.pdone      bsr     ui_panel_blit           ; the HUD panel -> the normal display only
            move.l  v_work(a5),a0
            move.l  v_disp(a5),a1
            bsr     copy_planes
            btst    #0,v_scr+1(a5)
            bne.s   .vert
            move.w  #$0030,$92(a6)          ; across: one word early for the fine scroll,
            move.w  #$00d0,$94(a6)          ; 16-bit fetch on AGA (as a tile world)
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            move.w  #$0000,$1fc(a6)
.ocs        lea     cop_mods-V-128(a5),a0
            move.w  #-2,2(a0)
            move.w  #-2,6(a0)
            move.w  #0,10(a0)
            move.l  v_disp(a5),d0
            subq.l  #2,d0
            bsr     set_bpl
            move.w  #96-42,v_smod(a5)
            bra.s   .bobs
.vert       move.w  #0,v_smod(a5)
            tst.w   v_ddfs(a5)              ; a narrow map: the HUD fetches the whole width,
            beq.s   .vfull                  ; the play area (from the split) only its middle;
            move.w  #$0038,$92(a6)          ; 16-bit fetch on AGA
            move.w  #$00d0,$94(a6)
            btst    #0,H_FLAGS+1(a4)
            beq.s   .vocs
            move.w  #$0000,$1fc(a6)
.vocs       lea     cop_ddf-V-128(a5),a0    ; the copper puts the HUD's back each frame
            move.l  #$00920038,(a0)
            move.l  #$009400d0,4(a0)
.vfull      move.l  v_disp(a5),d0
            bsr     set_bpl
.bobs       move.w  #0,v_bob(a5)
            move.l  v_sblk(a5),a3
            cmp.w   #3,SC_NBUF(a3)
            bne.s   .txt
            move.l  v_sbuf(a5),d0           ; BOBs: buffers 0 and 1 are shown in turn,
            move.l  d0,v_bufa(a5)           ; 2 is the background they are wiped from
            add.l   v_sstride(a5),d0
            move.l  d0,v_bufb(a5)
            move.l  d0,v_draw(a5)
            add.l   v_sstride(a5),d0
            move.l  d0,v_back(a5)
            move.w  #1,v_bob(a5)
            move.w  #1,v_bobbuf(a5)
            move.w  #0,v_drawn(a5)
            move.l  #0,v_bobn(a5)
.txt        move.l  #0,v_dd2(a5)            ; text: the HUD strip only
            move.l  #0,v_ddk(a5)
            move.l  v_sbuf(a5),v_shbuf(a5)
            move.w  v_spos(a5),v_shpos(a5)
            move.w  v_spos(a5),v_dpos(a5)
            move.w  v_gradfix(a5),d1
            bsr     build_grad
            move.l  v_sbuf(a5),d0           ; show the first buffer
            move.w  v_spos(a5),d1
            bsr     scroll_show
            movem.l (sp)+,d0-d7/a0-a3
.r          rts

; back to the normal display (title, level cards, messages)
scroll_off: tst.w   v_scr(a5)
            beq     .r
            move.w  #0,v_scr(a5)
            move.w  #0,v_split(a5)
            move.w  #0,v_sdx(a5)
            move.w  #0,v_sdy(a5)
            move.w  #320,v_pw(a5)
            move.w  #0,v_xoff(a5)
            move.w  #0,v_ddfs(a5)
            lea     cop_ddf-V-128(a5),a0    ; (copper no-ops again)
            move.l  #$01fe0000,(a0)
            move.l  #$01fe0000,4(a0)
            move.w  v_hudrow0(a5),v_hudrow(a5)
            move.w  #$0038,$92(a6)
            move.w  #$00d0,$94(a6)
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            move.w  #$0003,$1fc(a6)
            move.w  #$00b8,$94(a6)
.ocs        lea     cop_mods-V-128(a5),a0
            move.w  #0,2(a0)
            move.w  #0,6(a0)
            move.w  #0,10(a0)
            move.l  v_disp(a5),d0
            bsr     set_bpl
            bsr     bob_plain
            move.w  v_gradfix(a5),d1
            bsr     build_grad
.r          rts

; the scenery moves on: v_spos, and v_sdx / v_sdy for the actors that move with it
scroll_tick:
            move.w  #0,v_sdx(a5)
            move.w  #0,v_sdy(a5)
            move.w  v_scr(a5),d1
            beq.s   .r
            move.l  v_sblk(a5),a0
            move.w  v_sacc(a5),d0
            add.w   SC_SPEED(a0),d0
            move.w  d0,d2
            and.w   #3,d2
            move.w  d2,v_sacc(a5)
            lsr.w   #2,d0                   ; d0 = pixels this frame
            beq.s   .r
            tst.l   v_map(a5)
            bne     map_tick
            move.w  v_spos(a5),d2
            cmp.w   #1,d1
            bne.s   .rt
            sub.w   d0,d2                   ; flying up: the picture moves down
            move.w  d0,v_sdy(a5)
            bra.s   .wv
.rt         cmp.w   #2,d1
            bne.s   .dn
            add.w   d0,d2                   ; flying right: it moves left
            neg.w   d0
            move.w  d0,v_sdx(a5)
            bra.s   .wh
.dn         cmp.w   #3,d1
            bne.s   .lf
            add.w   d0,d2                   ; flying down: it moves up
            neg.w   d0
            move.w  d0,v_sdy(a5)
            bra.s   .wv
.lf         sub.w   d0,d2                   ; flying left: it moves right
            move.w  d0,v_sdx(a5)
.wh         tst.w   d2                      ; across: 0..319
            bpl.s   .h1
            add.w   #320,d2
.h1         cmp.w   #320,d2
            blt.s   .set
            sub.w   #320,d2
            bra.s   .set
.wv         and.w   #255,d2                 ; down: 0..255
.set        move.w  d2,v_spos(a5)
.r          rts

; ============================================================================
;  scrolling map (version 10): drawn line by line as the view climbs it
; ============================================================================
; the view moves d0 lines up the map, drawing each line as it comes in; at the top it stops
map_tick:   move.w  v_camy(a5),d2
            sub.w   d0,d2
            bgt.s   .m1
            moveq   #0,d2                   ; the top: the end of the map
            move.w  #1,v_mend(a5)
.m1         move.w  v_camy(a5),d1
            sub.w   d2,d1                   ; d1 = lines it really moves
            beq.s   .r
            move.w  d1,v_sdy(a5)
            move.w  d2,v_camy(a5)
            move.w  d2,d0
            subq.w  #1,d1
.l          bsr     map_line
            addq.w  #1,d0
            dbf     d1,.l
            and.w   #255,d2
            move.w  d2,v_spos(a5)
.r          rts

; level start: the view at the bottom of the map, its first screen drawn, no waves out yet
map_start:  movem.l d0-d1/a0,-(sp)
            move.l  v_map(a5),a0
            move.w  MP_H(a0),d0
            lsl.w   #4,d0
            sub.w   #256,d0
            bpl.s   .h
            moveq   #0,d0
.h          move.w  d0,v_camy(a5)
            and.w   #255,d0
            move.w  d0,v_spos(a5)
            move.w  #0,v_spn(a5)
            move.w  #0,v_mend(a5)
            lea     v_spq(a5),a0
            moveq   #SPQ_MAX*2-1,d1
.q          move.l  #0,(a0)+
            dbf     d1,.q
            move.w  v_camy(a5),d0
            move.w  #255,d1
.l          bsr     map_line
            addq.w  #1,d0
            dbf     d1,.l
            movem.l (sp)+,d0-d1/a0
            rts

; map line d0 (pixels from the top of the map) -> ring line d0 & 255, both copies of the
; picture, every scroll buffer: drawn once (buffer 0, first copy), then copied
map_line:   movem.l d0-d7/a0-a3,-(sp)
            move.w  d0,d1
            lsr.w   #4,d1
            mulu    v_mcols(a5),d1
            tst.w   v_mword(a5)
            beq.s   .bc
            add.l   d1,d1                   ; (word cells)
.bc         move.l  v_mmap(a5),a0
            add.l   d1,a0                   ; a0 = its row of the map
            move.w  d0,d2
            and.w   #15,d2
            add.w   d2,d2                   ; d2 = the line in a tile picture (bytes)
            and.l   #255,d0
            add.w   #SCR_MARG,d0
            mulu    v_bpr(a5),d0            ; d0 = the line in a buffer (bytes)
            move.l  v_sbuf(a5),a2
            add.l   d0,a2                   ; a2 = buffer 0, this line
            move.l  v_plsz(a5),d3           ; d3 = a plane
            move.w  H_DEPTH(a4),d6
            subq.w  #1,d6                   ; d6 = planes - 1
            move.w  v_tbm(a5),d7
            move.l  v_mimg(a5),a1
            add.w   d2,a1                   ; a1 = line d2 of tile 0, plane 0
            move.l  a2,d4
            move.w  v_mcols(a5),d5
            subq.w  #1,d5
.col        moveq   #0,d1
            tst.w   v_mword(a5)
            beq.s   .cb
            move.w  (a0)+,d1
            bra.s   .cw
.cb         move.b  (a0)+,d1
.cw         mulu    d7,d1
            lea     0(a1,d1.l),a3           ; this tile's line, plane 0
            move.l  a2,-(sp)
            move.w  d6,d2
.pl         move.w  (a3),(a2)
            lea     32(a3),a3
            add.l   d3,a2
            dbf     d2,.pl
            move.l  (sp)+,a2
            addq.l  #2,a2
            dbf     d5,.col
            move.l  d4,a2                   ; the line drawn, each plane -> the second copy,
            move.w  v_bpr(a5),d5            ; and both copies in the other buffers
            lsr.w   #2,d5
            subq.w  #1,d5                   ; d5 = longs a line - 1 (an even number of tiles)
            move.w  v_bpr(a5),d7
            mulu    #256,d7                 ; d7 = the second copy, 256 lines on
            move.l  v_sblk(a5),a3
            move.w  SC_NBUF(a3),d4
            subq.w  #1,d4                   ; d4 = buffers - 1
            move.w  d6,d2
.cpl        move.l  a2,a0                   ; a0 = the line in this plane of buffer 0
            move.w  d4,d1
            move.l  a2,a1
            bra.s   .c2
.cbuf       add.l   v_sstride(a5),a1        ; the next buffer: its first copy too
            move.l  a0,a3
            move.l  a1,a2
            move.w  d5,d0
.cw1        move.l  (a3)+,(a2)+
            dbf     d0,.cw1
.c2         move.l  a0,a3                   ; and its second copy
            lea     0(a1,d7.l),a2
            move.w  d5,d0
.cw2        move.l  (a3)+,(a2)+
            dbf     d0,.cw2
            dbf     d1,.cbuf
            move.l  a0,a2
            add.l   d3,a2                   ; the next plane
            dbf     d2,.cpl
            movem.l (sp)+,d0-d7/a0-a3
            rts

; the map's spawners: each goes off when the view reaches it and sends out its wave,
; one every SP_GAP frames
spawn_tick: tst.l   v_map(a5)
            beq     .r
            tst.w   v_scr(a5)
            beq     .r
            movem.l d0-d7/a0-a3,-(sp)
            move.l  v_map(a5),a3
.trig       move.w  v_spn(a5),d0
            cmp.w   MP_NSP(a3),d0
            bhs.s   .run
            lsl.w   #4,d0                   ; x SP_SIZE
            move.l  MP_SP(a3),d1
            add.l   a4,d1
            move.l  d1,a0
            add.w   d0,a0                   ; a0 = the next spawner
            move.w  v_camy(a5),d1
            cmp.w   SP_TRIG(a0),d1
            bgt.s   .run                    ; not reached yet
            addq.w  #1,v_spn(a5)
            lea     v_spq(a5),a1            ; a free place for its wave
            moveq   #SPQ_MAX-1,d2
.q          tst.l   (a1)
            beq.s   .put
            addq.l  #8,a1
            dbf     d2,.q
            bra.s   .trig                   ; (all busy: this wave is lost)
.put        move.l  a0,(a1)
            move.w  SP_N(a0),4(a1)
            move.w  #0,6(a1)
            bra.s   .trig
.run        lea     v_spq(a5),a1
            moveq   #SPQ_MAX-1,d2
.w          tst.l   (a1)
            beq.s   .wn
            tst.w   6(a1)
            beq.s   .go
            subq.w  #1,6(a1)
            bra.s   .wn
.go         move.l  (a1),a0
            move.w  SP_N(a0),d3
            sub.w   4(a1),d3                ; d3 = which one of the wave
            bsr     spawn_one
            move.w  SP_GAP(a0),6(a1)
            subq.w  #1,4(a1)
            bgt.s   .wn
            move.l  #0,(a1)
.wn         addq.l  #8,a1
            dbf     d2,.w
            movem.l (sp)+,d0-d7/a0-a3
.r          rts

; one of a wave: spawner a0, d3 = which one (0 = the first)
spawn_one:  movem.l d0-d7/a0-a2,-(sp)
            move.w  SP_ACT(a0),d4
            cmp.w   H_NACT(a4),d4
            bhs     .out
            move.l  a0,a1                   ; a1 = the spawner
            bsr     free_copy
            beq     .out
            move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
            bsr     actor_rec
            move.l  a0,a2                   ; a2 = the actor
            moveq   #0,d0
            move.b  SP_PAT(a1),d0
            cmp.b   #$ff,d0
            bne.s   .p
            move.w  A_PAT(a2),d0
.p          move.w  d0,v_pat(a5,d5.w)
            moveq   #0,d0
            move.b  SP_EDGE(a1),d0
            move.w  d0,v_edge(a5,d5.w)
            move.w  SP_DX(a1),d2            ; along its edge: which one x the spacing
            muls    d3,d2
            move.w  SP_X(a1),d0
            move.w  SP_Y(a1),d1
            btst    #0,SP_EDGE(a1)
            bne.s   .side
            add.w   d2,d0
            bra.s   .pos
.side       add.w   d2,d1
.pos        cmp.w   #4,v_pat(a5,d5.w)       ; on the ground: where its spot on the map is now
            bne.s   .put
            add.w   SP_TRIG(a1),d1
            sub.w   v_camy(a5),d1
.put        bsr     come_out
            move.w  d3,d0                   ; every other one zigzags off the other way
            and.w   #1,d0
            move.w  d0,v_dx(a5,d5.w)
            move.w  d3,d0                   ; each one weaves a quarter wave on from the one
            lsl.w   #4,d0                   ; before, so a wave does not fly one track
            and.w   #63,d0
            move.w  d0,v_tmr(a5,d5.w)
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; d4 = an actor -> d4 = a copy of it that is not out (Z clear), Z set: all out. Uses d0
free_copy:  movem.l d1-d2/a0,-(sp)
            bsr     actor_rec
            move.w  A_TYPE(a0),d2           ; d2 = its type (the first copy)
            move.w  d2,d4
.l          cmp.w   H_NACT(a4),d4
            bhs.s   .no
            bsr     actor_rec
            cmp.w   A_TYPE(a0),d2
            bne.s   .no
            move.w  d4,d1
            lsl.w   #ACTV_SHIFT,d1
            tst.w   v_vis(a5,d1.w)
            beq.s   .yes
            addq.w  #1,d4
            bra.s   .l
.no         moveq   #0,d0
            bra.s   .o
.yes        moveq   #1,d0
.o          movem.l (sp)+,d1-d2/a0
            tst.w   d0
            rts

; actor d5 / a2 comes out at d0 / d1: shown, unhurt, its animation from the start. A
; flyer starts its pattern there (v_pat / v_edge) and is gone when it leaves
come_out:   move.w  #1,v_vis(a5,d5.w)
            move.w  #0,v_life(a5,d5.w)
            move.w  #0,v_safe(a5,d5.w)
            move.w  #0,v_thr(a5,d5.w)
            move.w  #0,v_hitf(a5,d5.w)
            move.w  #-1,v_aset(a5,d5.w)
            move.w  #-1,v_aplay(a5,d5.w)
            and.w   #$00ff,v_edge(a5,d5.w)
            move.w  d0,-(sp)
            move.w  A_HP(a2),d0
            bne.s   .hp
            moveq   #1,d0
.hp         move.w  d0,v_hp(a5,d5.w)
            move.w  A_FRATE(a2),d0
            lsr.w   #1,d0
            move.w  d0,v_ftmr(a5,d5.w)
            move.w  (sp)+,d0
            cmp.w   #ROLE_FLY,A_ROLE(a2)
            beq     fly_put
            move.w  d0,v_ax(a5,d5.w)
            move.w  d1,v_ay(a5,d5.w)
            move.w  d0,v_px(a5,d5.w)
            move.w  d1,v_py(a5,d5.w)
            move.w  d0,v_ox(a5,d5.w)
            move.w  d1,v_oy(a5,d5.w)
            rts

; d0 = scroll buffer, d1 = the view's place in the picture -> the bitplane
; pointers and fine scroll at the copper split
scroll_show:
            movem.l d0-d4/a0,-(sp)
            move.l  d0,v_shbuf(a5)          ; (build_grad shows it again after a rebuild)
            move.w  d1,v_shpos(a5)
            moveq   #0,d3
            btst    #0,v_scr+1(a5)
            beq.s   .ac
            move.w  d1,d3                   ; up / down: line SCR_MARG + place + the HUD's lines
            add.w   #SCR_MARG,d3
            add.w   v_hudlines(a5),d3
            mulu    v_bpr(a5),d3
            moveq   #0,d2                   ; no fine scroll
            bra.s   .ptr
.ac         move.w  d1,d4                   ; across: the screen starts at pixel X0 = SCR_MARG + place
            add.w   #SCR_MARG,d4
            move.w  d4,d2
            and.w   #15,d2
            neg.w   d2
            add.w   #16,d2
            and.w   #15,d2                  ; delay (16 - (X0 & 15)) & 15
            subq.w  #1,d4
            lsr.w   #4,d4
            add.w   d4,d4                   ; first word fetched, one early for the fine scroll
            move.w  v_hudlines(a5),d3
            add.w   #SCR_MARG,d3
            mulu    #96,d3
            and.l   #$ffff,d4
            add.l   d4,d3
.ptr        add.l   d0,d3
            move.l  v_csplit(a5),a0
            move.w  H_DEPTH(a4),d4
            subq.w  #1,d4
.p          swap    d3
            move.w  d3,2(a0)
            swap    d3
            move.w  d3,6(a0)
            addq.l  #8,a0
            add.l   v_plsz(a5),d3
            dbf     d4,.p
            move.w  d2,d1                   ; BPLCON1: both playfields
            lsl.w   #4,d1
            or.w    d2,d1
            move.w  d1,10(a0)
            movem.l (sp)+,d0-d4/a0
            rts

; ============================================================================
;  flyers (role 10): shoot 'em up waves
; ============================================================================
; a flyer (d5, a2) to its start: where it was placed, one screen beyond the edge
; it comes in from, so a group placed on the stage flies in keeping its shape
fly_start:  movem.l d0-d2,-(sp)
            move.w  A_X(a2),d0
            move.w  A_Y(a2),d1
            moveq   #3,d2
            and.b   v_edge+1(a5,d5.w),d2
            bne.s   .r
            sub.w   #256,d1                 ; from the top
            bra.s   .go
.r          cmp.w   #1,d2
            bne.s   .b
            add.w   v_pw(a5),d0             ; from the right
            bra.s   .go
.b          cmp.w   #2,d2
            bne.s   .l
            add.w   #256,d1                 ; from the bottom
            bra.s   .go
.l          sub.w   v_pw(a5),d0             ; from the left
.go         bsr.s   fly_put
            movem.l (sp)+,d0-d2
            rts

; a flyer (d5, a2) to d0 / d1, its pattern starting again there
fly_put:    move.w  d0,v_ax(a5,d5.w)
            move.w  d1,v_ay(a5,d5.w)
            move.w  d0,v_px(a5,d5.w)
            move.w  d1,v_py(a5,d5.w)
            move.w  d0,v_ox(a5,d5.w)
            move.w  d1,v_oy(a5,d5.w)
; the line across a flyer (d5, a2) weaves round becomes where it is now
fly_rebase: move.w  d2,-(sp)
            moveq   #1,d2
            and.b   v_edge+1(a5,d5.w),d2        ; from the top or bottom: across is x
            bne.s   .y
            move.w  v_ax(a5,d5.w),v_base(a5,d5.w)
            bra.s   .t
.y          move.w  v_ay(a5,d5.w),v_base(a5,d5.w)
.t          move.w  #0,v_tmr(a5,d5.w)
            move.w  (sp)+,d2
            rts

; a flyer (d5, a2) comes in again at a random place across, a little beyond its edge
fly_again:  movem.l d0-d4,-(sp)
            moveq   #3,d3
            and.b   v_edge+1(a5,d5.w),d3        ; d3 = its edge
            bsr     fly_lim                 ; d1 / d2 = the room across
            sub.w   d1,d2
            addq.w  #1,d2
            bgt.s   .rm
            moveq   #1,d2
.rm         bsr     rand
            and.l   #$ffff,d0
            divu    d2,d0
            swap    d0
            add.w   d0,d1                   ; d1 = across
            cmp.w   #4,v_pat(a5,d5.w)            ; one that moves with the scenery keeps its lane
            bne.s   .lane
            move.w  v_base(a5,d5.w),d1
.lane
            bsr     rand
            and.w   #63,d0
            move.w  d0,d4                   ; d4 = how far beyond the edge
            tst.w   d3
            bne.s   .r
            move.w  d1,d0                   ; from the top: above it
            move.w  A_YMAX(a2),d1
            sub.w   #256,d1
            sub.w   d4,d1
            bra.s   .go
.r          cmp.w   #1,d3
            bne.s   .b
            move.w  v_pw(a5),d0             ; from the right
            add.w   d4,d0
            bra.s   .go
.b          cmp.w   #2,d3
            bne.s   .l
            move.w  d1,d0                   ; from the bottom
            move.w  #256,d1
            add.w   d4,d1
            bra.s   .go
.l          move.w  A_XMAX(a2),d0           ; from the left
            sub.w   v_pw(a5),d0
            sub.w   d4,d0
.go         bsr     fly_put
            movem.l (sp)+,d0-d4
            rts

; d3 = a flyer's edge (a2) -> d1 / d2 = the least / most its place across can be:
; x 0..A_XMAX, or y under the HUD strip (scrolling) .. A_YMAX
fly_lim:    btst    #0,d3
            bne.s   .y
            moveq   #0,d1
            move.w  A_XMAX(a2),d2
            rts
.y          moveq   #0,d1
            tst.w   v_split(a5)
            beq.s   .y1
            move.w  v_hudlines(a5),d1
.y1         move.w  A_YMAX(a2),d2
            rts

; a flyer coming in to its place (pattern 5) -> d0 = how far it still has to go (0 = there)
fly_rest:   moveq   #3,d0
            and.b   v_edge+1(a5,d5.w),d0
            beq.s   .t
            cmp.w   #1,d0
            beq.s   .r
            cmp.w   #2,d0
            beq.s   .b
            move.w  A_X(a2),d0              ; from the left
            sub.w   v_ax(a5,d5.w),d0
            bra.s   .c
.r          move.w  v_ax(a5,d5.w),d0        ; from the right
            sub.w   A_X(a2),d0
            bra.s   .c
.b          move.w  v_ay(a5,d5.w),d0        ; from the bottom
            sub.w   A_Y(a2),d0
            bra.s   .c
.t          move.w  A_Y(a2),d0              ; from the top
            sub.w   v_ay(a5,d5.w),d0
.c          tst.w   d0
            bpl.s   .x
            moveq   #0,d0
.x          rts

; a shown flyer (d5, d7, a2): along, away from its edge, at its speed; across by
; its pattern. Off the far edge it comes in again (A_ENTER bit 0) or hides.
fly_move:   movem.l d0-d4/a0,-(sp)
            moveq   #3,d3
            and.b   v_edge+1(a5,d5.w),d3        ; d3 = its edge
            move.w  v_pat(a5,d5.w),d4       ; d4 = its pattern
            cmp.w   #4,d4                   ; 4: it moves with the scenery
            bne.s   .own
            move.w  v_sdx(a5),d0
            add.w   d0,v_ax(a5,d5.w)
            move.w  v_sdy(a5),d0
            add.w   d0,v_ay(a5,d5.w)
            bra     .exit
.own        move.w  v_spd(a5,d5.w),d0       ; d0 = how far along this frame
            cmp.w   #5,d4                   ; 5: in to its place, then across (a boss)
            bne.s   .along
            bsr     fly_rest
            tst.w   d0
            beq     .zig                    ; there: it patrols across
            cmp.w   v_spd(a5,d5.w),d0
            ble.s   .along
            move.w  v_spd(a5,d5.w),d0
.along      cmp.w   #1,d3
            beq.s   .gr
            cmp.w   #2,d3
            beq.s   .gb
            cmp.w   #3,d3
            beq.s   .gl
            add.w   d0,v_ay(a5,d5.w)        ; from the top: down
            bra.s   .pat
.gr         sub.w   d0,v_ax(a5,d5.w)        ; from the right: left
            bra.s   .pat
.gb         sub.w   d0,v_ay(a5,d5.w)        ; from the bottom: up
            bra.s   .pat
.gl         add.w   d0,v_ax(a5,d5.w)        ; from the left: right
.pat        cmp.w   #1,d4
            beq.s   .wave
            cmp.w   #2,d4
            beq.s   .zig
            cmp.w   #3,d4
            beq     .home
            bra     .exit                   ; 0 straight (5 still coming in)

.wave       addq.w  #1,v_tmr(a5,d5.w)       ; 1: weaves either side of the line it came in on
            move.w  v_tmr(a5,d5.w),d0
            and.w   #63,d0
            lea     sine64(pc),a0
            move.b  0(a0,d0.w),d0
            ext.w   d0
            add.w   v_base(a5,d5.w),d0
            bra     .set

.zig        bsr     .across                 ; 2 (and a boss in its place): across and back, edge to edge
            move.w  v_spd(a5,d5.w),d2
            tst.w   v_dx(a5,d5.w)
            bne.s   .zl
            add.w   d2,d0
            bsr     fly_lim
            cmp.w   d2,d0
            ble     .set
            move.w  d2,d0
            move.w  #1,v_dx(a5,d5.w)
            bra     .set
.zl         sub.w   d2,d0
            bsr     fly_lim
            cmp.w   d1,d0
            bge     .set
            move.w  d1,d0
            move.w  #0,v_dx(a5,d5.w)
            bra     .set

.home       move.w  d4,-(sp)                ; 3: drifts across towards the player
            move.w  H_PLAYER(a4),d4
            bmi.s   .hn
            cmp.w   H_NACT(a4),d4
            bhs.s   .hn
            bsr     actor_rec               ; a0 = the player's record
            lsl.w   #ACTV_SHIFT,d4
            btst    #0,d3
            bne.s   .hy
            move.w  A_BX0(a0),d1            ; player's middle - its middle, across
            add.w   A_BX1(a0),d1
            sub.w   A_BX0(a2),d1
            sub.w   A_BX1(a2),d1
            asr.w   #1,d1
            add.w   v_ax(a5,d4.w),d1
            sub.w   v_ax(a5,d5.w),d1
            bra.s   .hs
.hy         move.w  A_BY0(a0),d1
            add.w   A_BY1(a0),d1
            sub.w   A_BY0(a2),d1
            sub.w   A_BY1(a2),d1
            asr.w   #1,d1
            add.w   v_ay(a5,d4.w),d1
            sub.w   v_ay(a5,d5.w),d1
.hs         move.w  (sp)+,d4
            bsr     .across
            tst.w   d1
            beq     .exit
            bmi.s   .hm
            addq.w  #1,d0
            bra.s   .set
.hm         subq.w  #1,d0
            bra.s   .set
.hn         move.w  (sp)+,d4
            bra.s   .exit

.set        move.w  d0,-(sp)                ; d0 -> its place across, kept on the screen
            bsr     fly_lim
            move.w  (sp)+,d0
            cmp.w   d1,d0
            bge.s   .s1
            move.w  d1,d0
.s1         cmp.w   d2,d0
            ble.s   .s2
            move.w  d2,d0
.s2         btst    #0,d3
            bne.s   .sy
            move.w  d0,v_ax(a5,d5.w)
            bra.s   .exit
.sy         move.w  d0,v_ay(a5,d5.w)

.exit       cmp.w   #5,d4                   ; a boss never leaves
            beq.s   .out
            tst.w   d3                      ; gone off the far edge?
            bne.s   .xr
            cmp.w   #256,v_ay(a5,d5.w)
            blt.s   .out
            bra.s   .gone
.xr         cmp.w   #1,d3
            bne.s   .xb
            move.w  A_XMAX(a2),d0
            sub.w   v_pw(a5),d0
            cmp.w   v_ax(a5,d5.w),d0
            blt.s   .out
            bra.s   .gone
.xb         cmp.w   #2,d3
            bne.s   .xl
            move.w  A_YMAX(a2),d0
            sub.w   #256,d0
            cmp.w   v_ay(a5,d5.w),d0
            blt.s   .out
            bra.s   .gone
.xl         move.w  v_ax(a5,d5.w),d0
            cmp.w   v_pw(a5),d0
            blt.s   .out
.gone       btst    #0,v_edge(a5,d5.w)      ; it comes back, or it is gone
            beq.s   .hide
            bsr     fly_again
            bra.s   .out
.hide       move.w  #0,v_vis(a5,d5.w)
.out        movem.l (sp)+,d0-d4/a0
            rts

; d0 = its place across now
.across     btst    #0,d3
            bne.s   .ay
            move.w  v_ax(a5,d5.w),d0
            rts
.ay         move.w  v_ay(a5,d5.w),d0
            rts

sine64:     dc.b    0,4,8,12,15,19,22,25,28,31,33,35,37,38,39,40,40,40,39,38,37,35,33,31,28,25,22,19,15,12,8,4
            dc.b    0,-4,-8,-12,-15,-19,-22,-25,-28,-31,-33,-35,-37,-38,-39,-40,-40,-40,-39,-38,-37,-35,-33,-31,-28,-25,-22,-19,-15,-12,-8,-4
            even

; ============================================================================
;  options (role 11) and power-ups
; ============================================================================
; the player's trail all at its place (level start, sent home)
trail_reset:
            movem.l d0-d2/a0,-(sp)
            move.w  H_PLAYER(a4),d0
            bmi.s   .r
            cmp.w   H_NACT(a4),d0
            bhs.s   .r
            lsl.w   #ACTV_SHIFT,d0
            move.w  v_ax(a5,d0.w),d1
            swap    d1
            move.w  v_ay(a5,d0.w),d1
            lea     v_trail(a5),a0
            moveq   #63,d2
.f          move.l  d1,(a0)+
            dbf     d2,.f
.r          movem.l (sp)+,d0-d2/a0
            rts

; d4 = an actor that was moved by a rule: the player's trail starts again where it is
trail_check:
            cmp.w   H_PLAYER(a4),d4
            beq.s   trail_reset
            rts

; options follow the player's trail: the trail takes the player's place whenever it
; moves, and option k sits k x OPT_GAP steps back along it
opt_follow: movem.l d0-d7/a0-a2,-(sp)
            move.w  H_PLAYER(a4),d4
            bmi     .out
            cmp.w   H_NACT(a4),d4
            bhs     .out
            bsr     actor_rec
            move.l  a0,a1                   ; a1 = the player's record
            move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
            move.w  v_ax(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d1
            cmp.w   v_ox(a5,d5.w),d0        ; moved this frame: a new step on the trail
            bne.s   .step
            cmp.w   v_oy(a5,d5.w),d1
            beq.s   .place
.step       move.w  v_trn(a5),d2
            addq.w  #1,d2
            and.w   #63,d2
            move.w  d2,v_trn(a5)
            lsl.w   #2,d2
            lea     v_trail(a5),a0
            move.w  d0,0(a0,d2.w)
            move.w  d1,2(a0,d2.w)
.place      move.w  H_NACT(a4),d6
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            moveq   #0,d7
.o          cmp.w   #ROLE_OPT,A_ROLE(a2)
            bne.s   .n
            move.w  d7,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)
            beq.s   .n
            move.w  A_RANK(a2),d2           ; its step on the trail
            mulu    #OPT_GAP,d2
            neg.w   d2
            add.w   v_trn(a5),d2
            and.w   #63,d2
            lsl.w   #2,d2
            lea     v_trail(a5),a0
            move.w  A_BX0(a1),d0            ; centred where the player's middle was
            add.w   A_BX1(a1),d0
            sub.w   A_BX0(a2),d0
            sub.w   A_BX1(a2),d0
            asr.w   #1,d0
            add.w   0(a0,d2.w),d0
            move.w  A_BY0(a1),d1
            add.w   A_BY1(a1),d1
            sub.w   A_BY0(a2),d1
            sub.w   A_BY1(a2),d1
            asr.w   #1,d1
            add.w   2(a0,d2.w),d1
            move.w  d0,v_ax(a5,d5.w)
            move.w  d1,v_ay(a5,d5.w)
.n          lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt.s   .o
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; shows the next hidden option -> d0 = 1 (Z clear) when there was one
opt_add:    movem.l d1/d4-d7/a0,-(sp)
            moveq   #0,d7
.f          cmp.w   H_NACT(a4),d7
            bge.s   .none
            move.w  d7,d4
            bsr     actor_rec
            cmp.w   #ROLE_OPT,A_ROLE(a0)
            bne.s   .n
            move.w  A_FROM(a0),d1
            cmp.w   v_level(a5),d1
            bgt.s   .n
            move.w  d7,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)
            bne.s   .n
            move.w  #1,v_vis(a5,d5.w)
            moveq   #1,d0
            bra.s   .out
.n          addq.w  #1,d7
            bra.s   .f
.none       moveq   #0,d0
.out        movem.l (sp)+,d1/d4-d7/a0
            tst.w   d0
            rts

; DO 23: a power-up for the player - R_VAL 0 more firepower, 1 more speed,
; 2 one more option (a multiple), 3 loses them all (it was hit)
act_power:  movem.l d0-d7/a0-a2,-(sp)
            move.w  H_PLAYER(a4),d4
            bmi     .out
            cmp.w   H_NACT(a4),d4
            bhs     .out
            move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
            move.w  R_VAL(a3),d0
            bne.s   .nfire
            cmp.w   #POWER_MAX,v_power(a5)
            bhs     .out
            addq.w  #1,v_power(a5)
            bra     .out
.nfire      cmp.w   #1,d0
            bne.s   .nspd
            cmp.w   #8,v_spd(a5,d5.w)
            bhs     .out
            addq.w  #1,v_spd(a5,d5.w)
            addq.w  #1,v_pspd(a5)
            bra     .out
.nspd       cmp.w   #2,d0
            bne.s   .nopt
            bsr     opt_add
            beq     .out
            addq.w  #1,v_nopt(a5)
            bra     .out
.nopt       cmp.w   #4,d0                   ; 4: homing missiles (one, then two at a time)
            bne.s   .nmis
            cmp.w   #MISS_MAX,v_miss(a5)
            bhs     .out
            addq.w  #1,v_miss(a5)
            bra     .out
.nmis       cmp.w   #3,d0
            bne     .out
            move.w  #0,v_miss(a5)
            move.w  #0,v_power(a5)          ; lose them all
            move.w  #0,v_pspd(a5)
            move.w  #0,v_nopt(a5)
            move.w  v_spd0(a5,d5.w),v_spd(a5,d5.w)
            moveq   #0,d7
.oh         cmp.w   H_NACT(a4),d7
            bge.s   .out
            move.w  d7,d4
            bsr     actor_rec
            cmp.w   #ROLE_OPT,A_ROLE(a0)
            bne.s   .on
            move.w  d7,d1
            lsl.w   #ACTV_SHIFT,d1
            move.w  #0,v_vis(a5,d1.w)
.on         addq.w  #1,d7
            bra.s   .oh
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; ============================================================================
;  effects (role 12): explosions and sparks
; ============================================================================
; DO 24: set off effect d4 on actor R_VAL. If it is already going, the next effect
; after it goes instead (a few in a row: several at once); with all of them going
; the one named starts again. It plays its Idle animation once round, then hides.
act_effect: movem.l d0-d7/a0-a2,-(sp)
            cmp.w   H_NACT(a4),d4
            bhs     .out
            bsr     ctx_val
            move.w  d0,d6
            cmp.w   H_NACT(a4),d6
            bhs     .out
            move.w  d4,d3                   ; d3 = the one named
.find       move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)
            beq.s   .got
            addq.w  #1,d4
            cmp.w   H_NACT(a4),d4
            bhs.s   .named
            bsr     actor_rec
            cmp.w   A_TYPE(a0),d3           ; its copies
            beq.s   .find
.named      move.w  d3,d4
            move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
.got        bsr     actor_rec
            move.l  a0,a2                   ; a2 = the effect's record
            move.w  d6,d4
            bsr     actor_rec               ; a0 = where it goes off
            lsl.w   #ACTV_SHIFT,d6
            move.w  A_BX0(a0),d0            ; centred on it, kept on the screen
            add.w   A_BX1(a0),d0
            sub.w   A_BX0(a2),d0
            sub.w   A_BX1(a2),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d6.w),d0
            bpl.s   .x0
            moveq   #0,d0
.x0         cmp.w   A_XMAX(a2),d0
            ble.s   .x1
            move.w  A_XMAX(a2),d0
.x1         move.w  A_BY0(a0),d1
            add.w   A_BY1(a0),d1
            sub.w   A_BY0(a2),d1
            sub.w   A_BY1(a2),d1
            asr.w   #1,d1
            add.w   v_ay(a5,d6.w),d1
            bpl.s   .y0
            moveq   #0,d1
.y0         cmp.w   A_YMAX(a2),d1
            ble.s   .y1
            move.w  A_YMAX(a2),d1
.y1         move.w  d0,v_ax(a5,d5.w)
            move.w  d1,v_ay(a5,d5.w)
            move.w  d0,v_px(a5,d5.w)
            move.w  d1,v_py(a5,d5.w)
            move.w  #1,v_vis(a5,d5.w)
            move.w  #-1,v_aset(a5,d5.w)     ; its animation from the first frame
            move.w  #MOMENT,d0              ; shown for its Idle animation once round
            move.l  A_ANIM(a2),d1
            beq.s   .t
            lea     0(a4,d1.l),a0
            move.w  AN_N(a0),d0
            mulu    AN_RATE(a0),d0
            addq.w  #1,d0
.t          move.w  d0,v_life(a5,d5.w)
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; for each shot actor: the actors a WHEN 11 rule names it hitting (a = b: anything,
; every bit). Shots only stop at those, so they fly through options, pickups and
; explosions. No rule for a shot: 0, it stops at anything (as it always did).
hit_masks:  movem.l d0-d2/d6/a0-a1,-(sp)
            lea     v_hitmask(a5),a1
            moveq   #MAX_ACT-1,d0
.c          move.l  #0,(a1)+
            dbf     d0,.c
            move.w  H_NRULE(a4),d6
            beq.s   .r
            subq.w  #1,d6
            move.l  H_RULES(a4),d0
            lea     0(a4,d0.l),a0
            lea     v_hitmask(a5),a1
.l          cmp.w   #11,R_WHEN(a0)
            bne.s   .n
            move.w  R_A(a0),d1
            cmp.w   #MAX_ACT,d1
            bhs.s   .n
            lsl.w   #2,d1
            move.w  R_B(a0),d2
            cmp.w   R_A(a0),d2
            bne.s   .one
            move.l  #-1,0(a1,d1.w)
            bra.s   .n
.one        cmp.w   #MAX_ACT,d2
            bhs.s   .n
            move.w  d2,d0                   ; every copy of it
            bsr     type_mask
            or.l    d0,0(a1,d1.w)
.n          move.w  R_NAND(a0),d0
            lsl.w   #3,d0
            lea     RULE_SIZE(a0,d0.w),a0
            dbf     d6,.l
.r          movem.l (sp)+,d0-d2/d6/a0-a1
            rts

; ============================================================================
;  tile world (version 6)
; ============================================================================
; level start: a fresh copy of the map, nothing carried, then on screen
tiles_start:
            tst.l   v_tiles(a5)
            beq     .r
            move.l  v_tiles(a5),a0
            move.l  T_MAP(a0),d0
            lea     0(a4,d0.l),a0           ; designed map -> map as played
            move.l  v_wmap(a5),a1
            move.w  v_tw(a5),d0
            mulu    v_th(a5),d0
            move.w  v_tcell(a5),d1
            lsl.l   d1,d0                   ; bytes
            addq.l  #3,d0
            lsr.l   #2,d0                   ; longs (both are long aligned)
            subq.l  #1,d0
.cp         move.l  (a0)+,(a1)+
            subq.l  #1,d0
            bpl.s   .cp
            lea     v_inv(a5),a0
            move.w  #511,d0
.ci         move.w  #0,(a0)+
            dbf     d0,.ci
            move.w  #0,v_sel(a5)
            move.w  #0,v_tool(a5)
            move.w  #0,v_menu(a5)
            move.w  #0,v_fwait(a5)
            move.w  #0,v_swing(a5)
            move.w  #0,v_swcool(a5)
            move.w  #0,v_digt(a5)
            move.l  #-1,v_digc(a5)
            bsr     tiles_on
.r          rts

; the tile world on screen: the HUD strip shows the top lines of the normal
; display, then the copper switches to the scrolling picture
tiles_on:   tst.l   v_tiles(a5)
            beq     .r
            move.w  #1,v_tmode(a5)
            move.w  #1,v_split(a5)
            move.w  v_tline(a5),d0          ; modulo under the split: the picture's line less the 42 bytes fetched
            sub.w   #42,d0
            move.w  d0,v_smod(a5)
            move.w  #0,v_hudrow(a5)
            move.w  #$0030,$92(a6)          ; DDFSTRT one word early: room for the fine scroll
            move.w  #$00d0,$94(a6)          ; DDFSTOP: 21 words a line
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            move.w  #$0000,$1fc(a6)         ; AGA: FMODE 16-bit fetch while scrolling
.ocs        lea     cop_mods-V-128(a5),a0
            move.w  #-2,2(a0)               ; HUD lines: 21 words fetched, 20 shown
            move.w  #-2,6(a0)
            move.w  #0,10(a0)
            move.l  v_disp(a5),d0
            subq.l  #2,d0
            bsr     set_bpl
            move.w  v_gradfix(a5),d1
            bsr     build_grad
            move.w  #-100,v_tx0(a5)         ; draw the whole picture
            bsr     cam_follow
            bsr     cam_window
            bsr     cop_scroll
.r          rts

; back to the normal display (title, level cards, messages)
tiles_off:  tst.w   v_tmode(a5)
            beq     .r
            move.w  #0,v_tmode(a5)
            move.w  #0,v_split(a5)
            move.w  v_hudrow0(a5),v_hudrow(a5)
            move.w  #$0038,$92(a6)
            move.w  #$00d0,$94(a6)
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            move.w  #$0003,$1fc(a6)
            move.w  #$00b8,$94(a6)
.ocs        lea     cop_mods-V-128(a5),a0
            move.w  #0,2(a0)
            move.w  #0,6(a0)
            move.w  #0,10(a0)
            move.l  v_disp(a5),d0
            bsr     set_bpl
            move.w  v_gradfix(a5),d1
            bsr     build_grad
.r          rts

; camera on the player, kept inside the map
cam_follow: tst.w   v_tmode(a5)
            beq     .r
            movem.l d0-d4,-(sp)
            move.w  v_tsh(a5),d4
            moveq   #0,d0
            moveq   #0,d1
            move.w  H_PLAYER(a4),d2
            bmi.s   .cl
            lsl.w   #ACTV_SHIFT,d2
            move.w  v_ax(a5,d2.w),d0
            sub.w   #160-8,d0
            move.w  v_ay(a5,d2.w),d1
            sub.w   #136-12,d1
.cl         tst.w   d0
            bge.s   .x1
            moveq   #0,d0
.x1         move.w  v_tw(a5),d3
            lsl.w   d4,d3
            sub.w   #320,d3
            cmp.w   d3,d0
            ble.s   .x2
            move.w  d3,d0
.x2         tst.w   d1
            bge.s   .y1
            moveq   #0,d1
.y1         move.w  v_th(a5),d3
            lsl.w   d4,d3
            sub.w   #256,d3
            cmp.w   d3,d1
            ble.s   .y2
            move.w  d3,d1
.y2         move.w  d0,v_camx(a5)
            move.w  d1,v_camy(a5)
            movem.l (sp)+,d0-d4
.r          rts

;  keeps the NCOL x NROW tiles round the camera drawn: one new column / row
; per tile moved, or everything after a jump (level start, an actor sent home)
cam_window: tst.w   v_tmode(a5)
            beq     .r
            movem.l d0-d5,-(sp)
            move.w  v_tsh(a5),d5
            move.w  v_camx(a5),d2           ; d2 / d3 = wanted top-left tile
            lsr.w   d5,d2
            move.w  v_tw(a5),d0
            sub.w   v_tncol(a5),d0
            cmp.w   d0,d2
            ble.s   .a
            move.w  d0,d2
.a          move.w  v_camy(a5),d3
            lsr.w   d5,d3
            move.w  v_th(a5),d0
            sub.w   v_tnrow(a5),d0
            cmp.w   d0,d3
            ble.s   .b
            move.w  d0,d3
.b          move.w  d2,d4
            sub.w   v_tx0(a5),d4
            bpl.s   .c
            neg.w   d4
.c          cmp.w   #1,d4
            bgt.s   .all
            move.w  d3,d4
            sub.w   v_ty0(a5),d4
            bpl.s   .d
            neg.w   d4
.d          cmp.w   #1,d4
            bgt.s   .all
            cmp.w   v_tx0(a5),d2            ; one column
            beq.s   .rows
            bgt.s   .right
            subq.w  #1,v_tx0(a5)            ; moved left: the new column is the first
            move.w  v_tx0(a5),d0
            bsr     draw_col
            bra.s   .rows
.right      addq.w  #1,v_tx0(a5)            ; moved right: the new column is the last
            move.w  v_tx0(a5),d0
            add.w   v_tncol(a5),d0
            subq.w  #1,d0
            bsr     draw_col
.rows       cmp.w   v_ty0(a5),d3            ; one row
            beq.s   .out
            bgt.s   .down
            subq.w  #1,v_ty0(a5)
            move.w  v_ty0(a5),d1
            bsr     draw_row
            bra.s   .out
.down       addq.w  #1,v_ty0(a5)
            move.w  v_ty0(a5),d1
            add.w   v_tnrow(a5),d1
            subq.w  #1,d1
            bsr     draw_row
            bra.s   .out
.all        move.w  d2,v_tx0(a5)            ; everything
            move.w  d3,v_ty0(a5)
            move.w  d3,d1
            move.w  v_tnrow(a5),d4
            subq.w  #1,d4
.al         bsr     draw_row
            addq.w  #1,d1
            dbf     d4,.al
.out        movem.l (sp)+,d0-d5
.r          rts

; d0 = map column: its NROW tiles in the picture
draw_col:   movem.l d1/d4,-(sp)
            move.w  v_ty0(a5),d1
            move.w  v_tnrow(a5),d4
            subq.w  #1,d4
.c          bsr     draw_cell
            addq.w  #1,d1
            dbf     d4,.c
            movem.l (sp)+,d1/d4
            rts

; d1 = map row: its NCOL tiles in the picture
draw_row:   movem.l d0/d4,-(sp)
            move.w  v_tx0(a5),d0
            move.w  v_tncol(a5),d4
            subq.w  #1,d4
.c          bsr     draw_cell
            addq.w  #1,d0
            dbf     d4,.c
            movem.l (sp)+,d0/d4
            rts

; d0 = column, d1 = row -> d2 = map cell (long), d3 = its tile
map_get:    moveq   #0,d2
            move.w  d1,d2
            mulu    v_tw(a5),d2
            moveq   #0,d3
            move.w  d0,d3
            add.l   d3,d2
            move.l  a0,-(sp)
            move.l  v_wmap(a5),a0
            moveq   #0,d3
            tst.w   v_tcell(a5)
            bne.s   .w
            move.b  0(a0,d2.l),d3
            move.l  (sp)+,a0
            rts
.w          add.l   d2,a0
            add.l   d2,a0
            move.w  (a0),d3
            move.l  (sp)+,a0
            rts

; map cell d2 (long) = tile d3
map_put:    move.l  a0,-(sp)
            move.l  v_wmap(a5),a0
            tst.w   v_tcell(a5)
            bne.s   .w
            move.b  d3,0(a0,d2.l)
            move.l  (sp)+,a0
            rts
.w          add.l   d2,a0
            add.l   d2,a0
            move.w  d3,(a0)
            move.l  (sp)+,a0
            rts

; d0 = column, d1 = row: draws that map tile into the scrolling picture.
; The picture is a ring of RING bytes per plane, kept twice (so the display
; never has to wrap): map pixel (x, y) is at ((y x LINE + x / 8 + 2) mod RING)
; and RING bytes further on.
draw_cell:  movem.l d0-d7/a0-a3,-(sp)
            bsr     map_get
            mulu    v_tbytes(a5),d3
            move.l  v_timg(a5),a0
            add.l   d3,a0                   ; its picture
            move.w  v_tsh(a5),d4
            moveq   #0,d2
            move.w  d1,d2
            lsl.l   d4,d2                   ; row x S (fits a word: the map is < 32768 pixels)
            mulu    v_tline(a5),d2
            moveq   #0,d5
            move.w  d0,d5
            subq.w  #3,d4
            lsl.l   d4,d5                   ; column x S / 8
            add.l   d5,d2
            addq.l  #2,d2
            divu    v_tring(a5),d2
            clr.w   d2
            swap    d2                      ; d2 = offset in the ring
            moveq   #0,d7
            move.w  v_tring(a5),d7          ; d7 = RING (long)
            move.l  v_tbuf(a5),a1
            move.w  H_DEPTH(a4),d6
            subq.w  #1,d6
            move.w  v_tsz(a5),d0
.pl         move.l  d2,d3
            move.w  d0,d4
            subq.w  #1,d4
.ln         move.l  a1,a2
            add.l   d3,a2
            lea     0(a2,d7.l),a3           ; the second copy
            cmp.w   #16,d0
            beq.s   .w16
            bgt.s   .big
            move.b  (a0),(a2)               ; 8 x 8
            move.b  (a0)+,(a3)
            bra.s   .nx
.w16        move.w  (a0),(a2)
            move.w  (a0)+,(a3)
            bra.s   .nx
.big        cmp.w   #32,d0
            bne.s   .w64
            move.l  (a0),(a2)
            move.l  (a0)+,(a3)
            bra.s   .nx
.w64        move.l  (a0),(a2)+
            move.l  (a0)+,(a3)+
            move.l  (a0),(a2)
            move.l  (a0)+,(a3)
.nx         add.w   v_tline(a5),d3
            cmp.l   d7,d3
            blt.s   .in
            sub.l   d7,d3
.in         dbf     d4,.ln
            add.l   v_tbufpl(a5),a1
            dbf     d6,.pl
            movem.l (sp)+,d0-d7/a0-a3
            rts

; d0 = column, d1 = row: redraws that tile if it is in the picture
redraw_cell:
            move.w  d2,-(sp)
            move.w  d0,d2
            sub.w   v_tx0(a5),d2
            cmp.w   v_tncol(a5),d2
            bcc.s   .r
            move.w  d1,d2
            sub.w   v_ty0(a5),d2
            cmp.w   v_tnrow(a5),d2
            bcc.s   .r
            bsr     draw_cell
.r          move.w  (sp)+,d2
            rts

; the copper moves at the HUD split: bitplane pointers and fine scroll for
; the camera (the picture starts HUD_LINES lines down the screen)
cop_scroll: tst.w   v_tmode(a5)
            beq     .sc
            movem.l d0-d4/a0,-(sp)
            move.w  v_camx(a5),d0
            move.w  d0,d1
            and.w   #15,d1
            moveq   #16,d2                  ; delay 16 - (x & 15), 0 when x is a tile edge
            sub.w   d1,d2
            and.w   #15,d2
            add.w   #15,d0                  ; first word fetched: (x + 15) / 16 - 1, +1 for the slack
            lsr.w   #4,d0
            add.w   d0,d0
            moveq   #0,d3
            move.w  v_camy(a5),d3
            add.w   v_hudlines(a5),d3
            mulu    v_tline(a5),d3
            ext.l   d0
            add.l   d0,d3
            divu    v_tring(a5),d3          ; where the ring starts on screen
            clr.w   d3
            swap    d3
            cmp.l   #8,d3                   ; the first bytes of copy 1 may be unwritten
            bcc.s   .rs                     ; (a 32 / 64 wide tile line spills into copy 2):
            moveq   #0,d4                   ; show copy 2 there
            move.w  v_tring(a5),d4
            add.l   d4,d3
.rs         add.l   v_tbuf(a5),d3
            move.l  v_csplit(a5),a0
            move.w  H_DEPTH(a4),d4
            subq.w  #1,d4
.p          swap    d3
            move.w  d3,2(a0)
            swap    d3
            move.w  d3,6(a0)
            addq.l  #8,a0
            add.l   v_tbufpl(a5),d3
            dbf     d4,.p
            move.w  d2,d1                   ; BPLCON1: both playfields
            lsl.w   #4,d1
            or.w    d2,d1
            move.w  d1,10(a0)
            movem.l (sp)+,d0-d4/a0
.r          rts
.sc         tst.w   v_scr(a5)               ; a scrolling backdrop without BOBs: show it now
            beq.s   .r                      ; (with BOBs bob_flip shows each buffer as drawn)
            tst.w   v_bob(a5)
            bne.s   .r
            movem.l d0-d1,-(sp)
            move.l  v_sbuf(a5),d0
            move.w  v_spos(a5),d1
            bsr     scroll_show
            movem.l (sp)+,d0-d1
            rts

; d0 = x, d1 = y (map pixels): Z clear when that point is in a solid tile
; (or off the map: the map's edges are walls)
solid_px:   movem.l d0-d3/a0,-(sp)
            tst.w   d0
            bmi.s   .yes
            tst.w   d1
            bmi.s   .yes
            move.w  v_tsh(a5),d2
            asr.w   d2,d0
            cmp.w   v_tw(a5),d0
            bge.s   .yes
            asr.w   d2,d1
            cmp.w   v_th(a5),d1
            bge.s   .yes
            bsr     map_get
            lsl.w   #3,d3
            move.l  v_tiles(a5),a0
            btst    #0,T_PROPS+TP_FLAGS(a0,d3.w)
            bne.s   .yes
            moveq   #0,d2
            bra.s   .out
.yes        moveq   #1,d2
.out        tst.w   d2
            movem.l (sp)+,d0-d3/a0
            rts

; d0 = x, d1 = y for actor a2: Z clear when its box (A_BX0..A_BY1) would be
; in a solid tile - checked at its corners and the middle of its sides
box_solid:  movem.l d0-d4,-(sp)
            move.w  d0,d2
            add.w   A_BX0(a2),d2            ; left
            move.w  d0,d3
            add.w   A_BX1(a2),d3            ; right
            move.w  d1,d4
            add.w   A_BY0(a2),d4            ; top
            add.w   A_BY1(a2),d1            ; bottom
            move.w  d2,d0
            exg     d1,d4
            bsr     solid_px                ; top left
            bne.s   .hit
            move.w  d3,d0
            bsr     solid_px                ; top right
            bne.s   .hit
            exg     d1,d4
            bsr     solid_px                ; bottom right
            bne.s   .hit
            move.w  d2,d0
            bsr     solid_px                ; bottom left
            bne.s   .hit
            add.w   d4,d1                   ; middle of the sides
            asr.w   #1,d1
            bsr     solid_px
            bne.s   .hit
            move.w  d3,d0
            bsr     solid_px
            bne.s   .hit
            moveq   #0,d0
            bra.s   .out
.hit        moveq   #1,d0
.out        tst.w   d0
            movem.l (sp)+,d0-d4
            rts

; actor d5 / a2 moved sideways into a wall: back where it was (turning
; round); a platform player steps up onto a block one tile high
tile_hres:  movem.l d0-d1,-(sp)
            move.w  v_ax(a5,d5.w),d0
            cmp.w   v_ox(a5,d5.w),d0
            beq.s   .r
            move.w  v_ay(a5,d5.w),d1
            bsr     box_solid
            beq.s   .r
            cmp.w   #6,A_ROLE(a2)
            bne.s   .back
            tst.w   v_gnd(a5,d5.w)
            beq.s   .back
            cmp.w   #16,v_tsz(a5)           ; tiles up to 16 high: steps up one
            bgt.s   .back
            sub.w   v_tsz(a5),d1
            bsr     box_solid
            bne.s   .back
            move.w  d1,v_ay(a5,d5.w)        ; step up
            bra.s   .r
.back       move.w  v_ox(a5,d5.w),d0        ; stuck in a wall already: let it move
            move.w  v_ay(a5,d5.w),d1
            bsr     box_solid
            bne.s   .r
            move.w  v_ox(a5,d5.w),v_ax(a5,d5.w)
            eor.w   #1,v_dx(a5,d5.w)
.r          movem.l (sp)+,d0-d1
            rts

; the same up and down (actors without gravity)
tile_vres:  movem.l d0-d1,-(sp)
            move.w  v_ay(a5,d5.w),d1
            cmp.w   v_oy(a5,d5.w),d1
            beq.s   .r
            move.w  v_ax(a5,d5.w),d0
            bsr     box_solid
            beq.s   .r
            move.w  v_oy(a5,d5.w),d1
            bsr     box_solid
            bne.s   .r
            move.w  v_oy(a5,d5.w),v_ay(a5,d5.w)
            eor.w   #1,v_dy(a5,d5.w)
.r          movem.l (sp)+,d0-d1
            rts

; gravity in a tile world: falls pixel by pixel until it lands on a solid
; tile, bumps its head on one going up
tile_phys:  bsr     tile_hres
            cmp.w   #6,A_ROLE(a2)           ; a platform player on a ladder climbs: up / down, no gravity
            bne     .grav
            bsr     on_ladder
            beq     .grav
            move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
            move.w  #1,v_gnd(a5,d5.w)
            bsr     snap_col                ; line up with the ladder (so it fits the shaft)
            move.w  v_joy(a5),d2
            btst    #0,d2
            beq.s   .cdn
            move.w  v_ax(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d1
            sub.w   v_spd(a5,d5.w),d1
            bsr     box_solid
            bne.s   .cr
            move.w  d1,v_ay(a5,d5.w)
            rts
.cdn        btst    #1,d2
            beq.s   .cr
            move.w  v_ax(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d1
            add.w   v_spd(a5,d5.w),d1
            bsr     box_solid
            bne.s   .cr
            move.w  d1,v_ay(a5,d5.w)
.cr         rts
.grav       move.w  v_vy(a5,d5.w),d0
            cmp.w   #7,A_ROLE(a2)           ; hoppers float down more slowly
            beq.s   .light
            addq.w  #GRAVITY,d0
            bra.s   .g
.light      addq.w  #HOP_GRAVITY,d0
.g          cmp.w   #MAX_FALL,d0
            ble.s   .v
            move.w  #MAX_FALL,d0
.v          move.w  d0,v_vy(a5,d5.w)
            add.w   v_ysub(a5,d5.w),d0
            move.w  d0,d3
            asr.w   #4,d3                   ; d3 = pixels this frame
            and.w   #15,d0
            move.w  d0,v_ysub(a5,d5.w)
            tst.w   d3
            beq.s   .still
            bmi.s   .up
            subq.w  #1,d3
.dl         move.w  v_ax(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d1
            addq.w  #1,d1
            bsr     box_solid
            bne.s   .land
            addq.w  #1,v_ay(a5,d5.w)
            dbf     d3,.dl
            move.w  #0,v_gnd(a5,d5.w)
            rts
.land       move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
            move.w  #1,v_gnd(a5,d5.w)
            rts
.up         neg.w   d3
            subq.w  #1,d3
.ul         move.w  v_ax(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d1
            subq.w  #1,d1
            bsr     box_solid
            bne.s   .bump
            subq.w  #1,v_ay(a5,d5.w)
            dbf     d3,.ul
            move.w  #0,v_gnd(a5,d5.w)
            rts
.bump       move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
            rts
.still      move.w  v_ax(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d1
            addq.w  #1,d1
            bsr     box_solid
            beq.s   .air
            move.w  #1,v_gnd(a5,d5.w)
            tst.w   v_vy(a5,d5.w)
            ble.s   .r
            move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
.r          rts
.air        move.w  #0,v_gnd(a5,d5.w)
            rts

; the player (d7, d5 / a2) in a tile world where it digs: fire + a direction
; digs the tile that way (it takes TP_HARD frames), fire alone places the
; tile it carries in front of it. Z clear while fire is held (no walking).
tile_dig:   move.l  v_tiles(a5),a0
            btst    #0,T_FLAGS+1(a0)
            beq     .no
            cmp.w   H_PLAYER(a4),d7
            bne     .no
            move.w  v_joy(a5),d2
            btst    #4,d2
            beq     .off
            movem.l d0-d4/a0-a1,-(sp)
            and.w   #15,d2
            tst.w   T_NTOOL(a0)
            beq     .nt
            bsr     tool_rec                ; tools: fire uses the one picked with space
            moveq   #0,d3
            move.b  TL_ACT+1(a1),d3
            beq     .pick
            cmp.w   #3,d3                   ; a weapon: weapon_tick swings it, the player keeps moving
            bne.s   .nw
            movem.l (sp)+,d0-d4/a0-a1
            bra     .off
.nw         move.w  v_joyprev(a5),d4        ; build / put: once per press
            btst    #4,d4
            bne     .held
            cmp.w   #2,d3
            bne.s   .ham
            move.w  TL_TILE(a1),d3          ; a ladder part, a torch: where it stands
            bsr     ptile_core
            bra     .held
.ham        tst.w   d2                      ; hammer: the tile carried, where fire points
            beq     .place
            btst    #3,d2
            bne.s   .hr
            btst    #2,d2
            bne.s   .hl
            bsr     .midx
            move.w  v_ay(a5,d5.w),d1
            btst    #1,d2
            bne.s   .hd
            add.w   A_BY0(a2),d1            ; above the head
            subq.w  #4,d1
            bra     .put
.hd         add.w   A_BY1(a2),d1            ; under the feet
            addq.w  #4,d1
            bra     .put
.hr         move.w  v_ax(a5,d5.w),d0
            add.w   A_BX1(a2),d0
            addq.w  #4,d0
            bra     .pf
.hl         move.w  v_ax(a5,d5.w),d0
            add.w   A_BX0(a2),d0
            subq.w  #4,d0
            bra     .pf
.pick       tst.w   d2                      ; pickaxe: fire on its own digs the way it faces
            bne.s   .nt
            tst.w   v_face(a5,d5.w)
            bne.s   .left
            bra.s   .right
.nt         tst.w   d2
            beq     .place
            btst    #3,d2
            bne.s   .right
            btst    #2,d2
            bne.s   .left
            move.w  v_ay(a5,d5.w),d1        ; up or down: above the head / under the feet -
            btst    #1,d2                   ; the middle, then each edge (it can stand on two tiles)
            bne.s   .down
            add.w   A_BY0(a2),d1
            subq.w  #4,d1
            bra.s   .vdig
.down       add.w   A_BY1(a2),d1
            addq.w  #4,d1
.vdig       bsr     snap_col                ; straight down / up: line up with the column
            bsr     .midx
            bsr     dig_px
            bne     .held
            move.w  v_ax(a5,d5.w),d0
            add.w   A_BX0(a2),d0
            bsr     dig_px
            bne     .held
            move.w  v_ax(a5,d5.w),d0
            add.w   A_BX1(a2),d0
            bsr     dig_px
            bra     .held
.right      move.w  v_ax(a5,d5.w),d0        ; beside it: the body first, then the feet
            add.w   A_BX1(a2),d0
            addq.w  #4,d0
            bra.s   .side
.left       move.w  v_ax(a5,d5.w),d0
            add.w   A_BX0(a2),d0
            subq.w  #4,d0
.side       bsr     .midy
            bsr     dig_px
            bne.s   .held
            move.w  v_ay(a5,d5.w),d1
            add.w   A_BY1(a2),d1
            subq.w  #2,d1
            bsr     dig_px
            bra.s   .held
.place      move.w  v_joyprev(a5),d3        ; fire just pressed: put a tile down
            btst    #4,d3
            bne.s   .held
            move.w  v_ax(a5,d5.w),d0        ; in front of it, at its feet
            tst.w   v_face(a5,d5.w)
            bne.s   .pl
            add.w   A_BX1(a2),d0
            addq.w  #4,d0
            bra.s   .pf
.pl         add.w   A_BX0(a2),d0
            subq.w  #4,d0
.pf         move.w  v_ay(a5,d5.w),d1
            add.w   A_BY1(a2),d1
            subq.w  #2,d1
.put        move.w  v_sel(a5),d3            ; when it carries one
            beq.s   .held
            add.w   d3,d3
            lea     v_inv(a5),a1
            tst.w   0(a1,d3.w)
            beq.s   .held
            bsr     place_px
.held       movem.l (sp)+,d0-d4/a0-a1
            moveq   #1,d0                   ; Z clear: fire is held
            rts
.off        move.l  #-1,v_digc(a5)          ; fire let go: start again next time
.no         moveq   #0,d0
            rts
.midx       move.w  v_ax(a5,d5.w),d0
            move.w  A_BX0(a2),d3
            add.w   A_BX1(a2),d3
            asr.w   #1,d3
            add.w   d3,d0
            rts
.midy       move.w  v_ay(a5,d5.w),d1
            move.w  A_BY0(a2),d3
            add.w   A_BY1(a2),d3
            asr.w   #1,d3
            add.w   d3,d1
            rts

; d0 / d1 = map pixel -> d0 = column, d1 = row, d2 = cell; Z set when off the map
; (d3 = the tile there)
px_cell:    tst.w   d0
            bmi.s   .off
            tst.w   d1
            bmi.s   .off
            move.w  v_tsh(a5),d2
            asr.w   d2,d0
            cmp.w   v_tw(a5),d0
            bge.s   .off
            asr.w   d2,d1
            cmp.w   v_th(a5),d1
            bge.s   .off
            bsr     map_get
            move.w  #1,-(sp)                ; Z clear
            tst.w   (sp)+
            rts
.off        move.w  #0,-(sp)
            tst.w   (sp)+
            rts

; digs at map pixel d0 / d1: Z clear when there was something to dig there
dig_px:     movem.l d0-d4/a0-a1,-(sp)
            bsr     px_cell                 ; d3 = tile
            beq     .none
            move.w  d3,d4
            lsl.w   #3,d4
            move.l  v_tiles(a5),a1
            lea     T_PROPS(a1,d4.w),a1     ; a1 = its properties
            btst    #1,TP_FLAGS(a1)
            beq     .none
            cmp.l   v_digc(a5),d2           ; a new tile: start digging it
            beq.s   .same
            move.l  d2,v_digc(a5)
            move.w  #0,v_digt(a5)
.same       addq.w  #1,v_digt(a5)
            move.w  v_digt(a5),d4
            cmp.w   TP_HARD(a1),d4
            blt     .busy
            move.w  d3,-(sp)
            move.w  TP_BECOMES(a1),d3       ; dug out
            bsr     map_put
            move.w  (sp)+,d3
            move.w  #0,v_digt(a5)
            move.l  #-1,v_digc(a5)
            bsr     redraw_cell
            move.w  d3,v_sel(a5)            ; carried
            move.w  d3,d4
            add.w   d4,d4
            lea     v_inv(a5),a0
            cmp.w   #99,0(a0,d4.w)
            bge.s   .full
            addq.w  #1,0(a0,d4.w)
.full       moveq   #0,d0
            move.w  TP_POINTS(a1),d0        ; score
            beq.s   .nosc
            add.l   v_score(a5),d0
            cmp.l   #SCORE_MAX,d0
            bls.s   .sc
            move.l  #SCORE_MAX,d0
.sc         move.l  d0,v_score(a5)
.nosc       moveq   #0,d0
            move.b  TP_SOUND(a1),d0
            cmp.b   #$ff,d0
            beq.s   .nosnd
            bsr     play_sfx
.nosnd      bsr     draw_hud
            btst    #2,TP_FLAGS(a1)         ; counts towards the level goal
            beq.s   .busy
            movem.l (sp)+,d0-d4/a0-a1
            movem.l d0-d7/a0-a3,-(sp)
            bsr     act_goal                ; (may move on to the next level)
            movem.l (sp)+,d0-d7/a0-a3
            moveq   #1,d0
            rts
.busy       movem.l (sp)+,d0-d4/a0-a1
            moveq   #1,d0
            rts
.none       movem.l (sp)+,d0-d4/a0-a1
            moveq   #0,d0
            rts

; puts the tile carried at map pixel d0 / d1 if that place is not solid
place_px:   movem.l d0-d4/a0-a1,-(sp)
            bsr     px_cell
            beq.s   .r
            lsl.w   #3,d3
            move.l  v_tiles(a5),a1
            btst    #0,T_PROPS+TP_FLAGS(a1,d3.w)
            bne.s   .r
            move.w  v_sel(a5),d3
            bsr     map_put
            add.w   d3,d3
            lea     v_inv(a5),a0
            subq.w  #1,0(a0,d3.w)
            bsr     redraw_cell
            bsr     draw_hud
.r          movem.l (sp)+,d0-d4/a0-a1
            rts

; DO 20: tile world - put tile R_VAL where actor d4 (offset d5) is, at the
; middle of its box, if that place is not solid (a ladder part, a block, a torch)
act_ptile:  tst.w   v_tmode(a5)
            beq     .r
            movem.l d0-d4/a0-a2,-(sp)
            cmp.w   H_NACT(a4),d4
            bcc.s   .out
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            mulu    #ACT_SIZE,d4
            add.l   d4,a2                   ; its record (the box)
            move.w  R_VAL(a3),d3
            bsr     ptile_core
.out        movem.l (sp)+,d0-d4/a0-a2
.r          rts

; tile d3 where actor d5 / a2 is: its middle, then its feet, then its head - the
; first place that is not solid and does not have that tile already
ptile_core: movem.l d0-d6/a0,-(sp)
            move.w  d3,d6
            move.l  v_tiles(a5),a0
            cmp.w   T_NT(a0),d6
            bcc.s   .out
            moveq   #2,d4                   ; try its middle, then its feet, then its head
.try        move.w  v_ax(a5,d5.w),d0
            move.w  A_BX0(a2),d1
            add.w   A_BX1(a2),d1
            asr.w   #1,d1
            add.w   d1,d0
            move.w  v_ay(a5,d5.w),d1
            cmp.w   #1,d4
            bne.s   .t2
            add.w   A_BY1(a2),d1            ; feet
            subq.w  #2,d1
            bra.s   .t4
.t2         bcs.s   .t3
            move.w  A_BY0(a2),d2            ; middle
            add.w   A_BY1(a2),d2
            asr.w   #1,d2
            add.w   d2,d1
            bra.s   .t4
.t3         add.w   A_BY0(a2),d1            ; head
            addq.w  #2,d1
.t4         bsr     px_cell                 ; d0 / d1 = column / row, d2 = cell, d3 = tile
            beq.s   .nx
            cmp.w   d6,d3
            beq.s   .nx                     ; that tile is there already
            lsl.w   #3,d3
            move.l  v_tiles(a5),a0
            btst    #0,T_PROPS+TP_FLAGS(a0,d3.w)
            beq.s   .put                    ; nothing solid there
.nx         dbf     d4,.try
            bra.s   .out
.put        move.w  d6,d3
            bsr     map_put
            bsr     redraw_cell
.out        movem.l (sp)+,d0-d6/a0
            rts

; actor d5 / a2: its box middle onto the middle of the tile column it is in,
; if that place is free - climbing a ladder, digging straight up or down
snap_col:   movem.l d0-d4,-(sp)
            move.w  A_BX0(a2),d1
            add.w   A_BX1(a2),d1
            asr.w   #1,d1
            move.w  v_ax(a5,d5.w),d3
            add.w   d1,d3
            move.w  v_tsh(a5),d4
            lsr.w   d4,d3
            lsl.w   d4,d3
            move.w  v_tsz(a5),d2
            lsr.w   #1,d2
            add.w   d2,d3
            sub.w   d1,d3
            move.w  d3,d0
            move.w  v_ay(a5,d5.w),d1
            bsr     box_solid
            bne.s   .r
            move.w  d3,v_ax(a5,d5.w)
.r          movem.l (sp)+,d0-d4
            rts

; Z clear when actor d5 / a2 is on a ladder tile (its feet or its middle)
on_ladder:  movem.l d0-d3/a0,-(sp)
            move.w  v_ax(a5,d5.w),d0
            move.w  A_BX0(a2),d1
            add.w   A_BX1(a2),d1
            asr.w   #1,d1
            add.w   d1,d0
            move.w  d0,-(sp)                ; middle x
            move.w  v_ay(a5,d5.w),d1
            add.w   A_BY1(a2),d1            ; feet
            bsr.s   .lad
            bne.s   .yes
            move.w  (sp),d0
            move.w  v_ay(a5,d5.w),d1
            move.w  A_BY0(a2),d2
            add.w   A_BY1(a2),d2
            asr.w   #1,d2
            add.w   d2,d1                   ; middle
            bsr.s   .lad
.yes        addq.l  #2,sp                   ; (leaves the flags alone)
            movem.l (sp)+,d0-d3/a0
            rts
.lad        bsr     px_cell
            beq.s   .no
            lsl.w   #3,d3
            move.l  v_tiles(a5),a0
            btst    #3,T_PROPS+TP_FLAGS(a0,d3.w)
.no         rts

; 8 directions from (3 x vertical + horizontal): up-left, up, up-right,
; left, (still), right, down-left, down, down-right
dir_tab:    dc.b    7,0,1,6,0,2,5,4,3
            even

hide_sprites:
            move.w  H_NACT(a4),d6
            beq     .done
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            subq.w  #1,d6
.h          tst.w   A_BOB(a2)               ; BOBs go with the backdrop
            bne.s   .h2
            move.l  A_SPR(a2),d0
            lea     0(a4,d0.l),a0
            move.l  #0,(a0)
            move.l  A_SPR2(a2),d0
            beq.s   .h1
            lea     0(a4,d0.l),a0
            move.l  #0,(a0)
.h1         move.l  A_ANIM(a2),d0           ; and every animation frame
            beq.s   .h2
            lea     0(a4,d0.l),a1
            moveq   #3,d2                   ; 4 animations (12 with 8 directions, 21 with Fire,
            btst    #1,A_AMODE+1(a2)        ; 2 more with Hit and Die)
            beq.s   .hd
            moveq   #20,d2
            bra.s   .hhd
.hd         btst    #0,A_AMODE+1(a2)
            beq.s   .hhd
            moveq   #11,d2
.hhd        btst    #2,A_AMODE+1(a2)
            beq.s   .ha
            addq.w  #2,d2
.ha         lea     AN_RIGHT(a1),a3
            moveq   #31,d1                  ; 16 right + 16 left
.hf         move.l  (a3)+,d0
            lea     0(a4,d0.l),a0
            move.l  #0,(a0)
            dbf     d1,.hf
            lea     ANIM_SIZE(a1),a1
            dbf     d2,.ha
.h2
            lea     ACT_SIZE(a2),a2
            dbf     d6,.h
.done       rts

; ============================================================================
;  BOBs (blitter objects, ADAM Pro)
;  Actors with A_BOB set are drawn into the bitplanes by the blitter instead
;  of using a hardware sprite, so there can be more than 8 and they use the
;  backdrop colours. There are two displays: each frame bob_draw wipes the
;  BOBs out of the one that is not on screen (copying v_back over them) and
;  draws them at their new places; bob_flip shows it at the start of the
;  next frame, so nothing is ever drawn into the picture being shown.
;  Cookie-cut per plane: A = mask, B = image plane, C = D = screen,
;  D = AB + ~AC. The image is w words wide (A_BSIZE); the blit is one word
;  wider for the shift, with A's last word masked off (BLTALWM = 0) and A/B
;  modulo -2, and C/D modulo 40 - 2 * (w + 1).
; ============================================================================
;
;  Waiting for the blitter: DMACONR's busy flag (BBUSY) only rises once a
;  blit actually starts, and with 7-8 planes on AGA the bitplanes take nearly
;  every bus slot, so a blit can sit queued for a long time while a fast CPU
;  already reads "not busy" and overwrites its registers. So every blit is
;  started with bgo, which clears the BLIT request in INTREQ first, and bwait
;  waits for that request - it is set only when a blit has finished.
;  (INTENA leaves BLIT off, so no interrupt happens; init_display sets the
;  request once so the first bwait does not wait for nothing.)
bwait:      btst    #6,$1f(a6)              ; INTREQR bit 6: a blit has finished
            beq.s   bwait
            rts

; starts the blit set up in the blitter registers: d0.w = BLTSIZE
bgo:        move.w  #$0040,$9c(a6)          ; INTREQ: clear BLIT
            move.w  d0,$58(a6)              ; BLTSIZE - go
            rts

bob_flip:
            tst.w   v_bob(a5)
            beq.s   .r
            tst.w   v_drawn(a5)
            beq.s   .r
            move.w  #0,v_drawn(a5)
            move.l  v_draw(a5),d0
            tst.w   v_scr(a5)               ; scrolling: at the split, where it was drawn
            beq.s   .pl
            move.w  v_dpos(a5),d1
            bsr     scroll_show
            bra.s   .sw
.pl         bsr     set_bpl
.sw         moveq   #0,d1                   ; draw into the other one next
            move.l  v_bufa(a5),d0
            cmp.l   v_draw(a5),d0
            bne.s   .a
            moveq   #1,d1
            move.l  v_bufb(a5),d0
.a          move.l  d0,v_draw(a5)
            move.w  d1,v_bobbuf(a5)
.r          rts

bob_draw:
            tst.w   v_bob(a5)
            beq     .r
            movem.l d0-d7/a0-a3,-(sp)
            move.w  #0,v_bx0(a5)            ; the screen's top left in the display
            move.w  #0,v_by0(a5)
            move.w  v_scr(a5),d0
            beq.s   .org
            move.w  v_spos(a5),d1
            move.w  d1,v_dpos(a5)           ; (bob_flip shows it at this place)
            move.w  #SCR_MARG,v_by0(a5)
            btst    #0,d0
            beq.s   .orx
            add.w   d1,v_by0(a5)            ; up / down: SCR_MARG + place lines down
            bra.s   .org
.orx        add.w   #SCR_MARG,d1            ; across: SCR_MARG + place pixels across
            move.w  d1,v_bx0(a5)
.org
            lea     v_bobold(a5),a3         ; a3 = this display's list of old places
            lea     v_bobn(a5),a1           ; a1 = its count
            tst.w   v_bobbuf(a5)
            beq.s   .b0
            lea     MAX_ACT*4(a3),a3
            addq.l  #2,a1
.b0
            move.w  #$8400,$96(a6)          ; DMACON: BLTPRI - the CPU only waits for the blitter here
            move.l  v_plsz(a5),a2           ; a2 = a plane (until the actors)
            ; ---- wipe last time's BOBs: background -> display
            bsr     bwait
            move.l  #$09f00000,$40(a6)      ; BLTCON0/1: D = A
            move.l  #$ffffffff,$44(a6)      ; first / last word masks
            move.w  (a1),d6
            subq.w  #1,d6
            bmi.s   .wiped
            move.l  a3,a0
.wipe       moveq   #0,d4
            move.w  (a0)+,d4                ; byte offset in a plane
            move.w  (a0)+,d5                ; BLTSIZE
            move.w  d5,d0
            and.w   #63,d0
            add.w   d0,d0
            move.w  v_bpr(a5),d1
            sub.w   d0,d1                   ; modulo: the line - blit width in bytes
            move.l  v_back(a5),d2
            add.l   d4,d2
            move.l  v_draw(a5),d3
            add.l   d4,d3
            move.w  H_DEPTH(a4),d7
            subq.w  #1,d7
.ww         btst    #6,$1f(a6)              ; (bwait)
            beq.s   .ww
            move.w  d1,$64(a6)              ; AMOD
            move.w  d1,$66(a6)              ; DMOD
.wpl        btst    #6,$1f(a6)              ; (bwait)
            beq.s   .wpl
            move.l  d2,$50(a6)              ; BLTAPT
            move.l  d3,$54(a6)              ; BLTDPT
            move.w  #$0040,$9c(a6)          ; (bgo)
            move.w  d5,$58(a6)
            add.l   a2,d2
            add.l   a2,d3
            dbf     d7,.wpl
            dbf     d6,.wipe
.wiped      move.w  #0,(a1)

            ; ---- draw every visible BOB where it is now
            move.w  H_NACT(a4),d6
            beq     .done
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            moveq   #0,d7
.act        tst.w   A_BOB(a2)
            beq     .nxt
            move.w  d7,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)
            beq     .nxt
            tst.w   v_safe(a5,d5.w)         ; flashing while immune
            beq.s   .vis
            btst    #2,v_anim+1(a5)
            bne     .nxt
.vis        move.w  v_ax(a5,d5.w),d0        ; on the screen? Partly off only where the display
            move.w  v_ay(a5,d5.w),d1        ; has spare edges (scrolling), else all of it
            tst.w   v_bx0(a5)
            bne.s   .cxs
            tst.w   d0
            bmi     .nxt
            cmp.w   A_XMAX(a2),d0
            bgt     .nxt
            bra.s   .cy
.cxs        move.w  A_XMAX(a2),d2           ; -width
            sub.w   #320,d2
            cmp.w   d2,d0
            ble     .nxt
            cmp.w   #320,d0
            bge     .nxt
.cy         tst.w   v_by0(a5)
            bne.s   .cys
            tst.w   d1
            bmi     .nxt
            cmp.w   A_YMAX(a2),d1
            bgt     .nxt
            bra.s   .in
.cys        move.w  A_YMAX(a2),d2           ; -height
            sub.w   #256,d2
            cmp.w   d2,d1
            ble     .nxt
            cmp.w   #256,d1
            bge     .nxt
.in         add.w   v_bx0(a5),d0            ; d0 / d1 = its pixel in the display
            add.w   v_by0(a5),d1
            move.w  d0,d2                   ; d2 = x, for the shift
            mulu    v_bpr(a5),d1
            lsr.w   #4,d0
            add.w   d0,d0
            and.l   #$ffff,d0
            add.l   d1,d0                   ; byte offset in a plane
            move.l  v_fofs(a5,d5.w),d1
            lea     0(a4,d1.l),a0           ; a0 = mask, the planes follow
            move.w  (a1),d1                 ; remember it for next time's wipe
            lsl.w   #2,d1
            move.w  d0,0(a3,d1.w)
            move.w  A_BSIZE(a2),2(a3,d1.w)
            addq.w  #1,(a1)
            move.l  v_draw(a5),d3
            add.l   d0,d3                   ; d3 = screen, plane 0
            move.w  d2,d0
            and.w   #15,d0
            ror.w   #4,d0                   ; shift into bits 15-12
            move.w  d0,v_bcon(a5)
            move.w  #0,v_bflash(a5)         ; hit by a shot: a white flash (colour 1 under the mask)
            tst.w   v_hitf(a5,d5.w)
            beq.s   .nf
            btst    #1,v_anim+1(a5)
            bne.s   .nf
            move.w  #$0bfa,v_bflash(a5)
.nf         bsr     bwait
            move.w  d0,$42(a6)              ; BLTCON1: B shift
            or.w    #$0fca,d0
            move.w  d0,$40(a6)              ; BLTCON0: A shift, use ABCD, D = AB + ~AC
            move.l  #$ffff0000,$44(a6)      ; keep A's first word, drop the extra one
            move.w  #-2,$64(a6)             ; AMOD
            move.w  #-2,$62(a6)             ; BMOD
            move.w  A_BSIZE(a2),d4
            move.w  d4,d0
            and.w   #63,d0
            add.w   d0,d0                   ; blit width in bytes
            move.w  v_bpr(a5),d1
            sub.w   d0,d1
            move.w  d1,$60(a6)              ; CMOD
            move.w  d1,$66(a6)              ; DMOD
            subq.w  #2,d0                   ; image width in bytes
            move.w  d4,d1
            lsr.w   #6,d1                   ; lines
            mulu    d1,d0                   ; d0 = bytes per mask / plane
            move.l  d0,v_bstep(a5)
            move.l  a0,d2
            add.l   d0,d2                   ; d2 = image, plane 0
            move.w  H_DEPTH(a4),d1
            subq.w  #1,d1
            tst.w   v_bflash(a5)
            bne.s   .pl
            move.l  v_plsz(a5),d5           ; (d5 = a plane: the actor's offset is done with)
.pq         btst    #6,$1f(a6)              ; (bwait)
            beq.s   .pq
            move.l  a0,$50(a6)              ; A = mask
            move.l  d2,$4c(a6)              ; B = image plane
            move.l  d3,$48(a6)              ; C = screen
            move.l  d3,$54(a6)              ; D = screen
            move.w  #$0040,$9c(a6)          ; (bgo)
            move.w  d4,$58(a6)
            add.l   d0,d2
            add.l   d5,d3
            dbf     d1,.pq
            bra.s   .nxt
.pl         btst    #6,$1f(a6)              ; (bwait)
            beq.s   .pl
            move.w  v_bflash(a5),d0         ; the flash: plane 0 set (D = A + ~AC),
            beq.s   .pn                     ; the others cleared (D = ~AC)
            or.w    v_bcon(a5),d0
            move.w  d0,$40(a6)
            move.w  #$0b0a,v_bflash(a5)
.pn         move.l  a0,$50(a6)              ; A = mask
            move.l  d2,$4c(a6)              ; B = image plane
            move.l  d3,$48(a6)              ; C = screen
            move.l  d3,$54(a6)              ; D = screen
            move.w  #$0040,$9c(a6)          ; (bgo)
            move.w  d4,$58(a6)
            add.l   v_bstep(a5),d2
            add.l   v_plsz(a5),d3
            dbf     d1,.pl
.nxt        lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .act
.done       bsr     bwait
            move.w  #$0400,$96(a6)          ; DMACON: BLTPRI off
            move.w  #1,v_drawn(a5)
            movem.l (sp)+,d0-d7/a0-a3
.r          rts

; ============================================================================
;  collisions - bounding boxes trimmed to each sprite's drawn pixels
;  touch:      d0.w = actor a, d1.w = actor b  -> d0 = 1 and NE when touching
;  touch_any:  d0.w = actor a                  -> any other visible actor
; ============================================================================
touch_pair:
            movem.l d2-d5/a0-a1,-(sp)
            move.w  H_NACT(a4),d2
            cmp.w   d2,d0
            bhs     .no
            cmp.w   d2,d1
            bhs     .no
            move.w  d0,d4                   ; both shown, neither safe (before the records:
            lsl.w   #ACTV_SHIFT,d4          ; most pairs stop here)
            move.w  d1,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d4.w)
            beq     .no
            tst.w   v_vis(a5,d5.w)
            beq     .no
            tst.w   v_safe(a5,d4.w)
            bne     .no
            tst.w   v_safe(a5,d5.w)
            bne     .no
            lea     v_arec(a5),a1
            move.w  d0,d2
            add.w   d2,d2
            add.w   d2,d2
            move.l  0(a1,d2.w),a0           ; record a
            move.w  d1,d2
            add.w   d2,d2
            add.w   d2,d2
            move.l  0(a1,d2.w),a1           ; record b
            move.w  v_ax(a5,d4.w),d2        ; a.left > b.right ?
            add.w   A_BX0(a0),d2
            move.w  v_ax(a5,d5.w),d3
            add.w   A_BX1(a1),d3
            cmp.w   d3,d2
            bgt.s   .no
            move.w  v_ax(a5,d5.w),d2        ; b.left > a.right ?
            add.w   A_BX0(a1),d2
            move.w  v_ax(a5,d4.w),d3
            add.w   A_BX1(a0),d3
            cmp.w   d3,d2
            bgt.s   .no
            move.w  v_ay(a5,d4.w),d2        ; a.top > b.bottom ?
            add.w   A_BY0(a0),d2
            move.w  v_ay(a5,d5.w),d3
            add.w   A_BY1(a1),d3
            cmp.w   d3,d2
            bgt.s   .no
            move.w  v_ay(a5,d5.w),d2        ; b.top > a.bottom ?
            add.w   A_BY0(a1),d2
            move.w  v_ay(a5,d4.w),d3
            add.w   A_BY1(a0),d3
            cmp.w   d3,d2
            bgt.s   .no
            moveq   #1,d0
            bra.s   .out
.no         moveq   #0,d0
.out        movem.l (sp)+,d2-d5/a0-a1
            tst.w   d0
            rts

touch_any:
            movem.l d1/d6-d7,-(sp)
            move.w  d0,d6                   ; actor a
            moveq   #0,d7
.t          cmp.w   H_NACT(a4),d7
            bge.s   .none
            cmp.w   d6,d7
            beq.s   .skip
            move.w  d6,d0
            move.w  d7,d1
            bsr     touch_pair
            bne.s   .hit
.skip       addq.w  #1,d7
            bra.s   .t
.none       moveq   #0,d0
            bra.s   .out
.hit        moveq   #1,d0
.out        movem.l (sp)+,d1/d6-d7
            tst.w   d0
            rts

; ============================================================================
;  WHEN / DO rules
; ============================================================================
run_rules:
            move.w  H_NRULE(a4),d6
            beq     .done
            move.l  H_RULES(a4),d0
            lea     0(a4,d0.l),a3
            moveq   #0,d7
.r          move.w  d7,d5
            add.w   d5,d5                   ; latch offset
            lea     v_latch(a5),a2
            add.w   d5,a2                   ; a2 = this rule's latch
            move.l  #-1,v_cta(a5)           ; no copies matched yet (v_cta and v_ctb)
            move.w  R_WHEN(a3),d0
            cmp.w   #18,d0
            bhi     .next
            add.w   d0,d0
            move.w  .jt(pc,d0.w),d0
            jmp     .jt(pc,d0.w)
.jt         dc.w    .touch-.jt,.fire-.jt,.timer-.jt,.score-.jt,.lives-.jt,.next-.jt,.jump-.jt,.next-.jt
            dc.w    .hold-.jt,.inview-.jt,.strike-.jt,.thrown-.jt,.pickup-.jt,.ltime-.jt,.auto-.jt,.mapend-.jt
            dc.w    .aend-.jt,.iget-.jt,.iuse-.jt

.iget       move.w  v_igotp(a5),d0          ; the player got item n (last frame)
            move.w  R_N(a3),d1
            cmp.w   #ITEM_MAX,d1
            bhs     .next
            btst    d1,d0
            beq     .next
            bsr     fire_action
            bra     .next

.iuse       move.w  v_useit(a5),d0          ; the player used item n (space bar menu) on (a copy of) actor b
            bmi     .next
            cmp.w   R_N(a3),d0
            bne     .next
            move.w  H_PLAYER(a4),d0
            bmi     .next
            move.w  R_B(a3),d1
            bsr     touch_types
            beq     .next
            bsr     fire_action
            beq     .next
            tst.w   v_uspent(a5)            ; the first rule that fires spends it (used up / kept / a use)
            bne     .next
            move.w  #1,v_uspent(a5)
            move.w  R_N(a3),d0
            bsr     item_spend
            bra     .next

.aend       move.l  v_aended(a5),d0         ; (a copy of) actor a finished its Hit / Die this frame:
            beq     .next                   ; n = 0 Hit, 1 Die, 2 either
            move.w  R_A(a3),d1
            bsr     type_bit
            beq     .next
            move.w  R_N(a3),d0
            cmp.w   #2,d0
            bhs.s   .ae
            move.w  d1,d2
            lsl.w   #ACTV_SHIFT,d2
            cmp.w   v_aendk(a5,d2.w),d0
            bne     .next
.ae         move.w  d1,v_cta(a5)
            bsr     fire_action
            bra     .next

.mapend     tst.w   v_mend(a5)              ; the scrolling map has reached its top (once)
            beq     .clear
            bra     .edge

.ltime      tst.w   v_sectick(a5)           ; N seconds into the level (once a level)
            beq     .next
            move.w  v_ltime(a5),d0
            cmp.w   R_N(a3),d0
            bne     .next
            bsr     fire_action
            bra     .next

.auto       btst    #4,v_joy+1(a5)          ; fire held: at once, then every N frames (auto-fire)
            beq     .clear
            tst.w   (a2)
            beq.s   .af
            subq.w  #1,(a2)
            bne     .next
.af         move.w  R_N(a3),(a2)
            bsr     fire_action
            bra     .next

.pickup     move.w  v_picked(a5),d4         ; the player picked (a copy of) actor a up this frame
            bmi     .next
            move.w  d4,d0
            cmp.w   R_A(a3),d4              ; the actor named, or a copy of it
            beq.s   .pka
            bsr     type_of
            cmp.w   R_A(a3),d4
            bne     .next
.pka        move.w  d0,v_cta(a5)
            bsr     fire_action
            bra     .next

.thrown     move.w  v_hitn(a5),d1           ; thrown actor a hit actor b (b = a: anything) this frame
            beq     .next
            subq.w  #1,d1
            lea     v_hits(a5),a0
.th         moveq   #0,d0                   ; each hit it matches fires it (two copies hit at once)
            move.b  (a0)+,d0
            moveq   #0,d2
            move.b  (a0)+,d2
            cmp.w   R_A(a3),d0              ; the actor named, or a copy of it
            beq.s   .tha
            move.w  d0,d4
            bsr     type_of
            cmp.w   R_A(a3),d4
            bne.s   .thn
.tha        move.w  R_B(a3),d4
            cmp.w   R_A(a3),d4
            beq.s   .thy
            cmp.w   d4,d2
            beq.s   .thy
            move.w  d2,d4
            bsr     type_of
            cmp.w   R_B(a3),d4
            bne.s   .thn
.thy        move.w  d0,v_cta(a5)
            move.w  d2,v_ctb(a5)
            movem.l d1/a0,-(sp)
            bsr     fire_action
            movem.l (sp)+,d1/a0
.thn        dbf     d1,.th
            bra     .next

.strike     move.l  v_struck(a5),d0         ; the player's weapon struck (a copy of) actor b this frame
            move.w  R_B(a3),d1
            bsr     type_bit
            beq     .next
            move.w  d1,v_ctb(a5)
            bsr     fire_action
            bra     .next

.inview     tst.w   v_sectick(a5)           ; every N seconds while (a copy of) actor a is on the screen
            beq     .next
            move.w  R_A(a3),d0
            bsr     type_on_screen
            bne.s   .iv
            move.w  R_N(a3),(a2)            ; out of view: ring a second after it comes back
            subq.w  #1,(a2)
            bra     .next
.iv         move.w  d1,v_cta(a5)
            addq.w  #1,(a2)
            move.w  (a2),d0
            cmp.w   R_N(a3),d0
            blt     .next
            move.w  #0,(a2)
            bsr     fire_action
            bra     .next

.hold       move.w  v_joy(a5),d0            ; fire held (stick centred) for N tenths of a second:
            and.w   #$1f,d0                 ; fires once a hold
            cmp.w   #$10,d0
            bne     .clear
            move.w  R_N(a3),d0
            mulu    #5,d0
            cmp.w   (a2),d0
            bls     .next                   ; already fired this hold
            addq.w  #1,(a2)
            cmp.w   (a2),d0
            bne     .next
            bsr     fire_action
            bra     .next

.jump       move.l  v_jumped(a5),d0         ; (a copy of) actor a jumped this frame
            move.w  R_A(a3),d1
            bsr     type_bit
            beq     .next
            move.w  d1,v_cta(a5)
            bsr     fire_action
            bra     .next

.touch      move.w  R_A(a3),d0              ; a copy of a touches a copy of b (b = a: anything)
            move.w  R_B(a3),d1
            bsr     touch_types
            beq.s   .clear
.edge       tst.w   (a2)
            bne     .next
            bsr     fire_action             ; (an IF line said no: try again next frame)
            beq     .next
            move.w  #1,(a2)
            bra     .next
.clear      move.w  #0,(a2)
            bra     .next

.fire       btst    #4,v_joy+1(a5)
            beq.s   .clear
            bra.s   .edge

.timer      tst.w   v_sectick(a5)
            beq     .next
            addq.w  #1,(a2)
            move.w  (a2),d0
            cmp.w   R_N(a3),d0
            blt     .next
            move.w  #0,(a2)
            bsr     fire_action
            bra     .next

.score      tst.w   (a2)
            bne     .next
            moveq   #0,d0
            move.w  R_N(a3),d0
            cmp.l   v_score(a5),d0
            bhi     .next
            bsr     fire_action
            beq     .next
            move.w  #1,(a2)
            bra     .next

.lives      tst.w   v_lives(a5)
            bne     .next
            tst.w   (a2)
            bne     .next
            bsr     fire_action
            beq     .next
            move.w  #1,(a2)

.next       move.w  R_NAND(a3),d0           ; (rule_next)
            lsl.w   #3,d0
            lea     RULE_SIZE(a3,d0.w),a3
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .r
.done       move.w  #-1,v_useit(a5)         ; a use nothing took is gone
            rts

; runs every rule whose WHEN is d0 (5 = game starts, 7 = level starts)
run_when_rules:
            move.w  d0,d4
            move.w  H_NRULE(a4),d6
            beq.s   .done
            move.l  H_RULES(a4),d0
            lea     0(a4,d0.l),a3
            moveq   #0,d7
.r          cmp.w   R_WHEN(a3),d4
            bne.s   .n
            move.w  d4,-(sp)
            move.l  #-1,v_cta(a5)
            bsr     fire_action
            move.w  (sp)+,d4
.n          bsr     rule_next
            addq.w  #1,d7
            cmp.w   d6,d7
            blt.s   .r
.done       rts

; a3 = a rule -> the next rule (past its AND DO lines)
rule_next:  move.l  d0,-(sp)
            move.w  R_NAND(a3),d0
            lsl.w   #3,d0
            lea     RULE_SIZE(a3,d0.w),a3
            move.l  (sp)+,d0
            rts

; the rule's DO, then each of its AND DO lines (do_action reads R_ACT / R_TGT / R_VAL,
; so a3 points AND_SIZE before each line: its act / target / value sit at 8 / 10 / 12).
; Only when its IF lines all say yes (if_check): d0 = 1, Z clear = it fired, else d0 = 0, Z set.
; (IF lines go to act_none in do_action.)
fire_action:
            bsr     if_check
            bne.s   .go
            rts
.go         movem.l d5-d7/a2-a3,-(sp)
            move.w  R_A(a3),v_rta(a5)       ; (do_action turns them into the copies that matched)
            move.w  R_B(a3),v_rtb(a5)
            move.w  R_NAND(a3),d7
            move.l  a3,a2
            movem.l d7/a2,-(sp)
            bsr     do_action
            movem.l (sp)+,d7/a2
.and        subq.w  #1,d7
            bmi.s   .done
            addq.l  #AND_SIZE,a2
            move.l  a2,a3
            movem.l d7/a2,-(sp)
            bsr     do_action
            movem.l (sp)+,d7/a2
            bra.s   .and
.done       movem.l (sp)+,d5-d7/a2-a3
            moveq   #1,d0
            rts

; a3 = rule
do_action:
            move.w  R_TGT(a3),d4            ; target actor (the copy that made the rule fire)
            bsr     ctx_actor
            move.w  d4,d5                   ; -> d5 = offset
            lsl.w   #ACTV_SHIFT,d5
            move.w  R_ACT(a3),d0
            cmp.w   #31,d0
            bhi     act_none
            add.w   d0,d0
            move.w  acttab(pc,d0.w),d0
            jmp     acttab(pc,d0.w)
acttab:     dc.w    act_score-acttab
            dc.w    act_loselife-acttab
            dc.w    act_sound-acttab
            dc.w    act_flash-acttab
            dc.w    act_home-acttab
            dc.w    act_random-acttab
            dc.w    act_hide-acttab
            dc.w    act_show-acttab
            dc.w    act_bgcol-acttab
            dc.w    act_over-acttab
            dc.w    act_win-acttab
            dc.w    act_faster-acttab
            dc.w    act_slower-acttab
            dc.w    act_addlife-acttab
            dc.w    act_moveto-acttab
            dc.w    act_moment-acttab
            dc.w    act_safe-acttab
            dc.w    act_goal-acttab
            dc.w    act_music-acttab
            dc.w    act_nomusic-acttab
            dc.w    act_ptile-acttab
            dc.w    act_drop-acttab
            dc.w    act_shoot-acttab
            dc.w    act_power-acttab
            dc.w    act_effect-acttab
            dc.w    act_spawn-acttab
            dc.w    act_anim-acttab
            dc.w    act_pal-acttab
            dc.w    act_igive-acttab
            dc.w    act_itake-acttab
            dc.w    act_make-acttab
            dc.w    act_idrop-acttab

act_none:   rts

; DO 27: switch to palette value (0 = the main one), fading over target frames (0 = at once)
act_pal:    move.w  R_VAL(a3),d0
            move.w  R_TGT(a3),d1
            bra     pal_switch

; ============================================================================
;  items: what the player carries (v_icnt), picked up by touching an item's actor,
;  given, taken, made from recipes, used from the space bar menu, checked by IF lines
; ============================================================================

; DO 28: give the player target of item value / DO 29: take them away
act_igive:  move.w  R_VAL(a3),d0
            move.w  R_TGT(a3),d1
            bra     item_give
act_itake:  move.w  R_VAL(a3),d0
            move.w  R_TGT(a3),d1
            bra     item_take
; DO 30: make recipe value, if the player has what it takes
act_make:   move.w  R_VAL(a3),d0
            bra     recipe_make
; DO 31: the player drops an item value - its actor comes out where the player is
act_idrop:  move.w  R_VAL(a3),d0
            bra     item_drop

; d0 = item -> a0 = its record, Z clear; Z set = no such item
item_rec:   movem.l d0-d1,-(sp)
            move.l  v_items(a5),d1
            beq.s   .no
            move.l  d1,a0
            cmp.w   IT_N(a0),d0
            bhs.s   .no
            mulu    #IT_SIZE,d0
            lea     IT_RECS(a0,d0.l),a0
            moveq   #1,d1
            bra.s   .o
.no         moveq   #0,d1
.o          tst.w   d1
            movem.l (sp)+,d0-d1
            rts

; d0 = recipe -> a0 = its record, Z clear; Z set = no such recipe
recipe_rec: movem.l d0-d1,-(sp)
            move.l  v_items(a5),d1
            beq.s   .no
            move.l  d1,a0
            cmp.w   IT_NR(a0),d0
            bhs.s   .no
            lsl.w   #3,d0                   ; RC_SIZE
            move.w  IT_N(a0),d1
            mulu    #IT_SIZE,d1
            add.w   d0,d1
            lea     IT_RECS(a0,d1.l),a0
            moveq   #1,d1
            bra.s   .o
.no         moveq   #0,d1
.o          tst.w   d1
            movem.l (sp)+,d0-d1
            rts

; a3 = a rule -> Z clear (d0 = 1) when its IF lines all say yes; then the 'uses' ones are spent
if_check:   movem.l d1-d3/a0-a1,-(sp)
            moveq   #0,d3                   ; pass 0 checks, pass 1 spends
.pass       move.w  R_NAND(a3),d2
            lea     RULE_SIZE(a3),a0
            bra.s   .lc
.l          move.w  (a0),d0
            bpl.s   .nx                     ; a DO line
            move.w  4(a0),d1                ; its item
            cmp.w   #ITEM_MAX,d1
            bhs.s   .fail
            add.w   d1,d1
            lea     v_icnt(a5),a1
            move.w  0(a1,d1.w),d1           ; how many the player carries
            and.w   #3,d0
            tst.w   d3
            bne.s   .spend
            cmp.w   #2,d0
            beq.s   .none
            cmp.w   #3,d0
            beq.s   .least
            tst.w   d1                      ; has / uses: one at least
            beq.s   .fail
            bra.s   .nx
.none       tst.w   d1
            bne.s   .fail
            bra.s   .nx
.least      cmp.w   2(a0),d1
            blo.s   .fail
            bra.s   .nx
.spend      cmp.w   #1,d0
            bne.s   .nx
            move.w  4(a0),d0
            bsr     item_spend
.nx         addq.l  #AND_SIZE,a0
.lc         dbf     d2,.l
            tst.w   d3
            bne.s   .ok
            moveq   #1,d3
            bra.s   .pass
.ok         moveq   #1,d0
            bra.s   .o
.fail       moveq   #0,d0
.o          movem.l (sp)+,d1-d3/a0-a1
            tst.w   d0
            rts

; d0 = item: the player uses one - used up, kept, or one of its uses goes
item_spend: movem.l d0-d1/a0-a1,-(sp)
            bsr     item_rec
            beq.s   .o
            lea     v_icnt(a5),a1
            add.w   d0,d0
            move.b  IT_USE(a0),d1
            cmp.b   #1,d1
            beq.s   .o                      ; kept
            cmp.b   #2,d1
            bne.s   .one
            lea     v_iuse(a5),a1           ; a few uses: one goes, the last one uses it up
            subq.w  #1,0(a1,d0.w)
            bgt.s   .o
            move.w  IT_USES(a0),0(a1,d0.w)
            lea     v_icnt(a5),a1
.one        tst.w   0(a1,d0.w)
            beq.s   .o
            subq.w  #1,0(a1,d0.w)
            bsr     draw_hud
.o          movem.l (sp)+,d0-d1/a0-a1
            rts

; d0 = item, d1 = how many: the player gets them (never more than IT_CARRY); WHEN 17 sees it
item_give:  movem.l d0-d3/a0-a1,-(sp)
            bsr     item_rec
            beq.s   .o
            lea     v_icnt(a5),a1
            move.w  d0,d3
            add.w   d3,d3
            move.w  0(a1,d3.w),d2
            bne.s   .add
            move.w  IT_USES(a0),v_iuse-v_icnt(a1,d3.w)    ; the first one: all its uses
.add        tst.w   d1
            ble.s   .o
            add.w   d2,d1
            cmp.w   IT_CARRY(a0),d1
            ble.s   .put
            move.w  IT_CARRY(a0),d1
.put        cmp.w   d2,d1
            ble.s   .o                      ; full: nothing more
            move.w  d1,0(a1,d3.w)
            move.w  v_igot(a5),d1
            bset    d0,d1
            move.w  d1,v_igot(a5)
            bsr     draw_hud
.o          movem.l (sp)+,d0-d3/a0-a1
            rts

; d0 = item, d1 = how many: the player loses them (what it has, when it has fewer)
item_take:  movem.l d0-d2/a0-a1,-(sp)
            bsr     item_rec
            beq.s   .o
            lea     v_icnt(a5),a1
            add.w   d0,d0
            move.w  0(a1,d0.w),d2
            sub.w   d1,d2
            bpl.s   .put
            moveq   #0,d2
.put        move.w  d2,0(a1,d0.w)
            bsr     draw_hud
.o          movem.l (sp)+,d0-d2/a0-a1
            rts

; d0 = recipe -> Z clear when the player has what it takes (a0 = the recipe)
recipe_can: movem.l d0-d2/a1,-(sp)
            bsr     recipe_rec
            beq.s   .no
            lea     v_icnt(a5),a1
            move.w  RC_A(a0),d0
            move.w  RC_B(a0),d1
            cmp.w   #ITEM_MAX,d0
            bhs.s   .no
            cmp.w   #ITEM_MAX,d1
            bhs.s   .no
            add.w   d0,d0
            add.w   d1,d1
            move.w  0(a1,d0.w),d2
            beq.s   .no
            tst.w   0(a1,d1.w)
            beq.s   .no
            cmp.w   d0,d1                   ; the same item twice: two of it
            bne.s   .yes
            cmp.w   #2,d2
            blo.s   .no
.yes        moveq   #1,d0
            bra.s   .o
.no         moveq   #0,d0
.o          tst.w   d0
            movem.l (sp)+,d0-d2/a1
            rts

; d0 = recipe: if the player has what it takes, the ingredients go (unless kept) and it
; gets RC_N of what it makes
recipe_make:
            movem.l d0-d1/a0,-(sp)
            bsr     recipe_can
            beq.s   .o
            moveq   #1,d1
            btst    #0,RC_FLAGS(a0)
            bne.s   .ka
            move.w  RC_A(a0),d0
            bsr     item_take
.ka         btst    #1,RC_FLAGS(a0)
            bne.s   .kb
            move.w  RC_B(a0),d0
            bsr     item_take
.kb         move.w  RC_OUT(a0),d0
            moveq   #0,d1
            move.b  RC_N(a0),d1
            bsr     item_give
.o          movem.l (sp)+,d0-d1/a0
            rts

; d0 = item: the player drops one - a hidden copy of its actor comes out beside the player
; (the way it faces), flashing (safe) for a moment so it is not picked straight up again
item_drop:  movem.l d0-d7/a0-a1,-(sp)
            bsr     item_rec
            beq     .o
            lea     v_icnt(a5),a1
            move.w  d0,d6
            add.w   d6,d6
            tst.w   0(a1,d6.w)
            beq     .o
            move.w  IT_ACT(a0),d2           ; its actor
            bmi     .o
            move.w  H_PLAYER(a4),d7
            bmi     .o
            cmp.w   H_NACT(a4),d7
            bhs     .o
            move.w  d2,d1
.f          cmp.w   H_NACT(a4),d1           ; it, then its copies: the first one hidden
            bhs     .o
            cmp.w   d2,d1
            beq.s   .f1
            move.w  d1,d4
            move.l  a0,-(sp)
            bsr     actor_rec
            move.w  A_TYPE(a0),d3
            move.l  (sp)+,a0
            cmp.w   d3,d2
            bne     .o
.f1         move.w  d1,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)
            beq.s   .got
            addq.w  #1,d1
            bra.s   .f
.got        subq.w  #1,0(a1,d6.w)
            move.w  d1,d4
            lsl.w   #ACTV_SHIFT,d7
            bsr     actor_rec               ; a0 = the dropped one's record
            move.w  v_ax(a5,d7.w),d0        ; beside the player, the way it faces
            add.w   #DROP_GAP,d0
            tst.w   v_face(a5,d7.w)
            beq.s   .side
            sub.w   #2*DROP_GAP,d0
.side       tst.w   d0
            bpl.s   .xl
            moveq   #0,d0
.xl         cmp.w   A_XMAX(a0),d0
            ble.s   .xr
            move.w  A_XMAX(a0),d0
.xr         move.w  d0,v_ax(a5,d5.w)
            move.w  v_ay(a5,d7.w),v_ay(a5,d5.w)
            move.w  #1,v_vis(a5,d5.w)
            move.w  #SAFE_TIME,v_safe(a5,d5.w)
            bsr     stop_fall
            bsr     draw_hud
.o          movem.l (sp)+,d0-d7/a0-a1
            rts

; each frame: the player picks up an item whose actor (or a copy) it touches, unless it
; carries as many as it can; the actor hides
item_tick:  move.l  v_items(a5),d0
            beq.s   .r
            movem.l d0-d7/a0-a2,-(sp)
            move.l  d0,a2
            move.w  H_PLAYER(a4),d6
            bmi.s   .o
            move.w  IT_N(a2),d7
            moveq   #0,d5                   ; item
            lea     IT_RECS(a2),a2
            bra.s   .lc
.l          move.w  IT_ACT(a2),d1
            bmi.s   .nx
            lea     v_icnt(a5),a1
            move.w  d5,d2
            add.w   d2,d2
            move.w  0(a1,d2.w),d2
            cmp.w   IT_CARRY(a2),d2
            bhs.s   .nx                     ; full
            move.w  d6,d0
            bsr     touch_types
            beq.s   .nx
            move.w  v_ctb(a5),d2            ; the copy touched hides
            lsl.w   #ACTV_SHIFT,d2
            move.w  #0,v_vis(a5,d2.w)
            move.w  d5,d0
            moveq   #1,d1
            bsr     item_give
.nx         lea     IT_SIZE(a2),a2
            addq.w  #1,d5
.lc         dbf     d7,.l
.o          movem.l (sp)+,d0-d7/a0-a2
.r          rts

; a new game: v_items, and each item's starting count and uses
items_reset:
            movem.l d0-d2/a0-a1,-(sp)
            move.l  #0,v_items(a5)
            move.w  #0,v_igot(a5)
            move.w  #0,v_igotp(a5)
            move.w  #-1,v_useit(a5)
            lea     v_icnt(a5),a1
            moveq   #ITEM_MAX-1,d2
.z          move.w  #0,(a1)+
            dbf     d2,.z
            move.l  H_ITEMS(a4),d0
            beq.s   .o
            add.l   a4,d0
            move.l  d0,v_items(a5)
            move.l  d0,a0
            move.w  IT_N(a0),d2
            lea     IT_RECS(a0),a0
            lea     v_icnt(a5),a1
            bra.s   .lc
.l          move.w  IT_START(a0),(a1)
            move.w  IT_USES(a0),v_iuse-v_icnt(a1)
            addq.l  #2,a1
            lea     IT_SIZE(a0),a0
.lc         dbf     d2,.l
.o          movem.l (sp)+,d0-d2/a0-a1
            rts

; the next level: items not kept on it (IT_FLAGS bit 0 clear) are gone
items_level:
            movem.l d0/d2/a0-a1,-(sp)
            moveq   #0,d0
            bra.s   items_clear
; a life lost: items lost with a life (IT_FLAGS bit 1) are gone
items_life:
            movem.l d0/d2/a0-a1,-(sp)
            moveq   #1,d0
items_clear:
            move.l  v_items(a5),d2
            beq.s   .o
            move.l  d2,a0
            move.w  IT_N(a0),d2
            lea     IT_RECS(a0),a0
            lea     v_icnt(a5),a1
            bra.s   .lc
.l          tst.w   d0
            bne.s   .life
            btst    #0,IT_FLAGS(a0)
            bne.s   .nx
            bra.s   .gone
.life       btst    #1,IT_FLAGS(a0)
            beq.s   .nx
.gone       move.w  #0,(a1)
.nx         addq.l  #2,a1
            lea     IT_SIZE(a0),a0
.lc         dbf     d2,.l
.o          movem.l (sp)+,d0/d2/a0-a1
            rts

; DO 26: actor d4 plays its Hit (value 0) or Die (1) animation once; WHEN 16 fires at its end
act_anim:   cmp.w   H_NACT(a4),d4
            bhs     act_none
            move.w  R_VAL(a3),d0
            and.w   #1,d0
            move.w  d0,v_aplay(a5,d5.w)
            move.w  #-1,v_aset(a5,d5.w)     ; from its first frame
            rts

; actor d7 (d5) has finished its Hit / Die: WHEN 16 rules see it this frame
anim_ended: move.l  d0,-(sp)
            move.w  v_aplay(a5,d5.w),v_aendk(a5,d5.w)
            move.w  #-1,v_aplay(a5,d5.w)
            move.l  v_aended(a5),d0
            bset    d7,d0
            move.l  d0,v_aended(a5)
            move.l  (sp)+,d0
            rts

; d4 = an actor a rule names -> d4 = the copy of it that made the rule fire (when one did)
ctx_actor:  tst.w   v_cta(a5)
            bmi.s   .b
            cmp.w   v_rta(a5),d4
            bne.s   .b
            move.w  v_cta(a5),d4
            rts
.b          tst.w   v_ctb(a5)
            bmi.s   .r
            cmp.w   v_rtb(a5),d4
            bne.s   .r
            move.w  v_ctb(a5),d4
.r          rts

; R_VAL as an actor -> d0 (the copy that made the rule fire, when one did)
ctx_val:    move.w  d4,-(sp)
            move.w  R_VAL(a3),d4
            bsr.s   ctx_actor
            move.w  d4,d0
            move.w  (sp)+,d4
            rts

; d4 = an actor -> d4 = its type (A_TYPE: the first of its copies)
type_of:    movem.l d0/a0,-(sp)
            bsr     actor_rec
            move.w  A_TYPE(a0),d4
            movem.l (sp)+,d0/a0
            rts

; d0 = a bit per actor, d1 = a type -> d1 = its first copy with its bit set (Z clear); Z set: none
type_bit:   movem.l d2-d4/a0,-(sp)
            move.l  d0,d3
            move.w  d1,d2
.l          cmp.w   H_NACT(a4),d1
            bhs.s   .no
            cmp.w   #MAX_ACT,d1
            bhs.s   .no
            cmp.w   d2,d1                   ; the actor named, then its copies
            beq.s   .tb1
            move.w  d1,d4
            bsr     actor_rec
            cmp.w   A_TYPE(a0),d2
            bne.s   .no
.tb1        btst    d1,d3
            bne.s   .yes
            addq.w  #1,d1
            bra.s   .l
.no         moveq   #0,d2
            bra.s   .o
.yes        moveq   #1,d2
.o          move.l  d3,d0
            tst.w   d2
            movem.l (sp)+,d2-d4/a0
            rts

; d0 = a type -> d0 = a bit for each of its copies
type_mask:  movem.l d1-d4/a0,-(sp)
            move.w  d0,d2
            move.w  d0,d1
            moveq   #0,d3
.l          cmp.w   H_NACT(a4),d1
            bhs.s   .o
            cmp.w   #MAX_ACT,d1
            bhs.s   .o
            cmp.w   d2,d1                   ; the actor named, then its copies
            beq.s   .tm1
            move.w  d1,d4
            bsr     actor_rec
            cmp.w   A_TYPE(a0),d2
            bne.s   .o
.tm1        bset    d1,d3
            addq.w  #1,d1
            bra.s   .l
.o          move.l  d3,d0
            movem.l (sp)+,d1-d4/a0
            rts

; d0 = a type -> Z clear when a copy of it is on the screen (d1 = that copy)
type_on_screen:
            movem.l d2/d4/a0,-(sp)
            move.w  d0,d2
            move.w  d0,d1
.l          cmp.w   H_NACT(a4),d1
            bhs.s   .no
            cmp.w   d2,d1                   ; the actor named, then its copies
            beq.s   .ts1
            move.w  d1,d4
            bsr     actor_rec
            cmp.w   A_TYPE(a0),d2
            bne.s   .no
.ts1        move.w  d1,d0
            bsr     on_screen
            bne.s   .yes
            addq.w  #1,d1
            bra.s   .l
.no         moveq   #0,d0
            bra.s   .o
.yes        moveq   #1,d0
.o          movem.l (sp)+,d2/d4/a0
            tst.w   d0
            rts

; d0 / d1 = types a / b -> Z clear when a copy of a touches a copy of b (b = a: anything
; but itself); the pair goes in v_cta / v_ctb. Both shown, neither safe (as touch_pair).
touch_types:
            movem.l d1-d6/a0-a1,-(sp)
            move.w  d0,d2                   ; d2 = type a, d3 = type b
            move.w  d1,d3
            lea     v_arec(a5),a1
            move.w  d2,d6                   ; d6 = a copy of a
.ia         cmp.w   H_NACT(a4),d6
            bhs     .no
            move.w  d6,d0
            add.w   d0,d0
            add.w   d0,d0
            move.l  0(a1,d0.w),a0
            cmp.w   d2,d6                   ; the actor named, then its copies
            beq.s   .ia1
            cmp.w   A_TYPE(a0),d2
            bne     .no
.ia1        move.w  d6,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)          ; hidden or safe: nothing to test
            beq     .na
            tst.w   v_safe(a5,d5.w)
            bne     .na
            move.w  v_ax(a5,d5.w),d0        ; its box
            move.w  d0,d1
            add.w   A_BX0(a0),d0
            move.w  d0,v_hbx0(a5)
            add.w   A_BX1(a0),d1
            move.w  d1,v_hbx1(a5)
            move.w  v_ay(a5,d5.w),d0
            move.w  d0,d1
            add.w   A_BY0(a0),d0
            move.w  d0,v_hby0(a5)
            add.w   A_BY1(a0),d1
            move.w  d1,v_hby1(a5)
            moveq   #0,d5                   ; anything: every actor
            cmp.w   d2,d3
            beq.s   .ib
            move.w  d3,d5                   ; else the copies of b
.ib         cmp.w   H_NACT(a4),d5
            bhs     .na
            move.w  d5,d0
            add.w   d0,d0
            add.w   d0,d0
            move.l  0(a1,d0.w),a0
            cmp.w   d2,d3
            bne.s   .tb
            cmp.w   d5,d6
            beq     .nb
            bra.s   .tp
.tb         cmp.w   d3,d5
            beq.s   .tp
            cmp.w   A_TYPE(a0),d3
            bne     .na
.tp         move.w  d5,d4
            lsl.w   #ACTV_SHIFT,d4
            tst.w   v_vis(a5,d4.w)
            beq.s   .nb
            tst.w   v_safe(a5,d4.w)
            bne.s   .nb
            move.w  v_ax(a5,d4.w),d0
            move.w  d0,d1
            add.w   A_BX0(a0),d0            ; b's left past a's right?
            cmp.w   v_hbx1(a5),d0
            bgt.s   .nb
            add.w   A_BX1(a0),d1            ; b's right before a's left?
            cmp.w   v_hbx0(a5),d1
            blt.s   .nb
            move.w  v_ay(a5,d4.w),d0
            move.w  d0,d1
            add.w   A_BY0(a0),d0
            cmp.w   v_hby1(a5),d0
            bgt.s   .nb
            add.w   A_BY1(a0),d1
            cmp.w   v_hby0(a5),d1
            bge.s   .yes
.nb         addq.w  #1,d5
            bra     .ib
.na         addq.w  #1,d6
            bra     .ia
.no         moveq   #0,d0
            bra.s   .o
.yes        move.w  d6,v_cta(a5)
            move.w  d5,v_ctb(a5)
            moveq   #1,d0
.o          movem.l (sp)+,d1-d6/a0-a1
            tst.w   d0
            rts

; DO 25: a copy of actor d4 that is not out yet comes out on actor R_VAL - a big one
; breaks into small ones, a hatch lets a fighter out. A flyer starts its pattern there;
; each next one zigzags off the other way. It is gone when it leaves the screen.
act_spawn:  movem.l d0-d7/a0-a2,-(sp)
            cmp.w   H_NACT(a4),d4
            bhs     .out
            bsr     ctx_val
            move.w  d0,d6                   ; d6 = where
            cmp.w   H_NACT(a4),d6
            bhs     .out
            bsr     free_copy
            beq     .out
            move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
            bsr     actor_rec
            move.l  a0,a2                   ; a2 = the one that comes out
            move.w  A_PAT(a2),v_pat(a5,d5.w)
            move.w  A_ENTER(a2),v_edge(a5,d5.w)
            move.w  d6,d4
            bsr     actor_rec               ; a0 = where it comes out
            lsl.w   #ACTV_SHIFT,d6
            move.w  A_BX0(a0),d0            ; centred on it
            add.w   A_BX1(a0),d0
            sub.w   A_BX0(a2),d0
            sub.w   A_BX1(a2),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d6.w),d0
            move.w  A_BY0(a0),d1
            add.w   A_BY1(a0),d1
            sub.w   A_BY0(a2),d1
            sub.w   A_BY1(a2),d1
            asr.w   #1,d1
            add.w   v_ay(a5,d6.w),d1
            bsr     come_out
            eor.w   #1,v_spalt(a5)
            move.w  v_spalt(a5),v_dx(a5,d5.w)
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; an actor that fires by itself (A_FIRE; d5 / d7 / a2): every A_FRATE frames, give or take,
; while it is on the screen, a volley of its shot (A_FPAT)
foe_fire:   movem.l d0-d7/a0-a3,-(sp)
            tst.w   v_vis(a5,d5.w)
            beq     .out
            tst.w   v_ftmr(a5,d5.w)
            beq.s   .go
            subq.w  #1,v_ftmr(a5,d5.w)
            bra     .out
.go         move.w  d7,d0
            bsr     on_screen
            beq     .out
            bsr     rand
            and.w   #15,d0
            add.w   A_FRATE(a2),d0
            move.w  d0,v_ftmr(a5,d5.w)
            move.w  A_FIRE(a2),d3           ; d3 = the shot
            cmp.w   H_NACT(a4),d3
            bhs     .out
            move.w  d7,d6                   ; d6 / d7 / a1 = the shooter
            move.w  d5,d7
            move.l  a2,a1
            move.w  d3,d4
            bsr     actor_rec               ; a0 = the shot's record
            move.w  A_FPAT(a1),d0
            beq.s   .own
            cmp.w   #3,d0
            beq.s   .ring
            cmp.w   #4,d0
            beq.s   .fan
            bsr     aim_player              ; 1 / 2: at the player
            beq     .out
            moveq   #0,d2
            moveq   #0,d4
            bsr     shoot_one
            cmp.w   #2,A_FPAT(a1)
            bne     .out
            moveq   #-1,d4
            bsr     shoot_one
            moveq   #1,d4
            bsr     shoot_one
            bra.s   .out
.own        bsr     shot_aim
            bra.s   .one
.fan        bsr     shot_aim
            moveq   #0,d2
            moveq   #-1,d4
            bsr     shoot_one
            moveq   #1,d4
            bsr     shoot_one
.one        moveq   #0,d2
            moveq   #0,d4
            bsr     shoot_one
            bra.s   .out
.ring       move.w  #0,v_aprec(a5)
            lea     ring8(pc),a3
            moveq   #7,d5
.rl         move.b  (a3)+,d0
            ext.w   d0
            move.w  d0,v_aimx(a5)
            move.b  (a3)+,d0
            ext.w   d0
            move.w  d0,v_aimy(a5)
            moveq   #0,d2
            moveq   #0,d4
            bsr     shoot_one
            dbf     d5,.rl
.out        movem.l (sp)+,d0-d7/a0-a3
            rts

ring8:      dc.b    0,-1,1,-1,1,0,1,1,0,1,-1,1,-1,0,-1,-1

; a shot d3 aimed straight at the player from the shooter (a1 / d7): v_avx / v_avy at
; the shot's speed, v_aprec = 1. Z set: no player
aim_player: movem.l d0-d5/a0,-(sp)
            move.w  H_PLAYER(a4),d4
            bmi     .no
            cmp.w   H_NACT(a4),d4
            bhs     .no
            move.w  d3,d5
            lsl.w   #ACTV_SHIFT,d5
            move.w  v_spd(a5,d5.w),d5
            lsl.w   #4,d5                   ; d5 = its speed, 1/16 pixels a frame
            bsr     actor_rec               ; a0 = the player's record
            lsl.w   #ACTV_SHIFT,d4
            move.w  A_BX0(a0),d0            ; player's middle - the shooter's middle
            add.w   A_BX1(a0),d0
            sub.w   A_BX0(a1),d0
            sub.w   A_BX1(a1),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d4.w),d0
            sub.w   v_ax(a5,d7.w),d0
            move.w  A_BY0(a0),d1
            add.w   A_BY1(a0),d1
            sub.w   A_BY0(a1),d1
            sub.w   A_BY1(a1),d1
            asr.w   #1,d1
            add.w   v_ay(a5,d4.w),d1
            sub.w   v_ay(a5,d7.w),d1
            bsr     vec_speed
            move.w  d0,v_avx(a5)
            move.w  d1,v_avy(a5)
            bsr     sign_w
            move.w  d0,v_aimx(a5)
            move.w  d1,d0
            bsr     sign_w
            move.w  d0,v_aimy(a5)
            move.w  #1,v_aprec(a5)
            moveq   #1,d0
            bra.s   .o
.no         moveq   #0,d0
.o          movem.l (sp)+,d0-d5/a0
            rts

; d0 / d1 = a way (pixels), d5 = a speed -> d0 / d1 that way at that speed (octagon length)
vec_speed:  movem.l d2-d4,-(sp)
            move.w  d0,d2
            bpl.s   .a
            neg.w   d2
.a          move.w  d1,d3
            bpl.s   .b
            neg.w   d3
.b          cmp.w   d3,d2                   ; d2 = the longer, d3 = the shorter
            bge.s   .c
            exg     d2,d3
.c          move.w  d3,d4
            add.w   d4,d4
            add.w   d3,d4
            lsr.w   #3,d4
            add.w   d4,d2                   ; length ~ longer + 3/8 shorter
            bne.s   .d
            moveq   #0,d0
            move.w  d5,d1                   ; (right on top of it: down)
            bra.s   .o
.d          muls    d5,d0
            divs    d2,d0
            muls    d5,d1
            divs    d2,d1
.o          movem.l (sp)+,d2-d4
            rts

; a homing missile (d5, a2): every other frame it turns a quarter of the way towards the
; nearest thing it can hit that is on the screen (its hit mask); with nothing there it
; flies on
missile_steer:
            movem.l d0-d7/a0-a1,-(sp)
            btst    #0,v_anim+1(a5)
            bne     .out
            lea     -10(sp),sp              ; (sp) nearest so far, 2 / 4 its way, 6 / 8 this one's
            move.w  #$7fff,(sp)
            move.w  v_pool(a5,d5.w),d0      ; d3 = what it can hit
            moveq   #-1,d3
            cmp.w   #MAX_ACT,d0
            bhs.s   .m
            lsl.w   #2,d0
            lea     v_hitmask(a5),a1
            move.l  0(a1,d0.w),d3
            bne.s   .m
            moveq   #-1,d3
.m          move.w  A_BX0(a2),d6            ; d6 / d7 = its middle
            add.w   A_BX1(a2),d6
            asr.w   #1,d6
            add.w   v_ax(a5,d5.w),d6
            move.w  A_BY0(a2),d7
            add.w   A_BY1(a2),d7
            asr.w   #1,d7
            add.w   v_ay(a5,d5.w),d7
            lea     v_arec(a5),a1
            moveq   #0,d4
.j          tst.l   d3                      ; the actors in its mask, in turn
            beq     .pick
            lsr.l   #1,d3
            bcc     .n
            cmp.w   H_NACT(a4),d4
            bhs     .pick
            cmp.w   H_PLAYER(a4),d4
            beq     .n
            move.w  d4,d1
            lsl.w   #ACTV_SHIFT,d1
            tst.w   v_vis(a5,d1.w)
            beq     .n
            tst.w   v_safe(a5,d1.w)
            bne     .n
            move.w  d4,d0
            add.w   d0,d0
            add.w   d0,d0
            move.l  0(a1,d0.w),a0
            move.w  A_ROLE(a0),d0
            cmp.w   #ROLE_SHOT,d0
            beq     .n
            cmp.w   #ROLE_OPT,d0
            beq     .n
            cmp.w   #ROLE_FX,d0
            beq     .n
            move.w  A_FROM(a0),d0
            cmp.w   v_level(a5),d0
            bgt     .n
            move.w  A_BX0(a0),d0            ; its middle, on the screen?
            add.w   A_BX1(a0),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d1.w),d0
            bmi     .n
            cmp.w   v_pw(a5),d0
            bge     .n
            move.w  A_BY0(a0),d2
            add.w   A_BY1(a0),d2
            asr.w   #1,d2
            add.w   v_ay(a5,d1.w),d2
            cmp.w   v_hudlines(a5),d2
            blt     .n
            cmp.w   #256,d2
            bge     .n
            sub.w   d6,d0                   ; its way to that one's middle
            sub.w   d7,d2
            move.w  d0,6(sp)
            move.w  d2,8(sp)
            tst.w   d0
            bpl.s   .a1
            neg.w   d0
.a1         tst.w   d2
            bpl.s   .a2
            neg.w   d2
.a2         add.w   d2,d0
            cmp.w   (sp),d0
            bge.s   .n
            move.w  d0,(sp)
            move.w  6(sp),2(sp)
            move.w  8(sp),4(sp)
.n          addq.w  #1,d4
            bra     .j
.pick       cmp.w   #$7fff,(sp)
            beq.s   .done
            move.w  2(sp),d0
            move.w  4(sp),d1
            move.w  d5,d7
            move.w  v_spd(a5,d7.w),d5
            lsl.w   #4,d5
            bsr     vec_speed
            sub.w   v_tvx(a5,d7.w),d0       ; a quarter of the way round
            asr.w   #2,d0
            add.w   d0,v_tvx(a5,d7.w)
            sub.w   v_tvy(a5,d7.w),d1
            asr.w   #2,d1
            add.w   d1,v_tvy(a5,d7.w)
.done       lea     10(sp),sp
.out        movem.l (sp)+,d0-d7/a0-a1
            rts

; DO 21: the player drops what it carries (it falls, harmless)
act_drop:   move.w  v_carry(a5),d0
            bmi     act_none
            move.w  #-1,v_carry(a5)
            lsl.w   #ACTV_SHIFT,d0
            move.w  #2,v_thr(a5,d0.w)
            move.w  #0,v_tvx(a5,d0.w)
            move.w  #0,v_vy(a5,d0.w)
            move.w  #0,v_gnd(a5,d0.w)
            rts

; ============================================================================
;  pick up and throw: the player touches an actor with 'can be carried' and
;  presses fire to pick it up (it rides on its head); fire again throws it the
;  way the player faces, in an arc. Each press is used up (v_fwait).
; ============================================================================
carry_tick:
            movem.l d0-d7/a0-a2,-(sp)
            move.w  #-1,v_picked(a5)
            tst.w   v_fwait(a5)             ; fire used for a pick-up / throw: ignored until let go
            beq.s   .fw
            btst    #7,$bfe001              ; the button itself (tool_menu may have masked v_joy already)
            beq.s   .fm
            move.w  #0,v_fwait(a5)
            bra.s   .fw
.fm         and.w   #$ffef,v_joy(a5)
.fw         move.w  H_PLAYER(a4),d7
            bmi     .out
            cmp.w   H_NACT(a4),d7
            bhs     .out
            move.w  d7,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d5.w)
            beq     .out
            move.w  v_joy(a5),d0            ; fire just pressed?
            btst    #4,d0
            beq     .out
            move.w  v_joyprev(a5),d0
            btst    #4,d0
            bne     .out
            tst.w   v_carry(a5)
            bpl.s   .throw
            moveq   #0,d6                   ; pick up the first carriable actor it touches
.pk         cmp.w   H_NACT(a4),d6
            bge     .out
            cmp.w   #MAX_ACT,d6
            bge     .out
            cmp.w   d7,d6
            beq.s   .pn
            move.w  d6,d4
            bsr     actor_rec
            tst.w   A_CARRY(a0)
            beq.s   .pn
            move.w  A_FROM(a0),d0
            cmp.w   v_level(a5),d0
            bgt.s   .pn
            move.w  d6,d1
            lsl.w   #ACTV_SHIFT,d1
            tst.w   v_thr(a5,d1.w)          ; not while it flies
            bne.s   .pn
            move.w  d7,d0
            move.w  d6,d1
            bsr     overlap_pair
            beq.s   .pn
            move.w  d6,v_carry(a5)
            move.w  d6,v_picked(a5)
            bra.s   .used
.pn         addq.w  #1,d6
            bra.s   .pk
.throw      move.w  v_carry(a5),d1
            lsl.w   #ACTV_SHIFT,d1
            move.w  #1,v_thr(a5,d1.w)
            moveq   #THROW_VX,d0
            tst.w   v_face(a5,d5.w)
            beq.s   .tr
            neg.w   d0
.tr         move.w  d0,v_tvx(a5,d1.w)
            move.w  #-THROW_VY,v_vy(a5,d1.w)
            move.w  #0,v_ysub(a5,d1.w)
            move.w  #0,v_gnd(a5,d1.w)
            move.w  #-1,v_carry(a5)
.used       move.w  #1,v_fwait(a5)          ; this press is used up
            and.w   #$ffef,v_joy(a5)
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; the carried actor: its box centred over the player's, standing on its head
carry_follow:
            movem.l d0-d7/a0-a2,-(sp)
            move.w  v_carry(a5),d6
            bmi     .out
            move.w  H_PLAYER(a4),d4
            bmi.s   .drop
            move.w  d6,d1
            lsl.w   #ACTV_SHIFT,d1
            tst.w   v_vis(a5,d1.w)          ; hidden by a rule: no longer carried
            beq.s   .drop
            bsr     actor_rec               ; a0 = the player's record
            move.l  a0,a1
            move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
            move.w  d6,d4
            bsr     actor_rec               ; a0 = the carried actor's
            move.w  A_BX0(a1),d0            ; x: centre on centre
            add.w   A_BX1(a1),d0
            sub.w   A_BX0(a0),d0
            sub.w   A_BX1(a0),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d5.w),d0
            bpl.s   .x0
            moveq   #0,d0
.x0         cmp.w   A_XMAX(a0),d0
            ble.s   .x1
            move.w  A_XMAX(a0),d0
.x1         move.w  d0,v_ax(a5,d1.w)
            move.w  v_ay(a5,d5.w),d0        ; y: its feet on the player's head
            add.w   A_BY0(a1),d0
            sub.w   A_BY1(a0),d0
            subq.w  #1,d0
            bpl.s   .y0
            moveq   #0,d0
.y0         move.w  d0,v_ay(a5,d1.w)
            move.w  #0,v_vy(a5,d1.w)
            move.w  #0,v_ysub(a5,d1.w)
            move.w  v_face(a5,d5.w),v_face(a5,d1.w)
            bra.s   .out
.drop       move.w  #-1,v_carry(a5)
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; the thrown actor d7 (d5, a2): note the first actor it hits (not the player),
; then it is spent and drops
throw_hits:
            movem.l d0-d6/a0,-(sp)
            moveq   #0,d6
.j          cmp.w   H_NACT(a4),d6
            bge.s   .out
            cmp.w   #MAX_ACT,d6
            bge.s   .out
            cmp.w   d7,d6
            beq.s   .n
            cmp.w   H_PLAYER(a4),d6
            beq.s   .n
            move.w  d6,d4
            bsr     actor_rec
            move.w  A_FROM(a0),d0
            cmp.w   v_level(a5),d0
            bgt.s   .n
            move.w  d7,d0
            move.w  d6,d1
            bsr     overlap_pair
            beq.s   .n
            move.w  v_hitn(a5),d0
            cmp.w   #HIT_MAX,d0
            bge.s   .sp
            lea     v_hits(a5),a0
            add.w   d0,d0
            move.b  d7,0(a0,d0.w)
            move.b  d6,1(a0,d0.w)
            addq.w  #1,v_hitn(a5)
.sp         move.w  #2,v_thr(a5,d5.w)
            move.w  #0,v_tvx(a5,d5.w)
            bra.s   .out
.n          addq.w  #1,d6
            bra.s   .j
.out        movem.l (sp)+,d0-d6/a0
            rts

; the shot d7 (d5, a2): the first actor it hits - not the one that fired it, not another
; shot, not one that is safe - goes in v_hits as (the actor the Shoot rule named, it).
; Z clear when it hit something. Only the actors in its hit mask are looked at: the
; boxes first, the rest only when they overlap.
shot_hits:
            movem.l d1-d6/a0-a1,-(sp)
            move.w  v_pool(a5,d5.w),d0      ; d3 = what this shot stops at (v_hitmask)
            moveq   #-1,d3
            cmp.w   #MAX_ACT,d0
            bhs.s   .m
            lsl.w   #2,d0
            lea     v_hitmask(a5),a1
            move.l  0(a1,d0.w),d3
            bne.s   .m
            moveq   #-1,d3                  ; no rule for it: anything
.m          move.w  v_ax(a5,d5.w),d0        ; the shot's box
            move.w  d0,d1
            add.w   A_BX0(a2),d0
            move.w  d0,v_hbx0(a5)
            add.w   A_BX1(a2),d1
            move.w  d1,v_hbx1(a5)
            move.w  v_ay(a5,d5.w),d0
            move.w  d0,d1
            add.w   A_BY0(a2),d0
            move.w  d0,v_hby0(a5)
            add.w   A_BY1(a2),d1
            move.w  d1,v_hby1(a5)
            lea     v_arec(a5),a1
            moveq   #0,d6
.j          tst.l   d3
            beq     .none
            lsr.l   #1,d3
            bcc     .n
            cmp.w   H_NACT(a4),d6
            bhs     .none
            move.w  d6,d1
            lsl.w   #ACTV_SHIFT,d1          ; d1 = its offset
            tst.w   v_vis(a5,d1.w)
            beq     .n
            move.w  d6,d0
            add.w   d0,d0
            add.w   d0,d0
            move.l  0(a1,d0.w),a0           ; a0 = its record
            move.w  v_ax(a5,d1.w),d2        ; its left past the shot's right?
            move.w  d2,d4
            add.w   A_BX0(a0),d2
            cmp.w   v_hbx1(a5),d2
            bgt     .n
            add.w   A_BX1(a0),d4            ; its right before the shot's left?
            cmp.w   v_hbx0(a5),d4
            blt     .n
            move.w  v_ay(a5,d1.w),d2
            move.w  d2,d4
            add.w   A_BY0(a0),d2
            cmp.w   v_hby1(a5),d2
            bgt     .n
            add.w   A_BY1(a0),d4
            cmp.w   v_hby0(a5),d4
            blt     .n
            cmp.w   d7,d6                   ; they overlap: is it something it can hit?
            beq     .n
            cmp.w   v_owner(a5,d5.w),d6
            beq     .n
            tst.w   v_safe(a5,d1.w)
            bne     .n
            move.w  A_ROLE(a0),d0
            cmp.w   #ROLE_SHOT,d0           ; shots pass each other by, and options and effects
            beq     .n
            cmp.w   #ROLE_OPT,d0
            beq     .n
            cmp.w   #ROLE_FX,d0
            beq     .n
            cmp.w   H_PLAYER(a4),d6         ; an option's shots pass the player by
            bne.s   .lv
            move.w  v_owner(a5,d5.w),d4
            move.l  a0,-(sp)
            bsr     actor_rec
            cmp.w   #ROLE_OPT,A_ROLE(a0)
            move.l  (sp)+,a0
            beq.s   .n
.lv         move.w  A_FROM(a0),d0
            cmp.w   v_level(a5),d0
            bgt.s   .n
            subq.w  #1,v_hp(a5,d1.w)        ; a tough one: each hit but the last only flashes it
            ble.s   .down
            move.w  #HIT_FLASH,v_hitf(a5,d1.w)
            bra.s   .hit
.down       move.w  A_HP(a0),d0             ; worn down: ready for the next time, and WHEN 11
            bne.s   .hp
            moveq   #1,d0
.hp         move.w  d0,v_hp(a5,d1.w)
            move.w  #0,v_hitf(a5,d1.w)
            move.w  v_hitn(a5),d0
            cmp.w   #HIT_MAX,d0
            bge.s   .hit
            lea     v_hits(a5),a0
            add.w   d0,d0
            move.b  v_pool+1(a5,d5.w),0(a0,d0.w)
            move.b  d6,1(a0,d0.w)
            addq.w  #1,v_hitn(a5)
.hit        moveq   #1,d0
            bra.s   .out
.n          addq.w  #1,d6
            bra     .j
.none       moveq   #0,d0
.out        movem.l (sp)+,d1-d6/a0-a1
            tst.w   d0
            rts

; d0.w -> -1, 0 or 1
sign_w:     tst.w   d0
            beq.s   .r
            bmi.s   .m
            moveq   #1,d0
            rts
.m          moveq   #-1,d0
.r          rts

; DO 22: fire the shot d4 (d5) from actor R_VAL. When it is already flying the next
; actor after it that is a shot (role 9) goes instead, so a few shots in a row make
; rapid fire. It starts on the shooter's middle and flies its aim (A_UP) at its speed.
; The player fires a volley as wide as its firepower (v_power), and each of its
; options fires one more shot the same way.
act_shoot:
            movem.l d0-d7/a0-a2,-(sp)
            move.w  d4,d3                   ; d3 = the shot the rule names
            cmp.w   H_NACT(a4),d3
            bhs     .out
            bsr     ctx_val
            move.w  d0,d6                   ; d6 = the shooter
            cmp.w   H_NACT(a4),d6
            bhs     .out
            move.w  d6,d0                   ; shown, on this level and on the screen
            bsr     on_screen
            beq     .out
            move.w  d6,d7
            lsl.w   #ACTV_SHIFT,d7          ; d7 = its offset
            move.w  d6,d4
            bsr     actor_rec
            move.l  a0,a1                   ; a1 = the shooter's record
            move.w  d3,d4
            bsr     actor_rec               ; a0 = the named shot's record
            bsr     shot_aim                ; -> v_aimx / v_aimy
            lea     vol_tab(pc),a2          ; the volley: one shot, or the player's firepower
            moveq   #0,d0
            cmp.w   H_PLAYER(a4),d6
            bne.s   .v0
            move.w  v_power(a5),d0
            cmp.w   #6,A_UP(a0)             ; homing missiles: as many as it has picked up
            bne.s   .v1
            move.w  v_miss(a5),d0
            beq     .out
            addq.w  #3,d0
.v1         add.w   d0,d0
.v0         move.w  0(a2,d0.w),d0
            lea     0(a2,d0.w),a2
.vol        move.b  (a2)+,d2                ; side offset
            cmp.b   #$7f,d2
            beq.s   .opts
            ext.w   d2
            move.b  (a2)+,d4                ; spread
            ext.w   d4
            bsr     shoot_one
            beq.s   .out                    ; no shot free
            bra.s   .vol
.opts       cmp.w   H_PLAYER(a4),d6         ; the player's options fire too (not missiles)
            bne.s   .out
            cmp.w   #6,A_UP(a0)
            beq.s   .out
            moveq   #0,d5
.ol         cmp.w   H_NACT(a4),d5
            bge.s   .out
            move.w  d5,d4
            bsr     actor_rec
            cmp.w   #ROLE_OPT,A_ROLE(a0)
            bne.s   .on
            move.w  d5,d0
            bsr     on_screen
            beq.s   .on
            move.w  d5,d6
            move.w  d5,d7
            lsl.w   #ACTV_SHIFT,d7
            move.l  a0,a1
            moveq   #0,d2
            moveq   #0,d4
            bsr     shoot_one
            beq.s   .out
.on         addq.w  #1,d5
            bra.s   .ol
.out        movem.l (sp)+,d0-d7/a0-a2
            rts

; the player's volleys (v_power 0..3): pairs of (pixels to the side, spread), $7f ends
vol_tab:    dc.w    vol_1-vol_tab,vol_2-vol_tab,vol_3-vol_tab,vol_4-vol_tab,vol_m1-vol_tab,vol_m2-vol_tab
vol_1:      dc.b    0,0,$7f
vol_2:      dc.b    -6,0,6,0,$7f
vol_3:      dc.b    0,0,0,-1,0,1,$7f
vol_4:      dc.b    -6,0,6,0,0,-1,0,1,$7f
vol_m1:     dc.b    0,0,$7f                 ; homing missiles
vol_m2:     dc.b    -10,0,10,0,$7f
            even

; the way a volley flies (a0 = the named shot, a1 / d6 / d7 = the shooter) -> v_aimx /
; v_aimy, each -1, 0 or 1: the shot's aim (A_UP) - 1 up, 2 down, 3 left, 4 right,
; 5 at the player (8 directions), 0 the way the shooter goes (the player: the
; joystick, else the way it last moved; a platform player: the way it faces)
shot_aim:   movem.l d0-d4/a0,-(sp)
            move.w  #0,v_aprec(a5)
            move.w  A_UP(a0),d2
            cmp.w   #6,d2                   ; 6: a missile sets off the way the screen scrolls
            bne.s   .n6
            moveq   #0,d0
            moveq   #-1,d1                  ; (up when it does not)
            move.w  v_scr(a5),d2
            cmp.w   #2,d2
            bne.s   .s3
            moveq   #1,d0
            moveq   #0,d1
.s3         cmp.w   #3,d2
            bne.s   .s4
            moveq   #1,d1
.s4         cmp.w   #4,d2
            bne     .go
            moveq   #-1,d0
            moveq   #0,d1
            bra     .go
.n6         moveq   #0,d0
            moveq   #-1,d1
            cmp.w   #1,d2
            beq     .go                     ; up
            moveq   #1,d1
            cmp.w   #2,d2
            beq     .go                     ; down
            moveq   #0,d1
            moveq   #-1,d0
            cmp.w   #3,d2
            beq     .go                     ; left
            moveq   #1,d0
            cmp.w   #4,d2
            beq     .go                     ; right
            cmp.w   #5,d2
            beq.s   .atp
            cmp.w   #6,A_ROLE(a1)           ; 0: a platform player shoots the way it faces
            bne.s   .joy
            moveq   #1,d0
            tst.w   v_face(a5,d7.w)
            beq     .go
            moveq   #-1,d0
            bra     .go
.joy        cmp.w   H_PLAYER(a4),d6         ; the player: the way the stick points
            bne.s   .last
            move.w  v_joy(a5),d2
            moveq   #0,d0
            moveq   #0,d1
            btst    #0,d2
            beq.s   .j1
            moveq   #-1,d1
.j1         btst    #1,d2
            beq.s   .j2
            moveq   #1,d1
.j2         btst    #2,d2
            beq.s   .j3
            moveq   #-1,d0
.j3         btst    #3,d2
            beq.s   .j4
            moveq   #1,d0
.j4         move.w  d0,d2
            or.w    d1,d2
            bne     .go
.last       move.w  v_mdx(a5,d7.w),d0       ; else the way it last moved
            move.w  v_mdy(a5,d7.w),d1
            move.w  d0,d2
            or.w    d1,d2
            bne     .go
            moveq   #-1,d1                  ; (never moved: up)
            bra     .go
.atp        move.w  H_PLAYER(a4),d4         ; 5: at the player, in one of 8 directions
            bmi.s   .last
            bsr     actor_rec               ; a0 = the player's record
            lsl.w   #ACTV_SHIFT,d4
            move.w  A_BX0(a0),d0            ; player's middle - the shooter's middle
            add.w   A_BX1(a0),d0
            sub.w   A_BX0(a1),d0
            sub.w   A_BX1(a1),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d4.w),d0
            sub.w   v_ax(a5,d7.w),d0
            move.w  A_BY0(a0),d1
            add.w   A_BY1(a0),d1
            sub.w   A_BY0(a1),d1
            sub.w   A_BY1(a1),d1
            asr.w   #1,d1
            add.w   v_ay(a5,d4.w),d1
            sub.w   v_ay(a5,d7.w),d1
            move.w  d0,d2                   ; d2 / d4 = how far across / down
            bpl.s   .ax
            neg.w   d2
.ax         move.w  d1,d4
            bpl.s   .ay
            neg.w   d4
.ay         add.w   d2,d2                   ; across only when it is more than half the way down
            cmp.w   d4,d2
            bgt.s   .sx
            moveq   #0,d0
.sx         lsr.w   #1,d2
            add.w   d4,d4                   ; down only when it is more than half the way across
            cmp.w   d2,d4
            bgt.s   .sy
            moveq   #0,d1
.sy         bsr     sign_w
            exg     d0,d1
            bsr     sign_w
            exg     d0,d1
            move.w  d0,d2
            or.w    d1,d2
            bne.s   .go
            moveq   #1,d1                   ; (right on top of it: down)
.go         move.w  d0,v_aimx(a5)
            move.w  d1,v_aimy(a5)
            movem.l (sp)+,d0-d4/a0
            rts

; one shot of a volley: d3 = the shot named, d6 / d7 / a1 = the shooter, d2 = pixels to
; the side of the aim it starts, d4 = -1 / 0 / 1 it veers that way. Z set: no shot free
shoot_one:  movem.l d0-d7/a0-a2,-(sp)
            move.w  d2,v_vside(a5)
            move.w  d4,v_vspr(a5)
            move.w  d3,d4                   ; a free shot: the one named, or a shot after it
.find       cmp.w   H_NACT(a4),d4
            bhs     .none
            cmp.w   #MAX_ACT,d4
            bhs     .none
            cmp.w   d6,d4
            beq     .none
            bsr     actor_rec               ; a0 = its record
            cmp.w   d3,d4
            beq.s   .head
            cmp.w   A_TYPE(a0),d3           ; its copies
            bne     .none
.head       move.w  d4,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_thr(a5,d5.w)          ; flying (or thrown)
            bne.s   .nx
            cmp.w   v_carry(a5),d4
            beq.s   .nx
            move.w  A_FROM(a0),d0
            cmp.w   v_level(a5),d0
            ble.s   .free
.nx         addq.w  #1,d4
            bra.s   .find

.free       move.w  A_BX0(a1),d0            ; its box centred on the shooter's
            add.w   A_BX1(a1),d0
            sub.w   A_BX0(a0),d0
            sub.w   A_BX1(a0),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d7.w),d0
            move.w  A_BY0(a1),d1
            add.w   A_BY1(a1),d1
            sub.w   A_BY0(a0),d1
            sub.w   A_BY1(a0),d1
            asr.w   #1,d1
            add.w   v_ay(a5,d7.w),d1
            move.w  v_aimy(a5),d2           ; moved to the side: (-aim y, aim x) x pixels
            neg.w   d2
            muls    v_vside(a5),d2
            add.w   d2,d0
            move.w  v_aimx(a5),d2
            muls    v_vside(a5),d2
            add.w   d2,d1
            tst.w   v_tmode(a5)
            bne.s   .pos
            tst.w   d0                      ; one screen: it starts on it
            bpl.s   .x0
            moveq   #0,d0
.x0         cmp.w   A_XMAX(a0),d0
            ble.s   .x1
            move.w  A_XMAX(a0),d0
.x1         tst.w   d1
            bpl.s   .y0
            moveq   #0,d1
.y0         cmp.w   A_YMAX(a0),d1
            ble.s   .pos
            move.w  A_YMAX(a0),d1
.pos        move.w  d0,v_ax(a5,d5.w)
            move.w  d1,v_ay(a5,d5.w)
            move.w  d0,v_px(a5,d5.w)
            move.w  d1,v_py(a5,d5.w)
            move.w  d0,v_ox(a5,d5.w)
            move.w  d1,v_oy(a5,d5.w)

            tst.w   v_aprec(a5)             ; a worked-out way (aimed at the player)
            bne.s   .prec
            move.w  v_aimx(a5),d0           ; aim x speed, a bit less on the diagonals
            move.w  v_aimy(a5),d1
            move.w  v_spd(a5,d5.w),d2
            tst.w   d0
            beq.s   .sp
            tst.w   d1
            beq.s   .sp
            move.w  d2,d4
            lsr.w   #2,d4
            sub.w   d4,d2
.sp         lsl.w   #4,d2                   ; 1/16 pixels a frame
            muls    d2,d0
            muls    d2,d1
            bra.s   .spr
.prec       move.w  v_avx(a5),d0
            move.w  v_avy(a5),d1
.spr        move.w  d0,d2                   ; spread: half its speed to the side
            move.w  d1,d4
            asr.w   #1,d2
            asr.w   #1,d4
            muls    v_vspr(a5),d2
            muls    v_vspr(a5),d4
            sub.w   d4,d0
            add.w   d2,d1
            move.w  d0,v_tvx(a5,d5.w)
            move.w  d1,v_tvy(a5,d5.w)
            move.w  #0,v_xsub(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
            move.w  #SHOT_FLY,v_thr(a5,d5.w)
            move.w  #1,v_vis(a5,d5.w)
            move.w  #0,v_life(a5,d5.w)
            move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_gnd(a5,d5.w)
            move.w  d6,v_owner(a5,d5.w)
            move.w  d3,v_pool(a5,d5.w)
            moveq   #1,d0
            bra.s   .out
.none       moveq   #0,d0
.out        tst.w   d0
            movem.l (sp)+,d0-d7/a0-a2
            rts

; d0 / d1 = actors -> Z clear when both are shown and their boxes overlap
overlap_pair:
            movem.l d2-d5/a0-a1,-(sp)
            move.w  d0,d2
            move.w  d1,d3
            move.w  d2,d4
            bsr     actor_rec
            move.l  a0,a1
            move.w  d3,d4
            bsr     actor_rec               ; a1 = record a, a0 = record b
            move.w  d2,d4
            lsl.w   #ACTV_SHIFT,d4
            move.w  d3,d5
            lsl.w   #ACTV_SHIFT,d5
            tst.w   v_vis(a5,d4.w)
            beq     .no
            tst.w   v_vis(a5,d5.w)
            beq     .no
            move.w  v_ax(a5,d4.w),d2        ; a.left > b.right ?
            add.w   A_BX0(a1),d2
            move.w  v_ax(a5,d5.w),d3
            add.w   A_BX1(a0),d3
            cmp.w   d3,d2
            bgt.s   .no
            move.w  v_ax(a5,d5.w),d2        ; b.left > a.right ?
            add.w   A_BX0(a0),d2
            move.w  v_ax(a5,d4.w),d3
            add.w   A_BX1(a1),d3
            cmp.w   d3,d2
            bgt.s   .no
            move.w  v_ay(a5,d4.w),d2        ; a.top > b.bottom ?
            add.w   A_BY0(a1),d2
            move.w  v_ay(a5,d5.w),d3
            add.w   A_BY1(a0),d3
            cmp.w   d3,d2
            bgt.s   .no
            move.w  v_ay(a5,d5.w),d2        ; b.top > a.bottom ?
            add.w   A_BY0(a0),d2
            move.w  v_ay(a5,d4.w),d3
            add.w   A_BY1(a1),d3
            cmp.w   d3,d2
            bgt.s   .no
            moveq   #1,d0
            bra.s   .out
.no         moveq   #0,d0
.out        movem.l (sp)+,d2-d5/a0-a1
            tst.w   d0
            rts

; play song R_VAL from the top / stop the music
act_music:  move.w  R_VAL(a3),d0
            bra     music_play
act_nomusic:
            bra     music_stop

act_moment: cmp.w   H_NACT(a4),d4
            bhs     act_none
            move.w  #1,v_vis(a5,d5.w)
            move.w  #MOMENT,v_life(a5,d5.w)
            rts

act_safe:   cmp.w   H_NACT(a4),d4
            bhs     act_none
            move.w  #SAFE_TIME,v_safe(a5,d5.w)
            rts

; one more towards the level goal; reaching it finishes the level
act_goal:   move.l  v_game(a5),d0
            beq     act_none
            move.l  d0,a0
            move.w  G_GOAL(a0),d1
            beq     act_none
            addq.w  #1,v_goal(a5)
            bsr     draw_hud
            move.w  v_goal(a5),d0
            cmp.w   d1,d0
            blt     act_none
            move.w  v_level(a5),d0          ; last level done: congratulations
            cmp.w   G_NLEVELS(a0),d0
            bge     act_win
            bra     level_next

stop_fall:  move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_ysub(a5,d5.w)
            move.w  #0,v_gnd(a5,d5.w)
            move.w  #0,v_thr(a5,d5.w)       ; a thrown actor lands where it is sent
            move.w  #0,v_tvx(a5,d5.w)
            cmp.w   v_carry(a5),d4          ; and is no longer carried
            bne.s   .r
            move.w  #-1,v_carry(a5)
.r          rts

; target (d4/d5) goes to the place where actor R_VAL is
act_moveto: cmp.w   H_NACT(a4),d4
            bhs     act_none
            bsr     ctx_val
            cmp.w   H_NACT(a4),d0
            bhs     act_none
            lsl.w   #ACTV_SHIFT,d0
            move.w  v_ax(a5,d0.w),v_ax(a5,d5.w)
            move.w  v_ay(a5,d0.w),d1
            addq.w  #8,d1
            move.w  d1,v_ay(a5,d5.w)
            bsr     stop_fall
            bsr     actor_rec
            cmp.w   #ROLE_FLY,A_ROLE(a0)    ; a flyer carries on from there
            bne     trail_check
            move.l  a0,a2
            bra     fly_rebase

act_score:  moveq   #0,d0
            move.w  R_VAL(a3),d0
            add.l   v_score(a5),d0
            cmp.l   #SCORE_MAX,d0
            bls.s   .ok
            move.l  #SCORE_MAX,d0
.ok         move.l  d0,v_score(a5)
            bra     draw_hud

act_loselife:
            tst.w   v_lives(a5)
            beq.s   .z
            subq.w  #1,v_lives(a5)
.z          bsr     items_life              ; items lost with a life
            bra     draw_hud

act_addlife:
            cmp.w   #9,v_lives(a5)
            bhs.s   .z
            addq.w  #1,v_lives(a5)
.z          bra     draw_hud

act_sound:  move.w  R_VAL(a3),d0
            and.w   #63,d0
            bra     play_sfx

act_flash:  move.w  #16,v_flash(a5)
            rts

act_home:   cmp.w   H_NACT(a4),d4
            bhs     act_none
            bsr     stop_fall
            bsr     actor_rec
            cmp.w   #ROLE_FLY,A_ROLE(a0)    ; a flyer: back off the screen, to fly in again
            bne.s   .pl
            move.l  a0,a2
            bra     fly_start
.pl         move.w  A_X(a0),v_ax(a5,d5.w)
            move.w  A_Y(a0),v_ay(a5,d5.w)
            bra     trail_check

act_random: cmp.w   H_NACT(a4),d4
            bhs     act_none
            bsr     stop_fall
            bsr     actor_rec
            cmp.w   #ROLE_FLY,A_ROLE(a0)    ; a flyer comes in again from its edge
            bne.s   .any
            move.l  a0,a2
            bra     fly_again
.any        move.w  A_XMAX(a0),d2
            addq.w  #1,d2
            move.w  A_YMAX(a0),d3
            sub.w   #15,d3
            bsr     rand
            and.l   #$ffff,d0
            divu    d2,d0
            swap    d0
            move.w  d0,v_ax(a5,d5.w)
            bsr     rand
            and.l   #$ffff,d0
            divu    d3,d0
            swap    d0
            add.w   #16,d0                  ; keep clear of the top row
            move.w  d0,v_ay(a5,d5.w)
            bra     trail_check

act_hide:   cmp.w   H_NACT(a4),d4
            bhs     act_none
            move.w  #0,v_vis(a5,d5.w)
            cmp.l   #-1,v_cta(a5)           ; no copy made the rule fire: every copy hides
            bne.s   .r                      ; (v_cta and v_ctb both -1)
            movem.l d0-d2/a0,-(sp)
            move.w  d4,d2
            move.w  d4,d1
.l          addq.w  #1,d1
            cmp.w   H_NACT(a4),d1
            bhs.s   .o
            move.w  d1,d4
            bsr     actor_rec
            cmp.w   A_TYPE(a0),d2
            bne.s   .o
            move.w  d1,d0
            lsl.w   #ACTV_SHIFT,d0
            move.w  #0,v_vis(a5,d0.w)
            bra.s   .l
.o          move.w  d2,d4
            movem.l (sp)+,d0-d2/a0
.r          rts

act_show:   cmp.w   H_NACT(a4),d4
            bhs     act_none
            move.w  #1,v_vis(a5,d5.w)
            rts

act_bgcol:  move.w  R_VAL(a3),d0
            move.w  H_DEPTH(a4),d6
            moveq   #1,d1
            lsl.w   d6,d1
            cmp.w   d1,d0
            bhs     act_none
            move.l  H_PAL(a4),d1
            lea     0(a4,d1.l),a0
            add.w   d0,d0
            add.w   d0,d0
            move.l  0(a0,d0.w),d1
            move.l  d1,v_bg(a5)
            tst.l   H_GRAD(a4)
            beq.s   .plain
            bsr     rgb12                   ; the sky becomes this one colour
            move.w  d4,v_gradfix(a5)
            move.w  d4,d1
            bra     build_grad
.plain      move.l  d1,v_curpal(a5)         ; (a palette fade starts from it)
            moveq   #0,d0
            bra     setcol

act_faster: cmp.w   H_NACT(a4),d4
            bhs     act_none
            cmp.w   #8,v_spd(a5,d5.w)
            bhs.s   .z
            addq.w  #1,v_spd(a5,d5.w)
.z          rts

act_slower: cmp.w   H_NACT(a4),d4
            bhs     act_none
            cmp.w   #1,v_spd(a5,d5.w)
            bls.s   .z
            subq.w  #1,v_spd(a5,d5.w)
.z          rts

act_over:   move.l  H_TOVER(a4),d0
            lea     0(a4,d0.l),a0
            bra.s   end_screen
act_win:    move.l  H_TWIN(a4),d0
            lea     0(a4,d0.l),a0

; a0 = message.  Shows it, waits for fire, then restarts the game.
end_screen:
            move.l  a0,-(sp)                ; (scroll_off uses a0)
            bsr     scroll_off
            bsr     tiles_off
            bsr     music_stop              ; music and effects off
            bsr     hide_sprites
            move.l  (sp)+,a0
            moveq   #0,d0
            move.l  v_bg(a5),d1
            bsr     setcol
            move.l  a0,a1                   ; centre the text
            moveq   #0,d1
.len        tst.b   (a1)+
            beq.s   .lend
            addq.w  #1,d1
            bra.s   .len
.lend       cmp.w   #40,d1
            bls.s   .lok
            moveq   #40,d1
.lok        neg.w   d1
            add.w   #40,d1
            lsr.w   #1,d1
            subq.w  #1,d1                   ; one space of box either side
            moveq   #15,d2
            move.w  H_MSGCOL(a4),d3
            move.w  #1,v_opaque(a5)
            moveq   #' ',d0
            bsr     draw_char
            addq.w  #1,d1
            bsr     draw_text
            move.l  a0,a1
.end        tst.b   (a1)+
            beq.s   .endd
            addq.w  #1,d1
            bra.s   .end
.endd       moveq   #' ',d0
            bsr     draw_char
            move.w  #0,v_opaque(a5)
            bsr     wait_fire
            bra     game_restart

; waits for fire to be released, pressed and released again
wait_fire:
.wr         bsr     wait_vbl
            btst    #7,$bfe001
            beq.s   .wr
.wp         bsr     wait_vbl
            btst    #7,$bfe001
            bne.s   .wp
.wu         bsr     wait_vbl
            btst    #7,$bfe001
            beq.s   .wu
            rts

; "LEVEL 3" into v_text
level_text: move.l  v_game(a5),a0
            lea     G_LEVTXT(a0),a0
            lea     v_text(a5),a1
.c          move.b  (a0)+,(a1)+
            bne.s   .c
            move.b  #' ',-1(a1)
            move.w  v_level(a5),d0
            cmp.w   #10,d0
            blt.s   .one
            move.b  #'1',(a1)+
            sub.w   #10,d0
.one        add.b   #'0',d0
            move.b  d0,(a1)+
            move.b  #0,(a1)
            rts

; a0 = text, d2 = text row: centred, small letters, message colour
centre_text:
            move.l  a0,a1
            moveq   #0,d1
.len        tst.b   (a1)+
            beq.s   .l2
            addq.w  #1,d1
            bra.s   .len
.l2         neg.w   d1
            add.w   #40,d1
            asr.w   #1,d1
            bpl.s   .ok
            moveq   #0,d1
.ok         move.w  H_MSGCOL(a4),d3
            bra     draw_text

; a0 = text, d2 = pixel line: centred, double-size letters straight onto the screen
big_text:   movem.l d0-d7/a0-a3,-(sp)
            move.l  a0,a1
            moveq   #0,d1
.len        tst.b   (a1)+
            beq.s   .l2
            addq.w  #1,d1
            bra.s   .len
.l2         cmp.w   #20,d1
            ble.s   .l3
            moveq   #20,d1
.l3         move.w  d1,d4                   ; characters
            add.w   d1,d1
            neg.w   d1
            add.w   #40,d1
            lsr.w   #1,d1                   ; first byte column
            subq.w  #1,d4
            bmi.s   .out
.ch         moveq   #0,d0
            move.b  (a0)+,d0
            bsr     big_char
            addq.w  #2,d1
            dbf     d4,.ch
.out        movem.l (sp)+,d0-d7/a0-a3
            rts

; d0 = character, d1 = byte column, d2 = pixel line (16 x 16, transparent)
big_char:   movem.l d0-d7/a0-a3,-(sp)
            and.w   #$ff,d0
            cmp.w   #96,d0
            blo.s   .up
            sub.w   #32,d0
.up         cmp.w   #32,d0
            blo.s   .sp
            cmp.w   #96,d0
            blo.s   .ok
.sp         moveq   #32,d0
.ok         sub.w   #32,d0
            lsl.w   #3,d0
            move.l  v_font(a5),a1
            add.w   d0,a1
            move.w  d2,d4
            mulu    #40,d4
            add.w   d1,d4
            move.l  v_disp(a5),a2
            add.l   d4,a2                   ; top-left byte on screen
            move.w  H_MSGCOL(a4),d3
            moveq   #7,d7                   ; 8 glyph rows
            move.l  v_dd2(a5),d2            ; BOBs: both displays (0 = same byte)
.row        move.b  (a1)+,d0                ; double every bit -> 16 bit mask
            moveq   #0,d5
            moveq   #7,d6
.bit        add.w   d5,d5
            add.w   d5,d5
            btst    d6,d0
            beq.s   .b0
            or.w    #3,d5
.b0         dbf     d6,.bit
            move.w  d5,d6
            not.w   d6
            moveq   #0,d4                   ; plane
            move.l  a2,a3
            move.w  H_DEPTH(a4),d1
            subq.w  #1,d1
.pl         move.b  (a3),d0                 ; two screen lines, high byte then low byte
            ror.w   #8,d6
            and.b   d6,d0
            ror.w   #8,d5
            btst    d4,d3
            beq.s   .c1
            or.b    d5,d0
.c1         move.b  d0,(a3)
            move.b  d0,40(a3)
            move.b  d0,0(a3,d2.l)
            move.b  d0,40(a3,d2.l)
            move.b  1(a3),d0
            ror.w   #8,d6
            and.b   d6,d0
            ror.w   #8,d5
            btst    d4,d3
            beq.s   .c2
            or.b    d5,d0
.c2         move.b  d0,1(a3)
            move.b  d0,41(a3)
            move.b  d0,1(a3,d2.l)
            move.b  d0,41(a3,d2.l)
            add.l   #PLANE_SIZE,a3
            addq.w  #1,d4
            dbf     d1,.pl
            lea     80(a2),a2
            dbf     d7,.row
            movem.l (sp)+,d0-d7/a0-a3
            rts

; d4 = actor index -> a0 = actor record (d0 is changed)
actor_rec:  move.w  d4,d0
            and.w   #MAX_ACT-1,d0
            add.w   d0,d0
            add.w   d0,d0
            lea     v_arec(a5),a0
            move.l  0(a0,d0.w),a0
            rts

; xorshift32 -> d0.l
rand:       move.l  d1,-(sp)
            move.l  v_rand(a5),d0
            move.l  d0,d1
            lsl.l   #8,d1
            lsl.l   #5,d1
            eor.l   d1,d0
            move.l  d0,d1
            clr.w   d1
            swap    d1
            lsr.l   #1,d1
            eor.l   d1,d0
            move.l  d0,d1
            lsl.l   #5,d1
            eor.l   d1,d0
            move.l  d0,v_rand(a5)
            move.l  (sp)+,d1
            rts

; ============================================================================
;  border-style screen flash on colour 0
; ============================================================================
flash_tick:
            move.w  v_flash(a5),d0
            beq.s   .r
            subq.w  #1,d0
            move.w  d0,v_flash(a5)
            beq.s   .restore
            btst    #1,d0
            beq.s   .restore
            tst.l   H_GRAD(a4)
            beq.s   .white
            move.w  #$0fff,d1
            bra     build_grad
.white      moveq   #0,d0
            move.l  #$ffffff,d1
            bra     setcol
.restore    tst.l   H_GRAD(a4)
            beq.s   .plain
            move.w  v_gradfix(a5),d1
            bra     build_grad
.plain      moveq   #0,d0
            move.l  v_bg(a5),d1
            bra     setcol
.r          rts

; ============================================================================
;  named palettes (version 11)
; ============================================================================
; d5.w = the backdrop colours a palette can change (1 << depth, at most PAL_FADE); d4 is lost
pal_ncol:   move.w  H_DEPTH(a4),d5
            moveq   #1,d4
            lsl.w   d5,d4
            move.w  d4,d5
            cmp.w   #PAL_FADE,d5
            ble.s   .r
            move.w  #PAL_FADE,d5
.r          rts

; at a level start: the palette the level starts with, at once
level_pal:  movem.l d0-d1/a0,-(sp)
            move.l  H_PALS(a4),d0
            beq.s   .r
            lea     0(a4,d0.l),a0
            move.w  v_level(a5),d1
            subq.w  #1,d1
            cmp.w   #10,d1
            bhs.s   .r
            moveq   #0,d0
            move.b  PS_LEVEL(a0,d1.w),d0
            moveq   #0,d1
            bsr     pal_switch
.r          movem.l (sp)+,d0-d1/a0
            rts

; d0.w = palette (0 = the main one, 1.. the named ones), d1.w = frames to fade over (0 = at once).
; The colours a palette leaves alone are the main palette's.
pal_switch:
            movem.l d0-d7/a0-a3,-(sp)
            move.l  H_PALS(a4),d2
            beq     .out
            lea     0(a4,d2.l),a3           ; the palettes block
            cmp.w   PS_N(a3),d0             ; unsigned: a bad number does nothing
            bhi     .out
            bsr     pal_ncol                ; d5 = colours
            lea     v_frompal(a5),a0        ; fade from what is shown now
            lea     v_curpal(a5),a1
            move.w  d5,d3
            bra.s   .fc
.f          move.l  (a1)+,(a0)+
.fc         dbf     d3,.f
            lea     v_tgtpal(a5),a0         ; to the main palette ...
            move.l  H_PAL(a4),d2
            lea     0(a4,d2.l),a1
            move.w  d5,d3
            bra.s   .tc
.t          move.l  (a1)+,(a0)+
.tc         dbf     d3,.t
            tst.w   d0
            beq.s   .go
            subq.w  #1,d0                   ; ... with this palette's colours
            lsl.w   #2,d0
            move.l  PS_OFFS(a3,d0.w),d2
            lea     0(a4,d2.l),a1
            lea     v_tgtpal(a5),a0
            move.w  (a1)+,d3
            bra.s   .oc
.o          move.w  (a1)+,d2
            addq.l  #2,a1
            move.l  (a1)+,d4
            cmp.w   d5,d2
            bhs.s   .oc
            lsl.w   #2,d2
            move.l  d4,0(a0,d2.w)
.oc         dbf     d3,.o
.go         tst.w   d1
            bgt.s   .fr
            moveq   #1,d1
.fr         move.w  d1,v_pftot(a5)
            move.w  d1,v_pfade(a5)
            cmp.w   #1,d1
            bne.s   .out
            bsr     pal_tick                ; at once
.out        movem.l (sp)+,d0-d7/a0-a3
            rts

; every frame while a palette fades: each colour = from + (to - from) x step / frames
pal_tick:
            tst.w   v_pfade(a5)
            beq     .r
            movem.l d0-d7/a0-a2,-(sp)
            move.w  v_pftot(a5),d7
            move.w  d7,d6
            sub.w   v_pfade(a5),d6
            addq.w  #1,d6                   ; d6 = step 1 .. frames
            subq.w  #1,v_pfade(a5)
            bsr     pal_ncol                ; d5 = colours
            lea     v_frompal(a5),a0
            lea     v_tgtpal(a5),a1
            lea     v_curpal(a5),a2
            move.w  #1,v_cophold(a5)        ; AGA with a sky: the copper waits once, not per colour
            btst    #0,H_FLAGS+1(a4)
            beq.s   .go
            tst.l   H_GRAD(a4)
            beq.s   .go
            move.w  #$0080,$96(a6)
.go         moveq   #0,d0                   ; colour index
.c          move.l  (a0)+,d1
            move.l  (a1)+,d2
            moveq   #0,d4
            moveq   #16,d3
            bsr.s   .comp
            moveq   #8,d3
            bsr.s   .comp
            moveq   #0,d3
            bsr.s   .comp
            cmp.l   (a2),d4
            beq.s   .same
            move.l  d4,(a2)
            move.l  d4,d1
            bsr     setcol
            tst.w   d0
            bne.s   .same
            move.l  d4,v_bg(a5)             ; colour 0: a flash comes back to it
.same       addq.l  #4,a2
            addq.w  #1,d0
            cmp.w   d5,d0
            blt.s   .c
            move.w  #0,v_cophold(a5)
            btst    #0,H_FLAGS+1(a4)
            beq.s   .done
            tst.l   H_GRAD(a4)
            beq.s   .done
            move.w  #$8080,$96(a6)
.done       movem.l (sp)+,d0-d7/a0-a2
.r          rts
; one gun: d1 = from, d2 = to, d3 = its shift -> ORed into d4
.comp       movem.l d1-d2,-(sp)
            lsr.l   d3,d1
            and.l   #$ff,d1
            lsr.l   d3,d2
            and.l   #$ff,d2
            sub.w   d1,d2
            muls    d6,d2
            divs    d7,d2
            add.w   d1,d2
            and.l   #$ff,d2
            lsl.l   d3,d2
            or.l    d2,d4
            movem.l (sp)+,d1-d2
            rts

; ============================================================================
;  copper sky: COLOR00 changes on every display line
;  d1.w = -1 : use the gradient table      d1.w = $0RGB : one fixed colour
; ============================================================================
;  On AGA the table has a second half: 256 words of low nibbles. Each line
;  then writes COLOR00 twice - high nibbles (LOCT clear, which also copies
;  them to the low nibbles), then the low nibbles with LOCT set - so the sky
;  gets 24-bit colour. One fixed colour (d1 >= 0) only needs the first write.
build_grad:
            movem.l d0-d5/a0-a2,-(sp)
            lea     cop_grad-V-128(a5),a0
            move.l  H_GRAD(a4),d0
            beq     .nosky
            lea     0(a4,d0.l),a1           ; high nibbles
            lea     512(a1),a2              ; low nibbles (AGA)
            moveq   #0,d5                   ; d5 = 1: write low nibbles too
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            tst.w   d1
            bpl.s   .ocs
            moveq   #1,d5
.ocs        move.w  #$0180,(a0)+            ; top border = first colour
            move.w  (a1),d2
            tst.w   d1
            bmi.s   .top
            move.w  d1,d2
.top        move.w  d2,(a0)+
            tst.w   d5
            beq.s   .t0
            move.l  #$01060e00,(a0)+        ; BPLCON3: LOCT
            move.w  #$0180,(a0)+
            move.w  (a2),(a0)+
            move.l  #$01060c00,(a0)+        ; BPLCON3: back to normal
.t0         moveq   #0,d3                   ; line index
.line       move.w  d3,d4
            add.w   #$2c,d4
            cmp.w   #$100,d4                ; past line 255: wait for the wrap
            bne.s   .w
            move.l  #$ffdffffe,(a0)+
.w          lsl.w   #8,d4
            or.w    #$07,d4
            move.w  d4,(a0)+
            move.w  #$fffe,(a0)+
            tst.w   v_split(a5)             ; tile world / scrolling: the moving picture starts here
            beq.s   .nosp
            cmp.w   v_hudlines(a5),d3
            bne.s   .nosp
            bsr     .split
.nosp       tst.w   d5
            beq.s   .hi
            move.l  #$01060c00,(a0)+        ; BPLCON3: bank 0, high nibbles
.hi         move.w  #$0180,(a0)+
            bsr     .col
            move.w  d2,(a0)+
            tst.w   d5
            beq.s   .nx
            move.l  #$01060e00,(a0)+        ; BPLCON3: LOCT, low nibbles
            move.w  #$0180,(a0)+
            move.w  (a2)+,(a0)+
.nx         addq.w  #1,d3
            cmp.w   #256,d3
            blt.s   .line
            tst.w   d5
            beq.s   .off
            move.l  #$01060c00,(a0)+        ; leave BPLCON3 as the CPU set it
.off        move.l  #$fffffffe,(a0)+
            movem.l (sp)+,d0-d5/a0-a2
            rts
.nosky      tst.w   v_split(a5)             ; no sky: just the split
            beq.s   .off
            move.w  v_hudlines(a5),d0       ; wait for the end of the HUD strip
            add.w   #$2c,d0
            lsl.w   #8,d0
            or.w    #$07,d0
            move.w  d0,(a0)+
            move.w  #$fffe,(a0)+
            bsr     .split
            bra.s   .off
; bitplane pointers (filled in by cop_scroll), modulos and fine scroll
.split      move.l  a0,v_csplit(a5)
            move.w  H_DEPTH(a4),d4
            subq.w  #1,d4
            move.w  #$00e0,d2
.sp         move.w  d2,(a0)+
            move.w  #0,(a0)+
            addq.w  #2,d2
            move.w  d2,(a0)+
            move.w  #0,(a0)+
            addq.w  #2,d2
            dbf     d4,.sp
            move.w  v_smod(a5),d2           ; modulo below the split
            move.w  #$0108,(a0)+
            move.w  d2,(a0)+
            move.w  #$010a,(a0)+
            move.w  d2,(a0)+
            move.l  #$01020000,(a0)+
            move.w  v_ddfs(a5),d2           ; a narrow map: fetch only the play area
            beq.s   .spw
            move.w  #$0092,(a0)+
            move.w  d2,(a0)+
            move.w  #$0094,(a0)+
            move.w  v_ddfe(a5),(a0)+
.spw        bsr     cop_scroll              ; the right pointers at once: rebuilding the whole list
            tst.w   v_scr(a5)               ; (a flash) takes longer than the vertical blank, and the
            beq.s   .spr                    ; copper must never meet empty ones
            movem.l d0-d1,-(sp)
            move.l  v_shbuf(a5),d0
            move.w  v_shpos(a5),d1
            bsr     scroll_show
            movem.l (sp)+,d0-d1
.spr        rts
.col        move.w  (a1)+,d2                ; next table colour, or the fixed one
            tst.w   d1
            bmi.s   .t
            move.w  d1,d2
.t          rts

; 24-bit $00RRGGBB in d1 -> 12-bit $0RGB in d4
rgb12:      move.l  d3,-(sp)
            move.l  d1,d3
            lsr.l   #8,d3
            lsr.l   #4,d3
            and.w   #$0f00,d3
            move.w  d3,d4
            move.l  d1,d3
            lsr.l   #8,d3
            and.w   #$00f0,d3
            or.w    d3,d4
            move.l  d1,d3
            lsr.l   #4,d3
            and.w   #$000f,d3
            or.w    d3,d4
            move.l  (sp)+,d3
            rts

; ============================================================================
;  music and sound effects - both played by ptplayer (CIA-B interrupts)
; ============================================================================
init_music:
            move.w  #-1,v_song(a5)
            moveq   #0,d0
            move.l  H_MUSIC(a4),d1
            beq.s   .none
            move.l  d1,d0
            add.l   a4,d0
.none       move.l  d0,v_music(a5)
            rts

; d0.w = song index: plays that song from the top. A song that is not in
; the music table (or is empty) leaves the music stopped.
music_play:
            movem.l d0-d1/a0-a1,-(sp)
            bsr     music_stop
            move.l  v_music(a5),d1
            beq.s   .out
            move.l  d1,a0
            cmp.w   M_NSONGS(a0),d0         ; unsigned: a negative index fails too
            bhs.s   .out
            move.w  d0,d1
            lsl.w   #3,d1
            lea     M_SONGS(a0,d1.w),a0
            move.l  (a0)+,d1                ; offset of the MOD bytes
            tst.l   (a0)                    ; length
            beq.s   .out
            tst.l   d1
            bpl.s   .mem
            bsr     song_fetch              ; on disk 2: read it in (if it is not already)
            cmp.w   v_d2song(a5),d0
            bne.s   .out                    ; could not
            move.l  H_DISK2(a4),d1
            lea     0(a4,d1.l),a0
            move.l  D2_BUF(a0),d1
.mem        move.w  d0,v_song(a5)
            lea     0(a4,d1.l),a0           ; a0 = MOD
            sub.l   a1,a1                   ; samples follow the patterns
            moveq   #0,d0                   ; from the first song position
            bsr     _mt_init
            lea     _mt_Enable(pc),a0
            st      (a0)                    ; go
.out        movem.l (sp)+,d0-d1/a0-a1
            rts

; ============================================================================
;  disk 2 (version 12)
; ============================================================================
disk2_init: move.w  #-1,v_d2song(a5)
            move.w  #-1,v_d2drv(a5)
            move.l  #-1,v_dcyl(a5)
            move.l  #-1,v_dcyl+4(a5)
            rts

; at a level card: when this level's song lives on disk 2, read it in now (asking for
; the disk if it is in no drive), so the level starts with it
level_disk2:
            movem.l d0-d1/a0,-(sp)
            tst.l   H_DISK2(a4)
            beq.s   .out
            move.l  v_music(a5),d0
            beq.s   .out
            move.l  d0,a0
            move.w  v_level(a5),d1
            subq.w  #1,d1
            cmp.w   #9,d1
            bls.s   .lv
            moveq   #0,d1
.lv         moveq   #0,d0
            move.b  M_LEVEL(a0,d1.w),d0
            cmp.w   #$ff,d0
            beq.s   .out
            bsr     song_fetch
.out        movem.l (sp)+,d0-d1/a0
            rts

; d0.w = song: when it lives on disk 2 and is not in the buffer, find disk 2 and read it
; in (v_d2song = d0 when it worked). The music stops while the disk is read.
song_fetch:
            movem.l d0-d7/a0-a3,-(sp)
            move.l  v_music(a5),d1
            beq     .out
            move.l  d1,a0
            cmp.w   M_NSONGS(a0),d0
            bhs     .out
            cmp.w   v_d2song(a5),d0
            beq     .out                    ; in the buffer already
            move.w  d0,d7                   ; d7 = song
            lsl.w   #3,d0
            move.l  M_SONGS(a0,d0.w),d5     ; offset
            bpl     .out                    ; on the game disk: in memory
            move.l  M_SONGS+4(a0,d0.w),d6   ; length
            beq     .out
            and.l   #$7fffffff,d5
            bsr     music_stop
            move.w  #-1,v_d2song(a5)
            bsr     disk2_find              ; -> d0 drive
            lea     str_loading(pc),a0
            moveq   #15,d2
            bsr     say
            move.l  d5,d1
            divu    #TRK_BYTES,d1           ; d1.w = its first track
            add.l   #TRK_BYTES-1,d6
            divu    #TRK_BYTES,d6           ; d6.w = tracks
            move.l  H_DISK2(a4),d2
            lea     0(a4,d2.l),a2
            move.l  D2_BUF(a2),d2
            lea     0(a4,d2.l),a2           ; a2 = the song buffer
            subq.w  #1,d6
.trk        bsr     track_read
            bne.s   .bad
            lea     TRK_BYTES(a2),a2
            addq.w  #1,d1
            dbf     d6,.trk
            move.w  d7,v_d2song(a5)
            bra.s   .done
.bad        bsr     drive_off               ; a damaged disk 2: say so, then play on without it
            lea     str_d2err(pc),a0
            moveq   #17,d2
            bsr     say
            bsr     wait_fire
.done       bsr     drive_off
            bsr     restore_backdrop
.out        movem.l (sp)+,d0-d7/a0-a3
            rts

; a0 = text, d2 = row: a message on the screen (registers kept)
say:        movem.l d0-d7/a0-a3,-(sp)
            bsr     centre_text
            movem.l (sp)+,d0-d7/a0-a3
            rts

; -> d0.w = the drive disk 2 is in: where it was last, then DF1, then DF0; while it is
; in none of them the screen asks for it
disk2_find:
            movem.l d1-d7/a0-a3,-(sp)
            moveq   #0,d7                   ; 1 once the screen asks
.again      move.w  v_d2drv(a5),d0
            bmi.s   .try1
            bsr     disk2_check
            beq.s   .found
.try1       moveq   #1,d0
            bsr     disk2_check
            beq.s   .found
            moveq   #0,d0
            bsr     disk2_check
            beq.s   .found
            bsr     drive_off
            tst.w   d7
            bne.s   .wait
            moveq   #1,d7
            lea     str_disk2(pc),a0
            moveq   #15,d2
            bsr     say
.wait       moveq   #24,d6                  ; half a second, then look again
.w          bsr     wait_vbl
            dbf     d6,.w
            bra.s   .again
.found      move.w  d0,v_d2drv(a5)
            tst.w   d7
            beq.s   .r
            bsr     restore_backdrop        ; the request goes
.r          movem.l (sp)+,d1-d7/a0-a3
            rts

; d0.w = drive: Z set when disk 2 (its 'ADM2' sector with D2_ID) is in it
disk2_check:
            movem.l d0-d2/a0-a2,-(sp)
            move.l  H_DISK2(a4),d1
            lea     0(a4,d1.l),a1
            move.l  D2_BUF(a1),d1
            lea     0(a4,d1.l),a2           ; read track 0 into the song buffer
            moveq   #0,d1
            bsr     track_read
            bne.s   .no
            cmp.l   #'ADM2',(a2)
            bne.s   .no
            move.l  D2_ID(a1),d1
            cmp.l   4(a2),d1
.no         movem.l (sp)+,d0-d2/a0-a2       ; (movem keeps the flags)
            rts

; d0.w = drive, d1.w = track 0..159, a2 = 5632 bytes: reads the track's 11 sectors.
; Z set when they all came in (three tries).
track_read:
            movem.l d0-d7/a0-a3,-(sp)
            moveq   #2,d7
.try        bsr     drive_on
            move.w  d1,d2
            lsr.w   #1,d2
            bsr     seek
            btst    #0,d1
            bne.s   .up
            bset    #2,$bfd100              ; /SIDE high: the lower head (side 0)
            bra.s   .rd
.up         bclr    #2,$bfd100              ; the upper head (side 1)
.rd         bsr     raw_read
            bne.s   .fail
            bsr     decode_track
            beq.s   .ok
.fail       dbf     d7,.try
            moveq   #1,d0                   ; Z clear
            bra.s   .out
.ok         moveq   #0,d0                   ; Z set
.out        movem.l (sp)+,d0-d7/a0-a3
            rts

; d0.w = drive 0..3: selected with its motor on; waits (at most ~0.6 s) for it to be ready
drive_on:   movem.l d0-d2,-(sp)
            moveq   #3,d1
            add.w   d0,d1                   ; its /SELx bit
            or.b    #$78,$bfd100            ; no drive selected
            bclr    #7,$bfd100              ; motor on ...
            bclr    d1,$bfd100              ; ... latched as it is selected
            move.w  #300,d2
.rdy        btst    #5,$bfe001              ; /RDY
            beq.s   .r
            moveq   #31,d0                  ; ~2 ms
            bsr     lines_wait
            dbf     d2,.rdy
.r          movem.l (sp)+,d0-d2
            rts

; every drive's motor off, none selected
drive_off:  movem.l d0-d1,-(sp)
            moveq   #3,d1
.m          or.b    #$78,$bfd100
            bset    #7,$bfd100              ; motor off ...
            move.w  d1,d0
            addq.w  #3,d0
            bclr    d0,$bfd100              ; ... latched as it is selected
            or.b    #$78,$bfd100
            dbf     d1,.m
            movem.l (sp)+,d0-d1
            rts

; d0.w = drive (selected), d2.w = cylinder: moves its head there (the first time from cylinder 0)
seek:       movem.l d0-d4/a0,-(sp)
            lea     v_dcyl(a5),a0
            add.w   d0,d0
            add.w   d0,a0
            move.w  (a0),d3                 ; where its head is, -1 = not known
            bpl.s   .known
            bset    #1,$bfd100              ; outwards, to cylinder 0
            moveq   #89,d4
.zero       btst    #4,$bfe001              ; /TK0
            beq.s   .at0
            bsr.s   .step
            dbf     d4,.zero
.at0        moveq   #0,d3
.known      cmp.w   d3,d2
            beq.s   .there
            bhi.s   .in
            bset    #1,$bfd100              ; out
            subq.w  #1,d3
            bra.s   .st
.in         bclr    #1,$bfd100              ; in
            addq.w  #1,d3
.st         bsr.s   .step
            bra.s   .known
.there      move.w  d3,(a0)
            move.w  #300,d0                 ; the head settles (~19 ms)
            bsr     lines_wait
            movem.l (sp)+,d0-d4/a0
            rts
.step       bclr    #0,$bfd100              ; a step pulse
            bset    #0,$bfd100
            move.w  #47,d0                  ; ~3 ms
            bra     lines_wait

; d0.w = raster lines to wait (64 us each)
lines_wait: movem.l d0-d1,-(sp)
.l          move.b  6(a6),d1
.s          cmp.b   6(a6),d1
            beq.s   .s
            dbf     d0,.l
            movem.l (sp)+,d0-d1
            rts

; reads one turn of the selected drive's track by disk DMA, from the first sync word.
; -> a0 = the raw buffer, Z set when it came in
raw_read:   movem.l d0-d1,-(sp)
            move.l  H_DISK2(a4),d0
            lea     0(a4,d0.l),a0
            move.l  D2_RAW(a0),d0
            lea     0(a4,d0.l),a0
            move.w  #$4000,$24(a6)          ; DSKLEN: no disk DMA
            move.w  #$8210,$96(a6)          ; DMACON: disk DMA on
            move.w  #$7f00,$9e(a6)          ; ADKCON: precomp off ...
            move.w  #$9500,$9e(a6)          ; ... MFM, word sync, 2 us cells
            move.w  #$4489,$7e(a6)          ; DSKSYNC
            move.l  a0,$20(a6)              ; DSKPT
            move.w  #$0002,$9c(a6)          ; INTREQ: DSKBLK clear
            move.w  #$8000+RAW_WORDS,$24(a6)
            move.w  #$8000+RAW_WORDS,$24(a6) ; (written twice to start)
            move.w  #250,d1                 ; at most ~0.5 s
.w          btst    #1,$1f(a6)              ; INTREQR: DSKBLK
            bne.s   .done
            moveq   #31,d0
            bsr     lines_wait
            dbf     d1,.w
            move.w  #$4000,$24(a6)
            movem.l (sp)+,d0-d1
            andi.b  #$fb,ccr                ; Z clear: nothing came
            rts
.done       move.w  #$4000,$24(a6)
            move.w  #$0002,$9c(a6)
            movem.l (sp)+,d0-d1
            ori.b   #$04,ccr                ; Z set
            rts

; a0 = raw track, a2 = 5632 bytes, d1.w = track: decodes its sectors (AmigaDOS: after
; the sync, info long, label, header checksum, data checksum, 512 data bytes - odd
; bits then even bits). Z set when all 11 came in with good checksums.
decode_track:
            movem.l d0-d7/a0-a3,-(sp)
            moveq   #0,d6                   ; a bit per sector decoded
            move.l  #$55555555,d5
            lea     RAW_WORDS*2-1088(a0),a3 ; the last place a whole sector can start
.find       cmp.l   a3,a0
            bhs     .end
            cmp.w   #$4489,(a0)+
            bne.s   .find
.sync       cmp.w   #$4489,(a0)
            bne.s   .hdr
            addq.l  #2,a0
            bra.s   .sync
.hdr        move.l  (a0),d0                 ; info, odd bits
            move.l  4(a0),d2                ;       even bits
            and.l   d5,d0
            and.l   d5,d2
            add.l   d0,d0
            or.l    d2,d0                   ; $ff, track, sector, sectors to the gap
            move.l  d0,d2
            swap    d2
            cmp.b   d1,d2
            bne.s   .find                   ; another track
            lsr.w   #8,d0
            and.w   #$ff,d0                 ; d0 = sector
            cmp.w   #11,d0
            bhs.s   .find
            move.l  48(a0),d3               ; data checksum
            move.l  52(a0),d2
            and.l   d5,d3
            and.l   d5,d2
            add.l   d3,d3
            or.l    d2,d3
            lea     56(a0),a1
            moveq   #0,d4
            move.w  #255,d2
.ck         move.l  (a1)+,d7
            eor.l   d7,d4
            dbf     d2,.ck
            and.l   d5,d4
            cmp.l   d3,d4
            bne.s   .find                   ; damaged: the next try reads it again
            move.l  a3,-(sp)
            lea     56(a0),a1
            move.w  d0,d2
            mulu    #512,d2
            lea     0(a2,d2.l),a3
            moveq   #127,d2
.dc         move.l  512(a1),d4              ; even bits
            move.l  (a1)+,d3                ; odd bits
            and.l   d5,d3
            and.l   d5,d4
            add.l   d3,d3
            or.l    d4,d3
            move.l  d3,(a3)+
            dbf     d2,.dc
            move.l  (sp)+,a3
            bset    d0,d6
            lea     1080(a0),a0
            bra     .find
.end        cmp.w   #$07ff,d6
            movem.l (sp)+,d0-d7/a0-a3
            rts

; stops the music and any sound effects
music_stop:
            movem.l d0-d1/a0-a1,-(sp)
            move.w  #-1,v_song(a5)
            bsr     _mt_end                 ; also clears _mt_Enable
            movem.l (sp)+,d0-d1/a0-a1
            rts

; at 'level starts': this level's song (entry 0 for a single screen game).
; A song that is already playing carries on; a level with no song leaves
; the music as it is (a 'play music' or 'stop music' rule decides).
level_music:
            movem.l d0-d1/a0,-(sp)
            move.l  v_music(a5),d0
            beq.s   .out
            move.l  d0,a0
            move.w  v_level(a5),d1
            subq.w  #1,d1
            cmp.w   #9,d1
            bls.s   .lv
            moveq   #0,d1
.lv         moveq   #0,d0
            move.b  M_LEVEL(a0,d1.w),d0
            cmp.w   #$ff,d0
            beq.s   .out
            cmp.w   v_song(a5),d0
            beq.s   .out
            bsr     music_play
.out        movem.l (sp)+,d0-d1/a0
            rts

; d0 = sound 0..63 (ADAM writes a table entry for every sound and keeps rule
; and tile values below the count). With no music it plays on channel (sound AND 3), as it
; always did; while a song plays ptplayer picks the channel that disturbs
; the music least. The channel goes back to the music when the sound ends.
play_sfx:
            movem.l d0-d1/a0-a1,-(sp)
            and.w   #63,d0
            move.l  H_SFX(a4),d1
            lea     0(a4,d1.l),a0
            move.w  d0,d1
            lsl.w   #3,d1
            add.w   d1,a0                   ; a0 = sound entry
            tst.w   4(a0)                   ; length in words
            beq.s   .out
            lea     v_sfx(a5),a1
            move.l  (a0),d1
            add.l   a4,d1
            move.l  d1,(a1)                 ; sfx_ptr
            move.w  4(a0),4(a1)             ; sfx_len
            move.w  6(a0),d1                ; per-sound period (sampled sounds)
            bne.s   .per
            move.w  #SFX_PERIOD,d1
.per        move.w  d1,6(a1)                ; sfx_per
            move.w  #64,8(a1)               ; sfx_vol
            and.w   #3,d0
            tst.w   v_song(a5)
            bmi.s   .cha
            moveq   #-1,d0                  ; music playing: best channel
.cha        move.b  d0,10(a1)               ; sfx_cha
            move.b  #64,11(a1)              ; sfx_pri: all equal, newest wins
            move.l  a1,a0
            bsr     _mt_playfx
.out        movem.l (sp)+,d0-d1/a0-a1
            rts

; ============================================================================
;  text  (8 x 8 font, 40 columns x 32 rows, drawn into the bitplanes)
;  draw_text:  a0 = string, d1 = column, d2 = row, d3 = palette index
;  draw_char:  d0 = character, d1 = column, d2 = row, d3 = palette index
; ============================================================================
draw_text:
            movem.l d0-d1/a0,-(sp)
.c          moveq   #0,d0
            move.b  (a0)+,d0
            beq.s   .done
            cmp.w   #40,d1
            bhs.s   .done
            bsr     draw_char
            addq.w  #1,d1
            bra.s   .c
.done       movem.l (sp)+,d0-d1/a0
            rts

draw_char:
            cmp.w   #40,d1                  ; off the right edge: nothing
            bhs     .off
            movem.l d0-d7/a0-a3,-(sp)
            and.w   #$ff,d0
            cmp.w   #96,d0                  ; fold lower case
            blo.s   .up
            sub.w   #32,d0
.up         cmp.w   #32,d0
            blo.s   .sp
            cmp.w   #96,d0
            blo.s   .ok
.sp         moveq   #32,d0
.ok         sub.w   #32,d0
            lsl.w   #3,d0
            move.l  v_font(a5),a1
            add.w   d0,a1                   ; glyph
            move.w  d2,d4
            mulu    #320,d4
            add.w   d1,d4                   ; byte offset of the cell
            move.l  v_disp(a5),a2
            add.l   d4,a2
            move.l  v_work(a5),a3
            add.l   d4,a3                   ; backdrop + hills under the cell
            move.w  H_DEPTH(a4),d6
            subq.w  #1,d6
            moveq   #0,d5                   ; plane number
.plane      move.l  a1,a0
            moveq   #7,d7
.line       move.b  (a0)+,d0                ; glyph bits
            moveq   #0,d4                   ; shadow bits: the line above, one pixel right
            tst.w   v_shadow(a5)
            bmi.s   .ns
            cmp.w   #7,d7
            beq.s   .ns
            move.b  -2(a0),d4
            lsr.b   #1,d4
.ns         moveq   #0,d1                   ; opaque text: colour 0 box
            tst.w   v_opaque(a5)
            bne.s   .bg
            move.b  (a3),d1                 ; background
.bg
            move.b  d0,d2
            or.b    d4,d2
            not.b   d2
            and.b   d2,d1
            btst    d5,d3
            beq.s   .clr
            or.b    d0,d1
.clr        move.w  v_shadow(a5),d2         ; the shadow where there is no letter
            bmi.s   .wr
            btst    d5,d2
            beq.s   .wr
            move.b  d0,d2
            not.b   d2
            and.b   d4,d2
            or.b    d2,d1
.wr         move.b  d1,(a2)
            move.l  v_dd2(a5),d2            ; BOBs: the second display too (0 = same byte)
            move.b  d1,0(a2,d2.l)
            move.l  v_ddk(a5),d2            ; and the BOB background, so wiping a BOB keeps the text
            move.b  d1,0(a2,d2.l)
            lea     40(a2),a2
            lea     40(a3),a3
            dbf     d7,.line
            add.l   #PLANE_SIZE-320,a2
            add.l   #PLANE_SIZE-320,a3
            addq.w  #1,d5
            dbf     d6,.plane
            movem.l (sp)+,d0-d7/a0-a3
.off        rts

; d0 = 0..99 drawn as two digits at d1 (d1 moves on)
two_digits: movem.l d0/d4,-(sp)
            and.l   #$ffff,d0
            divu    #10,d0
            move.l  d0,d4
            add.b   #'0',d0
            bsr     draw_char
            addq.w  #1,d1
            swap    d4
            move.w  d4,d0
            add.b   #'0',d0
            bsr     draw_char
            addq.w  #1,d1
            movem.l (sp)+,d0/d4
            rts

draw_hud:
            tst.l   v_ui(a5)
            bne     ui_hud
            movem.l d0-d3/a0-a1,-(sp)
            move.w  v_hudrow(a5),d2
            move.w  H_HUDCOL(a4),d3
            tst.w   H_SHOWSC(a4)
            beq.s   .nosc
            lea     str_score(pc),a0
            moveq   #1,d1
            bsr     draw_text
            move.l  v_score(a5),d0          ; 5 decimal digits
            lea     v_digits+5(a5),a0
            move.b  #0,(a0)
            moveq   #4,d1
.dg         divu    #10,d0
            swap    d0
            add.b   #'0',d0
            move.b  d0,-(a0)
            clr.w   d0
            swap    d0
            dbf     d1,.dg
            moveq   #7,d1
            bsr     draw_text
.nosc       move.l  v_game(a5),d0           ; goal counter
            beq.s   .nogoal
            move.l  d0,a1
            tst.w   G_GOAL(a1)
            beq.s   .nogoal
            lea     G_LABEL(a1),a0
            moveq   #15,d1
            bsr     hud_digging
            beq.s   .gl
            moveq   #13,d1                  ; digging: room for the tile carried
.gl         bsr     draw_text
.lab        tst.b   (a0)+                   ; column after the label
            beq.s   .labd
            addq.w  #1,d1
            bra.s   .lab
.labd       addq.w  #1,d1
            move.w  v_goal(a5),d0
            bsr     two_digits
            moveq   #'/',d0
            bsr     draw_char
            addq.w  #1,d1
            move.w  G_GOAL(a1),d0
            bsr     two_digits
.nogoal     bsr     hud_digging             ; digging: the tile the player places, and how many
            beq.s   .notile
            move.w  v_sel(a5),d0
            move.l  v_tiles(a5),a0
            move.w  T_NT(a0),d1
            lsl.w   #3,d1
            lea     T_PROPS(a0,d1.w),a0     ; names
            add.w   d0,d0
            add.w   d0,d0
            add.w   d0,a0
            moveq   #24,d1
            moveq   #3,d0
.tn         move.l  d0,-(sp)
            move.b  (a0)+,d0
            bne.s   .tc
            moveq   #' ',d0
.tc         bsr     draw_char
            addq.w  #1,d1
            move.l  (sp)+,d0
            dbf     d0,.tn
            moveq   #' ',d0
            bsr     draw_char
            addq.w  #1,d1
            move.w  v_sel(a5),d0
            add.w   d0,d0
            lea     v_inv(a5),a0
            move.w  0(a0,d0.w),d0
            bsr     two_digits
.notile     tst.w   H_SHOWLV(a4)
            beq.s   .nolv
            lea     str_lives(pc),a0
            moveq   #31,d1
            bsr     hud_digging
            beq.s   .lv
            moveq   #32,d1
.lv         bsr     draw_text
            moveq   #'0',d0
            add.w   v_lives(a5),d0
            addq.w  #6,d1
            bsr     draw_char
.nolv       movem.l (sp)+,d0-d3/a0-a1
            rts

;  the custom HUD panel picture -> the work copy (top or bottom strip)
ui_panel_blit:
            movem.l d0-d3/a0-a2,-(sp)
            move.l  v_ui(a5),d0
            beq.s   .r
            move.l  d0,a2
            move.l  UI_PANEL(a2),d0
            beq.s   .r
            lea     0(a4,d0.l),a0           ; the picture, plane after plane
            move.w  v_hudrow0(a5),d0
            mulu    #320,d0                 ; byte where the strip starts
            move.l  v_work(a5),a1
            add.l   d0,a1
            move.w  UI_ROWS(a2),d2
            mulu    #80,d2                  ; longs a plane (rows x 8 lines x 40 bytes / 4)
            subq.w  #1,d2
            move.w  H_DEPTH(a4),d3
            subq.w  #1,d3
.pl         move.l  a1,-(sp)
            move.w  d2,d1
.cp         move.l  (a0)+,(a1)+
            dbf     d1,.cp
            move.l  (sp)+,a1
            add.l   #PLANE_SIZE,a1
            dbf     d3,.pl
.r          movem.l (sp)+,d0-d3/a0-a2
            rts

;  the custom HUD: each field in its place, colour, shadow and label
ui_hud:     movem.l d0-d7/a0-a3,-(sp)
            move.l  v_ui(a5),a3
            move.w  UI_NF(a3),d7
            beq     .done
            subq.w  #1,d7
            lea     UI_FIELDS(a3),a2
.f          move.w  F_ROW(a2),d2
            cmp.w   UI_ROWS(a3),d2          ; only rows the panel has
            bcc     .nx
            add.w   v_hudrow(a5),d2
            move.w  F_COL(a2),d1
            move.w  F_COLOUR(a2),d3
            move.w  F_SHADOW(a2),v_shadow(a5)
            lea     F_LABEL(a2),a0
            move.w  F_TYPE(a2),d6
            cmp.w   #3,d6                   ; goal: only with a goal; no label of its own -> the goal's name
            bne.s   .lb
            move.l  v_game(a5),d0
            beq     .nx
            move.l  d0,a1
            tst.w   G_GOAL(a1)
            beq     .nx
            tst.b   (a0)
            bne.s   .lb
            lea     G_LABEL(a1),a0
.lb         cmp.w   #4,d6                   ; tile carried: only in a tile world where the player digs
            bne.s   .tq
            bsr     hud_digging
            beq     .nx
.tq         cmp.w   #6,d6                   ; tool: only in a tile world with tools
            bne.s   .iq
            bsr     hud_tools
            beq     .nx
.iq         cmp.w   #7,d6                   ; item count (F_DIGITS high byte = the item): only
            bne.s   .dl                     ; with items; no label of its own -> the item's name
            move.l  v_items(a5),d0
            beq     .nx
            tst.b   (a0)
            bne.s   .dl
            move.w  F_DIGITS(a2),d0
            lsr.w   #8,d0
            bsr     item_rec
            beq     .nx
            lea     IT_NAME(a0),a0
.dl         bsr     draw_text               ; the label
.adv        tst.b   (a0)+                   ; column after it
            beq.s   .va
            addq.w  #1,d1
            bra.s   .adv
.va         tst.w   d6
            beq     .nx
            cmp.w   #1,d6
            bne.s   .nsc
            move.l  v_score(a5),d0          ; score: F_DIGITS digits (1..6)
            move.w  F_DIGITS(a2),d4
            bsr     ui_number
            bra     .nx
.nsc        cmp.w   #2,d6
            bne.s   .nlv
            moveq   #0,d0
            move.w  v_lives(a5),d0
            move.w  F_DIGITS(a2),d4
            bsr     ui_number
            bra     .nx
.nlv        cmp.w   #5,d6
            bne.s   .ngl
            moveq   #0,d0
            move.w  v_level(a5),d0
            move.w  F_DIGITS(a2),d4
            bsr     ui_number
            bra     .nx
.ngl        cmp.w   #3,d6
            bne.s   .ntl
            move.l  v_game(a5),d0
            beq     .nx
            move.l  d0,a1
            tst.w   G_GOAL(a1)
            beq     .nx
            tst.b   F_LABEL(a2)             ; after the goal's own name: a space
            bne.s   .gs
            addq.w  #1,d1
.gs         move.w  v_goal(a5),d0           ; nn/nn
            bsr     two_digits
            moveq   #'/',d0
            bsr     draw_char
            addq.w  #1,d1
            move.w  G_GOAL(a1),d0
            bsr     two_digits
            bra     .nx
.ntl        cmp.w   #6,d6
            bne.s   .nto
            move.l  v_tiles(a5),a0          ; the tool's name, 8 letters
            bsr     tool_rec
            lea     TL_NAME(a1),a0
            moveq   #7,d4
.tl         moveq   #0,d0
            move.b  (a0)+,d0
            bne.s   .tlc
            moveq   #' ',d0
.tlc        bsr     draw_char
            addq.w  #1,d1
            dbf     d4,.tl
            bra     .nx
.nto        cmp.w   #7,d6
            bne.s   .nt4
            tst.b   F_LABEL(a2)             ; after the item's own name: a space
            bne.s   .is
            addq.w  #1,d1
.is         move.w  F_DIGITS(a2),d4         ; how many the player carries
            move.w  d4,d0
            lsr.w   #8,d0
            cmp.w   #ITEM_MAX,d0
            bhs     .nx
            add.w   d0,d0
            lea     v_icnt(a5),a1
            moveq   #0,d5
            move.w  0(a1,d0.w),d5
            move.l  d5,d0
            bsr     ui_number
            bra     .nx
.nt4        cmp.w   #4,d6
            bne     .nx
            move.w  v_sel(a5),d0            ; the tile's name, then how many
            move.l  v_tiles(a5),a0
            move.w  T_NT(a0),d4
            lsl.w   #3,d4
            lea     T_PROPS(a0,d4.w),a0
            add.w   d0,d0
            add.w   d0,d0
            add.w   d0,a0
            moveq   #3,d4
.tn         moveq   #0,d0
            move.b  (a0)+,d0
            bne.s   .tc
            moveq   #' ',d0
.tc         bsr     draw_char
            addq.w  #1,d1
            dbf     d4,.tn
            moveq   #' ',d0
            bsr     draw_char
            addq.w  #1,d1
            move.w  v_sel(a5),d0
            add.w   d0,d0
            lea     v_inv(a5),a0
            move.w  0(a0,d0.w),d0
            bsr     two_digits
.nx         lea     F_SIZE(a2),a2
            dbf     d7,.f
.done       move.w  #-1,v_shadow(a5)
            movem.l (sp)+,d0-d7/a0-a3
            rts

; d0 = number drawn with d4 digits (1..6, leading zeros) at d1 (d1 moves on)
ui_number:  movem.l d0/d4-d5/a0,-(sp)
            and.w   #7,d4
            bne.s   .ok
            moveq   #1,d4
.ok         cmp.w   #6,d4
            bls.s   .k
            moveq   #6,d4
.k          lea     v_digits+6(a5),a0
            move.b  #0,(a0)
            move.w  d4,d5
            subq.w  #1,d5
.dg         divu    #10,d0
            swap    d0
            add.b   #'0',d0
            move.b  d0,-(a0)
            clr.w   d0
            swap    d0
            dbf     d5,.dg
            bsr     draw_text
            add.w   d4,d1
            movem.l (sp)+,d0/d4-d5/a0
            rts

; Z clear when the HUD shows the tile carried (tile world where the player digs)
hud_digging:
            tst.w   v_tmode(a5)
            beq.s   .r
            move.l  a0,-(sp)
            move.l  v_tiles(a5),a0
            btst    #0,T_FLAGS+1(a0)
            move.l  (sp)+,a0
.r          rts

; d0 = actor -> Z clear (d0 = 1) when it is shown and on the screen (a tile world: inside
; the camera's view; one screen: whenever it is shown)
on_screen:  movem.l d1-d2/a0,-(sp)
            cmp.w   H_NACT(a4),d0
            bhs     .no
            move.w  d0,d1
            lsl.w   #ACTV_SHIFT,d0
            tst.w   v_vis(a5,d0.w)
            beq     .no
            add.w   d1,d1
            add.w   d1,d1
            lea     v_arec(a5),a0
            move.l  0(a0,d1.w),a0
            move.w  A_FROM(a0),d1
            cmp.w   v_level(a5),d1
            bgt     .no
            tst.w   v_tmode(a5)
            bne.s   .tw
            move.w  v_ax(a5,d0.w),d1        ; one screen: inside it (flyers wait outside)
            add.w   A_BX1(a0),d1
            bmi     .no
            move.w  v_ax(a5,d0.w),d1
            add.w   A_BX0(a0),d1
            cmp.w   v_pw(a5),d1
            bge.s   .no
            moveq   #0,d2                   ; below the HUD strip when it scrolls
            tst.w   v_split(a5)
            beq.s   .tp
            move.w  v_hudlines(a5),d2
.tp         move.w  v_ay(a5,d0.w),d1
            add.w   A_BY1(a0),d1
            cmp.w   d2,d1
            blt.s   .no
            move.w  v_ay(a5,d0.w),d1
            add.w   A_BY0(a0),d1
            cmp.w   #256,d1
            bge.s   .no
            bra.s   .yes
.tw         move.w  v_ax(a5,d0.w),d1        ; its right edge left of the view?
            add.w   A_BX1(a0),d1
            cmp.w   v_camx(a5),d1
            blt.s   .no
            move.w  v_camx(a5),d2           ; its left edge right of it?
            add.w   #320,d2
            move.w  v_ax(a5,d0.w),d1
            add.w   A_BX0(a0),d1
            cmp.w   d2,d1
            bge.s   .no
            move.w  v_ay(a5,d0.w),d1        ; above it?
            add.w   A_BY1(a0),d1
            cmp.w   v_camy(a5),d1
            blt.s   .no
            move.w  v_camy(a5),d2           ; below it?
            add.w   #256,d2
            sub.w   v_hudlines(a5),d2
            move.w  v_ay(a5,d0.w),d1
            add.w   A_BY0(a0),d1
            cmp.w   d2,d1
            bge.s   .no
.yes        moveq   #1,d0
            bra.s   .out
.no         moveq   #0,d0
.out        movem.l (sp)+,d1-d2/a0
            tst.w   d0
            rts

; -> d0 = what the tool in use does (TL_ACT), -1 = no tools
tool_kind:  moveq   #-1,d0
            tst.w   v_tmode(a5)
            beq.s   .r
            movem.l d4/a0-a1,-(sp)
            move.l  v_tiles(a5),a0
            tst.w   T_NTOOL(a0)
            beq.s   .x
            bsr     tool_rec
            moveq   #0,d0
            move.b  TL_ACT+1(a1),d0
.x          movem.l (sp)+,d4/a0-a1
.r          rts

; the player's weapon (a tool that does 3): fire swings it (fire + left / right: that
; way), or with Auto it swings by itself when something a WHEN 10 rule strikes is in
; reach, turning to face it. A swing marks what it reaches in v_struck. d5 / d7 / a2 = actor
weapon_tick:
            cmp.w   H_PLAYER(a4),d7
            bne     .r
            tst.w   v_swcool(a5)
            beq.s   .c0
            subq.w  #1,v_swcool(a5)
.c0         tst.w   v_swing(a5)
            beq.s   .s0
            subq.w  #1,v_swing(a5)
.s0         tst.w   v_tmode(a5)
            beq     .r
            tst.w   v_carry(a5)             ; hands full: no swinging
            bpl     .r
            movem.l d0-d4/a0-a1,-(sp)
            move.l  v_tiles(a5),a0
            btst    #0,T_FLAGS+1(a0)
            beq     .out
            tst.w   T_NTOOL(a0)
            beq     .out
            bsr     tool_rec
            cmp.b   #3,TL_ACT+1(a1)
            bne     .out
            tst.w   v_swcool(a5)
            bne     .out
            move.w  v_joy(a5),d0
            btst    #4,d0
            beq.s   .auto
            move.w  v_joyprev(a5),d1
            btst    #4,d1
            bne.s   .auto                   ; still held from the last swing
            btst    #2,d0
            beq.s   .f1
            move.w  #1,v_face(a5,d5.w)
.f1         btst    #3,d0
            beq.s   .go
            move.w  #0,v_face(a5,d5.w)
            bra.s   .go
.auto       btst    #0,TL_ACT(a1)
            beq     .out
            bsr     strike_mask
            tst.l   d2
            beq     .out
            move.w  v_face(a5,d5.w),d1      ; in front first, then behind
            bsr     strike_test
            bne.s   .go
            eor.w   #1,d1
            bsr     strike_test
            beq     .out
            move.w  d1,v_face(a5,d5.w)
.go         move.w  #SWING_TIME,v_swing(a5)
            move.w  #SWING_COOL,v_swcool(a5)
            move.w  v_face(a5,d5.w),d1
            moveq   #-1,d2
            bsr     strike_test
            or.l    d0,v_struck(a5)
.out        movem.l (sp)+,d0-d4/a0-a1
.r          rts

; -> d2 = bit per actor some WHEN 10 rule strikes (Auto only swings at those)
strike_mask:
            movem.l d0-d1/a0,-(sp)
            moveq   #0,d2
            move.w  H_NRULE(a4),d1
            beq.s   .r
            move.l  H_RULES(a4),d0
            lea     0(a4,d0.l),a0
            subq.w  #1,d1
.l          cmp.w   #10,R_WHEN(a0)
            bne.s   .n
            move.w  R_B(a0),d0              ; every copy of it
            bsr     type_mask
            or.l    d0,d2
.n          move.w  R_NAND(a0),d0
            lsl.w   #3,d0
            lea     RULE_SIZE(a0,d0.w),a0
            dbf     d1,.l
.r          movem.l (sp)+,d0-d1/a0
            rts

; what the player's weapon reaches: d1 = 0 right / 1 left, d2 = actors to try (bit each),
; d5 / a2 = the player, a1 = the weapon -> d0 = bits of the actors it reaches (Z set: none)
strike_test:
            movem.l d1-d7/a0,-(sp)
            moveq   #0,d0
            move.w  v_ax(a5,d5.w),d3
            add.w   A_BX0(a2),d3            ; the player's left
            move.w  v_ax(a5,d5.w),d4
            add.w   A_BX1(a2),d4            ; and right
            move.w  d3,d6
            add.w   d4,d6
            asr.w   #1,d6                   ; its middle
            tst.w   d1
            bne.s   .lf
            move.w  d6,d3                   ; right: the middle .. the right + reach
            add.w   TL_TILE(a1),d4
            bra.s   .yy
.lf         sub.w   TL_TILE(a1),d3          ; left: the left - reach .. the middle
            move.w  d6,d4
.yy         move.w  d3,v_sbox(a5)
            move.w  d4,v_sbox+2(a5)
            move.w  v_ay(a5,d5.w),d3        ; from the reach above its head (the swing's arc)
            add.w   A_BY0(a2),d3
            sub.w   TL_TILE(a1),d3
            move.w  d3,v_sbox+4(a5)
            move.w  v_ay(a5,d5.w),d3
            add.w   A_BY1(a2),d3
            move.w  d3,v_sbox+6(a5)
            move.w  d5,d7                   ; the player
            move.l  H_ACTORS(a4),d3
            lea     0(a4,d3.l),a0
            moveq   #0,d6
.j          cmp.w   H_NACT(a4),d6
            bge.s   .done
            cmp.w   #32,d6
            bge.s   .done
            btst    d6,d2
            beq.s   .nx
            move.w  d6,d5
            lsl.w   #ACTV_SHIFT,d5
            cmp.w   d7,d5
            beq.s   .nx
            tst.w   v_vis(a5,d5.w)
            beq.s   .nx
            move.w  A_FROM(a0),d3
            cmp.w   v_level(a5),d3
            bgt.s   .nx
            move.w  v_ax(a5,d5.w),d3
            add.w   A_BX0(a0),d3
            cmp.w   v_sbox+2(a5),d3
            bgt.s   .nx
            move.w  v_ax(a5,d5.w),d3
            add.w   A_BX1(a0),d3
            cmp.w   v_sbox(a5),d3
            blt.s   .nx
            move.w  v_ay(a5,d5.w),d3
            add.w   A_BY0(a0),d3
            cmp.w   v_sbox+6(a5),d3
            bgt.s   .nx
            move.w  v_ay(a5,d5.w),d3
            add.w   A_BY1(a0),d3
            cmp.w   v_sbox+4(a5),d3
            blt.s   .nx
            bset    d6,d0
.nx         lea     ACT_SIZE(a0),a0
            addq.w  #1,d6
            bra.s   .j
.done       movem.l (sp)+,d1-d7/a0
            tst.l   d0
            rts

; Z clear in a tile world with tools (the space bar menu)
hud_tools:  tst.w   v_tmode(a5)
            beq.s   .r
            move.l  a0,-(sp)
            move.l  v_tiles(a5),a0
            tst.w   T_NTOOL(a0)
            move.l  (sp)+,a0
.r          rts

str_score:  dc.b    "SCORE ",0
str_lives:  dc.b    "LIVES ",0
str_fire:   dc.b    "PRESS FIRE",0
str_disk2:  dc.b    "PLEASE INSERT DISK 2",0
str_loading: dc.b   "LOADING",0
str_d2err:  dc.b    "DISK 2 ERROR - PRESS FIRE",0
str_use:    dc.b    "USE ",0
str_make:   dc.b    "MAKE ",0
            even

font:
            include "font.inc"

; ============================================================================
;  ptplayer 6.4 by Frank Wille (public domain - ptplayer/LICENSE).
;  Unmodified except that its closing "end" directive is commented out.
;  Single section, PC-relative with its own base register, so it is
;  position independent like the rest of the engine. Every entry point
;  used here (_mt_install, _mt_init, _mt_end, _mt_playfx) saves a4/a5.
; ============================================================================
            even
            include "ptplayer/ptplayer.asm"

; ============================================================================
;  chip data
; ============================================================================
            cnop    0,8
null_spr:   dc.l    0,0

copper:
cop_bpl:    dc.w    $00e0,0,$00e2,0
            dc.w    $00e4,0,$00e6,0
            dc.w    $00e8,0,$00ea,0
            dc.w    $00ec,0,$00ee,0
            dc.w    $00f0,0,$00f2,0
            dc.w    $00f4,0,$00f6,0
            dc.w    $00f8,0,$00fa,0
            dc.w    $00fc,0,$00fe,0
cop_spr:    dc.w    $0120,0,$0122,0
            dc.w    $0124,0,$0126,0
            dc.w    $0128,0,$012a,0
            dc.w    $012c,0,$012e,0
            dc.w    $0130,0,$0132,0
            dc.w    $0134,0,$0136,0
            dc.w    $0138,0,$013a,0
            dc.w    $013c,0,$013e,0
cop_ddf:    dc.w    $01fe,0,$01fe,0         ; a narrow map: the HUD's DDFSTRT / DDFSTOP (else no-ops)
cop_mods:   dc.w    $0108,0,$010a,0,$0102,0 ; modulos and fine scroll from the top (tile world: HUD strip)
cop_grad:   dc.w    $ffff,$fffe             ; sky lines are built here at run time
            ds.b    256*20+32+128           ; AGA: wait + 4 moves per line; + the tile world split

            cnop    0,4
V:          ds.b    V_SIZE+128
            cnop    0,4
stack:      ds.b    2048
stack_top:
            cnop    0,8
data_start:
