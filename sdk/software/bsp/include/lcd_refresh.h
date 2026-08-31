#ifndef LCD_REFRESH_H
#define LCD_REFRESH_H

#include "common_func.h"

#define LCD_REFRESH_BASE_ADDR            0xbf100000u

#define LCD_REFRESH_CTRL_ENABLE_MASK     0x00000001u
#define LCD_REFRESH_CTRL_ABORT_MASK      0x00000010u

#define LCD_REFRESH_STATUS_BUSY          0x00000001u
#define LCD_REFRESH_STATUS_DONE          0x00000002u
#define LCD_REFRESH_STATUS_SPI_ERROR     0x00000004u
#define LCD_REFRESH_STATUS_AXI_ERROR     0x00000008u
#define LCD_REFRESH_STATUS_CFG_ERROR     0x00000010u
#define LCD_REFRESH_STATUS_ERROR_MASK    (LCD_REFRESH_STATUS_SPI_ERROR | \
                                          LCD_REFRESH_STATUS_AXI_ERROR | \
                                          LCD_REFRESH_STATUS_CFG_ERROR)

#define LCD_REFRESH_PIXEL_FORMAT_RGB565  1u

typedef struct {
    U32 fb_base;
    U16 width;
    U16 height;
    U32 stride_bytes;
    U8 pixel_format;
} lcd_refresh_cfg_t;

/* Raw register snapshot for board bring-up and the BladeOS `lcd_diag` shell
 * command.  This reports the FPGA transport state; it cannot confirm that a
 * write-only LCD panel has accepted or displayed the pixels. */
typedef struct {
    U32 ctrl;
    U32 status;
    U32 fb_base;
    U32 stride_bytes;
    U32 size;
    U32 pixel_format;
    U32 dirty_xy;
    U32 dirty_wh;
    U32 spi_clk_div;
} lcd_refresh_debug_snapshot_t;

void lcd_init(const lcd_refresh_cfg_t *cfg);
void lcd_enable(U8 en);
void lcd_set_front(U32 fb_base);
void lcd_set_dirty_rect(U16 x, U16 y, U16 w, U16 h);
U32 lcd_get_status(void);
void lcd_get_debug_snapshot(lcd_refresh_debug_snapshot_t *snapshot);
void lcd_clear_status(U32 mask);
void lcd_present_full(void);
void lcd_present_rect(int x, int y, int w, int h);
void lcd_wait_refresh_done(void);
U32 lcd_wait_refresh_done_checked(void);

#endif /* LCD_REFRESH_H */
