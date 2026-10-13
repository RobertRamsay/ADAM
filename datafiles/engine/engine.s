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
H_SFX       equ 48         ; offset: 8 sound entries
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
HDR_SIZE    equ 100

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
TP_SOUND    equ 1          ; byte: sound 0..7, $ff = none
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
                           ; 3 left, 4 right, 5 at the player
A_BX0       equ 14
A_BY0       equ 16
A_BX1       equ 18
A_BY1       equ 20
A_SPR       equ 22         ; long offset of this actor's hardware sprite block
A_CHAN      equ 26         ; hardware sprite channel 0..7 (colour pair = channel / 2)
A_SPR2      equ 28         ; long offset of a hopper's crouch frame, 0 = none
A_CARRY     equ 32         ; 1 = the player can pick it up (fire) and throw it (fire again)
A_AMODE     equ 34         ; animation flags: bit 0 = 8 directions (table has 12 entries),
                           ; bit 1 = Fire animations for the player (table has 21 entries)
A_FROM      equ 36         ; first level this actor appears on (1..10)
A_FAST      equ 38         ; +1 speed every N levels, 0 = never
A_BOB       equ 40         ; 1 = BOB: A_SPR / A_SPR2 / frames are BOB images, A_CHAN is unused
A_XMAX      equ 42         ; furthest right it goes: 320 - width
A_YMAX      equ 44         ; furthest down it goes: 256 - height
A_BSIZE     equ 46         ; BOB: BLTSIZE (height << 6) | (width in words + 1), 0 for a sprite
A_ANIM      equ 48         ; long offset of the animation table, 0 = one frame (A_SPR)
ACT_SIZE    equ 52

; animation table (data block version 5): 4 entries - 0 Idle (standing still),
; 1 Walk (moving), 2 Jump (in the air going up), 3 Fall (in the air coming
; down; Jump and Fall only for platform players, hoppers and fallers). ADAM
; fills empty animations in from the others, so every entry has 1..8 frames.
; With 8 directions (A_AMODE bit 0) 8 more follow: 4 N, 5 NE, 6 E, 7 SE, 8 S,
; 9 SW, 10 W, 11 NW, used instead of Walk; ADAM bakes any turning round into
; their frames. An entry with mode 3 ('stand facing') shows frame 1 of the
; direction the actor last moved in.
; With Fire animations (A_AMODE bit 1) 9 more follow: 12 Fire (no direction),
; 13..20 Fire + N .. NW. While the player holds fire they are picked from the
; joystick direction instead of the movement (digging, shooting, swinging).
AN_N        equ 0          ; number of frames 1..8
AN_RATE     equ 2          ; 50ths of a second per frame (2..30)
AN_MODE     equ 4          ; 0 = loop, 1 = once (stays on the last), 2 = ping-pong, 3 = stand facing (8 directions)
AN_RIGHT    equ 8          ; 8 longs: frame offsets facing right
AN_LEFT     equ 40         ; 8 longs: facing left (the same frames when not flipped)
ANIM_SIZE   equ 72

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

; ---------------- engine variables (offsets from V) ----------------
; Per-actor state is one ACTV_SIZE record per actor, starting at V. a5 =
; V+128, so a field is v_xx(a5,Dn) with Dn = actor * ACTV_SIZE (actor << ACTV_SHIFT):
; the field offsets (-128..-65) fit the signed 8-bit displacement and the
; index register carries the actor. Scalars follow the MAX_ACT records.
MAX_ACT     equ 32
ACTV_SIZE   equ 64
ACTV_SHIFT  equ 6
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
            rsset   -128+MAX_ACT*ACTV_SIZE
v_anim      rs.w 1
v_joyprev   rs.w 1
v_jumped    rs.l 1         ; bit per actor that jumped this frame
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
            bsr     init_display

