"""Prove the migrated bake is portable, deterministic and matches authored runtime data."""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


SCRIPT = Path(__file__).with_name("generate_rain_surface.py")
ADDON = SCRIPT.parents[2]
ROOT = next(parent for parent in ADDON.parents if (parent / "project.godot").is_file())
BASE = ADDON / "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe"
SOURCE = ADDON / "samples/silver_wolf/import_sources/soft_tissue_input_probe.json"
OUTPUTS = ("rain_surface.json", "rain_chart.bin", "rain_vertex_uv.bin", "rain_chart.png")


class RainBakeTest(unittest.TestCase):
    def setUp(self):
        (ROOT / ".temp").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="rain_generator_", dir=ROOT / ".temp")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)

    def run_bake(self, script=SCRIPT, *args):
        return subprocess.run(
            [sys.executable, str(script), *map(str, args)],
            cwd=self.work, capture_output=True, text=True, timeout=120,
        )

    def test_relocated_default_inputs_and_deterministic_rebuild(self):
        host = self.work / "renamed_host"
        relocated = host / "addons/npr_character_frame"
        host.mkdir()
        (host / "project.godot").write_text('[application]\nconfig/name="Bake fixture"\n')
        for source in (SCRIPT, SOURCE, BASE / "material_wetness.png", BASE / "garment_mask.png"):
            target = relocated / source.relative_to(ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        tool = relocated / SCRIPT.relative_to(ADDON)
        result = self.run_bake(tool)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = host / ".temp/rain_bake"
        generated = json.loads((output / "rain_surface.json").read_text())
        authored = json.loads((BASE / "rain_surface.json").read_text())
        metadata = {"inputs", "generator_sha256", "generator_config"}
        self.assertEqual(
            {k: v for k, v in generated.items() if k not in metadata},
            {k: v for k, v in authored.items() if k not in metadata},
        )
        for name in ("rain_chart.bin", "rain_vertex_uv.bin"):
            self.assertEqual((output / name).read_bytes(), (BASE / name).read_bytes(), name)
        with Image.open(output / "rain_chart.png") as generated_image:
            self.assertEqual(generated_image.mode, "RGBA")
            self.assertEqual(generated_image.size, tuple(authored["size"]))
            self.assertEqual(generated_image.tobytes(), (BASE / "rain_chart.bin").read_bytes())
        for role, path in (("geometry_probe", SOURCE), ("material_map", BASE / "material_wetness.png"),
                           ("garment_mask", BASE / "garment_mask.png")):
            self.assertEqual(generated["inputs"][role]["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(generated["generator_sha256"], hashlib.sha256(tool.read_bytes()).hexdigest())
        self.assertNotIn(str(host), json.dumps(generated))
        repeated = self.work / "repeat"
        result = self.run_bake(tool, "--output", repeated)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in OUTPUTS:
            self.assertEqual((output / name).read_bytes(), (repeated / name).read_bytes(), name)

    def test_missing_required_mask_does_not_write_outputs(self):
        output = self.work / "invalid_missing"
        result = self.run_bake(SCRIPT, "--garment", self.work / "missing.png", "--output", output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Rain bake failed", result.stderr)
        self.assertFalse(output.exists())

    def test_invalid_geometry_and_mask_fail_before_writing(self):
        mesh = {"positions": [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                "uv": [[0, 0], [1, 0], [0, 1]], "indices": [0, 1, 3]}
        source = self.work / "invalid.json"
        source.write_text(json.dumps({"meshes": [mesh]}))
        output = self.work / "invalid_geometry"
        result = self.run_bake(SCRIPT, "--source", source, "--output", output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("indices", result.stderr)
        self.assertFalse(output.exists())
        material = self.work / "rgb.png"
        Image.new("RGB", (1024, 512)).save(material)
        result = self.run_bake(SCRIPT, "--material", material, "--output", output)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires RGBA", result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
