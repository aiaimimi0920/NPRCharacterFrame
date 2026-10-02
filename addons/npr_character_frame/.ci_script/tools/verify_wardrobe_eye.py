"""Verify real saved eye source, procedural texture and its complete GLB export."""

import hashlib
import json
import math
from pathlib import Path
import struct
import tempfile

import bpy

SCRIPTS = ('build_wardrobe_eye.py', 'verify_wardrobe_eye.py')
OUTPUTS = ('eye_authored_v1.blend', 'eye_authored_v1.glb', 'eye_iris_v1.png', 'eye_authored_v1.json')
NAMES = {side+'_'+part for side in ('EyeL', 'EyeR') for part in ('Sclera', 'Iris', 'Pupil', 'TearFilm')}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def glb_content(path):
    data = path.read_bytes()
    require(len(data) >= 20 and struct.unpack_from('<III', data) == (0x46546c67, 2, len(data)),
            'Invalid GLB header')
    offset, chunks = 12, {}
    while offset < len(data):
        require(offset+8 <= len(data), 'Truncated GLB chunk header')
        size, kind = struct.unpack_from('<II', data, offset)
        offset += 8
        require(size % 4 == 0 and offset+size <= len(data) and kind not in chunks, 'Invalid GLB chunks')
        chunks[kind] = data[offset:offset+size]
        offset += size
    require(set(chunks) == {0x4e4f534a, 0x004e4942}, 'Missing GLB JSON or BIN')
    gltf = json.loads(chunks[0x4e4f534a])
    require(gltf.get('asset', {}).get('version') == '2.0', 'Expected glTF 2')
    require(all('uri' not in row for row in gltf.get('buffers', [])+gltf.get('images', [])),
            'Eye GLB must embed buffers and images')
    gltf.pop('asset')  # Exporter label is not runtime geometry or material data.
    return gltf, chunks[0x004e4942]


