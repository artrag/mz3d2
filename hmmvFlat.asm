	psect	text,class=CODE

	global _RLEData,_workpage
	global _CEIL,_FLOOR
	
; void hmmvFlat(uint color_x, uint lineHeight);
;  call as: hmmvFlat((color << 8) | x, lineHeight);
;
; input:
;   [e]  = x            (e & 3) == 0 
;   [d]  = color
;   [bc] = lineHeight   full height = 64
;
; Preconditions:
;  - VDP R#17 (indirect register addressing) must point to R#44 (CLR)
;  - VDP R#39 (DY.high) must point to the correct vram page
;  - VDP R#40-41 (NX) must already have the value 4

	global _hmmvFlat
_hmmvFlat:
	ld	hl,-(64+1)
	add	hl,bc
	jr	nc,clip
	ld	c,64
clip:				; c = min(64, lineHeight)

	ld	h,_RLEData/256
	ld	a,(_workpage)	; 0 or 1
	add	a,a		; 0 or 2
	inc	a		; 1 or 3
	add	a,e		; (e & 3) == 0, so no overflow
	ld	l,a		; hl = &RLEData[x/4][workpage].high
	
	ld	a,(hl)		; high byte of old color
	dec	l		; hl = &RLEData[x/4][workpage].low
	or	a		; non-zero means a texture (or sprite)
	jr	nz,DiffColor	; treat this as if color was changed
	ld	a,(hl)		; low byte of old color
	cp	d		; new color
	jp	z,SameColor

DiffColor:	; new column has different color
1:	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

	ld	(hl),d		; store new color, low byte ..
	inc	l		; hl = &RLEData[x/4][workpage].high
	ld	(hl),0		; .. and high byte
	dec	h		; hl = &lineHeight[x/4][workpage].high

	di
	ld	a,e		; x-coord
	out	(0x99),a
	ld	e,64		; put often used constant in register (for code size)
	ld	a,(hl)		; high byte of old lineHeight
	ld	(hl),0		; new clipped lineHeight is always < 256
	dec	l		; hl = &lineHeight[x/4][workpage].low
	or	a
	ld	a,36+128	;      doesn't change flags
	out	(0x99),a		; dx   doesn't change flags
	jr	nz,clipOld1	; old lineHeight >= 256 -> clip to 64
	ld	a,(hl)		; low byte of old lineHeight
	cp	e
	jr	c,clipOld2
clipOld1:
	ld	a,e		; do as-if old lineHeight = 64

clipOld2:
	cp      c
	ld      (hl),c
	jr      c,DiffBiggerEq
	jr      z,DiffBiggerEq

DiffSmaller:
	; different color and smaller, draw: ceiling+wall+floor
	; -- ceiling segment
	ld	b,a		; b = old lineHeight
	ld	a,e		; 64
	sub	b		; oldDrawStart
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,_CEIL
	out	(0x9b),a	; clr

	ld	a,b		; old lineHeight
	sub	c		; new lineHeight
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd

	; -- wall segment
wait2:
	in	a,(0x99)
	rrca
	jr	c,wait2		; wait for CE

	ld	a,d		; new color
	out	(0x9b),a	; clr

	ld	a,c		; new lineHeight
	add	a,a
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd

	; -- floor segment
wait3:
	in	a,(0x99)
	rrca
	jr	c,wait3		; wait for CE

	ld	a,_FLOOR
	out	(0x9b),a	; clr

	ld	a,b		; old lineHeight
	sub	c		; new lineHeight
	jr	last		; ny

DiffBiggerEq:
	; different color and bigger or equal: only draw wall segment
	ld	a,e		; 64
	sub	c		; newDrawStart
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,d		; new color
	out	(0x9b),a	; clr
	
	ld	a,c		; new lineHeight
	add	a,a
last:
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	ei
	out	(0x99),a	; cmd
	ret

SameColor:
	; New and old column have the same color, this also means the old
	; column was NOT a texture, and thus the old lineHeight must be in
	; range [1..64]. So there's no need to clip/check/update the upper
	; byte of the old lineHeight.
	dec	h		; hl = &lineHeight[x/4][workpage].low
	ld	a,(hl)		; old lineHeight
	cp	c
	ret	z		; same color and same lineHeight -> nothing to do

1:	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

	ld	b,(hl)		; b = old lineHeight, reload from memory (cheaper than 'ld b,a' above)
	ld	(hl),c		; store new lineHeight

	di			;
	ld	a,e		; x-coord
	out	(0x99),a
	ld	e,64		; often used constant
	ld	a,36+128
	out	(0x99),a		; dx

	ld	a,b		; same compare as above, but redoing the compare
	cp	c		; is as cheap as save-restore (e.g. in af')
	ld	a,e		; 64
	jr	c,SameBigger

SameSmaller:
	; same color and smaller: only erase top/bottom of previously drawn wall
	; -- ceiling segment
	sub	b		; oldDrawStart
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,_CEIL
	out	(0x9b),a	; clr

	ld	a,b		; old lineHeight
	sub	c		; new lineHeight
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd

	; -- floor segment
wait5:
	in	a,(0x99)
	rrca
	jr	c,wait5		; wait for CE

	ld	a,_FLOOR
	out	(0x9b),a	; clr

	ld	a,e		; 64
	add	a,c		; new lineHeight
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,b		; old lineHeight
	sub	c		; new lineHeight
	jr	last		; ny

SameBigger:
	; same color and bigger: extend wall segment at the top and bottom
	; -- top segment
	sub	c		; new lineHeight
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,d		; new color
	out	(0x9b),a	; clr

	ld	a,c		; new lineHeight
	sub	b		; old lineHeight
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd

	; -- bottom segment
wait6:
	in	a,(0x99)
	rrca
	jr	c,wait6		; wait for CE

	ld	a,e		; 64
	add	a,b		; old lineHeight
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,c		; new lineHeight
	sub	b		; old lineHeight
	jp	last		; ny
