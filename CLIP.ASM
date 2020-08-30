T_MIN	equ	64
T_MAX	equ	255-T_MIN

_clipMove:
	ld	bc,(_y)		; b = yh  c = yl
	ld	a,_mapWidth
	mulub_a_b		; hl = yh * mapWidth
	ld	de,(_x)		; d = xh  e = xl
	ld	a,e		; a = xl
	ld	e,d		; e = xh
	ld	d,_world/256
	add	hl,de		; hl = &world[yh][xh]
	ld	de,_mapWidth

	cp	T_MIN
	jr	c,West
	cp	T_MAX+1
	jr	nc,East

TestY:	; at this point xl is in range [T_MIN .. T_MAX]
	ld	a,c		; a = yl
	cp	T_MIN
	jr	c,North
	cp	T_MAX+1
	ret	c

South:	add	hl,de
	xor	a		; a = 0
	cp	(hl)		; world[yh+1][xh]
	ret	nc
YMax:	ld	a,T_MAX
	ld	(_y),a		; yl = T_MAX
	ret

North:	xor	a		; a = 0, clear carry flag
	sbc	hl,de
	cp	(hl)		; world[yh-1][xh]
	ret	nc
YMin:	ld	a,T_MIN
	ld	(_y),a		; yl = T_MIN
	ret

ClipWest:
	ld	a,T_MIN
	ld	(_x),a		; xl = T_MIN
	jr	TestY

West:	dec	hl		; hl = &world[yh][xh-1]
	ld	b,a		; b = xl
	xor	a		; a = 0
	cp	(hl)		; world[yh][xh-1]
	inc	hl
	jr	c,ClipWest
	ld	a,c		; a = yl
	cp	T_MIN
	jr	c,NorthWest
	cp	T_MAX+1
	ret	c

SouthWest:
	add	hl,de
	xor	a		; a = 0
	cp	(hl)		; world[yh+1][xh]
	jr	c,YMax
	dec	hl
	cp	(hl)		; world[yh+1][xh-1]
	ret	nc
	ld	a,c
	cpl			; a = 255 - yl
	cp	b		; (255-yl) - xl
	jr	nc,YMax		; -> (256-yl) >= xl
XMin:	ld	a,T_MIN
	ld	(_x),a		; xl = T_MIN
	ret

NorthWest:
	xor	a		; a = 0, clear carry flag
	sbc	hl,de
	cp	(hl)		; world[yh-1][xh]
	jr	c,YMin
	dec	hl
	cp	(hl)		; world[yh-1][xh-1]
	ret	nc
	ld	a,b		; xl
	cp	c		; yl
	jr	c,YMin		; -> yl > xl
	jr	XMin

ClipEast:
	ld	a,T_MAX
	ld	(_x),a		; xl = T_MAX
	jr	TestY

East:	inc	hl		; hl = &world[yh][xh+1]
	ld	b,a		; b = xl
	xor	a		; a = 0
	cp	(hl)		; world[yh][xh+1]
	dec	hl
	jr	c,ClipEast
	ld	a,c		; a = yl
	cp	T_MIN
	jr	c,NorthEast
	cp	T_MAX+1
	ret	c

SouthEast:
	add	hl,de
	xor	a		; a = 0
	cp	(hl)		; world[yh+1][xh]
	jr	c,YMax
	inc	hl
	cp	(hl)		; world[yh+1][xh+1]
	ret	nc
	ld	a,c		; yl
	cp	b		; xl
	jr	c,YMax		; -> xl > yl  or (255 - xl) < (255 - yl)
XMax:	ld	a,T_MAX
	ld	(_x),a
	ret

NorthEast:
	xor	a		; a = 0, clear carry
	sbc	hl,de
	cp	(hl)		; world[yh-1][xh]
	jr	c,YMin
	inc	hl
	cp	(hl)		; world[yh-1][xh+1]
	ret	nc
	ld	a,b
	cpl			; 255 - xl
	cp	c		; yl
	jr	c,YMin		; -> (255-xl) < yl
	jr	XMax
