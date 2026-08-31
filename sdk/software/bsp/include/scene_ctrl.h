#ifndef SCENE_CTRL_H
#define SCENE_CTRL_H

#include "common_func.h"

#define SCENE_CTRL_BASE_ADDR 0xbf400000u
#define SCENE_CTRL_REG_CTRL 0x00u
#define SCENE_CTRL_REG_STATUS 0x04u
#define SCENE_CTRL_REG_MODEL_BASE 0x08u
#define SCENE_CTRL_REG_MODEL_SIZE 0x0cu
#define SCENE_CTRL_REG_MODEL_INFO 0x10u
#define SCENE_CTRL_REG_ROTATION0 0x14u
#define SCENE_CTRL_REG_ROTATION1 0x18u
#define SCENE_CTRL_REG_POSITION 0x1cu
#define SCENE_CTRL_REG_TRANSLATE_Z 0x20u
#define SCENE_CTRL_REG_RENDER_CFG 0x24u
#define SCENE_CTRL_REG_CLEAR_COLOR 0x28u
#define SCENE_CTRL_REG_VIEWPORT_ORIGIN 0x2cu
#define SCENE_CTRL_REG_VIEWPORT_SIZE 0x30u
#define SCENE_CTRL_REG_VIEWPORT_CFG 0x34u
#define SCENE_CTRL_REG_CMD_CFG 0x38u
#define SCENE_CTRL_REG_CMD_WORD0 0x3cu
#define SCENE_CTRL_REG_CMD_WORD1 0x40u
#define SCENE_CTRL_REG_CMD_WORD2 0x44u
#define SCENE_CTRL_REG_CMD_WORD3 0x48u
#define SCENE_CTRL_REG_CMD_PUSH 0x4cu
#define SCENE_CTRL_REG_CMD_FRAME_START 0x50u
#define SCENE_CTRL_REG_CMD_STATUS 0x54u

#define SCENE_CTRL_CTRL_ABORT 0x08u
#define SCENE_CTRL_CTRL_LOAD_START 0x02u
#define SCENE_CTRL_CTRL_RENDER_START 0x04u
#define SCENE_CTRL_STATUS_BUSY 0x01u
#define SCENE_CTRL_STATUS_LOAD_DONE 0x02u
#define SCENE_CTRL_STATUS_RENDER_DONE 0x04u
#define SCENE_CTRL_STATUS_ERROR 0x08u
#define SCENE_CTRL_STATUS_MODEL_VALID 0x20u

#define SCENE_CTRL_RENDER_CFG_CLEAR_BEFORE 0x01u
#define SCENE_CTRL_RENDER_CFG_AUTO_PRESENT 0x02u
#define SCENE_CTRL_RENDER_CFG_BACKFACE_CULL 0x04u
#define SCENE_CTRL_RENDER_CFG_DEPTH_SORT 0x08u
#define SCENE_CTRL_RENDER_CFG_ANIMATION 0x10u
#define SCENE_CTRL_RENDER_CFG_KEEP_CURRENT_FRAME 0x20u

#define SCENE_CTRL_VIEWPORT_ENABLE 0x01u
#define SCENE_CTRL_VIEWPORT_LOCAL_CLEAR 0x02u

#define SCENE_CTRL_CMD_STATUS_READY 0x01u
#define SCENE_CTRL_CMD_STATUS_FULL 0x02u
#define SCENE_CTRL_CMD_STATUS_LOCKED 0x04u
#define SCENE_CTRL_CMD_STATUS_LEVEL_SHIFT 7u
#define SCENE_CTRL_CMD_STATUS_MESH_SHIFT 12u
#define SCENE_CTRL_CMD_STATUS_FRAME_SHIFT 16u

#define SCENE_CTRL_CMD_CLEAR 1u
#define SCENE_CTRL_CMD_DRAW 2u
#define SCENE_CTRL_CMD_PRESENT 3u

typedef struct {
    U32 word0;
    U32 word1;
    U32 word2;
    U32 word3;
} scene_ctrl_cmd_t;

