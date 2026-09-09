#!/usr/bin/env python3
"""Run-local CPU_ONLY vs CPU_MATMUL display equivalence gate.

This deliberately reads only a run directory.  It never edits the approved
golden manifest and emits a machine-readable pair report plus annotated rows.
"""
from __future__ import annotations
import argparse, json
from pathlib import Path

MODE_PAIRS = ("CPU_ONLY", "CPU_MATMUL")

def rows(path: Path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", type=Path)
    ap.add_argument("--output-dir", type=Path)
    args = ap.parse_args()
    root = args.run_dir
    output = args.output_dir or root / "equivalence"
    output.mkdir(parents=True, exist_ok=True)
    grouped = {}
    errors = []
    for mode in MODE_PAIRS:
        for path in sorted((root / mode).glob("*/validated/frames.jsonl")):
            for row in rows(path):
                key = (row.get("asset", {}).get("id"), row.get("rep"), row.get("frame"))
                grouped.setdefault(key, {})[mode] = (row, path)
    pairs = []
    for key in sorted(grouped, key=lambda x: tuple(str(v) for v in x)):
        pair = grouped[key]; reasons = []
        if any(mode not in pair for mode in MODE_PAIRS):
            reasons.append("missing_mode_record")
        else:
            left, left_path = pair[MODE_PAIRS[0]]; right, right_path = pair[MODE_PAIRS[1]]
            left_crc = left.get("scene", {}).get("frame_crc", 0)
            right_crc = right.get("scene", {}).get("frame_crc", 0)
            if not isinstance(left_crc, int) or not 0 < left_crc <= 0xffffffff: reasons.append("CPU_ONLY frame_crc is zero or invalid")
            if not isinstance(right_crc, int) or not 0 < right_crc <= 0xffffffff: reasons.append("CPU_MATMUL frame_crc is zero or invalid")
            if left_crc != right_crc: reasons.append("display_crc_mismatch")
            for row, mode in ((left, MODE_PAIRS[0]), (right, MODE_PAIRS[1])):
                if row.get("error") != "NONE" or row.get("timeout") is not False or row.get("status") != "PASS": reasons.append(f"{mode} status tuple is not passing")
            pairs.append({"asset": key[0], "rep": key[1], "frame": key[2], "equivalence": "PASS" if not reasons else "FAIL", "frame_crc": {"CPU_ONLY": left_crc, "CPU_MATMUL": right_crc}, "inputs": {"CPU_ONLY": str(left_path), "CPU_MATMUL": str(right_path)}, "reasons": reasons})
        if any(mode not in pair for mode in MODE_PAIRS):
            pairs.append({"asset": key[0], "rep": key[1], "frame": key[2], "equivalence": "FAIL", "reasons": reasons, "inputs": {mode: str(pair[mode][1]) for mode in pair}})
    if not pairs: errors.append("no CPU_ONLY/CPU_MATMUL frame pairs found")
    passed = not errors and bool(pairs) and all(p["equivalence"] == "PASS" for p in pairs)
    report = {"schema": "scene-controller-equivalence/v1", "run_dir": str(root), "modes": list(MODE_PAIRS), "pairs": pairs, "status": "PASS" if passed else "FAIL", "approved_golden_modified": False}
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with (output / "verification.jsonl").open("w", encoding="utf-8") as stream:
        for pair in pairs: stream.write(json.dumps(pair, sort_keys=True) + "\n")
    print(json.dumps({"status": report["status"], "pairs": len(pairs), "report": str(output / "report.json")}, sort_keys=True))
    return 0 if passed else 1

if __name__ == "__main__": raise SystemExit(main())
