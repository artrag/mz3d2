#include <sys.h>

// #define EI() asm(" ei")
// #define DI() asm(" di")

/*
* PORT mappings
*/
static port unsigned char v99 @ 0x99; // VDP: Command and status register
static port unsigned char v98 @ 0x98; // VDP: Video RAM data

////////////////////////////////////
//  Msx timer
////////////////////////////////////
extern unsigned int jiffy;

////////////////////////////////////
//  Msx2 video
////////////////////////////////////

void	bordercolor (char color);
void	setpage(char page);
void	scr(char mode);
void 	SetPalette(void);
void 	vdpsetvramwr(unsigned int addr,unsigned char p);
void 	vdpsetvramrd(unsigned int addr,unsigned char p);
  


////////////////////////////////////
//  Keyboard access
////////////////////////////////////

unsigned char	checkkbd(unsigned char kbdline);
unsigned int	getmouse(void);
char joy(void);

// Line Bit_7 Bit_6 Bit_5 Bit_4 Bit_3 Bit_2 Bit_1 Bit_0
// 0 "7" "6" "5" "4" "3" "2" "1" "0"
// 1 ";" "]" "[" "\" "=" "-" "9" "8"
// 2 "B" "A" ??? "/" "." "," "'" "`"
// 3 "J" "I" "H" "G" "F" "E" "D" "C"
// 4 "R" "Q" "P" "O" "N" "M" "L" "K"
// 5 "Z" "Y" "X" "W" "V" "U" "T" "S"
// 6 F3 F2 F1 CODE CAP GRAPH CTRL SHIFT
// 7 RET SEL BS STOP TAB ESC F5 F4
// 8 RIGHT DOWN UP LEFT DEL INS HOME SPACE