static inline void scene_ctrl_write(U32 offset, U32 value) { *(volatile U32 *)(SCENE_CTRL_BASE_ADDR + offset) = value; }
static inline U32 scene_ctrl_read(U32 offset) { return *(volatile U32 *)(SCENE_CTRL_BASE_ADDR + offset); }
static inline void scene_ctrl_configure(U32 base, U32 size) { scene_ctrl_write(SCENE_CTRL_REG_MODEL_BASE, base); scene_ctrl_write(SCENE_CTRL_REG_MODEL_SIZE, size); }
static inline void scene_ctrl_set_rotation(U16 yaw, U16 pitch, U16 roll, U16 scale) {
    scene_ctrl_write(SCENE_CTRL_REG_ROTATION0, ((U32)pitch << 16) | yaw);
    scene_ctrl_write(SCENE_CTRL_REG_ROTATION1, ((U32)scale << 16) | roll);
}
static inline void scene_ctrl_set_position(U16 center_x, U16 center_y, U16 translate_z) {
    scene_ctrl_write(SCENE_CTRL_REG_POSITION, ((U32)center_y << 16) | center_x);
    scene_ctrl_write(SCENE_CTRL_REG_TRANSLATE_Z, translate_z);
}
static inline void scene_ctrl_set_render_cfg(U8 render_cfg, U8 clear_color) {
    scene_ctrl_write(SCENE_CTRL_REG_RENDER_CFG, render_cfg);
    scene_ctrl_write(SCENE_CTRL_REG_CLEAR_COLOR, clear_color);
}
static inline void scene_ctrl_set_viewport(U16 x, U16 y, U16 width, U16 height, U8 cfg) {
    scene_ctrl_write(SCENE_CTRL_REG_VIEWPORT_ORIGIN, ((U32)y << 16) | x);
    scene_ctrl_write(SCENE_CTRL_REG_VIEWPORT_SIZE, ((U32)height << 16) | width);
    scene_ctrl_write(SCENE_CTRL_REG_VIEWPORT_CFG, cfg);
}
static inline void scene_ctrl_load(void) { scene_ctrl_write(SCENE_CTRL_REG_CTRL, SCENE_CTRL_CTRL_LOAD_START); }
static inline void scene_ctrl_render(void) { scene_ctrl_write(SCENE_CTRL_REG_CTRL, SCENE_CTRL_CTRL_RENDER_START); }
static inline void scene_ctrl_abort(void) { scene_ctrl_write(SCENE_CTRL_REG_CTRL, SCENE_CTRL_CTRL_ABORT); }
static inline U8 scene_ctrl_error_code(void) { return (U8)(scene_ctrl_read(SCENE_CTRL_REG_STATUS) >> 8); }
static inline void scene_ctrl_cmd_enable(void) { scene_ctrl_write(SCENE_CTRL_REG_CMD_CFG, 1u); }
static inline U32 scene_ctrl_cmd_status(void) { return scene_ctrl_read(SCENE_CTRL_REG_CMD_STATUS); }
static inline U32 scene_ctrl_cmd_frame_count(void) { return scene_ctrl_cmd_status() >> SCENE_CTRL_CMD_STATUS_FRAME_SHIFT; }
static inline U8 scene_ctrl_cmd_mesh_count(void) { return (U8)((scene_ctrl_cmd_status() >> SCENE_CTRL_CMD_STATUS_MESH_SHIFT) & 0x0fu); }
static inline void scene_ctrl_cmd_stage(const scene_ctrl_cmd_t *cmd) {
    scene_ctrl_write(SCENE_CTRL_REG_CMD_WORD0, cmd->word0);
    scene_ctrl_write(SCENE_CTRL_REG_CMD_WORD1, cmd->word1);
    scene_ctrl_write(SCENE_CTRL_REG_CMD_WORD2, cmd->word2);
    scene_ctrl_write(SCENE_CTRL_REG_CMD_WORD3, cmd->word3);
}
static inline void scene_ctrl_cmd_push(const scene_ctrl_cmd_t *cmd) {
    while (!(scene_ctrl_cmd_status() & SCENE_CTRL_CMD_STATUS_READY)) {}
    scene_ctrl_cmd_stage(cmd);
    scene_ctrl_write(SCENE_CTRL_REG_CMD_PUSH, 1u);
}
static inline void scene_ctrl_cmd_start_frame(void) { scene_ctrl_write(SCENE_CTRL_REG_CMD_FRAME_START, 1u); }
static inline scene_ctrl_cmd_t scene_ctrl_cmd_clear(U8 color) {
    scene_ctrl_cmd_t cmd = { SCENE_CTRL_CMD_CLEAR, 0u, 0u, (U32)color };
    return cmd;
}
static inline scene_ctrl_cmd_t scene_ctrl_cmd_present(void) {
    scene_ctrl_cmd_t cmd = { SCENE_CTRL_CMD_PRESENT, 0u, 0u, 0u };
    return cmd;
}
static inline scene_ctrl_cmd_t scene_ctrl_cmd_draw(U8 mesh, S16 x, S16 y, S16 z, U8 yaw, U8 pitch, U8 roll, U16 scale) {
    scene_ctrl_cmd_t cmd;
    cmd.word0 = SCENE_CTRL_CMD_DRAW | ((U32)(mesh & 0x0fu) << 8) | ((U32)(U16)x << 16);
    cmd.word1 = (U32)(U16)y | ((U32)(U16)z << 16);
    cmd.word2 = ((U32)(yaw & 0x0fu) << 0) | ((U32)(pitch & 0x0fu) << 4) | ((U32)(roll & 0x0fu) << 8) | ((U32)scale << 16);
    cmd.word3 = 0u;
    return cmd;
}
#endif
