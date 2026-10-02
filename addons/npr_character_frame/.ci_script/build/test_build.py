"""Verify user-visible build numbering, failure reservation and host discovery."""

from pathlib import Path
import tempfile
import unittest
import json
import os
import hashlib
from unittest.mock import patch

from build import main, project_root, reserve


class BuildTests(unittest.TestCase):
    def setUp(self):
        host = project_root(Path(__file__).resolve().parent)
        temporary = Path(os.environ.get('NPR_TEST_TEMP_ROOT', host / '.temp'))
        temporary.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(prefix='build-tests-', dir=temporary)
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'project.godot').write_text('[application]\nconfig/version="1.3.0"\n', encoding='utf-8')

    def test_failed_attempts_are_reserved_and_release_resets(self):
        for expected in ('1.3.0.0', '1.3.0.1'):
            self.assertEqual(main(['--project', str(self.root), '--godot', str(self.root/'missing.exe')]), 1)
            record = json.loads((self.root/'.export'/expected/'build.json').read_text(encoding='utf-8'))
            self.assertEqual(record['status'], 'failed')
            self.assertEqual(record['build_version'], expected)
        self.assertEqual(reserve(self.root, '1.4.0').name, '1.4.0.0')
        self.assertEqual(reserve(self.root, '1.3.0').name, '1.3.0.2')

    def test_numeric_order_and_no_overwrite(self):
        (self.root/'.export/1.3.0.9').mkdir(parents=True)
        (self.root/'.export/1.3.0.10').mkdir()
        marker = self.root/'.export/1.3.0.10/keep.txt'
        marker.write_text('existing package', encoding='utf-8')
        self.assertEqual(reserve(self.root, '1.3.0').name, '1.3.0.11')
        self.assertEqual(marker.read_text(encoding='utf-8'), 'existing package')
        with self.assertRaises(ValueError):
            reserve(self.root, '../1.3.0')

    def test_host_discovery_after_rename(self):
        nested = self.root/'RenamedProject/addons/npr_character_frame/.ci_script/build'
        nested.mkdir(parents=True)
        renamed = self.root/'RenamedProject'
        (renamed/'project.godot').write_text('config_version=5\n', encoding='utf-8')
        self.assertEqual(project_root(nested), renamed)

    def _engine_and_source(self, include_release=True):
        engine = self.root / 'engine/godot.exe'
        engine.parent.mkdir()
        engine.write_bytes(b'fake-editor')
        for mode in ['debug', 'release'] if include_release else ['debug']:
            (engine.parent / f'godot.windows.template_{mode}.x86_64.exe').write_bytes(mode.encode())
        (engine.parent / 'companion.dll').write_bytes(b'fake-dll')
        source = self.root / 'addons/npr_character_frame'
        source.mkdir(parents=True)
        (source / 'runtime.gd').write_text('extends Node\n', encoding='utf-8')
        for excluded in ['.ci_script', 'docs', 'import_sources']:
            (source / excluded).mkdir()
            (source / excluded / 'excluded.txt').write_text('author-only', encoding='utf-8')
        return engine

    def _build(self, engine, arguments=(), failure=False):
        calls = []
        presets = []
        appdata = []

        def fake_run(command, log, timeout=600):
            calls.append(command)
            log.write_text('fake process for command-selection unit test\n', encoding='utf-8')
            if failure:
                raise RuntimeError('injected import failure')
            if '--path' in command:
                stage = Path(command[command.index('--path') + 1])
                preset = (stage / 'export_presets.cfg').read_text(encoding='utf-8')
                if '--export-debug' in command or '--export-release' in command:
                    presets.append(preset)
                    option = next(line for line in preset.splitlines() if line.startswith('custom_template/'))
                    template = Path(json.loads(option.split('=', 1)[1]))
                    Path(command[-1]).write_bytes(template.read_bytes())
                    Path(command[-1]).with_suffix('.pck').write_bytes(b'fake-pack')
            else:
                appdata.append(os.environ['APPDATA'])

        with patch('build.run', side_effect=fake_run):
            code = main(['--project', str(self.root), '--godot', str(engine), *arguments])
        latest = max((self.root / '.export').iterdir(), key=lambda p: int(p.name.rsplit('.', 1)[1]))
        record = json.loads((latest / 'build.json').read_text(encoding='utf-8'))
        return code, latest, record, calls, presets, appdata

    def test_default_stays_debug_and_inputs_are_unchanged(self):
        engine = self._engine_and_source()
        code, output, record, calls, presets, appdata = self._build(engine)
        self.assertEqual(code, 0)
        self.assertEqual(record['configuration'], 'debug')
        self.assertIn('--export-debug', calls[1])
        self.assertIn('custom_template/debug=', presets[0])
        self.assertNotIn('custom_template/release=', presets[0])
        self.assertEqual((output / 'NPRShowcase.exe').read_bytes(), b'debug')
        self.assertEqual(record['template_sha256'], hashlib.sha256(b'debug').hexdigest())
        inputs = json.loads((output / 'source-inputs.json').read_text(encoding='utf-8'))
        self.assertEqual({row['path'] for row in inputs}, {'project.godot', 'addons/npr_character_frame/runtime.gd'})
        self.assertTrue(Path(appdata[0]).is_relative_to(self.root / '.temp/build/1.3.0.0'))
        self.assertFalse((self.root / '.temp/build/1.3.0.0/project').exists())
        self.assertTrue((self.root / 'addons/npr_character_frame/runtime.gd').is_file())

    def test_release_selects_matching_export_mode_and_template(self):
        engine = self._engine_and_source()
        code, output, record, calls, presets, _ = self._build(engine, ['--configuration', 'release'])
        self.assertEqual(code, 0)
        self.assertEqual(record['configuration'], 'release')
        self.assertIn('--export-release', calls[1])
        self.assertIn('custom_template/release=', presets[0])
        self.assertNotIn('custom_template/debug=', presets[0])
        self.assertEqual((output / 'NPRShowcase.exe').read_bytes(), b'release')
        self.assertEqual(record['template_sha256'], hashlib.sha256(b'release').hexdigest())
        self.assertEqual(calls[2][0], str(output / 'NPRShowcase.exe'))
        self.assertIn('--quit-after', calls[2])

    def test_explicit_template_is_scoped_to_selected_mode(self):
        engine = self._engine_and_source()
        custom = self.root / 'custom-template.exe'
        custom.write_bytes(b'custom')
        for mode in ['debug', 'release']:
            with self.subTest(mode=mode):
                code, output, record, calls, presets, _ = self._build(
                    engine, ['--configuration', mode, '--template', str(custom)])
                self.assertEqual(code, 0)
                self.assertIn('--export-' + mode, calls[1])
                self.assertIn(f'custom_template/{mode}=', presets[0])
                self.assertEqual((output / 'NPRShowcase.exe').read_bytes(), b'custom')
                self.assertEqual(record['template_sha256'], hashlib.sha256(b'custom').hexdigest())

    def test_missing_release_template_never_falls_back_to_debug(self):
        engine = self._engine_and_source(include_release=False)
        code, _, record, calls, _, _ = self._build(engine, ['--configuration', 'release'])
        self.assertEqual(code, 1)
        self.assertEqual(record['configuration'], 'release')
        self.assertIn('release template', record['error'])
        self.assertEqual(calls, [])

    def test_modes_share_monotonic_attempt_numbers(self):
        engine = self._engine_and_source()
        for mode, version in [('debug', '1.3.0.0'), ('release', '1.3.0.1')]:
            code, output, _, _, _, _ = self._build(engine, ['--configuration', mode])
            self.assertEqual(code, 0)
            self.assertEqual(output.name, version)

    def test_explicit_work_root_preserves_host_and_records_log_location(self):
        engine = self._engine_and_source()
        external = self.root / 'independent-work'
        external.mkdir()
        sentinel = external / 'keep.txt'
        sentinel.write_text('keep', encoding='utf-8')
        previous = os.environ.get('APPDATA')
        code, output, record, _, _, appdata = self._build(
            engine, ['--configuration', 'release', '--work-root', str(external)])
        self.assertEqual(code, 0)
        self.assertEqual((output / record['logs']).resolve(), external / output.name)
        self.assertTrue(Path(appdata[0]).is_relative_to(external))
        self.assertEqual(os.environ.get('APPDATA'), previous)
        self.assertFalse((external / output.name / 'project').exists())
        self.assertEqual(sentinel.read_text(encoding='utf-8'), 'keep')
        self.assertFalse((self.root / '.temp/build').exists())

    def test_failed_import_cleans_only_owned_stage_and_keeps_receipt(self):
        engine = self._engine_and_source()
        external = self.root / 'failure-work'
        code, output, record, _, _, _ = self._build(
            engine, ['--configuration', 'release', '--work-root', str(external)], failure=True)
        self.assertEqual(code, 1)
        self.assertEqual(record['status'], 'failed')
        self.assertIn('injected import failure', record['error'])
        self.assertTrue((external / output.name / 'import.log').is_file())
        self.assertFalse((external / output.name / 'project').exists())
        self.assertTrue((self.root / 'addons/npr_character_frame/runtime.gd').is_file())
        self.assertEqual(reserve(self.root, '1.3.0').name, '1.3.0.1')

    def test_unknown_mode_rejected_before_reserving_attempt(self):
        with self.assertRaises(SystemExit) as raised:
            main(['--project', str(self.root), '--configuration', 'invalid'])
        self.assertEqual(raised.exception.code, 2)
        self.assertFalse((self.root / '.export').exists())

    def test_existing_work_attempt_is_preserved_and_failure_is_recorded(self):
        engine = self._engine_and_source()
        external = self.root / 'shared-work'
        old = external / '1.3.0.0/project'
        old.mkdir(parents=True)
        marker = old / 'keep.txt'
        marker.write_text('prior attempt', encoding='utf-8')
        code, _, record, calls, _, _ = self._build(
            engine, ['--configuration', 'release', '--work-root', str(external)])
        self.assertEqual(code, 1)
        self.assertEqual(record['status'], 'failed')
        self.assertEqual(calls, [])
        self.assertEqual(marker.read_text(encoding='utf-8'), 'prior attempt')


if __name__ == '__main__':
    unittest.main()
