# 展示袜口高度校准

`NPRCharacterDefinition.showcase_height_profile` 引用 `NPRShowcaseHeightProfile`。基础渲染可省略；完整展示必须显式提供有效资源，没有银狼默认回退。参考为 `samples/silver_wolf/profiles/showcase_height.tres`。

## 字段与空间

高度是完成展示对齐后的 **actor 静止空间 Y**，不是动画后的世界 Y、源模型局部高度或腿长百分比。四个字段均为 GDScript 双精度 float，不用 Vector2 存范围，避免既有存档端点收缩。

| 字段 | 合同 |
|---|---|
| `min_height` / `max_height` | 有限、严格递增，选择与存档使用闭区间。 |
| `default_height` | 有限且位于闭区间内，作为新状态工厂高度。 |
| `step` | 有限且大于零，仅用于 UI 步进，不要求存档数值落在步进网格上。 |

本配置不改变 `hosiery_profile.domain_height_range`：后者负责几何候选域，仍需掩码与所选高度共同确定覆盖。不能根据候选域机械推导 UI 范围，也不能只凭资源结构通过就宣称袜口贴合正确。新角色需将 Body、拟合层和雨水的静止坐标保持一致，并实际观察可用范围。

## 实例、存档与兼容

展示入树时深复制本资源；初始、重置和保存路径重载共用该快照。状态再深复制，源资源后改不热更新已打开的展示。Body、拟合层和雨水继续消费同一状态高度，不另行夹取不同范围。

内部状态构造为 `STATE.new(character_id, palette_profile, height_profile)`，调用者须先验证输入。正常宿主只需配置 definition。旧的两参数内部调用需显式补充资源；没有隐式样例兼容层。

用户方案保持 schema 10：只保存实际高度，不保存作者范围或默认值。合法已有值保持权威，不按新默认重算、不按 step 取整；非法值原子拒绝，不 clamp 修复文件。旧 schema 1–5 缺失高度仍按历史规则补 `1.34`，**不是作者 default_height**。若新范围不包含这个历史值，该旧方案会被拒绝，不改写为新工厂高度。

因此，同一 character_id 缩窄范围可能拒绝旧方案，作者应保持旧合法范围或另行设计显式迁移。不得把不兼容的新角色数据复用旧角色身份。银狼仍为 `[0.5,1.55]`、默认 `1.34`、步长 `0.01`，原方案文件不需要迁移。

## 验收

`showcase_height_profile_regression.gd` 验证替代作者输入、非法资源、快照、三条状态创建路径、真实滑块信号、Body/拟合/雨水消费者、schema 1–10 和 GPU 精确重置。`hosiery_height_contract_regression.gd` 保留银狼历史合同；`palette_contract_regression.gd` 保留完整默认方案字节合同。

作者还须检查实际包中的最小/默认/最大袜口位置、拟合层、主要动作及雨水分类，分别记录合规错误和视觉建议。替代配置仍使用银狼几何的程序测试，不等于第二标准角色或全部动作的视觉验收。
