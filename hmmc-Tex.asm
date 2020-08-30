	psect	text,class=CODE

	global _RLEData,_workpage
	global _CEIL,_FLOOR
	
muluw_hl_bc macro
	db 0xed,0xc3	;de:hl<-hl*bc
	endm
			
mulub_a_b   macro
	db 0xED,0xC1	;hl<- a*b
	endm
			
;; void hmmcTexRender(uchar x, uint lineHeight, char* texData);
; input: e       = x-coord      (e & 3) == 0
;        bc      = lineHeight  64 means full height
;        stack+2 = pointer to RLE texture data
;
; precondition:
;   VDP R#17 points to CLR register
;   VDP R#40 (NX) = 4
;
; TODO - use SP trick to access RLE data ... does that actually speed
;        things up? Probably it does for the zoom out loop. Maybe not
;        for zoom in (because we still need 'exx' and 'pop' fetches both
;        values in the same set of (shadow) registers).

	global _hmmcTexRender
_hmmcTexRender:
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
	ld	d,a		; d = min(64, old_lineHeight)
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
	sub	d		; old lineHeight
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a		; dy

	ld	a,_CEIL
	out	(0x9b),a		; clr

	ld	a,0xc0			; HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a		; cmd

2:
	in	a,(0x99)
	rrca
	jr	c,2b		; wait for CE
	jr	Wall2		; skip setting dy

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
	ld	a,c		; lineHeight
	add	a,a		; lineHeight * 2
	out	(0x99),a
	add	a,a		; lineHeight < 64, so no overflow
	exx
	ld	b,a		; b' = lineHeight * 4
	ld	a,e
	ld	e,0		; de' = (64 - lineHeight) << 8 = y
	exx
	ld	l,a		; hl = texData

	dec	hl		; cheaper than 'jr' to skip 'inc hl' instruction (on R800, but not on Z80)
	ld	a,42+128
	out	(0x99),a	; ny

Next0:
	inc	hl		; skip texData->color
	ld	a,(hl)		; texData->length
	inc	hl
	exx
	mulub_a_b		; hl' = a*b' = length * lineHeight * 4
	add	hl,de		; hl' = y2 = y + (.. * ..)
	ex	de,hl		; de' = y2    hl' = y  
	ld	a,d
	sub	h		; (y2 >> 8) - (y >> 8) 
	exx
	jr	z,Next0		; no need to check for (hl+1) == 0
	add	a,a		; 2 bytes per Y, cannot overflow (lineHeight < 64)
	ld	b,a		; b = segment length on screen

	ld	a,(hl)		; texData->color
	out	(0x9b),a	; clr   first pixel needs to be send separately

	ld	a,0xf0		; HMMC
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd

	djnz	hmmc4		; always more than 1 pixel
	; cannot fall-through

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
	jr	z,Next1		; no need to check for (hl+1)==0 (last segment is always visible)
	add	a,a		; 2 bytes (4 pixels) per Y, cannot overflow
	ld	b,a		; b = segment length (on screen) (2*N, with N >= 1)

hmmc4:	ld	a,(hl)		; texData: color
hmmc3:	out	(0x9b),a	; clr
	djnz	hmmc3

hmmc2:	inc	hl
	ld	a,(hl)		; texData->length
	or	a
	jr	nz,DoWhile1

	; -- floor segment
