#include "blade_os.h"

#include <rthw.h>
#include <rtthread.h>

#include "fb_cache.h"
#include "gdu_fb.h"
#include "gfx2d.h"
#include "gfx_perf.h"
#include "gru.h"
#include "led.h"
#include "regaddr.h"
#include "soc_config.h"

#define OS_FB_FRAME_BYTES   (SOC_FB_WIDTH * SOC_FB_HEIGHT * SOC_FB_PIXEL_BYTES)
#define OS_FB_BASE_C        (SOC_FB_BASE_B + OS_FB_FRAME_BYTES)
#define OS_FB_BASE_D        (OS_FB_BASE_C + OS_FB_FRAME_BYTES)

#define COLOR_BLACK         0x0000u
#define COLOR_WHITE         0xffffu
#define COLOR_RED           0xe000u
#define COLOR_GREEN         0x0700u
#define COLOR_BLUE          0x0018u
#define COLOR_YELLOW        0xe700u
#define COLOR_CYAN          0x07ffu
#define COLOR_ORANGE        0xf4a0u
#define COLOR_SILVER        0xc618u
#define COLOR_GRAY          0x8410u
#define COLOR_DARK          0x18c3u
#define COLOR_NAVY          0x084fu
#define COLOR_MINT          0x87f0u

#define BTN_UP_MASK         0x01u
#define BTN_LEFT_MASK       0x02u
#define BTN_DOWN_MASK       0x04u
#define BTN_RIGHT_MASK      0x08u
#define BTN_CENTER_MASK     0x10u

#define SW_BACK_MASK        0x40u
#define SW_HOME_MASK        0x80u

#define INPUT_POLL_MS       20
#define UI_REFRESH_MS       50

#define TERM_CELL_W         7
#define TERM_CELL_H         9
#define TERM_BODY_Y         28
#define TERM_STATUS_Y       (SOC_FB_HEIGHT - 12)
#define TERM_COLS           (SOC_FB_WIDTH / TERM_CELL_W)
#define TERM_ROWS           ((SOC_FB_HEIGHT - TERM_BODY_Y - 16) / TERM_CELL_H)
#define TERM_LOG_LINES      128
#define TERM_CMD_COUNT      8

#define UI_MQ_DEPTH         32

typedef enum
{
    BLADE_SCENE_DESKTOP = 0,
    BLADE_SCENE_TERMINAL = 1,
    BLADE_SCENE_MONITOR = 2
} blade_scene_t;

typedef enum
{
    UI_EVENT_NONE = 0,
    UI_EVENT_UP,
    UI_EVENT_DOWN,
    UI_EVENT_LEFT,
    UI_EVENT_RIGHT,
    UI_EVENT_CONFIRM,
    UI_EVENT_BACK,
    UI_EVENT_HOME,
    UI_EVENT_OPEN_DESKTOP,
    UI_EVENT_OPEN_TERMINAL,
    UI_EVENT_OPEN_MONITOR,
    UI_EVENT_CLEAR_TERMINAL
} ui_event_type_t;

typedef struct
{
    U8 type;
    U8 data0;
    U16 data1;
} ui_event_msg_t;

typedef struct
{
    U32 base[2];
    gfx_ctx_t ctx[2];
    U8 front_idx;
    U8 back_idx;
} blade_fb_pool_t;

typedef struct
{
    U32 gru_pix;
    U32 blit_pix;
    U32 gdu_rd;
    U32 gdu_wait;
} blade_monitor_window_t;

static blade_fb_pool_t g_desktop_pool;
static blade_fb_pool_t g_app_pool;

static rt_mq_t g_ui_mq = RT_NULL;
static rt_thread_t g_ui_thread = RT_NULL;
static rt_thread_t g_input_thread = RT_NULL;

static volatile U32 g_pending_button_irq;

static U8 g_hw_ready;
static U8 g_app_ready;
static blade_scene_t g_scene = BLADE_SCENE_DESKTOP;
static U8 g_selected_app;
static U8 g_monitor_period_slot;

static U8 g_desktop_dirty;
static U8 g_terminal_dirty;
static U8 g_monitor_dirty;

static U32 g_current_fb_base;
static U32 g_btn_event_count;
static U32 g_sw_event_count;
static U32 g_present_count;
static U32 g_scene_switch_count;
static U32 g_gru_error_count;
static U32 g_gdu_error_count;
static U8 g_switch_stable;
static U8 g_switch_candidate;
static U8 g_switch_debounce;

static char g_term_lines[TERM_LOG_LINES][TERM_COLS];
static U16 g_term_head;
static U16 g_term_count;
static U16 g_term_write;
static U16 g_term_col;
static U16 g_term_view_offset;
static U16 g_term_generation;
static U16 g_term_render_generation;
static U8 g_term_cmd_index;

static const char *const g_term_cmd_names[TERM_CMD_COUNT] =
{
    "help",
    "clear",
    "uptime",
    "status",
    "gru",
    "gdu",
    "desktop",
    "monitor"
};

static gfx_perf_t g_perf_prev;
static gfx_perf_t g_perf_curr;
static blade_monitor_window_t g_monitor_window;
static U8 g_perf_valid;
static rt_tick_t g_monitor_last_tick;

