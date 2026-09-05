#!/usr/bin/env python3
"""Summarise valid Scene Controller frame records using nearest-rank percentiles."""
from __future__ import annotations
import argparse,json,math,statistics
from pathlib import Path
def percentile(values:list[int], p:float)->int:
    return sorted(values)[max(0, math.ceil(len(values)*p)-1)]
def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument("jsonl",type=Path); ap.add_argument("--output-dir",type=Path,required=True); args=ap.parse_args()
    rows=[json.loads(x) for x in args.jsonl.read_text(encoding="utf-8").splitlines() if x.strip()]
    valid=[r for r in rows if r["equivalence"]=="PASS" and r["error"]=="NONE" and r["timeout"] is False and r["status"]=="PASS"]
    metrics={}
    for name, getter in {"active_cycles":lambda r:r["cycles"]["active"],"frame_latency_ns":lambda r:r["cycles"]["latency_ns"],"idle_rate_permille":lambda r:r["rtos"]["idle_rate_permille"]}.items():
        values=[getter(r) for r in valid]
        if not values: continue
        mean=statistics.fmean(values); std=statistics.stdev(values) if len(values)>1 else 0.0; ci=1.96*std/math.sqrt(len(values))
        metrics[name]={"mean":mean,"median":statistics.median(values),"p95":percentile(values,.95),"p99":percentile(values,.99) if len(values)>=1500 else "INVALID","max":max(values),"ci95":[mean-ci,mean+ci]}
    report={"schema":"scene-controller-summary/v1","frames_total":len(rows),"frames_valid":len(valid),"frames_excluded":len(rows)-len(valid),"over_budget":sum(r["cycles"]["latency_ns"]>33333333 for r in valid),"metrics":metrics}
    args.output_dir.mkdir(parents=True,exist_ok=True); (args.output_dir/"summary.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    lines=["# Scene Controller summary","",f"Valid frames: {len(valid)}/{len(rows)}",""]+[f"- {key}: median={value['median']}, P99={value['p99']}, max={value['max']}" for key,value in metrics.items()]
    (args.output_dir/"report.md").write_text("\n".join(lines)+"\n",encoding="utf-8"); print(args.output_dir/"summary.json"); return 0
if __name__ == "__main__": raise SystemExit(main())
