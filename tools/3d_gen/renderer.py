"""Offline orthographic reference renderer for SketchBook low-poly assets."""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
import hashlib
import math
from pathlib import Path
from typing import Any

from dynamic_surface_shading import SHADE_LEVELS_Q15
from color_rgb332 import hex_to_rgb332, rgb332_to_hex, shade_hex_rgb332
from geometry_surface import face_normal, unit_normal
from model import Face, Model, normalise_color
from profiles import RenderProfile, resolve_profile

SIN16 = (0, 24, 45, 59, 64, 59, 45, 24, 0, -24, -45, -59, -64, -59, -45, -24)
LITE_Q15_ONE = 32767
LIGHT_X_Q15 = -11400
LIGHT_Y_Q15 = 16300
LIGHT_Z_Q15 = -26050
_LIGHT_VECTOR = tuple(component / LITE_Q15_ONE for component in (LIGHT_X_Q15, LIGHT_Y_Q15, LIGHT_Z_Q15))
SHADE_LEVELS = tuple(level / LITE_Q15_ONE for level in SHADE_LEVELS_Q15)
_EPSILON = 1e-6
FOCUS_YAW_INDICES = (0, 3, 4, 12)
_DEPTH_EPSILON = 1e-6
BUCKET_LEVELS_Q15 = {
    "back_bottom": 24248,
    "side": 26869,
    "top": 30473,
    "front": LITE_Q15_ONE,
}
BUCKET_LEVELS = {key: value / LITE_Q15_ONE for key, value in BUCKET_LEVELS_Q15.items()}


@dataclass(frozen=True)
class SurfaceShade:
    surface_id: int
    source_normal: tuple[float, float, float]
    lambert: float
    shade_level: int
    shade_intensity: float


@dataclass(frozen=True)
class RenderConfig:
    frame_width: int = 400
    frame_height: int = 300
    target_height: float = 120.0
    center: bool = True
    yaw_steps: int = 16
    background: str = "#00FF00"
    profile: RenderProfile | str = "no_zbuffer"
    output_root: Path | str | None = None
    debug_surface_colors: bool = False
    debug_normals: bool = False
    enable_object_outline: bool = False
    outline_color: tuple[int, int, int] | None = None
    outline_connectivity: int | None = None
    include_silhouette: bool | None = None

    def __post_init__(self) -> None:
        if self.frame_width <= 0 or self.frame_height <= 0:
            raise ValueError("frame dimensions must be positive")
        if self.target_height <= 0.0:
            raise ValueError("target height must be positive")
        if self.yaw_steps <= 0:
            raise ValueError("yaw_steps must be positive")
        normalise_color(self.background, "background")
        if not isinstance(self.profile, RenderProfile):
            object.__setattr__(self, "profile", resolve_profile(str(self.profile)))
        if self.output_root is not None and not isinstance(self.output_root, Path):
            object.__setattr__(self, "output_root", Path(self.output_root))
        if self.outline_color is None:
            object.__setattr__(self, "outline_color", self.profile.outline_color)
        if self.outline_connectivity is None:
            object.__setattr__(self, "outline_connectivity", self.profile.outline_connectivity)
        if self.include_silhouette is None:
            object.__setattr__(self, "include_silhouette", self.profile.include_silhouette)
        if self.outline_connectivity not in (4,):
            raise ValueError("outline_connectivity must be 4")
        if len(self.outline_color) != 3 or any(channel < 0 or channel > 255 for channel in self.outline_color):
            raise ValueError("outline_color must contain three 0..255 channels")
        if self.enable_object_outline and not self.profile.use_zbuffer:
            raise ValueError("object outline requires a Z-buffer-enabled profile")
        if self.profile.enable_object_outline:
            object.__setattr__(self, "enable_object_outline", True)
        if self.debug_surface_colors and self.debug_normals:
            raise ValueError("debug_surface_colors and debug_normals are mutually exclusive")

    def to_summary(self) -> dict[str, Any]:
        return {
            "frame_width": self.frame_width,
            "frame_height": self.frame_height,
            "target_height": self.target_height,
            "center": self.center,
            "yaw_steps": self.yaw_steps,
            "background": self.background,
            "profile": self.profile.name,
            "pitch_degrees": self.profile.pitch_degrees,
            "debug_surface_colors": self.debug_surface_colors,
            "debug_normals": self.debug_normals,
            "enable_object_outline": self.enable_object_outline,
            "outline_connectivity": self.outline_connectivity,
            "include_silhouette": self.include_silhouette,
            "outline_color": list(self.outline_color),
        }


