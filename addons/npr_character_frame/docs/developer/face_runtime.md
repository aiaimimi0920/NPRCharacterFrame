# 面部运行时入口

`runtime/face/npr_face_rig.gd` 是组合入口，负责诊断眼、原眼睑、符号眼/嘴、控制器、表示同步及信号生命周期。它不读取 showcase 状态、不创建 UI，也不依赖固定样例资产。角色须具备已验证的 eye-geometry、face-motion、face-atlas、symbol-surface 和动作数据。

## 创建

先初始化 `NPRCharacter` 与 `runtime/animation/npr_performance.gd`，再创建 rig。rig 的父级应处于 actor 空间，保持单位局部变换；每个角色只创建一个实例。

```gdscript
const FACE_RIG = preload("res://addons/npr_character_frame/runtime/face/npr_face_rig.gd")

func attach_face(actor: NPRCharacter, performance: Node) -> Node3D:
	var rig := FACE_RIG.new()
	actor.add_child(rig)
	rig.setup(actor, performance)
	return rig
```

`setup()` 是一次性操作，要求节点已进入场景树、角色和动作驱动初始化完成。动作驱动的 `source_space(role)` 提供原网格局部空间到 actor 空间的静止变换，role 0/1/2 对应 body/face/hair。面部曲面不再读取 `_spaces`。

## 节点和接口

rig 的 `eye_layer` 与 `original_lids` 是其子节点；`symbol_eyes`、`symbol_mouth` 为保持源脸 skin/skeleton 关系，挂在角色 face mesh 下。使用这些属性访问节点，避免依赖宿主展示场景路径。

`set_eye_focus()`、`set_pupil_scale()`、`set_eye_lid_closure()`、`set_eye_wetness()` 和 `eye_pupil_contract()` 委托眼控制器。注视/尺度变化发出 `eye_controls_changed`；side 为 -1 双眼、0 左眼、1 右眼。

`controls` 负责输入和材质/网格应用，`presentation` 负责表示选择。`presentation.request_eye_geometry()` 记录诊断眼请求；`apply_expression_frame()` 接收含 `eye_symbol`、`mouth_symbol` 的已求值 Dictionary。rig 自动订阅驱动的 `expression_evaluated` 与 `pose_applied`，以及 `RenderingServer.frame_pre_draw`。保存与 UI 层不需要重复连接这些更新信号。展示层继续负责将已保存状态映射到运行时接口。

## 释放与重建

rig 离开场景树时主动断开动作与全局帧信号，并对挂在 face mesh 下的两个符号曲面执行 `queue_free()`；其自身子节点随 rig 释放。符号曲面的释放在帧末完成。同一 actor 上重建时先释放旧 rig，等待待释放节点清理，再创建新实例并重新应用当前状态。

rig 用于随角色销毁或替换，不作为显示开关；显示切换使用 `presentation` 接口。退出树后的实例不可重新 setup 或重新挂入复用。重建时不要保留旧 `controls`、`presentation` 或节点引用。

## 验证范围

[配置与生命周期回归](../../.ci_script/framework/eye_geometry_profile_regression.gd) 验证真实角色上的替代配置、独立装配/控制/表示、符号曲面清理、信号断开及同角色重建。固定视觉和工作台另由各自回归验证，已知失败见 [实施记录](../design/implementation_status.md)。这些检查不代替第二个标准角色的完整验收。
