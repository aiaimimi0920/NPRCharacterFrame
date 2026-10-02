"""Rasterize explicitly authored material regions; never infer class from color."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ADDON = Path(__file__).resolve().parents[2]
SAMPLE = ADDON / "samples/silver_wolf"
PROBE = SAMPLE / "import_sources/soft_tissue_input_probe.json"
RECIPE = SAMPLE / "import_sources/material_wetness_recipe.json"
MESH = SAMPLE / "assets/canonical/silver_wolf/body/mesh.scn"

def host_root():
    for parent in ADDON.parents:
        if (parent / "project.godot").is_file():
            return parent
    raise ValueError("No project.godot found; specify --output")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("probe", type=Path, nargs="?", default=PROBE)
    parser.add_argument("--regions", type=Path, default=RECIPE)
    parser.add_argument("--mesh", type=Path, default=MESH)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = args.regions
    config = json.loads(source.read_text(encoding="utf-8"))
    if sha(args.mesh) != config["source_mesh_sha256"]:
        raise ValueError("Source mesh changed: re-author regions")
    if sha(args.probe) != config["probe_sha256"]:
        raise ValueError("Probe identity changed: regenerate and review authored regions")
    if config.get("schema") != 1:
        raise ValueError("Expected regions schema 1")
    for region in config["groups"]:
        if type(region["channel"]) is not int or not 0 <= region["channel"] < 4:
            raise ValueError("Region channel must be an integer in 0..3")
        if not region["ids"] or any(type(i) is not int or not 0 <= i < 108 for i in region["ids"]):
            raise ValueError("Region IDs must refer to sample groups 0..107")
        for box in region.get("exclude_uv_rects", []):
            if (len(box) != 4 or any(type(v) is not int for v in box)
                    or not 0 <= box[0] <= box[2] < 1024
                    or not 0 <= box[1] <= box[3] < 512):
                raise ValueError("Invalid exclusion rectangle")
    out = args.output or host_root() / ".temp/material_wetness_bake"
    data = json.loads(args.probe.read_text(encoding="utf-8"))["meshes"][0]
    positions, uv = np.asarray(data["positions"]), np.asarray(data["uv"])
    triangles = np.asarray(data["indices"]).reshape(-1, 3)
    parent = list(range(len(positions)))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    def union(a, b):
        parent[find(a)] = find(b)
    for a, b, c in triangles:
        union(a, b)
        union(b, c)
    seams = {}
    for i, point in enumerate(positions):
        key = tuple(np.round(point, 5))
        if key in seams:
            union(i, seams[key])
        else:
            seams[key] = i
    roots = [find(i) for i in range(len(positions))]
    order = sorted(set(roots), key=lambda key: roots.index(key))
    ids = np.asarray([order.index(key) for key in roots])
    if len(ids) != 21273 or len(order) != 108:
        raise ValueError("Re-author material groups for changed topology")
    channels = np.zeros((512, 1024, 4), dtype=np.uint8)
    for region in config["groups"]:
        mask = Image.new("L", (1024, 512))
        draw = ImageDraw.Draw(mask)
        for face in triangles[np.isin(ids[triangles[:, 0]], region["ids"])]:
            draw.polygon([tuple(uv[index] * [1024, 512]) for index in face], fill=255)
        for box in region.get("exclude_uv_rects", []):
            draw.rectangle(box, fill=0)
        channels[:, :, region["channel"]] |= np.asarray(mask)
    conflict = (channels > 0).sum(2) > 1
    channels[conflict] = 0
    out.mkdir(parents=True, exist_ok=True)
    Image.fromarray(channels).save(out / "material_wetness.png")
    manifest = {"schema": 1, "source_mesh_sha256": sha(args.mesh),
                "probe_sha256": sha(args.probe), "regions_sha256": sha(source),
                "generator_sha256": sha(Path(__file__)), "output_sha256": sha(out / "material_wetness.png"),
                "channels": config["channels"], "colorspace": "linear", "conflicting_texels_excluded": int(conflict.sum()),
                "texels": [int((channels[:, :, i] > 0).sum()) for i in range(4)],
                "inputs": {"probe": args.probe.name, "mesh": args.mesh.name, "regions": source.name},
                "generator_config": {"numpy": np.__version__, "pillow": Image.__version__}}
    (out / "material_wetness_generation.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))

if __name__ == "__main__":
    main()
