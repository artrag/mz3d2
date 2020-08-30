	psect	text,class=CODE

	global _RLEData,_workpage
	global _CEIL,_FLOOR
	
muluw_hl_bc macro
	db 0xed,0xc3	; de:hl < -hl * bc
	endm
			
mulub_a_b   macro
	db 0xED,0xC1	; hl <- a * b
	endm

;; void hmmvTexRender(uchar x, uint lineHeight, char* texData);
; input: e       = x-coord      (e & 3) == 0
;        bc      = lineHeight  64 means full height
;        stack+2 = pointer to RLE texture data

; TODO it might be more efficient to change the order of the parameters
;      e.g. swap 1st and 3rd so that x-coord (which is not always needed)
;      is on the stack (also only 8 bit vs 16 bit on the stack)
;      after this swap, posibly also swap 1st and 2nd, so that texData is
;      in DE (might be useful to bring move it to HL with 'ex de,hl')

; TODO now we first compare texData, and next lineHeight. It might be more
;      efficient to swap this order because lineHeight varies more frequently
;
; TODO - use SP trick to access RLE data

	global _hmmvTexRender
_hmmvTexRender:
	ld	a,(_workpage)	; 0 or 1
	add	a,a		; 0 or 2
	add	a,e		; (e & 3) == 0, so no overflow

	exx
	ld	hl,2
	add	hl,sp
	ld	e,(hl)
	inc	hl		; can be 'inc l' if we know SP is 2-aligned (only matters for Z80)
	ld	d,(hl)		; de' = texData
	
	ld	h,_RLEData/256
	ld	l,a		; hl' = &RLEData[x/4][workpage].low

	ld	a,(hl)		; old texData.low
	cp	e		; new texData.low
	jp	nz,DiffTex1
	inc	l
	ld	a,(hl)		; old texData.high
	cp	d		; new texData.high
	jp	nz,DiffTex2

SameTexture:
	dec	h		; hl' = &lineHeight[x/4][workpage].high
	ld	a,(hl)		; old lineHeight.high
	exx
	cp	b		; new lineHeight.high
	jr	nz,DiffHeight1
	ld	a,c		; new lineHeight.low
	exx
	ld	b,(hl)		; b' = old lineHeight.high
	dec	l		; hl' = &lineHeight[..][..].low
	cp	(hl)		; old lineHeight.low
	jr	nz,DiffHeight2

AllSame:
	pop	hl		; return address
	inc	sp		; pop parameter from stack
	inc	sp		; (on Z80 'pop af' is cheaper)
	jp	(hl)		; return

DiffTex1:
	ld	(hl),e		; store new texData.low
	inc	l
DiffTex2:
	ld	(hl),d		; store new texData.high

	dec	h		; hl = &lineHeight[x/4][workpage].high
	exx
DiffHeight1:
	ld	a,b		; lineHeight.high
	exx
	ld	b,(hl)		; b' = old lineHeight.high
	ld	(hl),a		; store new lineHeight.high
	dec	l
	exx
	ld	a,c		; lineHeight.low
	exx
DiffHeight2:
	ld	c,(hl)		; c' = old lineHeight.low
	ld	(hl),a		; store new lineHeight.low

	; at this point:
	;  bc  = lineHeight
	;  e   = x-coord
	;  bc' = old lineHeight
	;  de' = texData

1:	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

	di
	exx
	ld	a,e		; x-coord
	out	(0x99),a
	ld	hl,-64
	add	hl,bc
	ld	a,36+128
	out	(0x99),a		; dx
	jp	c,ClipTex

NoClipTex:
	; lineHeight < 64
	; This means there's always at least 1 ceiling and 1 floor pixel.
	; It also means 'lineHeight * 4' always fits in 8 bits
	exx
	ld	a,b
	or	a
	jr	nz,ClipOld1	; old lineHeight >= 256 -> clip to 64
	ld	a,c
	cp	64+1		; old lineHeight <= 64  -> no need to clip
	jr	c,ClipOld2
ClipOld1:
	ld	a,64
