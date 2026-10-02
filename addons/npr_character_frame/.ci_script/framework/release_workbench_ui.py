"""实际 Windows Release EXE 工作台切片；不注入脚本、不调用包内方法。"""

from __future__ import annotations

import argparse
import ctypes as ct
from ctypes import wintypes as wt
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import traceback

import numpy as np
from PIL import Image, ImageGrab


STAGE = (220, 110, 1050, 785)  # 固定在操作前；排除导航、动态文案和底栏。


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def host_root() -> Path:
    return next(p for p in Path(__file__).resolve().parents if (p / "project.godot").is_file())


class Desktop:
    def __init__(self, package: Path, layout: Path, output: Path):
        self.package, self.output = package, output
        self.layout = json.loads(layout.read_text(encoding="utf-8"))
        self.report = {"checks": [], "inputs": [], "images": {}, "processes": [],
                       "package": str(package), "stage_roi": STAGE,
                       "input_method": "directed Win32 mouse messages, including embedded menu rows",
                       "boundaries": ["not all desktop controls", "Dummy audio is not listening acceptance",
                                      "not long-term or cross-device acceptance"]}
        self.proc = None
        self.hwnd = None
        self.logs = []
        self.diagnostic = 0
        self.user = ct.WinDLL("user32", use_last_error=True)
        signatures = {
            "PostMessageW": ([wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM], wt.BOOL),
            "GetClientRect": ([wt.HWND, ct.POINTER(wt.RECT)], wt.BOOL),
            "ClientToScreen": ([wt.HWND, ct.POINTER(wt.POINT)], wt.BOOL),
            "GetWindowThreadProcessId": ([wt.HWND, ct.POINTER(wt.DWORD)], wt.DWORD),
            "SetWindowPos": ([wt.HWND, wt.HWND, ct.c_int, ct.c_int, ct.c_int, ct.c_int, wt.UINT], wt.BOOL),
            "SetForegroundWindow": ([wt.HWND], wt.BOOL),
            "GetForegroundWindow": ([], wt.HWND),
            "IsWindowVisible": ([wt.HWND], wt.BOOL),
        }
        for name, (args, result) in signatures.items():
            fn = getattr(self.user, name)
            fn.argtypes, fn.restype = args, result
        self.user.SetProcessDPIAware()
        output.mkdir(parents=True, exist_ok=False)
        (output / "appdata").mkdir()
        shutil.copyfile(layout, output / "layout.json")
        shutil.copyfile(__file__, output / "driver.py")

    def check(self, name: str, passed: bool, **details) -> bool:
        self.report["checks"].append({"name": name, "passed": bool(passed), **details})
        print(("PASS " if passed else "FAIL ") + name, flush=True)
        return bool(passed)

    def identity(self) -> None:
        manifest = json.loads((self.package / "build.json").read_text(encoding="utf-8"))
        if manifest["configuration"] != "release" or manifest["status"] != "success":
            raise RuntimeError("A successful Release package is required")
        artifacts = {name: digest(self.package / name) for name in manifest["artifacts"]}
        if artifacts != manifest["artifacts"]:
            raise RuntimeError("Package artifact identity mismatch")
        inputs = json.loads((self.package / "source-inputs.json").read_text(encoding="utf-8"))
        mismatches = []
        for row in inputs:
            path = host_root() / row["path"]
            data = path.read_bytes()
            if row["path"] == "project.godot":
                # build.py 在 Windows staging 中重写版本和 CRLF；其余文件逐字节验证。
                project = re.sub(r'^config/version="[^"]+"',
                                 f'config/version="{manifest["release_version"]}"',
                                 path.read_text(encoding="utf-8"), flags=re.M)
                data = project.replace("\n", "\r\n").encode("utf-8")
            if hashlib.sha256(data).hexdigest() != row["sha256"]:
                mismatches.append(row["path"])
        if mismatches:
            raise RuntimeError("Source layout and package inputs differ: " + str(mismatches))
        self.report["artifacts"] = artifacts
        self.report["source_inputs"] = len(inputs)
        self.check("release_identity", True, source_inputs=len(inputs))

    def start(self, name: str) -> None:
        env = os.environ.copy()
        env["APPDATA"] = str(self.output / "appdata")
        self.logs = [open(self.output / f"{name}.{suffix}.log", "wb") for suffix in ("stdout", "stderr")]
        self.proc = subprocess.Popen(
            [str(self.package / "NPRShowcase.exe"), "--audio-driver", "Dummy", "--resolution",
             "1440x900", "--position", "20,20", "--quit-after", "60000"],
            cwd=self.package, env=env, stdout=self.logs[0], stderr=self.logs[1])
        self.report["processes"].append({"name": name, "pid": self.proc.pid})
        callback_type = ct.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            windows = []

            @callback_type
            def collect(hwnd, _):
                pid = wt.DWORD()
                self.user.GetWindowThreadProcessId(hwnd, ct.byref(pid))
                rect = wt.RECT()
                self.user.GetClientRect(hwnd, ct.byref(rect))
                if pid.value == self.proc.pid and self.user.IsWindowVisible(hwnd) and rect.right > 1000:
                    windows.append(hwnd)
                return True

            self.user.EnumWindows(collect, 0)
            if windows:
                self.hwnd = windows[0]
                break
            if self.proc.poll() is not None:
                raise RuntimeError("Package exited before opening a window")
            time.sleep(0.5)
        else:
            raise RuntimeError("Package did not open a window")
        self.user.SetWindowPos(self.hwnd, wt.HWND(-1), 0, 0, 0, 0, 0x0013)
        self.user.SetForegroundWindow(self.hwnd)
        time.sleep(15)
        self.diagnostic = 0
        self.client_bounds()

    def client_bounds(self) -> tuple[int, int, int, int]:
        rect, origin = wt.RECT(), wt.POINT()
        if not self.user.GetClientRect(self.hwnd, ct.byref(rect)):
            raise RuntimeError("Cannot read client rectangle")
        if (rect.right, rect.bottom) != (1440, 900):
            raise RuntimeError(f"Unexpected client size: {rect.right}x{rect.bottom}")
        if not self.user.ClientToScreen(self.hwnd, ct.byref(origin)):
            raise RuntimeError("Cannot read client origin")
        return origin.x, origin.y, origin.x + rect.right, origin.y + rect.bottom

    def post(self, message: int, wparam: int, lparam: int, hwnd=None) -> None:
        if not self.user.PostMessageW(hwnd or self.hwnd, message, wparam, lparam):
            raise ct.WinError(ct.get_last_error())

    def click(self, rect) -> None:
        x, y = round((rect[0] + rect[2]) / 2), round((rect[1] + rect[3]) / 2)
        if not (0 <= x < 1440 and 0 <= y < 900):
            raise RuntimeError(f"Offscreen target: {rect}")
        pos = (y << 16) | x
        self.post(0x0200, 0, pos)
        self.post(0x0201, 1, pos)
        time.sleep(0.08)
        self.post(0x0202, 0, pos)
        time.sleep(0.3)
        self.post(0x0200, 0, (795 << 16) | 1020)

    def target(self, name: str, page: int = 8, click: bool = True):
        if name in self.layout["globals"]:
            rect = self.layout["globals"][name]
        else:
            self.click(self.layout["globals"][f"Section{page}"])
            time.sleep(0.2)  # 真实归属文案更新后再定位，不冻结标签。
            key = "8_diagnostic_1" if page == 8 and self.diagnostic == 1 else str(page)
            measured = self.layout["pages"][key]
            control = measured["controls"][name]
            bounds = self.client_bounds()
            area = measured["scroll"]
            # 在滚动条内滚动，避免面部页 HSlider 吞下滚轮并改变方案。
            x, y = round(area[2] - 3), round((area[1] + area[3]) / 2)
            self.post(0x0200, 0, (y << 16) | x)
            for _ in range(control["wheel"]):
                self.post(0x020A, (-120 * 65536) & 0xFFFFFFFF,
                          ((bounds[1] + y) << 16) | (bounds[0] + x))
                time.sleep(0.045)
            time.sleep(0.25)
            rect = control["rect"]
        self.report["inputs"].append({"target": name, "page": page, "click": click,
                                       "diagnostic": self.diagnostic, "rect": rect,
                                       "time": time.monotonic()})
        if click:
            self.click(rect)
        else:
            self.post(0x0200, 0, (795 << 16) | 1020)
        return rect

    def option(self, name: str, index: int, page: int = 8) -> None:
        key = "8_diagnostic_1" if page == 8 and self.diagnostic == 1 else str(page)
        measured = self.layout["pages"][key]["controls"][name]
        if not 0 <= index < len(measured["items"]):
            raise ValueError("Option index outside measured menu")
        self.target(name, page)
        self.capture(f"menu_{len(self.report['inputs']):03d}_{name}")
        left, top, right, bottom = measured["popup"]
        # 本切片只使用无分隔符、等高文本行的三个菜单；点击实际嵌入式 Popup。
        row = (bottom - top - 4) / len(measured["items"])
        y = top + 2 + (index + 0.5) * row
        self.click((left, y - 1, right, y + 1))
        time.sleep(0.4)
        self.report["inputs"].append({"option": name, "index": index, "popup": measured["popup"]})
        if name == "DiagnosticMode":
            self.diagnostic = index

    def capture(self, name: str) -> str:
        time.sleep(0.2)
        self.user.SetWindowPos(self.hwnd, wt.HWND(-1), 0, 0, 0, 0, 0x0013)
        path = self.output / f"{name}.png"
        ImageGrab.grab(bbox=self.client_bounds(), all_screens=True).convert("RGBA").save(path)
        self.report["images"][name] = {"file": path.name, "sha256": digest(path)}
        return name

    def compare(self, name: str, first: str, second: str, equal: bool, roi=STAGE) -> bool:
        a, b = [np.asarray(Image.open(self.output / f"{key}.png").convert("RGBA").crop(roi))
                for key in (first, second)]
        delta = np.abs(a.astype(np.int16) - b.astype(np.int16))
        changed = int(np.any(delta != 0, axis=2).sum())
        return self.check(name, (changed == 0) if equal else (changed > 0),
                          first=first, second=second, equal=equal, roi=roi,
                          changed_pixels=changed, max_channel_difference=int(delta.max()))

    def saved(self, name: str) -> bytes:
        self.target("Save")
        files = list((self.output / "appdata").rglob("silver_wolf_wardrobe.json"))
        if len(files) != 1:
            raise RuntimeError("Expected exactly one isolated saved scheme")
        data = files[0].read_bytes()
        if json.loads(data)["schema"] != 10:
            raise RuntimeError("Unexpected saved scheme schema")
        (self.output / f"{name}.json").write_bytes(data)
        return data

    def close(self) -> None:
        if self.proc is None:
            return
        forced = False
        if self.proc.poll() is None:
            try:
                self.user.SetWindowPos(self.hwnd, wt.HWND(-2), 0, 0, 0, 0, 0x0013)
                self.post(0x0010, 0, 0)
                self.proc.wait(timeout=15)
            except (OSError, subprocess.TimeoutExpired):
                forced = True
                self.proc.kill()  # 仅清理本 driver 持有的 EXE 进程。
                self.proc.wait(timeout=10)
        for stream in self.logs:
            stream.close()
        record = self.report["processes"][-1]
        record.update(exit_code=self.proc.returncode, forced_cleanup=forced)
        logs = "\n".join(Path(stream.name).read_text(encoding="utf-8", errors="replace") for stream in self.logs)
        issues = re.findall(r"^.*(?:ERROR:|WARNING:|Parse Error|Op\w+ is not supported yet\.).*$", logs, re.M)
        self.check(record["name"] + "_exit_and_logs", self.proc.returncode == 0 and not forced and not issues,
                   exit_code=self.proc.returncode, issues=issues)
        self.proc = None

    def run(self) -> None:
        self.identity()
        self.start("first")
        baseline = self.saved("saved_baseline")
        self.target("FaceView")
        diag_rect = self.target("DiagnosticMode", click=False)
        diagnostic_ui = self.capture("normal_diagnostic_ui")
        lock_rect = self.target("FrameworkLock", click=False)
        unlocked_ui = self.capture("unlocked_ui")
        self.target("FrameworkLock")
        base = self.capture("locked_a")
        time.sleep(2)
        stable = self.capture("locked_b")
        if not self.compare("lock_holds_exact_pixels", base, stable, True):
            raise RuntimeError("Lock fixture is not stable; remaining comparisons are not valid")
        for effect in ["Comic_sweat", "Comic_anger", "Comic_emphasis", "Comic_star_eyes",
                       "Comic_heart_eyes", "Behavior_wave_mouth"]:
            self.target(effect)
            active = self.capture(effect)
            self.compare(effect + "_visible", base, active, False)
            self.target("ClearFrameworkEffects")
            restored = self.capture(effect + "_cleared")
            self.compare(effect + "_clear_restores", base, restored, True)
        self.target("DiagnosticHideHair")
        hidden = self.capture("hair_hidden")
        self.compare("hair_hide_visible", base, hidden, False)
        self.target("DiagnosticHideHair")
        self.compare("hair_restore_exact", base, self.capture("hair_restored"), True)

        self.option("MouthSymbolMode", 1, 6)
        expected_mouth = self.capture("expected_mouth_only")
        self.compare("base_mouth_symbol_visible", base, expected_mouth, False)
        self.option("EyeSymbolMode", 1, 6)
        both = self.capture("both_symbols")
        self.compare("base_eye_symbol_visible", expected_mouth, both, False)
        self.option("DiagnosticMode", 1)
        diag = self.capture("diagnostic_both")
        self.compare("diagnostic_visible", both, diag, False)
        self.option("EyeSymbolMode", 0, 6)
        self.option("DiagnosticMode", 0)
        restored = self.capture("diagnostic_latest_mouth_only")
        self.compare("diagnostic_restores_latest_mouth_only", expected_mouth, restored, True)
        data = json.loads(self.saved("saved_mouth_only"))
        self.check("mouth_only_UI_saved", data == (json.loads(baseline) | {"mouth_symbol": 1}))

        self.option("EyeSymbolMode", 1, 6)
        self.option("MouthSymbolMode", 0, 6)
        expected_eye = self.capture("expected_eye_only")
        self.compare("base_eye_only_differs_from_both", both, expected_eye, False)
        self.option("MouthSymbolMode", 1, 6)
        self.option("DiagnosticMode", 1)
        self.option("MouthSymbolMode", 0, 6)
        self.option("DiagnosticMode", 0)
        restored = self.capture("diagnostic_latest_eye_only")
        self.compare("diagnostic_restores_latest_eye_only", expected_eye, restored, True)
        data = json.loads(self.saved("saved_eye_only"))
        self.check("eye_only_UI_saved", data == (json.loads(baseline) | {"eye_symbol": 1}))
        self.option("EyeSymbolMode", 0, 6)
        self.compare("base_symbols_off_restores", base, self.capture("base_symbols_off"), True)
        self.check("temporary_tools_preserve_saved_bytes", self.saved("saved_after") == baseline)
        self.target("FrameworkLock")
        moving = self.capture("unlocked_a")
        time.sleep(2)
        self.compare("unlock_resumes_animation", moving, self.capture("unlocked_b"), False)

        # 故意带着未保存的临时工具状态退出，重启检查默认控件和持续播放。
        self.target("FrameworkLock")
        self.target("Comic_star_eyes")
        self.target("DiagnosticHideHair")
        self.option("DiagnosticMode", 1)
        self.capture("before_restart_temporary_state")
        self.close()
        self.start("restart")
        self.target("FaceView")
        self.target("DiagnosticMode", click=False)
        normal = self.capture("restart_normal_diagnostic_ui")
        self.compare("restart_diagnostic_normal", diagnostic_ui, normal, True,
                     tuple(round(x) for x in diag_rect))
        self.target("FrameworkLock", click=False)
        restarted = self.capture("restarted_ui")
        self.compare("restart_lock_control_off", unlocked_ui, restarted, True,
                     tuple(round(x) for x in lock_rect))
        hair = self.layout["pages"]["8"]["controls"]["DiagnosticHideHair"]
        lock = self.layout["pages"]["8"]["controls"]["FrameworkLock"]
        if hair["wheel"] != lock["wheel"]:
            raise RuntimeError("Restart hair control needs a separately aligned capture")
        self.compare("restart_hair_control_off", unlocked_ui, restarted, True,
                     tuple(round(x) for x in hair["rect"]))
        moving = self.capture("restart_live_a")
        time.sleep(2)
        self.compare("restart_live_animation", moving, self.capture("restart_live_b"), False)
        self.check("restart_saved_bytes_unchanged", self.saved("saved_restart") == baseline)
        self.close()
        self.identity()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--layout", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or host_root() / ".temp" / "release_workbench" / datetime.now().strftime("%Y%m%d-%H%M%S")
    app = Desktop(args.package.resolve(), args.layout.resolve(), output.resolve())
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
            c["passed"] for c in app.report["checks"]) else "failed"
        write_json(output / "report.json", app.report)
    print(f"RELEASE_WORKBENCH_{app.report['status'].upper()} {output}", flush=True)
    return 0 if app.report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
