"""Fixed rendering profiles for the offline 3D reference renderer."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class RenderProfile:
    name: str
    use_zbuffer: bool
    use_shading: bool
    shading_mode: str
    pitch_degrees: float
    description: str
    enable_object_outline: bool = False
    outline_connectivity: int = 4
    include_silhouette: bool = True
    outline_color: tuple[int, int, int] = (40, 28, 20)


PROFILES: dict[str, RenderProfile] = {
    "no_zbuffer": RenderProfile(
        name="no_zbuffer",
        use_zbuffer=False,
        use_shading=False,
        shading_mode="none",
        pitch_degrees=0.0,
        description="Back-face cull plus average-Z painter sort, matching the current Sketch flow.",
    ),
    "zbuffer": RenderProfile(
        name="zbuffer",
        use_zbuffer=True,
        use_shading=False,
        shading_mode="none",
        pitch_degrees=0.0,
        description="Back-face cull plus per-pixel Z-buffer visibility.",
    ),
    "zbuffer_object_outline": RenderProfile(
        name="zbuffer_object_outline",
        use_zbuffer=True,
        use_shading=False,
        shading_mode="none",
        pitch_degrees=0.0,
        description="Z-buffer visibility plus visible object-ID outline post-processing.",
        enable_object_outline=True,
    ),
}

PROFILE_ALIASES: dict[str, str] = {}


def resolve_profile(name: str) -> RenderProfile:
    key = PROFILE_ALIASES.get(name, name)
    try:
        return PROFILES[key]
    except KeyError as exc:
        valid = ", ".join(sorted(set(PROFILES) | set(PROFILE_ALIASES)))
        raise ValueError(f"unknown profile '{name}'; expected one of: {valid}") from exc
