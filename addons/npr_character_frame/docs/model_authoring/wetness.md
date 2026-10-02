# 湿润材质纹理

样例人工材质分区的生成入口、输入身份和回归命令见 [分区重建](material_wetness_baking.md)。
身体、眼部与头发湿润图，以及薄纱/缝线图的生成入口见 [视觉数据图重建](visual_maps_baking.md)。

角色定义的 `wetness_profile` 指向 `NPRWetnessProfile`。基础渲染允许为空，湿润功能和完整 showcase 需要有效配置。四张 Texture2D 必须存在且宽高非零，推荐无损 PNG 和线性数据导入；不要烘入颜色校正。样例见 [wetness.tres](../../samples/silver_wolf/profiles/wetness.tres)。

- `body_mask`：Body UV1 的 R 通道湿润权重，乘以皮肤/丝袜/装备区域的现有强度。
- `material_regions`：Body RGBA 分别为织物、涂层/皮革、聚合物、金属区域权重；shader 按通道总和与 1 的较大值归一化。原服装的吸收与反光使用这些权重；雨水接收范围也读取此图，R 表示织物。
- `eye_tear_mask`：脸部 UV1 的 R 通道泪光权重，仍受 light map 的眼球分类（`0.1 < baked_mask < 0.8`）和闭眼状态门控。
- `eye_tear_uv_limit`：泪光采样坐标 `frag_uv` 的两个严格上限，条件为 `x < limit.x && y < limit.y`。分量必须有限且处于 [0,1]；新 profile 默认 `(1,1)`，覆盖标准 [0,1) UV，样例显式保留 `(0.26,0.32)`。标准非负 UV 下任一分量为 0 即关闭泪光；此参数不改变眼球分类或闭眼门控，不能仅换贴图和上限就宣称任意布局可用。
- `hair_mask`：头发采样 UV 的 R 通道湿润权重，必须绑定到框架头发基础材质与 next_pass。

上述 UV 使用各部件现有 shader 的采样约定；不能把 Body、脸和头发视为同一 UV 图集。没有对应效果的标准角色可提供非空黑图。结构检查不识别通道内容、贴合质量或真实材质语义。

`apply_materials(body, face, hair_passes)` 接收实例私有 ShaderMaterial 与显式头发 pass 列表，绑定纹理与泪光 UV 上限，不修改湿润强度、功能开关或源贴图。调用者负责传入全部需要的 pass；showcase 保持两 pass 绑定。初始化后更换 profile、纹理或上限需重新应用。未绑定 profile 的 shader 默认保留旧上限 `(0.26,0.32)`。该配置不包含雨滴几何、雨水模拟/表面附着数据或眼球分类语义。

给制作 AI 的提示词：按角色各部件 UV 绘制身体湿润强度、RGBA 材质分区、眼部泪光和头发湿润图，记录通道语义与导入设置。将贴图绑定到角色 profile，检查四个独立湿润区域从 0 到 1 的变化，特别确认服装/丝袜/合并装备分区不会互相污染、头发双 pass 一致、闭眼时泪光正确遮挡。先运行程序检查，再提供 [湿润复核](tests/wetness_review.md) 的固定视角开关对照。
