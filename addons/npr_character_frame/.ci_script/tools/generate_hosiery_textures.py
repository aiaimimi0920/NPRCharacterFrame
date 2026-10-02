"""Rebuild the sample textile maps without Blender or a character snapshot.

Port of build_wardrobe_hosiery.py::build_textures. Keep the byte-backed image
rounding, float32 tangent normals and bottom-up Blender pixel orientation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, PngImagePlugin

ADDON = Path(__file__).resolve().parents[2]
SIZE = 128
REPEATS = 8
TEXTILE_PERIOD_M = 0.0025
LEGACY_GENERATOR_SHA256 = "998ddabb4c61139d73163ba4f82aab43ee0d459b3bcbfbcd7349c1fc3f0cc517"


def host_root() -> Path:
    for parent in ADDON.parents:
        if (parent / "project.godot").is_file():
            return parent
    raise ValueError("No host project.godot found; specify --output")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build_pixels() -> dict[str, np.ndarray]:
    pixels = {name: [] for name in ("weave", "roughness", "normal")}
    for y in range(SIZE):
        for x in range(SIZE):
            a = (x + y) * math.tau * REPEATS / SIZE
            b = (x - y) * math.tau * REPEATS / SIZE
            fiber = 0.5 + 0.25 * (math.cos(a) + math.cos(b))
            value = 0.78 + 0.22 * fiber
            encoded = 1.055 * value ** (1.0 / 2.4) - 0.055
            pixels["weave"].append((encoded, encoded, encoded))
            rough = 0.30 + 0.16 * (1.0 - fiber)
            pixels["roughness"].append((rough, rough, rough))
            # Blender mathutils uses single-precision Vector storage. Double
            # precision changes quantization at half-byte boundaries.
            normal = np.array((0.20 * (math.sin(a) + math.sin(b)),
                               0.20 * (math.sin(a) - math.sin(b)), 1.0), dtype=np.float32)
            normal /= np.float32(math.sqrt(float(np.dot(normal, normal))))
            pixels["normal"].append((normal + np.float32(1)) * np.float32(0.5))
    result = {}
    for name, values in pixels.items():
        samples = np.asarray(values).reshape(SIZE, SIZE, 3)
        # The old byte-backed PNG export rounds to nearest and reverses rows.
        result[name] = np.floor(samples[::-1] * 255 + 0.5).astype(np.uint8)
    return result


def generate(output: Path) -> dict:
    pixels = build_pixels()
    output.mkdir(parents=True, exist_ok=True)
    textures = {}
    for name, samples in pixels.items():
        filename = f"hosiery_{name}_v1.png"
        metadata = PngImagePlugin.PngInfo()
        if name == "weave":
            metadata.add(b"sRGB", b"\x03")
        Image.fromarray(samples).save(output / filename, pnginfo=metadata)
        textures[name] = {
            "path": filename,
            "color_space": "sRGB" if name == "weave" else "linear",
            "channels": {"weave": "RGB reflectance", "roughness": "R absolute roughness",
                         "normal": "RGB tangent normal"}[name],
            "size": [SIZE, SIZE],
            "mode": "RGB",
            "mipmaps": True,
            "sha256": sha256((output / filename).read_bytes()),
            "pixel_sha256": sha256(samples.tobytes()),
        }
    report = {
        "schema": 1,
        "generator": Path(__file__).name,
        "generator_sha256": sha256(Path(__file__).read_bytes()),
        "provenance": {"algorithm": "build_wardrobe_hosiery.py::build_textures",
                       "legacy_generator_sha256": LEGACY_GENERATOR_SHA256},
        "generator_config": {"numpy": np.__version__, "pillow": Image.__version__,
                             "sample_calibrated": True, "size": SIZE,
                             "textile_repeats": REPEATS, "textile_period_m": TEXTILE_PERIOD_M,
                             "tile_span_m": TEXTILE_PERIOD_M * REPEATS,
                             "normal_storage": "float32", "row_order": "Blender bottom-up to PNG top-down",
                             "quantization": "floor(sample * 255 + 0.5)"},
        "textures": textures,
        "scope": "Procedural sample textile lookdev; does not build hosiery geometry or measured yarn data",
    }
    (output / "hosiery_textures_generation.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or host_root() / ".temp/hosiery_textures_bake"
    report = generate(output)
    print(json.dumps({"maps": len(report["textures"]), "size": [SIZE, SIZE],
                      "textile_repeats": REPEATS}))


if __name__ == "__main__":
    main()
