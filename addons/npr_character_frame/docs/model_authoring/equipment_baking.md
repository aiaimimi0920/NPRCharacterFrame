# 样例装备几何与材质烘焙

[build_wardrobe_equipment.py](../../.ci_script/tools/build_wardrobe_equipment.py) 整合样例装备的基础几何与独立材质制作。生成四槽合并几何 `equipment.json`，以及十九个独立网格的材质 GLB。它保留样例固定位置、尺寸、对象名称、色块与 Smart UV 算法；其它角色按 [装备标准](equipment.md) 制作自己的数据，此工具不自动适配模型。

## 输入与运行

需要 Blender CLI，实际验证版本为 5.2.2 LTS。将 `blender` 放到 PATH，在宿主项目根目录运行：

```powershell
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_equipment.py --
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_equipment.py -- --verify-only --report .temp/equipment_bake/verified.json
python addons/npr_character_frame/.ci_script/tools/test_build_wardrobe_equipment.py -v
```

测试支持 `--blender <executable>`、环境变量 `BLENDER_EXECUTABLE` 或 PATH。保留 `--python-exit-code 1`，确保脚本异常返回失败。

默认配方 [equipment_bake_inputs.json](../../samples/silver_wolf/import_sources/equipment_bake_inputs.json) 仅依赖同目录的 [equipment.blend](../../samples/silver_wolf/import_sources/equipment.blend)。归档输入为 115938 字节，SHA256 `cc7bc4225f0b15d91136349ccfe4c38a026cb924c23cd8895fb54cabc74f10a5`，与正式材质 manifest 的 source_input_sha256 相同。配方按自身目录解析相对路径，拒绝绝对路径、越出 addon、错误 schema、缺失文件与身份不符。

工具先程序生成基础装备，再打开归档输入，比较全部对象、几何、UV、变换、集合和材质归属；不匹配时不创建输出。材质阶段仍读取归档输入，保留历史制作的准确来源。新输出的 `equipment.blend` 是经过几何核验的新容器，有独立哈希；不能用其哈希替换归档输入身份，也不要求两个 Blend 文件逐字节相同。

## 两条运行路径与输出

默认写宿主 `.temp/equipment_bake/`，按脚本位置发现 project.godot，支持宿主改名和异地 cwd。支持 `--recipe`、`--output`、`--report`；相对参数按调用者 cwd 解析。输出和报告拒绝写入交付 addon，不覆盖正式 JSON、GLB 或导入设置。

- `equipment.blend`：十九个基础制作网格，按 head/chest/back/weapon 分成 3/4/7/5 个对象。四槽三角形数量分别为 148/344/580/364。
- `equipment.json`：四槽 actor 空间位置、法线、色块及三角索引，运行时合并到私有 Body，复用 Body 材质。骨骼与色块 UV 由角色 profile 提供。
- `equipment_materials_v1.blend` 与 `equipment_materials_v1.glb`：同一装备的十九网格独立材质路径，保留 dark/silver/violet/Material 四种制作 palette。GLB 嵌入纹理，不依赖外部 buffer/image URI；运行时按 profile 中的精确对象名称分槽，与合并模式互斥。
- `textures/materials_v1/`：八张 64×64 作者 PNG，每种 palette 一张 sRGB 颜色图和一张线性 R 通道绝对粗糙度图。运行场景实际绑定三张颜色和三张粗糙度图，共六张；未绑定的制作纹理不计入运行时统计。glTF 导出的粗糙度纹理经过通道打包，文件身份与作者粗糙度 PNG 分别记录。
- `material_authored_v1.json`：记录材质用途、粗糙度范围、metallic/coat、纹理尺寸/色彩空间/通道、对象与输入/产物身份。
- `equipment_generation.json`：记录两份代码、配方、归档输入、十三产物及 Blender 版本/commit，无本机绝对地址。
- `verification.json`：完整保存后核验通过才写的 receipt；`--report` 可指定其它路径。

材质 Blend 使用 `//textures/materials_v1/...` 相对图片引用，整个输出目录一起移动后仍可验证。Blender 在 Windows 保存时可能使用反斜杠；核验仅规范化分隔符，仍要求实际引用为相对路径。生成时禁用 `.blend1` 与 Python bytecode。没有迁入无当前消费者的裸基础 `equipment.glb` 输出。`NPR_MATERIAL_ID` 是制作源属性，当前运行时分组使用 profile 对象名称。

## 保存后核验与回归

正常生成自动执行 [verify_wardrobe_equipment.py](../../.ci_script/tools/verify_wardrobe_equipment.py)，也可独立 verify-only。核验器先检查代码、配方、输入及十三产物身份，再重开归档输入与实际保存的基础 Blend，比对全部几何、UV、变换、集合、材质，并从保存网格重算 bridge，逐项检查 positions/normals/swatches/indices。

材质核验从归档输入重新制作期望结果，完整比较八张 PNG 和 manifest，再打开实际保存的材质 Blend，核对几何、UV、变换、材质节点/连接、材质数值及相对图片路径。保存属性误差上限保持 `1e-7`。分别从输入重建场景和实际保存源导出 GLB，与交付 GLB 比较完整 JSON 与嵌入 BIN，仅排除 glTF asset 的 exporter 标签。此检查防止 Blend 与 GLB 被同步错改后仅凭彼此一致获得通过；复核临时产物自动清理。

持久测试仅复制两脚本、配方和一个输入到 `.temp/` 下的改名宿主，从无关 cwd 默认调用。完整比较正式 bridge、GLB JSON/BIN、manifest 除明确来源字段外的全部字段，以及现存正式 manifest 记载的八张作者 PNG 哈希。当前正式目录仅保留导入后的运行纹理，测试不依赖旧项目中的作者 PNG 副本。重复生成 bridge/GLB/PNG 应字节一致，两份 Blend 独立核验，并移动整个输出目录验证相对纹理；源输入哈希不得变化。Blend 容器及含其哈希的制作记录不承诺跨次或跨版本字节一致。

负例覆盖输入身份/缺失/schema/绝对/越界路径、更新哈希后的实际源对象改名或顶点错误、bridge、材质元数据、保存基础几何、metallic、图片、输出身份及 addon 输出/报告拒绝；同步错改材质 Blend 与 GLB 并更新哈希也须被输入重建对照拒绝。失败不写新的成功 receipt，测试临时宿主自动清理。

## 外部 AI 复核

按 [装备复核用例](tests/equipment_review.md) 采集四槽、两种材质模式、动作、侧后视与湿润对照，并附 profile、输入/产物身份、保存后 receipt 和程序报告：

> 复用程序几何、UV、材质及纹理证据，检查两条路径是否保持相同位置和轮廓，附件骨骼是否符合语义，动作是否漂浮或穿插，色块与湿润响应是否影响正确部位。分别输出合规错误、视觉优化建议和未评估内容，每条引用具体视角、帧和部位。保存源与导出一致不证明动作或最终材质质量。只输出建议，不修改模型。

插件不调用 AI。工具和 import_sources 随插件源码交付，运行包排除它们。样例固定算法重建不替代通用校准、第二角色或完整 P05/P06 验收。