@dataclass
class FrameResult:
    yaw_index: int
    yaw_degrees: float
    pixels: bytes
    triangles: list[dict[str, Any]]
    visible_count: int
    frame_hash: str
    depth_stats: dict[str, Any] | None
    occlusion_stats: dict[str, Any]
    object_id_debug_pixels: bytes | None = None
    outline_mask_pixels: bytes | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "yaw_index": self.yaw_index,
            "yaw_degrees": round(self.yaw_degrees, 6),
            "visible_count": self.visible_count,
            "frame_hash": self.frame_hash,
            "depth_stats": self.depth_stats,
            "occlusion_stats": self.occlusion_stats,
            "triangles": self.triangles,
        }


@dataclass
class RenderReport:
    asset_name: str
    config: dict[str, Any]
    frames: list[FrameResult]
    focus_frame_indices: list[int]

    def to_dict(self) -> dict[str, Any]:
        focus_set = set(self.focus_frame_indices)
        return {
            "asset_name": self.asset_name,
            "config": self.config,
            "focus_frame_indices": self.focus_frame_indices,
            "focus_frames": [
                {
                    "yaw_index": frame.yaw_index,
                    "yaw_degrees": round(frame.yaw_degrees, 6),
                    "visible_count": frame.visible_count,
                    "frame_hash": frame.frame_hash,
                    "depth_stats": frame.depth_stats,
                    "occlusion_stats": frame.occlusion_stats,
                }
                for frame in self.frames
                if frame.yaw_index in focus_set
            ],
            "frames": [frame.to_dict() for frame in self.frames],
        }


@dataclass
class RasterResult:
    winner_buffer: list[int]
    depth_buffer: list[float] | None
    object_id_buffer: list[int] | None
    stats: dict[str, int]


def render_frame(model: Model, config: RenderConfig, yaw_index: int) -> FrameResult:
    _ensure_object_metadata(model)
    prepared = _normalise_model_copy(model, config.target_height, config.center)
    return _render_prepared(prepared, config, yaw_index)


def render_sweep(model: Model, config: RenderConfig) -> RenderReport:
    _ensure_object_metadata(model)
    prepared = _normalise_model_copy(model, config.target_height, config.center)
    frames = [_render_prepared(prepared, config, yaw_index) for yaw_index in range(config.yaw_steps)]
    focus_frames = [index for index in FOCUS_YAW_INDICES if index < config.yaw_steps]
    return RenderReport(asset_name=prepared.name, config=config.to_summary(), frames=frames, focus_frame_indices=focus_frames)


def _normalise_model_copy(model: Model, target_height: float, center: bool) -> Model:
    copied = Model(
        name=model.name,
        origin=tuple(model.origin),
        vertices=list(model.vertices),
        faces=[Face(tuple(face.indices), face.color, face.name, deepcopy(face.extra)) for face in model.faces],
        metadata=deepcopy(model.metadata),
        extra=deepcopy(model.extra),
    )
    if not copied.vertices:
        raise ValueError("model has no vertices")
    min_y = min(vertex[1] for vertex in copied.vertices)
    max_y = max(vertex[1] for vertex in copied.vertices)
    source_height = max_y - min_y
    if source_height <= 0.0:
        raise ValueError("model height must be positive before scaling")

    scale = target_height / source_height
    scaled = [(vertex[0] * scale, vertex[1] * scale, vertex[2] * scale) for vertex in copied.vertices]
    if center:
        min_x = min(vertex[0] for vertex in scaled)
        max_x = max(vertex[0] for vertex in scaled)
        min_y = min(vertex[1] for vertex in scaled)
        max_y = max(vertex[1] for vertex in scaled)
        min_z = min(vertex[2] for vertex in scaled)
        max_z = max(vertex[2] for vertex in scaled)
        center_xyz = ((min_x + max_x) / 2.0, (min_y + max_y) / 2.0, (min_z + max_z) / 2.0)
        scaled = [(x - center_xyz[0], y - center_xyz[1], z - center_xyz[2]) for x, y, z in scaled]
    copied.vertices = scaled
    copied.origin = (0.0, 0.0, 0.0)
    _ensure_object_metadata(copied)
    return copied


def _ensure_object_metadata(model: Model) -> None:
    if all(isinstance(face.extra.get("object_id"), int) and not isinstance(face.extra.get("object_id"), bool) for face in model.faces):
        if isinstance(model.metadata.get("object_table"), list):
            return

    explicit_names = [_face_object_name(face) for face in model.faces]
    if any(name is None for name in explicit_names):
        component_names = _build_face_component_names(model)
        resolved_names = [
            explicit_name if explicit_name is not None else component_name
            for explicit_name, component_name in zip(explicit_names, component_names)
        ]
    else:
        resolved_names = [str(name) for name in explicit_names]

    object_ids_by_name: dict[str, int] = {}
    face_indices_by_name: dict[str, list[int]] = {}
    object_table: list[dict[str, Any]] = []
    for face_index, (face, object_name) in enumerate(zip(model.faces, resolved_names)):
        object_id = object_ids_by_name.get(object_name)
        if object_id is None:
            object_id = len(object_table) + 1
            object_ids_by_name[object_name] = object_id
            face_indices_by_name[object_name] = []
            object_table.append({"object_id": object_id, "name": object_name, "face_indices": face_indices_by_name[object_name]})
        face_indices_by_name[object_name].append(face_index)
        face.extra["object_name"] = object_name
        face.extra["object_id"] = object_id
    model.metadata["object_table"] = object_table


