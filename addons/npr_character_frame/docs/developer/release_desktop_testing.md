# 实际 Release 工作台桌面门禁

本入口验证实际导出的 `NPRShowcase.exe`，不是使用编辑器加载 PCK，也不是 PlayGodot fork 或包内注入脚本。CA–CE 与固定 R2 收尾脚本共同覆盖约定的主要操作和保存/恢复流程；不穷举所有参数组合。当前验收范围以 [P05 固定收尾清单](../design/p05_remaining_acceptance.md) 为准，不以历史章节的未覆盖范围继续追加待办。

## 入口与前提

- [release_workbench_layout.gd](../../.ci_script/framework/release_workbench_layout.gd)：实例化实际主场景，保持动态归属/预算标签，测量真实滚轮步数、控件矩形和嵌入式下拉菜单位置。布局阶段可调用 UI 方法，仅用于定位，不计包内功能通过。
- [release_workbench_ui.py](../../.ci_script/framework/release_workbench_ui.py)：独立 APPDATA，向实际 EXE 窗口发送 Win32 鼠标移动/按下/释放/滚轮消息，截取客户区，使用正常“保存方案”按钮核验 schema 和字节。不读写包内对象，不直接写存档。
- Windows 桌面会话须可截图，窗口客户区固定 `1440×900`；测试窗口临时置顶。Python 环境须已有 Pillow 和 NumPy。布局和实际包的生产输入必须匹配；修改运行时后须先重新构建。
- 输入前后检查 `build.json` 三个实际产物哈希与生产输入。`project.godot` 按现有构建脚本的版本替换和 Windows CRLF 重写规则比较，其余文件逐字节核对，不新增引擎兼容检查或降级。

从宿主项目根目录运行，`$env:NPR_GODOT_PATH` 指向用户提供的引擎，`$package` 指向已成功构建的 Release 目录：

```powershell
$package = (Resolve-Path '.export/1.3.0.63').Path
$out = Join-Path $PWD ('.temp/release-workbench/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path "$out/layout/appdata" -Force | Out-Null
$previous = $env:APPDATA
try {
    $env:APPDATA = "$out/layout/appdata"
    rtk powershell.exe -NoProfile -File addons/npr_character_frame/.ci_script/framework/run_validation.ps1 `
        -GodotPath $env:NPR_GODOT_PATH -Mode lab `
        -TestScript res://addons/npr_character_frame/.ci_script/framework/release_workbench_layout.gd `
        -OutputPath "$out/layout" -TimeoutSeconds 180
    if ($LASTEXITCODE -ne 0) { throw 'Layout measurement failed' }
} finally {
    $env:APPDATA = $previous
}
rtk python addons/npr_character_frame/.ci_script/framework/release_workbench_ui.py `
    --package $package --layout "$out/layout/layout.json" --output "$out/desktop"
```

`--output` 不接受既有目录；省略时默认在宿主 `.temp/release_workbench/` 创建时间目录。本机可显式选择独立临时根。driver 保存源码快照、布局、全部输入、PNG、日志、保存方案和 `report.json`；异常保留现场，退出时仅清理本次持有的 EXE，不扫描终止其他项目进程。

## CA：工作台基础切片，35 项检查

1. 包/源码身份前后核对；首次启动和重启的退出码及错误/警告日志。
2. 面部近景下观察锁定保持画面；解锁后恢复实际连续运动。
3. 汗滴、怒气、强调三种卡片；星形眼、爱心眼、短时波浪嘴。各自须产生可见响应，取消后回到同次锁定的原图。
4. 隐藏头发确实改变画面，重新显示后精确恢复。
5. 普通眼嘴符号独立开启；诊断期间改变眼或嘴，退出后恢复**最新**独立输入，不恢复进入诊断前的旧组合。两种预期参考图均在同一锁定中提前采集，另核对保存文件仅改变对应一个字段。
6. 临时工具不改变保存方案；故意带着锁定、隐藏头发、诊断和星眼退出，重启后诊断/锁定/头发控件恢复默认，实时动画继续，保存字节保持。

35 项包含身份和退出检查，不等于 35 个独立控件。图像比较共 27 对，其中 24 对使用固定舞台区域、3 对使用明确的重启控件矩形。

## CB：A/B、角色风格与质量切片，58 项检查

入口 [release_style_quality_ui.py](../../.ci_script/framework/release_style_quality_ui.py) 复用上述 driver、布局与独立 APPDATA。保持同一个成功 Release 包，不为相同生产输入重复构建：

