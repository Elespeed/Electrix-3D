#!/usr/bin/env python
#Query bounded facts from a Verilator VCD without loading it into context.
#
# Verilator counterpart of skill/modelsim-batch-debug/scripts/vcd_query.py.
# Self-contained (depends only on `vcdvcd`): summary / scope.list / signal.find /
# value.at / value.window / edge.find / event.count. Every signal-bearing query
# requires a signal filter and/or a bounded time range (task book §11.4).
#
# Differences from the ModelSim flavour:
#   * No manifest/profile dependency (Stage-1 has no VCD manifest); --phase and
#     --profile are accepted for command compatibility and echoed, not used to
#     filter signals.
#   * Signal names normalised for BOTH simulators: strip a leading "sim:/" and
#     turn "/" into "." so ModelSim (`sim:/tb/u/x`) and Verilator
#     (`tb.u.x`, Verilator emits "." as the hierarchy separator) match the same.
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import sys
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

try:
    from vcdvcd import VCDVCD
except ImportError as exc:  # pragma: no cover
    print(json.dumps({"ok": False, "error": {"code": "MISSING_DEPENDENCY", "message": str(exc)}}))
    sys.exit(1)


TIME_RE = re.compile(r"^([0-9]+(?:\.[0-9]+)?)\s*(fs|ps|ns|us|ms|s)$", re.IGNORECASE)
BIT_RE = re.compile(r"^(?P<base>.+)\[(?P<index>\d+)\]$")
RANGE_RE = re.compile(r"^(?P<base>.+)\[(?P<msb>\d+):(?P<lsb>\d+)\]$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Query Verilator VCD facts with bounded JSON output.")
    parser.add_argument("--vcd", required=True)
    parser.add_argument("--phase", help="accepted for compatibility; recorded, not used to filter")
    parser.add_argument("--profile", action="append", default=[], help="accepted for compatibility; recorded, not used to filter")
    parser.add_argument("--action", required=True, choices=[
        "summary",
        "scope.list",
        "signal.find",
        "value.at",
        "value.window",
        "edge.find",
        "event.count",
    ])
    parser.add_argument("--pattern")
    parser.add_argument("--scope")
    parser.add_argument("--signal")
    parser.add_argument("--time")
    parser.add_argument("--start")
    parser.add_argument("--end")
    parser.add_argument("--value")
    parser.add_argument("--edge", choices=["rising", "falling", "any"], default="any")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--max-signals", type=int, default=50)
    parser.add_argument("--max-transitions", type=int, default=64)
    return parser.parse_args()


def normalize_signal_name(name: str) -> str:
    """Map both ModelSim and Verilator hierarchical names to dotted form.

    Strips a leading ModelSim ``sim:/`` and a Verilator ``TOP.`` wrapper scope so
    the same query matches both simulators' VCDs."""
    text = name.strip()
    if text.startswith("sim:/"):
        text = text[len("sim:/"):]
    elif text.startswith("sim:"):
        text = text[len("sim:"):]
    text = text.replace("/", ".")
    if text.startswith("TOP."):
        text = text[len("TOP."):]
    return text


def load_vcd(path: Path, with_tvs: bool) -> VCDVCD:
    return VCDVCD(str(path), store_tvs=with_tvs)


def parse_time_to_seconds(text: str) -> Decimal:
    match = TIME_RE.match(text.strip())
    if not match:
        raise ValueError(f"Invalid time '{text}'")
    number = Decimal(match.group(1))
    unit = match.group(2).lower()
    factor = {
        "fs": Decimal("1e-15"),
        "ps": Decimal("1e-12"),
        "ns": Decimal("1e-9"),
        "us": Decimal("1e-6"),
        "ms": Decimal("1e-3"),
        "s": Decimal("1"),
    }[unit]
    return number * factor


def parse_time_to_ticks(text: str, timescale_factor: Decimal) -> int:
    seconds = parse_time_to_seconds(text)
    return int(seconds / timescale_factor)


def format_ticks(ticks: int, factor: Decimal) -> str:
    seconds = Decimal(ticks) * factor
    abs_seconds = abs(seconds)
    units = (
        ("s", Decimal("1")),
        ("ms", Decimal("1e-3")),
        ("us", Decimal("1e-6")),
        ("ns", Decimal("1e-9")),
        ("ps", Decimal("1e-12")),
        ("fs", Decimal("1e-15")),
    )
    for unit, scale in units:
        value = seconds / scale
        if abs_seconds >= scale and abs(value) < Decimal("1000"):
            return f"{value:.6f}{unit}"
    unit, scale = units[-1]
    return f"{seconds / scale:.6f}{unit}"