def _face_object_name(face: Face) -> str | None:
    for key in ("object_name", "group"):
        value = face.extra.get(key)
        if isinstance(value, str) and value:
            return value
    return face.name if isinstance(face.name, str) and face.name else None


def _build_face_component_names(model: Model) -> list[str]:
    face_indices_by_vertex: list[list[int]] = [[] for _ in model.vertices]
    for face_index, face in enumerate(model.faces):
        for vertex_index in face.indices:
            face_indices_by_vertex[vertex_index].append(face_index)

    face_components = [-1] * len(model.faces)
    component_count = 0
    for start_face_index in range(len(model.faces)):
        if face_components[start_face_index] >= 0:
            continue
        pending = [start_face_index]
        face_components[start_face_index] = component_count
        while pending:
            current_face_index = pending.pop()
            for vertex_index in model.faces[current_face_index].indices:
                for neighbour_face_index in face_indices_by_vertex[vertex_index]:
                    if face_components[neighbour_face_index] >= 0:
                        continue
                    face_components[neighbour_face_index] = component_count
                    pending.append(neighbour_face_index)
        component_count += 1
    return [f"component_{component_index}" for component_index in face_components]


def _render_prepared(model: Model, config: RenderConfig, yaw_index: int) -> FrameResult:
    yaw_index %= config.yaw_steps
    coeff_sin, coeff_cos = _yaw_coefficients(yaw_index, config.yaw_steps)
    pitch_radians = math.radians(config.profile.pitch_degrees)
    pitch_sin = math.sin(pitch_radians)
    pitch_cos = math.cos(pitch_radians)
    background = _hex_to_rgb(config.background)
    transformed = _transform_vertices(
        model, config.frame_width, config.frame_height, coeff_sin, coeff_cos, pitch_sin, pitch_cos,
    )
    surface_shades = _build_surface_shade_cache(
        model,
        use_shading=config.profile.use_shading,
        shading_mode=config.profile.shading_mode,
        debug_surface_colors=config.debug_surface_colors,
        debug_normals=config.debug_normals,
        sin_yaw=coeff_sin / 64.0,
        cos_yaw=coeff_cos / 64.0,
        sin_pitch=pitch_sin,
        cos_pitch=pitch_cos,
    )
    triangle_info: list[dict[str, Any]] = []
    visible_triangles: list[dict[str, Any]] = []
    for face_index, face in enumerate(model.faces):
        info = _prepare_triangle(
            face_index,
            face,
            model,
            transformed,
            config.frame_width,
            config.frame_height,
            config.profile.use_shading,
            surface_shades,
            shading_mode=config.profile.shading_mode,
            debug_surface_colors=config.debug_surface_colors,
            debug_normals=config.debug_normals,
        )
        triangle_info.append(info)
        if not info["culled"] and info["bbox_clipped"] is not None:
            visible_triangles.append(info)

    painter_order = sorted(visible_triangles, key=lambda item: item["painter_depth"])
    painter_raster = _rasterize_frame(config.frame_width, config.frame_height, painter_order, use_zbuffer=False)
    zbuffer_raster = _rasterize_frame(config.frame_width, config.frame_height, visible_triangles, use_zbuffer=True)
    active_raster = zbuffer_raster if config.profile.use_zbuffer else painter_raster

    pixels = _compose_pixels(
        config.frame_width,
        config.frame_height,
        background,
        active_raster.winner_buffer,
        triangle_info,
    )
    object_id_debug_pixels = None
    outline_mask_pixels = None
    if config.enable_object_outline:
        object_ids = active_raster.object_id_buffer
        if object_ids is None:
            raise ValueError("object outline requires object_id_buffer")
        outline_mask = build_object_outline_mask(
            object_ids,
            width=config.frame_width,
            height=config.frame_height,
            include_silhouette=bool(config.include_silhouette),
            connectivity=int(config.outline_connectivity),
        )
        object_id_debug_pixels = _object_id_debug_pixels(object_ids)
        outline_mask_pixels = _outline_mask_pixels(outline_mask)
        pixels = _apply_outline_pixels(pixels, outline_mask, tuple(config.outline_color))
    depth_stats = _summarise_depth(active_raster.depth_buffer) if active_raster.depth_buffer is not None else None
    occlusion_stats = _build_occlusion_stats(
        config.frame_width,
        config.frame_height,
        visible_triangles,
        painter_raster,
        zbuffer_raster,
    )
    frame_hash = hashlib.sha256(pixels).hexdigest()
    return FrameResult(
        yaw_index=yaw_index,
        yaw_degrees=(360.0 * yaw_index) / config.yaw_steps,
        pixels=bytes(pixels),
        triangles=triangle_info,
        visible_count=len(visible_triangles),
        frame_hash=frame_hash,
        depth_stats=depth_stats,
        occlusion_stats=occlusion_stats,
        object_id_debug_pixels=object_id_debug_pixels,
        outline_mask_pixels=outline_mask_pixels,
    )


