from __future__ import annotations

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from model import Face, Model
from static_shading import (
    STATIC_SHADE_LEVELS,
    apply_static_face_shading,
    classify_normal_bucket,
    face_normal,
)


class StaticFaceShadingTests(unittest.TestCase):
    def test_dominant_axis_bucket_mapping_matches_style_rules(self) -> None:
        self.assertEqual(classify_normal_bucket((0.0, 0.0, -4.0))[0], "front")
        self.assertEqual(classify_normal_bucket((0.0, 3.0, 0.0))[0], "top")
        self.assertEqual(classify_normal_bucket((5.0, 0.0, 0.0))[0], "side")
        self.assertEqual(classify_normal_bucket((-5.0, 0.0, 0.0))[0], "side")
        self.assertEqual(classify_normal_bucket((0.0, 0.0, 6.0))[0], "front")
        self.assertEqual(classify_normal_bucket((0.0, -2.0, 0.0))[0], "back_bottom")

    def test_static_shading_preserves_geometry_and_annotates_faces(self) -> None:
        model = Model(
            "buckets",
            (0.0, 0.0, 0.0),
            [
                (0.0, 0.0, 0.0),
                (0.0, 0.0, 1.0),
                (1.0, 0.0, 0.0),
                (0.0, 1.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#CC801A", "top_like"),
                Face((0, 3, 1), "#CC801A", "side_like"),
                Face((0, 2, 3), "#CC801A", "back_like"),
                Face((0, 3, 2), "#CC801A", "front_like"),
            ],
            metadata={"source": {"obj": "demo.obj"}},
        )

        shaded = apply_static_face_shading(model)

        self.assertEqual(shaded.vertices, model.vertices)
        self.assertEqual([face.indices for face in shaded.faces], [face.indices for face in model.faces])
        self.assertIn("static_face_shading", shaded.metadata)
        buckets = [face.extra["static_shade_bucket"] for face in shaded.faces]
        self.assertEqual(buckets, ["top", "side", "front", "front"])
        self.assertEqual(shaded.faces[0].extra["static_shade_intensity"], round(STATIC_SHADE_LEVELS["top"], 6))
        self.assertEqual(shaded.faces[1].extra["static_shade_intensity"], round(STATIC_SHADE_LEVELS["side"], 6))
        self.assertEqual(shaded.faces[2].extra["static_shade_intensity"], round(STATIC_SHADE_LEVELS["front"], 6))
        self.assertEqual(shaded.faces[3].extra["static_shade_intensity"], round(STATIC_SHADE_LEVELS["front"], 6))
        self.assertNotEqual(shaded.faces[0].color, model.faces[0].color)

    def test_face_normal_matches_expected_orientation(self) -> None:
        vertices = [(0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0)]
        normal = face_normal(vertices, Face((0, 1, 2), "#FFFFFF"))
        self.assertEqual(normal, (0.0, 1.0, 0.0))

    def test_static_shading_groups_connected_coplanar_triangles_into_one_surface(self) -> None:
        model = Model(
            "quad",
            (0.0, 0.0, 0.0),
            [
                (0.0, 0.0, 1.0),
                (1.0, 0.0, 1.0),
                (1.0, 1.0, 1.0),
                (0.0, 1.0, 1.0),
                (2.0, 0.0, 1.0),
                (2.0, 1.0, 1.0),
            ],
            [
                Face((0, 1, 2), "#CC801A", "front_a", {"group": "head", "material": "fur"}),
                Face((0, 2, 3), "#CC801A", "front_b", {"group": "head", "material": "fur"}),
                Face((1, 4, 5), "#CC801A", "front_c", {"group": "head", "material": "fur"}),
            ],
        )

        shaded = apply_static_face_shading(model)

        self.assertEqual(shaded.faces[0].extra["static_shade_surface_id"], shaded.faces[1].extra["static_shade_surface_id"])
        self.assertEqual(shaded.faces[0].extra["static_shade_surface_face_count"], 2)
        self.assertEqual(shaded.faces[0].color, shaded.faces[1].color)
        self.assertNotEqual(shaded.faces[0].extra["static_shade_surface_id"], shaded.faces[2].extra["static_shade_surface_id"])
        self.assertEqual(shaded.faces[2].extra["static_shade_surface_face_count"], 1)

    def test_static_shading_does_not_merge_connected_faces_that_are_not_coplanar(self) -> None:
        model = Model(
            "hinge",
            (0.0, 0.0, 0.0),
            [
                (0.0, 0.0, 0.0),
                (1.0, 0.0, 0.0),
                (0.0, 1.0, 0.0),
                (1.0, 1.0, 0.2),
            ],
            [
                Face((0, 1, 2), "#CC801A", "left", {"group": "head", "material": "fur"}),
                Face((1, 3, 2), "#CC801A", "right", {"group": "head", "material": "fur"}),
            ],
        )

        shaded = apply_static_face_shading(model)

        self.assertNotEqual(shaded.faces[0].extra["static_shade_surface_id"], shaded.faces[1].extra["static_shade_surface_id"])
        self.assertEqual(shaded.faces[0].extra["static_shade_surface_face_count"], 1)
        self.assertEqual(shaded.faces[1].extra["static_shade_surface_face_count"], 1)
