# 样例诊断眼表与虹膜烘焙

[build_wardrobe_eye.py](../../.ci_script/tools/build_wardrobe_eye.py) 制作左右各四个刚性眼表：Sclera、Iris、Pupil、TearFilm，并生成 256×256 sRGB 程序虹膜。眼中心通过当前 Face 的 BVH 射线求得，眼表深度拟合共享滑动眼睑轮廓。此工具沿用样例中心、孔径、斜率和层深，不提供其它模型的自动校准。

## 输入与运行

需要 Blender CLI，实际验证版本为 5.2.2 LTS。将 `blender` 放到 PATH，在宿主项目根目录执行：

```powershell
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_eye.py --
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_eye.py -- --verify-only --report .temp/eye_bake/verified.json
python addons/npr_character_frame/.ci_script/tools/test_build_wardrobe_eye.py -v
```

测试也支持 `--blender <executable>`、环境变量 `BLENDER_EXECUTABLE` 或 PATH，不写死安装地址。保留 `--python-exit-code 1`，确保脚本异常返回失败。

默认配方 [eye_bake_inputs.json](../../samples/silver_wolf/import_sources/eye_bake_inputs.json) 仅复用现有两个输入，不新增大文件副本：

- [character_rig.blend](../../samples/silver_wolf/import_sources/character_rig.blend)：读取 raw rest Face 的顶点、面和世界变换，建立眼中心定位用 BVH；不求值旧 Shape Key 默认权重。
- [lid_surface_v2.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/lid_surface_v2.json)：读取左右各 65 列的 upper/lower 曲线，用于眼表深度拟合。

两文件 SHA256 分别为 `c26b3afd371ab118a01f9772adae1d07c9d11b7adbb22ef6395ef19417ab2dbd` 和 `2c4604a41336608bcb45e30dce5a64f7afa7512ec97b8a22e1a3ed6269807d8f`，与正式眼部 manifest 记载的输入相同。新入口不读取旧项目、外部备份 manifest 或整个快照；旧 JSON 中的 backup_manifest_sha256 仍是历史来源，新输出不包含该字段。

作者虹膜基线保存在 [import_sources/eye_iris_v1.png](../../samples/silver_wolf/import_sources/eye_iris_v1.png)，256×256 RGB、76329 字节，SHA256 `09bc7555a3d81ed86ceed022321d6e64239d4160b03c2f7b9218a89b99f88c5c`。它用于制作身份和重建回归；生成器仍在 scratch 输出同名 PNG，并让新 Blend 相对引用该输出，不把基线图片当作程序生成的输入。

配方按自身目录解析相对路径，拒绝绝对/越出 addon 的路径，逐项验证身份。写输出前检查 schema、65 列有限曲线、上下同位 X、正孔径、X 递增且均匀采样，以及当前样例 Face 对象、3748 顶点、有限世界位置和眼中心射线命中。几何校准只适用于此样例；其它角色按 [诊断眼标准](eye_geometry.md) 制作自己的资产。

## 输出及保存后检查

默认写宿主 `.temp/eye_bake/`，按脚本位置发现 project.godot，支持宿主改名和异地 cwd。支持 `--recipe`、`--output`、`--report`；相对参数按调用者 cwd 解析。输出和报告拒绝写入交付 addon，正式 GLB、虹膜、JSON 和导入配置不被覆盖。

- `eye_authored_v1.blend`：8 个独立刚性眼表，无蒙皮、闭合 Shape Key 或额外眼皮；虹膜引用 `//eye_iris_v1.png`，两文件一起移动后仍可重新打开和验证。
- `eye_authored_v1.glb`：8 网格、4 材质、1 张嵌入虹膜，无外部 buffer/image URI、骨架或动画。每侧 Sclera/TearFilm 为 585 顶点/1024 三角形；Iris/Pupil 的制作源为 241 顶点/240 多边形，GLB 三角化后各 432 三角形。
- `eye_iris_v1.png`：256×256 sRGB 程序径向纤维、边缘环和高光；文件身份记录在 manifest 和生成记录。
- `eye_authored_v1.json`：沿用 schema 2 的中心、孔径、对象/材质、深度拟合与制作参数，路径使用输出文件名，记录本次真实来源身份。
- `eye_generation.json`：两份代码、配方、两输入、四产物以及 Blender 版本/commit，无本机绝对地址。
- `verification.json`：完整保存后核验通过才写的 receipt；`--report` 可指定其它路径。

