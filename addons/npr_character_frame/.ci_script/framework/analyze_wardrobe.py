"""Strict GPU wardrobe gates using independent authored ownership captures.

The region images retain production geometry, depth, skinning and MSAA. A pixel
with any green/blue sample may contain garment/hosiery coverage. All other
pixels must be byte-exact; there is no RGB tolerance or screen-space crop.
"""

import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def changed(delta: np.ndarray, domain: np.ndarray) -> int:
    return int(np.any(delta[domain], axis=-1).sum())


def analyze(root: Path) -> dict:
    manifest = json.loads((root / "wardrobe_regions.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != 1:
        raise ValueError("Unsupported wardrobe region schema")
    cache = {}
    checks = []
    metrics = {"palette": {}, "hosiery": {}, "negative_controls": {}}

    def check(condition, label):
        checks.append({"label": label, "pass": bool(condition)})

    def load(name, filename, expected):
        path = root / filename
        if Path(filename).name != filename or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Capture identity mismatch: {name}")
        return np.asarray(Image.open(path).convert("RGBA"), dtype=np.int16)

    def image(name):
        if name not in cache:
            cache[name] = load(name, f"{name}_stage.png", manifest["frames"][name])
        return cache[name]

    def regions(name):
        entry = manifest["regions"][name]
        if not all(entry.get(key) is True for key in ("saved", "exact_restore", "camera_unchanged")):
            raise ValueError(f"Region capture changed production state: {name}")
        marker = load(name, entry["file"], entry["sha256"])
        frame = image(name)
        if marker.shape != frame.shape or entry["size"] != [frame.shape[1], frame.shape[0]]:
            raise ValueError(f"Region/frame size mismatch: {name}")
        dye, hosiery = marker[..., 1] > 0, marker[..., 2] > 0
        head = (marker[..., 0] > 0) & ~dye & ~hosiery
        # No arbitrary erosion: exclude only genuinely mixed MSAA coverage.
        core = (marker[..., 2] == 255) & ~dye & ~head
        for domain, label in ((dye, "dye"), (hosiery, "hosiery"), (head, "head"), (core, "leg core")):
            if not domain.any() or domain.all():
                raise ValueError(f"Empty or unbounded {label} region: {name}")
        return {"dye": dye, "hosiery": hosiery, "head": head, "core": core}

    front = regions("default")
    back = regions("back_opaque")
    base = image("default")
    for index in range(1, 7):
        difference = np.abs(image(f"palette{index}") - base)
        row = {"visible": int((difference[..., :3].max(2) > 2).sum()),
               "outside_dye": changed(difference, ~front["dye"]),
               "head": changed(difference, front["head"]),
               "alpha": int(np.count_nonzero(difference[..., 3]))}
        metrics["palette"][str(index)] = row
        check(row["visible"] > 10000, f"Palette {index} visibly recolors clothing")
        check(row["head"] == 0, f"Palette {index} preserves visible head, hair and eyes exactly")
        check(row["outside_dye"] == 0, f"Palette {index} preserves every non-dye pixel, including waist skin")
        check(row["alpha"] == 0, f"Palette {index} preserves full alpha coverage")

    for prefix, region in (("stocking", front), ("back", back)):
        delta = np.abs(image(prefix + "_opaque") - image(prefix + "_transparent"))
        row = {"visible": int((delta[..., :3].max(2) > 2).sum()),
               "outside_hosiery": changed(delta, ~region["hosiery"]),
               "alpha": int(np.count_nonzero(delta[..., 3]))}
        metrics["hosiery"][prefix] = row
        check(row["visible"] > 5000, f"{prefix} visibly changes leg pixels")
        check(row["outside_hosiery"] == 0, f"{prefix} preserves all non-hosiery pixels, including upper body and fingers")
        check(row["alpha"] == 0, f"{prefix} preserves opaque skin silhouette")
    brightness = [float(image(name)[front["core"], :3].mean())
                  for name in ("stocking_opaque", "default", "stocking_transparent")]
    metrics["leg_brightness"] = brightness
    check(brightness[0] < brightness[1] < brightness[2], "Opacity monotonically darkens actual hosiery interior")
    neutral = image("expression0")
    for index in range(1, 5):
        check((np.abs(image(f"expression{index}") - neutral) > 2).sum() > 100,
              f"Expression {index} visibly changes the face")

    negative = regions("negative_reference")
    reference = image("negative_reference")
    for name, domain in (("face_dye", negative["head"]), ("clothing_leak", ~negative["dye"]),
                         ("hosiery_leak", ~negative["hosiery"])):
        count = changed(np.abs(image("negative_" + name) - reference), domain)
        metrics["negative_controls"][name] = count
        check(count > 0, f"Real GPU {name} is rejected by the same exact domain gate")
    alpha_errors = int(np.count_nonzero(image("negative_alpha")[..., 3] != reference[..., 3]))
    metrics["negative_controls"]["alpha"] = alpha_errors
    check(alpha_errors > 0, "Real GPU alpha damage is rejected")
    image("negative_restored")  # Verify the actual file, not only two manifest values.
    check(manifest["frames"]["negative_reference"] == manifest["frames"]["negative_restored"],
          "Negative controls restore exact production PNG bytes")
    return {"schema": 1, "checks": checks, "metrics": metrics}


def main(root: Path) -> int:
    try:
        report = analyze(root)
    except (OSError, ValueError, KeyError) as error:
        report = {"schema": 1, "checks": [], "input_error": str(error)}
    passed = "input_error" not in report and all(row["pass"] for row in report["checks"])
    (root / "wardrobe_analysis.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(("WARDROBE_IMAGES_OK " if passed else "WARDROBE_IMAGES_FAILED ") + json.dumps(report))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main(Path(sys.argv[1])))
