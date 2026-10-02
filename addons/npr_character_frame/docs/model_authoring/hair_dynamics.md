# 头发与附属动态链数据

角色定义通过 `hair_dynamics_data_path` 指定项目内 `res://` JSON。基础渲染允许留空，当前完整 showcase 动作驱动要求有效配置；动态模拟初始关闭。示例见 [hair_dynamic_v1.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/hair_dynamic_v1.json)，校验见 [npr_hair_dynamics_data.gd](../../runtime/npr_hair_dynamics_data.gd)。

## Schema 3 运行时合同

`schema` 为 3，坐标为显示高度对齐后的 actor 空间。`bones` 列出追加到 [16 根 canonical 骨骼](performance.md) 后的动态骨名，名称唯一且不可与 canonical 重名，索引从 16 开始。

`source_vertices` 和 `weights` 使用字符串键 `"0"`、`"2"`，分别表示原始 Body、Hair surface 0。顶点数为正整数并与实际导入模型一致。每个 weights 数组的行是 `[vertex_index, influences]`，索引不可重复；influences 是 1–4 个 `[bone_index, weight]`，骨骼索引有效、权重有限且在 0–1 内，总和与 1 的误差不超过 0.00001。未覆盖的顶点保持 performance 数据的权重，关闭动态时恢复全部 canonical 权重。

`chains` 是非空数组，每条包含：

- 唯一 `name`、`role`（0 或 2）、canonical `parent` 索引，以及有限且非负的 `radius`。
- `points`：至少两个有限三维向量，相邻点不可重合；`bones`：每个线段一个追加骨索引。所有追加骨必须各归属一条链的一个线段。
- `motion.pinned_nodes`：非空、从 0 开始的连续点索引。`stiffness`、`wind_gain`、`damping`、`max_offset` 各含每个点对应的有限非负数值。数值合法不代表参数能得到理想的稳定性或风格。
- `surface_samples`：非空接触采样行 `[point, influences, plane, face_gap, vertex_index]`。point 为 actor 空间位置；face_gap 有限非负；索引必须在对应原始部件中有效、在该链内唯一，并有显式动态 weights 行。采样和实际顶点权重只能引用自身链的动态骨或其 canonical parent。

Hair 采样的 plane 是 `[nx, ny, nz, d]`，法线为单位向量，遵循 Godot Plane 的 `normal.dot(point) = d` 约定；Body 链不读取 plane，可提供空数组。接触采样重新绑定时会使用实际打包后的网格位置和权重。

`colliders` 为胶囊数组，每项有唯一非空 name、canonical parent、start/end 三维向量和非负 radius。名为 `head` 的粗胶囊在 Hair 表面约束阶段被专门跳过，该阶段使用头部表面。`head_surface` 提供 canonical parent 和 `body_faces`，后者是按每三个点一个三角形排列的有限坐标数组；后续运行时会从实际 Body 中完全受该 parent 控制的三角形重新构建头部碰撞表面。

`head_surface.bvh_origin` 是必需的 `[x, y, z]` 有限数值数组，单位为米，位于与 `body_faces` 相同的 actor 静止空间。制作方选择靠近本角色头部几何的原点，避免 BVH 数值远离零；不是世界位置、骨骼平移、碰撞余量或头部胶囊中心。样例显式声明 `[-0.112, 2.58, -0.06]`，其它角色不能照抄。缺失、错误维度、非数字或非有限值会被拒绝，不再隐式使用样例原点；创建动态模拟前必须先通过数据校验。

作者三角形创建、实际 Body 重新绑定、接触查询共用该实例的原点。查询先通过头部变形逆变换返回 actor 静止空间，再与三角形一样执行 `(point - bvh_origin) * 100.0`。100 倍缩放仍是框架的数值算法常量：小三角形与毫米级移动的行列式可能低于引擎的绝对平行判定阈值，缩放避免这种假漏碰撞。它不改变模型显示尺寸、接触余量、motion 参数或物理单位，不作为角色可调参数。数据校验仅证明数值合法，不证明原点足够接近几何或全范围接触精度；需继续采集真实运动与接触证据。

`set_hair_collision_enabled()` 将开关传给当前动态模拟，启用上述胶囊、头部表面及 `surface_samples` 的接触约束。碰撞制作与检查以角色定义指定的同一份动态 JSON 和当前网格为输入；交付时保持它们的拓扑、骨骼及坐标身份一致。

## 制作与验收

保留样例中同类的源文件、生成器身份和 motion profile 等制作元数据；这些资料不代替运行时结构与几何检查。制作方必须保证头部三角形、采样平面、face_gap 和顶点顺序来自当前模型。顶点数量相同不能证明拓扑顺序相同。静态头发区域、发辫和刘海应按设计分别制作权重及运动参数。

当前样例的相对输入配方、独立 Blender 生成入口及保存后蒙皮验证见 [头发动态烘焙](hair_dynamic_baking.md)。默认写宿主 `.temp/`；原 profile 的历史 rig 身份保持，正式 bridge/GLB 不自动替换。

给制作 AI 的提示词：按当前角色导入后的 Body/Hair 拓扑生成动态链与权重，为所有参与接触的表面制作采样。不要复制样例坐标和顶点索引。先修复模型检查的合规错误，再采集无风/有风、不同动作和动态开关的时序证据，分别说明静态区域、根部与末端运动，并按 [复核用例](tests/hair_dynamics_review.md) 输出建议。

通用程序校验覆盖结构、数值、骨骼归属和原始顶点数；不证明采样覆盖完整、三角形无穿插或审美质量。样例测试中的固定后颈、发辫与刘海阈值只适用于样例。动态及表面接触实现位于 `runtime/animation/`，面部装配及控制位于 `runtime/face/`；完整框架的剩余合同审计和新角色全功能验收仍按 P05/P06 推进。
