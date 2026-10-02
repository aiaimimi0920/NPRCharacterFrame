# P05 固定收尾执行记录

范围以 [固定清单](p05_remaining_acceptance.md) 的 R1–R5 为准。本记录不增设新切片或总组，不将历史“下一步”恢复为待办。

## 当前交付结论（2026-10-02）

原对话 `01a0fc41-7ced-7d10-aa6f-927cb4898987` 于 `2026-10-02T14:57:37.607Z` 收到用户决定：“如果你已经多次尝试都没有找到异常点，那么就先忽略这个异常点把，当前是否可以交付了？”因此 R4 改为**用户接受的 BT 已知限制**，不再阻塞工程包交付，不再继续捕获或随机搜索。BT 未修复，正常观看影响仍未定；所有历史严格失败保留为失败。

本次只进行既有证据复算、包身份核对和文档收口，没有生产、引擎、持久测试修改，没有新 Godot 运行或重新出包。最终验收输入快照仍匹配；30 阶段记录、GDScript 3618 项与衣装图像 40 项、shader 180 项、综合图像 7 项和 332 张历史 RGBA 再次核对通过。R2 的 34 张原图/11 对差分、组合存档/重启复核通过；R3 原始长测数据按同一固定判据复算 14/14；真实系统音频原始证据按相同分析器复算 11/11。406 项生产输入及 Release `.63` 的 EXE/PCK/DLL 身份一致。

**当前可交付既有标准角色框架与本机 Windows 展示包；尚不把 P01–P06 全计划写成完成。** 物理扬声器实际听感未收到反馈，亦未擅自视为用户已接受移交人工。本次已单独请求接收方式确认；在回复前，P05 状态为 `delivery_ready_pending_listening_disposition`，不是最终关闭。此项不是新的音频缺陷或新开发任务。使用入口、边界及接收步骤见 [交付说明](../developer/release_handoff.md)。

本次证据另存 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_delivery_20261002/`，不覆盖此前 `delivery.json`。以下记录保留当时结论，旧“未接受例外/继续定位”不再表示当前待办。

### 后续现场试听（已执行操作，待实际听感反馈）

用户继续推进后，使用同一 `.63` EXE 和 WASAPI 做了一次有界现场试听，复用既有桌面 driver 与页面定位：一次自然播放窗口、一次片尾前的停止操作。独立 APPDATA，不录麦克风或回环，不调整音量/默认设备，不操作保存/重置。两次生产/包身份检查均通过；进程正常退出，日志无错误/警告，复核残留为 0。原始四张截图与动作时间戳保存在 `rolenpr2_p05_listening_20261002/listening_r1/`。

实际截图确认“播放口型示例”和“停止语音”的目标区域；页面顶部的“语音播放中”是 `_play_speech()` 写入的启动提示，而停止按钮直接连接 `speech.stop`，不将该静态提示作为停止后的实时播放状态证明。此轮未录制声音，也没有新的包内状态探针，不能由鼠标输入单独宣称声学停止已验证；程序和系统输出证明仍复用上一轮的真实回环及生命周期测试。

本轮回执为 `interaction_completed_awaiting_user_feedback`，不关闭 P05。已请求用户反馈两段实际听感；用户反馈前停止继续重复试听或集成运行，若报告具体异常再定位对应问题。没有生产/GDScript/引擎改动，不新出包，不重开 BT 或 P06。

## R1：输入合同一致性核对（完成）

2026-10-02 对下列八项做了一次有界静态核对，未发现需要生产修改的明确合同矛盾。主线程抽查制作规范入口与雨水规范，发现入口仍写“尚未形成完全通用的全功能角色配置合同”，与已经列出的专项输入规范不一致；已改为准确区分现有合同、角色专属数据制作和基础检查的边界。没有以静态核对代替模型视觉验收，也没有由未审阅的所有求值路径衍生额外任务。

| 项目 | 已核对的责任文件与规范 | 结论 |
| --- | --- | --- |
| definition | `npr_character_definition.gd` 输入/校验；`model_authoring/README.md` | 基础与全功能可选输入区分一致；修正文档入口过时阶段表述 |
| 眼/表情 | `npr_face_motion_profile.gd`、`runtime/face/npr_face_rig.gd`；`face_motion.md` | 作者输入、诊断眼依赖、运行时装配一致；已有 ownership 回归复用 |
| 动作/口型 | `runtime/npr_performance_data.gd`、`runtime/animation/npr_performance.gd`；`performance.md` | canonical 16 骨、实际顶点数、30 FPS 动作合同一致 |
| 软组织 | `runtime/npr_soft_tissue_data.gd`、`check_model.gd`；`soft_tissue.md` | 稀疏索引及 Body 顶点数检查一致；空形变不冒充视觉效果 |
| 头发 | `runtime/npr_hair_dynamics_data.gd`、`check_model.gd`；`hair_dynamics.md` | schema、追加骨/权重/接触输入一致，视觉和碰撞覆盖另有明确范围 |
| 装备 | `npr_equipment_profile.gd`、`runtime/equipment/npr_equipment.gd`；`equipment.md` | 槽位、骨名、场景/材质输入责任一致 |
| 丝袜 | `npr_hosiery_profile.gd`、`runtime/hosiery/npr_garment_geometry.gd`；`hosiery.md` | 原始未蒙皮 Body 的额外预处理前提已明确，不与基础模型允许蒙皮矛盾 |
| 湿润/雨水 | `npr_wetness_profile.gd`、`npr_rain_profile.gd`、`runtime/rain/npr_surface_rain.gd`；`wetness.md`、`rain.md` | 四图/UV 上限及显式头发 pass 绑定与湿润规范一致；雨水三文件输入和实例状态责任一致，二进制/拓扑检查边界已公开 |

现行 `check_model.gd` 明确列出 `visual appearance`、`full-feature role data`、`texture channel semantics` 为 `not_evaluated`，专项规范未将其冒充通过。合理 canonical 合同、样例默认选择和展示内部协作不再提取。R1 本次核对完成，不另开全库巡检。

## R2：固定主要流程（程序验收及真实系统音频输出完成，物理听感待反馈）

复用 CA–CF 已完成证据。新增 `release_closeout_ui.py` 只覆盖固定清单列出的缺口、一次组合保存/重启及恢复默认；布局探针从既有四页扩为九页，没有修改产品 UI。源码布局通过后在同一 `.63` 实际 EXE 执行，独立 APPDATA，不读写用户方案。

最终 `desktop_r2` **22/22**；34 张原图、11 对 RGBA 比较独立复算通过（4 对严格相等、7 对非空），五个通道污染/空响应负对照检出。装备显隐、丝袜透明度端点、薄纱开关恢复、软组织压力及基础表情有实际可见响应。风场在分类页设 1.00、总览改 0.00、回分类页显示 0.00，存档独立确认只有同一个字段改变；截图人工确认读数和头发两个开关。雨水暂停按钮变化与恢复通过，真实时钟/水状态语义复用 BS 和固定稳定性检查，不把按钮像素变化单独当作粒子暂停证明。

组合值覆盖装备、丝袜款式/透明度、薄纱、头发动态/碰撞/风场、雨水启用/密度、皮肤湿润、动作、压力与表情；完整保存对象与预定字段精确一致，无无关字段污染。一次重启保持组合值，重置并保存后与初始字节相同，再次重启仍相同。语音启动原图显示“语音播放中 / 发音时间轴驱动口型”，随后真实点击停止；时钟/口型停止恢复以既有语音生命周期及最终套件为程序证据，Dummy 不作听感证明。

首次 `desktop_r1` 的薄纱基准图被 Windows 任务切换面板遮挡，严格恢复失败；失败原图、报告保留，没有改变阈值或裁剪区域。新目录重跑整轮通过。三次 EXE 均正常退出、日志无错误/警告，406 生产输入及三个产物保持。证据根 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_closeout_20261002/`，见 `desktop_r2/report.json` 和 `verification.json`。

