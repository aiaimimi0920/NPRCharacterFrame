"""Reconstruct all five shipped maps using a portable isolated host."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from PIL import Image
import generate_wardrobe_visual_maps as generator


class VisualMapsTest(unittest.TestCase):
    def setUp(self):
        parent = generator.host_root() / ".temp"
        parent.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="visual_maps_test_", dir=parent)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def run_bake(self, script, *args):
        return subprocess.run([sys.executable, str(script), *map(str, args)], cwd=self.root,
                              capture_output=True, text=True, timeout=60)

    def test_portable_rebuild_and_repeat(self):
        host = self.root / "renamed_host"
        addon = host / "addons/npr_character_frame"
        for source in (Path(generator.__file__), generator.SOURCE):
            target = addon / source.relative_to(generator.ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        (host / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        script = addon / ".ci_script/tools/generate_wardrobe_visual_maps.py"
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = host / ".temp/visual_maps_bake"
        baseline = generator.ADDON / "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe"
        expected = json.loads((baseline / "visual_maps_generation.json").read_text())
        actual = json.loads((output / "visual_maps_generation.json").read_text())
        self.assertEqual(actual["source"]["sha256"], expected["source"]["sha256"])
        self.assertEqual(set(actual["maps"]), set(expected["maps"]))
        self.assertEqual(actual["defaults"], expected["defaults"])
        for name in expected["maps"]:
            with Image.open(output / f"{name}.png") as image, Image.open(baseline / f"{name}.png") as original:
                self.assertEqual((image.mode, image.size), ("L", (1024, 512)))
                self.assertEqual(image.tobytes(), original.tobytes(), name)
            self.assertEqual(actual["maps"][name]["sha256"], generator._sha256(output / f"{name}.png"))
        self.assertNotIn(str(host), json.dumps(actual))
        before = {p.name: p.read_bytes() for p in output.iterdir()}
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})

    def test_missing_or_invalid_source_creates_no_output(self):
        cases = [self.root / "missing.png"]
        for mode, size in (("RGB", (1024, 512)), ("RGBA", (16, 16))):
            path = self.root / f"{mode}.png"
            Image.new(mode, size).save(path)
            cases.append(path)
        for source in cases:
            with self.subTest(source=source):
                output = self.root / "rejected"
                result = self.run_bake(generator.__file__, "--source", source, "--output", output)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