```powershell
rtk python addons/npr_character_frame/.ci_script/framework/release_style_quality_ui.py `
    --package $package --layout "$out/layout/layout.json" --output "$out/style-quality"
```

仅菜单和艺术光滑条的输入定位使用当前实际截图：限制在已测量控件附近，菜单行数、宽度或轨道缺失及多候选一律报错，不猜测点击。它不改变固定舞台 ROI，不以变化区域反推对照范围。[test_release_style_quality_ui.py](../../.ci_script/framework/test_release_style_quality_ui.py) 有 8 项定位合同测试；可用 `NPR_TEST_TEMP_ROOT` 显式指定测试图片输出根。

58 项包含包身份、退出和存档检查，图像比较为 50 对：

- “记录 A”自动锁定；空 B 不替换实时图，A/B 回看及返回实时精确对应记录画面；重置和重启清空两槽。
- 锁定时全身和近/中/远按钮不改变镜头；“角色与灯光”和“仅灯光参数”拒绝应用，只有“仅角色参数”允许固定条件比较。
- 五种角色风格逐项应用并恢复：日常保持原基线，其余四种须有非空响应；每次恢复均 RGBA 零差异。并不覆盖解锁后的完整灯光作用范围。
- 艺术光权重 0 → 1 → 0，须可见变化并精确恢复；预先固定的屏幕下部条带 `[220,650,1050,785)` 保持不变。面部近景中的该条带主要是衣领/胸部，不等同全身非脸区域验证。
- 三档质量镜头实际切换；自动质量稳定后画面不再变化，关闭后恢复手动质量画面和控件。预算文案须另行抽查 `quality_0_auto.png`、`quality_1_auto.png`、`quality_2_auto.png`，不能把开关像素变化当作档位正确的证明。
- 临时风格、A/B、自动质量不污染方案；重置和重启后保存字节与初始方案一致。

CB 证据目录 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_cb_20261001/` 保留首轮选错菜单/滑条的失败及后续复测，最终使用范围与结果见实施记录。预算显示不是 GPU 耗时测量；三个固定镜头也不是连续缩放的迟滞、视觉连续性或全部质量分支验收。

## CC：解锁预设作用范围

[release_scope_ui.py](../../.ci_script/framework/release_scope_ui.py) 使用加入第 4 页“灯光渲染”测量的新布局，验证“侧光与逆光”“体积插画”的三个作用范围。沿用相同命令参数：

```powershell
rtk python addons/npr_character_frame/.ci_script/framework/release_scope_ui.py `
    --package $package --layout "$out/layout/layout.json" --output "$out/scope"
```

先全量应用并记录可见参数，再分别应用仅灯光／仅角色：方位角、高度角、补光、阴影强度与轮廓宽度应匹配相应全量或初始参考；环境光能量、曝光、镜头视场角始终匹配宿主初始值。每项比较同时包含当前值标签和滑条，ROI 来自输入前的布局测量。全量参考须先通过非空变化检查，并人工核对其数值与 `.tres`；不能只用两次相同错误值证明正确。

现有 UI 没有独立动作暂停，故解锁阶段只比较 UI 参数，不比较不同时间的角色画面。应用后重新锁定，再验证重复应用相同角色参数不改变画面，恢复角色参数按 scope 产生可见变化或保持原图。全部恢复及重启读数回到初始，临时操作不改变存档。

此切片只覆盖两种预设和八项可见读数，不证明全部 shader 参数、其余三种预设的所有作用范围、非默认宿主光照配置或完整 Release。实际作用范围以 `NPRStylePreset` 合同为准：灯光是角色拥有的灯光参数，宿主环境光／曝光不属于预设。

## CD：漫画时长、保持与正面叠层

[release_comic_timing_ui.py](../../.ci_script/framework/release_comic_timing_ui.py) 复用布局和外部鼠标 driver，采用独立 APPDATA。命令参数与上述入口相同：

```powershell
rtk python addons/npr_character_frame/.ci_script/framework/release_comic_timing_ui.py `
    --package $package --layout "$out/layout/layout.json" --output "$out/comic-timing"
```

