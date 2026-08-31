from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools/3d_gen/robotss_articulation/robotss_walk.py"
SPEC = importlib.util.spec_from_file_location("robotss_walk", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
robotss_walk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(robotss_walk)


class RobotssArticulationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        imported = robotss_walk.import_obj(robotss_walk.ASSET_ROOT / "robotss.obj", robotss_walk.ASSET_ROOT / "robotss.mtl")
        cls.base = imported.model
        cls.owners = robotss_walk.build_vertex_part_map(cls.base)
        cls.pivots = robotss_walk._load_pivots(robotss_walk.ASSET_ROOT / "robotss_pivot.json")

    def test_every_vertex_has_one_expected_part(self) -> None:
        self.assertGreater(len(self.owners), 0)
        self.assertTrue(set(self.owners).issubset(set(robotss_walk.PARTS)))
        self.assertTrue(set(robotss_walk.MOVING_PARTS).issubset(set(self.owners)))

    def test_neutral_reference_check_reports_a_result(self) -> None:
        result = robotss_walk._verify_neutral(self.base, self.owners, self.pivots, ROOT / "assets/3d/generated/robotss/legacy_v3/robotss_shade.json")
        self.assertTrue(result["checked"])
        self.assertIsInstance(result["matches"], bool)

    def test_pivots_are_fixed_and_opposite_limbs_have_opposite_roll(self) -> None:
        posed, angles = robotss_walk.pose_obj_model(self.base, self.owners, self.pivots, 4, 16, 25.0)
        self.assertEqual(angles["arm_l"], angles["leg_r"])
        self.assertEqual(angles["arm_l"], -angles["arm_r"])
        for vertex, owner, transformed in zip(self.base.vertices, self.owners, posed.vertices):
            if owner == "body":
                self.assertEqual(vertex, transformed)
        for part in ("arm_l", "arm_r", "leg_l", "leg_r"):
            self.assertEqual(robotss_walk._roll_rotate(self.pivots[part], self.pivots[part], angles[part]), self.pivots[part])

    def test_front_view_roll_moves_every_limb_in_the_screen_plane(self) -> None:
        posed, _ = robotss_walk.pose_obj_model(self.base, self.owners, self.pivots, 4, 16, 25.0)
        for part in ("arm_l", "arm_r", "leg_l", "leg_r"):
            self.assertTrue(any(
                owner == part and abs(original[0] - transformed[0]) > 1e-8
                for original, owner, transformed in zip(self.base.vertices, self.owners, posed.vertices)
            ), part)

    def test_generated_v4_meshes_recompose_with_exported_pivots(self) -> None:
        meshes, vertices, faces = robotss_walk.load_v4_model(
            robotss_walk.V4_ASSET_ROOT / "robotss_shade.s3d.mif",
            robotss_walk.V4_ASSET_ROOT / "robotss_shade.json",
        )
        posed, angles = robotss_walk.pose_v4_model(meshes, vertices, faces, 0, 16, 25.0)
        self.assertEqual(len(meshes), 5)
        self.assertEqual(len(posed.vertices), 88)
        self.assertEqual(len(posed.faces), 132)
        self.assertTrue(all(value == 0.0 for value in angles.values()))


if __name__ == "__main__":
    unittest.main()
