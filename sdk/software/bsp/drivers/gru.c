#include "gru.h"
#include "uart_io.h"

#define GRU_CTRL_REG         (*(volatile U32 *)(GRU_BASE_ADDR + 0x00))
#define GRU_STATUS_REG       (*(volatile U32 *)(GRU_BASE_ADDR + 0x04))
#define GRU_FB_BASE_REG      (*(volatile U32 *)(GRU_BASE_ADDR + 0x08))
#define GRU_STRIDE_REG       (*(volatile U32 *)(GRU_BASE_ADDR + 0x0c))
#define GRU_WIDTH_HEIGHT_REG (*(volatile U32 *)(GRU_BASE_ADDR + 0x10))
#define GRU_CMD_W0_REG       (*(volatile U32 *)(GRU_BASE_ADDR + 0x18))
#define GRU_CMD_W1_REG       (*(volatile U32 *)(GRU_BASE_ADDR + 0x1c))
#define GRU_CMD_PUSH_REG     (*(volatile U32 *)(GRU_BASE_ADDR + 0x20))
#define GRU_CMD_LEVEL_REG    (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_CMD_LEVEL_OFS))
#define GRU_EXT_W0_REG       (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_EXT_W0_OFS))
#define GRU_EXT_W1_REG       (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_EXT_W1_OFS))
#define GRU_EXT_W2_REG       (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_EXT_W2_OFS))
#define GRU_EXT_W3_REG       (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_EXT_W3_OFS))
#define GRU_EXT_W4_REG       (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_EXT_W4_OFS))
#define GRU_EXT_PUSH_REG     (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_EXT_PUSH_OFS))
#define GRU_DEPTH_BASE_REG   (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_DEPTH_BASE_OFS))
#define GRU_DEPTH_CTRL_REG   (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_DEPTH_CTRL_OFS))
#define GRU_TEX_BASE_REG     (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_TEX_BASE_OFS))
#define GRU_TEX_SIZE_REG     (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_TEX_SIZE_OFS))
#define GRU_TEX_STRIDE_REG   (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_TEX_STRIDE_OFS))
#define GRU_TEX_CTRL_REG     (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_TEX_CTRL_OFS))
#define GRU_PERF_WCB_SPAN_IN   (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_WCB_SPAN_IN_OFS))
#define GRU_PERF_WCB_PIX_IN    (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_WCB_PIX_IN_OFS))
#define GRU_PERF_WCB_AW_TXN    (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_WCB_AW_TXN_OFS))
#define GRU_PERF_WCB_BEAT_OUT  (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_WCB_BEAT_OUT_OFS))
#define GRU_PERF_WCB_FULL_BEAT (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_WCB_FULL_BEAT_OFS))
#define GRU_PERF_WCB_PARTIAL   (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_WCB_PARTIAL_OFS))
#define GRU_PERF_WCB_FLUSH     (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_WCB_FLUSH_OFS))
#define GRU_PERF_BLIT_COUNT    (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_BLIT_COUNT_OFS))
#define GRU_PERF_BLIT_RD_BEAT  (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_BLIT_RD_BEAT_OFS))
#define GRU_PERF_BLIT_WR_BEAT  (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_BLIT_WR_BEAT_OFS))
#define GRU_PERF_BLIT_PIXEL    (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_BLIT_PIXEL_OFS))
#define GRU_PERF_BLIT_CYCLE    (*(volatile U32 *)(GRU_BASE_ADDR + GRU_REG_PERF_BLIT_CYCLE_OFS))

static U32 gru_pack_w0(gru_opcode_t opcode, U8 color_idx, U8 font_id, U16 x0, U16 y0)
{
    return (((U32)y0 & 0xffu) << 24) |
           (((U32)x0 & 0x1ffu) << 15) |
           (((U32)font_id & 0x3u) << 13) |
           (((U32)color_idx & 0xffu) << 5) |
           ((U32)opcode & 0x1fu);
}

