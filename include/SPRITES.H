
#define texWidth 64
#define texHeight 64

struct Sprite
{
  uint x;
  uint y;
  long tx;
  long ty;
  uchar type;
};

#define numSprites 16
#define _numSprites 16

//1D Zbuffer
extern int invZBuffer[Wscr/Xres];

//function used to sort the sprites
void combSort(int* order, long* dist,uint amount);

void setsprites(void);

extern struct Sprite sprite[numSprites];

//arrays used to sort the sprites
extern int spriteOrder[numSprites];
extern long spriteDistance[numSprites];


extern uchar color0[Wscr/Xres];
extern uchar color1[Wscr/Xres];
extern uchar hight0[Wscr/Xres];
extern uchar hight1[Wscr/Xres];



