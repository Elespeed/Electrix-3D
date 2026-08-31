"""Compatibility wrapper for dynamic surface shading."""
from __future__ import annotations

from dynamic_surface_shading import (
    LIGHT_VECTOR_Q8,
    LITE_Q15_ONE,
    SHADE_LEVELS,
    SHADE_LEVELS_Q15,
    annotate_dynamic_face_shading,
    annotate_dynamic_surface_shading,
    shade_hex_rgb332,
    unit_normal,
)

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
