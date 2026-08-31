#!/usr/bin/env bash
# verilator_build.sh — WSL-side driver for the Verilator flow.
#
# Invoked by fpga/verilator/Makefile with cwd = the WSL path of fpga/verilator:
#   wsl --cd <win-verilator-root> bash scripts/verilator_build.sh <mode> <tb> [jobs] [extra verilator args...]
#
# VCD settings are read from the environment (Make exports VCD/VCD_CFG/VCD_OUT_REL
# and lists them in WSLENV so they actually cross into WSL):
#   VCD=1 VCD_CFG=lite VCD_OUT_REL=vcd/<tb>/lite.vcd
#
# All compile + simulation output is appended to logs/transcript_<tb>.log so the
# Windows-side build_result_json.py / transcript_summarize.py can classify it
# without the agent ever loading the raw log. Exit-code markers are written
# explicitly into the transcript (WSL's own exit code is also propagated).
#
# task book: doc/Verilator迁移与批量调试任务书.md §5, §7, §8, §11.
set -u

MODE="${1:?usage: verilator_build.sh <lint|compile|run> <tb> [jobs] [extra verilator args...]}"
TB="${2:?missing tb}"
JOBS="${3:-8}"
shift 3 2>/dev/null || shift "$#"
EXTRA=("$@")

# The MCU-equivalence examples intentionally use their own generated ROM image.
# Keep the historical Blade GUI tests bound to the shared SDK image.
case "$TB" in
    blade_mcu_2x2_small_tb)
        EXTRA+=("-DRTL_SRAM_INIT_FILE=\"../../sdk/software/examples/blade2x2_mcu_small/obj/axi_ram.mif\"")
        ;;
    blade_mcu_2x2_large_tb)
        EXTRA+=("-DRTL_SRAM_INIT_FILE=\"../../sdk/software/examples/blade2x2_mcu/obj/axi_ram.mif\"")
        ;;
esac

VERILATOR="${VERILATOR:-verilator}"
MDIR="${MDIR:-build}"
LOG_DIR="${LOG_DIR:-logs}"
mkdir -p "$MDIR" "$LOG_DIR"

# ---- VCD / trace config -----------------------------------------------------
# Verilator tracing is a COMPILE-TIME choice: VCD=1 verilate with --trace
# --trace-depth N. cfg -> depth (task §11.2): depth-1 keeps the TB's top-level
# gru_s_*/gdu_s_* AXI handshake signals (enough for contention/backpressure)
# while staying small.
VCD="${VCD:-0}"
VCD_CFG="${VCD_CFG:-lite}"
VCD_OUT_REL="${VCD_OUT_REL:-vcd/${TB}/${VCD_CFG}.vcd}"

case "$VCD_CFG" in
    lite)  TRACE_DEPTH=(--trace-depth 1) ;;
    debug) TRACE_DEPTH=(--trace-depth 3) ;;
    full)  TRACE_DEPTH=() ;;           # no depth limit
    *)     TRACE_DEPTH=(--trace-depth 1) ;;
esac

TRACE_FLAGS=()
if [ "$VCD" = "1" ]; then
    mkdir -p "$(dirname "$VCD_OUT_REL")"
    TRACE_FLAGS=(--trace "${TRACE_DEPTH[@]}")
fi

TRANSCRIPT="$LOG_DIR/transcript_${TB}.log"
FILELIST="filelist/tb_${TB}.f"
BIN="$MDIR/V${TB}"
LIVE_LOG="${LIVE_LOG:-1}"
TRACE_KEY_FILE="$MDIR/.trace_key"
MAIN_TEMPLATE="scripts/verilator_main.cpp"
MAIN_CPP="$MDIR/vlt_main_${TB}.cpp"

# Stable key capturing the exact trace/build intent; reused binaries must match
# it or we re-verilate (a binary compiled without --trace cannot emit a VCD, and
# a --binary build cannot serve a VCD run that needs the custom main). Including
# the trace flags + custom-main hash also invalidates reuse across method/main
# changes.
MAIN_HASH=""
if [ "$VCD" = "1" ] && [ -f "$MAIN_TEMPLATE" ]; then
    MAIN_HASH="$(md5sum "$MAIN_TEMPLATE" 2>/dev/null | cut -c1-8)"
