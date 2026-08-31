#include "gfx2d.h"
#include "fb_cache.h"
#include "gru.h"

static S32 gfx_abs32(S32 v)
{
    return (v < 0) ? -v : v;
}

static void gfx_swap_s32(S32 *a, S32 *b)
{
    S32 t;
    t = *a;
    *a = *b;
    *b = t;
}

static U8 gfx_ctx_valid(const gfx_ctx_t *ctx)
{
    if (ctx == 0) {
        return 0u;
    }
    if (ctx->fb_ptr == 0) {
        return 0u;
    }
    if ((ctx->width == 0u) || (ctx->height == 0u)) {
        return 0u;
    }
    if (ctx->stride_px == 0u) {
        return 0u;
    }
    return 1u;
}

static U32 gfx_blit_region_bytes(U16 src_w, U16 src_h, U16 src_stride_px)
{
    U32 row_bytes;

    row_bytes = ((src_stride_px == 0u) ? (U32)src_w : (U32)src_stride_px) * 2u;
    if (src_h == 0u) {
        return 0u;
    }

    return (row_bytes * (U32)(src_h - 1u)) + ((U32)src_w * 2u);
}

void gfx_init(gfx_ctx_t *ctx, volatile U16 *fb_ptr, U16 width, U16 height, U16 stride_px)
{
    if (ctx == 0) {
        return;
    }

    ctx->fb_ptr = fb_ptr;
    ctx->width = width;
    ctx->height = height;
    ctx->stride_px = (stride_px == 0u) ? width : stride_px;
    ctx->font_id = gfx_pick_font_for_res(width, height);
    ctx->backend = GFX_BACKEND_CPU;
}

void gfx_set_font(gfx_ctx_t *ctx, gfx_font_id_t font_id)
{
    if (ctx == 0) {
        return;
    }

    if ((font_id != GFX_FONT_4X6) &&
        (font_id != GFX_FONT_5X7) &&
        (font_id != GFX_FONT_6X8)) {
        return;
    }

    ctx->font_id = font_id;
}

void gfx_set_backend(gfx_ctx_t *ctx, gfx_backend_t backend)
{
    if (ctx == 0) {
        return;
    }

    ctx->backend = backend;
}

void gfx_sync(gfx_ctx_t *ctx)
{
    if (ctx == 0) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        gru_wait_idle();
    }
}

gfx_font_id_t gfx_pick_font_for_res(U16 width, U16 height)
{
    if ((width <= 80u) && (height <= 60u)) {
        return GFX_FONT_4X6;
    }
    if ((width <= 128u) && (height <= 96u)) {
        return GFX_FONT_5X7;
    }
    return GFX_FONT_6X8;
}

void gfx_clear(gfx_ctx_t *ctx, U16 color)
{
    U16 y;
    U16 x;
    volatile U16 *row;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        gru_clear(gru_color_to_idx(color));
        return;
    }

    for (y = 0; y < ctx->height; ++y) {
        row = ctx->fb_ptr + ((U32)y * (U32)ctx->stride_px);
        for (x = 0; x < ctx->width; ++x) {
            row[x] = color;
        }
    }
}

void gfx_draw_pixel(gfx_ctx_t *ctx, S32 x, S32 y, U16 color)
{
    if (!gfx_ctx_valid(ctx)) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        gfx_sync(ctx);
    }

    if ((x < 0) || (y < 0) || (x >= (S32)ctx->width) || (y >= (S32)ctx->height)) {
        return;
    }

    ctx->fb_ptr[(U32)y * (U32)ctx->stride_px + (U32)x] = color;
}

void gfx_draw_hline(gfx_ctx_t *ctx, S32 x0, S32 x1, S32 y, U16 color)
{
    S32 x;
    volatile U16 *row;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }
    if ((y < 0) || (y >= (S32)ctx->height)) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        if (x0 > x1) {
            gfx_swap_s32(&x0, &x1);
        }
        if (x1 < 0 || x0 >= (S32)ctx->width) {
            return;
        }
        if (x0 < 0) {
            x0 = 0;
        }
        if (x1 >= (S32)ctx->width) {
            x1 = (S32)ctx->width - 1;
        }
        gru_fill_rect((U16)x0, (U16)y, (U16)(x1 - x0 + 1), 1u, gru_color_to_idx(color));
        return;
    }

    if (x0 > x1) {
        gfx_swap_s32(&x0, &x1);
    }
    if (x1 < 0 || x0 >= (S32)ctx->width) {
        return;
    }
    if (x0 < 0) {
        x0 = 0;
    }
    if (x1 >= (S32)ctx->width) {
        x1 = (S32)ctx->width - 1;
    }

    row = ctx->fb_ptr + ((U32)y * (U32)ctx->stride_px);
    for (x = x0; x <= x1; ++x) {
        row[x] = color;
    }
}

