"""Real Blender bake tests; select CLI with --blender, BLENDER_EXECUTABLE or PATH."""

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


SCRIPT = Path(__file__).with_name('build_wardrobe_hair_dynamic.py')
ADDON = SCRIPT.parents[2]
ROOT = next(parent for parent in ADDON.parents if (parent/'project.godot').is_file())
BASE = ADDON/'samples/silver_wolf/assets/authoring/silver_wolf/wardrobe'
RECIPE = ADDON/'samples/silver_wolf/import_sources/hair_dynamic_bake_inputs.json'
GLB = ADDON/'samples/silver_wolf/assets/runtime/hair_dynamic_v1.glb'
METADATA = {'motion_profile', 'blender', 'source', 'glb', 'source_sha256', 'glb_sha256',
            'generator_sha256', 'canonical_source_sha256', 'backup_manifest_sha256'}
BLENDER = None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def runtime_fields(data):
    return {key: value for key, value in data.items() if key not in METADATA}


def glb_content(path):
    data = path.read_bytes()
    if struct.unpack_from('<III', data) != (0x46546c67, 2, len(data)):
        raise ValueError('Invalid glTF 2 binary')
    offset, chunks = 12, {}
    while offset < len(data):
        size, kind = struct.unpack_from('<II', data, offset)
        offset += 8
        chunks[kind] = data[offset:offset+size]
        offset += size
    if offset != len(data):
        raise ValueError('Invalid GLB chunk lengths')
    gltf = json.loads(chunks[0x4e4f534a])
    # Exporter/version labels do not alter the asset's geometry, skin or images.
    gltf.pop('asset')
    return gltf, chunks[0x004e4942]


