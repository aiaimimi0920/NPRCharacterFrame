# 开发者文档

## 组成与职责

插件根的 `NPRCharacter`、`NPRCharacterDefinition`、材质/表情/风格 Resource 是公开入口；`runtime/` 包含渲染、深度、阴影、几何与效果实现；`shaders/`、`materials/`、`presets/` 按职责组织；`showcase/` 为完整交互场景；`samples/` 为附带测试模型；`.ci_script/` 为长期自动化。

动作驱动、头发动态和表面接触已归入 `runtime/animation/`；面部装配、控制与表示位于 `runtime/face/`；装备装配位于 `runtime/equipment/`；Body 私有网格构建与拟合丝袜位于 `runtime/hosiery/`；持续面雨模拟与 GPU 场位于 `runtime/rain/`，输入来自角色定义。展示层负责组合运行时模块、UI 与保存状态；旧隐藏点滴渲染路径已删除，近景锚点仅保留在测试 fixture。完整框架的合同审计、生成器迁移与新角色验收仍未完成。后续工作见 [计划 P05](../design/optimization_plan.md)。

## 使用入口

复制整个 `addons/npr_character_frame/` 到宿主项目，使用用户提供的 Godot 引擎。启用插件后安装 shader globals，工具菜单 `Run NPR Character Showcase` 启动 [展示场景](../../showcase/wardrobe.tscn)。命令行可先执行 `--headless --path <host> --script res://addons/npr_character_frame/install.gd`，再导入项目。

提供 `NPRCharacterDefinition` Resource：`model_scene`、三个角色节点路径、`material_set`、`material_profile`、`use_source_materials`、`display_height`。先调用 `validate()` 获取错误列表，再赋给 `NPRCharacter.definition`，最后把角色节点加入场景树。源材质模式要求事先正确构建框架 shader 材质链；不是任意原始材质兼容模式。

完整展示场景可在入树前配置 `character_definition`、`character_id`、`character_display_name` 和 `demo_speech_path`。默认 `.tscn` 显式选择银狼，状态与默认保存位置按稳定角色 ID 归属；旧银狼文件名和 schema 10 保持。完整功能要求、初始化拒绝、路径覆盖和演示语音规则见 [展示角色输入](showcase.md)。

## 主要接口

- `NPRComicProfile`：`definition.comic_profile` 提供标准动作骨名、actor 静止锚点、按 sweat/anger/emphasis 排列的三组卡片偏移/尺寸，以及贴脸 tear/hatching 双侧区域。`validate()` 检查有限值与正尺寸，`apply_material()` 只写静态校准，不碰 tint/opacity、动画矩阵或生命周期。基础渲染允许 null，完整展示需要有效资源；使用期间不修改共享 Resource，更换角色重新 setup。空间、独立宿主绑定及验证边界见 [漫画校准](../model_authoring/comic.md)。

- `NPRRainProfile`：`definition.rain_profile` 提供持续面雨 surface JSON、chart RGBA8 和 vertex UV RGBAF 三文件路径；`validate()` 检查结构/索引和二进制尺寸，`load_surface()` 返回独立数据。基础渲染可为空，完整 showcase 必需；模拟与 GPU 场位于 `runtime/rain/`，输入配置不改变每帧预算。格式和验证边界见 [雨水数据](../model_authoring/rain.md)。

- `NPRWetnessProfile`：`definition.wetness_profile` 提供 Body mask、RGBA 材质分区、眼泪和头发四纹理及 `eye_tear_uv_limit`；`validate()` 检查资源尺寸与有限 [0,1] 上限，`apply_materials(body, face, hair_passes)` 绑定实例材质且保留强度/开关。showcase 显式传入头发两个 pass。UV 严格上限、默认值及仍保留的眼球分类限制见 [湿润标准](../model_authoring/wetness.md)。

- `NPRFaceMotionProfile`：每角色眼动/眼睑校准与表情资源；由 `definition.face_motion_profile` 注入。`validate()` 检查参数及 JSON；`load_lid_data()` 读取作者数据；`validate_lid_data(data, face_vertex_count)` 可额外检查原始脸部索引。实现见 `runtime/face/`，接入约定见 [眼动制作标准](../model_authoring/face_motion.md)。

