#include "sketchbook.h"

static volatile U32 *sketchbook_reg(const sketchbook_t *dev, U32 offset)
{
    return (volatile U32 *)(dev->base_addr + offset);
}

static U32 sketchbook_pack_xy(S16 x, S16 y)
{
    return ((U32)(U16)y << 16) | (U32)(U16)x;
}

static void sketchbook_submit5(
    sketchbook_t *dev, sketchbook_opcode_t opcode, U8 rgb332,
    U32 w1, U32 w2, U32 w3, U32 w4
)
{
    sketchbook_wait_submit_ready(dev);
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD0) = ((U32)rgb332 << 5) | (U32)opcode;
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD1) = w1;
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD2) = w2;
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD3) = w3;
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD4) = w4;
    __asm__ volatile("" : : : "memory");
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD_PUSH) = 1u;
    __asm__ volatile("" : : : "memory");
}

static void sketchbook_submit(
    sketchbook_t *dev, sketchbook_opcode_t opcode, U8 rgb332,
    U32 w1, U32 w2, U32 w3
)
{
    sketchbook_submit5(dev, opcode, rgb332, w1, w2, w3, 0u);
}

void sketchbook_init(sketchbook_t *dev, U32 base_addr)
{
    if (dev == 0) {
        return;
    }
    dev->base_addr = base_addr;
    sketchbook_enable(dev, 1u);
}

void sketchbook_enable(sketchbook_t *dev, U8 enable)
{
    if (dev == 0) {
        return;
    }
    *sketchbook_reg(dev, SKETCHBOOK_REG_CTRL) =
        (enable != 0u) ? SKETCHBOOK_CTRL_DISPLAY_ENABLE : 0u;
    __asm__ volatile("" : : : "memory");
}

void sketchbook_soft_reset(sketchbook_t *dev)
{
    if (dev == 0) {
        return;
    }
    *sketchbook_reg(dev, SKETCHBOOK_REG_CTRL) =
        SKETCHBOOK_CTRL_DISPLAY_ENABLE | SKETCHBOOK_CTRL_SOFT_RESET;
    __asm__ volatile("" : : : "memory");
}

U32 sketchbook_get_status(const sketchbook_t *dev)
{
    return (dev == 0) ? SKETCHBOOK_STATUS_ERROR : *sketchbook_reg(dev, SKETCHBOOK_REG_STATUS);
}

U32 sketchbook_get_cmd_level(const sketchbook_t *dev)
{
    return (dev == 0) ? 0u : *sketchbook_reg(dev, SKETCHBOOK_REG_CMD_LEVEL);
}

U32 sketchbook_get_frame_counter(const sketchbook_t *dev)
{
    return (dev == 0) ? 0u : *sketchbook_reg(dev, SKETCHBOOK_REG_FRAME_COUNTER);
}

void sketchbook_clear_status(sketchbook_t *dev, U32 mask)
{
    if (dev == 0) {
        return;
    }
    *sketchbook_reg(dev, SKETCHBOOK_REG_STATUS) = mask;
    __asm__ volatile("" : : : "memory");
}

void sketchbook_wait_submit_ready(const sketchbook_t *dev)
{
    U32 status;

    if (dev == 0) {
        return;
    }
    do {
        status = sketchbook_get_status(dev);
    } while ((status & (SKETCHBOOK_STATUS_CMD_FULL | SKETCHBOOK_STATUS_FRAME_CLOSED)) != 0u);
}

void sketchbook_wait_frame_done(sketchbook_t *dev)
{
    if (dev == 0) {
        return;
    }
    while ((sketchbook_get_status(dev) & SKETCHBOOK_STATUS_FRAME_DONE) == 0u) {
    }
    sketchbook_clear_status(dev, SKETCHBOOK_STATUS_FRAME_DONE);
}

void sketchbook_clear(sketchbook_t *dev, U8 rgb332)
{
    sketchbook_submit(dev, SKETCHBOOK_CMD_CLEAR, rgb332, 0u, 0u, 0u);
}