class HairDynamicBakeTest(unittest.TestCase):
    def setUp(self):
        (ROOT/'.temp').mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='hair_dynamic_test_', dir=ROOT/'.temp')
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.host = self.work/'renamed_host'
        self.addon = self.host/'addons/npr_character_frame'
        self.host.mkdir()
        (self.host/'project.godot').write_text('config_version=5\n', encoding='utf-8')
        self.recipe = self.addon/RECIPE.relative_to(ADDON)
        self.script = self.addon/SCRIPT.relative_to(ADDON)
        sources = [SCRIPT, RECIPE]
        sources.extend((RECIPE.parent/row['path']).resolve() for row in read_json(RECIPE)['files'].values())
        for source in sources:
            target = self.addon/source.relative_to(ADDON)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def run_blender(self, *args):
        return subprocess.run(
            [str(BLENDER), '--background', '--factory-startup', '--python-exit-code', '1',
             '--python', str(self.script), '--', *map(str, args)],
            cwd=self.work, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180,
            env={**os.environ, 'PYTHONOPTIMIZE': '1'},
        )

    def require_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)

    def require_rejection(self, result, message, output=None):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stdout+result.stderr)
        if output:
            self.assertFalse(output.exists())

    def verify(self, output, report):
        result = self.run_blender('--output', output, '--verify-only', '--report', report)
        self.require_success(result)
        self.assertIn('HAIR_DYNAMIC_SOURCE_OK', result.stdout)
        receipt = read_json(report)
        authored = read_json(BASE/'hair_dynamic_v1.json')
        self.assertTrue(receipt['pass'])
        self.assertEqual(receipt['vertices'], {'Body': authored['source_vertices']['0'],
                                             'Hair': authored['source_vertices']['2']})
        self.assertEqual(receipt['bones'], 16+len(authored['bones']))
        self.assertEqual(receipt['chains'], len(authored['chains']))
        self.assertEqual(receipt['glb_meshes'], 2)
        self.assertLessEqual(receipt['rest_max_error'], 2e-6)
        self.assertEqual(receipt['uv_max_error'], 0)
        self.assertLessEqual(receipt['weight_max_error'], 2e-6)
        self.assertTrue(all(abs(total-1) <= 2e-6 for total in receipt['weight_sum_range']))
        self.assertEqual(receipt['outputs'], {name: digest(output/name) for name in
                                             ('hair_dynamic_v1.blend', 'hair_dynamic_v1.glb', 'hair_dynamic_v1.json')})

    def test_relocated_default_bake_and_complete_data_reconstruction(self):
        sources = {path: digest(path) for path in self.addon.rglob('*') if path.is_file()}
        result = self.run_blender()
        self.require_success(result)
        self.assertIn('HAIR_DYNAMIC_BUILD_OK', result.stdout)
        output = self.host/'.temp/hair_dynamic_bake'
        bridge = read_json(output/'hair_dynamic_v1.json')
        self.assertEqual(runtime_fields(bridge), runtime_fields(read_json(BASE/'hair_dynamic_v1.json')))
        self.assertEqual(glb_content(output/'hair_dynamic_v1.glb'), glb_content(GLB))
        recipe = read_json(self.recipe)
        generation = read_json(output/'hair_dynamic_generation.json')
        self.assertEqual(generation['generator_sha256'], digest(self.script))
        self.assertEqual(generation['input_recipe_sha256'], digest(self.recipe))
        self.assertEqual(bridge['canonical_source_sha256'], recipe['files']['rig']['sha256'])
        self.assertNotEqual(bridge['canonical_source_sha256'], recipe['historical_input_blend_sha256'])
        self.assertEqual(generation['historical_input_blend_sha256'], recipe['historical_input_blend_sha256'])
        self.assertNotIn('backup_manifest_sha256', bridge)
        for role, row in recipe['files'].items():
            path = (self.recipe.parent/row['path']).resolve()
            self.assertEqual(generation['inputs'][role], {'name': path.name, 'sha256': digest(path)})
        self.assertEqual(bridge['motion_profile'], 'hair_motion_profile_v1.json')
        self.assertEqual(bridge['motion_profile_sha256'], recipe['files']['profile']['sha256'])
        self.assertEqual(bridge['source'], 'hair_dynamic_v1.blend')
        self.assertEqual(bridge['glb'], 'hair_dynamic_v1.glb')
        self.assertEqual(bridge['source_sha256'], digest(output/'hair_dynamic_v1.blend'))
        self.assertEqual(bridge['glb_sha256'], digest(output/'hair_dynamic_v1.glb'))
        self.assertNotIn(str(self.host), json.dumps(bridge)+json.dumps(generation))
        self.verify(output, self.work/'verified.json')
        repeated = self.work/'repeat'
        self.require_success(self.run_blender('--output', repeated))
        self.assertEqual(runtime_fields(read_json(repeated/'hair_dynamic_v1.json')), runtime_fields(bridge))
        self.assertEqual(glb_content(repeated/'hair_dynamic_v1.glb'), glb_content(output/'hair_dynamic_v1.glb'))
        self.verify(repeated, self.work/'repeat_verified.json')
        for path, sha in sources.items():
            self.assertEqual(digest(path), sha, str(path))

    def test_bad_input_identity_missing_files_and_paths_do_not_create_output(self):
        cases = []
        for role in read_json(self.recipe)['files']:
            data = read_json(self.recipe)
            data['files'][role]['sha256'] = '0'*64
            cases.append(('identity_'+role, data, 'Input identity'))
            data = read_json(self.recipe)
            data['files'][role]['path'] = 'missing_'+role
            cases.append(('missing_'+role, data, 'FileNotFoundError'))
        data = read_json(self.recipe)
        data['schema'] = 2
        cases.append(('schema', data, 'Expected schema 1'))
        data = read_json(self.recipe)
        data.pop('head_bvh_origin')
        cases.append(('origin_missing', data, 'Head BVH origin'))
        for name, value in [('null', None), ('short', [0, 0]), ('boolean', [False, 0, 0]),
                            ('nan', [0, float('nan'), 0]), ('infinite', [0, 0, float('inf')])]:
            data = read_json(self.recipe)
            data['head_bvh_origin'] = value
            cases.append(('origin_'+name, data, 'Head BVH origin'))
        rig = (self.recipe.parent/'character_rig.blend').resolve()
        data = read_json(self.recipe)
        data['files']['rig']['path'] = str(rig)
        cases.append(('absolute', data, 'paths must be relative'))
        outside = self.work/'outside.blend'
        shutil.copy2(rig, outside)
        data = read_json(self.recipe)
        data['files']['rig']['path'] = os.path.relpath(outside, self.recipe.parent)
        cases.append(('escape', data, 'Input identity or location'))
        for name, recipe, message in cases:
            with self.subTest(name=name):
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
                output = self.work/name
                self.require_rejection(self.run_blender('--output', output), message, output)

    def test_alternate_bvh_origin_changes_only_the_runtime_calibration(self):
        recipe = read_json(self.recipe)
        recipe['head_bvh_origin'] = [3.25, -4.5, 2.0]
        self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
        output = self.work/'alternate_origin'
        self.require_success(self.run_blender('--output', output))
        bridge = read_json(output/'hair_dynamic_v1.json')
        self.assertEqual(bridge['head_surface']['bvh_origin'], recipe['head_bvh_origin'])
        expected = runtime_fields(read_json(BASE/'hair_dynamic_v1.json'))
        expected['head_surface']['bvh_origin'] = recipe['head_bvh_origin']
        self.assertEqual(runtime_fields(bridge), expected)
        self.assertEqual(glb_content(output/'hair_dynamic_v1.glb'), glb_content(GLB))
        self.verify(output, self.work/'alternate_verified.json')

    def test_invalid_calibration_rejected_even_with_matching_input_hash(self):
        recipe = read_json(self.recipe)
        profile_path = (self.recipe.parent/recipe['files']['profile']['path']).resolve()
        original = profile_path.read_text(encoding='utf-8')
        cases = []
        profile = json.loads(original)
        profile['canonical_source_sha256'] = '0'*64
        cases.append(('history', profile, 'Historical motion profile identity'))
        profile = json.loads(original)
        profile['static_zones'][0]['vertices'].pop()
        cases.append(('static', profile, 'Static zone no longer matches'))
        profile = json.loads(original)
        profile['chains']['ponytail']['curve'][1] = profile['chains']['ponytail']['curve'][0]
        cases.append(('curve', profile, 'distinct finite points'))
        profile = json.loads(original)
        profile['chains']['ponytail']['weight_curve'][1][1] = 2
        cases.append(('weight_curve', profile, 'Invalid motion weight curve'))
        profile = json.loads(original)
        profile['chains']['ponytail']['pinned_nodes'] = [1]
        cases.append(('pins', profile, 'consecutive root prefix'))
        for value in (float('nan'), -1):
            profile = json.loads(original)
            profile['chains']['ponytail']['max_offset'][1] = value
            cases.append(('offset_'+str(value), profile, 'finite nonnegative values'))
        for name, profile, message in cases:
            with self.subTest(name=name):
                profile_path.write_text(json.dumps(profile), encoding='utf-8')
                recipe['files']['profile']['sha256'] = digest(profile_path)
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8')
                output = self.work/name
                self.require_rejection(self.run_blender('--output', output), message, output)

    def test_saved_skin_output_corruption_and_delivery_writes_are_rejected(self):
        output = self.work/'candidate'
        self.require_success(self.run_blender('--output', output))
        bridge_path = output/'hair_dynamic_v1.json'
        generation_path = output/'hair_dynamic_generation.json'
        original = read_json(bridge_path)
        generation = read_json(generation_path)
        cases = []
        bridge = read_json(bridge_path)
        bridge['weights']['0'][0][1] = [[0, 1.0]]
        cases.append(('weight_mismatch', bridge, 'Saved skin weights and bridge differ'))
        bridge = read_json(bridge_path)
        bridge['source_vertices']['0'] -= 1
        cases.append(('count', bridge, 'Saved canonical topology, vertex count or UVs changed'))
        bridge = read_json(bridge_path)
        bridge['head_surface']['bvh_origin'][0] += 1
        cases.append(('origin', bridge, 'Saved head BVH origin differs from recipe'))
        for name, bridge, message in cases:
            with self.subTest(name=name):
                bridge_path.write_text(json.dumps(bridge), encoding='utf-8')
                generation['outputs'][bridge_path.name] = digest(bridge_path)
                generation_path.write_text(json.dumps(generation), encoding='utf-8')
                report = self.work/(name+'_receipt.json')
                self.require_rejection(self.run_blender('--output', output, '--verify-only', '--report', report),
                                       message, report)
        bridge_path.write_text(json.dumps(original), encoding='utf-8')
        generation['outputs'][bridge_path.name] = digest(bridge_path)
        generation_path.write_text(json.dumps(generation), encoding='utf-8')
        glb_path = output/'hair_dynamic_v1.glb'
        glb_path.write_bytes(glb_path.read_bytes()+b'corruption')
        report = self.work/'corrupt_receipt.json'
        self.require_rejection(self.run_blender('--output', output, '--verify-only', '--report', report),
                               'Generated output identity changed', report)
        target = self.addon/'rejected_output'
        self.require_rejection(self.run_blender('--output', target), 'Output must be outside', target)
        target = self.addon/'rejected_report.json'
        self.require_rejection(self.run_blender('--output', output, '--verify-only', '--report', target),
                               'Report must be outside', target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blender', default=os.environ.get('BLENDER_EXECUTABLE') or shutil.which('blender'))
    args, remaining = parser.parse_known_args()
    if not args.blender or not Path(args.blender).is_file():
        parser.error('Pass --blender <executable>, set BLENDER_EXECUTABLE, or put blender on PATH')
    BLENDER = Path(args.blender).resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
