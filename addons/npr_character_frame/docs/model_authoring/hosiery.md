# 动态拟合丝袜纹理

样例三张织纹图的独立生成入口与验证见 [织纹重建](hosiery_textures_baking.md)；Body 法线修正的采集与生成见 [表面重建](body_surface_baking.md)。

角色定义的 `hosiery_profile` 指向 `NPRHosieryProfile`，为 Body 服装与动态拟合丝袜提供六个 Texture2D 和静止 Body 域边界。基础渲染可不配置，完整 showcase 或拟合丝袜功能需要完整配置。已有自制 profile 需补齐新增的 tulle_mask 与 stitch_mask；不使用对应效果时可提供非空的黑色数据图。样例见 [hosiery.tres](../../samples/silver_wolf/profiles/hosiery.tres)。

## 贴图语义

- `weave_texture`：织物颜色，RGB 按 shader 的 `source_color` 语义采样。
- `roughness_texture`：线性数据，使用 R 通道；现有 shader 将结果限制到 [0.25, 1]。
- `normal_texture`：切线空间法线 RGB，作为法线数据导入，现有法线深度为 0.35。
- `garment_mask`：R/G/B 分别为 Body 主色、次色和饰边染色权重，RGB 总和用于染色覆盖；alpha 为丝袜覆盖，并参与现有腿部 AO 修正遮罩。Body 与拟合层共用此资源，使用 `(UV.x, 1 - UV.y)` 采样，丝袜 alpha 再乘顶点域与高度覆盖。
- `tulle_mask`：线性数据，Body 使用 R 通道控制薄纱覆盖，乘以展示薄纱强度。
- `stitch_mask`：线性数据，Body 使用 R 通道控制贴图缝线，乘以缝线强度；启用 metric seams 时由程序袜口缝线覆盖该结果，当前 showcase 默认启用 metric seams。

`apply_body_material()` 绑定三张掩码及袜口/尺度参数；`apply_material()` 给拟合层绑定织物三图与共用 garment_mask。薄纱和缝线掩码只属于 Body 路径，不作为拟合层的织物采样图。制作掩码需保留独立 RGBA 通道，使用线性数据语义，不能把 RGB 染色权重误当作最终颜色。

每个纹理必须存在且宽高大于零。推荐交付无损 PNG，掩码保留 alpha，数据纹理不能烘入颜色校正。颜色/粗糙度/法线纹理应对应同一平铺结构；掩码使用角色自身 Body UV，不要求与平铺图尺寸相同。程序只验证资源与尺寸，不能根据图片尺寸认定语义或 UV 正确。

## 几何与当前尺度

拟合层直接共享当前 Body 网格、骨架、skin 和 blend shapes，装备重建 Body 后重新绑定，不需要独立丝袜模型资产。旧独立 GLB 及其未使用的派生贴图已从插件移除；profile 继续绑定三张正式织纹图。Body 的 CUSTOM0.r 提供腿部域，CUSTOM0.yzw 提供静止位置，必须与角色的数据生成流程一致。

