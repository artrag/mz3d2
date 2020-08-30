	psect	text,class=CODE

	global _RLEData,_workpage

mulub_a_c   macro
	db 0xED,0xC9	; hl <- a * c
	endm


; void hmmcVtrace1(uchar* texData, uint lineHeight_x);
;   call as
;      hmmcVtrace1(texData, lineHeight | (x << 8));
;
; Input: de = texData-pointer
;        c  = lineHeight   must be strictly smaller than 64
;        b  = x-coord
;
; Preconditions:
;    VDP R#17 = 44 (CLR)
;    VDP R#36 (NX) = 1

; Pseudo-code:
;	wait_CE
;	write DX
;
;  loop0:
;	get RLE-length, if == 0: goto end2
;	calc screen_length, if == 0: goto loop0
;	if transparent: goto loop0
;	write NY = 255  // too big
;	write DY
;	write CLR
;	write CMD = HMMC
;	screen_length -= 1, if == 0: goto loop2
;	goto draw
;
;  loop1:
;	get RLE-length, if == 0: goto end
;	calc screen_length, if == 0: goto loop1
;	if transparent: goto loop1
;	write DY  // change DY with a command in progress
;	          // TODO does this work correctly on real HW?
;	goto draw
;
;  loop2:
;	get RLE-length, if == 0: goto end
;	calc screen-length, if == 0: goto loop2
;	if transparent: goto loop1
;  draw:
;	loop screen-length: write clr
;	goto loop2
;
;  end:
;	write CMD = STOP  // because we wrote a too large value for NY
;  end2:
;	return

	global _hmmcVtrace1
_hmmcVtrace1:
1:	in	a,(0x99)
	rrca
	jr	c,1b		; wait for CE

	di
	push	ix		; store ix
	ld	ix,0		; because 'ld ix,sp' instruction doesn't exist
	add	ix,sp		; ix = sp  (to be able to restore sp later)
	ld	a,b		; x-coord
	out	(0x99),a	; no need to mask bit0, the VDP ignores it anyway
	and	0xfc		; clear lower 2 bits
	ld	l,a
	ld	a,(_workpage)	; 0 or 1
	add	a,a		; 0 or 2
	add	a,l		; cannot overflow
	ld	h,_RLEData/256
	ld	l,a		; hl = &RLEData[x/4][workpage].low

	inc	l
	ld	(hl),0xff	; RLEData[x][workpage] = 0xff..

	dec	h
	;ld	(hl),0		; lineHeight[.][.].high  must already be 0
	dec	l
	ld	(hl),c		; lineHeight[.][.] = lineHeight

	ex	de,hl		; hl = texData
	ld	sp,hl		; sp = texData

	ld	a,64
	sub	c		; lineHeight
	ld	d,a
	ld	e,0		; de = (64 - lineHeight) << 8
	sla	c
	sla	c		; c = lineHeight * 4 (no overflow)
	ld	a,36+128
	out	(0x99),a	; dx

loop0:	; in this loop we have to set CLR before starting the command
	pop	hl		; l = len   h = color
	ld	a,l
	or	a
	jr	z,vtraceend2	; len == 0 -> done   (HMMC cmd not yet started)
	ld	b,h		; b = color
	mulub_a_c		; hl = a * c = len * lineHeight * 4
	add	hl,de		;
	ex	de,hl		; de = newY   hl = oldY
	ld	a,d
	sub	h
	jr	z,loop0		; segment not visible (too small after scaling)
	ld	l,a		; l = count
	ld	a,b
	or	a
	jr	z,loop0		; color == 0 -> transparent segment
	ld	a,255		; too big (but ok)
	out	(0x99),a
	ld	a,42+128
	out	(0x99),a	; NY
	ld	a,h		; oldY
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a	; DY
	ld	a,b
	out	(0x9b),a	; CLR
	ld	a,0xf0		; HMMC
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; CMD
	dec	l		; count -= 1
	jr	z,loop2		; only 1 pixel -> next segment (1 pixel already drawn)

draw2:	ld	a,b		; a = color
draw1:	ld	b,l		; b = count (at least 1)
draw:	out	(0x9b),a
	djnz	draw

loop2:	; in this loop we _DON'T_ have to set the DY VDP register
	pop	hl		; l = len   h = color
	ld	a,l
	or	a
	jr	z,vtraceend	; len == 0 -> done
	ld	b,h		; b = color
	mulub_a_c		; hl = a * c = len * lineHeight * 4
	add	hl,de		;
	ex	de,hl		; de = newY   hl = oldY
	ld	a,d
	sub	h
	jr	z,loop2		; segment not visible (too small after scaling)
	ld	l,a		; l = count
	ld	a,b		; a = color
	or	a		; transparent? (and at least 1 pixel in
	jr	nz,draw1	; visible size) -> update DY on next segment

loop1:	; in this loop we _DO_ have to set the DY VDP register (prev was transparent)
	pop	hl		; l = len   h = color
	ld	a,l
	or	a
	jr	z,vtraceend	; len == 0 -> done
	ld	b,h		; b = color
	mulub_a_c		; hl = a * c = len * lineHeight * 4
	add	hl,de		;
	ex	de,hl		; de = newY   hl = oldY
	ld	a,d
	sub	h
	jr	z,loop1		; segment not visible (too small after scaling)
	ld	l,a		; l = count
	ld	a,b		; a = color
	or	a
	jr	z,loop1		; color == 0 -> transparent segment
	ld	a,h		; oldY
	out	(0x99),a
	ld	a,38+128
	out	(0x99),a	; DY
	jr	draw2

vtraceend: ; on jump to this label, a == 0
	out	(0x99),a
	ld	a,46+128
	out	(0x99),a	; CMD = STOP, needed because we set NY too high
vtraceend2:
	ld	sp,ix		; restore sp
	pop	ix		; restore ix
	ei
	ret

