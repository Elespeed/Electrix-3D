#!/usr/bin/env python3
"""Batch-render low-poly JSON assets with fixed offline 3D comparison profiles."""
from __future__ import annotations

import argparse
import json
from math import ceil, sqrt
import os
from pathlib import Path
import struct
import sys
import time
import zlib

from PIL import Image

from model import Model
from profiles import PROFILES, PROFILE_ALIASES, resolve_profile
from renderer import RenderConfig, render_sweep

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_ROOT = ROOT / "assets/3d/previews/frame"


def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload)) +
        tag +
        payload +
        struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    if len(pixels) != width * height * 3:
        raise ValueError("pixel buffer size does not match image dimensions")
    rows = []
    stride = width * 3
    for row in range(height):
        start = row * stride
        rows.append(b"\x00" + pixels[start:start + stride])
    payload = zlib.compress(b"".join(rows), level=9)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"".join((
        b"\x89PNG\r\n\x1a\n",
        _png_chunk(b"IHDR", header),
        _png_chunk(b"IDAT", payload),
        _png_chunk(b"IEND", b""),
    ))
    # Windows can transiently reject an in-place truncate while Explorer,
    # antivirus, or an image preview still has the prior frame open.  Write a
    # complete sibling first, then replace atomically; retry the replacement
    # briefly for the same external-handle race.
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(png)
    last_error: OSError | None = None
    for _ in range(5):
        try:
            os.replace(temporary, path)
            return
        except OSError as exc:
            last_error = exc
            time.sleep(0.05)
    if temporary.exists():
        temporary.unlink()
    assert last_error is not None
    raise last_error