正常生成自动执行 [verify_wardrobe_eye.py](../../.ci_script/tools/verify_wardrobe_eye.py)，也可独立 verify-only。核验器先核对代码/配方/输入/输出身份，再从输入重新制作期望眼表与虹膜，打开实际保存的 Blend，对照全部顶点、原多边形索引、UV、平滑标记、世界变换及材质节点/连接；保存属性最大误差不超过 `1e-7`。刚性、对象命名、独立父级、材质槽和相对虹膜路径也必须满足约定。

随后分别从保存源和输入重建场景导出 GLB，与交付 GLB 比较完整 JSON 和嵌入 BIN；仅排除 glTF asset 中的 exporter 标签。此检查覆盖导出几何/法线/UV、节点变换、完整材质属性和嵌入图片，防止 Blend 与 GLB 被一起改动后仅靠彼此一致获得通过。临时复核产物在检查结束自动清理。程序虹膜 PNG 必须与输入重建结果逐字节一致。

旧生成器定义的独立 lid() 函数没有被主流程调用，因此没有迁入。当前眼皮和睫毛闭合由 [基础骨架与滑动眼睑](performance_baking.md) 生成并由 face rig 组合，眼表自身保持刚性；不能把此工具描述成共享眼皮制作入口。

## 回归与外部 AI 复核

持久测试仅复制两脚本、配方和两输入到 `.temp/` 下的改名宿主，从无关 cwd 调用。完整比较正式 manifest 除明确来源路径/文件身份/Blender 标签外的全部字段，GLB 比较完整 JSON/BIN，虹膜比较全部 PNG 字节。重复生成 GLB/PNG 应字节一致，并重新打开两份 Blend 核验；另将完整输出移到新目录验证相对纹理路径，源输入哈希不得变化。Blend 容器及包含其哈希的制作记录不承诺跨次或跨版本逐字节一致。

Godot 样例 GLB 使用 `gltf/embedded_image_handling=1`（Extract Textures），导入器从嵌入 PNG 生成并加载 runtime 下的 `eye_authored_v1_eye_iris_v1.png`。该派生纹理启用 mipmaps，眼部装配从场景材质读取它；随 GLB 保留其 .import 配置。作者基线存于带 .gdignore 的 import_sources，构建排除该目录；运行包只保留实际绑定的派生纹理及其导入产物。两张 PNG 当前字节相同，制作身份、导入参数和运行归属分别记录。

负例覆盖输入身份/缺失/schema/绝对/越界路径，更新哈希后的坏采样/非有限位置/错误孔径和实际缺失 Face 的 rig。保存后检查覆盖改动顶点、材质、GLB 节点、程序 PNG、产物身份及 addon 输出/报告拒绝；还同步修改保存材质和 GLB，证明与输入重建结果的检查能拒绝一致但错误的产物。失败不写新的成功 receipt，测试临时宿主自动清理。

按 [诊断眼复核用例](tests/eye_geometry_review.md) 采集原眼/诊断眼开关、独立注视、瞳孔尺度、半闭/全闭与湿润连续帧，附程序报告、保存后 receipt、输入身份和 profile：

> 复用程序几何、材质、纹理和标记证据，检查眼中心对齐、眼皮贴合、瞳孔漂移、层间穿插及泪膜遮挡。分别输出合规错误、视觉优化建议和未评估内容，每条引用具体视角、帧和部位。保存源与导出一致不证明注视或闭合视觉质量；证据不足时不虚构通过。只输出建议，不修改模型。

插件不调用 AI。工具/import_sources 随插件源码交付，运行包排除它们。当前样例重建不替代通用校准、第二角色或完整 P05/P06 验收。
