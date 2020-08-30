#include "msx2lib.h"
#include "vdphlp.h"

#pragma psect	bss=ddadata

uchar world[mapHeight][mapWidth];


#asm
_mapWidth	equ mapWidth
_mapHeight	equ mapHeight
	global _mapWidth
	global _mapHeight
#endasm
