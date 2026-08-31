#include <rthw.h>
#include <rtthread.h>
#include "regaddr.h"
#include "common_func.h"
#include "confreg_time.h"
#include "uart_print.h"

extern void uart_putchar(char c);

unsigned long UART_BASE = 0xbf000000;
unsigned long CONFREG_TIMER_BASE = 0xbf20f100;
unsigned long CONFREG_CLOCKS_PER_SEC = 50000000L;
unsigned long CORE_CLOCKS_PER_SEC = 33000000L;

static void rt3d_systick_config(rt_uint32_t ticks)
{
    RegWrite(CONFREG_INT_EDGE, 0x10u);
    RegWrite(CONFREG_INT_POL, 0x10u);
    RegWrite(CONFREG_INT_CLR, 0x10u);
    RegWrite(CONFREG_INT_EN, 0x10u);
    RegWrite(CONFREG_TIMER_CMP, ticks);
    RegWrite(CONFREG_TIMER_EN, 1u);
}

void rt_hw_board_init(void)
{
    rt3d_systick_config(CONFREG_CLOCKS_PER_SEC / RT_TICK_PER_SECOND);
}

void Timer_IntrHandler(void)
{
    RegWrite(CONFREG_TIMER_EN, 0);
    RegWrite(CONFREG_TIMER_EN, 1);
    rt_tick_increase();
    RegWrite(CONFREG_INT_CLR, 0x10u);
}

void HWI0_IntrHandler(void)
{
    if (RegRead(CONFREG_INT_STATE) & 0x10u) Timer_IntrHandler();
}

void rt_hw_console_output(const char *str)
{
    while (*str) {
        if (*str == '\n') uart_putchar('\r');
        uart_putchar(*str++);
    }
}

char rt_hw_console_getchar(void)
{
    return -1;
}
