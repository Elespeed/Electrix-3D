#include "gdu_fb.h"
#include "uart_io.h"

#define GDU_CTRL_REG         (*(volatile U32 *)(GDU_BASE_ADDR + 0x00))
#define GDU_STATUS_REG       (*(volatile U32 *)(GDU_BASE_ADDR + 0x04))
#define GDU_FB_BASE_REG      (*(volatile U32 *)(GDU_BASE_ADDR + 0x08))
#define GDU_STRIDE_REG       (*(volatile U32 *)(GDU_BASE_ADDR + 0x0c))
#define GDU_WIDTH_HEIGHT_REG (*(volatile U32 *)(GDU_BASE_ADDR + 0x10))
#define GDU_PIXEL_FMT_REG    (*(volatile U32 *)(GDU_BASE_ADDR + 0x14))
#define GDU_SWAP_CTRL_REG    (*(volatile U32 *)(GDU_BASE_ADDR + 0x18))
#define GDU_PERF_RD_AR_TXN       (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_RD_AR_TXN_OFS))
#define GDU_PERF_RD_BEAT         (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_RD_BEAT_OFS))
#define GDU_PERF_RD_WAIT         (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_RD_WAIT_OFS))
#define GDU_PERF_ARB_GRU_GRANT   (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_GRU_GRANT_OFS))
#define GDU_PERF_ARB_GDU_GRANT   (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_GDU_GRANT_OFS))
#define GDU_PERF_ARB_GRU_WAIT    (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_GRU_WAIT_OFS))
#define GDU_PERF_ARB_GDU_WAIT    (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_GDU_WAIT_OFS))
#define GDU_PERF_ARB_GRU_MAXWAIT (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_GRU_MAXWAIT_OFS))
#define GDU_PERF_ARB_GDU_MAXWAIT (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_GDU_MAXWAIT_OFS))
#define GDU_PERF_ARB_QOS         (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_QOS_OFS))
#define GDU_PERF_ARB_CRITICAL    (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_CRITICAL_OFS))
#define GDU_PERF_ARB_STARVE      (*(volatile U32 *)(GDU_BASE_ADDR + GDU_REG_PERF_ARB_STARVE_OFS))

void gdu_fb_init(const gdu_fb_cfg_t *cfg)
{
    U32 pixel_format;

    if (cfg == 0) {
        return;
    }

    pixel_format = (cfg->pixel_format == 0u) ? GDU_PIXEL_FORMAT_RGB565 : (U32)cfg->pixel_format;

    // 🔧 关键修复：禁用 GDU 并清除所有配置
    GDU_CTRL_REG = 0u;

    // 添加内存屏障确保禁用操作完成
    __asm__ volatile("" : : : "memory");

    // 配置所有参数
    GDU_FB_BASE_REG = cfg->fb_base;
    GDU_STRIDE_REG = cfg->stride_bytes;
    GDU_WIDTH_HEIGHT_REG = ((U32)cfg->height << 16) | (U32)cfg->width;
    GDU_PIXEL_FMT_REG = pixel_format;

    // 🔧 关键修复：添加内存屏障确保所有写入完成
    // 这个屏障确保上面的 AXI 写操作在硬件中完全生效，
    // 然后才允许后续的 enable 操作执行
    __asm__ volatile("" : : : "memory");
}

void gdu_fb_enable(U8 en)
{
    // 在 enable 前再次添加屏障，确保前面的初始化已完成
    __asm__ volatile("" : : : "memory");

    GDU_CTRL_REG = (en != 0u) ? GDU_CTRL_ENABLE_MASK : 0u;

    // Enable 后添加屏障，确保 enable 信号已发出
    __asm__ volatile("" : : : "memory");
}

U32 gdu_fb_get_status(void)
{
    return GDU_STATUS_REG;
}

void gdu_fb_wait_frame_done(void)
{
    (void)gdu_fb_wait_present_done_checked();
}

U32 gdu_fb_wait_frame_done_checked(void)
{
    return gdu_fb_wait_present_done_checked();
}

void gdu_fb_wait_present_done(void)
{
    (void)gdu_fb_wait_present_done_checked();
}