game_restart:
            lea     -128(a5),a7             ; a5 = V+128 (stack_top is too far for a PC-relative lea)
            add.l   #stack_top-V,a7
            bsr     music_stop              ; silence: music and effects
            move.w  #1,v_level(a5)
            bsr     init_palette
            bsr     clear_state
            move.l  #0,v_score(a5)
            move.w  H_LIVES(a4),v_lives(a5)
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
level_card: lea     -128(a5),a7             ; a5 = V+128 (stack_top is too far for a PC-relative lea)
            add.l   #stack_top-V,a7
            bsr     tiles_off
            bsr     hide_sprites
            bsr     restore_backdrop
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
            bsr     init_actors
            bsr     clear_latches
            move.w  #0,v_goal(a5)
            bsr     tiles_start
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

            lea     cop_spr(pc),a0          ; sprite pointers: all null first
            lea     null_spr(pc),a1
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
            lea     cop_spr(pc),a0
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
.cop        lea     copper(pc),a0
            move.l  a0,$80(a6)              ; COP1LC
            move.w  d0,$88(a6)              ; COPJMP1 strobe
            move.w  #$83e0,$96(a6)          ; DMAEN BPLEN COPEN BLTEN SPREN
            move.w  #$8040,$9c(a6)          ; INTREQ: BLIT set = "no blit running" (see bwait)
            rts

; d0 = bitplane memory -> copper bitplane pointers
set_bpl:    movem.l d0/d7/a0,-(sp)
            lea     cop_bpl(pc),a0
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
            move.l  H_PLANES(a4),d0         ; original backdrop -> work copy
            lea     0(a4,d0.l),a0
            move.l  v_work(a5),a1
            move.w  H_DEPTH(a4),d7
            mulu    #PLANE_SIZE/4,d7
            subq.l  #1,d7
.cp         move.l  (a0)+,(a1)+
            dbf     d7,.cp
            bsr     draw_terrain            ; this level's hills into the work copy
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
.notshot
            lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .a
.done       rts

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
            move.w  #$8080,$96(a6)          ; copper on again
.done       movem.l (sp)+,d0-d4
            rts

; ============================================================================
;  one frame of game
; ============================================================================
frame:
            bsr     bob_flip                ; BOBs: show last frame's drawing (copper idle here too)
            bsr     flash_tick              ; copper edits first, while the copper is idle
            addq.w  #1,v_anim(a5)
            move.l  #0,v_jumped(a5)
            move.l  #0,v_struck(a5)
            move.w  #0,v_hitn(a5)
            bsr     read_joy
            bsr     read_key
            bsr     tool_menu               ; space bar: the tool menu - the game waits while it is open
            bne     .wait
            move.w  #0,v_sectick(a5)
            addq.w  #1,v_fcount(a5)
            cmp.w   #50,v_fcount(a5)
            blt.s   .f1
            move.w  #0,v_fcount(a5)
            move.w  #1,v_sectick(a5)
.f1         bsr     carry_tick              ; fire picks up / throws
            bsr     move_actors
            bsr     carry_follow            ; what the player carries rides on its head
            move.w  v_joy(a5),v_joyprev(a5)
            bsr     cam_follow              ; tile world: camera, new tiles, scroll
            bsr     cam_window
            bsr     cop_scroll
            bsr     place_sprites
            bsr     bob_draw
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

; the tool menu (a tile world with tools): space opens it in the HUD row, left / right
; choose, fire or space take the tool. Z clear while it is open (the game waits)
tool_menu:  tst.w   v_tmode(a5)
            beq     .no
            movem.l d1-d3/a0,-(sp)
            move.l  v_tiles(a5),a0
            move.w  T_NTOOL(a0),d1
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
            move.w  #1,v_menu(a5)
            move.w  v_tool(a5),v_msel(a5)
            bsr     menu_draw
            bra     .yes
.open       move.w  v_joy(a5),d2            ; newly pressed
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
.take       move.w  v_msel(a5),v_tool(a5)
            move.w  #0,v_menu(a5)
            bsr     menu_clear
            bsr     draw_hud
            move.l  #-1,v_digc(a5)
.yes        move.w  v_joy(a5),v_joyprev(a5)
            movem.l (sp)+,d1-d3/a0
            moveq   #1,d0
            rts
.none       movem.l (sp)+,d1-d3/a0
.no         moveq   #0,d0
            rts

