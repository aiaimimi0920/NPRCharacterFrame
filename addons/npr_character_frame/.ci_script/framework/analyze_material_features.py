"""Validate Silver Wolf NPR 1.1 feature captures and auxiliary-buffer coverage."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


def difference(root: Path, first: str, second: str) -> dict[str, int]:
    with Image.open(root / f"{first}.png") as a, Image.open(root / f"{second}.png") as b:
        assert a.size == b.size, (first, second, "size mismatch")
        channels = ImageChops.difference(a.convert("RGB"), b.convert("RGB")).split()
        diff = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
        histogram = diff.histogram()
        return {
            "changed_pixels": sum(histogram[1:]),
            "max_error": max(index for index, count in enumerate(histogram) if count),
        }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(root: Path) -> None:
    report = json.loads((root / "material_features.json").read_text(encoding="utf-8"))
    assert report["schema_version"] == 1 and report["failures"] == 0

    checks = [
        ("stocking_half", "stocking_off", "stocking_half", 1000),
        ("stocking_full", "stocking_off", "stocking_full", 1000),
        ("matcap", "matcap_off", "matcap_full", 1000),
        ("secondary_emission", "secondary_emission_off", "secondary_emission_on", 250),
        ("region_outline", "region_outline_off", "region_outline_on", 100),
        ("lip_outline_fix", "lip_outline_fix_off", "lip_outline_fix_on", 20),
        ("expression_shadow", "expression_off", "expression_shadow", 100),
        ("expression_highlight", "expression_off", "expression_highlight", 100),
        ("expression_blush", "expression_off", "expression_blush", 100),
        ("hair_anisotropy", "hair_anisotropy_off", "hair_anisotropy_left_light", 100),
        (
            "hair_light_response",
            "hair_anisotropy_left_light",
            "hair_anisotropy_right_light",
            1000,
        ),
        ("hair_side_fade", "hair_side_fade_off", "hair_side_fade_on", 100),
        ("hair_silhouette", "hair_silhouette_off", "hair_silhouette_on", 100),
        ("visibility_dither", "visibility_100", "visibility_050", 1000),
    ]
    results: dict[str, object] = {}
    capture_set = set(report["captures"])
    for label, first, second, minimum in checks:
        assert first in capture_set and second in capture_set
        stats = difference(root, first, second)
        assert stats["changed_pixels"] >= minimum, (label, stats)
        results[label] = stats

    dissolve_counts: list[int] = []
    for amount in ("025", "050", "075", "090"):
        stats = difference(root, "dissolve_000", f"dissolve_{amount}")
        dissolve_counts.append(stats["changed_pixels"])
        results[f"dissolve_{amount}"] = stats
    assert all(a < b for a, b in zip(dissolve_counts, dissolve_counts[1:])), dissolve_counts

    auxiliary = report["auxiliary"]
    full = auxiliary["auxiliary_dissolve_000"]
    dissolved = auxiliary["auxiliary_dissolve_050"]
    assert full["width"] > 16 and full["height"] > 16
    assert full["coverage"] > 0 and dissolved["coverage"] < full["coverage"]
    assert all(count > 0 for count in full["roles"]), full["roles"]
    results["auxiliary"] = {
        "full_coverage": full["coverage"],
        "dissolved_coverage": dissolved["coverage"],
        "roles": full["roles"],
        "size": [full["width"], full["height"]],
    }

    attributes = auxiliary["mesh_attributes"]
    assert len(attributes) == 3
    assert attributes[2]["tangent"], "Silver Wolf hair must provide Tangent"
    results["mesh_attributes"] = attributes

    project = Path(__file__).resolve().parents[2]
    generation_path = project / "samples/silver_wolf/assets/authoring/silver_wolf/optional/generation.json"
    generation = json.loads(generation_path.read_text(encoding="utf-8"))
    assert generation["schema_version"] == 2 and len(generation["outputs"]) == 7
    assert generation["quality_checks"]["all_passed"]
    for record in generation["outputs"].values():
        path = project / record["path"]
        assert path.is_file() and sha256(path) == record["sha256"]
        with Image.open(path) as image:
            assert image.size == (record["width"], record["height"])
        assert set(record["channels"]) == {"R", "G", "B", "A"}
    assert "face_outline_control.png" in generation["outputs"]
    results["generated_texture_manifest"] = {
        "outputs": len(generation["outputs"]),
        "sha256_verified": True,
    }

    output = json.dumps(results, ensure_ascii=False, indent=2)
    (root / "material_feature_checks.json").write_text(output + "\n", encoding="utf-8")
    print(output)
    print("MATERIAL_FEATURE_CHECKS_OK")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
