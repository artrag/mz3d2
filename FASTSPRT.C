#include <hitech.h>
#include <sys.h>
#include <intrpt.h>

#include <stdlib.h>
#include <float.h>
#include <math.h>
#include "msx2lib.h"
#include "vdphlp.h"

void error(const char* message);

extern uint framecount;

typedef uint ANGLE;
typedef char bool;

#define clip(a, b, x)  (((x) > (b)) ? (b) : (((x)<(a) ? (a):(x))))

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

#define NUM_SPRITES 32

// Helper struct used while sorting the sprites.
// - Only the y coord (in camera-space) is important for sorting, the
//   rest of the sprite attributes can be found by following 'ptr'.
// - The actual sorting algorithm doesn't care about the 'ptr' field,
//   it just gets copied along.
struct SortElem {
	int y;
	void* extra;
};

typedef struct SortElem SortElem;

SortElem sortArray[NUM_SPRITES + 1]; // one extra for sentinel

// Struct with all the info about a single sprite,
//  this can have many attributes, so copying instances of this struct
//  is relatively slow
struct Sprite {
	int x, y; 	// world coordinates
	ANGLE beta;	// direction
	char status;	// current status
	int y2; 	// camera coordinates (x)
	int x2; 	// camera coordinates (y)
};

typedef struct Sprite Sprite;

Sprite sprites[NUM_SPRITES];

uchar VisibleSprites;

extern int xPos,yPos;
extern ANGLE alpha;        //        viewing direction

extern FP_0_16 cosine[];
extern ANGLE fovAngles[];
extern FP_8_8 dists[NDIRS]; // perpendicular distance per column (one element filled in)

FP_S7_8 mul3(FP_S7_8 a, FP_0_16 b); // {	return ((long)a * (long)b) >> 16;}


#asm
	global _mul3
_mul3:
; Input: DE = 16-bit   signed
;        BC = 16-bit unsigned
; Output: HL = (DE*BC) >> 16
       ex      de,hl
       bit     7,h
       jr      z,1f
       muluw_hl_bc             ; hl < 0
       ex      de,hl
       or      a
       sbc     hl,bc
       ret
1:     muluw_hl_bc             ; hl >= 0
       ex      de,hl
       ret
#endasm


extern uchar world[mapHeight][mapWidth];

// Sprite initialization
// dummy code to load enemy positions from the map

void set_sprites(void)	{
	uchar r,c;
	Sprite* p_sprite = sprites;
	
	for (r = 0; r < mapHeight; ++r) {
		for (c = 0; c < mapWidth; ++c) {
			uchar t = world[r][c];
			if ((t != 'X') && !('C' <= t && t <= 'F')) continue;

			world[r][c] = 0; // remove place holder
			if (p_sprite == sprites + NUM_SPRITES) {
				error("Too many sprites in map");
			}
			
			// intilialise sprite array
			p_sprite->x = c * 256 + 128;
			p_sprite->y = r * 256 + 128;
			p_sprite->beta = 0;
			p_sprite->status = (t == 'X')
			                 ? 0          // standing robot
			                 : (t - 'C' + 2); // pillar0 - pillar3
			++p_sprite;
		}
	}
	sprites[0].status = 1; // walking
}

void UNIT_Init(void);
bool UNIT_UpdateMove(void);
extern int UNIT_cKeyFrame;
extern uint UNIT_PosX,UNIT_PosY,UNIT_destX,UNIT_destY;


// Quick and dirty to see how it goes
// it works on the sole active NPC (the first)
void move_npcs(void) {
	Sprite* p_sprite;
	
	if (UNIT_UpdateMove()) 
		UNIT_Init();
	
	p_sprite = sprites;
	p_sprite->x = UNIT_PosX;
	p_sprite->y = UNIT_PosY;
	
	p_sprite->beta = UNIT_cKeyFrame*(NR_ANGLES/8);
}


void sort_sprites(SortElem* p_sprite1,SortElem* p_sprite2);

char* savesp;

#asm
; Sort 'elements' is descending order (from big to small). Sorting in ascending
; order is also possible with minor changes to the code. An element has a value
; (on which they are sorted) and an extra 16-bit attribute. The sort code
; itself doesn't care about this extra attribute (it's simply moved along to
; the correct position). The application code can put in this extra attribute
; the original index or a pointer to the original element (with much more
; attributes).
;
;   struct SortElem {
;	int y;
;	void* extra;
;   };
;    SortElem array[MAX+1];
;
;    int numElems; // must be   1 <= numElems <= MAX
;    sortElems(array, array+numElems);
;
; Input: [DE] = Ptr to first element (inclusive)
;        [BC] = Ptr to last  element (exclusive)
;
; Preconditions:
;  - there's room to store a sentinel at the end
;  - there is at least one element to sort

	global _sort_sprites,_savesp
