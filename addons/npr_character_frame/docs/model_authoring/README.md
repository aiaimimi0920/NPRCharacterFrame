# 模型制作规范与 AI 提示词

模型制作方遵守本框架标准并交付模型、贴图、配置。框架不自动适配非标准模型。机器可读基础规范在 [asset_contract.json](../../asset_contract.json)，真实校验实现见 [定义校验](../../npr_character_definition.gd) 和 [几何校验](../../runtime/npr_model_validator.gd)。

## 已实现的基础渲染标准

交付 `NPRCharacterDefinition` 资源，包含 Node3D 根的 PackedScene；使用相对后代 NodePath 显式绑定 body、face、hair 三个不同 MeshInstance3D。每个角色角色部件是单 surface 的三角形 ArrayMesh，装备不另留未绑定 mesh；必须有非零有限高度、NORMAL、UV1 和非奇异变换。

坐标在导入后为 Y 向上、Z 向前、X 向右。蒙皮模型必须有 Skin 和可解析的 Skeleton3D。面部 SDF 使用 UV2 或轮廓平滑法线使用 UV2 时提供该通道；头发各向异性或切线轮廓模式需要 TANGENT。头发同时使用各向异性与平滑轮廓时，不要用平滑法线覆盖发丝切线，选择 UV2 编码轮廓法线。

常规模型提供 `NPRCharacterMaterials` 的完整基础纹理；源材质模式必须提供现成框架 shader 链。纹理语义、通道、UV 翻转和 slot 编码以机器契约为准。推荐无损 PNG 交换，数据贴图使用线性/原始通道，颜色贴图遵守契约 sRGB 约定，保留 alpha。不要把所有图片统一作 sRGB，也不要对 ILM/LUT 使用有损压缩。

body LUT 是 8×8；body/hair 冷暖 ramp 高度为 16、宽度至少 2。ILM 的 alpha 编码八个区域，推荐 `(slot+0.5)/8`。普通基础贴图和 SDF 的 UV 规则不同，不可统一翻转后假设正确。

## 全功能数据的状态

四槽位装备使用 [装备数据标准](equipment.md) 配置几何、材质场景、标签、附件骨骼与色块。程序检查输入结构，动作绑定和材质效果按 [装备复核用例](tests/equipment_review.md) 提供证据。

眼动/滑动眼睑及每角色表情资源绑定已提供 [P05-A 制作标准](face_motion.md)。程序检查包含 profile 数值、眼睑结构和睫毛索引；仍需实际动作和闭合截图复核。

骨骼权重、四种动作和面部/口型形状使用 [P05-B 动作数据标准](performance.md)，由角色定义指定 JSON。程序检查其结构和原始拓扑；形变质量按 [动作复核用例](tests/performance_review.md) 评估。

骨骼诊断另由 `rig_layout_data_path` 指定本角色的 [actor 静止端点](performance.md#骨骼诊断端点)，不复制样例坐标；标准骨序、父级、有限坐标与非零骨段由程序校验。同姿态渲染/白模/骨骼对照用于复核贴合与动作跟随，结构通过不等于最终视觉验收。

Body 压力形变使用 [P05-C 软组织数据标准](soft_tissue.md)，由角色定义指定稀疏 corrective。顶点数量、索引和有限数值可自动检查；局部作用区域与碰撞安全需模型专属证据。

头发与 Body 附属动态链使用 [P05-D 头发动态标准](hair_dynamics.md)，校验追加骨骼、权重、链和接触数据结构；视觉风格、稳定性及碰撞覆盖按 [动态复核用例](tests/hair_dynamics_review.md) 提供模型专属证据。

符号眼/嘴的替换曲面、墨迹尺度和描边遮罩使用 [P05-F 符号曲面标准](symbol_surfaces.md)，由角色 Resource 同时驱动生成几何与 shader；贴合和遮挡仍需实际画面复核。

Face atlas 的绘制眼 accent、补肤行、诊断替换域和圆眼校准使用 [Face atlas 作者规则](face_atlas.md)，由角色资源提供，不要求固定 512px 布局；ILM 与 CPU 分类标准不变。

诊断眼模型、左右眼中心与光学参数使用 [诊断眼资产标准](eye_geometry.md)，通过角色 Resource 提供；运行时创建、控制及生命周期已整合到 face rig。

Body 服装与拟合丝袜使用 [丝袜标准](hosiery.md) 指定六张纹理、Body 域、法线修正、袜口、尺度和腿部 AO 校准，运行时装配已提取；视觉质量依照 [丝袜复核用例](tests/hosiery_review.md) 提供角色专属证据。

Body/Face/Hair 的湿润输入使用 [湿润纹理](wetness.md) 指定四张数据图，独立区域效果依照 [湿润复核用例](tests/wetness_review.md) 提供证据。持续面雨的三文件输入见 [雨水数据](rain.md) 与 [雨水复核用例](tests/rain_review.md)，运行时位于 `runtime/rain/`，动态状态由显式参数提供；旧隐藏点滴资产已删除，样例雨水生成入口已迁入。

头发动态、装备、雨水、口型、表情、眼睑和软组织已有上述专项输入合同；JSON/BIN、骨骼、掩码及坐标内容仍需为每个角色制作，不能靠猜测复制银狼数据。基础几何检查不代表全功能或视觉验收：使用方应按所启用模块提供专项资源，并按对应复核用例验证。第二标准角色的实际制作与验收属于 P06，不是现有合同必须无限扩展的前提。

## 分类提示词

漫画头部锚点、三卡片和贴脸泪滴/排线使用 [漫画校准标准](comic.md) 与 [程序/外部 AI 复核用例](tests/comic_review.md)。提供本角色的 `comic_profile`，不要复制样例坐标；基本数值合规不能代替动画、遮挡和视觉证据。

已迁移的离线入口包括 [雨水](rain_baking.md)、[服装掩码](garment_baking.md)、[材质湿润分区](material_wetness_baking.md)、[视觉数据图](visual_maps_baking.md)、[Body 法线修正](body_surface_baking.md)、[丝袜织纹](hosiery_textures_baking.md)、[软组织压力](soft_tissue_baking.md)、[头发动态](hair_dynamic_baking.md)、[骨架/动作/表情/滑动眼睑](performance_baking.md)、[诊断眼表/虹膜](eye_baking.md) 和 [装备几何/材质](equipment_baking.md)。剩余角色资产继续逐项核对实际消费者、输入身份与可重建性。

- [几何与绑定](prompts/geometry.md)
- [贴图与材质](prompts/textures.md)
- [功能数据交付](prompts/feature_data.md)
- [程序合规测试的 AI 复核](tests/contract_review.md)
- [柔和目标的程序检查](tests/face_softness_programmatic.md)
- [柔和目标的 AI 提示词](tests/face_softness_prompt.md)

执行方式与输出协议见 [测试文档](../developer/testing.md)。AI 只输出建议；修改模型由外部制作流程负责。

展示所需的全身、半身、面部和软组织观察构图由作者提供 [showcase_camera 配置](showcase_camera.md)，并按 [镜头复核协议](tests/showcase_camera_review.md) 留存证据；不是自动模型适配。

完整展示配色由角色显式提供 [配色制作规范](showcase_palette.md) 所述资源；保留槽位 0 原材质与 -1 自定义语义，不机械覆盖用户存档 RGB。

P05-BN 显式展示高度配置见 [袜口高度校准](showcase_height.md)；新增 `showcase_height_profile_regression.gd`，完整 suite 增至 25 阶段。
