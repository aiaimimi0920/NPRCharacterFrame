"""Check that both packed smooth-normal sources match and differ from hard normals."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


def difference(root: Path, first: str, second: str) -> dict[str, int]:
    with Image.open(root / f"{first}.png") as a, Image.open(root / f"{second}.png") as b:
        assert a.size == b.size
        channels = ImageChops.difference(a.convert("RGB"), b.convert("RGB")).split()
        diff = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
        histogram = diff.histogram()
        return {
            "changed_pixels": sum(histogram[1:]),
            "max_error": max(index for index, count in enumerate(histogram) if count),
        }


def main(root: Path) -> None:
    hard_vs_tangent = difference(root, "outline_vertex_normal", "outline_tangent_smooth")
    tangent_vs_uv2 = difference(root, "outline_tangent_smooth", "outline_uv2_oct_smooth")
    assert hard_vs_tangent["changed_pixels"] >= 100, hard_vs_tangent
    assert tangent_vs_uv2["changed_pixels"] <= 32, tangent_vs_uv2
    assert tangent_vs_uv2["max_error"] <= 8, tangent_vs_uv2
    report = {
        "hard_vs_tangent": hard_vs_tangent,
        "tangent_vs_uv2_oct": tangent_vs_uv2,
    }
    output = json.dumps(report, ensure_ascii=False, indent=2)
    (root / "smooth_normal_checks.json").write_text(output + "\n", encoding="utf-8")
    print(output)
    print("SMOOTH_NORMAL_CHECKS_OK")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