- `NPRCharacterDefinition.mesh_paths()` / `validate()`：角色绑定和定义层校验。
- `NPRCharacterDefinition.rig_layout_data_path` / `load_rig_layout_data()`：角色自有 schema 1 骨骼诊断端点，空路径允许基础渲染，完整展示诊断要求配置。`runtime/npr_rig_layout_data.gd` 校验当前 canonical 骨序、父级有序无环、有限 head/tail 与非零骨段；加载返回独立字典。诊断层以实际动作调色板变换 actor 静止端点，不从平坦 Skeleton3D 推导端点，也不固定读取样例。标准、制作要求与视觉边界见 [骨骼诊断端点](../model_authoring/performance.md#骨骼诊断端点)。
- `NPREquipmentProfile`：`definition.equipment_profile` 提供四槽位的几何 JSON、独立材质 PackedScene、标签、骨骼名称、色块 UV 和节点分组；`validate()` 检查资源结构，`validate_bones()` 校验动作依赖，`load_geometry()` 返回独立数据。装备控制器 `slot_label()` 服务 UI，诊断数量按实际资源计算。标准与限制见 [装备数据](../model_authoring/equipment.md)。
- `NPRHosieryProfile`：`definition.hosiery_profile` 绑定拟合丝袜的六张纹理与 Body 区域边界，`validate()` 检查资源、尺寸和有限有效边界；`apply_material()` 写入 shell 的四个 sampler，`build_regions(vertices, source_to_actor)` 生成 CUSTOM0 的区域值与 actor 静止坐标，供装备初始化前构建私有 Body。基础渲染可为空，完整展示需要配置。法线修正、形态与 shader 尺度限制见 [丝袜纹理与区域](../model_authoring/hosiery.md)。
- `NPRHosieryProfile.normal_correction_path`：可选原始 Body 法线修正 JSON；`load_normal_correction()` 返回独立数据，`validate_normal_correction(vertices)` 核对顶点数量和记录中的源位置，`apply_normal_correction(arrays)` 先校验后修改私有 surface arrays，返回错误数组。空路径保留原法线；共用实现位于 `runtime/npr_body_surface.gd`，不读取样例路径，位置检查不代表完整三角拓扑验证。
- `NPRHosieryProfile.apply_cuff(material)`：将 `cuff_band_width`、`cuff_stitch_offset`、`cuff_stitch_width` 绑定到共享袜口 shader；Body 与拟合层分别应用，默认参数保持原渲染值。动态修改后需重新绑定两个材质，`apply_material()` 已包含拟合层绑定；不再提供未消费的 seam center/size uniform。
- `NPRHosieryProfile.apply_textile(material)`：绑定 `textile_period_m`、`textile_repeats`、`shell_offset_m`；程序织纹与三张贴图共用周期，纹理 tile 跨度为周期乘以重复次数。壳偏移保留统一缩放下的世界尺度补偿，详见制作规范中的空间限制；Body/拟合层分别重绑，`apply_material()` 包含拟合层绑定。
- `NPRHosieryProfile.apply_body_material(material)`：绑定 Body 的 garment/tulle/stitch 三掩码及袜口、尺度参数；与拟合层共用 garment_mask，避免染色和覆盖来自不同角色数据。完整 profile 现在要求六张非空纹理，新增 tulle_mask、stitch_mask。染色颜色、强度、袜口高度仍由显示状态控制，湿润贴图尚未包含。
- `NPRHosieryProfile.apply_leg_ao(material)`：绑定局部 light map G 校准开关、UV 矩形和高度/G 下限；新 profile 默认关闭，`apply_body_material()` 包含调用。原 shader 的左侧、丝袜域及掩码 alpha 限制不变，详见制作规范；原 light map 不会被修改。
- `runtime/face/npr_face_rig.gd.setup(actor, performance)`：统一创建面部节点、控制器并管理动作/帧信号；退出场景树时清理外置符号曲面。独立宿主接入与重建约定见 [面部运行时入口](face_runtime.md)。动作驱动的 `source_space(role)` 公开提供静止表面空间变换。
- `runtime/face/npr_face_presentation.gd`：`bind(actor, eye_layer, original_lids, symbol_eyes, symbol_mouth, skin, controls, head_pose)` 显式接收运行时节点、眼控制器与无参数头部变换回调。`request_eye_geometry()` 记录诊断眼请求并使模式缓存失效；`apply_expression_frame()` 在模式变化时同步眼/嘴曲面可见性和 face/outline 遮罩，随后执行 `sync_pose()`，读取已求值的源脸 blend shapes 与眨眼。`sync_light()` 同步源脸实例光照。诊断临时可见性在模式未变时保留，退出诊断调用 `invalidate_expression_frame()` 后重新应用当前表情。模块不连接全局信号，调用方负责信号生命周期并在源动作/表情求值后调用；更换角色创建新实例。
- `runtime/face/npr_eye_geometry.gd.assemble(target, profile, face_motion, face_material, render_layers, wetness)`：把已验证的诊断眼资源装配到空 Node3D，创建左右眼节点、独立光学材质并绑定眼睑数据，返回使用共享 face 材质的可选眼皮网格。调用者拥有 target 与子节点，负责释放；无需 showcase 或动作驱动。`bind_profiles()` 可重新绑定静态校准，眼部 shader 与共享 include 位于 `shaders/eye/`。
- `runtime/face/npr_eye_controls.gd`：`bind(search_root, layer, face, profile, apply_original, original_lids)` 在静止位置缓存眼表/虹膜/瞳孔，接收原眼运动回调 `Callable(left: Vector3, right: Vector3)`（XY 注视、Z 瞳孔比例）和可选原生眼睑。节点由调用者拥有，使用期间须保持有效；更换角色需创建新控制器。`set_eye_focus()` / `set_pupil_scale()` 的 side 为 -1 双眼、0 左、1 右，通过校验后发出 `controls_changed`；`eye_pupil_contract()` 保留 count、lid_count、focus、scale、range。闭合/湿润 setter 更新材质且不发此信号。`restore(left, right)` 静默恢复已验证值，由调用者在确定表示可见性后执行 `apply_pupils()`；原生眼表示恢复最新输入，诊断眼表示将原眼回调置中性。`reset()` 保留既有应用顺序，清零报告的湿润状态后由完整状态应用刷新湿润材质。姿态和符号切换委托 face presentation，保存/UI 适配仍在 showcase。
- `NPREyeGeometryProfile`：由 `definition.eye_geometry_profile` 指定诊断眼 PackedScene、landmarks JSON、注视增益、阴影、层深、闭合曲面和泪膜参数。`validate()` 校验场景、标记和光学范围，`load_landmarks()` 返回独立 Dictionary；`validate_lid_profiles()` 检查 shader 要求的 65 列均匀采样。`apply_surface()` / `apply_tear()` 绑定材质，CPU 注视和 shader 共用 `gaze_gain`。基础渲染可为空，完整展示图层必须提供。节点命名与校准范围见 [诊断眼资产](../model_authoring/eye_geometry.md)。
- `NPRSymbolSurfaceProfile`：由 `definition.symbol_surface_profile` 绑定符号眼/嘴的曲面、墨迹尺度和描边遮罩校准。`validate()` 检查参数；`NPRCharacter` 在初始化时对私有 face 材质链和 outline 应用 `apply_material()`。`runtime/face/npr_symbol_surface.gd.setup(face, space, material, profile, eye)` 构造共享蒙皮的替换曲面。完整 showcase 图层要求配置此资源，基础渲染允许 null；初始化后改变资源需要显式重建曲面并重绑材质。详见 [符号曲面](../model_authoring/symbol_surfaces.md)。
- `NPRCharacterDefinition.hair_dynamics_data_path` / `load_hair_dynamics_data()`：schema 3 动态链、蒙皮和接触数据。`runtime/npr_hair_dynamics_data.gd` 的 `validate(data, vertex_counts)` 检查结构及可选的实际三部件顶点数；当前完整动作驱动要求配置此数据，基础渲染可留空。内部 `runtime/animation/npr_hair_dynamics.gd` 构造函数接收已校验的 Dictionary 和来源路径，复制输入后运行。详见 [头发动态数据](../model_authoring/hair_dynamics.md)。
- `NPRCharacterDefinition.soft_tissue_data_path` / `load_soft_tissue_data()`：角色自有压力形变 JSON，空路径允许基础渲染。`runtime/npr_soft_tissue_data.gd` 的 `validate(data, body_vertex_count)` 检查稀疏位移和可选的实际 Body 顶点数；完整 showcase 动作驱动要求有效数据。详见 [软组织数据标准](../model_authoring/soft_tissue.md)。
- `NPRCharacterDefinition.performance_data_path` / `load_performance_data()`：角色自有 schema 1 动作、权重与面部形状数据；空路径允许基础渲染，动作功能必须配置。`runtime/npr_performance_data.gd` 的 `validate(data, vertex_counts)` 校验结构及可选的三部件原始顶点数，读取返回独立 Dictionary，运行时追加动态骨不会写回资产。制作标准见 [动作数据](../model_authoring/performance.md)。
- `NPRCharacterMaterials.validate()` / `validate_optional()` / `build()`：纹理、轴、平滑法线选项校验与每角色私有材质创建。
- `NPRCharacter`：`set_face_light()`、`set_outline_width()`、`set_face_expression()`、`set_stocking_strength()`、`set_hair_anisotropy()`、`set_dissolve()`、`set_visibility_alpha()` 等效果接口；`get_world_bounds()` 和 `pick_surface()` 提供几何查询。
- `NPRCharacter.intersect_role_ray(role, origin, direction)`：世界空间物理射线，role 为 0 Body / 1 Face / 2 Hair，返回空字典或 `position`、世界 `distance`、源 `mesh` 名称。无效 role/未初始化安全返回空；保留 CPU blend shape/skin、部件 mask、special clip transform 的既有查询规则，但不因节点隐藏或 camera.cull_mask 过滤，不跨角色选择 nearest。不等于可见表面 `pick_surface()`，也不提供法线、UV/triangle 或可持久的拓扑附着。漫画先对每个 face/hair hit 做锚点范围筛选，再累积 nearest；不能先聚合 nearest 再筛选。
- `NPRExpressionProfile` / `NPRExpressionController`：表情配置、所有权和优先级；不要从外部同时覆盖控制器管理的 blend shape。
- `NPRStylePreset`：捕获、应用、验证角色风格；`NPRScreenQuality`、`NPRComicLayer`、`NPRRenderDiagnostics` 提供质量、漫画表现和诊断能力。

完整公开声明索引见 [API 索引](api_reference.md)，从源码生成；下划线方法为内部实现，不承诺外部接口稳定性。

## Face atlas 校准

`NPRFaceAtlasProfile` 提供 Face 纹理采样坐标，`definition.face_atlas_profile` 基础可选、组合面部及完整展示必需。初始化仅绑定私有 Face 材质，原眼睑/符号曲面沿用该材质；不覆盖动态表情/眼动。未配置时 atlas 操作默认关闭。数值、坐标域及验收边界见 [作者规则](../model_authoring/face_atlas.md)。

## 动作运行时

[`runtime/animation/npr_performance.gd`](../../runtime/animation/npr_performance.gd) 负责骨骼调色板、表情/口型、眼动和压力形变，并组合 [`npr_hair_dynamics.gd`](../../runtime/animation/npr_hair_dynamics.gd) 与 [`npr_surface_contact.gd`](../../runtime/animation/npr_surface_contact.gd)。这些模块不读取 showcase 或 samples 路径；展示场景负责创建驱动、连接 UI 和保存选择。

驱动是 Node，初始化前需确保 `NPRCharacter` 已进入场景树且 `initialized` 为 true，并具备 face motion、performance、soft tissue、hair dynamics 全部有效配置。把驱动加入场景树后调用一次 `setup(actor)`；同一驱动不支持重复 setup。驱动与角色同生命周期释放。`automatic` 只控制自动动作时钟和眨眼时间；设为 false 后，Node 的 `_process(delta)` 仍推进弹簧、头发和表情状态。确定性采样还需由调用者通过 `set_process(false)` 接管调度，再以明确的步长/步数调用 `apply_pose(time, delta)`；仅固定 time 或等待相同渲染帧数不能保证相同模拟状态。测试专属时钟及验证边界见 [测试说明](testing.md#确定性模拟采集)。`set_hair_dynamic_enabled()`、`set_hair_collision_enabled()`、`set_soft_tissue_pressure()` 和眼动方法沿用现有行为。样例外部场景装配仍需单独验证，目录迁移不等于全功能新角色验收。

`set_hair_collision_enabled(value)` 同步动态模拟的碰撞开关；约束数据来自角色的 hair dynamics JSON（胶囊、头部表面和接触采样）及实际网格。`head_surface.bvh_origin` 必须提供本角色的有限 actor 静止空间原点；三角形创建、Body 重建与头部逆变换后的查询共用该值，100 倍 BVH 数值缩放仍为框架算法常量。校准由构造实例时读取，更换数据须创建新的动态模拟，不在运行中修改共享字典。`hair_collision_contract()` 返回当前开关、胶囊数量和本次修正测量，制作与诊断边界见 [头发动态标准](../model_authoring/hair_dynamics.md)。

作者头部 BVH 的创建与实际 Body 绑定后的重建在 Debug、Release 中均无条件执行；`assert` 只检查创建返回值，不承载初始化副作用。非调试模板会省略断言表达式，编辑器或 Debug 展示包通过不能替代 Release 接触验证。实际两个模板的专项入口见 [构建与版本](build.md#头部接触的实际模板回归)。

## 装备运行时

[`runtime/equipment/npr_equipment.gd`](../../runtime/equipment/npr_equipment.gd) 是每角色一个的 RefCounted 控制器。角色初始化且 Body 已具备 CUSTOM0 域后调用一次 `setup(actor)`，缓存未追加装备的 Body 基础网格；角色定义必须包含有效装备配置与动作骨骼。控制器不支持重复 setup，更换角色应创建新实例。材质场景作为角色子节点随角色释放，控制器不会单独销毁该节点。

`apply(actor, body_mesh, choices)` 接收按 head/chest/back/weapon 排列的四个布尔选择，重新组合基础网格并更新 `attachments`。调用方应随后更新动作驱动的附加顶点绑定；`set_authored_materials_enabled()` 切换材质模式后也需调用 `apply()`，才能同步恢复或组合 Body。姿态求值后调用 `sync_pose(performance)`，驱动需提供 `bone_deformation(bone_name)`；`set_wetness()` 修改每实例材质，`slot_label()` 和 `authored_material_contract()` 提供显示标签及诊断。展示层仍负责操作顺序、信号和保存，不要求运行时读取其私有成员。

## 拟合丝袜运行时

[`runtime/hosiery/npr_garment_geometry.gd`](../../runtime/hosiery/npr_garment_geometry.gd) 的静态 `install(source, source_to_actor, profile)` 为原始 Body 创建私有网格：先应用可选法线修正，再写 CUSTOM0 区域/静止位置，保留源材质及顶点/UV/三角索引，不修改共享源网格。输入必须是已验证的单 surface Body，CUSTOM0 未占用、无 blend shapes、无 skin；调用位置必须在装备缓存与动作驱动初始化之前。`source_to_actor` 为 `actor.global_transform.affine_inverse() * source.global_transform`。同一已处理网格不能再次 install，也不支持直接对已蒙皮网格重建；更换配置需要从原始 Body 重新初始化。法线错误会报告并返回而不替换源网格，其余前提沿用断言约束。

[`runtime/hosiery/npr_fitted_hosiery.gd`](../../runtime/hosiery/npr_fitted_hosiery.gd) 是 Node3D 层。先加入场景树，再调用一次 `setup(body_mesh, hosiery_profile)`；Body 必须已完成 CUSTOM0 域和动作/蒙皮初始化，profile 必须已校验。层默认隐藏，自建 `FittedHosiery` 子节点与私有材质；调用者通过 `visible` 控制显示。材质 render priority 为 10，保留原透明合成和阴影行为，shader 位于 [`shaders/body/hosiery_fitted_shell.gdshader`](../../shaders/body/hosiery_fitted_shell.gdshader)。

`sync_body()` 同步 Body 网格、世界变换、AABB、剔除边界、skin、骨架路径和 blend shapes；应在动作求值、装备重建后及绘制前调用。模块不自行连接 RenderingServer 信号，调用者负责调度并保证源 Body 在使用期间有效。`set_surface_state(opacity, height, stitch_strength)` 接收已验证的显示状态并更新材质，不读取展示状态对象或保存文件。`mesh_instance` 和 `material` 可用于诊断；释放层会释放其子节点，不释放源 Body。更换源角色需创建新实例，不重复 setup。

## 工程入口

持续面雨接入见 [雨水运行时](rain_runtime.md)，通过显式启用、到达率、种子、表面湿润与丝袜参数配置；调用方负责帧调度，运行时不读取展示状态对象。

- [测试与外部 AI 协作](testing.md)
- [构建与版本](build.md)
- [模型制作规范](../model_authoring/README.md)
- [样例雨水资产重建](../model_authoring/rain_baking.md)
- [样例服装掩码重建](../model_authoring/garment_baking.md)
- [样例材质湿润分区重建](../model_authoring/material_wetness_baking.md)
- [样例五张视觉数据图重建](../model_authoring/visual_maps_baking.md)
- [样例 Body 法线修正重建](../model_authoring/body_surface_baking.md)
- [样例丝袜织纹重建](../model_authoring/hosiery_textures_baking.md)
- [样例软组织压力烘焙](../model_authoring/soft_tissue_baking.md)
- [样例头发动态烘焙](../model_authoring/hair_dynamic_baking.md)
- [样例骨架、动作与滑动眼睑烘焙](../model_authoring/performance_baking.md)
- [样例诊断眼表与虹膜烘焙](../model_authoring/eye_baking.md)
- [样例装备几何与材质烘焙](../model_authoring/equipment_baking.md)
- [开发计划](../design/optimization_plan.md)

遵循 [Godot 项目组织](https://docs.godotengine.org/zh-cn/4.x/tutorials/best_practices/project_organization.html)、[GDScript 风格](https://docs.godotengine.org/zh-cn/4.x/tutorials/scripting/gdscript/gdscript_styleguide.html) 和 [Shader 风格](https://docs.godotengine.org/zh-cn/4.x/tutorials/shaders/shaders_style_guide.html)。按功能组织共同使用的场景和资源，不为了形式创建空层级。

## 作者展示镜头

`NPRShowcaseCameraProfile` 是 `NPRCharacterDefinition.showcase_camera_profile` 的可选 Resource；基础渲染不依赖它，完整展示必须提供。定义校验传播 profile 错误；展示实例入树时深复制镜头快照。字段和责任见 [镜头制作规范](../model_authoring/showcase_camera.md)，使用入口见 [完整展示](showcase.md)。

### 展示配色作者输入

`NPRShowcasePaletteProfile` 经 `NPRCharacterDefinition.showcase_palette_profile` 提供有序标签、三通道 RGB 和默认槽位；基础渲染可省略，完整展示必需。UI 和初始化/重置/路径重载使用入树时的深复制快照，schema 10 不变。内部 `wardrobe_state.gd` 构造须显式传入 `(character_id, palette_profile, height_profile)`，不再隐式使用银狼配色。字段、索引兼容和作者责任见 [配色制作规范](../model_authoring/showcase_palette.md)。

### 展示袜口高度作者输入

完整展示必须提供 showcase_height_profile；其闭区间、工厂值与 UI 步长使用入树快照，基础渲染可省略。几何候选域不替代选择范围；旧 schema 填 1.34 与作者工厂值分开，已有数值不按步长量化。见 [高度制作规范](../model_authoring/showcase_height.md)。