拟合层由 `runtime/hosiery/npr_fitted_hosiery.gd` 装配，shader 位于 `shaders/body/hosiery_fitted_shell.gdshader`；独立场景可直接使用运行时节点，不需要展示层类。调用顺序和生命周期见 [开发者文档](../developer/README.md#拟合丝袜运行时)。

私有 Body 的预处理入口为 `runtime/hosiery/npr_garment_geometry.gd.install()`，用于已验证的单 surface、未蒙皮、无 blend shapes 且 CUSTOM0 空闲的原始网格。运行时按顺序完成此预处理、装备缓存与动作初始化，再创建拟合层；装备或动作已修改网格后不能重复预处理。Body 服装掩码现从同一 profile 读取，腿部 AO 修正参数见下方校准说明；独立雨水输入由 [rain profile](rain.md) 提供。

`domain_height_range` 是 actor 静止空间的 Y 开区间，两个边界必须有限且递增；`domain_half_width` 是有限正数，指定中心区域的 X 半宽；`domain_full_width_below` 为有限 Y 阈值，低于此值时不限制 X。顶点必须满足高度开区间，并满足 `abs(x) < domain_half_width` 或 `y < domain_full_width_below`，CUSTOM0.r 才为 1，否则为 0；所有等号边界均不包含。CUSTOM0.yzw 始终保存 actor 静止位置。它定义几何候选范围，最终可见范围还与服装掩码及 shader 高度相交，程序检查不能证明该范围不会覆盖手部等非腿区域。

`build_regions(vertices, source_to_actor)` 使用源顶点与 mesh 到 actor 的变换生成数据，不修改源数组。必须在装备缓存基础 Body 之前写入；装备追加自己的 `-1` 域，不能在之后对整个混合网格重新生成丝袜域。改变边界后需重新构建 Body 和装备/动作绑定，单独更新纹理材质不会更新顶点域。

织物平铺采用 actor 米制静止位置 XY；`textile_period_m` 为有限正纱线周期（默认 0.0025 m），`textile_repeats` 为每张贴图内的正整数重复次数（默认 8），完整纹理 tile 跨度为两者乘积（默认 0.02 m）。颜色、粗糙度和法线共用此采样坐标，重复次数必须与实际烘焙纹理匹配。Body 程序织纹使用同一周期，在原 weave_scale=1024 时获得该物理周期，艺术调节 weave_scale 仍会缩放程序织纹频率；程序织纹的 1.35 横纵比例保持原值。

`shell_offset_m` 为沿法线的有限非负偏移，默认 0.00025 m，零值合法。沿用原 shader 的世界尺度补偿：以 MODEL_MATRIX 第一基向量长度除去统一缩放；此公式不保证非均匀缩放/剪切下每个方向都是相同世界距离，制作与场景装配应保持正的统一缩放。纹理周期使用 actor 静止空间，整体放大角色时其世界纹理尺寸也随之放大，与壳偏移的空间语义不同。

`apply_textile(material)` 将尺度配置绑定到 Body 与拟合层；`apply_material()` 已包含拟合层绑定。运行时更改尺度后分别重绑两个材质即可，无需重建几何或重新烘焙纹理；但更改重复次数必须符合所用纹理内容。六张纹理、区域、法线、袜口和尺度配置不代表完整框架/第二角色已验收。透明度、高度、缝线强度继续由展示状态控制。

## 袜口折边与缝线

袜口形状由 `cuff_band_width`（折边带宽）、`cuff_stitch_offset`（从袜口向下的缝线中心偏移）、`cuff_stitch_width`（缝线宽度）控制，使用 actor 静止空间的米制 Y 距离。宽度必须为有限正数，偏移为有限非负数；默认分别是 0.016、0.012、0.0012。三个参数都参与 Body 与拟合层共用的 metric stitch 函数。最终仍受袜口高度裁切、覆盖掩码与缝线强度限制，配置通过不能保证缝线位于折边内部，制作时需通过近景确认。

`apply_cuff(material)` 绑定这三个参数；`apply_material()` 为拟合层绑定纹理时也会调用它。运行时修改配置需给 Body 和拟合层分别重新应用，不影响网格/蒙皮，不需要重建 Body。高度与缝线强度继续属于展示状态。原 `seam_centers` 和 `seam_size` 没有 shader 消费，已移除；当前实现不提供左右腿独立中心或纵向接缝形状控制。

## 可选腿部 AO 校准

`leg_ao_repair_enabled` 默认关闭，仅用于需要局部提高 light map G 明暗阈值的角色。`leg_ao_repair_uv` 是采样 UV 的 `(min_u, min_v, max_u, max_v)`，各值有限、位于 [0, 1]，两个区间递增；`leg_ao_repair_values` 是 `(min_height, max_height, G_floor)`，高度为 actor 静止空间的有限递增范围，G 下限位于 [0, 1]。即使关闭开关，也要求保存的校准值合法。样例显式保存原左腿校准，不应复制到其他角色。

`apply_leg_ao()` 绑定 Body 的三项 uniform，`apply_body_material()` 包含此调用；拟合层无需该修正。shader 原行为保持：wardrobe 与 repair 开关均启用后，按正反面选择对应采样 UV，UV 矩形和高度使用闭区间，另要求静止位置 x <= 0，并乘丝袜候选域与 garment_mask alpha。按最终权重把原 G 值混合到 `max(original_G, G_floor)`，不能降低原 G，也不修改原始 light map 文件。该功能不支持独立右腿选择或自动识别 AO 缺陷；程序只检查参数，不保证校准区域与真实瑕疵匹配。

## 可选 Body 法线修正

`normal_correction_path` 指向角色自己的 `res://` JSON；留空表示保留作者原始法线。不应复制样例修正行到其他网格。JSON 必须提供 `schema: 1`、正整数 `vertex_count` 和数组 `normal_rows`，每行为 `[index, source_x, source_y, source_z, normal_x, normal_y, normal_z]`。索引必须唯一、整数且不越界，全部数值有限，法线非零；空修正数组有效。位置和法线使用原始 Body surface 0 的 mesh 局部空间，修正值直接写入，不由程序重新归一化，制作时应提供单位法线。

定义校验检查 JSON 结构，模型检查及应用前进一步核对原始顶点数量和每行源位置，位置误差必须小于 `0.00001`。应用先完成全部校验再写入法线，拒绝时数组保持不变。必须在动作蒙皮、装备追加和 Body 重建之前应用；共享原始网格不被写回。无修正配置时不要求提供 JSON。

此合同仅证明顶点数量和被记录位置相符，没有检查全部顶点或三角连通性；重复位置顶点互换也可能无法区分。`source_sha256` 等哈希、`seam_groups`、`stitch` 等旧样例字段只作制作追溯，不参与运行时法线应用，不代表袜口配置或几何接缝质量已验收。样例 JSON 保留原值，上游采集与生成器已迁入插件，命令见 [表面重建](body_surface_baking.md)。

## 给制作 AI 的提示词

为当前角色制作织物颜色、R 通道粗糙度、切线空间法线及 Body UV 对应的 alpha 服装掩码，提供 Texture2D 配置和导入说明。让前三张纹理的织纹相位与周期一致，记录每 tile 的实际重复次数和目标米制纱线周期，选择不会穿插或浮起的壳偏移；检查掩码上下方向及与腿部域的交集，不要复制示例角色的掩码。根据 actor 静止坐标设置高度区间、中心半宽和低位全宽阈值，并用腿部和手部/躯干负例确认范围。如需修复网格法线接缝，按当前原始 Body 的索引和局部位置交付上述修正 JSON；无需修正则留空路径。运行程序检查，然后依照 [丝袜复核用例](tests/hosiery_review.md) 提供旋转、动作、透明度和关闭层的对照证据。