## R3：35 分钟有界运行（运行/资源门禁完成，时序视觉限制归 R4）

按固定清单预先定义的预热、时长、预算和增长/退化判据执行。不能用本项统计放宽 BT 精确图像门禁。

`closeout_stability.gd` 在匹配编辑器中运行正常场景，动作、眨眼、头发动态/碰撞、风场和最高密度面雨保留真实调度；第 600/1500 秒锁定 2 秒并检查恢复，第 900 秒禁用雨水 2 秒再开启，第 1200 秒重播。性能窗口固定为第 300–600 秒和 1800–2100 秒，均为同配置的无操作阶段；记录实际帧间隔、引擎对象/节点/孤儿/资源及渲染内存，外部 runner 另采进程 Private Bytes。不是实际 Release EXE 的性能测量，不宣称取得引擎未暴露的全部 RID 总数。该长测独立于日常 suite，不将 suite 扩为 31 阶段。

完整 2100 秒运行 **15/15**，EXIT=0 / ISSUES=0，独立分析器 **14/14**。两个性能窗口分别 12157/12507 个实际帧间隔：p50 为 24.329/23.452 ms、p95 为 31.860/31.699 ms、p99 为 37.670/36.760 ms。该结果证明本机该配置未长时退化，不宣称持续 60 FPS 或跨设备性能。

前后各 30 个稳定采样的中位数：对象 3145→3145、节点 248→248、孤儿 0→0、资源 266→266、渲染内存 420950464→420950464 bytes；引擎跟踪内存 235846093→236575441 bytes。外部 Private Bytes 前后各 578 个采样，中位数 1604288512→1612472320 bytes，增长 8183808 bytes（约 7.8 MiB），满足运行前固定上限。所有观察帧最大 32 次雨水更新、320 个活动粒子。两次锁定的动作/雨水时钟严格保持，解锁后继续；临时序列不改变最终配置对象。

本项没有用这些性能数字冒充水滴全帧视觉无闪烁。正常观看影响仍按 R4 的既有有界证据与用户处置结论记录，不再为了时序未知追加随机运行。证据 `stability_r1/` 与 `stability_verification.json`。

