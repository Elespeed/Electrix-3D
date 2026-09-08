#!/usr/bin/env python3
"""Check command/frame CRCs against an approved, versioned golden manifest."""
from __future__ import annotations
import argparse, json
from pathlib import Path
def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("jsonl",type=Path); ap.add_argument("--goldens",type=Path,required=True); ap.add_argument("--output",type=Path,required=True); args=ap.parse_args()
    golden=json.loads(args.goldens.read_text(encoding="utf-8"))
    if golden.get("status") != "APPROVED":
        raise SystemExit(f"REFUSED: golden manifest status is {golden.get('status')!r}; expected 'APPROVED'")
    table=golden.get("frames",{})
    checked=[]; failures=[]
    for raw in args.jsonl.read_text(encoding="utf-8").splitlines():
        if not raw.strip(): continue
        row=json.loads(raw); key=f"{row['asset']['id']}/{(row['frame']-1)%16}"
        want=table.get(key)
        if want is None: failures.append({"key":key,"reason":"missing_golden"}); row["equivalence"]="FAIL"
        elif want["command_crc"] != row["scene"]["command_crc"] or want["frame_crc"] != row["scene"]["frame_crc"]:
            failures.append({"key":key,"reason":"crc_mismatch","expected":want,"actual":row["scene"]}); row["equivalence"]="FAIL"
        else: row["equivalence"]="PASS"
        checked.append(row)
    args.output.write_text("\n".join(json.dumps(x,sort_keys=True) for x in checked)+"\n",encoding="utf-8")
    print(json.dumps({"checked":len(checked),"failures":failures},indent=2))
    return 1 if failures else 0
if __name__ == "__main__": raise SystemExit(main())