; the HUD row as the tool menu: each tool's name, the one picked in the message colour
menu_draw:  movem.l d0-d7/a0-a1,-(sp)
            bsr     menu_clear
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
            move.w  v_ax(a5,d5.w),v_ox(a5,d5.w)
            move.w  v_ay(a5,d5.w),v_oy(a5,d5.w)
            tst.w   v_safe(a5,d5.w)         ; immunity counts down
            beq.s   .nosafe
            subq.w  #1,v_safe(a5,d5.w)
.nosafe     tst.w   v_life(a5,d5.w)         ; shown-for-a-moment actors hide again
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

.shot       move.w  v_ax(a5,d5.w),d0        ; a shot flies straight
            add.w   v_tvx(a5,d5.w),d0
            move.w  v_ay(a5,d5.w),d1
            add.w   v_tvy(a5,d5.w),d1
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
.adv        lea     ACT_SIZE(a2),a2
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
            tst.w   v_swing(a5)             ; the player swinging: it keeps facing the way it struck
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
.anim       move.l  A_ANIM(a2),d1
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
.tick
            moveq   #0,d3
            move.w  v_anim(a5),d3
            sub.w   v_astart(a5,d5.w),d3    ; 50ths since it started
            move.w  AN_RATE(a0),d4
            bne.s   .rt
            moveq   #8,d4
.rt         divu    d4,d3                   ; d3 = steps
            and.l   #$ffff,d3
            move.w  AN_N(a0),d4             ; frames 1..8
            move.w  AN_MODE(a0),d2
            beq.s   .mloop
            cmp.w   #1,d2
            beq.s   .monce
            cmp.w   #1,d4                   ; ping-pong: 0 1 2 .. n-1 n-2 .. 1
            ble.s   .mf0
            move.w  d4,d2
            add.w   d2,d2
            subq.w  #2,d2                   ; period 2n - 2
            divu    d2,d3
            swap    d3
            cmp.w   d4,d3
            blt.s   .mfi
            neg.w   d3
            add.w   d2,d3
            bra.s   .mfi
.monce      cmp.w   d4,d3                   ; once: stays on the last frame
            blt.s   .mfi
            move.w  d4,d3
            subq.w  #1,d3
            bra.s   .mfi
.mloop      divu    d4,d3
            swap    d3
            bra.s   .mfi
.mf0        moveq   #0,d3
.mfi        and.w   #7,d3
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
            lea     cop_spr(pc),a1
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
            tst.w   v_safe(a5,d5.w)         ; flashing while immune
            beq.s   .show
            btst    #2,v_anim+1(a5)
            beq.s   .show
.hid        move.l  #0,(a0)
            bra     .next
.show       move.w  v_ay(a5,d5.w),d0
            move.w  v_ax(a5,d5.w),d1
            tst.w   v_tmode(a5)             ; tile world: where it is on the screen
            beq.s   .scr
            sub.w   v_camy(a5),d0
            sub.w   v_camx(a5),d1
            cmp.w   #-24,d0
            ble     .hid
            cmp.w   #256,d0
            bge     .hid
            cmp.w   #-16,d1
            ble     .hid
            cmp.w   #320,d1
            bge     .hid
.scr        add.w   #$2c,d0                 ; VSTART
            add.w   #128,d1                 ; HSTART
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
            move.w  #0,v_hudrow(a5)
            move.w  #$0030,$92(a6)          ; DDFSTRT one word early: room for the fine scroll
            move.w  #$00d0,$94(a6)          ; DDFSTOP: 21 words a line
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            move.w  #$0000,$1fc(a6)         ; AGA: FMODE 16-bit fetch while scrolling
.ocs        lea     cop_mods(pc),a0
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
            move.w  v_hudrow0(a5),v_hudrow(a5)
            move.w  #$0038,$92(a6)
            move.w  #$00d0,$94(a6)
            btst    #0,H_FLAGS+1(a4)
            beq.s   .ocs
            move.w  #$0003,$1fc(a6)
            move.w  #$00b8,$94(a6)
.ocs        lea     cop_mods(pc),a0
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
            beq     .r
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
            beq.s   .done
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
            moveq   #3,d2                   ; 4 animations (12 with 8 directions, 21 with Fire)
            btst    #1,A_AMODE+1(a2)
            beq.s   .hd
            moveq   #20,d2
            bra.s   .ha
