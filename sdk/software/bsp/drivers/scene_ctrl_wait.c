#include <rtthread.h>
#include <rthw.h>
#include "scene_ctrl.h"
#include "scene_ctrl_wait.h"

static struct rt_semaphore scene_done_sem;
static U8 scene_wait_ready;
static volatile U8 scene_observed_status;

void scene_ctrl_wait_init(void)
{
    if (scene_wait_ready) return;
    rt_sem_init(&scene_done_sem, "scene", 0, RT_IPC_FLAG_PRIO);
    scene_ctrl_irq_clear(SCENE_CTRL_IRQ_ALL);
    scene_ctrl_irq_enable(SCENE_CTRL_IRQ_FRAME_DONE | SCENE_CTRL_IRQ_ERROR);
    scene_wait_ready = 1u;
}

void scene_ctrl_wait_prepare(void)
{
    rt_base_t level;
    if (!scene_wait_ready) return;
    level = rt_hw_interrupt_disable();
    scene_observed_status = 0u;
    rt_hw_interrupt_enable(level);
    while (rt_sem_take(&scene_done_sem, 0) == RT_EOK) {}
}

void scene_ctrl_wait_isr(void)
{
    U8 status = scene_ctrl_irq_status();
    if (status == 0u) return;
    scene_observed_status |= status;
    scene_ctrl_irq_clear(status);
    (void)rt_sem_release(&scene_done_sem);
}

U8 scene_ctrl_wait_poll(U32 completed)
{
    U8 status;
    for (;;) {
        status = scene_ctrl_irq_status();
        if (status & SCENE_CTRL_IRQ_ERROR) return status;
        if (scene_ctrl_cmd_frame_count() != completed) return status | SCENE_CTRL_IRQ_FRAME_DONE;
    }
}

U8 scene_ctrl_wait_irq(U32 completed, S32 timeout_ticks)
{
    U8 status;
    for (;;) {
        status = scene_ctrl_irq_status();
        if (status & SCENE_CTRL_IRQ_ERROR) return status;
        if (scene_ctrl_cmd_frame_count() != completed) return status | SCENE_CTRL_IRQ_FRAME_DONE;
        if (rt_sem_take(&scene_done_sem, timeout_ticks) != RT_EOK) return 0u;
        status = scene_observed_status;
        scene_observed_status = 0u;
        if (status & SCENE_CTRL_IRQ_ERROR) return status;
        if (status & SCENE_CTRL_IRQ_FRAME_DONE) return status;
    }
}
