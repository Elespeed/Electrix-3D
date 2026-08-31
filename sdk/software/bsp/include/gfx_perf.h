#ifndef GFX_PERF_H
#define GFX_PERF_H

/*
 * gfx_perf — unified performance sampling/print for the graphics subsystem.
 *
 * Phase-4 deliverable (doc/05_phase4_runtime_buffering_and_metrics.md §4): a
 * single place for 3D demos / firmware to read every graphics performance
 * counter without dropping into a waveform or testbench.  All counters are
 * cumulative since hard reset; sample twice and diff to measure a window.
 *
 * gru_perf_t  (gru.h)      — GRU render/blit write path (WCB + blit engine).
 * gdu_perf_t  (gdu_fb.h)   — GDU framebuffer reader + GRU↔GDU DDR arbiter.
 */

#include "common_func.h"
#include "gru.h"
#include "gdu_fb.h"

typedef struct {
    gru_perf_t gru;
    gdu_perf_t gdu;
} gfx_perf_t;

/* Read every GRU + GDU perf counter into *p in one consistent pass. */
void gfx_perf_sample_all(gfx_perf_t *p);

/* Print every counter (GRU then GDU) over UART, labelled. */
void gfx_perf_print_all(const gfx_perf_t *p);

#endif /* GFX_PERF_H */
