	psect text,class=CODE

muluw_hl_bc macro
            db 0xed,0xc3	;de:hl<-hl*bc
            endm
			
mulub_a_b   macro           
			db 0xED,0xC1 	;hl<- a*b
			endm
			
mulub_a_c   macro           
			db 0xED,0xC9 	;hl<- a*c
			endm

	global cosine_low
	global _direction
	global _side
	global _x,_y
	global _dist

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;
	; C prototipe
	;
	; uint tex_coord(void);
	
	global _tex_coord
_tex_coord:
	ld	hl,(_direction)	; h = quadrant  l = a
	ld	a,(_side)
	and	1
	jr	z,1f
	ld	de,(_x)		; tex = x
	inc	h		; ++quadrant
	jr	2f
1:	ld	de,(_y)		; tex = y
2:	push	de		; de = tex

	ld	a,h		; a= quadrant
	ld	h,cosine_low/256; hl = &cosine_low[a]
	and	3
	jr	z,tex0
	cp	2
	jr	c,tex1
	jr	z,tex2
	jr	tex3

tex2:
	ld	a,l		; a = direction & 255
	neg
	jr	z,texend0	; a == 0?
	ld	l,a		; hl = &cosine_low[256 - a]
	;jr	tex3

tex3:
	ld	c,(hl)
	inc	h
	ld	b,(hl)		; bc = cosine[a]
	ld	hl,(_dist)
	muluw_hl_bc		; de = (cosine[..] * dist) >> 16
	pop	hl		; hl = tex
	or	a
	sbc	hl,de
	ret			;return value in hl

tex0:
	ld	a,l		; a = direction & 255
	neg
	jr	z,texend0	; a == 0?
	ld	l,a		; hl = &cosine_low[256 - a]
	;jr	tex1

tex1:	ld	c,(hl)
	inc	h
	ld	b,(hl)		; bc = cosine[a]
	ld	hl,(_dist)
	muluw_hl_bc		; de = (cosine[..] * dist) >> 16
	pop	hl		; hl = tex
	add	hl,de
	ret			;  return value in hl

texend0:
	pop	hl		; hl = tex
	ret			;  return value in hl
