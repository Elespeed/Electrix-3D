"""OBJ/MTL import for the generic low-poly model format."""
from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
from typing import Iterable

from model import Face, Model


class ObjImportError(ValueError):
    def __init__(self, errors: Iterable[str]):
        self.errors = list(errors)
        super().__init__("\n".join(self.errors))


@dataclass(frozen=True)
class ImportedObj:
    model: Model
    materials: dict[str, str]


@dataclass(frozen=True)
class _PendingFace:
    indices: tuple[int, int, int]
    color: str
    group_name: str | None
    object_name: str | None
    material_name: str


def _parse_float(token: str, label: str, errors: list[str]) -> float:
    try:
        value = float(token)
    except ValueError:
        errors.append(f"{label} must be a number")
        return 0.0
    if not math.isfinite(value):
        errors.append(f"{label} must be finite")
        return 0.0
    return value


def _clamp_channel(value: float) -> int:
    return max(0, min(255, int(round(value * 255.0))))


def _kd_to_hex(channels: list[float], label: str, errors: list[str]) -> str:
    if len(channels) != 3:
        errors.append(f"{label} must have exactly three components")
        return "#000000"
    if any((not math.isfinite(channel)) or channel < 0.0 or channel > 1.0 for channel in channels):
        errors.append(f"{label} components must be within [0, 1]")
        return "#000000"
    red, green, blue = (_clamp_channel(channel) for channel in channels)
    return f"#{red:02X}{green:02X}{blue:02X}"


def _build_connectivity_object_names(
    vertices: list[tuple[float, float, float]],
    faces: list[_PendingFace],
) -> list[str]:
    if not faces:
        return []

    face_indices_by_vertex: list[list[int]] = [[] for _ in vertices]
    for face_index, face in enumerate(faces):
        for vertex_index in face.indices:
            face_indices_by_vertex[vertex_index].append(face_index)

    face_components = [-1] * len(faces)
    component_count = 0
    for start_face_index in range(len(faces)):
        if face_components[start_face_index] >= 0:
            continue
        pending = [start_face_index]
        face_components[start_face_index] = component_count
        while pending:
            current_face_index = pending.pop()
            current_face = faces[current_face_index]
            for vertex_index in current_face.indices:
                for neighbour_face_index in face_indices_by_vertex[vertex_index]:
                    if face_components[neighbour_face_index] >= 0:
                        continue
                    face_components[neighbour_face_index] = component_count
                    pending.append(neighbour_face_index)
        component_count += 1

    return [f"component_{component_index}" for component_index in face_components]


def _build_object_metadata(
    vertices: list[tuple[float, float, float]],
    faces: list[_PendingFace],
) -> tuple[list[int], list[dict[str, object]], list[str]]:
    explicit_names = [face.object_name for face in faces]
    if any(name is None for name in explicit_names):
        component_names = _build_connectivity_object_names(vertices, faces)
        resolved_names = [
            explicit_name if explicit_name is not None else component_name
            for explicit_name, component_name in zip(explicit_names, component_names)
        ]
    else:
        resolved_names = [str(name) for name in explicit_names]

    object_ids_by_name: dict[str, int] = {}
    face_indices_by_name: dict[str, list[int]] = {}
    ordered_names: list[str] = []
    face_object_ids: list[int] = []
    for face_index, object_name in enumerate(resolved_names):
        object_id = object_ids_by_name.get(object_name)
        if object_id is None:
            object_id = len(ordered_names) + 1
            object_ids_by_name[object_name] = object_id
            face_indices_by_name[object_name] = []
            ordered_names.append(object_name)
        face_indices_by_name[object_name].append(face_index)
        face_object_ids.append(object_id)

    object_table = [
        {
            "object_id": object_ids_by_name[name],
            "name": name,
            "face_indices": face_indices_by_name[name],
        }
        for name in ordered_names
    ]
    return face_object_ids, object_table, resolved_names


