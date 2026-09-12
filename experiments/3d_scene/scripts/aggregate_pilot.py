#!/usr/bin/env python3
"""Aggregate one-model, three-backend PILOT results without CRC gating."""
from __future__ import annotations
import argparse, json, math, statistics
from pathlib import Path

MODES = ("CPU_ONLY", "CPU_MATMUL", "SCENE_CONTROLLER")

def nearest(values: list[int], percentile: float) -> int:
    return sorted(values)[max(0, math.ceil(len(values) * percentile) - 1)]

def load_rows(root: Path, run_id: str, model: str, mode: str) -> list[dict]:
    run = root / "experiments/3d_scene/runs" / run_id / mode / model
    path = run / "validated/frames.jsonl"
    if not path.exists():
        raise SystemExit(f"missing validated frames: {path}")
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows:
        raise SystemExit(f"empty validated frames: {path}")
    manifest_path = run / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected = manifest["formal_frames"] * manifest["repetitions"]
    if len(rows) != expected:
        raise SystemExit(f"sample count mismatch in {path}: got {len(rows)}, expected {expected}")
    if any(row.get("status") != "PASS" or row.get("error") != "NONE" or row.get("timeout") is not False for row in rows):
        raise SystemExit(f"non-passing frame in {path}")
    return rows

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--model", required=True)
    args = ap.parse_args()
    records = {}
    for mode in MODES:
        rows = load_rows(args.root, args.run_id, args.model, mode)
        active = [row["cycles"]["active"] for row in rows]
        latency = [row["cycles"]["latency_ns"] for row in rows]
        records[mode] = {
            "samples": len(rows),
            "active_median": int(statistics.median(active)),
            "latency_median_ns": int(statistics.median(latency)),
            "latency_p95_ns": nearest(latency, 0.95),
            "latency_p99_ns": "INVALID",
            "budget_ns": 33_333_333,
            "budget_over_frames": sum(value > 33_333_333 for value in latency),
        }
    matmul = records["CPU_MATMUL"]
    scene = records["SCENE_CONTROLLER"]
    report = {
        "schema": "scene-controller-pilot-aggregate/v1",
        "run_class": "PILOT",
        "decision_use": "descriptive_only",
        "run_id": args.run_id,
        "model": args.model,
        "modes": records,
        "scene_vs_matmul": {
            "active_reduction": (matmul["active_median"] - scene["active_median"]) / matmul["active_median"] if matmul["active_median"] else None,
            "latency_relative_change": scene["latency_median_ns"] / matmul["latency_median_ns"] - 1 if matmul["latency_median_ns"] else None,
            "note": "pilot descriptive/non-decisive; P99 INVALID below 1500 frames",
        },
    }
    out = args.root / "experiments/3d_scene/runs" / args.run_id / "PILOT" / args.model
    out.mkdir(parents=True, exist_ok=True)
    (out / "aggregate_report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    lines = [f"# PILOT aggregate ({args.model})", "", "Descriptive only; CRC is diagnostic and not a gate.", "", "| Mode | N | active median | latency median (ns) | latency P95 (ns) | P99 | over budget |", "| --- | ---: | ---: | ---: | ---: | --- | ---: |"]
    for mode in MODES:
        value = records[mode]
        lines.append(f"| {mode} | {value['samples']} | {value['active_median']} | {value['latency_median_ns']} | {value['latency_p95_ns']} | INVALID | {value['budget_over_frames']} |")
    compare = report["scene_vs_matmul"]
    lines += ["", f"- Scene vs Matmul active reduction: `{compare['active_reduction']}`", f"- Scene vs Matmul latency relative change: `{compare['latency_relative_change']}`", "- P99: `INVALID` (pilot sample count below 1500)."]
    (out / "aggregate_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(out / "aggregate_report.json")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