fi
# EXTRA carries PERF_G_FLAGS (-G overrides) and VERILATOR_EXTRA; since -G params
# are baked in at elaboration, a perf↔functional switch must invalidate reuse.
TRACE_KEY="vcd=${VCD}:cfg=${VCD_CFG}:out=${VCD_OUT_REL}:flags=${TRACE_FLAGS[*]:-none}:main=${MAIN_HASH}:extra=${EXTRA[*]:-none}"

# --timing is mandatory: the TB uses #delay / @(posedge) / time params / watchdog
# (task §7.1). -Wall for visibility; -Werror is intentionally NOT set and
# -Wno-fatal keeps benign warnings (UNUSEDSIGNAL/WIDTHEXPAND/BLKSEQ ...) from
# failing the exit — they are still reported in the transcript for classification
# (task §5.3: "先分类 warning，避免无关告警把迁移卡死").
TIMING_FLAGS=()
if "$VERILATOR" --help 2>/dev/null | grep -q -- "--timing"; then
    TIMING_FLAGS=(--timing)
fi
COMMON=(-sv "${TIMING_FLAGS[@]}" -Wall -Wno-fatal --top-module "$TB" -f "$FILELIST" +define+VERILATOR_BUILD -j "$JOBS" --Mdir "$MDIR")

: > "$TRANSCRIPT"
{
    echo "=============================================================="
    echo "Verilator build driver"
    echo "  mode          = $MODE"
    echo "  tb            = $TB"
    echo "  jobs          = $JOBS"
    echo "  verilator     = $("$VERILATOR" --version)"
    echo "  filelist      = $FILELIST"
    echo "  mdir          = $MDIR"
    echo "  binary        = $BIN"
    echo "  transcript    = $TRANSCRIPT"
    echo "  vcd           = $VCD (cfg=$VCD_CFG out=$VCD_OUT_REL)"
    echo "  timing_flags  = ${TIMING_FLAGS[*]:-none}"
    echo "  trace_flags   = ${TRACE_FLAGS[*]:-none}"
    echo "  extra         = ${EXTRA[*]:-}"
    echo "=============================================================="
} >> "$TRANSCRIPT" 2>&1

# Preserve the transcript as the machine-readable source of truth while also
# making $display, $fatal, and Verilator diagnostics visible to an interactive
# caller.  PIPESTATUS preserves the simulator/compiler status rather than tee's.
run_logged() {
    if [ "$LIVE_LOG" = "1" ]; then
        "$@" 2>&1 | tee -a "$TRANSCRIPT"
        return "${PIPESTATUS[0]}"
    fi
    "$@" >> "$TRANSCRIPT" 2>&1
}

if [ ! -f "$FILELIST" ]; then
    echo "%Error: filelist not found: $FILELIST" >> "$TRANSCRIPT"
    echo "VERILATOR_COMPILE_RC=99" >> "$TRANSCRIPT"
    echo "VERILATOR_RUN_RC=not_run_no_filelist" >> "$TRANSCRIPT"
    exit 99
fi

trace_key_matches() {
    [ -f "$TRACE_KEY_FILE" ] && [ "$(cat "$TRACE_KEY_FILE" 2>/dev/null)" = "$TRACE_KEY" ]
}

# `run-batch` is the normal user entry point, so it must never silently run a
# stale elaborated binary.  Keep the fast path when inputs are unchanged, but
# rebuild whenever a relevant HDL/TB/filelist/helper or the RT-Thread ROM image
# is newer.  Limit the sim tree to source extensions: PPM frame dumps must not
# themselves trigger a rebuild.
sources_newer_than_binary() {
    local newest
    [ ! -x "$BIN" ] && return 0
    newest=$(
        {
            find filelist scripts -type f -newer "$BIN" -print
            find ../../rtl -type f \( -name '*.v' -o -name '*.sv' -o -name '*.vh' -o -name '*.svh' -o -name '*.h' \) -newer "$BIN" -print
            find ../../sim -type f \( -name '*.v' -o -name '*.sv' -o -name '*.vh' -o -name '*.svh' -o -name '*.h' \) -newer "$BIN" -print
            find ../../sdk/software/examples/RTThread_Nano/obj -maxdepth 1 -type f \( -name 'rom.vlog' -o -name 'axi_ram.coe' \) -newer "$BIN" -print
            find ../../sdk/software/examples/blade2x2/obj -maxdepth 1 -type f \( -name 'rom.vlog' -o -name 'axi_ram.coe' \) -newer "$BIN" -print
            find ../../sdk/software/examples/blade2x2_mcu/obj -maxdepth 1 -type f \( -name 'rom.vlog' -o -name 'axi_ram.coe' -o -name 'axi_ram.mif' \) -newer "$BIN" -print
            find ../../sdk/software/examples/blade2x2_mcu_small/obj -maxdepth 1 -type f \( -name 'rom.vlog' -o -name 'axi_ram.coe' -o -name 'axi_ram.mif' \) -newer "$BIN" -print
        } 2>/dev/null | head -n 1
    )
    [ -n "$newest" ]
}

