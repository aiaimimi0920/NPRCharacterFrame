"""复用实包鼠标 driver，验证 A/B、角色风格和质量工作台；不注入运行时脚本。"""

from datetime import datetime, timezone
import argparse
import shutil
import time
import traceback
from pathlib import Path

import numpy as np
from PIL import Image

from release_workbench_ui import Desktop, STAGE, digest, host_root, write_json


def true_runs(mask, offset=0):
    edges = np.diff(np.r_[False, mask, False].astype(np.int8))
    return [(int(low) + offset, int(high) + offset)
            for low, high in zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1))]


def actual_popup_rect(path, expected, count):
    """当前固定主题的亮色嵌入菜单；仅定位输入，绝不用于裁剪舞台断言。"""
    pixels = np.asarray(Image.open(path).convert("RGB"))
    left, _, right, _ = map(round, expected)
    column = pixels[95:795, left + 3]
    candidates = [(low, high) for low, high in true_runs(np.all(column > 210, axis=1), 95)
                  if 22 * count <= high - low <= 34 * count + 12]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one visible {count}-row popup, found {candidates}")
    top, bottom = candidates[0]
    row = pixels[(top + bottom) // 2, left + 4:right - 4]
    if np.mean(np.all(row > 210, axis=1)) < 0.5:
        raise RuntimeError("Popup width does not match the expected menu")
    return left, top, right, bottom


def actual_slider_y(path, expected):
    """限定已知滑条附近的全宽亮色轨道；缺失或多候选都拒绝点击。"""
    pixels = np.asarray(Image.open(path).convert("RGB"))
    left, top, right, bottom = map(round, expected)
    center = (top + bottom) // 2
    low, high = max(145, center - 55), min(784, center + 56)
    strip = pixels[low:high, left + 12:right - 12]
    bright = (strip[:, :, 0] > 90) & (strip[:, :, 1] > 100) & (strip[:, :, 2] > 70)
    candidates = [(a, b) for a, b in true_runs(np.mean(bright, axis=1) > 0.9, low)
                  if 1 <= b - a <= 12]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one slider track, found {candidates}")
    return sum(candidates[0]) / 2


class StyleQualityDesktop(Desktop):
    def __init__(self, package, layout, output):
        super().__init__(package, layout, output)
        shutil.copyfile(__file__, output / "scenario.py")
        self.report["scenario"] = "A/B, locked character styles, face art weight and screen quality"
        self.report["sources"] = {
            "driver.py": digest(output / "driver.py"),
            "scenario.py": digest(output / "scenario.py"),
            "layout.json": digest(output / "layout.json"),
        }
        self.report["manual_budget_review"] = "pending: inspect three quality_N_auto.png files"
        self.report["boundaries"].extend([
            "unlocked full/lighting-only preset scopes not validated here",
            "budget labels do not prove measured GPU cost or hysteresis boundary behavior",
        ])

    def control_image(self, control, name):
        rect = self.target(control, click=False)
        return self.capture(name), tuple(round(value) for value in rect)

    def option(self, name, index, page=8):
        measured = self.layout["pages"][str(page)]["controls"][name]
        count = len(measured["items"])
        if not 0 <= index < count:
            raise ValueError("Option index outside the measured menu")
        self.target(name, page)
        shot = self.capture(f"menu_{len(self.report['inputs']):03d}_{name}")
        rect = actual_popup_rect(self.output / (shot + ".png"), measured["popup"], count)
        left, top, right, bottom = rect
        y = top + (index + 0.5) * (bottom - top) / count
        self.click((left, y - 1, right, y + 1))
        time.sleep(0.4)
        self.report["inputs"].append({"option": name, "index": index,
                                       "expected_popup": measured["popup"], "actual_popup": rect,
                                       "source_image": shot})

    def slider_endpoint(self, name, high):
        rect = self.target(name, click=False)
        shot = self.capture(f"slider_{len(self.report['inputs']):03d}_{name}")
        y = actual_slider_y(self.output / (shot + ".png"), rect)
        x = rect[2] - 1 if high else rect[0] + 1
        self.click((x - 0.5, y - 1, x + 0.5, y + 1))
        self.report["inputs"].append({"slider": name, "endpoint": "maximum" if high else "minimum",
                                       "actual_y": y, "source_image": shot})

    def preset(self, index, scope):
        self.option("StylePreset", index)
        self.option("StyleScope", scope)
        self.target("ApplyStylePreset")

    def run(self):
        self.identity()
        self.start("first")
        saved = self.saved("saved_baseline")
        self.target("FaceView")
        picker_initial, picker_rect = self.control_image("StylePreset", "initial_style_picker")
        quality_initial, quality_rect = self.control_image("ScreenQualityEnabled", "initial_quality_control")

        # 先记录 A，让真实按钮自动锁定，而不是脚本设置暂停状态。
        self.target("CaptureA")
        original = self.capture("capture_a_live")
        time.sleep(2)
        if not self.compare("capture_a_automatically_holds_pixels", original, self.capture("capture_a_stable"), True):
            raise RuntimeError("A/B observation lock did not hold; remaining fixed-pose comparisons invalid")
        self.target("ShowB")
        self.compare("empty_b_keeps_live", original, self.capture("empty_b"), True)
        for control in ["FullView", "QualityView0", "QualityView1", "QualityView2"]:
            self.target(control)
            self.compare(control + "_rejected_while_locked", original, self.capture(control + "_locked"), True)

        self.preset(3, 0)
        self.compare("all_scope_rejected_while_locked", original, self.capture("all_scope_rejected"), True)
        self.preset(3, 2)
        self.compare("lighting_scope_rejected_while_locked", original, self.capture("lighting_scope_rejected"), True)
        self.preset(3, 1)
        changed = self.capture("character_flat_live")
        self.compare("character_scope_changes_pixels", original, changed, False)
        self.target("CaptureB")
        self.target("ShowA")
        self.compare("show_a_matches_recorded_a", original, self.capture("show_a"), True)
        self.target("ShowB")
        self.compare("show_b_matches_recorded_b", changed, self.capture("show_b"), True)
        self.target("ShowA")
        self.compare("show_a_repeat_is_stable", original, self.capture("show_a_repeat"), True)
        self.target("ShowLive")
        self.compare("show_live_restores_current_b", changed, self.capture("show_live"), True)
        self.target("RestoreStylePreset")
        self.compare("ab_restore_style_exact", original, self.capture("ab_style_restored"), True)

        # 五种角色参数：日常应保持原基线，其余必须有非空响应，逐项精确恢复。
        for index in range(5):
            self.preset(index, 1)
            image = self.capture(f"character_preset_{index}")
            self.compare(f"character_preset_{index}_response", original, image, index == 0)
            self.target("RestoreStylePreset")
            self.compare(f"character_preset_{index}_restore", original,
                         self.capture(f"character_preset_{index}_restored"), True)

        self.preset(3, 1)
        self.slider_endpoint("FaceArtLightWeight", False)
        face_zero = self.capture("face_weight_zero")
        self.slider_endpoint("FaceArtLightWeight", True)
        face_one = self.capture("face_weight_one")
        self.compare("face_weight_has_visible_response", face_zero, face_one, False)
        self.compare("face_weight_preserves_lower_body", face_zero, face_one, True,
                     (220, 650, 1050, 785))
        self.slider_endpoint("FaceArtLightWeight", False)
        self.compare("face_weight_zero_restores", face_zero, self.capture("face_weight_zero_again"), True)
        self.target("RestoreStylePreset")
        self.compare("face_art_style_restores", original, self.capture("face_art_restored"), True)
        self.check("ab_styles_preserve_saved_bytes", self.saved("saved_after_styles") == saved)

        previous_view = None
        for index in range(3):
            self.target("FrameworkLock")
            self.target(f"QualityView{index}")
            self.target("FrameworkLock")
            manual, rect = self.control_image("ScreenQualityEnabled", f"quality_{index}_manual")
            if previous_view is not None:
                self.compare(f"quality_view_{index}_framing_changes", previous_view, manual, False)
            previous_view = manual
            self.target("ScreenQualityEnabled")
            time.sleep(1.2)
            auto, _ = self.control_image("ScreenQualityEnabled", f"quality_{index}_auto")
            self.compare(f"quality_{index}_control_enabled", manual, auto, False, rect)
            time.sleep(1)
            self.compare(f"quality_{index}_settled_pixels_stable", auto,
                         self.capture(f"quality_{index}_auto_stable"), True)
            self.target("ScreenQualityEnabled")
            restored, _ = self.control_image("ScreenQualityEnabled", f"quality_{index}_manual_restored")
            self.compare(f"quality_{index}_manual_pixels_restored", manual, restored, True)
            self.compare(f"quality_{index}_control_off_restored", manual, restored, True, rect)
        self.check("quality_preserves_saved_bytes", self.saved("saved_after_quality") == saved)

        # 带着 A/B 引用和自动质量执行真实重置，必须清除槽位与临时开关。
        self.target("ScreenQualityEnabled")
        self.target("ShowA")
        self.target("Reset")
        self.target("FrameworkLock")
        reset = self.capture("reset_live")
        for slot in ["A", "B"]:
            self.target("Show" + slot)
            self.compare("reset_clears_capture_" + slot, reset, self.capture("reset_show_" + slot), True)
        off, _ = self.control_image("ScreenQualityEnabled", "reset_quality_control")
        self.compare("reset_disables_auto_quality", quality_initial, off, True, quality_rect)
        self.check("reset_saved_bytes", self.saved("saved_after_reset") == saved)

        # 留下未保存的风格/自动质量/A 引用后退出，重启必须不继承这些临时工具。
        self.preset(4, 1)
        self.target("ScreenQualityEnabled")
        self.target("CaptureA")
        self.target("ShowA")
        self.capture("before_restart_temporary_tools")
        self.close()
        self.start("restart")
        self.target("FaceView")
        picker, _ = self.control_image("StylePreset", "restart_style_picker")
        self.compare("restart_default_style_picker", picker_initial, picker, True, picker_rect)
        off, _ = self.control_image("ScreenQualityEnabled", "restart_quality_control")
        self.compare("restart_auto_quality_off", quality_initial, off, True, quality_rect)
        self.target("FrameworkLock")
        restarted = self.capture("restart_live")
        for slot in ["A", "B"]:
            self.target("Show" + slot)
            self.compare("restart_clears_capture_" + slot, restarted,
                         self.capture("restart_show_" + slot), True)
        self.preset(0, 1)
        self.compare("restart_daily_character_is_baseline", restarted, self.capture("restart_daily"), True)
        self.check("restart_saved_bytes_unchanged", self.saved("saved_restart") == saved)
        self.close()
        self.identity()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = (args.output or host_root() / ".temp/release_style_quality" /
              datetime.now().strftime("%Y%m%d-%H%M%S")).resolve()
    app = StyleQualityDesktop(args.package.resolve(), args.layout.resolve(), output)
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
    print(f"RELEASE_STYLE_QUALITY_{app.report['status'].upper()} {output}", flush=True)
    return 0 if app.report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