static const char *blade_os_scene_name(blade_scene_t scene)
{
    switch (scene)
    {
    case BLADE_SCENE_DESKTOP:
        return "desktop";
    case BLADE_SCENE_TERMINAL:
        return "terminal";
    case BLADE_SCENE_MONITOR:
        return "monitor";
    default:
        return "unknown";
    }
}

static rt_tick_t blade_os_ms_to_tick(rt_int32_t ms)
{
    rt_tick_t tick;

    tick = rt_tick_from_millisecond(ms);
    if (tick == 0)
    {
        tick = 1;
    }
    return tick;
}

static void blade_os_set_leds_for_scene(blade_scene_t scene)
{
    U32 led_mask;

    switch (scene)
    {
    case BLADE_SCENE_DESKTOP:
        led_mask = 0x04u;
        break;
    case BLADE_SCENE_TERMINAL:
        led_mask = 0x01u;
        break;
    case BLADE_SCENE_MONITOR:
        led_mask = 0x02u;
        break;
    default:
        led_mask = 0x08u;
        break;
    }

    if (g_selected_app == 1u)
    {
        led_mask |= 0x10u;
    }
    setLedPin(led_mask);
}

static void blade_os_ctx_init(gfx_ctx_t *ctx, U32 base_addr)
{
    gfx_init(ctx, (volatile U16 *)base_addr, SOC_FB_WIDTH, SOC_FB_HEIGHT,
             (U16)(SOC_FB_STRIDE_BYTES / 2u));
    gfx_set_backend(ctx, GFX_BACKEND_GRU);
    gfx_set_font(ctx, GFX_FONT_5X7);
}

static void blade_os_pool_init(blade_fb_pool_t *pool, U32 base_a, U32 base_b)
{
    pool->base[0] = base_a;
    pool->base[1] = base_b;
    pool->front_idx = 0u;
    pool->back_idx = 1u;
    blade_os_ctx_init(&pool->ctx[0], base_a);
    blade_os_ctx_init(&pool->ctx[1], base_b);
}

static gfx_ctx_t *blade_os_front_ctx(blade_fb_pool_t *pool)
{
    return &pool->ctx[pool->front_idx];
}

static gfx_ctx_t *blade_os_back_ctx(blade_fb_pool_t *pool)
{
    return &pool->ctx[pool->back_idx];
}

static U32 blade_os_front_base(blade_fb_pool_t *pool)
{
    return pool->base[pool->front_idx];
}

static U32 blade_os_back_base(blade_fb_pool_t *pool)
{
    return pool->base[pool->back_idx];
}

static void blade_os_config_gru_target(blade_fb_pool_t *pool)
{
    gru_config_fb(blade_os_back_base(pool), SOC_FB_STRIDE_BYTES, SOC_FB_WIDTH, SOC_FB_HEIGHT);
}

static void blade_os_mark_status(U32 status)
{
    if ((status & (GRU_STATUS_AXI_ERROR | GRU_STATUS_CFG_ERROR)) != 0u)
    {
        g_gru_error_count++;
    }
    if ((status & (GDU_STATUS_UNDERFLOW | GDU_STATUS_AXI_ERROR)) != 0u)
    {
        g_gdu_error_count++;
    }
}

static void blade_os_draw_meter(gfx_ctx_t *ctx,
                                S32 x,
                                S32 y,
                                S32 width,
                                S32 height,
                                U32 value,
                                U32 full_scale,
                                U16 fill,
                                const char *label)
{
    U32 filled;
    char text[32];

    if (full_scale == 0u)
    {
        full_scale = 1u;
    }
    if (value > full_scale)
    {
        value = full_scale;
    }

    filled = (value * (U32)(width - 2)) / full_scale;

    gfx_draw_text(ctx, x, y - 10, label, COLOR_WHITE, COLOR_BLACK, 1u);
    gfx_draw_rect(ctx, x, y, width, height, COLOR_WHITE);
    gfx_fill_rect(ctx, x + 1, y + 1, width - 2, height - 2, COLOR_DARK);
    if (filled > 0u)
    {
        gfx_fill_rect(ctx, x + 1, y + 1, (S32)filled, height - 2, fill);
    }

    rt_snprintf(text, sizeof(text), "%lu", (unsigned long)value);
    gfx_draw_text(ctx, x + width + 6, y + 2, text, COLOR_WHITE, COLOR_BLACK, 1u);
}

static void blade_os_clear_line(char *line)
{
    U16 i;

    for (i = 0; i < TERM_COLS; ++i)
    {
        line[i] = ' ';
    }
}

static void blade_os_terminal_reset(void)
{
    U16 i;

    for (i = 0; i < TERM_LOG_LINES; ++i)
    {
        blade_os_clear_line(g_term_lines[i]);
    }

    g_term_head = 0u;
    g_term_count = 1u;
    g_term_write = 0u;
    g_term_col = 0u;
    g_term_view_offset = 0u;
    g_term_generation++;
    g_terminal_dirty = 1u;
}

static U16 blade_os_term_line_index(U16 logical_index)
{
    return (U16)((g_term_head + logical_index) % TERM_LOG_LINES);
}

static void blade_os_terminal_advance_line(void)
{
    U16 next_write;

    next_write = (U16)((g_term_write + 1u) % TERM_LOG_LINES);
    if (g_term_count < TERM_LOG_LINES)
    {
        g_term_count++;
    }
    else
    {
        g_term_head = (U16)((g_term_head + 1u) % TERM_LOG_LINES);
    }

    g_term_write = next_write;
    g_term_col = 0u;
    blade_os_clear_line(g_term_lines[g_term_write]);
}

