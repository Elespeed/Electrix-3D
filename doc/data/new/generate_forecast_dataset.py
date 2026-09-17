"""Create a deterministic, clearly labelled synthetic 300-frame forecast dataset.

This utility is solely for preflighting data-processing and document layout.  It
does not run RTL, FPGA hardware, or any benchmark, and its output must not be
reported as an experiment measurement.
"""

from __future__ import annotations

import csv
import math
import random
from pathlib import Path


OUT = Path(__file__).parent / "forecast_300_frames.csv"
SEED = 20260913
FRAMES_PER_CONDITION = 300
LABEL = "FORECAST_SYNTHETIC_DO_NOT_USE_AS_MEASURED_RESULT"

# Centres are transparent scenario inputs informed by the 4-frame pilot
# narrative in the manuscript, not estimates produced by a fitted model.
# S3/S4 deliberately retain the pilot's marginal >33.333 ms scene latency.
CONDITIONS = {
    "S0": {
        "CPU_ONLY": (72_000, 17.90, 0.050, 0.030),
        "CPU_MATMUL": (61_500, 17.85, 0.050, 0.030),
        "SCENE_CONTROLLER": (1_730, 16.30, 0.015, 0.025),
    },
    "S1": {
        "CPU_ONLY": (190_000, 18.00, 0.050, 0.030),
        "CPU_MATMUL": (171_000, 17.95, 0.050, 0.030),
        "SCENE_CONTROLLER": (1_735, 18.10, 0.015, 0.025),
    },
    "S2": {
        "CPU_ONLY": (650_000, 31.80, 0.050, 0.030),
        "CPU_MATMUL": (595_000, 31.70, 0.050, 0.030),
        "SCENE_CONTROLLER": (1_755, 20.20, 0.015, 0.025),
    },
    "S3": {
        "CPU_ONLY": (1_320_000, 48.00, 0.045, 0.028),
        "CPU_MATMUL": (1_205_000, 47.70, 0.045, 0.028),
        "SCENE_CONTROLLER": (2_650, 34.74, 0.020, 0.018),
    },
    "S4": {
        "CPU_ONLY": (1_968_009, 75.823, 0.040, 0.025),
        "CPU_MATMUL": (1_863_108, 73.680, 0.040, 0.025),
        "SCENE_CONTROLLER": (3_405, 34.723, 0.020, 0.018),
    },
}


def positive_lognormal(rng: random.Random, centre: float, rel_sd: float) -> float:
    """Return a positive value with `centre` as an approximate median."""
    return centre * math.exp(rng.gauss(0.0, rel_sd))


def main() -> None:
    rng = random.Random(SEED)
    fields = [
        "record_class", "forecast_basis", "scale", "mode", "replicate",
        "frame", "active_cycles", "blocked_cycles", "wall_cycles",
        "latency_ns", "active_wall_pct", "equivalence_predicted", "status",
    ]
    with OUT.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for scale, modes in CONDITIONS.items():
            for mode, (active_centre, latency_ms_centre, active_sd, latency_sd) in modes.items():
                for frame in range(1, FRAMES_PER_CONDITION + 1):
                    active = max(1, round(positive_lognormal(rng, active_centre, active_sd)))
                    latency_ns = max(1, round(positive_lognormal(rng, latency_ms_centre, latency_sd) * 1_000_000))
                    wall = max(active, round(latency_ns * 33_000_000 / 1_000_000_000))
                    writer.writerow({
                        "record_class": LABEL,
                        "forecast_basis": "scenario_inputs_in_generate_forecast_dataset_py",
                        "scale": scale,
                        "mode": mode,
                        "replicate": "FORECAST_RUN_1",
                        "frame": frame,
                        "active_cycles": active,
                        "blocked_cycles": wall - active,
                        "wall_cycles": wall,
                        "latency_ns": latency_ns,
                        "active_wall_pct": f"{100 * active / wall:.6f}",
                        "equivalence_predicted": "NOT_VERIFIED",
                        "status": "FORECAST_ONLY",
                    })


if __name__ == "__main__":
    main()