def write_contact_sheet(path: Path, width: int, height: int, frames: list[bytes], background: str) -> None:
    count = len(frames)
    columns = max(1, int(ceil(sqrt(count))))
    rows = int(ceil(count / columns))
    sheet_width = columns * width
    sheet_height = rows * height
    bg = bytes((int(background[1:3], 16), int(background[3:5], 16), int(background[5:7], 16)))
    canvas = bytearray(bg * (sheet_width * sheet_height))
    for index, frame in enumerate(frames):
        tile_x = (index % columns) * width
        tile_y = (index // columns) * height
        for row in range(height):
            src_start = row * width * 3
            dst_start = ((tile_y + row) * sheet_width + tile_x) * 3
            canvas[dst_start:dst_start + width * 3] = frame[src_start:src_start + width * 3]
    write_png(path, sheet_width, sheet_height, bytes(canvas))


def write_gif(path: Path, width: int, height: int, frames: list[bytes], duration_ms: int = 80) -> None:
    """Write the rendered yaw sweep as a looping GIF without rereading PNGs."""
    if not frames:
        raise ValueError("cannot write GIF without frames")
    images = [Image.frombytes("RGB", (width, height), frame) for frame in frames]
    images[0].save(path, save_all=True, append_images=images[1:], duration=duration_ms, loop=0, disposal=2)


def build_output_dir(output_root: Path, model_path: Path, profile_name: str) -> Path:
    return output_root / model_path.stem / profile_name


def _parse_rgb_triplet(value: str) -> tuple[int, int, int]:
    parts = value.split(",")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("outline color must be R,G,B")
    try:
        channels = tuple(int(part) for part in parts)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("outline color must be R,G,B") from exc
    if any(channel < 0 or channel > 255 for channel in channels):
        raise argparse.ArgumentTypeError("outline color channels must be in 0..255")
    return channels


def _write_surface_debug(output_dir: Path, model: Model) -> None:
    shading = model.metadata.get("dynamic_surface_shading")
    if not isinstance(shading, dict):
        return
    surfaces = shading.get("surfaces")
    if not isinstance(surfaces, list):
        return
    (output_dir / "surfaces.json").write_text(
        json.dumps({"asset_name": model.name, "surfaces": surfaces}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    lines = [f"asset={model.name}", f"surface_count={len(surfaces)}"]
    for surface in surfaces:
        if not isinstance(surface, dict):
            continue
        lines.append(
            "surface_id={surface_id} face_count={face_count} normal={normal}".format(
                surface_id=surface.get("surface_id"),
                face_count=surface.get("face_count"),
                normal=surface.get("canonical_normal"),
            )
        )
    (output_dir / "surface_report.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path, help="input lowpoly JSON asset")
    parser.add_argument("--profile", default="no_zbuffer",
                        help="render profile name: no_zbuffer, zbuffer, or zbuffer_object_outline")
    parser.add_argument("--frame-width", type=int, default=400, help="output frame width in pixels")
    parser.add_argument("--frame-height", type=int, default=300, help="output frame height in pixels")
    parser.add_argument("--target-height", type=float, default=120.0, help="normalised model height in scene units")
    parser.add_argument("--preserve-scale", action="store_true",
                        help="render at the JSON asset's stored size instead of normalising it to --target-height")
    parser.add_argument("--yaw-steps", type=int, default=16, help="number of frames in one full yaw sweep")
    parser.add_argument("--background", default="#00FF00", help="background colour as #RRGGBB")
    parser.add_argument("--no-center", action="store_true", help="do not recenter the model after scaling")
    parser.add_argument("--dump-surfaces", action="store_true", help="write surface metadata reports alongside frames")
    parser.add_argument("--debug-surface-colors", action="store_true",
                        help="ignore material shading and assign each surface a stable debug colour")
    parser.add_argument("--debug-normals", action="store_true",
                        help="visualise canonical surface normals as RGB colours")
    parser.add_argument("--dump-object-ids", action="store_true", help="write object-id debug images alongside frames")
    parser.add_argument("--dump-outline-mask", action="store_true", help="write outline-mask debug images alongside frames")
    parser.add_argument("--outline-color", type=_parse_rgb_triplet, default=None, help="override outline colour as R,G,B")
    parser.add_argument("--no-silhouette-outline", action="store_true",
                        help="do not draw outlines against background pixels")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT,
                        help=f"base output directory (default: {DEFAULT_OUTPUT_ROOT})")
    args = parser.parse_args(argv)

    try:
        profile = resolve_profile(args.profile)
        enable_object_outline = profile.enable_object_outline or args.dump_object_ids or args.dump_outline_mask
        if enable_object_outline and not profile.use_zbuffer:
            raise ValueError("object outline requires a Z-buffer-enabled profile")
        model = Model.load(args.model)
        target_height = args.target_height
        if args.preserve_scale:
            min_y = min(vertex[1] for vertex in model.vertices)
            max_y = max(vertex[1] for vertex in model.vertices)
            target_height = max_y - min_y
            if target_height <= 0.0:
                raise ValueError("model height must be positive before rendering")
        config = RenderConfig(
            frame_width=args.frame_width,
            frame_height=args.frame_height,
            target_height=target_height,
            center=not args.no_center,
            yaw_steps=args.yaw_steps,
            background=args.background,
            profile=profile,
            output_root=args.output_root,
            debug_surface_colors=args.debug_surface_colors,
            debug_normals=args.debug_normals,
            enable_object_outline=enable_object_outline,
            outline_color=args.outline_color,
            include_silhouette=not args.no_silhouette_outline,
        )
        report = render_sweep(model, config)
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 1

    output_dir = build_output_dir(args.output_root, args.model, profile.name)
    output_dir.mkdir(parents=True, exist_ok=True)
    if args.dump_surfaces:
        _write_surface_debug(output_dir, model)
    object_table = model.metadata.get("object_table")
    if isinstance(object_table, list):
        (output_dir / "object_table.json").write_text(
            json.dumps({"asset_name": model.name, "object_table": object_table}, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    frame_buffers: list[bytes] = []
    for frame in report.frames:
        frame_path = output_dir / f"frame_{frame.yaw_index:04d}.png"
        write_png(frame_path, config.frame_width, config.frame_height, frame.pixels)
        frame_buffers.append(frame.pixels)
        if args.dump_object_ids and frame.object_id_debug_pixels is not None:
            write_png(
                output_dir / f"frame_{frame.yaw_index:04d}_object_ids.png",
                config.frame_width,
                config.frame_height,
                frame.object_id_debug_pixels,
            )
        if args.dump_outline_mask and frame.outline_mask_pixels is not None:
            write_png(
                output_dir / f"frame_{frame.yaw_index:04d}_outline_mask.png",
                config.frame_width,
                config.frame_height,
                frame.outline_mask_pixels,
            )
    write_contact_sheet(output_dir / "contact_sheet.png", config.frame_width, config.frame_height, frame_buffers, config.background)
    write_gif(output_dir / "animation.gif", config.frame_width, config.frame_height, frame_buffers)
    (output_dir / "frames.json").write_text(json.dumps(report.to_dict(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"Wrote {len(report.frames)} frames to {output_dir}")
    if args.preserve_scale:
        print(f"Preserved asset scale (model height {config.target_height:.6g} scene units)")
    print(f"Profiles: {', '.join(sorted(set(PROFILES) | set(PROFILE_ALIASES)))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
