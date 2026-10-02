# 样例 Body 法线修正重建

[Godot 采集脚本](../../.ci_script/tools/hosiery_surface_probe.gd) 读取原始角色 Body surface 0：源位置、源法线、UV、归一化 actor 静止位置及索引。它在展示变形和重打包之前采集，不修改 canonical mesh。使用提供的引擎，从宿主根执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File addons/npr_character_frame/.ci_script/framework/run_validation.ps1 -Mode inspect -GodotPath $env:NPR_GODOT_PATH -TestScript res://addons/npr_character_frame/.ci_script/tools/hosiery_surface_probe.gd -OutputPath .temp/body_surface_probe
python addons/npr_character_frame/.ci_script/tools/build_hosiery_surface.py .temp/body_surface_probe/body_surface.json
python addons/npr_character_frame/.ci_script/tools/test_build_hosiery_surface.py --probe .temp/body_surface_probe/body_surface.json -v
```

`NPR_GODOT_PATH` 由调用者指向用户提供的引擎。采集器复用带超时和进程清理的框架运行器，支持其 `<mode> <output>` 参数；直接无参数运行则输出 `.temp/hosiery_surface_probe/`。probe 是可重新采集的临时数据，不永久复制到模型源目录。Python 依赖 NumPy、Pillow，默认输出 `.temp/hosiery_surface_bake/hosiery_surface.json`；可传 `--mesh`、`--garment`、`--output`，相对参数按调用目录解析，默认源路径从脚本定位插件和宿主。

样例算法按 garment alpha、固定 actor 腿部域、源位置小数 4 位焊接与法线夹角阈值筛选修正，不修改硬装备边缘。源 mesh 哈希必须与采集记录相同；11 列数值有限、索引合法、掩码 RGBA 1024×512 才能处理。无候选时失败并要求检查校准，不输出空修正。哈希只证明捕获声明与文件身份一致，不能证明外部修改过的 probe 仍来自该 mesh。

当前重建得到 179 个修正顶点、88 组接缝，`normal_rows`、`seam_groups`、顶点数与原记录完全相同。新鲜 probe SHA256 与历史记录也相同。当前 garment_mask 哈希已不同于旧生成记录，但本次完整结果比较证明当前输入保持全部修正内容；新报告如实记录实际掩码身份，原报告和正式资源不覆盖。回归不会要求旧掩码哈希冒充新输入。

JSON 中的 `stitch` 是历史制作元数据，不是当前运行参数入口；现有袜口/织物参数由 hosiery profile 提供。应用合同见 [丝袜规范](hosiery.md)。工具固定样例空间、区域与阈值，不是任意角色法线自动修复器。

无需 AI 路径比较全部修正行与分组、源身份和重复生成结果，并拒绝身份/坐标/索引错误。外部 AI 提示词：复用这些程序报告及同灯光、固定六角度的法线修正开关截图，检查皮肤接缝是否连续、硬边是否保留、有无过度平滑；输出定位明确的修改建议，区分合规与视觉建议，不直接改模型，证据不足说明未评估。程序重建一致不代替视觉验收。