## R4：BT 影响处置（历史调查；现已接受已知限制，未修复）

现有失败原图为 1152×720；已记录最大约 73 个像素、每通道差 1，约占 0.0088%。这是量级描述，不是新的接受阈值。关闭雨水材质也曾复现，不能据此修改雨水算法。自然运行已有 GPU 插值与若干时刻单粒子正常材质可见响应，但不是全帧无闪烁证明。

静态差分 x255 拼图不是原速观看证据。当前准确结论为“严格差分失败，根因及正常观看影响未定”，不宣称无可见影响。此前曾提交是否接受列名限制；用户要求尝试解决而非接受例外，后续结果见本文末节。不再追加 sampler/灯光随机搜索，也不用 Dummy 音频假装听感通过。

## R5：最终集成（技术门禁完成；当前接收状态见本文顶部）

固定 30 阶段 suite、生产输入/包身份及当前文档技术门禁已完成，以下保留失败经过。首轮把完整套件输出放在项目外，违反既有 `testing.md` 的 `res://` 临时资源前提，30 阶段中 3 项（眼部、软组织、头发）失败，退出码 1；原日志与全部输出保留在证据根 `suite/`。仅将重跑输出改到全新的宿主 `.temp/framework-suite/p05_closeout_20261002_r2/`，测试及生产断言未改；汇总日志仍在外部证据目录。文档同步更新实际套件数量为 28 项专项＋导入/启动共 30 阶段。R4 未得到明确处置前，不宣称整个 P05 已完成。

第二轮 30 阶段收回，29 阶段通过，语音 `Actual audio completes naturally` 失败，整套退出码 1。原始记录显示自然阶段墙钟已过 5.247970 秒，但 mixer 仍在 4.835555 秒，尚未到 4.963356 秒片尾；原测试将“片长＋0.3 秒墙钟”误用为音频线程完成前提。本地匹配引擎 Dummy 源码逐块混音后休眠，墙钟与播放进度不是锁步。一次独立诊断正常收到真实结束信号，但没有复现原失败；不能把诊断的成功写成原运行已成功。

仅修改 `speech_lifecycle_regression.gd` 的自然结束等待：等待真实 `finished` 信号，片长两倍＋0.3 秒只作有界挂起保护，原“停止”和“口型清空”断言保留，并增加暂停负对照与恰好一次结束信号断言。没有改生产语音、驱动、pitch、seek 或手动触发结束。专项最终 `speech_signal_r2` **31/31**，真实等待 5.015882 秒；屏蔽实际结束信号的负对照即使最终已经停止，仍被新的信号断言拒绝。首个专项的新增暂停断言误认为 paused 时 `playing` 为真，实际引擎返回 false；保留该失败，改为检查明确暂停及仍持有 playback，而非用 `playing` 代替暂停语义。独立核对见 `speech_verification.json`。

第三轮使用全新 `.temp/framework-suite/p05_closeout_20261002_r3/`，按最终测试源码快照重新执行固定 30 阶段；R2 桌面与 R3 长测不重跑。本轮完整运行已经通过，不把第二轮的 29 项通过拼成整套成功。

最终 30 阶段全部 `EXIT=0 / ISSUES=0`，整套退出码 0，输出 `NPR_CHARACTER_FRAME_SUITE_OK`。独立检查最终源码快照未漂移；GDScript **3618/3618**，另有 shader **180/180**、衣装图像 **40/40**、综合图像 **7/7**。与 BY 基线的 **332 张原图**逐 RGBA 相同。406 项生产输入和 `.63` 的 EXE/PCK/DLL 身份保持，无生产修改，不重复出包。详见 `run_r3.json`、`suite_r3.log` 和 `integration_verification.json`。

62 份 Markdown 的 341 个相对文件链接有效；本轮文本 UTF-8 无 BOM，Python AST、GDScript 后置检查及 `git diff --check` 通过。最后进程核对没有 Godot 残留，`process_cleanup.json` 的 `remaining_count=0`；没有停止用户编辑器。未提交、推送或删除历史失败。

## 上一轮交接状态（历史快照）

工程技术门禁已完成。交付回执为 `engineering_gates_passed_pending_user_disposition`，不是 `p05_complete_with_accepted_limits`：尚未收到用户对 BT“影响未定的已知限制”以及实际语音听感移交人工复核的明确决定，因此没有代替用户接受例外。剩余仅为这两项列名处置，不新增开发组、切片、随机重跑或 P06 工作。

如两项均获用户明确接受，记录真实决定后可关闭 P05，并保留 BT 原严格失败、实际听感未验收及长测不等于 Release FPS 的边界；不能更改历史门禁为通过。若用户要求其中一项仍须阻塞，只处理对应既有要求，不重新打开已经结算的 R1/R2/R3/R5 技术成果。

## 2026-10-02：按用户要求尝试解决音频与 BT

