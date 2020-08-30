#include	<stdio.h>
#include	<string.h>
#include 	<stdlib.h>
#include 	"msx2lib.h"
#include 	"vdphlp.h"
#include 	"npcai.h"
#include 	"msxdos2.h"

void error(const char* message);
void error2(const char* message, const char* argument);

// place sprites in the map
void set_sprites(void);


// Heavily modified _fgets routine:
// - no more check for buffer overflow!
// - read until 'EOF', EOT or '\n', but don't store this character in the buffer
// - buffer always gets zero-terminated
// - returns the number of characters that are stored in the buffer (exclusing
//   the zero-terminator)
#define EOT 0x04


int _fgets(char* buf, char pFile) {
	static uchar c;
	int i=0;
	while (1) {
		if (_read(pFile, &c, 1)==0) 	// EOF
			return i;
		if ((c == EOT) || (c == '\n')) {
			buf[i] = '\0';
			return i;
		}
		buf[i] = c;
		++i;
	}
}


///////////////////////////////////////

uchar StartX,StartY;
extern uchar world[mapHeight][mapWidth];

void plotline(uchar* data) {
	uchar c;
	uchar* p = data;
	while (c = *p++) {
		outp(0x98, c | (c << 4) | (c >> 4));
	}
}

extern char esc,tab;
typedef uint  FP_8_8;   // 16 bit [0..256) step: 1/256
extern FP_8_8 xPos;     // player x-position
extern FP_8_8 yPos;     //        y-position

void openmap(void)
{
	int r;
	uint addr = 2*256*128;
	uchar *p;
	uchar count,t;
	
	setpage(2);
	
	r = 0; 
	while (r<mapHeight) {
		for	(t=0;t<2;t++) {
			vdpsetvramwr(addr, 1); 
			p = world[r];
			count = mapWidth;
			while (count--)	{
				uchar c = *p++;
				outp(0x98, c | (c << 4) | (c >> 4));
			}
			addr += 128;
		}
		r++;
	}
	
	
	{
		uint old_addr = (xPos>>8) + (yPos>>8)*128*2 + 2*256*128;
		while  (tab){
			addr = (xPos>>8) + (yPos>>8)*128*2 + 2*256*128;
			vdpsetvramwr(addr		, 1); outp(0x98,t);
			vdpsetvramwr(addr +  128, 1); outp(0x98,t);
			t--;
			if	(old_addr!=addr) {
				t = 0;
				vdpsetvramwr(old_addr	   , 1); outp(0x98,t);
				vdpsetvramwr(old_addr +	128, 1); outp(0x98,t);
			}
			old_addr = addr;
		}
	}
	
}

// The content of the worldMap[][] array contains values in range [0..63],
// combined with the 'side' information (north, east, south, west) this
// forms a 8-bit value. That value is used as index in the wallTypes[] array.
//
// The values in the wallTypes[] array have the following meaning:
//   bit7  : should texture coordinates be calculated?
//   bit6-0: texture number
// Next the texture number and texture coordinates are combined to lookup a
// value in the rletxture[][] array.
//
// Values in the rletxture[][] array have the following meaning:
//  value <  0x100: draw a single colored column
//  value >= 0x100: pointer to texture data
//
// Texture data starts with a treshold value, followed by the RLE encoded
// texture data. This treshold is an estimate for when it's cheaper to draw
// the texture data using the HMMC or HMMV variant of the draw routine. The
// RLE data is a stream of byte-pairs, where each pair represents a segment
// of the texture with a single color. The pair has the format (size, color).
// The RLE-stream stops with a zero-byte. Note that the sum of the lengths
// of the segments must be exactly equal to 128.
//
// Note: to have a wall with a single color, the value in wallTypes[] must
// have bit7=0 (to force texture coord to zero), and rletxture[val][0] must
// be < 0x100 (there's no 'direct' way to specify a single colored wall).

// The content of this array is specific to the level. It should be filled-in
// by the level loading code. But for now we could initialize it with hardcoded
// values (just as we currently hardcode the texture data).
// TODO for extra speed, align this table on a 256-byte boundary



