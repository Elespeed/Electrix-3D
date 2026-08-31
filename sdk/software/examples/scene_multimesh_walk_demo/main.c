#include <stdio.h>
#include "led.h"
#include "scene_ctrl.h"

unsigned long UART_BASE = 0xbf000000;
unsigned long CONFREG_TIMER_BASE = 0xbf20f100;
unsigned long CONFREG_CLOCKS_PER_SEC = 50000000L;
unsigned long CORE_CLOCKS_PER_SEC = 33000000L;

#define ROBOT_MODEL_BASE 0x1c400000u
#define ROBOT_MODEL_SIZE 1856u
#define ROBOT_MESH_COUNT 5u
#define WALK_FRAMES 16u
#define WALK_CLEAR_COLOR 0x1cu

static U8 walk_phase(U8 n) {
    switch (n) {
    case 0: case 8: return 0u;
    case 1: case 7: return 1u;
    case 2: case 3: case 4: case 5: case 6: return 2u;
    case 9: case 15: return 15u;
    default: return 14u;
    }
}

static void submit_frame(U8 frame) {
    U8 phase = walk_phase(frame);
    U8 opposite = walk_phase((U8)((frame + 8u) & 15u));
    scene_ctrl_cmd_t cmd;
    cmd = scene_ctrl_cmd_clear(WALK_CLEAR_COLOR); scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_draw(0u, -11, -25, 0, 0u, phase, 0u, 0x0100u); scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_draw(1u,  11, -25, 0, 0u, opposite, 0u, 0x0100u); scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_draw(2u, -18,  11, 0, 0u, opposite, 0u, 0x0100u); scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_draw(3u,  18,  11, 0, 0u, phase, 0u, 0x0100u); scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_draw(4u,   0,  31, 0, 0u, 0u, 0u, 0x0100u); scene_ctrl_cmd_push(&cmd);
    cmd = scene_ctrl_cmd_present(); scene_ctrl_cmd_push(&cmd);
    scene_ctrl_cmd_start_frame();
}

int main(void) {
    U32 status;
    U32 completed;
    U8 frame;
    U32 cycles = 0;

    setvbuf(stdout, 0, _IONBF, 0);
    printf("SCENE ROBOT WALK START\r\n");
    scene_ctrl_cmd_enable();
    scene_ctrl_configure(ROBOT_MODEL_BASE, ROBOT_MODEL_SIZE);
    scene_ctrl_load();
    do { status = scene_ctrl_read(SCENE_CTRL_REG_STATUS); } while (status & SCENE_CTRL_STATUS_BUSY);
    if ((status & (SCENE_CTRL_STATUS_ERROR | SCENE_CTRL_STATUS_MODEL_VALID)) != SCENE_CTRL_STATUS_MODEL_VALID ||
        (scene_ctrl_cmd_mesh_count() != ROBOT_MESH_COUNT)) {
        printf("SCENE ROBOT WALK LOAD FAIL %u\r\n", scene_ctrl_error_code());
        setLedPin(0xf000u);
        for (;;) {}
    }
    printf("SCENE ROBOT WALK LOADED meshes=%u\r\n", ROBOT_MESH_COUNT);
    setLedPin(0x00ffu);
    for (;;) {
        for (frame = 0; frame < WALK_FRAMES; ++frame) {
            completed = scene_ctrl_cmd_frame_count();
            submit_frame(frame);
            while (scene_ctrl_cmd_frame_count() == completed) {
                if (scene_ctrl_read(SCENE_CTRL_REG_STATUS) & SCENE_CTRL_STATUS_ERROR) {
                    printf("SCENE ROBOT WALK FAIL frame=%u code=%u\r\n", frame, scene_ctrl_error_code());
                    setLedPin(0xf000u);
                    for (;;) {}
                }
            }
        }
        ++cycles;
        printf("SCENE ROBOT WALK PASS cycle=%u\r\n", cycles);
    }
}
