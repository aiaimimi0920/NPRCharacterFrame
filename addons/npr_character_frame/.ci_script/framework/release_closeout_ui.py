"""P05 固定 R2 主要操作与跨页存档收尾；不穷举控件组合。"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import time
import traceback

from release_style_quality_ui import StyleQualityDesktop, actual_slider_y
from release_workbench_ui import digest, write_json


class CloseoutDesktop(StyleQualityDesktop):
    def __init__(self, package, layout, output):
        super().__init__(package, layout, output)
        shutil.copyfile(Path(__file__).with_name('release_style_quality_ui.py'), output / 'locator.py')
        shutil.copyfile(__file__, output / 'scenario.py')
        self.report['sources'].update({name: digest(output / name) for name in ('locator.py', 'scenario.py')})
        self.report['scope'] = 'Frozen R2 representative pages, combined save/restart/reset'
        self.report.pop('manual_budget_review')

    def endpoint(self, name, high, page):
        rect = self.target(name, page, click=False)
        shot = self.capture(f'slider_{len(self.report["inputs"]):03d}')
        y = actual_slider_y(self.output / (shot + '.png'), rect)
        x = rect[2] - 1 if high else rect[0] + 1
        self.click((x - .5, y - 1, x + .5, y + 1))

    def visual_toggle(self, name, page):
        before = self.capture(name + '_before')
        self.target(name, page)
        self.compare(name + '_visible', before, self.capture(name + '_on'), False)
        self.target(name, page)
        self.compare(name + '_restored', before, self.capture(name + '_off'), True)

    def run(self):
        self.identity()
        self.start('initial')
        baseline = self.saved('saved_baseline')
        initial = json.loads(baseline)
        self.target('FullView')
        self.target('FrameworkLock')
        self.visual_toggle('EquipmentSlot0', 0)
        self.target('FrameworkLock')
        self.target('HosieryView', 1)
        self.target('FrameworkLock')
        before = self.capture('stocking_before')
        self.endpoint('StockingTransparency', True, 1)
        self.compare('transparency_visible', before, self.capture('stocking_clear'), False)
        self.endpoint('StockingTransparency', False, 1)
        self.compare('transparency_endpoints_differ', 'stocking_clear', self.capture('stocking_opaque'), False)
        self.target('HosieryStyle1', 1)
        self.visual_toggle('TulleGeometryEnabled', 1)
        self.endpoint('Debug软组织压力', True, 5)
        pressure = self.capture('pressure_on')
        self.endpoint('Debug软组织压力', False, 5)
        self.compare('pressure_visible', pressure, self.capture('pressure_off'), False)
        self.target('FrameworkLock')
        self.target('FaceView')
        self.target('FrameworkLock')
        neutral = self.capture('expression_neutral')
        self.target('Expression1', 6)
        self.compare('expression_visible', neutral, self.capture('expression_active'), False)
        self.target('Expression0', 6)
        self.compare('expression_restored', neutral, self.capture('expression_restored'), True)
        self.target('FrameworkLock')

        # 一次跨页组合，按完整保存对象核验，防止无效点击/误动其他字段。
        self.target('EquipmentSlot0', 0)
        self.target('TulleGeometryEnabled', 1)
        self.target('HairDynamicEnabled', 2)
        self.target('HairCollisionEnabled', 2)
        self.endpoint('Debug风场强度', True, 2)
        wind_max = json.loads(self.saved('saved_wind_max'))
        self.check('hair_page_wind_max_saved', wind_max['wind_strength'] == 1.0)
        self.target('Debug风场强度', 7, click=False)
        self.capture('overview_wind_max')
        self.endpoint('Debug风场强度', False, 7)
        self.check('overview_changes_only_shared_wind',
                   json.loads(self.saved('saved_overview_wind_min')) == (wind_max | {'wind_strength': 0.0}))
        self.target('Debug风场强度', 2, click=False)
        self.capture('hair_wind_min_after_overview')
        self.endpoint('Debug风场强度', True, 2)
        self.target('DropletsEnabled', 3)
        self.endpoint('Debug降雨密度', True, 3)
        self.endpoint('Debug皮肤湿润', True, 3)
        pause_rect = tuple(round(v) for v in self.target('DropletPreviewPause', 3, click=False))
        self.capture('rain_play_control')
        self.target('DropletPreviewPause', 3)
        self.compare('rain_pause_control_changes', 'rain_play_control',
                     self.capture('rain_pause_control'), False, pause_rect)
        self.target('DropletPreviewPause', 3)
        self.compare('rain_resume_control_restores', 'rain_play_control',
                     self.capture('rain_resume_control'), True, pause_rect)
        self.target('DropletPreviewRestart', 3)
        self.capture('rain_restarted')
        self.target('Action1', 5)
        self.endpoint('Debug软组织压力', True, 5)
        self.target('Expression1', 6)
        self.target('SpeechDemo', 6)
        self.capture('speech_started')
        self.target('SpeechStop', 6)
        self.capture('speech_stopped')
        expected = initial | dict(equipment=[True, False, False, False],
            stocking_transparency=0.0, hosiery_style=1, tulle_geometry_enabled=True,
            hair_dynamic_enabled=True, hair_collision_enabled=True, wind_strength=1.0,
            droplets_enabled=True, droplet_count=12, wetness_regions=[1.0, 0.0, 0.0, 0.0],
            action=1, soft_tissue_pressure=1.0, expression=1)
        combined = self.saved('saved_combined')
        self.check('all_selected_fields_and_no_unrelated_mutation', json.loads(combined) == expected,
                   expected=expected, actual=json.loads(combined))
        self.close()
        self.start('restart')
        self.check('combined_save_survives_restart', self.saved('saved_restart') == combined)
        self.target('FullView')
        self.capture('restart_combined_visible')
        self.target('Reset')
        self.check('reset_restores_factory_save', self.saved('saved_reset') == baseline)
        self.close()
        self.start('factory_restart')
        self.check('factory_save_survives_restart', self.saved('saved_factory_restart') == baseline)
        self.capture('factory_restart_visible')
        self.close()
        self.identity()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--layout', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    app = CloseoutDesktop(args.package.resolve(), args.layout.resolve(), args.output.resolve())
    try:
        app.run()
    except Exception:
        app.report['exception'] = traceback.format_exc()
        print(app.report['exception'], flush=True)
        if app.proc and app.proc.poll() is None and app.hwnd:
            app.capture('failure')
    finally:
        app.close()
        app.report['finished_utc'] = datetime.now(timezone.utc).isoformat()
        app.report['status'] = 'passed' if not app.report.get('exception') and all(
            row['passed'] for row in app.report['checks']) else 'failed'
        write_json(app.output / 'report.json', app.report)
    print('RELEASE_CLOSEOUT_' + app.report['status'].upper(), flush=True)
    return 0 if app.report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
