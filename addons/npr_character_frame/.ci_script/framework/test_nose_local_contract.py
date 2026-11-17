"""Source contract checks; GPU/render and model acceptance remain separate."""
from pathlib import Path
import unittest
import math
import re
from types import SimpleNamespace

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


    def test_signed_squares_are_defined(self):
        self.assertNotIn("pow(", LOCAL)
        self.assertIn("normalized_x * normalized_x", LOCAL)
        self.assertIn("normalized_y * normalized_y", LOCAL)

    def test_signed_numeric_grid_from_production_expressions(self):
        # Execute the scalar assignments extracted from the production function.
        # CPU double precision is not GPU validation; render coverage is separate.
        def smoothstep(a, b, x):
            t = max(0.0, min(1.0, (x - a) / (b - a)))
            return t * t * (3.0 - 2.0 * t)

        def sample(x, y, z, curve, domain):
            env = dict(
                position=SimpleNamespace(x=x, y=y, z=z),
                u_npr_nose_local_curve=SimpleNamespace(**dict(zip("xyzw", curve))),
                u_npr_nose_local_domain=SimpleNamespace(**dict(zip("xyzw", domain))),
                max=max, abs=abs, exp=math.exp, smoothstep=smoothstep,
            )
            body = LOCAL.split("vec3 npr_nose_local_albedo", 1)[1]
            for line in body.splitlines():
                match = re.fullmatch(r"\s*float (\w+) = (.*);", line)
                update = re.fullmatch(r"\s*mask \*= (.*);", line)
                if match:
                    env[match[1]] = eval(match[2], {"__builtins__": {}}, env)
                elif update:
                    env["mask"] *= eval(update[1], {"__builtins__": {}}, env)
            return env["mask"]

        curve, domain = (0.0, 0.0015, 0.0055, 0.001), (0.0035, 0.0065, 0.0, 0.007)
        for x in (0.0, 0.002, 0.0035, 0.005, 0.0065, 0.008):
            center = curve[0] + curve[1] * (x / curve[2]) ** 2
            for dy in (0.0, 0.0005, 0.001, 0.003):
                for z in (-0.001, 0.0, 0.0035, 0.007, 0.008):
                    values = [sample(sx*x, center+sy*dy, z, curve, domain)
                              for sx in (-1, 1) for sy in (-1, 1)]
                    self.assertTrue(all(math.isfinite(v) and 0 <= v <= 1 for v in values))
                    for value in values[1:]:
                        self.assertAlmostEqual(value, values[0], places=12)
                    if x >= domain[1] or z <= domain[2]:
                        self.assertEqual(values[0], 0.0)
        self.assertEqual(sample(0, 0, 0.007, curve, domain), 1.0)
        self.assertAlmostEqual(sample(0, 0.001, 0.007, curve, domain), math.exp(-1))
        self.assertEqual(sample(0, 0, 0.0035, curve, domain), 0.5)
        for params in ((0, 0, 0, 0), (0, 0, -1, -1)):
            self.assertTrue(math.isfinite(sample(0, 0, 0, params, (0, 0, 0, 0))))


if __name__ == "__main__":
    unittest.main()
