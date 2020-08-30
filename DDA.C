#include <hitech.h>
#include <sys.h>
#include <intrpt.h>

#include <stdlib.h>
#include <float.h>
#include <math.h>
#include "msx2lib.h"
#include "vdphlp.h"

#include "clipmove.h"

void printfps(int fps);

uint fps;
uint framecount;
uint jiffy @ 0xFC9E;

// Rotation angles have 10 bit precision. 
//   8 bit is not enough
//   9 bit is mostly ok, but occasionally gives a (small) artifact
//   10 bit should be fine
// An additional advantage of using 10 bit is that the quadrant can be very
// easily obtained in Z80 code. Also per-quadrant look up tables (LUT) are
// easily indexed in Z80 code using 10 bit (is 8 bit per quadrant).

typedef uint ANGLE;
typedef char bool;

#define M_PI (3.14159265358979)

#define false 0
#define true 1

#define ANGLE_BITS  10
#define NR_ANGLES  (1 << ANGLE_BITS) 
#define Q1 (NR_ANGLES / 4)

// Fixed point datatypes
typedef uchar u8;       //  8 bit [0..256) step: 1
typedef uchar FP_0_8;   //  8 bit [0..  1) step: 1/256
typedef uint  FP_8_8;   // 16 bit [0..256) step: 1/256
typedef uint  FP_0_16;  // Unsigned fixed point 0.16 step: 1/65536
typedef  int  FP_S0_15; // Signed   fixed point 0.15
typedef  int  FP_S7_8;

// Number of rays cast per screen.
//  If this number is changed, the precision of ANGLE must be re-tuned.
#define NDIRS 64

extern uchar world[mapHeight][mapWidth];

//////////////////////////////////////////////////////////////////////
//
// Look up tables (LUT)
//
//////////////////////////////////////////////////////////////////////

// Correction angle (add to the view direction) per ray-cast-column
//   could be reduced to 8-bit and either sign-extend on use, or store
//   with an offset of +128
ANGLE fovAngles[NDIRS];

// cosine for 1st quadrant (all positive numbers)
//   cos(x) * 65536
FP_0_16 cosine[Q1] = {
	65535, 65533, 65528, 65521, 65511, 65499, 65484, 65467,
	65447, 65425, 65400, 65373, 65343, 65311, 65277, 65240,
	65200, 65159, 65114, 65067, 65018, 64967, 64912, 64856,
	64797, 64735, 64672, 64605, 64536, 64465, 64392, 64316,
	64237, 64156, 64073, 63987, 63899, 63809, 63716, 63621,
	63523, 63423, 63320, 63215, 63108, 62998, 62886, 62772,
	62655, 62536, 62415, 62291, 62165, 62036, 61906, 61772,
	61637, 61499, 61359, 61217, 61072, 60925, 60776, 60624,
	60470, 60314, 60156, 59995, 59832, 59667, 59499, 59330,
	59158, 58983, 58807, 58628, 58448, 58265, 58079, 57892,
	57703, 57511, 57317, 57121, 56923, 56722, 56520, 56315,
	56108, 55900, 55689, 55476, 55260, 55043, 54824, 54603,
	54379, 54154, 53926, 53697, 53465, 53232, 52996, 52759,
	52519, 52277, 52034, 51789, 51541, 51292, 51041, 50787,
	50532, 50275, 50016, 49756, 49493, 49228, 48962, 48694,
	48424, 48152, 47878, 47603, 47325, 47046, 46765, 46483,
	46199, 45912, 45625, 45335, 45044, 44751, 44456, 44160,
	43862, 43562, 43261, 42958, 42654, 42348, 42040, 41731,
	41420, 41108, 40794, 40478, 40161, 39843, 39523, 39201,
	38878, 38554, 38228, 37900, 37572, 37241, 36910, 36577,
	36243, 35907, 35570, 35231, 34892, 34551, 34208, 33865,
	33520, 33173, 32826, 32477, 32127, 31776, 31424, 31071,
	30716, 30360, 30003, 29645, 29286, 28926, 28564, 28202,
	27838, 27474, 27108, 26742, 26374, 26005, 25636, 25265,
	24894, 24521, 24148, 23774, 23398, 23022, 22645, 22268,
	21889, 21510, 21129, 20748, 20366, 19984, 19600, 19216,
	18832, 18446, 18060, 17673, 17285, 16897, 16508, 16119,
	15729, 15338, 14947, 14555, 14163, 13770, 13376, 12983,
	12588, 12193, 11798, 11402, 11006, 10609, 10212,  9815,
	 9417,  9019,  8621,  8222,  7823,  7423,  7024,  6624,
	 6224,  5823,  5422,  5022,  4621,  4219,  3818,  3417,
	 3015,  2613,  2211,  1809,  1407,  1005,   603,   201
};


