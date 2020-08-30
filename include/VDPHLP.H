#include <hitech.h>


/////////////////////////////////////////////////////////
// General definitions for rendering
/////////////////////////////////////////////////////////

#define Xres 	4
#define Yres 	1

#define Wscr	256
#define Hscr	128

#define Ntex 9
#define Nsprt 44*2

#define CEIL 0xFF
#define FLOOR 0x11

#define WALL_HEIGHT 64

// World
#define mapWidth  48   // preferably a power of 2 (but not required)
#define mapHeight 48

/////////////////////////////////////////////////////////
// General helper for ASM code
/////////////////////////////////////////////////////////

#asm

; Only use this version when the standard ISR is active
wait_ce		MACRO
	ld	a,2		; wait VDPready
	di
	out	(0x99),a	; select S#2
	ld	a,15+128
	out	(0x99),a
1:	in	a,(0x99)
	rra
	jr	c,1b
	xor	a
	out	(0x99),a
	ld	a,15+128
	ei
	out	(0x99),a	; select S#0
	ENDM


muluw_hl_bc macro
	db 0xed,0xc3	; de:hl <- hl * bc
	endm

mulub_a_b   macro
	db 0xed,0xc1	; hl <- a * b
	endm

mulub_a_c   macro
	db 0xed,0xc9	; hl <- a * c
	endm

mulub_a_d   macro
	db 0xed,0xd1	; hl <- a * d
	endm

mulub_a_e   macro
	db 0xed,0xd9	; hl <- a * e
	endm

#endasm

#define vdp_reg(reg,dat) outp(0x99,(dat));outp(0x99,(reg)|128);
#define wait_CE() 	asm("wait_ce");

//typedef unsigned char uchar;  //  8-bit unsigned
typedef unsigned int  uint;   // 16-bit unsigned

struct commands {
	uint  sx, sy;	// 32
	uint  dx, dy;	// 36
	uint  nx, ny;	// 40
            uchar   clr;	//44
            uchar   arg;	//45
            uchar   cmd;	//46
        };

/////////////////////////////////////////////////////////
// Actual rendering functions
/////////////////////////////////////////////////////////


// void 	texColRender(uchar x, uint lineHeight,uint tex);

void 	hmmvFlat(uint color_x, uint lineHeight);

void 	hmmvTexRender(uchar x, uint lineHeight, uchar* texData);
void 	hmmcTexRender(uchar x, uint lineHeight, uchar* texData);

void	swap_buffer(void);
void send_vdpcmd(struct commands* cmd);
void	cmd_cls(void);
void	screen_int(void);

void 	vtrace0(uchar sprt_type);
void	vtrace1(uint lineHeight,uchar	x,uchar	tex);

void 	hmmvSprite(uchar x, uint lineHeight, uchar* texData);
void 	hmmvVtrace1(uchar* texData, uint lineHeight_x);
void 	hmmcVtrace1(uchar* texData, uint lineHeight_x);

void 	vdp_setup0(void);

void	pset(uchar x,uchar y,uchar color,uchar page);
extern char	workpage;