void sketchbook_draw_pixel(sketchbook_t *dev, S16 x, S16 y, U8 rgb332)
{
    sketchbook_submit(dev, SKETCHBOOK_CMD_DRAW_PIXEL, rgb332, sketchbook_pack_xy(x, y), 0u, 0u);
}

void sketchbook_fill_rect(sketchbook_t *dev, S16 x, S16 y, U16 width, U16 height, U8 rgb332)
{
    sketchbook_submit(
        dev, SKETCHBOOK_CMD_FILL_RECT, rgb332, sketchbook_pack_xy(x, y),
        ((U32)height << 16) | (U32)width, 0u
    );
}

void sketchbook_draw_line(sketchbook_t *dev, S16 x0, S16 y0, S16 x1, S16 y1, U8 rgb332)
{
    sketchbook_submit(
        dev, SKETCHBOOK_CMD_DRAW_LINE, rgb332,
        sketchbook_pack_xy(x0, y0), sketchbook_pack_xy(x1, y1), 0u
    );
}

void sketchbook_draw_glyph(
    sketchbook_t *dev, S16 x, S16 y, char ascii, sketchbook_font_t font, U8 rgb332
)
{
    sketchbook_submit(
        dev, SKETCHBOOK_CMD_DRAW_GLYPH, rgb332, sketchbook_pack_xy(x, y),
        ((U32)font << 8) | (U32)(U8)ascii, 0u
    );
}

void sketchbook_triangle_flat(
    sketchbook_t *dev,
    S16 x0, S16 y0, S16 x1, S16 y1, S16 x2, S16 y2,
    U8 rgb332
)
{
    sketchbook_submit(
        dev, SKETCHBOOK_CMD_TRIANGLE_FLAT, rgb332,
        sketchbook_pack_xy(x0, y0), sketchbook_pack_xy(x1, y1), sketchbook_pack_xy(x2, y2)
    );
}

void sketchbook_triangle_gouraud(
    sketchbook_t *dev,
    S16 x0, S16 y0, U8 c0, S16 x1, S16 y1, U8 c1, S16 x2, S16 y2, U8 c2
)
{
    sketchbook_submit5(dev, SKETCHBOOK_CMD_TRIANGLE_GOURAUD, c0,
        sketchbook_pack_xy(x0, y0), sketchbook_pack_xy(x1, y1), sketchbook_pack_xy(x2, y2),
        (U32)c1 | ((U32)c2 << 8));
}

void sketchbook_blit_sprite(
    sketchbook_t *dev, U8 sprite_id, S16 x, S16 y, U16 width, U16 height,
    U8 color_key_enable, U8 color_key
)
{
    sketchbook_submit(
        dev, SKETCHBOOK_CMD_BLIT, color_key, sketchbook_pack_xy(x, y),
        ((U32)height << 16) | (U32)width,
        (U32)sprite_id | ((color_key_enable != 0u) ? SKETCHBOOK_BLIT_COLOR_KEY_ENABLE : 0u)
    );
}

void sketchbook_blit_asset(
    sketchbook_t *dev, U8 asset_id, S16 dst_x, S16 dst_y, U16 src_x, U16 src_y,
    U16 width, U16 height, U8 color_key_enable, U8 color_key
)
{
    U32 w0 = SKETCHBOOK_CMD_BLIT_ASSET | ((U32)color_key << 5) |
             ((color_key_enable != 0u) ? (1u << 13) : 0u) | ((U32)asset_id << 22);
    sketchbook_wait_submit_ready(dev);
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD0) = w0;
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD1) = sketchbook_pack_xy(dst_x, dst_y);
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD2) = ((U32)src_y << 16) | (U32)src_x;
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD3) = ((U32)height << 16) | (U32)width;
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD4) = 0u;
    __asm__ volatile("" : : : "memory");
    *sketchbook_reg(dev, SKETCHBOOK_REG_CMD_PUSH) = 1u;
    __asm__ volatile("" : : : "memory");
}

void sketchbook_present(sketchbook_t *dev)
{
    sketchbook_submit(dev, SKETCHBOOK_CMD_PRESENT, 0u, 0u, 0u, 0u);
}
