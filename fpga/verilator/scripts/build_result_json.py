#!/usr/bin/env python
#Build a structured result JSON from a Verilator transcript + run metadata.
#
# Verilator-flavoured counterpart of fpga/modelsim/scripts/build_result_json.py.
# Reads the transcript written by verilator_build.sh, classifies compile vs run
# errors, PASS/FAIL markers, $fatal/timeout, contention stats and framebuffer
# mismatches, and emits the schema from task book §9.
#
# Pass/fail precedence (task §9): compile fail -> error; else $fatal / explicit
# FAIL / non-clean exit -> fail; else explicit PASS -> pass; else unknown.
# Never judges PASS from exit code 0 alone.
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path


SCHEMA_VERSION = 1

# Verilator diagnostic prefixes.
VLT_ERROR_RE = re.compile(r"%Error\b")
VLT_WARNING_RE = re.compile(r"%Warning\b")
# C++ (g++) build errors from the --binary link/compile stage.
CPP_ERROR_RE = re.compile(r":\s*(?:fatal )?error:", re.IGNORECASE)
CPP_LINK_RE = re.compile(r"undefined reference|collect2: error|ld returned", re.IGNORECASE)
# Runtime / testbench failure signals.  A %Fatal line carries the actual
# assertion text (e.g. a pixel mismatch); Verilator then echoes a generic
# "%Error ... Verilog $stop" that says nothing on its own.
FATAL_MSG_RE = re.compile(r"%Fatal\b[^\r\n]*")
FATAL_RE = re.compile(r"\$fatal|\bfatal\b", re.IGNORECASE)
TIMEOUT_RE = re.compile(r"timeout after", re.IGNORECASE)
FB_MISMATCH_RE = re.compile(r"\[FB_MEM_MISMATCH\]|\[FRAME_MISMATCH\]")
# PASS / FAIL word markers.
PASS_RE = re.compile(r"\bPASS\b")
FAIL_RE = re.compile(r"\bFAIL\b")
# Contention TB scenario stats lines.
CONT_STATS_RE = re.compile(r"\[GRU_GDU_CONT_TB\]\[STATS\]\s+(?P<key>[A-Za-z0-9_]+)=(?P<value>.+)")
# Checkpoint lines: "[GRU_GDU_CONT_TB] <text>" but NOT tagged [STATS]/[PERF]/...
CHECKPOINT_RE = re.compile(r"\[GRU_GDU_CONT_TB\]\s+(?P<cp>[A-Za-z][^\[\r\n]*)$")
OS_GDU_DIAG_RE = re.compile(r"\[(?P<tb>[A-Za-z0-9_]+)\]\[GDU_DIAG\]\[(?P<cp>[^\]]+)\]")
# Exit-code markers written by verilator_build.sh.
COMPILE_RC_RE = re.compile(r"VERILATOR_COMPILE_RC=(\S+)")
RUN_RC_RE = re.compile(r"VERILATOR_RUN_RC=(\S+)")
LINT_RC_RE = re.compile(r"VERILATOR_LINT_RC=(\S+)")
SIM_STAGE_RE = re.compile(r"=== stage: simulate")
COMPILE_STAGE_RE = re.compile(r"=== stage: verilator --binary")

