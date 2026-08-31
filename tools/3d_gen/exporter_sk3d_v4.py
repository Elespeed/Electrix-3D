"""SK3D V4 static-colour multi-mesh export profile."""
from __future__ import annotations

from dataclasses import dataclass
import math
import struct
from pathlib import Path
from typing import Iterable

from color_rgb332 import hex_to_rgb332
from exporter_sk3d import SK3D_MAGIC
from model import Face, Model

SK3D_VERSION_MULTIMESH = 4
SK3D_V4_MAX_MESHES = 16
SK3D_V4_MAX_VERTICES = 128
SK3D_V4_MAX_TRIANGLES = 192


class Sk3dV4ValidationError(ValueError):
    def __init__(self, errors: Iterable[str]):
        self.errors = list(errors)
        super().__init__("\n".join(self.errors))


@dataclass(frozen=True)
class Mesh:
    name: str
    pivot: tuple[float, float, float]
    vertices: list[tuple[float, float, float]]
    faces: list[Face]


@dataclass(frozen=True)
class MultiMeshModel:
    name: str
    meshes: list[Mesh]


def validate(model: MultiMeshModel) -> list[str]:
    errors: list[str] = []
    if not 1 <= len(model.meshes) <= SK3D_V4_MAX_MESHES:
        errors.append(f"SK3D V4 requires 1..{SK3D_V4_MAX_MESHES} meshes; model has {len(model.meshes)}")
    vertices = 0
    triangles = 0
    for mesh_index, mesh in enumerate(model.meshes):
        if not mesh.name:
            errors.append(f"mesh {mesh_index} has an empty name")
        if not mesh.vertices:
            errors.append(f"mesh {mesh_index} has no vertices")
        if not mesh.faces:
            errors.append(f"mesh {mesh_index} has no triangles")
        for vertex_index, vertex in enumerate(mesh.vertices):
            for axis, coordinate in zip("xyz", vertex):
                if not math.isfinite(coordinate) or not -128 <= coordinate <= 127:
                    errors.append(f"mesh {mesh_index} vertex {vertex_index} {axis} is outside SK3D Q8.8 range [-128, 127]")
        for face_index, face in enumerate(mesh.faces):
            if len(face.indices) != 3 or any(index < 0 or index >= len(mesh.vertices) for index in face.indices):
                errors.append(f"mesh {mesh_index} face {face_index} has invalid vertex indices")
        vertices += len(mesh.vertices)
        triangles += len(mesh.faces)
    if not 1 <= vertices <= SK3D_V4_MAX_VERTICES:
        errors.append(f"SK3D V4 requires 1..{SK3D_V4_MAX_VERTICES} total vertices; model has {vertices}")
    if not 1 <= triangles <= SK3D_V4_MAX_TRIANGLES:
        errors.append(f"SK3D V4 requires 1..{SK3D_V4_MAX_TRIANGLES} total triangles; model has {triangles}")
    return errors


def encode_words(model: MultiMeshModel) -> list[int]:
    errors = validate(model)
    if errors:
        raise Sk3dV4ValidationError(errors)
    vertex_count = sum(len(mesh.vertices) for mesh in model.meshes)
    triangle_count = sum(len(mesh.faces) for mesh in model.meshes)
    words = [SK3D_MAGIC, vertex_count, triangle_count, SK3D_VERSION_MULTIMESH | (len(model.meshes) << 8)]
    vertex_base = triangle_base = 0
    for mesh in model.meshes:
        words.extend([vertex_base, len(mesh.vertices), triangle_base, len(mesh.faces)])
        vertex_base += len(mesh.vertices)
        triangle_base += len(mesh.faces)
    for mesh in model.meshes:
        for x, y, z in mesh.vertices:
            xq, yq, zq = (int(round(value * 256.0)) for value in (x, y, z))
            words.extend([((xq & 0xffff) << 16) | (yq & 0xffff), zq & 0xffff])
    vertex_base = 0
    for mesh in model.meshes:
        for face in mesh.faces:
            i0, i1, i2 = (vertex_base + index for index in face.indices)
            words.extend([i0 | (i1 << 8) | (i2 << 16), hex_to_rgb332(face.color)])
        vertex_base += len(mesh.vertices)
    return words


def mif_text(model: MultiMeshModel) -> str:
    return "\n".join(f"{word:032b}" for word in encode_words(model)) + "\n"


def export_mif(model: MultiMeshModel, path: str | Path) -> None:
    Path(path).write_text(mif_text(model), encoding="ascii", newline="\n")


def export_bin(model: MultiMeshModel, path: str | Path) -> None:
    Path(path).write_bytes(b"".join(struct.pack("<I", word) for word in encode_words(model)))
