#include "gru_cmd_buffer.h"

#define GRU_CB_BASE_REG       (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_CB_BASE_OFS))
#define GRU_CB_WORD_COUNT_REG (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_CB_WORD_COUNT_OFS))
#define GRU_CB_CTRL_REG       (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_CB_CTRL_OFS))
#define GRU_CB_STATUS_REG     (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_CB_STATUS_OFS))

static U32 gru_pack_w0(gru_opcode_t opcode, U8 color_idx, U8 font_id, U16 x0, U8 y0)
{
    return (((U32)y0 & 0xffu) << 24) |
           (((U32)x0 & 0x1ffu) << 15) |
           (((U32)font_id & 0x3u) << 13) |
           (((U32)color_idx & 0xffu) << 5) |
           ((U32)opcode & 0x1fu);
}

static U32 gru_pack_w1_xy(U16 x1, U8 y1)
{
    return (((U32)y1 & 0xffu) << 9) |
           ((U32)x1 & 0x1ffu);
}

static U32 gru_pack_w1_ascii(char ch)
{
    return (U32)(U8)ch;
}

static U32 gru_pack_w1_size(U16 width, U16 height)
{
    return (((U32)height & 0xffffu) << 16) |
           ((U32)width & 0xffffu);
}

static U32 gru_pack_xy16(U16 x, U16 y)
{
    return (((U32)y & 0xffffu) << 16) |
           ((U32)x & 0xffffu);
}

static U8 gru_cmd_buffer_reserve(gru_cmd_buffer_t *cb, U16 word_count)
{
    if ((cb == 0) || (cb->words == 0)) {
        return 0u;
    }
    if ((U32)cb->used_words + (U32)word_count > (U32)cb->capacity_words) {
        cb->overflow = 1u;
        return 0u;
    }
    return 1u;
}

static void gru_cmd_buffer_push_header(gru_cmd_buffer_t *cb, U8 opcode, U16 total_words)
{
    cb->words[cb->used_words++] = ((U32)opcode << 24) | (U32)total_words;
}

void gru_cmd_buffer_init(gru_cmd_buffer_t *cb, U32 *storage_words, U16 capacity_words)
{
    if (cb == 0) {
        return;
    }
    cb->words = storage_words;
    cb->capacity_words = capacity_words;
    cb->used_words = 0u;
    cb->overflow = 0u;
}

U8 gru_cmd_buffer_has_error(const gru_cmd_buffer_t *cb)
{
    if (cb == 0) {
        return 1u;
    }
    return cb->overflow;
}

void gru_cmd_buffer_reset(gru_cmd_buffer_t *cb)
{
    if (cb == 0) {
        return;
    }
    cb->used_words = 0u;
    cb->overflow = 0u;
}

U8 gru_cmd_buffer_append_raw_cmd(gru_cmd_buffer_t *cb, U32 cmd_w0, U32 cmd_w1)
{
    if (!gru_cmd_buffer_reserve(cb, 3u)) {
        return 0u;
    }
    gru_cmd_buffer_push_header(cb, GRU_CB_OP_RAW_CMD, 3u);
    cb->words[cb->used_words++] = cmd_w0;
    cb->words[cb->used_words++] = cmd_w1;
    return 1u;
}

U8 gru_cmd_buffer_append_raw_ext_cmd(
    gru_cmd_buffer_t *cb,
    U32 cmd_w0,
    U32 cmd_w1,
    U32 ext_w0,
    U32 ext_w1,
    U32 ext_w2,
    U32 ext_w3,
    U32 ext_w4
)
{
    if (!gru_cmd_buffer_reserve(cb, 8u)) {
        return 0u;
    }
    gru_cmd_buffer_push_header(cb, GRU_CB_OP_RAW_EXT_CMD, 8u);
    cb->words[cb->used_words++] = cmd_w0;
    cb->words[cb->used_words++] = cmd_w1;
    cb->words[cb->used_words++] = ext_w0;
    cb->words[cb->used_words++] = ext_w1;
    cb->words[cb->used_words++] = ext_w2;
    cb->words[cb->used_words++] = ext_w3;
    cb->words[cb->used_words++] = ext_w4;
    return 1u;
}

U8 gru_cmd_buffer_append_fence(gru_cmd_buffer_t *cb)
{
    if (!gru_cmd_buffer_reserve(cb, 1u)) {
        return 0u;
    }
    gru_cmd_buffer_push_header(cb, GRU_CB_OP_FENCE, 1u);
    return 1u;
}

