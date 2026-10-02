"""实际 Release 解锁预设作用范围；仅比较实际 UI 参数和同次重新锁定后的渲染。"""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import shutil
import traceback

from release_style_quality_ui import StyleQualityDesktop
from release_workbench_ui import digest, host_root, write_json


FIELDS = {
    "yaw": ("方位角", "lighting"),
    "elevation": ("高度角", "lighting"),
    "ambient": ("环境光能量", "host"),
    "exposure": ("曝光", "host"),
    "fov": ("镜头视场角", "host"),
    "fill": ("补光", "lighting"),
    "shadow": ("阴影强度", "lighting"),
    "outline": ("轮廓宽度", "character"),
}


class ScopeDesktop(StyleQualityDesktop):
    def __init__(self, package, layout, output):
        super().__init__(package, layout, output)
        shutil.copyfile(Path(__file__).with_name("release_style_quality_ui.py"), output / "locator.py")
        shutil.copyfile(__file__, output / "scenario.py")
        self.report["sources"].update({name: digest(output / name) for name in ("locator.py", "scenario.py")})
        self.report.pop("manual_budget_review")
        self.report["scenario"] = "Unlocked rim/illustration scope isolation through actual UI readouts"
        self.report["boundaries"] = [
            "eight visible parameter readouts, not all shader values",
            "two non-default presets, not all five presets in all scopes",
            "no cross-time unlocked stage comparison",
            "Dummy audio; not listening, long-term or cross-device acceptance",
        ]
        self.report["parameter_captures"] = {}

    def parameters(self, prefix):
        result = {}
        for key, (title, _) in FIELDS.items():
            name = "Debug" + title
            self.target(name, page=4, click=False)
            entry = self.layout["pages"]["4"]["controls"][name]
            label, slider = entry["label_rect"], entry["rect"]
            roi = tuple(round(value) for value in (label[0], label[1], label[2], slider[3]))
            if not (1080 <= roi[0] < roi[2] <= 1415 and 145 <= roi[1] < roi[3] <= 785):
                raise RuntimeError(f"Parameter label outside fixed options area: {key}: {roi}")
            image = self.capture(prefix + "_" + key)
            result[key] = {"image": image, "roi": roi}
        self.report["parameter_captures"][prefix] = result
        return result

    def match_parameters(self, name, actual, expected, keys=None, equal=True):
        for key in keys or FIELDS:
            if actual[key]["roi"] != expected[key]["roi"]:
                raise RuntimeError("Parameter rectangles differ")
            self.compare(name + "_" + key, expected[key]["image"], actual[key]["image"],
                         equal, actual[key]["roi"])

    def run(self):
        self.identity()
        self.start("first")
        self.target("FaceView")
        saved = self.saved("saved_baseline")
        baseline = self.parameters("baseline")
        for preset in (2, 4):
            all_values = None
            for scope in (0, 2, 1):
                prefix = f"preset_{preset}_scope_{scope}"
                self.target("RestoreStylePreset")
                self.preset(preset, scope)
                actual = self.parameters(prefix)
                if scope == 0:
                    all_values = actual
                    self.match_parameters(prefix + "_changed", actual, baseline,
                                          [key for key, (_, kind) in FIELDS.items() if kind != "host"], False)
                else:
                    for key, (_, kind) in FIELDS.items():
                        included = kind == ("lighting" if scope == 2 else "character")
                        self.match_parameters(prefix + "_isolation", actual,
                                              all_values if included else baseline, [key])
                self.match_parameters(prefix + "_host_unchanged", actual, baseline,
                                      [key for key, (_, kind) in FIELDS.items() if kind == "host"])
                # 应用后才锁定，保留真实已应用的灯光；仅比较这一姿态内的角色幂等性/恢复。
                self.target("FrameworkLock")
                current = self.capture(prefix + "_locked")
                self.preset(0 if scope == 2 else preset, 1)
                self.compare(prefix + "_character_idempotent", current,
                             self.capture(prefix + "_same_character"), True)
                self.target("RestoreStylePreset")
                self.compare(prefix + "_character_restore", current,
                             self.capture(prefix + "_character_restored"), scope == 2)
                self.target("FrameworkLock")
                self.check(prefix + "_save_unchanged", self.saved(prefix + "_saved") == saved)
            self.target("RestoreStylePreset")
            self.match_parameters(f"preset_{preset}_full_restore", self.parameters(f"restored_{preset}"), baseline)
        self.preset(2, 0)
        self.capture("before_restart_temporary_preset")
        self.close()
        self.start("restart")
        self.target("FaceView")
        self.match_parameters("restart_defaults", self.parameters("restart"), baseline)
        self.check("restart_save_unchanged", self.saved("saved_restart") == saved)
        self.close()
        self.identity()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = (args.output or host_root() / ".temp/release_scope" /
              datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    app = ScopeDesktop(args.package.resolve(), args.layout.resolve(), output)
    try:
        app.run()
    except Exception:
        app.report["exception"] = traceback.format_exc()
        print(app.report["exception"], flush=True)
        if app.proc and app.proc.poll() is None and app.hwnd:
            app.capture("failure")
    finally:
        app.close()
        app.report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        app.report["status"] = "passed" if not app.report.get("exception") and all(
            item["passed"] for item in app.report["checks"]) else "failed"
        write_json(output / "report.json", app.report)
    print(f"RELEASE_SCOPE_{app.report['status'].upper()} {output}", flush=True)
    return 0 if app.report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