void gfx_draw_vline(gfx_ctx_t *ctx, S32 x, S32 y0, S32 y1, U16 color)
{
    S32 y;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }
    if ((x < 0) || (x >= (S32)ctx->width)) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        if (y0 > y1) {
            gfx_swap_s32(&y0, &y1);
        }
        if (y1 < 0 || y0 >= (S32)ctx->height) {
            return;
        }
        if (y0 < 0) {
            y0 = 0;
        }
        if (y1 >= (S32)ctx->height) {
            y1 = (S32)ctx->height - 1;
        }
        gru_fill_rect((U16)x, (U16)y0, 1u, (U16)(y1 - y0 + 1), gru_color_to_idx(color));
        return;
    }

    if (y0 > y1) {
        gfx_swap_s32(&y0, &y1);
    }
    if (y1 < 0 || y0 >= (S32)ctx->height) {
        return;
    }
    if (y0 < 0) {
        y0 = 0;
    }
    if (y1 >= (S32)ctx->height) {
        y1 = (S32)ctx->height - 1;
    }

    for (y = y0; y <= y1; ++y) {
        ctx->fb_ptr[(U32)y * (U32)ctx->stride_px + (U32)x] = color;
    }
}

void gfx_draw_line(gfx_ctx_t *ctx, S32 x0, S32 y0, S32 x1, S32 y1, U16 color)
{
    S32 dx;
    S32 sx;
    S32 dy;
    S32 sy;
    S32 err;
    S32 e2;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }

    if ((ctx->backend == GFX_BACKEND_GRU) &&
        (x0 >= 0) && (y0 >= 0) &&
        (x1 >= 0) && (y1 >= 0)) {
        gru_draw_line((U16)x0, (U16)y0, (U16)x1, (U16)y1, gru_color_to_idx(color));
        return;
    }

    dx = gfx_abs32(x1 - x0);
    sx = (x0 < x1) ? 1 : -1;
    dy = -gfx_abs32(y1 - y0);
    sy = (y0 < y1) ? 1 : -1;
    err = dx + dy;

    for (;;) {
        gfx_draw_pixel(ctx, x0, y0, color);
        if ((x0 == x1) && (y0 == y1)) {
            break;
        }
        e2 = err << 1;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

void gfx_draw_rect(gfx_ctx_t *ctx, S32 x, S32 y, S32 w, S32 h, U16 color)
{
    if ((w <= 0) || (h <= 0)) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        gfx_draw_hline(ctx, x, x + w - 1, y, color);
        gfx_draw_hline(ctx, x, x + w - 1, y + h - 1, color);
        gfx_draw_vline(ctx, x, y, y + h - 1, color);
        gfx_draw_vline(ctx, x + w - 1, y, y + h - 1, color);
        return;
    }

    gfx_draw_hline(ctx, x, x + w - 1, y, color);
    gfx_draw_hline(ctx, x, x + w - 1, y + h - 1, color);
    gfx_draw_vline(ctx, x, y, y + h - 1, color);
    gfx_draw_vline(ctx, x + w - 1, y, y + h - 1, color);
}