static void blade_os_terminal_put_char_internal(char ch)
{
    if (ch == '\r')
    {
        g_term_col = 0u;
        return;
    }

    if (ch == '\n')
    {
        blade_os_terminal_advance_line();
        g_term_generation++;
        g_terminal_dirty = 1u;
        return;
    }

    if (ch == '\b')
    {
        if (g_term_col > 0u)
        {
            g_term_col--;
            g_term_lines[g_term_write][g_term_col] = ' ';
            g_term_generation++;
            g_terminal_dirty = 1u;
        }
        return;
    }

    if ((U8)ch < 0x20u)
    {
        return;
    }

    if (g_term_col >= TERM_COLS)
    {
        blade_os_terminal_advance_line();
    }

    g_term_lines[g_term_write][g_term_col] = ch;
    g_term_col++;
    g_term_generation++;
    g_terminal_dirty = 1u;
}

static void blade_os_draw_desktop(gfx_ctx_t *ctx)
{
    U16 term_fill;
    U16 mon_fill;

    term_fill = (g_selected_app == 0u) ? COLOR_ORANGE : COLOR_NAVY;
    mon_fill = (g_selected_app == 1u) ? COLOR_MINT : COLOR_NAVY;

    gfx_clear(ctx, COLOR_BLUE);
    gfx_fill_rect(ctx, 0, 0, SOC_FB_WIDTH, 22, COLOR_BLACK);
    gfx_fill_rect(ctx, 0, SOC_FB_HEIGHT - 18, SOC_FB_WIDTH, 18, COLOR_BLACK);

    gfx_set_font(ctx, GFX_FONT_6X8);
    gfx_draw_text(ctx, 8, 7, "BladeOS", COLOR_YELLOW, COLOR_BLACK, 1u);
    gfx_draw_text(ctx, 88, 7, "RT-Thread Nano  DDR OK", COLOR_CYAN, COLOR_BLACK, 1u);

    gfx_fill_rect(ctx, 34, 64, 104, 82, term_fill);
    gfx_draw_rect(ctx, 34, 64, 104, 82, COLOR_WHITE);
    gfx_fill_rect(ctx, 182, 64, 104, 82, mon_fill);
    gfx_draw_rect(ctx, 182, 64, 104, 82, COLOR_WHITE);

    gfx_set_font(ctx, GFX_FONT_5X7);
    gfx_draw_text(ctx, 58, 88, "Terminal", COLOR_WHITE, term_fill, 1u);
    gfx_draw_text(ctx, 210, 88, "Monitor", COLOR_WHITE, mon_fill, 1u);
    gfx_draw_text(ctx, 60, 106, "shell log", COLOR_SILVER, term_fill, 1u);
    gfx_draw_text(ctx, 206, 106, "perf view", COLOR_SILVER, mon_fill, 1u);

    if (g_selected_app == 0u)
    {
        gfx_draw_rect(ctx, 28, 58, 116, 94, COLOR_YELLOW);
        gfx_draw_rect(ctx, 27, 57, 118, 96, COLOR_WHITE);
    }
    else
    {
        gfx_draw_rect(ctx, 176, 58, 116, 94, COLOR_YELLOW);
        gfx_draw_rect(ctx, 175, 57, 118, 96, COLOR_WHITE);
    }

    gfx_draw_text(ctx, 14, SOC_FB_HEIGHT - 12,
                  "LEFT/RIGHT select  CENTER open  SW6 back  SW7 home",
                  COLOR_WHITE, COLOR_BLACK, 1u);
}

static void blade_os_terminal_row_text(U16 logical_row, char *out_text)
{
    U16 i;
    U16 line_index;

    line_index = blade_os_term_line_index(logical_row);
    for (i = 0; i < TERM_COLS; ++i)
    {
        out_text[i] = g_term_lines[line_index][i];
    }
    out_text[TERM_COLS] = '\0';
}

static void blade_os_draw_terminal(gfx_ctx_t *ctx)
{
    char row_text[TERM_COLS + 1];
    char header[64];
    char footer[64];
    U16 visible_lines;
    U16 logical_start;
    U16 row;

    gfx_clear(ctx, COLOR_BLACK);
    gfx_fill_rect(ctx, 0, 0, SOC_FB_WIDTH, 20, COLOR_DARK);
    gfx_fill_rect(ctx, 0, 20, SOC_FB_WIDTH, 8, COLOR_NAVY);

    gfx_set_font(ctx, GFX_FONT_5X7);
    rt_snprintf(header, sizeof(header), "Terminal cmd=%s view=%u",
                g_term_cmd_names[g_term_cmd_index],
                (unsigned int)g_term_view_offset);
    gfx_draw_text(ctx, 6, 7, header, COLOR_YELLOW, COLOR_DARK, 1u);

    visible_lines = (g_term_count > TERM_ROWS) ? TERM_ROWS : g_term_count;
    if (g_term_count > (U16)(visible_lines + g_term_view_offset))
    {
        logical_start = (U16)(g_term_count - visible_lines - g_term_view_offset);
    }
    else
    {
        logical_start = 0u;
    }

    for (row = 0; row < visible_lines; ++row)
    {
        blade_os_terminal_row_text((U16)(logical_start + row), row_text);
        gfx_draw_text(ctx, 0, TERM_BODY_Y + (row * TERM_CELL_H),
                      row_text, COLOR_WHITE, COLOR_BLACK, 1u);
    }

    rt_snprintf(footer, sizeof(footer), "UP/DOWN cmd  LEFT/RIGHT scroll  CENTER run");
    gfx_draw_text(ctx, 4, TERM_STATUS_Y, footer, COLOR_CYAN, COLOR_BLACK, 1u);
}

