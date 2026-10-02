"""Real sample reconstruction, portability and invalid-input regression."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from PIL import Image
import generate_wardrobe_mask as generator


class GarmentBakeTest(unittest.TestCase):
    def setUp(self):
        temporary = generator.host_root() / ".temp"
        temporary.mkdir(exist_ok=True)
        self.sandbox = tempfile.TemporaryDirectory(prefix="garment_test_", dir=temporary)
        self.addCleanup(self.sandbox.cleanup)
        self.root = Path(self.sandbox.name)

    def run_bake(self, script, *args):
        return subprocess.run([sys.executable, str(script), *map(str, args)],
                              cwd=self.root, capture_output=True, text=True, timeout=120)

    def test_renamed_host_and_repeat_match_existing_asset(self):
        host = self.root / "renamed_host"
        addon = host / "addons/npr_character_frame"
        script = addon / ".ci_script/tools/generate_wardrobe_mask.py"
        for source in (Path(generator.__file__), generator.PROBE, generator.SOURCE):
            target = addon / source.relative_to(generator.ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        (host / "project.godot").write_text('config_version=5\n', encoding="utf-8")
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = host / ".temp/garment_bake"
        baseline = generator.SAMPLE / "assets/authoring/silver_wolf/wardrobe"
        with Image.open(output / "garment_mask.png") as actual, Image.open(baseline / "garment_mask.png") as expected:
            self.assertEqual((actual.mode, actual.size), ("RGBA", (1024, 512)))
            self.assertEqual(actual.tobytes(), expected.tobytes())
        manifest = json.loads((output / "generation.json").read_text())
        original = json.loads((baseline / "generation.json").read_text())
        for key in ("source_sha256", "probe_sha256", "covered_pixels", "head_only_vertices",
                    "channels", "domain_policy", "identity"):
            self.assertEqual(manifest[key], original[key], key)
        self.assertNotIn(str(host), json.dumps(manifest))
        before = {f.name: f.read_bytes() for f in output.iterdir()}
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {f.name: f.read_bytes() for f in output.iterdir()})

    def test_invalid_inputs_do_not_create_output(self):
        valid = {"meshes": [{"positions": [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                             "uv": [[0, 0], [1, 0], [0, 1]], "indices": [0, 1, 2]}]}
        for field, value in (("indices", [0, 1, 3]), ("indices", [0, 1, 1.5]),
                             ("positions", [[float("nan"), 0, 0]] * 3), ("uv", [[0, 0]])):
            with self.subTest(field=field, value=value):
                data = json.loads(json.dumps(valid))
                data["meshes"][0][field] = value
                probe = self.root / "bad.json"
                probe.write_text(json.dumps(data), encoding="utf-8")
                output = self.root / "rejected"
                result = self.run_bake(generator.__file__, probe, "--output", output)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())
        texture = self.root / "wrong_size.png"
        Image.new("RGB", (16, 16)).save(texture)
        result = self.run_bake(generator.__file__, "--source", texture, "--output", output)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
