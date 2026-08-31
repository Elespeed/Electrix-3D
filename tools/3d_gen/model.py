"""Generic, loss-conscious low-poly model format and JSON I/O."""
from __future__ import annotations

from dataclasses import dataclass, field
import json
import math
from pathlib import Path
from typing import Any, Iterable


class ModelValidationError(ValueError):
    """Raised when a JSON document cannot be represented by the editor."""

    def __init__(self, errors: Iterable[str]):
        self.errors = list(errors)
        super().__init__("\n".join(self.errors))


def _number(value: Any, label: str, errors: list[str]) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        errors.append(f"{label} must be a number")
        return 0.0
    result = float(value)
    if not math.isfinite(result):
        errors.append(f"{label} must be finite")
        return 0.0
    return result


def normalise_color(value: Any, label: str = "color") -> str:
    if not isinstance(value, str) or len(value) != 7 or not value.startswith("#"):
        raise ValueError(f"{label} must be #RRGGBB")
    try:
        int(value[1:], 16)
    except ValueError as exc:
        raise ValueError(f"{label} must be #RRGGBB") from exc
    return value.upper()


@dataclass
class Face:
    indices: tuple[int, int, int]
    color: str = "#C0C0C0"
    name: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        result = dict(self.extra)
        result["indices"] = list(self.indices)
        result["color"] = self.color
        if self.name is not None:
            result["name"] = self.name
        return result


@dataclass
class Model:
    name: str = "untitled"
    origin: tuple[float, float, float] = (0.0, 0.0, 0.0)
    vertices: list[tuple[float, float, float]] = field(default_factory=list)
    faces: list[Face] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)
    extra: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def empty(cls) -> "Model":
        return cls()

    @classmethod
    def from_dict(cls, document: Any) -> "Model":
        if not isinstance(document, dict):
            raise ModelValidationError(["root JSON value must be an object"])
        return cls._from_generic(document)

    @classmethod
    def _from_generic(cls, document: dict[str, Any]) -> "Model":
        errors: list[str] = []
        if document.get("format") != "lowpoly-model":
            errors.append("format must be 'lowpoly-model'")
        if document.get("version") != 1:
            errors.append("version must be 1")
        name = document.get("name")
        if not isinstance(name, str) or not name.strip():
            errors.append("name must be a non-empty string")
            name = "untitled"
        origin = _vector(document.get("origin", [0, 0, 0]), "origin", errors)
        vertices_raw = document.get("vertices")
        vertices: list[tuple[float, float, float]] = []
        if not isinstance(vertices_raw, list):
            errors.append("vertices must be an array")
        else:
            for index, value in enumerate(vertices_raw):
                vertices.append(_vector(value, f"vertices[{index}]", errors))
        faces_raw = document.get("faces")
        faces: list[Face] = []
        if not isinstance(faces_raw, list):
            errors.append("faces must be an array")
        else:
            for index, value in enumerate(faces_raw):
                face = _face_from_value(value, index, len(vertices), errors)
                if face is not None:
                    faces.append(face)
        if errors:
            raise ModelValidationError(errors)
        metadata = document.get("metadata", {})
        if not isinstance(metadata, dict):
            errors.append("metadata must be an object")
        if errors:
            raise ModelValidationError(errors)
        known = {"format", "version", "name", "origin", "vertices", "faces", "metadata"}
        return cls(str(name), origin, vertices, faces, dict(metadata),
                   {key: value for key, value in document.items() if key not in known})

    def to_dict(self) -> dict[str, Any]:
        result = dict(self.extra)
        result.update({
            "format": "lowpoly-model",
            "version": 1,
            "name": self.name,
            "origin": list(self.origin),
            "vertices": [list(vertex) for vertex in self.vertices],
            "faces": [face.to_dict() for face in self.faces],
        })
        if self.metadata:
            result["metadata"] = dict(self.metadata)
        return result

    def save(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.to_dict(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    @classmethod
    def load(cls, path: str | Path) -> "Model":
        try:
            document = json.loads(Path(path).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ModelValidationError([f"could not read JSON: {exc}"]) from exc
        return cls.from_dict(document)

    def delete_vertex(self, vertex_index: int) -> int:
        """Delete one vertex and connected faces; return the number of faces removed."""
        if not 0 <= vertex_index < len(self.vertices):
            raise IndexError("vertex index out of range")
        del self.vertices[vertex_index]
        old_count = len(self.faces)
        kept: list[Face] = []
        for face in self.faces:
            if vertex_index in face.indices:
                continue
            kept.append(Face(tuple(index - 1 if index > vertex_index else index for index in face.indices),
                             face.color, face.name, dict(face.extra)))
        self.faces = kept
        return old_count - len(self.faces)


def _vector(value: Any, label: str, errors: list[str]) -> tuple[float, float, float]:
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        errors.append(f"{label} must contain exactly three numbers")
        return (0.0, 0.0, 0.0)
    return tuple(_number(axis, f"{label}[{axis_index}]", errors) for axis_index, axis in enumerate(value))  # type: ignore[return-value]


def _face_from_value(value: Any, position: int, vertex_count: int, errors: list[str]) -> Face | None:
    if not isinstance(value, dict):
        errors.append(f"faces[{position}] must be an object")
        return None
    indices = value.get("indices")
    if (not isinstance(indices, list) or len(indices) != 3 or
            any(isinstance(item, bool) or not isinstance(item, int) for item in indices)):
        errors.append(f"faces[{position}].indices must contain exactly three integer indices")
        return None
    if any(item < 0 or item >= vertex_count for item in indices):
        errors.append(f"faces[{position}] has an out-of-range vertex index")
        return None
    try:
        color = normalise_color(value.get("color"), f"faces[{position}].color")
    except ValueError as exc:
        errors.append(str(exc))
        return None
    name = value.get("name")
    if name is not None and not isinstance(name, str):
        errors.append(f"faces[{position}].name must be a string")
        return None
    return Face(tuple(indices), color, name,
                {key: item for key, item in value.items() if key not in {"indices", "color", "name"}})
