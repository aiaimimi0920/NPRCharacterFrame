# 测试与外部 AI 协作

长期入口位于 [.ci_script](../../.ci_script/)。framework 是框架回归；model 是标准模型合规与共用采集；ai_model 是外部 AI 证据准备工具。测试结果与截图默认写入宿主 `.temp/`，可以删除，不作为运行输入。

在宿主项目根目录执行，下例 `$env:NPR_GODOT_PATH` 由使用方设置为提供的 Godot 可执行文件：

```powershell
& ./addons/npr_character_frame/.ci_script/framework/run_suite.ps1
& $env:NPR_GODOT_PATH --headless --path . --script res://addons/npr_character_frame/.ci_script/model/check_model.gd -- --definition res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres --output res://.temp/model_check
& $env:NPR_GODOT_PATH --path . --audio-driver Dummy --script res://addons/npr_character_frame/.ci_script/model/capture_views.gd -- --definition res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres --output res://.temp/model_views
python ./addons/npr_character_frame/.ci_script/ai_model/prepare_review.py .temp/model_views
```

首次使用先导入项目，确保公开 Resource 类型可解析。`.ci_script/` 是隐藏目录，Godot 不会自动导入其中内容；这里的 GDScript 无全局 class_name，按明确路径加载，引用已在可见目录导入的模型资源。不要把需要自动导入的 PNG/GLB 新资源放到隐藏测试目录中。

`check_model.gd` 返回 0 表示已执行的定义/几何规则通过，1 表示合规错误，2 表示无法写报告；这不代表视觉效果或所有功能数据已经验收。报告中的 `not_evaluated` 必须保留。

`capture_views.gd` 输出六个固定角度及相机/几何数据。`prepare_review.py` 验证证据完整性，输出小体积摘要与提示词；它不调用 AI。外部程序读取 `ai_request.json` 并附上相对路径指向的六张图片，选择自己的 AI 服务，保存结构化建议。生成请求不能被记作 AI 测试通过。

## 结果字段

- `compliance_errors`：违反明确规则的事实，包含位置、证据、规则和建议。
- `visual_suggestions`：视觉目标差距和修改方向，不自动当作硬性不合规。
- `measurements`：程序取得的数据，必须说明计算范围。
- `not_evaluated`：未覆盖、证据不足或需要人工/AI 判断的内容。

标准用例对见 [cases.json](../../.ci_script/model/cases.json)。无需 AI 的路径可以独立运行；目前“柔和”的程序路径只提供证据和人工复核，不虚构通用审美分数。后续 P05 建立角色面部区域与目标基线后，再增加可校准的曲率测量规则。

现存回归失败见 [开发计划](../design/optimization_plan.md)。套件保留失败退出码并继续收集其它用例结果。自动化运行后检查、清理本次 Godot 子进程。

`run_suite.ps1` 当前执行导入、真实主场景启动及 22 个 GDScript 专项，包含确定性采集时钟、非悬停输入和综合视觉回归；衣装及综合采集后分别实际执行 `analyze_wardrobe.py`、`analyze_visual_directions.py`，任一分析器非零退出使 suite 失败，不能由功能断言通过覆盖。仍**不包含**跨运行历史图像逐字节比较、全部实时动态序列或完整 Release 包验收。不得仅凭 `NPR_CHARACTER_FRAME_SUITE_OK` 宣称全部视觉门禁通过。需要真实 `res://` 替代资源的专项应使用新的宿主 `.temp` 输出目录；运行时使用隔离 APPDATA，避免读取用户方案。

suite 的 `-PythonPath` 默认为 `python`，所选 Python 必须能导入 NumPy 和 Pillow；依赖预检查在创建测试输出、启动 Godot 前执行。优先使用依赖完整的独立环境。Windows 的 APPDATA 隔离可能隐藏 per-user site-packages：如需复用已有用户安装，应在隔离前用同一个 Python 查询 `site.getusersitepackages()`，将返回目录加入本次进程的 `PYTHONPATH`，再设置 APPDATA；不要在项目中写死开发机包路径或修改用户持久环境。

```powershell
# $python 由使用方设为已准备好 NumPy/Pillow 的 Python 可执行文件。
& $python -c "import numpy; import PIL"
& ./addons/npr_character_frame/.ci_script/framework/run_suite.ps1 -PythonPath $python -OutputPath .temp/framework-suite/<新的输出目录>
```

### 衣装严格区域图像门禁

