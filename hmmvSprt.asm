	psect	text,class=CODE

	global _RLEData,_workpage

muluw_hl_bc macro
	db 0xed,0xc3	; de:hl <- hl * bc
	endm

mulub_a_c   macro
	db 0xED,0xC9	; hl <- a * c
	endm

; void hmmvSprite(uchar x, uint lineHeight, uchar* texData);
;
; Input: e  = x-coord
;        bc = lineHeight   (must be < 16384)
;        stack+2 = texData-pointer
;
; Preconditions:
;  - VDP R#17 (indirect register addressing) must point to R#44 (CLR)
;  - VDP R#39 (DY.high) must point to the correct vram page
;  - VDP R#40-41 (NX) must already have the value 2
;
; Note: If the last segment in the sprite RLE data is transparent, it can be
;    omitted. So the sum of the segment length doesn't need to sum to 128.
;    (For wall textures the sum must always be 128).

	global _hmmvSprite
_hmmvSprite:
1:	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

	push	ix		; store ix
	ld	ix,0		; because 'ld ix,sp' instruction doesn't exist
	add	ix,sp		; ix = framepointer (also to restore sp later)
	ld	a,e		; x-coord
	and	0xfc		; clear lower 2 bits
	ld	l,a
	ld	a,(_workpage)	; 0 or 1
	add	a,a		; 0 or 2
	add	a,l		; cannot overflow
	ld	h,_RLEData/256
	ld	l,a		; hl = &RLEData[x/4][workpage].low

	di
	ld	a,e		; x-coord, no need to mask bit0, the VDP ignores
	out	(0x99),a	;   it anyway  (reg DE is free now)
	ex	de,hl		; save hl (in de)
	ld	l,(ix+4)
	ld	h,(ix+5)	; hl = texData
	ld	sp,hl		; sp = texData
	ex	de,hl		; restore hl
	
	inc	l
	ld	(hl),0xff	; RLEData[x][workpage] = 0xff..

	dec	h		; hl = &lineHeight[.][.].high
	ld	(hl),b
	dec	l
	ld	(hl),c		; lineHeight[.][.] = lineHeight
	ld	a,b
	or	a
	ld	a,36+128
	out	(0x99),a	; dx
	jr	nz,SpriteZoom	; lineHeight >= 256 -> zoom
	ld	a,c		; new lineHeight
	cp	64
	jr	nc,SpriteZoom

SpriteNoZoom:
	; at this point
	;  lineHeight[][] and RLEData[][] arrays are updated
	;  VDP reg DX is already written
	;  bc = lineHeight   (lineHeight < 64, so b=0)
	;  sp = texData

	ld	a,64
	sub	c		; 64 - lineHeight  (no underflow)
	ld	d,a
	ld	e,b		; de = (64 - lineHeight) << 8   (e=b=0)
	sla	c
	sla	c		; c = lineHeight * 4 (no overflow)

loop1:	; in this loop we _DO_ have to set the DY VDP register
	pop	hl		; l = len   h = color
	ld	a,l
	or	a
	jr	z,vtraceend	; len == 0 -> done
	ld	b,h		; b = color
	mulub_a_c		; hl = a * c = len * lineHeight * 4
	add	hl,de		;
	ex	de,hl		; de = newY   hl = oldY
	ld	a,d
	cp	h
	jr	z,loop1		; segment not visible (too small after scaling)
	ld	a,b
	or	a
	jr	z,loop1		; color == 0 -> transparent segment
1:
	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE
	ld	a,h		; oldY
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a	; DY
	jr	draw

loop2:	; in this loop we _DON'T_ have to set the DY VDP register
	pop	hl		; l = len   h = color
	ld	a,l
	or	a
	jr	z,vtraceend		; len == 0 -> done
	ld	b,h		; b = color
	mulub_a_c		; hl = a * c = len * lineHeight * 4
loop2b:	add	hl,de
	ex	de,hl		; de = newY   hl = oldY
	ld	a,d
	cp	h
	jr	z,loop2		; segment not visible (too small after scaling)
	ld	a,b
	or	a		; transparent? (and at least 1 pixel in
	jr	z,loop1		; visible size) -> update DY on next segment
2:
	in	a,(0x99)
	rrca
	jr	c,2b
draw:
	ld	a,d		; newY
	sub	h		; oldY
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a	; ny
	ld	a,b		; b = color
	out	(0x9b),a	; clr
	; Instructions between loop2 and loop2b are duplicated here (marked
	; with **). Between VDP OUT instructions they are for free. This
	; possibly saves some cycles on very small lineHeights (when several
	; successive segments are too small to be visible).
	pop	hl		; ** l = len   h = color
	ld	a,l		; ** a = len (possibly 0)
	ld	b,h		; ** b = color
	mulub_a_c		; ** hl = a * c = len * lineHeight * 4
	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd
	jr	nz,loop2b	; ** z -> result of mulub, zero when len == 0

vtraceend:	
	ld	sp,ix		; restore sp
	pop	ix		; restore ix
	pop	hl		; return address
	inc	sp
	inc	sp		; pop parameter
	ei
	jp	(hl)		; return


