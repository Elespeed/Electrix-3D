#ifndef SKETCHBOOK_H
#define SKETCHBOOK_H

#include "common_func.h"

/* SketchBook owns its framebuffer internally and is exposed only through this
 * command-register window; software never receives a framebuffer address. */
#define SKETCHBOOK_BASE_ADDR 0xbf100000u

typedef struct {
    U32 base_addr;
} sketchbook_t;

typedef enum {
    SKETCHBOOK_CMD_CLEAR         = 0,
    SKETCHBOOK_CMD_DRAW_PIXEL    = 1,
    SKETCHBOOK_CMD_FILL_RECT     = 2,
    SKETCHBOOK_CMD_DRAW_LINE     = 3,
    SKETCHBOOK_CMD_DRAW_GLYPH    = 4,
    SKETCHBOOK_CMD_TRIANGLE_FLAT = 5,
    SKETCHBOOK_CMD_PRESENT       = 6,
    SKETCHBOOK_CMD_BLIT          = 7,
    SKETCHBOOK_CMD_BLIT_ASSET    = 8,
    SKETCHBOOK_CMD_TRIANGLE_GOURAUD = 9
} sketchbook_opcode_t;

#define SKETCHBOOK_SPRITE_CAT 0u
#define SKETCHBOOK_BLIT_COLOR_KEY_ENABLE 0x100u
#define SKETCHBOOK_BLIT_DEFAULT_KEY 0xe3u

/* RGB332 layout: RRR GGG BB.  Use this to migrate RGB565 constants at call
 * sites; SketchBook commands and framebuffer storage are RGB332 only. */
#define SKETCHBOOK_RGB565_TO_RGB332(rgb565) \
    ((U8)((((U16)(rgb565) >> 8) & 0xe0u) | (((U16)(rgb565) >> 6) & 0x1cu) | (((U16)(rgb565) >> 3) & 0x03u)))

typedef enum {
    SKETCHBOOK_FONT_4X6 = 0,
    SKETCHBOOK_FONT_5X7 = 1,
    SKETCHBOOK_FONT_6X8 = 2
} sketchbook_font_t;

#define SKETCHBOOK_REG_CTRL          0x00u
#define SKETCHBOOK_REG_STATUS        0x04u
#define SKETCHBOOK_REG_CMD0          0x08u
#define SKETCHBOOK_REG_CMD1          0x0cu
#define SKETCHBOOK_REG_CMD2          0x10u
#define SKETCHBOOK_REG_CMD3          0x14u
#define SKETCHBOOK_REG_CMD_PUSH      0x18u
#define SKETCHBOOK_REG_CMD_LEVEL     0x1cu
#define SKETCHBOOK_REG_FRAME_COUNTER 0x20u
#define SKETCHBOOK_REG_PAGE_STATUS   0x24u
#define SKETCHBOOK_REG_ERR_STATUS    0x28u
#define SKETCHBOOK_REG_CMD4          0x2cu

#define SKETCHBOOK_CTRL_DISPLAY_ENABLE 0x01u
#define SKETCHBOOK_CTRL_SOFT_RESET     0x02u

#define SKETCHBOOK_STATUS_BUSY         0x01u
#define SKETCHBOOK_STATUS_IDLE         0x02u
#define SKETCHBOOK_STATUS_CMD_FULL     0x04u
#define SKETCHBOOK_STATUS_FRAME_CLOSED 0x08u
#define SKETCHBOOK_STATUS_SWAP_PENDING 0x10u
#define SKETCHBOOK_STATUS_FRAME_DONE   0x20u
#define SKETCHBOOK_STATUS_ERROR        0x40u

void sketchbook_init(sketchbook_t *dev, U32 base_addr);
void sketchbook_enable(sketchbook_t *dev, U8 enable);
void sketchbook_soft_reset(sketchbook_t *dev);
U32 sketchbook_get_status(const sketchbook_t *dev);
U32 sketchbook_get_cmd_level(const sketchbook_t *dev);
U32 sketchbook_get_frame_counter(const sketchbook_t *dev);
void sketchbook_clear_status(sketchbook_t *dev, U32 mask);
void sketchbook_wait_submit_ready(const sketchbook_t *dev);
void sketchbook_wait_frame_done(sketchbook_t *dev);

void sketchbook_clear(sketchbook_t *dev, U8 rgb332);
void sketchbook_draw_pixel(sketchbook_t *dev, S16 x, S16 y, U8 rgb332);
void sketchbook_fill_rect(sketchbook_t *dev, S16 x, S16 y, U16 width, U16 height, U8 rgb332);
void sketchbook_draw_line(sketchbook_t *dev, S16 x0, S16 y0, S16 x1, S16 y1, U8 rgb332);
void sketchbook_draw_glyph(
    sketchbook_t *dev, S16 x, S16 y, char ascii, sketchbook_font_t font, U8 rgb332
);
void sketchbook_triangle_flat(
    sketchbook_t *dev,
    S16 x0, S16 y0, S16 x1, S16 y1, S16 x2, S16 y2,
    U8 rgb332
);
void sketchbook_triangle_gouraud(
    sketchbook_t *dev,
    S16 x0, S16 y0, U8 c0, S16 x1, S16 y1, U8 c1, S16 x2, S16 y2, U8 c2
);
void sketchbook_blit_sprite(
    sketchbook_t *dev, U8 sprite_id, S16 x, S16 y, U16 width, U16 height,
    U8 color_key_enable, U8 color_key
);
void sketchbook_blit_asset(
    sketchbook_t *dev, U8 asset_id, S16 dst_x, S16 dst_y, U16 src_x, U16 src_y,
    U16 width, U16 height, U8 color_key_enable, U8 color_key
);
void sketchbook_present(sketchbook_t *dev);

#endif /* SKETCHBOOK_H */