void gfx_fill_rect(gfx_ctx_t *ctx, S32 x, S32 y, S32 w, S32 h, U16 color)
{
    S32 x0;
    S32 y0;
    S32 x1;
    S32 y1;
    S32 yy;
    S32 xx;
    S32 x_clip;
    S32 y_clip;
    S32 w_clip;
    S32 h_clip;
    volatile U16 *row;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }
    if ((w <= 0) || (h <= 0)) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        x_clip = x;
        y_clip = y;
        w_clip = w;
        h_clip = h;

        if (x_clip < 0) {
            w_clip += x_clip;
            x_clip = 0;
        }
        if (y_clip < 0) {
            h_clip += y_clip;
            y_clip = 0;
        }
        if ((x_clip + w_clip) > (S32)ctx->width) {
            w_clip = (S32)ctx->width - x_clip;
        }
        if ((y_clip + h_clip) > (S32)ctx->height) {
            h_clip = (S32)ctx->height - y_clip;
        }
        if ((w_clip <= 0) || (h_clip <= 0)) {
            return;
        }
        gru_fill_rect((U16)x_clip, (U16)y_clip, (U16)w_clip, (U16)h_clip, gru_color_to_idx(color));
        return;
    }

    x0 = x;
    y0 = y;
    x1 = x + w - 1;
    y1 = y + h - 1;

    if (x1 < 0 || y1 < 0 || x0 >= (S32)ctx->width || y0 >= (S32)ctx->height) {
        return;
    }

    if (x0 < 0) {
        x0 = 0;
    }
    if (y0 < 0) {
        y0 = 0;
    }
    if (x1 >= (S32)ctx->width) {
        x1 = (S32)ctx->width - 1;
    }
    if (y1 >= (S32)ctx->height) {
        y1 = (S32)ctx->height - 1;
    }

    for (yy = y0; yy <= y1; ++yy) {
        row = ctx->fb_ptr + ((U32)yy * (U32)ctx->stride_px);
        for (xx = x0; xx <= x1; ++xx) {
            row[xx] = color;
        }
    }
}

void gfx_blit_rgb565(gfx_ctx_t *ctx, S32 x, S32 y, const U16 *src, U16 src_w, U16 src_h, U16 src_stride)
{
    S32 sx0;
    S32 sy0;
    S32 sx1;
    S32 sy1;
    S32 sx;
    S32 sy;
    U16 stride;
    volatile U16 *dst_row;
    const U16 *src_row;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }
    if (src == 0) {
        return;
    }
    if ((src_w == 0u) || (src_h == 0u)) {
        return;
    }

    stride = (src_stride == 0u) ? src_w : src_stride;

    sx0 = 0;
    sy0 = 0;
    sx1 = (S32)src_w - 1;
    sy1 = (S32)src_h - 1;

    if (x < 0) {
        sx0 = -x;
    }
    if (y < 0) {
        sy0 = -y;
    }
    if ((x + sx1) >= (S32)ctx->width) {
        sx1 = (S32)ctx->width - 1 - x;
    }
    if ((y + sy1) >= (S32)ctx->height) {
        sy1 = (S32)ctx->height - 1 - y;
    }
    if ((sx0 > sx1) || (sy0 > sy1)) {
        return;
    }

    for (sy = sy0; sy <= sy1; ++sy) {
        dst_row = ctx->fb_ptr + ((U32)(y + sy) * (U32)ctx->stride_px) + (U32)(x + sx0);
        src_row = src + ((U32)sy * (U32)stride) + (U32)sx0;
        for (sx = sx0; sx <= sx1; ++sx) {
            dst_row[sx - sx0] = src_row[sx - sx0];
        }
    }
}

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
)
{
    S32 src_x_clip;
    S32 src_y_clip;
    S32 dst_x_clip;
    S32 dst_y_clip;
    S32 w_clip;
    S32 h_clip;
    U32 src_stride_bytes;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }
    if ((src_w == 0u) || (src_h == 0u)) {
        return;
    }
    if (src_base_addr == 0u) {
        return;
    }

    src_x_clip = (S32)src_x;
    src_y_clip = (S32)src_y;
    dst_x_clip = dst_x;
    dst_y_clip = dst_y;
    w_clip = (S32)src_w;
    h_clip = (S32)src_h;

    if (dst_x_clip < 0) {
        src_x_clip -= dst_x_clip;
        w_clip += dst_x_clip;
        dst_x_clip = 0;
    }
    if (dst_y_clip < 0) {
        src_y_clip -= dst_y_clip;
        h_clip += dst_y_clip;
        dst_y_clip = 0;
    }
    if ((dst_x_clip + w_clip) > (S32)ctx->width) {
        w_clip = (S32)ctx->width - dst_x_clip;
    }
    if ((dst_y_clip + h_clip) > (S32)ctx->height) {
        h_clip = (S32)ctx->height - dst_y_clip;
    }
    if ((w_clip <= 0) || (h_clip <= 0)) {
        return;
    }

    src_stride_bytes = ((src_stride == 0u) ? (U32)src_w : (U32)src_stride) * 2u;

    if (ctx->backend == GFX_BACKEND_GRU) {
        fb_cache_flush_range(
            src_base_addr + ((U32)src_y_clip * src_stride_bytes) + ((U32)src_x_clip * 2u),
            gfx_blit_region_bytes((U16)w_clip, (U16)h_clip, (U16)(src_stride_bytes / 2u))
        );
        gru_blit_rgb565(
            src_base_addr,
            src_stride_bytes,
            (U16)src_x_clip,
            (U16)src_y_clip,
            (U16)dst_x_clip,
            (U16)dst_y_clip,
            (U16)w_clip,
            (U16)h_clip
        );
        return;
    }

    gfx_blit_rgb565(
        ctx,
        dst_x_clip,
        dst_y_clip,
        (const U16 *)(src_base_addr + ((U32)src_y_clip * src_stride_bytes) + ((U32)src_x_clip * 2u)),
        (U16)w_clip,
        (U16)h_clip,
        (src_stride == 0u) ? src_w : src_stride
    );
}