`wardrobe_region_capture.gd` 只在测试中生成 Shader 副本，沿用生产 vertex/fragment 路径、几何、蒙皮、深度、stencil 和 MSAA。R 标记 Face/Hair，G 标记作者 garment_mask 的非零染色域，B 标记当前生产 hosiery_domain；诊断时隐藏描边、地面暂用黑色但仍参与深度遮挡。随后恢复原 shader、诊断参数及地面，要求相机不变且生产像素完全相同。区域不是根据配色后的差分反推，也不是移动或裁剪固定屏幕矩形。

`wardrobe_regions.json` 记录三组 marker、截图 SHA256、尺寸、作者服装掩码身份和恢复收据。分析器核对实际参与门禁的文件身份/尺寸/恢复状态，拒绝空或全域 marker。六种配色要求所有非 G 像素零变化，正背丝袜要求所有非 B 像素零变化，全画面 alpha 必须完全相同；显式头发保护使用 R 非零且 G/B 为零的区域。MSAA 混合像素只要目标 G/B 通道非零，就可能含目标覆盖，不进行任意膨胀/腐蚀，也不对域外引入 1/255 容差。原可见染色/丝袜/表情变化阈值保留，丝袜亮度顺序检查改用实际纯 B 核心域。

原 226 项衣装功能断言保留；当前报告为 239 项，图像分析为 40 项。采集序列末尾另建真实场景，分别注入 Face 误染、服装染色越界、丝袜域越界和 alpha 损坏，要求同一套精确比较能检出，最后校验恢复图的实际文件哈希及 PNG 字节身份。正常配色/丝袜门禁已在 1152×720、1440×900 两种起始尺寸验证；末尾负对照沿用导航测试后的 1440×900，不宣称两种负对照分辨率。

独立分析或验证分析器时，可执行：

```powershell
python ./addons/npr_character_frame/.ci_script/framework/analyze_wardrobe.py .temp/framework-suite/<本轮目录>/wardrobe_regression
$env:PYTHONDONTWRITEBYTECODE = '1'
python ./addons/npr_character_frame/.ci_script/framework/test_analyze_wardrobe.py
python -O ./addons/npr_character_frame/.ci_script/framework/test_analyze_wardrobe.py
```

16 项单测覆盖 1/255 腰部/脸/手指/alpha 污染、无效负对照、无可见染色、恢复不精确、截图或 marker 篡改、空/全域、尺寸、状态、schema 和路径逃逸；分析器不依赖可被 `python -O` 删除的 assert。两种模式都必须通过，保留 JSON 报告与进程退出码。

此合同证明的是当前作者域之外的零变化，不独立证明作者掩码或生产域公式本身的语义/审美正确性，也不替代任意角色、姿态、镜头或外部 AI 复核。动态跨运行采集由下述独立合同追踪，综合视觉微差另行验证。旧固定 ROI 失败、初版无效 Face 负对照、依赖环境失败均保留，不能追认为通过。

### 确定性模拟采集

`capture_clock.gd` 是隐藏测试目录内的调度器，不是运行时限帧或游戏时间接口。衣装及显示测试为每个新驱动绑定该时钟：保留原有 `automatic=false`，再停止 Node 的自动 process；每个测试明确请求的等待槽手动调用原 `_process(1.0/60.0)`，而不是把不确定的实际帧 delta 交给驱动。原有明确的姿态调用、UI 输入、保存/重建、次级运动/头发/碰撞设置均保留；额外 GPU 提交等待和区域诊断绘制不推进模拟。60 Hz 是本采集协议，不改变用户运行时的更新频率。

两项报告的 `capture_states` 为每张图记录测试时钟 ticks、固定步长、clip_time、调度所有权和模拟状态 SHA256。ticks 只统计此调度器的更新，不包含测试中原有的显式 `apply_pose()` 调用；状态摘要包含骨矩阵、脸部权重、弹簧位置/速度、头发累积器/当前和前一位置、表情输出。重建会重新绑定并从 0 计数。重复采集应同时比较图像和这些记录，不能以状态一致代替 GPU 像素一致。

`capture_clock_regression.gd` 在真实展示场景中固定 clip_time=1.5，开启次级运动、头发、碰撞及风，执行 48 个固定步。插入额外渲染等待、释放后新建场景都必须得到完全相同的模拟字节及 GPU 像素；同样更新次数但把 delta 加倍必须产生实际状态/图像差异，每组还检查相对初始帧的可见动态响应。因此不是关闭动态效果或只验证空场景。该 26 项专项已接入 suite；真实衣装/显示的跨进程重复证据和保留差异见 [实施记录](../design/implementation_status.md)。它不代替实时自动眨眼时序、音频播放、雨水、综合视觉或完整 Release 验收。

