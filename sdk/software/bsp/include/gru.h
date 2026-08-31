#ifndef GRU_H
#define GRU_H

#include "common_func.h"

#define GRU_BASE_ADDR              0xbf300000u

#define GRU_CTRL_ENABLE_MASK       0x1u
#define GRU_CTRL_SOFT_RESET_MASK   0x2u

#define GRU_STATUS_BUSY            0x1u
#define GRU_STATUS_CMD_FULL        0x2u
#define GRU_STATUS_CMD_EMPTY       0x4u
#define GRU_STATUS_DONE            0x8u
#define GRU_STATUS_AXI_ERROR       0x10u
#define GRU_STATUS_CFG_ERROR       0x20u
#define GRU_STATUS_FENCE_DONE      0x40u
#define GRU_STATUS_ENGINE_STALL    0x80u

#define GRU_REG_EXT_W0_OFS         0x30u
#define GRU_REG_EXT_W1_OFS         0x34u
#define GRU_REG_EXT_W2_OFS         0x38u
#define GRU_REG_EXT_W3_OFS         0x3cu
#define GRU_REG_EXT_W4_OFS         0x40u
#define GRU_REG_EXT_PUSH_OFS       0x44u
#define GRU_REG_CMD_LEVEL_OFS      0x24u
#define GRU_REG_TEX_BASE_OFS       0x80u
#define GRU_REG_TEX_SIZE_OFS       0x84u
#define GRU_REG_TEX_STRIDE_OFS     0x88u
#define GRU_REG_TEX_CTRL_OFS       0x8cu

typedef enum {
    GRU_OP_CLEAR = 0,
    GRU_OP_FILL_RECT = 1,
    GRU_OP_DRAW_LINE = 2,
    GRU_OP_DRAW_GLYPH = 3,
    GRU_OP_FENCE = 4,
    GRU_OP_BLIT = 5,
    GRU_OP_TRIANGLE_FLAT = 6,
    GRU_OP_CLEAR_DEPTH = 7,
    GRU_OP_TRIANGLE_Z = 8,
    GRU_OP_TRIANGLE_GOURAUD = 9,
    GRU_OP_SET_TEXTURE = 10,
    GRU_OP_TRIANGLE_TEXTURED = 11,
    GRU_OP_TRIANGLE_TEXTURED_PC = 12
} gru_opcode_t;

typedef enum {
    GRU_FONT_4X6 = 0,
    GRU_FONT_5X7 = 1,
    GRU_FONT_6X8 = 2,
    GRU_FONT_6X7 = 2
} gru_font_id_t;

typedef struct {
    U8 opcode;
    U8 color_idx;
    U8 font_id;
    U16 x0;
    U8 y0;
} gru_cmd_header_t;

typedef struct {
    U32 fb_base;
    U16 width;
    U16 height;
    U32 stride_bytes;
} gru_cfg_t;

/* Phase-4: GRU performance counter MMIO window (read-only, cumulative since
 * hard reset).  Offsets mirror the GRU_REG_PERF_* macros in rtl/ip/gru/gru_defs.vh. */
#define GRU_REG_DEPTH_BASE_OFS         0x48u
#define GRU_REG_DEPTH_CTRL_OFS         0x4cu
#define GRU_DEPTH_CTRL_ENABLE_MASK     0x1u
#define GRU_DEPTH_CTRL_WRITE_MASK      0x2u
#define GRU_DEPTH_CTRL_LEQUAL_MASK     0x4u
#define GRU_TEX_CTRL_FORMAT_MASK       0x7u
#define GRU_TEX_CTRL_WRAP_MASK         0x8u
#define GRU_TEX_CTRL_FILTER_MASK       0x10u
#define GRU_REG_PERF_WCB_SPAN_IN_OFS   0x50u
#define GRU_REG_PERF_WCB_PIX_IN_OFS    0x54u
#define GRU_REG_PERF_WCB_AW_TXN_OFS    0x58u
#define GRU_REG_PERF_WCB_BEAT_OUT_OFS  0x5cu
#define GRU_REG_PERF_WCB_FULL_BEAT_OFS 0x60u
#define GRU_REG_PERF_WCB_PARTIAL_OFS   0x64u
#define GRU_REG_PERF_WCB_FLUSH_OFS     0x68u
#define GRU_REG_PERF_BLIT_COUNT_OFS    0x6cu
#define GRU_REG_PERF_BLIT_RD_BEAT_OFS  0x70u
#define GRU_REG_PERF_BLIT_WR_BEAT_OFS  0x74u
#define GRU_REG_PERF_BLIT_PIXEL_OFS    0x78u
#define GRU_REG_PERF_BLIT_CYCLE_OFS    0x7cu

