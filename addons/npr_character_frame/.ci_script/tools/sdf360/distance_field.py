"""Original exact squared Euclidean distance transform, separable lower envelope."""

import numpy as np


def edt_line(f):
    n = len(f)
    v = np.zeros(n, dtype=np.int32)
    z = np.empty(n + 1)
    out = np.empty(n)
    k = 0
    z[0] = -np.inf
    z[1] = np.inf
    for q in range(1, n):
        s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * (q - v[k]))
        while s <= z[k]:
            k -= 1
            s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * (q - v[k]))
        k += 1
        v[k] = q
        z[k] = s
        z[k + 1] = np.inf
    k = 0
    for q in range(n):
        while z[k + 1] < q:
            k += 1
        out[q] = (q - v[k]) ** 2 + f[v[k]]
    return out


def distance_to(mask):
    f = np.where(mask, 0.0, 1e9)
    f = np.stack([edt_line(row) for row in f])
    return np.sqrt(np.stack([edt_line(col) for col in f.T]).T)


def signed_distance(lit, spread=24.0):
    if lit.all():
        return np.ones(lit.shape) * spread
    if not lit.any():
        return np.ones(lit.shape) * -spread
    return np.clip(distance_to(~lit) - distance_to(lit), -spread, spread)
