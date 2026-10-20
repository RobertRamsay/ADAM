; ============================================================================
;  ADAM Pro loading screen - a small position-independent block the bootblock
;  reads before the game (boot.s). ADAM appends the data (LS_* header, copper
;  list, picture planes, bar strip) right after this code, at ls_data.
;
;  Entry points (a0 = the block, a5 = $dff000; d2-d7/a2-a6 are saved by the
;  bootblock's call_block):
;     0  init      fix the copper list's pointers, show the screen
;     4  progress  d0.w = 0..1024: reveal the full bar up to that point
;     8  done      display off (the engine takes over at once)
;
;  The bar: ADAM draws the empty bar into the picture and keeps a strip of the
;  same screen area with the full bar (whole bytes, so the edge bytes already
;  hold the right picture pixels). Progress copies the newly reached part of
;  the strip onto the screen: pixel columns (left to right or right to left,
;  masking the edge byte) or whole rows (bottom to top, top to bottom).
;  Pictures (version 2): each shows when the progress reaches its threshold -
;  ADAM keeps them in order and stores each as the screen bytes it covers.
;
;  The copper list is ADAM's: plain MOVEs and WAITs. A MOVE to BPLxPTH or
;  SPRxPTH holds the high word of an offset from the block start and the next
;  MOVE (xPTL) the low word; init adds the block's address to each pair.
;  Same layout in scr_loadscr.gml (loadscr_block) and adf_reference.py.
;  Assemble:  vasmm68k_mot -Fbin -pic -m68000 -no-opt -o loadscr.bin loadscr.s
; ============================================================================
LS_MAGIC    equ 0          ; 'LSCR'
LS_VER      equ 4          ; word: 2
LS_FLAGS    equ 6          ; word: bit 0 AGA
LS_DEPTH    equ 8          ; word: bitplanes 1..8
LS_MODE     equ 10         ; word: fill 0 left to right, 1 right to left, 2 bottom to top, 3 top to bottom
LS_COPPER   equ 12         ; long: copper list (offset from the block)
LS_PLANES   equ 16         ; long: picture, plane after plane, 40 x 256 bytes each
LS_STRIP    equ 20         ; long: the full bar, plane after plane, LS_SSTRIDE x LS_BARH bytes each
LS_BARX     equ 24         ; word: bar left pixel
LS_BARY     equ 26         ; word: bar top line
LS_BARW     equ 28         ; word: bar width in pixels
LS_BARH     equ 30         ; word: bar height in lines
LS_SX0      equ 32         ; word: the strip's first byte column on the screen
LS_SSTRIDE  equ 34         ; word: bytes per strip row
LS_NPIC     equ 36         ; word: pictures (PI_*), in the order they show
LS_PICS     equ 40         ; long: the pictures (offset from the block)
LS_SIZE     equ 48
PI_THR      equ 0          ; word: shows when the progress (0..1024) reaches this
PI_COL      equ 2          ; word: its first byte column on the screen
PI_Y        equ 4          ; word: its top line
PI_WB       equ 6          ; word: bytes across
PI_H        equ 8          ; word: lines
PI_DATA     equ 12         ; long: its bytes, plane after plane (offset from the block)
PI_SIZE     equ 16
PLANE_BYTES equ 10240      ; 40 bytes x 256 lines

            bra.w   ls_init
            bra.w   ls_prog
            bra.w   ls_done

; ---------------------------------------------------------------------------
ls_init:    lea     ls_data(pc),a1
            move.l  LS_COPPER(a1),a2
            add.l   a0,a2                   ; a2 = copper list
            move.l  a2,a3
.fix        move.w  (a3),d1
            cmp.w   #$ffff,d1               ; end of the list
            beq.s   .fixed
            move.w  d1,d2
            sub.w   #$e0,d2                 ; BPL1PTH..BPL8PTL
            cmp.w   #$1e,d2
            bls.s   .ptr
            move.w  d1,d2
            sub.w   #$120,d2                ; SPR0PTH..SPR7PTL
            cmp.w   #$1e,d2
            bhi.s   .next
.ptr        btst    #1,d2                   ; xPTH (not xPTL)
            bne.s   .next
            move.w  2(a3),d2
            swap    d2
            move.w  6(a3),d2
            add.l   a0,d2
            move.w  d2,6(a3)
            swap    d2
            move.w  d2,2(a3)
            addq.l  #8,a3
            bra.s   .fix
.next       addq.l  #4,a3
            bra.s   .fix
.fixed      lea     ls_px(pc),a3
            clr.w   (a3)
            lea     ls_pic(pc),a3
            clr.w   (a3)
            move.l  a2,$80(a5)              ; COP1LC
            move.w  d0,$88(a5)              ; COPJMP1
            move.w  #$8380,$96(a5)          ; DMACON: master, bitplanes, copper on
            rts

; ---------------------------------------------------------------------------
; d0.w = progress 0..1024
ls_prog:    lea     ls_data(pc),a1
            and.l   #$ffff,d0
            cmp.w   #1024,d0
            bls.s   .inrange
            move.w  #1024,d0
.inrange    move.w  d0,-(sp)                ; (the pictures want it after the bar)
            move.w  LS_BARW(a1),d1          ; columns, or rows for the up / down fills
            cmp.w   #2,LS_MODE(a1)
            blo.s   .len
            move.w  LS_BARH(a1),d1
.len        mulu    d1,d0
            lsr.l   #8,d0
            lsr.l   #2,d0                   ; d0 = columns / rows of the bar that are full
            lea     ls_px(pc),a2
            move.w  (a2),d1                 ; d1 = how many were already shown
            cmp.w   d1,d0
            bls     .pics
            move.w  d0,(a2)
            move.w  LS_MODE(a1),d2
            cmp.w   #2,d2
            bhs     .rows
            move.w  LS_BARX(a1),d3          ; columns: d3 = first new pixel, d4 = end
            tst.w   d2
            bne.s   .rtl
            move.w  d3,d4
            add.w   d1,d3
            add.w   d0,d4
            bra.s   .cols
.rtl        add.w   LS_BARW(a1),d3          ; right to left: from the bar's right edge
            move.w  d3,d4
            sub.w   d1,d4
            sub.w   d0,d3
.cols       move.w  LS_SSTRIDE(a1),d2
            mulu    LS_BARH(a1),d2
            move.l  d2,a2                   ; a2 = bytes per strip plane
            move.w  d3,d5
            lsr.w   #3,d5                   ; d5 = byte column
.col        move.w  d5,d6
            lsl.w   #3,d6                   ; the column's first pixel
            move.w  d3,d1
            sub.w   d6,d1                   ; lo = first new pixel in this byte
            bpl.s   .lo
            moveq   #0,d1
.lo         move.w  d4,d2
            sub.w   d6,d2                   ; hi = end in this byte
            cmp.w   #8,d2
            ble.s   .hi
            moveq   #8,d2
.hi         move.w  #$ff,d7
            lsr.w   d1,d7                   ; pixels lo..7
            move.w  #$ff,d1
            lsr.w   d2,d1
            not.w   d1                      ; pixels 0..hi-1
            and.w   d1,d7                   ; d7 = mask (bit 7 = leftmost pixel)
            move.b  d7,d6
            not.b   d6                      ; d6 = keep mask
            move.l  LS_PLANES(a1),a3
            add.l   a0,a3
            move.w  LS_BARY(a1),d1
            mulu    #40,d1
            add.l   d1,a3
            add.w   d5,a3                   ; a3 = screen byte, plane 0, bar top
            move.l  LS_STRIP(a1),a4
            add.l   a0,a4
            move.w  d5,d1
            sub.w   LS_SX0(a1),d1
            add.w   d1,a4                   ; a4 = strip byte, plane 0, top row
            move.w  LS_DEPTH(a1),d0
            subq.w  #1,d0
.plane      move.l  a3,a5
            move.l  a4,a6
            move.w  LS_BARH(a1),d1
            subq.w  #1,d1
.row        move.b  (a6),d2
            and.b   d7,d2
            and.b   d6,(a5)
            or.b    d2,(a5)
            lea     40(a5),a5
            add.w   LS_SSTRIDE(a1),a6
            dbf     d1,.row
            add.l   #PLANE_BYTES,a3
            add.l   a2,a4
            dbf     d0,.plane
            addq.w  #1,d5
            move.w  d5,d2
            lsl.w   #3,d2
            cmp.w   d4,d2
            blt     .col
            bra     .pics

.rows       cmp.w   #3,d2                   ; rows: d3 = first new row of the bar, d4 = end
            beq.s   .ttb
            move.w  LS_BARH(a1),d3          ; bottom to top
            move.w  d3,d4
            sub.w   d0,d3
            sub.w   d1,d4
            bra.s   .rw
.ttb        move.w  d1,d3
            move.w  d0,d4
.rw         move.w  LS_SSTRIDE(a1),d2
            mulu    LS_BARH(a1),d2
            move.l  d2,a2                   ; a2 = bytes per strip plane
            move.l  LS_PLANES(a1),a3
            add.l   a0,a3
            move.w  LS_BARY(a1),d1
            add.w   d3,d1
            mulu    #40,d1
            add.l   d1,a3
            add.w   LS_SX0(a1),a3           ; a3 = screen, plane 0, the first new row
            move.l  LS_STRIP(a1),a4
            add.l   a0,a4
            move.w  d3,d1
            mulu    LS_SSTRIDE(a1),d1
            add.l   d1,a4                   ; a4 = strip, plane 0, the first new row
            sub.w   d3,d4
            subq.w  #1,d4                   ; d4 = rows - 1
            move.w  LS_SSTRIDE(a1),d5
            move.w  LS_DEPTH(a1),d0
            subq.w  #1,d0
.rpl        move.l  a3,a5
            move.l  a4,a6
            move.w  d4,d1
.rrow       move.w  d5,d2
            subq.w  #1,d2
.rb         move.b  (a6)+,(a5)+
            dbf     d2,.rb
            lea     40(a5),a5
            sub.w   d5,a5                   ; the next line, back to the first column
            dbf     d1,.rrow
            add.l   #PLANE_BYTES,a3
            add.l   a2,a4
            dbf     d0,.rpl

.pics       move.w  (sp)+,d0                ; the pictures the progress has reached
.pnext      move.w  LS_NPIC(a1),d7
            beq     .out
            lea     ls_pic(pc),a2
            move.w  (a2),d6                 ; how many are showing
            cmp.w   d7,d6
            bhs     .out
            move.l  LS_PICS(a1),a3
            add.l   a0,a3
            lsl.w   #4,d6                   ; x PI_SIZE
            add.w   d6,a3                   ; a3 = the next one
            cmp.w   PI_THR(a3),d0
            blo     .out
            addq.w  #1,(a2)
            move.l  PI_DATA(a3),a4
            add.l   a0,a4                   ; a4 = its bytes
            move.l  LS_PLANES(a1),a5
            add.l   a0,a5
            move.w  PI_Y(a3),d1
            mulu    #40,d1
            add.l   d1,a5
            add.w   PI_COL(a3),a5           ; a5 = the screen under it, plane 0
            move.w  LS_DEPTH(a1),d5
            subq.w  #1,d5
.ppl        move.l  a5,a6
            move.w  PI_H(a3),d4
            subq.w  #1,d4
.prow       move.l  a6,a2
            move.w  PI_WB(a3),d2
            subq.w  #1,d2
.pb         move.b  (a4)+,(a2)+
            dbf     d2,.pb
            lea     40(a6),a6
            dbf     d4,.prow
            add.l   #PLANE_BYTES,a5
            dbf     d5,.ppl
            bra     .pnext
.out        rts

; ---------------------------------------------------------------------------
ls_done:    move.w  #$0180,$96(a5)          ; DMACON: bitplanes and copper off
            move.w  #$0200,$100(a5)         ; BPLCON0: no bitplanes
            move.w  #0,$180(a5)             ; COLOR00 black
            rts

ls_px:      dc.w    0                       ; bar columns / rows shown so far
ls_pic:     dc.w    0                       ; pictures showing

            cnop    0,8
ls_data:                                    ; ADAM's data follows (LS_*)
