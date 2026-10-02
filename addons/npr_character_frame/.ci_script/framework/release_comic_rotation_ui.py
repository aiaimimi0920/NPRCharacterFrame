"""实际 Release 鼠标旋转及头发/卡片四状态对照，不注入或读回包内节点。"""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import shutil
import time
import traceback

import numpy as np
from PIL import Image

from release_style_quality_ui import StyleQualityDesktop
from release_workbench_ui import STAGE, digest, host_root, write_json


class RotationDesktop(StyleQualityDesktop):
    def __init__(self, package, layout, output):
        super().__init__(package, layout, output)
        shutil.copyfile(Path(__file__).with_name("release_style_quality_ui.py"), output / "locator.py")
        shutil.copyfile(__file__, output / "scenario.py")
        self.report["sources"].update({name: digest(output / name) for name in ("locator.py", "scenario.py")})
        self.report.pop("manual_budget_review")
        self.report["scenario"] = "Real mouse orbit, hair/effect factorial captures and birth-facing guard"
        self.report["occlusion_samples"] = []
        self.report["boundaries"] = [
            "angles are requested mouse deltas, not runtime transform readback",
            "no equality comparisons across unlocked animation time",
            "hair occlusion observations require separate independent review",
            "not arbitrary scene occluders, all effects, all models or long-term acceptance",
        ]

    def rotate(self, degrees, pitch=0):
        pixels = round(degrees / 0.4)
        vertical = round(pitch / 0.25)
        if not -650 <= pixels <= 650 or not -140 <= vertical <= 140:
            raise ValueError("Drag exceeds the safe stage region")
        x, y = (330 if pixels > 0 else 990), 450
        pos = lambda a, b: (b << 16) | a
        self.post(0x0200, 0, pos(x, y))
        time.sleep(0.10)
        self.post(0x0201, 1, pos(x, y))
        time.sleep(0.08)
        for step in range(1, 26):
            self.post(0x0200, 1, pos(x + round(pixels * step / 25), y + round(vertical * step / 25)))
            time.sleep(0.015)
        self.post(0x0202, 0, pos(x + pixels, y + vertical))
        time.sleep(0.35)
        self.post(0x0200, 0, (795 << 16) | 1020)
        self.report["inputs"].append({"drag": "left_button", "requested_yaw_delta": degrees,
                                       "requested_pitch_delta": pitch,
                                       "from": [x, y], "to": [x + pixels, y + vertical]})

    def mask(self, first, second):
        a, b = [np.asarray(Image.open(self.output / (name + ".png")).convert("RGBA").crop(STAGE))
                for name in (first, second)]
        return np.any(a != b, axis=2)

    def fresh_front(self):
        self.target("ClearFrameworkEffects")
        self.target("ResetView")
        self.target("FaceView")

    def side_sample(self, mode, kind, degrees, pitch=0):
        self.fresh_front()
        self.target("FrameworkLock")
        name = f"{mode}_{kind}_{degrees:+d}" + (f"_pitch{pitch:+d}" if pitch else "")
        baseline = self.capture(name + "_birth_empty")
        self.target("Comic_" + kind)
        born = self.capture(name + "_birth_visible")
        self.compare(name + "_born_visible", baseline, born, False)
        self.target("FrameworkLock")
        self.rotate(degrees, pitch)
        self.target("FrameworkLock")
        a = self.capture(name + "_hair_effect")
        self.target("DiagnosticHideHair")
        b = self.capture(name + "_nohair_effect")
        self.target("ClearFrameworkEffects")
        c = self.capture(name + "_nohair_empty")
        self.target("DiagnosticHideHair")
        d = self.capture(name + "_hair_empty")
        self.compare(name + "_hair_toggle_effective", c, d, False)
        visible, uncovered = self.mask(a, d), self.mask(b, c)
        sample = {"mode": mode, "kind": kind, "requested_yaw": degrees, "requested_pitch": pitch,
                  "images": {"hair_effect": a, "nohair_effect": b, "nohair_empty": c, "hair_empty": d},
                  "visible_pixels": int(visible.sum()), "without_hair_pixels": int(uncovered.sum()),
                  "hair_blocked_pixels": int((uncovered & ~visible).sum()),
                  "visible_outside_uncovered": int((visible & ~uncovered).sum())}
        self.report["occlusion_samples"].append(sample)
        print("OCCLUSION " + str(sample), flush=True)
        self.target("FrameworkLock")

    def back_sample(self, mode):
        self.fresh_front()
        self.target("FrameworkLock")
        base = self.capture(mode + "_front_empty")
        self.target("Comic_anger")
        self.compare(mode + "_front_born_visible", base, self.capture(mode + "_front_born"), False)
        self.target("FrameworkLock")
        self.rotate(180)
        self.target("FrameworkLock")
        before = self.capture(mode + "_back_held")
        self.target("DiagnosticHideHair")
        hidden_hair = self.capture(mode + "_back_nohair_held")
        self.target("ClearFrameworkEffects")
        self.compare(mode + "_back_hidden_even_without_hair", hidden_hair,
                     self.capture(mode + "_back_nohair_empty"), True)
        self.target("DiagnosticHideHair")
        empty = self.capture(mode + "_back_empty")
        self.compare(mode + "_front_born_hidden_at_back", before, empty, True)
        self.target("Comic_anger")
        self.compare(mode + "_rear_born_visible", empty, self.capture(mode + "_rear_born"), False)
        self.target("FrameworkLock")
        self.rotate(-180)
        self.target("FrameworkLock")
        front = self.capture(mode + "_front_rear_token")
        self.target("ClearFrameworkEffects")
        self.compare(mode + "_rear_born_does_not_relocate_to_front", front,
                     self.capture(mode + "_front_rear_cleared"), True)
        self.target("FrameworkLock")

    def run(self):
        self.identity()
        self.start("first")
        saved = self.saved("saved_baseline")
        self.target("ComicHold")
        for mode in ("scene", "overlay"):
            if mode == "overlay":
                self.target("ComicOverlay")
                self.capture("overlay_selected")
            for kind in ("anger", "sweat"):
                for degrees in (-72, 72):
                    self.side_sample(mode, kind, degrees)
            self.side_sample(mode, "anger", 72, 35)
            self.back_sample(mode)
        self.check("rotation_does_not_change_save", self.saved("saved_after_rotation") == saved)
        self.close()
        self.identity()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = (args.output or host_root() / ".temp/release_comic_rotation" /
              datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    app = RotationDesktop(args.package.resolve(), args.layout.resolve(), output)
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
    print(f"RELEASE_COMIC_ROTATION_{app.report['status'].upper()} {output}", flush=True)
    return 0 if app.report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