def _yaw_coefficients(yaw_index: int, yaw_steps: int) -> tuple[int, int]:
    if yaw_steps == 16:
        return SIN16[yaw_index & 0xF], SIN16[(yaw_index + 4) & 0xF]
    angle = (2.0 * math.pi * yaw_index) / yaw_steps
    return int(round(math.sin(angle) * 64.0)), int(round(math.cos(angle) * 64.0))


def _transform_vertices(
    model: Model,
    frame_width: int,
    frame_height: int,
    coeff_sin: int,
    coeff_cos: int,
    pitch_sin: float,
    pitch_cos: float,
) -> list[dict[str, int]]:
    cx = frame_width // 2
    cy = frame_height // 2
    transformed: list[dict[str, int]] = []
    for vertex in model.vertices:
        qx, qy, qz = (int(round((value - origin) * 256.0)) for value, origin in zip(vertex, model.origin))
        tx = ((qx * coeff_cos) + (qz * coeff_sin)) >> 14
        ty = qy >> 8
        tz = ((-qx * coeff_sin) + (qz * coeff_cos)) >> 14
        if pitch_sin:
            ty, tz = round((ty * pitch_cos) - (tz * pitch_sin)), round((ty * pitch_sin) + (tz * pitch_cos))
        transformed.append({
            "tx": tx,
            "ty": ty,
            "tz": tz,
            "sx": cx + tx,
            "sy": cy - ty,
        })
    return transformed


def _prepare_triangle(
    face_index: int,
    face: Face,
    model: Model,
    transformed: list[dict[str, int]],
    frame_width: int,
    frame_height: int,
    use_shading: bool,
    surface_shades: dict[int, SurfaceShade] | None,
    *,
    shading_mode: str,
    debug_surface_colors: bool,
    debug_normals: bool,
) -> dict[str, Any]:
    v0, v1, v2 = (transformed[item] for item in face.indices)
    screen_vertices = [(v0["sx"], v0["sy"]), (v1["sx"], v1["sy"]), (v2["sx"], v2["sy"])]
    depth_vertices = [v0["tz"], v1["tz"], v2["tz"]]
    area2 = ((screen_vertices[1][0] - screen_vertices[0][0]) * (screen_vertices[2][1] - screen_vertices[0][1]) -
             (screen_vertices[2][0] - screen_vertices[0][0]) * (screen_vertices[1][1] - screen_vertices[0][1]))
    bbox_clipped = _clip_bbox(screen_vertices, frame_width, frame_height)
    lambert = 1.0
    shade_level = None
    shade_intensity = 1.0
    shaded_color = face.color
    shade_source = "baked_face_color"
    surface_id = face.extra.get("surface_id")
    object_id = face.extra.get("object_id")
    surface_normal = None
    static_shaded_asset = "static_face_shading" in model.metadata
    dynamic_shaded_asset = "dynamic_surface_shading" in model.metadata
    if use_shading and not static_shaded_asset:
        if dynamic_shaded_asset:
            material_id = face.extra.get("material_id")
            if shading_mode == "bucket":
                if not isinstance(surface_id, int) or surface_shades is None or surface_id not in surface_shades:
                    raise ValueError(f"dynamic bucket shading requires valid surface_id on face {face_index}")
                surface_shade = surface_shades[surface_id]
                lambert = surface_shade.lambert
                shade_level = surface_shade.shade_level
                shade_intensity = surface_shade.shade_intensity
                surface_normal = [round(component, 6) for component in surface_shade.source_normal]
                shaded_color = _shade_hex_q15(face.color, int(round(shade_intensity * LITE_Q15_ONE)))
                shade_source = "dynamic_surface_bucket"
            else:
                if not isinstance(surface_id, int) or surface_shades is None or surface_id not in surface_shades:
                    raise ValueError(f"dynamic surface shading requires valid surface_id on face {face_index}")
                surface_shade = surface_shades[surface_id]
                lambert = surface_shade.lambert
                shade_level = surface_shade.shade_level
                shade_intensity = surface_shade.shade_intensity
                surface_normal = [round(component, 6) for component in surface_shade.source_normal]
                shaded_color = _resolve_material_shade_color(model, material_id, shade_level, face.color)
                shade_source = "dynamic_surface"
        else:
            lambert = _shade_diffuse(model, face)
            shade_level, shade_intensity = _quantise_lambert(lambert)
            shaded_color = _shade_hex(face.color, shade_intensity)
            shade_source = "dynamic_lambert"
    if dynamic_shaded_asset and isinstance(surface_id, int) and surface_shades is not None and surface_id in surface_shades:
        surface_normal = [round(component, 6) for component in surface_shades[surface_id].source_normal]
        if debug_surface_colors:
            shaded_color = _surface_debug_color(surface_id)
            shade_source = "debug_surface_colors"
        elif debug_normals:
            shaded_color = _normal_debug_color(tuple(surface_normal))
            shade_source = "debug_normals"
    return {
        "face_index": face_index,
        "indices": list(face.indices),
        "name": face.name,
        "material": face.extra.get("material"),
        "group": face.extra.get("group"),
        "base_color": face.color,
        "shaded_color": shaded_color,
        "screen_vertices": [list(vertex) for vertex in screen_vertices],
        "depth_vertices": depth_vertices,
        "painter_depth": sum(depth_vertices),
        "lambert_intensity": round(lambert, 6),
        "shade_level": shade_level,
        "shade_intensity": round(shade_intensity, 6),
        "shade_source": shade_source,
        "surface_id": surface_id,
        "object_id": object_id,
        "surface_normal": surface_normal,
        "screen_area2": area2,
        # Screen Y is flipped after projection, so +Z front faces have
        # negative screen-space winding and non-negative area is back-facing.
        "culled": area2 >= 0,
        "bbox_clipped": bbox_clipped,
    }