static U32 blade_os_diff_u32(U32 now, U32 prev)
{
    return now - prev;
}

static void blade_os_monitor_sample(void)
{
    gfx_perf_sample_all(&g_perf_curr);
    if (g_perf_valid != 0u)
    {
        g_monitor_window.gru_pix =
            blade_os_diff_u32(g_perf_curr.gru.wcb_pix_in, g_perf_prev.gru.wcb_pix_in);
        g_monitor_window.blit_pix =
            blade_os_diff_u32(g_perf_curr.gru.blit_pixel, g_perf_prev.gru.blit_pixel);
        g_monitor_window.gdu_rd =
            blade_os_diff_u32(g_perf_curr.gdu.rd_beat, g_perf_prev.gdu.rd_beat);
        g_monitor_window.gdu_wait =
            blade_os_diff_u32(g_perf_curr.gdu.arb_gdu_wait, g_perf_prev.gdu.arb_gdu_wait);
    }
    else
    {
        g_monitor_window.gru_pix = g_perf_curr.gru.wcb_pix_in;
        g_monitor_window.blit_pix = g_perf_curr.gru.blit_pixel;
        g_monitor_window.gdu_rd = g_perf_curr.gdu.rd_beat;
        g_monitor_window.gdu_wait = g_perf_curr.gdu.arb_gdu_wait;
        g_perf_valid = 1u;
    }
    g_perf_prev = g_perf_curr;
}

static void blade_os_draw_monitor(gfx_ctx_t *ctx)
{
    char text[64];
    U32 uptime_ms;
    U32 max_scale;
    U32 period_ms;

    blade_os_monitor_sample();

    uptime_ms = (U32)rt_tick_get();
    uptime_ms = (uptime_ms * 1000u) / RT_TICK_PER_SECOND;
    period_ms = (g_monitor_period_slot == 0u) ? 100u :
                (g_monitor_period_slot == 1u) ? 200u : 500u;

    gfx_clear(ctx, COLOR_BLACK);
    gfx_fill_rect(ctx, 0, 0, SOC_FB_WIDTH, 22, COLOR_DARK);
    gfx_set_font(ctx, GFX_FONT_5X7);

    rt_snprintf(text, sizeof(text), "Monitor uptime=%lu ms", (unsigned long)uptime_ms);
    gfx_draw_text(ctx, 6, 8, text, COLOR_YELLOW, COLOR_DARK, 1u);

    rt_snprintf(text, sizeof(text), "scene=%s presents=%lu period=%lu ms",
                blade_os_scene_name(g_scene),
                (unsigned long)g_present_count,
                (unsigned long)period_ms);
    gfx_draw_text(ctx, 6, 28, text, COLOR_WHITE, COLOR_BLACK, 1u);

    rt_snprintf(text, sizeof(text), "btn=%lu sw=%lu gru_err=%lu gdu_err=%lu",
                (unsigned long)g_btn_event_count,
                (unsigned long)g_sw_event_count,
                (unsigned long)g_gru_error_count,
                (unsigned long)g_gdu_error_count);
    gfx_draw_text(ctx, 6, 40, text, COLOR_SILVER, COLOR_BLACK, 1u);

    max_scale = g_monitor_window.gru_pix;
    if (g_monitor_window.blit_pix > max_scale)
    {
        max_scale = g_monitor_window.blit_pix;
    }
    if (g_monitor_window.gdu_rd > max_scale)
    {
        max_scale = g_monitor_window.gdu_rd;
    }
    if (g_monitor_window.gdu_wait > max_scale)
    {
        max_scale = g_monitor_window.gdu_wait;
    }
    if (max_scale < 64u)
    {
        max_scale = 64u;
    }

    blade_os_draw_meter(ctx, 16, 76, 180, 14, g_monitor_window.gru_pix, max_scale,
                        COLOR_GREEN, "GRU pixels");
    blade_os_draw_meter(ctx, 16, 106, 180, 14, g_monitor_window.blit_pix, max_scale,
                        COLOR_ORANGE, "BLIT pixels");
    blade_os_draw_meter(ctx, 16, 136, 180, 14, g_monitor_window.gdu_rd, max_scale,
                        COLOR_CYAN, "GDU read beats");
    blade_os_draw_meter(ctx, 16, 166, 180, 14, g_monitor_window.gdu_wait, max_scale,
                        COLOR_RED, "GDU wait");

    rt_snprintf(text, sizeof(text), "raw blit_cycle=%lu raw gdu_max_wait=%lu",
                (unsigned long)g_perf_curr.gru.blit_cycle,
                (unsigned long)g_perf_curr.gdu.arb_gdu_max_wait);
    gfx_draw_text(ctx, 16, 196, text, COLOR_SILVER, COLOR_BLACK, 1u);
    gfx_draw_text(ctx, 16, 224, "UP/DOWN refresh  SW6/SW7 exit",
                  COLOR_WHITE, COLOR_BLACK, 1u);
}

