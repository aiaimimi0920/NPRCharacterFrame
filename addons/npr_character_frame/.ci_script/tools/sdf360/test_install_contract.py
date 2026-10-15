"""Pure source/package regression tests; not a substitute for engine loading."""

import unittest
from pathlib import Path
from definition_output import bind_directional_atlas, MATERIAL_SCRIPT, BASE_SCRIPT

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (
    BASE_SCRIPT + '\n[sub_resource type="Resource" id="Materials"]\nsdf_on_uv2 = true\n'
)


class InstallContract(unittest.TestCase):
    def test_output_script_is_published(self):
        output = bind_directional_atlas(SOURCE, "assets/face.png")
        self.assertIn(MATERIAL_SCRIPT, output)
        self.assertNotIn("showcase_extensions", output)
        self.assertTrue(
            (ROOT.parent.parent / MATERIAL_SCRIPT.removeprefix("res://")).is_file()
        )
        self.assertIn('face_sdf360 = ExtResource("sdf360_atlas")', output)

    def test_missing_and_duplicate_fields_fail(self):
        for token in (
            BASE_SCRIPT,
            '[sub_resource type="Resource" id="Materials"]',
            "sdf_on_uv2 = true",
        ):
            for value in ("", token + token):
                with self.subTest(token=token, value=value), self.assertRaises(
                    ValueError
                ):
                    bind_directional_atlas(
                        SOURCE.replace(token, value), "assets/face.png"
                    )

    def test_invalid_or_duplicate_binding_fails(self):
        for path in (
            "",
            "../face.png",
            "/face.png",
            "res://face.png",
            'a".png',
            "a\nb.png",
        ):
            with self.subTest(path=path), self.assertRaises(ValueError):
                bind_directional_atlas(SOURCE, path)
        with self.assertRaises(ValueError):
            bind_directional_atlas(SOURCE + "face_sdf360 = null", "assets/a.png")

    def test_published_uids_are_complete_and_unique(self):
        directory = ROOT / "shaders/face/sdf360"
        sources = [
            p
            for p in directory.iterdir()
            if p.suffix in (".gd", ".gdshader", ".gdshaderinc")
        ]
        self.assertEqual(len(sources), 7)
        uids = [Path(str(p) + ".uid").read_text().strip() for p in sources]
        self.assertEqual(len(set(uids)), 7)
        self.assertTrue(all(u.startswith("uid://") and len(u) > 6 for u in uids))
        all_uids = [p.read_text().strip() for p in ROOT.rglob("*.uid")]
        self.assertTrue(all(all_uids.count(u) == 1 for u in uids))

    def test_source_mode_validates_before_binding(self):
        base = (ROOT / "npr_character_materials.gd").read_text()
        definition = (ROOT / "npr_character_definition.gd").read_text()
        self.assertIn("not validate_source_materials().is_empty()", base)
        self.assertIn("material_set.validate_source_materials()", definition)
        extension = (ROOT / "shaders/face/sdf360/sdf_materials.gd").read_text()
        for guard in (
            "if not sdf_on_uv2:",
            "width % 24 != 0",
            "height % 7 != 0",
            "width / 24 <= 4",
            "height / 7 <= 4",
            "Directional SDF requires use_source_materials=false",
        ):
            self.assertIn(guard, extension)


if __name__ == "__main__":
    unittest.main()
