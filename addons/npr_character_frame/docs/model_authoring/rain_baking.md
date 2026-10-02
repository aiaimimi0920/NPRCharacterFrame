# 样例雨水资产重建

持久入口为 [generate_rain_surface.py](../../.ci_script/tools/generate_rain_surface.py)，使用 Python、NumPy 和 Pillow，不启动 Blender 或 Godot。已验证的库版本为 NumPy 2.5.3、Pillow 12.3.0；输出元数据记录实际版本。现有环境可直接执行，无需为重建另行全局安装工具。

在宿主项目根目录执行：

```powershell
python addons/npr_character_frame/.ci_script/tools/generate_rain_surface.py --output .temp/rain_bake
python addons/npr_character_frame/.ci_script/tools/test_generate_rain_surface.py -v
```

不指定参数时，从脚本位置寻找宿主 `project.godot` 和插件目录，默认输出到宿主 `.temp/rain_bake/`；宿主改名或更换工作目录后仍可使用。显式相对参数按命令的工作目录解析。`--source`、`--material`、`--garment` 可分别指定几何 probe、材质分类图和服装遮罩；`--output` 指定输出目录。输出目录中同名文件会被重新生成，默认不会修改正式样例资源。

默认输入：

- [原始几何 probe](../../samples/silver_wolf/import_sources/soft_tissue_input_probe.json)：保留原捕获文件，SHA256 为 `5510eb176b9af55527424312fabba253ddbe2e14012f9c36ef1830500e9b0859`。生成器读取 `meshes[0]` 的 `positions`、`uv` 与平铺三角 `indices`，对应最终 Body 静止 actor 空间和顶点顺序。文件保留完整原捕获身份，不能把再次导出后的不同顶点顺序当作相同输入。
- `samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/material_wetness.png`：RGBA 1024×512，按最强通道及阈值分类材质。
- 同目录 `garment_mask.png`：RGBA 1024×512，alpha 参与丝袜区域判定；此文件必需，缺失时会报错，不再以 None 进入分类过程。

输出 `rain_surface.json`、`rain_chart.bin`、`rain_vertex_uv.bin` 三份运行输入，及只用于查看的 `rain_chart.png`。JSON 记录三输入的语义角色、文件名和 SHA256、生成器 SHA256、库版本及主要样例配置，不写开发机绝对路径。BIN 格式见 [雨水数据合同](rain.md)。`import_sources/` 由 `.gdignore` 排除 Godot 导入，并由构建脚本排除运行包；`.ci_script/` 同样不进入运行包。交付完整插件源目录时它们仍可用于离线重建。

当前迁移保留样例已审阅算法：1536×1536 atlas、5 位小数几何焊接、6 位 UV 边匹配、固定 shelf 打包/缩放规则、丝袜静止高度区间 0.18–1.48 m，以及原覆盖冲突判断。它是样例重建工具，尚未成为所有标准角色通用的可配置烘焙器；显式文件参数不会自动推断新模型的高度、分类或 UV 校准。

验收依据：重新烘焙的所有运行时 JSON 数值与现存样例相同，两份 BIN 必须逐字节一致；PNG 解码像素必须等于 RGBA8 chart BIN。重复烘焙的四份文件也应逐字节一致。元数据因迁移路径约定、完整输入身份和生成器代码变化而更新，不把这些变化当作渲染数据变化。回归还会在改名宿主中从无关工作目录运行默认入口，并验证缺失遮罩、非法索引和错误图片格式不会写出产物。

给制作 AI 的提示词：先明确最终 Body 的静止坐标、拓扑和 UV，提供与渲染版本对应的几何 probe 及两份线性 RGBA 分类数据。运行此样例工具只能用于复现对应样例；新角色应先定义自己的校准与生成参数，再按照雨水合同生成并接受实际模型回归，不能复制银狼的固定高度与索引。