static U32 gru_pack_w1_xy(U16 x1, U16 y1)
{
    return (((U32)y1 & 0x100u) << 10) |
           (((U32)y1 & 0xffu) << 9) |
           ((U32)x1 & 0x1ffu);
}

static U32 gru_pack_w1_xy_invw0_hi(U16 x1, U8 y1, U16 inv_w0_q8_8)
{
    return ((((U32)inv_w0_q8_8 >> 10) & 0x3fu) << 26) |
           (((U32)y1 & 0xffu) << 9) |
           ((U32)x1 & 0x1ffu);
}

static U32 gru_pack_w1_ascii(U16 y0, char ch)
{
    return (((U32)y0 & 0x100u) << 9) | (U32)(U8)ch;
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

static U32 gru_pack_uv16(S16 u_q8_8, S16 v_q8_8)
{
    return (((U32)(U16)v_q8_8) << 16) |
           (U32)(U16)u_q8_8;
}

static U16 gru_pack_signed_x9(S16 x)
{
    return (U16)x & 0x01ffu;
}

static U8 gru_pack_signed_y8(S16 y)
{
    return (U8)y;
}

static U32 gru_pack_triangle_ext_w0(S16 x2, S16 y2)
{
    return (((U32)gru_pack_signed_y8(y2) & 0xffu) << 9) |
           ((U32)gru_pack_signed_x9(x2) & 0x1ffu);
}

static void gru_submit(gru_opcode_t opcode, U8 color_idx, U8 font_id, U16 x0, U16 y0, U32 w1)
{
    GRU_CMD_W0_REG = gru_pack_w0(opcode, color_idx, font_id, x0, y0);
    GRU_CMD_W1_REG = w1 | (((U32)y0 & 0x100u) << 9);
    __asm__ volatile("" : : : "memory");
    GRU_CMD_PUSH_REG = 1u;
    __asm__ volatile("" : : : "memory");
}

static void gru_submit_ext(
    gru_opcode_t opcode,
    U8 color_idx,
    U8 font_id,
    U16 x0,
    U16 y0,
    U32 w1,
    U32 ext_w0,
    U32 ext_w1,
    U32 ext_w2,
    U32 ext_w3,
    U32 ext_w4
)
{
    GRU_CMD_W0_REG = gru_pack_w0(opcode, color_idx, font_id, x0, y0);
    GRU_CMD_W1_REG = w1 | (((U32)y0 & 0x100u) << 9);
    GRU_EXT_W0_REG = ext_w0;
    GRU_EXT_W1_REG = ext_w1;
    GRU_EXT_W2_REG = ext_w2;
    GRU_EXT_W3_REG = ext_w3;
    GRU_EXT_W4_REG = ext_w4;
    __asm__ volatile("" : : : "memory");
    GRU_EXT_PUSH_REG = 1u;
    __asm__ volatile("" : : : "memory");
}

void gru_config_fb(U32 fb_base, U32 stride_bytes, U16 width, U16 height)
{
    GRU_FB_BASE_REG = fb_base;
    GRU_STRIDE_REG = stride_bytes;
    GRU_WIDTH_HEIGHT_REG = ((U32)height << 16) | (U32)width;
    __asm__ volatile("" : : : "memory");
}

void gru_init(const gru_cfg_t *cfg)
{
    if (cfg == 0) {
        return;
    }

    GRU_CTRL_REG = 0u;
    __asm__ volatile("" : : : "memory");
    gru_config_fb(cfg->fb_base, cfg->stride_bytes, cfg->width, cfg->height);
    GRU_CTRL_REG = GRU_CTRL_ENABLE_MASK;
    __asm__ volatile("" : : : "memory");
}

void gru_enable(U8 en)
{
    GRU_CTRL_REG = (en != 0u) ? GRU_CTRL_ENABLE_MASK : 0u;
    __asm__ volatile("" : : : "memory");
}

void gru_soft_reset(void)
{
    GRU_CTRL_REG = GRU_CTRL_ENABLE_MASK | GRU_CTRL_SOFT_RESET_MASK;
    __asm__ volatile("" : : : "memory");
}

U32 gru_get_status(void)
{
    return GRU_STATUS_REG;
}

U32 gru_get_cmd_level(void)
{
    return GRU_CMD_LEVEL_REG;
}

void gru_clear_status(U32 mask)
{
    /* DONE, FENCE_DONE and error/stall indications are write-one-to-clear. */
    GRU_STATUS_REG = mask;
    __asm__ volatile("" : : : "memory");
}

void gru_wait_done(void)
{
    gru_wait_idle();
}

void gru_wait_idle(void)
{
    while ((gru_get_status() & GRU_STATUS_BUSY) != 0u) {
    }
}

U32 gru_wait_idle_checked(void)
{
    U32 status;

    do {
        status = gru_get_status();
    } while ((status & GRU_STATUS_BUSY) != 0u);

    return status;
}

void gru_clear(U8 color_idx)
{
    gru_submit(GRU_OP_CLEAR, color_idx, 0u, 0u, 0u, 0u);
}

void gru_fill_rect(U16 x, U16 y, U16 w, U16 h, U8 color_idx)
{
    U16 x1;
    U16 y1;

    if ((w == 0u) || (h == 0u)) {
        return;
    }

    x1 = (U16)(x + w - 1u);
    y1 = (U16)(y + h - 1u);
    gru_submit(GRU_OP_FILL_RECT, color_idx, 0u, x, y, gru_pack_w1_xy(x1, y1));
}

void gru_draw_line(U16 x0, U16 y0, U16 x1, U16 y1, U8 color_idx)
{
    gru_submit(GRU_OP_DRAW_LINE, color_idx, 0u, x0, y0, gru_pack_w1_xy(x1, y1));
}

void gru_triangle_flat(
    S16 x0, S16 y0,
    S16 x1, S16 y1,
    S16 x2, S16 y2,
    U8 color_idx
)
{
    gru_submit_ext(
        GRU_OP_TRIANGLE_FLAT,
        color_idx,
        0u,
        gru_pack_signed_x9(x0),
        gru_pack_signed_y8(y0),
        gru_pack_w1_xy(gru_pack_signed_x9(x1), gru_pack_signed_y8(y1)),
        gru_pack_triangle_ext_w0(x2, y2),
        0u,
        0u,
        0u,
        0u
    );
}

void gru_draw_glyph(U16 x, U16 y, char ch, gru_font_id_t font_id, U8 color_idx)
{
    gru_submit(GRU_OP_DRAW_GLYPH, color_idx, (U8)font_id, x, y, gru_pack_w1_ascii(y, ch));
}

void gru_issue_fence(void)
{
    gru_submit(GRU_OP_FENCE, 0u, 0u, 0u, 0u, 0u);
}

void gru_blit_rgb565(
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
        return;
    }

    gru_submit_ext(
        GRU_OP_BLIT,
        0u,
        0u,
        0u,
        0u,
        gru_pack_w1_size(width, height),
        src_base_addr,
        src_stride_bytes,
        gru_pack_xy16(src_x, src_y),
        gru_pack_xy16(dst_x, dst_y),
        0u
    );
}

