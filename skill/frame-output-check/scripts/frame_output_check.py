from __future__ import annotations

import argparse
import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image


@dataclass(frozen=True)
class Probe:
    name: str
    x: int
    y: int


@dataclass(frozen=True)
class Region:
    name: str
    x0: int
    y0: int
    x1: int
    y1: int


MCU_PROBES = (
    Probe("title_green_bar", 400, 40),
    Probe("left_tile_center", 100, 320),
    Probe("right_tile_center", 600, 320),
    Probe("left_focus_probe", 60, 140),
    Probe("right_focus_probe", 500, 140),
)

MCU_REGIONS = (
    Region("title_band", 250, 20, 550, 80),
    Region("left_tile", 40, 130, 320, 390),
    Region("right_tile", 470, 130, 750, 390),
)


def rgb_tuple(pixel: tuple[int, ...]) -> tuple[int, int, int]:
    if len(pixel) >= 3:
        return int(pixel[0]), int(pixel[1]), int(pixel[2])
    value = int(pixel[0])
    return value, value, value


def load_image(path: Path) -> tuple[Image.Image, Path | None]:
    image = Image.open(path).convert("RGB")
    generated_png = None
    if path.suffix.lower() == ".ppm":
        generated_png = path.with_suffix(".png")
        image.save(generated_png)
    return image, generated_png


def mean_rgb(image: Image.Image, region: Region) -> tuple[int, int, int]:
    crop = image.crop((region.x0, region.y0, region.x1, region.y1))
    pixels = list(crop.getdata())
    total = len(pixels) or 1
    r = sum(p[0] for p in pixels) // total
    g = sum(p[1] for p in pixels) // total
    b = sum(p[2] for p in pixels) // total
    return r, g, b


def top_colors(image: Image.Image, limit: int = 6) -> list[dict]:
    counter = Counter(image.getdata())
    return [
        {"rgb": list(map(int, color)), "count": int(count)}
        for color, count in counter.most_common(limit)
    ]


def non_black_ratio(image: Image.Image) -> float:
    pixels = image.getdata()
    total = image.width * image.height
    non_black = sum(1 for pixel in pixels if pixel != (0, 0, 0))
    return round(non_black / total, 6) if total else 0.0


def summarize_image(path: Path) -> dict:
    image, generated_png = load_image(path)
    probes = {
        probe.name: list(rgb_tuple(image.getpixel((probe.x, probe.y))))
        for probe in MCU_PROBES
        if probe.x < image.width and probe.y < image.height
    }
    regions = {
        region.name: list(mean_rgb(image, region))
        for region in MCU_REGIONS
        if region.x1 <= image.width and region.y1 <= image.height
    }
    return {
        "path": str(path),
        "generated_png": str(generated_png) if generated_png else None,
        "width": image.width,
        "height": image.height,
        "non_black_ratio": non_black_ratio(image),
        "top_colors": top_colors(image),
        "probes": probes,
        "regions": regions,
    }


def diff_images(left: Path, right: Path) -> dict:
    left_image, _ = load_image(left)
    right_image, _ = load_image(right)
    if left_image.size != right_image.size:
        return {
            "left": str(left),
            "right": str(right),
            "same_size": False,
            "left_size": list(left_image.size),
            "right_size": list(right_image.size),
        }

    total = left_image.width * left_image.height
    changed = 0
    abs_delta = 0
    left_pixels = list(left_image.getdata())
    right_pixels = list(right_image.getdata())
    for lp, rp in zip(left_pixels, right_pixels):
        if lp != rp:
            changed += 1
            abs_delta += abs(lp[0] - rp[0]) + abs(lp[1] - rp[1]) + abs(lp[2] - rp[2])

    probe_diffs = {}
    for probe in MCU_PROBES:
        if probe.x < left_image.width and probe.y < left_image.height:
            lp = rgb_tuple(left_image.getpixel((probe.x, probe.y)))
            rp = rgb_tuple(right_image.getpixel((probe.x, probe.y)))
            probe_diffs[probe.name] = {
                "left": list(lp),
                "right": list(rp),
                "changed": lp != rp,
            }

    return {
        "left": str(left),
        "right": str(right),
        "same_size": True,
        "changed_pixels": changed,
        "changed_ratio": round(changed / total, 6) if total else 0.0,
        "mean_abs_channel_delta": round(abs_delta / (total * 3), 4) if total else 0.0,
        "probe_diffs": probe_diffs,
    }


def sorted_inputs(paths: Iterable[str]) -> list[Path]:
    resolved: list[Path] = []
    for pattern in paths:
        expanded = list(Path().glob(pattern)) if any(ch in pattern for ch in "*?[]") else [Path(pattern)]
        for candidate in expanded:
            if candidate.is_file():
                resolved.append(candidate)
    return sorted(set(path.resolve() for path in resolved))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Summarize framebuffer output images for display validation.")
    parser.add_argument("images", nargs="+", help="PPM or PNG images to summarize. Wildcards are allowed.")
    parser.add_argument("--compare", action="store_true", help="Compare adjacent images in the given order.")
    parser.add_argument("--json-out", help="Write the full JSON report to this file.")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    images = sorted_inputs(args.images)
    if not images:
        raise SystemExit("No input images matched.")

    report = {
        "images": [summarize_image(path) for path in images],
        "comparisons": [],
    }
    if args.compare and len(images) >= 2:
        report["comparisons"] = [
            diff_images(images[idx], images[idx + 1])
            for idx in range(len(images) - 1)
        ]

    payload = json.dumps(report, indent=2, ensure_ascii=False)
    print(payload)
    if args.json_out:
        Path(args.json_out).write_text(payload + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