_sort_sprites:

SortElems:
	di				;
	push	ix		;
	ld	(_savesp),sp	; save SP *** doesn't work when code is in ROM (in that case store in IY or in a global variable)
	ld	h,b		;
	ld	l,c		; HL = BC = addr of sentinel element
	xor	a		;
	ld	(bc),a		;
	inc	bc		;
	ld	(bc),a		; fill-in sentinel
	ld	bc,-4		; -sizeof(SortElem)
	add	hl,bc		; hl = last element
	exx			;

LoopO:	
	exx			; At this point sub-range [HL, Buf-End) is sorted
	or	a		; clear carry flag
	sbc	hl,de		; Start of buffer reached?
	jr	z,Exit		;  -> done
	add	hl,de		; restore hl
	add	hl,bc		; go to previous element,
	ld	sp,hl		;  possibly this element is not yet
	exx			;  in the correct position

LoopI:	
	pop	hl		; HL <- (SP) ; SP += 2    HL = new  element.y
	pop	bc		; BC <- (SP) ; SP += 2    BC = new  element.ptr
	pop	de		; DE <- (SP) ; SP += 2    DE = next element.y
	or	a		; clear carry flag
	sbc	hl,de		; next <= new -> new element is in correct position
	jr	nc,LoopO	; because of the end-sentinel, this loop always terminates
	add	hl,de		; restore value of 'next element.y'
	pop	ix		; IX <- (SP) ; SP += 2    IX = next element.ptr
	push	bc		; Store new           new  element.ptr
	push	hl		;   and               new  element.y
	push	ix		;   next element in   next element.ptr
	push	de		;   different order   next element.y
	inc	sp		; SP += 4 (move to next element)
	inc	sp		;   alternative is to pop 2 values
	inc	sp		;   (the pop'ed value doesn't matter, only move sp)
	inc	sp		;   on Z80 pop is faster, on R800 this is faster
	jr	LoopI		;

Exit:	ld	sp,(_savesp)		; restore SP
	pop	ix		; restore IX
	ei			;
	ret			;

#endasm

// Sprite calculations:
// Translate sprite coordinates from the 2D map to the camera space
	
void translate_sprites(void)	{
	uchar i;
	Sprite* 	p_sprite = sprites;
	SortElem* 	p_sortArray = sortArray;
	
	for	(i=0;i<NUM_SPRITES;i++,p_sprite++) {
		
		FP_S7_8 x2, y2;
			
		// Translate sprite coordinates
		//  note: all input coordinates are unsigned, but after translation
		//  the coordinates can become negative, so there we need signed
		//  values.
		FP_S7_8 tx = p_sprite->x - xPos;
		FP_S7_8 ty = p_sprite->y - yPos;

		// Rotate over minus the viewing direction. This brings the sprites
		// coordinates into camera-space.
		uchar quadrant = alpha >> 8;
		uchar a = alpha & 255;
		
		// Split into 4 quadrants: that way we only need to store one quadrant
		// of a cosine LUT. This also allows us to keep one factor of the
		// multiplication(s) always positive (allows for a faster asm version
		// of the multiplication).
		// TODO optimization:
		//  - skip calculating 'y2' if 'x2 < 0' 
		FP_S7_8 u, v;
		if (a == 0) {
			u =  tx;
			v =  ty;
		} else {
			FP_0_16 c = cosine[     a];
			FP_0_16 s = cosine[Q1 - a];
			// all these multiplications are:
			//  signed-fixed-point-7.8 x unsigned-fixed-point-0.16
			//  -> signed-fixed-point-7.8
			FP_S7_8 t1 = mul3(tx, c);
			FP_S7_8 t2 = mul3(ty, s);
			FP_S7_8 t3 = mul3(tx, s);
			FP_S7_8 t4 = mul3(ty, c);
			u =  t1 + t2;
			v = -t3 + t4;
		}
		switch (quadrant & 3) {
			case 0: x2 =  u; y2 =  v; break;
			case 1: x2 =  v; y2 = -u; break;
			case 2: x2 = -u; y2 = -v; break;
			case 3: x2 = -v; y2 =  u; break;
		}
		
		// filter sprites outside the 90° FOV angle
		// we could (should) add more filters here.
		
		if	((y2<x2)&&(y2>-x2)) {	
			p_sprite->y2 = y2;		// no need to store camera coords if the sprite is filtered away
			p_sprite->x2 = x2;

			p_sortArray->y = x2;
			p_sortArray->extra = p_sprite;
			p_sortArray++;
		}
	}

	VisibleSprites = p_sortArray - sortArray;
	
	if	(VisibleSprites>1) {
		sort_sprites(sortArray,p_sortArray);
	}
	
	// TODO one could test on max distance here, after sorting
}




void plot_sprites(void) {
	uchar i,j;
	SortElem* p_sortArray = sortArray;
	
	for	(i=0;i<VisibleSprites;i++,p_sortArray++) {
		
		Sprite* p_sprite = p_sortArray->extra;
			
		ANGLE beta = p_sprite->beta;        //        enemy viewing direction
			
		// On screen sprite height
		// Note: this is the same division as for wall height. We
		//  already have a fast (very specialized) asm implementation
		//  for this formula.
		uint h = (64U * 256U) / p_sprite->x2;

		// On screen sprite X-coordinate:
		//   0 -> left column, 63 -> right column
		//   but the calculated value can also be outside this range
		// The straight-forward implementation uses a division, but by
		// reusing the 'h' variable this can be transformed to a
		// multiplication: (32 * y2 / x2) == (y2 * h / 512).
		// The following multiplication is:
		//   signed-fixed-point-7.8 x unsigned-16 -> signed-16
		//   (in C simply do signed-32 x signed-32)

		int cx = 64 + (((int)(((long)p_sprite->y2 * h * 3) >> 8)) >>1);			// Relies on FoV angle of 67.38°!

		ANGLE gamma = fovAngles[clip(0, 255, cx)/2];
		ANGLE delta = beta-alpha-gamma-NR_ANGLES/2;
		uchar relative_direction = ((delta+(NR_ANGLES/16))/(NR_ANGLES/8))&7;		// only 8 directions

		
		// On screen sprite width: fixed ratio of sprite height
		// (could also be the same as sprite height). The factor 1/3
		// is only to make it look better in the ascii version.
		int cw = h;

		// Sprite X-texture-coordinates
		// - texture coordinates go from [0..64)
		// - we want a texture-delta (texture coord increase per
		//   screen column) (must be 8.8 fixed point)
		// - obvious formula is: DtexX = 64 / cw, but after
		//   substituting, 'h', we get the following
		// - factor 3 is only for the ascii renderer, for mz3d (when
		//   cw = h) we simply get 'DtexX = x2'
		
		FP_8_8 DtexX = p_sprite->x2 >> 1;
				
		FP_8_8 TtexX = 0; // start in left sprite tex column, ...
		// (optional): experiment, this formula may look better
		// for zoomed out sprites: it makes the rouding errors on
		// the left and the right side of the sprite symmetrical.
		// Is this worth the extra code?
		// (When there are no rounding errors, the result of the
		// following calculation is zero).
		//TtexX = (0x4000 - DtexX * cw) / 2;
		
		// Calculate clipped start (inclusive) and end (exclusive)
		// screen colums where sprite is visible.
		int xt = cx - (cw / 2);
		int xmin = xt;
		int xmax = ((xt + cw) >= 128) ? 128 : (xt + cw);

		if (xt < 0) {
			xmin = 0;
			TtexX = -xt * DtexX; // ... but in case of clipping,
								 // start in other tex column
		}

		// Actually draw sprite columns:
		// - check that sprite distance (x2) is smaller than the wall
		//   distance for this column
		
		if (xmin<xmax) {
		
			// preset the vdp for sprites and set the animation frame
			switch (p_sprite->status)	{
				case	0:	
				vtrace0(relative_direction*5);			// frames 0,5,10,...35
				break;
				
				case	1:
				vtrace0((1+((jiffy>>3) & 3))+relative_direction*5);			// frames 1-4,6-9,...36-39
				break;
				
				case	2:vtrace0(40);break;			// pillar0
				case	3:vtrace0(41);break;			// pillar1
				case	4:vtrace0(42);break;			// pillar2
				case	5:vtrace0(43);break;			// pillar3
				
			}
			
			DtexX;
			for ( j = xmin; j < xmax; j++) {
				uchar texX = TtexX >> 7;		
				
				if (p_sprite->x2 < dists[j>>1]) {
					vtrace1(h,j<<1,texX);		// testing
				}
				TtexX += DtexX;
			}
		}
	}
}