def load_mtl(path: str | Path) -> dict[str, str]:
    source = Path(path)
    errors: list[str] = []
    materials: dict[str, str] = {}
    current_name: str | None = None

    try:
        lines = source.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ObjImportError([f"could not read MTL: {exc}"]) from exc

    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        keyword, *rest = line.split()
        if keyword == "newmtl":
            if not rest:
                errors.append(f"{source.name}:{line_number} newmtl requires a material name")
                current_name = None
                continue
            current_name = " ".join(rest)
        elif keyword == "Kd":
            if current_name is None:
                errors.append(f"{source.name}:{line_number} Kd appears before newmtl")
                continue
            channels = [_parse_float(token, f"{source.name}:{line_number} Kd", errors) for token in rest]
            if len(channels) == 3 and not errors:
                materials[current_name] = _kd_to_hex(channels, f"{source.name}:{line_number} Kd", errors)

    if errors:
        raise ObjImportError(errors)
    return materials


def import_obj(path: str | Path, mtl_path: str | Path | None = None) -> ImportedObj:
    obj_path = Path(path)
    if mtl_path is None:
        mtl_path = obj_path.with_suffix(".mtl")
    materials = load_mtl(mtl_path)

    try:
        lines = obj_path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ObjImportError([f"could not read OBJ: {exc}"]) from exc

    errors: list[str] = []
    vertices: list[tuple[float, float, float]] = []
    pending_faces: list[_PendingFace] = []
    groups_seen: list[str] = []
    objects_seen: list[str] = []
    current_group: str | None = None
    current_object: str | None = None
    current_material: str | None = None

    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        keyword, *rest = line.split()
        if keyword == "v":
            if len(rest) < 3:
                errors.append(f"{obj_path.name}:{line_number} vertex requires at least three coordinates")
                continue
            vertices.append(tuple(_parse_float(token, f"{obj_path.name}:{line_number} vertex", errors) for token in rest[:3]))  # type: ignore[arg-type]
        elif keyword == "o":
            current_object = " ".join(rest) if rest else None
            if current_object and current_object not in objects_seen:
                objects_seen.append(current_object)
        elif keyword == "g":
            current_group = " ".join(rest) if rest else None
            if current_group and current_group not in groups_seen:
                groups_seen.append(current_group)
        elif keyword == "usemtl":
            if not rest:
                errors.append(f"{obj_path.name}:{line_number} usemtl requires a material name")
                current_material = None
                continue
            current_material = " ".join(rest)
            if current_material not in materials:
                errors.append(f"{obj_path.name}:{line_number} references unknown material '{current_material}'")
        elif keyword == "f":
            if len(rest) != 3:
                errors.append(f"{obj_path.name}:{line_number} face must be triangulated; got {len(rest)} vertices")
                continue
            if current_material is None:
                errors.append(f"{obj_path.name}:{line_number} face is missing usemtl")
                continue
            indices: list[int] = []
            for token in rest:
                raw_index = token.split("/", 1)[0]
                try:
                    vertex_index = int(raw_index)
                except ValueError:
                    errors.append(f"{obj_path.name}:{line_number} face index '{token}' is not an integer")
                    vertex_index = 0
                if vertex_index <= 0:
                    errors.append(f"{obj_path.name}:{line_number} face index '{token}' must be positive")
                    continue
                zero_based = vertex_index - 1
                if zero_based >= len(vertices):
                    errors.append(f"{obj_path.name}:{line_number} face index '{token}' is out of range")
                    continue
                indices.append(zero_based)
            if len(indices) == 3:
                pending_faces.append(
                    _PendingFace(
                        indices=tuple(indices),
                        color=materials[current_material],
                        group_name=current_group,
                        object_name=current_object if current_object is not None else current_group,
                        material_name=current_material,
                    )
                )

    if errors:
        raise ObjImportError(errors)

    face_object_ids, object_table, resolved_object_names = _build_object_metadata(vertices, pending_faces)
    faces = []
    for face, object_id, object_name in zip(pending_faces, face_object_ids, resolved_object_names):
        extra = {
            "material": face.material_name,
            "object_name": object_name,
            "object_id": object_id,
        }
        if face.group_name is not None:
            extra["group"] = face.group_name
        faces.append(Face(face.indices, face.color, face.group_name, extra))

    model = Model(
        name=obj_path.stem,
        origin=(0.0, 0.0, 0.0),
        vertices=vertices,
        faces=faces,
        metadata={
            "source": {"obj": obj_path.name, "mtl": Path(mtl_path).name},
            "objects": objects_seen,
            "groups": groups_seen,
            "materials": materials,
            "object_table": object_table,
        },
    )
    return ImportedObj(model=model, materials=materials)