# Convert a Verilog time string ("70us") to integer ps (the VCD timescale is 1ps;
# the TB is `timescale 1ns/1ps). Consumed by the custom main's windowed dumping
# (VLT_TRACE_START_PS / VLT_TRACE_END_PS) to implement task §11.3 window crop.
time_to_ps() {
    case "$1" in
        *fs) echo $(( ${1%fs} / 1000 )) ;;
        *ps) echo $(( ${1%ps} )) ;;
        *ns) echo $(( ${1%ns} * 1000 )) ;;
        *us) echo $(( ${1%us} * 1000000 )) ;;
        *ms) echo $(( ${1%ms} * 1000000000 )) ;;
        *s)  echo $(( ${1%s} * 1000000000000 )) ;;
        *)   echo "$1" ;;
    esac
}

# Verilate + C++ build. Functional (VCD=0) uses Verilator's --binary auto-main.
# VCD=1 cannot use --binary: its auto-main never opens a VCD, so we verilate with
# --cc --exe --build + a per-build custom main (verilator_main.cpp with the top
# name substituted) that opens/dumps the trace at runtime via VLT_TRACE_FILE.
do_verilate() {
    if [ "$VCD" = "1" ]; then
        if [ ! -f "$MAIN_TEMPLATE" ]; then
            echo "%Error: VCD custom main template missing: $MAIN_TEMPLATE" >> "$TRANSCRIPT"
            return 99
        fi
        sed "s/__VL_TOP__/${TB}/g" "$MAIN_TEMPLATE" > "$MAIN_CPP"
        echo "=== stage: verilator --cc --exe --build (trace) main=$MAIN_CPP trace_key=$TRACE_KEY ===" >> "$TRANSCRIPT"
        # No -o: with --cc --exe --build the default output is Mdir/V<top> (= $BIN);
        # passing -o build/V<top> would double-nest under `make -C build` and fail.
        run_logged "$VERILATOR" --cc --exe --build "${COMMON[@]}" "${TRACE_FLAGS[@]}" "$MAIN_CPP" "${EXTRA[@]}"
    else
        echo "=== stage: verilator --binary (verilate + C++ build) trace_key=$TRACE_KEY ===" >> "$TRANSCRIPT"
        run_logged "$VERILATOR" --binary "${COMMON[@]}" "${EXTRA[@]}"
    fi
}

# ---- lint ------------------------------------------------------------------
if [ "$MODE" = "lint" ]; then
    echo "=== stage: verilator --lint-only ===" >> "$TRANSCRIPT"
    run_logged "$VERILATOR" --lint-only "${COMMON[@]}" "${EXTRA[@]}"
    rc=$?
    echo "VERILATOR_LINT_RC=$rc" >> "$TRANSCRIPT"
    echo "[verilator_build.sh] lint rc=$rc  transcript=$TRANSCRIPT"
    exit "$rc"
fi

# ---- compile ---------------------------------------------------------------
if [ "$MODE" != "compile" ] && [ "$MODE" != "run" ]; then
    echo "%Error: unknown mode '$MODE' (expected lint|compile|run)" >> "$TRANSCRIPT"
    exit 2
fi

# Reuse only if both the elaboration intent and every relevant input are
# unchanged.  Thus the usual `make ... run-batch` command automatically
# recompiles after RTL/TB/filelist/C-image edits.
COMPILE_RC=0
if [ "$MODE" = "run" ] && [ -x "$BIN" ] && trace_key_matches && ! sources_newer_than_binary; then
    echo "=== stage: reuse existing binary ($BIN) trace_key=$TRACE_KEY ===" >> "$TRANSCRIPT"
    echo "[verilator_build.sh] reusing up-to-date binary $BIN"
