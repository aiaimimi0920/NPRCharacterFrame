"""Run with --probe pointing to a freshly captured body_surface.json."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import build_hosiery_surface as generator

PROBE = None


class SurfaceBakeTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="surface_test_", dir=generator.host_root() / ".temp")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def run_bake(self, script, probe, *args):
        return subprocess.run([sys.executable, "-O", str(script), str(probe), *map(str, args)],
                              cwd=self.root, capture_output=True, text=True, timeout=60)

    def test_portable_reconstruction(self):
        host = self.root / "renamed_host"
        addon = host / "addons/npr_character_frame"
        for source in (Path(generator.__file__), generator.MESH, generator.ASSET / "garment_mask.png"):
            target = addon / source.relative_to(generator.ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        (host / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        probe = self.root / "body_surface.json"
        shutil.copy2(PROBE, probe)
        script = addon / ".ci_script/tools/build_hosiery_surface.py"
        result = self.run_bake(script, probe)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = host / ".temp/hosiery_surface_bake/hosiery_surface.json"
        actual = json.loads(output.read_text())
        expected = json.loads((generator.ASSET / "hosiery_surface.json").read_text())
        for key in expected:
            if key not in ("generator_sha256", "garment_sha256"):
                self.assertEqual(actual[key], expected[key], key)
        self.assertEqual(actual["garment_sha256"], generator.sha(generator.ASSET / "garment_mask.png"))
        self.assertNotIn(str(host), json.dumps(actual))
        before = output.read_bytes()
        result = self.run_bake(script, probe)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, output.read_bytes())

    def test_invalid_probe_rejected_without_output(self):
        valid = json.loads(PROBE.read_text())
        for field, value in (("source_sha256", "wrong"), ("vertices", [[float("nan")] * 11]),
                             ("indices", [0, 1, len(valid["vertices"])]), ("indices", [0, 1, 1.5])):
            with self.subTest(field=field, value=value):
                data = dict(valid)
                data[field] = value
                probe = self.root / "invalid.json"
                probe.write_text(json.dumps(data), encoding="utf-8")
                output = self.root / "rejected"
                result = self.run_bake(generator.__file__, probe, "--output", output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("ValueError", result.stderr)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    PROBE = args.probe.resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