def _build_surface_shade_cache(
    model: Model,
    *,
    use_shading: bool,
    shading_mode: str,
    debug_surface_colors: bool,
    debug_normals: bool,
    sin_yaw: float,
    cos_yaw: float,
    sin_pitch: float,
    cos_pitch: float,
) -> dict[int, SurfaceShade] | None:
    shading = model.metadata.get("dynamic_surface_shading")
    if not isinstance(shading, dict):
        return None
    surfaces = shading.get("surfaces")
    if not isinstance(surfaces, list):
        raise ValueError("dynamic surface shading metadata must include surfaces")
    if not use_shading and not debug_surface_colors and not debug_normals:
        return {}

    surface_shades: dict[int, SurfaceShade] = {}
    for surface in surfaces:
        if not isinstance(surface, dict):
            raise ValueError("dynamic surface shading surface entries must be objects")
        surface_id = surface.get("surface_id")
        canonical_normal = surface.get("canonical_normal")
        if (
            isinstance(surface_id, bool) or not isinstance(surface_id, int) or
            not isinstance(canonical_normal, list) or len(canonical_normal) != 3
        ):
            raise ValueError("dynamic surface shading requires surface_id and canonical_normal[3]")
        nx, ny, nz = (float(component) for component in canonical_normal)
        rvx = (cos_yaw * nx) + (sin_yaw * nz)
        rvy = ny
        rvz = (-sin_yaw * nx) + (cos_yaw * nz)
        pvy = (cos_pitch * rvy) - (sin_pitch * rvz)
        pvz = (sin_pitch * rvy) + (cos_pitch * rvz)
        if shading_mode == "bucket":
            bucket_name, shade_level, shade_intensity = _quantise_bucket_normal((rvx, pvy, pvz))
            lambert = shade_intensity
        else:
            bucket_name = None
            lambert = max(0.0, min(1.0, (rvx * _LIGHT_VECTOR[0]) + (pvy * _LIGHT_VECTOR[1]) + (pvz * _LIGHT_VECTOR[2])))
            shade_level, shade_intensity = _quantise_lambert(lambert)
        surface_shades[surface_id] = SurfaceShade(
            surface_id=surface_id,
            source_normal=(nx, ny, nz),
            lambert=lambert,
            shade_level=shade_level,
            shade_intensity=shade_intensity,
        )
    return surface_shades


def _resolve_material_shade_color(model: Model, material_id: Any, shade_level: int | None, fallback_color: str) -> str:
    if not isinstance(shade_level, int):
        return fallback_color
    shading = model.metadata.get("dynamic_surface_shading")
    if not isinstance(shading, dict):
        return fallback_color
    materials = shading.get("materials")
    if not isinstance(materials, list):
        return fallback_color
    if isinstance(material_id, bool) or not isinstance(material_id, int) or not 0 <= material_id < len(materials):
        return fallback_color
    material = materials[material_id]
    if not isinstance(material, dict):
        return fallback_color
    shade_colors = material.get("shade_colors")
    if not isinstance(shade_colors, list) or not 0 <= shade_level < len(shade_colors):
        return fallback_color
    return str(shade_colors[shade_level])


