#ifndef RT3D_METRICS_H
#define RT3D_METRICS_H

/*
 * Measurement-only support for the rt_3d benchmark (T06/T07).
 *
 * The API deliberately has no UART, allocation, or scheduler side effects in
 * the timing functions.  Counters are the LoongArch CPU counter returned by
 * get_cpu_clock_count() and wrap-safe unsigned subtraction is used.
 */
#include <stdint.h>
#include "confreg_time.h"

#ifndef RT_THREAD_PRIORITY_MAX
#define RT_THREAD_PRIORITY_MAX 32
#endif

#define RT3D_STAGE_COUNT 5u
#define RT3D_BACKGROUND_PRIORITY  (RT_THREAD_PRIORITY_MAX - 2)

typedef enum {
    RT3D_STAGE_TRANSFORM = 0,
    RT3D_STAGE_TRIANGLE_CULL,
    RT3D_STAGE_PAINTER_SORT,
    RT3D_STAGE_COMMAND_SUBMIT,
    RT3D_STAGE_POLLING
} rt3d_stage_t;

typedef struct {
    uint32_t stage_cycles[RT3D_STAGE_COUNT];
    uint32_t active_cycles;
    uint32_t polling_cycles;
    uint32_t blocked_cycles;
    uint32_t wall_cycles;
    uint32_t frame_latency_ns;
} rt3d_frame_metrics_t;

typedef struct {
    volatile uint32_t idle_cycles;
    volatile uint32_t sample_cycles;       /* total cycles in latest window */
    volatile uint32_t sample_idle_cycles; /* idle cycles in latest window */
    volatile uint32_t last_cycle;
    volatile uint32_t sample_start;
    volatile uint32_t sample_idle_start;
    volatile uint32_t initialized;
} rt3d_idle_metrics_t;

typedef struct {
    uint32_t units;
    uint32_t window_cycles;
    uint32_t units_per_second;
} rt3d_background_metrics_t;

/* Frame/stage timing.  begin/end calls may be nested only as documented:
 * one frame and one active stage at a time. */
void rt3d_frame_begin(rt3d_frame_metrics_t *m);
void rt3d_stage_begin(rt3d_frame_metrics_t *m, rt3d_stage_t stage);
void rt3d_stage_end(rt3d_frame_metrics_t *m, rt3d_stage_t stage);
void rt3d_polling_begin(rt3d_frame_metrics_t *m);
void rt3d_polling_end(rt3d_frame_metrics_t *m);
void rt3d_blocked_add(rt3d_frame_metrics_t *m, uint32_t cycles);
void rt3d_frame_end(rt3d_frame_metrics_t *m);

/* RT-Thread idle hook support.  Register rt3d_idle_hook with
 * rt_thread_idle_sethook() once during benchmark setup. */
void rt3d_idle_init(rt3d_idle_metrics_t *m);
void rt3d_idle_hook(void);
void rt3d_idle_sample(rt3d_idle_metrics_t *m);
uint32_t rt3d_idle_rate_permille(const rt3d_idle_metrics_t *m);

/* Deterministic, mode-independent background work.  A unit is intentionally
 * small and allocation-free, so throughput can be sampled over a fixed
 * counter window. */
void rt3d_background_reset(void);
uint32_t rt3d_background_step(void);
void rt3d_background_sample(rt3d_background_metrics_t *out);

#endif /* RT3D_METRICS_H */
