#include <hitech.h>
#include <sys.h>
#include <intrpt.h>

#include <float.h>
#include <math.h>
#include "msx2lib.h"
#include "vdphlp.h"

#include "clipmove.h"
///////////////////////////////////////////////////////////////

extern int xPos,yPos;
extern uchar world[mapHeight][mapWidth];

#define x xPos
#define y yPos
#define T_MIN  64
#define T_MAX (255 - T_MIN)
#define EMPTY 0

#asm
	global _xPos,_yPos,_mapWidth,_world
	global _clipMove2
_clipMove2:
_x	equ _xPos
_y	equ _yPos

*include clip.asm
#endasm

/*
void clipMove2(void)
{

	unsigned char xh = x >> 8;
	unsigned char yh = y >> 8;
	unsigned char xl = x & 255;
	unsigned char yl = y & 255;
	
	const char* p = &world[yh][xh];
	if (xl < T_MIN) {
		// west
		if (*(p - 1) != EMPTY) {
			x = (xh << 8) | T_MIN;
			goto test_y;
		} else {
			if (yl < T_MIN) {
				// north
				p -= mapWidth;
				if (*p != EMPTY) {
					y = (yh << 8) | T_MIN;
				} else if (*(p - 1) != EMPTY) {
					// north-west
					if (xl < yl) {
						y = (yh << 8) | T_MIN;
					} else {
						x = (xh << 8) | T_MIN;
					}
				}
			} else if (yl > T_MAX) {
				// south
				p += mapWidth;
				if (*p != EMPTY) {
					y = (yh << 8) | T_MAX;
				} else if (*(p - 1) != EMPTY) {
					// south-west
					if (xl < (255 - yl)) {
						y = (yh << 8) | T_MAX;
					} else {
						x = (xh << 8) | T_MIN;
					}
				}
			}
		}
	} else if (xl > T_MAX) {
		// east
		if (*(p + 1) != EMPTY) {
			x = (xh << 8) | T_MAX;
			goto test_y;
		} else {
			if (yl < T_MIN) {
				// north
				p -= mapWidth;
				if (*p != EMPTY) {
					y = (yh << 8) | T_MIN;
				} else if (*(p + 1) != EMPTY) {
					// north-east
					if ((255 - xl) < yl) {
						y = (yh << 8) | T_MIN;
					} else {
						x = (xh << 8) | T_MAX;
					}
				}
			} else if (yl > T_MAX) {
				// south
				p += mapWidth;
				if (*p != EMPTY) {
					y = (yh << 8) | T_MAX;
				} else if (*(p + 1) != EMPTY) {
					// south-east
					if (xl > yl) {
						y = (yh << 8) | T_MAX;
					} else {
						x = (xh << 8) | T_MAX;
					}
				}
			}
		}
	} else {
test_y:		// at this point xl is in range [T_MIN .. T_MAX]
		if (yl < T_MIN) {
			// north
			if (*(p - mapWidth) != EMPTY) {
				y = (yh << 8) | T_MIN;
			}
		} else if (yl > T_MAX) {
			// south
			if (*(p + mapWidth) != EMPTY) {
				y = (yh << 8) | T_MAX;
			}
		}
	}
}


///////////////////////////////////////////////////////////////
#define T_MIN  64
#define T_MAX (255 - T_MIN)

void clipMove(void)
{
	int xh = xPos >> 8;
	int yh = yPos >> 8;
	int xl = xPos & 255;
	int yl = yPos & 255;

	// west
	if ((xl < T_MIN) && (world[yh][xh - 1] != 0)) {
		xl = T_MIN;
	}
	// east
	if ((xl > T_MAX) && (world[yh][xh + 1] != 0)) {
		xl = T_MAX;
	}
	// north
	if ((yl < T_MIN) && (world[yh - 1][xh] != 0)) {
		yl = T_MIN;
	}
	// south
	if ((yl > T_MAX) && (world[yh + 1][xh] != 0)) {
		yl = T_MAX;
	}
	// north-west
	if ((xl < T_MIN) && (yl < T_MIN) && (world[yh - 1][xh - 1] != 0)) {
		if (xl < yl) {
			yl = T_MIN;
		} else {
			xl = T_MIN;
		}
	}
	// north-east
	if ((xl > T_MAX) && (yl < T_MIN) && (world[yh - 1][xh + 1] != 0)) {
		if ((255 - xl) < yl) {
			yl = T_MIN;
		} else {
			xl = T_MAX;
		}
	}
	// south-west
	if ((xl < T_MIN) && (yl > T_MAX) && (world[yh + 1][xh - 1] != 0)) {
		if (xl < (255 - yl)) {
			yl = T_MAX;
		} else {
			xl = T_MIN;
		}
	}
	// south-east
	if ((xl > T_MAX) && (yl > T_MAX) && (world[yh + 1][xh + 1] != 0)) {
		if ((255 - xl) < (255 - yl)) {
			yl = T_MAX;
		} else {
			xl = T_MAX;
		}
	}

	xPos = (xh << 8) | xl;
	yPos = (yh << 8) | yl;
}
*/