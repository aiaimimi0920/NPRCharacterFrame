"""Test the exact normal-field section of the native recipe without Blender."""

import unittest, ast, numpy as np
from pathlib import Path

# Execute only the selected pure-numpy expressions, using a constant face width
# to isolate the direction contract from the geometric width interpolation.
s = Path(__file__).with_name("bake.py").read_text()
section = s[s.index("xx, yy = np.meshgrid") : s.index("atlas = np.zeros")]
ns = {
    "np": np,
    "N": 256,
    "u": (np.arange(256) + 0.5) / 256,
    "v": (np.arange(256) + 0.5) / 256,
    "width": lambda y: 0.09,
    "H": 0.236,
    "Y0": 1.544,
}
exec(compile(section, "proxy", "exec"), ns)
n = ns["normals"]
x = ns["xx"]
y = ns["yy"]
mid = ns["Y0"] + ns["H"] * 0.52


class DirectionContract(unittest.TestCase):
    def test_front_back(self):
        self.assertTrue((n[:, :, 2] > 0).all())

    def test_right_light(self):
        self.assertTrue((n[:, :, 0][x > 0] > 0).all())
        self.assertTrue((n[:, :, 0][x < 0] < 0).all())

    def test_top_light(self):
        self.assertTrue((n[:, :, 1][y > mid] > 0).all())
        self.assertTrue((n[:, :, 1][y < mid] < 0).all())

    def test_normalized_finite(self):
        self.assertTrue(np.isfinite(n).all())
        np.testing.assert_allclose(np.linalg.norm(n, axis=-1), 1, atol=1e-12)

    def test_no_internal_vertical_rings(self):
        for ix in range(256):
            self.assertLessEqual(np.count_nonzero(np.diff(np.sign(n[:, ix, 1]))), 1)


if __name__ == "__main__":
    unittest.main()
