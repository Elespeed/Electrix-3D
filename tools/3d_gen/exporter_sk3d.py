"""Strict SK3D0 / SketchBook generic scene export profile."""
from __future__ import annotations

import math
from pathlib import Path
import struct
from typing import Iterable

from color_rgb332 import hex_to_rgb332
from model import Model, normalise_color

SK3D_MAGIC = 0x534B3344  # "SK3D" with version 0 stored in header word3
SK3D_VERSION_STATIC = 2
SK3D_VERSION_DYNAMIC = 3
SK3D_MAX_VERTICES = 128
SK3D_MAX_TRIANGLES = 192
SK3D_MAX_MATERIALS = 64
SK3D_MAX_FACE_GROUPS = 192


class Sk3dValidationError(ValueError):
    def __init__(self, errors: Iterable[str]):
        self.errors = list(errors)
        super().__init__("\n".join(self.errors))


def _dynamic_shading_metadata(model: Model) -> dict | None:
    metadata = model.metadata.get("dynamic_surface_shading")
    return metadata if isinstance(metadata, dict) else None


def _sk3d_version(model: Model) -> int:
    return SK3D_VERSION_DYNAMIC if _dynamic_shading_metadata(model) is not None else SK3D_VERSION_STATIC


def _pack_signed_q1_8(value: int) -> int:
    if not -512 <= value <= 511:
        raise Sk3dValidationError([f"packed normal component {value} exceeds signed Q1.8 range"])
    return value & 0x3FF


def _header_word3(model: Model) -> int:
    if _sk3d_version(model) == SK3D_VERSION_STATIC:
        return SK3D_VERSION_STATIC
    shading = _dynamic_shading_metadata(model)
    assert shading is not None
    material_count = len(shading.get("materials", []))
    surface_count = len(shading.get("surfaces", []))
    return SK3D_VERSION_DYNAMIC | (material_count << 8) | (surface_count << 16)


