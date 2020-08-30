
	psect text,class=CODE


; muluw .hl,.bc            |ED C3 ;de:hl<-hl*bc
; mulub .a,.b              |ED C1 ;   hl<- a*b
; mulub .a,.c              |ED C9
; mulub .a,.d              |ED D1
; mulub .a,.e              |ED D9

muluw_hl_bc macro
	db 0xed,0xc3	;de:hl<-hl*bc
	endm

mulub_a_b   macro           
	db 0xED,0xC1 	;hl<- a*b
	endm
 
	global cosine_low
	global secant_low

	global _x,_y
	global _alpha
	global _fovAngleP
	global _distP
	global _mapWidth
	global _world
	global _direction
	global _color
	global _side
	global _height
	global _dist
	
; //// global variables:
;
; // input for DDA asm routine:
;   FP_8_8 x;         // x-coordinate player position
;   FP_8_8 y;         // y-coordinate player position
;   ANGLE alpha;      // viewing direction
;   ANGLE* fovAngleP; // should be initialized to start of fovAngles array
;   FP_8_8* distP;    // should be initialized to start of dists array
;

; // output from DDA asm routine: 
;   FP_8_8 dists[NDIRS]; // perpendicular distance per column (one element filled in)
;   uchar color;         // 'color' of the hit world-block
;   uchar side;          // side on which the block was hit
;   uint height;         // visible height for the column
;   // the input variables fovAngleP and distP are updated
;   ANGLE direction;     // required for the texture coord calculation
;                        //  (split in upper and lower 8-bit part)
;
;
; //// Use the asm routine like this:
;
;   void draw()
;   {
;	vdp_setup0();
;	fovAngleP = fovAngles;
;	distP = dists;
;	for (i = 0; i < NDIRS; ++i) {
;		ASM: <the asm routine below>
;		ASM: this replaces lines 207-352 from the C code
;		ASM: in the future more will be moved from C to asm
;
;		C: asm routine above calculates the variables:
;		C:    color, side, height, direction
;		C: (optionally) calculate texture coord
;		C:    the variables 'a' and 'quadrant' should be
;		C:    replaced with the lower/upper 8 bits of 'direction'
;               C:    (upper part still needs '& 3').
;		C: actually draw the column
;	}
;   }
;

	global _fast_dda
_fast_dda:
	push ix

	; TODO make _mapWidth a power of 2
	ld	a,(_y+1)	; a = y >> 8
	ld	b,_mapWidth
	mulub_a_b		; hl = (y >> 8) * mapWidth
	ld	bc,(_x+1)	; c = x >> 8
	ld	b,_world/256
	add	hl,bc
	push	hl		; hl = &world[y >> 8][x >> 8]

	ld	hl,(_fovAngleP)
	ld	e,(hl)
	inc	hl
	ld	d,(hl)		; de = fovAngle
	ld	hl,(_alpha)
	add	hl,de		; hl = alpha + fovAngle
	ld	(_direction),hl

	; switch (quadrant)
	ld	a,h		; hl = direction
	and	3		; a = quadrant
	jp	z,dda_0		; case 0
	cp	2
	jp	c,dda_1		; case 1
	jr	z,dda_2		; case 2
	;jr	dda_3		; case 3