用户明确要求尝试解决两项，不是接受例外。前一轮 `delivery.json` 保留为历史技术门禁快照，当前证据根为 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_audio_20261002/`。没有修改生产脚本、shader、引擎、用户音量或默认设备，不开启麦克风；因此既有 30 阶段及 `.63` 身份仍复用，不再重复出包或全套验收。

### 真实音频：系统输出链路验证完成

实际 `.63` Release 改用 WASAPI 启动，通过真实页面控件完成一次自然播放及一次中途停止。默认端点为 Realtek 扬声器，48000 Hz、双声道、未静音；用系统 render-loopback 采集 20 秒原始浮点 WAV。最终 `audio_desktop_r2` 正常退出，日志无错误/警告，406 项生产输入和三个包产物身份保持。首轮临时 driver 缓存了滚动前的按钮坐标，误打开模态文件对话框并在退出时被 owned cleanup 终止；截图/录音/失败报告保留，修正为每次重新定位控件后整轮重跑，不把这次失败归因 WASAPI。

直接与原始 WAV 的 FFmpeg 重采样结果比较时，信号误差比未满足 30 dB 检查；该失败保留。实际资源经 QOA 导入，Godot 使用固定点三次插值，并不等于 FFmpeg 原 WAV 的理想重采样。随后由匹配引擎分别解码源项目导入资源与 `.63` PCK 的实际音频，二者浮点字节 SHA256 相同，再以实际包内解码结果验证输出，未降低原阈值、未对录音做时间扭曲或移除静音区。

最终 **11/11**：完整片段相关系数 **0.9999998266**、信号误差比 **64.60 dB**；第二次起始片段相关系数 **0.9999998762**。录音无削波、无 NaN，无首包之后的不连续或时间戳错误；停止后及两次播放之间恢复静音。人工停止发生在自然片尾之前，停止操作返回后没有继续出声。左右声道最大差约 `2.91e-9`；100 ms 丢帧、静音和倒放错误音频三个负对照均被相同门禁拒绝。详见 `audio_package_verification.json`、`audio_negative_verification.json` 和 `audio_desktop_r2/system_output.wav`。

此证据关闭“只验证 Dummy、没有真实系统输出”的缺口；不等于用麦克风验证扬声器振膜、接线、房间声学或主观听感。已请用户反馈现场听到的情况，未收到反馈前不虚构“亲耳听过”。

### BT：新增可校准的同帧 HDR 观测，本轮未复现

离线复核三个历史坏帧组：68/69/73 个变化像素均只改变一个 RGB 通道的正负一级，Alpha 不变；三组共同的 **48 个坐标连同变化通道和方向完全一致**。多数点在平滑区域。这支持优先调查固定数值路径的低位变化，不足以证明根因或无视觉影响。已核实相关坏帧的 TAA/debanding 关闭，材质时间速度为零，不能仅因 shader 出现 TIME 就修改它。

本轮临时 `CompositorEffect` 在正常透明渲染后、后处理前，通过只读 compute shader 提取已知 **68 个坐标**的 HDR 值，同时保留全图 PNG 严格门禁。未写回颜色、未改材质/雨水/阴影，不注册或启用项目 addon。直接读 HDR 纹理因无 COPY_FROM 标志失败，改用只读采样到独立 buffer；首个 compute 版本 push constant 长度错误也保留。最终 `hdr_r3` **11/11、EXIT=0 / ISSUES=0**，固定 120 帧正常、600 帧观察器、120 帧恢复，共 **840 帧**没有复现漂移，三个阶段正常图像相同，600 个连续 HDR 样本稳定。

另做一次仅用于校准的短序列（不再搜索坏帧），**20/20**：相机轻移同时改变 HDR 与 PNG，恢复后两者精确恢复；后处理亮度改变 PNG 而 HDR 不变，恢复后两者也精确恢复。独立分析确认观察器能区分上述两个阶段，不是读取空 buffer 或把上一帧当当前帧。见 `hdr_verification.json`。

结论是 `diagnostic_valid_not_reproduced`，**不是修复**。读回同步与 resolved-color 访问可能影响时序，不能排除观察器扰动；本轮没有捕获坏帧，不能判定材质/混合与后处理哪一段负责。按有界原则停止同类重跑，保留经过校准的观察器和历史严格失败。BT 仍是 P05 未解决项，没有接受例外，也没有将它挪入 P06。

### BT：GPU 留存与一次读回验证

后续只针对已知的中途同步干扰改进临时诊断：每帧将 68 个 HDR 点和 GPU 帧标记写入独立 SSBO，脱离观察器后一次读回；渲染回调内不再同步读回。未修改生产、持久回归或引擎。证据根 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_ring_20261002/`。

短校准 **44/44**：相机与后处理亮度分别逐帧交替，GPU slot 标记连续，HDR 与 PNG 同帧对应；故意错配后一帧的负对照被拒绝。随后仅执行一次固定 **120/600/120，共 840 帧**的正常/留存/恢复观察，**13/13、EXIT=0 / ISSUES=0**。独立分析重新核对原图 RGBA 哈希、HDR 原字节哈希、600 个连续 slot 与 GPU 标记，三个阶段 PNG 完全一致，留存区只有一个 HDR 状态；两次运行日志无错误，测试进程残留为 0。