extern uchar wallTypes[256];
uchar *buffer = wallTypes;
	
void loaddata(const char* name)
{
	int r, c;
	uint addr = 0;


	char pFile = _open(name, O_RDONLY);
	if (pFile < 0) {
		error2("Error opening file: ", name);
	}
	
	memset(world,' ',mapWidth*mapHeight);
	
	scr(5);
	r = 0; // *** This was missing in the original code, was that a bug? ***
	       // *** Can that explain the (r - 1) hack below?               ***
	while (_fgets(buffer, pFile)) {
		vdpsetvramwr(addr, 0); plotline(buffer); addr += 128;
		vdpsetvramwr(addr, 0); plotline(buffer); addr += 128;
		strncpy(world[r++], buffer, mapWidth);
	}
	_close(pFile);
		
		// In this loop we should:
		// - remap tiles/walls
	// - fill datascructures for doors and switches
	// - place enemies
	for (r = 0; r < mapHeight; ++r) {
		for (c = 0; c < mapWidth; ++c) {
			switch (world[r][c]) {
				case 'P':
					StartX = c;
					StartY = r;
					world[r][c] = 0;
					break;
				case '.':
					world[r][c] = 0;
					break;
				default:
					break;
			}
		}
	}
	
	// place sprites in the map	reading them from the map itself
	set_sprites();


	///////////////////////////////////////////
	// enemy paths are coded in nodes
	// WIP: this code needs to be extended 
	// to multiple paths
	///////////////////////////////////////////
	memcpy(strchr(name, '.') + 1, "dat", 3);
	pFile = _open(name, O_RDONLY);
	if (pFile < 0) {
		error2("Error opening file: ", name);
	}
	
	r = 0;
	while (_fgets(buffer, pFile)) {
		for (c = 0; buffer[c]; ++c) {
			uchar k = buffer[c] - 'a'; // nodes are 'a', 'b', ..., 'z'
			if (k < NNODES / 2) {
				uint x = c * 256 + 128;
				uint y = r * 256 + 128;
				nodelist[             k].x = x;
				nodelist[             k].y = y;
				nodelist[NNODES - 1 - k].x = x;
				nodelist[NNODES - 1 - k].y = y;
			}
		}
		++r;
	}
	_close(pFile);
	
	
	////////////////////////////////////////////////////////////////////////
	// wallTypes is used like this:
	//   uchar wallType = wallTypes[(color << 2) | side];
/*
	for (r = 0; r < 256; ++r) {
		c = r >> 2;
		wallTypes[r] = (r & 1) 
		             + c * 2           // ATM only 2 sides are used: N/S and E/W
		             + (c ? 0x80 : 0); // texture 0 is uniform, it doesn't need texX
	}
*/
	for (r=0;r<256;r++) {
		// ATM only two sides are used: N/S and E/W

		for (c=0;c<Ntex;c++) {
			if ((r & ~3) == (('0'+c)<<2))					// textures are '0','1',...,Ntex-1
				wallTypes[r] = (r&1)+c*2+(c!=0)*0x80;		// texture 0 is uniform, it doesn't need texX
		}
	}

}

//////////////////////////////////////////////////////

void 	loadseg(const char* name, uchar seg);
void 	load(const char* name, void* dest, uint nbyte);
void 	dosinit(void);
uchar	alloc_seg(void);
uchar 	alloc_seg2(void);
void	free_seg(uchar seg);
uchar	get_seg(void);
void	set_seg(uchar seg);

extern uchar palettedata[32];
uchar seg_sprt[8],seg_text[8];

extern uchar* rletxture[2*Ntex][32];
extern uchar* rlesprite[Nsprt][32];

extern uchar rlesegtxture[2*Ntex][32];
extern uchar rlesegsprite[Nsprt][32];


