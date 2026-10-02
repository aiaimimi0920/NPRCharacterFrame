"""Real Blender tests for both equipment paths and portable authoring output."""

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

SCRIPT = Path(__file__).with_name('build_wardrobe_equipment.py')
ADDON = SCRIPT.parents[2]
ROOT = next(p for p in ADDON.parents if (p/'project.godot').is_file())
RECIPE = ADDON/'samples/silver_wolf/import_sources/equipment_bake_inputs.json'
BASE = ADDON/'samples/silver_wolf/assets/authoring/silver_wolf/wardrobe'
GLB = ADDON/'samples/silver_wolf/assets/runtime/equipment_materials_v1.glb'
SCRIPTS = ('build_wardrobe_equipment.py', 'verify_wardrobe_equipment.py')
BLENDER = None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def material_fields(data):
    skip = {'blender', 'source_input', 'source', 'glb', 'source_sha256', 'glb_sha256',
            'generator_sha256', 'backup_manifest_sha256'}
    result = {key: value for key, value in data.items() if key not in skip}
    result['provenance'] = {key: value for key, value in result['provenance'].items() if key != 'generation'}
    for row in result['textures'].values():
        row['path'] = Path(row['path']).name; row['roughness']['path'] = Path(row['roughness']['path']).name
    return result


def glb_content(path):
    data = path.read_bytes()
    if struct.unpack_from('<III', data) != (0x46546c67, 2, len(data)):
        raise ValueError('Invalid GLB header')
    size = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20+size]); gltf.pop('asset')
    return gltf, data[28+size:]


