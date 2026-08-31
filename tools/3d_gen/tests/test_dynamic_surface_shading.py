from __future__ import annotations

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dynamic_surface_shading import annotate_dynamic_surface_shading
from model import Face, Model


class DynamicSurfaceShadingTests(unittest.TestCase):
    def test_annotation_uses_surface_ids_and_surface_metadata(self) -> None:
        model = Model(
            "quad",
            (0.0, 0.0, 0.0),
            [(0.0, 0.0, 1.0), (1.0, 0.0, 1.0), (1.0, 1.0, 1.0), (0.0, 1.0, 1.0)],
            [
                Face((0, 1, 2), "#CC801A", extra={"material": "fur"}),
                Face((0, 2, 3), "#000000", extra={"material": "eyes"}),
            ],
            metadata={"materials": {"fur": "#CC801A", "eyes": "#000000"}},
        )

        annotated = annotate_dynamic_surface_shading(model)

        self.assertIn("dynamic_surface_shading", annotated.metadata)
        shading = annotated.metadata["dynamic_surface_shading"]
        self.assertEqual(len(shading["surfaces"]), 1)
        self.assertEqual(annotated.faces[0].extra["surface_id"], annotated.faces[1].extra["surface_id"])
        self.assertNotIn("unit_normal", annotated.faces[0].extra)
        self.assertEqual(shading["surfaces"][0]["face_indices"], [0, 1])
