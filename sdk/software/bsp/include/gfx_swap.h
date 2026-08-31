#ifndef GFX_SWAP_H
#define GFX_SWAP_H

#include "gfx2d.h"

typedef struct {
    gfx_ctx_t ctx[2];
    U32 fb_base[2];
    U16 width;
    U16 height;
    U16 stride_px;
    U32 stride_bytes;
    U8 active_idx;
    U8 back_idx;
    U8 gdu_enabled;
} gfx_swap_ctx_t;

void gfx_swap_init(
    gfx_swap_ctx_t *ctx,
    U32 fb_base_a,
    U32 fb_base_b,
    U16 width,
    U16 height,
    U32 stride_bytes,
    gfx_backend_t backend
);
gfx_ctx_t *gfx_swap_back_ctx(gfx_swap_ctx_t *ctx);
void gfx_swap_boot_front(gfx_swap_ctx_t *ctx);
U32 gfx_swap_present(gfx_swap_ctx_t *ctx);

#endif /* GFX_SWAP_H */
