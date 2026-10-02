# 漫画效果角色校准

完整展示角色须在 `NPRCharacterDefinition.comic_profile` 指定 `NPRComicProfile` Resource。基础渲染可留空；已配置但非法的 profile 由 definition 校验拒绝。新 profile 不提供隐式银狼默认值。共享 Resource 作为只读作者输入；运行时计时、tint、opacity、hold 和表情所有权不是制作数据，也不写入装扮方案。

## 坐标与字段

- `anchor_bone`：现行 [动作标准](performance.md) 的 canonical 骨名，样例使用 head；不能凭任意原始骨架名配置。
- `anchor_origin: Vector3`：display-height 对齐后的 actor 静止空间锚点。运行时取 `bone_deformation(anchor_bone) * Transform3D(Basis.IDENTITY, anchor_origin)`，父 actor 再应用世界变换。
- `card_offsets: PackedVector3Array(3)` 和 `card_sizes: PackedVector2Array(3)`：严格依次为 sweat、anger、emphasis；偏移是生成时观察平面相对锚点的偏移，尺寸为原始卡片宽/高。必须有限，宽/高严格正值。生成时经 face/hair 几何采样调整深度，随后保持出生时的锚点局部位置，后续旋转相机不能重布置卡片，背面不出现 ghost。
- `tear_left/right`、`hatching_left/right: Vector4`：XY 是同一 actor 静止空间中的区域中心，ZW 为严格正值的完整宽/高。左右命名沿用当前 Face 标定，必须用本角色的实际眼下/脸颊位置制作，不推断为任意骨架的解剖左右。

所有分量必须有限。校验只证明结构和数值有效，不证明脸部覆盖、尺寸审美或遮挡正确。tear/hatching 走原 Face 材质的 SURFACE 路径，没有被消费的两种卡片偏移/尺寸字段已移除；shy/tension 使用排线并组合现有表情，star/heart eyes 走现有符号表示，不能把它们都当悬浮卡片。

## 独立宿主绑定

先校验 profile 与动作数据，再由宿主创建和持有锚点，随 `pose_applied` 更新上述变换。使用 `NPRComicLayer` 管理寿命/替换/取消。贴脸效果先调用 `profile.apply_material(actor.materials[1])` 绑定五个静态 uniform，再使用 SURFACE attachment；动态 world_to_anchor/tint/opacity 仍归 comic layer。不得对导入源或另一个角色的材质写值。完整展示的 `wardrobe_framework.setup()` 已执行此路径。

原 shader 的前表面 `local.z > 0.005` 域和泪滴/排线造型算法保持不变；region.zw 是区域尺寸而不是新的 shader 阈值。更换角色要重建宿主模块及锚点，不在效果活跃时修改共享 profile。

物理几何采样用 `actor.intersect_role_ray(role, origin, direction)`；它不检查 mesh.visible 或 camera.cull_mask，但仍遵守部件 mask 和几何查询规则。要选可见最近表面用 `pick_surface()`。漫画出生采样保留逐 role 锚点范围筛选，不能用跨角色 nearest 替换；结果不含 UV/triangle，不能用于持久拓扑绑定。

## 制作与验收

作者交付本角色 `.tres`、字段说明、固定相机的开/关图片与 head 动作序列。按 [漫画复核用例](tests/comic_review.md) 测试三卡片、贴脸区域、相机和角色绕转、背面生成、hold/取消/到期及真实头发遮挡。测试同时核对独立角色材质和保存方案不变。程序合规、样例对照及外部 AI 建议分别记录，不用样例通过代替第二标准角色的全功能验收。
