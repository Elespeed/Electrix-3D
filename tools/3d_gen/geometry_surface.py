"""Geometry-driven surface reconstruction for triangulated low-poly assets."""
from __future__ import annotations

from dataclasses import dataclass
import math

from model import Face, Model

EPSILON = 1e-9
DEFAULT_VERTEX_EPSILON = 1e-6
DEFAULT_PLANE_EPSILON = 1e-6
DEFAULT_NORMAL_ANGLE_EPSILON_DEGREES = 0.5


@dataclass(frozen=True)
class Surface:
    surface_id: int
    face_indices: list[int]
    canonical_normal: tuple[float, float, float]


def face_normal(vertices: list[tuple[float, float, float]], face: Face) -> tuple[float, float, float]:
    a, b, c = (vertices[item] for item in face.indices)
    ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    return (
        (ab[1] * ac[2]) - (ab[2] * ac[1]),
        (ab[2] * ac[0]) - (ab[0] * ac[2]),
        (ab[0] * ac[1]) - (ab[1] * ac[0]),
    )


def unit_normal(normal: tuple[float, float, float]) -> tuple[float, float, float]:
    nx, ny, nz = normal
    length = math.sqrt((nx * nx) + (ny * ny) + (nz * nz))
    if length <= EPSILON:
        return (0.0, 0.0, -1.0)
    return (nx / length, ny / length, nz / length)


def reconstruct_surfaces(
    model: Model,
    *,
    vertex_epsilon: float = DEFAULT_VERTEX_EPSILON,
    plane_epsilon: float = DEFAULT_PLANE_EPSILON,
    normal_angle_epsilon_degrees: float = DEFAULT_NORMAL_ANGLE_EPSILON_DEGREES,
) -> list[Surface]:
    welded_vertices = _weld_vertices(model.vertices, vertex_epsilon)
    adjacency = _build_face_adjacency(model.faces, welded_vertices)
    face_normals = [face_normal(model.vertices, face) for face in model.faces]
    normal_dot_threshold = math.cos(math.radians(normal_angle_epsilon_degrees))

    pending = set(range(len(model.faces)))
    surfaces: list[Surface] = []
    while pending:
        seed = min(pending)
        pending.remove(seed)
        cluster = [seed]
        stack = [seed]
        while stack:
            current = stack.pop()
            for candidate in sorted(adjacency[current]):
                if candidate not in pending:
                    continue
                if not _faces_are_coplanar(
                    model,
                    current,
                    candidate,
                    face_normals,
                    plane_epsilon=plane_epsilon,
                    normal_dot_threshold=normal_dot_threshold,
                ):
                    continue
                pending.remove(candidate)
                cluster.append(candidate)
                stack.append(candidate)
        surfaces.append(
            Surface(
                surface_id=len(surfaces),
                face_indices=sorted(cluster),
                canonical_normal=_canonical_normal(cluster, face_normals),
            )
        )
    return surfaces


def _weld_vertices(vertices: list[tuple[float, float, float]], epsilon: float) -> list[int]:
    buckets: dict[tuple[int, int, int], int] = {}
    welded: list[int] = []
    for vertex in vertices:
        key = tuple(int(round(component / epsilon)) for component in vertex)
        welded.append(buckets.setdefault(key, len(buckets)))
    return welded


def _build_face_adjacency(faces: list[Face], welded_vertices: list[int]) -> list[set[int]]:
    adjacency = [set() for _ in faces]
    edge_to_faces: dict[tuple[int, int], list[int]] = {}
    for face_index, face in enumerate(faces):
        indices = [welded_vertices[item] for item in face.indices]
        edges = (
            tuple(sorted((indices[0], indices[1]))),
            tuple(sorted((indices[1], indices[2]))),
            tuple(sorted((indices[2], indices[0]))),
        )
        for edge in edges:
            edge_to_faces.setdefault(edge, []).append(face_index)
    for face_indices in edge_to_faces.values():
        for left in face_indices:
            for right in face_indices:
                if left != right:
                    adjacency[left].add(right)
    return adjacency


def _faces_are_coplanar(
    model: Model,
    left_index: int,
    right_index: int,
    face_normals: list[tuple[float, float, float]],
    *,
    plane_epsilon: float,
    normal_dot_threshold: float,
) -> bool:
    left_unit = unit_normal(face_normals[left_index])
    right_unit = unit_normal(face_normals[right_index])
    alignment = sum(left_component * right_component for left_component, right_component in zip(left_unit, right_unit))
    if abs(alignment) < normal_dot_threshold:
        return False
    oriented_left = left_unit if alignment >= 0.0 else tuple(-component for component in left_unit)
    anchor = model.vertices[model.faces[left_index].indices[0]]
    plane_offset = sum(component * anchor[axis] for axis, component in enumerate(oriented_left))
    return all(
        abs(sum(component * model.vertices[vertex_index][axis] for axis, component in enumerate(oriented_left)) - plane_offset)
        <= plane_epsilon
        for vertex_index in model.faces[right_index].indices
    )


def _canonical_normal(
    face_indices: list[int],
    face_normals: list[tuple[float, float, float]],
) -> tuple[float, float, float]:
    reference = unit_normal(face_normals[face_indices[0]])
    nx = ny = nz = 0.0
    for face_index in face_indices:
        current = face_normals[face_index]
        oriented = current
        if sum(reference[axis] * current[axis] for axis in range(3)) < 0.0:
            oriented = tuple(-component for component in current)
        nx += oriented[0]
        ny += oriented[1]
        nz += oriented[2]
    return unit_normal((nx, ny, nz))