floor:	ld	a,c		; new lineHeight
	cp	d		; old lineHeight
	jr	nc,TexEnd	; new >= old -> no need to draw floor pixels

	ld	a,d		; old lineHeight
	sub	c		; new lineHeight
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a		; ny

	ld	a,_FLOOR
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
	; height, so there are no ceiling or floor pixels.
	; Or in other words: we need to draw exactly 128 texture pixels.

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
	ld	a,38+128
	out	(0x99),a	; dy
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

	; y = (Hscr - lineHeight) << 8
	ld	a,128		; full screen height
	out	(0x99),a
	ld	hl,64		; carry-flag is already clear
	sbc	hl,bc		; hl = 64 - lineHeight
	ld	b,l
	ld	c,0		;   bc = (64 - lineHeight) << 8   (lower 16 bits)
	ex	de,hl		; d:bc = (64 - lineHeight) << 8   (full 24 bits)
	dec	hl		; hl = texData-1  (doesn't change flags)
	ld	a,42+128
	out	(0x99),a	; NY
	jr	z,TopDone0	; lineHeight == 64 -> no need to skip texels

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

	jp	nz,LastSegment0	; more than 256 Y -> draw 128 Y
	ld	a,b
	or	a
	jr	z,TopDone0	; no need to draw partial segment (at top of screen)

	cp	128
	jp	nc,LastSegment0	; 128 or more Y -> draw 128 Y
	add	a,a		; 2 bytes per Y, cannot overflow
	ld	d,a		; d = length of first partial segment (register B is not free)

	ld	a,(hl)
	out	(0x9b),a		; clr

	ld	a,0xf0			; HMMC
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a		; cmd

	dec	d		; cannot become 0 at this point
	ld	a,(hl)
hmmc7:	out	(0x9b),a
	dec	d		; cannot use 'djnz' because reg B is not free
	jr	nz,hmmc7

TopDone:
	; at this point
	; bc  = y ~= lastDrawnY << 8  (exclusive) (includes fractional part)
	; hl  = texData-1  (one byte before the segment that should be drawn from start)
	; bc' = lineHeight * 4
	set	7,b		; b = last-drawn-y-coord (exclusive)
				; add 128, that way we can detect overflow and '>128'
				; using the carry-flag (so using only 1 test)
	ld	d,b		; d = last-drawn-y-coord (exclusive)

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
	add	a,c
	ld	c,a
	exx
	ld	a,h
	exx
	adc	a,b
	jr	c,LastSegment
	ld	b,a		; bc += hl'
	sub	d
	jr	z,ZoomLoop

	add	a,a		; 2 bytes per Y, cannot overflow
	ld	e,a		; e = #bytes
	ld	d,b		; d = newY

hmmc8:	ld	a,(hl)		; texData->color
hmmc5:	out	(0x9b),a	; clr
	dec	e
	jr	nz,hmmc5
	jr	ZoomLoop

LastSegment:
	; note: as soon as the last segment has more than one Y
	; it's cheaper to draw it using HMMV instead of HMMC
	xor	a
	sub	d		; a = 128 - (y - 128)  =  256 - y  =  0 - y 
	dec	a		; was at least 1
	ld	a,(hl)		; texData->color
	out	(0x9b),a	; clr
	jr	z,hmmc6		; was only one Y, finish HMMC command

	ld	a,0xc0		; otherwise finish with HMMV
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; CMD
	jp	TexEnd

hmmc6:	out	(0x9b),a	; clr
	jp	TexEnd


TopDone0:
	; this is similar to TopDone (above) except that the HMMC command is
	; not yet started
	ld	b,128
	ld	d,b
ZoomLoop0:
	inc	hl
	ld	a,(hl)		; texData->length
	inc	hl
	exx
	ld	l,a
	ld	h,0		; hl' = zero-extend(length)
	muluw_hl_bc		; de':hl' = RLE-length * lineHeight * 4
	ld	a,l
	exx
	jr	c,LastSegment0	; carry set -> de' != 0 (result of muluw didn't fit in 16-bit)
	add	a,c
	ld	c,a
	exx
	ld	a,h
	exx
	adc	a,b
	jr	c,LastSegment0
	ld	b,a		; bc += hl'
	sub	d
	jr	z,ZoomLoop0

	add	a,a		; 2 bytes per Y, cannot overflow
	ld	e,a		; e = #bytes
	ld	d,b		; d = newY

	ld	a,(hl)
	out	(0x9b),a	; first clr

	ld	a,0xf0		; hmmc
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd
	dec	e		; cannot become 0 at this point
	jr	hmmc8

LastSegment0:
	; we need to write 128 Y of the same color, use HMMV (even
	; though this is the hmmc renderer).
	ld	a,(hl)		; texData->color
	out	(0x9b),a	; first clr

	ld	a,0xc0		; hmmv
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; cmd
	jp	TexEnd
