#include <rthw.h>
#include <rtthread.h>
#include "regaddr.h"
#include "common_func.h"
#include "confreg_time.h"
#include "uart_print.h"
#include "scene_ctrl_wait.h"

#define RT3D_CONFREG_TIMER_MASK 0x10u
#define RT3D_CONFREG_SCENE_MASK 0x40u
#define RT3D_CONFREG_IRQ_MASK (RT3D_CONFREG_TIMER_MASK | RT3D_CONFREG_SCENE_MASK)

extern void uart_putchar(char c);
extern void rt_system_heap_init(void *begin_addr, void *end_addr);
extern unsigned char __heap_start;
extern unsigned char __heap_end;

unsigned long UART_BASE = 0xbf000000;
unsigned long CONFREG_TIMER_BASE = 0xbf20f100;
unsigned long CONFREG_CLOCKS_PER_SEC = 50000000L;
unsigned long CORE_CLOCKS_PER_SEC = 33000000L;

static void rt3d_systick_config(rt_uint32_t ticks)
{
    RegWrite(CONFREG_INT_EDGE, RT3D_CONFREG_TIMER_MASK);
    RegWrite(CONFREG_INT_POL, RT3D_CONFREG_IRQ_MASK);
    RegWrite(CONFREG_INT_CLR, RT3D_CONFREG_IRQ_MASK);
    RegWrite(CONFREG_INT_EN, RT3D_CONFREG_IRQ_MASK);
    RegWrite(CONFREG_TIMER_CMP, ticks);
    RegWrite(CONFREG_TIMER_EN, 1u);
}

void rt_hw_board_init(void)
{
    rt_system_heap_init(&__heap_start, &__heap_end);
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
    U32 state = RegRead(CONFREG_INT_STATE);
    if (state & RT3D_CONFREG_TIMER_MASK) Timer_IntrHandler();
    if (state & RT3D_CONFREG_SCENE_MASK) scene_ctrl_wait_isr();
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
