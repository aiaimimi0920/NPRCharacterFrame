# 四槽位装备数据

角色定义的 `equipment_profile` 指向 `NPREquipmentProfile`，样例为 [equipment.tres](../../samples/silver_wolf/profiles/equipment.tres)。基础渲染可以留空；使用装备或完整 showcase 时需要配置，并提供含附件骨骼的 performance 数据。

## 槽位和绑定

框架固定四槽位及保存顺序：`head`、`chest`、`back`、`weapon`。`slot_labels` 提供四个非空显示名，`attachment_bones` 提供四个 performance 骨骼名称，允许多个槽位使用同一骨骼。名称必须存在于动作数据；合并几何时解析为动作骨骼索引，独立材质路径使用名称查询变换。不要照抄样例骨骼索引。

`swatch_uvs` 将色块字符串映射为有限 [0, 1] Vector2。它描述 Body 原贴图中的采样点；框架写入网格 UV 时翻转 V。色块颜色、材质语义仍由该角色的 Body 材质决定。

## 合并几何 JSON

`geometry_path` 是项目内 `res://` JSON。顶层恰好包含四个槽位字典，每项包含非空的 `positions`、`normals`、`swatches`、`indices` 数组。positions/normals 每项为三个有限数字，normals/swatches 长度必须与顶点数相同；每个 swatch 必须在 profile 字典中存在。indices 为整数值的三角形索引，长度为 3 的倍数，且全部位于顶点范围。

位置和法线按角色显示高度对齐后的 actor 空间交付。框架变换到 Body 局部空间，并按每个三角形 `[0, 2, 1]` 的顺序写入索引；制作方应按此约定检查正反面。当前合并路径复用 Body 材质、深度与阴影网格，附加顶点的 CUSTOM0 写为 `[-1, 0, 0, 0]` 以标记装备域。Body 须先由 `runtime/hosiery/npr_garment_geometry.gd` 建立 CUSTOM0，再初始化装备与动作；区域来自角色 hosiery profile，调用顺序见 [开发者文档](../developer/README.md)。

## 独立材质场景

`material_scene` 为 PackedScene，根是单位变换 Node3D，直接子节点全为有网格 surface 的 MeshInstance3D，不能含嵌套节点。`material_slots` 恰好包含四个槽位，各为非空 PackedStringArray，列出对应直接子节点的精确名称；名称跨槽位不能重复，场景与分组必须完全对应。

每个 surface 的有效材质为 StandardMaterial3D，允许 mesh 级材质覆盖。运行时将有效材质复制到私有 surface override，避免湿润调整污染源资源。mesh 变换表示 actor 空间静止位置；姿势应用为附件骨骼变换乘静止变换。独立材质模式与合并几何模式互斥，槽位选择和保存格式共用。

诊断统计返回实际网格数与去重后的已绑定 Texture2D 实例数。当前样例为 19 个网格、6 张纹理（三张颜色与三张粗糙度）；制作清单中未被场景使用的纹理不计入该统计。

## 给制作 AI 的提示词

按四槽位提供 actor 空间装备几何 JSON、独立材质场景和 profile。为每槽位填写显示名、实际动作骨骼名称、所有材质节点名，并提供与当前 Body 材质一致的色块 UV。确保两种显示路径表现同一装备与位置，避免附件漂移、反面和错误湿润区域。程序检查后依据 [装备复核用例](tests/equipment_review.md) 提交槽位、动作、材质模式与湿润对照证据。

装备装配位于 `runtime/equipment/npr_equipment.gd`，展示层负责状态、调用顺序与保存。样例的两条几何/材质路径可按 [装备烘焙](equipment_baking.md) 重建并核验保存源。结构校验和重建一致不证明骨骼选择的语义正确、几何穿插、侧视轮廓或最终材质质量。
