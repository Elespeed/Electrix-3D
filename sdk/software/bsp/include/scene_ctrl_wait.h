#ifndef SCENE_CTRL_WAIT_H
#define SCENE_CTRL_WAIT_H

#include "common_func.h"

/* Called once after RT-Thread is initialized.  The IRQ is level-triggered at
 * the CPU; Scene IRQ_STATUS remains sticky until the ISR writes W1C. */
void scene_ctrl_wait_init(void);
void scene_ctrl_wait_prepare(void);
void scene_ctrl_wait_isr(void);

/* Both APIs wait for a command-frame count different from completed.  They
 * return the observed Scene IRQ status; zero means a timeout. */
U8 scene_ctrl_wait_poll(U32 completed);
U8 scene_ctrl_wait_irq(U32 completed, S32 timeout_ticks);

#endif