def build_signal_catalog(references: list[str]) -> tuple[dict[str, list[int]], set[str], dict[str, str]]:
    groups: dict[str, list[int]] = defaultdict(list)
    scalars: set[str] = set()
    vectors: dict[str, str] = {}
    for ref in references:
        range_match = RANGE_RE.match(ref)
        if range_match:
            vectors[range_match.group("base")] = ref
            continue
        match = BIT_RE.match(ref)
        if match:
            groups[match.group("base")].append(int(match.group("index")))
        else:
            scalars.add(ref)
    return groups, scalars, vectors


def resolve_signal(query: str, references: list[str]) -> dict[str, object]:
    normalized = normalize_signal_name(query)
    groups, scalars, vectors = build_signal_catalog(references)
    if normalized in scalars:
        return {"kind": "scalar", "name": normalized}
    if normalized in vectors:
        return {"kind": "vector", "name": vectors[normalized]}
    if normalized in groups:
        return {"kind": "bus", "name": normalized, "bits": sorted(groups[normalized], reverse=True)}
    if normalized in references:
        return {"kind": "scalar", "name": normalized}
    return {"kind": "missing", "name": normalized}


def value_for_tick(vcd: VCDVCD, signal: str, tick: int) -> str:
    tv = vcd[signal].tv
    current = "x"
    for at, value in tv:
        if at > tick:
            break
        current = value
    return current


def bus_value_for_tick(vcd: VCDVCD, base: str, bits: list[int], tick: int) -> str:
    parts = []
    for bit in bits:
        parts.append(value_for_tick(vcd, f"{base}[{bit}]", tick))
    return "".join(parts)


def compact_samples(items: list[object], limit: int) -> list[object]:
    return items[:limit]


class NormVcd:
    """Wrap a VCDVCD so ``proxy[normalized_name]`` resolves to the original
    reference key. Matching uses normalized names (TOP./sim:/ stripped) but
    vcdvcd's keys are the original hierarchy, so value lookups must map back."""

    def __init__(self, vcd: VCDVCD, norm_to_orig: dict[str, str]) -> None:
        self._vcd = vcd
        self._m = norm_to_orig

    def __getitem__(self, name: str):
        return self._vcd[self._m.get(name, name)]

    def __getattr__(self, attr: str):
        return getattr(self._vcd, attr)


