#include <rthw.h>
#include <rtthread.h>

#include "cpuport.h"
#include "regdef.h"

volatile rt_ubase_t  rt_interrupt_from_thread = 0;
volatile rt_ubase_t  rt_interrupt_to_thread   = 0;
volatile rt_uint32_t rt_thread_switch_interrupt_flag = 0;

struct rt_hw_stack_frame {
    rt_ubase_t era;         /* era - era    - program counter                     */
    rt_ubase_t ra;          /* r1  - ra     - return address for jumps            */
    rt_ubase_t tp;          /* r2  - tp     - thread pointer                      */
    rt_ubase_t crmd;
    rt_ubase_t a0;          /* r4 - a0     - return value or function argument 0  */
    rt_ubase_t a1;          /* r5 - a1     - return value or function argument 1  */
    rt_ubase_t a2;          /* r6                                                 */
    rt_ubase_t a3;          /* r7                                                 */
    rt_ubase_t a4;          /* r8                                                 */
    rt_ubase_t a5;          /* r9                                                 */
    rt_ubase_t a6;          /* r10                                                */
    rt_ubase_t a7;          /* r11                                                */
    rt_ubase_t t0;          /* r12                                                */
    rt_ubase_t t1;          /* r13                                                */
    rt_ubase_t t2;          /* r14                                                */
    rt_ubase_t t3;          /* r15                                                */
    rt_ubase_t t4;          /* r16                                                */
    rt_ubase_t t5;          /* r17                                                */
    rt_ubase_t t6;          /* r18                                                */
    rt_ubase_t t7;          /* r19                                                */
    rt_ubase_t t8;          /* r20                                                */
    rt_ubase_t x ;          /* r21                                                */
    rt_ubase_t fp;          /* r22                                                */
    rt_ubase_t s0;          /* r23                                                */
    rt_ubase_t s1;          /* r24                                                */
    rt_ubase_t s2;          /* r25                                                */
    rt_ubase_t s3;          /* r26                                                */
    rt_ubase_t s4;          /* r27                                                */
    rt_ubase_t s5;          /* r28                                                */
    rt_ubase_t s6;          /* r29                                                */
    rt_ubase_t s7;          /* r30                                                */
    rt_ubase_t s8;          /* r31                                                */

    rt_ubase_t prmd;
};

/**
 * This function will initialize thread stack
 *
 * @param tentry the entry of thread
 * @param parameter the parameter of entry
 * @param stack_addr the beginning stack address
 * @param texit the function will be called when thread exit
 *
 * @return stack address
 */
rt_uint8_t *rt_hw_stack_init(void       *tentry,
                             void       *parameter,
                             rt_uint8_t *stack_addr,
                             void       *texit)
{
    struct rt_hw_stack_frame *frame;
    rt_uint8_t         *stk;
    int                i;

    stk  = stack_addr + sizeof(rt_ubase_t);
    stk  = (rt_uint8_t *)RT_ALIGN_DOWN((rt_ubase_t)stk, REGBYTES);
    stk -= sizeof(struct rt_hw_stack_frame);

    frame = (struct rt_hw_stack_frame *)stk;

    for (i = 0; i < sizeof(struct rt_hw_stack_frame) / sizeof(rt_ubase_t); i++)
    {
        ((rt_ubase_t *)frame)[i] = 0xdeadbeef;
    }

    frame->ra      = (rt_ubase_t)texit;
    frame->a0      = (rt_ubase_t)parameter;
    frame->era     = (rt_ubase_t)tentry;

    /* set PIE to 1 */
    frame->crmd = 0x0;
    frame->prmd = 0x4;

    return stk;
}

/*
 * void rt_hw_context_switch_interrupt(rt_ubase_t from, rt_ubase_t to);
 */
void rt_hw_context_switch_interrupt(rt_ubase_t from, rt_ubase_t to)
{
    if (rt_thread_switch_interrupt_flag == 0)
        rt_interrupt_from_thread = from;

    rt_interrupt_to_thread = to;
    rt_thread_switch_interrupt_flag = 1;

    return ;
}

/** shutdown CPU */
void rt_hw_cpu_shutdown()
{
    rt_uint32_t level;
    rt_kprintf("shutdown...\n");

    level = rt_hw_interrupt_disable();
    while (level)
    {
        RT_ASSERT(0);
    }
}
