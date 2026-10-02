# 样例骨架、动作、表情与滑动眼睑烘焙

[build_wardrobe_rig.py](../../.ci_script/tools/build_wardrobe_rig.py) 从现有原始几何 probe 和 rest layout 构造三部件、16 骨蒙皮、12 个 Face 相对 Shape Key、四组动作及四张滑动眼睑曲面。眼睑算法位于 [build_wardrobe_lid_surface.py](../../.ci_script/tools/build_wardrobe_lid_surface.py)，只在制作时执行睫毛 ARAP；运行时没有新增求解开销。入口使用样例的部件标签、口部坐标、皮肤拓扑和动作校准，不能直接用于其它角色的自动适配。

## 输入与运行

需要 Blender CLI，实际验证版本为 5.2.2 LTS。将 `blender` 放到 PATH，在宿主项目根目录执行：

```powershell
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_rig.py --
blender --background --factory-startup --python-exit-code 1 --python addons/npr_character_frame/.ci_script/tools/build_wardrobe_rig.py -- --verify-only --report .temp/performance_bake/verified.json
python addons/npr_character_frame/.ci_script/tools/test_build_wardrobe_rig.py -v
```

测试支持 `--blender <executable>`、环境变量 `BLENDER_EXECUTABLE` 或 PATH，不固定本机安装目录。保留 `--python-exit-code 1`，避免脚本异常被当作成功。

默认配方 [performance_bake_inputs.json](../../samples/silver_wolf/import_sources/performance_bake_inputs.json) 复用两个现存输入，没有再复制大 JSON 或 Blend：

- [soft_tissue_input_probe.json](../../samples/silver_wolf/import_sources/soft_tissue_input_probe.json)：按 Body、Face、Hair 排列的原始 positions、UV、三角索引；保留原捕获中的中文部件标签。
- [rig_layout.json](../../samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/rig_layout.json)：schema 1 的 16 根骨骼名称、父级和静止端点。

输入路径按配方目录解析，拒绝绝对或越出 addon 的路径，逐项核对文件 SHA256。写输出前检查有限位置/UV、完整整数三角索引、三部件顺序、骨骼名称/父级/有效端点及固定皮肤/眼窝拓扑。皮肤组件大小为 1292/107/107，左右眼窝各一条 33 点边界；这些要求来自当前样例，不应复制成其它模型的通用制作参数。

probe 的文件 SHA256 为 `5510eb176b9af55527424312fabba253ddbe2e14012f9c36ef1830500e9b0859`；眼睑 `authoring.probe_sha256` 沿用 `sha256(json.dumps(probe, sort_keys=True).encode())`，为 `5e15bcedaa5c5050ae434f05a8cbf2a3c7eefe29618f2e5b622ab1f2812ac3d8`。这两个哈希使用不同字节表示；它们不相等不能据此判定输入发生变化。新制作记录单独保存文件身份。

## 输出及保存后验证

默认写宿主 `.temp/performance_bake/`，按脚本位置发现 `project.godot`，支持宿主改名和异地 cwd。`--recipe`、`--output`、`--report` 可显式指定；相对参数按调用者 cwd 解析。输出和报告拒绝写入交付 addon，正式运行资源及当前制作源不被覆盖。

- `character_rig.blend`：三部件、16 骨、12 个面部形状、四动作和四眼睑对象；各眼睑 585 顶点/1024 三角形，带 `closed`、`arc` 相对 Shape Key 和刚性 head 蒙皮。
- `performance.json`：按 [动作数据标准](performance.md) 输出全部权重、面部稀疏位移及四动作，每动作为 30 FPS、0–120 共 121 帧、每帧 16 骨的 3×4 形变调色板。
- `lid_surface_v2.json`：按 [眼动标准](face_motion.md) 输出四曲面、65 列眼窝采样、睫毛所有权及闭合/半闭修正。闭合仍为上眼皮 72%、下眼皮 28%，ARAP 保持 20 次、目标权重 0.08。
- `performance_generation.json`：四份生成/核验代码、配方、两个输入和三产物身份，以及 Blender/NumPy 版本；没有开发机绝对地址。
- `verification.json`：所有保存后检查通过才产生的 receipt；显式 `--report` 可改路径。

正常生成自动重新打开刚保存的 Blend；`--verify-only` 可独立复核。[verify_wardrobe_rig.py](../../.ci_script/tools/verify_wardrobe_rig.py) 先验证生成代码、输入和输出身份，再核对全部三角索引、静止位置、UV、骨骼父级/rest、顶点组顺序/权重、armature modifier、全部 Face 和眼睑相对 Shape Key、默认权重与场景/动作帧范围。随后重新求值四动作的全部 121 帧，与 JSON 对照。矩阵使用 `C.inverted() @ pose_bone.matrix @ rest_bone.matrix_local.inverted() @ C`，C 将 Godot Y-up 转为 Blender Z-up。

静止位置、骨端点和 Shape Key 最大误差不超过 `3e-7`；UV、权重及动作矩阵最大误差不超过 `1e-7`；蒙皮归一化误差不超过 `2e-6`。Blender 保存骨数组使用层级遍历序，核验器按名称查 rest 骨；bridge 和顶点组保留 canonical 顺序。创建 Shape Key 显式使用 `from_mix=False`、`value=0`，保证编辑源默认中性，防止当前形状混入后续形状。

新入口合并了原本分开的 rig 和滑动眼睑落盘步骤，最终 blink 稀疏数组与正式数据一致。旧 `refine_wardrobe_blink.py` 和旧 `build_blinks` 的脸壳 blink 位移没有迁入；滑动眼睑只消费眼窝域，不使用那些旧位移，不能再用旧 refiner 覆盖当前睫毛形状。

## 回归与外部 AI 复核

持久测试仅复制四脚本、配方和两个输入到 `.temp/` 下的改名宿主，从无关 cwd 默认运行。完整比较正式 performance 的全部字段和眼睑 JSON 除生成器名称外的全部字段，重复生成比较两份 JSON 的字节并分别重新验证 Blend，源输入哈希必须不变。Blend 容器和包含其哈希的制作记录不承诺跨次或跨版本逐字节一致。

负例覆盖身份/缺失/绝对/越界路径，以及更新输入哈希后的坏几何、部件顺序、眼窝拓扑和骨架。保存后测试覆盖归一化但错骨的权重、错误形状/动作矩阵、实际 Blend 内被修改的 Shape Key、损坏产物及 addon 输出/报告拒绝。失败不写新的成功 receipt，测试宿主自动清理。

按 [动作复核](tests/performance_review.md) 和 [眼动复核](tests/face_motion_review.md) 采集固定视角下的四动作序列、五口型、左右眨眼以及闭合 0/0.5/1，附程序检查和保存后 receipt：

> 复用几何、权重、形状和动作的程序证据。检查关节拉伸、口型辨识、嘴唇穿插、循环接缝、睫毛连续性和半闭/全闭曲面贴合。分别输出明确合规错误、视觉优化建议和未评估内容，每条引用具体帧和部位。程序数据一致不证明视觉质量；缺少连续帧或接触证据时不宣称动作平滑或闭合无穿插。只输出建议，不修改模型。

插件不调用 AI。源码交付保留工具与 import_sources；运行包排除这些目录。此烘焙能重建当前 performance/眼睑，不证明新 Blend 与历史整个 rig 逐字段等价；不自动替换软组织和头发烘焙配方中的当前 rig，不替代第二角色或完整 P05/P06 验收。
