"""Static, non-physical face shading for low-poly Sketch assets."""
from __future__ import annotations

from copy import deepcopy
import math
from typing import NamedTuple

from color_rgb332 import shade_hex_rgb332 as _shade_hex_rgb332
from geometry_surface import face_normal
from model import Face, Model

LITE_Q15_ONE = 32767
STATIC_SHADE_LEVELS_Q15 = {
    # Keep the faces visually distinguishable after RGB332 quantisation.  In
    # particular, a raised/rotated limb must not make its top face look like
    # the front face.
    "back_bottom": 22937,  # 0.70
    "side": 29490,        # 0.90
    "top": 44235,         # 1.35
    "front": 36044,       # 1.10
}
STATIC_SHADE_LEVELS = {
    key: value / LITE_Q15_ONE for key, value in STATIC_SHADE_LEVELS_Q15.items()
}
STATIC_SHADE_METADATA = {
    "mode": "group_material_surface_bucket_v3",
    "axis_convention": {
        "front_back": "+/-Z",
        "up": "+Y",
        "side": "+/-X",
        "down": "-Y",
    },
    "levels_q15": {
        "front_back": STATIC_SHADE_LEVELS_Q15["front"],
        "top": STATIC_SHADE_LEVELS_Q15["top"],
        "side": STATIC_SHADE_LEVELS_Q15["side"],
        "bottom": STATIC_SHADE_LEVELS_Q15["back_bottom"],
    },
    "levels_ratio": {
        "front_back": round(STATIC_SHADE_LEVELS["front"], 6),
        "top": round(STATIC_SHADE_LEVELS["top"], 6),
        "side": round(STATIC_SHADE_LEVELS["side"], 6),
        "bottom": round(STATIC_SHADE_LEVELS["back_bottom"], 6),
    },
}
_EPSILON = 1e-9
_PLANE_EPSILON = 1e-6


class SurfaceKey(NamedTuple):
    group: str
    material: str
    axis: int
    plane: int


def shade_hex_rgb332(color: str, intensity_q15: int) -> str:
    return _shade_hex_rgb332(
        color,
        intensity_q15,
        STATIC_SHADE_LEVELS_Q15["back_bottom"],
        max(STATIC_SHADE_LEVELS_Q15.values()),
    )


def classify_normal_bucket(normal: tuple[float, float, float]) -> tuple[str, float]:
    nx, ny, nz = normal
    length = math.sqrt((nx * nx) + (ny * ny) + (nz * nz))
    if length <= _EPSILON:
        return "back_bottom", STATIC_SHADE_LEVELS["back_bottom"]
    unit = (nx / length, ny / length, nz / length)
    dominant_axis = max(range(3), key=lambda index: abs(unit[index]))
    component = unit[dominant_axis]
    if dominant_axis == 0:
        return "side", STATIC_SHADE_LEVELS["side"]
    if dominant_axis == 1:
        if component >= 0.0:
            return "top", STATIC_SHADE_LEVELS["top"]
        return "back_bottom", STATIC_SHADE_LEVELS["back_bottom"]
    return "front", STATIC_SHADE_LEVELS["front"]


def _normal_unit_and_axis(normal: tuple[float, float, float]) -> tuple[tuple[float, float, float], int]:
    nx, ny, nz = normal
    length = math.sqrt((nx * nx) + (ny * ny) + (nz * nz))
    if length <= _EPSILON:
        return (0.0, 0.0, 0.0), 2
    unit = (nx / length, ny / length, nz / length)
    return unit, max(range(3), key=lambda index: abs(unit[index]))


def _surface_key(face: Face, vertices: list[tuple[float, float, float]]) -> SurfaceKey:
    normal = face_normal(vertices, face)
    _, axis = _normal_unit_and_axis(normal)
    plane = round(sum(vertices[index][axis] for index in face.indices) / 3.0 / _PLANE_EPSILON)
    return SurfaceKey(
        str(face.extra.get("group", face.name or "")),
        str(face.extra.get("material", face.color)),
        axis,
        plane,
    )


def _share_edge(left: Face, right: Face) -> bool:
    return len(set(left.indices) & set(right.indices)) >= 2


