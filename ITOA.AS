
	psect	text,class=CODE
	global	_printfps

mulub_a_e macro 
 db 0xed,0xd9 ; hl <- a * e 
 endm 
 
CALSLT equ 0x001c ;call ix in slot (iy) 
exttbl equ 0xfcc1 ;main rom slot 

_printfps:
	ld	hl,240
	ld	(0xfcb7),hl
	ld	hl,184
	ld	(0xfcb9),hl
	; trick for 8-bit unsigned division by 10:
	;   a / 10  ==  (a * 205) >> 11
	di
	xor	a
	out	(0x99),a
	push	ix
	push	iy
	ld	a,205
	ld	c,e
	mulub_a_e		; hl = 'fps' * 205
	ld	a,h		; a = ('fps' * 205) >> 8
	rrca
	rrca
	rrca
	and	0x1f		; a = (('fps' * 205) >> 8) >> 3 = 'fps' / 10
	ld	d,a		; d = 'fps' / 10

	add	a,a
	add	a,a
	add	a,a
		
	add	a,d		; * 9
	add	a,d		; *10
	sub	c		; a = (('fps / 10) * 10) - 'fps'
	ld	b,a		; b = -('fps' % 10)
	ld	a,15+128
	out	(0x99),a	; select S#0

	ld	a,d
	add	a,'0'
	ld     iy,(exttbl-1)
	ld     ix,0x8d
	call	CALSLT		; note: we trust that this doesn't change register B

	ld	a,'0'
	sub	b
	ld     iy,(exttbl-1)
	ld     ix,0x8d
	call	CALSLT

	ld	a,2
	out	(0x99),a
	pop	iy
	pop	ix
	ld	a,15+128
	ei
	out	(0x99),a	; select S#2
	ret	

	psect	bss,class=DATA
	global	_string
_string:
	defs	8