ClipOld2:	
	exx	
	ld	b,a		; b = min(64, old_lineHeight)
	sub     c               ; new lineHeight
	jr      c,Wall1
	jr      z,Wall1         ; new >= old -> no need to draw ceiling pixels

	; lineHeight < 64 and smaller than previous frame
	; -> only draw 'extra' ceiling/floor pixels
	; -- ceiling segment
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,64
	sub	b		; old lineHeight
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,_CEIL
	out	(0x9b),a		; clr

	ld	a,0xc0			; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a		; cmd
	jr	Wall2

Wall1:
	; lineHeight < 64, but bigger than previous frame
	; -> no need to draw ceiling/floor pixels
	ld	a,64
	sub	c		; new lineHeight
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	; -- wall segment
	; pseudo code for inner loop:
	;   y = (64 - lineHeight) << 8;
	;   do {
	;       y2 = y + (*p++ * lineHeight * 4);
	;       plot((y2 >> 8) - (y >> 8), *p++);
	;       y = y2;
	;   } while (*p);
Wall2:
	ld	a,64
	sub	c
	exx
	ld	b,a		; tmp
	ld	a,d
	ld	d,b		; d' = 64 - lineHeight
	exx
	ld	h,a		; h = texData.high

	ld	a,c
	add	a,a
	add	a,a		; lineHeight < 64, so no overflow
	exx
	ld	b,a		; b' = lineHeight * 4
	ld	a,e
	ld	e,0		; de' = (64 - lineHeight) << 8 = y
	exx
	ld	l,a		; hl = texData

	dec	hl		; cheaper than 'jr' to skip next instruction (on R800, but not on Z80)
Next1:
	inc	hl		; skip texData->color
	ld	a,(hl)		; texData->length
DoWhile1:
	inc	hl
	exx
	mulub_a_b		; hl' = a*b' = length * lineHeight * 4
	add	hl,de		; hl' = y2 = y + (.. * ..)
	ex	de,hl		; de' = y2    hl' = y  
	ld	a,d
	sub	h		; (y2 >> 8) - (y >> 8) 
	exx
	jr	z,Next1		; no need to check for (hl+1) == 0
	ld	e,a		; e = segment length (on screen)

2:
	in	a,(0x99)
	rrca
	jr	c,2b		; wait for CE

	ld	a,e		; segment length
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,(hl)		; texData: color
	inc	hl
	out	(0x9b),a	; clr

	ld	a,0xc0			; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd

	ld	a,(hl)		; texData->length
	or	a
	jr	nz,DoWhile1

	; -- floor segment
	ld	a,c		; new lineHeight
	cp	b		; old lineHeight
	jr	nc,TexEnd	; new >= old -> no need to draw floor pixels

3:
	in	a,(0x99)
	rrca
	jr	c,3b		; wait for CE

	ld	a,b		; old lineHeight
	sub	c		; new lineHeight
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,_FLOOR
last_seg:
	out	(0x9b),a		; clr

	ld	a,0xc0			; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a		; cmd

TexEnd:
	pop	hl		; return address
	inc	sp		; pop parameter from stack
	inc	sp		; (on Z80 'pop af' is cheaper)
	ei
	jp	(hl)		; return