def _is_coplanar_with_same_orientation(
    left: Face,
    right: Face,
    vertices: list[tuple[float, float, float]],
) -> bool:
    left_normal = face_normal(vertices, left)
    right_normal = face_normal(vertices, right)
    left_unit, left_axis = _normal_unit_and_axis(left_normal)
    right_unit, right_axis = _normal_unit_and_axis(right_normal)
    if left_axis != right_axis:
        return False
    dot = sum(left_component * right_component for left_component, right_component in zip(left_unit, right_unit))
    if dot < 1.0 - _PLANE_EPSILON:
        return False
    anchor = vertices[left.indices[0]]
    plane_offset = sum(anchor[index] * left_unit[index] for index in range(3))
    return all(
        abs(sum(vertices[index][axis] * left_unit[axis] for axis in range(3)) - plane_offset) <= _PLANE_EPSILON
        for index in right.indices
    )


def _surface_clusters(model: Model) -> list[tuple[SurfaceKey, list[int]]]:
    pending = set(range(len(model.faces)))
    clusters: list[tuple[SurfaceKey, list[int]]] = []
    face_keys = [_surface_key(face, model.vertices) for face in model.faces]
    while pending:
        seed = pending.pop()
        key = face_keys[seed]
        cluster = [seed]
        stack = [seed]
        while stack:
            current = stack.pop()
            neighbors = [
                candidate for candidate in list(pending)
                if (
                    face_keys[candidate] == key and
                    _share_edge(model.faces[current], model.faces[candidate]) and
                    _is_coplanar_with_same_orientation(model.faces[current], model.faces[candidate], model.vertices)
                )
            ]
            for candidate in neighbors:
                pending.remove(candidate)
                stack.append(candidate)
                cluster.append(candidate)
        clusters.append((key, sorted(cluster)))
    return clusters


def _cluster_normal(model: Model, face_indices: list[int]) -> tuple[float, float, float]:
    nx = ny = nz = 0.0
    for face_index in face_indices:
        face_nx, face_ny, face_nz = face_normal(model.vertices, model.faces[face_index])
        nx += face_nx
        ny += face_ny
        nz += face_nz
    return nx, ny, nz


def apply_static_face_shading(model: Model) -> Model:
    shaded = Model(
        name=f"{model.name}_shade",
        origin=tuple(model.origin),
        vertices=list(model.vertices),
        faces=[],
        metadata=deepcopy(model.metadata),
        extra=deepcopy(model.extra),
    )
    metadata = dict(STATIC_SHADE_METADATA)
    shaded.metadata["static_face_shading"] = metadata
    cluster_info_by_face: dict[int, dict[str, object]] = {}
    for surface_id, (surface_key, cluster) in enumerate(_surface_clusters(model)):
        normal = _cluster_normal(model, cluster)
        bucket, intensity = classify_normal_bucket(normal)
        intensity_q15 = STATIC_SHADE_LEVELS_Q15[bucket]
        cluster_info = {
            "surface_id": surface_id,
            "surface_group": surface_key.group,
            "surface_material": surface_key.material,
            "surface_axis": surface_key.axis,
            "surface_plane": round(surface_key.plane * _PLANE_EPSILON, 6),
            "surface_face_count": len(cluster),
            "bucket": bucket,
            "intensity": round(intensity, 6),
            "intensity_q15": intensity_q15,
            "normal": [round(component, 6) for component in normal],
        }
        for face_index in cluster:
            cluster_info_by_face[face_index] = cluster_info

    for face_index, face in enumerate(model.faces):
        cluster_info = cluster_info_by_face[face_index]
        extra = dict(face.extra)
        extra["static_shade_base_color"] = face.color
        extra["static_shade_bucket"] = str(cluster_info["bucket"])
        extra["static_shade_intensity"] = cluster_info["intensity"]
        extra["static_shade_intensity_q15"] = cluster_info["intensity_q15"]
        extra["static_shade_normal"] = cluster_info["normal"]
        extra["static_shade_surface_id"] = cluster_info["surface_id"]
        extra["static_shade_surface_group"] = cluster_info["surface_group"]
        extra["static_shade_surface_material"] = cluster_info["surface_material"]
        extra["static_shade_surface_axis"] = cluster_info["surface_axis"]
        extra["static_shade_surface_plane"] = cluster_info["surface_plane"]
        extra["static_shade_surface_face_count"] = cluster_info["surface_face_count"]
        shaded.faces.append(
            Face(
                tuple(face.indices),
                shade_hex_rgb332(face.color, int(cluster_info["intensity_q15"])),
                face.name,
                extra,
            )
        )
    return shaded
