# 诊断眼模型与标记

角色定义的 `eye_geometry_profile` 指向 `NPREyeGeometryProfile`，其中 `model_scene` 为导入 GLB 或 Godot PackedScene，`landmarks_path` 为项目内 `res://` JSON。基础渲染可为空，完整 showcase visual layers 必须提供。样例配置见 [eye_geometry.tres](../../samples/silver_wolf/profiles/eye_geometry.tres)。

## 场景约定

根为单位变换的 Node3D，眼部位置已按显示高度对齐后的 actor 空间制作。根的直接子节点必须为单 surface 的 MeshInstance3D，不能有嵌套节点。每侧至少包含 `EyeL_Sclera`、`EyeL_Iris`、`EyeL_Pupil`、`EyeL_TearFilm`，另一侧将前缀换为 `EyeR_`。允许同前缀的 `UpperLid` 和 `LowerLid` 可选网格。名称用于左右分组和材质分类，不接受任意命名自动适配。

Sclera、Iris、Pupil 的源 surface 材质必须是 StandardMaterial3D，运行时读取其 albedo_color 和 albedo_texture 并换成眼表 shader；TearFilm 使用泪膜 shader，可选眼皮使用角色 face 材质。装配会移除导入根并保留子节点变换，整个眼层跟随 canonical head 形变，因此导入根不得携带额外位移/旋转/缩放。

样例虹膜由 GLB 嵌入图片导入为 `eye_authored_v1_eye_iris_v1.png`，两眼实际绑定同一派生纹理并保留 mipmaps。作者 PNG 基线位于 import_sources，仅随插件源码交付；制作和导入关系见 [诊断眼烘焙](eye_baking.md)。

## 标记 JSON

`schema` 为 2，`landmarks` 提供 `EyeL.center`、`EyeR.center`，每项为三个有限数值 `[x, y, z]`。中心与角色 face-motion 资源的 lid profiles 使用同一 actor 空间。运行时以中心为原点转换眼睑轮廓为 `eye_profile` 和 `eye_bounds` shader 参数。

样例 JSON 中 source、glb、hash、objects、materials、aperture、bone、closure_shape 和其它制作说明可用于追溯；当前运行时只从 JSON 消费左右中心。实际模型使用 `model_scene`，不能通过修改元数据中的 glb 字符串替换模型。源纹理通过场景材质交付。

## 制作与边界

给制作 AI 的提示词：提供符合命名和材质约定的眼场景，使用当前模型的对齐空间和真实左右眼中心，保持场景与 lid profiles 一致。运行程序检查，再按 [诊断眼复核用例](tests/eye_geometry_review.md) 采集独立左右注视、瞳孔尺度、闭合和湿润视图。不要复制样例中心或把追溯元数据误当作生效参数。

## 光学与运动配置

`gaze_gain` 是左右注视的 actor 空间 XY 位移尺度，必须非负有限；CPU 的虹膜/瞳孔位置与 shader 的 `focus_offset` 使用同一配置。瞳孔比例仍使用公共状态范围 0.65–1.35。

`aperture_size` 必须为正有限数值，和有限的 `aperture_slope`、范围 [0, 1] 的 `upper_shade` 一起控制上眼睑阴影归一化。真正裁剪边界来自 face-motion 的 lid profiles：左右各 65 列，X 递增且上下轮廓均匀同位采样，误差不超过 0.000001。配置诊断眼时必须同时提供 face-motion 资源。

`layer_depths` 顺序为 Sclera、Iris（含可选眼皮）、Pupil、TearFilm，非负值表示向后退。`closure_meeting` 在 [0, 1] 内指定闭合位置；`shell_offset`、`shell_bulge_max`、`shell_bulge_ratio` 为非负有限曲面参数。不要照抄样例尺度而忽略模型空间。

泪膜配置为 `tear_tint`（各分量 [0, 1]）、`tear_alpha`、`tear_transmission`（[0, 1]）、`refraction_strength`（[0, 0.05]）、`ior`（[1, 2]）、`thickness`（[0, 0.02]）。湿润量仍由动态展示状态控制。初始化后编辑 profile 需重新装配并绑定材质。

资产、标记与上述光学参数已归属角色 profile；统一接入节点为 [face rig](../developer/face_runtime.md)，组合 `runtime/face/` 下的装配、控制与表示同步模块并管理节点和信号生命周期。展示层负责保存/UI 适配。眼部 shader 与共享 include 位于 `shaders/eye/`。结构和数值校验不证明实际网格位置、眼睑贴合、穿插或最终模型闭合质量。

当前样例的刚性眼表、虹膜与 schema 2 标记可按 [诊断眼烘焙](eye_baking.md) 重建，并核验实际保存源和 GLB；共享滑动眼皮由独立生成链提供，未启用旧独立眼皮制作函数。固定样例坐标不作为其它模型的推荐值。
