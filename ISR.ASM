	psect text,class=CODE

_jiffy	equ	0xfc9e

; Install custom ISR
;  void initISR(void (*fun)(void));
	
	global _initISR
	
_initISR:
	di
	ld	a,2
	out	(0x99),a
	ld	(CallMove),de

	ld	a,(0x0038+0)
	ld	hl,(0x0038+1)
	ld	(saveISR+0),a
	ld	(saveISR+1),hl	; store original ISR address

	ld	a,0xC3		; JP instruction
	ld	hl,_myISR
	ld	(0x0038+0),a
	ld	(0x0038+1),hl	; install custom ISR

	ld	a,15+128
	ei
	out	(0x99),a	; custom ISR needs S#2 as default status reg
	ret

; Restore default ISR
;  void restoreISR();
	
	global _restoreISR
	
_restoreISR:
	di
	xor	a
	out	(0x99),a

	ld	a,(saveISR+0)
	ld	hl,(saveISR+1)
	ld	(0x0038+0),a
	ld	(0x0038+1),hl	; install custom ISR
	
	ld	a,15+128
	ei
	out	(0x99),a	; original ISR needs S#0 as default status reg
	ret



_myISR:	; when ISR is entered, CPU is already in 'DI' mode
	push	af
	xor	a
	out	(0x99),a
	push	bc
	push	de
	push	hl
	push	ix
	push	iy
	ld	a,15+128
	out	(0x99),a	; select S#0

	exx
	push	bc
	push	de
	push	hl
	ex	af,af'
	push	af

	in	a,(0x99)	; we must read VDP S#0
	or	a
	jp	p,noVDPIRQ	; check bit 7 

	ld	hl,(_jiffy)
	inc	hl
	ld	(_jiffy),hl	; needed for 'fps' calculations

	; do custom ISR stuff
	;  e.g. the movement stuff
	ld	hl,return
	push	hl
	ld	hl,(CallMove)
	jp	(hl)		; simulate call
return:

noVDPIRQ:
	pop	af
	ex	af,af'
	pop	hl
	pop	de
	pop	bc
	exx
	ld	a,2
	out	(0x99),a
	pop	iy
	pop	ix
	pop	hl
	pop	de
	pop	bc
	ld	a,15+128
	out	(0x99),a	; select S#2

	pop	af
	ei			; must be last instruction before ret
	ret


	psect		bss
saveISR:
	ds 3
CallMove:
	ds	2
	
