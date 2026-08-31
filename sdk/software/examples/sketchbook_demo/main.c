#include <stdio.h>

#include "led.h"
#include "sketchbook.h"

unsigned long UART_BASE = 0xbf000000;
unsigned long CONFREG_TIMER_BASE = 0xbf20f100;
unsigned long CONFREG_CLOCKS_PER_SEC = 50000000L;
unsigned long CORE_CLOCKS_PER_SEC = 33000000L;

int main(void)
{
    sketchbook_t display;

    setvbuf(stdout, 0, _IONBF, 0);
    setLedPin(0x0001u);
    printf("SKETCHBOOK DEMO START\r\n");

    sketchbook_init(&display, SKETCHBOOK_BASE_ADDR);
    sketchbook_clear(&display, 0x02u);
    sketchbook_fill_rect(&display, 24, 24, 160, 80, 0xe0u);
    sketchbook_fill_rect(&display, 64, 128, 240, 96, 0x1cu);
    sketchbook_draw_line(&display, 0, 0, 399, 299, 0xffu);
    sketchbook_draw_glyph(&display, 32, 48, 'S', SKETCHBOOK_FONT_6X8, 0xffu);
    sketchbook_draw_glyph(&display, 40, 48, 'B', SKETCHBOOK_FONT_6X8, 0xffu);
    /* Consecutive source pixels exercise all eight RGB332 framebuffer lanes. */
    sketchbook_draw_pixel(&display, 200, 24, 0x00u);
    sketchbook_draw_pixel(&display, 201, 24, 0xe0u);
    sketchbook_draw_pixel(&display, 202, 24, 0x1cu);
    sketchbook_draw_pixel(&display, 203, 24, 0x03u);
    sketchbook_draw_pixel(&display, 204, 24, 0xffu);
    sketchbook_draw_pixel(&display, 205, 24, 0xe3u);
    sketchbook_draw_pixel(&display, 206, 24, 0x1fu);
    sketchbook_draw_pixel(&display, 207, 24, 0x92u);
    sketchbook_triangle_flat(&display, 250, 40, 350, 40, 300, 100, 0x92u);
    sketchbook_present(&display);
    sketchbook_wait_frame_done(&display);

    if (sketchbook_get_status(&display) & SKETCHBOOK_STATUS_ERROR) {
        printf("SKETCHBOOK DEMO FAIL\r\n");
        setLedPin(0xf000u);
    } else {
        printf("SKETCHBOOK DEMO PASS\r\n");
        setLedPin(0x00ffu);
    }
    for (;;) { }
}
