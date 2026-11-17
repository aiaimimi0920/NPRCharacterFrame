"""Source contract checks; GPU/render and model acceptance remain separate."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
FACE = (ROOT / "shaders/face/face_base.gdshader").read_text(encoding="utf-8")
LOCAL = (ROOT / "shaders/face/nose_local.gdshaderinc").read_text(encoding="utf-8")


class NoseLocalContract(unittest.TestCase):
    def test_disabled_default(self):
        self.assertIn("uniform bool u_npr_nose_local_enabled = false;", LOCAL)
        self.assertEqual(FACE.count("if (u_npr_nose_local_enabled)"), 1)

    def test_legacy_calculation_precedes_opt_in(self):
        legacy = "float nose_line_factor  = calculate_nose_line_factor(normal_ws, view_dir_ws, ilm_sample.b);"
        blend = "vec3 albedo_blender_color = mix(albedo.rgb, u_nose_line_color, nose_line_factor);"
        self.assertLess(FACE.index(legacy), FACE.index(blend))
        self.assertLess(FACE.index(blend), FACE.index("if (u_npr_nose_local_enabled)"))
        self.assertIn("npr_nose_local_albedo(albedo.rgb, npr_nose_local_position)", FACE)

    def test_mesh_local_position_and_color_contract(self):
        self.assertIn("npr_nose_local_position = VERTEX;", FACE)
        self.assertIn("u_npr_nose_local_color : source_color", LOCAL)
        self.assertNotIn("texture(", LOCAL)
        self.assertNotIn("CUSTOM", LOCAL)
        self.assertNotIn("VIEW_MATRIX", LOCAL)

    def test_degenerate_parameter_guards(self):
        self.assertIn("max(abs(u_npr_nose_local_curve.z), 0.000001)", LOCAL)
        self.assertIn("max(abs(u_npr_nose_local_curve.w), 0.000001)", LOCAL)
        self.assertIn("u_npr_nose_local_domain.x + 0.000001", LOCAL)
        self.assertIn("u_npr_nose_local_domain.z + 0.000001", LOCAL)
        self.assertIn("clamp(u_npr_nose_local_color.a, 0.0, 1.0)", LOCAL)


if __name__ == "__main__":
    unittest.main()
