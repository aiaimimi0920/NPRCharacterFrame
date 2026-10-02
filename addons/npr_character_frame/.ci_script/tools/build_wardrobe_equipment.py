"""Bake the fixed sample's merged equipment bridge and independent materials."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_wardrobe_equipment import geometry_snapshot, compare, verify_saved

ADDON = Path(__file__).resolve().parents[2]
RECIPE = ADDON/'samples/silver_wolf/import_sources/equipment_bake_inputs.json'
TEXTURE_DIR = Path('textures/materials_v1')
PALETTE = {'dark': (.035, .045, .08, 1.), 'silver': (.72, .78, .90, 1.),
           'violet': (.28, .20, .55, 1.), 'Material': (.55, .57, .64, 1.)}
SURFACES = {
    'dark': {'role': 'matte polymer', 'roughness': [.58, .70], 'metallic': 0., 'coat': 0.},
    'silver': {'role': 'brushed metal coating', 'roughness': [.24, .34], 'metallic': .72, 'coat': 0.},
    'violet': {'role': 'polished crystal coating', 'roughness': [.16, .22], 'metallic': 0., 'coat': .65},
    'Material': {'role': 'satin trim', 'roughness': [.40, .48], 'metallic': 0., 'coat': 0.},
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def host_root():
    for parent in ADDON.parents:
        if (parent/'project.godot').is_file():
            return parent
    raise ValueError('No project.godot found; specify --output')


def load_input(recipe_path):
    recipe = json.loads(recipe_path.read_text(encoding='utf-8'))
    if recipe.get('schema') != 1 or set(recipe.get('files', {})) != {'equipment'}:
        raise ValueError('Expected schema 1 with equipment input')
    row = recipe['files']['equipment']; relative = Path(row['path'])
    if relative.is_absolute():
        raise ValueError('Recipe paths must be relative')
    source = (recipe_path.parent/relative).resolve()
    if not source.is_relative_to(ADDON) or sha(source) != row['sha256']:
        raise ValueError('Input identity or location mismatch: equipment')
    return source


def xyz(point):
    return (point[0], -point[2], point[1])


def godot(point):
    return [round(point.x, 7), round(point.z, 7), round(-point.y, 7)]


def box(name, center, size, color, materials, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(center))
    ob = bpy.context.object; ob.name = name
    ob.scale = (size[0], size[2], size[1]); ob.rotation_euler.y = angle
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = ob.modifiers.new('Machined edges', 'BEVEL')
    bevel.width = min(size)*.18; bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    ob.data.materials.append(materials[color])
    return ob


def gem(name, center, scale, color, materials):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=xyz(center))
    ob = bpy.context.object; ob.name = name
    ob.scale = (scale[0], scale[2], scale[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(materials[color])
    return ob


def export_part(objects):
    vertices, normals, indices, swatches = [], [], [], []
    for ob in objects:
        ob.data.calc_loop_triangles()
        for triangle in ob.data.loop_triangles:
            for vertex in triangle.vertices:
                indices.append(len(vertices))
                vertices.append(godot(ob.matrix_world @ ob.data.vertices[vertex].co))
                normals.append(godot(ob.matrix_world.to_3x3() @ triangle.normal))
                swatches.append(ob.data.materials[0].name)
    return dict(positions=vertices, normals=normals, indices=indices, swatches=swatches)


def create_base():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials = {}
    for name in ('violet', 'dark', 'silver'):
        mat = bpy.data.materials.new(name); mat.diffuse_color = PALETTE[name]
        materials[name] = mat
    parts = {}
    parts['head'] = [
        box('Signal hairclip rail', (.12, 2.77, .015), (.16, .027, .04), 'dark', materials, -.3),
        gem('Signal crystal A', (.12, 2.80, .04), (.045, .095, .023), 'violet', materials),
        gem('Signal crystal B', (.18, 2.76, .035), (.023, .065, .018), 'silver', materials),
    ]
    parts['chest'] = [
        box('Brooch backing', (-.20, 2.23, .245), (.095, .11, .025), 'dark', materials, .35),
        gem('Prism brooch', (-.20, 2.23, .267), (.042, .052, .025), 'violet', materials),
        box('Brooch ribbon L', (-.22, 2.14, .251), (.025, .12, .012), 'silver', materials, -.15),
        box('Brooch ribbon R', (-.18, 2.14, .251), (.025, .10, .012), 'violet', materials, .18),
    ]
    for ob in parts['head']:
        pivot = Vector((.12, -.015, 2.77))
        ob.location = pivot+(ob.location-pivot)*.55+Vector((-.075, -.035, -.04)); ob.scale *= .55
    parts['back'] = [box('Drone mount', (0, 2.04, -.30), (.19, .28, .09), 'dark', materials)]
    for side in (-1, 1):
        parts['back'] += [
            box('Drone stabilizer', (side*.25, 2.13, -.36), (.38, .055, .07), 'silver', materials, side*.38),
            box('Drone wing', (side*.40, 2.20, -.37), (.13, .36, .065), 'violet', materials, side*.38),
            gem('Drone reactor', (side*.30, 2.10, -.42), (.055, .095, .035), 'violet', materials),
        ]
    parts['weapon'] = [
        box('Photon blade grip', (.57, 1.35, .05), (.045, .22, .045), 'dark', materials, -.12),
        box('Photon blade guard', (.57, 1.22, .05), (.20, .045, .065), 'silver', materials, -.12),
        box('Photon blade spine', (.60, .83, .05), (.075, .77, .045), 'dark', materials, -.09),
        gem('Photon blade crystal', (.60, .83, .075), (.07, .45, .032), 'violet', materials),
        gem('Photon blade pommel', (.56, 1.48, .05), (.04, .045, .04), 'silver', materials),
    ]
    bpy.context.view_layer.update()
    data = {key: export_part(objects) for key, objects in parts.items()}
    for key, objects in parts.items():
        collection = bpy.data.collections.new(key); bpy.context.scene.collection.children.link(collection)
        for ob in objects:
            for old in list(ob.users_collection):
                old.objects.unlink(ob)
            collection.objects.link(ob)
    return data


def validate_source(source, expected):
    bpy.ops.wm.open_mainfile(filepath=str(source))
    compare(geometry_snapshot(), expected, 'Archived equipment geometry changed')


def save_texture(output, name, color, roughness=False):
    (output/TEXTURE_DIR).mkdir(parents=True, exist_ok=True)
    suffix = '_roughness' if roughness else ''
    image = bpy.data.images.new('equipment_'+name+suffix, width=64, height=64, alpha=False)
    image.colorspace_settings.name = 'Non-Color' if roughness else 'sRGB'
    values = []
    for y in range(64):
        for x in range(64):
            grain = .5+.25*math.sin(x*2.31+y*1.71)+.25*math.cos(x*1.31-y*2.17)
            if name == 'silver':
                grain = .5+.5*math.sin(y*math.tau/4+.15*math.sin(x*.3))
            if roughness:
                low, high = SURFACES[name]['roughness']; value = low+(high-low)*grain
                values.extend((value, value, value, 1.))
            else:
                values.extend((*[c*(.97+.03*grain) for c in color[:3]], 1.))
    image.pixels = values
    path = output/TEXTURE_DIR/('equipment_'+name+suffix+'.png')
    image.filepath_raw = str(path); image.file_format = 'PNG'; image.save()
    return path


def make_material(name, texture_path, roughness_path, color):
    material = bpy.data.materials.get('Authored_'+name) or bpy.data.materials.new('Authored_'+name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links; nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial'); shader = nodes.new('ShaderNodeBsdfPrincipled')
    shader.inputs['Metallic'].default_value = SURFACES[name]['metallic']
    shader.inputs['Coat Weight'].default_value = SURFACES[name]['coat']
    shader.inputs['Coat Roughness'].default_value = .12
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = bpy.data.images.load(str(texture_path), check_existing=True)
    links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    roughness = nodes.new('ShaderNodeTexImage')
    roughness.image = bpy.data.images.load(str(roughness_path), check_existing=True)
    roughness.image.colorspace_settings.name = 'Non-Color'
    links.new(roughness.outputs['Color'], shader.inputs['Roughness'])
    links.new(shader.outputs['BSDF'], output.inputs['Surface']); material.diffuse_color = color
    return material


def create_materials(source, output):
    bpy.ops.wm.open_mainfile(filepath=str(source))
    textures, materials = {}, {}
    for name, color in PALETTE.items():
        texture = save_texture(output, name, color); roughness = save_texture(output, name, color, True)
        textures[name] = (texture, roughness)
        materials[name] = make_material(name, texture, roughness, color)
    objects = []
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        bpy.context.view_layer.objects.active = ob; ob.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.uv.smart_project(island_margin=.03)
        bpy.ops.object.mode_set(mode='OBJECT'); ob.select_set(False)
        name = ob.data.materials[0].name if ob.data.materials else 'Material'
        name = name if name in materials else 'Material'
        ob.data.materials.clear(); ob.data.materials.append(materials[name])
        ob['NPR_MATERIAL_ID'] = 'equipment_'+name
        objects.append({'name': ob.name, 'material_id': 'equipment_'+name})
    return textures, objects


def export_glb(path):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', export_apply=True)


def material_manifest(source, output, textures, objects):
    manifest = {
        'schema': 1, 'name': 'material_authored_v1', 'blender': bpy.app.version_string,
        'source_input': source.name, 'source_input_sha256': sha(source),
        'source': 'equipment_materials_v1.blend', 'glb': 'equipment_materials_v1.glb',
        'generator_sha256': sha(Path(__file__)), 'surfaces': SURFACES,
        'provenance': {'asset_owner': 'RoleNPR project authoring',
                       'generation': 'build_wardrobe_equipment.py; deterministic procedural samples',
                       'third_party_source': False, 'review_required_before_release': True,
                       'license_status': 'internal-authored-pending-review', 'redistribution': 'not-approved'},
        'textures': {}, 'objects': objects, 'default_disabled': True,
        'coordinate_system': 'Godot Y-up authored positions, Blender Z-up export',
    }
    for name, (path, roughness) in textures.items():
        manifest['textures'][name] = {
            'path': path.relative_to(output).as_posix(), 'sha256': sha(path), 'size': [64, 64],
            'color_space': 'sRGB base color',
            'roughness': {'path': roughness.relative_to(output).as_posix(), 'sha256': sha(roughness),
                          'color_space': 'linear', 'channel': 'R absolute roughness', 'size': [64, 64]},
        }
    manifest['source_sha256'] = sha(output/manifest['source'])
    manifest['glb_sha256'] = sha(output/manifest['glb'])
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, default=RECIPE)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    output = args.output.resolve() if args.output else host_root()/'.temp/equipment_bake'
    report = args.report.resolve() if args.report else output/'verification.json'
    if output.is_relative_to(ADDON):
        raise ValueError('Output must be outside the delivered addon')
    if report.is_relative_to(ADDON):
        raise ValueError('Report must be outside the delivered addon')
    source = load_input(args.recipe.resolve())
    if args.verify_only:
        verify_saved(output, report, source, args.recipe.resolve(), create_base, create_materials, export_part, export_glb, material_manifest)
        return
    data = create_base(); expected = geometry_snapshot()
    validate_source(source, expected)  # Preflight before writing any output.
    output.mkdir(parents=True, exist_ok=True)
    create_base(); bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'equipment.blend'))
    (output/'equipment.json').write_text(json.dumps(data, separators=(',', ':')), encoding='utf-8')
    textures, objects = create_materials(source, output)
    for image in bpy.data.images:
        if image.filepath and (Path(bpy.path.abspath(image.filepath)).resolve()).is_relative_to(output):
            image.filepath = '//'+Path(bpy.path.abspath(image.filepath)).resolve().relative_to(output).as_posix()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'equipment_materials_v1.blend'), relative_remap=False)
    export_glb(output/'equipment_materials_v1.glb')
    manifest = material_manifest(source, output, textures, objects)
    (output/'material_authored_v1.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    outputs = ['equipment.blend', 'equipment.json', 'equipment_materials_v1.blend',
               'equipment_materials_v1.glb', 'material_authored_v1.json']
    outputs += [path.relative_to(output).as_posix() for pair in textures.values() for path in pair]
    generation = {'schema': 1, 'generator': Path(__file__).name,
                  'scripts': {name: sha(Path(__file__).with_name(name)) for name in
                              ('build_wardrobe_equipment.py', 'verify_wardrobe_equipment.py')},
                  'input_recipe': args.recipe.name, 'input_recipe_sha256': sha(args.recipe),
                  'inputs': {'equipment': {'name': source.name, 'sha256': sha(source)}},
                  'blender_version': bpy.app.version_string, 'blender_commit': bpy.app.build_hash.decode(),
                  'outputs': {name: sha(output/name) for name in outputs},
                  'scope': 'Fixed sample four-slot merged geometry and nineteen independent material meshes'}
    (output/'equipment_generation.json').write_text(json.dumps(generation, indent=2)+'\n', encoding='utf-8')
    verify_saved(output, report, source, args.recipe.resolve(), create_base, create_materials, export_part, export_glb, material_manifest)
    print('EQUIPMENT_BUILD_OK', {key: len(row['indices'])//3 for key, row in data.items()})


if __name__ == '__main__':
    main()
