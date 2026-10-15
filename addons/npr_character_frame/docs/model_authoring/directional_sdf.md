# 定向面部 SDF（664已确认切片）

可选材质脚本：`res://addons/npr_character_frame/shaders/face/sdf360/sdf_materials.gd`，继承 NPRCharacterMaterials。保留原有必需纹理字段，额外设置 face_sdf360 纹理。没有此纹理时沿用原框架材质；不会强制改变已有角色。

图集有24个循环方位列、7个仰角行（-90°到90°）。线性距离值0.5为边界，亮侧正距离。每块四周2px扩边，块大小由纹理尺寸推导，支持128/256等分辨率。禁用mipmap与重复寻址。Shader在头部局部X右/Y上/Z前空间采样，四邻块距离插值后再smoothstep。两个极点的所有方位块必须一致。

664生成示例使用连续凸形艺术化光照代理，不直接把眼窝和嘴唇的细碎法线作为面部阴影。此前663实际画面出现眼周孤立色块和横条，已由这次修复替换。几何未改变。

离线源代码位于 `.ci_script/tools/sdf360/`。bundle.py接受--recipe-dir（授权的face.py/face_style.json目录）、--output与可选--workspace，输出Beaver原生blender.start请求。本脚本不自行启动Blender或AI；现有Beaver示例提供完整头部生成配方和恢复输入合同。

可调参数：u_npr_sdf360_enabled、u_npr_sdf360_softness、u_npr_sdf360_debug。使用者可以通过ShaderMaterial调节开关、边界柔度与黑白诊断。

验证：9项纯测试、250真实渲染/诊断截图、10项方向明暗图像检查、首尾接缝和模型身份检查。2026-10-15用户确认本轮效果。仅覆盖单主光、当前头部切片；不包含多灯合成、通用投射阴影、全部角色/表情或完整产品验收。原生模型验证未覆盖全部资产依赖，新生成输出另核对SHA256。

本实现使用自有计算与数据；没有分发参考视频或银狼模型的SDF资源。复制插件即可获得材质类，角色贴图仍由作者按合同提供。

## 安装与输入校验补修

定向图集当前只支持生成材质模式（use_source_materials=false）及显式 sdf_on_uv2=true；源材质模式与非空定向图集组合会明确报错，避免静默忽略效果。空图集继续沿用基类行为。Face 网格仍需满足既有 UV2 模型检查。

非空图集宽必须整除24，高必须整除7，每块宽高均大于4；尺寸检查不能代替2px扩边像素正确性的烘焙验证。非方形块本身不被错误拒绝。生成定义只引用固定插件路径，并对缺失/重复绑定字段立即报错。七个资源保留此前实际 Godot 导入生成的 UID，避免重新生成身份。

补修验证：14项纯 Python 测试；在独立临时宿主复制插件、使用既有 4.8-dev 引擎运行 engine_contract.gd，15项断言通过（实际生成定义加载、材质类、图集绑定、null、有效128/256内核、非法尺寸、边距、UV2和源材质组合）。这不是完整角色渲染或全产品验收。运行入口：--headless --path <host> --script res://addons/npr_character_frame/.ci_script/tools/sdf360/engine_contract.gd；仅在临时宿主执行；小型程序纹理 fixture 只用于尺寸与资源绑定检查，不代表有效的光照数据。
