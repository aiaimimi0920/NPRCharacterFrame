"""Author metric cuff/back seams and a sparse normal repair for this authored Body.

Input: hosiery_surface_probe.gd; never edits the canonical mesh.
The 2 mm cuff rings share heights with build_wardrobe_hosiery.py. Back seams
are symmetric about an authored leg centreline; UV island boundaries are not
physical seams. All unrelated visual maps remain byte-for-byte unchanged.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

ADDON = Path(__file__).resolve().parents[2]
SAMPLE = ADDON / "samples/silver_wolf"
ASSET = SAMPLE / "assets/authoring/silver_wolf/wardrobe"
MESH = SAMPLE / "assets/canonical/silver_wolf/body/mesh.scn"


def host_root():
    for parent in ADDON.parents:
        if (parent / "project.godot").is_file():
            return parent
    raise ValueError("No project.godot found; specify --output")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bake(probe_path: Path, output: Path, source: Path = MESH,
         garment: Path = ASSET / "garment_mask.png"):
    data = json.loads(probe_path.read_text(encoding="utf-8"))
    if data["source_sha256"] != sha(source):
        raise ValueError("Re-probe the current canonical Body")
    rows = np.array(data["vertices"], dtype=np.float64)
    if rows.ndim != 2 or rows.shape[1] != 11 or not len(rows) or not np.isfinite(rows).all():
        raise ValueError("Expected finite nonempty Nx11 surface rows")
    positions, normals, uv, rest = rows[:, :3], rows[:, 3:6], rows[:, 6:8].copy(), rows[:, 8:11]
    uv[:, 1] = 1 - uv[:, 1]
    indices = np.asarray(data["indices"])
    if (indices.ndim != 1 or not len(indices) or len(indices) % 3
            or indices.dtype.kind not in "iu" or indices.min() < 0 or indices.max() >= len(rows)):
        raise ValueError("Expected valid integer triangle indices")
    faces = indices.reshape(-1, 3)
    with Image.open(garment) as source_mask:
        if source_mask.mode != "RGBA" or source_mask.size != (1024, 512):
            raise ValueError("Sample garment must be RGBA 1024x512")
        mask = np.asarray(source_mask)[..., 3]
    h, w = mask.shape
    centers = uv[faces].mean(axis=1)
    samples = np.clip((centers * [w, h]).astype(int), 0, [w - 1, h - 1])
    skin_faces = mask[samples[:, 1], samples[:, 0]] > 250
    leg = (rest[:, 1] > .45) & (rest[:, 1] < 1.55) & (abs(rest[:, 0]) < .32)
    eligible_faces = skin_faces & leg[faces].all(axis=1)
    # Vertices touching non-skin faces are excluded: retain hard equipment edges.
    eligible = np.zeros(len(rows), bool)
    eligible[faces[eligible_faces].ravel()] = True
    eligible[faces[~skin_faces].ravel()] = False
    groups = defaultdict(list)
    for i in np.flatnonzero(eligible):
        groups[tuple(np.round(positions[i], 4))].append(int(i))
    corrections, seams = [], []
    for ids in groups.values():
        if len(ids) < 2:
            continue
        ns = normals[ids]
        if np.min(ns @ ns.T) < .75:
            continue
        normal = ns.sum(axis=0)
        normal /= np.linalg.norm(normal)
        if np.min(ns @ normal) >= .99999:
            continue
        seams.append(ids)
        for i in ids:
            corrections.append([i, *positions[i].tolist(), *normal.tolist()])
    if not corrections or not seams:
        raise ValueError("No repair candidates; review sample calibration")
    output.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": 1,
        "source_sha256": sha(source),
        "garment_sha256": sha(garment),
        "probe_sha256": sha(probe_path),
        "generator_sha256": sha(Path(__file__)),
        "inputs": {"probe": probe_path.name, "mesh": source.name, "garment": garment.name},
        "generator_config": {"numpy": np.__version__, "pillow": Image.__version__},
        "vertex_count": len(rows),
        "scope": "Private wardrobe Body, skin-only welded-position normal seams; canonical unchanged",
        "normal_rows": corrections,
        "seam_groups": seams,
        "stitch": {"width_m": .002, "cuff_heights_m": [1.32, 1.34],
                   "back_seam_heights_m": [.48, 1.34],
                   "coordinates": "CUSTOM0.yzw: normalized actor rest position in metres",
                   "centers": [[-.15,.07,0,1.36],[.15,.22,.21,1.36]]},
    }
    (output / "hosiery_surface.json").write_text(json.dumps(report, separators=(",", ":"))+"\n", encoding="utf-8")
    print(json.dumps({"normal_vertices": len(corrections), "seams": len(seams)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("probe", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--mesh", type=Path, default=MESH)
    parser.add_argument("--garment", type=Path, default=ASSET / "garment_mask.png")
    args = parser.parse_args()
    bake(args.probe, args.output or host_root() / ".temp/hosiery_surface_bake", args.mesh, args.garment)