`verification.json` 的结论为 `not_reproduced`、`bt_fixed=false`：去除中途 HDR 同步读回后仍未复现，不能据此宣布修复或证明观察器零干扰。额外 compute/resolve 仍存在，最终 PNG 仍逐帧读回。本次不追加同配置随机试跑，不放宽严格差分；下一次定位必须提供新的可检验机制或真实坏帧现场，不能以继续积累正常帧代替修复。R1–R5 范围不变，音频现场反馈尚未收到，历史失败继续有效。

### BT：量化边界的离线机制核对

后续不启动新一轮随机采样，改为对已有失败原图、当前 HDR 留存和匹配引擎颜色路径做离线核对。历史 68 个变化通道在当前 HDR 的理想 sRGB 转换下，距 8 位半整数边界的中位数为 **0.032415 个码值**，同位置 136 个未变化通道为 **0.258586**；41/68 可由相邻 fp16 步长跨过历史一级码值边界。该结果支持“微小数值变化被量化放大为一级差”的敏感性假设，但没有解释微小变化来自哪里。

不能跨运行归因：当前 PNG 的 204 个被检查通道中，30 个不同于历史正常图；CPU 理想转换也仅匹配当前 189/204 个通道，不是 GPU bilinear/算术/attachment 写入的精确模拟。历史无操作序列反复往返两种图像（factors 10 次切换、light 6 次），单次 shader 编译完成替换不能单独解释。原失败图和全图严格门禁均不变。

匹配引擎源码确认 SDR 在 shader 显式 sRGB 编码后写 UNORM，`get_image()` 对 RGBA8 走原字节复制，无 CPU 二次颜色舍入；tonemap push constants 先清零，debanding 无时间项。历史快照另确认 screen-space AA、TAA、debanding、glow 和颜色 adjustment 关闭。未把源码默认值当作未保存的运行实测值。证据 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_quantization_20261002/analysis.json` 与同目录 `README.md` 保存逐坐标数据、输入身份和源码行号。

本轮没有生产修复或新渲染运行，结论为 `quantization_sensitivity_supported_not_cause_proven`。同一真实坏帧的 HDR/最终 attachment 对应关系仍缺失，BT 保持未修复；不通过降低色阶、放宽阈值或无证据归咎引擎来关闭 P05。

### BT：shader 初始化假设核对结束，未发现修复点

对 Body 的 fragment→light→post_light 赋值链、直接 include 及匹配引擎 Forward+ 初始化做一次有界只读核对。`npr_body_post_gain/active`、shadow delta 的 ramp/贡献/gain 等输入在存活 fragment 上均先写后读；诊断 `MATERIAL_LIGHT_DATA` 即使没有匹配灯光也已有初值。引擎每次 fragment 清零 material light data 与各光照累加器，post_light 局部量从已赋值结果初始化；名称映射对应。未发现可达的漏初始化路径，不实施无依据的冗余清零。

具体文件行号、责任和核对边界见 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_initialization_20261002/audit.md`。本项是指定控制流的静态核对，不是生成 GLSL/SPIR-V 或 GPU 行为证明。没有新渲染运行或生产修改，BT 未修复；该假设检查结束，不恢复为全库巡检或随机试跑任务。

### BT：固定 GPU 命令重放入口未建立

恢复会话 `01a0faf6-d96a-7ea0-96aa-b4f7b802b5e2` 后，拟检验同一捕获命令的重复重放能否产生两种颜色，先检查已有 RenderDoc 1.39。普通 `--python` 启动及独立 APPDATA 启动均在 20 秒上限内没有写出脚本入口标记，第二次也未枚举到该进程的顶层窗口；只终止本次拥有的进程。offscreen 的针对性尝试正常返回启动失败日志：`Available platform plugins are: windows.` 没有执行后续捕获或 GPU 重放，不把 API/界面入口问题归因于产品或 GPU 驱动。

`renderdoccmd vulkanlayer --explain` 显示系统注册指向已不存在的旧下载路径，而当前 Program Files 的 1.39 未注册；没有修改注册表、安装工具、修改引擎或新建网络映射。此注册问题只是现场事实，不足以解释 qrenderdoc 脚本超时。Context7 请求失败，API 信息仅来自本机工具帮助与匹配源码，不宣称已获取在线文档。

同轮核对 `render_forward_clustered.cpp:2458–2485`：使用 MSAA 时，颜色 resolve 在调用 POST_TRANSPARENT compositor 前执行；2130–2132 对 access_resolved_color 的前置条件只涉及 PRE_OPAQUE、POST_OPAQUE 和 PRE_TRANSPARENT。因此，旧观察器的 POST_TRANSPARENT/access_resolved_color=true 不能单独证明新增了一次 resolve。未修改观察器或再跑相同采样，不能据此证明其对调度无扰动。

