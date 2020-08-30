
#ifndef  __MSXDOS2_H__
#define  __MSXDOS2_H__


/* standard descriptors */
#define  STDIN   0
#define  STDOUT  1
#define  STDERR  2
#define  AUX     3
#define  PRN     4

/* open/creat flags */
#define  O_RDONLY   0x01
#define  O_WRONLY   0x02
#define  O_RDWR     0x00
#define  O_INHERIT  0x04

/* creat attributes */
#define  ATTR_RDONLY  0x01
#define  ATTR_HIDDEN  0x02
#define  ATTR_SYSTEM  0x04
#define  ATTR_VOLUME  0x08
#define  ATTR_FOLDER  0x10
#define  ATTR_ARCHIV  0x20
#define  ATTR_DEVICE  0x80

/* seek whence */
#define  SEEK_SET  0
#define  SEEK_CUR  1
#define  SEEK_END  2


extern unsigned char last_error;


extern char _open(char *, unsigned char);
extern char _creat(char *, unsigned char, unsigned char);
extern char _close(char);
extern char _dup(char);
extern int _read(char, void *, int);
extern int _write(char, void *, int);
extern long _lseek(char, long, char);		//        long l = lseek(fd, 10, SEEK_CUR);
extern void _exit(int);

#endif
