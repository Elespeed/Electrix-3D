#!/usr/bin/env python3
"""Normative stdlib validator for scene-controller-experiment/v1 JSONL."""
from __future__ import annotations
import argparse, json
from pathlib import Path
SCHEMA="scene-controller-experiment/v1"; MODES={"CPU_ONLY","CPU_MATMUL","SCENE_CONTROLLER"}; REQUIRED={"run_id","mode","rep","frame","asset","config_hash","cycles","scene","error","timeout","status"}
def fail(line: int, message: str) -> None: raise ValueError(f"line {line}: {message}")
def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("jsonl",type=Path); ap.add_argument("--manifest",type=Path); args=ap.parse_args(); expected={}; count=0
    manifest_path=args.manifest or args.jsonl.parent.parent/"manifest.json"
    manifest=json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else None
    for line, raw in enumerate(args.jsonl.read_text(encoding="utf-8").splitlines(),1):
        if not raw.strip(): continue
        row=json.loads(raw)
        if row.get("schema") != SCHEMA or row.get("record") != "frame": fail(line,"expected scene-controller frame record")
        missing=REQUIRED-row.keys()
        if missing: fail(line,"missing "+", ".join(sorted(missing)))
        if row["mode"] not in MODES: fail(line,"unsupported benchmark mode")
        if not isinstance(row["rep"],int) or row["rep"] < 1 or not isinstance(row["frame"],int) or row["frame"] < 1: fail(line,"rep/frame must be positive integers")
        asset=row["asset"]
        if not isinstance(asset,dict) or not all(k in asset for k in ("id","sha256","V","T","M")): fail(line,"asset identity incomplete")
        if asset["M"] != 1: fail(line,"only single-mesh assets (M=1) are valid")
        if manifest:
            if row["run_id"] != manifest.get("run_id") or row["mode"] != manifest.get("mode") or asset["id"] != manifest.get("model"): fail(line,"manifest identity mismatch")
            if asset["sha256"] != manifest.get("asset_sha256") or row["config_hash"] != manifest.get("config_sha256"): fail(line,"asset/config hash mismatch")
        if not isinstance(asset["sha256"],str) or len(asset["sha256"]) != 64 or not isinstance(row["config_hash"],str) or len(row["config_hash"]) != 64: fail(line,"unfrozen asset/config hash")
        key=(row["run_id"],row["rep"]); next_frame=expected.get(key,1)
        if row["frame"] != next_frame: fail(line,f"expected frame {next_frame}")
        expected[key]=next_frame+1
        cycles=row["cycles"]; scene=row["scene"]
        if not isinstance(cycles,dict) or any(not isinstance(cycles.get(k),int) or cycles[k] < 0 for k in ("active","polling","blocked","wall","latency_ns")): fail(line,"invalid cycles")
        if cycles["active"] > cycles["wall"] or cycles["polling"] > cycles["wall"] or cycles["blocked"] > cycles["wall"]: fail(line,"cycle component exceeds wall")
        scene_keys=("load_bytes","axi_transactions","transform_cycles","cull_cycles","sort_cycles","command_cycles","input_triangles","culled_triangles","output_triangles","command_crc","frame_crc")
        if not isinstance(scene,dict) or any(k not in scene for k in scene_keys) or any(not isinstance(scene[k],int) or scene[k] < 0 for k in scene_keys): fail(line,"scene counters incomplete")
        if scene["culled_triangles"] + scene["output_triangles"] != scene["input_triangles"]: fail(line,"triangle accounting mismatch")
        if not isinstance(row["rtos"],dict) or any(k not in row["rtos"] for k in ("idle_rate_permille","background_units","background_units_per_second")): fail(line,"rtos counters incomplete")
        count += 1
    if not count: raise SystemExit("no frame records")
    print(f"VALID: {args.jsonl} ({count} frames, {len(expected)} repetitions)")
    return 0
if __name__ == "__main__":
    try: raise SystemExit(main())
    except (ValueError,json.JSONDecodeError) as exc: raise SystemExit(f"INVALID: {exc}")