static U32 blade_os_present_pool(blade_fb_pool_t *pool)
{
    U32 status;
    U8 next_front;

    status = gru_wait_idle_checked();
    blade_os_mark_status(status);
    if ((status & (GRU_STATUS_AXI_ERROR | GRU_STATUS_CFG_ERROR)) != 0u)
    {
        return status;
    }

    fb_cache_flush_frame(blade_os_back_base(pool), SOC_FB_WIDTH, SOC_FB_HEIGHT, SOC_FB_STRIDE_BYTES);
    if (g_current_fb_base != blade_os_back_base(pool))
    {
        rt_kprintf("[DBG][PRESENT] request front=%08lx back=%08lx\n",
                   (unsigned long)g_current_fb_base,
                   (unsigned long)blade_os_back_base(pool));
        gdu_fb_request_swap(blade_os_back_base(pool));
        status = gdu_fb_wait_swap_done_checked();
        rt_kprintf("[DBG][PRESENT] swap_done status=%08lx\n", (unsigned long)status);
        blade_os_mark_status(status);
        if ((status & (GDU_STATUS_UNDERFLOW | GDU_STATUS_AXI_ERROR)) != 0u)
        {
            return status;
        }
    }

    next_front = pool->back_idx;
    pool->back_idx = pool->front_idx;
    pool->front_idx = next_front;
    g_current_fb_base = blade_os_front_base(pool);
    blade_os_config_gru_target(pool);
    g_present_count++;
    return status;
}

static U32 blade_os_show_front_pool(blade_fb_pool_t *pool)
{
    U32 status;

    if (g_current_fb_base == blade_os_front_base(pool))
    {
        blade_os_config_gru_target(pool);
        return 0u;
    }

    gdu_fb_request_swap(blade_os_front_base(pool));
    status = gdu_fb_wait_swap_done_checked();
    blade_os_mark_status(status);
    if ((status & (GDU_STATUS_UNDERFLOW | GDU_STATUS_AXI_ERROR)) == 0u)
    {
        g_current_fb_base = blade_os_front_base(pool);
        blade_os_config_gru_target(pool);
        g_present_count++;
    }
    return status;
}

static void blade_os_render_desktop_and_present(void)
{
    blade_os_config_gru_target(&g_desktop_pool);
    blade_os_draw_desktop(blade_os_back_ctx(&g_desktop_pool));
    (void)blade_os_present_pool(&g_desktop_pool);
    g_desktop_dirty = 0u;
}

static void blade_os_render_terminal_and_present(void)
{
    blade_os_config_gru_target(&g_app_pool);
    blade_os_draw_terminal(blade_os_back_ctx(&g_app_pool));
    (void)blade_os_present_pool(&g_app_pool);
    g_term_render_generation = g_term_generation;
    g_terminal_dirty = 0u;
}

static void blade_os_render_monitor_and_present(void)
{
    blade_os_config_gru_target(&g_app_pool);
    blade_os_draw_monitor(blade_os_back_ctx(&g_app_pool));
    (void)blade_os_present_pool(&g_app_pool);
    g_monitor_dirty = 0u;
}

static rt_err_t blade_os_queue_event(U8 event_type)
{
    ui_event_msg_t msg;

    if (g_ui_mq == RT_NULL)
    {
        return -RT_ERROR;
    }

    msg.type = event_type;
    msg.data0 = 0u;
    msg.data1 = 0u;
    return rt_mq_send(g_ui_mq, &msg, sizeof(msg));
}

static void blade_os_print_uptime(void)
{
    U32 ticks;
    U32 ms;

    ticks = (U32)rt_tick_get();
    ms = (ticks * 1000u) / RT_TICK_PER_SECOND;
    rt_kprintf("uptime: %lu ticks  %lu ms\n", (unsigned long)ticks, (unsigned long)ms);
}

static void blade_os_print_status(void)
{
    rt_kprintf("scene=%s selected_app=%s presents=%lu scene_switch=%lu\n",
               blade_os_scene_name(g_scene),
               (g_selected_app == 0u) ? "terminal" : "monitor",
               (unsigned long)g_present_count,
               (unsigned long)g_scene_switch_count);
    rt_kprintf("btn_events=%lu sw_events=%lu term_gen=%u view=%u\n",
               (unsigned long)g_btn_event_count,
               (unsigned long)g_sw_event_count,
               (unsigned int)g_term_generation,
               (unsigned int)g_term_view_offset);
    rt_kprintf("gru_errors=%lu gdu_errors=%lu\n",
               (unsigned long)g_gru_error_count,
               (unsigned long)g_gdu_error_count);
}

static void blade_os_print_help(void)
{
    rt_kprintf("help clear uptime status gru gdu desktop monitor terminal\n");
}