class EquipmentBakeTest(unittest.TestCase):
    def setUp(self):
        (ROOT/'.temp').mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='equipment_bake_test_', dir=ROOT/'.temp')
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name); self.host = self.work/'renamed_host'
        self.addon = self.host/'addons/npr_character_frame'; self.host.mkdir()
        (self.host/'project.godot').write_text('config_version=5\n', encoding='utf-8')
        self.script = self.addon/SCRIPT.relative_to(ADDON); self.recipe = self.addon/RECIPE.relative_to(ADDON)
        sources = [SCRIPT.with_name(name) for name in SCRIPTS]+[RECIPE]
        sources.extend((RECIPE.parent/row['path']).resolve() for row in read_json(RECIPE)['files'].values())
        for source in sources:
            target = self.addon/source.relative_to(ADDON); target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def run_blender(self, *args, expression=None, blend=None):
        command = [str(BLENDER), '--background']+([str(blend)] if blend else ['--factory-startup'])
        command += ['--python-exit-code', '1']
        command += ['--python-expr', expression] if expression else ['--python', str(self.script), '--', *map(str, args)]
        return subprocess.run(command, cwd=self.work, capture_output=True, text=True,
                              encoding='utf-8', errors='replace', timeout=180,
                              env={**os.environ, 'PYTHONOPTIMIZE': '1'})

    def success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)

    def reject(self, result, message, target):
        self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn(message, result.stdout+result.stderr); self.assertFalse(target.exists())

    def verify(self, output, report):
        result = self.run_blender('--output', output, '--verify-only', '--report', report)
        self.success(result); self.assertIn('EQUIPMENT_SOURCE_OK', result.stdout)
        receipt = read_json(report)
        self.assertTrue(receipt['pass'] and receipt['glb_matches_saved_source'] and receipt['glb_matches_reconstruction'])
        self.assertTrue(receipt['image_paths_relative'])
        self.assertEqual((receipt['objects'], receipt['author_textures'], receipt['runtime_textures']), (19, 8, 6))
        self.assertEqual(receipt['slot_triangles'], {'head': 148, 'chest': 344, 'back': 580, 'weapon': 364})
        for name in ('reference_max_error', 'base_max_error', 'material_geometry_max_error'):
            self.assertLessEqual(receipt[name], 1e-7)
        self.assertEqual(receipt['outputs'], {name: digest(output/name) for name in receipt['outputs']})

    def test_relocated_complete_bridge_materials_repeated_and_portable_source(self):
        sources = {p: digest(p) for p in self.addon.rglob('*') if p.is_file()}
        self.success(self.run_blender()); output = self.host/'.temp/equipment_bake'
        self.assertEqual((output/'equipment.json').read_bytes(), (BASE/'equipment.json').read_bytes())
        manifest = read_json(output/'material_authored_v1.json'); reference = read_json(BASE/'material_authored_v1.json')
        self.assertEqual(material_fields(manifest), material_fields(reference))
        self.assertEqual(glb_content(output/'equipment_materials_v1.glb'), glb_content(GLB))
        for row in reference['textures'].values():
            for texture in (row, row['roughness']):
                path = output/'textures/materials_v1'/Path(texture['path']).name
                self.assertEqual(digest(path), texture['sha256'])
        generation = read_json(output/'equipment_generation.json')
        self.assertEqual(generation['scripts'], {name: digest(self.script.with_name(name)) for name in SCRIPTS})
        self.assertEqual(generation['input_recipe_sha256'], digest(self.recipe))
        source = self.recipe.parent/'equipment.blend'
        self.assertEqual(generation['inputs'], {'equipment': {'name': source.name, 'sha256': digest(source)}})
        self.assertNotEqual(digest(output/'equipment.blend'), digest(source))
        self.assertNotIn('backup_manifest_sha256', manifest)
        self.assertNotIn(str(self.host), json.dumps(generation)+json.dumps(manifest))
        self.verify(output, self.work/'verified.json')
        repeated = self.work/'repeat'; self.success(self.run_blender('--output', repeated))
        for name in generation['outputs']:
            if name.endswith(('.png', '.glb')) or name == 'equipment.json':
                self.assertEqual((output/name).read_bytes(), (repeated/name).read_bytes())
        self.verify(repeated, self.work/'repeat_verified.json')
        moved = self.work/'moved_source'; shutil.copytree(output, moved)
        self.verify(moved, self.work/'moved_verified.json')
        for path, identity in sources.items():
            self.assertEqual(digest(path), identity, str(path))

    def test_input_identity_missing_schema_and_path_rejection(self):
        original = read_json(self.recipe); cases = []
        recipe = read_json(self.recipe); recipe['files']['equipment']['sha256'] = '0'*64
        cases.append(('identity', recipe, 'Input identity'))
        recipe = read_json(self.recipe); recipe['files']['equipment']['path'] = 'missing.blend'
        cases.append(('missing', recipe, 'FileNotFoundError'))
        recipe = read_json(self.recipe); recipe['schema'] = 2
        cases.append(('schema', recipe, 'Expected schema 1'))
        source = self.recipe.parent/original['files']['equipment']['path']
        recipe = read_json(self.recipe); recipe['files']['equipment']['path'] = str(source)
        cases.append(('absolute', recipe, 'paths must be relative'))
        outside = self.work/'outside.blend'; shutil.copy2(source, outside)
        recipe = read_json(self.recipe); recipe['files']['equipment']['path'] = os.path.relpath(outside, self.recipe.parent)
        cases.append(('escape', recipe, 'Input identity or location'))
        for name, recipe, message in cases:
            with self.subTest(name=name):
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8'); output = self.work/name
                self.reject(self.run_blender('--output', output), message, output)

    def test_actual_invalid_source_rejected_with_updated_identity(self):
        recipe = read_json(self.recipe); source = self.recipe.parent/'equipment.blend'; original = source.read_bytes()
        for name, expression in [
            ('name', "bpy.data.objects['Drone mount'].name='Wrong'"),
            ('vertex', "bpy.data.objects['Prism brooch'].data.vertices[0].co.x += .01"),
        ]:
            with self.subTest(name=name):
                source.write_bytes(original)
                code = 'import bpy; '+expression+'; bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)'
                self.success(self.run_blender(expression=code, blend=source))
                recipe['files']['equipment']['sha256'] = digest(source)
                self.recipe.write_text(json.dumps(recipe), encoding='utf-8'); output = self.work/name
                self.reject(self.run_blender('--output', output), 'Archived equipment geometry changed', output)

    def test_saved_bridge_material_texture_export_and_addon_writes_rejected(self):
        output = self.work/'candidate'; self.success(self.run_blender('--output', output))
        generation_path = output/'equipment_generation.json'; manifest_path = output/'material_authored_v1.json'
        generation = read_json(generation_path); original_manifest = manifest_path.read_bytes()
        originals = {name: (output/name).read_bytes() for name in generation['outputs']}

        def update():
            manifest = read_json(manifest_path)
            manifest['source_sha256'] = digest(output/'equipment_materials_v1.blend')
            manifest['glb_sha256'] = digest(output/'equipment_materials_v1.glb')
            for row in manifest['textures'].values():
                row['sha256'] = digest(output/row['path']); row['roughness']['sha256'] = digest(output/row['roughness']['path'])
            manifest_path.write_text(json.dumps(manifest), encoding='utf-8')
            generation['outputs'] = {name: digest(output/name) for name in generation['outputs']}
            generation_path.write_text(json.dumps(generation), encoding='utf-8')

        def restore():
            for name, contents in originals.items():
                (output/name).write_bytes(contents)
            manifest_path.write_bytes(original_manifest); update()

        def refuse(name, message):
            report = self.work/(name+'_receipt.json')
            self.reject(self.run_blender('--output', output, '--verify-only', '--report', report), message, report)

        bridge = read_json(output/'equipment.json'); bridge['head']['positions'][0][0] += .01
        (output/'equipment.json').write_text(json.dumps(bridge), encoding='utf-8'); update()
        refuse('bridge', 'Saved base geometry and bridge differ')
        restore(); manifest = read_json(manifest_path); manifest['textures']['silver']['roughness']['color_space'] = 'sRGB'
        manifest_path.write_text(json.dumps(manifest), encoding='utf-8'); update()
        refuse('metadata', 'Material manifest contract changed')
        restore()
        code = ("import bpy; bpy.data.objects['Prism brooch'].data.vertices[0].co.x += .01; "
                "bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)")
        self.success(self.run_blender(expression=code, blend=output/'equipment.blend')); update()
        refuse('base', 'Saved equipment geometry changed')
        for synchronized in (False, True):
            restore()
            code = ("import bpy; bpy.data.materials['Authored_silver'].node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=.1; "
                    "bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)")
            if synchronized:
                code += ("; bpy.ops.object.select_all(action='SELECT'); bpy.ops.export_scene.gltf(filepath=bpy.path.abspath('//equipment_materials_v1.glb'), "
                         "export_format='GLB', export_apply=True)")
            self.success(self.run_blender(expression=code, blend=output/'equipment_materials_v1.blend')); update()
            refuse('material_'+str(synchronized), 'GLB and rebuilt equipment inputs differ' if synchronized else 'GLB and saved material source differ')
        restore(); png = output/'textures/materials_v1/equipment_silver_roughness.png'
        png.write_bytes(png.read_bytes()+b'corruption'); update()
        refuse('texture', 'Procedural equipment texture changed')
        restore(); glb = output/'equipment_materials_v1.glb'; glb.write_bytes(glb.read_bytes()+b'corruption')
        refuse('identity', 'Generated output identity changed')
        target = self.addon/'rejected_output'
        self.reject(self.run_blender('--output', target), 'Output must be outside', target)
        target = self.addon/'rejected_report.json'
        self.reject(self.run_blender('--output', output, '--verify-only', '--report', target), 'Report must be outside', target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blender', default=os.environ.get('BLENDER_EXECUTABLE') or shutil.which('blender'))
    args, remaining = parser.parse_known_args()
    if not args.blender or not Path(args.blender).is_file():
        parser.error('Pass --blender <executable>, set BLENDER_EXECUTABLE, or put blender on PATH')
    BLENDER = Path(args.blender).resolve()
    unittest.main(argv=[sys.argv[0], *remaining])