# Known-noise Verilator warnings to bucket separately (do not fail the run).
KNOWN_NOISE = {
    "unused_reset": re.compile(r"%Warning-UNUSED.*reset|UNUSEDPARAM|UNDRIVEN|UNUSED", re.IGNORECASE),
    "width": re.compile(r"%Warning-WIDTH", re.IGNORECASE),
    "casex": re.compile(r"%Warning-CASEX|%Warning-CASEINCOMPLETE", re.IGNORECASE),
    "blksync": re.compile(r"%Warning-BLKSYNC|%Warning-BLKANDNBLK", re.IGNORECASE),
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Build a Verilator result JSON from the transcript.")
    p.add_argument("--transcript", required=True)
    p.add_argument("--result", required=True)
    p.add_argument("--tb", required=True)
    p.add_argument("--exit-code", default="0", help="propagated simulator/lint exit code")
    p.add_argument("--mode", default="run", choices=["lint", "compile", "run"])
    p.add_argument("--vcd-path", default="")
    p.add_argument("--selected-cfg", default="")
    p.add_argument("--capture-mode", default="disabled")
    p.add_argument("--phase", default="")
    p.add_argument("--build-dir", default="")
    p.add_argument("--simulator-version", default="")
    return p.parse_args()


def parse_scalar(value: str) -> object:
    text = value.strip()
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return text


def parse_contention_stats(lines: list[str]) -> list[dict[str, object]]:
    scenarios: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for raw in lines:
        m = CONT_STATS_RE.search(raw.strip())
        if not m:
            continue
        key, value = m.group("key"), parse_scalar(m.group("value"))
        if key == "scenario":
            current = {"scenario": value}
            scenarios.append(current)
        elif current is not None:
            current[key] = value
    return scenarios


def classify(line: str) -> str | None:
    if FATAL_MSG_RE.search(line):
        return "fatal_marker"
    if VLT_ERROR_RE.search(line) or CPP_ERROR_RE.search(line) or CPP_LINK_RE.search(line):
        return "error_marker"
    if VLT_WARNING_RE.search(line):
        return "warning"
    if FB_MISMATCH_RE.search(line):
        return "fail_marker"
    if TIMEOUT_RE.search(line):
        return "fatal_marker"
    if FAIL_RE.search(line):
        return "fail_marker"
    if PASS_RE.search(line):
        return "pass_marker"
    return None


def known_noise_bucket(line: str) -> str | None:
    for name, pat in KNOWN_NOISE.items():
        if pat.search(line):
            return name
    return None


def main() -> None:
    args = parse_args()
    transcript = Path(args.transcript)
    result_path = Path(args.result)

    lines: list[str] = []
    text_all = ""
    if transcript.exists():
        text_all = transcript.read_text(encoding="utf-8", errors="replace").replace("\x00", "")
        lines = text_all.splitlines()

    # Stage boundaries + explicit RC markers from the driver script.
    compile_rc = None
    run_rc = None
    in_compile = False
    in_run = False
    for ln in lines:
        if COMPILE_STAGE_RE.search(ln):
            in_compile, in_run = True, False
        elif SIM_STAGE_RE.search(ln):
            in_compile, in_run = False, True
        m = COMPILE_RC_RE.search(ln)
        if m:
            try:
                compile_rc = int(m.group(1))
            except ValueError:
                compile_rc = None
        m = RUN_RC_RE.search(ln)
        if m:
            tok = m.group(1)
            run_rc = 0 if tok in {"0"} else (None if tok.startswith("not_run") or tok == "skipped_compile_only" else (int(tok) if tok.lstrip("-").isdigit() else None))

    try:
        exit_code = int(args.exit_code)
    except ValueError:
        exit_code = -1

    compile_ok = (compile_rc == 0) if compile_rc is not None else (exit_code == 0 and args.mode != "lint")
    # "load" in Verilator = the simulated binary actually started (run stage reached).
    load_ok = run_rc is not None and args.mode == "run"
    run_ok = (run_rc == 0) if run_rc is not None else (compile_ok and args.mode != "run")

    counts = {"error_marker": 0, "warning": 0, "pass_marker": 0, "fail_marker": 0, "fatal_marker": 0}
    known_noise_counts: dict[str, int] = {}
    samples: dict[str, list[str]] = {k: [] for k in counts}
    checkpoint_seq: list[str] = []
    fatal_signals = 0
    fb_mismatch_count = 0
    fatal_messages: list[str] = []

    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        cm = CHECKPOINT_RE.search(line)
        if cm:
            checkpoint_seq.append(cm.group("cp").strip())
        cm = OS_GDU_DIAG_RE.search(line)
        if cm:
            checkpoint_seq.append(f"{cm.group('tb')}:GDU_DIAG:{cm.group('cp')}")
        if FB_MISMATCH_RE.search(line):
            fb_mismatch_count += 1
        if FATAL_RE.search(line) and "[GRU_GDU_CONT_TB]" in line:
            fatal_signals += 1
        fm = FATAL_MSG_RE.search(line)
        if fm:
            fatal_messages.append(fm.group(0))

        bucket = known_noise_bucket(line)
        if bucket:
            known_noise_counts[bucket] = known_noise_counts.get(bucket, 0) + 1
            continue
        kind = classify(line)
        if not kind:
            continue
        counts[kind] += 1
        if len(samples[kind]) < 8:
            samples[kind].append(line)

    last_checkpoint = checkpoint_seq[-1] if checkpoint_seq else None
    final_marker = None
    for cp in checkpoint_seq:
        if cp.strip().upper() in {"PASS", "FAIL"} or cp.strip().endswith("PASS") or cp.strip().endswith("FAIL"):
            final_marker = cp.strip()

    explicit_fail = counts["fail_marker"] > 0 or counts["fatal_marker"] > 0 or fatal_signals > 0
    explicit_pass = counts["pass_marker"] > 0

    if not compile_ok:
        status, pass_fail = "error", "FAIL"
    elif exit_code != 0 and args.mode == "run" and run_rc != 0:
        status, pass_fail = "fail", "FAIL"
    elif explicit_fail:
        status, pass_fail = "fail", "FAIL"
    elif explicit_pass:
        status, pass_fail = "pass", "PASS"
    else:
        status, pass_fail = "unknown", "UNKNOWN"

    # Capture a couple of useful health counters from the [STATS] block.
    stats = parse_contention_stats(lines)
    health = {}
    for s in stats:
        for k in ("gdu_underflow_count", "gdu_axi_error_count", "gru_axi_error_count"):
            if k in s:
                health.setdefault(k, s[k])

    semantics_note = None
    if not compile_ok and (VLT_ERROR_RE.search(text_all) is None) and exit_code != 0:
        semantics_note = "Non-zero exit without a Verilator %Error line — possible X/4-state or unsupported construct; cross-check with ModelSim."

    # Verilator version from the transcript header the driver writes, unless an
    # explicit --simulator-version was supplied.
    simulator_version = args.simulator_version
    if not simulator_version:
        mv = re.search(r"verilator\s*=\s*(Verilator[^\n\r]*)", text_all)
        if mv:
            simulator_version = mv.group(1).strip()

    result = {
        "schema_version": SCHEMA_VERSION,
        "simulator": "verilator",
        "simulator_version": simulator_version,
        "tb": args.tb,
        "mode": args.mode,
        "status": status,
        "pass_fail": pass_fail,
        "compile_ok": bool(compile_ok),
        "load_ok": bool(load_ok),
        "run_ok": bool(run_ok),
        "exit_code": exit_code,
        "compile_rc": compile_rc,
        "run_rc": run_rc,
        "last_checkpoint": last_checkpoint,
        "final_marker": final_marker,
        "checkpoint_sequence": checkpoint_seq[-12:],
        "phase_hint": args.phase or None,
        "samples": samples,
        "fatal_messages": fatal_messages[-4:],
        "warning_counts": {
            "warning": counts["warning"],
            "error": counts["error_marker"],
            "fatal": counts["fatal_marker"],
            "fail_marker": counts["fail_marker"],
            "pass_marker": counts["pass_marker"],
        },
        "known_noise_counts": known_noise_counts,
        "framebuffer_mismatch_lines": fb_mismatch_count,
        "health_counters": health,
        "scenarios": stats,
        "selected_cfg": args.selected_cfg or None,
        "capture_mode": args.capture_mode,
        "vcd_path": args.vcd_path or None,
        "transcript_path": str(transcript),
        "build_dir": args.build_dir,
        "simulator_semantics_note": semantics_note,
    }

    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"[build_result_json] {result_path} status={status} pass_fail={pass_fail}")


if __name__ == "__main__":
    main()
