#include <stdio.h>
#include <rtthread.h>

#include "confreg_time.h"

unsigned long UART_BASE = 0xbf000000;
unsigned long CONFREG_TIMER_BASE = 0xbf20f100;
unsigned long CONFREG_CLOCKS_PER_SEC = 50000000L;
unsigned long CORE_CLOCKS_PER_SEC = 33000000L;

int main(void)
{
    setvbuf(stdout, 0, _IONBF, 0);
    rt_kprintf("SK_OS main thread online\n");
    return 0;
}
