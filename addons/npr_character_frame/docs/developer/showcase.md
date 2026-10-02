# 完整展示场景的角色输入

`showcase/wardrobe.tscn` 是默认银狼展示入口，不是框架唯一可用角色。其四个导出字段显式提供样例配置；`NPRCharacter` 的渲染 definition 不承担展示名称、存档身份或演示语音的业务归属。

在节点进入场景树前配置：

```gdscript
var showcase = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn").instantiate()
showcase.character_definition = my_complete_definition
showcase.character_id = "my_character"
showcase.character_display_name = "我的角色"
showcase.demo_speech_path = "" # Optional Rhubarb JSON, with its companion WAV.
add_child(showcase)
```

这不是运行时切换角色 API。definition、ID、名称和演示路径都应在入树前设定；更换角色创建新展示实例。配置不包含任意模型适配、角色选择器或导入向导。完整展示的镜头和配色由角色作者配置，布局仍沿用既有约定，第二标准角色仍须单独完成视觉验收。

## 字段与初始化

| 字段 | 合同 |
|---|---|
| `character_definition` | 必须符合框架模型标准，并提供完整展示需要的所有功能数据；不是只满足基础渲染的最小 definition。实例内复制 definition，功能 Resource 仍按既有只读共享约定使用；镜头及配色 profile 单独深复制为当前实例快照。 |
| `character_id` | 稳定且由宿主保证唯一，匹配 `[a-z][a-z0-9_]{0,63}`。不使用显示名称作为键；不能包含路径分隔符、空白或换行。两个角色若故意使用同一 ID，就会共享默认存档归属。 |
| `character_display_name` | 非空显示名称，用于标题和初始服装标题，不写入方案、不参与文件名。 |
| `demo_speech_path` | 可空；非空时必须指向存在的 Rhubarb JSON。音频格式、相邻 WAV 和时间轴有效性仍由既有 `wardrobe_speech.load_clip()` 在播放时检查。 |

`wardrobe_configuration.gd` 检查身份、名称、definition 校验，以及完整展示需要的 showcase camera/palette、face motion/atlas、符号、漫画、诊断眼、丝袜、湿润、雨水、装备 profile 和 performance/soft tissue/hair dynamics/rig layout 数据路径。基础 `NPRCharacterDefinition` 的可选性没有改变；新增严格要求只属于完整展示。

元数据不合法时，在创建舞台和驱动之前拒绝。若模型实例的根类型、角色网格或材质被 `NPRCharacter` 拒绝，则停止展示装配，不继续索引空 meshes/materials，也不创建动作、语音等驱动。这不等于证明任意输入资产的所有运行时几何和视觉质量；资产仍须通过模型规范与专项检查。

## 方案归属与兼容性

默认保存位置为 `user://<character_id>_wardrobe.json`。默认银狼保持 **`user://silver_wolf_wardrobe.json`** 和 schema 10；不会迁移、清空或重命名原用户文件。

状态构造器 `wardrobe_state.gd.new(character_id, profile)` 显式接收身份和已验证的配色配置。`to_data()` 写入该身份，`load_data()` 在赋值之前拒绝不同身份的数据；存档不能更换当前角色。初始创建、重置方案、ready 后切换保存位置都使用入树时冻结的身份，即使后来误写公开 `character_id` 字段，也不能让已加载角色变换存档归属。

原有 `configure_save_path(path)` 保留：入树前的显式路径优先于自动默认；ready 后调用会以原身份重建默认状态，再尝试加载该文件。错误身份/坏数据保持默认状态，设置无效方案提示，不在加载时覆盖文件。该方法仍是宿主提供的路径覆盖，不是文件访问隔离机制；宿主应避免把不同身份显式指向同一写入文件。重置方案保留覆盖路径，不自动保存。

## 演示语音

默认场景仍引用原银狼 `demo.json`，语音资源及 Rhubarb 采样算法没有改变。其他配置可提供自己的路径或留空。留空时点击示例按钮会提示“未配置口型示例，请载入口型与语音”，不回退到银狼音频、不停止已有外部音频。手动载入 JSON/WAV 的入口仍保留；播放、停止及工作台调用继续使用同一展示方法。

## 验证边界

`showcase_identity_regression.gd` 已加入 framework suite，覆盖默认文案/语音、独立身份存档、跨身份原子拒绝、默认路径和显式覆盖优先级、重置及重建、冻结身份、不同 definition 实际绑定和外部演示片段。替代配置复用银狼几何，只是接入接口的真实场景夹具，**不是 P06 第二标准角色验收**。

两种故意失败的生命周期检查需单独运行：设置环境变量 `NPR_SHOWCASE_NEGATIVE` 为 `missing_feature` 或 `runtime_model`，执行同一脚本。前者只能出现 `ERROR: Invalid showcase configuration: Full showcase requires face_atlas_profile`，后者只能出现 `ERROR: NPR character rejected: model_scene root must be Node3D`；同时要求进程退出码 0、报告全部检查通过、没有其它错误或泄漏警告。正常 suite 不允许忽略这些错误。其余运行方式见 [测试说明](testing.md)。

## 展示镜头

入树前通过 `character_definition.showcase_camera_profile` 提供 [作者镜头配置](../model_authoring/showcase_camera.md)。完整展示拒绝缺失或非法配置，不回退到银狼坐标；运行实例持有 `duplicate(true)` 快照，之后修改源 Resource 不影响当前镜头。更换配置创建新实例。

全身、半身、面部切换沿用原规则：清 target.x，更新高度和距离，保留 target.z、orbit pitch 和当前 FOV；水平偏移按当前预设距离/全身距离缩放。重置视角清平移和旋转，恢复配置初始 FOV 与全身构图。软组织观察使用独立 target/distance 并重置俯仰、转台和水平偏移。镜头校准不写入 schema 10，切换镜头不自动保存方案。`showcase_camera_regression.gd` 覆盖默认构图、替代配置实际 GPU 变化、实例隔离及保存字节不变；替代配置仍使用银狼模型，不代表第二角色。

## 展示配色

入树前通过 `character_definition.showcase_palette_profile` 提供 [作者配色配置](../model_authoring/showcase_palette.md)。标签、三通道 RGB、默认槽位显式归属角色。UI 与初始化、重置、路径重载共享入树时的深复制快照；源资源修改不热更新已打开实例。槽位 0 始终关闭染色，-1 为用户自定义，保存 RGB 不按预设重算。旧 schema 填充值及其他默认校准保持原合同。

袜口高度作者配置及旧方案兼容规则见 [展示高度校准](../model_authoring/showcase_height.md)。
