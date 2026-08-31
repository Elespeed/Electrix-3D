#ifndef GFX2D_H
#define GFX2D_H

#include "common_func.h"
#include "gfx_font.h"

typedef enum {
    GFX_BACKEND_CPU = 0,
    GFX_BACKEND_GRU = 1
} gfx_backend_t;

typedef struct {
    volatile U16 *fb_ptr;
    U16 width;
    U16 height;
    U16 stride_px;
    gfx_font_id_t font_id;
    gfx_backend_t backend;
} gfx_ctx_t;

void gfx_init(gfx_ctx_t *ctx, volatile U16 *fb_ptr, U16 width, U16 height, U16 stride_px);
void gfx_set_font(gfx_ctx_t *ctx, gfx_font_id_t font_id);
void gfx_set_backend(gfx_ctx_t *ctx, gfx_backend_t backend);
void gfx_sync(gfx_ctx_t *ctx);
gfx_font_id_t gfx_pick_font_for_res(U16 width, U16 height);

void gfx_clear(gfx_ctx_t *ctx, U16 color);
void gfx_draw_pixel(gfx_ctx_t *ctx, S32 x, S32 y, U16 color);
void gfx_draw_hline(gfx_ctx_t *ctx, S32 x0, S32 x1, S32 y, U16 color);
void gfx_draw_vline(gfx_ctx_t *ctx, S32 x, S32 y0, S32 y1, U16 color);
void gfx_draw_line(gfx_ctx_t *ctx, S32 x0, S32 y0, S32 x1, S32 y1, U16 color);
void gfx_draw_rect(gfx_ctx_t *ctx, S32 x, S32 y, S32 w, S32 h, U16 color);
void gfx_fill_rect(gfx_ctx_t *ctx, S32 x, S32 y, S32 w, S32 h, U16 color);

void gfx_blit_rgb565(gfx_ctx_t *ctx, S32 x, S32 y, const U16 *src, U16 src_w, U16 src_h, U16 src_stride);
void gfx_blit_rgb565_phys(
    gfx_ctx_t *ctx,
    S32 x,
    S32 y,
    U32 src_base_addr,
    U16 src_w,
    U16 src_h,
    U16 src_stride
);
void gfx_blit_rgb565_phys_ex(
    gfx_ctx_t *ctx,
    S32 dst_x,
    S32 dst_y,
    U32 src_base_addr,
    U16 src_x,
    U16 src_y,
    U16 src_w,
    U16 src_h,
    U16 src_stride
);
void gfx_draw_char(gfx_ctx_t *ctx, S32 x, S32 y, char ch, U16 fg, U16 bg, U8 transparent_bg);
void gfx_draw_text(gfx_ctx_t *ctx, S32 x, S32 y, const char *text, U16 fg, U16 bg, U8 transparent_bg);

#endif /* GFX2D_H */