SpriteZoom:
	; At this point lineHeight >= 64. But it's not sure we need to start
	; drawing from the top of the screen (when 1st segment is transparent).
	; (Possibly) we need also need to skip a portion of the 1st segment
	; texture data.
	ld	a,c		; lineHeight.low
	add	a,a
	exx
	ld	c,a		; c' = (lineHeight * 2).low
	exx
	ld	a,b		; lineHeight.high
	adc	a,a
	exx
	ld	b,a		; bc' = lineHeight * 2
	sla	c
	rl	b		; bc' = lineHeight * 4    (also clears carry)
	exx			;  no overflow as long as lineHeight < 16384

	ld	hl,64		; carry-flag is not set  (h=0)
	ld	e,h		; e = 0
	sbc	hl,bc		; hl = 64 - lineHeight  (possibly negative)
	ld	d,l
	ld	c,h		; c:de = (64 - lineHeight) << 8
	jp	z,TopDone1	; lineHeight == 64 -> no need to skip texels

	; c:de = (64 - lineHeight) << 8
	; bc' = lineHeight * 4
	; sp = texData
SkipTop:
	pop	hl		; l = len   h = color
	ld	a,l
	or	a		; for sprites we must check for end-of-data when zoomed
	jr	z,vtraceend	; because last transparent segment can be omitted
	exx
	ld	l,a
	ld	h,0
	muluw_hl_bc		; de':hl' = length * lineHeight * 4
	ld	a,l		; bits 7-0
	exx
	add	a,e
	ld	e,a
	exx
	ld	a,h		; bits 15-8
	exx
	adc	a,d
	ld	d,a
	exx
	ld	a,e		; bits 23-16
	exx
	adc	a,c
	ld	c,a		; c:de += e':hl'
	jr	nc,SkipTop	; do { .. } while (c:de < 0)

	; found end of first segment that is at or below the top of the screen
	jp	nz,Last128	; more than 256 pixels -> draw 128
	ld	a,d
	or	a
	jr	z,TopDone1	; top of screen, no need to draw partial first segment
	cp	128
	jp	nc,Last128	; 128 pixels or more -> draw 128

	ld	a,h		; h = color
	or	a
	jr	z,TopDone1	; first visible segment is transparent
	out	(0x9b),a	; clr

	xor	a		; top of screen
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a	; dy
	
	ld	a,d		; endY
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a	; ny

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd

TopDone2:
	; at this point we must draw full segments (last segment must
	; possibly be clipped at the bottom)
	;   de  = lastDrawnY << 8
	;   bc' = lineHeight * 4
	;   sp  = texData
	set	7,d		; d += 128. We add 128 because that way we can check
				; for overflow and > 128 with a single test

ZoomLoop2:	; no need to set DY in this loop
	pop	hl		; l = len   h = color
ZoomLoop2b:
	ld	a,l
	or	a
	jr	z,vtraceend	; end-of-data?
	exx
	ld	l,a
	ld	h,0
	muluw_hl_bc		; de':hl' = length * lineHeight * 4
	ld	a,l		; bits 7-0
	exx
	ld	c,d		; c = prev EndY
	jr	c,LastSegment2	; carry set -> de' != 0  (more than 256 pixels)
	add	a,e
	ld	e,a
	exx
	ld	a,h		; bits 15-8
	exx
	adc	a,d
	jr	c,LastSegment2
	ld	d,a		; de += hl'
	cp	c		; c = previous endY
	jr	z,ZoomLoop2	; less than 1 pixel after scaling
	ld	a,h
	or	a
	jr	z,ZoomLoop1	; transparent -> set DY on next segment
1:
	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

ZoomDraw:
	ld	a,d
	sub	c		; newEndY - oldEndY
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a	; ny

	ld	a,h		; h = color
	out	(0x9b),a	; clr

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	pop	hl		; ** interleaved TODO can we interleave more?
	out	(0x99),a	; cmd
	jr	ZoomLoop2b

TopDone1:
	; same as TopDone2, except that we need to set DY on next segment
	set	7,d		; d += 128. We add 128 because that way we can check
				; for overflow and > 128 with a single test

ZoomLoop1:	; we DO need to set DY in this loop
	pop	hl		; l = len   h = color
	ld	a,l
	or	a
	jp	z,vtraceend	; end-of-data?
	exx
	ld	l,a
	ld	h,0
	muluw_hl_bc		; de':hl' = length * lineHeight * 4
	ld	a,l		; bits 7-0
	exx
	ld	c,d		; c = prev endY
	jr	c,LastSegment1	; carry set -> de' != 0  (more than 256 pixels)
	add	a,e
	ld	e,a
	exx
	ld	a,h		; bits 15-8
	exx
	adc	a,d
	jr	c,LastSegment1
	ld	d,a		; de += hl'
	cp	c		; c = previous endY
	jr	z,ZoomLoop1	; less than 1 pixel
	ld	a,h
	or	a
	jr	z,ZoomLoop1	; transparent
1:
	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

	ld	a,c		; previous endY
	sub	128
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a	; dy
	jr	ZoomDraw

LastSegment2:
	ld	a,h
	or	a
	jp	z,vtraceend
1:
	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

Last2:	xor	a
	sub	c		; a = 128 - (oldEndy - 128) = 256 - c = 0 - c
Last:	out	(0x99),a
	ld	a,42+128
	out	(0x99),a	; ny

	ld	a,h		; h = color
	out	(0x9b),a	; clr

	ld	a,0xc0		; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd
	jp	vtraceend

LastSegment1:
	ld	a,h
	or	a
	jp	z,vtraceend
1:
	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

	ld	a,c
	sub	128
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a	; dy
	jr	Last2

Last128:	; at this point we've already waited for CE
	ld	a,h
	or	a
	jp	z,vtraceend
	
	xor	a		; top of screen
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a	; dy
	
	ld	a,128		; full screen height
	jr	Last

