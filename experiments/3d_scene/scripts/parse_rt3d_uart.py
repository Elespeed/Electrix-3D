#!/usr/bin/env python3
"""Convert RT3D JSON UART records from a Verilator transcript into JSONL."""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

PREFIX = "RT3D JSON "
def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("transcript", type=Path); ap.add_argument("--output", type=Path, required=True); args = ap.parse_args()
    records = []
    for line in args.transcript.read_text(encoding="utf-8", errors="replace").splitlines():
        at = line.find(PREFIX)
        if at >= 0:
            try: records.append(json.loads(line[at + len(PREFIX):]))
            except json.JSONDecodeError as exc: raise SystemExit(f"malformed RT3D JSON: {exc}")
    if not records: raise SystemExit("no RT3D JSON records found; rerun with RUN_ARGS=+UART_ECHO")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(json.dumps(x, sort_keys=True) for x in records) + "\n", encoding="utf-8")
    print(f"wrote {len(records)} records to {args.output}")
    return 0
if __name__ == "__main__": raise SystemExit(main())
