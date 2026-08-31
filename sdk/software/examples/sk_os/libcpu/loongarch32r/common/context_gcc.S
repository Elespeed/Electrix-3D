#include "cpuport.h"
#include "regdef.h"

/*
 * rt_base_t rt_hw_interrupt_disable(void);
 */
    .globl rt_hw_interrupt_disable
rt_hw_interrupt_disable:
    addi.w      sp, sp, -4
    st.w        t0, sp, 0
    li.w        a0, 0
    li.w        t0, 0x4
    csrxchg     a0, t0, csr_crmd
    ld.w        t0, sp, 0
    addi.w      sp, sp, 4
    jr          ra

/*
 * void rt_hw_interrupt_enable(rt_base_t level);
 */
    .globl rt_hw_interrupt_enable
rt_hw_interrupt_enable:
    addi.w      sp, sp, -4
    st.w        t0, sp, 0
    li.w        t0, 0x4
    csrxchg     a0, t0, csr_crmd
    ld.w        t0, sp, 0
    addi.w      sp, sp, 4
    jr          ra

/*
 * void rt_hw_context_switch_to(rt_ubase_t to);
 * a0 --> to
 */
    .globl rt_hw_context_switch_to
rt_hw_context_switch_to:
    LOAD sp, a0, 0
    b    rt_hw_context_switch_exit

/*
 * void rt_hw_context_switch(rt_ubase_t from, rt_ubase_t to);
 *
 * a0 --> from
 * a1 --> to
 */
    .globl rt_hw_context_switch
rt_hw_context_switch:
    /* saved from thread context
     *     ra       -> sp(0)
     *     ra       -> sp(1)
     *     tp       -> sp(2)
     *     crmd.ie  -> sp(3)
     *     r(i)     -> sp(i)
     *     prmd.pie -> sp(32)
     */
    addi.w  sp, sp, -33 * REGBYTES
    STORE   sp, a0, 0

    STORE ra, sp, 0 * REGBYTES
    STORE ra, sp, 1 * REGBYTES
    STORE tp, sp, 2 * REGBYTES
    
    STORE zero, sp, 3 * REGBYTES
    STORE a0, sp, 4 * REGBYTES
    STORE a1, sp, 5 * REGBYTES
    STORE a2, sp, 6 * REGBYTES
    STORE a3, sp, 7 * REGBYTES
    STORE a4, sp, 8 * REGBYTES
    STORE a5, sp, 9 * REGBYTES
    STORE a6, sp, 10 * REGBYTES
    STORE a7, sp, 11 * REGBYTES
    STORE t0, sp, 12 * REGBYTES
    STORE t1, sp, 13 * REGBYTES
    STORE t2, sp, 14 * REGBYTES
    STORE t3, sp, 15 * REGBYTES
    STORE t4, sp, 16 * REGBYTES
    STORE t5, sp, 17 * REGBYTES
    STORE t6, sp, 18 * REGBYTES
    STORE t7, sp, 19 * REGBYTES
    STORE t8, sp, 20 * REGBYTES
    STORE $r21, sp,21 * REGBYTES
    STORE fp, sp, 22 * REGBYTES
    STORE s0, sp, 23 * REGBYTES
    STORE s1, sp, 24 * REGBYTES
    STORE s2, sp, 25 * REGBYTES
    STORE s3, sp, 26 * REGBYTES
    STORE s4, sp, 27 * REGBYTES
    STORE s5, sp, 28 * REGBYTES
    STORE s6, sp, 29 * REGBYTES
    STORE s7, sp, 30 * REGBYTES
    STORE s8, sp, 31 * REGBYTES
    
    csrrd a0, csr_crmd
    andi a0, a0, 4

    STORE a0, sp, 32 * REGBYTES

    /* restore to thread context
     * sp(0) -> era;
     * sp(1) -> ra;
     * sp(i) -> x(i+2)
     */
    LOAD sp, a1, 0

    b rt_hw_context_switch_exit


.global rt_hw_context_switch_exit
rt_hw_context_switch_exit:
    /* resw ra to mepc */
    LOAD a0, sp, 0 * REGBYTES
    csrwr a0, csr_era

    LOAD a0, sp, 3 * REGBYTES
    li.w     t0, 0x4
    csrxchg  a0, t0, csr_crmd
    LOAD a0, sp, 32 * REGBYTES
    csrxchg  a0, t0, csr_prmd

    LOAD ra, sp, 1 * REGBYTES
    LOAD tp, sp, 2 * REGBYTES
    LOAD a0, sp, 4 * REGBYTES
    LOAD a1, sp, 5 * REGBYTES
    LOAD a2, sp, 6 * REGBYTES
    LOAD a3, sp, 7 * REGBYTES
    LOAD a4, sp, 8 * REGBYTES
    LOAD a5, sp, 9 * REGBYTES
    LOAD a6, sp, 10 * REGBYTES
    LOAD a7, sp, 11 * REGBYTES
    LOAD t0, sp, 12 * REGBYTES
    LOAD t1, sp, 13 * REGBYTES
    LOAD t2, sp, 14 * REGBYTES
    LOAD t3, sp, 15 * REGBYTES
    LOAD t4, sp, 16 * REGBYTES
    LOAD t5, sp, 17 * REGBYTES
    LOAD t6, sp, 18 * REGBYTES
    LOAD t7, sp, 19 * REGBYTES
    LOAD t8, sp, 20 * REGBYTES
    LOAD $r21, sp,21 * REGBYTES
    LOAD fp, sp, 22 * REGBYTES
    LOAD s0, sp, 23 * REGBYTES
    LOAD s1, sp, 24 * REGBYTES
    LOAD s2, sp, 25 * REGBYTES
    LOAD s3, sp, 26 * REGBYTES
    LOAD s4, sp, 27 * REGBYTES
    LOAD s5, sp, 28 * REGBYTES
    LOAD s6, sp, 29 * REGBYTES
    LOAD s7, sp, 30 * REGBYTES
    LOAD s8, sp, 31 * REGBYTES

    addi.w sp, sp, 33 * REGBYTES

    ertn