void grph_init(void)
{
	uchar *p;
	uchar i;
	int count;
	
	dosinit();
	
	load("palt_asm.bin", palettedata, 32);
	
	load("tadd_asm.bin", rletxture,2*2*Ntex*32); 
	load("sadd_asm.bin", rlesprite,2*Nsprt*32); 	
		
	load("tseg_asm.bin", rlesegtxture,2*Ntex*32); 
	load("sseg_asm.bin", rlesegsprite,Nsprt*32); 
	
	{
		uchar n[] = "tsg0_asm.bin";
		for	(i=0;i<2;i++)		{		// ATM only 2 segments for textures
			seg_text[i] = alloc_seg();	// extra segment for textures
			loadseg(n, seg_text[i]);
			n[3]++;
		}
	}
	
	{
		uchar n[] = "ssg0_asm.bin";
		for	(i=0;i<7;i++) 		{		// ATM only 4 segments for sprites
			seg_sprt[i] = alloc_seg();	// extra segment for textures
			loadseg(n, seg_sprt[i]);
			n[3]++;
		}
	}
	
	p = rlesegtxture;
	count = 2 * Ntex * 32;		// initilalise rlesegsprite too
	do {
		if (*p!=0xFF)	*p = seg_text[*p];
		++p;
	} while (--count);
	
	p = rlesegsprite;
	count = Nsprt * 32;		// initilalise rlesegsprite too
	do {
		if (*p!=0xFF)	*p = seg_sprt[*p];
		++p;
	} while (--count);

}


void load(const char* name, void* dest, uint nbyte)
{
	char pFile = _open(name, O_RDONLY);
	if (pFile < 0) {
		error2("Error opening file: ", name);
	}
	if (_read(pFile, dest, nbyte) != nbyte) {
		error2("Error reading file: ", name);
	}
	_close(pFile);
}

void loadseg(const char* name, uchar seg)
{
	set_seg(seg);
	load(name, (uchar*)0x8000, 0x4000);
}



uchar alloc_seg()
{
	uchar result = alloc_seg2();
	if (!result) {
		error("Not enough ram\n");
	}
	return result;
}

#asm

	psect	bss,class=DATA
	
_wallTypes:		defs	256

	psect		text

_rlesegtxture:		defs	2*Ntex*32
_rlesegsprite:		defs	Nsprt*32

_rletxture:			defs	2*2*Ntex*32
_rlesprite:			defs	2*Nsprt*32

_palettedata: 		defs 	32


	
EXTBIO equ 0xffca

	global _dosinit

_dosinit:
	push	ix
	push	iy
	xor	a
	ld	de,0x0402
	call	EXTBIO
	ld	de,ALL_SEG
	ld	bc,0x30
	ldir
	pop	iy
	pop	ix
	ret

	global _alloc_seg2, _get_seg, _set_seg
	
_get_seg:		
	call GET_P2
	ld	l,a
	ret
		
    
_set_seg:
	ld	a,e
	jp PUT_P2
		
_alloc_seg2:
	xor a
	ld b,a
	call ALL_SEG
	ld l,a
	ret	nz		; *** TODO *** Is this correct? My documentation says the carry flag is used.
	ld	l,0		; no free RAM
	ret
        
       
ALL_SEG:        jp 0
FRE_SEG:        jp 0
RD_SEG:         jp 0
WR_SEG:         jp 0
CAL_SEG:        jp 0
CALLS:          jp 0
PUT_PH:         jp 0
GET_PH:         jp 0
PUT_P0:         jp 0
GET_P0:         jp 0
PUT_P1:         jp 0
GET_P1:         jp 0
PUT_P2:         jp 0
GET_P2:         jp 0
PUT_P3:         jp 0
GET_P3:         jp 0


    psect	bss,class=DATA
_last_error:
	ds 1

	psect	text,class=CODE

;3.47   OPEN FILE HANDLE (43H)
;     Parameters:    C = 43H (_OPEN) 
;                        DE = Drive/path/file ASCIIZ string
;                                or fileinfo block pointer
;                    A = Open mode. b0 set => no write
;                                   b1 set => no read
;                                   b2 set => inheritable   
;                                 b3..b7   -  must be clear
;     Results:       A = Error
;                    B = New file handle

    global __open
