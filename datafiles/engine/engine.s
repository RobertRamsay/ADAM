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
HDR_SIZE    equ 84

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
A_UP        equ 12
A_BX0       equ 14
A_BY0       equ 16
A_BX1       equ 18
A_BY1       equ 20
A_SPR       equ 22         ; long offset of this actor's hardware sprite block
A_CHAN      equ 26         ; hardware sprite channel 0..7 (colour pair = channel / 2)
A_SPR2      equ 28         ; long offset of the second animation frame, 0 = none
A_ARATE     equ 32         ; frames per animation frame
A_AMODE     equ 34         ; 0 = always animate, 1 = only while moving
A_FROM      equ 36         ; first level this actor appears on (1..10)
A_FAST      equ 38         ; +1 speed every N levels, 0 = never
ACT_SIZE    equ 48

; rule record
R_WHEN      equ 0
R_A         equ 2
R_B         equ 4
R_N         equ 6
R_ACT       equ 8
R_TGT       equ 10
R_VAL       equ 12
RULE_SIZE   equ 16

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
XMAX        equ 304        ; 320 - 16
YMAX        equ 232        ; 256 - 24
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

; ---------------- engine variables (offsets from V) ----------------
            rsset   -128            ; a5 = V+128 so per-actor tables fit d8(a5,Dn)
v_ax        rs.w 8
v_ay        rs.w 8
v_spd       rs.w 8
v_vis       rs.w 8
v_dx        rs.w 8
v_dy        rs.w 8
v_px        rs.w 8
v_py        rs.w 8
v_vy        rs.w 8         ; vertical speed in 1/16 pixels per frame
v_ysub      rs.w 8
v_tmr       rs.w 8
v_gnd       rs.w 8         ; 1 = standing on the ground
v_squat     rs.w 8         ; hopper squat countdown before a jump
v_life      rs.w 8         ; frames until a 'shown for a moment' actor hides
v_safe      rs.w 8         ; frames of flashing immunity left
v_anim      rs.w 1
v_joyprev   rs.w 1
v_jumped    rs.w 1         ; bit per actor that jumped this frame
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
v_latch     rs.w 128
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
            lea     stack_top(pc),a7
            lea     V+128(pc),a5
            lea     data_start(pc),a4
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
            lea     stack_top(pc),a7
            bsr     music_stop              ; silence: music and effects
            move.w  #1,v_level(a5)
            bsr     init_palette
            bsr     clear_state
            move.l  #0,v_score(a5)
            move.w  H_LIVES(a4),v_lives(a5)
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
level_card: lea     stack_top(pc),a7
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
            move.l  H_DISP(a4),d0
            add.l   a4,d0
            move.l  d0,v_disp(a5)

            lea     cop_bpl(pc),a0          ; bitplane pointers
            moveq   #7,d7
.bpl        swap    d0
            move.w  d0,2(a0)
            swap    d0
            move.w  d0,6(a0)
            add.l   #PLANE_SIZE,d0
            addq.l  #8,a0
            dbf     d7,.bpl

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
.spr        lea     cop_spr(pc),a0
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
            lea     ACT_SIZE(a2),a2
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
            move.w  #$0000,$1fc(a6)         ; FMODE   - OCS compatible fetch
            move.w  #$0c00,$106(a6)         ; BPLCON3
            move.w  #$00ff,$10c(a6)         ; BPLCON4 - sprite colours 240-255
            bra.s   .cop
.ocs        move.w  d1,$100(a6)
.cop        lea     copper(pc),a0
            move.l  a0,$80(a6)              ; COP1LC
            move.w  d0,$88(a6)              ; COPJMP1 strobe
            move.w  #$83a0,$96(a6)          ; DMAEN BPLEN COPEN SPREN
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
            move.l  v_work(a5),a0           ; work copy -> screen
            move.l  v_disp(a5),a1
            move.w  H_DEPTH(a4),d7
            mulu    #PLANE_SIZE/4,d7
            subq.l  #1,d7
.cp2        move.l  (a0)+,(a1)+
            dbf     d7,.cp2
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
            add.w   d5,d5
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
            lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .a
.done       rts

clear_latches:
            lea     v_latch(a5),a0
            move.w  #127,d7
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
            bsr     flash_tick              ; copper edits first, while the copper is idle
            addq.w  #1,v_anim(a5)
            move.w  #0,v_jumped(a5)
            bsr     read_joy
            move.w  #0,v_sectick(a5)
            addq.w  #1,v_fcount(a5)
            cmp.w   #50,v_fcount(a5)
            blt.s   .f1
            move.w  #0,v_fcount(a5)
            move.w  #1,v_sectick(a5)