dda_3:	; case 3
	ld	a,l		; a = direction & 255
	neg			; 256 - a
	ld	bc,32767
	jr	z,1f		; a == 0?
	ld	h,secant_low/256
	ld	l,a		; hl = &secant_low[256-a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[256-a]
	ld	b,(hl)
1:	push	bc		; bc = lenX

	ld	a,(_x)		; a = xfrac
	neg
	jr	z,1f		; a == 0?
	ld	h,0
	ld	l,a
	muluw_hl_bc		; de:hl = (256 - xfrac) * lenX
	ld	c,h		; bc = de:hl >> 8
	ld	b,e
1:	push	bc		; bc = distX

	ld	hl,(_direction)	; l = direction & 255
	ld	h,secant_low/256; hl = &secant_low[a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[a]
	ld	b,(hl)
	push	bc		; bc = lenY

	ld	hl,(_y)		; l = yfrac
	ld	h,0
	muluw_hl_bc		; de:hl = yfrac * lenY
	ld	l,h
	ld	h,e		; hl = distY = de:hl >> 8

	pop	de		; de = lenY
	exx
	pop	ix		; ix = distX
	pop	de		; de' = lenX
	pop	hl		; hl' = worldP
	ld	bc,-_mapWidth	; bc' = -mapWidth

	; while (1)
loop3b:	exx
; loop3:	ld	a,ixh		; distX.high
loop3:	db 0xdd
	ld	a,h		; distX.high
	cp	h		; distY.high
	jr	c,2f		; ->distX smaller
	jr	nz,1f		; ->distY smaller
	; ld	a,ixl		; distX.low
	db 0xdd
	ld	a,l		; distX.low
	cp	l		; distY.low
	jr	c,2f		; -> distX smaller

1:	; distX >= distY
	exx
	add	hl,bc		; worldP -= mapWidth
	ld	a,(hl)		; a = color
	or	a
	exx
	jp	nz,end3
	add	hl,de		; distY += lenY
	jr	loop3

2:	; distX < distY
	exx
	inc	hl		; worldP += 1
	ld	a,(hl)		; a = color
	or	a
	jp	nz,end0
	add	ix,de		; distX += lenX
	jr	loop3b


dda_2:	; case 2
	ld	h,secant_low/256; hl = &secant_low[a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[a]
	ld	b,(hl)
	push	bc		; bc = lenX

	ld	hl,(_x)		; l = xfrac
	ld	h,0
	muluw_hl_bc		; de:hl = xfrac * lenX
	ld	b,e
	ld	c,h		; bc = de:hl >> 8
	push	bc		; bc = distX

	ld	a,(_direction)	; a = direction & 255
	neg
	ld	bc,32767
	jr	z,1f		; a == 0?
	ld	h,secant_low/256
	ld	l,a		; hl = &secant_low[256 - a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[256 - a]
	ld	b,(hl)
1:	push	bc		; bc = lenY

	ld	hl,(_y)		; l = yfrac
	ld	h,0
	muluw_hl_bc		; de:hl = yfrac * lenY
	ld	l,h
	ld	h,e		; hl = distY = de:hl >> 8

	pop	de		; de = lenY
	exx
	pop	ix		; ix = distX
	pop	de		; de' = lenX
	pop	hl		; hl' = worldP
	ld	bc,-_mapWidth	; bc' = -mapWidth

	; while (1)
loop2b:	exx
; loop2:	ld	a,ixh		; distX.high
loop2:	db 0xdd
	ld	a,h		; distX.high
	cp	h		; distY.high
	jr	c,2f		; ->distX smaller
	jr	nz,1f		; ->distY smaller
	; ld	a,ixl		; distX.low
	db 0xdd
	ld	a,l		; distX.low
	cp	l		; distY.low
	jr	c,2f		; -> distX smaller

1:	; distX >= distY
	exx
	add	hl,bc		; worldP -= mapWidth
	ld	a,(hl)		; a = color
	or	a
	exx
	jp	nz,end3
	add	hl,de		; distY += lenY
	jr	loop2

2:	; distX < distY
	exx
	dec	hl		; worldP -= 1
	ld	a,(hl)		; a = color
	or	a
	jp	nz,end2
	add	ix,de		; distX += lenX
	jr	loop2b


dda_1:	; case 1
	ld	a,l		; a = direction & 255
	neg
	ld	bc,32767
	jr	z,1f		; a == 0?
	ld	h,secant_low/256
	ld	l,a		; hl = &secant_low[a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[a]
	ld	b,(hl)
1:	push	bc		; bc = lenX

	ld	hl,(_x)		; l = xfrac
	ld	h,0
	muluw_hl_bc		; de:hl = xfrac * lenX
	ld	b,e
	ld	c,h
	push	bc		; bc = distX

	ld	hl,(_direction) ; l = direction & 255
	ld	h,secant_low/256; hl = &secant_low[a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[a]
	ld	b,(hl)
	push	bc		; bc = lenY

	ld	a,(_y)		; a = yfrac
	neg
	jr	z,1f
	ld	h,0
	ld	l,a
	muluw_hl_bc
	ld	b,e
	ld	c,h
1:	ld	h,b
	ld	l,c		; hl = distY

	pop	de		; de = lenY
	exx
	pop	ix		; ix = distX
	pop	de		; de' = lenX
	pop	hl		; hl' = worldP
	ld	bc,_mapWidth	; bc' = mapWidth
	
	; while (1)
loop1b:	exx
;loop1:  ld	a,ixh		; distX.high
loop1:	db 0xdd
	ld	a,h		; distX.high
	cp	h		; distY.high
	jr	c,2f		; ->distX smaller
	jr	nz,1f		; ->distY smaller
	; ld	a,ixl		; distX.low
	db 0xdd
	ld	a,l		; distX.low
	cp	l		; distY.low
	jr	c,2f		; -> distX smaller

1:	; distX >= distY
	exx
	add	hl,bc		; worldP += mapWidth
	ld	a,(hl)		; a = color
	or	a
	exx
	jr	nz,end1
	add	hl,de		; distY += lenY
	jr	loop1

2:	; distX < distY
	exx
	dec	hl		; worldP -= 1
	ld	a,(hl)		; a = color
	or	a
	jr	nz,end2
	add	ix,de		; distX += lenX
	jr	loop1b


dda_0:	; case 0
	ld	h,secant_low/256; hl = &secant_low[a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[a]
	ld	b,(hl)
	push	bc		; bc = lenX

	ld	a,(_x)		; a = xfrac
	neg
	jr	z,1f		; a == 0?
	ld	h,0
	ld	l,a
	muluw_hl_bc
	ld	b,e
	ld	c,h		; bc = de:hl >> 8
1:	push	bc		; bc = distX

	ld	a,(_direction)
	neg
	ld	bc,32767
	jr	z,1f
	ld	h,secant_low/256
	ld	l,a		; hl = &secant_low[256 - a]
	ld	c,(hl)
	inc	h		; hl = &secant_high[256 - a]
	ld	b,(hl)
1:	push	bc		; bc = lenY

	ld	a,(_y)		; a = yfrac
	neg
	jr	z,1f
	ld	h,0
	ld	l,a
	muluw_hl_bc
	ld	b,e
	ld	c,h
1:	ld	h,b
	ld	l,c		; hl = distY

	pop	de		; de = lenY
	exx
	pop	ix		; ix = distX
	pop	de		; de' = lenX
	pop	hl		; hl' = worldP
	ld	bc,_mapWidth	; bc' = mapWidth
	
	; while (1)
loop0b:	exx
; loop0:	ld	a,ixh		; distX.high
loop0:	db	0xdd
	ld	a,h		; distX.high
	cp	h		; distY.high
	jr	c,2f		; ->distX smaller
	jr	nz,1f		; ->distY smaller
	; ld	a,ixl		; distX.low
	db	0xdd
	ld	a,l		; distX.low
	cp	l		; distY.low
	jr	c,2f		; -> distX smaller

1:	; distX >= distY
	exx
	add	hl,bc		; worldP += mapWidth
	ld	a,(hl)		; a = color
	or	a
	exx
	jr	nz,end1
	add	hl,de		; distY += lenY
	jr	loop0

2:	; distX < distY
	exx
	inc	hl		; worldP += 1
	ld	a,(hl)		; a = color
	or	a
	jr	nz,end0
	add	ix,de		; distX += lenX
	jr	loop0b


end3:	ld	e,3		; e  = side = NORTH
	jr	end13

end2:	ld	e,2		; e  = side = EAST
	jr	end02

end1:	ld	e,1		; e  = side = SOUTH
end13:	ld	b,h
	ld	c,l		; bc = distY
	jr	ddaend

end0:	ld	e,0		; e = side = WEST

end02:	db 0xdd
	ld	b,h		; end02:	ld	b,ixh
	db	0xdd
	ld	c,l		; bc = distX
	;jr	ddaend

ddaend:	ld	(_color),a
	ld	a,e
	ld	(_side),a
	ld	(_dist),bc	; bc = non-perpendicular distance

	ld	hl,(_fovAngleP)
	ld	d,(hl)		; d = fovAngle & 255
	inc	hl
	ld	a,(hl)		; a = fovAngle >> 8
	inc	hl
	ld	(_fovAngleP),hl	; ++fovAngleP;
	or	a
	ld	a,d
	jr	z,1f
	neg
1:
	ld	h,cosine_low/256
	ld	l,a		; hl = &cosine_low[..]
	ld	a,(hl)		
	inc	h		; hl = &cosine_high[..]
	ld	h,(hl)
	ld	l,a		; hl = cosine(..)
	muluw_hl_bc		; de:hl = dist * cosine(..)

	; de = perpendicular distance
	ld	hl,(_distP)
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(_distP),hl	; *distP++ = dist


; Very specialized routine to calculate
;   HL = 0x4000 / DE  (clipped to [1 .. 16383])
; When DE is in range
; a) [0x0000 .. 0x0001] -> result is clipped to 16383
; b) [0x0002 .. 0x0080] -> (result 16 bit, remainder  8 bit,  14 iterations)
; c) [0x0081 .. 0x00FF] -> (result  8 bit, remainder  8 bit, 6+1 iterations)
; d) [0x0100 .. 0x3FFF] -> (result  8 bit, remainder 16 bit,   7 iterations)
; e) [0x4000 .. 0xFFFF] -> result is clipped to 1

Divide:
	ld	a,d
	or	a
	jr	z,divABC
	cp	0x21		; for correctness we need this from 0x40
	jr	nc,divE		;   for speed already do this from 0x21 (same result)

divD:	; 0x100 <= de < 0x4000
	ld	hl,128		; hl = remainder
	ld	a,1		; a  = quotient (bit 0 set, so we can later use 'cpl')
	ld	b,7		; possibly unroll 7x
2:	add	hl,hl
	sbc	hl,de
	jr	nc,1f
	add	hl,de
1:	adc	a,a
	djnz	2b
	ld	h,0
	jr	divend3		; l = cpl(a)

divE:	; de >= 0x4000  (or even  de >= 0x2100)
	ld	hl,1
	jr	divend

divABC:	; de < 0x100
	; Possible optimization: use LUT for small dividers
	;   ld	h,div_tab_low/256 ; 256-bytes aligned
	;   ld	l,e
	;   ld  a,(hl)
	;   inc	h
	;   ld	h,(hl)
	;   ld	l,a
	ld	a,e
	cp	128+1
	jr	c,divAB

divC:	; 0x80 < de < 0x100
	ld	b,6		; There are exactly 7 significant bits in the result,
				; (bit 6 is always 1), so handle 1st iteration special.
				; Possibly unroll next loop
	ld	l,2		; 'set' 'upper' quotient bit (still needs cpl and <<= 6)
	xor	a
	sub	e		; a = 256 - e
3:	add	a,a
	jr	c,1f		; we actually need 9 bits  ..  or 8 bits + carry
	cp	e
	jr	c,2f
1:	sub	e
	or	a		; clear carry flag (needed when jumped to label '1')
2:	rl	l
	djnz	3b
	ld	h,0
	jr	divend2		; l = cpl(l)

divA:	; de <= 1 
	ld	hl,16383
	jr	divend

divAB:	; de <= 0x80
	cp	2
	jr	c,divA

divB:	; 2 <= de <= 0x80
	ld	hl,3		; lower 2 bits will be <<= 14 and 'cpl'
	ld	a,1
	ld	b,14		; possibly unroll
1:	add	a,a
	cp	e
	jr	c,2f
	sub	e
2:	adc	hl,hl
	djnz	1b
	ld	a,h
	cpl
	ld	h,a
divend2:
	ld	a,l
divend3:
	cpl
	ld	l,a

divend:	ld	(_height),hl
	pop	ix
	ret