U32 gdu_fb_wait_present_done_checked(void)
{
    U32 status;

    do {
        status = gdu_fb_get_status();
    } while ((status & (GDU_STATUS_PRESENT_DONE | GDU_STATUS_UNDERFLOW | GDU_STATUS_AXI_ERROR)) == 0u);

    return status;
}

void gdu_fb_request_swap(U32 fb_base)
{
    GDU_FB_BASE_REG = fb_base;
    __asm__ volatile("" : : : "memory");
    GDU_SWAP_CTRL_REG = 1u;
    __asm__ volatile("" : : : "memory");
}

void gdu_fb_wait_swap_done(void)
{
    (void)gdu_fb_wait_swap_done_checked();
}

U32 gdu_fb_wait_swap_done_checked(void)
{
    U32 status;

    do {
        status = gdu_fb_get_status();
    } while ((status & (GDU_STATUS_SWAP_DONE | GDU_STATUS_UNDERFLOW | GDU_STATUS_AXI_ERROR)) == 0u);

    return status;
}

/* ---- Phase-4 performance interface ---- */

void gdu_perf_sample(gdu_perf_t *p)
{
    if (p == 0) {
        return;
    }
    p->rd_ar_txn           = GDU_PERF_RD_AR_TXN;
    p->rd_beat             = GDU_PERF_RD_BEAT;
    p->rd_wait             = GDU_PERF_RD_WAIT;
    p->arb_gru_grant       = GDU_PERF_ARB_GRU_GRANT;
    p->arb_gdu_grant       = GDU_PERF_ARB_GDU_GRANT;
    p->arb_gru_wait        = GDU_PERF_ARB_GRU_WAIT;
    p->arb_gdu_wait        = GDU_PERF_ARB_GDU_WAIT;
    p->arb_gru_max_wait    = GDU_PERF_ARB_GRU_MAXWAIT;
    p->arb_gdu_max_wait    = GDU_PERF_ARB_GDU_MAXWAIT;
    p->arb_qos_override    = GDU_PERF_ARB_QOS;
    p->arb_critical_override = GDU_PERF_ARB_CRITICAL;
    p->arb_starve          = GDU_PERF_ARB_STARVE;
    __asm__ volatile("" : : : "memory");
}

static void gdu_perf_put_u32(U32 v)
{
    char buf[11];
    int i;

    i = 10;
    buf[10] = '\0';
    if (v == 0u) {
        uart_puts_blocking("0");
        return;
    }
    while ((v != 0u) && (i > 0)) {
        i--;
        buf[i] = (char)('0' + (v % 10u));
        v /= 10u;
    }
    uart_puts_blocking(&buf[i]);
}

static void gdu_perf_line(const char *label, U32 val)
{
    uart_puts_blocking(label);
    uart_puts_blocking("=");
    gdu_perf_put_u32(val);
    uart_puts_blocking("\r\n");
}

void gdu_perf_print(const gdu_perf_t *p)
{
    if (p == 0) {
        return;
    }
    uart_puts_blocking("[GDU_PERF]\r\n");
    gdu_perf_line("  rd_ar_txn           ", p->rd_ar_txn);
    gdu_perf_line("  rd_beat             ", p->rd_beat);
    gdu_perf_line("  rd_wait             ", p->rd_wait);
    gdu_perf_line("  arb_gru_grant       ", p->arb_gru_grant);
    gdu_perf_line("  arb_gdu_grant       ", p->arb_gdu_grant);
    gdu_perf_line("  arb_gru_wait        ", p->arb_gru_wait);
    gdu_perf_line("  arb_gdu_wait        ", p->arb_gdu_wait);
    gdu_perf_line("  arb_gru_max_wait    ", p->arb_gru_max_wait);
    gdu_perf_line("  arb_gdu_max_wait    ", p->arb_gdu_max_wait);
    gdu_perf_line("  arb_qos_override    ", p->arb_qos_override);
    gdu_perf_line("  arb_critical_override", p->arb_critical_override);
    gdu_perf_line("  arb_starve          ", p->arb_starve);
}