.f1         bsr     move_actors
            move.w  v_joy(a5),v_joyprev(a5)
            bsr     place_sprites
            bsr     run_rules
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
            add.w   d5,d5
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
            beq.s   .horiz
            cmp.w   #1,d0
            beq.s   .horiz
            bra     .next

.player     move.w  v_spd(a5,d5.w),d1
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
            cmp.w   #YMAX,d0
            ble.s   .pd1
            move.w  #YMAX,d0
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
            cmp.w   #XMAX,d0
            ble.s   .pr1
            move.w  #XMAX,d0
.pr1        move.w  d0,v_ax(a5,d5.w)
.pr         bra     .next

.horiz      move.w  v_spd(a5,d5.w),d1
            move.w  v_ax(a5,d5.w),d0
            tst.w   v_dx(a5,d5.w)
            bne.s   .hl
            add.w   d1,d0
            cmp.w   #XMAX,d0
            ble.s   .hs
            move.w  #XMAX,d0
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
            cmp.w   #YMAX,d0
            ble.s   .vs
            move.w  #YMAX,d0
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
            add.w   d4,d4
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

.platform  move.w  v_spd(a5,d5.w),d1      ; walk left / right
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
            cmp.w   #XMAX,d0
            ble.s   .wr1
            move.w  #XMAX,d0
.wr1        move.w  d0,v_ax(a5,d5.w)
.wr         tst.w   v_gnd(a5,d5.w)          ; jump: fire or up, just pressed
            beq.s   .pphys
            move.w  v_joyprev(a5),d0
            not.w   d0
            and.w   d2,d0
            and.w   #17,d0
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
            cmp.w   #XMAX,d0
            ble.s   .hjs
            move.w  #XMAX,d0
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

.next       lea     ACT_SIZE(a2),a2
            addq.w  #1,d7
            cmp.w   d6,d7
            blt     .loop
.done       rts

; d7 = actor index -> sets its bit in v_jumped (d5 = actor offset)
jumped:     move.w  #0,v_gnd(a5,d5.w)
            move.w  v_jumped(a5),d0
            bset    d7,d0
            move.w  d0,v_jumped(a5)
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
            move.w  v_ax(a5,d5.w),d2
            addq.w  #8,d2
            cmp.w   #319,d2
            bls.s   .ok
            move.w  #319,d2
.ok         add.w   d2,d2
            move.w  0(a0,d2.w),d2
            rts
.none       move.w  #256,d2
            rts

; gravity and ground contact for actor d5 (record a2)
physics:    move.w  v_vy(a5,d5.w),d0
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
            bsr.s   ground_y
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
            cmp.w   #YMAX,d0
            ble.s   .top
            move.w  #YMAX,v_ay(a5,d5.w)
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
            add.w   d5,d5
            move.l  A_SPR(a2),d0            ; pick the animation frame
            move.l  A_SPR2(a2),d1
            beq.s   .frame
            cmp.w   #7,A_ROLE(a2)           ; hoppers show frame 2 while squatting
            bne.s   .cyc
            tst.w   v_squat(a5,d5.w)
            beq.s   .frame
            move.l  d1,d0
            bra.s   .frame
.cyc
            moveq   #0,d2
            move.w  v_anim(a5),d2
            move.w  A_ARATE(a2),d3
            bne.s   .rate
            moveq   #8,d3
.rate       divu    d3,d2
            btst    #0,d2
            beq.s   .moving
            tst.w   A_AMODE(a2)
            beq.s   .two
            move.w  v_ax(a5,d5.w),d2        ; only while moving
            cmp.w   v_px(a5,d5.w),d2
            bne.s   .two
            move.w  v_ay(a5,d5.w),d2
            cmp.w   v_py(a5,d5.w),d2
            beq.s   .frame
.two        move.l  d1,d0
.moving
.frame      move.w  v_ax(a5,d5.w),v_px(a5,d5.w)
            move.w  v_ay(a5,d5.w),v_py(a5,d5.w)
            lea     0(a4,d0.l),a0           ; a0 = sprite block to show
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
            add.w   #$2c,d0                 ; VSTART
            move.w  v_ax(a5,d5.w),d1
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

hide_sprites:
            move.w  H_NACT(a4),d6
            beq.s   .done
            move.l  H_ACTORS(a4),d0
            lea     0(a4,d0.l),a2
            subq.w  #1,d6
