#!/usr/bin/env python3
"""Render a pivot-driven in-place walk for the robotss OBJ asset.

This is deliberately an offline experiment.  It does not write SK3D/MIF
assets.  It renders the legacy OBJ/V3 preview and the generated V4 asset into
separate output directories.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import json
from math import cos, pi, sin
from pathlib import Path
import sys
from typing import Any

from PIL import Image, ImageDraw

TOOL_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = TOOL_ROOT.parents[1]
sys.path.insert(0, str(TOOL_ROOT))

from color_rgb332 import hex_to_rgb332, rgb332_to_hex
from importer_obj import import_obj
from model import Face, Model
from renderer import RenderConfig, render_frame
from static_shading import apply_static_face_shading

ASSET_ROOT = REPO_ROOT / "assets/3d/sources/robotss"
DEFAULT_OUTPUT = REPO_ROOT / "assets/3d/previews/robotss/articulation/out"
DEFAULT_V4_OUTPUT = REPO_ROOT / "assets/3d/previews/robotss/articulation/out_v4"
V3_ASSET_ROOT = REPO_ROOT / "assets/3d/generated/robotss/v3"
V4_ASSET_ROOT = REPO_ROOT / "assets/3d/generated/robotss/v4"
MOVING_PARTS = {"arm_l": 1.0, "leg_r": 1.0, "arm_r": -1.0, "leg_l": -1.0}
STATIC_PARTS = ("body", "face")
PARTS = tuple(MOVING_PARTS) + STATIC_PARTS
PIVOT_PARTS = tuple(MOVING_PARTS)


def _load_pivots(path: Path) -> dict[str, tuple[float, float, float]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    objects = document.get("objects")
    if not isinstance(objects, dict):
        raise ValueError("pivot JSON must contain an objects map")
    pivots: dict[str, tuple[float, float, float]] = {}
    # The body is deliberately static in this demo, so a body pivot is
    # optional.  Current robotss exports may contain a face pivot instead.
    for part in PIVOT_PARTS:
        value = objects.get(part, {}).get("obj_pivot")
        if not isinstance(value, list) or len(value) != 3:
            raise ValueError(f"pivot JSON is missing objects.{part}.obj_pivot")
        pivots[part] = tuple(float(component) for component in value)
    return pivots


def _part_for_group(group_name: str) -> str:
    """Map names such as ``arm_l_材质.003`` to their pivot key."""
    for part in PARTS:
        if group_name == part or group_name.startswith(part + "_"):
            return part
    raise ValueError(f"robotss OBJ group is not covered by the part map: {group_name!r}")


def build_vertex_part_map(model: Model) -> list[str]:
    owners: list[str | None] = [None] * len(model.vertices)
    for face in model.faces:
        group = face.extra.get("group")
        if not isinstance(group, str):
            raise ValueError("robotss faces must retain OBJ group metadata")
        part = _part_for_group(group)
        for vertex_index in face.indices:
            previous = owners[vertex_index]
            if previous is not None and previous != part:
                raise ValueError(f"vertex {vertex_index} belongs to both {previous} and {part}")
            owners[vertex_index] = part
    if any(owner is None for owner in owners):
        raise ValueError("robotss has a vertex without a part assignment")
    return [str(owner) for owner in owners]


def _roll_rotate(vertex: tuple[float, float, float], pivot: tuple[float, float, float], degrees: float) -> tuple[float, float, float]:
    """Rotate around OBJ +Z, matching Scene Controller roll convention."""
    radians = degrees * pi / 180.0
    x, y, z = (vertex[index] - pivot[index] for index in range(3))
    return (pivot[0] + x * cos(radians) - y * sin(radians), pivot[1] + x * sin(radians) + y * cos(radians), pivot[2] + z)


def pose_obj_model(base: Model, owners: list[str], pivots: dict[str, tuple[float, float, float]], frame_index: int, frame_count: int, amplitude_degrees: float) -> tuple[Model, dict[str, float]]:
    phase = 2.0 * pi * frame_index / frame_count
    angles = {part: amplitude_degrees * sin(phase) * direction for part, direction in MOVING_PARTS.items()}
    vertices = [
        _roll_rotate(vertex, pivots[owner], angles[owner]) if owner in angles else vertex
        for vertex, owner in zip(base.vertices, owners)
    ]
    return Model(base.name, base.origin, vertices,
                 [Face(tuple(face.indices), face.color, face.name, deepcopy(face.extra)) for face in base.faces],
                 deepcopy(base.metadata), deepcopy(base.extra)), angles


def normalise_with_base_bounds(model: Model, base: Model, target_height: float = 120.0) -> Model:
    """Apply the neutral OBJ's affine normalisation to every animation frame."""
    min_y = min(vertex[1] for vertex in base.vertices)
    max_y = max(vertex[1] for vertex in base.vertices)
    scale = target_height / (max_y - min_y)
    scaled_base = [(x * scale, y * scale, z * scale) for x, y, z in base.vertices]
    center = tuple((min(vertex[axis] for vertex in scaled_base) + max(vertex[axis] for vertex in scaled_base)) / 2.0 for axis in range(3))
    vertices = [(x * scale - center[0], y * scale - center[1], z * scale - center[2]) for x, y, z in model.vertices]
    faces = [Face(tuple(face.indices), rgb332_to_hex(hex_to_rgb332(face.color)), face.name, deepcopy(face.extra)) for face in model.faces]
    result = Model(model.name, (0.0, 0.0, 0.0), vertices, faces, deepcopy(model.metadata), deepcopy(model.extra))
    result.metadata["robotss_articulation"] = {"target_height": target_height, "normalization_center": list(center), "normalization_scale": scale}
    return result


