#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from manifest_utils import checkpoint_regex, default_manifest_path, load_manifest, noise_rules, phase_from_checkpoint


PASS_RE = re.compile(r"\bPASS\b", re.IGNORECASE)
FAIL_RE = re.compile(r"\bFAIL\b", re.IGNORECASE)
WARN_RE = re.compile(r"\*\*\s+Warning:| WARNING:", re.IGNORECASE)
ERROR_RE = re.compile(r"\*\*\s+Error| ERROR:", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize a ModelSim transcript log.")
    parser.add_argument("--log", required=True)
    parser.add_argument("--manifest")
    parser.add_argument("--max-lines", type=int, default=8)
    return parser.parse_args()


def append_limited(bucket: list[str], value: str, limit: int) -> None:
    if len(bucket) < limit:
        bucket.append(value)


def classify(line: str) -> str | None:
    if "Error loading design" in line:
        return "load_error"
    if "Simulation error:" in line:
        return "runtime_error"
    if line.startswith("# Errors:") or "vlog-" in line or "vcom-" in line:
        if ERROR_RE.search(line):
            return "compile_error"
    if " at time " in line and " ERROR:" in line:
        return "runtime_error"
    if ERROR_RE.search(line):
        if "vopt-" in line or "vsim-" in line:
            return "runtime_error"
        return "compile_error"
    if WARN_RE.search(line):
        return "warning"
    if "VCD output" in line or "VCD preset" in line or "VCD window" in line or "VCD hit time" in line:
        return "vcd_info"
    if PASS_RE.search(line):
        return "pass_marker"
    if FAIL_RE.search(line):
        return "fail_marker"
    return None


def matches_known_noise(line: str, rules: list[dict[str, object]]) -> dict[str, object] | None:
    for rule in rules:
        pattern = str(rule.get("match", ""))
        if pattern and re.search(pattern, line):
            return rule
    return None


def derive_manifest_path(log_path: Path, explicit_path: str | None) -> Path:
    if explicit_path:
        return Path(explicit_path).resolve()
    modelsim_root = log_path.parent.parent
    return default_manifest_path(modelsim_root).resolve()


def main() -> None:
    args = parse_args()
    log_path = Path(args.log).resolve()
    if not log_path.exists():
        print(json.dumps({"ok": False, "error": {"code": "LOG_NOT_FOUND", "message": str(log_path)}}))
        sys.exit(1)

    manifest_path = derive_manifest_path(log_path, args.manifest)
    manifest = load_manifest(manifest_path)
    known_noise_rules = noise_rules(manifest)
    checkpoint_re = re.compile(checkpoint_regex(manifest))

    raw_text = log_path.read_text(encoding="utf-8", errors="replace").replace("\x00", "")
    lines = raw_text.splitlines()

    summary = {
        "ok": True,
        "log": str(log_path),
        "manifest": str(manifest_path),
        "line_count": len(lines),
        "status": "unknown",
        "phase_hint": None,
        "last_checkpoint": None,
        "final_marker": None,
        "checkpoint_sequence": [],
        "counts": {
            "compile_error": 0,
            "load_error": 0,
            "runtime_error": 0,
            "warning": 0,
            "known_noise": 0,
            "pass_marker": 0,
            "fail_marker": 0,
            "vcd_info": 0,
        },
        "known_noise_counts": {},
        "samples": {
            "compile_error": [],
            "load_error": [],
            "runtime_error": [],
            "warning": [],
            "known_noise": [],
            "pass_marker": [],
            "fail_marker": [],
            "vcd_info": [],
        },
    }

    for raw in lines:
        line = raw.strip()
        if not line:
            continue

        checkpoint_match = checkpoint_re.search(line)
        if checkpoint_match:
            checkpoint = checkpoint_match.groupdict().get("checkpoint") or checkpoint_match.group(0)
            summary["checkpoint_sequence"].append(checkpoint)
            if checkpoint in {"PASS", "FAIL"}:
                summary["final_marker"] = checkpoint
            else:
                summary["last_checkpoint"] = checkpoint

        known_noise = matches_known_noise(line, known_noise_rules)
        if known_noise:
            summary["counts"]["known_noise"] += 1
            noise_id = str(known_noise.get("id", "known_noise"))
            summary["known_noise_counts"][noise_id] = summary["known_noise_counts"].get(noise_id, 0) + 1
            append_limited(summary["samples"]["known_noise"], line, args.max_lines)
            continue

        kind = classify(line)
        if not kind:
            continue
        summary["counts"][kind] += 1
        append_limited(summary["samples"][kind], line, args.max_lines)

    summary["phase_hint"] = phase_from_checkpoint(manifest, summary["last_checkpoint"])

    if summary["counts"]["compile_error"] or summary["counts"]["load_error"]:
        summary["status"] = "compile_or_load_failed"
    elif summary["counts"]["runtime_error"] or summary["counts"]["fail_marker"]:
        summary["status"] = "runtime_failed"
    elif summary["counts"]["pass_marker"]:
        summary["status"] = "pass"
    else:
        summary["status"] = "no_pass_fail_marker"

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
