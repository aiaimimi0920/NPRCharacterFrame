"""Saved base/material source and GLB verification for the equipment bake."""

import hashlib
import json
import math
from pathlib import Path
import struct
import tempfile

import bpy

SCRIPTS = ('build_wardrobe_equipment.py', 'verify_wardrobe_equipment.py')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def geometry_snapshot():
    bpy.context.view_layer.update()
    result = {}
    for ob in bpy.context.scene.objects:
        require(ob.type == 'MESH' and ob.parent is None and not ob.modifiers
                and ob.data.shape_keys is None and not ob.hide_render and not ob.hide_viewport,
                'Equipment must contain independent rigid meshes')
        mesh = ob.data
        require(len(mesh.materials) == 1 and mesh.materials[0] is not None, 'Equipment requires one material slot')
        result[ob.name] = {
            'vertices': [list(v.co) for v in mesh.vertices],
            'faces': [list(poly.vertices) for poly in mesh.polygons],
            'smooth': [poly.use_smooth for poly in mesh.polygons],
            'uv': {layer.name: [list(row.uv) for row in layer.data] for layer in mesh.uv_layers},
            'transform': [v for row in ob.matrix_world for v in row],
            'collections': sorted(col.name for col in ob.users_collection),
            'material': mesh.materials[0].name,
            'material_id': ob.get('NPR_MATERIAL_ID'),
        }
    return result


def compare(actual, expected, message='Saved equipment geometry changed', path='source'):
    if isinstance(expected, dict):
        require(isinstance(actual, dict) and set(actual) == set(expected), message+': '+path)
        return max((compare(actual[k], v, message, path+'/'+k) for k, v in expected.items()), default=0.)
    if isinstance(expected, list):
        require(isinstance(actual, list) and len(actual) == len(expected), message+': '+path)
        return max((compare(a, b, message, path+'/'+str(i)) for i, (a, b) in enumerate(zip(actual, expected))), default=0.)
    if type(expected) is float:
        require(type(actual) in (int, float) and math.isfinite(actual), message+': '+path)
        error = abs(actual-expected)
        require(error <= 1e-7, message+': '+path)
        return error
    require(type(actual) == type(expected) and actual == expected, message+': '+path)
    return 0.


def glb_content(path):
    data = path.read_bytes()
    require(len(data) >= 20 and struct.unpack_from('<III', data) == (0x46546c67, 2, len(data)), 'Invalid GLB header')
    offset, chunks = 12, {}
    while offset < len(data):
        require(offset+8 <= len(data), 'Truncated GLB chunk')
        size, kind = struct.unpack_from('<II', data, offset); offset += 8
        require(size % 4 == 0 and offset+size <= len(data) and kind not in chunks, 'Invalid GLB chunks')
        chunks[kind] = data[offset:offset+size]; offset += size
    require(set(chunks) == {0x4e4f534a, 0x004e4942}, 'Missing GLB JSON/BIN')
    gltf = json.loads(chunks[0x4e4f534a])
    require(gltf.get('asset', {}).get('version') == '2.0'
            and all('uri' not in row for row in gltf.get('buffers', [])+gltf.get('images', [])), 'GLB must embed images and buffers')
    gltf.pop('asset')
    return gltf, chunks[0x004e4942]