34 项检查包括身份、退出、存档和时长窗口；26 对图像检查中 19 对要求零差异，7 对要求非空响应。持续时间通过实际滑条端点设置并保留读数原图；0.25 秒效果用于检查观察锁定/保持及解锁恢复，8 秒效果用于检查存续及等待 9 秒后的自然退场。自然动作阶段不比较跨时刻角色图；重新锁定后比较“取消本页临时表现”前后，确认当前是否仍有可见效果。墙钟等待不等于精确引擎计时验收。

叠层仅决定新建悬浮卡片使用的深度模式，不追溯修改已有卡片；源脸排线始终走表面效果。本入口只比较正面无遮挡图，未验证遮挡体、旋转背面、全部漫画类型或表情请求与保持的全部组合。

**重置与重启不同**：重置方案清除表现并取消保持，但沿用当前会话的持续时间及叠层选择；重启恢复默认 1.5 秒、保持关闭、叠层关闭。两者均不把这些临时工具选择写入装扮存档。

手动复核：面部近景 → 设 0.25 秒 → 锁定并生成怒气 → 等待，效果应保留；开启保持再解锁，效果仍跟随头部；取消保持后应自然退场。重新锁定后生成卡片，切换叠层不应改变已有卡片。注意保持不是观察锁定，也不承诺暂停所有眼嘴表情请求。

## 图像与输入约束

舞台区域在操作前固定为客户区 `[220,110,1050,785)`，排除导航、动态 UI 文案和底栏，不根据失败差分反推裁剪范围。相同条件的恢复要求 RGBA 零差异；可见响应必须至少有一个变化像素。完整客户区原图同时保留供人工审阅；这是桌面合成图，不是离屏透明缓冲或全角色区域验收。

不要求两次独立启动在自然动作的不同时间产生相同图像。两轮各自在同一次锁定内做严格恢复对照。面部菜单用测得的真实嵌入式菜单行进行鼠标点击，不以发送键盘消息成功当作选择成功；普通符号选择另由存档和画面共同核验。滚轮落在滚动条内，避免普通 HSlider 消费滚轮并修改数值；逐次发送真实滚轮，不把整数首步乘以次数当作精确滚动位置。

2026-10-01 的证据目录为 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_ca_20261001/`。保留了不滚动页面、菜单测量、staging 换行身份和无效键盘选择的历史失败；最终结果及独立像素复算见实施记录 P05-CA，不以空变化通过诊断恢复检查。

## 未覆盖范围与手动观察

### 固定 R2：九页主要流程与组合保存

[release_closeout_ui.py](../../.ci_script/framework/release_closeout_ui.py) 复用实际 HWND 鼠标驱动，使用覆盖九页的布局采集结果。命令参数与 CA–CE 相同，必须使用全新输出目录和隔离 APPDATA。

```powershell
rtk python addons/npr_character_frame/.ci_script/framework/release_closeout_ui.py `
    --package $package --layout "$out/layout/layout.json" --output "$out/closeout"
```

固定测试：装备槽 0 显隐/恢复、透明度两端、薄纱款式/几何、软组织压力、基础表情；分类页风场 1 → 总览 0 → 分类页同步；头发动态/碰撞、雨水启用/密度/湿润、暂停按钮恢复和重播、动作及语音启动/停止；全部代表持久值一次保存重启，再重置保存并重启。存档按完整对象核对预期字段，不把控件点击回执当作成功。雨水时钟/状态与语音时钟/口型语义另复用对应源码生命周期检查，Dummy 不证明听感。

2026-10-02 `rolenpr2_p05_closeout_20261002/desktop_r2` 为 22/22，34 张图、11 对独立 RGBA 复算通过，三个启动均正常退出，方案字节符合预期。首轮任务切换面板遮挡图保留，不放宽断言。结合 CA–CE 结算固定覆盖表，不再要求所有页面每个参数排列均通过。

同日追加真实音频专项：`.63` 使用 `--audio-driver WASAPI`，沿用隔离 APPDATA 和每次重新定位的真实语音按钮，不缓存跨滚动坐标。自然播放与中途停止的系统 render-loopback 录音 20 秒，实际包内 QOA 解码对照 **11/11**，相关系数约 0.99999983，信号误差比 64.60 dB，左右声道一致、停止后静音、退出无错误。100 ms 丢帧、静音、倒放三个负对照被拒绝。原 WAV 经 FFmpeg 理想重采样并不等于包内压缩及引擎固定点插值，原比较失败单独保留，没有降低阈值。证据 `rolenpr2_p05_bt_audio_20261002/audio_desktop_r2/system_output.wav`、`audio_package_verification.json`；不改系统音量/默认设备、不启用麦克风。此结果证明实际系统输出链路，不代替物理扬声器的现场听感反馈。