def snapshot():
    bpy.context.view_layer.update()
    require(set(bpy.data.objects.keys()) == NAMES, 'Saved ocular object names changed')
    result = {}
    for ob in bpy.data.objects:
        require(ob.type == 'MESH' and ob.parent is None and not ob.modifiers and ob.data.shape_keys is None,
                'Ocular surfaces must remain rigid independent meshes')
        require(not ob.hide_render and not ob.hide_viewport, 'Saved ocular visibility changed')
        mesh = ob.data
        require(len(mesh.uv_layers) == 1 and len(mesh.materials) == 1, 'Saved eye UV/material slots changed')
        mat = mesh.materials[0]
        require(mat is not None and mat.use_nodes, 'Saved eye material missing')
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        require(bsdf is not None, 'Saved eye shader source missing')
        textures = [node for node in mat.node_tree.nodes if node.type == 'TEX_IMAGE']
        links = sorted((link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
                       for link in mat.node_tree.links)
        image = None
        if textures:
            require(len(textures) == 1 and textures[0].image is not None, 'Saved iris image missing')
            image = textures[0].image
            require(image.packed_file is None and Path(bpy.path.abspath(image.filepath)).name == 'eye_iris_v1.png',
                    'Saved iris image reference changed')
            image = {'name': image.name, 'size': list(image.size),
                     'color_space': image.colorspace_settings.name, 'file_format': image.file_format}
        result[ob.name] = {
            'vertices': [list(vertex.co) for vertex in mesh.vertices],
            'faces': [list(poly.vertices) for poly in mesh.polygons],
            'smooth': [poly.use_smooth for poly in mesh.polygons],
            'uv': [list(row.uv) for row in mesh.uv_layers[0].data],
            'transform': [value for row in ob.matrix_world for value in row],
            'material': {'name': mat.name, 'diffuse_color': list(mat.diffuse_color),
                         'base_color': list(bsdf.inputs['Base Color'].default_value),
                         'roughness': bsdf.inputs['Roughness'].default_value,
                         'specular_ior': bsdf.inputs['Specular IOR Level'].default_value,
                         'node_types': sorted(node.type for node in mat.node_tree.nodes),
                         'links': links, 'image': image},
        }
    return result


def compare(actual, expected, path='source'):
    message = 'Saved eye geometry or materials changed: '+path
    if isinstance(expected, dict):
        require(isinstance(actual, dict) and set(actual) == set(expected), message)
        return max((compare(actual[key], value, path+'/'+key) for key, value in expected.items()), default=0.)
    if isinstance(expected, (list, tuple)):
        require(isinstance(actual, (list, tuple)) and len(actual) == len(expected), message)
        return max((compare(a, b, path+'/'+str(i)) for i, (a, b) in enumerate(zip(actual, expected))), default=0.)
    if type(expected) is float:
        require(type(actual) in (int, float) and math.isfinite(actual), message)
        error = abs(actual-expected)
        require(error <= 1e-7, message)
        return error
    require(type(actual) == type(expected) and actual == expected, message)
    return 0.


def verify_saved(output, report, inputs, profiles, recipe, create_scene, export_glb):
    generation = read_json(output/'eye_generation.json')
    require(generation['schema'] == 1 and generation['generator'] == SCRIPTS[0]
            and generation['scripts'] == {name: sha(Path(__file__).with_name(name)) for name in SCRIPTS},
            'Generation script identity changed')
    require(generation['input_recipe'] == recipe.name and generation['input_recipe_sha256'] == sha(recipe)
            and generation['inputs'] == {role: {'name': path.name, 'sha256': sha(path)} for role, path in inputs.items()},
            'Generation input identity changed')
    identities = {name: sha(output/name) for name in OUTPUTS}
    require(generation['outputs'] == identities, 'Generated output identity changed')
    manifest = read_json(output/'eye_authored_v1.json')
    require(manifest['schema'] == 2 and manifest['name'] == 'eye_authored_v1'
            and manifest['source'] == OUTPUTS[0] and manifest['glb'] == OUTPUTS[1]
            and manifest['source_sha256'] == identities[OUTPUTS[0]] and manifest['glb_sha256'] == identities[OUTPUTS[1]]
            and manifest['generator_sha256'] == sha(Path(__file__).with_name(SCRIPTS[0]))
            and manifest['character_reference'] == inputs['rig'].name and manifest['character_sha256'] == sha(inputs['rig'])
            and manifest['lid_source'] == inputs['lids'].name and manifest['lid_source_sha256'] == sha(inputs['lids']),
            'Eye manifest identity changed')
    require('backup_manifest_sha256' not in manifest, 'Historical backup must not claim current generation')
    with tempfile.TemporaryDirectory(prefix='.verify_eye_', dir=output) as temporary:
        work = Path(temporary)
        objects, landmarks, materials = create_scene(inputs['rig'], profiles, work, write_texture=False)
        expected = snapshot()
        bpy.data.images['eye_iris_v1'].save()
        require(sha(work/'eye_iris_v1.png') == identities['eye_iris_v1.png'], 'Procedural iris texture changed')
        export_glb(work/'rebuilt_inputs.glb')
        rebuilt_glb, rebuilt_bin = glb_content(work/'rebuilt_inputs.glb')
        require(manifest['landmarks'] == json.loads(json.dumps(landmarks))
                and manifest['objects'] == [ob.name for ob in objects]
                and manifest['materials'] == [mat.name for mat in materials.values()]
                and manifest['default_disabled'] is True
                and manifest['coordinate_system'] == 'Godot Y-up authored positions, Blender Z-up export'
                and manifest['closure_shape'] == 'shared sliding lids; rigid ocular surfaces'
                and manifest['depth_fit'] == 'lid_surface_v2 curved shell' and manifest['max_envelope_offset_m'] == .004
                and manifest['iris_texture'] == {'path': 'eye_iris_v1.png', 'sha256': identities['eye_iris_v1.png'],
                                               'color_space': 'sRGB', 'size': [256, 256]},
                'Eye manifest landmarks or material contract changed')
        bpy.ops.wm.open_mainfile(filepath=str(output/'eye_authored_v1.blend'))
        require(bpy.data.images['eye_iris_v1'].filepath == '//eye_iris_v1.png', 'Saved iris path must remain relative')
        actual = snapshot()
        error = compare(actual, expected)
        export_glb(work/'saved_source.glb')
        saved_glb, saved_bin = glb_content(work/'saved_source.glb')
        output_glb, output_bin = glb_content(output/'eye_authored_v1.glb')
        require((saved_glb, saved_bin) == (output_glb, output_bin), 'GLB and saved eye source differ')
        require((rebuilt_glb, rebuilt_bin) == (output_glb, output_bin), 'GLB and rebuilt eye inputs differ')
        require(set(node['name'] for node in output_glb['nodes']) == NAMES
                and len(output_glb['meshes']) == 8 and len(output_glb['materials']) == 4
                and len(output_glb['images']) == 1 and not output_glb.get('skins') and not output_glb.get('animations'),
                'Exported rigid ocular structure changed')
    receipt = {'schema': 1, 'pass': True, 'objects': 8, 'materials': 4,
               'vertices': {name: len(row['vertices']) for name, row in actual.items()},
               'faces': {name: len(row['faces']) for name, row in actual.items()},
               'saved_attribute_max_error': error, 'glb_matches_saved_source': True,
               'glb_matches_reconstruction': True,
               'iris_size': [256, 256], 'iris_color_space': 'sRGB', 'iris_path_relative': True,
               'outputs': identities, 'generation_sha256': sha(output/'eye_generation.json')}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print('EYE_SOURCE_OK', json.dumps(receipt))