// angle computation
uchar i;

///////////////////////////////////////////////////////////////

ANGLE* fovAngleP;

FP_8_8 dists[NDIRS]; // perpendicular distance per column (one element filled in)
FP_8_8* distP;

void draw(void);

/////////////////////////////////////////////////////////////
//
void 	initISR(void (*fun)(void));
void 	restoreISR(void);



/////////////////////////////////////////////////////////////
// Movement global variables:
//  current position, orientation and speed
// TODO initial position and orientation depends on the level
FP_8_8 xPos;     // player x-position
FP_8_8 yPos;     //        y-position
ANGLE alpha;        //        viewing direction
FP_S0_15 fwdSpeed; // forward/backward speed
FP_S0_15 sideSpeed; // sideways speed (strafe)
		
// Player position and orientation
FP_8_8 x, y;

// Initial position depending on level
extern uchar StartX,StartY;


// TODO set the variables below to 'reasonable' values.

// Maybe these values belong to the level?? (e.g. a slippery 'ice' level can
// have less friction or some levels allow to run faster)
//
// * Friction (actually 1-f)
//    0.0 means infinite friction (impossible to move)
//    1.0 means no friction (allows infinite velocity)
FP_0_16 friction = 50000; // ~0.76  (-> takes ~9 iterations to reach full speed)

// * Acceleration.
// Note that the maximal velocity is given by this formula:
// (though because of rounding errors, the results is a bit less)
//   maxVelocity = accelation * (friction / (1 - friction))
//                          stop, forward, backward, invalid
FP_S0_15 accelFwdTab[8] =  {    0,     500,     -400,       0,   // walk
                                0,    1000,     -800,       0 }; // run
//                          stop,    right,     left, invalid
FP_S0_15 accelSideTab[8] = {    0,     300,     -300,       0,   // walk
                                0,     600,     -600,       0 }; // run

// Rotation speed (TODO is this a good value?)
// TODO Make this configurable in some game menu ???
//      Or can this be a constant?
ANGLE rotSpeed;
#define slowRotSpeed  3
#define fastRotSpeed  6

FP_S0_15 accelWalk = 1200;
FP_S0_15 accelRun  = 2400;

///////////////////////////////////////////////////////////////

struct MoveCommands {
	bool forward;
	bool backward;
	bool strafeLeft;
	bool strafeRight;
	bool run;
} move;


FP_S0_15 mul(FP_S0_15 a, FP_0_16 b); 

//////////////////////////////////////////////////
//	FP_S0_15 mul(FP_S0_15 a, FP_0_16 b) {
//		return (a * (long)(b)) >> 16; 
//	}

#asm
	global _mul
_mul:
  ;_a stored from de - int  
  ;_b stored from bc - uint
		ex      de,hl
		bit     7,h
		jr      z,bp_dp
bp_dn:  muluw_hl_bc
		ex      de,hl
		or      a
		sbc     hl,bc
		ret

bp_dp:  muluw_hl_bc
		ex      de,hl
		ret
#endasm

  
FP_S0_15 mul2(FP_S0_15 a, FP_0_16 b);

