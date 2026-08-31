from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from exporter_sk3d import SK3D_MAGIC
from exporter_sk3d_v4 import Mesh, MultiMeshModel, Sk3dV4ValidationError, encode_words, validate
from model import Face
from obj2sk3d_v4 import build_single_mesh_v4_model, build_v4_model


class Sk3dV4ExporterTests(unittest.TestCase):
    def test_encodes_header_descriptors_and_global_indices(self) -> None:
        model = MultiMeshModel("two", [
            Mesh("left", (0, 0, 0), [(0, 0, 0), (1, 0, 0), (0, 1, 0)], [Face((0, 1, 2), "#112233")]),
            Mesh("right", (3, 0, 0), [(0, 0, 0), (1, 0, 0), (0, 1, 0)], [Face((0, 1, 2), "#445566")]),
        ])
        words = encode_words(model)
        self.assertEqual(words[:4], [SK3D_MAGIC, 6, 2, 0x00000204])
        self.assertEqual(words[4:12], [0, 3, 0, 1, 3, 3, 1, 1])
        self.assertEqual(words[-2], 0x00050403)

    def test_rejects_empty_or_out_of_range_mesh(self) -> None:
        empty = MultiMeshModel("bad", [Mesh("empty", (0, 0, 0), [], [])])
        self.assertTrue(any("no vertices" in error for error in validate(empty)))
        with self.assertRaises(Sk3dV4ValidationError):
            encode_words(empty)
        out_of_range = MultiMeshModel("bad", [Mesh("bad", (0, 0, 0), [(128, 0, 0), (0, 0, 0), (0, 1, 0)], [Face((0, 1, 2), "#FFFFFF")])])
        self.assertTrue(any("outside SK3D" in error for error in validate(out_of_range)))

    def test_robotss_manifest_rebuilds_pivot_local_meshes(self) -> None:
        root = Path(__file__).resolve().parents[3]
        model_root = root / "assets/3d/sources/robotss"
        model = build_v4_model(model_root / "robotss.obj", model_root / "robotss.mtl", model_root / "robotss.v4.json", 120.0, True, 1.0)
        self.assertEqual([mesh.name for mesh in model.meshes], ["leg_r", "leg_l", "arm_r", "arm_l", "body"])
        self.assertEqual(sum(len(mesh.vertices) for mesh in model.meshes), 88)
        self.assertEqual(sum(len(mesh.faces) for mesh in model.meshes), 132)
        self.assertTrue(any(abs(component) > 0.01 for component in model.meshes[0].pivot))
        self.assertEqual(validate(model), [])

    def test_blade_without_manifest_exports_one_v4_mesh(self) -> None:
        root = Path(__file__).resolve().parents[3]
        model_root = root / "assets/3d/sources/blade"
        model = build_single_mesh_v4_model(model_root / "blade.obj", model_root / "blade.mtl", 120.0, True, 1.0)
        self.assertEqual(len(model.meshes), 1)
        self.assertEqual(model.meshes[0].name, "root")
        self.assertEqual(validate(model), [])

    def test_manifest_rejects_overlap(self) -> None:
        root = Path(__file__).resolve().parents[3]
        model_root = root / "assets/3d/sources/robotss"
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / "overlap.json"
            manifest_path.write_text(json.dumps({"format": "sk3d_v4_mesh_manifest", "version": 1, "pivot_file": str(model_root / "robotss_pivot.json"), "meshes": [
                {"name": "one", "group_prefixes": ["leg_r_"], "pivot_key": "leg_r"},
                {"name": "two", "group_prefixes": ["leg_r_"], "pivot_key": "leg_r"},
            ]}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "overlaps"):
                build_v4_model(model_root / "robotss.obj", model_root / "robotss.mtl", manifest_path, 120.0, True, 1.0)


if __name__ == "__main__":
    unittest.main()
