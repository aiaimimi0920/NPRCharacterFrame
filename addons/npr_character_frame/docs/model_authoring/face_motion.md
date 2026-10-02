# 眼动与眼睑制作标准（P05-A）

在 `NPRCharacterDefinition.face_motion_profile` 绑定 [NPRFaceMotionProfile](../../npr_face_motion_profile.gd)。基础渲染允许不提供此资源；使用眼动/滑动眼睑功能的角色必须提供。示例见 [face_motion.tres](../../samples/silver_wolf/profiles/face_motion.tres)，其中数值只适用于银狼，不是其它角色的推荐值。

## 交付数据

- `expression_profile`：角色自己的 `NPRExpressionProfile`。每个行为遵守既有四通道所有权协议；当前完整展示仍使用 neutral、blush、sparkle、surprised、tense、happy、sad、angry、sleepy 名称。
- `lid_surface_path`：项目内 `res://` JSON 路径，schema 为 2。不得绑定开发机目录；导出时必须包含动态 JSON。
- 组件分类：feature_component_limit（严格小于）、skin_component_min（严格大于）；眼部高度上下界和前方界；嘴部高度上界、前方界、中心 X 和半宽；左右分界 side_split_x。必须按完整断开的几何组件设计，不能让眼球部件与脸皮共享组件。
- UV 分类：iris_max_u / iris_min_v、pupil_u_range / pupil_min_v、glint_uv_bounds（最小 U、最大 U、最小 V、最大 V）；所有边界使用严格比较。UV 数据与阈值共同决定哪些完整组件进入眼动。边界相邻并不代表允许把脸皮作为眼球部件。
- 拓扑预期：每侧 minimum_eye_vertices 和 expected_pupil_vertices。不要照抄银狼的 100/28；由自己的拓扑确定。运行时眼形生成会核对匹配结果。
- 位移：horizontal_motion 两个 Vector3（负 X 一侧在前）、vertical_motion；pupil_scale_step 必须正数，控制生长/收缩目标与权重换算；pupil_forward_offset 提供生长时的深度间距。
- 眼睑画布：lid_centers 两个 Vector2 和正的 lid_canvas_scale，供符号/眼睑 shader 使用。

所有位置/位移都是经过角色显示高度归一化后的 actor 坐标，不是原始 mesh local 坐标；算法会用提供的 mesh→actor 变换转换。改变 display_height、模型中轴或拓扑后必须重新校准数据。

## 眼睑 JSON

`surfaces` 中每项有 L_ 或 R_ 开头的 name；vertices、normals、closed、arc 为等长的三维数值行，uv 为同长二维行。closed/arc 是相对位移；indices 为非负、整值、范围有效的完整三角形。程序执行闭合权重 c 与弧形中间权重 `4*c*(1-c)`，不要把 closed 写成绝对坐标。

`lash_vertices.L/R` 是原始 face surface 的顶点索引，标识睫毛隐藏范围；不能使用眼睑附加网格的索引。`profiles.L/R` 是上下眼睑轨迹行，每行 upper/lower 为三维坐标。数值必须有限；索引与属性长度由程序检查。

## 给制作 AI 的指令

根据自己的模型测量并生成上述 Resource 与 JSON，先对齐 actor 坐标，再标注完整眼部/嘴部组件和 UV 区域。解释每个分类范围对应的部件、左右顺序和拓扑计数来源；运行 check_model.gd，修正具体错误，不用改框架阈值容忍错误模型。最后提供默认、左右/上下极限注视、最小/最大瞳孔、闭眼 0/0.5/1 的截图进行视觉复核。

程序报告通过仅表示已执行的规则通过，不证明区域选择正确或闭合无穿插。对应 [外部 AI 复核](tests/face_motion_review.md) 可消费程序结果与截图，只输出建议。

## 当前边界

此资源已消除眼动/滑动眼睑 helper 对样例路径和校准常量的依赖，并提供每角色表情 profile 绑定。动作数据、符号曲面和诊断眼球也已由角色配置提供，面部控制与表示已移入 runtime；展示层负责 UI、状态及调度。完整标准角色接入与通用制作校准仍属于后续 P05/P06。

样例 [骨架与眼睑烘焙](performance_baking.md) 复用现有 probe/layout，重建四滑动曲面和睫毛位移，并验证实际保存的 closed/arc 相对 Shape Key。旧脸壳 blink refiner 不属于当前生成链。
