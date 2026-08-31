from __future__ import annotations

import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from model import Model, ModelValidationError


class ModelTests(unittest.TestCase):
    def test_generic_round_trip_preserves_extra_fields(self) -> None:
        document = {
            "format": "lowpoly-model", "version": 1, "name": "triangle",
            "vertices": [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
            "faces": [{"indices": [0, 1, 2], "color": "#ff8090", "name": "front", "material": "matte"}],
            "metadata": {"author": "test"},
        }
        model = Model.from_dict(document)
        saved = model.to_dict()
        self.assertEqual(saved["metadata"], {"author": "test"})
        self.assertEqual(saved["faces"][0]["material"], "matte")
        self.assertEqual(saved["faces"][0]["color"], "#FF8090")

    def test_origin_defaults_to_zero_and_json_file_round_trips(self) -> None:
        model = Model.from_dict({"format": "lowpoly-model", "version": 1, "name": "empty", "vertices": [], "faces": []})
        self.assertEqual(model.origin, (0.0, 0.0, 0.0))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.json"
            model.save(path)
            self.assertEqual(Model.load(path).to_dict(), model.to_dict())

    def test_invalid_indices_and_non_finite_numbers_are_rejected(self) -> None:
        with self.assertRaises(ModelValidationError) as caught:
            Model.from_dict({"format": "lowpoly-model", "version": 1, "name": "bad",
                             "vertices": [[float("inf"), 0, 0]],
                             "faces": [{"indices": [0, 1, 2], "color": "#000000"}]})
        self.assertTrue(any("finite" in message for message in caught.exception.errors))
        self.assertTrue(any("out-of-range" in message for message in caught.exception.errors))