def verify_saved(output, report, source, recipe, create_base, create_materials, export_part, export_glb, material_manifest):
    generation = read_json(output/'equipment_generation.json')
    require(generation['schema'] == 1 and generation['generator'] == SCRIPTS[0]
            and generation['scripts'] == {name: sha(Path(__file__).with_name(name)) for name in SCRIPTS},
            'Generation script identity changed')
    require(generation['input_recipe'] == recipe.name and generation['input_recipe_sha256'] == sha(recipe)
            and generation['inputs'] == {'equipment': {'name': source.name, 'sha256': sha(source)}},
            'Generation input identity changed')
    expected_names = {'equipment.blend', 'equipment.json', 'equipment_materials_v1.blend',
                      'equipment_materials_v1.glb', 'material_authored_v1.json'}
    expected_names |= {'textures/materials_v1/equipment_'+name+suffix+'.png'
                       for name in ('dark', 'silver', 'violet', 'Material') for suffix in ('', '_roughness')}
    require(set(generation['outputs']) == expected_names, 'Generated output list changed')
    identities = {name: sha(output/name) for name in expected_names}
    require(generation['outputs'] == identities, 'Generated output identity changed')
    expected_bridge = create_base(); base = geometry_snapshot()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    reference_error = compare(geometry_snapshot(), base, 'Archived equipment geometry changed')
    bpy.ops.wm.open_mainfile(filepath=str(output/'equipment.blend'))
    base_error = compare(geometry_snapshot(), base)
    groups = {key: list(bpy.data.collections[key].objects) for key in expected_bridge}
    # Collection iteration is name-sorted; bridge keeps authored part order.
    actual_bridge = {}
    for key, expected in expected_bridge.items():
        # Recover original part order from the expected bridge's first vertex.
        candidates = {ob.name: export_part([ob]) for ob in groups[key]}
        combined = {field: [] for field in ('positions', 'normals', 'indices', 'swatches')}
        remaining = dict(candidates)
        while remaining:
            offset = len(combined['positions'])
            name = next((name for name, row in remaining.items()
                         if row['positions'] == expected['positions'][offset:offset+len(row['positions'])]
                         and row['normals'] == expected['normals'][offset:offset+len(row['normals'])]
                         and row['swatches'] == expected['swatches'][offset:offset+len(row['swatches'])]), None)
            require(name is not None, 'Saved base mesh and bridge order differ')
            row = remaining.pop(name)
            for field in ('positions', 'normals', 'swatches'):
                combined[field].extend(row[field])
            combined['indices'].extend(index+offset for index in row['indices'])
        actual_bridge[key] = combined
    require(actual_bridge == expected_bridge == read_json(output/'equipment.json'), 'Saved base geometry and bridge differ')
    manifest = read_json(output/'material_authored_v1.json')
    require(manifest['source_input'] == source.name and manifest['source_input_sha256'] == sha(source)
            and manifest['source'] == 'equipment_materials_v1.blend' and manifest['glb'] == 'equipment_materials_v1.glb'
            and manifest['source_sha256'] == identities[manifest['source']] and manifest['glb_sha256'] == identities[manifest['glb']]
            and manifest['generator_sha256'] == sha(Path(__file__).with_name(SCRIPTS[0]))
            and 'backup_manifest_sha256' not in manifest, 'Material manifest identity changed')
    with tempfile.TemporaryDirectory(prefix='.verify_equipment_', dir=output) as temporary:
        work = Path(temporary)
        textures, objects = create_materials(source, work)
        expected_material = geometry_snapshot()
        for pair in textures.values():
            for path in pair:
                require(sha(path) == identities[path.relative_to(work).as_posix()], 'Procedural equipment texture changed')
        output_textures = {name: tuple(output/path.relative_to(work) for path in pair) for name, pair in textures.items()}
        expected_manifest = material_manifest(source, output, output_textures, objects)
        require(manifest == json.loads(json.dumps(expected_manifest)), 'Material manifest contract changed')
        export_glb(work/'rebuilt.glb'); rebuilt = glb_content(work/'rebuilt.glb')
        require(manifest['objects'] == objects and manifest['schema'] == 1 and manifest['name'] == 'material_authored_v1',
                'Material manifest objects changed')
        bpy.ops.wm.open_mainfile(filepath=str(output/'equipment_materials_v1.blend'))
        material_error = compare(geometry_snapshot(), expected_material)
        image_paths = []
        for ob in bpy.context.scene.objects:
            for node in ob.data.materials[0].node_tree.nodes:
                if node.type == 'TEX_IMAGE':
                    image = node.image
                    relative = image.filepath.replace('\\', '/') if image is not None else ''
                    require(image is not None and image.packed_file is None
                            and relative.startswith('//textures/materials_v1/'), 'Saved material textures must remain relative')
                    require(sha(Path(bpy.path.abspath(image.filepath))) == identities[relative[2:]], 'Saved material texture changed')
                    image_paths.append(relative[2:])
        export_glb(work/'saved.glb'); saved = glb_content(work/'saved.glb')
        delivered = glb_content(output/'equipment_materials_v1.glb')
        require(saved == delivered, 'GLB and saved material source differ')
        require(rebuilt == delivered, 'GLB and rebuilt equipment inputs differ')
        require(len(delivered[0]['meshes']) == 19 and len(delivered[0]['nodes']) == 19
                and len(delivered[0]['materials']) == 3 and len(delivered[0]['images']) == 6
                and not delivered[0].get('skins') and not delivered[0].get('animations'), 'Exported equipment structure changed')
    receipt = {'schema': 1, 'pass': True, 'objects': 19,
               'slot_triangles': {key: len(row['indices'])//3 for key, row in expected_bridge.items()},
               'reference_max_error': reference_error, 'base_max_error': base_error, 'material_geometry_max_error': material_error,
               'author_textures': 8, 'runtime_textures': len(set(image_paths)), 'image_paths_relative': True,
               'glb_matches_saved_source': True, 'glb_matches_reconstruction': True,
               'outputs': identities, 'generation_sha256': sha(output/'equipment_generation.json')}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print('EQUIPMENT_SOURCE_OK', json.dumps(receipt))
