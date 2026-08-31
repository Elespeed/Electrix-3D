#ifndef GRU_CMD_BUFFER_H
#define GRU_CMD_BUFFER_H

#include "gru.h"

#define GRU_REG_CB_BASE_OFS       0x90u
#define GRU_REG_CB_WORD_COUNT_OFS 0x94u
#define GRU_REG_CB_CTRL_OFS       0x98u
#define GRU_REG_CB_STATUS_OFS     0x9cu

#define GRU_CB_CTRL_EXEC_MASK     0x1u
#define GRU_CB_CTRL_IRQ_EN_MASK   0x2u

#define GRU_CB_STATUS_BUSY        0x1u
#define GRU_CB_STATUS_DONE        0x2u
#define GRU_CB_STATUS_CFG_ERROR   0x4u
#define GRU_CB_STATUS_AXI_ERROR   0x8u
#define GRU_CB_STATUS_PRESENT     0x10u

#define GRU_CB_OP_RAW_CMD         0x20u
#define GRU_CB_OP_RAW_EXT_CMD     0x21u
#define GRU_CB_OP_FENCE           0x7eu
#define GRU_CB_OP_PRESENT         0x7fu

typedef struct {
    U32 *words;
    U16 capacity_words;
    U16 used_words;
    U8 overflow;
} gru_cmd_buffer_t;

void gru_cmd_buffer_init(gru_cmd_buffer_t *cb, U32 *storage_words, U16 capacity_words);
U8   gru_cmd_buffer_has_error(const gru_cmd_buffer_t *cb);
void gru_cmd_buffer_reset(gru_cmd_buffer_t *cb);

U8 gru_cmd_buffer_append_raw_cmd(gru_cmd_buffer_t *cb, U32 cmd_w0, U32 cmd_w1);
U8 gru_cmd_buffer_append_raw_ext_cmd(
    gru_cmd_buffer_t *cb,
    U32 cmd_w0,
    U32 cmd_w1,
    U32 ext_w0,
    U32 ext_w1,
    U32 ext_w2,
    U32 ext_w3,
    U32 ext_w4
);
U8 gru_cmd_buffer_append_fence(gru_cmd_buffer_t *cb);
U8 gru_cmd_buffer_append_present(gru_cmd_buffer_t *cb);

U8 gru_cmd_buffer_append_clear(gru_cmd_buffer_t *cb, U8 color_idx);
U8 gru_cmd_buffer_append_fill_rect(gru_cmd_buffer_t *cb, U16 x, U16 y, U16 w, U16 h, U8 color_idx);
U8 gru_cmd_buffer_append_draw_line(gru_cmd_buffer_t *cb, U16 x0, U16 y0, U16 x1, U16 y1, U8 color_idx);
U8 gru_cmd_buffer_append_draw_glyph(gru_cmd_buffer_t *cb, U16 x, U16 y, char ch, gru_font_id_t font_id, U8 color_idx);
U8 gru_cmd_buffer_append_clear_depth(gru_cmd_buffer_t *cb, U16 depth_value);
U8 gru_cmd_buffer_append_blit_rgb565(
    gru_cmd_buffer_t *cb,
    U32 src_base_addr,
    U32 src_stride_bytes,
    U16 src_x,
    U16 src_y,
    U16 dst_x,
    U16 dst_y,
    U16 width,
    U16 height
);

void gru_cmd_buffer_submit(const gru_cmd_buffer_t *cb, U8 irq_enable);
U32  gru_cmd_buffer_get_status(void);
void gru_cmd_buffer_clear_status(U32 mask);
void gru_cmd_buffer_wait_done(void);
U32  gru_cmd_buffer_wait_done_checked(void);

#endif
