from __future__ import annotations

import subprocess
import struct
import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from exporter_sk3d import SK3D_MAGIC, Sk3dValidationError, bin_bytes, encode_words, mif_text, validate
from dynamic_shading import annotate_dynamic_face_shading
from model import Face, Model
from obj2sk3d import SK3D_SAFE_COORDINATE, _normalise_model


def triangle_model() -> Model:
    return Model("triangle", (0, 0, 0), [(0, 0, 0), (1, 0, 0), (0, 1, 0)], [Face((0, 1, 2), "#FF8090")])


class Sk3dExporterTests(unittest.TestCase):
    def test_normalise_auto_fits_oversized_model_to_sk3d_range(self) -> None:
        model = Model(
            "wide",
            (0, 0, 0),
            [(-2, 0, 0), (2, 0, 0), (0, 1, 0)],
            [Face((0, 1, 2), "#FFFFFF")],
        )

        _normalise_model(model, target_height=120.0, center=True)

        self.assertLessEqual(max(abs(value) for vertex in model.vertices for value in vertex), SK3D_SAFE_COORDINATE)
        normalization = model.metadata["normalization"]
        self.assertAlmostEqual(normalization["sk3d_auto_fit_scale"], SK3D_SAFE_COORDINATE / 240.0)
        self.assertAlmostEqual(normalization["effective_target_height"], 120.0 * SK3D_SAFE_COORDINATE / 240.0)
        self.assertEqual(validate(model), [])

    def test_normalise_applies_requested_uniform_scale(self) -> None:
        model = Model(
            "scaled",
            (0, 0, 0),
            [(0, 0, 0), (1, 0, 0), (0, 1, 0)],
            [Face((0, 1, 2), "#FFFFFF")],
        )

        _normalise_model(model, target_height=120.0, center=True, scale_multiplier=0.5)

        self.assertAlmostEqual(max(vertex[1] for vertex in model.vertices) - min(vertex[1] for vertex in model.vertices), 60.0)
        normalization = model.metadata["normalization"]
        self.assertEqual(normalization["requested_scale"], 0.5)
        self.assertEqual(normalization["effective_target_height"], 60.0)

    def test_minimal_triangle_encoding(self) -> None:
        words = encode_words(triangle_model())
        self.assertEqual(words[:4], [SK3D_MAGIC, 3, 1, 2])
        self.assertEqual(words[10:], [0x00020100, 0xF2])
        self.assertEqual(bin_bytes(triangle_model()), struct.pack(f"<{len(words)}I", *words))

    def test_dynamic_triangle_encoding_includes_materials_and_surfaces(self) -> None:
        dynamic_model = annotate_dynamic_face_shading(
            Model(
                "quad",
                (0, 0, 0),
                [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)],
                [
                    Face((0, 1, 2), "#CC801A", extra={"material": "fur", "group": "head"}),
                    Face((0, 2, 3), "#CC801A", extra={"material": "fur", "group": "head"}),
                ],
                metadata={"materials": {"fur": "#CC801A"}},
            )
        )

        words = encode_words(dynamic_model)

        self.assertEqual(words[:4], [SK3D_MAGIC, 4, 2, 0x0001_0103])
        self.assertEqual(len(words), 4 + (4 * 2) + 1 + 1 + (2 * 2))
        self.assertEqual(words[-4], 0x00020100)
        self.assertEqual(words[-3], 0x0000)
        self.assertEqual(words[-2], 0x00030200)
        self.assertEqual(words[-1], 0x0000)

    def test_capacity_and_degenerate_fail(self) -> None:
        model = triangle_model()
        model.vertices.extend([(0, 0, 1)] * 126)
        model.faces.extend([Face((0, 1, 2), "#000000")] * 192)
        self.assertTrue(any("1..128" in issue for issue in validate(model)))
        model = triangle_model()
        model.faces[0].indices = (0, 0, 1)  # type: ignore[assignment]
        with self.assertRaises(Sk3dValidationError):
            encode_words(model)

    def test_cat1_asset_matches_checked_in_mif(self) -> None:
        root = Path(__file__).resolve().parents[3]
        model = Model.load(root / "assets/3d/generated/cat1/legacy_v3/cat1.json")
        expected = (root / "assets/3d/generated/cat1/legacy_v3/cat1.s3d.mif").read_text(encoding="ascii")
        self.assertEqual((len(model.vertices), len(model.faces)), (98, 144))
        self.assertEqual(mif_text(model), expected)

    def test_cli_generates_deterministic_cat1_outputs(self) -> None:
        root = Path(__file__).resolve().parents[3]
        script = root / "tools/3d_gen/obj2sk3d.py"
        obj_path = root / "assets/3d/sources/cat1/cat1.obj"
        mtl_path = root / "assets/3d/sources/cat1/cat1.mtl"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "cat1.s3d.mif"
            subprocess.run(
                [sys.executable, str(script), str(obj_path), "--mtl", str(mtl_path),
                 "--target-height", "120", "--center", "--output", str(output)],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )
            checked_in = (root / "assets/3d/generated/cat1/legacy_v3/cat1.s3d.mif").read_text(encoding="ascii")
            self.assertEqual(output.read_text(encoding="ascii"), checked_in)
            self.assertTrue((Path(directory) / "cat1.json").exists())
            self.assertTrue((Path(directory) / "cat1_ref_pkg.svh").exists())
            self.assertEqual(
                (Path(directory) / "cat1.s3d.bin").read_bytes(),
                bin_bytes(Model.load(root / "assets/3d/generated/cat1/legacy_v3/cat1.json")),
            )
            self.assertTrue((Path(directory) / "cat1_shade.json").exists())
            self.assertTrue((Path(directory) / "cat1_shade.s3d.mif").exists())
            self.assertTrue((Path(directory) / "cat1_shade.s3d.bin").exists())
            self.assertTrue((Path(directory) / "cat1_shade_ref_pkg.svh").exists())
            self.assertNotEqual(
                (Path(directory) / "cat1_shade.s3d.mif").read_text(encoding="ascii"),
                checked_in,
            )