void gfx_blit_rgb565_phys(
    gfx_ctx_t *ctx,
    S32 x,
    S32 y,
    U32 src_base_addr,
    U16 src_w,
    U16 src_h,
    U16 src_stride
)
{
    gfx_blit_rgb565_phys_ex(ctx, x, y, src_base_addr, 0u, 0u, src_w, src_h, src_stride);
}

void gfx_draw_char(gfx_ctx_t *ctx, S32 x, S32 y, char ch, U16 fg, U16 bg, U8 transparent_bg)
{
    U8 gx;
    U8 gy;
    U8 on;
    const gfx_font_desc_t *desc;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }

    desc = gfx_font_desc(ctx->font_id);
    if (desc == 0) {
        return;
    }

    if ((ctx->backend == GFX_BACKEND_GRU) && (x >= 0) && (y >= 0)) {
        if (transparent_bg == 0u) {
            gfx_fill_rect(ctx, x, y, desc->width, desc->height, bg);
        }
        gru_draw_glyph((U16)x, (U16)y, ch, (gru_font_id_t)ctx->font_id, gru_color_to_idx(fg));
        return;
    }

    for (gy = 0; gy < desc->height; ++gy) {
        for (gx = 0; gx < desc->width; ++gx) {
            on = gfx_font_pixel(ctx->font_id, ch, gx, gy);
            if (on != 0u) {
                gfx_draw_pixel(ctx, x + (S32)gx, y + (S32)gy, fg);
            } else if (transparent_bg == 0u) {
                gfx_draw_pixel(ctx, x + (S32)gx, y + (S32)gy, bg);
            }
        }
    }
}

void gfx_draw_text(gfx_ctx_t *ctx, S32 x, S32 y, const char *text, U16 fg, U16 bg, U8 transparent_bg)
{
    S32 cx;
    S32 cy;
    U8 step_x;
    U8 step_y;
    const gfx_font_desc_t *desc;
    const char *p;

    if (!gfx_ctx_valid(ctx)) {
        return;
    }
    if (text == 0) {
        return;
    }

    desc = gfx_font_desc(ctx->font_id);
    if (desc == 0) {
        return;
    }

    if (ctx->backend == GFX_BACKEND_GRU) {
        cx = x;
        cy = y;
        step_x = (U8)(desc->width + 1u);
        step_y = (U8)(desc->height + 1u);
        p = text;
        while (*p != '\0') {
            if (*p == '\n') {
                cx = x;
                cy += (S32)step_y;
            } else {
                gfx_draw_char(ctx, cx, cy, *p, fg, bg, transparent_bg);
                cx += (S32)step_x;
            }
            ++p;
        }
        return;
    }

    step_x = (U8)(desc->width + 1u);
    step_y = (U8)(desc->height + 1u);
    cx = x;
    cy = y;
    p = text;

    while (*p != '\0') {
        if (*p == '\n') {
            cx = x;
            cy += (S32)step_y;
        } else {
            gfx_draw_char(ctx, cx, cy, *p, fg, bg, transparent_bg);
            cx += (S32)step_x;
        }
        ++p;
    }
}
