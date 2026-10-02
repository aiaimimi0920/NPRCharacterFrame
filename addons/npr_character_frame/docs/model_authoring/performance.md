# 动作、蒙皮与口型数据

角色定义的 `performance_data_path` 指向项目内 `res://` JSON。基础渲染可留空；展示动作与口型时必须提供。路径不依赖宿主目录名。样例数据见 [performance.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/performance.json)，字段检查实现见 [npr_performance_data.gd](../../runtime/npr_performance_data.gd)。

## Schema 1

根字典含 `schema: 1`、`bones`、`weights`、`shapes`、`actions`。当前动画驱动按固定语义索引读取骨骼，`bones` 必须依次为：

```text
root, hips, spine, chest, neck, head, arm.L, forearm.L,
arm.R, forearm.R, thigh.L, shin.L, thigh.R, shin.R, secondary.L, secondary.R
```

`weights` 按 body、face、hair 存放三个数组；每项对应导入后该部件 surface 0 的一个原始顶点，数量与顺序必须完全一致，不能使用 Blender 导出前的索引代替。每顶点含 1–4 个 `[bone_index, weight]`，索引为 0–15 整数，权重为有限的 0–1 数值，总和与 1 的误差不超过 0.00001。运行时新增装备顶点另走附件绑定，不能混入这里。

`shapes` 是形状名到稀疏 `[face_vertex_index, dx, dy, dz]` 数组的映射。索引必须落在原始 face 顶点范围，位移有限，使用显示高度对齐后的 actor 空间。当前必要形状为 `blink.L`、`blink.R`、`blink_mid.L`、`blink_mid.R`、`happy`、`sad`、`angry`、`aa`、`ee`、`ih`、`oh`、`ou`。相同索引的多条位移在运行时相加；空数组表示该形状没有位移，结构检查不会判断其视觉有效性。新增名称只有得到控制器输入才会产生权重。

`actions` 必须提供 `idle`、`greeting`、`look_around`、`presentation`。每项含 `fps: 30` 和至少两帧 `frames`；每帧严格包含上述 16 根骨的变换。每个变换为 12 个有限数值，按 3×4 行顺序存放：

```text
[xx, xy, xz, tx, yx, yy, yz, ty, zx, zy, zz, tz]
```

矩阵表示 actor 空间的蒙皮形变调色板，静止绑定姿态为单位矩阵；不能直接填骨骼局部姿态矩阵。播放器按 30 FPS 插值并循环，制作方应提供连续的首尾帧；程序结构检查不证明循环接缝或旋转插值质量。

## 骨骼诊断端点

角色定义的 `rig_layout_data_path` 指向本角色的 `res://` JSON；基础渲染可留空，完整展示的白模/骨骼诊断装配必须提供。当前样例复用 [rig_layout.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/rig_layout.json)，不另存重复端点。字段检查见 [npr_rig_layout_data.gd](../../runtime/npr_rig_layout_data.gd)。

根字典含 `schema: 1` 与 `bones`，每骨含 `name`、`parent`、`head`、`tail`；名称和顺序与上文 canonical 动作骨骼完全一致。第一根 root 的 parent 必须显式为 null，其余 parent 必须引用之前已有的骨名，从而排除未知父级、自指、环和额外根。head/tail 是有限的三分量数值数组，不能含布尔、NaN/Inf 或超出 Vector3 表示范围的值；骨段必须非零。`coordinate_system` 等作者说明是追溯信息，不代替实际字段检查。

端点使用显示高度对齐后的 **actor 静止空间**，不是模型源节点局部坐标、世界坐标或已经求值的姿态。诊断层将当前 `bone_deformation(name)` 变形调色板分别乘以 head/tail，保留作者骨段和真实动作。运行时 Skeleton3D 是 identity-rest 的平坦调色板，不能从矩阵原点或不存在的父级层次推导这些端点。16 根是当前动作数据标准，不是固定使用银狼坐标的许可；新角色须制作自己的端点。

`load_rig_layout_data()` 每次返回独立 Dictionary，初始化的诊断层保留自己的快照；改动资源后须新建诊断层，不承诺重复 setup 或运行中热更新。诊断数据不进入用户方案，render/white/skeleton 切换不改相机、动作和保存状态。结构通过只证明可解析且符合标准，不证明端点贴合骨架、动作形变或最终穿插质量。

## 给模型制作 AI 的要求

按上述骨骼顺序和导入后的三部件顶点顺序输出 JSON，并提供本角色的诊断端点 JSON。权重、静止端点应按模型实际骨架重新制作，面部形状应根据该模型的嘴唇、眼皮和表情形态制作，不复制样例的坐标、顶点索引或位移。提供四种动作以及各口型、左右眨眼的截图或序列，附同姿态的骨骼/碰撞视图。运行模型检查，先修复 `compliance_errors`，再按 [复核用例](tests/performance_review.md) 整理视觉改进建议。

## 当前边界

此合同覆盖 canonical 骨骼、采样动作、权重和面部 delta。[头发动态](hair_dynamics.md)、[软组织](soft_tissue.md) 和 [符号曲面](symbol_surfaces.md) 分别遵守各自的角色数据标准。诊断眼、装备和雨水已由角色配置提供，完整生成链及新角色验收仍未完成。通过此校验不代表新角色已经能使用完整展示场景；未校验的形变美观性、循环连续性和其它功能数据应明确报告为未评估。

当前样例可用 [基础骨架与眼睑烘焙](performance_baking.md) 重建完整数据，并重新打开 Blend 核验保存的权重、Shape Key 和全部动作帧；固定样例算法不用于其它角色自动校准。