证据 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_capture_20261002/` 保存预定边界、三次入口检查及失败日志。结论为 `capture_entry_unavailable_bt_unresolved`，没有 RDC、没有新 Godot 运行或生产修复；BT 的原严格失败和物理听感待反馈状态继续保留。不重新打开已结算工程门禁，也不将捕获工具问题列成新的产品验收要求。

### BT：抓帧入口恢复，固定 GPU 重放与阶段读取通过

后续没有延长原超时或重装工具，而是采样自有 qrenderdoc 主线程：三次调用栈停在 `QStandardPaths::findExecutable → QFileInfo → NetShareEnum` 的网络查询。PATH 中存在孤立的反斜杠项及其他残缺项。只给测试子进程使用本地 PATH 后，脚本约 1 秒完成；在同一本地 PATH 前仅加回孤立反斜杠，6 秒内再次不进入脚本；仅保留原 PATH 的完整盘符绝对路径也约 1 秒通过。由此确认启动阻碍，不修改用户/系统 PATH、Vulkan 注册表或网络映射。

RenderDoc 嵌入脚本实际不提供 `__file__`，临时脚本改用显式路径/环境参数。第一次捕获误把 Vulkan capture layer 环境设置在 replay host 自身，引发 `IsCaptureMode(m_State)` 断言及 host 崩溃，保留 crash.zip、日志和原脚本；随后将环境严格限制在目标 Godot 子进程。启动器跟踪实际子进程树并保留句柄，结束时清理自身的 crash handler/conhost 与 renderer，不终止用户编辑器。没有为此给全局 Python 安装依赖。

最终 `capture_r2` 取得两份真实 Vulkan RDC（帧 517/518），场景/状态/保存/清理 **8/8**，Godot 正常退出且无错误。使用既有历史 trigger_r1 的冻结雨水纹理，采集正常 RGBA SHA256 为 `5000c06842a07f6c2bf4fc2b8bc3a32e257abb69d9f9cf517439f5a46f557e2e`，与历史正常图逐字节一致，不是另一个自然雨水快照。人工查看原 PNG 确认为对应丝袜近景。捕获日志显示 RenderDoc 下 Vulkan 1.3.0，历史无捕获运行是 Vulkan 1.4.325；注入与降报 API 版本可能改变执行条件，不能冒充零介入原运行。

`replay_r1` 对每份固定捕获分别强制完整重放 32 次，每次读取 11 个指定纹理资源，64 次均保持各自原始字节；两捕获的相同资源哈希也一致。`ResourceId::3583` 的 1152×720 RGBA8 attachment 精确匹配 Godot 原图。`calibration_r1` 的实际 event 180/227/180（两个 MSAA render pass 结束点）读回证明阶段改变会改变内容、返回同事件精确恢复；最终 RGBA 仍匹配原图，校准 **3/3**。保存四个真实 MSAA 样本、event 229 的 resolve 输出及最终 RGBA。独立 Python/Pillow 复算全部原字节，并拒绝单字节一级污染，不以哈希自报替代解码核验。

正常捕获的 GPU resolve 有 8375 个通道不同于理想四样本平均后转 fp16，但这不自动构成缺陷。与历史坏帧掩码精确对齐后，72 个变化通道中有 70 个的四样本相同，仅 1 个涉及上述平均差异；同位置其余 144 个 RGB 通道均不涉及。该结果不支持用当前这组样本的单纯平均舍入解释整组历史变化，历史异常帧的 MSAA/HDR 内容仍未知；不关闭 MSAA 或更改渲染精度。

证据 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_capture_debug_20261002/`，见 `verification.json`、`resolve_analysis.json`、`README.md`。结论为 `capture_and_replay_calibrated_bt_unresolved`：抓帧工具阻碍解决，BT 未修复、未接受例外。没有生产/引擎修改，不重复 suite 或出包。下一次必须利用真实异常状态定位差异发生阶段；不把 64 次正常重放累计为时间连续性通过，也不增加独立随机采样矩阵。

### BT：预启动同帧捕获校准完成，一次固定窗口未复现

RenderDoc 1.39 本地 `TriggerCapture` API 说明确认后触发捕获的是后续 Present 区间，不能追回已经读到的坏图。本轮没有接入原生扩展或远程线程，改为预启动有限连续捕获，并在临时根窗口绘制带反码/边界校验的帧号。回放按每份 RDC 的实际 Present 目标读取标记，与对应 Godot PNG 全部 RGBA 比较，不猜帧号偏移或复用旧资源/事件号。

运行前固定为 6 帧时序校准＋校准后一次 32 帧冻结窗口，不延长搜索。校准另外在角色 SubViewport 放置明确标为 synthetic 的同帧标记，**6/6** 精确配对、**11 次**相邻帧错配拒绝；矩形之外与历史正常画面逐字节相同，标记污染及一级通道污染均检出。首轮分析器错误地将启动参数 1152×648 当作实际窗口尺寸；实际场景最小尺寸使其为 1152×720。保留 `timing_replay_r1` 和失败脚本，改为 Present 目标定位后，只重放同一批校准 RDC 得到 `timing_replay_r2`，没有重复捕获或改变严格比较。

