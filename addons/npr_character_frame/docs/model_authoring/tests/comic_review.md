# 漫画校准的程序与外部 AI 复核

输入为本角色 definition/comic profile、动作数据和实际运行截图，使用同一份证据完成程序与外部 AI 路径，不重复生成已有截图。资源格式见 [漫画标准](../comic.md)。

## 无需 AI 的路径

1. `check_model.gd` 校验已配置 profile 的标准骨名、有限值、三项数组及正尺寸；null 对基础渲染合法，完整展示必须配置。报告保留 `not_evaluated`。
2. 在实际展示保持固定相机/动作/光照，以三卡片和 tear/hatching 做开/关及恢复对照；head 动作验证锚点变形，替代作者配置确认没有回退样例常量。
3. 分别绕转 actor 和 camera，保留同一 token 的出生局部坐标，检查背面隐藏与背面生成不重新定位；hold 后释放并验证到期、取消和节点回收。
4. 把符号放在真实动态 Hair 后方，比较 scene / overlay / 隐藏头发三种模式。物理 ray hit 本身不证明渲染遮挡；任何不符合精确断言的结果须记录失败，不扩大 overlay 的含义为仅忽略头发。
5. 两实例采用不同 profile，材质/锚点/资源及保存方案互不污染。框架回归入口见 [测试说明](../../developer/testing.md)；当前样例专项不自动加载外部第二角色。

## 交给外部 AI 的提示词

“你是 NPR 角色漫画效果复核员。依据角色制作规范和附图，逐项判断 sweat/anger/emphasis 的位置、尺寸、出生后绕转连续性；tear/hatching 是否贴合眼下/脸颊而非漂浮平面；head 动作是否跟随；背面是否有 ghost；真实头发 scene 遮挡与 overlay 对照是否符合说明。只依据提供证据，缺少视频、背面、到期或第二实例证据时记为未评估。合规事实、视觉建议和无法判断项分开，给出图片/帧及可复现问题，不虚构评分，不将程序 ray hit 或样例通过认作遮挡/新角色完整验收。不要修改模型。”

输出按 `compliance_errors`、`visual_suggestions`、`measurements`、`not_evaluated` 分组。外部调用者选择自己的 AI 服务并保存实际回复；生成提示词不是 AI 验收完成，插件不接入 AI API。
