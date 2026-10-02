"""Author dynamic chains on canonical hair and the hanging fabric strap.

blender --background --python-exit-code 1 --python build_wardrobe_hair_dynamic.py --
The bridge preserves canonical vertex indices; runtime renders the same NPR
surfaces and auxiliary passes. The blend/GLB retain the inspectable skin.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ADDON = Path(__file__).resolve().parents[2]
RECIPE = ADDON / 'samples/silver_wolf/import_sources/hair_dynamic_bake_inputs.json'
SOURCE = Path('hair_dynamic_v1.blend')
GLB = Path('hair_dynamic_v1.glb')
MANIFEST = Path('hair_dynamic_v1.json')


def host_root():
    for parent in ADDON.parents:
        if (parent / 'project.godot').is_file():
            return parent
    raise ValueError('No project.godot found; specify --output')


def verify_inputs(recipe_path):
    recipe = json.loads(recipe_path.read_text(encoding='utf-8'))
    if recipe.get('schema') != 1 or set(recipe.get('files', {})) != {'rig', 'performance', 'profile'}:
        raise ValueError('Expected schema 1 with rig/performance/profile inputs')
    origin = recipe.get('head_bvh_origin')
    if (not isinstance(origin, list) or len(origin) != 3
            or not all(type(value) in (int, float) and math.isfinite(value) for value in origin)):
        raise ValueError('Head BVH origin must be a finite actor-space vector')
    paths = {}
    for role, row in recipe['files'].items():
        relative = Path(row['path'])
        if relative.is_absolute():
            raise ValueError('Recipe paths must be relative')
        path = (recipe_path.parent / relative).resolve()
        if not path.is_relative_to(ADDON) or sha256(path) != row['sha256']:
            raise ValueError('Input identity or location mismatch: ' + role)
        paths[role] = path
    return recipe, paths


def curve_parameter(point, curve):
    lengths = [(b-a).length for a, b in zip(curve, curve[1:])]
    total, start, best = sum(lengths), 0.0, (float('inf'), 0.0)
    for a, b, length in zip(curve, curve[1:], lengths):
        if not math.isfinite(length) or length <= 0:
            raise ValueError('Curve segment must have positive finite length')
        t = max(0.0, min(1.0, (point-a).dot(b-a) / (length*length)))
        candidate = ((point-a-(b-a)*t).length_squared, (start+t*length)/total)
        best = min(best, candidate)
        start += length
    return best[1]


def resample_curve(curve):
    lengths = [(b-a).length for a, b in zip(curve, curve[1:])]
    result = []
    for node in range(4):
        remaining = sum(lengths)*node/3
        for a, b, length in zip(curve, curve[1:], lengths):
            if remaining <= length + 1e-8:
                result.append([round(v, 7) for v in a.lerp(b, min(1.0, remaining/length))])
                break
            remaining -= length
    if len(result) != 4:
        raise ValueError('Curve must resample to four nodes')
    return result


def curve_weight(u, knots):
    for (a, wa), (b, wb) in zip(knots, knots[1:]):
        if u <= b:
            t = max(0.0, min(1.0, (u-a)/(b-a)))
            return wa + (wb-wa)*t*t*(3-2*t)
    return knots[-1][1]


def validate_profile(profile, mesh, points):
    if profile.get('schema') != 1:
        raise ValueError('Expected schema 1 motion profile')
    shells = {min(group): group for group in components(mesh, weld=False)}
    for zone in profile['static_zones']:
        positions = {tuple(round(v, 5) for v in points[i]) for i in shells[zone['shell_seed']]}
        expected = {i for i, p in enumerate(points) if tuple(round(v, 5) for v in p) in positions}
        if expected != set(zone['vertices']):
            raise ValueError('Static zone no longer matches canonical shell and seams')
    for motion in profile['chains'].values():
        curve = [Vector(p) for p in motion['curve']]
        if (len(curve) < 2 or any(len(p) != 3 or not all(math.isfinite(v) for v in p) for p in motion['curve'])
                or not all((b-a).length > 1e-6 for a, b in zip(curve, curve[1:]))):
            raise ValueError('Motion curve must contain distinct finite points')
        knots = motion['weight_curve']
        if (len(knots) < 2 or any(len(row) != 2 or not all(math.isfinite(v) for v in row) for row in knots)
                or knots[0] != [0, 0] or knots[-1] != [1, 1]
                or not all(a[0] < b[0] and 0 <= a[1] <= b[1] <= 1 for a, b in zip(knots, knots[1:]))):
            raise ValueError('Invalid motion weight curve')
        pins = motion['pinned_nodes']
        if not (0 < len(pins) < 4 and pins == list(range(len(pins)))):
            raise ValueError('Motion pins must be a consecutive root prefix')
        for key in ['wind_gain', 'stiffness', 'damping', 'max_offset']:
            if len(motion[key]) != 4 or not all(math.isfinite(v) and v >= 0 for v in motion[key]):
                raise ValueError('Motion arrays require four finite nonnegative values: ' + key)


def resolve_zones(profile, meshes, points):
    """Authored complete shells plus UV seams, with deterministic shared-root ownership."""
    result, pinned, claimed = {}, {}, {0: set(), 2: set()}
    claimed[2].update(i for zone in profile['static_zones'] for i in zone['vertices'])
    for zone in profile['dynamic_zones']:
        role = zone['role']
        shells = {min(group): group for group in components(meshes[role].data, weld=zone['weld'])}
        selected = {i for seed in zone['shell_seeds'] for i in shells[seed]}
        positions = {tuple(round(v, 5) for v in points[role][i]) for i in selected}
        selected = {i for i, p in enumerate(points[role]) if tuple(round(v, 5) for v in p) in positions}
        selected -= claimed[role]
        if not selected or zone['name'] in result:
            raise ValueError('Empty or duplicate dynamic zone')
        claimed[role].update(selected)
        result[zone['name']] = selected
        fixed = {i for seed in zone.get('pinned_shell_seeds', []) for i in shells[seed]}
        positions = {tuple(round(v, 5) for v in points[role][i]) for i in fixed}
        pinned[zone['name']] = {i for i in selected if tuple(round(v, 5) for v in points[role][i]) in positions}
    return result, pinned


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def xyz(point):
    return Vector((point[0], -point[2], point[1]))


def godot(point):
    return Vector((point.x, point.z, -point.y))


def components(mesh, weld=True):
    parents = list(range(len(mesh.vertices)))

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    welded = {}
    for vertex in mesh.vertices if weld else []:
        key = tuple(round(v, 5) for v in vertex.co)
        if key in welded:
            parents[root(vertex.index)] = root(welded[key])
        welded[key] = vertex.index
    for edge in mesh.edges:
        parents[root(edge.vertices[1])] = root(edge.vertices[0])
    groups = {}
    for index in range(len(parents)):
        groups.setdefault(root(index), []).append(index)
    return list(groups.values())


def mesh_snapshot(obj):
    return {
        'points': [godot(obj.matrix_world @ vertex.co) for vertex in obj.data.vertices],
        'faces': [tuple(p.vertices) for p in obj.data.polygons],
        'uv': {layer.name: [tuple(loop.uv) for loop in layer.data] for layer in obj.data.uv_layers},
        'weights': [{obj.vertex_groups[group.group].name: group.weight for group in vertex.groups
                     if group.weight > 0} for vertex in obj.data.vertices],
    }


def verify_glb(path, bone_count):
    data = path.read_bytes()
    if len(data) < 20 or struct.unpack_from('<III', data) != (0x46546c67, 2, len(data)):
        raise ValueError('Invalid GLB header or length')
    size, kind = struct.unpack_from('<II', data, 12)
    if kind != 0x4e4f534a or size > len(data) - 20:
        raise ValueError('Invalid GLB JSON chunk')
    gltf = json.loads(data[20:20 + size])
    if any('uri' in row for key in ('buffers', 'images') for row in gltf.get(key, [])):
        raise ValueError('GLB must not depend on external buffers or images')
    if (len(gltf.get('skins', [])) != 1 or len(gltf['skins'][0]['joints']) != bone_count
            or {mesh['name'] for mesh in gltf.get('meshes', [])} != {'Body', 'Hair'}):
        raise ValueError('GLB palette or Body/Hair mesh inventory changed')
    for mesh in gltf['meshes']:
        for primitive in mesh['primitives']:
            if not {'POSITION', 'NORMAL', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0'} <= set(primitive['attributes']):
                raise ValueError('GLB is missing canonical geometry or skin attributes')
    return len(gltf['meshes'])


def verify_saved(output, inputs, recipe_path, report):
    generation = json.loads((output/'hair_dynamic_generation.json').read_text(encoding='utf-8'))
    if (generation['generator_sha256'] != sha256(Path(__file__))
            or generation['input_recipe_sha256'] != sha256(recipe_path)):
        raise ValueError('Generation script or recipe identity changed')
    for name in (SOURCE, GLB, MANIFEST):
        if generation['outputs'][name.name] != sha256(output/name):
            raise ValueError('Generated output identity changed: ' + name.name)
    bridge = json.loads((output/MANIFEST).read_text(encoding='utf-8'))
    recipe = json.loads(recipe_path.read_text(encoding='utf-8'))
    if bridge.get('head_surface', {}).get('bvh_origin') != recipe['head_bvh_origin']:
        raise ValueError('Saved head BVH origin differs from recipe')
    if (bridge.get('schema') != 3 or bridge.get('name') != 'hair_dynamic_v1'
            or bridge['canonical_source_sha256'] != sha256(inputs['rig'])
            or bridge['source_sha256'] != sha256(output/SOURCE) or bridge['glb_sha256'] != sha256(output/GLB)):
        raise ValueError('Saved bridge or source identity changed')
    performance = json.loads(inputs['performance'].read_text(encoding='utf-8'))
    names = performance['bones'] + bridge['bones']
    bpy.ops.wm.open_mainfile(filepath=str(inputs['rig']))
    canonical = {role: mesh_snapshot(bpy.data.objects[name]) for role, name in ((0, 'Body'), (2, 'Hair'))}
    bpy.ops.wm.open_mainfile(filepath=str(output/SOURCE))
    rig = bpy.data.objects['DynamicBindPalette']
    if [bone.name for bone in rig.data.bones] != names:
        raise ValueError('Saved dynamic bone palette changed')
    rest_error = uv_error = weight_error = 0.0
    sums, vertices, triangles = [], {}, {}
    for role, name in ((0, 'Body'), (2, 'Hair')):
        obj = bpy.data.objects[name]
        original, saved = canonical[role], mesh_snapshot(obj)
        if (len(saved['points']) != len(original['points'])
                or bridge['source_vertices'][str(role)] != len(original['points'])
                or saved['faces'] != original['faces'] or saved['uv'] != original['uv']):
            raise ValueError('Saved canonical topology, vertex count or UVs changed: ' + name)
        if obj.parent != rig or not any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers):
            raise ValueError('Saved Body/Hair is not bound to the dynamic palette')
        for actual, expected in zip(saved['points'], original['points']):
            error = (actual - expected).length
            if not math.isfinite(error) or error > 2e-6:
                raise ValueError('Saved rest positions changed: ' + name)
            rest_error = max(rest_error, error)
        overrides = {}
        for index, influences in bridge['weights'][str(role)]:
            if type(index) is not int or not 0 <= index < len(saved['points']) or index in overrides:
                raise ValueError('Saved bridge has invalid or duplicate weight indices')
            expected = {}
            for bone, weight in influences:
                if (type(bone) is not int or not 0 <= bone < len(names) or names[bone] in expected
                        or not math.isfinite(weight) or not 0 <= weight <= 1):
                    raise ValueError('Saved bridge has invalid skin influences')
                expected[names[bone]] = weight
            overrides[index] = {bone: weight for bone, weight in expected.items() if weight > 0}
        for index, actual in enumerate(saved['weights']):
            expected = overrides.get(index, original['weights'][index])
            for bone in set(expected) | set(actual):
                error = abs(expected.get(bone, 0) - actual.get(bone, 0))
                if not math.isfinite(error) or error > 2e-6:
                    raise ValueError('Saved skin weights and bridge differ: ' + name)
                weight_error = max(weight_error, error)
            total = sum(actual.values())
            if not math.isfinite(total) or abs(total - 1) > 2e-6:
                raise ValueError('Saved skin weights are not normalized: ' + name)
            sums.append(total)
        vertices[name] = len(saved['points'])
        triangles[name] = len(saved['faces'])
    if any('Collision.' + row['name'] not in bpy.data.objects for row in bridge['colliders']):
        raise ValueError('Missing authored collision objects')
    receipt = {
        'pass': True, 'blender_version': bpy.app.version_string,
        'vertices': vertices, 'triangles': triangles, 'bones': len(names), 'chains': len(bridge['chains']),
        'rest_max_error': rest_error, 'uv_max_error': uv_error, 'weight_max_error': weight_error,
        'weight_sum_range': [min(sums), max(sums)], 'glb_meshes': verify_glb(output/GLB, len(names)),
        'outputs': {path.name: sha256(output/path) for path in (SOURCE, GLB, MANIFEST)},
    }
    if report:
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print('HAIR_DYNAMIC_SOURCE_OK', vertices, 'max_weight_error=', weight_error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, default=RECIPE)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    recipe, inputs = verify_inputs(args.recipe.resolve())
    output = args.output.resolve() if args.output else host_root() / '.temp/hair_dynamic_bake'
    if output.is_relative_to(ADDON):
        raise ValueError('Output must be outside the delivered addon')
    if args.report and args.report.resolve().is_relative_to(ADDON):
        raise ValueError('Report must be outside the delivered addon')
    if args.verify_only:
        verify_saved(output, inputs, args.recipe.resolve(), args.report)
        return
    source = inputs['rig']
    profile = json.loads(inputs['profile'].read_text(encoding='utf-8'))
    if profile['canonical_source_sha256'] != recipe['historical_input_blend_sha256']:
        raise ValueError('Historical motion profile identity changed')
    static = {i for zone in profile['static_zones'] for i in zone['vertices']}
    bpy.ops.wm.open_mainfile(filepath=str(source))
    meshes = {0: bpy.data.objects['Body'], 2: bpy.data.objects['Hair']}
    points = {role: [godot(obj.matrix_world @ v.co) for v in obj.data.vertices]
              for role, obj in meshes.items()}
    validate_profile(profile, meshes[2].data, points[2])
    zones, pinned = resolve_zones(profile, meshes, points)
    face = bpy.data.objects['Face']
    face_points = [godot(face.matrix_world @ v.co) for v in face.data.vertices]
    face_tree = BVHTree.FromPolygons(face_points, [list(p.vertices) for p in face.data.polygons])
    performance = json.loads(inputs['performance'].read_text(encoding='utf-8'))
    if (len(performance['bones']) != 16 or len(set(performance['bones'])) != 16
            or any(len(performance['weights'][role]) != len(points[role]) for role in meshes)):
        raise ValueError('Canonical performance palette or topology changed')
    # Ears belong to Body, not Face. Keep actual rigid-head triangles, including
    # their concave rims and back surfaces, instead of guessing a head capsule.
    head_vertices = {i for i, weights in enumerate(performance["weights"][0])
                     if sum(w for b, w in weights if b == 5) > .99999}
    body_head_faces = [[round(v, 7) for v in points[0][i]]
                       for polygon in meshes[0].data.polygons
                       if all(i in head_vertices for i in polygon.vertices)
                       for corner in range(1, len(polygon.vertices) - 1)
                       for i in (polygon.vertices[0], polygon.vertices[corner], polygon.vertices[corner + 1])]
    hair_groups = sorted(components(meshes[2].data), key=len, reverse=True)
    # Coordinate boxes identify shells; they must not cut moving tips in half.
    # Do not weld here: separate locks share scalp vertices with the static cap.
    sides = [set(), set()]
    for group in components(meshes[2].data, weld=False):
        left = any(points[2][i].x < -.24 and 2.35 < points[2][i].y < 2.67
                   and points[2][i].z > -.12 for i in group)
        right = any(points[2][i].x > .02 and 2.36 < points[2][i].y < 2.65
                    and points[2][i].z > -.15 for i in group)
        if not (left or right):
            continue
        for i in group:
            side = int(points[2][i].x >= -.112) if left and right else int(right)
            sides[side].add(i)
    # Identical seam vertices must carry identical weights, even across UV splits.
    ownership = {tuple(round(v, 5) for v in points[2][i]): side
                 for side in range(2) for i in sorted(sides[side])}
    sides = [set(), set()]
    for i, point in enumerate(points[2]):
        key = tuple(round(v, 5) for v in point)
        if key in ownership:
            sides[ownership[key]].add(i)
    front = set().union(*(indices for name, indices in zones.items() if name.startswith('bangs.')))
    selections = [
        ('ponytail', 2, 5, sorted(set(hair_groups[0]) - static)),
        ('side.L', 2, 5, sorted(sides[0] - static - front - set(hair_groups[0]))),
        ('side.R', 2, 5, sorted(sides[1] - static - front - set(hair_groups[0]))),
    ]
    strap = next(group for group in components(meshes[0].data)
                 if len(group) > 150 and min(points[0][i].y for i in group) < .7
                 and max(points[0][i].y for i in group) < 1.6
                 and max(points[0][i].x for i in group) < -.14)
    selections.append(('fabric.strap', 0, 1, sorted(set(strap) | zones['fabric.strap'])))
    # Preserve existing palette indices 16..27; front sections append their bones.
    for name, indices in zones.items():
        if name.startswith('bangs.'):
            selections.append((name, 2, 5, sorted(indices - set(hair_groups[0]))))
    chains, overrides = [], {'0': [], '2': []}
    joint_names = []
    for name, role, parent, indices in selections:
        motion = profile['chains'][name]
        curve = [Vector(p) for p in motion['curve']]
        guides = strap if name == 'fabric.strap' else indices
        high = max(points[role][i].y for i in guides)
        low = min(points[role][i].y for i in guides)
        if name in ('side.L', 'side.R'):
            high = min(high, 2.67 if name == 'side.L' else 2.65)
            guides = [i for i in indices if points[role][i].y <= high
                      and points[role][i].z > (-.12 if name == 'side.L' else -.15)
                      and (points[role][i].x < -.24 if name == 'side.L' else points[role][i].x > .02)]
        centers = []
        for node in range(4):
            height = high + (low - high) * node / 3
            nearest = sorted(guides, key=lambda i: abs(points[role][i].y - height))[:max(3, len(guides)//16)]
            center = sum((points[role][i] for i in nearest), Vector()) / len(nearest)
            center.y = height
            centers.append([round(x, 7) for x in center])
        if role == 2:
            centers = resample_curve(curve)
        bones = []
        for segment in range(3):
            bones.append(16 + len(joint_names))
            joint_names.append(f'dynamic.{name}.{segment}')
        rows = []
        for index in indices:
            fraction = max(0.0, min(1.0, (high - points[role][index].y) / (high-low)))
            if role == 2:
                fraction = curve_parameter(points[role][index], curve)
            fade = max(0.0, min(1.0, (fraction - .08) / .45)) if role == 2 else min(1.0, fraction * 8.0)
            weight = fade * fade * (3.0 - 2.0 * fade) if role == 2 else fade
            if role == 2:
                weight = curve_weight(fraction, motion['weight_curve'])
            # A vertex near a joint blends the preceding and following segment.
            # The old mapping blended toward the next joint a whole segment early.
            coordinate = max(0.0, min(2.0, fraction * 3.0 - 1.0))
            a, blend = int(coordinate), coordinate % 1.0
            influences = [[bones[a], round(weight*(1-blend), 7)]]
            if a < 2 and blend > 0:
                influences.append([bones[a+1], round(weight*blend, 7)])
            if weight < 1.0:
                influences.append([parent, round(1-weight, 7)])
            if index in pinned.get(name, set()):
                influences = [[parent, 1.0]]
            rows.append([index, influences])
        overrides[str(role)].extend(rows)
        samples = {}
        contacts = []
        for index, influences in rows:
            point = [round(v, 7) for v in points[role][index]]
            key = (tuple(point), tuple((b, w) for b, w in influences))
            plane = []
            distance = 0.0
            if role == 2:
                nearest, normal, _, distance = face_tree.find_nearest(Vector(point))
                if normal.dot(nearest - Vector((-.112, 2.58, -.06))) < 0:
                    normal = -normal
                plane = [*normal, normal.dot(nearest)]
            samples[key] = [point, influences, plane, distance, index]
            if plane:
                contacts.append([index, plane, distance])
        chains.append({'name': name, 'role': role, 'parent': parent, 'points': centers,
                       'motion': motion,
                       'attachment_vertices': sorted(pinned.get(name, set())),
                       'bones': bones, 'vertices': len(indices), 'radius': .004 if role == 2 else .006,
                       'surface_samples': list(samples.values()), 'vertex_contacts': contacts})
    for zone in profile['static_zones']:
        overrides['2'].extend([[i, [[zone['parent'], 1.0]]] for i in zone['vertices']])
    names = performance['bones'] + joint_names
    for obj in [obj for obj in bpy.data.objects if obj not in meshes.values()]:
        bpy.data.objects.remove(obj, do_unlink=True)
    armature = bpy.data.armatures.new('DynamicBindPalette')
    rig = bpy.data.objects.new('DynamicBindPalette', armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name in names:
        bone = armature.edit_bones.new(name)
        bone.head, bone.tail = (0, 0, 0), (0, 1, 0)
    bpy.ops.object.mode_set(mode='OBJECT')
    for role, obj in meshes.items():
        obj.parent = None
        obj.modifiers.clear()
        for name in joint_names:
            obj.vertex_groups.new(name=name)
        for index, influences in overrides[str(role)]:
            for group in obj.vertex_groups:
                group.remove([index])
            for bone, weight in influences:
                if weight > 0:
                    obj.vertex_groups[names[bone]].add([index], weight, 'REPLACE')
        skin = obj.modifiers.new('DynamicSkin', 'ARMATURE')
        skin.object = rig
        obj.parent = rig
    colliders = [
        {'name': 'head', 'parent': 5, 'start': [-.112,2.47,-.06], 'end': [-.112,2.68,-.08], 'radius': .12},
        {'name': 'shoulders', 'parent': 3, 'start': [-.29,2.17,-.04], 'end': [.12,2.17,-.04], 'radius': .09},
        {'name': 'left_thigh', 'parent': 10, 'start': [-.13,1.36,.07], 'end': [-.14,.84,.08], 'radius': .075},
    ]
    for row in colliders:
        start, end = xyz(row['start']), xyz(row['end'])
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, location=(start+end)*.5)
        obj = bpy.context.object
        obj.name = 'Collision.' + row['name']
        obj.scale = (row['radius'],row['radius'],(end-start).length*.5+row['radius'])
        obj.rotation_euler = (end-start).to_track_quat('Z','Y').to_euler()
        obj.hide_render = True
    (output/SOURCE.parent).mkdir(parents=True, exist_ok=True)
    (output/GLB.parent).mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output/SOURCE))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in list(meshes.values())+[rig]:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(output/GLB), export_format='GLB', use_selection=True,
                              export_animations=False, export_morph=False, export_skins=True)
    manifest = {'schema': 3, 'name': 'hair_dynamic_v1', 'default_disabled': True,
                'motion_profile': inputs['profile'].name, 'motion_profile_sha256': sha256(inputs['profile']),
                'static_zones': profile['static_zones'],
                'dynamic_zones': [{**zone, 'vertices': sorted(zones[zone['name']])}
                                  for zone in profile['dynamic_zones']],
                'blender': bpy.app.version_string, 'source': SOURCE.as_posix(), 'glb': GLB.as_posix(),
                'source_sha256': sha256(output/SOURCE), 'glb_sha256': sha256(output/GLB),
                'generator_sha256': sha256(Path(__file__)), 'canonical_source_sha256': sha256(source),
                'coordinate_system': 'Godot actor-local metres; canonical vertex indices',
                'bones': joint_names, 'chains': chains, 'weights': overrides, 'colliders': colliders,
                'head_surface': {'parent': 5, 'method': 'face tangents plus swept Body head triangles',
                                 'bvh_origin': recipe['head_bvh_origin'],
                                 'body_faces': body_head_faces},
                'selection_policy': 'authored front shells and strap hardware; static nape; identical UV seams',
                'source_vertices': {str(k):len(v) for k,v in points.items()}}
    (output/MANIFEST).write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    generation = {
        'schema': 1, 'generator': Path(__file__).name, 'generator_sha256': sha256(Path(__file__)),
        'blender_version': bpy.app.version_string, 'blender_commit': bpy.app.build_hash.decode(),
        'input_recipe': args.recipe.name, 'input_recipe_sha256': sha256(args.recipe),
        'inputs': {role: {'name': path.name, 'sha256': sha256(path)} for role, path in inputs.items()},
        'historical_input_blend_sha256': recipe['historical_input_blend_sha256'],
        'historical_snapshot_manifest_sha256': recipe.get('historical_snapshot_manifest_sha256'),
        'outputs': {path.name: sha256(output/path) for path in (SOURCE, GLB, MANIFEST)},
        'scope': 'Fixed sample chains and contact sampling; compare all bridge fields before promotion',
    }
    (output/'hair_dynamic_generation.json').write_text(json.dumps(generation, indent=2)+'\n', encoding='utf-8')
    print('HAIR_DYNAMIC_BUILD_OK', [(c['name'],c['vertices']) for c in chains])


if __name__ == '__main__':
    main()
