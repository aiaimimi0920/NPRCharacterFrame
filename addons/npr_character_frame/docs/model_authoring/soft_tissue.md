# 软组织压力形变数据

`NPRCharacterDefinition.soft_tissue_data_path` 指向项目内 `res://` JSON。基础渲染可留空；当前完整 showcase 动作驱动要求提供有效数据。该文件描述制作阶段烘焙的 Body 压力 corrective，由压力值线性驱动。样例见 [soft_tissue_v1.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/soft_tissue_v1.json)。

## 必需字段

- `schema` 为 1，`name` 为 `soft_tissue_pressure`。
- `source_vertices` 为正整数，等于导入后原始 Body surface 0 的顶点数。顶点顺序必须一致；数量检查无法证明顺序一致。
- `default` 为 0，`range` 为 `[0, 1]`。0 表示无压力，1 表示完整烘焙形变。
- `deltas` 为稀疏 `[vertex_index, dx, dy, dz]` 数组，索引是范围内的整数且不可重复，所有数值必须有限。位移使用显示高度对齐后的 actor 空间，Y 向上，单位米。运行时将它转换到 Body 局部空间后写入相对 Blend Shape。

未列出的顶点保持零位移，运行时追加的装备顶点也保持零位移。空 `deltas` 是显式无形变资产；程序可以接受它，但不能据此宣称压力效果已完成。默认保持原有效法线/切线方向，压力位移不会自动重新计算表面方向。

当前运行时在 full/balanced 质量级应用相同 corrective，performance 质量级或隐藏时将权重置零，恢复后使用当前压力值。已绑定的 authored skin 如包含同名形状，也会接收同一压力权重。

## 制作证据与检查范围

样例的 `space`、`normal_tangent`、`quality`、`collision`、`domain`、`source` 是制作说明和追溯元数据。保留它们有助于复核；通用程序检查不把文字或声明的碰撞余量当作几何证明，也不把样例左腿坐标约束套用到所有模型。

制作方应保存生成源与输入身份，按该模型的实际受压部位生成稀疏位移，避免越界、穿插或影响无关部位。提供压力 0/0.5/1、恢复零值和动作组合的几何/图像证据。需要无压力效果的角色应交付明确的无形变资产并说明原因。

当前样例的独立 Blender 生成入口、四输入相对配方和保存后 Shape Key 验证见 [压力烘焙](soft_tissue_baking.md)。默认产物写宿主 `.temp/`；现存 rig 与历史 rig 的身份区别保留，正式 bridge 不自动替换。

给模型制作 AI 的提示词：按上述原始顶点顺序和 actor 空间生成 pressure corrective，保证半压力为线性插值；提交作用区域、位移上限和碰撞验证证据。先运行模型合规检查，再使用 [软组织复核用例](tests/soft_tissue_review.md) 输出修改建议，不复制样例的索引和坐标。

当前通用校验只覆盖结构、数值与顶点数量。样例专项测试中的固定部位、碰撞胶囊和图像 ROI 仅用于样例回归，不能证明另一个角色的碰撞或形变质量。其它功能的当前数据标准见 [制作规范入口](README.md)，剩余解耦按 P05 分项处理。
