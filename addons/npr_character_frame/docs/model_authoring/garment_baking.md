# 样例服装掩码重建

入口为 [generate_wardrobe_mask.py](../../.ci_script/tools/generate_wardrobe_mask.py)。依赖 Python、NumPy 和 Pillow，无需启动 Godot。默认复用插件内的 `soft_tissue_input_probe.json` 与样例 Body `base.png`，不依赖旧项目或历史临时目录。从宿主根目录运行：

```powershell
python addons/npr_character_frame/.ci_script/tools/generate_wardrobe_mask.py
python addons/npr_character_frame/.ci_script/tools/test_generate_wardrobe_mask.py -v
```

默认输出宿主 `.temp/garment_bake/garment_mask.png` 和 `generation.json`；宿主由脚本向上查找 `project.godot`，可改名、移动或从其它工作目录运行脚本。显式位置参数指定 probe，`--source` 指定颜色图，`--output` 指定输出目录；这些相对参数按调用者工作目录解析。输出不会自动覆盖正式资源。

这是 Silver Wolf 样例的重建工具：1024×512 RGB/RGBA 颜色图、原静止坐标空间、按小数 5 位焊接、连通表面最低 Y ≥ 2.32 的头部保护、固定颜色阈值及 5 像素皮肤膨胀规则都属于样例校准。输入必须提供每顶点有限 XYZ/UV 和合法整数三角索引。尺寸/结构检查通过不能证明不同模型的坐标或颜色语义正确。`--legacy-height-cutoff` 仅用于旧逐像素高度规则对照，不作为正式样例结果。

输出为线性数据图：R 冷色布料、G 深色布料、B 浅色饰边、A 皮肤候选；A 需与框架顶点腿部域相交，不表示全身透明度。头部共享 UV 与皮肤保护从 RGB 中排除。正式使用规则见 [丝袜纹理与区域](hosiery.md)。生成记录包括输入哈希、生成器哈希、软件版本、通道计数和保护顶点数，文件名不含开发机绝对地址。

无需 AI 路径：与现有样例逐像素核对，并检查通道计数 `[48416, 150143, 100780, 36024]`、头部保护顶点 `2215`、源输入身份；改名宿主与重复生成测试包含在上述测试入口。对新角色，作者应按框架语义制作掩码并单独校准，不直接套用样例阈值。

外部 AI 提示词：提供原色图、RGBA 各通道预览、固定六角度染色与丝袜展示截图、输入哈希和程序计数。请检查皮肤/头部是否误染、衣领是否被高度截断、共享 UV 是否污染以及丝袜边界是否贴合；只输出带证据的修改建议，区分不合规与视觉建议，证据不足时说明未评估，不修改模型。程序数据供复用，本插件不调用 AI 服务。
