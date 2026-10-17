"""CPU source contracts for full outline holdout; GPU coverage needs native review."""

from pathlib import Path
import re
import unittest


SHADER = Path(__file__).resolve().parents[2] / "shaders/face/face_outline_pixels.gdshader"


class FaceOutlineHoldoutTests(unittest.TestCase):
    def setUp(self):
        self.source = SHADER.read_text()
        self.vertex, self.fragment = self.source.split("void fragment() {", 1)

    def test_full_holdout_guard_is_face_only_and_independent_of_lip_fix(self):
        # Match the production branch, then evaluate its actual scalar predicates.
        branch = re.search(
            r"if\s*\((?P<guard>u_npr_outline_control_enabled\s*&&\s*u_npr_outline_role\s*==\s*1)\)\s*\{"
            r"\s*float holdout = texture\(u_npr_outline_control, v_npr_outline_uv\)\.b;"
            r"\s*if\s*\((?P<cutoff>holdout\s*>=\s*1\.0)\)\s*\{\s*discard;\s*\}\s*\}",
            self.fragment,
        )
        self.assertIsNotNone(branch, "Full holdout must discard in fragment, not only reduce width")
        self.assertNotIn("u_npr_outline_lip_fix_enabled", self.fragment[:branch.end()])
        predicate = "(" + branch["guard"].replace("&&", "and") + ") and (" + branch["cutoff"] + ")"
        for enabled in (False, True):
            for role in (0, 1, 2):
                for holdout in (0.0, 0.5, 254 / 255, 1.0):
                    with self.subTest(enabled=enabled, role=role, holdout=holdout):
                        actual = eval(predicate, {"__builtins__": {}}, {
                            "u_npr_outline_control_enabled": enabled,
                            "u_npr_outline_role": role,
                            "holdout": holdout,
                        })
                        self.assertEqual(actual, enabled and role == 1 and holdout == 1.0)

    def test_disabled_default_and_partial_width_path_are_preserved(self):
        self.assertIn("uniform bool u_npr_outline_control_enabled = false;", self.source)
        self.assertIn("resolved_width *= 1.0 - control.b;", self.vertex)
        self.assertIn("if (u_npr_outline_lip_fix_enabled && u_npr_outline_role == 1)", self.vertex)
        self.assertIn("render_mode unshaded, cull_front,", self.source)
        self.assertNotIn("outline_width_pixels", self.fragment)


if __name__ == "__main__":
    unittest.main()