`fixed_capture_r1` 取得 32 份 RDC（帧 518–549、标记 4–35，共 3,144,888,790 bytes），夹具 **10/10**、正常退出；`fixed_replay_r1` **32/32** 与对应源图精确相同。冻结段共 35 帧，全部等于历史正常 RGBA `5000c06842a07f6c2bf4fc2b8bc3a32e257abb69d9f9cf517439f5a46f557e2e`，没有自然坏帧。最初 3 个源帧不在 RDC 窗口内，不能计入 GPU 覆盖。第一份参考的四个 MSAA 样本与 resolved HDR 也与旧正常捕获字节一致；当前 resolve 为 event 230，旧捕获为 229，编号已按当前动作链重新识别。

证据根仍为 `rolenpr2_p05_bt_capture_debug_20261002/`，最新见 `frame_window.md`、`window_verification.json`、`window_process_cleanup.json`。524 项生产/持久测试源码和 `.63` 的 EXE/PCK/DLL 保持；新增两份临时 GDScript 后置检查通过，相关测试进程残留 0。只增加临时采集/分析和当前文档，没有生产、引擎、suite 或包变更。

结论为 `same_frame_capture_calibrated_bt_not_reproduced`：同帧对应关系可靠，BT 未修复、未接受例外，P05 不关闭。注入、逐帧落盘与根窗口标记仍会改变时序，日志也仍是 Vulkan 1.3.0，不能把本窗口稳定当成原 Vulkan 1.4.325 运行已无异常。按预定上限停止，不再追加相同窗口或随机矩阵；进一步因果归因仍需真实异常帧的 GPU 状态。物理听感仍待用户现场反馈。

### BT：既有三个正常 RDC 的 GPU 输入差异已分类

后续没有重新启动场景或增加捕获，固定读取上一窗口第 1/16/32 份 RDC（帧 518/533/549，标记 4/19/35）。每份 14 个角色颜色阶段 draw＋1 个 tonemap draw，共 45 个快照、30 对首帧对照。实际管线/顺序/参数、12 个 shader SPIR-V、specialization、push constants、顶点/索引内容、采样器及纹理绑定保持；不是只比较脚本属性或最终截图。

实际常量差异只有 set 1/binding 0 中 offset 3008 的 float32：26.850000381→46.923591614→67.066665649。捕获反射与匹配源码的 48 字段 SceneData 布局一致，对应当前 time。编译后 Body fragment 确认该值乘以材质色相速度；三帧实际速度为 0。实际色相启用值为 1，不能用源码默认 false 宣称分支关闭。另一个变化是 set 1/binding 2 的 InstanceDataBuffer 偏移 720896→0→0，但所绑定的 720,896 bytes 全部相同；更换缓冲半区不等于实例输入改变。这两项正常帧差异不足以认定 BT 根因，不修改生产时间或双缓冲策略。

首版采集把部分 SWIG 数组序列化成地址字符串，保留 `audit_r1`，不把它算完整状态证据。修正后的 `audit_r2` 在 180 秒上限停于 40/45 快照；超时保持失败。`audit_r3` 在新目录逐对象核验并复用 40 个已保存的不可变 RDC 事件快照，只补余下 5 个，不冒充重新完整跑过 45 个。第一版分类误把材质默认关闭当实际值的失败也已保留，修正的是解释而非真实 GPU 数据。

