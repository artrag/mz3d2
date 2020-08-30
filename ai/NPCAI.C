
#include	<string.h>
#include 	<stdlib.h>
#include 	<math.h>
#include 	"msx2lib.h"
#include 	"vdphlp.h"
#include 	"npcai.h"

node nodelist[NNODES];

#define timeGetTime()	(*((uint*)(0xFC9E)))

#define bool char
#define false (0)
#define true (!false)


/*--| CLASS |-----------------------------------------------------------------------*\
| Name: UNIT
| Desc: the Unit class
\*----------------------------------------------------------------------------------*/
	bool UNIT_DestSet;
	int UNIT_cKeyFrame;
	int UNIT_MoveX,UNIT_MoveY;
	
	uint UNIT_StartTick,UNIT_CTick;
	
	node* UNIT_PATH = nodelist;
	int UNIT_cPath;
	int UNIT_nPath;
	
	void UNIT_NewMove(void);
	void UNIT_Stop(void);

	bool UNIT_IsAtNode(void);
	uint UNIT_PosX,UNIT_PosY,UNIT_destX,UNIT_destY;
	int UNIT_Speed;
	void UNIT_Init(void);
	void UNIT_Turn(char Side);
	bool UNIT_UpdateMove(void);
/*----------------------------------------------------------------------------------*\
| Name: Turn
| Desc: Change the side which the character is facing
\*----------------------------------------------------------------------------------*/
void UNIT_Turn(char Side)
{
	UNIT_cKeyFrame=Side;
}
/*----------------------------------------------------------------------------------*\
| Name: GetKoef
| Desc: Get the amount to move at the corrent frame
\*----------------------------------------------------------------------------------*/
#define UNIT_GetKoef() ((timeGetTime()-UNIT_CTick)/8.0);

/*----------------------------------------------------------------------------------*\
| Name: IsAtNode
| Desc: Verifies if the character is at the node
\*----------------------------------------------------------------------------------*/
bool UNIT_IsAtNode()
{
	uint xx = UNIT_PATH[UNIT_cPath].x;
	uint yy = UNIT_PATH[UNIT_cPath].y;
	
		if (UNIT_MoveX+UNIT_Speed==0 && UNIT_PosX < UNIT_destX && UNIT_MoveY+UNIT_Speed==0 && UNIT_PosY < UNIT_destY)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	else if (UNIT_MoveX==0 && UNIT_MoveY+UNIT_Speed==0 && UNIT_PosY < UNIT_destY)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	else if (UNIT_MoveX==UNIT_Speed && UNIT_PosX > UNIT_destX && UNIT_MoveY+UNIT_Speed==0 && UNIT_PosY < UNIT_destY)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	else if (UNIT_MoveX+UNIT_Speed==0 && UNIT_PosX < UNIT_destX && UNIT_MoveY==0)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	else if (UNIT_MoveX==UNIT_Speed && UNIT_PosX > UNIT_destX && UNIT_MoveY==0)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	else if (UNIT_MoveX+UNIT_Speed==0 && UNIT_PosX < UNIT_destX && UNIT_MoveY==UNIT_Speed && UNIT_PosY > UNIT_destY)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	else if (UNIT_MoveX==0 && UNIT_MoveY==UNIT_Speed && UNIT_PosY > UNIT_destY)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	else if (UNIT_MoveX==UNIT_Speed && UNIT_PosX > UNIT_destX && UNIT_MoveY==UNIT_Speed && UNIT_PosY > UNIT_destY)
	{ UNIT_PosX=xx; UNIT_PosY=yy; return true; }

	return false;
}
/*----------------------------------------------------------------------------------*\
| Name: Init
| Desc: UNIT initialization
\*----------------------------------------------------------------------------------*/

#define sign(X)  ((X>0)-(X<0))

void UNIT_NewMove()
{
	int	Ux,Uy,Vx,Vy;
	
	UNIT_cPath++;
	
	Ux = UNIT_PosX;
	Uy = UNIT_PosY;

	Vx = UNIT_PATH[UNIT_cPath].x;
	Vy = UNIT_PATH[UNIT_cPath].y;

	
	if (Vx < (int) (Ux) && Vy < (int) (Uy))
	{ UNIT_MoveX=UNIT_MoveY=-UNIT_Speed; UNIT_Turn(5);}

	else if (Vx== (int) (Ux) && Vy < (int) (Uy))
	{ UNIT_MoveX=0; UNIT_MoveY=-UNIT_Speed; UNIT_Turn(6);}			

	else if (Vx > (int) (Ux) && Vy < (int) (Uy))
	{ UNIT_MoveX=UNIT_Speed; UNIT_MoveY=-UNIT_Speed; UNIT_Turn(7); }	

	else if (Vx < (int) (Ux) && Vy== (int) (Uy))
	{ UNIT_MoveX=-UNIT_Speed; UNIT_MoveY=0; UNIT_Turn(4); }

	else if (Vx > (int) (Ux) && Vy== (int) (Uy))
	{ UNIT_MoveX=UNIT_Speed; UNIT_MoveY=0; UNIT_Turn(0);}

	else if (Vx < (int) (Ux) && Vy > (int) (Uy))
	{ UNIT_MoveX=-UNIT_Speed; UNIT_MoveY=UNIT_Speed; UNIT_Turn(3);}

	else if (Vx== (int) (Ux) && Vy > (int) (Uy))
	{ UNIT_MoveX=0; UNIT_MoveY=UNIT_Speed; UNIT_Turn(2);}

	else if (Vx > (int) (Ux) && Vy > (int) (Uy))
	{ UNIT_MoveX=UNIT_MoveY=UNIT_Speed; UNIT_Turn(1);}
	
	UNIT_destX=Vx;
	UNIT_destY=Vy;

}


void UNIT_Init()
{
	UNIT_DestSet = true;
	UNIT_cKeyFrame=0;
	UNIT_Speed=5;
	
	UNIT_nPath = NNODES;
	UNIT_cPath = 0;
	
	UNIT_PosX = UNIT_PATH[UNIT_cPath].x;
	UNIT_PosY = UNIT_PATH[UNIT_cPath].y;
	
	UNIT_NewMove();
}
/*----------------------------------------------------------------------------------*\
| Name: UpdateMove
| Desc: Update the move for the frame
\*----------------------------------------------------------------------------------*/
bool UNIT_UpdateMove()
{
	uint Koef;
	if (UNIT_CTick==timeGetTime()) return false;
	
	if (UNIT_IsAtNode())
		UNIT_NewMove();

	if (UNIT_cPath>UNIT_nPath-1){
		return true;
	}

	// Koef = UNIT_GetKoef();
	Koef = 1;
	UNIT_PosX += (int)(UNIT_MoveX*Koef);
	UNIT_PosY += (int)(UNIT_MoveY*Koef);
	UNIT_CTick = timeGetTime();
	
	return false;
}


/*
void test(void)
{
	uint addr;
	bool bRunning=true;
	
	UNIT_Init();

	
	// MAIN LOOP
	// while (bRunning)
	while (UNIT_cPath<UNIT_nPath)
	{
		bRunning = !UNIT_UpdateMove();
	
		addr = ((UNIT_PosX)>>8)+((UNIT_PosY)>>8)*256;vdpsetvramwr(addr,0);outp(0x98,rand());
		
		
	}
	
}
*/