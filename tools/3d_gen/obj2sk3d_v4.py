#!/usr/bin/env python3
"""Convert OBJ/MTL plus an explicit mesh manifest into SK3D V4 assets."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from exporter_sk3d_v4 import Mesh, MultiMeshModel, Sk3dV4ValidationError, export_bin, export_mif
from importer_obj import ObjImportError, import_obj
from model import Face
from obj2sk3d import _normalise_model
from static_shading import apply_static_face_shading


def _load_manifest(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or document.get("format") != "sk3d_v4_mesh_manifest" or document.get("version") != 1:
        raise ValueError("V4 manifest must be format sk3d_v4_mesh_manifest version 1")
    if not isinstance(document.get("meshes"), list):
        raise ValueError("V4 manifest must contain a meshes array")
    return document


def _source_pivots(manifest: dict, manifest_path: Path) -> dict[str, tuple[float, float, float]]:
    pivot_file = manifest.get("pivot_file")
    if pivot_file is None:
        return {}
    if not isinstance(pivot_file, str):
        raise ValueError("pivot_file must be a string")
    document = json.loads((manifest_path.parent / pivot_file).read_text(encoding="utf-8"))
    objects = document.get("objects")
    if not isinstance(objects, dict):
        raise ValueError("pivot file must contain an objects map")
    result = {}
    for name, value in objects.items():
        pivot = value.get("obj_pivot") if isinstance(value, dict) else None
        if not isinstance(pivot, list) or len(pivot) != 3:
            raise ValueError(f"pivot file objects.{name}.obj_pivot must contain three coordinates")
        result[name] = tuple(float(component) for component in pivot)
    return result


def _normalise_point(point: tuple[float, float, float], normalization: dict) -> tuple[float, float, float]:
    scale = float(normalization["scale"]) * float(normalization["sk3d_auto_fit_scale"])
    source_center = normalization.get("source_center", [0.0, 0.0, 0.0])
    return tuple((coordinate - float(source_center[index])) * scale for index, coordinate in enumerate(point))


def build_v4_model(obj_path: Path, mtl_path: Path, manifest_path: Path, target_height: float, center: bool, scale: float) -> MultiMeshModel:
    manifest = _load_manifest(manifest_path)
    model = import_obj(obj_path, mtl_path).model
    _normalise_model(model, target_height, center, scale)
    shaded = apply_static_face_shading(model)
    pivots = _source_pivots(manifest, manifest_path)
    claimed: set[int] = set()
    meshes: list[Mesh] = []
    for mesh_index, entry in enumerate(manifest["meshes"]):
        if not isinstance(entry, dict):
            raise ValueError(f"meshes[{mesh_index}] must be an object")
        name = entry.get("name")
        prefixes = entry.get("group_prefixes")
        pivot_key = entry.get("pivot_key")
        if not isinstance(name, str) or not name or not isinstance(prefixes, list) or not prefixes or not all(isinstance(item, str) for item in prefixes):
            raise ValueError(f"meshes[{mesh_index}] requires name and non-empty group_prefixes")
        if not isinstance(pivot_key, str) or pivot_key not in pivots:
            raise ValueError(f"meshes[{mesh_index}] pivot_key is missing from pivot_file")
        selected = [index for index, face in enumerate(shaded.faces) if isinstance(face.extra.get("group"), str) and any(face.extra["group"].startswith(prefix) for prefix in prefixes)]
        if not selected:
            raise ValueError(f"meshes[{mesh_index}] selects no OBJ faces")
        overlap = claimed.intersection(selected)
        if overlap:
            raise ValueError(f"meshes[{mesh_index}] overlaps earlier meshes at faces {sorted(overlap)}")
        claimed.update(selected)
        old_indices = sorted({vertex for face_index in selected for vertex in shaded.faces[face_index].indices})
        remap = {old: new for new, old in enumerate(old_indices)}
        pivot = _normalise_point(pivots[pivot_key], shaded.metadata["normalization"])
        vertices = [tuple(component - pivot[axis] for axis, component in enumerate(shaded.vertices[old])) for old in old_indices]
        faces = [Face(tuple(remap[index] for index in shaded.faces[face_index].indices), shaded.faces[face_index].color, shaded.faces[face_index].name, dict(shaded.faces[face_index].extra)) for face_index in selected]
        meshes.append(Mesh(name=name, pivot=pivot, vertices=vertices, faces=faces))
    missing = set(range(len(shaded.faces))) - claimed
    if missing:
        raise ValueError(f"V4 manifest leaves OBJ faces unassigned: {sorted(missing)}")
    return MultiMeshModel(shaded.name, meshes)


def build_single_mesh_v4_model(obj_path: Path, mtl_path: Path, target_height: float, center: bool, scale: float) -> MultiMeshModel:
    """Export models without a V4 manifest as one static-colour mesh."""
    model = import_obj(obj_path, mtl_path).model
    _normalise_model(model, target_height, center, scale)
    shaded = apply_static_face_shading(model)
    faces = [Face(tuple(face.indices), face.color, face.name, dict(face.extra)) for face in shaded.faces]
    return MultiMeshModel(shaded.name, [Mesh(name="root", pivot=(0.0, 0.0, 0.0), vertices=list(shaded.vertices), faces=faces)])


def write_outputs(model: MultiMeshModel, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    base = output_path.name.removesuffix(".s3d.mif")
    export_mif(model, output_path)
    export_bin(model, output_path.with_name(f"{base}.s3d.bin"))
    document = {"format": "SK3D", "version": 4, "name": model.name, "mesh_count": len(model.meshes), "meshes": [
        {"mesh_id": index, "name": mesh.name, "pivot": list(mesh.pivot), "vertex_count": len(mesh.vertices), "triangle_count": len(mesh.faces)}
        for index, mesh in enumerate(model.meshes)
    ]}
    output_path.with_name(f"{base}.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("obj", type=Path)
    parser.add_argument("--mtl", type=Path, required=True)
    manifest_group = parser.add_mutually_exclusive_group(required=True)
    manifest_group.add_argument("--manifest", type=Path)
    manifest_group.add_argument("--single-mesh", action="store_true", help="export the complete model as one V4 mesh")
    parser.add_argument("--target-height", type=float, default=120.0)
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--center", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        model = (build_v4_model(args.obj, args.mtl, args.manifest, args.target_height, args.center, args.scale)
                 if args.manifest is not None else build_single_mesh_v4_model(args.obj, args.mtl, args.target_height, args.center, args.scale))
        write_outputs(model, args.output)
    except (ObjImportError, Sk3dV4ValidationError, ValueError, json.JSONDecodeError) as exc:
        print(exc, file=sys.stderr)
        return 1
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
