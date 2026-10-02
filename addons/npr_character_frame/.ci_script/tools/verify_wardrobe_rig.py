"""Reopen the baked Blender source and compare real saved data with the bridge."""

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
PARTS = ('Body', 'Face', 'Hair')
SHAPES = {'blink.L', 'blink.R', 'blink_mid.L', 'blink_mid.R',
          'happy', 'sad', 'angry', 'aa', 'ee', 'ih', 'oh', 'ou'}
ACTIONS = {'idle', 'greeting', 'look_around', 'presentation'}
OUTPUTS = ('character_rig.blend', 'performance.json', 'lid_surface_v2.json')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def xyz(point):
    return Vector((point[0], -point[2], point[1]))


def finite(row, length):
    return (isinstance(row, list) and len(row) == length
            and all(type(v) in (int, float) and math.isfinite(v) for v in row))


def max_error(actual, expected):
    require(len(actual) == len(expected), 'Saved attribute count changed')
    return max((abs(a-b) for a, b in zip(actual, expected)), default=0.)


def identity_error(matrix):
    return max(abs(matrix[r][c] - int(r == c)) for r in range(4) for c in range(4))


def topology(mesh, points, indices, uv):
    require(len(mesh.vertices) == len(points), 'Saved canonical vertex count changed')
    faces = [tuple(poly.vertices) for poly in mesh.polygons]
    require(faces == [(indices[i], indices[i+2], indices[i+1]) for i in range(0, len(indices), 3)],
            'Saved triangle indices changed')
    rest = max((max_error(v.co, xyz(p)) for v, p in zip(mesh.vertices, points)), default=0.)
    require(len(mesh.uv_layers) == 1, 'Saved UV layers changed')
    layer = mesh.uv_layers[0]
    uv_error = max((max_error(layer.data[loop.index].uv, uv[loop.vertex_index])
                    for loop in mesh.loops), default=0.)
    require(rest <= 3e-7 and uv_error <= 1e-7, 'Saved rest positions or UVs changed')
    return rest, uv_error


def shape_keys(ob, shapes):
    keys = ob.data.shape_keys
    require(keys is not None and keys.use_relative, 'Saved relative Shape Keys missing')
    require(set(keys.key_blocks.keys()) == {'Basis', *shapes}, 'Saved Shape Key names changed')
    basis = keys.key_blocks['Basis']
    require(all(max_error(a.co, b.co) <= 3e-7 for a, b in zip(basis.data, ob.data.vertices)),
            'Saved Basis and rest mesh differ')
    error = 0.
    for name, rows in shapes.items():
        deltas = {}
        for row in rows:
            require(finite(row, 4) and type(row[0]) is int and 0 <= row[0] < len(basis.data)
                    and row[0] not in deltas, 'Invalid sparse Shape Key rows')
            deltas[row[0]] = xyz(row[1:])
        key = keys.key_blocks[name]
        require(key.relative_key == basis and key.value == 0 and not key.mute,
                'Saved Shape Key relative basis or default changed')
        for i, (point, rest) in enumerate(zip(key.data, basis.data)):
            expected = rest.co + deltas.get(i, Vector((0, 0, 0)))
            error = max(error, max_error(point.co, expected))
    require(error <= 3e-7, 'Saved Shape Keys and bridge differ')
    return error


def skin(ob, rig, names, rows):
    require(ob.parent is None and len(ob.modifiers) == 1 and ob.modifiers[0].type == 'ARMATURE'
            and ob.modifiers[0].object == rig, 'Saved armature binding changed')
    require(list(ob.vertex_groups.keys()) == names and len(rows) == len(ob.data.vertices),
            'Saved vertex groups or weight count changed')
    error, totals = 0., []
    for vertex, row in zip(ob.data.vertices, rows):
        expected = {}
        for pair in row:
            require(finite(pair, 2) and type(pair[0]) is int and 0 <= pair[0] < len(names)
                    and 0 <= pair[1] <= 1 and pair[0] not in expected, 'Invalid bridge weights')
            expected[pair[0]] = pair[1]
        actual = {group.group: group.weight for group in vertex.groups}
        require(all(0 <= index < len(names) for index in actual), 'Invalid saved vertex group index')
        require(all(math.isfinite(w) and 0 <= w <= 1 for w in actual.values()), 'Invalid saved weights')
        total = sum(actual.values())
        totals.append(total)
        require(abs(total-1) <= 2e-6 and abs(sum(expected.values())-1) <= 2e-6,
                'Saved or bridge weights are not normalized')
        error = max(error, max((abs(actual.get(i, 0)-expected.get(i, 0))
                                for i in set(actual)|set(expected)), default=0.))
    require(error <= 1e-7, 'Saved skin weights and bridge differ')
    return error, totals