U8 gru_color_to_idx(U16 rgb565)
{
    return (U8)(((rgb565 >> 8) & 0xe0u) |
                ((rgb565 >> 6) & 0x1cu) |
                ((rgb565 >> 3) & 0x03u));
}

/* ---- Phase-4 performance / depth-buffer interface ---- */

void gru_perf_sample(gru_perf_t *p)
{
    if (p == 0) {
        return;
    }
    p->wcb_span_in    = GRU_PERF_WCB_SPAN_IN;
    p->wcb_pix_in     = GRU_PERF_WCB_PIX_IN;
    p->wcb_aw_txn     = GRU_PERF_WCB_AW_TXN;
    p->wcb_beat_out   = GRU_PERF_WCB_BEAT_OUT;
    p->wcb_full_beat  = GRU_PERF_WCB_FULL_BEAT;
    p->wcb_partial_beat = GRU_PERF_WCB_PARTIAL;
    p->wcb_flush      = GRU_PERF_WCB_FLUSH;
    p->blit_count     = GRU_PERF_BLIT_COUNT;
    p->blit_rd_beat   = GRU_PERF_BLIT_RD_BEAT;
    p->blit_wr_beat   = GRU_PERF_BLIT_WR_BEAT;
    p->blit_pixel     = GRU_PERF_BLIT_PIXEL;
    p->blit_cycle     = GRU_PERF_BLIT_CYCLE;
    __asm__ volatile("" : : : "memory");
}

