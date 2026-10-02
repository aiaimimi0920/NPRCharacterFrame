# 样例头发动态烘焙

[build_wardrobe_hair_dynamic.py](../../.ci_script/tools/build_wardrobe_hair_dynamic.py) 将当前样例的 canonical Body/Hair 绑定到动态骨骼调色板，并生成 schema 3 bridge、可查看蒙皮的 Blend 和 GLB。七条链为后发辫、左右侧发、服装垂带及中/左/右刘海；静态后颈、接缝、根部固定和动态区所有权沿用原算法。此入口使用样例的壳编号、坐标和曲线，不提供其它角色的自动校准。

## 输入与调用

需要 Blender CLI，实际验证版本为 5.2.2 LTS。将 `blender` 放到 PATH，从宿主项目根目录执行：

```powershell
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_hair_dynamic.py --
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_hair_dynamic.py -- --verify-only --report .temp/hair_dynamic_bake/verified.json
python addons/npr_character_frame/.ci_script/tools/test_build_wardrobe_hair_dynamic.py -v
```

测试也接受 `--blender <executable>` 或环境变量 `BLENDER_EXECUTABLE`；不固定开发机安装目录。保留 `--python-exit-code 1`，确保脚本异常返回失败。

默认使用 [hair_dynamic_bake_inputs.json](../../samples/silver_wolf/import_sources/hair_dynamic_bake_inputs.json)，仅依赖三个现有输入，无新增 rig 或 performance 副本：

- [character_rig.blend](../../samples/silver_wolf/import_sources/character_rig.blend)：Body/Hair/Face 的源几何和 canonical 蒙皮。
- [performance.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/performance.json)：16 根 canonical 骨骼顺序、Body 刚性头部顶点权重；头部三角形和耳部来自实际源几何。
- [hair_motion_profile_v1.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/hair_motion_profile_v1.json)：静态/动态壳、曲线、固定节点和运动参数。

配方按自身目录解析相对路径，拒绝绝对或越出 addon 的路径，逐项核对 SHA256。当前 rig 与 profile 声明的历史 rig 身份不同；原 profile 的历史身份保持，并由配方明确记录。已完整对照七条链、全部权重/接触采样、头部表面及其它运行字段，证明这份现存输入可重建当前动态资产，不能据此认定整个历史角色或其它动作/表情数据等价。旧外部快照和 `wardrobe_asset_backup` 无运行依赖，历史 manifest 身份仅用于追溯。

配方的 `head_bvh_origin` 是本样例的三分量有限 actor 静止空间坐标，原样写入 bridge 的 `head_surface.bvh_origin`；不由生成器写死，也不参与几何、权重或 GLB 烘焙。非法值在创建输出前拒绝。保存后检查还要求 bridge 原点与当前配方一致，即使修改 bridge 并更新产物哈希也不能掩盖不一致。运行时单位、缩放与其它角色制作要求见 [头发动态标准](hair_dynamics.md)。正式 bridge 此字段是后续显式校准补充；既有历史生成器/源哈希仍保留其原来源含义，新生成记录另行记录当前代码和配方，不冒充历史重烘焙。

## 输出与保存后检查

默认写宿主 `.temp/hair_dynamic_bake/`，由脚本位置向上发现 `project.godot`，支持宿主改名和异地工作目录。`--recipe`、`--output`、`--report` 支持显式输入；相对参数按调用者 cwd 解析。输出及报告拒绝写入交付 addon，不覆盖正式 bridge、GLB 或 `.import`。

- `hair_dynamic_v1.json`：沿用 [头发动态标准](hair_dynamics.md) 的 schema 3；制作路径使用输出文件名，记录当前 rig、profile、生成器和产物的真实身份，不把历史快照哈希作为新来源。
- `hair_dynamic_v1.blend`：Body/Hair、16 根 canonical 骨与 21 根追加动态骨、实际权重和制作碰撞对象。
- `hair_dynamic_v1.glb`：Body/Hair 和 37 骨蒙皮，无外部 buffer/image URI；供制作检查，运行时仍以角色定义中的 bridge 驱动当前 NPR 网格。
- `hair_dynamic_generation.json`：三输入、配方、生成器和产物身份，以及实际 Blender 版本/commit、明确标记的历史 rig/快照身份；无开发机绝对地址。

`--verify-only` 首先检查生成器、配方及三产物身份，然后分别打开输入 rig 和生成的 Blend。检查 Body/Hair 顶点数、全部面索引及所有 UV 层保持；静止位置误差不超过 `2e-6`。检查保存的骨骼顺序、父级和 armature modifier：bridge 覆盖的顶点与其权重一致，未覆盖顶点保持当前输入 rig 的权重，误差及归一化误差不超过 `2e-6`。此外检查制作碰撞对象存在、GLB 的 Body/Hair/37 骨蒙皮及必需几何属性。成功 receipt 记录实际误差、顶点/面数、权重和范围与产物身份。

保存后验证证明当前源和输出之间的对应关系，不证明声明的胶囊覆盖所有接触，也不等同于完整运动稳定性或视觉验收。固定坐标、头部 BVH 接触平面和位移上限仍需按该模型复核。

## 程序回归与外部 AI

持久测试只将脚本、配方和三个必需输入复制到 `.temp/` 下的改名宿主，从无关 cwd 调用默认生成入口。除明确的来源路径/哈希和 Blender 标签外，完整比较正式 bridge 的所有字段；GLB 比较除 exporter 标签外的完整 JSON 和嵌入 BIN，覆盖几何、蒙皮、材质及图片。重复生成再次对照 bridge 和 GLB，并重新打开两个输出 Blend 验证；源文件哈希不得变化。Blend 容器及包含其哈希的制作记录不要求跨次或跨版本逐字节一致。

负例覆盖输入身份/缺失/绝对/越界路径、历史 profile 身份、静态壳、曲线、权重曲线、固定节点、非法 BVH 原点和非有限/负运动参数。即使更新配方使坏 profile 的哈希匹配，也必须在输出前拒绝非法校准。另以有效归一化但错误的骨权重验证保存后不一致拒绝，并验证错顶点数、原点与配方不符、GLB 损坏及 addon 内输出/报告拒绝；失败不得写成功 receipt。替代有限原点只改变 bridge 的对应字段，其余完整运行字段和 GLB JSON/BIN 必须与正式资产一致。测试宿主自动清理。

按 [动态复核用例](tests/hair_dynamics_review.md) 采集静风/有风、动作组合、动态/碰撞开关和恢复的连续帧，复用程序报告、保存后蒙皮 receipt、链端位移和静态区域漂移测量：

> 检查固定后颈和链根是否稳定、侧发与刘海是否自然响应、后发辫和垂带是否穿插或突跳。复用程序身份和权重证据，分别输出明确合规错误、视觉优化建议和未评估内容，每条引用帧与部位。缺少连续帧或接触几何证据时，不宣称碰撞安全已通过。只输出建议，不修改模型。

插件不调用 AI。生成工具和 import_sources 随插件源码交付，运行包按既有构建规则排除它们。样例重建不替代第二角色或完整 P05/P06 验收。