证据 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_gpu_inputs_20261002/`：`comparison.json` 保存全部差异路径，`classification.json` 保存映射及非 time 字节/绘制错序/实例单字节污染负对照，`verification.json` 核验 63 个二进制、提取来源、524 项源码/持久测试和 `.63` 三个产物。Python AST、UTF-8 无 BOM、文档与进程检查通过，相关残留 0；本轮没有修改 GDScript、生产或引擎，没有 suite/包变更。

该轮结论为 `normal_GPU_input_audit_verified_bt_unresolved`。当时未比较纹理 texel 或阴影 atlas，且三个输入全是正常帧；不能据此证明 GPU 内部执行恒定或历史异常已排除。该项检查结束，不追加正常帧数量或同类窗口，BT 保持未修复、未接受例外；真实异常状态或新的可反证机制仍是后续归因前提。后续纹理内容证据见下一节。

### BT：既有正常 RDC 的纹理内容核对完成，异常状态仍缺失

只重放上述第 1/16/32 份既有捕获，未新启动 Godot、未追加捕获窗口。对 15 个已审计 draw 的 vertex/pixel 反射绑定收集 45 个纹理资源，另加入 resolve 时的 4×MSAA color，共每份 **46 个资源、46 个状态、117 个子资源**。读取全部 mip、array layer 和 MSAA sample，3D 纹理按完整深度字节验证；不将 PNG 转换或单一 mip 的哈希当成全纹理内容。每份读回 157,784,524 bytes，没有超过预定预算或遗漏资源。

按当前捕获的 `GetUsage` 保守识别写入：未知 usage 和 Barrier 也作为状态边界，仅在后续对应 draw 之前没有新写入时复用快照。所有采样点均未发现同事件写入风险记录；post-draw 读回不被泛化为任意读写混合 shader 的 pre-draw 证明。跨捕获按相同资源、对应 draw 覆盖和 mip/layer/sample 配对，保留各自真实 event/write boundary。

最终 **92 对状态、234 对子资源原始字节全部相同**，覆盖：set 1/binding 6 的 4096×4096 D16 方向阴影 atlas；binding 5 的 4×4 D16 shadow atlas；binding 24 的 1152×720 R32_FLOAT depth buffer；binding 25 的 1152×720、10 级 mip color buffer；冻结雨水 heads/trails；tonemap 的 resolved HDR 输入与 4 个 MSAA 样本。名称按捕获绑定和匹配引擎声明映射，不仅凭资源编号猜用途；绑定/声明并不证明每个像素动态采样了它。最终 RGBA 三份仍为历史正常图的原哈希。

首版核验器误把前两份的 resolve event 230 当作跨捕获固定编号，第三份实际为 229，核验失败。失败源码和日志保留；改为各自事件/写入边界核对及 draw 相对配对，没有改捕获内容或相等门禁。四个负对照均检出：单字节哈希损坏、更新合法哈希后的单字节内容变化、等长度 MSAA sample 0/1 互换，以及错误 draw 状态配对。

证据根 `C:/Users/Public/nas_home/AI/GameEditor/linshi/rolenpr2_p05_bt_gpu_textures_20261002/`。`comparison_r3.json` 保存全配对事件及差异清单；`verification.json` 独立复算 **315 个二进制文件、351 次子资源引用**，并核对 524 项源码/持久测试、`.63` 三个产物、文本和文档链接。Python AST、UTF-8 无 BOM、`git diff --check` 通过；Godot/RenderDoc 相关进程残留 0。

此项只关闭“这三份正常捕获尚未比较纹理内容”的证据缺口，**不构成 BT 修复或历史异常帧的因果排除**。没有新增生产/GDScript/引擎改动，不重复 suite 或出包；R4 仍未修复、未接受例外。按预定边界结束本次正常帧审计，不继续积累同类正常帧。后续定位仍须新的具体可检验机制或真实异常 GPU 状态，而不是把正常输入稳定推断为用户原失败不存在。

### BT：恢复历史暂停转换路径并留存同帧 HDR，单次有界运行未复现

本轮先比较真实触发器与后续诊断代码，而不是再次扩大正常捕获数量。历史 `trigger_r1/trigger_probe.gd:10–22` 在每个后续候选前解除暂停一帧，再暂停等待 8 帧，首次失败位于 `search_2`。旧 `ring_probe.gd` 只在首次暂停插入固定观察窗口；`frame_probe.gd` 使用历史 heads/trails 的 ImageTexture，保留画面却没有执行这段状态转换。该差异构成具体的观察范围缺口，不是已经证明的根因。

`rolenpr2_p05_bt_transition_hdr_20261002/plan.json` 运行前固定：保留原 ViewportTexture、原三次自然推进与暂停顺序，最多四段各 360 帧；若发生变化，仅保留首次变化后 120 帧即停止。沿用先前已校准的 GPU 留存实现，在原历史 72 个差异像素的 3×3 邻域读取 647 点，容量 2048 帧、buffer 21,233,664 bytes。观察期间不执行 HDR CPU 读回，结束后一次收集；没有 RenderDoc 注入、全局配置或引擎改动。只新增一次性测试，不加入日常 suite。

首先执行 19 个短校准帧：相机交替使 HDR 和 PNG 同步改变，后处理亮度交替只改变 PNG，二者恢复后精确还原。GDScript **70/70**；独立分析拒绝相邻 HDR 帧错配、单字节 RGBA 污染及 GPU slot 标记污染。没有把合成变化当作 BT 自然坏帧。

随后唯一一次正式运行 **1466/1466、EXIT=0 / ISSUES=0**。四段各 360 帧，共 **1440 个静态图像样本**；每段的全图 RGBA 与 647 点 HDR 原字节都保持不变，每段暴露输入快照只有一个状态。四段 CPU 水状态、粒子状态与基准 PNG 各不相同，证明三次解除暂停确实发生作用，不能以无效操作获得稳定结果。GPU 共留存 1471 个连续 slot，包含附加的初始化与片段间过渡，未将这些额外 slot 计成 1471 个静态验收帧。

独立核验 **7 张原图、746 个输入二进制**、全部 GPU marker/slot、524 项源码/持久测试与 `.63` 三个产物身份。匹配引擎为 `4.8.dev.custom_build.38b6ddee7`，实际日志 Vulkan 1.4.325，两次运行无错误/警告；GDScript 后置检查、Python AST、UTF-8 无 BOM、文档与进程核对通过，Godot/RenderDoc 残留 0。初版校准分析输出了不必要的全屏坐标长表，已无损压缩归档并核对解压 SHA256；紧凑报告仅缩短派生坐标列表，保留全部原 PNG/HDR，不修改门禁。

结论为 `historical_transition_path_verified_not_reproduced`，不是修复。当前恢复的是原转换顺序，不是同一历史水状态；额外 compositor/compute 和 PNG 同步读回仍可能影响执行。没有新鲜坏帧，不能由本次稳定排除转换、阴影或后处理路径。按预定上限结束，不再追加第二轮相同观察；R4 未修复、未接受例外，已结算的其他工程门禁不重开。
