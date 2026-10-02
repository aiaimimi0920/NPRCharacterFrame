"""Build the showcase into the host's .export/<release>.<attempt> directory."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def project_root(start):
    for candidate in (start, *start.parents):
        if (candidate / 'project.godot').is_file():
            return candidate
    raise ValueError('Cannot find host project.godot')


def reserve(root, version):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('Release version must contain three nonnegative integers')
    exports = root / '.export'
    exports.mkdir(exist_ok=True)
    attempts = [int(p.name[len(version) + 1:]) for p in exports.iterdir()
                if p.is_dir() and re.fullmatch(re.escape(version) + r'\.\d+', p.name)]
    number = max(attempts, default=-1) + 1
    while True:
        output = exports / f'{version}.{number}'
        try:
            output.mkdir()
            return output
        except FileExistsError:
            number += 1


def run(command, log, timeout=600):
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    with log.open('w', encoding='utf-8') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                   creationflags=flags)
        try:
            code = process.wait(timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               creationflags=flags, check=False)
            else:
                process.kill()
            process.wait()
            raise RuntimeError(f'Timed out; see {log.name}') from None
    text = log.read_text(encoding='utf-8', errors='replace')
    if code or re.search(r'ERROR:|SCRIPT ERROR:|SHADER ERROR:|Parse Error', text):
        raise RuntimeError(f'Command failed ({code}); see {log.name}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('NPR_GODOT_PATH'))
    parser.add_argument('--configuration', choices=('debug', 'release'), default='debug',
                        help='Export configuration; defaults to debug')
    parser.add_argument('--template', help='Custom Windows template for the selected configuration; defaults beside Godot')
    parser.add_argument('--version', help='Public three-part release; defaults to project config/version')
    parser.add_argument('--project', type=Path)
    parser.add_argument('--work-root', type=Path,
                        help='Temporary build root; defaults to the host .temp/build directory')
    args = parser.parse_args(argv)
    root = args.project.resolve() if args.project else project_root(Path(__file__).resolve().parent)
    project = (root / 'project.godot').read_text(encoding='utf-8')
    version = args.version or re.search(r'^config/version="([^"]+)"', project, re.M).group(1)
    output = reserve(root, version)
    work_root = args.work_root.resolve() if args.work_root else root / '.temp/build'
    work = work_root / output.name
    try:
        logs = Path(os.path.relpath(work, output)).as_posix() + '/'
    except ValueError:
        # Windows cannot represent a relative path across drive letters.
        logs = work.as_posix() + '/'
    record = {'release_version': version, 'build_version': output.name, 'status': 'building',
              'started_utc': datetime.now(timezone.utc).isoformat(),
              'logs': logs, 'target': 'Windows Desktop', 'configuration': args.configuration}
    manifest = output / 'build.json'
    manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
    stage = None
    try:
        # An explicit root can be shared by hosts. Never reuse or clean an older attempt.
        work.mkdir(parents=True, exist_ok=False)
        if not args.godot:
            raise ValueError('Pass --godot or set NPR_GODOT_PATH')
        godot = Path(args.godot).resolve()
        template = (Path(args.template).resolve() if args.template else
                    godot.parent / f'godot.windows.template_{args.configuration}.x86_64.exe')
        if not godot.is_file() or not template.is_file():
            raise FileNotFoundError(f'Configured Godot executable or {args.configuration} template is missing')
        stage = work / 'project'
        stage.mkdir()
        shutil.copytree(root / 'addons/npr_character_frame', stage / 'addons/npr_character_frame',
                        ignore=shutil.ignore_patterns('.ci_script', 'docs', '__pycache__', 'import_sources'))
        for p in (root / 'icon.svg',):
            if p.is_file():
                shutil.copy2(p, stage / p.name)
        project = re.sub(r'^config/version="[^"]+"', f'config/version="{version}"', project, flags=re.M)
        (stage / 'project.godot').write_text(project, encoding='utf-8')
        preset = '[preset.0]\nname="NPR Showcase"\nplatform="Windows Desktop"\nrunnable=true\n'
        preset += 'export_filter="all_resources"\ninclude_filter="addons/npr_character_frame/**/*.json,addons/npr_character_frame/**/*.bin,addons/npr_character_frame/**/*.wav"\n'
        preset += 'exclude_filter="addons/npr_character_frame/**/provenance/*"\nexport_path=""\n'
        preset += f'[preset.0.options]\ncustom_template/{args.configuration}=' + json.dumps(template.as_posix()) + '\n'
        preset += 'binary_format/embed_pck=false\napplication/modify_resources=false\n'
        (stage / 'export_presets.cfg').write_text(preset, encoding='utf-8')
        record['engine_sha256'] = hashlib.sha256(godot.read_bytes()).hexdigest()
        record['template_sha256'] = hashlib.sha256(template.read_bytes()).hexdigest()
        inputs = [{'path': p.relative_to(stage).as_posix(),
                   'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                  for p in sorted(stage.rglob('*')) if p.is_file() and p.name != 'export_presets.cfg']
        (output / 'source-inputs.json').write_text(json.dumps(inputs, indent=2), encoding='utf-8')
        run([str(godot), '--headless', '--path', str(stage), '--editor', '--import', '--quit'],
            work / 'import.log')
        executable = output / 'NPRShowcase.exe'
        run([str(godot), '--headless', '--path', str(stage), '--export-' + args.configuration, 'NPR Showcase',
             str(executable)], work / 'export.log')
        if not executable.is_file() or not executable.with_suffix('.pck').is_file():
            raise RuntimeError('Exporter did not produce the executable and PCK')
        # Custom Windows templates can link companion DLLs (for example Spout).
        for dependency in template.parent.glob('*.dll'):
            shutil.copy2(dependency, output / dependency.name)
        if (template.parent / 'licenses').is_dir():
            shutil.copytree(template.parent / 'licenses', output / 'licenses')
        # Do not read or modify a user's existing showcase settings during smoke testing.
        old_appdata = os.environ.get('APPDATA')
        os.environ['APPDATA'] = str(work / 'appdata')
        try:
            Path(os.environ['APPDATA']).mkdir()
            run([str(executable), '--audio-driver', 'Dummy', '--quit-after', '90'],
                work / 'package-startup.log', timeout=300)
        finally:
            if old_appdata is None:
                os.environ.pop('APPDATA', None)
            else:
                os.environ['APPDATA'] = old_appdata
        record['status'] = 'success'
        record['artifacts'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in output.iterdir() if p.suffix in {'.exe', '.pck', '.dll'}}
    except Exception as error:
        record['status'] = 'failed'
        record['error'] = str(error)
    finally:
        record['finished_utc'] = datetime.now(timezone.utc).isoformat()
        manifest.write_text(json.dumps(record, indent=2), encoding='utf-8')
        if stage is not None and stage.exists():
            if not stage.resolve().is_relative_to(work.resolve()):
                raise RuntimeError('Refusing to clean a staging path outside this build attempt')
            shutil.rmtree(stage)
    print(json.dumps({'version': output.name, 'status': record['status'],
                      'manifest': manifest.relative_to(root).as_posix()}))
    return 0 if record['status'] == 'success' else 1


if __name__ == '__main__':
    sys.exit(main())