### 非悬停 UI 采集

`capture_pointer.gd` 在衣装截图前向 root viewport 注入控件外的鼠标 motion，然后沿用原有绘制等待和模拟步数。它不 warp 系统鼠标、不清空 tooltip_text、不改主题或 tooltip 延时；产品仍正常支持悬停提示。这是非悬停截图的输入合同，不用于要求悬停外观的截图。

`capture_pointer_regression.gd` 在 1152×720、1440×900 的真实展示中，先证明 Palette0 的提示框在实际墙钟延时后可见并改变 GPU 像素，再验证移出后的全画面精确恢复及待显示计时器的取消。保存状态、模拟字节和原 tooltip 文本必须保持。只靠图像裁剪或关闭提示框不能通过该正反对照。跨进程衣装采集仍需比较完整 PNG 集合、48 份模拟记录和原功能检查，不能仅凭提示框专项推断所有图片一致。

## 展示方案保存门禁

### 综合视觉确定性与精确恢复

`visual_directions_regression.gd` 在停止动作自动 process 后，先显式执行与 reset 相同的 `apply_pose(0.0, 0.1)`，使默认参考图经过真实姿态求值，而不是用尚未求值的骨矩阵/方向轴初值比较已求值的重置状态。雨水的 `visual_layers` 自动 process 也交由测试接管，每个明确等待槽调用原 `_process(1.0/60.0)`；原有显式雨水推进和暂停对照保留，且要求确实产生水滴和积水。不改变产品运行频率、每帧预算或效果开关。

每张图在 `captures` 中记录 `inputs` 和 `rain_stats`：动作模拟字节、雨水的水滴/积水/随机数状态等摘要、所有主材质及 next_pass 的有效参数摘要。材质未设置 override 时通过实际 RenderingServer 获取 shader 声明默认值，不将未设置误当成不同于显式默认值；不舍入浮点或忽略具体诊断参数。纹理记录资源路径，摘要不替代实际 GPU 图片或纹理内容校验。默认/重置必须同时满足输入摘要和 PNG 字节完全相同。

分析器按完整 RGBA 比较 default/reset、eye_temporal_neutral/eye_temporal_reset，要求零个差异像素；旧有 `<400`、`<120` 恢复容差不再使用。其它可见响应门槛保留，并非所有历史 ROI 判定都因此变成独立语义域证明。8 项内存单测覆盖 1/255 RGB、alpha、旧 ROI 外污染、真实响应缺失和 CLI 失败传播；普通 Python 与 `python -O` 均需通过。

```powershell
python ./addons/npr_character_frame/.ci_script/framework/analyze_visual_directions.py .temp/framework-suite/<本轮目录>/visual_directions_regression
$env:PYTHONDONTWRITEBYTECODE = '1'
python ./addons/npr_character_frame/.ci_script/framework/test_analyze_visual_directions.py
python -O ./addons/npr_character_frame/.ci_script/framework/test_analyze_visual_directions.py
```

跨进程重复仍须核对全部 11 张图和采集记录。此固定输入采集不代替实时自动眨眼、音频口型、长雨水序列、所有视角或第二标准角色验收。

`pupil_scale_persistence_regression.gd` 已接入 framework suite。它从真实眼控制器设置 0.65/1.35 端点，经磁盘 JSON、正式加载器、完整场景重建及再次保存验证左右眼独立值和文件字节保持。控制器使用 Vector3 的 real_t 精度，加载器接受数学端点与实际向量端点构成的最小闭区间，不对输入四舍五入、不使用任意容差；端点外 1e-9、明显越界、非有限值及错误类型仍必须拒绝，且失败不得部分修改状态。此项不改变 schema 10，也支持此前已写入的向量端点值。

```powershell
& ./addons/npr_character_frame/.ci_script/framework/run_validation.ps1 -GodotPath $env:NPR_GODOT_PATH -Mode capture -OutputPath .temp/pupil_persistence -TestScript res://addons/npr_character_frame/.ci_script/framework/pupil_scale_persistence_regression.gd -TimeoutSeconds 180
```