//////////////////////////////////////////////////
// This is NOT the same as the mul() function above:
//  - mul2() rounds to zero (round down in absolute value)
//  - mul()  rounds down (so negative values get bigger in
//           absolute value)
// For the friction calcultations it's important that eventually
// the numbers go to zero (so we need round to zero).
/* 
FP_S0_15 mul2(FP_S0_15 a, FP_0_16 b) {
	if (a < 0) {
		return -((-a * (long)(b)) >> 16);
	} else {
		return  (( a * (long)(b)) >> 16);
	}
}
*/

#asm
	global _mul2
_mul2:
;_b stored from bc
;_a stored from de

	bit	07h,d
	jp	z,1f

	ld	hl,0
	or	a
	sbc	hl,de
	muluw_hl_bc
	ld	hl,0
	or	a
	sbc	hl,de
	ret	
1:
	ex	de,hl
	muluw_hl_bc
	ex	de,hl
	ret
#endasm


char kbd;
char right,left,up,down,key1;
char right2,left2;
char key2,graph,shift;
char esc,tab;

bool doExit = false;

///////////////////////////////////////////////////////////////
char NoMouse;		// choose configuration for commands 
///////////////////////////////////////////////////////////////
char CurDx,CurDy;
uint pad;
///////////////////////////////////////////////////////////////

void getMoveCommands(void)
{
	move.forward     = false;
	move.backward    = false;
	move.strafeLeft  = false;
	move.strafeRight = false;
	move.run         = false;

	if (NoMouse) {
		//////////////////////////////////////
		
		kbd = checkkbd (8);

		right    = !(kbd & 128);
		left     = !(kbd & 16) ;
		up       = !(kbd & 32) ;
		down     = !(kbd & 64) ;
		key1 	 = !(kbd & 1)  ; // space

		//////////////////////////////////////
	}
	else {
		//////////////////////////////////////

		pad = getmouse();

		//CurDy = ((char) pad);			// unused
		CurDx = *(((char*)&pad)+1);

		//////////////////////////////////////

		left     = !(checkkbd (2) & 64) ;//A

		//////////////////////////////////////
		
		kbd = checkkbd (3);
		right    = !(kbd & 2);//D
		right2   = !(kbd & 4);//E

		//////////////////////////////////////

		left2    = !(checkkbd (4) & 64) ;//Q

		//////////////////////////////////////
		
		kbd = checkkbd (5);
		up       = !(kbd & 16) ;	// W
		down     = !(kbd & 1) ;		// S
		
		//////////////////////////////////////
		
		alpha -= CurDx;	// Mouse

		if (left2) {
			move.strafeLeft = true;
		}
		else
		if (right2) {
			move.strafeRight = true;
		}
	
	}
	
	//////////////////////////////////////
	
	kbd = checkkbd (6);
	
	shift 	=  !(kbd & 1);
	graph 	=  !(kbd & 4);
	key2 	=  !(kbd & 2);	// CTRL

	kbd = checkkbd (7);
	
	esc 	=  !(kbd & 4);
	tab 	=  !(kbd & 8);

	//////////////////////////////////////

	if (shift) {
		move.run      = true;
		rotSpeed	  = fastRotSpeed;
	}
	else {
		rotSpeed	  = slowRotSpeed;
	}
	if (esc) { // ESC
		doExit = true;
	}
	if (key2)		// or strafe
	{
		if (left) {
			move.strafeLeft = true;
		}
		if (right) {
			move.strafeRight = true;
		}
	}
	else			// or rotate
	{
		if (left) {
			alpha -= rotSpeed;
		}
		if (right) {
			alpha += rotSpeed;
		}
	}
	
	if (up) {
		move.forward = true;
	}
	if (down) {
		move.backward = true;
	}
}


///////////////////////////////////////////////////////////////

