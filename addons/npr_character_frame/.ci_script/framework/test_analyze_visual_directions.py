"""Exact recovery gates, including one-level RGB and alpha corruptions."""

import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image

import analyze_visual_directions as analyzer


class VisualAnalyzerTests(unittest.TestCase):
    def setUp(self):
        base = np.full((100, 100, 4), 100, dtype=np.uint8)
        base[..., 3] = 255
        self.images = {name + ".png": base.copy() for name in (
            "default", "enabled", "reset", "wrong_domain", "eye_temporal_neutral",
            "eye_temporal_left_expression", "eye_temporal_right_expression", "eye_temporal_reset",
        )}
        self.images["enabled.png"][10:95, 25:70, :3] = 150
        self.images["eye_temporal_left_expression.png"][15:40, 30:70, :3] = 150
        self.images["eye_temporal_right_expression.png"][15:40, 30:70, :3] = 50

    def image(self, path):
        return Image.fromarray(self.images[Path(path).name])

    def analyze(self):
        with patch.object(analyzer.Image, "open", side_effect=self.image):
            return analyzer.analyze(Path("unused"))

    def test_exact_images_pass(self):
        self.assertTrue(all(self.analyze()["checks"].values()))

    def test_single_level_reset_rgb_is_rejected(self):
        for channel in range(3):
            with self.subTest(channel=channel):
                self.images["reset.png"][99, 99, channel] += 1
                result = self.analyze()
                self.assertEqual(result["metrics"]["reset_pixels_changed"], 1)
                self.assertFalse(result["checks"]["reset_returns_to_baseline"])
                self.images["reset.png"][99, 99, channel] -= 1

    def test_single_level_reset_alpha_is_rejected(self):
        self.images["reset.png"][0, 0, 3] -= 1
        self.assertFalse(self.analyze()["checks"]["reset_returns_to_baseline"])

    def test_eye_reset_outside_old_roi_is_rejected(self):
        self.images["eye_temporal_reset.png"][99, 99, 0] += 1
        self.assertFalse(self.analyze()["checks"]["eye_temporal_reset"])

    def test_eye_reset_alpha_is_rejected(self):
        self.images["eye_temporal_reset.png"][0, 0, 3] -= 1
        self.assertFalse(self.analyze()["checks"]["eye_temporal_reset"])

    def test_identical_nondefault_pixels_pass(self):
        self.images["default.png"][99, 99, :3] = 200
        self.images["reset.png"][99, 99, :3] = 200
        self.assertTrue(self.analyze()["checks"]["reset_returns_to_baseline"])

    def test_missing_visible_response_is_rejected(self):
        self.images["enabled.png"] = self.images["default.png"].copy()
        result = self.analyze()
        self.assertFalse(result["checks"]["target_body_changes"])
        self.assertFalse(result["checks"]["target_face_changes"])

    def test_cli_propagates_recovery_failure(self):
        self.images["reset.png"][0, 0, 0] += 1
        with (
            patch.object(analyzer.Image, "open", side_effect=self.image),
            patch("sys.argv", ["analyze_visual_directions.py", "unused"]),
            patch.object(Path, "write_text"),
            patch("builtins.print"),
            self.assertRaises(SystemExit) as result,
        ):
            analyzer.main()
        self.assertEqual(result.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
