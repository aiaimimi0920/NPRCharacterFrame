"""Validate authored contact geometry and fixed-camera local GPU evidence.

Requires Pillow/numpy from the project's existing image-analysis environment.
This gate rejects wrong-domain geometry; it never edits assets or references.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rectangle(shape: tuple, coordinates: list, padding: int = 8) -> np.ndarray:
    height, width = shape[:2]
    x0, y0, x1, y1 = coordinates
    x0, y0 = np.maximum(np.floor([x0, y0]).astype(int) - padding, 0)
    x1, y1 = np.minimum(np.ceil([x1, y1]).astype(int) + padding, [width, height])
    mask = np.zeros((height, width), dtype=bool)
    mask[y0:y1, x0:x1] = True
    return mask


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--rebuild", type=Path)
    parser.add_argument("--backup", type=Path, help="Also verify every external pristine input")
    args = parser.parse_args()
    output = args.output
    report = json.loads((output / "soft_tissue.json").read_text(encoding="utf-8"))
    asset_path = ASSETS / "soft_tissue_v1.json"
    asset = json.loads(asset_path.read_text(encoding="utf-8"))
    generation_path = ASSETS / "soft_tissue_generation.json"
    generation = json.loads(generation_path.read_text(encoding="utf-8"))
    checks: list[dict] = []
    measurements: list[dict] = []

    def check(condition: bool, label: str, **values) -> None:
        checks.append({"pass": bool(condition), "label": label, **values})

    check(all(row["pass"] for row in report["checks"]), "Runtime geometry, passes, picking and lifecycle")
    check(report["renderer"] == "forward_plus" and bool(report["gpu"]), "Real Forward+ GPU identity")
    check(report["asset_sha256"] == digest(asset_path) == generation["bridge_sha256"], "Captured bridge identity")
    check(report["generation_sha256"] == digest(generation_path), "Captured generation identity")
    check(digest(ROOT / generation["source_blend"]) == generation["source_blend_sha256"], "Saved Blender source identity")
    check(digest(ROOT / generation["generator"]) == generation["generator_sha256"], "Rebuild script identity")
    input_manifest = ROOT / generation["input_manifest"]
    input_probe = ROOT / generation["input_probe"]
    check(digest(input_manifest) == generation["backup_manifest_sha256"], "Pristine snapshot identity")
    check(digest(input_probe) == asset["source"]["probe_sha256"], "Portable canonical probe identity")
    if args.backup:
        snapshot = json.loads((args.backup / "manifest.json").read_text(encoding="utf-8"))
        check(digest(args.backup / "manifest.json") == digest(input_manifest), "External pristine identity")
        check(all(digest(args.backup / "files" / row["path"]) == row["sha256"] for row in snapshot["files"]),
              "Every pristine input remains recoverable", files=len(snapshot["files"]))
    probe = json.loads(input_probe.read_text(encoding="utf-8"))
    positions = np.asarray(probe["meshes"][0]["positions"], dtype=float)
    rows = np.asarray(asset["deltas"], dtype=float)
    indices = rows[:, 0].astype(int)
    deltas = rows[:, 1:4]
    center = np.asarray(asset["collision"]["center"], dtype=float)
    radial = positions[indices][:, [0, 2]] - center[[0, 2]]
    new_radial = radial + deltas[:, [0, 2]]
    clearance = np.linalg.norm(new_radial, axis=1) - asset["collision"]["radius"]
    displacement = np.linalg.norm(deltas, axis=1)
    height = positions[indices, 1]
    check(len(set(indices)) == len(indices) and len(indices) >= 24, "Sparse asset indices are unique and meaningful")
    check(np.all((height >= 1.17) & (height <= 1.42)) and np.all(positions[indices, 0] < 0.0),
          "Authored domain is restricted to the left stocking contact")
    check(displacement.max() <= 0.009001 and displacement.max() >= 0.008,
          "Real corrective contains bounded compression", maximum_metres=float(displacement.max()))
    change = np.linalg.norm(new_radial, axis=1) - np.linalg.norm(radial, axis=1)
    check(change.min() < -0.008 and change.max() > 0.002,
          "Contact indentation and adjacent bulge both exist")
    check(clearance.min() >= 0.00099, "All authored positions respect the rigid collision core", minimum_metres=float(clearance.min()))
    if args.rebuild:
        rebuilt = args.rebuild / "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/soft_tissue_v1.json"
        check(digest(rebuilt) == digest(asset_path), "Independent rebuild produces identical position data")

    captures = {row["name"]: row for row in report["captures"]}

    def pixels(name: str) -> np.ndarray:
        return np.asarray(Image.open(output / f"{name}.png").convert("RGBA"), dtype=np.int16)

    def depth(name: str) -> np.ndarray:
        entry = captures[name]
        width, height = entry["depth_size"]
        data = np.frombuffer((output / f"{name}_depth.bin").read_bytes(), dtype=np.uint8)
        return data.reshape(height, width, int(entry["depth_stride"]))

    def decoded_depth(name: str) -> tuple:
        entry = captures[name]
        raw = depth(name)
        if entry["depth_format"] != 14 or entry["depth_stride"] != 6:
            raise ValueError("Expected the production RGBH depth encoder; unsupported format")
        values = raw.view("<f2").reshape(raw.shape[0], raw.shape[1], 3)
        coverage = values[..., 2] > 0.5
        red = values[..., 0].astype(np.float64)
        green = values[..., 1]
        # npr_depth_encode.gdshader stores (floor(d*256)/256, fract(d*256), coverage).
        # R's multiples of 1/256 are exact in half precision. G has a bounded
        # round-to-nearest half ULP. Compare decoded metre intervals because the
        # conservative shape bounds legitimately change each capture's range.
        check(np.all(red[coverage] * 256 == np.floor(red[coverage] * 256)), "Depth R has exact split encoding: " + name)
        lower = (np.nextafter(green, np.float16(-np.inf)).astype(float) + green.astype(float)) * 0.5
        upper = (np.nextafter(green, np.float16(np.inf)).astype(float) + green.astype(float)) * 0.5
        scale = float(entry["depth_range"])
        value = (red + green.astype(float) / 256.0) * scale
        rounding = np.maximum(green.astype(float) - lower, upper - green.astype(float)) / 256.0
        # Four float32 arithmetic roundings cover divide/multiply/fract and
        # reconstruction. This is an encoding error bound, not a visual tolerance.
        bound = (rounding + 4 * np.finfo(np.float32).eps) * scale
        return value, coverage, bound

    for view in ["front", "side", "back", "full"]:
        off = pixels(view + "_off")
        on = pixels(view + "_on")
        half = pixels(view + "_half")
        reset = pixels(view + "_reset")
        roi = rectangle(off.shape, captures[view + "_off"]["roi"])
        receiver = rectangle(off.shape, captures[view + "_off"]["shadow_roi"], padding=0)
        delta = np.max(np.abs(on - off), axis=2)
        half_delta = np.max(np.abs(half - off), axis=2)
        changed = delta > 1
        outside = int(np.count_nonzero(changed & ~(roi | receiver)))
        target = int(np.count_nonzero(changed & roi))
        half_target = int(np.count_nonzero((half_delta > 1) & roi))
        check(target >= 8 and half_target >= 4, f"Local full/half pressure visible: {view}", full=target, half=half_target)
        check(outside == 0, f"Non-target color/coverage unchanged: {view}", pixels=outside)
        check(np.array_equal(off, reset), f"Color and alpha reset exactly: {view}")
        depth_off, cover_off, error_off = decoded_depth(view + "_off")
        depth_on, cover_on, error_on = decoded_depth(view + "_on")
        depth_changed = (cover_off != cover_on) | (
            cover_off & cover_on & (np.abs(depth_on - depth_off) > error_off + error_on)
        )
        depth_roi = rectangle(depth_off.shape, [
            value * depth_off.shape[1 if i % 2 == 0 else 0] / off.shape[1 if i % 2 == 0 else 0]
            for i, value in enumerate(captures[view + "_off"]["roi"])
        ])
        target_depth = int(np.count_nonzero(depth_changed & depth_roi))
        outside_depth = int(np.count_nonzero(depth_changed & ~depth_roi))
        check(target_depth >= 1 and outside_depth == 0, f"Actual GPU depth updates only in the contact ROI: {view}",
              target_pixels=target_depth, outside_pixels=outside_depth)
        check(np.array_equal(depth(view + "_off"), depth(view + "_reset")), f"GPU depth reset exactly: {view}")
        measurements.append({"view": view, "target_pixels": target, "half_pixels": half_target,
                             "outside_pixels": outside, "depth_changed_pixels": target_depth})

    shadow_pixels = 0
    for action in ["idle", "greeting", "look_around", "presentation"]:
        off, on = pixels(action + "_off"), pixels(action + "_on")
        roi = rectangle(off.shape, captures[action + "_off"]["roi"])
        receiver = rectangle(off.shape, captures[action + "_off"]["shadow_roi"], padding=0)
        change = np.max(np.abs(on - off), axis=2) > 1
        shadow_pixels += int(np.count_nonzero(change & receiver & ~roi))
        check(np.count_nonzero(change & roi) >= 8 and not np.any(change & ~(roi | receiver)),
              f"Pressure stays local during authored action: {action}")
    check(shadow_pixels >= 8, "Real receiver shadow responds to the compressed geometry", pixels=shadow_pixels)

    off, wrong = pixels("wrong_off"), pixels("wrong_domain")
    roi = rectangle(off.shape, captures["wrong_off"]["roi"])
    outside_wrong = int(np.count_nonzero((np.max(np.abs(wrong - off), axis=2) > 1) & ~roi))
    check(outside_wrong >= 50, "Wrong-domain geometry is rejected by the same ROI invariant", pixels=outside_wrong)
    timings = []
    for block in report["timings"]:
        summary = {"action": block["action"], "pressure": block["pressure"], "samples": len(block["samples"]),
                   "secondary_peaks": block["secondary_peaks"], "secondary_budgets": block["secondary_budgets"]}
        for key in ["pose_us", "cpu_ms", "gpu_ms"]:
            values = np.asarray([row[key] for row in block["samples"]], dtype=float)
            check(len(values) == 120 and np.isfinite(values).all() and np.all(values >= 0), f"Measured {key} is valid")
            summary[key] = {"median": float(np.median(values)), "p95": float(np.percentile(values, 95)), "peak": float(values.max())}
        timings.append(summary)
    result = {"schema": 1, "pass": all(row["pass"] for row in checks), "checks": checks,
              "images": measurements, "timings": timings,
              "timing_scope": "Single-machine actor Stage only; not application FPS or cross-device certification"}
    (output / "soft_tissue_analysis.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    failed = [row for row in checks if not row["pass"]]
    print(f"SOFT_TISSUE_ANALYSIS checks={len(checks)} failures={len(failed)}")
    for row in failed:
        print(json.dumps(row))
    raise SystemExit(0 if result["pass"] else 1)


if __name__ == "__main__":
    main()
