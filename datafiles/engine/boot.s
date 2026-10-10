; ============================================================================
;  ADAM bootblock - loads the game (engine + data) into chip RAM and runs it.
;  Entered by the Kickstart strap: a1 = trackdisk IOStdReq, a6 = ExecBase.
;  ADAM patches 'loadsize' and the checksum when it writes the ADF.
;  Assemble:  vasmm68k_mot -Fbin -pic -m68000 -no-opt -o boot.bin boot.s
; ============================================================================
            dc.b    "DOS",0
            dc.l    0                       ; checksum (patched)
            dc.l    880                     ; root block
boot:
            move.l  a1,a2                   ; keep the IO request
            move.l  loadsize(pc),d0
            move.l  #$10002,d1              ; MEMF_CHIP | MEMF_CLEAR
            jsr     -198(a6)                ; AllocMem
            tst.l   d0
            beq.s   .fail
            move.l  d0,a3
            move.l  a2,a1
            move.w  #2,28(a1)               ; CMD_READ
            move.l  a3,40(a1)               ; io_Data
            move.l  loadsize(pc),36(a1)     ; io_Length
            move.l  #1024,44(a1)            ; io_Offset - straight after the bootblock
            jsr     -456(a6)                ; DoIO
            move.l  a2,a1
            move.w  #9,28(a1)               ; TD_MOTOR off
            move.l  #0,36(a1)
            jsr     -456(a6)                ; DoIO
            cmp.w   #37,20(a6)              ; Kickstart 2.0+ : flush caches
            blo.s   .nocc
            jsr     -636(a6)                ; CacheClearU
.nocc       jmp     (a3)                    ; never returns
.fail       moveq   #-1,d0
            rts
            cnop    0,4
loadsize:   dc.l    0
