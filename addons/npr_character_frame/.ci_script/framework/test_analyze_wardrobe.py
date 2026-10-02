"""In-memory corruption tests; real GPU controls are in wardrobe_regression.gd."""

import copy
import hashlib
import json
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

import analyze_wardrobe as analyzer


class ArrayImage:
    def __init__(self, array):
        self.array = array

    def convert(self, _mode):
        return self

    def __array__(self, dtype=None, copy=None):
        return self.array.astype(dtype, copy=True)


class WardrobeAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.marker = np.zeros((128, 256, 4), dtype=np.uint8)
        self.marker[..., 3] = 255
        self.marker[5:15, 20:120, 0] = 255
        self.marker[20:84, 10:210, 1] = 255
        self.marker[84:120, 10:210, 2] = 255
        base = np.full_like(self.marker, 100)
        base[..., 3] = 255
        self.arrays = {}
        self.manifest = {"schema": 1, "frames": {}, "regions": {}}

        def frame(name, array):
            self.arrays[name + "_stage.png"] = array.copy()

        frame("default", base)
        for i in range(1, 7):
            changed = base.copy()
            changed[self.marker[..., 1] > 0, :3] = 150
            frame(f"palette{i}", changed)
        for prefix in ("stocking", "back"):
            for label, value in (("opaque", 50), ("transparent", 200)):
                changed = base.copy()
                changed[self.marker[..., 2] > 0, :3] = value
                frame(prefix + "_" + label, changed)
        frame("expression0", base)
        for i in range(1, 5):
            changed = base.copy()
            changed[self.marker[..., 0] > 0, :3] = 150
            frame(f"expression{i}", changed)
        frame("negative_reference", base)
        frame("negative_restored", base)
        for name, pixel in (("face_dye", (6, 21, 0)), ("clothing_leak", (0, 0, 0)),
                            ("hosiery_leak", (0, 1, 0)), ("alpha", (0, 2, 3))):
            changed = base.copy()
            changed[pixel] -= 1
            frame("negative_" + name, changed)
        for name in ("default", "back_opaque", "negative_reference"):
            filename = name + "_regions.png"
            self.arrays[filename] = self.marker.copy()
            self.manifest["regions"][name] = {
                "file": filename, "size": [256, 128], "schema": 1,
                "saved": True, "exact_restore": True, "camera_unchanged": True,
            }
        self.refresh_hashes()

    def refresh_hashes(self):
        for filename, array in self.arrays.items():
            digest = hashlib.sha256(array.tobytes()).hexdigest()
            if filename.endswith("_stage.png"):
                self.manifest["frames"][filename[:-10]] = digest
            else:
                self.manifest["regions"][filename[:-12]]["sha256"] = digest

    def analyze(self):
        with patch.object(Path, "read_text", return_value=json.dumps(self.manifest)), \
             patch.object(Path, "read_bytes", lambda path: self.arrays[path.name].tobytes()), \
             patch.object(analyzer.Image, "open", lambda path: ArrayImage(self.arrays[path.name])):
            return analyzer.analyze(Path("synthetic-capture"))

    def labels_failed(self):
        return [row["label"] for row in self.analyze()["checks"] if not row["pass"]]

    def test_valid_capture(self):
        result = self.analyze()
        self.assertEqual(40, len(result["checks"]))
        self.assertEqual([], self.labels_failed())

    def test_one_unit_waist_dye_is_rejected(self):
        self.arrays["palette1_stage.png"][0, 0, 0] += 1
        self.refresh_hashes()
        self.assertTrue(any("non-dye" in label for label in self.labels_failed()))

    def test_one_unit_head_dye_is_rejected(self):
        self.arrays["palette2_stage.png"][6, 21, 0] += 1
        self.refresh_hashes()
        self.assertTrue(any("head, hair" in label for label in self.labels_failed()))

    def test_one_unit_finger_hosiery_is_rejected(self):
        self.arrays["stocking_opaque_stage.png"][0, 0, 0] += 1
        self.refresh_hashes()
        self.assertTrue(any("non-hosiery" in label for label in self.labels_failed()))

    def test_one_unit_alpha_is_rejected(self):
        self.arrays["palette3_stage.png"][30, 30, 3] -= 1
        self.refresh_hashes()
        self.assertTrue(any("alpha coverage" in label for label in self.labels_failed()))

    def test_missing_visible_dye_is_rejected(self):
        self.arrays["palette1_stage.png"] = self.arrays["default_stage.png"].copy()
        self.refresh_hashes()
        self.assertTrue(any("visibly recolors" in label for label in self.labels_failed()))

    def test_inert_gpu_negative_is_rejected(self):
        self.arrays["negative_face_dye_stage.png"] = self.arrays["negative_reference_stage.png"].copy()
        self.refresh_hashes()
        self.assertTrue(any("face_dye" in label for label in self.labels_failed()))

    def test_negative_restore_requires_exact_png_identity(self):
        self.arrays["negative_restored_stage.png"][0, 0, 0] += 1
        self.refresh_hashes()
        self.assertTrue(any("restore exact" in label for label in self.labels_failed()))

    def test_negative_restore_file_must_match_receipt(self):
        self.arrays["negative_restored_stage.png"][0, 0, 0] += 1
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            self.analyze()

    def test_empty_and_full_masks_are_rejected(self):
        for value in (0, 255):
            with self.subTest(value=value):
                self.arrays["default_regions.png"][..., :3] = value
                self.refresh_hashes()
                with self.assertRaisesRegex(ValueError, "Empty or unbounded"):
                    self.analyze()

    def test_wrong_dimensions_are_rejected(self):
        self.manifest["regions"]["default"]["size"] = [1440, 900]
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            self.analyze()

    def test_changed_capture_is_rejected(self):
        self.arrays["palette1_stage.png"][0, 0, 0] += 1
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            self.analyze()

    def test_changed_mask_is_rejected(self):
        self.arrays["default_regions.png"][0, 0, 1] = 255
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            self.analyze()

    def test_capture_state_and_camera_must_restore(self):
        original = copy.deepcopy(self.manifest)
        for flag in ("saved", "exact_restore", "camera_unchanged"):
            with self.subTest(flag=flag):
                self.manifest = copy.deepcopy(original)
                self.manifest["regions"]["default"][flag] = False
                with self.assertRaisesRegex(ValueError, "changed production state"):
                    self.analyze()

    def test_unknown_schema_is_rejected(self):
        self.manifest["schema"] = 999
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            self.analyze()

    def test_path_escape_is_rejected(self):
        self.manifest["regions"]["default"]["file"] = "../other.png"
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            self.analyze()


if __name__ == "__main__":
    unittest.main()