/* Default depth-buffer base.  Driver must program a real base via
 * gru_set_depth_base() before enabling the (future) Z path; 0 = unallocated. */
#define GRU_DEPTH_BASE_DEFAULT         0x00000000u

typedef struct {
    U32 wcb_span_in;      /* render spans (len>0) absorbed by the write-combine buf */
    U32 wcb_pix_in;       /* render pixels absorbed */
    U32 wcb_aw_txn;       /* AXI AW transactions (bursts) issued to DDR */
    U32 wcb_beat_out;     /* 128-bit W beats committed */
    U32 wcb_full_beat;    /* W beats with full byte-strobe (0xFFFF) */
    U32 wcb_partial_beat; /* W beats with partial byte-strobe */
    U32 wcb_flush;        /* row-eviction / done flush events */
    U32 blit_count;       /* blit commands accepted */
    U32 blit_rd_beat;     /* blit 128-bit read beats */
    U32 blit_wr_beat;     /* blit 128-bit write beats */
    U32 blit_pixel;       /* blit destination pixels written */
    U32 blit_cycle;       /* cycles blit engine busy */
} gru_perf_t;

typedef struct {
    U32 base_addr;
    U16 width;
    U16 height;
    U32 stride_bytes;
    U32 ctrl;
} gru_texture_cfg_t;

void gru_config_fb(U32 fb_base, U32 stride_bytes, U16 width, U16 height);
void gru_init(const gru_cfg_t *cfg);
void gru_enable(U8 en);
void gru_soft_reset(void);
U32 gru_get_status(void);
U32 gru_get_cmd_level(void);
void gru_clear_status(U32 mask);
void gru_wait_done(void);
void gru_wait_idle(void);
U32 gru_wait_idle_checked(void);

void gru_clear(U8 color_idx);
void gru_fill_rect(U16 x, U16 y, U16 w, U16 h, U8 color_idx);
void gru_draw_line(U16 x0, U16 y0, U16 x1, U16 y1, U8 color_idx);
void gru_triangle_flat(
    S16 x0, S16 y0,
    S16 x1, S16 y1,
    S16 x2, S16 y2,
    U8 color_idx
);
void gru_draw_glyph(U16 x, U16 y, char ch, gru_font_id_t font_id, U8 color_idx);
void gru_issue_fence(void);
void gru_blit_rgb565(
    U32 src_base_addr,
    U32 src_stride_bytes,
    U16 src_x,
    U16 src_y,
    U16 dst_x,
    U16 dst_y,
    U16 width,
    U16 height
);

U8 gru_color_to_idx(U16 rgb565);

/* Phase-4 performance / depth-buffer interface. */
void gru_perf_sample(gru_perf_t *p);
void gru_perf_print(const gru_perf_t *p);
void gru_set_depth_base(U32 depth_base);
U32  gru_get_depth_base(void);
void gru_set_depth_ctrl(U32 depth_ctrl);
U32  gru_get_depth_ctrl(void);
void gru_set_depth_state(U8 enable, U8 write_enable, U8 lequal);
void gru_set_texture(const gru_texture_cfg_t *cfg);
void gru_config_texture(
    U32 base_addr,
    U16 width,
    U16 height,
    U32 stride_bytes,
    U32 ctrl
);
void gru_clear_depth(U16 depth_value);
void gru_triangle_z(
    S16 x0, S16 y0, U16 z0,
    S16 x1, S16 y1, U16 z1,
    S16 x2, S16 y2, U16 z2,
    U8 color_idx
);
void gru_triangle_gouraud(
    S16 x0, S16 y0, U16 c0_rgb565,
    S16 x1, S16 y1, U16 c1_rgb565,
    S16 x2, S16 y2, U16 c2_rgb565
);
void gru_triangle_textured(
    S16 x0, S16 y0, S16 u0_q8_8, S16 v0_q8_8,
    S16 x1, S16 y1, S16 u1_q8_8, S16 v1_q8_8,
    S16 x2, S16 y2, S16 u2_q8_8, S16 v2_q8_8
);
void gru_triangle_textured_perspective(
    S16 x0, S16 y0, S16 u0_over_w_q8_8, S16 v0_over_w_q8_8, S16 inv_w0_q8_8,
    S16 x1, S16 y1, S16 u1_over_w_q8_8, S16 v1_over_w_q8_8, S16 inv_w1_q8_8,
    S16 x2, S16 y2, S16 u2_over_w_q8_8, S16 v2_over_w_q8_8, S16 inv_w2_q8_8
);

#endif /* GRU_H */
