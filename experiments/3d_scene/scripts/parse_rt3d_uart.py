#!/usr/bin/env python3
"""Convert RT3D JSON UART records from a Verilator transcript into JSONL."""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

PREFIX = "RT3D JSON "
FRAME_RE = re.compile(r"RT3D (?P<kind>FRAME|CYC|SCENE|STAGE|STAGE2|TRI|CRC|RTOS|RATE|HASH|CFG) (?P<body>.*)$")
CRC_RE = re.compile(r"\[DVI_MON\]\[CRC\]\s+(?:(?:named=(?P<label>\S+)\s+)?frame=(?P<frame>\d+)\s+crc=(?P<crc>[0-9a-fA-F]+)\s+width=(?P<width>\d+)\s+height=(?P<height>\d+))")
SAVE_RE = re.compile(r"\[DVI_MON\]\s+file saved to:\s+(?P<path>.+?)\s*$")
MODEL_DIMS = {"S0": (16, 24, 1), "S1": (32, 48, 1), "S2": (64, 96, 1), "S3": (96, 144, 1), "S4": (128, 192, 1)}

def compact_frame(match, model, manifest=None):
    if model not in MODEL_DIMS: raise SystemExit("--model is required for compact RT3D FRAME records")
    body = match["body"] if isinstance(match, dict) else match.group("body")
    fields = dict(item.split("=", 1) for item in body.split() if "=" in item)
    # In Verilator runs with DVI frame dumping enabled, stdout from the monitor
    # can interleave one UART fragment.  Firmware deliberately emits zero for
    # this placeholder; attach_display_evidence() replaces it with the first
    # completed DVI CRC following this record.  Do not discard a valid frame
    # merely because that reconstructible diagnostic fragment was interrupted.
    fields.setdefault("frame_crc", "0")
    try:
        nums = {k: int(fields[k], 16 if k in ("cmd", "frame_crc") else 10) for k in ("rep","frame","err","cmd","active","polling","blocked","wall","latency_ns","load_bytes","axi_transactions","transform_cycles","cull_cycles","sort_cycles","command_cycles","input_triangles","culled_triangles","output_triangles","frame_crc","idle_rate_permille","background_units","background_units_per_second")}
    except (KeyError, ValueError) as exc: raise SystemExit(f"incomplete RT3D FRAME record: {exc}")
    v,t,meshes=MODEL_DIMS[model]; manifest=manifest or {}
    asset_sha=fields.get("sha",manifest.get("asset_sha256","UNFROZEN")); cfg=fields.get("cfg",manifest.get("config_sha256","UNFROZEN"))
    return {"record":"frame","schema":"scene-controller-experiment/v1","run_id":manifest.get("run_id","firmware"),"mode":fields["mode"],"rep":nums["rep"],"frame":nums["frame"],"asset":{"id":fields.get("asset",model),"sha256":asset_sha,"V":int(fields.get("V",v)),"T":int(fields.get("T",t)),"M":int(fields.get("M",meshes))},"config_hash":cfg,"cycles":{k:nums[k] for k in ("active","polling","blocked","wall","latency_ns")},"scene":{k:nums[k] for k in ("load_bytes","axi_transactions","transform_cycles","cull_cycles","sort_cycles","command_cycles","input_triangles","culled_triangles","output_triangles")}|{"command_crc":nums["cmd"],"frame_crc":nums["frame_crc"]},"rtos":{k:nums[k] for k in ("idle_rate_permille","background_units","background_units_per_second")},"error":"MATRIX_ERROR" if nums["err"] else "NONE","timeout":False,"status":"FAIL" if nums["err"] else "PASS"}

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
    ap = argparse.ArgumentParser(); ap.add_argument("transcript", type=Path); ap.add_argument("--output", type=Path, required=True); ap.add_argument("--model", choices=sorted(MODEL_DIMS)); ap.add_argument("--manifest", type=Path); args = ap.parse_args()
    manifest_path = args.manifest or args.output.parent.parent / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else None
    records = []; crc_events = []; save_paths = []; pending = {}
    for order, line in enumerate(args.transcript.read_text(encoding="utf-8", errors="replace").splitlines()):
        at = line.find(PREFIX)
        if at >= 0:
            try:
                record = json.loads(line[at + len(PREFIX):]); record["_parse_order"] = order; records.append(record)
            except json.JSONDecodeError as exc: raise SystemExit(f"malformed RT3D JSON: {exc}")
        frame_match = FRAME_RE.search(line)
        if frame_match:
            # Firmware fragments records to fit RT_CONSOLEBUF_SIZE. Join all
            # fragments using the stable repetition/frame key; CFG is last.
            frag = frame_match.group("body"); fields = dict(x.split("=",1) for x in frag.split() if "=" in x)
            kind = frame_match.group("kind")
            if kind == "FRAME":
                key=(fields.get("rep"),fields.get("frame")); pending[key]=frag
            elif kind != "FRAME":
                key=(fields.get("rep"),fields.get("frame")); pending.setdefault(key,""); pending[key] += " "+frag
                if kind == "CFG":
                    record = compact_frame({"body":pending.pop(key)}, args.model, manifest); record["_parse_order"] = order; records.append(record)
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