.hd         btst    #0,A_AMODE+1(a2)
            beq.s   .ha
            moveq   #11,d2
.ha         lea     AN_RIGHT(a1),a3
            moveq   #15,d1                  ; 8 right + 8 left
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
            tst.l   v_disp2(a5)
            beq.s   .r
            tst.w   v_drawn(a5)
            beq.s   .r
            move.w  #0,v_drawn(a5)
            move.l  v_draw(a5),d0
            bsr     set_bpl
            moveq   #0,d1                   ; draw into the other one next
            move.l  v_disp(a5),d0
            cmp.l   v_draw(a5),d0
            bne.s   .a
            moveq   #1,d1
            move.l  v_disp2(a5),d0
.a          move.l  d0,v_draw(a5)
            move.w  d1,v_bobbuf(a5)
.r          rts

bob_draw:
            tst.l   v_disp2(a5)
            beq     .r
            movem.l d0-d7/a0-a3,-(sp)
            lea     v_bobold(a5),a3         ; a3 = this display's list of old places
            lea     v_bobn(a5),a1           ; a1 = its count
            tst.w   v_bobbuf(a5)
            beq.s   .b0
            lea     MAX_ACT*4(a3),a3
            addq.l  #2,a1
.b0
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
            moveq   #40,d1
            sub.w   d0,d1                   ; modulo: 40 - blit width in bytes
            move.l  v_back(a5),d2
            add.l   d4,d2
            move.l  v_draw(a5),d3
            add.l   d4,d3
            move.w  H_DEPTH(a4),d7
            subq.w  #1,d7
            bsr     bwait
            move.w  d1,$64(a6)              ; AMOD
            move.w  d1,$66(a6)              ; DMOD
.wpl        bsr     bwait
            move.l  d2,$50(a6)              ; BLTAPT
            move.l  d3,$54(a6)              ; BLTDPT
            move.w  d5,d0
            bsr     bgo
            add.l   #PLANE_SIZE,d2
            add.l   #PLANE_SIZE,d3
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
.vis        move.l  v_fofs(a5,d5.w),d0
            lea     0(a4,d0.l),a0           ; a0 = mask, the planes follow
            moveq   #0,d0
            move.w  v_ay(a5,d5.w),d0
            mulu    #40,d0
            move.w  v_ax(a5,d5.w),d1
            lsr.w   #4,d1
            add.w   d1,d1
            add.w   d1,d0                   ; byte offset in a plane
            move.w  (a1),d1                 ; remember it for next time's wipe
            lsl.w   #2,d1
            move.w  d0,0(a3,d1.w)
            move.w  A_BSIZE(a2),2(a3,d1.w)
            addq.w  #1,(a1)
            move.l  v_draw(a5),d3
            add.l   d0,d3                   ; d3 = screen, plane 0
            move.w  v_ax(a5,d5.w),d0
            and.w   #15,d0
            ror.w   #4,d0                   ; shift into bits 15-12
            bsr     bwait
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
            moveq   #40,d1
            sub.w   d0,d1
            move.w  d1,$60(a6)              ; CMOD
            move.w  d1,$66(a6)              ; DMOD
            subq.w  #2,d0                   ; image width in bytes
            move.w  d4,d1
            lsr.w   #6,d1                   ; lines
            mulu    d1,d0                   ; d0 = bytes per mask / plane
            move.l  a0,d2
            add.l   d0,d2                   ; d2 = image, plane 0
            move.w  H_DEPTH(a4),d1
            subq.w  #1,d1
.pl         bsr     bwait
            move.l  a0,$50(a6)              ; A = mask
            move.l  d2,$4c(a6)              ; B = image plane
            move.l  d3,$48(a6)              ; C = screen
            move.l  d3,$54(a6)              ; D = screen
            move.w  d0,-(sp)
            move.w  d4,d0
            bsr     bgo
            move.w  (sp)+,d0
            add.l   d0,d2
            add.l   #PLANE_SIZE,d3
            dbf     d1,.pl