def _rasterize_frame(
    frame_width: int,
    frame_height: int,
    triangles: list[dict[str, Any]],
    *,
    use_zbuffer: bool,
) -> RasterResult:
    winner_buffer = [-1] * (frame_width * frame_height)
    depth_buffer = None if not use_zbuffer else [float("-inf")] * (frame_width * frame_height)
    object_id_buffer = [0] * (frame_width * frame_height)
    stats = {"equal_depth_overwrite_count": 0}
    for info in triangles:
        _draw_triangle(
            winner_buffer,
            depth_buffer,
            object_id_buffer,
            frame_width,
            frame_height,
            info["screen_vertices"],
            info["depth_vertices"],
            info["face_index"],
            int(info["object_id"]) if isinstance(info["object_id"], int) else 0,
            stats,
        )
    return RasterResult(
        winner_buffer=winner_buffer,
        depth_buffer=depth_buffer,
        object_id_buffer=object_id_buffer,
        stats=stats,
    )


def _compose_pixels(
    frame_width: int,
    frame_height: int,
    background: tuple[int, int, int],
    winner_buffer: list[int],
    triangles: list[dict[str, Any]],
) -> bytes:
    pixels = bytearray(background * (frame_width * frame_height))
    for pixel_index, triangle_index in enumerate(winner_buffer):
        if triangle_index < 0:
            continue
        color = _hex_to_rgb(rgb332_to_hex(hex_to_rgb332(triangles[triangle_index]["shaded_color"])))
        base = pixel_index * 3
        pixels[base:base + 3] = bytes(color)
    return bytes(pixels)


def _build_occlusion_stats(
    frame_width: int,
    frame_height: int,
    visible_triangles: list[dict[str, Any]],
    painter_raster: RasterResult,
    zbuffer_raster: RasterResult,
) -> dict[str, Any]:
    overlap_flags = {triangle["face_index"]: False for triangle in visible_triangles}
    first_cover = [-1] * (frame_width * frame_height)
    first_depth = [None] * (frame_width * frame_height)
    overlap_pixels = 0
    shared_edge_candidate_pixels = 0
    for triangle in visible_triangles:
        face_index = triangle["face_index"]
        for pixel_index, depth in _iter_triangle_pixels(
            frame_width,
            frame_height,
            triangle["screen_vertices"],
            triangle["depth_vertices"],
        ):
            owner = first_cover[pixel_index]
            if owner == -1:
                first_cover[pixel_index] = face_index
                first_depth[pixel_index] = depth
            elif owner != face_index:
                if owner >= 0:
                    overlap_flags[owner] = True
                overlap_flags[face_index] = True
                if owner >= 0:
                    overlap_pixels += 1
                    prev_depth = first_depth[pixel_index]
                    if prev_depth is not None and abs(prev_depth - depth) <= _DEPTH_EPSILON:
                        shared_edge_candidate_pixels += 1
                first_cover[pixel_index] = -2
            elif owner == -2:
                overlap_flags[face_index] = True

    conflict_triangles: set[int] = set()
    corrected_pixels = 0
    filled_pixels = 0
    painter_winners = painter_raster.winner_buffer
    zbuffer_winners = zbuffer_raster.winner_buffer
    for painter_winner, zbuffer_winner in zip(painter_winners, zbuffer_winners):
        if zbuffer_winner >= 0:
            filled_pixels += 1
        if painter_winner != zbuffer_winner and zbuffer_winner >= 0:
            corrected_pixels += 1
            if painter_winner >= 0:
                conflict_triangles.add(painter_winner)
            conflict_triangles.add(zbuffer_winner)

    visible_depths = [depth for triangle in visible_triangles for depth in triangle["depth_vertices"]]
    depth_span = None
    depth_min = None
    depth_max = None
    if visible_depths:
        depth_min = min(visible_depths)
        depth_max = max(visible_depths)
        depth_span = depth_max - depth_min

    tiny_bbox_triangle_count = 0
    for triangle in visible_triangles:
        bbox = triangle["bbox_clipped"]
        if bbox is None:
            continue
        if (bbox[2] - bbox[0]) <= 2 or (bbox[3] - bbox[1]) <= 2:
            tiny_bbox_triangle_count += 1

    return {
        "visible_triangle_count": len(visible_triangles),
        "overlap_triangle_count": sum(1 for value in overlap_flags.values() if value),
        "overlap_pixel_count": overlap_pixels,
        "shared_edge_candidate_count": shared_edge_candidate_pixels,
        "painter_z_conflict_triangle_count": len(conflict_triangles),
        "zbuffer_corrected_pixel_count": corrected_pixels,
        "zbuffer_corrected_pixel_ratio": 0.0 if filled_pixels == 0 else round(corrected_pixels / filled_pixels, 6),
        "equal_depth_overwrite_count": zbuffer_raster.stats["equal_depth_overwrite_count"],
        "tiny_bbox_triangle_count": tiny_bbox_triangle_count,
        "filled_pixel_count": filled_pixels,
        "depth_min": depth_min,
        "depth_max": depth_max,
        "depth_span": depth_span,
    }


