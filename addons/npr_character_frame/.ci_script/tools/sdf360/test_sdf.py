import unittest, numpy as np
from distance_field import distance_to, signed_distance


class FieldTests(unittest.TestCase):
    def test_exact_distance(self):
        for seed in range(12):
            a = np.random.default_rng(seed).random((9, 11)) > 0.7
            d = distance_to(a)
            p = np.argwhere(a)
            brute = np.array(
                [
                    [min(np.linalg.norm(p - [j, i], axis=1)) for i in range(11)]
                    for j in range(9)
                ]
            )
            self.assertLess(np.max(abs(d - brute)), 1e-8)

    def test_sign(self):
        a = np.indices((10, 10))[1] > 4
        d = signed_distance(a)
        self.assertTrue((d[a] > 0).all())
        self.assertTrue((d[~a] < 0).all())

    def test_uniform(self):
        self.assertTrue((signed_distance(np.ones((4, 4), bool)) == 24).all())
        self.assertTrue((signed_distance(np.zeros((4, 4), bool)) == -24).all())

    def test_mirror(self):
        a = np.random.default_rng(5).random((13, 13)) > 0.5
        np.testing.assert_allclose(
            signed_distance(a)[:, ::-1], signed_distance(a[:, ::-1])
        )


if __name__ == "__main__":
    unittest.main()