ClipTex:
	; lineHeight >= 64. Texture is at least as high as the full screen
	; height, so there are no ceiling and floor pixels.

	; at this point:
	;  bc  = lineHeight
	;  de' = texData

	xor	a
	out	(0x99),a
	ld	a,c		; lineHeight.low
	add	a,a
	exx
	ld	c,a		; c' = (lineHeight * 2).low
	ld	a,d		; texData.high
	exx
	ld	d,a		; d = texData.high
	ld	a,b		; lineHeight.high
	adc	a,a		; (lineHeight * 2).high
	exx
	ld	b,a		; bc' = lineHeight * 2
	sla	c
	rl	b		; bc' = lineHeight * 4     clears carry flag
				; no overflow as long as lineHeight < 16384
	ld	a,e		; texData.low
	exx
	ld	e,a		; de = texData
	ld	a,38+128
	out	(0x99),a		; dy

	; y = (Hscr - lineHeight) << 8
	ld	hl,64		; carry-flag is already clear
	sbc	hl,bc		; hl = 64 - lineHeight
	ld	b,l
	ld	c,0		;   bc = (64 - lineHeight) << 8   (lower 16 bits)
	ex	de,hl		; d:bc = (64 - lineHeight) << 8   (full 24 bits)
	dec	hl		; hl = texData-1  (doesn't change flags)
	jr	z,TopDone	; lineHeight == 64 -> no need to skip texels

	; lineHeight > 64
	; -> y = 64 - lineHeight  is negative
	; skip texels till y becomes non-negative
SkipTop:
	inc	hl
	ld	a,(hl)		; texData->length
	inc	hl
	exx
	ld	l,a
	ld	h,0		; hl' = zero-extend(length)
	muluw_hl_bc		; de':hl' = length * lineHeight * 4
	ld	a,l
	exx
	add	a,c
	ld	c,a
	exx
	ld	a,h
	exx
	adc	a,b
	ld	b,a
	exx
	ld	a,e
	exx
	adc	a,d
	ld	d,a		; d:bc += e':hl'
	jr	nc,SkipTop	; while (d:bc < 0)

	ld	a,d		; ** recalculate zero-flag, allows to move the CE-test
	or	a		; ** a bit earlier (only costs 2 bytes code size)
	jr	z,ClipTop1
	ld	b,128		; more than 256 pixels, do as-if only 128 pixels
ClipTop1:
	ld	a,b
	or	a
	jr	z,TopDone	; no need to draw partial segment (at top of screen)

	cp	128+1
	jr	c,ClipTop2
	ld	a,128
ClipTop2:			; a = min(128, length-of-first-partial-segment)
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,(hl)
	out	(0x9b),a		; clr

	ld	a,0xc0			; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a		; cmd

TopDone:
	; at this point
	; bc  = y ~= lastDrawnY << 8  (exclusive) (includes fractional part)
	; hl  = texData-1  (one byte before the segment that should be drawn from start)
	; bc' = lineHeight * 4
	ld	a,b		; b = last-drawn-y-coord (exclusive)
	add	a,128		; add 128, that way we can detect overflow and '>128'
				; using the carry-flag (so using only 1 test)
	jr	c,TexEnd	; was already '>= 128' -> done 
	ld	b,a
	ld	d,a		; d = last-drawn-y-coord (exclusive)

ZoomLoop:
	inc	hl
	ld	a,(hl)		; texData->length
	inc	hl
	exx
	ld	l,a
	ld	h,0		; hl' = zero-extend(length)
	muluw_hl_bc		; de':hl' = RLE-length * lineHeight * 4
	ld	a,l
	exx
	jr	c,LastSegment	; carry set -> de' != 0 (result of muluw didn't fit in 16-bit)
ZoomLoop2:
	add	a,c
	ld	c,a
	exx
	ld	a,h
	exx
	adc	a,b
	jr	c,LastSegment
	ld	b,a		; bc += hl'
	cp	d
	jr	z,ZoomLoop

5:
	in	a,(0x99)
	rrca
	jr	c,5b		; wait for CE

	ld	a,b
	sub	d
	out	(0x99),a
	ld	d,b
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,(hl)
	inc	hl		; ** The instruction between ZoomLoop and ZoomLoop2
				; ** are duplicated here (marked with '**') and
				; ** interleaved with the VDP OUT instructions so
				; ** that between 2 OUT instructions there are
				; ** never more than 52 R800 cycles
	out	(0x9b),a	; clr
	ld	a,(hl)		; ** texData->length
	inc	hl		; **
	exx			; **
	ld	l,a		; **
	ld	h,0		; ** hl' = zero-extend(length)
	ld	a,0xc0		; HMMV
	out	(0x99),a		; clr
	muluw_hl_bc		; ** de':hl' = RLE-length * lineHeight * 4

	ld	a,46+128
	out	(0x99),a	; cmd
	ld	a,l		; **
	exx			; **
	jr	nc,ZoomLoop2	; ** carry set -> de' != 0 (result of muluw didn't fit in 16-bit)

LastSegment:
6:
	in	a,(0x99)
	rrca
	jr	c,6b		; wait for CE

	xor	a
	sub	d		; a = 128 - (y - 128)  =  256 - y  =  0 - y 
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,(hl)
	jp	last_seg		; clr
