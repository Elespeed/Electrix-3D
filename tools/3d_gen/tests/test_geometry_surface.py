from __future__ import annotations

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from geometry_surface import reconstruct_surfaces
from model import Face, Model


class GeometrySurfaceTests(unittest.TestCase):
    def test_coplanar_quad_reconstructs_one_surface(self) -> None:
        model = Model(
            "quad",
            (0.0, 0.0, 0.0),
            [(0.0, 0.0, 1.0), (1.0, 0.0, 1.0), (1.0, 1.0, 1.0), (0.0, 1.0, 1.0)],
            [
                Face((0, 1, 2), "#CC801A"),
                Face((0, 2, 3), "#00FF00"),
            ],
        )

        surfaces = reconstruct_surfaces(model)

        self.assertEqual(len(surfaces), 1)
        self.assertEqual(surfaces[0].face_indices, [0, 1])

    def test_non_coplanar_hinge_stays_split(self) -> None:
        model = Model(
            "hinge",
            (0.0, 0.0, 0.0),
            [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (1.0, 1.0, 0.2)],
            [
                Face((0, 1, 2), "#CC801A"),
                Face((1, 3, 2), "#CC801A"),
            ],
        )

        surfaces = reconstruct_surfaces(model)

        self.assertEqual(len(surfaces), 2)
        self.assertEqual([surface.face_indices for surface in surfaces], [[0], [1]])

    def test_welded_duplicate_vertices_still_merge_surface(self) -> None:
        model = Model(
            "welded",
            (0.0, 0.0, 0.0),
            [
                (0.0, 0.0, 1.0),
                (1.0, 0.0, 1.0),
                (1.0, 1.0, 1.0),
                (0.0, 0.0, 1.0),
                (1.0, 1.0, 1.0),
                (0.0, 1.0, 1.0),
            ],
            [
                Face((0, 1, 2), "#CC801A"),
                Face((3, 4, 5), "#CC801A"),
            ],
        )

        surfaces = reconstruct_surfaces(model)

        self.assertEqual(len(surfaces), 1)
        self.assertEqual(surfaces[0].face_indices, [0, 1])

    def test_cube_reconstructs_six_surfaces(self) -> None:
        vertices = [
            (-1.0, -1.0, -1.0),
            (1.0, -1.0, -1.0),
            (1.0, 1.0, -1.0),
            (-1.0, 1.0, -1.0),
            (-1.0, -1.0, 1.0),
            (1.0, -1.0, 1.0),
            (1.0, 1.0, 1.0),
            (-1.0, 1.0, 1.0),
        ]
        faces = [
            Face((0, 1, 2), "#FFFFFF"), Face((0, 2, 3), "#FFFFFF"),
            Face((4, 6, 5), "#FFFFFF"), Face((4, 7, 6), "#FFFFFF"),
            Face((0, 4, 5), "#FFFFFF"), Face((0, 5, 1), "#FFFFFF"),
            Face((3, 2, 6), "#FFFFFF"), Face((3, 6, 7), "#FFFFFF"),
            Face((0, 3, 7), "#FFFFFF"), Face((0, 7, 4), "#FFFFFF"),
            Face((1, 5, 6), "#FFFFFF"), Face((1, 6, 2), "#FFFFFF"),
        ]
        surfaces = reconstruct_surfaces(Model("cube", (0.0, 0.0, 0.0), vertices, faces))

        self.assertEqual(len(surfaces), 6)
        self.assertTrue(all(len(surface.face_indices) == 2 for surface in surfaces))