static void gru_perf_put_u32(U32 v)
{
    char buf[11];
    int i;

    i = 10;
    buf[10] = '\0';
    if (v == 0u) {
        uart_puts_blocking("0");
        return;
    }
    while ((v != 0u) && (i > 0)) {
        i--;
        buf[i] = (char)('0' + (v % 10u));
        v /= 10u;
    }
    uart_puts_blocking(&buf[i]);
}

static void gru_perf_line(const char *label, U32 val)
{
    uart_puts_blocking(label);
    uart_puts_blocking("=");
    gru_perf_put_u32(val);
    uart_puts_blocking("\r\n");
}

void gru_perf_print(const gru_perf_t *p)
{
    if (p == 0) {
        return;
    }
    uart_puts_blocking("[GRU_PERF]\r\n");
    gru_perf_line("  wcb_span_in   ", p->wcb_span_in);
    gru_perf_line("  wcb_pix_in    ", p->wcb_pix_in);
    gru_perf_line("  wcb_aw_txn    ", p->wcb_aw_txn);
    gru_perf_line("  wcb_beat_out  ", p->wcb_beat_out);
    gru_perf_line("  wcb_full_beat ", p->wcb_full_beat);
    gru_perf_line("  wcb_partial   ", p->wcb_partial_beat);
    gru_perf_line("  wcb_flush     ", p->wcb_flush);
    gru_perf_line("  blit_count    ", p->blit_count);
    gru_perf_line("  blit_rd_beat  ", p->blit_rd_beat);
    gru_perf_line("  blit_wr_beat  ", p->blit_wr_beat);
    gru_perf_line("  blit_pixel    ", p->blit_pixel);
    gru_perf_line("  blit_cycle    ", p->blit_cycle);
}

void gru_set_depth_base(U32 depth_base)
{
    GRU_DEPTH_BASE_REG = depth_base;
    __asm__ volatile("" : : : "memory");
}

U32 gru_get_depth_base(void)
{
    return GRU_DEPTH_BASE_REG;
}

void gru_set_depth_ctrl(U32 depth_ctrl)
{
    GRU_DEPTH_CTRL_REG = depth_ctrl;
    __asm__ volatile("" : : : "memory");
}

U32 gru_get_depth_ctrl(void)
{
    return GRU_DEPTH_CTRL_REG;
}

void gru_set_texture(const gru_texture_cfg_t *cfg)
{
    if (cfg == 0) {
        return;
    }

    gru_config_texture(
        cfg->base_addr,
        cfg->width,
        cfg->height,
        cfg->stride_bytes,
        cfg->ctrl
    );
}

void gru_config_texture(
    U32 base_addr,
    U16 width,
    U16 height,
    U32 stride_bytes,
    U32 ctrl
)
{
    GRU_TEX_BASE_REG = base_addr;
    GRU_TEX_SIZE_REG = ((U32)height << 16) | (U32)width;
    GRU_TEX_STRIDE_REG = stride_bytes;
    GRU_TEX_CTRL_REG = ctrl;
    __asm__ volatile("" : : : "memory");
}

void gru_set_depth_state(U8 enable, U8 write_enable, U8 lequal)
{
    U32 ctrl = 0u;

    if (enable != 0u) {
        ctrl |= GRU_DEPTH_CTRL_ENABLE_MASK;
    }
    if (write_enable != 0u) {
        ctrl |= GRU_DEPTH_CTRL_WRITE_MASK;
    }
    if (lequal != 0u) {
        ctrl |= GRU_DEPTH_CTRL_LEQUAL_MASK;
    }
    gru_set_depth_ctrl(ctrl);
}

