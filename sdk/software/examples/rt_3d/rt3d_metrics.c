#include "rt3d_metrics.h"

static rt3d_idle_metrics_t *g_idle_metrics;
static uint32_t g_background_units;
static uint32_t g_background_start;
static volatile uint32_t g_background_state = 0x13579bdfu;

static uint32_t elapsed(uint32_t start, uint32_t end)
{
    return end - start;
}

static void idle_account(rt3d_idle_metrics_t *m)
{
    uint32_t now, delta;
    if (m == 0 || !m->initialized) return;
    now = get_cpu_clock_count();
    delta = elapsed(m->last_cycle, now);
    m->idle_cycles += delta;
    m->last_cycle = now;
}

void rt3d_frame_begin(rt3d_frame_metrics_t *m)
{
    uint32_t i;
    if (m == 0) return;
    for (i = 0; i < RT3D_STAGE_COUNT; ++i) m->stage_cycles[i] = 0;
    m->active_cycles = 0;
    m->polling_cycles = 0;
    m->blocked_cycles = 0;
    m->wall_cycles = get_cpu_clock_count();
    m->frame_latency_ns = 0;
}

void rt3d_stage_begin(rt3d_frame_metrics_t *m, rt3d_stage_t stage)
{
    /* The timestamp is kept in the stage slot while it is active.  Callers
     * must finish a stage before beginning another one. */
    if (m == 0 || (unsigned)stage >= RT3D_STAGE_COUNT) return;
    m->stage_cycles[stage] = get_cpu_clock_count();
}

void rt3d_stage_end(rt3d_frame_metrics_t *m, rt3d_stage_t stage)
{
    uint32_t now, delta;
    if (m == 0 || (unsigned)stage >= RT3D_STAGE_COUNT) return;
    now = get_cpu_clock_count();
    delta = elapsed(m->stage_cycles[stage], now);
    m->stage_cycles[stage] = delta;
    m->active_cycles += delta;
}

void rt3d_polling_begin(rt3d_frame_metrics_t *m)
{
    rt3d_stage_begin(m, RT3D_STAGE_POLLING);
}

void rt3d_polling_end(rt3d_frame_metrics_t *m)
{
    uint32_t before;
    if (m == 0) return;
    before = m->active_cycles;
    rt3d_stage_end(m, RT3D_STAGE_POLLING);
    m->polling_cycles = m->stage_cycles[RT3D_STAGE_POLLING];
    m->active_cycles = before; /* polling is reported separately */
}

void rt3d_blocked_add(rt3d_frame_metrics_t *m, uint32_t cycles)
{
    if (m != 0) m->blocked_cycles += cycles;
}

void rt3d_frame_end(rt3d_frame_metrics_t *m)
{
    uint32_t cycles;
    if (m == 0) return;
    cycles = elapsed(m->wall_cycles, get_cpu_clock_count());
    m->wall_cycles = cycles;
    m->frame_latency_ns = (uint32_t)(((uint64_t)cycles * 1000000000ull) /
                                     (uint64_t)CORE_CLOCKS_PER_SEC);
}

void rt3d_idle_init(rt3d_idle_metrics_t *m)
{
    if (m == 0) return;
    m->idle_cycles = 0;
    m->sample_cycles = 0;
    m->sample_idle_cycles = 0;
    m->last_cycle = get_cpu_clock_count();
    m->sample_start = m->last_cycle;
    m->sample_idle_start = 0;
    m->initialized = 1;
    g_idle_metrics = m;
}

void rt3d_idle_hook(void)
{
    idle_account(g_idle_metrics);
}

void rt3d_idle_sample(rt3d_idle_metrics_t *m)
{
    uint32_t now;
    if (m == 0) return;
    /* Force a boundary even if the idle hook has not run since the last read. */
    idle_account(m);
    now = get_cpu_clock_count();
    m->sample_cycles = elapsed(m->sample_start, now);
    m->sample_idle_cycles = m->idle_cycles - m->sample_idle_start;
    m->sample_start = now;
    m->sample_idle_start = m->idle_cycles;
}

uint32_t rt3d_idle_rate_permille(const rt3d_idle_metrics_t *m)
{
    uint32_t total;
    if (m == 0 || !m->initialized) return 0;
    total = m->sample_cycles;
    if (total == 0) return 0;
    return (uint32_t)(((uint64_t)m->sample_idle_cycles * 1000ull) / total);
}

void rt3d_background_reset(void)
{
    g_background_units = 0;
    g_background_start = get_cpu_clock_count();
    g_background_state = 0x13579bdfu;
}

uint32_t rt3d_background_step(void)
{
    /* Fixed integer LFSR-like workload: same operation count in all modes. */
    uint32_t x = g_background_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    g_background_state = x;
    ++g_background_units;
    return x;
}

void rt3d_background_sample(rt3d_background_metrics_t *out)
{
    uint32_t now, cycles;
    if (out == 0) return;
    now = get_cpu_clock_count();
    cycles = elapsed(g_background_start, now);
    out->units = g_background_units;
    out->window_cycles = cycles;
    out->units_per_second = cycles == 0 ? 0 :
        (uint32_t)(((uint64_t)g_background_units * (uint64_t)CORE_CLOCKS_PER_SEC) /
                   (uint64_t)cycles);
}