def verify_saved(output, report, probe, layout, expected_lids, recipe_path, inputs, scripts):
    generation = read_json(output/'performance_generation.json')
    require(generation['schema'] == 1 and generation['generator'] == 'build_wardrobe_rig.py'
            and generation['scripts'] == {name: sha(Path(__file__).with_name(name)) for name in scripts},
            'Generation script identity changed')
    require(generation['input_recipe_sha256'] == sha(recipe_path)
            and generation['input_recipe'] == recipe_path.name
            and generation['inputs'] == {role: {'name': path.name, 'sha256': sha(path)}
                                         for role, path in inputs.items()}, 'Generation input identity changed')
    identities = {name: sha(output/name) for name in OUTPUTS}
    require(generation['outputs'] == identities, 'Generated output identity changed')
    bridge = read_json(output/'performance.json')
    lids = read_json(output/'lid_surface_v2.json')
    require(lids == expected_lids, 'Generated sliding lids differ from the input geometry')
    names = [row['name'] for row in layout['bones']]
    require(bridge['schema'] == 1 and bridge['bones'] == names and len(bridge['weights']) == 3
            and set(bridge['shapes']) == SHAPES and set(bridge['actions']) == ACTIONS,
            'Invalid performance bridge structure')
    for name, rows in lids['shapes'].items():
        require(bridge['shapes'][name] == rows, 'Performance and sliding lash shapes differ')
    bpy.ops.wm.open_mainfile(filepath=str(output/'character_rig.blend'))
    rig = bpy.data.objects.get('WardrobeRig')
    require(rig is not None and rig.type == 'ARMATURE' and set(rig.data.bones.keys()) == set(names),
            'Saved canonical bones changed')
    bone_error = 0.
    # Blender stores bones in hierarchy traversal order. Bridge/group indices
    # retain the canonical order; resolve the saved rest bones by name.
    for row in layout['bones']:
        bone = rig.data.bones[row['name']]
        require((bone.parent.name if bone.parent else None) == row['parent'], 'Saved bone parent changed')
        bone_error = max(bone_error, max_error(bone.head_local, xyz(row['head'])),
                         max_error(bone.tail_local, xyz(row['tail'])))
    require(bone_error <= 3e-7, 'Saved bone rest layout changed')
    require(identity_error(rig.matrix_world) <= 3e-7, 'Saved rig transform changed')
    metrics = {'rest_max_error': 0., 'uv_max_error': 0., 'weight_max_error': 0.,
               'shape_max_error': 0., 'action_max_error': 0., 'bone_rest_max_error': bone_error}
    counts, totals = {}, []
    for role, name in enumerate(PARTS):
        ob = bpy.data.objects.get(name)
        require(ob is not None and ob.type == 'MESH', 'Saved canonical mesh missing')
        require(identity_error(ob.matrix_world) <= 3e-7, 'Saved mesh transform changed')
        source = probe['meshes'][role]
        rest, uv = topology(ob.data, source['positions'], source['indices'],
                            [[u, 1-v] for u, v in source['uv']])
        weight_error, sums = skin(ob, rig, names, bridge['weights'][role])
        totals.extend(sums)
        metrics['rest_max_error'] = max(metrics['rest_max_error'], rest)
        metrics['uv_max_error'] = max(metrics['uv_max_error'], uv)
        metrics['weight_max_error'] = max(metrics['weight_max_error'], weight_error)
        counts[name] = len(ob.data.vertices)
        if name == 'Face':
            metrics['shape_max_error'] = shape_keys(ob, bridge['shapes'])
    for surface in lids['surfaces']:
        ob = bpy.data.objects.get('SlidingLid_'+surface['name'])
        require(ob is not None and ob.type == 'MESH', 'Saved sliding surface missing')
        rest, uv = topology(ob.data, surface['vertices'], surface['indices'], surface['uv'])
        require(identity_error(ob.matrix_world) <= 3e-7, 'Saved sliding surface transform changed')
        weight_error, _ = skin(ob, rig, ['head'], [[[0, 1.]] for _ in surface['vertices']])
        shapes = {name: [[i, *delta] for i, delta in enumerate(surface[name])]
                  for name in ('closed', 'arc')}
        metrics['shape_max_error'] = max(metrics['shape_max_error'], shape_keys(ob, shapes))
        metrics['rest_max_error'] = max(metrics['rest_max_error'], rest)
        metrics['uv_max_error'] = max(metrics['uv_max_error'], uv)
        counts[ob.name] = len(ob.data.vertices)
    require(set(bpy.data.actions.keys()) == ACTIONS and bpy.context.scene.render.fps == 30,
            'Saved action names or frame rate changed')
    require(bpy.context.scene.frame_start == 0 and bpy.context.scene.frame_end == 120,
            'Saved scene frame range changed')
    require(rig.animation_data is not None, 'Saved rig animation missing')
    for name, action in bridge['actions'].items():
        require(action['fps'] == 30 and len(action['frames']) == 121, 'Invalid sampled action shape')
        require(tuple(bpy.data.actions[name].frame_range) == (0., 120.), 'Saved action frame range changed')
        rig.animation_data.action = bpy.data.actions[name]
        for frame, poses in enumerate(action['frames']):
            require(len(poses) == 16 and all(finite(pose, 12) for pose in poses),
                    'Invalid sampled action matrices')
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            for bone_name, expected in zip(names, poses):
                deform = C.inverted() @ rig.pose.bones[bone_name].matrix @ rig.data.bones[bone_name].matrix_local.inverted() @ C
                actual = [deform[r][c] for r in range(3) for c in range(4)]
                metrics['action_max_error'] = max(metrics['action_max_error'], max_error(actual, expected))
    require(metrics['action_max_error'] <= 1e-7, 'Saved actions and bridge differ')
    receipt = {'schema': 1, 'pass': True, 'vertices': counts, 'bones': len(names),
               'face_shapes': len(SHAPES), 'actions': len(ACTIONS), 'sampled_frames_per_action': 121,
               'weight_sum_range': [min(totals), max(totals)], **metrics,
               'outputs': identities, 'generation_sha256': sha(output/'performance_generation.json')}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print('PERFORMANCE_SOURCE_OK', json.dumps(receipt))