漫画校准专项 `comic_profile_regression.gd` 已接入 framework suite，覆盖非法字段拒绝、基础可选性、definition 错误传播、替代配置实际画面变化/精确恢复、独立角色材质，以及公开单角色查询与原私有几何查询等价。卡片位置另以保留的旧 private-query 路径独立计算，核对实际偏移和透视缩放；查询包含命中/未命中、隐藏节点、camera mask 和非法 role/ray。

```powershell
& ./addons/npr_character_frame/.ci_script/framework/run_validation.ps1 -GodotPath $env:NPR_GODOT_PATH -Mode capture -OutputPath .temp/comic_profile_review -TestScript res://addons/npr_character_frame/.ci_script/framework/comic_profile_regression.gd -TimeoutSeconds 600
```

同时以 `comic_spawn_pin_regression.gd` 的 96 图/227 检查及 `framework_quality_comic_regression.gd` 的 33 图/121 检查做前后对照。P05-BB 保留旧边缘位置的部分可见负对照，新增完整头发覆盖位置的 SCENE、Overlay、移除头发 GPU 对照；覆盖采样仅验证夹具前提，不代替真实图像。原 28 图/110 检查失败证据保留，不能追认为通过。外部模型复核见 [漫画用例](../model_authoring/tests/comic_review.md)；新增配置及本机遮挡专项不是任意骨架适配或第二角色验收。

骨骼诊断端点另由 `rig_layout_data_regression.gd` 验证，已接入 framework suite。该项固定四动作、两个时间点，分别采集 render/white/skeleton；检查精确恢复、保存状态不变、角色自有端点的实际动画跟随，以及非法骨序/父级/坐标/零长骨段拒绝。替代 JSON 夹具写宿主 `.temp/framework/` 以提供真实 `res://` 路径，报告记录其位置；它不是正式运行输入。

```powershell
& ./addons/npr_character_frame/.ci_script/framework/run_validation.ps1 -GodotPath $env:NPR_GODOT_PATH -Mode capture -OutputPath .temp/rig_layout_review -TestScript res://addons/npr_character_frame/.ci_script/framework/rig_layout_data_regression.gd -TimeoutSeconds 300
```

使用新的输出目录及隔离 APPDATA。骨骼端点专项不代替 `wardrobe_display_regression.gd` 的全控件流程、完整 Release 或第二角色验收。P05-BA 已按当前服装页 EquipmentSlot0–3、丝袜页 StockingTransparency 及 fitted ShaderMaterial 修复过期显示夹具，完整 190 项已接入 suite；保留原 null 错误证据，不归因为生产控件缺失。动态骨骼跨运行截图差异另行追踪，不以模式内精确恢复通过代替。

当前展示方案写入 schema 10；schema 6–9 是加载时迁移的历史格式，不是新保存文件的预期版本。`visual_directions_regression.gd` 在既有六方向采集序列中调用实际保存方法，检查磁盘 JSON 的完整字段、schema 10 和加载后的精确状态，同时确认 dirty 清除、`.tmp` 已提交。JSON 将数字解析为 float，因此先精确比较 JSON 表示，再通过正式加载器恢复类型并比较原始快照；不使用浮点容差或只检查文件存在。

```powershell
& ./addons/npr_character_frame/.ci_script/framework/run_validation.ps1 -GodotPath $env:NPR_GODOT_PATH -Mode capture -OutputPath .temp/visual_save -TestScript res://addons/npr_character_frame/.ci_script/framework/visual_directions_regression.gd -TimeoutSeconds 600
```

请使用新的输出目录，并在隔离 APPDATA 下运行，避免读取用户的默认方案。原有 51 项非保存检查与 11 张图像采集顺序保留；新增检查放在图像采集结束后，覆盖真实场景重载、非默认丝袜/左右眼/符号参数、完整精度保存、schema 6–9 默认值迁移、退役诊断眼不复活、未知版本拒绝及调用方数据不被修改。保存文件检查器另用不存在、截断 JSON、数组、旧版本、缺字段、变值、额外字段和错误角色作负对照。合法 JSON 但不合规的文件还经过展示层真实加载，确认使用默认方案且不覆盖坏文件。当前综合专项为 108 项，原 104 项全部保留；不替代全部图像分析、外部 AI 或第二角色验收。

截断 JSON 的真实加载会由 Godot 输出预期解析错误，因此单独执行，不让正常门禁忽略错误日志：

```powershell
New-Item -ItemType Directory -Path .temp/malformed_save
& $env:NPR_GODOT_PATH --headless --path . --audio-driver Dummy --script res://addons/npr_character_frame/.ci_script/framework/visual_directions_regression.gd -- inspect .temp/malformed_save --malformed-save-only
```

