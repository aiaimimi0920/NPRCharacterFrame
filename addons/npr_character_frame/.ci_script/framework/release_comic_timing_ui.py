"""实际 Release 漫画时长/保持/叠层切片；不注入脚本，不比较自然动作跨时刻像素。"""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import shutil
import time
import traceback

from release_style_quality_ui import StyleQualityDesktop
from release_workbench_ui import digest, host_root, write_json


class ComicTimingDesktop(StyleQualityDesktop):
    def __init__(self, package, layout, output):
        super().__init__(package, layout, output)
        shutil.copyfile(Path(__file__).with_name("release_style_quality_ui.py"), output / "locator.py")
        shutil.copyfile(__file__, output / "scenario.py")
        self.report["sources"].update({name: digest(output / name) for name in ("locator.py", "scenario.py")})
        self.report.pop("manual_budget_review")
        self.report["scenario"] = "Comic lifetime, hold/lock, front-view overlay and restart"
        self.report["boundaries"] = [
            "wall-clock brackets, not exact engine delta/lifetime measurement",
            "front view without an introduced occluder; not real depth or back-facing acceptance",
            "hold pauses comic layer, not all expression requests",
            "Dummy audio; not listening, long-term or cross-device acceptance",
        ]
        self.report["timings"] = []

    def wait_for(self, label, seconds):
        start = time.monotonic()
        time.sleep(seconds)
        self.report["timings"].append({"label": label, "requested": seconds,
                                       "elapsed": time.monotonic() - start})

    def clear_probe(self, name, should_be_visible):
        before = self.capture(name + "_before_clear")
        self.target("ClearFrameworkEffects")
        after = self.capture(name + "_after_clear")
        self.compare(name, before, after, not should_be_visible)
        return after

    def run(self):
        self.identity()
        self.start("first")
        saved = self.saved("saved_baseline")
        self.target("FaceView")
        defaults = {}
        for control in ("EffectDuration", "ComicHold", "ComicOverlay"):
            defaults[control] = self.control_image(control, "default_" + control)
        self.target("FrameworkLock")
        baseline = self.capture("locked_baseline")
        self.slider_endpoint("EffectDuration", False)
        self.capture("duration_minimum")
        self.target("Comic_anger")
        minimum = self.capture("minimum_locked")
        self.compare("minimum_visible_while_locked", baseline, minimum, False)
        self.wait_for("locked_beyond_minimum", 1.0)
        self.compare("lock_preserves_minimum", minimum, self.capture("minimum_locked_later"), True)

        # 锁定中启用保持，解锁后仍保留短寿命漫画；重新锁定排除自然动作差分。
        self.target("ComicHold")
        self.target("FrameworkLock")
        self.wait_for("unlocked_held_beyond_minimum", 1.0)
        self.target("FrameworkLock")
        self.clear_probe("hold_survives_unlock_and_short_lifetime", True)
        self.target("Comic_anger")
        held = self.capture("held_before_hold_off")
        self.target("ComicHold")
        self.wait_for("hold_off_but_observation_locked", 1.0)
        self.compare("hold_off_does_not_override_observation_lock", held,
                     self.capture("hold_off_still_locked"), True)
        self.target("FrameworkLock")
        self.wait_for("unlocked_released_minimum", 1.0)
        self.target("FrameworkLock")
        self.clear_probe("released_minimum_retires", False)

        self.slider_endpoint("EffectDuration", True)
        maximum_control, maximum_rect = self.control_image("EffectDuration", "duration_maximum")
        self.target("Comic_anger")
        birth = self.report["inputs"][-1]["time"]
        self.target("FrameworkLock")
        self.wait_for("unlocked_long_lifetime_sample", 0.6)
        self.target("FrameworkLock")
        elapsed = time.monotonic() - birth
        self.check("long_sample_is_before_eight_seconds", elapsed < 7.8, elapsed=elapsed)
        self.clear_probe("long_lifetime_still_visible", True)

        long_base = self.capture("long_expiry_baseline")
        self.target("Comic_anger")
        self.compare("long_expiry_effect_initially_visible", long_base,
                     self.capture("long_expiry_active"), False)
        self.target("FrameworkLock")
        self.wait_for("unlocked_beyond_maximum", 9.0)
        self.target("FrameworkLock")
        self.clear_probe("long_lifetime_retires", False)

        # 前置叠层只在创建卡片时选择 shader；不重新配置已存在的卡片。
        front_base = self.capture("front_base")
        self.target("Comic_anger")
        scene = self.capture("scene_card")
        self.compare("scene_card_visible", front_base, scene, False)
        self.target("ComicOverlay")
        overlay_control, overlay_rect = self.control_image("ComicOverlay", "overlay_on")
        self.compare("overlay_toggle_does_not_mutate_existing_scene_card", scene,
                     self.capture("existing_scene_after_overlay_on"), True)
        self.target("ClearFrameworkEffects")
        self.compare("scene_card_clear_restores", front_base, self.capture("scene_cleared"), True)
        self.target("Comic_anger")
        overlay = self.capture("overlay_card")
        self.compare("overlay_card_visible", front_base, overlay, False)
        self.compare("front_unoccluded_scene_overlay_agree", scene, overlay, True)
        self.target("ComicOverlay")
        self.compare("overlay_off_does_not_mutate_existing_overlay_card", overlay,
                     self.capture("existing_overlay_after_off"), True)
        self.target("ClearFrameworkEffects")
        self.compare("overlay_card_clear_restores", front_base, self.capture("overlay_cleared"), True)

        # 排线使用源脸表面，不消费悬浮卡片的叠层选择。
        self.target("Comic_hatching")
        surface = self.capture("surface_scene")
        self.compare("surface_effect_visible", front_base, surface, False)
        self.target("ClearFrameworkEffects")
        self.target("ComicOverlay")
        self.target("Comic_hatching")
        self.compare("surface_effect_ignores_overlay_selection", surface,
                     self.capture("surface_overlay_selected"), True)
        self.target("ClearFrameworkEffects")
        self.compare("surface_clear_restores", front_base, self.capture("surface_cleared"), True)
        self.check("temporary_comics_preserve_save", self.saved("saved_after_comics") == saved)

        # 重置不重置当前会话的 duration/overlay；但清除效果并取消保持。
        self.target("ComicHold")
        self.target("Comic_anger")
        self.target("Reset")
        self.target("FrameworkLock")
        self.clear_probe("reset_clears_effects", False)
        reset_hold, _ = self.control_image("ComicHold", "reset_hold")
        self.compare("reset_disables_hold", defaults["ComicHold"][0], reset_hold,
                     True, defaults["ComicHold"][1])
        reset_duration, _ = self.control_image("EffectDuration", "reset_duration")
        self.compare("reset_preserves_session_duration", maximum_control, reset_duration, True, maximum_rect)
        reset_overlay, _ = self.control_image("ComicOverlay", "reset_overlay")
        self.compare("reset_preserves_session_overlay_choice", overlay_control, reset_overlay, True, overlay_rect)
        self.check("reset_save_unchanged", self.saved("saved_after_reset") == saved)
        self.target("ComicHold")
        self.target("Comic_anger")
        self.capture("before_restart")
        self.close()
        self.start("restart")
        self.target("FaceView")
        for control, (original, roi) in defaults.items():
            current, _ = self.control_image(control, "restart_" + control)
            self.compare("restart_default_" + control, original, current, True, roi)
        self.target("FrameworkLock")
        self.clear_probe("restart_has_no_effects", False)
        self.check("restart_save_unchanged", self.saved("saved_restart") == saved)
        self.close()
        self.identity()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = (args.output or host_root() / ".temp/release_comic_timing" /
              datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    app = ComicTimingDesktop(args.package.resolve(), args.layout.resolve(), output)
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
    print(f"RELEASE_COMIC_TIMING_{app.report['status'].upper()} {output}", flush=True)
    return 0 if app.report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