def _clip_bbox(screen_vertices: list[tuple[int, int]], frame_width: int, frame_height: int) -> list[int] | None:
    min_x = max(0, min(vertex[0] for vertex in screen_vertices))
    max_x = min(frame_width - 1, max(vertex[0] for vertex in screen_vertices))
    min_y = max(0, min(vertex[1] for vertex in screen_vertices))
    max_y = min(frame_height - 1, max(vertex[1] for vertex in screen_vertices))
    if min_x > max_x or min_y > max_y:
        return None
    return [min_x, min_y, max_x, max_y]


def _shade_diffuse(model: Model, face: Face) -> float:
    nx, ny, nz = unit_normal(face_normal(model.vertices, face))
    dot = (nx * _LIGHT_VECTOR[0]) + (ny * _LIGHT_VECTOR[1]) + (nz * _LIGHT_VECTOR[2])
    return max(0.0, min(1.0, dot))


def _quantise_lambert(diffuse: float) -> tuple[int, float]:
    if diffuse >= 0.75:
        level = 3
    elif diffuse >= 0.50:
        level = 2
    elif diffuse >= 0.25:
        level = 1
    else:
        level = 0
    return level, SHADE_LEVELS[level]


def _quantise_bucket_normal(view_normal: tuple[float, float, float]) -> tuple[str, int, float]:
    nx, ny, nz = view_normal
    dominant_axis = max(range(3), key=lambda index: abs((nx, ny, nz)[index]))
    component = (nx, ny, nz)[dominant_axis]
    if dominant_axis == 2:
        if component <= 0.0:
            return "front", 3, BUCKET_LEVELS["front"]
        return "back_bottom", 0, BUCKET_LEVELS["back_bottom"]
    if dominant_axis == 1:
        if component >= 0.0:
            return "top", 2, BUCKET_LEVELS["top"]
        return "back_bottom", 0, BUCKET_LEVELS["back_bottom"]
    return "side", 1, BUCKET_LEVELS["side"]


def _shade_hex(color: str, intensity: float) -> str:
    return _shade_hex_q15(color, int(round(intensity * LITE_Q15_ONE)))


def _shade_hex_q15(color: str, intensity_q15: int) -> str:
    return shade_hex_rgb332(color, intensity_q15, 0)


def _surface_debug_color(surface_id: int) -> str:
    digest = hashlib.sha256(f"surface:{surface_id}".encode("ascii")).digest()
    return f"#{digest[0]:02X}{digest[1]:02X}{digest[2]:02X}"


def _normal_debug_color(normal: tuple[float, float, float]) -> str:
    x, y, z = unit_normal(normal)
    return f"#{int(round((x + 1.0) * 127.5)):02X}{int(round((y + 1.0) * 127.5)):02X}{int(round((z + 1.0) * 127.5)):02X}"


def _object_id_debug_color(object_id: int) -> tuple[int, int, int]:
    if object_id == 0:
        return (0, 0, 0)
    value = (object_id * 0x45D9F3B) & 0xFFFFFFFF
    value ^= value >> 16
    return (
        64 + (value & 0xBF),
        64 + ((value >> 8) & 0xBF),
        64 + ((value >> 16) & 0xBF),
    )


def _object_id_debug_pixels(object_ids: list[int]) -> bytes:
    pixels = bytearray()
    for object_id in object_ids:
        pixels.extend(_object_id_debug_color(object_id))
    return bytes(pixels)


def _outline_mask_pixels(mask: list[bool]) -> bytes:
    pixels = bytearray()
    for enabled in mask:
        pixels.extend((255, 255, 255) if enabled else (0, 0, 0))
    return bytes(pixels)


def _apply_outline_pixels(
    pixels: bytes,
    outline_mask: list[bool],
    outline_color: tuple[int, int, int],
) -> bytes:
    outlined = bytearray(pixels)
    for pixel_index, enabled in enumerate(outline_mask):
        if not enabled:
            continue
        base = pixel_index * 3
        outlined[base:base + 3] = bytes(outline_color)
    return bytes(outlined)


def build_object_outline_mask(
    object_ids: list[int],
    *,
    width: int,
    height: int,
    include_silhouette: bool = True,
    connectivity: int = 4,
) -> list[bool]:
    if connectivity != 4:
        raise ValueError("only 4-connectivity is supported")
    if len(object_ids) != width * height:
        raise ValueError("object_ids size does not match width*height")

    mask = [False] * len(object_ids)
    for y in range(height):
        for x in range(width):
            pixel_index = (y * width) + x
            center_id = object_ids[pixel_index]
            if center_id == 0:
                continue
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx = x + dx
                ny = y + dy
                if not (0 <= nx < width and 0 <= ny < height):
                    if include_silhouette:
                        mask[pixel_index] = True
                        break
                    continue
                neighbour_id = object_ids[(ny * width) + nx]
                if neighbour_id == center_id:
                    continue
                if neighbour_id == 0 and not include_silhouette:
                    continue
                mask[pixel_index] = True
                break
    return mask


