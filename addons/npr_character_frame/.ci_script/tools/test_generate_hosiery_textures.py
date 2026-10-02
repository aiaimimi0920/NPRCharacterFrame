"""Verify the real sample maps and isolated-host CLI without Blender."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

import generate_hosiery_textures as generator


class HosieryTexturesTest(unittest.TestCase):
    def setUp(self):
        parent = generator.host_root() / ".temp"
        parent.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="hosiery_textures_test_", dir=parent)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def run_bake(self, script, *args):
        return subprocess.run([sys.executable, str(script), *map(str, args)], cwd=self.root,
                              capture_output=True, text=True, timeout=60)

    def assert_maps(self, output):
        baseline = generator.ADDON / "samples/silver_wolf/assets/runtime"
        report = json.loads((output / "hosiery_textures_generation.json").read_text())
        self.assertEqual(set(report["textures"]), {"weave", "roughness", "normal"})
        self.assertEqual(report["generator_config"]["textile_repeats"], 8)
        self.assertEqual(report["generator_config"]["tile_span_m"], 0.02)
        for name, entry in report["textures"].items():
            with Image.open(output / entry["path"]) as actual, Image.open(baseline / entry["path"]) as expected:
                self.assertEqual((actual.mode, actual.size), ("RGB", (128, 128)))
                self.assertEqual(actual.tobytes(), expected.tobytes(), name)
                pixels = actual.tobytes()
                self.assertEqual(entry["pixel_sha256"], hashlib.sha256(pixels).hexdigest())
                if name == "weave":
                    self.assertEqual(actual.info["srgb"], 3)
                else:
                    self.assertNotIn("srgb", actual.info)
                    self.assertNotIn("gamma", actual.info)
                    self.assertNotIn("icc_profile", actual.info)
                # Orientation is material for the tangent-normal channels.
                if name == "normal":
                    self.assertNotEqual(pixels, expected.transpose(Image.Transpose.FLIP_TOP_BOTTOM).tobytes())
            self.assertEqual(entry["sha256"], hashlib.sha256((output / entry["path"]).read_bytes()).hexdigest())
            self.assertEqual(entry["color_space"], "sRGB" if name == "weave" else "linear")
            samples = np.frombuffer(pixels, dtype=np.uint8).reshape(128, 128, 3)
            # All three maps describe the same periodic yarn tile.
            self.assertTrue(np.array_equal(samples, np.roll(samples, 16, axis=0)))
            self.assertTrue(np.array_equal(samples, np.roll(samples, 16, axis=1)))
        self.assertNotIn(str(self.root), json.dumps(report))

    def test_renamed_host_default_and_repeat(self):
        host = self.root / "renamed_host"
        script = host / "addons/npr_character_frame/.ci_script/tools/generate_hosiery_textures.py"
        script.parent.mkdir(parents=True)
        shutil.copy2(generator.__file__, script)
        (host / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = host / ".temp/hosiery_textures_bake"
        self.assert_maps(output)
        before = {p.name: p.read_bytes() for p in output.iterdir()}
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})

    def test_detached_script_explicit_output_and_unwritable_target(self):
        script = self.root / "detached/tools/generate_hosiery_textures.py"
        script.parent.mkdir(parents=True)
        shutil.copy2(generator.__file__, script)
        output = self.root / "explicit_output"
        result = self.run_bake(script, "--output", output)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_maps(output)
        blocked = self.root / "blocked_output"
        blocked.write_bytes(b"preserve existing file")
        result = self.run_bake(script, "--output", blocked)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(blocked.read_bytes(), b"preserve existing file")


if __name__ == "__main__":
    unittest.main()