### CE：真实旋转与出生朝向

CF 诊断补充：[comic_pinned_occlusion_regression.gd](../../.ci_script/framework/comic_pinned_occlusion_regression.gd) 是独立源码/PCK测试，不是本节桌面驱动。它将固定大小的怒气卡片通过公开 `pin()` 固定在真实刘海表面后方，内部点 25/25、轮廓边缘 10/25 深度采样，再验证 SCENE/OVERLAY 同 token、朝向允许、去头发显现及精确恢复。最终源码与 matching-editor/`.63` PCK 各 80/80、各 26 图，跨运行全部 RGBA 相同。该测试绕开工作台 `_pin_spawn()` 的出生避让，不能据此说实际 EXE 的公开 UI 已复现同样遮挡；实际包桌面范围仍以 CE 的结论为准。

[release_comic_rotation_ui.py](../../.ci_script/framework/release_comic_rotation_ui.py) 复用 CC 布局和实际 Release EXE；命令参数同其他桌面脚本：

```powershell
rtk python addons/npr_character_frame/.ci_script/framework/release_comic_rotation_ui.py `
    --package $package --layout "$out/layout/layout.json" --output "$out/rotation"
```

真实鼠标拖动请求 yaw ±72°，怒气另加 pitch +35°；角度是按输入比例换算的请求，不是包内状态读回。开启保持，正面生成后解锁旋转再锁定，同一锁定内采头发/卡片的四种状态。另在两种叠层模式检查正面出生转至背面隐藏、隐藏头发仍隐藏、背面出生可见及转回正面不重新排位。只比较同次锁定的图，不要求跨解锁自然动作相等。

2026-10-01 最终 `rolenpr2_p05_ce_20261001/gui_r2` 为 34/34，79 图、30 对差分和 10 组四状态独立复算一致，5 个负对照检出。四状态 `uncovered & ~visible` 是差分观测，不自动等同充分遮挡证据；当前俯视原图中怒气仍位于头发轮廓外，少量侧面边缘差异不足以证明 SCENE 遮挡或 OVERLAY 穿透。后续 CF 已提供几何关系明确的源码/PCK 夹具；固定收尾不再要求 EXE UI 复刻该夹具，也不以新增角度数量替代有效证据。

手动复核：框架工具 → 面部近景 → 开启保持 → 正面生成怒气 → 解锁并拖到背面 → 重新锁定。卡片应隐藏，隐藏头发后也不应出现；清除并在背面生成新卡片应可见。再解锁转回正面、锁定，新卡片应隐藏而不是搬到脸前。选择前置叠层后重复上述步骤，出生朝向限制仍应有效。本步骤不证明深度遮挡。

当前范围以 [P05 固定清单](../design/p05_remaining_acceptance.md) 为准：CC 已覆盖固定的解锁作用范围，CD 已覆盖代表时长/保持/叠层组合，R2 已覆盖九页主要操作，R3 已完成匹配编辑器 35 分钟运行/资源门禁。它们不证明全部组合、全部视角、跨设备视觉或持续 60 FPS；BT 时序视觉影响与实际语音听感仍等待明确处置，Dummy 音频不是听感证据。这些边界不自动扩为新的 P05 待办。银狼符号曲面仍是拟合预览，不因功能门禁通过而变成正式 authored 资产验收。

手动复核：打开当前 Release → “框架工具” → “查看面部近景” → 锁定相机/动作/灯光 → 依次生成漫画和符号 → “取消本页临时表现”。目标是效果立即可见，取消后恢复原眼嘴及头发位置。再打开“面部表情”的眼嘴符号，在“脸部替换分区”诊断期间关闭其中一路，返回正常渲染时只保留另一路；解锁后动作应继续播放。

CB 手动复核：面部近景 → “记录 A” → 选择“平面动画 / 仅角色参数”并应用 → “记录 B” → 交替查看 A/B → “返回实时渲染”，应回到当前 B 风格而非旧 A；“恢复初始风格”应回到记录前。保持锁定时，选择含灯光的作用范围应提示拒绝。然后解锁，依次切换近/中/远镜头并启用自动质量，检查档位与雨水每帧上限 32/16/8；关闭应恢复手动预算。本步骤不取代实际听感及长期视觉复核。