static void blade_os_open_scene(blade_scene_t scene)
{
    if (g_scene != scene)
    {
        rt_kprintf("[DBG][SCENE] %s -> %s\n", blade_os_scene_name(g_scene), blade_os_scene_name(scene));
        g_scene = scene;
        g_scene_switch_count++;
        blade_os_set_leds_for_scene(scene);

        if (scene == BLADE_SCENE_DESKTOP)
        {
            rt_kprintf("SCENE DESKTOP\n");
        }
        else if (scene == BLADE_SCENE_TERMINAL)
        {
            rt_kprintf("SCENE TERMINAL\n");
        }
        else if (scene == BLADE_SCENE_MONITOR)
        {
            rt_kprintf("SCENE MONITOR\n");
        }
    }

    if (scene == BLADE_SCENE_DESKTOP)
    {
        if (g_desktop_dirty != 0u)
        {
            blade_os_render_desktop_and_present();
        }
        else
        {
            (void)blade_os_show_front_pool(&g_desktop_pool);
        }
    }
    else if (scene == BLADE_SCENE_TERMINAL)
    {
        g_term_view_offset = 0u;
        blade_os_render_terminal_and_present();
    }
    else
    {
        g_monitor_last_tick = 0u;
        blade_os_render_monitor_and_present();
    }
}

static void blade_os_execute_terminal_command(U8 cmd_index)
{
    switch (cmd_index)
    {
    case 0u:
        blade_os_print_help();
        break;
    case 1u:
        blade_os_terminal_reset();
        break;
    case 2u:
        blade_os_print_uptime();
        break;
    case 3u:
        blade_os_print_status();
        break;
    case 4u:
        gru_perf_sample(&g_perf_curr.gru);
        gru_perf_print(&g_perf_curr.gru);
        break;
    case 5u:
        gdu_perf_sample(&g_perf_curr.gdu);
        gdu_perf_print(&g_perf_curr.gdu);
        break;
    case 6u:
        (void)blade_os_queue_event(UI_EVENT_OPEN_DESKTOP);
        break;
    case 7u:
        (void)blade_os_queue_event(UI_EVENT_OPEN_MONITOR);
        break;
    default:
        break;
    }
}

static void blade_os_handle_desktop_event(U8 event_type)
{
    if ((event_type == UI_EVENT_LEFT) || (event_type == UI_EVENT_RIGHT))
    {
        g_selected_app ^= 1u;
        g_desktop_dirty = 1u;
        blade_os_render_desktop_and_present();
        return;
    }

    if (event_type == UI_EVENT_CONFIRM)
    {
        if (g_selected_app == 0u)
        {
            blade_os_open_scene(BLADE_SCENE_TERMINAL);
        }
        else
        {
            blade_os_open_scene(BLADE_SCENE_MONITOR);
        }
    }
}

static void blade_os_handle_terminal_event(U8 event_type)
{
    if (event_type == UI_EVENT_UP)
    {
        if (g_term_cmd_index == 0u)
        {
            g_term_cmd_index = TERM_CMD_COUNT - 1u;
        }
        else
        {
            g_term_cmd_index--;
        }
        blade_os_render_terminal_and_present();
        return;
    }

    if (event_type == UI_EVENT_DOWN)
    {
        g_term_cmd_index = (U8)((g_term_cmd_index + 1u) % TERM_CMD_COUNT);
        blade_os_render_terminal_and_present();
        return;
    }

    if (event_type == UI_EVENT_LEFT)
    {
        if ((g_term_view_offset + 1u) < TERM_LOG_LINES)
        {
            g_term_view_offset++;
            blade_os_render_terminal_and_present();
        }
        return;
    }

    if (event_type == UI_EVENT_RIGHT)
    {
        if (g_term_view_offset > 0u)
        {
            g_term_view_offset--;
            blade_os_render_terminal_and_present();
        }
        return;
    }

    if (event_type == UI_EVENT_CONFIRM)
    {
        blade_os_execute_terminal_command(g_term_cmd_index);
        g_terminal_dirty = 1u;
    }
}

static void blade_os_handle_monitor_event(U8 event_type)
{
    if (event_type == UI_EVENT_UP)
    {
        if (g_monitor_period_slot == 0u)
        {
            g_monitor_period_slot = 2u;
        }
        else
        {
            g_monitor_period_slot--;
        }
        blade_os_render_monitor_and_present();
        return;
    }

    if (event_type == UI_EVENT_DOWN)
    {
        g_monitor_period_slot = (U8)((g_monitor_period_slot + 1u) % 3u);
        blade_os_render_monitor_and_present();
        return;
    }

    if (event_type == UI_EVENT_CONFIRM)
    {
        blade_os_render_monitor_and_present();
    }
}

static void blade_os_handle_event(U8 event_type)
{
    if ((event_type == UI_EVENT_HOME) || (event_type == UI_EVENT_OPEN_DESKTOP))
    {
        blade_os_open_scene(BLADE_SCENE_DESKTOP);
        return;
    }

    if (event_type == UI_EVENT_OPEN_TERMINAL)
    {
        g_selected_app = 0u;
        g_desktop_dirty = 1u;
        blade_os_open_scene(BLADE_SCENE_TERMINAL);
        return;
    }

    if (event_type == UI_EVENT_OPEN_MONITOR)
    {
        g_selected_app = 1u;
        g_desktop_dirty = 1u;
        blade_os_open_scene(BLADE_SCENE_MONITOR);
        return;
    }

    if (event_type == UI_EVENT_CLEAR_TERMINAL)
    {
        blade_os_terminal_reset();
        if (g_scene == BLADE_SCENE_TERMINAL)
        {
            blade_os_render_terminal_and_present();
        }
        return;
    }

    if ((event_type == UI_EVENT_BACK) && (g_scene != BLADE_SCENE_DESKTOP))
    {
        blade_os_open_scene(BLADE_SCENE_DESKTOP);
        return;
    }

    if (g_scene == BLADE_SCENE_DESKTOP)
    {
        blade_os_handle_desktop_event(event_type);
    }
    else if (g_scene == BLADE_SCENE_TERMINAL)
    {
        blade_os_handle_terminal_event(event_type);
    }
    else
    {
        blade_os_handle_monitor_event(event_type);
    }
}

