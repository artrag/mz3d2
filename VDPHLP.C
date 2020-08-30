#include	<hitech.h>
#include	"msx2lib.h"
#include	"vdphlp.h"



// These two arrays must be next to each other in memory and alligned to 100h
extern uint   lineheight[Wscr/Xres][2]; // 256 bytes
extern uchar* RLEData   [Wscr/Xres][2]; // 256 bytes   = color for flat shaded walls

#asm
_CEIL 	equ CEIL
_FLOOR 	equ FLOOR
	global _CEIL,_FLOOR
#endasm


///////////////////////////////////////////////////////
///////////////////////////////////////////////////////   

char workpage;

void screen_int()
{
	/*for (int i = 0; i < 64; ++i) {
		lineheight[i][0] = lineheight[i][1] = 0xffff;
		RLEData	  [i][0] = RLEData   [i][1] = (uchar*)0xffff;
	}*/
#asm
	global _lineheight
	//memset(lineheight, 0xff, 512);
	ld	hl,_lineheight
	ld	de,_lineheight+1
	ld	bc,512-1
	ld	(hl),0xff
	ldir
#endasm
	
	setpage(0);
	workpage = 1;
}

void cmd_cls()
{
	int	i;
	static struct commands cls_cmd = {
		  0,     0,	// source
		  0,     0,	// destination
		256, 256*4,	// size
		  0, 0, 0xc0	// color, arg, HMMV
	};
	send_vdpcmd(&cls_cmd);

	cls_cmd.nx = 8;
	cls_cmd.ny = 8;

	cls_cmd.dy = 8+128;
	for	(i=0;i<16;i++) {
		cls_cmd.dx = i*8;
		cls_cmd.clr = i+i*16;
		send_vdpcmd(&cls_cmd);	
		}

	cls_cmd.dy = 8+128+256;
	for	(i=0;i<16;i++) {
		cls_cmd.dx = i*8;
		cls_cmd.clr = i+i*16;
		send_vdpcmd(&cls_cmd);	
		}
}

void swap_buffer()
{
	setpage(workpage);
	workpage ^= 1;
}


#asm
	global	_send_vdpcmd
_send_vdpcmd:
	ld	a,32
	di
	out	(0x99),a
	ex	de,hl
	ld	a,17+128
	out	(0x99),a	; R#17 = 32
	
	ld	bc,15*256+0x9b
	ld	a,2
	out	(0x99),a
	ld	a,15+128
	out	(0x99),a	; select S#2

1:	in	a,(0x99)
	rrca
	jr	c,1b

	otir			; send command

	xor	a
	out	(0x99),a
	ld	a,15+128
	ei
	out	(0x99),a	; select S#0
	ret
#endasm

///////////////////////////////////////////////////////
///////////////////////////////////////////////////////

void	vdp_setup0(void)
{
#asm
	ld	a,36
	di
	out	(0x99),a
	ld	a,17+128
	out	(0x99),a	; R#17 = 36

1:	in	a,(0x99)
	rrca
	jr	c,1b		; wait CE
	
	xor	a
	out	(0x9b),a	; dxl
	out	(0x9b),a	; dxh
	out	(0x9b),a	; dyl
	ld	a,(_workpage)
	out	(0x9b),a	; dyh
	ld	a,Xres		; nxl
	out	(0x9b),a	; nxl
	xor	a
	out	(0x9b),a	; nxh
	out	(0x9b),a	; nyl
	out	(0x9b),a	; nyh
	out	(0x9b),a	; clr
	out	(0x9b),a	; arg
	
	ld	a,44+128
	out	(0x99),a
	ld	a,17+128
	ei
	out	(0x99),a	; R#17: set to CLR (no increment)
#endasm
}

///////////////////////////////////////////////////////
///////////////////////////////////////////////////////

void	pset(uchar x,uchar y,uchar color,uchar page)
{
	wait_CE();

	asm(" di");
	vdp_reg(36,x);				// dxl
	vdp_reg(38,y);				// dyl
	vdp_reg(39,page);			// dyh
	vdp_reg(40,2);				// nxl
	vdp_reg(42,2);				// nyl
	vdp_reg(44,color+(color<<4));	// clr
	vdp_reg(46, 0xc0);             // HMMV
	asm(" ei");
}

///////////////////////////////////////////////////////
///////////////////////////////////////////////////////



uchar** pframe_odd;
uchar** pframe_even;
uchar* pseg_frame_odd;
uchar* pseg_frame_even;

extern uchar* rlesprite[][32];
extern uchar rlesegsprite[][32];

void vtrace0(uchar sprt_type) 
{
	uchar Anim_Frame = sprt_type<<1;

	pframe_even 	= &rlesprite[Anim_Frame	  ][0];
	pseg_frame_even = &rlesegsprite[Anim_Frame][0];

	pframe_odd  	= pframe_even   + 32;
	pseg_frame_odd	= pseg_frame_even + 32;

	#asm
		ld	a,2		; nx
		di
		out	(0x99),a
		ld	a,40+128
		ei
		out	(0x99),a
	#endasm
}

uchar* pp;
uint threshold;



void	set_seg(uchar seg);

void vtrace1(uint lineHeight, uchar x, uchar xtex)
{
	// The caller should take care that 'xtex <= 63'.
	// if (xtex > 63) xtex = 63;
	
	if (xtex&1)
	{
		xtex>>=1;		//0-31
		pp = pframe_odd[xtex]; 	if (!pp) return;
		set_seg(pseg_frame_odd[xtex]);	// activate sprite segment
	}
	else
	{
		xtex>>=1;		//0-31
		pp = pframe_even[xtex];	if (!pp) return;
		set_seg(pseg_frame_even[xtex]);	// activate sprite segment
	}
	
	threshold = *((uint*)pp);
	pp += 2;
	
	if ((lineHeight > threshold) ||
	    (lineHeight >= Hscr / 2)) {
		hmmvSprite(x, lineHeight, pp);
	} else {
		hmmcVtrace1(pp, lineHeight | (x << 8));
	}
}

///////////////////////////////////////////////////////
