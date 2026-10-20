; ============================================================================
;  ADAM bootblock - loads the game (engine + data) into chip RAM and runs it,
;  showing a loading bar while the disk is read. If there is not enough chip
;  RAM for the game it shows a solid red screen and stops.
;  Entered by the Kickstart strap: a1 = trackdisk IOStdReq, a6 = ExecBase.
;  ADAM patches 'loadsize', 'bsssize' and the checksum when it writes the ADF.
;  Assemble:  vasmm68k_mot -Fbin -pic -m68000 -no-opt -o boot.bin boot.s
; ============================================================================
CHUNK       equ 11264               ; one cylinder (2 tracks x 11 sectors)
BAR_LINE    equ $96                 ; first raster line of the bar
BAR_X0      equ $50                 ; copper x where the bar starts
BAR_W       equ 128                 ; copper x units (= 256 low-res pixels)
COL_BG      equ $0012
COL_TROUGH  equ $0235
COL_FILL    equ $0f80
LINES_OFF   equ 72                  ; copper offset of the first bar line
NULL_SPR    equ 500                 ; offset of an empty sprite in the copper block

            dc.b    "DOS",0
            dc.l    0                       ; checksum (patched)
            dc.l    880                     ; root block
boot:
            move.l  a1,a2                   ; keep the IO request
            move.l  loadsize(pc),d0
            add.l   bsssize(pc),d0          ; + cleared memory after the data (tile world)
            move.l  #$10002,d1              ; MEMF_CHIP | MEMF_CLEAR
            jsr     -198(a6)                ; AllocMem - the game buffer
            tst.l   d0
            beq     .fail
            move.l  d0,a3

            move.l  #512,d0                 ; small chip block for the bar copper list
            move.l  #$10002,d1
            jsr     -198(a6)
            move.l  d0,a4
            tst.l   d0
            beq.s   .load
            bsr     build_copper
            lea     $dff000,a5
            move.l  a4,$80(a5)              ; COP1LC
            move.w  d0,$88(a5)              ; COPJMP1

.load       moveq   #0,d6                   ; bytes loaded
.chunk      move.l  loadsize(pc),d5
            sub.l   d6,d5
            ble.s   .loaded
            cmp.l   #CHUNK,d5
            ble.s   .size
            move.l  #CHUNK,d5
.size       move.l  a2,a1
            move.w  #2,28(a1)               ; CMD_READ
            lea     0(a3,d6.l),a0
            move.l  a0,40(a1)               ; io_Data
            move.l  d5,36(a1)               ; io_Length
            move.l  d6,d0
            add.l   #1024,d0
            move.l  d0,44(a1)               ; io_Offset - after the bootblock
            jsr     -456(a6)                ; DoIO
            add.l   d5,d6
            move.l  a4,d0                   ; update the bar
            beq.s   .chunk
            move.l  d6,d0
            lsr.l   #8,d0
            lsr.l   #1,d0                   ; sectors loaded
            lsl.l   #7,d0                   ; x BAR_W
            move.l  loadsize(pc),d1
            lsr.l   #8,d1
            lsr.l   #1,d1                   ; sectors in total
            divu    d1,d0
            and.w   #$00fe,d0
            add.w   #BAR_X0+1,d0            ; wait x | 1
            lea     LINES_OFF+8(a4),a0
            move.w  #BAR_LINE,d1
            moveq   #7,d2
.patch      move.w  d1,d3
            lsl.w   #8,d3
            or.w    d0,d3
            move.w  d3,(a0)
            lea     24(a0),a0
            addq.w  #1,d1
            dbf     d2,.patch
            bra.s   .chunk

.loaded     move.l  a2,a1
            move.w  #9,28(a1)               ; TD_MOTOR off
            move.l  #0,36(a1)
            jsr     -456(a6)                ; DoIO
            cmp.w   #37,20(a6)              ; Kickstart 2.0+ : flush caches
            blo.s   .nocc
            jsr     -636(a6)                ; CacheClearU
.nocc       jmp     (a3)                    ; the engine never returns
; Not enough chip RAM for the game (e.g. a big game on a 512KB A500): take
; over the display and show a solid red screen. Returning to the Kickstart
; would only bring back the insert-disk screen with no clue why.
.fail       lea     $dff000,a5
            move.w  #$7fff,$9a(a5)          ; INTENA - all interrupts off
            move.w  #$7fff,$96(a5)          ; DMACON - all DMA off (copper, planes, sprites)
            move.w  #$0200,$100(a5)         ; BPLCON0 - no bitplanes
            move.w  #0,$106(a5)             ; BPLCON3 (ECS/AGA) - bank 0, border not blanked
.red        move.w  #$0f00,$180(a5)         ; COLOR00 red, for ever
            bra.s   .red

; a4 = 512 byte chip block -> copper list: no bitplanes, dark screen,
; empty sprites, and an 8 line bar (fill | trough | background per line)
build_copper:
            move.l  a4,a0
            move.l  #$01000200,(a0)+        ; BPLCON0 - no bitplanes
            move.l  #($0180<<16)|COL_BG,(a0)+
            lea     NULL_SPR(a4),a1
            move.l  a1,d0
            move.w  #$0120,d1
            moveq   #7,d2
.spr        move.w  d1,(a0)+
            swap    d0
            move.w  d0,(a0)+
            swap    d0
            addq.w  #2,d1
            move.w  d1,(a0)+
            move.w  d0,(a0)+
            addq.w  #2,d1
            dbf     d2,.spr
            move.w  #BAR_LINE,d3
            moveq   #7,d2
.line       move.w  d3,d4
            lsl.w   #8,d4
            or.w    #BAR_X0+1,d4
            move.w  d4,(a0)+
            move.w  #$fffe,(a0)+
            move.l  #($0180<<16)|COL_FILL,(a0)+
            move.w  d4,(a0)+                ; fill end (patched as it loads)
            move.w  #$fffe,(a0)+
            move.l  #($0180<<16)|COL_TROUGH,(a0)+
            move.w  d3,d4
            lsl.w   #8,d4
            or.w    #BAR_X0+BAR_W+1,d4
            move.w  d4,(a0)+
            move.w  #$fffe,(a0)+
            move.l  #($0180<<16)|COL_BG,(a0)+
            addq.w  #1,d3
            dbf     d2,.line
            move.l  #$fffffffe,(a0)+
            rts

            cnop    0,4
loadsize:   dc.l    0                       ; bytes of engine + data to read
bsssize:    dc.l    0                       ; more chip RAM after them, cleared (version 6: tile world)