else
    if [ "$MODE" = "run" ] && [ -x "$BIN" ] && trace_key_matches; then
        echo "=== stage: rebuild because a source input is newer than $BIN ===" >> "$TRANSCRIPT"
        echo "[verilator_build.sh] source changed; rebuilding $BIN"
    fi
    do_verilate
    COMPILE_RC=$?
    echo "VERILATOR_COMPILE_RC=$COMPILE_RC" >> "$TRANSCRIPT"
    echo "[verilator_build.sh] compile rc=$COMPILE_RC"
    # Record the trace config only on a successful verilation so a half-built
    # binary is never mistaken for matching the requested trace intent.
    if [ "$COMPILE_RC" -eq 0 ]; then
        printf '%s' "$TRACE_KEY" > "$TRACE_KEY_FILE"
    fi
fi

if [ "$MODE" = "compile" ]; then
    echo "VERILATOR_RUN_RC=skipped_compile_only" >> "$TRANSCRIPT"
    [ "$COMPILE_RC" -eq 0 ] && [ -x "$BIN" ] && echo "[verilator_build.sh] binary ok: $BIN"
    exit "$COMPILE_RC"
fi

# compile must succeed before we can run.
if [ "$COMPILE_RC" -ne 0 ] || [ ! -x "$BIN" ]; then
    echo "%Error: compile failed (rc=$COMPILE_RC) or binary missing ($BIN); skipping run" >> "$TRANSCRIPT"
    echo "VERILATOR_RUN_RC=not_run_compile_failed" >> "$TRANSCRIPT"
    exit "$COMPILE_RC"
fi

# ---- run -------------------------------------------------------------------
echo "=== stage: simulate ($BIN) ===" >> "$TRANSCRIPT"
# This script runs from fpga/verilator, so ../../sim/frame_output reaches the
# repository-owned frame directory on every workstation.  An explicit caller
# supplied +DVI_OUT_DIR remains authoritative.
RUN_ARGS_EFFECTIVE="${RUN_ARGS:-}"
if [[ "$RUN_ARGS_EFFECTIVE" != *"+DVI_OUT_DIR="* ]]; then
    DVI_OUT_DIR_EFFECTIVE="${DVI_OUT_DIR_REL:-../../sim/frame_output}"
    RUN_ARGS_EFFECTIVE="${RUN_ARGS_EFFECTIVE} +DVI_OUT_DIR=${DVI_OUT_DIR_EFFECTIVE}"
else
    DVI_OUT_DIR_EFFECTIVE="caller-supplied in RUN_ARGS"
fi
echo "  dvi_out_dir   = ${DVI_OUT_DIR_EFFECTIVE}" >> "$TRANSCRIPT"
# For VCD runs the custom main reads VLT_TRACE_FILE at runtime and writes the
# canonical path directly; VLT_TRACE_START_PS/END_PS crop to a window (task §11.3).
if [ "$VCD" = "1" ]; then
    mkdir -p "$(dirname "$VCD_OUT_REL")"
    run_env=(env "VLT_TRACE_FILE=$VCD_OUT_REL")
    start_ps=""; end_ps=""
    if [ -n "${VCD_START:-}" ]; then start_ps="$(time_to_ps "$VCD_START")"; run_env+=("VLT_TRACE_START_PS=$start_ps"); fi
    if [ -n "${VCD_END:-}" ];   then end_ps="$(time_to_ps "$VCD_END")";   run_env+=("VLT_TRACE_END_PS=$end_ps"); fi
    {
        echo "  vcd_window    = start=${VCD_START:-none} end=${VCD_END:-none}"
        echo "  vcd_window_ps = start=${start_ps:-none} end=${end_ps:-none}"
    } >> "$TRANSCRIPT"
    run_logged "${run_env[@]}" "$BIN" $RUN_ARGS_EFFECTIVE
else
    run_logged "$BIN" $RUN_ARGS_EFFECTIVE
fi
RUN_RC=$?
echo "VERILATOR_RUN_RC=$RUN_RC" >> "$TRANSCRIPT"
echo "[verilator_build.sh] run rc=$RUN_RC  transcript=$TRANSCRIPT"

if [ "$VCD" = "1" ]; then
    if [ -s "$VCD_OUT_REL" ]; then
        echo "VERILATOR_VCD_PATH=$VCD_OUT_REL" >> "$TRANSCRIPT"
    else
        echo "[verilator_build.sh] %Warning: VCD=1 but no .vcd produced (expected $VCD_OUT_REL)" >> "$TRANSCRIPT"
    fi
fi

exit "$RUN_RC"
