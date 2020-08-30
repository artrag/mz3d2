#include <stdio.h>
#include <conio.h>
#include <stdlib.h>

#include <math.h>
#include <sys.h>
#include <string.h>
#include <hitech.h>
#include <intrpt.h>
#include "msx2lib.h"
#include "vdphlp.h"

void 	grph_init(void);

void	ddamain(void);
void	rnd_maze(void);
uchar	test_r800(void);
void    setr800(void);
char	testemulation(void);
void 	loaddata(char name[]);

extern char NoMouse;		// choose configuration for commands 

void print(const char* str);
#asm
_print:
	ex	de,hl
1:	ld	a,(hl)
	or	a
	ret	z
	exx		; shadow registers and IX,IY are preserved over DOS calls
	ld	c,2	; console output
	ld	e,a
	call	5
	exx
	inc	hl
	jr	1b
#endasm

void error2(const char* message, const char* argument) {
	scr(0);
	print(message);
	print(argument);
	print("\r\n");
	exit(1);
}
void error(const char* message) {
	error2(message," ");
}

void main(int argc, char *argv[]) {	
	uchar i;

	if (test_r800() < 3) {
		error("msxTR only - sorry!");
	}
	
	setr800();
	/*
	if (testemulation()) {
		error("Use real HW or better emulators (e.g. openmsx 0.8.1 or newer) - sorry!");
	}
	*/
	
	NoMouse = 1;
	if (NoMouse) {
		print("Press -now- CRTL for mouse support\r\n");
		for (i = 0; i < 60; ++i) {
			if (!(checkkbd (6) & 2)) { //CTRL
				NoMouse = 0;
				break;
			}
			asm("halt");
		}
	}
	
	grph_init();
		
	if (argc > 1) {
		if (strcmp(argv[1], "-L") == 0) {
			loaddata(argv[2]);
		}
	} else {
		loaddata("dungeon.txt");
	}
	
	scr(5);
	SetPalette();
	bordercolor(0);
	cmd_cls();
	ddamain();  
	scr(0);
}



#asm
rdslt	equ	0x000c
CALSLT	equ	0x001c
chgcpu	equ	0x0180	; change cpu mode
exttbl	equ	0xfcc1	; main rom slot

; Detect Turbo-R
	global _test_r800
_test_r800:
	ld	a,(exttbl)	; test msx1, msx2, msx2+
	ld	hl,0x002d
	call	rdslt
	ld	l,a
	ret


; Switch to r800 rom mode
	global _setr800
_setr800:
	push	ix
	push	iy
	ld	a,0x81            ;select r800 rom mode
	ld	iy,(exttbl-1)
	ld	ix,chgcpu
	call	CALSLT
	pop	iy
	pop	ix
	ret

; Check for buggy R800 emulation
	global _testemulation
_testemulation:
	ld   hl,0x100
	ld   b,h
	ld   c,l            ; 0x100 * 0x100 -> doesn't fit in 16-bit
	xor a
	muluw_hl_bc
	ret c              	; on a real R800 this will set the carry flag
	ld l,1
	ret		; carry-flag beh

#endasm
