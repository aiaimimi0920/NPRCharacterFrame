"""Build rigid independent eyes fitted under the shared sliding eyelids.

blender --background --python-exit-code 1 --python build_wardrobe_eye.py --
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_wardrobe_eye import verify_saved

ADDON = Path(__file__).resolve().parents[2]
RECIPE = ADDON / 'samples/silver_wolf/import_sources/eye_bake_inputs.json'
SOURCE = Path('eye_authored_v1.blend')
GLB = Path('eye_authored_v1.glb')
MANIFEST = Path('eye_authored_v1.json')
LANDMARKS = {"EyeL": (-0.186, 2.509), "EyeR": (-0.039, 2.5205)}
IRIS = Path('eye_iris_v1.png')
SLOPE = 0.08
APERTURE = (0.0345, 0.019)
PROFILES = {}


def profile_at(prefix, x):
    rows=PROFILES[prefix[-1]]
    a,b=rows[0]['upper'][0],rows[-1]['upper'][0]
    u=max(0.,min(1.,(x-a)/(b-a)))*64
    i=min(63,int(u));f=u-i
    return {key:[rows[i][key][j]*(1-f)+rows[i+1][key][j]*f for j in range(3)] for key in ['upper','lower']}


def fitted_depth(prefix, x, y, behind):
    s=profile_at(prefix,x);a,b=s['upper'],s['lower']
    t=max(0.,min(1.,(a[1]-y)/max(a[1]-b[1],1e-7)))
    return a[2]*(1-t)+b[2]*t+.00035+4*min(.008,max(0.,a[1]-b[1])*.20)*t*(1-t)-behind


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def host_root():
    for parent in ADDON.parents:
        if (parent/'project.godot').is_file():
            return parent
    raise ValueError('No project.godot found; specify --output')


def load_inputs(recipe_path):
    recipe = json.loads(recipe_path.read_text(encoding='utf-8'))
    if recipe.get('schema') != 1 or set(recipe.get('files', {})) != {'rig', 'lids'}:
        raise ValueError('Expected schema 1 with rig/lids inputs')
    paths = {}
    for role, row in recipe['files'].items():
        relative = Path(row['path'])
        if relative.is_absolute():
            raise ValueError('Recipe paths must be relative')
        path = (recipe_path.parent/relative).resolve()
        if not path.is_relative_to(ADDON) or sha256(path) != row['sha256']:
            raise ValueError('Input identity or location mismatch: '+role)
        paths[role] = path
    data = json.loads(paths['lids'].read_text(encoding='utf-8'))
    if data.get('schema') != 2 or set(data.get('profiles', {})) != {'L', 'R'}:
        raise ValueError('Expected schema 2 with left/right lid profiles')
    for rows in data['profiles'].values():
        if not isinstance(rows, list) or len(rows) != 65:
            raise ValueError('Lid profiles require 65 samples')
        for row in rows:
            for key in ('upper', 'lower'):
                point = row.get(key, [])
                if len(point) != 3 or not all(type(v) in (int, float) and math.isfinite(v) for v in point):
                    raise ValueError('Lid profiles require finite positions')
            if abs(row['upper'][0]-row['lower'][0]) > 1e-6 or row['upper'][1] <= row['lower'][1]:
                raise ValueError('Lid upper/lower samples must share X and positive aperture')
        start, end = rows[0]['upper'][0], rows[-1]['upper'][0]
        if end <= start or any(rows[i]['upper'][0] <= rows[i-1]['upper'][0] for i in range(1, 65)):
            raise ValueError('Lid profile X must increase')
        if any(abs(row['upper'][0]-(start+(end-start)*i/64)) > 1e-6 for i, row in enumerate(rows)):
            raise ValueError('Lid profiles require uniform X sampling')
    return paths, data['profiles']


def xyz(point):
    return Vector((point[0], -point[2], point[1]))


def material(name, color, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


def surface_depth(tree, x, y):
    hit, _, _, _ = tree.ray_cast(xyz((x, y, 0.5)), xyz((0, 0, -1)), 1.0)
    if hit is None:
        raise ValueError(f"Eye landmark misses canonical face: {x}, {y}")
    return -hit.y


def iris_texture(output, write=True):
    """Deterministic painted radial fibers, limbal ring and corneal highlights."""
    size = 256
    image = bpy.data.images.new('eye_iris_v1', width=size, height=size, alpha=False)
    image.colorspace_settings.name = 'sRGB'
    pixels = []
    for y in range(size):
        for x in range(size):
            u, v = (x + .5) / size * 2 - 1, (y + .5) / size * 2 - 1
            radius, angle = math.hypot(u, v), math.atan2(v, u)
            fiber = .5 + .25 * math.sin(angle * 73 + radius * 18) + .25 * math.sin(angle * 119 - radius * 31)
            light = .55 + .45 * max(0, -v)
            ring = min(1, max(0, (1 - radius) / .11))
            color = [(base + amplitude * fiber) * light * (.27 + .73 * ring)
                     for base, amplitude in [(0.63,.07),(.59,.07),(.79,.09)]]
            rim = math.exp(-((radius - .40) / .07) ** 2) * .05
            color = [min(1, channel + rim) for channel in color]
            glint = max(math.exp(-(((u+.40)/.14)**2 + ((v-.35)/.11)**2)*2),
                        .7 * math.exp(-(((u-.34)/.055)**2 + ((v+.36)/.07)**2)*2))
            pixels.extend([channel*(1-glint) + glint for channel in color] + [1])
    image.pixels = pixels
    image.filepath_raw = str(output / IRIS)
    image.file_format = 'PNG'
    if write:
        image.save()
    return image


def patch(tree, prefix, part, center, rx, ry, offset, mat):
    """A curved disk sampled on the real face, never a protruding full sphere."""
    segments, rings = 48, 5
    points = [(0.0, 0.0)]
    for ring in range(1, rings + 1):
        for segment in range(segments):
            angle = segment * math.tau / segments
            points.append((rx * ring / rings * math.cos(angle),
                           ry * ring / rings * math.sin(angle)))
    faces = [(0, 1 + s, 1 + (s + 1) % segments) for s in range(segments)]
    for ring in range(rings - 1):
        a, b = 1 + ring * segments, 1 + (ring + 1) * segments
        for s in range(segments):
            n = (s + 1) % segments
            faces.append((a + s, b + s, b + n, a + n))
    if part in ['Sclera','TearFilm']:
        points=[(s['upper'][0]-center[0], s['upper'][1]*(1-r/8)+s['lower'][1]*r/8-center[1])
                for s in PROFILES[prefix[-1]] for r in range(9)]
        faces=[]
        for col in range(64):
            for row in range(8):
                a=col*9+row;b=a+9;c=a+1;d=b+1
                faces.extend([(a,c,b),(b,c,d)])
    vertices = []
    for x, y in points:
        if part not in ['Sclera','TearFilm']:
            y += SLOPE * x
        # All layers follow the shared lid shell with ordered inward clearance.
        depth = fitted_depth(prefix,center[0]+x,center[1]+y,offset)
        vertices.append(xyz((x, y, depth - center[2])))
    obj = mesh_object(prefix + "_" + part, center, vertices, faces, mat)
    uv = obj.data.uv_layers.new(name="EyeUV")
    for loop in obj.data.loops:
        x, y = points[loop.vertex_index]
        uv.data[loop.index].uv = (x / (2 * rx) + 0.5, y / (2 * ry) + 0.5)
    # Ocular surfaces are rigid during blink. Shared sliding lids occlude them.
    return obj


def mesh_object(name, center, vertices, faces, mat):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = xyz(center)
    obj.data.materials.append(mat)
    return obj


def create_scene(source, profiles, output, write_texture=True):
    global PROFILES
    PROFILES = profiles
    bpy.ops.wm.open_mainfile(filepath=str(source))
    face = bpy.data.objects.get('Face')
    if face is None or face.type != 'MESH' or len(face.data.vertices) != 3748 or not face.data.polygons:
        raise ValueError('Canonical Face topology missing or changed')
    if any(not math.isfinite(v) for point in face.data.vertices for v in face.matrix_world @ point.co):
        raise ValueError('Canonical Face requires finite world positions')
    tree = BVHTree.FromPolygons([face.matrix_world @ v.co for v in face.data.vertices],
                               [tuple(p.vertices) for p in face.data.polygons])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials = {
        "Sclera": material("Eye_Sclera", (0.76, 0.73, 0.79), 0.34),
        "Iris": material("Eye_Iris", (1.0, 1.0, 1.0), 0.30),
        "Pupil": material("Eye_Pupil", (0.007, 0.005, 0.016), 0.28),
        "TearFilm": material("Eye_TearFilm", (0.96, 0.98, 1.0), 0.06),
    }
    image = iris_texture(output, write=write_texture)
    node = materials['Iris'].node_tree.nodes.new('ShaderNodeTexImage')
    node.image = image
    materials['Iris'].node_tree.links.new(node.outputs['Color'],
        materials['Iris'].node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    objects, landmarks = [], {}
    for prefix, (cx, cy) in LANDMARKS.items():
        depths = [surface_depth(tree, cx + APERTURE[0] * math.cos(a),
                                cy + APERTURE[1] * math.sin(a) + SLOPE * APERTURE[0] * math.cos(a))
                  for a in (index * math.tau / 48 for index in range(48))]
        center = (cx, cy, max(depths) + 0.0005)
        landmarks[prefix] = {"center": center, "aperture": APERTURE, "bone": "head"}
        for part, rx, ry, offset in (("Sclera", *APERTURE, 0.0018),
                                     ("Iris", 0.021, 0.026, 0.0012),
                                     ("Pupil", 0.0045, 0.0075, 0.0007),
                                     ("TearFilm", *APERTURE, 0.00025)):
            objects.append(patch(tree, prefix, part, center, rx, ry, offset, materials[part]))
        # One shared eyelid/lash representation owns both eye modes.
    return objects, landmarks, materials


def export_glb(path):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB',
                             export_animations=False, export_morph=True)


def manifest_data(output, inputs, objects, landmarks, materials):
    return {
        'schema': 2, 'name': 'eye_authored_v1', 'blender': bpy.app.version_string,
        'source': SOURCE.as_posix(), 'glb': GLB.as_posix(), 'character_reference': inputs['rig'].name,
        'source_sha256': sha256(output/SOURCE), 'glb_sha256': sha256(output/GLB),
        'character_sha256': sha256(inputs['rig']), 'generator_sha256': sha256(Path(__file__)),
        'landmarks': landmarks, 'objects': [obj.name for obj in objects],
        'materials': [mat.name for mat in materials.values()], 'default_disabled': True,
        'coordinate_system': 'Godot Y-up authored positions, Blender Z-up export',
        'closure_shape': 'shared sliding lids; rigid ocular surfaces', 'depth_fit': 'lid_surface_v2 curved shell',
        'lid_source': inputs['lids'].name, 'lid_source_sha256': sha256(inputs['lids']),
        'max_envelope_offset_m': 0.004,
        'iris_texture': {'path': IRIS.as_posix(), 'sha256': sha256(output/IRIS),
                         'color_space': 'sRGB', 'size': [256, 256]},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, default=RECIPE)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    output = args.output.resolve() if args.output else host_root()/'.temp/eye_bake'
    report = args.report.resolve() if args.report else output/'verification.json'
    if output.is_relative_to(ADDON):
        raise ValueError('Output must be outside the delivered addon')
    if report.is_relative_to(ADDON):
        raise ValueError('Report must be outside the delivered addon')
    inputs, profiles = load_inputs(args.recipe.resolve())
    if args.verify_only:
        verify_saved(output, report, inputs, profiles, args.recipe.resolve(), create_scene, export_glb)
        return
    # Geometry and landmark ray checks run before any output directory is made.
    objects, landmarks, materials = create_scene(inputs['rig'], profiles, output, write_texture=False)
    output.mkdir(parents=True, exist_ok=True)
    bpy.data.images['eye_iris_v1'].save()
    bpy.data.images['eye_iris_v1'].filepath = '//'+IRIS.name
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output / SOURCE), relative_remap=False)
    export_glb(output/GLB)
    manifest = manifest_data(output, inputs, objects, landmarks, materials)
    (output / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    generation = {
        'schema': 1, 'generator': Path(__file__).name,
        'scripts': {name: sha256(Path(__file__).with_name(name)) for name in
                    ('build_wardrobe_eye.py', 'verify_wardrobe_eye.py')},
        'input_recipe': args.recipe.name, 'input_recipe_sha256': sha256(args.recipe),
        'inputs': {role: {'name': path.name, 'sha256': sha256(path)} for role, path in inputs.items()},
        'blender_version': bpy.app.version_string, 'blender_commit': bpy.app.build_hash.decode(),
        'outputs': {path.name: sha256(output/path) for path in (SOURCE, GLB, IRIS, MANIFEST)},
        'scope': 'Fixed sample rigid ocular surfaces and procedural sRGB iris; shared sliding lids are separate',
    }
    (output/'eye_generation.json').write_text(json.dumps(generation, indent=2)+'\n', encoding='utf-8')
    verify_saved(output, report, inputs, profiles, args.recipe.resolve(), create_scene, export_glb)
    print("EYE_AUTHORED_BUILD_OK", len(objects), "rigid ocular surfaces; shared sliding lids")


if __name__ == "__main__":
    main()
