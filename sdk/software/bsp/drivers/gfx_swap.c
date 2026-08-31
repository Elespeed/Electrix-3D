#include "gfx_swap.h"

#include "fb_cache.h"
#include "gdu_fb.h"
#include "gru.h"

static void gfx_swap_config_gru_back(gfx_swap_ctx_t *ctx)
{
    if (ctx == 0) {
        return;
    }

    gru_config_fb(ctx->fb_base[ctx->back_idx], ctx->stride_bytes, ctx->width, ctx->height);
}

void gfx_swap_init(
    gfx_swap_ctx_t *ctx,
    U32 fb_base_a,
    U32 fb_base_b,
    U16 width,
    U16 height,
    U32 stride_bytes,
    gfx_backend_t backend
)
{
    U16 stride_px;

    if (ctx == 0) {
        return;
    }

    stride_px = (U16)(stride_bytes / 2u);
    if (stride_px == 0u) {
        stride_px = width;
    }

    ctx->fb_base[0] = fb_base_a;
    ctx->fb_base[1] = fb_base_b;
    ctx->width = width;
    ctx->height = height;
    ctx->stride_px = stride_px;
    ctx->stride_bytes = stride_bytes;
    ctx->active_idx = 0u;
    ctx->back_idx = 0u;
    ctx->gdu_enabled = 0u;

    gfx_init(&ctx->ctx[0], (volatile U16 *)fb_base_a, width, height, stride_px);
    gfx_init(&ctx->ctx[1], (volatile U16 *)fb_base_b, width, height, stride_px);
    gfx_set_backend(&ctx->ctx[0], backend);
    gfx_set_backend(&ctx->ctx[1], backend);

    gfx_swap_config_gru_back(ctx);
}

gfx_ctx_t *gfx_swap_back_ctx(gfx_swap_ctx_t *ctx)
{
    if (ctx == 0) {
        return 0;
    }

    return &ctx->ctx[ctx->back_idx];
}

void gfx_swap_boot_front(gfx_swap_ctx_t *ctx)
{
    if (ctx == 0) {
        return;
    }

    (void)gru_wait_idle_checked();
    fb_cache_flush_frame(ctx->fb_base[ctx->back_idx], ctx->width, ctx->height, ctx->stride_bytes);
    gdu_fb_enable(1u);

    ctx->active_idx = ctx->back_idx;
    ctx->back_idx = (ctx->active_idx == 0u) ? 1u : 0u;
    ctx->gdu_enabled = 1u;
    gfx_swap_config_gru_back(ctx);
}

U32 gfx_swap_present(gfx_swap_ctx_t *ctx)
{
    U32 status;
    U8 next_active;

    if (ctx == 0) {
        return 0u;
    }

    status = gru_wait_idle_checked();
    if ((status & (GRU_STATUS_AXI_ERROR | GRU_STATUS_CFG_ERROR)) != 0u) {
        return status;
    }

    fb_cache_flush_frame(ctx->fb_base[ctx->back_idx], ctx->width, ctx->height, ctx->stride_bytes);
    gdu_fb_request_swap(ctx->fb_base[ctx->back_idx]);

    status = gdu_fb_wait_swap_done_checked();
    if ((status & (GDU_STATUS_UNDERFLOW | GDU_STATUS_AXI_ERROR)) != 0u) {
        return status;
    }

    next_active = ctx->back_idx;
    ctx->back_idx = ctx->active_idx;
    ctx->active_idx = next_active;
    ctx->gdu_enabled = 1u;
    gfx_swap_config_gru_back(ctx);

    return status;
}
