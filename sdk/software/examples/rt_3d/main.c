#include <stdio.h>
#include <rtthread.h>
#include "rt_3d.h"
#include "rt3d_metrics.h"

static void rt3d_background(void *parameter)
{
    (void)parameter;
    for (;;) {
        (void)rt3d_background_step();
        rt_thread_mdelay(10);
    }
}

int main(void)
{
    rt_thread_t background;
    setvbuf(stdout, 0, _IONBF, 0);
    background = rt_thread_create("rt3dbg", rt3d_background, RT_NULL,
                                  1024, RT3D_BACKGROUND_PRIORITY, 20);
    if (background != RT_NULL) rt_thread_startup(background);
    rt_kprintf("RT3D START backend=%s warmup=%u frames=%u reps=%u\n",
               rt3d_backend_name(), RT3D_WARMUP_FRAMES,
               RT3D_FORMAL_FRAMES, RT3D_REPETITIONS);
    rt3d_run();
    rt_kprintf("RT3D COMPLETE\n");
    for (;;) rt_thread_mdelay(1000);
    return 0;
}
