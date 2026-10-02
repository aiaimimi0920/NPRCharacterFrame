"""Real Blender reconstruction/negative tests; no development-machine paths."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('build_wardrobe_rig.py')
ADDON = SCRIPT.parents[2]
ROOT = next(parent for parent in ADDON.parents if (parent/'project.godot').is_file())
RECIPE = ADDON/'samples/silver_wolf/import_sources/performance_bake_inputs.json'
BASE = ADDON/'samples/silver_wolf/assets/authoring/silver_wolf/wardrobe'
SCRIPTS = ('build_wardrobe_rig.py', 'build_wardrobe_lid_surface.py',
           'wardrobe_blink_domain.py', 'verify_wardrobe_rig.py')
BLENDER = None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


class PerformanceBakeTest(unittest.TestCase):
    def setUp(self):
        (ROOT/'.temp').mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='performance_test_', dir=ROOT/'.temp')
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.host = self.work/'renamed_host'
        self.addon = self.host/'addons/npr_character_frame'
        self.host.mkdir()
        (self.host/'project.godot').write_text('config_version=5\n', encoding='utf-8')
        self.recipe = self.addon/RECIPE.relative_to(ADDON)
        self.script = self.addon/SCRIPT.relative_to(ADDON)
        sources = [SCRIPT.with_name(name) for name in SCRIPTS] + [RECIPE]
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
        self.assertIn('PERFORMANCE_SOURCE_OK', result.stdout)
        receipt = read_json(report)
        self.assertTrue(receipt['pass'])
        self.assertEqual(receipt['vertices'], {'Body': 21273, 'Face': 3748, 'Hair': 4151,
                                             **{'SlidingLid_'+side+'_'+lid+'Lid': 585
                                                for side in ('L', 'R') for lid in ('Upper', 'Lower')}})
        self.assertEqual((receipt['bones'], receipt['face_shapes'], receipt['actions'],
                          receipt['sampled_frames_per_action']), (16, 12, 4, 121))
        for metric in ('rest_max_error', 'shape_max_error', 'bone_rest_max_error'):
            self.assertLessEqual(receipt[metric], 3e-7)
        for metric in ('uv_max_error', 'weight_max_error', 'action_max_error'):
            self.assertLessEqual(receipt[metric], 1e-7)
        self.assertTrue(all(abs(total-1) <= 2e-6 for total in receipt['weight_sum_range']))
        self.assertEqual(receipt['outputs'], {name: digest(output/name) for name in
                                             ('character_rig.blend', 'performance.json', 'lid_surface_v2.json')})

    def test_relocated_default_complete_reconstruction_and_repeated_bake(self):
        sources = {p: digest(p) for p in self.addon.rglob('*') if p.is_file()}
        self.success(self.run_blender())
        output = self.host/'.temp/performance_bake'
        self.assertEqual(read_json(output/'performance.json'), read_json(BASE/'performance.json'))
        lids = read_json(output/'lid_surface_v2.json')
        reference = read_json(BASE/'lid_surface_v2.json')
        lids['authoring'].pop('generator'); reference['authoring'].pop('generator')
        self.assertEqual(lids, reference)
        generation = read_json(output/'performance_generation.json')
        self.assertEqual(generation['scripts'], {name: digest(self.script.with_name(name)) for name in SCRIPTS})
        self.assertEqual(generation['input_recipe_sha256'], digest(self.recipe))
        for role, row in read_json(self.recipe)['files'].items():
            p = (self.recipe.parent/row['path']).resolve()
            self.assertEqual(generation['inputs'][role], {'name': p.name, 'sha256': digest(p)})
        self.assertNotIn(str(self.host), json.dumps(generation))
        self.assertNotEqual(lids['authoring']['probe_sha256'], generation['inputs']['probe']['sha256'])
        self.verify(output, self.work/'verified.json')
        repeated = self.work/'repeat'
        self.success(self.run_blender('--output', repeated))
        for name in ('performance.json', 'lid_surface_v2.json'):
            self.assertEqual((output/name).read_bytes(), (repeated/name).read_bytes())
        self.verify(repeated, self.work/'repeat_verified.json')
        for p, identity in sources.items():
            self.assertEqual(digest(p), identity, str(p))

    def test_input_identity_missing_and_path_rejection(self):
        original = read_json(self.recipe)
        cases = []
        for role in original['files']:
            recipe = read_json(self.recipe); recipe['files'][role]['sha256'] = '0'*64
            cases.append(('identity_'+role, recipe, 'Input identity'))
            recipe = read_json(self.recipe); recipe['files'][role]['path'] = 'missing_'+role
            cases.append(('missing_'+role, recipe, 'FileNotFoundError'))
        recipe = read_json(self.recipe); recipe['schema'] = 2
        cases.append(('schema', recipe, 'Expected schema 1'))
        source = (self.recipe.parent/original['files']['layout']['path']).resolve()
        recipe = read_json(self.recipe); recipe['files']['layout']['path'] = str(source)
        cases.append(('absolute', recipe, 'paths must be relative'))
        outside = self.work/'outside.json'; shutil.copy2(source, outside)
        recipe = read_json(self.recipe); recipe['files']['layout']['path'] = os.path.relpath(outside, self.recipe.parent)
        cases.append(('escape', recipe, 'Input identity or location'))
        for name, recipe, message in cases:
            with self.subTest(name=name):
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
                output = self.work/name
                self.reject(self.run_blender('--output', output), message, output)

    def test_invalid_geometry_and_layout_rejected_with_updated_hashes(self):
        recipe = read_json(self.recipe)
        paths = {role: (self.recipe.parent/row['path']).resolve() for role, row in recipe['files'].items()}
        originals = {role: path.read_text(encoding='utf-8') for role, path in paths.items()}
        cases = []
        for name, mutate, message in [
            ('nan', lambda p: p['meshes'][0]['positions'][0].__setitem__(0, float('nan')), 'finite positions'),
            ('index', lambda p: p['meshes'][0]['indices'].__setitem__(0, .5), 'integer triangle'),
            ('uv', lambda p: p['meshes'][0]['uv'].pop(), 'matching UVs'),
            ('order', lambda p: p['meshes'].reverse(), 'mesh order changed'),
            ('topology', lambda p: p['meshes'][1].__setitem__('indices', [0, 1, 2]), 'skin topology changed'),
        ]:
            data = json.loads(originals['probe']); mutate(data)
            cases.append((name, 'probe', data, message))
        for name, mutate, message in [
            ('parent', lambda p: p['bones'][0].__setitem__('parent', 'head'), 'parents must precede'),
            ('zero', lambda p: p['bones'][0].__setitem__('tail', p['bones'][0]['head']), 'zero-length'),
            ('bone', lambda p: p['bones'][0].__setitem__('name', 'invalid'), 'canonical schema 1'),
        ]:
            data = json.loads(originals['layout']); mutate(data)
            cases.append((name, 'layout', data, message))
        for name, role, data, message in cases:
            with self.subTest(name=name):
                for key, path in paths.items():
                    path.write_text(originals[key], encoding='utf-8')
                paths[role].write_text(json.dumps(data), encoding='utf-8')
                for key, path in paths.items():
                    recipe['files'][key]['sha256'] = digest(path)
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
                output = self.work/name
                self.reject(self.run_blender('--output', output), message, output)

    def test_output_and_saved_source_inconsistencies_and_addon_writes_rejected(self):
        output = self.work/'candidate'
        self.success(self.run_blender('--output', output))
        bridge_path = output/'performance.json'; generation_path = output/'performance_generation.json'
        original = bridge_path.read_bytes(); generation = read_json(generation_path)
        cases = []
        for name, mutate, message in [
            ('weight', lambda p: p['weights'][0].__setitem__(0, [[0, 1.]]), 'Saved skin weights and bridge differ'),
            ('shape', lambda p: p['shapes']['aa'][0].__setitem__(1, .1), 'Saved Shape Keys and bridge differ'),
            ('action', lambda p: p['actions']['greeting']['frames'][60][8].__setitem__(3, .1), 'Saved actions and bridge differ'),
        ]:
            data = json.loads(original); mutate(data); cases.append((name, data, message))
        for name, data, message in cases:
            with self.subTest(name=name):
                bridge_path.write_text(json.dumps(data), encoding='utf-8')
                generation['outputs'][bridge_path.name] = digest(bridge_path)
                generation_path.write_text(json.dumps(generation), encoding='utf-8')
                report = self.work/(name+'_receipt.json')
                self.reject(self.run_blender('--output', output, '--verify-only', '--report', report), message, report)
        bridge_path.write_bytes(original)
        generation['outputs'][bridge_path.name] = digest(bridge_path)
        blend = output/'character_rig.blend'
        expression = ("import bpy; bpy.data.objects['Face'].data.shape_keys.key_blocks['aa'].data[0].co.x += .02; "
                      "bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)")
        self.success(self.run_blender(expression=expression, blend=blend))
        generation['outputs'][blend.name] = digest(blend)
        generation_path.write_text(json.dumps(generation), encoding='utf-8')
        report = self.work/'saved_shape_receipt.json'
        self.reject(self.run_blender('--output', output, '--verify-only', '--report', report),
                    'Saved Shape Keys and bridge differ', report)
        blend.write_bytes(blend.read_bytes()+b'corruption')
        report = self.work/'corrupt_receipt.json'
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
