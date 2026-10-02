"""Generate deterministic authored masks for the six visual-direction lookdev paths.

The maps are intentionally authored from the existing garment mask and fixed UV
regions. They are inputs to the runtime contracts, not test-only overrides.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ADDON = Path(__file__).resolve().parents[2]
SOURCE = ADDON / "samples/silver_wolf/import_sources/visual_maps_garment_v1.png"


def host_root() -> Path:
    for parent in ADDON.parents:
        if (parent / "project.godot").is_file():
            return parent
    raise ValueError("No project.godot found; specify --output")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--source", type=Path, default=SOURCE,
                        help="Explicit garment source for reproducible sample maps")
    args = parser.parse_args()
    output = args.output or host_root() / ".temp/visual_maps_bake"
    garment_path = args.source
    with Image.open(garment_path) as source:
        if source.mode != "RGBA" or source.size != (1024, 512):
            raise ValueError("Sample garment source must be RGBA 1024x512")
        garment = np.asarray(source, dtype=np.float32) / 255.0
    output.mkdir(parents=True, exist_ok=True)
    alpha = garment[..., 3]
    fabric = np.maximum(garment[..., 0], np.maximum(garment[..., 1], garment[..., 2]))
    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w]
    uv_x = (xx + 0.5) / w
    uv_y = (yy + 0.5) / h

    # Thin tulle follows the existing garment domain but is kept in its own
    # grayscale asset so it cannot be confused with the dye channels.
    tulle = np.clip(alpha * (0.58 + 0.18 * np.sin(uv_x * 260.0) ** 2), 0.0, 1.0)
    tulle = np.asarray(Image.fromarray((tulle * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)))
    Image.fromarray(tulle).save(output / "tulle_mask.png")

    # Legacy UV-mask consumers only. Wardrobe now uses metric rest-space seams.
    binary = Image.fromarray((alpha > 0.35).astype(np.uint8) * 255)
    eroded = np.asarray(binary.filter(ImageFilter.MinFilter(9)), dtype=np.float32) / 255.0
    stitch = np.clip((alpha > 0.2).astype(np.float32) - eroded, 0.0, 1.0)
    stitch *= np.clip(1.0 - np.abs(uv_y - 0.46) / 0.18, 0.0, 1.0)
    Image.fromarray((stitch * 255).astype(np.uint8)).save(output / "stitch_mask.png")

    # Wetness is a linear scalar. It is strongest on exposed skin and lower
    # fabric, with a gentle authored gradient for lookdev repeatability.
    skin = alpha
    wet = np.clip(0.18 + 0.42 * skin + 0.28 * fabric + 0.12 * (1.0 - uv_y), 0.0, 1.0)
    wet *= np.clip(1.0 - 0.45 * np.abs(uv_x - 0.5), 0.0, 1.0)
    Image.fromarray((wet * 255).astype(np.uint8)).save(output / "wetness_map.png")

    # Shader uses (UV.x, 1-UV.y): lower iris vertices occupy y=0.01..0.12.
    # The old y=0.192 mask covered the upper iris. Keep this lobe below the pupil;
    # ILM and the iris island further restrict it in the production shader.
    eye = np.exp(-(((uv_x - 0.130) / 0.085) ** 2 + ((uv_y - 0.075) / 0.045) ** 2) * 3.0)
    eye = np.clip(eye * np.clip((0.125 - uv_y) / 0.09, 0.0, 1.0), 0.0, 1.0)
    Image.fromarray((eye * 255).astype(np.uint8)).save(output / "eye_tear_mask.png")

    # Hair receives a separate directional scalar, avoiding reuse of the body
    # map in the shader contract.
    hair = np.clip(0.18 + 0.62 * np.sin((uv_x * 1.7 + uv_y * 0.4) * np.pi) ** 2, 0.0, 1.0)
    Image.fromarray((hair * 255).astype(np.uint8)).save(output / "hair_wetness_map.png")

    manifest = {
        "schema": 1,
        "source": {"name": garment_path.name, "sha256": _sha256(garment_path)},
        "maps": {
            name: {"path": f"{name}.png", "colorspace": "linear", "channel": "R", "sha256": _sha256(output / f"{name}.png")}
            for name in ["tulle_mask", "stitch_mask", "wetness_map", "eye_tear_mask", "hair_wetness_map"]
        },
        "defaults": {"wetness": 0.0, "eye_wetness": 0.0, "wind_strength": 0.0, "soft_tissue_pressure": 0.0},
        "notes": "Authored lookdev maps; source generation is deterministic and reversible.",
        "generator_sha256": _sha256(Path(__file__)),
        "generator_config": {"numpy": np.__version__, "pillow": Image.__version__, "sample_calibrated": True},
        "eye_sheen_mapping": {"uv": "face shader (UV.x, 1-UV.y)", "center": [0.130, 0.075], "scope": "lower original iris", "generator_sha256": _sha256(Path(__file__))},
    }
    (output / "visual_maps_generation.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