U8 gru_cmd_buffer_append_present(gru_cmd_buffer_t *cb)
{
    if (!gru_cmd_buffer_reserve(cb, 1u)) {
        return 0u;
    }
    gru_cmd_buffer_push_header(cb, GRU_CB_OP_PRESENT, 1u);
    return 1u;
}

U8 gru_cmd_buffer_append_clear(gru_cmd_buffer_t *cb, U8 color_idx)
{
    return gru_cmd_buffer_append_raw_cmd(cb, gru_pack_w0(GRU_OP_CLEAR, color_idx, 0u, 0u, 0u), 0u);
}

U8 gru_cmd_buffer_append_fill_rect(gru_cmd_buffer_t *cb, U16 x, U16 y, U16 w, U16 h, U8 color_idx)
{
    U16 x1;
    U8 y1;

    if ((w == 0u) || (h == 0u)) {
        return 1u;
    }

    x1 = (U16)(x + w - 1u);
    y1 = (U8)(y + h - 1u);
    return gru_cmd_buffer_append_raw_cmd(
        cb,
        gru_pack_w0(GRU_OP_FILL_RECT, color_idx, 0u, x, (U8)y),
        gru_pack_w1_xy(x1, y1)
    );
}

U8 gru_cmd_buffer_append_draw_line(gru_cmd_buffer_t *cb, U16 x0, U16 y0, U16 x1, U16 y1, U8 color_idx)
{
    return gru_cmd_buffer_append_raw_cmd(
        cb,
        gru_pack_w0(GRU_OP_DRAW_LINE, color_idx, 0u, x0, (U8)y0),
        gru_pack_w1_xy(x1, (U8)y1)
    );
}

U8 gru_cmd_buffer_append_draw_glyph(gru_cmd_buffer_t *cb, U16 x, U16 y, char ch, gru_font_id_t font_id, U8 color_idx)
{
    return gru_cmd_buffer_append_raw_cmd(
        cb,
        gru_pack_w0(GRU_OP_DRAW_GLYPH, color_idx, (U8)font_id, x, (U8)y),
        gru_pack_w1_ascii(ch)
    );
}

U8 gru_cmd_buffer_append_clear_depth(gru_cmd_buffer_t *cb, U16 depth_value)
{
    return gru_cmd_buffer_append_raw_cmd(
        cb,
        gru_pack_w0(GRU_OP_CLEAR_DEPTH, 0u, 0u, 0u, 0u),
        (U32)depth_value
    );
}

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
)
{
    if ((width == 0u) || (height == 0u)) {
        return 1u;
    }

    return gru_cmd_buffer_append_raw_ext_cmd(
        cb,
        gru_pack_w0(GRU_OP_BLIT, 0u, 0u, 0u, 0u),
        gru_pack_w1_size(width, height),
        src_base_addr,
        src_stride_bytes,
        gru_pack_xy16(src_x, src_y),
        gru_pack_xy16(dst_x, dst_y),
        0u
    );
}

void gru_cmd_buffer_submit(const gru_cmd_buffer_t *cb, U8 irq_enable)
{
    U32 ctrl = GRU_CB_CTRL_EXEC_MASK;

    if ((cb == 0) || (cb->words == 0) || (cb->used_words == 0u)) {
        return;
    }
    if (irq_enable != 0u) {
        ctrl |= GRU_CB_CTRL_IRQ_EN_MASK;
    }

    GRU_CB_BASE_REG = (U32)cb->words;
    GRU_CB_WORD_COUNT_REG = (U32)cb->used_words;
    __asm__ volatile("" : : : "memory");
    GRU_CB_CTRL_REG = ctrl;
    __asm__ volatile("" : : : "memory");
}

U32 gru_cmd_buffer_get_status(void)
{
    return GRU_CB_STATUS_REG;
}

void gru_cmd_buffer_clear_status(U32 mask)
{
    GRU_CB_STATUS_REG = mask;
    __asm__ volatile("" : : : "memory");
}

void gru_cmd_buffer_wait_done(void)
{
    while ((gru_cmd_buffer_get_status() & GRU_CB_STATUS_DONE) == 0u) {
    }
}

U32 gru_cmd_buffer_wait_done_checked(void)
{
    U32 status;

    do {
        status = gru_cmd_buffer_get_status();
    } while ((status & GRU_CB_STATUS_DONE) == 0u);

    return status;
}