def _image_from_pixels(pixels: bytes, width: int, height: int) -> Image.Image:
    return Image.frombytes("RGB", (width, height), pixels)


def _write_gif(path: Path, frames: list[bytes], width: int, height: int) -> None:
    images = [_image_from_pixels(frame, width, height) for frame in frames]
    images[0].save(path, save_all=True, append_images=images[1:], duration=80, loop=0, disposal=2)


def _write_comparison_sheet(path: Path, no_z: list[bytes], zbuffer: list[bytes], width: int, height: int) -> None:
    tile_w, tile_h = width, height + 18
    columns = 4
    rows = (len(no_z) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * tile_w, rows * tile_h * 2), "#202020")
    draw = ImageDraw.Draw(sheet)
    for index, (no_z_pixels, z_pixels) in enumerate(zip(no_z, zbuffer)):
        x = (index % columns) * tile_w
        y = (index // columns) * tile_h * 2
        sheet.paste(_image_from_pixels(no_z_pixels, width, height), (x, y + 18))
        sheet.paste(_image_from_pixels(z_pixels, width, height), (x, y + tile_h + 18))
        draw.text((x + 2, y + 2), f"{index:02d} no-Z", fill="white")
        draw.text((x + 2, y + tile_h + 2), f"{index:02d} Z", fill="white")
    sheet.save(path)


def _pixel_difference_count(left: bytes, right: bytes) -> int:
    return sum(left[offset:offset + 3] != right[offset:offset + 3] for offset in range(0, len(left), 3))


def _verify_neutral(base: Model, owners: list[str], pivots: dict[str, tuple[float, float, float]], reference_path: Path) -> dict[str, Any]:
    neutral, angles = pose_obj_model(base, owners, pivots, 0, 16, 25.0)
    assert all(value == 0.0 for value in angles.values())
    candidate = normalise_with_base_bounds(neutral, base)
    reference = Model.load(reference_path)
    if len(candidate.vertices) != len(reference.vertices):
        return {"checked": True, "matches": False, "reason": "vertex_count", "candidate_vertices": len(candidate.vertices), "reference_vertices": len(reference.vertices)}
    for index, (actual, expected) in enumerate(zip(candidate.vertices, reference.vertices)):
        if any(abs(a - b) > 1e-8 for a, b in zip(actual, expected)):
            return {"checked": True, "matches": False, "reason": "vertex_position", "first_mismatch_vertex": index}
    return {"checked": True, "matches": True}


def _signed16(value: int) -> int:
    return value - 0x10000 if value & 0x8000 else value


def load_v4_model(mif_path: Path, json_path: Path) -> tuple[list[dict[str, Any]], list[tuple[float, float, float]], list[Face]]:
    """Load the generated baked V4 asset as local meshes plus descriptor pivots."""
    words = [int(line, 2) for line in mif_path.read_text(encoding="ascii").splitlines() if line]
    if len(words) < 4 or words[0] != 0x534B3344 or (words[3] & 0xff) != 4:
        raise ValueError(f"{mif_path} is not an SK3D V4 asset")
    vertex_count, triangle_count, mesh_count = words[1], words[2], (words[3] >> 8) & 0xff
    document = json.loads(json_path.read_text(encoding="utf-8"))
    meshes = document.get("meshes")
    if not isinstance(meshes, list) or len(meshes) != mesh_count:
        raise ValueError("V4 JSON mesh table does not match V4 MIF header")
    descriptor_base = 4
    vertex_base = descriptor_base + mesh_count * 4
    triangle_base = vertex_base + vertex_count * 2
    if len(words) != triangle_base + triangle_count * 2:
        raise ValueError("V4 MIF word count does not match its header")
    vertices = [
        (_signed16(words[vertex_base + index * 2] >> 16) / 256.0,
         _signed16(words[vertex_base + index * 2] & 0xffff) / 256.0,
         _signed16(words[vertex_base + index * 2 + 1] & 0xffff) / 256.0)
        for index in range(vertex_count)
    ]
    faces = [
        Face(((words[triangle_base + index * 2] >> 0) & 0xff,
              (words[triangle_base + index * 2] >> 8) & 0xff,
              (words[triangle_base + index * 2] >> 16) & 0xff),
             rgb332_to_hex(words[triangle_base + index * 2 + 1] & 0xff))
        for index in range(triangle_count)
    ]
    for index, mesh in enumerate(meshes):
        descriptor = words[descriptor_base + index * 4:descriptor_base + index * 4 + 4]
        if not isinstance(mesh, dict) or mesh.get("vertex_count") != descriptor[1] or mesh.get("triangle_count") != descriptor[3]:
            raise ValueError(f"V4 JSON mesh {index} does not match MIF descriptor")
        if not isinstance(mesh.get("pivot"), list) or len(mesh["pivot"]) != 3:
            raise ValueError(f"V4 JSON mesh {index} has no pivot")
        mesh["vertex_base"], mesh["triangle_base"] = descriptor[0], descriptor[2]
    return meshes, vertices, faces


def pose_v4_model(meshes: list[dict[str, Any]], vertices: list[tuple[float, float, float]], faces: list[Face], frame_index: int, frame_count: int, amplitude_degrees: float) -> tuple[Model, dict[str, float]]:
    phase = 2.0 * pi * frame_index / frame_count
    angles = {part: amplitude_degrees * sin(phase) * direction for part, direction in MOVING_PARTS.items()}
    positioned_vertices = list(vertices)
    for mesh in meshes:
        name = str(mesh["name"])
        pivot = tuple(float(component) for component in mesh["pivot"])
        angle = angles.get(name, 0.0)
        for index in range(int(mesh["vertex_base"]), int(mesh["vertex_base"]) + int(mesh["vertex_count"])):
            local = vertices[index]
            radians = angle * pi / 180.0
            positioned_vertices[index] = (local[0] * cos(radians) - local[1] * sin(radians) + pivot[0], local[0] * sin(radians) + local[1] * cos(radians) + pivot[1], local[2] + pivot[2])
    return Model("robotss_v4_shade", (0.0, 0.0, 0.0), positioned_vertices, faces), angles


def render_walk(output_dir: Path, frame_count: int = 16, amplitude_degrees: float = 25.0,
                verify_neutral: bool = False, yaw_degrees: int = 0, v3_asset_root: Path = V3_ASSET_ROOT) -> dict[str, Any]:
    imported = import_obj(ASSET_ROOT / "robotss.obj", ASSET_ROOT / "robotss.mtl")
    base = imported.model
    pivots = _load_pivots(ASSET_ROOT / "robotss_pivot.json")
    owners = build_vertex_part_map(base)
    neutral_reference = {"checked": False}
    if verify_neutral:
        neutral_reference = _verify_neutral(base, owners, pivots, v3_asset_root / "robotss_shade.json")

    output_dir.mkdir(parents=True, exist_ok=True)
    # 360 steps permits an exact integer-degree offline camera yaw while
    # retaining the renderer's existing fixed-point-like trig path.
    profiles = {name: RenderConfig(profile=name, yaw_steps=360) for name in ("no_zbuffer", "zbuffer")}
    pixels_by_profile: dict[str, list[bytes]] = {name: [] for name in profiles}
    frame_records: list[dict[str, Any]] = []
    for frame_index in range(frame_count):
        posed_obj, angles = pose_obj_model(base, owners, pivots, frame_index, frame_count, amplitude_degrees)
        posed = apply_static_face_shading(normalise_with_base_bounds(posed_obj, base))
        results = {name: render_frame(posed, config, yaw_degrees) for name, config in profiles.items()}
        for name, result in results.items():
            profile_dir = output_dir / name / "frames"
            profile_dir.mkdir(parents=True, exist_ok=True)
            config = profiles[name]
            _image_from_pixels(result.pixels, config.frame_width, config.frame_height).save(profile_dir / f"frame_{frame_index:04d}.png")
            pixels_by_profile[name].append(result.pixels)
        no_z = results["no_zbuffer"]
        zbuffer = results["zbuffer"]
        frame_records.append({
            "frame_index": frame_index,
            "joint_pitch_degrees": angles,
            "no_zbuffer": no_z.to_dict(),
            "zbuffer": zbuffer.to_dict(),
            "pixel_difference_count": _pixel_difference_count(no_z.pixels, zbuffer.pixels),
        })

    for name, config in profiles.items():
        _write_gif(output_dir / name / "robotss_walk.gif", pixels_by_profile[name], config.frame_width, config.frame_height)
    _write_comparison_sheet(output_dir / "comparison_contact_sheet.png", pixels_by_profile["no_zbuffer"], pixels_by_profile["zbuffer"], 400, 300)
    summary = {
        "asset": "robotss",
        "frame_count": frame_count,
        "amplitude_degrees": amplitude_degrees,
        "global_yaw_degrees": yaw_degrees,
        "coordinate_space": "OBJ; local pitch is applied before fixed neutral-bounds normalization",
        "part_map": {part: sorted(index for index, owner in enumerate(owners) if owner == part) for part in PARTS},
        "pivots_obj": {part: list(value) for part, value in pivots.items()},
        "neutral_reference": neutral_reference,
        "frames": frame_records,
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return summary


def render_v4_walk(output_dir: Path, frame_count: int = 16, amplitude_degrees: float = 25.0, yaw_degrees: int = 0, v4_asset_root: Path = V4_ASSET_ROOT) -> dict[str, Any]:
    meshes, vertices, faces = load_v4_model(v4_asset_root / "robotss_shade.s3d.mif", v4_asset_root / "robotss_shade.json")
    output_dir.mkdir(parents=True, exist_ok=True)
    profiles = {name: RenderConfig(profile=name, yaw_steps=360) for name in ("no_zbuffer", "zbuffer")}
    pixels_by_profile: dict[str, list[bytes]] = {name: [] for name in profiles}
    frame_records: list[dict[str, Any]] = []
    for frame_index in range(frame_count):
        posed, angles = pose_v4_model(meshes, vertices, faces, frame_index, frame_count, amplitude_degrees)
        results = {name: render_frame(posed, config, yaw_degrees) for name, config in profiles.items()}
        for name, result in results.items():
            profile_dir = output_dir / name / "frames"
            profile_dir.mkdir(parents=True, exist_ok=True)
            config = profiles[name]
            _image_from_pixels(result.pixels, config.frame_width, config.frame_height).save(profile_dir / f"frame_{frame_index:04d}.png")
            pixels_by_profile[name].append(result.pixels)
        frame_records.append({"frame_index": frame_index, "joint_pitch_degrees": angles,
                              "no_zbuffer": results["no_zbuffer"].to_dict(), "zbuffer": results["zbuffer"].to_dict(),
                              "pixel_difference_count": _pixel_difference_count(results["no_zbuffer"].pixels, results["zbuffer"].pixels)})
    for name, config in profiles.items():
        _write_gif(output_dir / name / "robotss_v4_walk.gif", pixels_by_profile[name], config.frame_width, config.frame_height)
    _write_comparison_sheet(output_dir / "comparison_contact_sheet.png", pixels_by_profile["no_zbuffer"], pixels_by_profile["zbuffer"], 400, 300)
    summary = {"asset": "robotss_shade", "format_version": 4, "frame_count": frame_count, "amplitude_degrees": amplitude_degrees,
               "global_yaw_degrees": yaw_degrees, "coordinate_space": "SK3D V4 mesh-local vertices plus exported pivots", "meshes": meshes, "frames": frame_records}
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--v4-output", type=Path, default=DEFAULT_V4_OUTPUT)
    parser.add_argument("--v3-asset-root", type=Path, default=V3_ASSET_ROOT)
    parser.add_argument("--v4-asset-root", type=Path, default=V4_ASSET_ROOT)
    parser.add_argument("--frames", type=int, default=16)
    parser.add_argument("--amplitude", type=float, default=25.0)
    parser.add_argument("--yaw-degrees", type=int, default=0,
                        help="fixed global yaw for every walk frame, in integer degrees")
    parser.add_argument("--verify-neutral", action="store_true")
    parser.add_argument("--skip-v3", action="store_true", help="render only the generated V4 asset")
    parser.add_argument("--skip-v4", action="store_true", help="render only the V3/OBJ animation")
    args = parser.parse_args(argv)
    if args.frames < 2:
        parser.error("--frames must be at least 2")
    if not 0 <= args.yaw_degrees < 360:
        parser.error("--yaw-degrees must be in 0..359")
    if not args.skip_v3:
        summary = render_walk(args.output, args.frames, args.amplitude, args.verify_neutral, args.yaw_degrees, args.v3_asset_root)
        print(f"Wrote V3 robotss articulation previews to {args.output}")
        reference = summary["neutral_reference"]
        if reference["checked"] and not reference["matches"]:
            print("Warning: current OBJ geometry differs from robotss_shade.json; details are in summary.json", file=sys.stderr)
    if not args.skip_v4:
        render_v4_walk(args.v4_output, args.frames, args.amplitude, args.yaw_degrees, args.v4_asset_root)
        print(f"Wrote V4 robotss articulation previews to {args.v4_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
