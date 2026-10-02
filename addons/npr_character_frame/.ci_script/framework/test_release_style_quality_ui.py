"""纯图像输入定位合同；不启动 Godot，不允许缺失或歧义目标被点击。"""

import os
from pathlib import Path
import unittest
import uuid

from PIL import Image, ImageDraw

from release_style_quality_ui import actual_popup_rect, actual_slider_y, host_root


class InputLocatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(os.environ.get("NPR_TEST_TEMP_ROOT", host_root() / ".temp/input_locator_tests"))
        cls.output = root / uuid.uuid4().hex
        cls.output.mkdir(parents=True, exist_ok=False)

    def picture(self, rectangles):
        image = Image.new("RGB", (1440, 900), (45, 70, 96))
        draw = ImageDraw.Draw(image)
        for rect in rectangles:
            draw.rectangle(rect, fill=(235, 236, 245))
        path = self.output / (self.id().rsplit(".", 1)[-1] + ".png")
        image.save(path)
        return path

    def test_popup_tracks_actual_position_not_old_y(self):
        path = self.picture([(1086, 480, 1409, 561)])
        self.assertEqual(actual_popup_rect(path, (1086, 450, 1410, 536), 3),
                         (1086, 480, 1410, 562))

    def test_popup_missing_rejected(self):
        with self.assertRaises(RuntimeError):
            actual_popup_rect(self.picture([]), (1086, 450, 1410, 536), 3)

    def test_popup_wrong_item_count_rejected(self):
        with self.assertRaises(RuntimeError):
            actual_popup_rect(self.picture([(1086, 480, 1409, 561)]), (1086, 450, 1410, 536), 5)

    def test_popup_ambiguous_rejected(self):
        path = self.picture([(1086, 200, 1409, 281), (1086, 480, 1409, 561)])
        with self.assertRaises(RuntimeError):
            actual_popup_rect(path, (1086, 450, 1410, 536), 3)

    def test_popup_narrow_stripe_rejected(self):
        with self.assertRaises(RuntimeError):
            actual_popup_rect(self.picture([(1088, 480, 1090, 561)]), (1086, 450, 1410, 536), 3)

    def test_slider_tracks_actual_track_not_old_y(self):
        path = self.picture([(1086, 500, 1409, 505)])
        self.assertEqual(actual_slider_y(path, (1086, 465, 1410, 493)), 503)

    def test_slider_missing_rejected(self):
        with self.assertRaises(RuntimeError):
            actual_slider_y(self.picture([]), (1086, 465, 1410, 493))

    def test_slider_ambiguous_rejected(self):
        path = self.picture([(1086, 450, 1409, 455), (1086, 500, 1409, 505)])
        with self.assertRaises(RuntimeError):
            actual_slider_y(path, (1086, 465, 1410, 493))


if __name__ == "__main__":
    unittest.main(verbosity=2)