.h          move.l  A_SPR(a2),d0
            lea     0(a4,d0.l),a0
            move.l  #0,(a0)
            move.l  A_SPR2(a2),d0
            beq.s   .h2
            lea     0(a4,d0.l),a0
            move.l  #0,(a0)
.h2
            lea     ACT_SIZE(a2),a2
            dbf     d6,.h
.done       rts

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
            add.w   d4,d4
            move.w  d1,d5
            add.w   d5,d5
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
            beq.s   .touch
            cmp.w   #1,d0
            beq.s   .fire
            cmp.w   #2,d0
            beq.s   .timer
            cmp.w   #3,d0
            beq     .score
            cmp.w   #4,d0
            beq     .lives
            cmp.w   #6,d0
            beq.s   .jump
            bra     .next

.jump       move.w  v_jumped(a5),d0         ; actor a jumped this frame
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

.next       lea     RULE_SIZE(a3),a3
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
.n          lea     RULE_SIZE(a3),a3
            addq.w  #1,d7
            cmp.w   d6,d7
            blt.s   .r
.done       rts

fire_action:
            movem.l d5-d7/a2-a3,-(sp)
            bsr     do_action
            movem.l (sp)+,d5-d7/a2-a3
            rts

; a3 = rule
do_action:
            move.w  R_TGT(a3),d5            ; target actor -> d5 = offset
            move.w  d5,d4
            add.w   d5,d5
            move.w  R_ACT(a3),d0
            cmp.w   #19,d0
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

act_none:   rts

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
            rts

; target (d4/d5) goes to the place where actor R_VAL is
act_moveto: cmp.w   H_NACT(a4),d4
            bhs     act_none
            move.w  R_VAL(a3),d0
            cmp.w   H_NACT(a4),d0
            bhs     act_none
            add.w   d0,d0
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
            bsr     rand
            and.l   #$ffff,d0
            divu    #XMAX+1,d0
            swap    d0
            move.w  d0,v_ax(a5,d5.w)
            bsr     rand
            and.l   #$ffff,d0
            divu    #YMAX+1-16,d0
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
            lea     font(pc),a1
            add.w   d0,a1
            move.w  d2,d4
            mulu    #40,d4
            add.w   d1,d4
            move.l  v_disp(a5),a2
            add.l   d4,a2                   ; top-left byte on screen
            move.w  H_MSGCOL(a4),d3
            moveq   #7,d7                   ; 8 glyph rows
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
            move.b  1(a3),d0
            ror.w   #8,d6
            and.b   d6,d0
            ror.w   #8,d5
            btst    d4,d3
            beq.s   .c2
            or.b    d5,d0
.c2         move.b  d0,1(a3)
            move.b  d0,41(a3)
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
            beq     .off
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
            tst.w   d5
            beq.s   .hi
            move.l  #$01060c00,(a0)+        ; BPLCON3: bank 0, high nibbles
.hi         move.w  #$0180,(a0)+
            bsr.s   .col
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
            lea     font(pc),a1
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
            moveq   #0,d1                   ; opaque text: colour 0 box
            tst.w   v_opaque(a5)
            bne.s   .bg
            move.b  (a3),d1                 ; background
.bg
            move.b  d0,d2
            not.b   d2
            and.b   d2,d1
            btst    d5,d3
            beq.s   .clr
            or.b    d0,d1
.clr        move.b  d1,(a2)
            lea     40(a2),a2
            lea     40(a3),a3
            dbf     d7,.line
            add.l   #PLANE_SIZE-320,a2
            add.l   #PLANE_SIZE-320,a3
            addq.w  #1,d5
            dbf     d6,.plane
            movem.l (sp)+,d0-d7/a0-a3
            rts

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
            movem.l d0-d3/a0-a1,-(sp)
            move.w  H_HUDROW(a4),d2
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
            bsr     draw_text
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
.nogoal     tst.w   H_SHOWLV(a4)
            beq.s   .nolv
            lea     str_lives(pc),a0
            moveq   #31,d1
            bsr     draw_text
            moveq   #'0',d0
            add.w   v_lives(a5),d0
            moveq   #37,d1
            bsr     draw_char
.nolv       movem.l (sp)+,d0-d3/a0-a1
            rts

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
cop_grad:   dc.w    $ffff,$fffe             ; sky lines are built here at run time
            ds.b    256*20+32               ; AGA: wait + 4 moves per line

            cnop    0,4
V:          ds.b    V_SIZE+128
            cnop    0,4
stack:      ds.b    2048
stack_top:
            cnop    0,8
data_start:
