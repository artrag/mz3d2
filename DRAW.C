#include <hitech.h>
#include <sys.h>
#include <intrpt.h>

#include <stdlib.h>
#include <float.h>
#include <math.h>

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

#include "vdphlp.h"

// Rotation angles have 10 bit precision. 
//   8 bit is not enough
//   9 bit is mostly ok, but occasionally gives a (small) artifact
//   10 bit should be fine
// An additional advantage of using 10 bit is that the quadrant can be very
// easily obtained in Z80 code. Also per-quadrant look up tables (LUT) are
// easily indexed in Z80 code using 10 bit (is 8 bit per quadrant).

typedef uint ANGLE;
typedef char bool;

extern ANGLE* fovAngleP;

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
	
//
// Look up tables (LUT)
//

// Correction angle (add to the view direction) per ray-cast-column
//   could be reduced to 8-bit and either sign-extend on use, or store
//   with an offset of +128
extern ANGLE fovAngles[NDIRS];

// texture computation
FP_0_8 tex;

extern FP_8_8 dists[NDIRS]; // perpendicular distance per column (one element filled in)
extern FP_8_8* distP;

uchar	col;

void fast_dda(void);

uchar color;         // 'color' of the hit world-block
uchar side;          // side on which the block was hit
uint height;         // visible height for the column
uint dist;			 // euclidean distance

ANGLE direction;     // required for the texture coord calculation
							//  (split in upper and lower 8-bit part)


uint tex_coord(void);

void translate_sprites(void);
void plot_sprites(void);

extern uchar* pp;
extern uint threshold;
extern uchar* rletxture[][32];

void	set_seg(uchar seg);
extern uchar rlesegtxture[][32];

void draw(void)
{
	// initialize fast_dda()
	fovAngleP = fovAngles;
	distP = dists;
	
	// initialize VDP for wall drawing
	vdp_setup0();

	col = 0;
	do {
		uchar wallType;
		fast_dda();
		// TODO possible optimization, let fast_dda() output the
		// following expression directly
		wallType = wallTypes[((color) << 2) | (side)];
		if (wallType & 0x80) {
			// need texture coords
			wallType &= ~0x80; // reset upper bit
			tex = (tex_coord() >> 3) & 31; // tex_coord returns 16 bits
		} else {
			// texture has no X-resolution
			tex = 0;
		}
		pp = rletxture[wallType][tex];
		set_seg(rlesegtxture[wallType][tex]);	// activate texture segment
		if (((uint)pp >> 8) == 0) {
			// single colored column in texture
			hmmvFlat((((uchar)pp) << 8) | col, height);
		} else {
			threshold = *((uint*)pp);
			pp += 2;
			if (height > threshold) {
				hmmvTexRender(col, height, pp);
			} else {
				hmmcTexRender(col, height, pp);
			}
		}
		col += Xres;
	} while (col != 0);

	translate_sprites();
	plot_sprites();
}
