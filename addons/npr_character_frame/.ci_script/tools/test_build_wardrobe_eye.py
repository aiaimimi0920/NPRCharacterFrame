"""Real Blender eye reconstruction and saved-source negative tests."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('build_wardrobe_eye.py')
ADDON = SCRIPT.parents[2]
ROOT = next(parent for parent in ADDON.parents if (parent/'project.godot').is_file())
RECIPE = ADDON/'samples/silver_wolf/import_sources/eye_bake_inputs.json'
BASE = ADDON/'samples/silver_wolf/assets/authoring/silver_wolf/wardrobe'
RUNTIME = ADDON/'samples/silver_wolf/assets/runtime'
AUTHOR_IRIS = RECIPE.parent/'eye_iris_v1.png'
SCRIPTS = ('build_wardrobe_eye.py', 'verify_wardrobe_eye.py')
METADATA = {'blender', 'source', 'glb', 'character_reference', 'source_sha256', 'glb_sha256',
            'backup_manifest_sha256', 'generator_sha256', 'lid_source'}
BLENDER = None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def runtime_fields(data):
    result = {key: value for key, value in data.items() if key not in METADATA}
    result['iris_texture'] = {key: value for key, value in result['iris_texture'].items() if key != 'path'}
    return result


def glb_content(path):
    data = path.read_bytes()
    if struct.unpack_from('<III', data) != (0x46546c67, 2, len(data)):
        raise ValueError('Invalid GLB header')
    size = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20+size])
    gltf.pop('asset')
    return gltf, data[28+size:]


def change_glb_node(path):
    data = path.read_bytes()
    size = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20+size]); gltf['nodes'][0]['translation'][0] += .01
    text = json.dumps(gltf, separators=(',', ':')).encode()
    text += b' '*((-len(text)) % 4)
    remaining = data[20+size:]
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 20+len(text)+len(remaining))
                     + struct.pack('<II', len(text), 0x4e4f534a)+text+remaining)


class EyeBakeTest(unittest.TestCase):
    def setUp(self):
        (ROOT/'.temp').mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='eye_bake_test_', dir=ROOT/'.temp')
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.host = self.work/'renamed_host'
        self.addon = self.host/'addons/npr_character_frame'
        self.host.mkdir()
        (self.host/'project.godot').write_text('config_version=5\n', encoding='utf-8')
        self.recipe = self.addon/RECIPE.relative_to(ADDON)
        self.script = self.addon/SCRIPT.relative_to(ADDON)
        sources = [SCRIPT.with_name(name) for name in SCRIPTS]+[RECIPE]
        sources.extend((RECIPE.parent/row['path']).resolve() for row in read_json(RECIPE)['files'].values())
        for source in sources:
            target = self.addon/source.relative_to(ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def run_blender(self, *args, expression=None, blend=None):
        command = [str(BLENDER), '--background']
        command += [str(blend)] if blend else ['--factory-startup']
        command += ['--python-exit-code', '1']
        command += ['--python-expr', expression] if expression else ['--python', str(self.script), '--', *map(str, args)]
        return subprocess.run(command, cwd=self.work, capture_output=True, text=True,
                              encoding='utf-8', errors='replace', timeout=180,
                              env={**os.environ, 'PYTHONOPTIMIZE': '1'})

    def success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)

    def reject(self, result, message, target):
        self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn(message, result.stdout+result.stderr)
        self.assertFalse(target.exists())

    def verify(self, output, report):
        result = self.run_blender('--output', output, '--verify-only', '--report', report)
        self.success(result)
        self.assertIn('EYE_SOURCE_OK', result.stdout)
        receipt = read_json(report)
        self.assertTrue(receipt['pass'] and receipt['glb_matches_saved_source'] and receipt['iris_path_relative'])
        self.assertTrue(receipt['glb_matches_reconstruction'])
        self.assertEqual((receipt['objects'], receipt['materials']), (8, 4))
        self.assertEqual(receipt['vertices'], {side+'_'+part: (585 if part in ('Sclera', 'TearFilm') else 241)
                                             for side in ('EyeL', 'EyeR') for part in ('Sclera', 'Iris', 'Pupil', 'TearFilm')})
        self.assertEqual(receipt['iris_size'], [256, 256])
        self.assertEqual(receipt['iris_color_space'], 'sRGB')
        self.assertEqual(receipt['saved_attribute_max_error'], 0.)
        self.assertEqual(receipt['outputs'], {name: digest(output/name) for name in
                                             ('eye_authored_v1.blend', 'eye_authored_v1.glb',
                                              'eye_iris_v1.png', 'eye_authored_v1.json')})

    def test_relocated_default_complete_reconstruction_repeat_and_portable_source(self):
        sources = {p: digest(p) for p in self.addon.rglob('*') if p.is_file()}
        self.success(self.run_blender())
        output = self.host/'.temp/eye_bake'
        self.assertEqual(runtime_fields(read_json(output/'eye_authored_v1.json')),
                         runtime_fields(read_json(BASE/'eye_authored_v1.json')))
        self.assertEqual(glb_content(output/'eye_authored_v1.glb'), glb_content(RUNTIME/'eye_authored_v1.glb'))
        self.assertIn((output/'eye_iris_v1.png').read_bytes(), glb_content(output/'eye_authored_v1.glb')[1])
        self.assertEqual((output/'eye_iris_v1.png').read_bytes(), AUTHOR_IRIS.read_bytes())
        generation = read_json(output/'eye_generation.json')
        self.assertEqual(generation['scripts'], {name: digest(self.script.with_name(name)) for name in SCRIPTS})
        self.assertEqual(generation['input_recipe_sha256'], digest(self.recipe))
        for role, row in read_json(self.recipe)['files'].items():
            p = (self.recipe.parent/row['path']).resolve()
            self.assertEqual(generation['inputs'][role], {'name': p.name, 'sha256': digest(p)})
        self.assertNotIn('backup_manifest_sha256', read_json(output/'eye_authored_v1.json'))
        self.assertNotIn(str(self.host), json.dumps(generation)+json.dumps(read_json(output/'eye_authored_v1.json')))
        self.verify(output, self.work/'verified.json')
        repeated = self.work/'repeat'
        self.success(self.run_blender('--output', repeated))
        for name in ('eye_authored_v1.glb', 'eye_iris_v1.png'):
            self.assertEqual((output/name).read_bytes(), (repeated/name).read_bytes())
        self.assertEqual(runtime_fields(read_json(output/'eye_authored_v1.json')),
                         runtime_fields(read_json(repeated/'eye_authored_v1.json')))
        self.verify(repeated, self.work/'repeat_verified.json')
        moved = self.work/'moved_source'
        shutil.copytree(output, moved)
        self.verify(moved, self.work/'moved_verified.json')
        for p, identity in sources.items():
            self.assertEqual(digest(p), identity, str(p))

    def test_input_identity_missing_files_and_path_rejection(self):
        original = read_json(self.recipe)
        cases = []
        for role in original['files']:
            recipe = read_json(self.recipe); recipe['files'][role]['sha256'] = '0'*64
            cases.append(('identity_'+role, recipe, 'Input identity'))
            recipe = read_json(self.recipe); recipe['files'][role]['path'] = 'missing_'+role
            cases.append(('missing_'+role, recipe, 'FileNotFoundError'))
        recipe = read_json(self.recipe); recipe['schema'] = 2
        cases.append(('schema', recipe, 'Expected schema 1'))
        source = (self.recipe.parent/original['files']['lids']['path']).resolve()
        recipe = read_json(self.recipe); recipe['files']['lids']['path'] = str(source)
        cases.append(('absolute', recipe, 'paths must be relative'))
        outside = self.work/'outside.json'; shutil.copy2(source, outside)
        recipe = read_json(self.recipe); recipe['files']['lids']['path'] = os.path.relpath(outside, self.recipe.parent)
        cases.append(('escape', recipe, 'Input identity or location'))
        for name, recipe, message in cases:
            with self.subTest(name=name):
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
                output = self.work/name
                self.reject(self.run_blender('--output', output), message, output)

    def test_invalid_profiles_and_actual_rig_rejected_with_updated_hashes(self):
        recipe = read_json(self.recipe)
        lids = (self.recipe.parent/recipe['files']['lids']['path']).resolve()
        original = lids.read_text(encoding='utf-8')
        for name, mutate, message in [
            ('schema', lambda p: p.__setitem__('schema', 3), 'Expected schema 2'),
            ('count', lambda p: p['profiles']['L'].pop(), '65 samples'),
            ('nan', lambda p: p['profiles']['R'][1]['upper'].__setitem__(2, float('nan')), 'finite positions'),
            ('x', lambda p: p['profiles']['L'][2]['upper'].__setitem__(0, p['profiles']['L'][1]['upper'][0]), 'share X'),
            ('uniform', lambda p: [p['profiles']['L'][2][key].__setitem__(0, p['profiles']['L'][2][key][0]+.0001)
                                  for key in ('upper', 'lower')], 'uniform X sampling'),
            ('aperture', lambda p: p['profiles']['R'][1].__setitem__('lower', p['profiles']['R'][1]['upper']), 'positive aperture'),
        ]:
            with self.subTest(name=name):
                data = json.loads(original); mutate(data)
                lids.write_text(json.dumps(data), encoding='utf-8')
                recipe['files']['lids']['sha256'] = digest(lids)
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
                output = self.work/name
                self.reject(self.run_blender('--output', output), message, output)
        lids.write_text(original, encoding='utf-8')
        recipe['files']['lids']['sha256'] = digest(lids)
        rig = (self.recipe.parent/recipe['files']['rig']['path']).resolve()
        expression = ("import bpy; bpy.data.objects['Face'].name='NotFace'; "
                      "bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)")
        self.success(self.run_blender(expression=expression, blend=rig))
        recipe['files']['rig']['sha256'] = digest(rig)
        self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
        output = self.work/'rig'
        self.reject(self.run_blender('--output', output), 'Canonical Face topology', output)

    def test_saved_geometry_material_export_texture_and_delivery_writes_rejected(self):
        output = self.work/'candidate'
        self.success(self.run_blender('--output', output))
        manifest_path = output/'eye_authored_v1.json'; generation_path = output/'eye_generation.json'
        manifest = read_json(manifest_path); generation = read_json(generation_path)
        originals = {name: (output/name).read_bytes() for name in generation['outputs']}

        def update_identities():
            manifest['source_sha256'] = digest(output/'eye_authored_v1.blend')
            manifest['glb_sha256'] = digest(output/'eye_authored_v1.glb')
            manifest['iris_texture']['sha256'] = digest(output/'eye_iris_v1.png')
            manifest_path.write_text(json.dumps(manifest), encoding='utf-8')
            generation['outputs'] = {name: digest(output/name) for name in generation['outputs']}
            generation_path.write_text(json.dumps(generation), encoding='utf-8')

        def restore():
            for name, contents in originals.items():
                (output/name).write_bytes(contents)
            update_identities()

        for name, expression in [
            ('geometry', "bpy.data.objects['EyeL_Iris'].data.vertices[0].co.x += .01"),
            ('material', "bpy.data.materials['Eye_Sclera'].node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9"),
        ]:
            with self.subTest(name=name):
                restore()
                code = ('import bpy; '+expression+'; bpy.context.preferences.filepaths.save_version=0; '
                        'bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)')
                self.success(self.run_blender(expression=code, blend=output/'eye_authored_v1.blend'))
                update_identities()
                report = self.work/(name+'_receipt.json')
                self.reject(self.run_blender('--output', output, '--verify-only', '--report', report),
                            'Saved eye geometry or materials changed', report)
        restore()
        code = ("import bpy; bpy.data.materials['Eye_Pupil'].node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=.7; "
                "bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath); "
                "bpy.ops.object.select_all(action='SELECT'); bpy.ops.export_scene.gltf(filepath=bpy.path.abspath('//eye_authored_v1.glb'), "
                "export_format='GLB', export_animations=False, export_morph=True)")
        self.success(self.run_blender(expression=code, blend=output/'eye_authored_v1.blend'))
        update_identities()
        report = self.work/'matched_material_glb_receipt.json'
        self.reject(self.run_blender('--output', output, '--verify-only', '--report', report),
                    'GLB and rebuilt eye inputs differ', report)
        restore(); change_glb_node(output/'eye_authored_v1.glb'); update_identities()
        report = self.work/'glb_receipt.json'
        self.reject(self.run_blender('--output', output, '--verify-only', '--report', report),
                    'GLB and saved eye source differ', report)
        restore(); png = output/'eye_iris_v1.png'; png.write_bytes(png.read_bytes()+b'corruption'); update_identities()
        report = self.work/'texture_receipt.json'
        self.reject(self.run_blender('--output', output, '--verify-only', '--report', report),
                    'Procedural iris texture changed', report)
        restore(); glb = output/'eye_authored_v1.glb'; glb.write_bytes(glb.read_bytes()+b'corruption')
        report = self.work/'identity_receipt.json'
        self.reject(self.run_blender('--output', output, '--verify-only', '--report', report),
                    'Generated output identity changed', report)
        target = self.addon/'rejected_output'
        self.reject(self.run_blender('--output', target), 'Output must be outside', target)
        target = self.addon/'rejected_report.json'
        self.reject(self.run_blender('--output', output, '--verify-only', '--report', target),
                    'Report must be outside', target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blender', default=os.environ.get('BLENDER_EXECUTABLE') or shutil.which('blender'))
    args, remaining = parser.parse_known_args()
    if not args.blender or not Path(args.blender).is_file():
        parser.error('Pass --blender <executable>, set BLENDER_EXECUTABLE, or put blender on PATH')
    BLENDER = Path(args.blender).resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
