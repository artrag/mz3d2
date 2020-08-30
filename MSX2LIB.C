#include "msx2lib.h"

char dummy[32];

void bordercolor(char color)
{
#asm
	ld	a,e
	di
	out	(0x99),a
	ld	a,7+128
	ei
	out	(0x99),a
#endasm
}

#asm

global _vdpsetvramwr
global _vdpsetvramrd

_vdpsetvramwr:
;Set VDP for writing at address CDE (17-bit) ;
            ld a,c
;Set VDP for writing at address ADE (17-bit) ;
            rlc d
            rla
            rlc d
            rla
            srl d ; primo shift, il secondo dopo la out
			di
            out (0x99),a ;set bits 15-17
            ld a,14+128
            out (0x99),a
            ld a,e ;set bits 0-7
            srl d ; secondo shift.
            out (0x99),a
            ld a,d ;set bits 8-14
            or 64 ; + write access
            out (0x99),a
			ei
            ret

_vdpsetvramrd:
;Set VDP for reading at address CDE (17-bit) ;
            ld a,c
;Set VDP for reading at address ADE (17-bit) ;
            rlc d
            rla
            rlc d
            rla
            srl d ; primo shift, il secondo dopo la out
			di
            out (0x99),a ;set bits 15-17
            ld a,14+128
            out (0x99),a
            ld a,e ;set bits 0-7
            srl d ; secondo shift.
            out (0x99),a
            ld a,d ;set bits 8-14
            out (0x99),a
			ei
            ret

	global _scr
_scr:

exttbl	equ	0xfcc1		; main rom slot
chgmod	equ	0x005f		; change graphic mode
CALSLT	equ	0x001c		; call ix in slot (iy)

	ld	a,e
	push	ix
	push	iy
	ld	iy,(exttbl-1)
	ld	ix,chgmod
	call	CALSLT

	; TODO is writing R#14 really needed?
	xor	a
	out	(0x99),a
	pop	iy
	pop	ix
	ld	a,14+128
	out	(0x99),a
	
	ld	a,2
	out	(0x99),a
	ld	a,9+128
	out	(0x99),a	

	ld	a,8|2
	out	(0x99),a
	ld	a,8+128
	ei
	out	(0x99),a
	ret


; Display page E in screen 5/8, E must be in range 0..3
	global _setpage
_setpage:
	ld	a,e
	rrca
	rrca
	rrca		; rotate >-> 3, is the same as << 5 (when 0 <= a <= 3)
	or	0x1f
	di
	out	(0x99),a
	ld	a,2+128
	ei
	out	(0x99),a
	ret

; Initialize the VDP palette
	global _SetPalette,_palettedata
_SetPalette:
	xor	a
	di
	out	(0x99),a
	ld	hl,_palettedata
	ld	a,16+128
	out	(0x99),a	; initialize palette pointer
	ld	bc,32*256+0x9A
	otir			; write palette data
	ei
	ret


#endasm

