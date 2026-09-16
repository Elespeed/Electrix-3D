"""Produce traceable descriptive statistics from the 4-frame pilot runs.

This is deliberately not a formal-experiment aggregator: the frozen protocol
requires 5 x 300 frames, which the available data do not contain.  The script
therefore labels the observed maximum as a conservative repeat-cycle P99 proxy
instead of claiming a measured P99.
"""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path
from statistics import mean, median, stdev


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
RUNS = {
    "S0": "PILOT-S0-4F-v3",
    "S1": "PILOT-S1-4F-20260912",
    "S2": "PILOT-S2-4F-20260912",
    "S3": "PILOT-S3-4F-20260912",
    "S4": "PILOT-S4-4F-20260912",
}
MODES = ("CPU_ONLY", "CPU_MATMUL", "SCENE_CONTROLLER")
MODE_CN = {"CPU_ONLY": "CPU全软件", "CPU_MATMUL": "矩阵卸载", "SCENE_CONTROLLER": "帧级卸载"}


def nearest_rank(values: list[float], q: float) -> float:
    """Nearest-rank percentile, as specified by the frozen protocol."""
    values = sorted(values)
    return values[max(0, math.ceil(q * len(values)) - 1)]


def load_rows(scale: str, mode: str) -> list[dict]:
    path = ROOT / "experiments" / "3d_scene" / "runs" / RUNS[scale] / mode / scale / "validated" / "frames.jsonl"
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert all(r["status"] == "PASS" and r["error"] == "NONE" and not r["timeout"] for r in rows), path
    return rows


def describe(rows: list[dict]) -> dict:
    active = [r["cycles"]["active"] for r in rows]
    latency = [r["cycles"]["latency_ns"] for r in rows]
    idle = [r["rtos"]["idle_rate_permille"] / 10 for r in rows]
    background = [r["rtos"]["background_units_per_second"] for r in rows]
    # Four frames cannot measure the protocol P99.  If the observed 4-frame
    # cycle is repeated to 1500 frames, the nearest-rank P99 is its maximum.
    return {
        "n_observed": len(rows),
        "active_mean": mean(active), "active_sd": stdev(active) if len(active) > 1 else 0,
        "active_median": median(active), "active_p95": nearest_rank(active, .95), "active_max": max(active),
        "latency_median_ns": median(latency), "latency_p95_ns": nearest_rank(latency, .95),
        "latency_max_ns": max(latency), "p99_proxy_ns": max(latency),
        "budget_over_observed": sum(x > 33_333_333 for x in latency),
        "idle_rate_mean_pct": mean(idle), "background_units_per_second_mean": mean(background),
    }


