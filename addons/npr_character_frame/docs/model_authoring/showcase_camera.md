# 展示镜头制作规范

`NPRShowcaseCameraProfile` 通过 `NPRCharacterDefinition.showcase_camera_profile` 输入。基础渲染可省略；完整 `showcase/wardrobe.tscn` 必需。不得把银狼坐标视为所有角色标准。

## 字段与坐标

坐标以展示完成高度对齐后的 actor 空间为校准基础，Y 向上，默认正面相机在目标 +Z；不是源建模文件的原始局部坐标。目标和距离应结合实际展示高度、角色比例、动作与 UI 遮挡校准。

| 字段 | 规则 |
|---|---|
| `view_heights` | `PackedFloat64Array`，严格三项，依次 full/half/face 的目标 Y，均有限。 |
| `view_distances` | 同顺序三项双精度距离，均有限且大于零。 |
| `horizontal_offset` | 有限，相机全身水平偏移；切换预设按该预设距离/全身距离缩放。 |
| `vertical_offset` | 有限，相机位置的 Y 偏置，不是目标 Y 或 Camera3D.v_offset。 |
| `field_of_view` | 有限，1–179 度；初始和重置视角使用。 |
| `pressure_target` | 有限 Vector3，软组织观察目标。 |
| `pressure_distance` | 有限且大于零，软组织观察距离。 |

保留双精度数组，避免把既有构图转换成 float32 后引入微小变化。`validate()` 只验证结构和数值，不保证构图。参考资源为 `samples/silver_wolf/profiles/showcase_camera.tres`；应为新角色独立制作资源。

## 初始化与交互

进入展示场景树前设置完整 definition。展示实例深复制 profile，源资源后续修改不会改变当前实例；重新实例化以应用新作者配置。profile 不写入用户 schema 10 方案。通用 near、滚轮限制、拖动灵敏度不是角色校准项。

全身/半身/面部切换保留当前俯仰、目标 Z 和当前 FOV，不是完整重置；全身水平偏移为基准。重置视角恢复作者初始 FOV、全身目标和距离，清平移/旋转。压力镜头使用独立目标和距离并清旋转、水平偏移。

质量观察页的近／中／远距离固定为 [3,7,18]，属于现有质量评估协议，不是新增的作者距离预设。三档目标 Y 使用实例快照的 full 高度，水平偏移按 horizontal_offset × 当前距离 / full 距离缩放；清目标 X/Z，保留俯仰和当前 FOV。A/B 锁定时不改变镜头，质量观察不写入方案。

## 验收责任

作者须提供三种预设、压力观察及重置的真实展示截图，注明分辨率、动作、旋转、FOV 和资源身份。检查头脚裁切、脸部大小、UI 遮挡、软组织可观察性及动作越界。数字通过与默认样例图不替代新角色视觉验收。按 [共用复核协议](tests/showcase_camera_review.md) 分开记录合规错误、视觉建议和未评估项。