void gru_clear_depth(U16 depth_value)
{
    gru_submit(GRU_OP_CLEAR_DEPTH, 0u, 0u, 0u, 0u, (U32)depth_value);
}

void gru_triangle_z(
    S16 x0, S16 y0, U16 z0,
    S16 x1, S16 y1, U16 z1,
    S16 x2, S16 y2, U16 z2,
    U8 color_idx
)
{
    gru_submit_ext(
        GRU_OP_TRIANGLE_Z,
        color_idx,
        0u,
        gru_pack_signed_x9(x0),
        gru_pack_signed_y8(y0),
        gru_pack_w1_xy(gru_pack_signed_x9(x1), gru_pack_signed_y8(y1)),
        gru_pack_triangle_ext_w0(x2, y2),
        ((U32)z1 << 16) | (U32)z0,
        (U32)z2,
        0u,
        0u
    );
}

void gru_triangle_gouraud(
    S16 x0, S16 y0, U16 c0_rgb565,
    S16 x1, S16 y1, U16 c1_rgb565,
    S16 x2, S16 y2, U16 c2_rgb565
)
{
    gru_submit_ext(
        GRU_OP_TRIANGLE_GOURAUD,
        0u,
        0u,
        gru_pack_signed_x9(x0),
        gru_pack_signed_y8(y0),
        gru_pack_w1_xy(gru_pack_signed_x9(x1), gru_pack_signed_y8(y1)),
        gru_pack_triangle_ext_w0(x2, y2),
        (U32)c0_rgb565,
        (U32)c1_rgb565,
        (U32)c2_rgb565,
        0u
    );
}

void gru_triangle_textured(
    S16 x0, S16 y0, S16 u0_q8_8, S16 v0_q8_8,
    S16 x1, S16 y1, S16 u1_q8_8, S16 v1_q8_8,
    S16 x2, S16 y2, S16 u2_q8_8, S16 v2_q8_8
)
{
    gru_submit_ext(
        GRU_OP_TRIANGLE_TEXTURED,
        0u,
        0u,
        gru_pack_signed_x9(x0),
        gru_pack_signed_y8(y0),
        gru_pack_w1_xy(gru_pack_signed_x9(x1), gru_pack_signed_y8(y1)),
        gru_pack_triangle_ext_w0(x2, y2),
        gru_pack_uv16(u0_q8_8, v0_q8_8),
        gru_pack_uv16(u1_q8_8, v1_q8_8),
        gru_pack_uv16(u2_q8_8, v2_q8_8),
        0u
    );
}

void gru_triangle_textured_perspective(
    S16 x0, S16 y0, S16 u0_over_w_q8_8, S16 v0_over_w_q8_8, S16 inv_w0_q8_8,
    S16 x1, S16 y1, S16 u1_over_w_q8_8, S16 v1_over_w_q8_8, S16 inv_w1_q8_8,
    S16 x2, S16 y2, S16 u2_over_w_q8_8, S16 v2_over_w_q8_8, S16 inv_w2_q8_8
)
{
    gru_submit_ext(
        GRU_OP_TRIANGLE_TEXTURED_PC,
        (U8)((U16)inv_w0_q8_8 & 0xffu),
        (U8)(((U16)inv_w0_q8_8 >> 8) & 0x3u),
        gru_pack_signed_x9(x0),
        gru_pack_signed_y8(y0),
        gru_pack_w1_xy_invw0_hi(gru_pack_signed_x9(x1), gru_pack_signed_y8(y1), (U16)inv_w0_q8_8),
        gru_pack_triangle_ext_w0(x2, y2),
        gru_pack_uv16(u0_over_w_q8_8, v0_over_w_q8_8),
        gru_pack_uv16(u1_over_w_q8_8, v1_over_w_q8_8),
        gru_pack_uv16(u2_over_w_q8_8, v2_over_w_q8_8),
        (((U32)(U16)inv_w2_q8_8) << 16) | (U32)(U16)inv_w1_q8_8
    );
}
