"""Render publication-ready SVG/PNG figures from the pilot statistics."""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


OUT = Path(__file__).resolve().parent / "figures"
STATS = json.loads((Path(__file__).resolve().parent / "pilot_descriptive_statistics.json").read_text(encoding="utf-8"))
SCALES = ["S0", "S1", "S2", "S3", "S4"]
MODES = ["CPU_ONLY", "CPU_MATMUL", "SCENE_CONTROLLER"]
COLORS = {"CPU_ONLY": "#4C78A8", "CPU_MATMUL": "#F58518", "SCENE_CONTROLLER": "#54A24B"}
LABELS = {"CPU_ONLY": "CPU-only", "CPU_MATMUL": "Matrix offload", "SCENE_CONTROLLER": "Frame-level offload"}


def finish(fig: plt.Figure, name: str) -> None:
    OUT.mkdir(exist_ok=True)
    fig.savefig(OUT / f"{name}.svg", bbox_inches="tight")
    fig.savefig(OUT / f"{name}.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def active_cycles() -> None:
    fig, ax = plt.subplots(figsize=(6.6, 3.65), constrained_layout=True)
    for mode in MODES:
        values = [STATS[s][mode]["active_median"] for s in SCALES]
        ax.plot(SCALES, values, marker="o", linewidth=2, markersize=5, color=COLORS[mode], label=LABELS[mode])
    ax.set_yscale("log")
    ax.set_ylabel("Median CPU active cycles / frame (log scale)")
    ax.set_xlabel("Workload scale")
    ax.grid(True, which="both", axis="y", alpha=.25)
    ax.legend(ncol=3, loc="upper left", frameon=False, fontsize=8)
    finish(fig, "fig4_active_cycles")


def latency() -> None:
    fig, ax = plt.subplots(figsize=(6.6, 3.65), constrained_layout=True)
    for mode in MODES:
        values = [STATS[s][mode]["p99_proxy_ns"] / 1e6 for s in SCALES]
        ax.plot(SCALES, values, marker="o", linewidth=2, markersize=5, color=COLORS[mode], label=LABELS[mode])
    ax.axhline(33.333, color="#E45756", linestyle="--", linewidth=1.5, label="33.333 ms budget")
    ax.set_ylabel("Conservative P99 proxy latency (ms)")
    ax.set_xlabel("Workload scale")
    ax.set_ylim(0, 85)
    ax.grid(True, axis="y", alpha=.25)
    ax.legend(ncol=2, loc="upper left", frameon=False, fontsize=8)
    finish(fig, "fig5_latency_proxy")


def resources() -> None:
    labels = ["LUT", "FF", "BRAM", "DSP", "LUTRAM"]
    values = [31.75, 14.79, 23.29, 5.41, .83]
    fig, ax = plt.subplots(figsize=(6.1, 3.55), constrained_layout=True)
    bars = ax.bar(labels, values, color=["#4C78A8", "#72B7B2", "#F58518", "#54A24B", "#B279A2"], width=.63)
    ax.set_ylabel("Utilization (%)")
    ax.set_ylim(0, 38)
    ax.grid(True, axis="y", alpha=.25)
    for bar, val in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width()/2, val + .75, f"{val:.2f}%", ha="center", va="bottom", fontsize=9)
    finish(fig, "fig6_resource_utilization")


if __name__ == "__main__":
    active_cycles(); latency(); resources()
