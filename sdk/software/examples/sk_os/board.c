#include <stdint.h>
#include <rthw.h>
#include <rtthread.h>
#include <stdio.h>
#include "regdef.h"
#include "common_func.h"
#include "confreg_time.h"
#include "led.h"
#include "uart_print.h"
#include "regaddr.h"
#include "sketch_os.h"

void Timer_IntrHandler(void);
void Button_IntrHandler(unsigned char button_state);

/* soc_top_sketch uses the legacy four-button confreg: BTN[3:0], timer=bit4.
 * Blade2x2's confreg_board has five buttons and places its timer at bit5. */
#define SKETCH_CONFREG_BUTTON_MASK  0x0fu
#define SKETCH_CONFREG_TIMER_MASK   0x10u
#define SKETCH_CONFREG_IRQ_MASK     (SKETCH_CONFREG_BUTTON_MASK | SKETCH_CONFREG_TIMER_MASK)

static uint32_t _SysTick_Config(rt_uint32_t ticks)
{
    RegWrite(CONFREG_INT_EDGE, SKETCH_CONFREG_IRQ_MASK);
	RegWrite(CONFREG_INT_POL, SKETCH_CONFREG_IRQ_MASK);
	RegWrite(CONFREG_INT_CLR, SKETCH_CONFREG_IRQ_MASK);
	RegWrite(CONFREG_INT_EN, SKETCH_CONFREG_IRQ_MASK);

	RegWrite(CONFREG_TIMER_CMP, ticks);    //timercmp 1ms:500000
	RegWrite(CONFREG_TIMER_EN, 0x1);       //timeren

    return 0;
}


extern char __heap_start[];
extern char __heap_end[];

static void *heap_start = __heap_start;
static void *heap_end = __heap_end;

/**
 * This function will initial your board.
 */
void rt_hw_board_init()
{
    /* System Tick Configuration */
    _SysTick_Config(CONFREG_CLOCKS_PER_SEC / RT_TICK_PER_SECOND);

    /* Call components board initial (use INIT_BOARD_EXPORT()) */
#ifdef RT_USING_COMPONENTS_INIT
    rt_components_board_init();
#endif

#if defined(RT_USING_USER_MAIN) && defined(RT_USING_HEAP)
    rt_system_heap_init((void *)heap_start, (void *)heap_end);
#endif

    sketch_os_hw_init();
}

void HWI0_IntrHandler(void)
{
	unsigned int int_state;
	int_state = RegRead(CONFREG_INT_STATE);

	if((int_state & SKETCH_CONFREG_TIMER_MASK) != 0u){
		Timer_IntrHandler();
	}
	if(int_state & SKETCH_CONFREG_BUTTON_MASK){
		Button_IntrHandler((unsigned char)(int_state & SKETCH_CONFREG_BUTTON_MASK));
	}
}

void Timer_IntrHandler(void)
{
	RegWrite(CONFREG_TIMER_EN, 0);
	RegWrite(CONFREG_TIMER_EN, 1);
    rt_tick_increase();
    RegWrite(CONFREG_INT_CLR, SKETCH_CONFREG_TIMER_MASK);
}

void Button_IntrHandler(unsigned char button_state)
{
    sketch_os_on_button_irq((U8)(button_state & SKETCH_CONFREG_BUTTON_MASK));
    RegWrite(CONFREG_INT_CLR, button_state & SKETCH_CONFREG_BUTTON_MASK);
}

extern void uart_putchar(char c);

/**
* @brief  重映射串口到rt_kprintf()函数
* @param  str：要输出到串口的字符串
* @retval 无
*
* @attention
*
*/
void rt_hw_console_output(const char *str)
{
    /* 进入临界段 */
    rt_enter_critical();

    /* 直到字符串结束 */
    while (*str!='\0')
    {
		if (*str=='\n') uart_putchar('\r');
		uart_putchar(*str);
        str++;
    }

    /* 退出临界段 */
    rt_exit_critical();
}

extern unsigned long UART_BASE;

char rt_hw_console_getchar(void)
{
	char ch = -1;

    if ((*( volatile char * ) ( UART_BASE + 0x5 )) & 0x1)
    {
        ch = *((volatile unsigned char *)(UART_BASE));
    }
	else
	{
		rt_thread_mdelay(10);
	}

	return ch;
}
