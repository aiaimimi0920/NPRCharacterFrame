"""Bake garment domains from the displayed rest mesh, without changing source assets.

Input is the preserved sample rest probe. RGB select cool cloth, dark cloth
and light trim; A selects exposed lower-body skin for an opaque-skin hosiery layer.
"""

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ADDON = Path(__file__).resolve().parents[2]
SAMPLE = ADDON / "samples/silver_wolf"
SOURCE = SAMPLE / "assets/authoring/silver_wolf/import_sources/body/texture/base.png"
PROBE = SAMPLE / "import_sources/soft_tissue_input_probe.json"


def host_root() -> Path:
    for parent in ADDON.parents:
        if (parent / "project.godot").is_file():
            return parent
    raise ValueError("No host project.godot found; specify --output")


def read_mesh(probe: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    mesh = json.loads(probe.read_text(encoding="utf-8"))["meshes"][0]
    positions = np.asarray(mesh["positions"], dtype=float)
    uv = np.asarray(mesh["uv"], dtype=float)
    indices = np.asarray(mesh["indices"])
    if positions.ndim != 2 or positions.shape[1] != 3 or not len(positions):
        raise ValueError("Expected nonempty Nx3 positions")
    if uv.shape != (len(positions), 2):
        raise ValueError("Expected one UV pair per vertex")
    if not np.isfinite(positions).all() or not np.isfinite(uv).all():
        raise ValueError("Positions and UVs must be finite")
    if (indices.ndim != 1 or not len(indices) or len(indices) % 3
            or indices.dtype.kind not in "iu" or indices.min() < 0
            or indices.max() >= len(positions)):
        raise ValueError("Expected valid integer triangle indices")
    return positions, uv, indices.reshape(-1, 3)


def head_only_vertices(positions: np.ndarray, indices: np.ndarray) -> np.ndarray:
    """Classify whole connected surfaces, welding imported position seams."""
    parent = list(range(len(positions)))

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left: int, right: int) -> None:
        parent[find(left)] = find(right)

    for a, b, c in indices:
        union(a, b)
        union(b, c)
    seams = {}
    for index, point in enumerate(positions):
        key = tuple(np.round(point, 5))
        if key in seams:
            union(index, seams[key])
        else:
            seams[key] = index
    roots = np.array([find(index) for index in range(len(positions))])
    minimum = {}
    for group, point in zip(roots, positions):
        minimum[group] = min(minimum.get(group, float("inf")), point[1])
    return np.array([minimum[group] >= 2.32 for group in roots])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("probe", type=Path, nargs="?", default=PROBE)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--legacy-height-cutoff", action="store_true",
                        help="Reproduce the old per-pixel height rule for comparison only")
    args = parser.parse_args()
    source = args.source
    positions, uv, indices = read_mesh(args.probe)
    with Image.open(source) as texture:
        if texture.size != (1024, 512) or texture.mode not in ("RGB", "RGBA"):
            raise ValueError("Sample base texture must be RGB/RGBA 1024x512")
        base = np.asarray(texture.convert("RGB"), dtype=float) / 255
    h, w = base.shape[:2]
    uv = uv * [w, h]
    head = head_only_vertices(positions, indices)
    head_usage = np.zeros((h, w), dtype=bool)
    low = np.full((h, w), np.inf)
    high = np.full((h, w), -np.inf)
    for ids in indices:
        tri = uv[ids]
        x0, y0 = np.maximum(np.floor(tri.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(tri.max(0)).astype(int), [w - 1, h - 1])
        if x1 < x0 or y1 < y0:
            continue
        a, b, c = tri
        det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(det) < 1e-8:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
        u = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / det
        v = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / det
        inside = (u >= -0.002) & (v >= -0.002) & (u + v <= 1.002)
        height = u * positions[ids[0], 1] + v * positions[ids[1], 1]
        height += (1 - u - v) * positions[ids[2], 1]
        lo, hi = low[y0:y1 + 1, x0:x1 + 1], high[y0:y1 + 1, x0:x1 + 1]
        lo[inside] = np.minimum(lo[inside], height[inside])
        hi[inside] = np.maximum(hi[inside], height[inside])
        if head[ids].any():
            head_usage[y0:y1 + 1, x0:x1 + 1] |= inside
    r, g, b = base.transpose(2, 0, 1)
    skin = (r > g * 1.03) & (r > b * 1.05) & (r > 0.58)
    skin_guard = np.asarray(Image.fromarray(skin.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0
    # Reject UVs used by any protected head component, including shared islands.
    # A tall collar remains one wearable surface instead of being sliced at 2.32 m.
    excluded = (high >= 2.32) if args.legacy_height_cutoff else head_usage
    garment = np.isfinite(low) & ~excluded & ~skin_guard
    cool = garment & (b > r * 1.12) & (b > g * 1.06) & (base.max(2) >= 0.48)
    dark = garment & ~cool & (base.max(2) < 0.48)
    trim = garment & ~cool & (base.min(2) > 0.65) & (base.max(2) - base.min(2) < 0.12)
    # The actor's rest-vertex CUSTOM0 domain selects legs independently of UV
    # seams. Alpha identifies skin inside that domain; it is not body alpha.
    stocking = skin
    mask = np.stack([cool, dark, trim, stocking], axis=2).astype(np.uint8) * 255
    assert mask[..., 3].sum() > 0, "No leg skin found"
    assert not mask[skin, :3].any(), "Garment colors must exclude skin"
    out = args.output or host_root() / ".temp/garment_bake"
    out.mkdir(parents=True, exist_ok=True)
    Image.fromarray(mask).save(out / "garment_mask.png")
    manifest = {
        "schema": 1, "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "probe_sha256": hashlib.sha256(args.probe.read_bytes()).hexdigest(),
        "channels": ["cool fabric", "dark fabric", "light trim", "skin for vertex-gated hosiery"],
        "covered_pixels": (mask > 0).sum(axis=(0, 1)).tolist(),
        "identity": "Skin excluded from RGB; head-only components excluded; face/hair assets untouched",
        "domain_policy": "legacy height cutoff" if args.legacy_height_cutoff else "connected surface minimum height with conservative shared-UV exclusion",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "output_sha256": hashlib.sha256((out / "garment_mask.png").read_bytes()).hexdigest(),
        "head_only_vertices": int(head.sum()),
        "note": "Source model and UVs unchanged; full connected collars remain dyeable",
        "inputs": {"base_texture": source.name, "rest_probe": args.probe.name},
        "generator_config": {"numpy": np.__version__, "pillow": Image.__version__,
                             "sample_calibrated": True, "head_minimum_y": 2.32,
                             "legacy_height_cutoff": args.legacy_height_cutoff},
    }
    (out / "generation.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest))


if __name__ == "__main__":
    main()
