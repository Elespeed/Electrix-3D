#include "lcd_refresh.h"

#define LCD_CTRL_REG         (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x00u))
#define LCD_STATUS_REG       (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x04u))
#define LCD_FB_BASE_REG      (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x08u))
#define LCD_STRIDE_REG       (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x0cu))
#define LCD_SIZE_REG         (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x10u))
#define LCD_PIXEL_FMT_REG    (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x14u))
#define LCD_REFRESH_REG      (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x18u))
#define LCD_DIRTY_XY_REG     (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x1cu))
#define LCD_DIRTY_WH_REG     (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x20u))
#define LCD_SPI_CLKDIV_REG   (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x24u))
#define LCD_IRQ_CLEAR_REG    (*(volatile U32 *)(LCD_REFRESH_BASE_ADDR + 0x28u))

#define LCD_REFRESH_FULL_START     0x1u
#define LCD_REFRESH_PARTIAL_START  0x2u

#ifndef LCD_DEFAULT_SPI_CLKDIV
#define LCD_DEFAULT_SPI_CLKDIV     4u
#endif

static void lcd_barrier(void)
{
    __asm__ volatile("" : : : "memory");
}

void lcd_init(const lcd_refresh_cfg_t *cfg)
{
    U32 pixel_format;

    if (cfg == 0) {
        return;
    }

    pixel_format = (cfg->pixel_format == 0u) ?
                   LCD_REFRESH_PIXEL_FORMAT_RGB565 : (U32)cfg->pixel_format;

    LCD_CTRL_REG = 0u;
    lcd_barrier();

    LCD_FB_BASE_REG = cfg->fb_base;
    LCD_STRIDE_REG = cfg->stride_bytes;
    LCD_SIZE_REG = ((U32)cfg->height << 16) | (U32)cfg->width;
    LCD_PIXEL_FMT_REG = pixel_format;
    LCD_SPI_CLKDIV_REG = LCD_DEFAULT_SPI_CLKDIV;
    LCD_IRQ_CLEAR_REG = LCD_REFRESH_STATUS_DONE | LCD_REFRESH_STATUS_ERROR_MASK;
    lcd_barrier();
}

void lcd_enable(U8 en)
{
    lcd_barrier();
    LCD_CTRL_REG = (en != 0u) ? LCD_REFRESH_CTRL_ENABLE_MASK : 0u;
    lcd_barrier();
}

void lcd_set_front(U32 fb_base)
{
    LCD_FB_BASE_REG = fb_base;
    lcd_barrier();
}

void lcd_set_dirty_rect(U16 x, U16 y, U16 w, U16 h)
{
    LCD_DIRTY_XY_REG = ((U32)y << 16) | (U32)x;
    LCD_DIRTY_WH_REG = ((U32)h << 16) | (U32)w;
    lcd_barrier();
}

U32 lcd_get_status(void)
{
    return LCD_STATUS_REG;
}

void lcd_get_debug_snapshot(lcd_refresh_debug_snapshot_t *snapshot)
{
    if (snapshot == 0) {
        return;
    }

    snapshot->ctrl         = LCD_CTRL_REG;
    snapshot->status       = LCD_STATUS_REG;
    snapshot->fb_base      = LCD_FB_BASE_REG;
    snapshot->stride_bytes = LCD_STRIDE_REG;
    snapshot->size         = LCD_SIZE_REG;
    snapshot->pixel_format = LCD_PIXEL_FMT_REG;
    snapshot->dirty_xy     = LCD_DIRTY_XY_REG;
    snapshot->dirty_wh     = LCD_DIRTY_WH_REG;
    snapshot->spi_clk_div  = LCD_SPI_CLKDIV_REG;
    lcd_barrier();
}

void lcd_clear_status(U32 mask)
{
    LCD_IRQ_CLEAR_REG = mask;
    lcd_barrier();
}

void lcd_present_full(void)
{
    LCD_REFRESH_REG = LCD_REFRESH_FULL_START;
    lcd_barrier();
}

void lcd_present_rect(int x, int y, int w, int h)
{
    if ((x < 0) || (y < 0) || (w <= 0) || (h <= 0) ||
        (x > 0xffff) || (y > 0xffff) || (w > 0xffff) || (h > 0xffff)) {
        return;
    }

    lcd_set_dirty_rect((U16)x, (U16)y, (U16)w, (U16)h);
    LCD_REFRESH_REG = LCD_REFRESH_PARTIAL_START;
    lcd_barrier();
}

void lcd_wait_refresh_done(void)
{
    (void)lcd_wait_refresh_done_checked();
}

U32 lcd_wait_refresh_done_checked(void)
{
    U32 status;

    do {
        status = lcd_get_status();
    } while ((status & (LCD_REFRESH_STATUS_DONE | LCD_REFRESH_STATUS_ERROR_MASK)) == 0u);

    return status;
}
