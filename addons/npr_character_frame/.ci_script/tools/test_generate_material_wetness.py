"""Verify actual material mask reconstruction and strict input identity."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from PIL import Image
import generate_material_wetness as generator


class MaterialBakeTest(unittest.TestCase):
    def setUp(self):
        parent = generator.host_root() / ".temp"
        parent.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="material_test_", dir=parent)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def run_bake(self, script, *args):
        return subprocess.run([sys.executable, "-O", str(script), *map(str, args)],
                              cwd=self.root, capture_output=True, text=True, timeout=120)

    def test_portable_reconstruction_and_repeat(self):
        host = self.root / "renamed_host"
        addon = host / "addons/npr_character_frame"
        for source in (Path(generator.__file__), generator.PROBE, generator.RECIPE, generator.MESH):
            target = addon / source.relative_to(generator.ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        (host / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        script = addon / ".ci_script/tools/generate_material_wetness.py"
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = host / ".temp/material_wetness_bake"
        baseline = generator.SAMPLE / "assets/authoring/silver_wolf/wardrobe"
        with Image.open(output / "material_wetness.png") as actual, Image.open(baseline / "material_wetness.png") as expected:
            self.assertEqual((actual.mode, actual.size), ("RGBA", (1024, 512)))
            self.assertEqual(actual.tobytes(), expected.tobytes())
        actual = json.loads((output / "material_wetness_generation.json").read_text())
        expected = json.loads((baseline / "material_wetness_generation.json").read_text())
        for key in ("texels", "channels", "colorspace", "conflicting_texels_excluded", "source_mesh_sha256"):
            self.assertEqual(actual[key], expected[key], key)
        self.assertNotEqual(actual["probe_sha256"], expected["probe_sha256"])
        self.assertEqual(actual["probe_sha256"], generator.sha(generator.PROBE))
        self.assertNotIn(str(host), json.dumps(actual))
        before = {p.name: p.read_bytes() for p in output.iterdir()}
        result = self.run_bake(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})

    def test_identity_and_recipe_rejection_even_with_python_optimization(self):
        output = self.root / "rejected"
        bad = self.root / "changed_source"
        bad.write_bytes(b"changed")
        historical = generator.SAMPLE / "assets/authoring/silver_wolf/wardrobe/material_wetness_regions.json"
        cases = [(bad,), ("--mesh", bad), ("--regions", historical)]
        for field, value in (("channel", 4), ("ids", [108]), ("exclude_uv_rects", [[0, 0, 1024, 512]])):
            recipe = json.loads(generator.RECIPE.read_text())
            recipe["groups"][0][field] = value
            path = self.root / (field + ".json")
            path.write_text(json.dumps(recipe), encoding="utf-8")
            cases.append(("--regions", path))
        for args in cases:
            with self.subTest(args=args):
                result = self.run_bake(generator.__file__, *args, "--output", output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ValueError", result.stderr)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