void doMove(void)
{
	static FP_S0_15 fwdAcc;
	static FP_S0_15 sideAcc;
	
	static FP_S0_15 xSpeed, ySpeed;
	static uchar quadrant,a;
	static FP_S0_15 u, v ;
	
	// TODO fill move struct with commands from keyboard (and mouse?)
	//  It's of course also possible to directly read the keyboard status
	//  in the if statements below. (Maybe this separation makes it easier
	//  to have reconfigurable controls? Is this needed?)
	
	getMoveCommands();
	
	fwdAcc =
		accelFwdTab [move.forward     + 2 * move.backward   + 4 * move.run];
	sideAcc =
		accelSideTab[move.strafeRight + 2 * move.strafeLeft + 4 * move.run];

	fwdSpeed  = mul2(fwdSpeed  + fwdAcc , friction);
	sideSpeed = mul2(sideSpeed + sideAcc, friction);
	
	quadrant = (alpha >> 8) & 3;
	a        = alpha & 255;
	
	if (a == 0) {
		u = fwdSpeed;
		v = sideSpeed;
	} else {
		FP_0_16 c = cosine[     a]; // cos(a)
		FP_0_16 s = cosine[Q1 - a]; // sin(a)
		FP_S0_15 t1 = mul(fwdSpeed,  c);
		FP_S0_15 t2 = mul(sideSpeed, s);
		FP_S0_15 t3 = mul(fwdSpeed,  s);
		FP_S0_15 t4 = mul(sideSpeed, c);
		u = t1 - t2;
		v = t3 + t4;
	}


	switch (quadrant) {
		case 0: xSpeed =  u; ySpeed =  v; break;
		case 1: xSpeed = -v; ySpeed =  u; break;
		case 2: xSpeed = -u; ySpeed = -v; break;
		case 3: xSpeed =  v; ySpeed = -u; break;
	}
	// Note: for negative numbers '/ 256' and '>> 8' is NOT the same.
	//  e.g. -100 / 256 = 0  but  -100 >> 8 = -1
	// TODO possible future extension:
	//   simpler (asm) code and more accurate: make x,y 24 bit
	//   values (rendering code will only use upper 16 bits).
	xPos += xSpeed / 256;
	yPos += ySpeed / 256;

	clipMove2();
}

///////////////////////////////////////////////////////////////
//
//	actual main
//
///////////////////////////////////////////////////////////////

// updates NPCs in the map
void move_npcs(void);

// pause the game and show the map
void openmap(void);

///////////////////////////////////////////////////////////////
// main loop
//  - updates the global variables 'x', 'y' and 'alpha'
//    and redraws the screen
void ddamain(void) {

	// Initial player position and orientation
	xPos = x = StartX * 256 + 128; 
	yPos = y = StartY * 256 + 128; 
	alpha = NR_ANGLES/2;
	
	// Change the value '1.0' in the 3rd line. If you change the value 1.0 to X, the
	// FOV becomes    2 * atan(1/x)  (in radians).  So X=2.0 results in fov=53
	// (X must be >= 1.0).
	
	for (i = 0; i < NDIRS; ++i) {
		double scrX = (double)(2 * i - NDIRS + 1) / NDIRS;
		double screenAlpha = atan(scrX * 2/3); // FOV = 67.38 degrees
		ANGLE a = NR_ANGLES * screenAlpha / (2.0 * M_PI) + 0.5;
		fovAngles[i] = a & (NR_ANGLES - 1);
	}
	
	// Resets all buffers
	screen_int();

	// enable custom isr
	initISR(doMove);
	do {
        //////////////////////////////////////

		framecount++;
		if (jiffy>=64) {
			fps = framecount*60/jiffy;
			if (fps<99)
				printfps(fps);
			else
				printfps(99);
		
			jiffy = framecount = 0;
			
			if (tab)
				openmap();
		}

        //////////////////////////////////////
		move_npcs();
		
		draw();
		
		swap_buffer();
		
		asm(" di");
		x = xPos;
		y = yPos;
		asm(" ei");
		
	} while (!esc);	// Test ESC
	
	// restore standard ISR
	restoreISR();
	
 }