.nxt        lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .act
.done       bsr     bwait
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
            move.l  H_ACTORS(a4),d2
            lea     0(a4,d2.l),a0
            move.l  a0,a1
            move.w  d0,d4
            mulu    #ACT_SIZE,d4
            add.w   d4,a0                   ; record a
            move.w  d1,d4
            mulu    #ACT_SIZE,d4
            add.w   d4,a1                   ; record b
            move.w  d0,d4
            lsl.w   #ACTV_SHIFT,d4
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
            move.w  R_WHEN(a3),d0
            beq     .touch
            cmp.w   #1,d0
            beq     .fire
            cmp.w   #2,d0
            beq     .timer
            cmp.w   #3,d0
            beq     .score
            cmp.w   #4,d0
            beq     .lives
            cmp.w   #6,d0
            beq     .jump
            cmp.w   #8,d0
            beq     .hold
            cmp.w   #9,d0
            beq     .inview
            cmp.w   #10,d0
            beq     .strike
            cmp.w   #11,d0
            beq     .thrown
            cmp.w   #12,d0
            beq     .pickup
            bra     .next

.pickup     move.w  v_picked(a5),d0         ; the player picked actor a up this frame
            bmi     .next
            cmp.w   R_A(a3),d0
            bne     .next
            bsr     fire_action
            bra     .next

.thrown     move.w  v_hitn(a5),d1           ; thrown actor a hit actor b (b = a: anything) this frame
            beq     .next
            subq.w  #1,d1
            lea     v_hits(a5),a0
.th         moveq   #0,d0
            move.b  (a0)+,d0
            moveq   #0,d2
            move.b  (a0)+,d2
            cmp.w   R_A(a3),d0
            bne.s   .thn
            move.w  R_B(a3),d0
            cmp.w   R_A(a3),d0
            beq.s   .thy
            cmp.w   d0,d2
            beq.s   .thy
.thn        dbf     d1,.th
            bra     .next
.thy        bsr     fire_action
            bra     .next

.strike     move.l  v_struck(a5),d0         ; the player's weapon struck actor b this frame
            move.w  R_B(a3),d1
            btst    d1,d0
            beq     .next
            bsr     fire_action
            bra     .next

.inview     tst.w   v_sectick(a5)           ; every N seconds while actor a is on the screen
            beq     .next
            move.w  R_A(a3),d0
            bsr     on_screen
            bne.s   .iv
            move.w  R_N(a3),(a2)            ; out of view: ring a second after it comes back
            subq.w  #1,(a2)
            bra     .next
.iv         addq.w  #1,(a2)
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

.jump       move.l  v_jumped(a5),d0         ; actor a jumped this frame
            move.w  R_A(a3),d1
            btst    d1,d0
            beq     .next
            bsr     fire_action
            bra     .next

.touch      move.w  R_A(a3),d0
            move.w  R_B(a3),d1
            cmp.w   d0,d1
            bne.s   .two
            bsr     touch_any
            bra.s   .tt
.two        bsr     touch_pair
.tt         beq.s   .clear
.edge       tst.w   (a2)
            bne     .next
            move.w  #1,(a2)
            bsr     fire_action
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
            move.w  #1,(a2)
            bsr     fire_action
            bra     .next

.lives      tst.w   v_lives(a5)
            bne     .next
            tst.w   (a2)
            bne     .next
            move.w  #1,(a2)
            bsr     fire_action

.next       bsr     rule_next
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .r
.done       rts

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
; so a3 points AND_SIZE before each line: its act / target / value sit at 8 / 10 / 12)
fire_action:
            movem.l d5-d7/a2-a3,-(sp)
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
            rts

; a3 = rule
do_action:
            move.w  R_TGT(a3),d5            ; target actor -> d5 = offset
            move.w  d5,d4
            lsl.w   #ACTV_SHIFT,d5
            move.w  R_ACT(a3),d0
            cmp.w   #22,d0
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

act_none:   rts

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
; Z clear when it hit something
shot_hits:
            movem.l d1-d6/a0,-(sp)
            moveq   #0,d6
