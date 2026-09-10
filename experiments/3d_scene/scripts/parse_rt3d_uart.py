#!/usr/bin/env python3
"""Convert RT3D JSON UART records from a Verilator transcript into JSONL."""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

PREFIX = "RT3D JSON "
FRAME_RE = re.compile(r"RT3D FRAME mode=(?P<mode>CPU_ONLY|CPU_MATMUL|SCENE_CONTROLLER) rep=(?P<rep>\d+) frame=(?P<frame>\d+) err=(?P<err>\d+) cmd=(?P<cmd>[0-9a-fA-F]+)")
CRC_RE = re.compile(r"\[DVI_MON\]\[CRC\]\s+(?:(?:named=(?P<label>\S+)\s+)?frame=(?P<frame>\d+)\s+crc=(?P<crc>[0-9a-fA-F]+)\s+width=(?P<width>\d+)\s+height=(?P<height>\d+))")
SAVE_RE = re.compile(r"\[DVI_MON\]\s+file saved to:\s+(?P<path>.+?)\s*$")
MODEL_DIMS = {"S0": (16, 24, 1), "S1": (32, 48, 1), "S2": (64, 96, 1), "S3": (96, 144, 1), "S4": (128, 192, 1)}

def compact_frame(match, model):
    if model not in MODEL_DIMS: raise SystemExit("--model is required for compact RT3D FRAME records")
    v, t, meshes = MODEL_DIMS[model]; error = int(match["err"])
    return {"record":"frame","schema":"scene-controller-experiment/v1","run_id":"firmware","mode":match["mode"],"rep":int(match["rep"]),"frame":int(match["frame"]),"asset":{"id":model,"sha256":"UNFROZEN","V":v,"T":t,"M":meshes},"config_hash":"UNFROZEN","cycles":{"active":0,"polling":0,"blocked":0,"wall":0,"latency_ns":0},"scene":{"load_bytes":0,"axi_transactions":0,"transform_cycles":0,"cull_cycles":0,"sort_cycles":0,"command_cycles":0,"input_triangles":t,"culled_triangles":0,"output_triangles":t,"command_crc":int(match["cmd"],16),"frame_crc":0},"rtos":{"idle_rate_permille":0,"background_units":0},"equivalence":"PENDING","error":"MATRIX_ERROR" if error else "NONE","timeout":False,"status":"FAIL" if error else "PASS"}

def attach_display_evidence(records, crc_events, save_paths):
    """Attach the completed monitor frame to the UART record it follows.

    Firmware prints its JSON before waiting for the vblank-completed capture.
    Therefore the first CRC after a record is the corresponding live frame;
    a later named CRC is preferred because it is the stable evidence capture.
    """
    for index, record in enumerate(records):
        next_order = records[index + 1]["_parse_order"] if index + 1 < len(records) else None
        following = [event for event in crc_events
                     if event["order"] > record["_parse_order"] and
                     (next_order is None or event["order"] < next_order)]
        if not following:
            continue
        named = [event for event in following if event.get("label")]
        event = named[0] if named else following[0]
        scene = record.setdefault("scene", {})
        scene["frame_crc"] = int(event["crc"], 16)
        record["display"] = {"frame": event["frame"], "width": event["width"], "height": event["height"], "crc": scene["frame_crc"]}
        # Named captures print "file saved" immediately before their named
        # CRC; automatic captures print it immediately after the CRC.
        paths = ([path for order, path in save_paths if order <= event["order"]][-1:]
                 if event.get("label") else
                 [path for order, path in save_paths if order >= event["order"]][:1])
        if paths:
            record["display"]["ppm"] = paths[0]

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("transcript", type=Path); ap.add_argument("--output", type=Path, required=True); ap.add_argument("--model", choices=sorted(MODEL_DIMS)); args = ap.parse_args()
    records = []; crc_events = []; save_paths = []
    for order, line in enumerate(args.transcript.read_text(encoding="utf-8", errors="replace").splitlines()):
        at = line.find(PREFIX)
        if at >= 0:
            try:
                record = json.loads(line[at + len(PREFIX):]); record["_parse_order"] = order; records.append(record)
            except json.JSONDecodeError as exc: raise SystemExit(f"malformed RT3D JSON: {exc}")
        frame_match = FRAME_RE.search(line)
        if frame_match:
            record = compact_frame(frame_match, args.model); record["_parse_order"] = order; records.append(record)
        match = CRC_RE.search(line)
        if match:
            crc_events.append({"order": order, **match.groupdict()})
        match = SAVE_RE.search(line)
        if match:
            save_paths.append((order, match.group("path")))
    if not records: raise SystemExit("no RT3D frame records found; rerun with RUN_ARGS=+UART_ECHO")
    attach_display_evidence(records, crc_events, save_paths)
    for record in records: record.pop("_parse_order", None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(json.dumps(x, sort_keys=True) for x in records) + "\n", encoding="utf-8")
    print(f"wrote {len(records)} records to {args.output}")
    return 0
if __name__ == "__main__": raise SystemExit(main())
