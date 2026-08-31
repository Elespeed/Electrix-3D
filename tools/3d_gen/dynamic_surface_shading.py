"""Dynamic surface-level shading metadata for low-poly Sketch assets."""
from __future__ import annotations

from copy import deepcopy
from typing import Any

from color_rgb332 import hex_to_rgb332, shade_hex_rgb332 as _shade_hex_rgb332
from geometry_surface import reconstruct_surfaces, unit_normal
from model import Face, Model

LITE_Q15_ONE = 32767
SHADE_LEVELS_Q15 = (13107, 19660, 26214, LITE_Q15_ONE)
SHADE_LEVELS = tuple(level / LITE_Q15_ONE for level in SHADE_LEVELS_Q15)
LIGHT_VECTOR_Q8 = (-89, 127, -203)


def shade_hex_rgb332(color: str, intensity_q15: int) -> str:
    return _shade_hex_rgb332(color, intensity_q15, SHADE_LEVELS_Q15[0])


def _material_order(model: Model) -> list[tuple[str, str]]:
    ordered: list[tuple[str, str]] = []
    seen: set[str] = set()
    material_colors = model.metadata.get("materials", {})
    for face in model.faces:
        material_name = str(face.extra.get("material", face.color))
        if material_name in seen:
            continue
        base_color = material_colors.get(material_name, face.color) if isinstance(material_colors, dict) else face.color
        ordered.append((material_name, str(base_color)))
        seen.add(material_name)
    return ordered


def annotate_dynamic_surface_shading(model: Model) -> Model:
    annotated = Model(
        name=model.name,
        origin=tuple(model.origin),
        vertices=list(model.vertices),
        faces=[],
        metadata=deepcopy(model.metadata),
        extra=deepcopy(model.extra),
    )

    materials = _material_order(model)
    material_id_by_name = {name: index for index, (name, _) in enumerate(materials)}
    material_entries: list[dict[str, Any]] = []
    for material_id, (material_name, base_color) in enumerate(materials):
        shade_colors = [shade_hex_rgb332(base_color, level) for level in SHADE_LEVELS_Q15]
        material_entries.append({
            "material_id": material_id,
            "name": material_name,
            "base_color": base_color,
            "shade_colors": shade_colors,
            "shade_colors_rgb332": [hex_to_rgb332(color) for color in shade_colors],
        })

    surfaces = reconstruct_surfaces(model)
    surface_info_by_face: dict[int, dict[str, Any]] = {}
    surface_entries: list[dict[str, Any]] = []
    for surface in surfaces:
        entry = {
            "surface_id": surface.surface_id,
            "face_indices": list(surface.face_indices),
            "face_count": len(surface.face_indices),
            "canonical_normal": [round(component, 6) for component in surface.canonical_normal],
            "canonical_normal_q8": [int(round(component * 256.0)) for component in surface.canonical_normal],
        }
        surface_entries.append(entry)
        for face_index in surface.face_indices:
            surface_info_by_face[face_index] = entry

    for face_index, face in enumerate(model.faces):
        surface_info = surface_info_by_face[face_index]
        material_name = str(face.extra.get("material", face.color))
        extra = dict(face.extra)
        extra["material_id"] = material_id_by_name[material_name]
        extra["surface_id"] = surface_info["surface_id"]
        annotated.faces.append(Face(tuple(face.indices), face.color, face.name, extra))

    annotated.metadata["dynamic_surface_shading"] = {
        "mode": "reconstructed_surface_directional_v1",
        "shade_levels_q15": list(SHADE_LEVELS_Q15),
        "light_vector_q8": list(LIGHT_VECTOR_Q8),
        "materials": material_entries,
        "surfaces": surface_entries,
    }
    return annotated


def annotate_dynamic_face_shading(model: Model) -> Model:
    return annotate_dynamic_surface_shading(model)


__all__ = [
    "LIGHT_VECTOR_Q8",
    "LITE_Q15_ONE",
    "SHADE_LEVELS",
    "SHADE_LEVELS_Q15",
    "annotate_dynamic_face_shading",
    "annotate_dynamic_surface_shading",
    "shade_hex_rgb332",
    "unit_normal",
]
