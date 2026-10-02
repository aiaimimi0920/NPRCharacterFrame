# Face atlas 程序检查与外部 AI 复核

## 无需 AI

使用 `check_model.gd` 对实际 definition 执行校验；提供 `face_atlas_profile` 时检查有限归一化采样坐标、递增 crop/V 区间、正 aspect 和递增正半径。基础 definition 可不提供，完整展示必须提供；通过数值检查不等于视觉通过。

运行 `face_atlas_profile_regression.gd` 锁定真实场景动作、时间、相机与光照，采集原眼 neutral/三尺度/左右独立注视/闭合、圆眼、眼嘴符号、头动、viseme、诊断眼和恢复。保留迁移前图并严格比较，不放宽像素阈值；检查每个校准字段替代后真实 GPU 变化与精确恢复、严格域边界/负 UV/repeat、材质/作者资源隔离和动态字段不被静态绑定覆盖。样例测试不能替代新角色专项。

## 交给外部 AI 的提示词

你是本框架标准角色的 Face atlas 复核者。先读取 [作者规则](../face_atlas.md)、实际 definition/profile、贴图尺寸/颜色空间/通道元数据及输入 SHA256，再根据同姿态/相机/光照的证据比较：accent 缩放是否保留暗轮廓而不污染虹膜；补肤是否残留唇/睫毛或改变脸部明暗；诊断眼是否残留原眼及误删嘴；圆眼是否被 ILM 限制；表示关闭后是否恢复最新左右眼输入。不要根据单张静态图声称时序恢复、源材质隔离或负 UV 边界通过。

输出 `compliance_errors`、`visual_suggestions`、`not_evaluated` 三组，并引用具体文件/帧/参数。缺少原始基线、遮挡、闭合或恢复证据就写未评估；不能虚构分数、自动修改资产或把样例表现作为第二角色验收。
