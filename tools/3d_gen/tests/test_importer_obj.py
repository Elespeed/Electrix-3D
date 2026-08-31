from __future__ import annotations

import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from importer_obj import ObjImportError, import_obj, load_mtl


class ObjImporterTests(unittest.TestCase):
    def test_mtl_and_obj_import_preserve_group_and_material(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mtl_path = root / "cat.mtl"
            obj_path = root / "cat.obj"
            mtl_path.write_text(
                "newmtl Fur\n"
                "Kd 0.8 0.5 0.1\n"
                "newmtl Eye\n"
                "Kd 0 0 0\n",
                encoding="utf-8",
            )
            obj_path.write_text(
                "mtllib cat.mtl\n"
                "g body\n"
                "v 0 0 0\n"
                "v 1 0 0\n"
                "v 0 1 0\n"
                "usemtl Fur\n"
                "f 1 2 3\n",
                encoding="utf-8",
            )
            imported = import_obj(obj_path, mtl_path)
            self.assertEqual(load_mtl(mtl_path)["Fur"], "#CC801A")
            self.assertEqual(len(imported.model.vertices), 3)
            self.assertEqual(imported.model.faces[0].indices, (0, 1, 2))
            self.assertEqual(imported.model.faces[0].color, "#CC801A")
            self.assertEqual(imported.model.faces[0].name, "body")
            self.assertEqual(imported.model.faces[0].extra["material"], "Fur")
            self.assertEqual(imported.model.faces[0].extra["object_name"], "body")
            self.assertEqual(imported.model.faces[0].extra["object_id"], 1)
            self.assertEqual(imported.model.metadata["source"]["obj"], "cat.obj")
            self.assertEqual(imported.model.metadata["object_table"][0]["name"], "body")

    def test_non_triangle_and_missing_material_fail_fast(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mtl_path = root / "bad.mtl"
            obj_path = root / "bad.obj"
            mtl_path.write_text("newmtl Fur\nKd 0.5 0.5 0.5\n", encoding="utf-8")
            obj_path.write_text(
                "v 0 0 0\n"
                "v 1 0 0\n"
                "v 1 1 0\n"
                "v 0 1 0\n"
                "f 1 2 3 4\n",
                encoding="utf-8",
            )
            with self.assertRaises(ObjImportError) as caught:
                import_obj(obj_path, mtl_path)
            self.assertTrue(any("triangulated" in message for message in caught.exception.errors))

    def test_object_name_prefers_o_over_g(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mtl_path = root / "demo.mtl"
            obj_path = root / "demo.obj"
            mtl_path.write_text("newmtl Fur\nKd 0.8 0.5 0.1\n", encoding="utf-8")
            obj_path.write_text(
                "o leg_rf\n"
                "g body_group\n"
                "v 0 0 0\n"
                "v 1 0 0\n"
                "v 0 1 0\n"
                "usemtl Fur\n"
                "f 1 2 3\n",
                encoding="utf-8",
            )
            imported = import_obj(obj_path, mtl_path)
            face = imported.model.faces[0]
            self.assertEqual(face.extra["object_name"], "leg_rf")
            self.assertEqual(face.extra["group"], "body_group")
            self.assertEqual(face.extra["object_id"], 1)
            self.assertEqual(imported.model.metadata["object_table"], [{"object_id": 1, "name": "leg_rf", "face_indices": [0]}])

    def test_group_name_is_used_when_object_name_is_absent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mtl_path = root / "demo.mtl"
            obj_path = root / "demo.obj"
            mtl_path.write_text("newmtl Fur\nKd 0.8 0.5 0.1\n", encoding="utf-8")
            obj_path.write_text(
                "g leg_lb\n"
                "v 0 0 0\n"
                "v 1 0 0\n"
                "v 0 1 0\n"
                "usemtl Fur\n"
                "f 1 2 3\n",
                encoding="utf-8",
            )
            imported = import_obj(obj_path, mtl_path)
            self.assertEqual(imported.model.faces[0].extra["object_name"], "leg_lb")
            self.assertEqual(imported.model.metadata["object_table"][0]["name"], "leg_lb")

    def test_connected_components_supply_stable_object_names_without_o_or_g(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mtl_path = root / "demo.mtl"
            obj_path = root / "demo.obj"
            mtl_path.write_text("newmtl Fur\nKd 0.8 0.5 0.1\n", encoding="utf-8")
            obj_path.write_text(
                "v 0 0 0\n"
                "v 1 0 0\n"
                "v 0 1 0\n"
                "v 10 0 0\n"
                "v 11 0 0\n"
                "v 10 1 0\n"
                "usemtl Fur\n"
                "f 1 2 3\n"
                "f 4 5 6\n",
                encoding="utf-8",
            )
            imported = import_obj(obj_path, mtl_path)
            self.assertEqual([face.extra["object_name"] for face in imported.model.faces], ["component_0", "component_1"])
            self.assertEqual([face.extra["object_id"] for face in imported.model.faces], [1, 2])
            self.assertEqual(
                imported.model.metadata["object_table"],
                [
                    {"object_id": 1, "name": "component_0", "face_indices": [0]},
                    {"object_id": 2, "name": "component_1", "face_indices": [1]},
                ],
            )