.j          cmp.w   H_NACT(a4),d6
            bge.s   .none
            cmp.w   #MAX_ACT,d6
            bge.s   .none
            cmp.w   d7,d6
            beq.s   .n
            cmp.w   v_owner(a5,d5.w),d6
            beq.s   .n
            move.w  d6,d4
            bsr     actor_rec
            cmp.w   #ROLE_SHOT,A_ROLE(a0)   ; shots pass each other by
            beq.s   .n
            move.w  A_FROM(a0),d0
            cmp.w   v_level(a5),d0
            bgt.s   .n
            move.w  d7,d0
            move.w  d6,d1
            bsr     touch_pair              ; both shown, neither safe, boxes overlap
            beq.s   .n
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
            bra.s   .j
.none       moveq   #0,d0
.out        movem.l (sp)+,d1-d6/a0
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
act_shoot:
            movem.l d0-d7/a0-a2,-(sp)
            move.w  d4,d3                   ; d3 = the shot the rule names
            cmp.w   H_NACT(a4),d3
            bhs     .out
            move.w  R_VAL(a3),d6            ; d6 = the shooter
            cmp.w   H_NACT(a4),d6
            bhs     .out
            move.w  d6,d7
            lsl.w   #ACTV_SHIFT,d7          ; d7 = its offset
            tst.w   v_vis(a5,d7.w)
            beq     .out
            move.w  d6,d4
            bsr     actor_rec
            move.l  a0,a1                   ; a1 = the shooter's record
            move.w  A_FROM(a1),d0
            cmp.w   v_level(a5),d0
            bgt     .out
            move.w  d3,d4                   ; a free shot: the one named, or a shot after it
.find       cmp.w   H_NACT(a4),d4
            bhs     .out
            cmp.w   #MAX_ACT,d4
            bhs     .out
            cmp.w   d6,d4
            beq     .out
            bsr     actor_rec               ; a0 = its record
            cmp.w   d3,d4
            beq.s   .head
            cmp.w   #ROLE_SHOT,A_ROLE(a0)
            bne     .out
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
            tst.w   v_tmode(a5)
            bne.s   .pos
            tst.w   d0
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

            move.w  A_UP(a0),d2             ; the aim -> d0 / d1 = -1, 0 or 1 across / down
            moveq   #0,d0
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
            move.l  a0,a2                   ; a2 = the shot's record
            bsr     actor_rec               ; a0 = the player's
            lsl.w   #ACTV_SHIFT,d4
            move.w  A_BX0(a0),d0            ; player's middle - the shot's middle
            add.w   A_BX1(a0),d0
            sub.w   A_BX0(a2),d0
            sub.w   A_BX1(a2),d0
            asr.w   #1,d0
            add.w   v_ax(a5,d4.w),d0
            sub.w   v_ax(a5,d5.w),d0
            move.w  A_BY0(a0),d1
            add.w   A_BY1(a0),d1
            sub.w   A_BY0(a2),d1
            sub.w   A_BY1(a2),d1
            asr.w   #1,d1
            add.w   v_ay(a5,d4.w),d1
            sub.w   v_ay(a5,d5.w),d1
            move.l  a2,a0
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

.go         move.w  v_spd(a5,d5.w),d2       ; speed; a bit less on the diagonals
            tst.w   d0
            beq.s   .sp
            tst.w   d1
            beq.s   .sp
            move.w  d2,d4
            lsr.w   #2,d4
            sub.w   d4,d2
.sp         muls    d2,d0
            muls    d2,d1
            move.w  d0,v_tvx(a5,d5.w)
            move.w  d1,v_tvy(a5,d5.w)
            move.w  #SHOT_FLY,v_thr(a5,d5.w)
            move.w  #1,v_vis(a5,d5.w)
            move.w  #0,v_life(a5,d5.w)
            move.w  #0,v_vy(a5,d5.w)
            move.w  #0,v_gnd(a5,d5.w)
            move.w  d6,v_owner(a5,d5.w)
            move.w  d3,v_pool(a5,d5.w)
.out        movem.l (sp)+,d0-d7/a0-a2
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
            move.w  R_VAL(a3),d0
            cmp.w   H_NACT(a4),d0
            bhs     act_none
            lsl.w   #ACTV_SHIFT,d0
            move.w  v_ax(a5,d0.w),v_ax(a5,d5.w)
            move.w  v_ay(a5,d0.w),d1
            addq.w  #8,d1
            move.w  d1,v_ay(a5,d5.w)
            bra     stop_fall

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
.z          bra     draw_hud

