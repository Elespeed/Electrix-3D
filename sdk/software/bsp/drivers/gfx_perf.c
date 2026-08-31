#include "gfx_perf.h"

void gfx_perf_sample_all(gfx_perf_t *p)
{
    if (p == 0) {
        return;
    }
    /* GDU first: its arbiter counters are the most time-sensitive (display
     * starvation).  Then GRU.  Both are cumulative; ordering only affects
     * sub-cycle skew, irrelevant at firmware sampling granularity. */
    gdu_perf_sample(&p->gdu);
    gru_perf_sample(&p->gru);
}

void gfx_perf_print_all(const gfx_perf_t *p)
{
    if (p == 0) {
        return;
    }
    gru_perf_print(&p->gru);
    gdu_perf_print(&p->gdu);
}
