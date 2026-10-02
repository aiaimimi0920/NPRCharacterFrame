# 持续面雨运行时

[`npr_surface_rain.gd`](../../runtime/rain/npr_surface_rain.gd) 是每角色一个的 RefCounted 模拟器；[`npr_rain_field.gd`](../../runtime/rain/npr_rain_field.gd) 管理 GPU 雨滴与水迹场。两者通过 preload 使用，没有全局 class_name。GPU stamp/decay shader 位于 [`shaders/rain/`](../../shaders/rain/)，Body 接收部分继续使用 Body shader。

在 `NPRCharacter` 已初始化、Body 已完成几何/动作装配并具有 `NPRGeometryState` 后调用一次 `setup(actor)`；要求有效 `definition.rain_profile` 及与实际 Body 对应的雨水顶点前缀。模拟器缓存 actor、Body 材质和几何状态，创建 `RainHeads`、`RainTrails` 两个 SubViewport 作为 actor 子节点。它们随 actor 释放；仅丢弃 RefCounted 引用不会删除这两个节点。更换角色需释放旧 actor 并创建新模拟器，不在同一实例上重复 setup。

`configure(rain_enabled: bool, arrivals_per_second: float, random_seed: int, surface_wetness: Vector3, hosiery_height: float, hosiery_opacity: float)` 接收显式值，不读取展示状态对象。调用方保证输入有效：到达率有限且非负，湿润三分量和不透明度有限且在 [0,1]，高度有限并适合角色的 actor 静止空间。接口不替调用方修正无效数据。

`surface_wetness` 的 X/Y/Z 分别对应皮肤、丝袜、服装，眼部湿润不传入雨水模拟。`arrivals_per_second` 是每模拟秒候选到达率，实际水滴出生还受表面分类和容量限制。修改种子或从开启切到关闭会清空状态；只改到达率、湿润值或丝袜参数时保留已有流动和水迹。

showcase 在调用处把原 `droplet_count` 转为到达率 count × 5，把 `stocking_transparency` 转为 `1 - transparency`，并从四湿润区域中提取第 0、1、3 项；原 UI、保存格式和控制范围不变。其它宿主可直接传参，无须构造 wardrobe state。

调用方在动作求值后调用 `advance(delta, speed)`，并负责暂停时停止调用。保留单帧 delta 上限 0.05 秒、最多 320 个水滴、每次 advance 最多 32 次水滴更新，不因迟到帧进行无限追赶；`updates_per_frame` 可降低预算。showcase 仍传入显示速度 × 2.85，暂停/恢复、质量选择和 UI 保存继续由展示层负责。

`clear()` 重置模拟与 GPU 场；`stats()` 提供计数、状态 hash 和更新预算供诊断。停止新雨且保留水迹时调用 `configure(true, 0.0, ...)`，保持种子不变并继续推进模拟；`configure(false, ...)` 关闭效果会清空，二者语义不同。`field.image()` 仅用于验证，会读回 GPU 图像，不应放入正常逐帧路径。

资产格式与验证边界见 [雨水数据](../model_authoring/rain.md)，回归与外部 AI 建议见 [雨水复核](../model_authoring/tests/rain_review.md)。旧隐藏点滴多网格、GLB、标记和响应曲线已删除；showcase 保留持续雨水的状态转换、暂停与重启。原 `contract()` 的 markers、attachments、asset_loaded、mesh_lod、quality_tier、visible 旧几何字段已移除，count 仍表示保存的 UI 密度值。雨水预算由 framework 继续控制，不再连接旧点滴网格 LOD 回调。

近景回归只需两个 Body 三角锚点，现位于 `.ci_script/framework/fixtures/silver_wolf_rain_anchors.json`，由测试辅助脚本采样实际变形几何；不随运行包交付，不参与生产角色加载。它们保留旧近景目标的重心坐标和 0.45 mm 偏移，不能当作其它角色的模型标准。

## 真实调度与残留基线

[`rain_realtime_regression.gd`](../../.ci_script/framework/rain_realtime_regression.gd) 保留展示雨水的真实 `_process()`，不手动调用 `advance()`。仅冻结角色姿态以隔离水的变化：先等待骨骼 palette 首次发布，再从实际变形表面确定近景相机。首次渲染前后锚点存在微小差异，不能先用未同步锚点拍 dry、再用已同步锚点拍 restored；专项记录相机、锚点、mesh transform 和姿态时钟，并要求恢复时精确一致。

专项自然降雨八秒，以同种子 `configure(true, 0.0, ...)` 停止新输入并等待全部水滴自然退场。CPU 粒子归零后，GPU heads 每个 texel 必须为零，而 trails 仍有水；暂停时 CPU/RNG、两张 GPU 场和实际画面字节不变。只切换 Body 的雨水材质开关，验证无活水滴时残留仍改变画面且 A/B 恢复 RGBA 零差异。继续运行约八秒，残留探针应保持非零并单调衰减；`wall_seconds` 从衰减起点计，`simulation_seconds` 独立记录。理论 `exp(-0.13 * simulation_seconds)` 仅作参考，不把 GPU 半精度累积当作精确解析解。

重启检查所有水迹/水滴 texel 清零，并用单个微弱 texel 的负对照检验检测器；不以缩小后的平均图判断“全空”。关闭效果后的 dry/restored 为全画面 RGBA 零差异。每个采样帧检查更新数不超当前预算、活动数不超 320；截图/GPU 读回、状态序列化和文件输出仅属于测试开销，不能把该运行的帧间隔当作产品性能基准或 60 FPS 保证。

两组各 60 帧近景保存自然水滴的 slot、age、triangle、bary、world/screen 坐标及真实采集时刻。记录的是 CPU 表面轨迹，不是 GPU 插值后质心；水滴可能在序列中自然退场。它们用于继续检查实际可见水滴的贴面、遮挡、跨 chart 过渡和闪烁，单靠有限坐标、像素发生变化或固定步 witness 通过，不宣称全场景视觉连续性完成。实际包验证可由匹配引擎加载 PCK，再运行包外专项和 fixture；这证明包内生产资源/逻辑，不等于导出 EXE 全部桌面控件或 Release 验收。
