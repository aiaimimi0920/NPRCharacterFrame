# model.face_motion：外部 AI 复核

程序路径：以角色定义运行 `.ci_script/model/check_model.gd`，检查 face_motion_profile 参数、眼睑 JSON 结构以及原脸睫毛索引；完整眼动生成时额外核验组件选择得到的每侧拓扑数量。框架自身回归用 `.ci_script/framework/face_motion_profile_regression.gd` 验证另一套六顶点校准可以驱动 runtime helper，它不是用户完整角色的替代验收。

外部 AI 输入：程序 report.json、角色校准配置、相机/光照说明和截图。截图至少覆盖默认、左右/上下极限注视、最小/最大瞳孔、闭眼 0/0.5/1；可用展示场景的现有控件采集，或由外部自动化驱动同一控件/API。保持相机和光照一致；缺少任何状态时记录未评估，不用其它状态代替。

提示词：根据校准及程序证据，检查左右一致性、眼白/瞳孔/高光是否整体移动、脸皮和眉毛是否被误带动、瞳孔缩放是否穿插、半闭/全闭是否连续，以及符号画布是否跟随眼睑。先区分数据、几何和材质原因，引用具体截图区域；不能只靠拓扑计数推断视觉通过。

输出 compliance_errors、visual_suggestions、not_evaluated；每条包括规则/目标、证据、建议和复核方法。程序硬性失败保留，主观外观差距归为视觉建议。只提出建议，不修改模型，不调用插件内置 AI 服务。

当前样例可附 [眼睑烘焙](../performance_baking.md) 的保存后 receipt，复用四曲面的几何/UV、closed/arc 及原 Face 睫毛位移对照结果。明确区分 probe 文件哈希与眼睑元数据的规范化 JSON 哈希；不要将二者不同写成输入合规错误。闭合贴合和穿插仍需截图/连续帧证据。
