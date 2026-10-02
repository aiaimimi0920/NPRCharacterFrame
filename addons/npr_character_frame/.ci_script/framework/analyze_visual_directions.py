"""Analyze focused visual-direction captures without accepting global averages."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def load(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.int16)


def changed(a: np.ndarray, b: np.ndarray, roi: tuple[slice, slice], threshold: int = 6) -> int:
    delta = np.abs(a[roi] - b[roi]).max(axis=2)
    return int((delta > threshold).sum())


def analyze(directory: Path) -> dict:
    default = load(directory / "default.png")
    enabled = load(directory / "enabled.png")
    reset = load(directory / "reset.png")
    wrong = load(directory / "wrong_domain.png")
    eye_neutral = load(directory / "eye_temporal_neutral.png")
    eye_left = load(directory / "eye_temporal_left_expression.png")
    eye_right = load(directory / "eye_temporal_right_expression.png")
    eye_reset = load(directory / "eye_temporal_reset.png")
    h, w = default.shape[:2]
    body_roi = (slice(int(h * 0.30), int(h * 0.96)), slice(int(w * 0.22), int(w * 0.74)))
    face_roi = (slice(int(h * 0.08), int(h * 0.42)), slice(int(w * 0.28), int(w * 0.68)))
    background = (slice(0, int(h * 0.20)), slice(0, int(w * 0.20)))
    eye_roi = (slice(int(h * 0.12), int(h * 0.45)), slice(int(w * 0.25), int(w * 0.75)))
    report = {
        "enabled_body_changed": changed(default, enabled, body_roi),
        "enabled_face_changed": changed(default, enabled, face_roi),
        "reset_pixels_changed": changed(default, reset, (slice(None), slice(None)), 0),
        "wrong_domain_background_changed": changed(default, wrong, background),
        "eye_temporal_left_changed": changed(eye_neutral, eye_left, eye_roi),
        "eye_temporal_right_changed": changed(eye_neutral, eye_right, eye_roi),
        "eye_temporal_reset_changed": changed(eye_neutral, eye_reset, (slice(None), slice(None)), 0),
    }
    checks = {
        "target_body_changes": report["enabled_body_changed"] > 200,
        "target_face_changes": report["enabled_face_changed"] > 20,
        # Explicit simulation inputs now permit exact full-frame RGBA recovery.
        "reset_returns_to_baseline": report["reset_pixels_changed"] == 0,
        "background_negative_control": report["wrong_domain_background_changed"] < 20,
        "eye_temporal_left": report["eye_temporal_left_changed"] > 20,
        "eye_temporal_right": report["eye_temporal_right_changed"] > 20,
        "eye_temporal_reset": report["eye_temporal_reset_changed"] == 0,
    }
    return {"metrics": report, "checks": checks}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    args = parser.parse_args()
    result = analyze(args.input)
    (args.input / "visual_analysis.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if all(result["checks"].values()) else 1)


if __name__ == "__main__":
    main()
