"""Export and run the real debug/release templates with a release-safe contact fixture."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


ADDON = Path(__file__).resolve().parents[2]
ROOT = next(p for p in ADDON.parents if (p/'project.godot').is_file())
CONTACT = Path('runtime/animation/npr_surface_contact.gd')
FIXTURE = Path('.ci_script/framework/surface_contact_regression')
FLAGS = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command, log, env=None, timeout=180):
    with log.open('w', encoding='utf-8') as stream:
        process = subprocess.Popen(list(map(str, command)), stdout=stream, stderr=subprocess.STDOUT,
                                   env=env, creationflags=FLAGS)
        try:
            code = process.wait(timeout)
        finally:
            if process.poll() is None:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   creationflags=FLAGS, check=False)
                else:
                    process.kill()
                process.wait()
    text = log.read_text(encoding='utf-8', errors='replace')
    return code, text


def require_success(command, log):
    code, text = execute(command, log)
    if code or re.search(r'ERROR:|SCRIPT ERROR:|SHADER ERROR:|Parse Error', text):
        raise RuntimeError(f'Command failed ({code}): {log.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('NPR_GODOT_PATH'), required=not os.environ.get('NPR_GODOT_PATH'))
    parser.add_argument('--debug-template', type=Path)
    parser.add_argument('--release-template', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    godot = Path(args.godot).resolve()
    templates = {
        'debug': (args.debug_template or godot.parent/'godot.windows.template_debug.x86_64.exe').resolve(),
        'release': (args.release_template or godot.parent/'godot.windows.template_release.x86_64.exe').resolve(),
    }
    for path in (godot, *templates.values()):
        if not path.is_file():
            raise FileNotFoundError(path)
    output = args.output.resolve() if args.output else ROOT/'.temp/surface_contact_templates'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    if output.is_relative_to(ADDON):
        raise ValueError('Output must be outside the delivered addon')
    output.mkdir(parents=True)
    record = {'status': 'running', 'engine_sha256': sha(godot), 'source_sha256': sha(ADDON/CONTACT),
              'fixture_sha256': sha((ADDON/FIXTURE).with_suffix('.gd')),
              'scene_sha256': sha((ADDON/FIXTURE).with_suffix('.tscn')),
              'runner_sha256': sha(Path(__file__)), 'modes': {}}
    try:
        stage = output/'project'
        stage.mkdir()
        for relative in (CONTACT, CONTACT.with_suffix('.gd.uid')):
            source = ADDON/relative
            if not source.is_file():
                continue
            target = stage/'addons/npr_character_frame'/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        # Hidden development directories are not discovered as export dependencies.
        # Export the same fixture from a normal scene directory in this isolated host.
        tests = stage/'tests'
        tests.mkdir()
        shutil.copy2((ADDON/FIXTURE).with_suffix('.gd'), tests/'surface_contact_regression.gd')
        scene = (ADDON/FIXTURE).with_suffix('.tscn').read_text(encoding='utf-8')
        source_path = 'res://addons/npr_character_frame/'+FIXTURE.with_suffix('.gd').as_posix()
        scene = scene.replace(source_path, 'res://tests/surface_contact_regression.gd')
        (tests/'surface_contact_regression.tscn').write_text(scene, encoding='utf-8')
        main_scene = 'res://tests/surface_contact_regression.tscn'
        project = 'config_version=5\n[application]\nconfig/name="NPR Surface Contact Test"\n'
        project += 'run/main_scene='+json.dumps(main_scene)+'\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        (stage/'project.godot').write_text(project, encoding='utf-8')
        preset = '[preset.0]\nname="NPR Contact Test"\nplatform="Windows Desktop"\nrunnable=true\n'
        preset += 'export_filter="all_resources"\n'
        preset += 'include_filter=""\nexclude_filter=""\n'
        preset += '[preset.0.options]\napplication/modify_resources=false\nbinary_format/embed_pck=false\n'
        for mode, path in templates.items():
            preset += 'custom_template/'+mode+'='+json.dumps(path.as_posix())+'\n'
        (stage/'export_presets.cfg').write_text(preset, encoding='utf-8')
        require_success([godot, '--headless', '--path', stage, '--editor', '--import', '--quit'], output/'import.log')
        for mode, template in templates.items():
            work = output/mode
            work.mkdir()
            executable = work/'SurfaceContact.exe'
            require_success([godot, '--headless', '--path', stage, '--export-'+mode, 'NPR Contact Test', executable],
                            work/'export.log')
            for dependency in template.parent.glob('*.dll'):
                shutil.copy2(dependency, work/dependency.name)
            appdata = work/'appdata'
            appdata.mkdir()
            code, log = execute([executable, '--headless', '--quit-after', '120', '--', mode, work], work/'runtime.log',
                                env={**os.environ, 'APPDATA': str(appdata)})
            report_path = work/'surface_contact.json'
            report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.is_file() else None
            passed = code == 0 and report is not None and report['failures'] == 0 and 'REGRESSION_OK' in log
            passed = passed and not re.search(r'ERROR:|SCRIPT ERROR:|SHADER ERROR:|Parse Error|WARNING:', log)
            record['modes'][mode] = {'pass': bool(passed), 'exit': code, 'report': report,
                                     'template_sha256': sha(template), 'exe_sha256': sha(executable),
                                     'pck_sha256': sha(executable.with_suffix('.pck'))}
        record['status'] = 'success' if all(row['pass'] for row in record['modes'].values()) else 'failed'
    except Exception as error:
        record['status'] = 'failed'
        record['error'] = str(error)
    finally:
        (output/'result.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'status': record['status'], 'modes': {mode: {'pass': row['pass'], 'exit': row['exit'],
                      'checks': len(row['report']['checks']) if row['report'] else 0,
                      'failures': row['report']['failures'] if row['report'] else None}
                     for mode, row in record['modes'].items()}, 'error': record.get('error')}, indent=2))
    return int(record['status'] != 'success')


if __name__ == '__main__':
    sys.exit(main())
