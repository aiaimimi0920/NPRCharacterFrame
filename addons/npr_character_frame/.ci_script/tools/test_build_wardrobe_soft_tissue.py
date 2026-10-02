"""Run real Blender reconstruction, portability and rejection checks.

Pass --blender <executable>, set BLENDER_EXECUTABLE, or put blender on PATH.
Temporary hosts are created under the current host's .temp and cleaned on exit.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("build_wardrobe_soft_tissue.py")
ADDON = SCRIPT.parents[2]
ROOT = next(parent for parent in ADDON.parents if (parent / "project.godot").is_file())
RECIPE = ADDON / "samples/silver_wolf/import_sources/soft_tissue_bake_inputs.json"
ASSET = ADDON / "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/soft_tissue_v1.json"
BLENDER = None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


class SoftTissueBakeTest(unittest.TestCase):
    def setUp(self):
        (ROOT / ".temp").mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix="soft_tissue_test_", dir=ROOT / ".temp")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.host = self.work / "renamed_host"
        self.addon = self.host / "addons/npr_character_frame"
        self.host.mkdir()
        (self.host / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        self.recipe = self.addon / RECIPE.relative_to(ADDON)
        self.script = self.addon / SCRIPT.relative_to(ADDON)
        sources = [SCRIPT, RECIPE]
        sources.extend((RECIPE.parent / row["path"]).resolve() for row in read_json(RECIPE)["files"].values())
        for source in sources:
            target = self.addon / source.relative_to(ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def run_blender(self, *args):
        return subprocess.run(
            [str(BLENDER), "--background", "--factory-startup", "--python-exit-code", "1",
             "--python", str(self.script), "--", *map(str, args)],
            cwd=self.work, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180,
        )

    def require_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def verify(self, output, report):
        result = self.run_blender("--output", output, "--verify-only", "--report", report)
        self.require_success(result)
        self.assertIn("SOFT_TISSUE_SOURCE_OK", result.stdout)
        receipt = read_json(report)
        self.assertTrue(receipt["pass"])
        self.assertEqual(receipt["vertices"], read_json(ASSET)["source_vertices"])
        self.assertLessEqual(receipt["shape_delta_max_error"], 2e-7)
        self.assertLessEqual(receipt["rest_max_error"], 2e-6)
        self.assertLessEqual(receipt["uv_max_error"], 2e-6)
        self.assertTrue(all(abs(total - 1.0) <= 2e-6 for total in receipt["weight_sum_range"]))
        self.assertEqual(receipt["bones"], 16)
        self.assertEqual(receipt["actions"], ["greeting", "idle", "look_around", "presentation"])
        self.assertEqual(receipt["source_sha256"], digest(output / "soft_tissue_v1.blend"))
        self.assertEqual(receipt["bridge_sha256"], digest(output / "soft_tissue_v1.json"))

    def test_relocated_default_bake_matches_all_corrective_fields(self):
        sources = {path: digest(path) for path in self.addon.rglob("*") if path.is_file()}
        result = self.run_blender()
        self.require_success(result)
        self.assertIn("SOFT_TISSUE_BAKE_OK", result.stdout)
        output = self.host / ".temp/soft_tissue_bake"
        actual = read_json(output / "soft_tissue_v1.json")
        expected = read_json(ASSET)
        self.assertEqual({k: v for k, v in actual.items() if k != "source"},
                         {k: v for k, v in expected.items() if k != "source"})
        recipe = read_json(self.recipe)
        self.assertEqual(actual["source"], {
            "blend": "soft_tissue_v1.blend",
            "canonical_body_sha256": recipe["files"]["body"]["sha256"],
            "probe_sha256": recipe["files"]["probe"]["sha256"],
            "input_blend_sha256": recipe["files"]["rig"]["sha256"],
        })
        self.assertNotEqual(actual["source"]["input_blend_sha256"], recipe["historical_input_blend_sha256"])
        generation = read_json(output / "soft_tissue_generation.json")
        self.assertEqual(generation["generator_sha256"], digest(self.script))
        self.assertEqual(generation["input_recipe_sha256"], digest(self.recipe))
        self.assertEqual(generation["changed_vertices"], len(expected["deltas"]))
        self.assertEqual(generation["bridge_sha256"], digest(output / "soft_tissue_v1.json"))
        self.assertEqual(generation["source_blend_sha256"], digest(output / "soft_tissue_v1.blend"))
        for role, row in recipe["files"].items():
            source = (self.recipe.parent / row["path"]).resolve()
            self.assertEqual(generation["inputs"][role], {"name": source.name, "sha256": digest(source)})
        self.assertNotIn(str(self.host), json.dumps(actual) + json.dumps(generation))
        self.verify(output, self.work / "verified.json")
        repeated = self.work / "repeat"
        self.require_success(self.run_blender("--output", repeated))
        self.assertEqual((output / "soft_tissue_v1.json").read_bytes(),
                         (repeated / "soft_tissue_v1.json").read_bytes())
        self.verify(repeated, self.work / "repeat_verified.json")
        for path, sha in sources.items():
            self.assertEqual(digest(path), sha, str(path))

    def test_bad_input_identity_paths_and_missing_files_do_not_create_output(self):
        valid = read_json(self.recipe)
        cases = []
        for role in valid["files"]:
            data = read_json(self.recipe)
            data["files"][role]["sha256"] = "0" * 64
            cases.append(("identity_" + role, data, "Input identity"))
            data = read_json(self.recipe)
            data["files"][role]["path"] = "missing_" + role
            cases.append(("missing_" + role, data, "FileNotFoundError"))
        data = read_json(self.recipe)
        data["schema"] = 2
        cases.append(("schema", data, "Expected schema 1"))
        data = read_json(self.recipe)
        data["files"]["rig"]["path"] = str((self.recipe.parent / "character_rig.blend").resolve())
        cases.append(("absolute", data, "paths must be relative"))
        outside = self.work / "outside.blend"
        shutil.copy2(self.recipe.parent / "character_rig.blend", outside)
        data = read_json(self.recipe)
        data["files"]["rig"]["path"] = os.path.relpath(outside, self.recipe.parent)
        cases.append(("escape", data, "Input identity or location"))
        for name, recipe, message in cases:
            with self.subTest(name=name):
                self.recipe.write_text(json.dumps(recipe), encoding="utf-8")
                output = self.work / name
                result = self.run_blender("--output", output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stdout + result.stderr)
                self.assertFalse(output.exists())

    def test_saved_bridge_corruption_and_delivery_output_are_rejected(self):
        output = self.work / "candidate"
        self.require_success(self.run_blender("--output", output))
        bridge = output / "soft_tissue_v1.json"
        original = read_json(bridge)
        cases = []
        data = read_json(bridge)
        data["deltas"][0][1] += 0.001
        cases.append(("shape_mismatch", data, "Shape Key and bridge differ"))
        data = read_json(bridge)
        data["deltas"][0][1] = float("nan")
        cases.append(("nonfinite", data, "nonfinite deltas"))
        data = read_json(bridge)
        data["deltas"].append(data["deltas"][0])
        cases.append(("duplicate", data, "duplicate"))
        data = read_json(bridge)
        data["source_vertices"] -= 1
        cases.append(("count", data, "vertex count changed"))
        for name, data, message in cases:
            with self.subTest(name=name):
                bridge.write_text(json.dumps(data), encoding="utf-8")
                report = self.work / (name + "_receipt.json")
                result = self.run_blender("--output", output, "--verify-only", "--report", report)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stdout + result.stderr)
                self.assertFalse(report.exists())
        bridge.write_text(json.dumps(original), encoding="utf-8")
        protected = self.addon / "rejected_output"
        result = self.run_blender("--output", protected)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Output must be outside", result.stdout + result.stderr)
        self.assertFalse(protected.exists())
        report = self.addon / "rejected_report.json"
        result = self.run_blender("--output", output, "--verify-only", "--report", report)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Report must be outside", result.stdout + result.stderr)
        self.assertFalse(report.exists())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", default=os.environ.get("BLENDER_EXECUTABLE") or shutil.which("blender"))
    args, remaining = parser.parse_known_args()
    if not args.blender or not Path(args.blender).is_file():
        parser.error("Pass --blender <executable>, set BLENDER_EXECUTABLE, or put blender on PATH")
    BLENDER = Path(args.blender).resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
