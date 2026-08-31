#!/usr/bin/env python3
"""Validate the benchmark JSONL v1 stream used by the 3D experiments.

The validator intentionally uses only the Python standard library so it can be
run in the SDK/CI images and directly against UART-captured files.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SCHEMA = "3d-benchmark/v1"
MODES = {"CPU_ONLY", "CPU_MATMUL", "SCENE_CONTROLLER"}
STATUSES = {"pass", "fail", "error"}
PHASES = ("transform", "triangle_cull", "painter_sort", "command_submit")
HEX_CRC = re.compile(r"^(?:0x)?[0-9a-fA-F]{1,8}$")


class ValidationError(Exception):
    pass


def _obj(value: Any, where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValidationError(f"{where}: expected object")
    return value


def _required(obj: dict[str, Any], fields: tuple[str, ...], where: str) -> None:
    missing = [field for field in fields if field not in obj]
    if missing:
        raise ValidationError(f"{where}: missing {', '.join(missing)}")


def _string(obj: dict[str, Any], field: str, where: str) -> str:
    value = obj.get(field)
    if not isinstance(value, str) or not value:
        raise ValidationError(f"{where}.{field}: expected non-empty string")
    return value


def _uint(value: Any, where: str) -> int:
    # bool is an int subclass, but is not a valid cycle/count value.
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValidationError(f"{where}: expected non-negative integer")
    return value


def _cycles(obj: dict[str, Any], where: str) -> None:
    _required(obj, ("active", "polling", "wall"), where)
    for field in ("active", "polling", "wall"):
        _uint(obj[field], f"{where}.{field}")
    if obj["active"] > obj["wall"]:
        raise ValidationError(f"{where}: active cannot exceed wall")
    if obj["polling"] > obj["wall"]:
        raise ValidationError(f"{where}: polling cannot exceed wall")


def _identity(obj: dict[str, Any], where: str) -> tuple[str, int, int, int]:
    mode = _string(obj, "mode", where)
    if mode not in MODES:
        raise ValidationError(f"{where}.mode: unsupported mode {mode!r}")
    values = tuple(_uint(obj.get(name), f"{where}.{name}") for name in ("V", "T", "M"))
    if not all(values):
        raise ValidationError(f"{where}: V, T and M must be positive")
    return (mode, *values)


def _validate_begin(record: dict[str, Any], line: int) -> tuple[str, tuple[str, int, int, int]]:
    where = f"line {line}"
    _required(record, ("record", "schema", "run_id", "mode", "V", "T", "M"), where)
    if record["record"] != "run_begin" or record["schema"] != SCHEMA:
        raise ValidationError(f"{where}: first record must be run_begin with schema {SCHEMA!r}")
    run_id = _string(record, "run_id", where)
    return run_id, _identity(record, where)


def _validate_frame(record: dict[str, Any], line: int, expected: tuple[str, int, int, int]) -> None:
    where = f"line {line}"
    _required(record, ("record", "run_id", "frame", "mode", "V", "T", "M", "cycles", "phases", "frame_latency_cycles", "crc", "status"), where)
    if record["record"] != "frame":
        raise ValidationError(f"{where}: expected frame record")
    if _identity(record, where) != expected:
        raise ValidationError(f"{where}: mode/V/T/M differs from run_begin")
    _uint(record["frame"], f"{where}.frame")
    _cycles(_obj(record["cycles"], f"{where}.cycles"), f"{where}.cycles")
    phases = _obj(record["phases"], f"{where}.phases")
    for phase in PHASES:
        _uint(phases.get(phase), f"{where}.phases.{phase}")
    _uint(record["frame_latency_cycles"], f"{where}.frame_latency_cycles")
    crc = record["crc"]
    if not ((isinstance(crc, int) and not isinstance(crc, bool) and 0 <= crc <= 0xFFFFFFFF) or (isinstance(crc, str) and HEX_CRC.fullmatch(crc))):
        raise ValidationError(f"{where}.crc: expected uint32 or hexadecimal string")
    status = _string(record, "status", where)
    if status not in STATUSES:
        raise ValidationError(f"{where}.status: expected one of {sorted(STATUSES)}")


def validate(path: Path) -> int:
    errors: list[str] = []
    begin: dict[str, Any] | None = None
    expected: tuple[str, int, int, int] | None = None
    run_id: str | None = None
    frame_count = 0
    frame_statuses: list[str] = []
    end: dict[str, Any] | None = None
    try:
        with path.open(encoding="utf-8") as stream:
            for line, raw in enumerate(stream, 1):
                if not raw.strip():
                    continue
                try:
                    record = _obj(json.loads(raw), f"line {line}")
                    kind = record.get("record")
                    if begin is None:
                        run_id, expected = _validate_begin(record, line)
                        begin = record
                        continue
                    if end is not None:
                        raise ValidationError("records are not allowed after run_end")
                    if record.get("run_id") != run_id:
                        raise ValidationError(f"line {line}: run_id differs from run_begin")
                    if kind == "frame":
                        assert expected is not None
                        _validate_frame(record, line, expected)
                        if record["frame"] != frame_count:
                            raise ValidationError(f"line {line}.frame: expected {frame_count}, got {record['frame']}")
                        frame_count += 1
                        frame_statuses.append(record["status"])
                    elif kind == "run_end":
                        _required(record, ("record", "schema", "run_id", "frames", "status"), f"line {line}")
                        if record["schema"] != SCHEMA:
                            raise ValidationError(f"line {line}.schema: expected {SCHEMA!r}")
                        if _uint(record["frames"], f"line {line}.frames") != frame_count:
                            raise ValidationError(f"line {line}.frames: does not match {frame_count} frame records")
                        status = _string(record, "status", f"line {line}")
                        if status not in STATUSES:
                            raise ValidationError(f"line {line}.status: expected one of {sorted(STATUSES)}")
                        expected_status = "error" if "error" in frame_statuses else ("fail" if "fail" in frame_statuses else "pass")
                        if status != expected_status:
                            raise ValidationError(f"line {line}.status: expected {expected_status!r} for frame statuses")
                        end = record
                    else:
                        raise ValidationError(f"line {line}: unknown record {kind!r}")
                except (json.JSONDecodeError, ValidationError) as exc:
                    errors.append(str(exc))
    except OSError as exc:
        errors.append(str(exc))
    if begin is None:
        errors.append("no run_begin record")
    if end is None:
        errors.append("no run_end record")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"VALID: {path} ({frame_count} frames, run_id={run_id})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate 3D benchmark JSONL schema v1")
    parser.add_argument("jsonl", type=Path)
    args = parser.parse_args()
    return validate(args.jsonl)


if __name__ == "__main__":
    raise SystemExit(main())
