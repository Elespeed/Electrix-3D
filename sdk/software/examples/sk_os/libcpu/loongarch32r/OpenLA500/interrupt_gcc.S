#include "cpuport.h"
#include "regdef.h"

 .section      .text.entry
  .align 6
  .global rtthread_irq_entry
rtthread_irq_entry:

    /* save all from thread context */
    addi.w sp, sp, -33 * REGBYTES

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
    csrrd t0, csr_prmd
    STORE t0, sp, 32 * REGBYTES

    move  s0, sp

    /* switch to interrupt stack */
    la.local    sp, _stack

    /* interrupt handle */
    bl          rt_interrupt_enter
    csrrd       a0, csr_estat
    csrrd       a1, csr_era
    move        a2, sp
    bl          handle_trap
    bl          rt_interrupt_leave

    /* switch to from thread stack */
    move        sp, s0

    /* need to switch new thread */
    la.local    s0, rt_thread_switch_interrupt_flag
    ld.w        s2, s0, 0
    beq         s2, zero, spurious_interrupt
    /* clear switch interrupt flag */
    st.w        zero, s0, 0

    csrrd a0, csr_era
    STORE a0, sp, 0 * REGBYTES

    la.local    s0, rt_interrupt_from_thread
    LOAD        s1, s0, 0
    STORE       sp, s1, 0

    la.local    s0, rt_interrupt_to_thread
    LOAD  s1, s0, 0
    LOAD  sp, s1, 0

    LOAD  a0, sp, 0 * REGBYTES
    csrwr a0, csr_era

spurious_interrupt:

    LOAD     a0, sp, 3 * REGBYTES
    li.w     t0, 0x4
    csrxchg  a0, t0, csr_crmd
    LOAD     a0, sp, 32 * REGBYTES
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


handle_trap:
    addi.w  s1, ra, 0                      /* save return address */

    srli.w  t0, a0, 16                  
    bne     zero, t0, is_exceptions
    andi    t0, a0, 0x3FC
    srli.w  t1, t0, 2         

    # 根据中断号跳转到相应的处理程序 priority
    move t2, t1            
    andi t2, t2, 0x1        
    li.w t8, 0x1 
    beq  t2, t8, handle_hwi0	  

    move t2, t1              
    andi t2, t2, 0x2          
    li.w t8, 0x2 
    beq  t2, t8, handle_hwi1	  

    move t2, t1                 
    andi t2, t2, 0x4           
    li.w t8, 0x4 
    beq  t2, t8, handle_hwi2	    

    move t2, t1                  
    andi t2, t2, 0x8             
    li.w t8, 0x8 
    beq  t2, t8, handle_hwi3	    

    move t2, t1                  
    andi t2, t2, 0x10              
    li.w t8, 0x10 
    beq  t2, t8, handle_hwi4	  

    move t2, t1                  
    andi t2, t2, 0x20             
    li.w t8, 0x20 
    beq  t2, t8, handle_hwi5	  

    move t2, t1                   
    andi t2, t2, 0x40            
    li.w t8, 0x40 
    beq  t2, t8, handle_hwi6	   

    move t2, t1
    andi t2, t2, 0x80
    li.w t8, 0x80 
    beq  t2, t8, handle_hwi7

trap_jump_exit:
    addi.w ra, s1, 0                      /* restore return address */
    jr   ra

is_exceptions:
    addi.w t8, a1, 4
    csrwr t8, csr_era
1:
    b 1b
    jr   ra


# HWI0 处理程序
handle_hwi0:

    bl HWI0_IntrHandler

    b trap_jump_exit

# HWI1 处理程序
handle_hwi1:
    b trap_jump_exit

# HWI2 处理程序
handle_hwi2:
    b trap_jump_exit

# HWI3 处理程序
handle_hwi3:
    b trap_jump_exit

# HWI4 处理程序
handle_hwi4:
    b trap_jump_exit

# HWI5 处理程序
handle_hwi5:
    b trap_jump_exit

# HWI6 处理程序
handle_hwi6:
    b trap_jump_exit

# HWI7 处理程序
handle_hwi7:
    b trap_jump_exit


.weak HWI0_IntrHandler
HWI0_IntrHandler:
1:
  b 1b
