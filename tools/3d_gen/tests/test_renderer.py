from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from model import Face, Model
from renderer import RenderConfig, render_frame, render_sweep


def rgb_at(pixels: bytes, width: int, x: int, y: int) -> tuple[int, int, int]:
    base = ((y * width) + x) * 3
    return pixels[base], pixels[base + 1], pixels[base + 2]


def filled_pixels(pixels: bytes) -> int:
    return sum(1 for base in range(0, len(pixels), 3) if pixels[base:base + 3] != b"\x00\x00\x00")


OUTLINE_RGB = (40, 28, 20)


class RendererTests(unittest.TestCase):
    def test_no_zbuffer_single_triangle_is_deterministic(self) -> None:
        model = Model(
            "triangle",
            (0.0, 0.0, 0.0),
            [(-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (0.0, 1.0, 0.0)],
            [Face((0, 1, 2), "#FF0000")],
        )
        config = RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="no_zbuffer")
        frame_a = render_frame(model, config, yaw_index=0)
        frame_b = render_frame(model, config, yaw_index=0)
        self.assertEqual(frame_a.frame_hash, frame_b.frame_hash)
        self.assertEqual(frame_a.visible_count, 1)
        self.assertEqual(rgb_at(frame_a.pixels, 32, 16, 16), (255, 0, 0))
        self.assertEqual(frame_a.occlusion_stats["visible_triangle_count"], 1)
        self.assertEqual(frame_a.occlusion_stats["painter_z_conflict_triangle_count"], 0)
        self.assertEqual(frame_a.occlusion_stats["zbuffer_corrected_pixel_count"], 0)

    def test_front_facing_triangle_remains_visible(self) -> None:
        model = Model(
            "front_face",
            (0.0, 0.0, 0.0),
            [(-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (0.0, 1.0, 0.0)],
            [Face((0, 1, 2), "#FF0000")],
        )
        frame = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer"), 0)
        self.assertEqual(frame.visible_count, 1)
        self.assertFalse(frame.triangles[0]["culled"])
        self.assertEqual(rgb_at(frame.pixels, 32, 16, 16), (255, 0, 0))

    def test_back_facing_triangle_is_culled(self) -> None:
        model = Model(
            "back_face",
            (0.0, 0.0, 0.0),
            [(-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (0.0, 1.0, 0.0)],
            [Face((0, 2, 1), "#FF0000")],
        )
        frame = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer"), 0)
        self.assertEqual(frame.visible_count, 0)
        self.assertTrue(frame.triangles[0]["culled"])
        self.assertEqual(rgb_at(frame.pixels, 32, 16, 16), (0, 255, 0))

    def test_front_eye_quad_disappears_when_head_turns_away(self) -> None:
        model = Model(
            "head_with_eye_quad",
            (0.0, 0.0, 0.0),
            [
                (-2.0, -2.0, -2.0), (2.0, -2.0, -2.0), (2.0, 2.0, -2.0), (-2.0, 2.0, -2.0),
                (-2.0, -2.0, 2.0), (2.0, -2.0, 2.0), (2.0, 2.0, 2.0), (-2.0, 2.0, 2.0),
                (-0.8, -0.3, 2.2), (0.8, -0.3, 2.2), (0.8, 0.8, 2.2), (-0.8, 0.8, 2.2),
            ],
            [
                Face((4, 5, 6), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((4, 6, 7), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((0, 3, 2), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((0, 2, 1), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((0, 4, 7), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((0, 7, 3), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((1, 2, 6), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((1, 6, 5), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((3, 7, 6), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((3, 6, 2), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((0, 1, 5), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((0, 5, 4), "#CC801A", extra={"object_id": 1, "object_name": "head"}),
                Face((8, 9, 10), "#00B7FF", extra={"object_id": 2, "object_name": "eye"}),
                Face((8, 10, 11), "#00B7FF", extra={"object_id": 2, "object_name": "eye"}),
            ],
            metadata={
                "object_table": [
                    {"object_id": 1, "name": "head", "face_indices": list(range(12))},
                    {"object_id": 2, "name": "eye", "face_indices": [12, 13]},
                ]
            },
        )
        config = RenderConfig(frame_width=48, frame_height=48, target_height=16, profile="zbuffer")

        front = render_frame(model, config, 0)
        back = render_frame(model, config, 8)

        self.assertEqual(rgb_at(front.pixels, 48, 24, 24), (0, 182, 255))
        self.assertGreater(sum(1 for tri in front.triangles if tri.get("object_id") == 2 and not tri["culled"]), 0)
        self.assertEqual(sum(1 for tri in back.triangles if tri.get("object_id") == 2 and not tri["culled"]), 0)
        self.assertNotEqual(rgb_at(back.pixels, 48, 24, 24), (0, 183, 255))

    def test_zbuffer_resolves_overlap_that_no_zbuffer_gets_wrong(self) -> None:
        model = Model(
            "overlap",
            (0.0, 0.0, 0.0),
            [
                (-2.0, -2.0, 100.0),
                (2.0, -2.0, -100.0),
                (0.0, 2.0, -100.0),
                (-2.0, -2.0, 0.0),
                (2.0, -2.0, 0.0),
                (0.0, 2.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#FF0000"),
                Face((3, 4, 5), "#0000FF"),
            ],
        )
        no_z = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="no_zbuffer"), 0)
        zbuf = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer"), 0)
        self.assertEqual(rgb_at(no_z.pixels, 32, 14, 17), (0, 0, 255))
        self.assertEqual(rgb_at(zbuf.pixels, 32, 14, 17), (255, 0, 0))
        self.assertGreater(zbuf.depth_stats["filled_pixels"], 0)
        self.assertGreater(zbuf.occlusion_stats["painter_z_conflict_triangle_count"], 0)
        self.assertGreater(zbuf.occlusion_stats["zbuffer_corrected_pixel_count"], 0)
        self.assertGreater(zbuf.occlusion_stats["zbuffer_corrected_pixel_ratio"], 0.0)
        self.assertIn("shared_edge_candidate_count", zbuf.occlusion_stats)
        self.assertIn("equal_depth_overwrite_count", zbuf.occlusion_stats)
        self.assertIn("tiny_bbox_triangle_count", zbuf.occlusion_stats)

    def test_shared_edge_rectangle_has_no_seam_in_no_zbuffer(self) -> None:
        model = Model(
            "shared_edge_quad",
            (0.0, 0.0, 0.0),
            [
                (-2.0, -2.0, 0.0),
                (2.0, -2.0, 0.0),
                (-2.0, 2.0, 0.0),
                (2.0, 2.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#00FF00"),
                Face((1, 3, 2), "#00FF00"),
            ],
        )
        frame = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, background="#000000", profile="no_zbuffer"), 0)
        self.assertEqual(filled_pixels(frame.pixels), 64)
        self.assertEqual(rgb_at(frame.pixels, 32, 16, 16), (0, 255, 0))
        self.assertEqual(rgb_at(frame.pixels, 32, 12, 12), (0, 255, 0))
        self.assertEqual(rgb_at(frame.pixels, 32, 19, 19), (0, 255, 0))
        self.assertEqual(frame.occlusion_stats["shared_edge_candidate_count"], 0)

    def test_shared_edge_rectangle_has_no_seam_in_zbuffer(self) -> None:
        model = Model(
            "shared_edge_quad_z",
            (0.0, 0.0, 0.0),
            [
                (-2.0, -2.0, 0.0),
                (2.0, -2.0, 0.0),
                (-2.0, 2.0, 0.0),
                (2.0, 2.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#00FF00"),
                Face((1, 3, 2), "#00FF00"),
            ],
        )
        frame = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, background="#000000", profile="zbuffer"), 0)
        self.assertEqual(filled_pixels(frame.pixels), 64)
        self.assertEqual(rgb_at(frame.pixels, 32, 16, 16), (0, 255, 0))
        self.assertEqual(rgb_at(frame.pixels, 32, 12, 12), (0, 255, 0))
        self.assertEqual(rgb_at(frame.pixels, 32, 19, 19), (0, 255, 0))
        self.assertEqual(frame.occlusion_stats["shared_edge_candidate_count"], 0)

    def test_object_outline_ignores_internal_diagonal_for_same_object(self) -> None:
        model = Model(
            "outlined_shared_object",
            (0.0, 0.0, 0.0),
            [
                (-2.0, -2.0, 0.0),
                (2.0, -2.0, 0.0),
                (-2.0, 2.0, 0.0),
                (2.0, 2.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#00FF00", extra={"object_id": 1, "object_name": "body"}),
                Face((1, 3, 2), "#00FF00", extra={"object_id": 1, "object_name": "body"}),
            ],
            metadata={"object_table": [{"object_id": 1, "name": "body", "face_indices": [0, 1]}]},
        )
        frame = render_frame(
            model,
            RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer_object_outline"),
            0,
        )
        self.assertEqual(rgb_at(frame.pixels, 32, 16, 16), (0, 255, 0))
        self.assertEqual(rgb_at(frame.pixels, 32, 12, 12), OUTLINE_RGB)
        self.assertIsNotNone(frame.object_id_debug_pixels)
        self.assertIsNotNone(frame.outline_mask_pixels)

    def test_object_outline_marks_boundary_between_different_objects_with_same_color(self) -> None:
        model = Model(
            "outlined_two_objects",
            (0.0, 0.0, 0.0),
            [
                (-4.0, -2.0, 0.0),
                (0.0, -2.0, 0.0),
                (-4.0, 2.0, 0.0),
                (0.0, 2.0, 0.0),
                (0.0, -2.0, 0.0),
                (4.0, -2.0, 0.0),
                (0.0, 2.0, 0.0),
                (4.0, 2.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#00FF00", extra={"object_id": 1, "group": "left"}),
                Face((1, 3, 2), "#00FF00", extra={"object_id": 1, "group": "left"}),
                Face((4, 5, 6), "#00FF00", extra={"object_id": 2, "group": "right"}),
                Face((5, 7, 6), "#00FF00", extra={"object_id": 2, "group": "right"}),
            ],
            metadata={
                "object_table": [
                    {"object_id": 1, "name": "left", "face_indices": [0, 1]},
                    {"object_id": 2, "name": "right", "face_indices": [2, 3]},
                ]
            },
        )
        frame = render_frame(
            model,
            RenderConfig(frame_width=48, frame_height=32, target_height=8, profile="zbuffer_object_outline"),
            0,
        )
        left_debug = rgb_at(frame.object_id_debug_pixels, 48, 16, 16)
        right_debug = rgb_at(frame.object_id_debug_pixels, 48, 30, 16)
        self.assertNotEqual(left_debug, right_debug)
        self.assertEqual(rgb_at(frame.pixels, 48, 23, 16), OUTLINE_RGB)
        self.assertEqual(rgb_at(frame.pixels, 48, 24, 16), OUTLINE_RGB)

    def test_object_outline_hidden_object_does_not_change_visible_result(self) -> None:
        front_only = Model(
            "front_only",
            (0.0, 0.0, 0.0),
            [(-2.0, -2.0, 0.0), (2.0, -2.0, 0.0), (-2.0, 2.0, 0.0), (2.0, 2.0, 0.0)],
            [
                Face((0, 1, 2), "#00FF00", extra={"object_id": 1, "group": "front"}),
                Face((1, 3, 2), "#00FF00", extra={"object_id": 1, "group": "front"}),
            ],
            metadata={"object_table": [{"object_id": 1, "name": "front", "face_indices": [0, 1]}]},
        )
        with_hidden = Model(
            "with_hidden",
            (0.0, 0.0, 0.0),
            [
                (-2.0, -2.0, 0.0), (2.0, -2.0, 0.0), (-2.0, 2.0, 0.0), (2.0, 2.0, 0.0),
                (-2.0, -2.0, 1.0), (2.0, -2.0, 1.0), (-2.0, 2.0, 1.0), (2.0, 2.0, 1.0),
            ],
            [
                Face((0, 1, 2), "#FF0000", extra={"object_id": 2, "group": "back"}),
                Face((1, 3, 2), "#FF0000", extra={"object_id": 2, "group": "back"}),
                Face((4, 5, 6), "#00FF00", extra={"object_id": 1, "group": "front"}),
                Face((5, 7, 6), "#00FF00", extra={"object_id": 1, "group": "front"}),
            ],
            metadata={
                "object_table": [
                    {"object_id": 2, "name": "back", "face_indices": [0, 1]},
                    {"object_id": 1, "name": "front", "face_indices": [2, 3]},
                ]
            },
        )
        config = RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer_object_outline")
        front_frame = render_frame(front_only, config, 0)
        hidden_frame = render_frame(with_hidden, config, 0)
        self.assertEqual(front_frame.frame_hash, hidden_frame.frame_hash)

    def test_object_outline_partial_occlusion_only_marks_visible_regions(self) -> None:
        model = Model(
            "partial_occlusion",
            (0.0, 0.0, 0.0),
            [
                (-4.0, -4.0, 0.0), (4.0, -4.0, 0.0), (-4.0, 4.0, 0.0), (4.0, 4.0, 0.0),
                (-2.0, -2.0, 1.0), (2.0, -2.0, 1.0), (-2.0, 2.0, 1.0), (2.0, 2.0, 1.0),
            ],
            [
                Face((0, 1, 2), "#00FF00", extra={"object_id": 2, "group": "back"}),
                Face((1, 3, 2), "#00FF00", extra={"object_id": 2, "group": "back"}),
                Face((4, 5, 6), "#00FF00", extra={"object_id": 1, "group": "front"}),
                Face((5, 7, 6), "#00FF00", extra={"object_id": 1, "group": "front"}),
            ],
            metadata={
                "object_table": [
                    {"object_id": 2, "name": "back", "face_indices": [0, 1]},
                    {"object_id": 1, "name": "front", "face_indices": [2, 3]},
                ]
            },
        )
        frame = render_frame(
            model,
            RenderConfig(frame_width=48, frame_height=48, target_height=16, profile="zbuffer_object_outline"),
            0,
        )
        self.assertEqual(rgb_at(frame.pixels, 48, 24, 24), (0, 255, 0))
        self.assertEqual(rgb_at(frame.pixels, 48, 20, 24), OUTLINE_RGB)
        self.assertEqual(rgb_at(frame.pixels, 48, 28, 24), OUTLINE_RGB)

    def test_zbuffer_output_is_unchanged_when_outline_is_not_enabled(self) -> None:
        model = Model(
            "plain_zbuffer",
            (0.0, 0.0, 0.0),
            [(-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (0.0, 1.0, 0.0)],
            [Face((0, 1, 2), "#FF0000", extra={"group": "tri"})],
        )
        baseline = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer"), 0)
        repeat = render_frame(model, RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer"), 0)
        self.assertEqual(baseline.frame_hash, repeat.frame_hash)

    def test_equal_depth_tiebreak_is_stable(self) -> None:
        model = Model(
            "equal_depth_overlap",
            (0.0, 0.0, 0.0),
            [
                (-2.0, -2.0, 0.0),
                (2.0, -2.0, 0.0),
                (0.0, 2.0, 0.0),
                (-2.0, -2.0, 0.0),
                (2.0, -2.0, 0.0),
                (0.0, 2.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#FF0000"),
                Face((3, 4, 5), "#0000FF"),
            ],
        )
        config = RenderConfig(frame_width=32, frame_height=32, target_height=8, profile="zbuffer")
        frame_a = render_frame(model, config, 0)
        frame_b = render_frame(model, config, 0)
        self.assertEqual(frame_a.frame_hash, frame_b.frame_hash)
        self.assertEqual(rgb_at(frame_a.pixels, 32, 16, 16), (255, 0, 0))
        self.assertEqual(frame_a.occlusion_stats["equal_depth_overwrite_count"], 0)

    def test_tiny_bbox_triangle_is_stable(self) -> None:
        model = Model(
            "tiny_bbox",
            (0.0, 0.0, 0.0),
            [
                (-0.5, -2.0, 0.0),
                (0.5, -2.0, 0.0),
                (0.0, 2.0, 0.0),
            ],
            [Face((0, 1, 2), "#FFFFFF")],
        )
        config = RenderConfig(frame_width=32, frame_height=32, target_height=4, profile="zbuffer")
        frame_a = render_frame(model, config, 0)
        frame_b = render_frame(model, config, 0)
        self.assertEqual(frame_a.frame_hash, frame_b.frame_hash)
        self.assertGreater(frame_a.occlusion_stats["tiny_bbox_triangle_count"], 0)
        self.assertGreaterEqual(frame_a.occlusion_stats["filled_pixel_count"], 1)

    def test_cull_degenerate_and_clipping_are_reported(self) -> None:
        model = Model(
            "mixed",
            (0.0, 0.0, 0.0),
            [
                (-1.0, -1.0, 0.0),
                (1.0, -1.0, 0.0),
                (0.0, 1.0, 0.0),
                (1.0, -1.0, 0.0),
                (3.0, -1.0, 0.0),
                (5.0, -1.0, 0.0),
                (4.0, 1.0, 0.0),
            ],
            [
                Face((0, 1, 2), "#FFFFFF"),
                Face((0, 2, 1), "#00FF00"),
                Face((0, 3, 1), "#FF00FF"),
                Face((4, 5, 6), "#FFFF00"),
            ],
        )
        frame = render_frame(model, RenderConfig(frame_width=32, frame_height=16, target_height=8, center=False, profile="zbuffer"), 0)
        self.assertEqual(frame.visible_count, 2)
        self.assertFalse(frame.triangles[0]["culled"])
        self.assertTrue(frame.triangles[1]["culled"])
        self.assertTrue(frame.triangles[2]["culled"])
        self.assertIsNotNone(frame.triangles[3]["bbox_clipped"])
        bbox = frame.triangles[3]["bbox_clipped"]
        self.assertEqual(bbox[2], 31)
        self.assertEqual(frame.occlusion_stats["visible_triangle_count"], 2)
        self.assertGreaterEqual(frame.occlusion_stats["filled_pixel_count"], 1)

    def test_cli_generates_stable_cat1_outputs(self) -> None:
        root = Path(__file__).resolve().parents[3]
        script = root / "tools/3d_gen/render_cli.py"
        model = root / "assets/3d/generated/cat1/legacy_v3/cat1.json"
        with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
            cmd = [sys.executable, str(script), str(model), "--profile", "zbuffer", "--output-root"]
            subprocess.run(cmd + [first_dir], cwd=root, check=True, capture_output=True, text=True)
            subprocess.run(cmd + [second_dir], cwd=root, check=True, capture_output=True, text=True)

            first_root = Path(first_dir) / "cat1" / "zbuffer"
            second_root = Path(second_dir) / "cat1" / "zbuffer"
            self.assertEqual((first_root / "frame_0004.png").read_bytes(), (second_root / "frame_0004.png").read_bytes())
            self.assertEqual((first_root / "contact_sheet.png").read_bytes(), (second_root / "contact_sheet.png").read_bytes())
            self.assertEqual((first_root / "animation.gif").read_bytes(), (second_root / "animation.gif").read_bytes())
            first_report = json.loads((first_root / "frames.json").read_text(encoding="utf-8"))
            second_report = json.loads((second_root / "frames.json").read_text(encoding="utf-8"))
            self.assertEqual(first_report, second_report)
            self.assertEqual(first_report["focus_frame_indices"], [0, 3, 4, 12])
            self.assertEqual([item["yaw_index"] for item in first_report["focus_frames"]], [0, 3, 4, 12])
            self.assertIn("occlusion_stats", first_report["frames"][0])

    def test_render_sweep_reports_all_frames(self) -> None:
        model = Model(
            "sweep",
            (0.0, 0.0, 0.0),
            [(-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (0.0, 1.0, 0.0)],
            [Face((0, 1, 2), "#00FFFF")],
        )
        report = render_sweep(model, RenderConfig(frame_width=16, frame_height=16, target_height=8, yaw_steps=16, profile="no_zbuffer"))
        self.assertEqual(len(report.frames), 16)
        self.assertEqual(report.config["profile"], "no_zbuffer")
        summary = report.to_dict()
        self.assertEqual(summary["focus_frame_indices"], [0, 3, 4, 12])
        self.assertEqual([item["yaw_index"] for item in summary["focus_frames"]], [0, 3, 4, 12])

    def test_cat1_focus_frames_report_occlusion_hotspots(self) -> None:
        root = Path(__file__).resolve().parents[3]
        model = Model.load(root / "assets/3d/generated/cat1/legacy_v3/cat1.json")
        front = render_frame(model, RenderConfig(profile="zbuffer"), 0)
        side = render_frame(model, RenderConfig(profile="zbuffer"), 3)
        hotspot = render_frame(model, RenderConfig(profile="zbuffer"), 12)
        self.assertEqual(front.occlusion_stats["visible_triangle_count"], front.visible_count)
        self.assertEqual(side.occlusion_stats["visible_triangle_count"], side.visible_count)
        self.assertGreaterEqual(front.occlusion_stats["zbuffer_corrected_pixel_count"], 0)
        self.assertGreater(side.occlusion_stats["zbuffer_corrected_pixel_count"], 0)
        self.assertGreater(hotspot.occlusion_stats["overlap_triangle_count"], 0)
        self.assertGreater(hotspot.occlusion_stats["depth_span"], 0)
