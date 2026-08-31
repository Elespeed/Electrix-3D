// Verilator custom main() with optional VCD tracing + time-windowed capture.
//
// WHY THIS EXISTS: Verilator 5.020's auto-generated --binary main() enables
// traceEverOn() but never opens a VCD file, so `--binary --trace` produces NO
// waveform. Getting a VCD requires a custom main that opens a VerilatedVcdC,
// opens a file, and dump()s each time step. verilator_build.sh sed-substitutes
// the real top-module name for __VL_TOP__ and builds this with --cc --exe --build
// for VCD runs only (the functional flow keeps Verilator's --binary main).
//
// RUNTIME env:
//   VLT_TRACE_FILE     trace output path (set by verilator_build.sh). If unset,
//                      no trace is opened.
//   VLT_TRACE_START_PS lower sim-time bound (ps; TB is 1ns/1ps) — only dump at/after.
//   VLT_TRACE_END_PS   upper sim-time bound (ps) — only dump at/before. 0/unset = no cap.
// Windowed dumping implements task §11.3 for real (Verilator's stock main can't
// crop), keeping lite VCDs small. Trace DEPTH is compile-time (--trace-depth),
// so a cfg change still re-verilates (.trace_key); a path/window change does not.
#include "verilated.h"
#include "V__VL_TOP__.h"
#include "verilated_vcd_c.h"

#include <cstdlib>
#include <memory>

static bool env_u64(const char* name, uint64_t& out) {
    const char* v = std::getenv(name);
    if (!v || !v[0]) return false;
    out = std::strtoull(v, nullptr, 10);
    return true;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> ctxp{new VerilatedContext};
    ctxp->commandArgs(argc, argv);
    ctxp->traceEverOn(true);
    const std::unique_ptr<V__VL_TOP__> topp{new V__VL_TOP__{ctxp.get()}};

    VerilatedVcdC* tfp = nullptr;
    const char* tfile = std::getenv("VLT_TRACE_FILE");
    if (tfile && tfile[0]) {
        tfp = new VerilatedVcdC;
        topp->trace(tfp, 99);  // depth capped by the compile-time --trace-depth
        tfp->open(tfile);
    }

    uint64_t start_ps = 0, end_ps = 0;
    bool have_start = env_u64("VLT_TRACE_START_PS", start_ps);
    bool have_end = env_u64("VLT_TRACE_END_PS", end_ps);

    while (!ctxp->gotFinish()) {
        topp->eval();
        if (!topp->eventsPending()) break;
        ctxp->time(topp->nextTimeSlot());
        if (tfp) {
            uint64_t t = ctxp->time();
            bool in_window = (!have_start || t >= start_ps) && (!have_end || t <= end_ps);
            if (in_window) tfp->dump(t);
        }
    }

    if (tfp) {
        tfp->close();
        delete tfp;
    }
    topp->final();
    return 0;
}
