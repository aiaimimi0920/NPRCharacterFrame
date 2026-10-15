"""Beaver-native bake of original 360-degree face shadow distance fields."""

from pathlib import Path
import bpy, json, hashlib, shutil, math
import numpy as np
from face import depth, nose, lip_detail_depth, STYLE
from distance_field import signed_distance

ROOT = Path(beaver_input("project.godot")).parent
OUT = "assets/aster/sdf_664/"
N = 256
PAD = 2
TILE = N + 2 * PAD
YAW = 24
ELEV = 7
SPREAD = 48.0
# Godot UV2 top-origin: matches the existing authored UV2 contract.
u = (np.arange(N) + 0.5) / N
v = (np.arange(N) + 0.5) / N
normals = np.zeros((N, N, 3))
e = 0.0002


def art_depth(x, z):
    return (
        depth(x, z)
        - nose(x, z) * (1 - STYLE["nose_sdf_scale"])
        - lip_detail_depth(x, z) * (1 - STYLE["lip_sdf_scale"])
    )


# A directional face SDF needs a continuous art-directed shading surface.
# The 663 differentiated eyelid/socket/lip relief and produced isolated islands
# and bands; those geometric micro-normals are deliberately excluded here.
from face import width, H, Y0

xx, yy = np.meshgrid((u - 0.5) * 0.235, 1.5 + 0.31 * (1 - v))
widths = np.array([max(0.02, width(y)) for y in yy[:, 0]])[:, None]
side = np.clip(xx / widths, -0.985, 0.985)
# Continuous convex cheek/forehead proxy, with asymmetric upper/lower tilt.
height = (yy - (Y0 + H * 0.52)) / H
nx = side * 0.83
ny = np.tanh(height * 2.4) * 0.62
nz = np.sqrt(np.maximum(0.08, 1 - np.minimum(0.92, nx * nx + ny * ny)))
normals = np.stack([nx, ny, nz], axis=-1)
normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
atlas = np.zeros((TILE * ELEV, TILE * YAW, 4), dtype=np.float32)
atlas[:, :, 3] = 1
fractions = []
for ei in range(ELEV):
    pitch = -math.pi / 2 + ei * math.pi / (ELEV - 1)
    for yi in range(YAW):
        yaw = yi * 2 * math.pi / YAW
        light = np.array(
            [
                math.sin(yaw) * math.cos(pitch),
                math.sin(pitch),
                math.cos(yaw) * math.cos(pitch),
            ]
        )
        if ei in (0, ELEV - 1):
            light = np.array([0.0, -1.0 if ei == 0 else 1.0, 0.0])
        lit = (normals @ light) > 1e-8
        sdf = signed_distance(lit, SPREAD)
        encoded = 0.5 + sdf / (2 * SPREAD)
        tile = np.pad(encoded, PAD, mode="edge")
        atlas[ei * TILE : (ei + 1) * TILE, yi * TILE : (yi + 1) * TILE, :3] = tile[
            :, :, None
        ]
        fractions.append(
            {
                "yaw": yi * 15,
                "elevation": -90 + ei * 30,
                "lit_fraction": float(lit.mean()),
            }
        )
im = bpy.data.images.new(
    "Aster original 360 SDF", width=TILE * YAW, height=TILE * ELEV, alpha=True
)
im.colorspace_settings.name = "Non-Color"
im.pixels.foreach_set(atlas[::-1].ravel())
im.file_format = "PNG"
im.filepath_raw = beaver_output(OUT + "face_sdf360.png")
im.save()
definition = (ROOT / "assets/aster/head_recovery_662/aster_definition.tres").read_text()
from definition_output import bind_directional_atlas

definition = bind_directional_atlas(definition, OUT + "face_sdf360.png")
Path(beaver_output("assets/aster/head_recovery_664/aster_definition.tres")).write_text(
    definition
)
report = {
    "version": 664,
    "geometry_source": 662,
    "geometry_sha256": hashlib.sha256(
        (ROOT / "assets/aster/head_recovery_662/aster_head.glb").read_bytes()
    ).hexdigest(),
    "method": "Original continuous convex shading-proxy masks; excludes eye/socket/lip micro-normal islands, exact 2D Euclidean signed distance transform per directional keyframe; shader interpolates distances before thresholding. No third-party atlas data.",
    "yaw_count": YAW,
    "elevation_count": ELEV,
    "resolution": N,
    "tile_size": TILE,
    "padding": PAD,
    "spread_px": SPREAD,
    "samples": fractions,
    "limits": "Single directional key light, authored base face UV2; does not bake cast occlusion or reproduce the video proprietary algorithm. Expressions retain base UV field.",
}
Path(beaver_output(OUT + "bake_report.json")).write_text(json.dumps(report, indent=2))
print(
    "SDF360_BAKE_READY",
    json.dumps({"frames": YAW * ELEV, "size": [TILE * YAW, TILE * ELEV]}),
)
