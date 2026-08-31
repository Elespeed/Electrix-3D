#!/usr/bin/env python
#Summarize a Verilator transcript without loading the whole log into context.
#
# Verilator counterpart of skill/modelsim-batch-debug/scripts/transcript_summarize.py.
# Self-contained (no external modules): classifies compile/run/warning/PASS-FAIL,
# extracts checkpoints, contention [STATS], framebuffer mismatches, and prints a
# compact JSON summary. Run it on fpga/verilator/logs/transcript_<tb>.log.
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


VLT_ERROR_RE = re.compile(r"%Error\b")
VLT_WARNING_RE = re.compile(r"%Warning\b")
CPP_ERROR_RE = re.compile(r":\s*(?:fatal )?error:", re.IGNORECASE)
CPP_LINK_RE = re.compile(r"undefined reference|collect2: error|ld returned", re.IGNORECASE)
# A %Fatal line carries the actual diagnostic (e.g. an expect_pixel/assertion
# mismatch message); Verilator then echoes a generic "%Error ... Verilog $stop"
# line that says nothing on its own.  Prefer the %Fatal text over that echo.
FATAL_MSG_RE = re.compile(r"%Fatal\b[^\r\n]*")
FATAL_RE = re.compile(r"\$fatal|\bfatal\b", re.IGNORECASE)
TIMEOUT_RE = re.compile(r"timeout after", re.IGNORECASE)
FB_MISMATCH_RE = re.compile(r"\[FB_MEM_MISMATCH\]|\[FRAME_MISMATCH\]")
PASS_RE = re.compile(r"\bPASS\b")
FAIL_RE = re.compile(r"\bFAIL\b")
STATS_RE = re.compile(r"\[GRU_GDU_CONT_TB\]\[STATS\]\s+(?P<key>[A-Za-z0-9_]+)=(?P<value>.+)")
PERF_RE = re.compile(r"\[GRU_GDU_CONT_TB\]\[PERF\]\s+(?P<rest>.+)")
CHECKPOINT_RE = re.compile(r"\[GRU_GDU_CONT_TB\]\s+(?P<cp>[A-Za-z][^\[\r\n]*)$")
OS_GDU_DIAG_RE = re.compile(r"\[(?P<tb>[A-Za-z0-9_]+)\]\[GDU_DIAG\]\[(?P<cp>[^\]]+)\]")
DVI_DUMP_RE = re.compile(r"\[DVI_MON\]\s+dumped frame=(?P<frame>\d+)")
DVI_SAVE_RE = re.compile(r"\[DVI_MON\]\s+file saved to:")
COMPILE_RC_RE = re.compile(r"VERILATOR_COMPILE_RC=(\S+)")
RUN_RC_RE = re.compile(r"VERILATOR_RUN_RC=(\S+)")


def classify(line: str) -> str | None:
    if FATAL_MSG_RE.search(line):
        return "fatal"
    if VLT_ERROR_RE.search(line) or CPP_ERROR_RE.search(line) or CPP_LINK_RE.search(line):
        return "error"
    if VLT_WARNING_RE.search(line):
        return "warning"
    if FB_MISMATCH_RE.search(line):
        return "fb_mismatch"
    if TIMEOUT_RE.search(line):
        return "timeout"
    if FAIL_RE.search(line):
        return "fail_marker"
    if PASS_RE.search(line):
        return "pass_marker"
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description="Summarize a Verilator transcript log.")
    ap.add_argument("--log", required=True)
    ap.add_argument("--max-lines", type=int, default=8)
    args = ap.parse_args()

    log = Path(args.log)
    if not log.exists():
        print(json.dumps({"ok": False, "error": {"code": "LOG_NOT_FOUND", "message": str(log)}}))
        sys.exit(1)

    lines = log.read_text(encoding="utf-8", errors="replace").replace("\x00", "").splitlines()
    counts = {"fatal": 0, "error": 0, "warning": 0, "timeout": 0, "fb_mismatch": 0, "fail_marker": 0, "pass_marker": 0, "perf": 0, "dvi_frame_dump": 0, "dvi_file_save": 0}
    samples: dict[str, list[str]] = {k: [] for k in counts}
    checkpoints: list[str] = []
    last_stats: dict[str, object] = {}
    compile_rc = run_rc = None
    first_error: str | None = None
    fatal_messages: list[str] = []

    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        m = CHECKPOINT_RE.search(line)
        if m:
            checkpoints.append(m.group("cp").strip())
        m = OS_GDU_DIAG_RE.search(line)
        if m:
            checkpoints.append(f"{m.group('tb')}:GDU_DIAG:{m.group('cp')}")
        if DVI_DUMP_RE.search(line):
            counts["dvi_frame_dump"] += 1
        if DVI_SAVE_RE.search(line):
            counts["dvi_file_save"] += 1
        m = STATS_RE.search(line)
        if m:
            last_stats[m.group("key")] = m.group("value").strip()
        if PERF_RE.search(line):
            counts["perf"] += 1
            if len(samples.setdefault("perf", [])) < args.max_lines:
                samples["perf"].append(line)
        for rx, key in ((COMPILE_RC_RE, "compile_rc"), (RUN_RC_RE, "run_rc")):
            mm = rx.search(line)
            if mm:
                tok = mm.group(1)
                if key == "compile_rc":
                    compile_rc = tok
                else:
                    run_rc = tok
        kind = classify(line)
        if kind:
            counts[kind] += 1
            if len(samples[kind]) < args.max_lines:
                samples[kind].append(line)
            if kind == "fatal":
                fatal_messages.append(line)
                if first_error is None:
                    first_error = line
            elif kind in {"error", "fb_mismatch", "timeout", "fail_marker"} and first_error is None:
                first_error = line

    # The %Fatal assertion text is the actionable diagnostic; a lone
    # "%Error ... Verilog $stop" echo should never mask it.
    if not fatal_messages and counts["error"]:
        first_error = first_error or (samples["error"][0] if samples["error"] else None)

    last_cp = checkpoints[-1] if checkpoints else None
    if counts["error"] or (compile_rc not in (None, "0")):
        status = "compile_or_run_error"
    elif counts["fatal"] or counts["timeout"] or counts["fail_marker"] or counts["fb_mismatch"]:
        status = "failed"
    elif counts["pass_marker"]:
        status = "pass"
    else:
        status = "no_pass_fail_marker"

    summary = {
        "ok": True,
        "log": str(log),
        "line_count": len(lines),
        "status": status,
        "last_checkpoint": last_cp,
        "checkpoints_tail": checkpoints[-12:],
        "compile_rc": compile_rc,
        "run_rc": run_rc,
        "counts": counts,
        "first_error": first_error,
        "fatal_messages": fatal_messages[-4:],
        "last_stats": last_stats,
        "samples": samples,
    }
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