static void blade_os_poll_background(void)
{
    rt_tick_t now;
    rt_tick_t period_tick;

    if ((g_scene == BLADE_SCENE_TERMINAL) &&
        (g_terminal_dirty != 0u) &&
        (g_term_render_generation != g_term_generation))
    {
        blade_os_render_terminal_and_present();
    }

    if (g_scene == BLADE_SCENE_MONITOR)
    {
        if (g_monitor_period_slot == 0u)
        {
            period_tick = blade_os_ms_to_tick(100);
        }
        else if (g_monitor_period_slot == 1u)
        {
            period_tick = blade_os_ms_to_tick(200);
        }
        else
        {
            period_tick = blade_os_ms_to_tick(500);
        }

        now = rt_tick_get();
        if ((g_monitor_last_tick == 0u) ||
            ((now - g_monitor_last_tick) >= period_tick) ||
            (g_monitor_dirty != 0u))
        {
            g_monitor_last_tick = now;
            blade_os_render_monitor_and_present();
        }
    }
}

static void blade_os_input_take_buttons(U32 *pending)
{
    rt_base_t level;

    level = rt_hw_interrupt_disable();
    *pending = g_pending_button_irq;
    g_pending_button_irq = 0u;
    rt_hw_interrupt_enable(level);
}

static void blade_os_input_post_button_events(U32 pending)
{
    rt_kprintf("[DBG][INPUT] pending_btn=%02lx\n", (unsigned long)pending);
    if ((pending & BTN_UP_MASK) != 0u)
    {
        g_btn_event_count++;
        (void)blade_os_queue_event(UI_EVENT_UP);
    }
    if ((pending & BTN_DOWN_MASK) != 0u)
    {
        g_btn_event_count++;
        (void)blade_os_queue_event(UI_EVENT_DOWN);
    }
    if ((pending & BTN_LEFT_MASK) != 0u)
    {
        g_btn_event_count++;
        (void)blade_os_queue_event(UI_EVENT_LEFT);
    }
    if ((pending & BTN_RIGHT_MASK) != 0u)
    {
        g_btn_event_count++;
        (void)blade_os_queue_event(UI_EVENT_RIGHT);
    }
    if ((pending & BTN_CENTER_MASK) != 0u)
    {
        g_btn_event_count++;
        (void)blade_os_queue_event(UI_EVENT_CONFIRM);
    }
}

static void blade_os_input_poll_switches(void)
{
    U8 sample;
    U8 changed;

    sample = (U8)(RegRead(CONFREG_SWITCH_DATA) & 0xffu);
    if (sample != g_switch_candidate)
    {
        rt_kprintf("[INPUT] sw sample=%02x candidate=%02x stable=%02x\n",
                   sample,
                   g_switch_candidate,
                   g_switch_stable);
        g_switch_candidate = sample;
        g_switch_debounce = 0u;
        return;
    }

    if (g_switch_debounce < 2u)
    {
        g_switch_debounce++;
        return;
    }

    if (g_switch_candidate != g_switch_stable)
    {
        changed = (U8)(g_switch_candidate ^ g_switch_stable);
        rt_kprintf("[INPUT] sw stable %02x -> %02x changed=%02x debounce=%u\n",
                   g_switch_stable,
                   g_switch_candidate,
                   changed,
                   g_switch_debounce);
        g_switch_stable = g_switch_candidate;

        if ((changed & SW_BACK_MASK) != 0u)
        {
            g_sw_event_count++;
            (void)blade_os_queue_event(UI_EVENT_BACK);
        }
        if ((changed & SW_HOME_MASK) != 0u)
        {
            g_sw_event_count++;
            (void)blade_os_queue_event(UI_EVENT_HOME);
        }
    }
}

static void blade_os_ui_thread_entry(void *parameter)
{
    ui_event_msg_t msg;
    rt_err_t err;

    (void)parameter;
    while (1)
    {
        err = rt_mq_recv(g_ui_mq, &msg, sizeof(msg), blade_os_ms_to_tick(UI_REFRESH_MS));
        if (err == RT_EOK)
        {
            blade_os_handle_event(msg.type);
        }
        blade_os_poll_background();
    }
}

static void blade_os_input_thread_entry(void *parameter)
{
    U32 pending;

    (void)parameter;
    while (1)
    {
        blade_os_input_take_buttons(&pending);
        if (pending != 0u)
        {
            blade_os_input_post_button_events(pending);
        }

        blade_os_input_poll_switches();
        rt_thread_mdelay(INPUT_POLL_MS);
    }
}