def main() -> None:
    all_rows: list[dict] = []
    stats: dict[str, dict[str, dict]] = {}
    for scale in RUNS:
        stats[scale] = {}
        for mode in MODES:
            rows = load_rows(scale, mode)
            stats[scale][mode] = describe(rows)
            for row in rows:
                all_rows.append({
                    "scale": scale, "run_id": RUNS[scale], "mode": mode, "frame": row["frame"],
                    "active_cycles": row["cycles"]["active"], "blocked_cycles": row["cycles"]["blocked"],
                    "wall_cycles": row["cycles"]["wall"], "latency_ns": row["cycles"]["latency_ns"],
                    "idle_rate_permille": row["rtos"]["idle_rate_permille"],
                    "background_units_per_second": row["rtos"]["background_units_per_second"],
                    "framebuffer_crc": row["display"]["crc"], "status": row["status"],
                    "error": row["error"], "timeout": row["timeout"],
                })

    with (OUT / "pilot_frame_records.csv").open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=all_rows[0].keys())
        writer.writeheader(); writer.writerows(all_rows)
    (OUT / "pilot_descriptive_statistics.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# 论文数据包：4帧先导实验的描述性统计与短跑外推", "",
        "## 使用边界", "",
        "- 数据源：`experiments/3d_scene/runs/PILOT-S0-4F-v3` 与 `PILOT-S1...S4-4F-20260912` 的 `validated/frames.jsonl`。",
        "- 每个规模点/方案仅有 4 个 PASS 帧，均为先导样本；不满足冻结协议规定的 5×300 帧正式统计。",
        "- 因此本文档中的“P99代理”不是实测 P99：将已观测 4 帧视为可重复循环，扩展至 1,500 帧后按最近秩法得到的保守最大值。论文应写为“短跑外推的保守 P99 代理值”，不能写成正式 P99。",
        "- 所有帧均 `status=PASS`、`error=NONE`、`timeout=false`；但本批 Scene Controller 与另外两种方案除首帧外的 framebuffer CRC 不一致，不能将本批性能数据表述为三方案逐帧输出等价验证。",
        "",
        "## 表 A：各规模点的核心填写数据", "",
        "|规模|方案|样本 n|active 中位数 (cycles)|active 均值±SD|帧延迟中位数 (ms)|P99代理 (ms)|观测超预算帧|RTOS 空闲率均值|后台吞吐 (units/s)|",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for scale in RUNS:
        for mode in MODES:
            s = stats[scale][mode]
            lines.append(f"|{scale}|{MODE_CN[mode]}|{s['n_observed']}|{s['active_median']:.0f}|{s['active_mean']:.1f}±{s['active_sd']:.1f}|{s['latency_median_ns']/1e6:.3f}|{s['p99_proxy_ns']/1e6:.3f}|{s['budget_over_observed']}/{s['n_observed']}|{s['idle_rate_mean_pct']:.2f}%|{s['background_units_per_second_mean']:.1f}|")
    lines += ["", "## 表 B：帧级卸载相对矩阵卸载", "", "|规模|active 降幅|延迟中位数变化|P99代理变化|短跑结论|", "|---|---:|---:|---:|---|"]
    for scale in RUNS:
        m, sc = stats[scale]["CPU_MATMUL"], stats[scale]["SCENE_CONTROLLER"]
        active_reduction = 1 - sc["active_median"] / m["active_median"]
        latency_change = sc["latency_median_ns"] / m["latency_median_ns"] - 1
        p99_change = sc["p99_proxy_ns"] / m["p99_proxy_ns"] - 1
        conclusion = "满足三项代理门槛" if (active_reduction >= .3 and p99_change <= .1 and sc["p99_proxy_ns"] <= 33_333_333) else "不满足代理门槛"
        lines.append(f"|{scale}|{active_reduction:.2%}|{latency_change:.2%}|{p99_change:.2%}|{conclusion}|")
    lines += ["", "## 可直接填入论文表 4 的 S4 行（短跑外推版）", "", "", "|指标|CPU全软件|矩阵卸载|帧级卸载|", "|---|---:|---:|---:|", f"|active cycles 中位数|{stats['S4']['CPU_ONLY']['active_median']:.0f}|{stats['S4']['CPU_MATMUL']['active_median']:.0f}|{stats['S4']['SCENE_CONTROLLER']['active_median']:.0f}|", f"|P99代理帧延迟/ms|{stats['S4']['CPU_ONLY']['p99_proxy_ns']/1e6:.3f}|{stats['S4']['CPU_MATMUL']['p99_proxy_ns']/1e6:.3f}|{stats['S4']['SCENE_CONTROLLER']['p99_proxy_ns']/1e6:.3f}|", f"|RTOS空闲率均值/%|{stats['S4']['CPU_ONLY']['idle_rate_mean_pct']:.2f}|{stats['S4']['CPU_MATMUL']['idle_rate_mean_pct']:.2f}|{stats['S4']['SCENE_CONTROLLER']['idle_rate_mean_pct']:.2f}|", "|等价帧数|0（本批无三方案逐帧CRC等价）|0（本批无三方案逐帧CRC等价）|0（本批无三方案逐帧CRC等价）|", "", "## 文件说明", "", "- `pilot_frame_records.csv`：60 条逐帧原始记录的扁平化副本。", "- `pilot_descriptive_statistics.json`：机器可读的完整统计量。", "- 本文档：论文填写表、计算口径与不可跨越的证据边界。", ""]
    (OUT / "论文填写数据包.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
