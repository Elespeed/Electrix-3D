#ifndef CPUPORT_H__
#define CPUPORT_H__

#include <rtconfig.h>

/* bytes of register width  */
#if (_LOONGARCH_SZPTR  == 32)
#define STORE                   st.w
#define LOAD                    ld.w
#define REGBYTES                4
#else
#define STORE                   st.d
#define LOAD                    ld.d
#define REGBYTES                8
#endif

#endif
