# 样例材质湿润分区重建

[生成入口](../../.ci_script/tools/generate_material_wetness.py) 根据人工编写的连通部件编号与排除矩形生成 RGBA 数据图，不从颜色猜测材质。依赖 Python、NumPy、Pillow；从宿主根运行：

```powershell
python addons/npr_character_frame/.ci_script/tools/generate_material_wetness.py
python addons/npr_character_frame/.ci_script/tools/test_generate_material_wetness.py -v
```

默认输出宿主 `.temp/material_wetness_bake/` 下的 `material_wetness.png` 和 `material_wetness_generation.json`，不覆盖正式资产。位置参数指定 probe，`--regions`、`--mesh`、`--output` 可显式选择输入和输出；相对参数按工作目录解析，默认路径从脚本发现宿主，不依赖项目根目录名称。源 mesh 仅作配方身份核验，实际栅格化读取 probe 的首个 Body 网格。

当前 [重建配方](../../samples/silver_wolf/import_sources/material_wetness_recipe.json) 使用已经保留的静止 probe。历史配方记录的 probe 哈希为 `1afd0727b5db2dacdec69ecfc8e2001bb024427691a8791036a0a173f23d17b3`，在本次两个项目的 probe 文件查找范围内未找到。新配方使用 `5510eb176b9af55527424312fabba253ddbe2e14012f9c36ef1830500e9b0859`，并保留历史身份；所有人工分组和排除矩形保持不变。正式历史配方及生成记录不改写。两份 probe 不能认定为同一原始捕获，仅已证明新输入能重建现有分区输出。

此工具固定样例 21273 个顶点、108 个焊接连通部件、1024×512 图集，按位置小数 5 位焊接，按顶点首次出现顺序编号。配方必须匹配 probe 和源 mesh 的 SHA256；不同身份即拒绝，即使使用 Python `-O` 也不跳过检查。不要为其它模型仅替换哈希；需重新人工确认部件编号和材质语义，并提供独立验收证据。

通道 R/G/B/A 分别表示吸水织物、涂层/皮革、硬聚合物和金属；多通道共享像素冲突全部清零，未分类区域保持干燥。运行规则见 [湿润材质纹理](wetness.md)。样例基线为通道像素数 `[207791, 32736, 15751, 23292]`，冲突数 0。重建测试核对全部像素、通道统计、改名宿主、异地工作目录与重复生成，并验证身份不符、非法通道/部件/矩形不会产生输出目录。

给外部制作 AI 的提示词：依据部件分离图、材质说明和各通道预览确认分类，不依据染色后的颜色推断材质。复用程序通道统计与输入身份，检查共享 UV、未分类区域及湿润开关多角度截图；输出具体区域和修改建议，区分合规错误与视觉建议，证据不足写未评估。插件不调用 AI，重建像素一致不代替材质语义或新角色验收。
