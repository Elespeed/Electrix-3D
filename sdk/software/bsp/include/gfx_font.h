#ifndef GFX_FONT_H
#define GFX_FONT_H

#include "common_func.h"

typedef enum {
    GFX_FONT_4X6 = 0,
    GFX_FONT_5X7 = 1,
    GFX_FONT_6X8 = 2
} gfx_font_id_t;

typedef struct {
    U8 width;
    U8 height;
} gfx_font_desc_t;

gfx_font_id_t gfx_font_from_string(const char *name);
const gfx_font_desc_t *gfx_font_desc(gfx_font_id_t font_id);
U8 gfx_font_pixel(gfx_font_id_t font_id, char ch, U8 x, U8 y);

#endif /* GFX_FONT_H */

