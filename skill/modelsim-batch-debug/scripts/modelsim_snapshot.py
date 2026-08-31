#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from manifest_utils import DEFAULT_MODELSIM_ROOT, default_manifest_path, load_manifest, resolve_profiles, snapshot_signals, unique_ordered


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect a compact ModelSim state snapshot at a specific time.")
    parser.add_argument("--modelsim-root", default=str(DEFAULT_MODELSIM_ROOT))
    parser.add_argument("--manifest")
    parser.add_argument("--tb", required=True)
    parser.add_argument("--time", required=True)
    parser.add_argument("--phase")
    parser.add_argument("--profile", action="append", default=[])
    parser.add_argument("--signal", action="append", default=[])
    parser.add_argument("--out")
    parser.add_argument("--extra-var", action="append", default=[])
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    modelsim_root = Path(args.modelsim_root).resolve()
    manifest_path = Path(args.manifest).resolve() if args.manifest else default_manifest_path(modelsim_root).resolve()
    manifest = load_manifest(manifest_path)
    selected_profiles = resolve_profiles(manifest, args.tb, args.phase, args.profile)
    signals = snapshot_signals(manifest, args.tb, args.phase, selected_profiles) + args.signal
    signals = unique_ordered([signal for signal in signals if signal])
    if not signals:
        print(json.dumps({"ok": False, "error": {"code": "NO_SIGNALS", "message": "No snapshot signals were resolved"}}))
        sys.exit(1)

    with tempfile.TemporaryDirectory(prefix="modelsim_snapshot_") as tmp_dir_name:
        tmp_dir = Path(tmp_dir_name)
        signal_file = tmp_dir / "signals.lst"
        out_file = Path(args.out).resolve() if args.out else (tmp_dir / "snapshot.json")
        signal_file.write_text("\n".join(signals) + "\n", encoding="utf-8")

        command = [
            "make",
            "-C",
            str(modelsim_root),
            f"TB={args.tb}",
            f"SNAPSHOT_TIME={args.time}",
            f"SNAPSHOT_SIGNALS_FILE={signal_file}",
            f"SNAPSHOT_OUT={out_file}",
            "snapshot",
        ]
        command.extend(args.extra_var)
        proc = subprocess.run(command, capture_output=True, text=True, shell=False)

        payload = {
            "ok": proc.returncode == 0 and out_file.exists(),
            "tb": args.tb,
            "time": args.time,
            "phase": args.phase,
            "selected_profiles": selected_profiles,
            "signal_count": len(signals),
            "snapshot_file": str(out_file),
            "stdout_tail": proc.stdout.splitlines()[-20:],
            "stderr_tail": proc.stderr.splitlines()[-20:],
        }
        if out_file.exists():
            payload["snapshot"] = json.loads(out_file.read_text(encoding="utf-8"))
        print(json.dumps(payload, indent=2))
        sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
