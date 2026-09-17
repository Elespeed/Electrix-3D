#!/usr/bin/env python3
"""Run the RT3D pilot matrix S0..S4 with immutable, labelled run folders.

This launcher deliberately runs one model at a time.  Each model rebuilds the
shared sdk/axi_ram.mif image, so parallel execution would contaminate runs.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

MODELS = ("S0", "S1", "S2", "S3", "S4")


def positive(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return parsed


def dump_limit(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be 0 (all dumps) or a positive limit")
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description="Sequential S0-S4 RT3D pilot regression")
    parser.add_argument("--frames", type=positive, default=4, help="formal frames per mode (default: 4)")
    parser.add_argument("--warmup", type=int, default=0, help="warmup frames per mode (default: 0)")
    parser.add_argument("--repetitions", type=positive, default=1, help="repetitions per mode (default: 1)")
    parser.add_argument("--dump-limit", type=dump_limit, default=0, help="0=dump all frames; 1 is the fast-regression exception")
    parser.add_argument("--prefix", default="REG", help="run-id prefix, e.g. PILOT or REG")
    parser.add_argument("--models", nargs="+", choices=MODELS, default=list(MODELS), help="ordered model subset (default: S0 S1 S2 S3 S4)")
    parser.add_argument("--layout", choices=("model-first", "mode-first", "reuse-mode-first"), default="model-first", help="model-first=historical isolation; mode-first=one matrix folder; reuse-mode-first=one Verilator build/mode")
    parser.add_argument("--date", help="YYYYMMDD suffix; defaults to today's local date")
    args = parser.parse_args()
    if args.warmup < 0:
        parser.error("--warmup must be non-negative")
    if not args.prefix or any(char.isspace() for char in args.prefix):
        parser.error("--prefix must be non-empty and contain no whitespace")
    day = args.date or dt.date.today().strftime("%Y%m%d")
    try:
        dt.datetime.strptime(day, "%Y%m%d")
    except ValueError:
        parser.error("--date must be YYYYMMDD")

    root = Path(__file__).resolve().parents[1]
    runs_root = root / "experiments" / "3d_scene" / "runs"
    # Run folders are immutable: a prior failed attempt may already have made
    # an empty raw/ directory before failing.  Pick one common suffix for the
    # whole S0..S4 matrix instead of overwriting or deleting that evidence.
    effective_prefix = args.prefix
    revision = 0
    def collision(prefix: str) -> bool:
        if args.layout in ("mode-first", "reuse-mode-first"):
            return (runs_root / f"{prefix}-{args.frames}F-{day}").exists()
        return any((runs_root / f"{prefix}-{model}-{args.frames}F-{day}").exists() for model in args.models)
    while collision(effective_prefix):
        revision += 1
        effective_prefix = f"{args.prefix}-r{revision:02d}"
    if effective_prefix != args.prefix:
        print(f"Run-name collision detected; using prefix {effective_prefix!r} (existing folders are unchanged).", flush=True)

    records = []
    if args.layout in ("mode-first", "reuse-mode-first"):
        run_id = f"{effective_prefix}-{args.frames}F-{day}"
        command = [
            "make", "-C", "experiments/3d_scene", f"RUN_ID={run_id}",
            f"PILOT_WARMUP={args.warmup}u", f"PILOT_FRAMES={args.frames}u",
            f"PILOT_REPETITIONS={args.repetitions}u", f"FRAME_DUMP_LIMIT={args.dump_limit}",
            f"PILOT_MODELS={' '.join(args.models)}", "pilot-reuse-matrix" if args.layout == "reuse-mode-first" else "pilot-matrix",
        ]
        print("+", subprocess.list2cmdline(command), flush=True)
        record = {"models": args.models, "run_id": run_id, "command": command}
        records.append(record)
        completed = subprocess.run(command, cwd=root)
        record["exit_code"] = completed.returncode
        if completed.returncode:
            print("FAILED: completed modes/models are retained.", file=sys.stderr)
    else:
        for model in args.models:
            run_id = f"{effective_prefix}-{model}-{args.frames}F-{day}"
            command = [
                "make", "-C", "experiments/3d_scene", f"MODEL={model}", f"RUN_ID={run_id}",
                f"PILOT_WARMUP={args.warmup}u", f"PILOT_FRAMES={args.frames}u",
                f"PILOT_REPETITIONS={args.repetitions}u", f"FRAME_DUMP_LIMIT={args.dump_limit}",
                "pilot-scale",
            ]
            print("+", subprocess.list2cmdline(command), flush=True)
            record = {"model": model, "run_id": run_id, "command": command}
            records.append(record)
            completed = subprocess.run(command, cwd=root)
            record["exit_code"] = completed.returncode
            if completed.returncode:
                print(f"FAILED: {model}; completed earlier models are retained.", file=sys.stderr)
                break

    output = runs_root / f"{effective_prefix}-matrix-{args.frames}F-{day}.regression.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"schema": "rt3d-regression/v1", "requested_prefix": args.prefix, "effective_prefix": effective_prefix, "layout": args.layout, "frames": args.frames, "warmup": args.warmup, "repetitions": args.repetitions, "frame_dump_limit": args.dump_limit, "records": records}, indent=2) + "\n", encoding="utf-8")
    print(f"Regression record: {output}")
    return 0 if records and all(record.get("exit_code") == 0 for record in records) else 1


if __name__ == "__main__":
    raise SystemExit(main())