act_addlife:
            cmp.w   #9,v_lives(a5)
            bhs.s   .z
            addq.w  #1,v_lives(a5)
.z          bra     draw_hud

act_sound:  move.w  R_VAL(a3),d0
            and.w   #7,d0
            bra     play_sfx

act_flash:  move.w  #16,v_flash(a5)
            rts

act_home:   cmp.w   H_NACT(a4),d4
            bhs     act_none
            bsr     stop_fall
            bsr     actor_rec
            move.w  A_X(a0),v_ax(a5,d5.w)
            move.w  A_Y(a0),v_ay(a5,d5.w)
            rts

act_random: cmp.w   H_NACT(a4),d4
            bhs     act_none
            bsr     stop_fall
            bsr     actor_rec
            move.w  A_XMAX(a0),d2
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
            rts

act_hide:   cmp.w   H_NACT(a4),d4
            bhs     act_none
            move.w  #0,v_vis(a5,d5.w)
            rts

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
.plain      moveq   #0,d0
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
            bsr     tiles_off
            bsr     music_stop              ; music and effects off
            move.l  a0,-(sp)
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

; d4 = actor index -> a0 = actor record
actor_rec:  move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a0
            move.w  d4,d0
            mulu    #ACT_SIZE,d0
            add.w   d0,a0
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
;  copper sky: COLOR00 changes on every display line
;  d1.w = -1 : use the gradient table      d1.w = $0RGB : one fixed colour
; ============================================================================
;  On AGA the table has a second half: 256 words of low nibbles. Each line
;  then writes COLOR00 twice - high nibbles (LOCT clear, which also copies
;  them to the low nibbles), then the low nibbles with LOCT set - so the sky
;  gets 24-bit colour. One fixed colour (d1 >= 0) only needs the first write.
build_grad:
            movem.l d0-d5/a0-a2,-(sp)
            lea     cop_grad(pc),a0
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
            tst.w   v_tmode(a5)             ; tile world: the scrolling picture starts here
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
.nosky      tst.w   v_tmode(a5)             ; no sky: just the tile world split
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
            move.w  v_tline(a5),d2          ; modulo: the picture's line less the 42 bytes fetched
            sub.w   #42,d2
            move.w  #$0108,(a0)+
            move.w  d2,(a0)+
            move.w  #$010a,(a0)+
            move.w  d2,(a0)+
            move.l  #$01020000,(a0)+
            rts
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
            move.w  d0,v_song(a5)
            lea     0(a4,d1.l),a0           ; a0 = MOD
            sub.l   a1,a1                   ; samples follow the patterns
            moveq   #0,d0                   ; from the first song position
            bsr     _mt_init
            lea     _mt_Enable(pc),a0
            st      (a0)                    ; go
.out        movem.l (sp)+,d0-d1/a0-a1
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

; d0 = sound 0..7. With no music it plays on channel (sound AND 3), as it
; always did; while a song plays ptplayer picks the channel that disturbs
; the music least. The channel goes back to the music when the sound ends.
play_sfx:
            movem.l d0-d1/a0-a1,-(sp)
            and.w   #7,d0
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
            bne.s   .dl
            bsr     hud_tools
            beq     .nx
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
            bra.s   .nx
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
.nto        cmp.w   #4,d6
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
            move.l  H_ACTORS(a4),d1
            lea     0(a4,d1.l),a0
            move.w  d0,d1
            mulu    #ACT_SIZE,d1
            add.l   d1,a0
            lsl.w   #ACTV_SHIFT,d0
            tst.w   v_vis(a5,d0.w)
            beq.s   .no
            move.w  A_FROM(a0),d1
            cmp.w   v_level(a5),d1
            bgt.s   .no
            tst.w   v_tmode(a5)
            beq.s   .yes
            move.w  v_ax(a5,d0.w),d1        ; its right edge left of the view?
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
            move.w  R_B(a0),d0
            bset    d0,d2
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
