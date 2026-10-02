# 样例软组织压力烘焙

[build_wardrobe_soft_tissue.py](../../.ci_script/tools/build_wardrobe_soft_tissue.py) 在 Blender 后台生成当前样例的准静态压力 corrective，并从实际保存的 Shape Key 导出运行时稀疏位移。它保留样例左腿筛选、接缝顶点一致选择、压缩及邻近凸起、内核半径限制；这些规则使用固定的样例坐标和皮肤掩码。其它角色需要自己的制作校准，本入口不提供通用软体或 FEM 求解。

## 输入与调用

需要可执行的 Blender CLI，实际验证版本为 5.2.2 LTS。将 `blender` 放到 PATH，从宿主项目根目录执行：

```powershell
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_soft_tissue.py --
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_soft_tissue.py -- --verify-only --report .temp/soft_tissue_bake/verified.json
python addons/npr_character_frame/.ci_script/tools/test_build_wardrobe_soft_tissue.py -v
```

测试脚本也接受 `--blender <executable>` 或环境变量 `BLENDER_EXECUTABLE`；工具和文档不固定本机安装地址。`--python-exit-code 1` 必须保留，确保脚本异常产生失败退出码。

默认输入配方是 [soft_tissue_bake_inputs.json](../../samples/silver_wolf/import_sources/soft_tissue_bake_inputs.json)，四个输入均从配方所在目录按相对路径解析，要求位于交付插件内且 SHA256 一致：

- `rig`：[character_rig.blend](../../samples/silver_wolf/import_sources/character_rig.blend)，保留当前角色骨架、动作和源网格。
- `probe`：[soft_tissue_input_probe.json](../../samples/silver_wolf/import_sources/soft_tissue_input_probe.json)，原始 Body 的位置、UV、三角索引和顶点顺序，复用其它已迁入生成器的输入。
- `garment`：[visual_maps_garment_v1.png](../../samples/silver_wolf/import_sources/visual_maps_garment_v1.png)，历史 RGBA 1024×512 图的 alpha 为皮肤选择依据。
- `body`：[mesh.scn](../../samples/silver_wolf/assets/canonical/silver_wolf/body/mesh.scn)，作为 canonical Body 的文件身份记录；实际数值重建使用 probe 和 Blender Body。

配方保留旧 rig 和旧快照 manifest 的历史哈希。当前 rig 的实际身份不同；完整比较已证明此输入可重建当前 Body corrective 的全部形变、作用域及碰撞字段。该结果不证明整个角色、面部形状、全部权重或动作与历史 rig 等价，不能用历史哈希冒充当前输入身份。旧外部快照没有作为运行依赖。

## 输出与验证

默认输出宿主 `.temp/soft_tissue_bake/`，由脚本位置向上发现 `project.godot`，支持宿主改名和异地工作目录。`--recipe`、`--output`、`--report` 可显式指定；显式相对参数按调用者工作目录解析。输出和报告拒绝写入交付插件目录，不覆盖正式运行资产。

- `soft_tissue_v1.blend`：源角色、相对 `soft_tissue_pressure` Shape Key、制作域及隐藏于渲染的内核/接触线框对象。
- `soft_tissue_v1.json`：[软组织数据标准](soft_tissue.md) 的运行时 bridge；Godot actor 空间 Y 向上、单位米，索引对应 canonical Body surface 0。
- `soft_tissue_generation.json`：当前生成器/配方/四输入的文件名与哈希、实际 Blender 版本和 commit、当前 Blend/bridge 身份及历史 rig 身份，无开发机绝对地址。

`--verify-only` 重新打开保存的 Blend：检查 Body/Shape Key 顶点数量，bridge schema/形状名及合法唯一稀疏位移，逐顶点比较 Shape Key 与 bridge（最大误差不超过 `2e-7`）；静止位置和 UV 误差不超过 `2e-6`，三角索引完全一致，前 16 骨权重和归一化误差不超过 `2e-6`，制作内核对象存在。成功 receipt 记录误差、顶点/三角数量、权重和范围、骨骼/动作名称与输出身份。这些检查不代替碰撞覆盖或视觉质量评价。

持久测试在 `.temp/` 中只复制生成器、配方和四个必需输入，改名宿主后从无关工作目录运行默认烘焙。比较正式 bridge 除 `source` 身份/路径外的全部字段，并独立核对新的 `source`；重新打开 Blend 验证，重复生成要求 bridge 全字节一致，检查源文件不被修改。Blend 容器及生成记录中的 Blend 哈希不要求跨次或跨 Blender 版本相同。

失败测试覆盖四输入身份篡改/缺失、非法配方、绝对/越界路径、bridge 位移篡改/非有限值/重复索引/顶点数量，以及写入交付目录的拒绝。输入失败不得创建输出，验证失败不得写成功 receipt。测试宿主自动清理；用户指定的重建证据留在 `.temp/`，可整体删除。

正式 [bridge](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/soft_tissue_v1.json) 和 [历史生成记录](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/soft_tissue_generation.json) 保留原身份。新记录用于这条独立生成链，不直接替换旧 `analyze_soft_tissue.py` 要求的历史 manifest/generator/source 字段；该分析器的历史追溯检查不能用新 receipt 伪装通过。生成源与 `.ci_script` 随复制插件交付，构建规则将它们排除出运行包。

## 外部 AI 复核

按 [软组织复核用例](tests/soft_tissue_review.md) 提供压力 0/0.5/1、恢复 0 和动作组合的固定视角截图。附 bridge 对照、保存后 receipt、实际位移及域外变化测量，避免 AI 从图像重新猜测已知数值。

> 复用保存后 Shape Key/bridge 一致性、作用域和位移测量，判断该模型受压部位是否平滑、局部且自然；指出穿插、无关部位变化和恢复错误。将明确结构错误与视觉优化建议分开，每条建议引用帧/部位和预期效果。声明的内核余量不等于所有动作碰撞安全；缺少证据时列为未评估。只输出建议，不修改模型。

插件不调用 AI。样例重建通过不替代第二个标准角色或全功能最终验收。
