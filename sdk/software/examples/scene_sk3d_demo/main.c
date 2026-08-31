#include <stdio.h>
#include "led.h"
#include "scene_ctrl.h"

unsigned long UART_BASE = 0xbf000000;
unsigned long CONFREG_TIMER_BASE = 0xbf20f100;
unsigned long CONFREG_CLOCKS_PER_SEC = 50000000L;
unsigned long CORE_CLOCKS_PER_SEC = 33000000L;

/* ExtRAM is a separate 4 MiB chip at bit22=1 in the shared 8 MiB SRAM
 * window.  Models must never consume the BaseRAM CPU image/data allocation. */
#define SCENE_MODEL_EXT_BASE 0x1c400000u
#define SCENE_MODEL_EXT_SIZE 1536u

#define SCENE_INITIAL_YAW   1u
#define SCENE_INITIAL_PITCH 0u
#define SCENE_INITIAL_ROLL  0u
#define SCENE_SCALE_Q8_8    0x0100u
#define SCENE_CENTER_X      200u
#define SCENE_CENTER_Y      150u
#define SCENE_CLEAR_COLOR   0x18u

int main(void) {
    U32 status;
    setvbuf(stdout, 0, _IONBF, 0);
    printf("SCENE SK3D START\r\n");
    scene_ctrl_configure(SCENE_MODEL_EXT_BASE, SCENE_MODEL_EXT_SIZE);
    scene_ctrl_set_rotation(SCENE_INITIAL_YAW, SCENE_INITIAL_PITCH,
                            SCENE_INITIAL_ROLL, SCENE_SCALE_Q8_8);
    scene_ctrl_set_position(SCENE_CENTER_X, SCENE_CENTER_Y, 0u);
    scene_ctrl_set_render_cfg(SCENE_CTRL_RENDER_CFG_CLEAR_BEFORE |
                              SCENE_CTRL_RENDER_CFG_AUTO_PRESENT |
                              SCENE_CTRL_RENDER_CFG_BACKFACE_CULL |
                              SCENE_CTRL_RENDER_CFG_DEPTH_SORT |
                              SCENE_CTRL_RENDER_CFG_ANIMATION,
                              SCENE_CLEAR_COLOR);
    scene_ctrl_load();
    do { status = scene_ctrl_read(SCENE_CTRL_REG_STATUS); } while (status & SCENE_CTRL_STATUS_BUSY);
    if ((status & (SCENE_CTRL_STATUS_ERROR | SCENE_CTRL_STATUS_MODEL_VALID)) != SCENE_CTRL_STATUS_MODEL_VALID) {
        printf("SCENE SK3D LOAD FAIL %u\r\n", scene_ctrl_error_code()); setLedPin(0xf000u); for (;;) {}
    }
    scene_ctrl_render();
    /* Animation keeps Scene busy while it owns SketchBook, so success means
     * the cached model was accepted and the autonomous renderer was started. */
    printf("SCENE SK3D PASS\r\n");
    setLedPin(0x00ffu);
    for (;;) {
        status = scene_ctrl_read(SCENE_CTRL_REG_STATUS);
        if (status & SCENE_CTRL_STATUS_ERROR) {
            printf("SCENE SK3D RENDER FAIL %u\r\n", scene_ctrl_error_code());
            setLedPin(0xf000u);
            for (;;) {}
        }
    }
}