def validate(model: Model) -> list[str]:
    errors: list[str] = []
    if not 1 <= len(model.vertices) <= SK3D_MAX_VERTICES:
        errors.append(f"SK3D0 requires 1..{SK3D_MAX_VERTICES} vertices; model has {len(model.vertices)}")
    if not 1 <= len(model.faces) <= SK3D_MAX_TRIANGLES:
        errors.append(f"SK3D0 requires 1..{SK3D_MAX_TRIANGLES} triangle faces; model has {len(model.faces)}")
    for index, vertex in enumerate(model.vertices):
        for axis, value, origin in zip("xyz", vertex, model.origin):
            relative = value - origin
            if not math.isfinite(relative) or not -128 <= relative <= 127:
                errors.append(f"vertex {index} {axis} relative to origin is {relative:g}; SK3D0 range is [-128, 127]")
            elif not -32768 <= int(round(relative * 256)) <= 32767:
                errors.append(f"vertex {index} {axis} cannot be represented as signed Q8.8")
    for position, face in enumerate(model.faces):
        if len(face.indices) != 3 or any(item < 0 or item >= len(model.vertices) for item in face.indices):
            errors.append(f"face {position} has invalid vertex indices")
            continue
        if len(set(face.indices)) != 3:
            errors.append(f"face {position} is degenerate (repeated vertex)")
        else:
            a, b, c = (model.vertices[item] for item in face.indices)
            cross = ((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]),
                     (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]),
                     (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
            if sum(component * component for component in cross) <= 1e-12:
                errors.append(f"face {position} is degenerate (zero area)")
        try:
            normalise_color(face.color, f"face {position} color")
        except ValueError as exc:
            errors.append(str(exc))
    shading = _dynamic_shading_metadata(model)
    if shading is not None:
        materials = shading.get("materials")
        surfaces = shading.get("surfaces")
        if not isinstance(materials, list) or not 1 <= len(materials) <= SK3D_MAX_MATERIALS:
            errors.append(f"dynamic SK3D requires 1..{SK3D_MAX_MATERIALS} materials")
        if not isinstance(surfaces, list) or not 1 <= len(surfaces) <= SK3D_MAX_FACE_GROUPS:
            errors.append(f"dynamic SK3D requires 1..{SK3D_MAX_FACE_GROUPS} surfaces")
        for material_index, material in enumerate(materials or []):
            if not isinstance(material, dict):
                errors.append(f"dynamic material {material_index} must be an object")
                continue
            shade_colors = material.get("shade_colors")
            if not isinstance(shade_colors, list) or len(shade_colors) != 4:
                errors.append(f"dynamic material {material_index} must provide four shade colors")
                continue
            for shade_index, color in enumerate(shade_colors):
                try:
                    normalise_color(color, f"dynamic material {material_index} shade {shade_index}")
                except ValueError as exc:
                    errors.append(str(exc))
        for surface_index, surface in enumerate(surfaces or []):
            if not isinstance(surface, dict):
                errors.append(f"dynamic surface {surface_index} must be an object")
                continue
            canonical_normal_q8 = surface.get("canonical_normal_q8")
            if (not isinstance(canonical_normal_q8, list) or len(canonical_normal_q8) != 3 or
                    any(isinstance(item, bool) or not isinstance(item, int) for item in canonical_normal_q8)):
                errors.append(f"dynamic surface {surface_index} must provide canonical_normal_q8[3]")
        material_count = len(materials or [])
        surface_count = len(surfaces or [])
        for position, face in enumerate(model.faces):
            material_id = face.extra.get("material_id")
            surface_id = face.extra.get("surface_id")
            if isinstance(material_id, bool) or not isinstance(material_id, int) or not 0 <= material_id < material_count:
                errors.append(f"face {position} has invalid material_id for dynamic SK3D")
            if isinstance(surface_id, bool) or not isinstance(surface_id, int) or not 0 <= surface_id < surface_count:
                errors.append(f"face {position} has invalid surface_id for dynamic SK3D")
    return errors


def encode_words(model: Model) -> list[int]:
    errors = validate(model)
    if errors:
        raise Sk3dValidationError(errors)
    words = [SK3D_MAGIC, len(model.vertices), len(model.faces), _header_word3(model)]
    for vertex in model.vertices:
        x, y, z = (int(round((value - origin) * 256)) for value, origin in zip(vertex, model.origin))
        words.extend([((x & 0xFFFF) << 16) | (y & 0xFFFF), z & 0xFFFF])
    shading = _dynamic_shading_metadata(model)
    if shading is not None:
        for material in shading["materials"]:
            shade_colors = material["shade_colors"]
            words.extend([
                hex_to_rgb332(shade_colors[0]) | (hex_to_rgb332(shade_colors[1]) << 8) |
                (hex_to_rgb332(shade_colors[2]) << 16) | (hex_to_rgb332(shade_colors[3]) << 24),
            ])
        for surface in shading["surfaces"]:
            nx_q8, ny_q8, nz_q8 = surface["canonical_normal_q8"]
            words.append(
                _pack_signed_q1_8(nx_q8) |
                (_pack_signed_q1_8(ny_q8) << 10) |
                (_pack_signed_q1_8(nz_q8) << 20)
            )
        for face in model.faces:
            index0, index1, index2 = face.indices
            words.extend([
                index0 | (index1 << 8) | (index2 << 16),
                int(face.extra["material_id"]) | (int(face.extra["surface_id"]) << 8),
            ])
    else:
        for face in model.faces:
            index0, index1, index2 = face.indices
            words.extend([index0 | (index1 << 8) | (index2 << 16), hex_to_rgb332(face.color)])
    return words


def triangle_base_word_index(model: Model) -> int:
    base = 4 + (len(model.vertices) * 2)
    shading = _dynamic_shading_metadata(model)
    if shading is None:
        return base
    return base + len(shading["materials"]) + len(shading["surfaces"])


def mif_text(model: Model) -> str:
    return "\n".join(f"{word:032b}" for word in encode_words(model)) + "\n"


def export_mif(model: Model, path: str | Path) -> None:
    output = mif_text(model)
    Path(path).write_text(output, encoding="ascii", newline="\n")


def bin_bytes(model: Model) -> bytes:
    """Return SK3D0 words as a little-endian raw binary stream.

    The MIF representation is word-oriented; this form is intended for
    software/ROM assets and therefore uses the target's little-endian layout.
    """
    return b"".join(struct.pack("<I", word) for word in encode_words(model))


def export_bin(model: Model, path: str | Path) -> None:
    Path(path).write_bytes(bin_bytes(model))