__open:
	; path already in DE
	ld	a,c		; a = flags
	ld	c,0x43
	call	5
	ld	(_last_error),a
	and    a
	ld     l,b
    ret    z
	ld     l,-1
	ret 

;3.48   CREATE FILE HANDLE (44H)
;     Parameters:    C = 44H (_CREATE) 
;                        DE = Drive/path/file ASCIIZ string
;                    A = Open mode. b0 set => no write
;                                   b1 set => no read
;                                   b2 set => inheritable   
;                                 b3..b7   -  must be clear
;                    B = b0..b6 = Required attributes
;                            b7 = Create new flag
;     Results:       A = Error
;                    B = New file handle


    global __creat
__creat:
	; path already in DE
	ld	a,c		; a = flags
	pop	hl		; return address
	pop	bc		; get attributes
	push	hl		; restore return address
	ld	b,c
	ld	c,0x44
	call	5
	ld	(_last_error),a
	and    a
	ld     l,b
    ret    z
	ld     l,-1
	ret 

;3.49   CLOSE FILE HANDLE (45H)
;     Parameters:    C = 45H (_CLOSE) 
;                    B = File handle
;     Results:       A = Error

    global __close
__close:
	ld	b,e	; b = handle
	ld	c,0x45
	call	5
	ld	(_last_error),a
	ld     l,a
	ret

;3.51   DUPLICATE FILE HANDLE (47H)
;     Parameters:    C = 47H (_DUP) 
;                    B = File handle
;     Results:       A = Error
;                    B = New file handle

	global __dup
__dup:
	ld	b,e		; b = handle
	ld	c,0x47
	call	5
	ld     (_last_error),a
	and    a
	ld     l,b
    ret    z
	ld     l,-1
	ret 

;3.52   READ FROM FILE HANDLE (48H)
;     Parameters:    C = 48H (_READ) 
;                    B = File handle
;                   DE = Buffer address
;                   HL = Number of bytes to read  
;     Results:       A = Error
;                   HL = Number of bytes actually read

    global __read
__read:
    pop     af      ; get return address
    pop     hl  	; bytes to be read
	push    af      ; restore return address 

	ld	d,b
	ld	b,e	; b = handle
	ld	e,c	; de = buffer address
	ld	c,0x48
	call	5
	ld	(_last_error),a
	and    a
	ret    z
	ld     hl,-1 
	ret

;3.53   WRITE TO FILE HANDLE (49H)
;     Parameters:    C = 49H (_WRITE) 
;                    B = File handle
;                   DE = Buffer address
;                   HL = Number of bytes to write
;     Results:       A = Error
;                   HL = Number of bytes actually written


    global __write
__write:
    pop     af      ; get return address
	pop	hl	; bytes to write
	push	af	; restore return address

	ld	d,b
	ld	b,e	; b = handle
	ld	e,c	; de = buffer address
	ld	c,0x49
	call	5
	ld     (_last_error),a
	and    a
	ret    z
	ld     hl,-1 
	ret

;3.54   MOVE FILE HANDLE POINTER (4AH)
;     Parameters:    C = 4AH (_SEEK) 
;                    B = File handle
;                    A = Method code
;                DE:HL = Signed offset
;     Results:       A = Error
;                DE:HL = New file pointer


    global __lseek
__lseek:
	push   ix
	ld     ix,0
	add    ix,sp
	ld	b,e		; b = handle
	ld	l,(ix+4)
	ld	h,(ix+5)
	ld	e,(ix+6)
	ld	d,(ix+7)	; de:hl = 32-bit offset
	ld	a,(ix+8)	; a = method
	pop	ix		; restore IX
	ld	c,0x4A
	call	5
	ld	(_last_error),a
	and    a
	ret    z
	ld     hl,-1
    ld     d,l 
    ld     e,l
	ret

;3.78   TERMINATE WITH ERROR CODE (62H)
;     Parameters:    C = 62H (_TERM) 
;                    B = Error code for termination
;     Results:       Does not return

    global __exit
__exit:
	ld     b,e
	ld     c,0x62
	jp     5

#endasm
