#ifndef GDU_FB_H
#define GDU_FB_H

#include "common_func.h"

#define GDU_BASE_ADDR            0xbf100000u
#define GDU_CTRL_ENABLE_MASK     0x1u

#define GDU_STATUS_UNDERFLOW     0x1u
#define GDU_STATUS_PRESENT_DONE  0x2u
#define GDU_STATUS_AXI_ERROR     0x4u
#define GDU_STATUS_SWAP_DONE     0x8u
#define GDU_STATUS_SWAP_PENDING  0x10u

#define GDU_STATUS_FRAME_DONE    GDU_STATUS_PRESENT_DONE

#define GDU_PIXEL_FORMAT_RGB565  1u

/* Phase-4: GDU performance counter MMIO window (read-only, cumulative since
 * hard reset).  Reader counters come from fb_axi_reader; arbiter counters from
 * ddr_axi_arbiter_2m1s (GRU↔GDU DDR read arbitration). */
#define GDU_REG_PERF_RD_AR_TXN_OFS       0x20u
#define GDU_REG_PERF_RD_BEAT_OFS         0x24u
#define GDU_REG_PERF_RD_WAIT_OFS         0x28u
#define GDU_REG_PERF_ARB_GRU_GRANT_OFS   0x2cu
#define GDU_REG_PERF_ARB_GDU_GRANT_OFS   0x30u
#define GDU_REG_PERF_ARB_GRU_WAIT_OFS    0x34u
#define GDU_REG_PERF_ARB_GDU_WAIT_OFS    0x38u
#define GDU_REG_PERF_ARB_GRU_MAXWAIT_OFS 0x3cu
#define GDU_REG_PERF_ARB_GDU_MAXWAIT_OFS 0x40u
#define GDU_REG_PERF_ARB_QOS_OFS         0x44u
#define GDU_REG_PERF_ARB_CRITICAL_OFS    0x48u
#define GDU_REG_PERF_ARB_STARVE_OFS      0x4cu

typedef struct {
    U32 rd_ar_txn;        /* fb reader AXI AR transactions */
    U32 rd_beat;          /* fb reader 128-bit read beats */
    U32 rd_wait;          /* fb reader cycles AR valid but not accepted */
    U32 arb_gru_grant;    /* DDR read grants to GRU */
    U32 arb_gdu_grant;    /* DDR read grants to GDU */
    U32 arb_gru_wait;     /* GRU read wait cycles */
    U32 arb_gdu_wait;     /* GDU read wait cycles */
    U32 arb_gru_max_wait; /* worst GRU read wait streak */
    U32 arb_gdu_max_wait; /* worst GDU read wait streak (= display starvation risk) */
    U32 arb_qos_override; /* low-water QoS overrides in GDU's favour */
    U32 arb_critical_override; /* critical-water overrides in GDU's favour */
    U32 arb_starve;       /* GRU starvation-relief grants */
} gdu_perf_t;

typedef struct {
    U32 fb_base;
    U16 width;
    U16 height;
    U32 stride_bytes;
    U8 pixel_format;
} gdu_fb_cfg_t;

void gdu_fb_init(const gdu_fb_cfg_t *cfg);
void gdu_fb_enable(U8 en);
U32 gdu_fb_get_status(void);
void gdu_fb_wait_frame_done(void);
U32 gdu_fb_wait_frame_done_checked(void);
void gdu_fb_wait_present_done(void);
U32 gdu_fb_wait_present_done_checked(void);
void gdu_fb_request_swap(U32 fb_base);
void gdu_fb_wait_swap_done(void);
U32 gdu_fb_wait_swap_done_checked(void);

/* Phase-4 performance interface. */
void gdu_perf_sample(gdu_perf_t *p);
void gdu_perf_print(const gdu_perf_t *p);

#endif /* GDU_FB_H */
