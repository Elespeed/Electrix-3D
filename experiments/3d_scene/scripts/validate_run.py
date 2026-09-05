#!/usr/bin/env python3
"""Normative stdlib validator for scene-controller-experiment/v1 JSONL."""
from __future__ import annotations
import argparse, json
from pathlib import Path
SCHEMA="scene-controller-experiment/v1"; REQUIRED={"run_id","mode","rep","frame","asset","config_hash","cycles","scene","equivalence","error","timeout","status"}
def fail(line: int, message: str) -> None: raise ValueError(f"line {line}: {message}")
def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("jsonl",type=Path); args=ap.parse_args(); expected={}; count=0
    for line, raw in enumerate(args.jsonl.read_text(encoding="utf-8").splitlines(),1):
        if not raw.strip(): continue
        row=json.loads(raw)
        if row.get("schema") != SCHEMA or row.get("record") != "frame": fail(line,"expected scene-controller frame record")
        missing=REQUIRED-row.keys()
        if missing: fail(line,"missing "+", ".join(sorted(missing)))
        if row["mode"] != "SCENE_CONTROLLER": fail(line,"only SCENE_CONTROLLER is valid in this phase")
        if not isinstance(row["rep"],int) or row["rep"] < 1 or not isinstance(row["frame"],int) or row["frame"] < 1: fail(line,"rep/frame must be positive integers")
        asset=row["asset"]
        if not isinstance(asset,dict) or not all(k in asset for k in ("id","sha256","V","T","M")): fail(line,"asset identity incomplete")
        key=(row["run_id"],row["rep"]); next_frame=expected.get(key,1)
        if row["frame"] != next_frame: fail(line,f"expected frame {next_frame}")
        expected[key]=next_frame+1
        cycles=row["cycles"]; scene=row["scene"]
        if not isinstance(cycles,dict) or any(not isinstance(cycles.get(k),int) or cycles[k] < 0 for k in ("active","polling","blocked","wall","latency_ns")): fail(line,"invalid cycles")
        if cycles["active"] > cycles["wall"] or cycles["polling"] > cycles["wall"] or cycles["blocked"] > cycles["wall"]: fail(line,"cycle component exceeds wall")
        if not isinstance(scene,dict) or any(k not in scene for k in ("load_bytes","axi_transactions","transform_cycles","cull_cycles","sort_cycles","command_cycles","input_triangles","culled_triangles","output_triangles","command_crc","frame_crc")): fail(line,"scene counters incomplete")
        count += 1
    if not count: raise SystemExit("no frame records")
    print(f"VALID: {args.jsonl} ({count} frames, {len(expected)} repetitions)")
    return 0
if __name__ == "__main__":
    try: raise SystemExit(main())
    except (ValueError,json.JSONDecodeError) as exc: raise SystemExit(f"INVALID: {exc}")