static int blade_os_app_init(void)
{
    if ((g_hw_ready == 0u) || (g_app_ready != 0u))
    {
        return 0;
    }

    g_ui_mq = rt_mq_create("osmq", sizeof(ui_event_msg_t), UI_MQ_DEPTH, RT_IPC_FLAG_FIFO);
    if (g_ui_mq == RT_NULL)
    {
        rt_kprintf("BLADE_OS mq create failed\n");
        return -1;
    }

    g_ui_thread = rt_thread_create("os_ui", blade_os_ui_thread_entry, RT_NULL, 3072, 6, 10);
    g_input_thread = rt_thread_create("os_in", blade_os_input_thread_entry, RT_NULL, 2048, 5, 10);
    if ((g_ui_thread == RT_NULL) || (g_input_thread == RT_NULL))
    {
        rt_kprintf("BLADE_OS thread create failed\n");
        return -1;
    }

    rt_thread_startup(g_ui_thread);
    rt_thread_startup(g_input_thread);

    g_app_ready = 1u;
    rt_kprintf("BLADE_OS READY\n");
    rt_kprintf("SCENE DESKTOP\n");
    return 0;
}
INIT_APP_EXPORT(blade_os_app_init);

void blade_os_hw_init(void)
{
    gdu_fb_cfg_t gdu_cfg;
    gru_cfg_t gru_cfg;
    U32 status;

    blade_os_pool_init(&g_desktop_pool, SOC_FB_BASE_A, SOC_FB_BASE_B);
    blade_os_pool_init(&g_app_pool, OS_FB_BASE_C, OS_FB_BASE_D);

    g_selected_app = 0u;
    g_monitor_period_slot = 1u;
    g_current_fb_base = blade_os_front_base(&g_desktop_pool);
    g_desktop_dirty = 0u;
    g_terminal_dirty = 0u;
    g_monitor_dirty = 0u;
    g_term_cmd_index = 0u;
    g_perf_valid = 0u;
    g_monitor_last_tick = 0u;
    g_pending_button_irq = 0u;
    g_switch_stable = (U8)(RegRead(CONFREG_SWITCH_DATA) & 0xffu);
    g_switch_candidate = g_switch_stable;
    g_switch_debounce = 0u;

    blade_os_terminal_reset();

    gdu_cfg.fb_base = blade_os_front_base(&g_desktop_pool);
    gdu_cfg.width = SOC_FB_WIDTH;
    gdu_cfg.height = SOC_FB_HEIGHT;
    gdu_cfg.stride_bytes = SOC_FB_STRIDE_BYTES;
    gdu_cfg.pixel_format = GDU_PIXEL_FORMAT_RGB565;

    gru_cfg.fb_base = blade_os_front_base(&g_desktop_pool);
    gru_cfg.width = SOC_FB_WIDTH;
    gru_cfg.height = SOC_FB_HEIGHT;
    gru_cfg.stride_bytes = SOC_FB_STRIDE_BYTES;

    gdu_fb_init(&gdu_cfg);
    gru_init(&gru_cfg);

    blade_os_draw_desktop(blade_os_front_ctx(&g_desktop_pool));
    status = gru_wait_idle_checked();
    blade_os_mark_status(status);
    fb_cache_flush_frame(blade_os_front_base(&g_desktop_pool),
                         SOC_FB_WIDTH,
                         SOC_FB_HEIGHT,
                         SOC_FB_STRIDE_BYTES);
    gdu_fb_enable(1u);
    blade_os_config_gru_target(&g_desktop_pool);
    blade_os_set_leds_for_scene(BLADE_SCENE_DESKTOP);
    g_hw_ready = 1u;
}

void blade_os_console_putchar(char ch)
{
    if (g_hw_ready == 0u)
    {
        return;
    }

    blade_os_terminal_put_char_internal(ch);
}

void blade_os_console_write(const char *str)
{
    if (str == RT_NULL)
    {
        return;
    }

    while (*str != '\0')
    {
        blade_os_console_putchar(*str);
        str++;
    }
}

U8 blade_os_is_ready(void)
{
    return g_hw_ready;
}

void blade_os_on_button_irq(U8 button_state)
{
    rt_kprintf("[DBG][BTN_IRQ] state=%02x pending=%02lx\n",
               (unsigned int)(button_state & 0x1fu),
               (unsigned long)g_pending_button_irq);
    g_pending_button_irq |= (U32)(button_state & 0x1fu);
}

static long blade_os_shell_clear(void)
{
    (void)blade_os_queue_event(UI_EVENT_CLEAR_TERMINAL);
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_clear, clear, clear terminal log);

static long blade_os_shell_uptime(void)
{
    blade_os_print_uptime();
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_uptime, uptime, show uptime);

static long blade_os_shell_status(void)
{
    blade_os_print_status();
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_status, status, show BladeOS status);

static long blade_os_shell_gru(void)
{
    gru_perf_sample(&g_perf_curr.gru);
    gru_perf_print(&g_perf_curr.gru);
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_gru, gru, print GRU performance counters);

static long blade_os_shell_gdu(void)
{
    gdu_perf_sample(&g_perf_curr.gdu);
    gdu_perf_print(&g_perf_curr.gdu);
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_gdu, gdu, print GDU performance counters);

static long blade_os_shell_desktop(void)
{
    (void)blade_os_queue_event(UI_EVENT_OPEN_DESKTOP);
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_desktop, desktop, switch to desktop scene);

static long blade_os_shell_monitor(void)
{
    (void)blade_os_queue_event(UI_EVENT_OPEN_MONITOR);
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_monitor, monitor, switch to monitor scene);

static long blade_os_shell_terminal(void)
{
    (void)blade_os_queue_event(UI_EVENT_OPEN_TERMINAL);
    return 0;
}
MSH_CMD_EXPORT_ALIAS(blade_os_shell_terminal, terminal, switch to terminal scene);