这一负对照必须同时满足：退出码 0；`malformed_save.json` 中 3 项全通过；输出 `MALFORMED_SAVE_NEGATIVE_OK`；日志恰好一条 `ERROR: Parse JSON failed. Error at line 0: Expected '}'`，无其它错误/警告；`save_truncated.json` 仍只有 `{`。不能仅凭退出码认定成功，也不能将此预期错误规则应用到常规 `run_validation.ps1`。运行结束仍需核对仅本次 Godot 测试进程已退出。

### 作者镜头回归

`showcase_camera_regression.gd` 纳入 suite，输出 `showcase_camera.json` 和固定 GPU 构图。覆盖数组顺序、有限值/正距离/FOV、基础可选与完整展示必需、原视图切换语义、配置深复制隔离、替代校准实际画面变化、A/B 锁及方案保存不变。历史 PNG 字节和相机记录对比是额外跨运行检查，不由单轮功能断言替代。数值合法不能证明头脚完整、面部大小或软组织观察区域适合作者角色。


### 配色与默认方案兼容门禁

`palette_contract_regression.gd` 使用真实展示按钮、Body 材质和 GPU 截图，验证原材质 0、自定义 -1、保存 RGB 权威性、schema 1–9 迁移及磁盘字节往返。`fixtures/silver_wolf_schema10_defaults.json` 来自 .55 真实包的默认保存文件，只用作历史兼容基线，不参与产品运行。负对照实际开启原材质槽位染色并要求检测变化与精确恢复。角色归属和后续提取边界见 [配色审计](../design/palette_ownership_audit.md)。

### 作者配色配置回归

`showcase_palette_profile_regression.gd` 已接入 suite，输出 `showcase_palette_profile.json`。在真实展示中使用三组替代配色与非零默认槽位，检查标签/色块、实际点击、GPU 变化、保存 RGB 权威性、源配置修改隔离、重置/路径重载/重建及精确像素恢复。状态级覆盖非法资源、缺失配置、实例隔离、索引范围原子拒绝和 schema 1–9 迁移。与原 `palette_contract_regression.gd` 并行保留，不替代原样例与存档兼容门禁；替代配色不等于第二标准角色。实际导出包另行验证颜色弹窗交互。

### 袜口高度与默认校准合同

`hosiery_height_contract_regression.gd` 已接入 suite，输出 `hosiery_height_contract.json`，覆盖真实滑块、三消费者、schema 1–10、存档边界、雨水静止坐标和 GPU 精确恢复。校准遗漏放在 observations，不把已知限制钉为正确行为。完整归属与下一步边界见 [默认校准审计](../design/default_state_calibration_audit.md)。可通过 run_validation.ps1 单独运行；既有 hosiery_profile_regression 会在输出目录生成替代法线资源，必须使用宿主 .temp 路径。

P05-BN 显式展示高度配置见 [袜口高度校准](../model_authoring/showcase_height.md)；新增 `showcase_height_profile_regression.gd`，完整 suite 增至 25 阶段。

P05-BO 新增 [实时生命周期门禁](realtime_lifecycle.md)：独立于固定步截图的引擎真实 delta 验证，覆盖三轮创建/暂停/恢复/重置/释放。suite 增至 26 阶段；本轮专项结果不能替代完整 26 阶段重跑。

P05-BP 新增 speech_lifecycle_regression.gd，覆盖实际音频流/mixer 驱动、同片段手动重播的代次隔离、缺省/失败加载、延迟演示取消及退出。suite 后续为 27 阶段；Dummy 输出不构成实际扬声器听感验收。详见 [实时生命周期](realtime_lifecycle.md)。

P05-BQ 新增 `visibility_lifecycle_regression.gd`，覆盖直接/父节点隐藏、显式暂停与 A/B 的精确状态/GPU 恢复、未暂停隐藏策略及独立雨水/漫画时钟、隐藏重置和释放。后续 suite 为 28 阶段；使用 `run_validation.ps1 -Mode capture -TestScript res://addons/npr_character_frame/.ci_script/framework/visibility_lifecycle_regression.gd` 单跑。暂停区间要求 RGBA 零差异，真实时间线之间不比较参考图哈希。合同与边界见 [actor 隐藏与重显示](realtime_lifecycle.md#p05-bqactor-隐藏与重显示)。
