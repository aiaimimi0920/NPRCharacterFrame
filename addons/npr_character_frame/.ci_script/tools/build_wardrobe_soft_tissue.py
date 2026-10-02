"""Bake an index-preserving stocking-contact corrective in Blender.

blender --background --python-exit-code 1 --python build_wardrobe_soft_tissue.py -- [--output scratch]

The saved Shape Key is the source of the runtime deltas. This is a bounded,
quasi-static garment-contact bake, not a general soft-body/FEM solver. A rigid
inner capsule limits compression; a smooth adjacent bulge represents displaced
tissue. All original vertices, UVs, weights and face keys remain recoverable.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ADDON = Path(__file__).resolve().parents[2]
RECIPE = ADDON / "samples/silver_wolf/import_sources/soft_tissue_bake_inputs.json"
NAME = "soft_tissue_pressure"


def sha256(path: Path) -> str:
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()


def host_root() -> Path:
    for parent in ADDON.parents:
        if (parent / "project.godot").is_file():
            return parent
    raise ValueError("No project.godot found; specify --output")


def verify_inputs(recipe_path: Path) -> tuple[dict, dict[str, Path]]:
    recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
    if recipe.get("schema") != 1 or set(recipe.get("files", {})) != {"rig", "probe", "garment", "body"}:
        raise ValueError("Expected schema 1 with rig/probe/garment/body inputs")
    paths = {}
    for role, row in recipe["files"].items():
        relative = Path(row["path"])
        if relative.is_absolute():
            raise ValueError("Recipe paths must be relative")
        path = (recipe_path.parent / relative).resolve()
        if not path.is_relative_to(ADDON) or sha256(path) != row["sha256"]:
            raise ValueError("Input identity or location mismatch: " + role)
        paths[role] = path
    return recipe, paths


def smooth(a: float, b: float, value: float) -> float:
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def godot(point: Vector) -> Vector:
    return Vector((point.x, point.z, -point.y))


def blender(point: Vector) -> Vector:
    return Vector((point.x, -point.z, point.y))


def bridge_rows(exported: dict, vertex_count: int) -> dict[int, Vector]:
    if exported.get("schema") != 1 or exported.get("name") != NAME or exported.get("source_vertices") != vertex_count:
        raise ValueError("Saved bridge schema, shape name or vertex count changed")
    rows = exported.get("deltas")
    if not isinstance(rows, list):
        raise ValueError("Saved bridge deltas must be an array")
    result = {}
    for row in rows:
        if (not isinstance(row, list) or len(row) != 4 or type(row[0]) is not int
                or not 0 <= row[0] < vertex_count or row[0] in result
                or any(type(value) not in (int, float) or not math.isfinite(value) for value in row[1:])):
            raise ValueError("Saved bridge has invalid, duplicate or nonfinite deltas")
        result[row[0]] = Vector(row[1:])
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", type=Path, default=RECIPE)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    recipe, inputs = verify_inputs(args.recipe.resolve())
    input_blend = inputs["rig"]
    probe_path = inputs["probe"]
    probe = json.loads(probe_path.read_text(encoding="utf-8"))["meshes"][0]
    out = args.output.resolve() if args.output else host_root() / ".temp/soft_tissue_bake"
    if out.is_relative_to(ADDON):
        raise ValueError("Output must be outside the delivered addon")
    if args.report and args.report.resolve().is_relative_to(ADDON):
        raise ValueError("Report must be outside the delivered addon")
    result_path = out / "soft_tissue_v1.json"
    blend_path = out / "soft_tissue_v1.blend"
    if args.verify_only:
        bpy.ops.wm.open_mainfile(filepath=str(blend_path))
        body = bpy.data.objects["Body"]
        exported = json.loads(result_path.read_text(encoding="utf-8"))
        key = body.data.shape_keys.key_blocks[NAME]
        basis = body.data.shape_keys.key_blocks["Basis"]
        if (len(body.data.vertices) != len(probe["positions"])
                or len(key.data) != len(body.data.vertices) or len(basis.data) != len(body.data.vertices)):
            raise ValueError("Saved body or Shape Key vertex count changed")
        rows = bridge_rows(exported, len(body.data.vertices))
        error = max((godot(key.data[i].co - basis.data[i].co) - rows.get(i, Vector())).length
                    for i in range(len(body.data.vertices)))
        if not math.isfinite(error) or error > 2e-7:
            raise ValueError(f"Saved Blender Shape Key and bridge differ: {error}")
        if "SoftTissueCore.L" not in bpy.data.objects:
            raise ValueError("Missing authored collision source")
        rest_error = max((godot(v.co) - Vector(p)).length for v, p in zip(body.data.vertices, probe["positions"]))
        expected_faces = [(probe["indices"][i], probe["indices"][i + 2], probe["indices"][i + 1])
                          for i in range(0, len(probe["indices"]), 3)]
        actual_faces = [tuple(poly.vertices) for poly in body.data.polygons]
        uv = body.data.uv_layers["UVMap"]
        uv_error = max((uv.data[loop.index].uv - Vector((probe["uv"][loop.vertex_index][0],
                        1.0 - probe["uv"][loop.vertex_index][1]))).length for loop in body.data.loops)
        sums = [sum(group.weight for group in vertex.groups if group.group < 16) for vertex in body.data.vertices]
        if (not math.isfinite(rest_error) or not math.isfinite(uv_error)
                or rest_error > 2e-6 or actual_faces != expected_faces or uv_error > 2e-6):
            raise ValueError("Saved topology, rest positions or UVs changed")
        if any(not math.isfinite(total) or abs(total - 1.0) > 2e-6 for total in sums):
            raise ValueError("Saved skin weights are not normalized")
        receipt = {"pass": True, "blender_version": bpy.app.version_string, "vertices": len(body.data.vertices),
                   "triangles": len(actual_faces), "shape_delta_max_error": error, "rest_max_error": rest_error,
                   "uv_max_error": uv_error, "weight_sum_range": [min(sums), max(sums)],
                   "bones": len(bpy.data.armatures["WardrobeRig"].bones),
                   "actions": sorted(action.name for action in bpy.data.actions),
                   "source_sha256": sha256(blend_path), "bridge_sha256": sha256(result_path)}
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        print(f"SOFT_TISSUE_SOURCE_OK vertices={len(body.data.vertices)} max_delta_error={error:.9g}")
        return

    # Always read the identity-checked source, never an in-place candidate.
    bpy.ops.wm.open_mainfile(filepath=str(input_blend))
    body = bpy.data.objects["Body"]
    mesh = body.data
    if len(mesh.vertices) != len(probe["positions"]):
        raise ValueError("Blender body topology does not match the canonical probe")
    drift = max((godot(v.co) - Vector(p)).length for v, p in zip(mesh.vertices, probe["positions"]))
    if not math.isfinite(drift) or drift > 2e-6:
        raise ValueError(f"Blender rest geometry drift: {drift}")

    # Select the exposed left thigh using the existing authored skin alpha and
    # a spatial domain. UV alone is ambiguous because this model reuses islands.
    mask = bpy.data.images.load(str(inputs["garment"]), check_existing=True)
    if tuple(mask.size) != (1024, 512) or mask.channels != 4:
        raise ValueError("Sample garment must be RGBA 1024x512")
    mask.pack()
    width, height = mask.size
    pixels = list(mask.pixels)
    selected: set[int] = set()
    for i, (point, uv) in enumerate(zip(probe["positions"], probe["uv"])):
        x, y, z = point
        px = max(0, min(width - 1, int(uv[0] * width)))
        py = max(0, min(height - 1, int((1.0 - uv[1]) * height)))
        if -0.30 < x < 0.0 and 1.12 < y < 1.43 and pixels[(py * width + px) * 4 + 3] > 0.5:
            selected.add(i)
    # Weld only the selection decision, never the actual mesh: coincident seam
    # vertices must receive the same corrective without changing vertex order.
    positions = [Vector(point) for point in probe["positions"]]
    def position_key(point: Vector) -> tuple:
        return tuple(round(float(value), 6) for value in point)
    selected_positions = {position_key(positions[i]) for i in selected}
    selected = {i for i, point in enumerate(positions) if position_key(point) in selected_positions}
    band = [positions[i] for i in selected if 1.25 < positions[i].y < 1.34]
    if len(band) < 12:
        raise ValueError("No sufficiently sampled stocking-contact domain")
    center = Vector(((min(p.x for p in band) + max(p.x for p in band)) * 0.5,
                     1.295, (min(p.z for p in band) + max(p.z for p in band)) * 0.5))
    radii = [(Vector((positions[i].x, center.y, positions[i].z)) - center).length for i in selected]
    core_radius = min(radii) * 0.65
    if core_radius < 0.015:
        raise ValueError("Invalid rigid tissue core")
    if not mesh.shape_keys:
        body.shape_key_add(name="Basis")
    key = body.shape_key_add(name=NAME)
    key.slider_min, key.slider_max = 0.0, 1.0
    group = body.vertex_groups.new(name="SoftPressureDomain")
    rows, domains = [], []
    min_clearance = math.inf
    for i in sorted(selected):
        point = positions[i]
        radial = Vector((point.x - center.x, 0.0, point.z - center.z))
        radius = radial.length
        offset = abs(point.y - center.y)
        support = 1.0 - smooth(0.095, 0.125, offset)
        # Smooth C1 contact and redistribution bands avoid cracks at the pinning
        # boundary. The inner capsule is a hard collision constraint for every
        # baked vertex, not a post-hoc clamp of a rendered shader color.
        contact = 1.0 - smooth(0.012, 0.045, offset)
        bulge = smooth(0.018, 0.049, offset) * (1.0 - smooth(0.055, 0.095, offset))
        displacement = (-0.009 * contact + 0.0035 * bulge) * support
        target_radius = max(core_radius + 0.001, radius + displacement)
        delta = radial.normalized() * (target_radius - radius)
        if delta.length < 1e-7:
            continue
        key.data[i].co += blender(delta)
        group.add([i], support, "REPLACE")
        # Export from the actual saved key, not from an independent approximation.
        actual = godot(key.data[i].co - mesh.shape_keys.key_blocks["Basis"].data[i].co)
        rows.append([i, *[round(float(value), 8) for value in actual]])
        domains.append([i, round(support, 7), round(contact, 7)])
        min_clearance = min(min_clearance, target_radius - core_radius)
    if len(rows) < 24 or min_clearance < 0.00099:
        raise ValueError("Insufficient corrective geometry or penetrating tissue core")

    # The collision source and pressing band are visible in Blender's authoring
    # view, hidden in renders, and excluded from the runtime bridge entirely.
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=core_radius, depth=0.27,
                                       location=blender(center))
    collider = bpy.context.object
    collider.name = "SoftTissueCore.L"
    collider.display_type = "WIRE"
    collider.hide_render = True
    collider["runtime_bone"] = "thigh.L"
    collider["collision_margin_metres"] = 0.001
    collider.modifiers.new("Authored rigid tissue collision", "COLLISION")
    bpy.ops.mesh.primitive_torus_add(major_segments=48, minor_segments=8,
                                   location=blender(center), major_radius=max(radii) - 0.009,
                                   minor_radius=0.007)
    cuff = bpy.context.object
    cuff.name = "SoftPressureContact.L"
    cuff.display_type = "WIRE"
    cuff.hide_render = True
    cuff["maximum_compression_metres"] = 0.009
    key.value = 0.0
    bpy.context.scene.frame_set(0)
    out.mkdir(parents=True, exist_ok=True)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    payload = {
        "schema": 1,
        "name": NAME,
        "source_vertices": len(mesh.vertices),
        "space": "Godot actor-local Y-up metres; indices of canonical Body surface 0",
        "default": 0.0,
        "range": [0.0, 1.0],
        "normal_tangent": "Preserve valid canonical directions for nonnegative relative blending",
        "quality": {"full": "authored corrective", "balanced": "same topology/corrective", "performance": "neutral"},
        "collision": {"name": collider.name, "bone": 10, "center": list(center),
                      "axis": [0.0, 1.0, 0.0], "radius": core_radius, "half_height": 0.135,
                      "margin": 0.001, "minimum_baked_clearance": min_clearance},
        "domain": {"role": "Body", "side": "left stocking contact", "y_range": [1.17, 1.42],
                   "max_displacement": 0.009001, "weights": domains},
        "source": {"blend": blend_path.name,
                   "canonical_body_sha256": sha256(inputs["body"]),
                   "probe_sha256": sha256(probe_path), "input_blend_sha256": sha256(input_blend)},
        "deltas": rows,
    }
    result_path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
    generation = {
        "schema": 1,
        "author": "Project-authored by Codex", "generator": Path(__file__).name,
        "generator_sha256": sha256(Path(__file__)), "blender_version": bpy.app.version_string,
        "blender_commit": bpy.app.build_hash.decode(),
        "input_recipe": args.recipe.name, "input_recipe_sha256": sha256(args.recipe),
        "inputs": {role: {"name": path.name, "sha256": sha256(path)} for role, path in inputs.items()},
        "historical_input_blend_sha256": recipe.get("historical_input_blend_sha256"),
        "source_blend": payload["source"]["blend"], "source_blend_sha256": sha256(blend_path),
        "bridge": result_path.name, "bridge_sha256": sha256(result_path),
        "changed_vertices": len(rows), "topology_preserved": True, "rest_probe_max_error": drift,
        "license": "New corrective/generator authored for this project; original model rights unchanged",
        "rebuild": "Use the same relative input recipe with --output <scratch>; compare all corrective fields",
    }
    (out / "soft_tissue_generation.json").write_text(json.dumps(generation, indent=2) + "\n", encoding="utf-8")
    print(f"SOFT_TISSUE_BAKE_OK changed_vertices={len(rows)} collision_clearance={min_clearance:.8f}")


if __name__ == "__main__":
    main()