def _draw_triangle(
    winner_buffer: list[int],
    zbuffer: list[float] | None,
    object_id_buffer: list[int],
    frame_width: int,
    frame_height: int,
    screen_vertices: list[list[int]],
    depth_vertices: list[int],
    triangle_index: int,
    object_id: int,
    stats: dict[str, int],
) -> None:
    for pixel_index, depth in _iter_triangle_pixels(
        frame_width,
        frame_height,
        screen_vertices,
        depth_vertices,
    ):
        if zbuffer is not None:
            current_depth = zbuffer[pixel_index]
            current_winner = winner_buffer[pixel_index]
            if depth < current_depth - _DEPTH_EPSILON:
                continue
            if abs(depth - current_depth) <= _DEPTH_EPSILON and current_winner >= 0:
                if current_winner <= triangle_index:
                    continue
                stats["equal_depth_overwrite_count"] += 1
            zbuffer[pixel_index] = depth
        winner_buffer[pixel_index] = triangle_index
        object_id_buffer[pixel_index] = object_id


def _iter_triangle_pixels(
    frame_width: int,
    frame_height: int,
    screen_vertices: list[list[int]],
    depth_vertices: list[int],
) -> Any:
    vertices = screen_vertices
    depths = depth_vertices
    bbox = _clip_bbox([(vertex[0], vertex[1]) for vertex in vertices], frame_width, frame_height)
    if bbox is None:
        return
    x0, y0 = vertices[0]
    x1, y1 = vertices[1]
    x2, y2 = vertices[2]
    area2 = ((x1 - x0) * (y2 - y0)) - ((x2 - x0) * (y1 - y0))
    if area2 == 0:
        return
    if area2 < 0:
        # The edge walker is written against positive screen-space winding.
        # Normalize clockwise faces here so culling and fill share one raster rule.
        vertices = [vertices[0], vertices[2], vertices[1]]
        depths = [depths[0], depths[2], depths[1]]
        x0, y0 = vertices[0]
        x1, y1 = vertices[1]
        x2, y2 = vertices[2]
        area2 = -area2
    min_x, min_y, max_x, max_y = bbox
    edges = (
        ((x0, y0), (x1, y1), _is_top_left_edge(x0, y0, x1, y1)),
        ((x1, y1), (x2, y2), _is_top_left_edge(x1, y1, x2, y2)),
        ((x2, y2), (x0, y0), _is_top_left_edge(x2, y2, x0, y0)),
    )
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            px = x + 0.5
            py = y + 0.5
            edge_values = [_edge_function(start, end, px, py) for start, end, _ in edges]
            if not _is_inside_triangle(edge_values, edges):
                continue
            l0 = edge_values[1] / area2
            l1 = edge_values[2] / area2
            l2 = edge_values[0] / area2
            depth = (l0 * depths[0]) + (l1 * depths[1]) + (l2 * depths[2])
            yield (y * frame_width) + x, depth


def _edge_function(start: tuple[int, int], end: tuple[int, int], px: float, py: float) -> float:
    return ((end[0] - start[0]) * (py - start[1])) - ((end[1] - start[1]) * (px - start[0]))


def _is_top_left_edge(x0: int, y0: int, x1: int, y1: int) -> bool:
    dy = y1 - y0
    dx = x1 - x0
    return dy < 0 or (dy == 0 and dx > 0)


def _is_inside_triangle(
    edge_values: list[float],
    edges: tuple[tuple[tuple[int, int], tuple[int, int], bool], ...],
) -> bool:
    for value, (_, _, is_top_left) in zip(edge_values, edges):
        if value > _EPSILON:
            continue
        if abs(value) <= _EPSILON and is_top_left:
            continue
        return False
    return True


def _summarise_depth(zbuffer: list[float] | None) -> dict[str, Any]:
    if zbuffer is None:
        return {"filled_pixels": 0, "min_depth": None, "max_depth": None}
    finite = [value for value in zbuffer if value != float("-inf")]
    if not finite:
        return {"filled_pixels": 0, "min_depth": None, "max_depth": None}
    return {
        "filled_pixels": len(finite),
        "min_depth": round(min(finite), 6),
        "max_depth": round(max(finite), 6),
    }


def _hex_to_rgb(color: str) -> tuple[int, int, int]:
    normalised = normalise_color(color)
    return int(normalised[1:3], 16), int(normalised[3:5], 16), int(normalised[5:7], 16)