def main() -> None:
    args = parse_args()
    vcd_path = Path(args.vcd).resolve()
    if not vcd_path.exists():
        print(json.dumps({"ok": False, "error": {"code": "VCD_NOT_FOUND", "message": str(vcd_path)}}))
        sys.exit(1)

    with_tvs = args.action in {"value.at", "value.window", "edge.find", "event.count"}
    vcd = load_vcd(vcd_path, with_tvs=with_tvs)
    # references = normalized (for matching/display); norm_to_orig maps back to
    # the original vcdvcd keys (TOP./sim:/ stripped only for matching).
    norm_to_orig: dict[str, str] = {}
    references: list[str] = []
    for raw_ref in vcd.references_to_ids.keys():
        norm = normalize_signal_name(raw_ref)
        norm_to_orig[norm] = raw_ref
        references.append(norm)
    pvcd = NormVcd(vcd, norm_to_orig)
    timescale_factor = Decimal(str(vcd.timescale["factor"]))

    # echo (not filter) phase/profile for command compatibility with the skill.
    compat = {"phase": args.phase, "profile": args.profile} if (args.phase or args.profile) else None

    if args.action == "summary":
        payload = {
            "ok": True,
            "action": args.action,
            "vcd": str(vcd_path),
            "timescale": str(vcd.timescale["factor"]),
            "signal_count": len(references),
            "end_tick": int(vcd.endtime),
            "end_time": format_ticks(int(vcd.endtime), timescale_factor),
            "compat": compat,
            "sample_signals": compact_samples(references, args.max_signals),
        }
        print(json.dumps(payload, indent=2))
        return

    if args.action == "signal.find":
        pattern = args.pattern or "*"
        pattern_norm = normalize_signal_name(pattern)
        matches = [
            ref for ref in references
            if fnmatch.fnmatch(ref, pattern_norm) or pattern_norm.lower() in ref.lower()
        ]
        payload = {
            "ok": True,
            "action": args.action,
            "pattern": pattern,
            "compat": compat,
            "match_count": len(matches),
            "matches": compact_samples(matches, args.max_signals),
            "truncated": len(matches) > args.max_signals,
        }
        print(json.dumps(payload, indent=2))
        return

    if args.action == "scope.list":
        scope = normalize_signal_name(args.scope or "")
        if not scope:
            print(json.dumps({"ok": False, "error": {"code": "SCOPE_REQUIRED", "message": "--scope is required"}}))
            sys.exit(1)
        prefix = scope + "."
        matches = [ref for ref in references if ref == scope or ref.startswith(prefix)]
        payload = {
            "ok": True,
            "action": args.action,
            "scope": scope,
            "match_count": len(matches),
            "matches": compact_samples(matches, args.max_signals),
            "truncated": len(matches) > args.max_signals,
        }
        print(json.dumps(payload, indent=2))
        return

    if not args.signal:
        print(json.dumps({"ok": False, "error": {"code": "SIGNAL_REQUIRED", "message": "--signal is required"}}))
        sys.exit(1)

    resolved = resolve_signal(args.signal, references)
    if resolved["kind"] == "missing":
        print(json.dumps({"ok": False, "error": {"code": "SIGNAL_NOT_FOUND", "message": resolved["name"]}}))
        sys.exit(1)

    if args.action == "value.at":
        if not args.time:
            print(json.dumps({"ok": False, "error": {"code": "TIME_REQUIRED", "message": "--time is required"}}))
            sys.exit(1)
        tick = parse_time_to_ticks(args.time, timescale_factor)
        if resolved["kind"] in {"scalar", "vector"}:
            value = value_for_tick(pvcd, resolved["name"], tick)
        else:
            value = bus_value_for_tick(pvcd, resolved["name"], resolved["bits"], tick)
        payload = {
            "ok": True,
            "action": args.action,
            "signal": resolved["name"],
            "time": args.time,
            "tick": tick,
            "value": value,
        }
        print(json.dumps(payload, indent=2))
        return

    if not args.start or not args.end:
        print(json.dumps({"ok": False, "error": {"code": "WINDOW_REQUIRED", "message": "--start and --end are required"}}))
        sys.exit(1)
    start_tick = parse_time_to_ticks(args.start, timescale_factor)
    end_tick = parse_time_to_ticks(args.end, timescale_factor)
    if end_tick < start_tick:
        print(json.dumps({"ok": False, "error": {"code": "BAD_WINDOW", "message": "--end must be >= --start"}}))
        sys.exit(1)

    if resolved["kind"] in {"scalar", "vector"}:
        tv = [(int(at), value) for at, value in pvcd[resolved["name"]].tv if start_tick <= int(at) <= end_tick]
        initial = value_for_tick(pvcd, resolved["name"], start_tick)
    else:
        tv = []
        initial = bus_value_for_tick(pvcd, resolved["name"], resolved["bits"], start_tick)
        seen_ticks = sorted({
            int(at)
            for bit in resolved["bits"]
            for at, _ in pvcd[f"{resolved['name']}[{bit}]"].tv
            if start_tick <= int(at) <= end_tick
        })
        for at in seen_ticks:
            value = bus_value_for_tick(pvcd, resolved["name"], resolved["bits"], at)
            tv.append((at, value))

    if args.action == "value.window":
        samples = [{"tick": at, "time": format_ticks(at, timescale_factor), "value": value} for at, value in tv]
        payload = {
            "ok": True,
            "action": args.action,
            "signal": resolved["name"],
            "start": args.start,
            "end": args.end,
            "initial_value": initial,
            "transition_count": len(tv),
            "samples": compact_samples(samples, args.max_transitions),
            "truncated": len(samples) > args.max_transitions,
        }
        print(json.dumps(payload, indent=2))
        return

    if args.action == "edge.find":
        if resolved["kind"] != "scalar":
            print(json.dumps({"ok": False, "error": {"code": "EDGE_SCALAR_ONLY", "message": "edge.find only supports scalar signals"}}))
            sys.exit(1)
        prev = value_for_tick(pvcd, resolved["name"], start_tick)
        matches = []
        for at, value in tv:
            is_rising = prev in {"0", "x", "z"} and value == "1"
            is_falling = prev == "1" and value in {"0", "x", "z"}
            if args.edge == "rising" and is_rising:
                matches.append({"tick": at, "time": format_ticks(at, timescale_factor), "value": value})
            elif args.edge == "falling" and is_falling:
                matches.append({"tick": at, "time": format_ticks(at, timescale_factor), "value": value})
            elif args.edge == "any" and (is_rising or is_falling):
                matches.append({"tick": at, "time": format_ticks(at, timescale_factor), "value": value})
            prev = value
        payload = {
            "ok": True,
            "action": args.action,
            "signal": resolved["name"],
            "edge": args.edge,
            "match_count": len(matches),
            "matches": compact_samples(matches, args.limit),
            "truncated": len(matches) > args.limit,
        }
        print(json.dumps(payload, indent=2))
        return

    if args.action == "event.count":
        target_value = args.value
        if target_value is None:
            count = len(tv)
            mode = "transitions"
        else:
            count = sum(1 for _, value in tv if value == target_value)
            mode = "value_matches"
        payload = {
            "ok": True,
            "action": args.action,
            "signal": resolved["name"],
            "mode": mode,
            "start": args.start,
            "end": args.end,
            "value": target_value,
            "count": count,
            "sample": compact_samples(
                [{"tick": at, "time": format_ticks(at, timescale_factor), "value": value} for at, value in tv],
                min(args.limit, args.max_transitions),
            ),
        }
        print(json.dumps(payload, indent=2))
        return


if __name__ == "__main__":
    main()
