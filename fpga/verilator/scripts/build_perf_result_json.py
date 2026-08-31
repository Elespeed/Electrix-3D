#!/usr/bin/env python
"""Build a structured performance-benchmark JSON from a Verilator transcript.

Verilator counterpart of ``fpga/modelsim/scripts/build_perf_result_json.py``.
The line grammar is simulator-agnostic (only the ``[GRU_GDU_CONT_TB][PERF]``
emissions matter), so this is a verbatim copy of the ModelSim logic — run it on
``fpga/verilator/logs/transcript_<tb>.log`` after a ``PERF_MODE=1`` run.

Parses the ``[GRU_GDU_CONT_TB][PERF]`` lines emitted by
``gru_gdu_blit_contention_tb`` in PERF_MODE and assembles them into a stable,
script-comparable result file. Designed to be run after the simulation (it only
needs the transcript), so it is robust to the TB's ``$finish`` aborting the
in-recipe result-builder step.

Line grammar (emitted by the TB):

    [GRU_GDU_CONT_TB][PERF] RUN_BEGIN run_id=<id> perf_mode=1 repeat=.. warmup=.. frames=.. regression=..
    [GRU_GDU_CONT_TB][PERF] scenario=<name> run_id=<id> metric=<m> value=<v>
    [GRU_GDU_CONT_TB][PERF] scenario=<name> run_id=<id> metric=frame value=<i> blit_cycles=.. total_cycles=.. fifo_min=.. underflow=..
    [GRU_GDU_CONT_TB][PERF] RUN_END run_id=<id> status=<PASS|FAIL>

Metric naming convention used by the TB:
  * ``<m>``                          a raw metric (value is a scalar)
  * ``regression_<id>_status``      PASS|WARN|FAIL   (paired with _value/_baseline)
  * ``hard_rule_<id>_status``       PASS|FAIL        (paired with _value)
  * ``scenario_result``             PASS|FAIL|WARN
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


PERF_RE = re.compile(r"\[GRU_GDU_CONT_TB\]\[PERF\]\s+(?P<rest>.+)")


def parse_pairs(rest: str) -> dict[str, str]:
    pairs: dict[str, str] = {}
    for tok in rest.split():
        if "=" in tok:
            key, val = tok.split("=", 1)
            pairs[key] = val
    return pairs


def parse_scalar(text: str) -> object:
    text = text.strip()
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    try:
        return float(text)
    except ValueError:
        return text


def _split_category(metrics: dict[str, object], prefix: str) -> dict[str, dict[str, object]]:
    """Split metrics like ``<prefix>_<id>_{status,value,baseline}`` into a
    nested ``{id: {status,value,baseline}}`` mapping."""
    out: dict[str, dict[str, object]] = {}
    suffix_keys = ("_status", "_value", "_baseline")
    for key in list(metrics.keys()):
        if not key.startswith(prefix + "_"):
            continue
        rest = key[len(prefix) + 1:]
        field = None
        base = rest
        for suf in suffix_keys:
            if rest.endswith(suf):
                field = suf[1:]
                base = rest[: -len(suf)]
                break
        entry = out.setdefault(base, {})
        if field is None:
            # bare status (kept for backwards compatibility with older emits)
            entry["status"] = metrics[key]
        else:
            entry[field] = metrics[key]
    return out


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--tb", required=True)
    parser.add_argument("--run-id", default="")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    transcript = Path(args.transcript)
    text = ""
    if transcript.exists():
        text = transcript.read_text(encoding="utf-8", errors="replace").replace("\x00", "")

    run_status = "UNKNOWN"
    run_id_reported = ""
    scenarios: dict[str, dict[str, object]] = {}
    order: list[str] = []
    has_perf = False

    for raw in text.splitlines():
        match = PERF_RE.search(raw.strip())
        if not match:
            continue
        has_perf = True
        rest = match.group("rest")
        pairs = parse_pairs(rest)
        if rest.startswith("RUN_BEGIN"):
            run_id_reported = pairs.get("run_id", run_id_reported)
            continue
        if rest.startswith("RUN_END"):
            run_status = pairs.get("status", run_status)
            run_id_reported = pairs.get("run_id", run_id_reported)
            continue
        name = pairs.get("scenario")
        metric = pairs.get("metric")
        if name is None or metric is None:
            continue
        entry = scenarios.get(name)
        if entry is None:
            entry = {"scenario": name, "metrics": {}, "frames": []}
            scenarios[name] = entry
            order.append(name)
        if metric == "frame":
            frame = {
                k: parse_scalar(v)
                for k, v in pairs.items()
                if k not in ("scenario", "run_id", "metric")
            }
            entry["frames"].append(frame)
            continue
        entry["metrics"][metric] = parse_scalar(pairs.get("value", ""))

    sc_list: list[dict[str, object]] = []
    for name in order:
        entry = scenarios[name]
        metrics = dict(entry["metrics"])
        result = metrics.get("scenario_result", "UNKNOWN")
        regression = _split_category(metrics, "regression")
        hard_rules = _split_category(metrics, "hard_rule")
        flat = {
            k: v
            for k, v in metrics.items()
            if not (
                k.startswith("regression_")
                or k.startswith("hard_rule_")
                or k == "scenario_result"
            )
        }
        out_entry: dict[str, object] = {
            "scenario": name,
            "run_id": run_id_reported,
            "result": result,
            "metrics": flat,
            "regression": regression,
            "hard_rules": hard_rules,
        }
        if entry["frames"]:
            out_entry["frames"] = entry["frames"]
        sc_list.append(out_entry)

    overall = run_status
    if overall == "UNKNOWN":
        any_fail = any(str(s.get("result")) == "FAIL" for s in sc_list)
        overall = "FAIL" if any_fail else ("PASS" if sc_list else "UNKNOWN")

    result_obj = {
        "tb": args.tb,
        "run_id": run_id_reported if run_id_reported else args.run_id,
        "status": overall,
        "scenario_count": len(sc_list),
        "scenarios": sc_list,
    }

    result_path = Path(args.result)
    if not has_perf:
        print(
            "[build_perf_result_json] no [PERF] content in transcript; "
            "skipping perf result (not a perf-mode run)."
        )
        return
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result_obj, indent=2), encoding="utf-8")
    print(
        f"[build_perf_result_json] wrote {result_path} "
        f"status={overall} scenarios={len(sc_list)}"
    )


if __name__ == "__main__":
    main()
