# 符号表情曲面校准

角色定义的 `symbol_surface_profile` 指向 `NPRSymbolSurfaceProfile`。基础渲染允许为空；使用符号曲面或完整 showcase visual layers 时必须提供有效资源。样例见 [symbol_surfaces.tres](../../samples/silver_wolf/profiles/symbol_surfaces.tres)。所有中心、半径和尺度使用显示高度对齐后的 actor 空间 XY 坐标，Z 表示前后。

## 参数

- `eye_centers`：恰好两个有限 Vector2，顺序为负 X 侧、正 X 侧；`eye_radius` 为两个眼部替换曲面共用的正 XY 半径。
- `mouth_center`、`mouth_radius`：口部替换曲面中心和正 XY 半径。
- `eye_ink_scale`、`mouth_ink_scale`：符号墨迹坐标归一化尺度，两个分量均为有限正数；程序符号内部造型比例与用户 size/stroke 控件保持现有定义。
- `outline_eye_centers`、`outline_eye_radius`：原眼周描边隐藏区域的两个中心和共用正半径，可与替换曲面略有差异以贴合原模型描边。
- `skin_front_min`：有限的前表面 Z 下界；选取三角形的全部顶点必须位于此界前方，face shader 的皮肤清理区域使用相同阈值。

上述资源同时绑定生成曲面、face shader 及 outline shader。制作方应成组校准，避免只移动曲面而留下原墨迹或描边遮罩。资源在初始化时应用；运行后修改需要重新生成曲面和绑定材质。

## 源网格要求和范围

曲面从 performance 已处理的 face surface 0 构造：需要有效的索引、法线、切线、4 槽蒙皮权重和 CUSTOM1，以及与原顶点对应的相对 Blend Shape 数据。CUSTOM1.w 的框架标签 2 表示可采样皮肤；生成口/眼曲面分别使用 3/4。这些标签由框架流程写入，不能随意重新编码。采样前域中应有 XY 投影面积非零的面片覆盖预期曲面区域。

当前实现从原脸皮肤采样并平滑生成替换曲面，沿用源 skin、skeleton、材质、UV 和边界形状；尚需独立评价贴合、洞口覆盖和侧视轮廓。此校准不代替作者制作的最终闭合曲面验收，也不包含诊断眼数据标准。

给制作 AI 的提示词：根据当前模型对齐后的脸部坐标提供两眼和嘴的中心、覆盖半径、墨迹尺度及原眼轮廓遮罩。不要复制样例坐标。先执行参数合规检查，再采集符号开关、大小/描边变化、转头、说话和眨眼恢复的图像，并按 [复核用例](tests/symbol_surface_review.md) 给出建议。

程序合规检查只确认参数数量、正半径和有限数值；不能证明预期区域有足够采样面、表面贴合或视觉遮挡正确。
