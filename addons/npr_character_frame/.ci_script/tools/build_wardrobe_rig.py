"""Blender rest rig, weighted character, actions and face keys with index-safe export.

Usage: blender --background --python-exit-code 1 --python build_wardrobe_rig.py --
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ADDON = Path(__file__).resolve().parents[2]
RECIPE = ADDON / 'samples/silver_wolf/import_sources/performance_bake_inputs.json'
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_wardrobe_lid_surface import build as build_lids, author_blender
from verify_wardrobe_rig import verify_saved

SCRIPTS = ('build_wardrobe_rig.py', 'build_wardrobe_lid_surface.py',
           'wardrobe_blink_domain.py', 'verify_wardrobe_rig.py')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def host_root():
    for parent in ADDON.parents:
        if (parent / 'project.godot').is_file():
            return parent
    raise ValueError('No project.godot found; specify --output')


def load_inputs(recipe_path):
    recipe = json.loads(recipe_path.read_text(encoding='utf-8'))
    if recipe.get('schema') != 1 or set(recipe.get('files', {})) != {'probe', 'layout'}:
        raise ValueError('Expected schema 1 with probe/layout inputs')
    paths = {}
    for role, row in recipe['files'].items():
        relative = Path(row['path'])
        if relative.is_absolute():
            raise ValueError('Recipe paths must be relative')
        path = (recipe_path.parent / relative).resolve()
        if not path.is_relative_to(ADDON) or sha(path) != row['sha256']:
            raise ValueError('Input identity or location mismatch: ' + role)
        paths[role] = path
    return paths


def validate_inputs(probe, layout):
    meshes = probe.get('meshes')
    if not isinstance(meshes, list) or len(meshes) != 3:
        raise ValueError('Probe must provide Body/Face/Hair')
    # Retain the existing sample probe labels; filenames and recipes are English.
    if [source.get('name') for source in meshes] != ['模型', '脸部模型', '头发模型']:
        raise ValueError('Canonical probe mesh order changed')
    for source in meshes:
        points, uv, indices = source['positions'], source['uv'], source['indices']
        if (not points or any(len(p) != 3 or not all(type(v) in (int, float) and math.isfinite(v) for v in p) for p in points)
                or len(uv) != len(points) or any(len(row) != 2 or not all(type(v) in (int, float) and math.isfinite(v) for v in row) for row in uv)):
            raise ValueError('Probe must contain finite positions and matching UVs')
        if (not indices or len(indices) % 3 or any(type(i) is not int or not 0 <= i < len(points) for i in indices)):
            raise ValueError('Probe requires valid integer triangle indices')
    expected = ['root', 'hips', 'spine', 'chest', 'neck', 'head', 'arm.L', 'forearm.L', 'arm.R', 'forearm.R',
                'thigh.L', 'shin.L', 'thigh.R', 'shin.R', 'secondary.L', 'secondary.R']
    rows = layout.get('bones', [])
    if layout.get('schema') != 1 or [row['name'] for row in rows] != expected:
        raise ValueError('Expected canonical schema 1 bone layout')
    seen = set()
    for row in rows:
        if row['parent'] and row['parent'] not in seen:
            raise ValueError('Bone parents must precede their children')
        for key in ('head', 'tail'):
            if len(row[key]) != 3 or not all(type(v) in (int, float) and math.isfinite(v) for v in row[key]):
                raise ValueError('Bone layout requires finite endpoints')
        if sum((a-b)**2 for a, b in zip(row['head'], row['tail'])) <= 1e-12:
            raise ValueError('Bone layout contains zero-length segment')
        seen.add(row['name'])


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--recipe', type=Path, default=RECIPE)
parser.add_argument('--output', type=Path)
parser.add_argument('--verify-only', action='store_true')
parser.add_argument('--report', type=Path)
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
inputs = load_inputs(args.recipe.resolve())
OUT = args.output.resolve() if args.output else host_root() / '.temp/performance_bake'
if OUT.is_relative_to(ADDON):
    raise ValueError('Output must be outside the delivered addon')
REPORT = args.report.resolve() if args.report else OUT / 'verification.json'
if REPORT.is_relative_to(ADDON):
    raise ValueError('Report must be outside the delivered addon')
probe = json.loads(inputs['probe'].read_text(encoding='utf-8'))
layout = json.loads(inputs['layout'].read_text(encoding='utf-8'))
validate_inputs(probe, layout)
lid_data = build_lids(probe)
if args.verify_only:
    verify_saved(OUT, REPORT, probe, layout, lid_data, args.recipe.resolve(), inputs, SCRIPTS)
    raise SystemExit(0)
blink_shapes = lid_data["shapes"]
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def xyz(p):
    return Vector((p[0], -p[2], p[1]))


def smooth(a, b, x):
    t = max(0., min(1., (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# One rest-layout source for authoring and runtime diagnostics. Values retain
# the original posed-source landmarks, without assuming a T-pose.
bones = [(b["name"], b["parent"], tuple(b["head"]), tuple(b["tail"])) for b in layout["bones"]]
names = [b[0] for b in bones]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
arm = bpy.data.armatures.new("WardrobeRig")
rig = bpy.data.objects.new("WardrobeRig", arm)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for name, parent, start, end in bones:
    bone = arm.edit_bones.new(name)
    bone.head, bone.tail = xyz(start), xyz(end)
    if parent:
        bone.parent = arm.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")


def weights(p, role):
    x, y, z = p
    if role:
        return [(5, 1.)]
    if y > 2.34:
        return [(5, 1.)]
    candidates = range(1, 14)
    ranking = []
    for i in candidates:
        a, b = Vector(bones[i][2]), Vector(bones[i][3])
        q = Vector(p)
        t = max(0, min(1, (q - a).dot(b - a) / (b - a).length_squared))
        distance = (q - a.lerp(b, t)).length
        ranking.append((distance, i))
    ranking.sort()
    selected = [(i, math.exp(-((distance / .12) ** 2))) for distance, i in ranking[:3]]
    # Compact soft tissue domains exclude collar, arms and abdomen.
    secondary = math.exp(-(((y - 2.10) / .115) ** 2)) * smooth(.08, .19, z)
    secondary *= 1 - smooth(.19, .27, abs(x + .04))
    # Slightly stronger bounded secondary motion makes the authored soft-tissue
    # cue readable in the developer showcase without expanding its domain.
    secondary_strength = .52
    selected = [(i, w * (1 - secondary_strength * secondary)) for i, w in selected]
    total = sum(w for _, w in selected) or 1
    selected = [(i, w / total * (1 - secondary_strength * secondary)) for i, w in selected]
    selected.append((14 if x < -.04 else 15, secondary_strength * secondary))
    return selected


def face_delta(p, name, uv):
    x, y, z = p
    dx = dy = dz = 0.
    if name.startswith("blink"):
        raise ValueError("Blink shapes require sliding-lid topology constraints")
    else:
        mouth = (1 - smooth(.024, .065, abs(x + .105)))
        mouth *= (1 - smooth(.014, .060, abs(y - 2.430))) * smooth(.05, .09, z)
        if name in ("aa", "ee", "ih", "oh", "ou"):
            mouth = (1 - smooth(.003, .025, abs(x + .105)))
            mouth *= (1 - smooth(.009, .034, abs(y - 2.430))) * smooth(.05, .09, z)
            opening, width = {"aa": (.016, .002), "ee": (.006, .006),
                              "ih": (.008, .004), "oh": (.014, -.006),
                              "ou": (.008, -.008)}[name]
            lower = 1 - smooth(2.429 + .10 * (x + .105), 2.431 + .10 * (x + .105), y)
            if .42 < uv[0] < .58 and .29 < uv[1] < .46:
                lower = 1 - smooth(.3685, .3720, uv[1])
                mouth = max(0, 1 - ((uv[0] - .5) / .052) ** 2) ** .5
                mouth *= 1 - smooth(.007, .068, abs(uv[1] - .3705))
            dy = opening * (.18 - 1.18 * lower) * mouth
            dx = (x + .105) / .04 * width * mouth
            dz = .005 * mouth if name in ("oh", "ou") else 0
        elif name in ("happy", "sad"):
            dy = .012 * smooth(.009, .035, abs(x + .105)) * mouth
            if name == "sad":
                dy *= -1
        elif name == "angry":
            brow = (1 - smooth(.008, .027, abs(y - 2.578))) * smooth(.05, .08, z)
            dy = -.014 * brow * (1 - smooth(.015, .07, abs(x + .105)))
    return Vector((dx, -dz, dy))


data = {"schema": 1, "bones": names, "weights": [], "shapes": {}, "actions": {}}
for role, source in enumerate(probe["meshes"]):
    mesh = bpy.data.meshes.new(["Body", "Face", "Hair"][role])
    indices = source["indices"]
    mesh.from_pydata([xyz(p) for p in source["positions"]], [],
                     [(indices[i], indices[i+2], indices[i+1]) for i in range(0, len(indices), 3)])
    mesh.update()
    ob = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.collection.objects.link(ob)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        u, v = source["uv"][loop.vertex_index]
        uv_layer.data[loop.index].uv = (u, 1-v)
    for name in names:
        ob.vertex_groups.new(name=name)
    rows = []
    for i, p in enumerate(source["positions"]):
        row = weights(p, role)
        for bone, weight in row:
            ob.vertex_groups[bone].add([i], weight, "REPLACE")
        rows.append([[bone, round(weight, 7)] for bone, weight in row])
    data["weights"].append(rows)
    modifier = ob.modifiers.new("Wardrobe armature", "ARMATURE")
    modifier.object = rig
    if role == 1:
        ob.shape_key_add(name="Basis", from_mix=False)
        for name in ["blink.L", "blink.R", "blink_mid.L", "blink_mid.R", "happy", "sad", "angry", "aa", "ee", "ih", "oh", "ou"]:
            key = ob.shape_key_add(name=name, from_mix=False)
            key.value = 0.
            changes = []
            authored_blink = {r[0]: r for r in blink_shapes.get(name, [])}
            for i, p in enumerate(source["positions"]):
                if name.startswith("blink"):
                    row = authored_blink.get(i, [i, 0., 0., 0.])
                    delta = Vector((row[1], -row[3], row[2]))
                else:
                    delta = face_delta(p, name, source["uv"][i])
                key.data[i].co += delta
                if delta.length > 1e-8:
                    changes.append([i, round(delta.x, 7), round(delta.z, 7), round(-delta.y, 7)])
            data["shapes"][name] = changes

scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start = 0
scene.frame_end = 120
rig.animation_data_create()
for action_name in ["idle", "greeting", "look_around", "presentation"]:
    action = bpy.data.actions.new(action_name)
    rig.animation_data.action = action
    action.use_fake_user = True
    for frame in range(0, 121, 5):
        t = frame / 30
        for bone in rig.pose.bones:
            bone.rotation_mode = "XYZ"
            bone.rotation_euler = (0, 0, 0)
            bone.location = (0, 0, 0)
        rig.pose.bones["chest"].rotation_euler.x = math.sin(t * math.pi / 2) * .015
        rig.pose.bones["head"].rotation_euler.y = math.sin(t * math.pi / 2) * .025
        envelope = math.sin(math.pi * t / 4) ** 2
        if action_name == "greeting":
            rig.pose.bones["arm.R"].rotation_euler.y = -.28 * envelope
            rig.pose.bones["arm.R"].rotation_euler.x = -.65 * envelope
            rig.pose.bones["forearm.R"].rotation_euler.x = -1.15 * envelope
            rig.pose.bones["forearm.R"].rotation_euler.z = .12 * math.sin(t * 7) * envelope
        elif action_name == "look_around":
            rig.pose.bones["head"].rotation_euler.y = .23 * math.sin(t * math.pi / 2)
        elif action_name == "presentation":
            rig.pose.bones["chest"].rotation_euler.y = .12 * math.sin(t * math.pi / 2)
            rig.pose.bones["arm.L"].rotation_euler.y = .24 * envelope
            rig.pose.bones["forearm.L"].rotation_euler.x = -.35 * envelope
        for side in ("L", "R"):
            rig.pose.bones["secondary." + side].rotation_euler.x = .025 * math.sin(t * math.pi * 3) * envelope
        for bone in rig.pose.bones:
            bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
    baked = []
    for frame in range(121):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        pose = []
        for name in names:
            deform = C.inverted() @ rig.pose.bones[name].matrix @ arm.bones[name].matrix_local.inverted() @ C
            pose.append([round(deform[r][c], 7) for r in range(3) for c in range(4)])
        baked.append(pose)
    data["actions"][action_name] = {"fps": 30, "frames": baked}
scene.frame_set(0)
OUT.mkdir(parents=True, exist_ok=True)
author_blender(lid_data)
# Complete the same sliding-lid overlay as the former separate authoring step.
data['shapes'].update(lid_data['shapes'])
(OUT / "lid_surface_v2.json").write_text(json.dumps(lid_data, separators=(",", ":")), encoding="utf-8")
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "character_rig.blend"))
(OUT / "performance.json").write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
generation = {
    'schema': 1, 'generator': Path(__file__).name,
    'scripts': {name: sha(Path(__file__).with_name(name)) for name in SCRIPTS},
    'input_recipe': args.recipe.name, 'input_recipe_sha256': sha(args.recipe),
    'inputs': {role: {'name': path.name, 'sha256': sha(path)} for role, path in inputs.items()},
    'blender_version': bpy.app.version_string, 'blender_commit': bpy.app.build_hash.decode(),
    'numpy_version': __import__('numpy').__version__,
    'outputs': {name: sha(OUT/name) for name in ('character_rig.blend', 'performance.json', 'lid_surface_v2.json')},
    'scope': 'Fixed sample rest layout, skin weights, four actions and sliding lid/expression keys',
}
(OUT/'performance_generation.json').write_text(json.dumps(generation, indent=2)+'\n', encoding='utf-8')
print("WARDROBE_RIG", len(names), "bones", list(data["actions"]),
      {name: len(rows) for name, rows in data["shapes"].items()})
verify_saved(OUT, REPORT, probe, layout, lid_data, args.recipe.resolve(), inputs, SCRIPTS)
