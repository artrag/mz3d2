	psect	text,class=CODE

; The mouse is read by 4 times reading a joystick port. Bits 3-0 of PSG
; register PSG#14 then read in sequence:
;   high part of X-offset (bit 7-4)
;   low  part of X-offset (bit 3-0)
;   high part of Y-offset (bit 7-4)
;   low  part of Y-offset (bit 3-0)
; All offsets are negative, or in other words: positive X is to the left
; and psoitive Y is up.
;
; Bit 4 (for port A) has to be inverted between each read, see source
; for details.

	global _getmouse
_getmouse:
	ld    de,0x9310		; read mouse in part A (see below)

; Read mouse:
;  input: DE = <magic values to select port>
;     to read port A:  D = &B10010011  E = &B00010000
;                  B:  D = &B11101100  E = &B00100000
;  output: H = X-offset
;          L = Y-offset
wait1	equ	10		; delay value
wait2	equ	30		; delay value

GTMOUS:	ld	b,wait2		; first time wait longer
	call	GTOFS2		; read bits 7-4 of X-offset
	rlca
	rlca
	rlca
	rlca
	ld	c,a
	call	GTOFST		; read bits 3-0 of X-offset
	or	c
	ld	h,a		; h = full X-offset
	call	GTOFST		; read bits 7-4 of Y-offset
	rlca
	rlca
	rlca
	rlca
	ld	c,a
	call	GTOFST		; read bits 3-0 of Y-offset
	or	c
	ld	l,a		; l = full Y-offset
	ret

GTOFST:	ld	b,wait1
GTOFS2:	ld	a,15
	out	(0xa0),a
	ld	a,d
	out	(0xa1),a	; toggle strobe pin
	xor	e
	ld	d,a
wait:	djnz	wait		; wait a while, (mouse is a slow device)
	ld	a,14
	out	(0xa0),a
	in	a,(0xa2)
	and	0x0f
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;0        Input joystick pin 1      (up)
;1        Input joystick pin 2      (down)
;2        Input joystick pin 3      (left)
;3        Input joystick pin 4      (right)
;4        Input joystick pin 6      (trigger A)
;5        Input joystick pin 7      (trigger B)

	global _joy
_joy:	ld	a,15
	out	(0xa0),a	; select PSG#15
	in	a,(0xa2)
	and	255-64
	out	(0xa1),a	; set joystick in port 1
	ld	a,14
	out	(0xa0),a	; select PSG#14
	in	a,(0xa2)
	ld	l,a
	ret


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; row/bit|    7     6     5     4     3     2     1     0
; -------+--------------------------------------------------
;    0   |    7     6     5     4     3     2     1     0
;    1   |    ;     ]     [     \     =     -     9     8
;    2   |    B     A    ???    /     .     ,     '     `
;    3   |    J     I     H     G     F     E     D     C
;    4   |    R     Q     P     O     N     M     L     K
;    5   |    Z     Y     X     W     V     U     T     S
;    6   |   F3    F2    F1   CODE   CAP  GRAPH CTRL  SHIFT
;    7   |   RET   SEL   BS   STOP   TAB   ESC   F5    F4
;    8   |  RIGHT DOWN   UP   LEFT   DEL   INS  HOME  SPACE
;    9   |    4     3     2     1     0     /     +     *
;   10   |    .     ,     -     9     8     7     6     5
;   11   |                           NO          YES     
;
; checkkbd: ckeck keyboard line
; in:  E = row
; out: L = bit pattern (1 = not pressed)
;
	global _checkkbd
_checkkbd:
	in	a,(0xaa)
	and	0xf0		; upper 4 bits should be preserved
	or	e
	out	(0xaa),a
	in	a,(0xa9)
	ld	l,a
	ret
