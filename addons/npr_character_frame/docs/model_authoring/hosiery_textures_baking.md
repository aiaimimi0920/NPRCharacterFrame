# 样例丝袜织纹重建

[generate_hosiery_textures.py](../../.ci_script/tools/generate_hosiery_textures.py) 从旧 Blender 丝袜生成器的 `build_textures` 函数提取三图算法，可独立运行，不需要人物 Blend、备份快照或 Blender。依赖 Python、NumPy、Pillow；从宿主根目录执行：

```powershell
python addons/npr_character_frame/.ci_script/tools/generate_hosiery_textures.py
python addons/npr_character_frame/.ci_script/tools/test_generate_hosiery_textures.py -v
```

默认写宿主 `.temp/hosiery_textures_bake/`，输出三张 PNG 和 `hosiery_textures_generation.json`，不会覆盖正式资源。`--output` 支持显式输出目录，相对参数按调用者工作目录解析；默认宿主由脚本位置向上发现 `project.godot`，允许宿主改名和异地工作目录调用。

三图均为 128×128 RGB，平铺内 8 次纱线周期；默认周期 0.0025 m，对应 tile 跨度 0.02 m。算法固定当前样例的双向斜纹、反射率、粗糙度和切线法线幅度。它提供程序化 lookdev 纹理，没有实测纱线或自动审美校准。实际采样由 [hosiery profile](hosiery.md) 的 `textile_period_m` 和 `textile_repeats` 决定；更换内容时需保持三图相位和重复次数一致。

- `hosiery_weave_v1.png`：RGB 反射率先显式 sRGB 编码，PNG 带 sRGB 标记，Godot 按 `source_color` 采样。
- `hosiery_roughness_v1.png`：R 通道绝对粗糙度，RGB 三通道值相同，按线性数据采样。
- `hosiery_normal_v1.png`：RGB 编码切线空间法线，按法线数据导入，保持现有 profile 的法线深度与方向约定。

旧 Blender 的图像像素从底行开始，写 PNG 时上下翻转；byte-backed 图像按最近字节量化，切线法线采用 float32。新入口明确保留这三项，全部解码 RGB 像素与现有图一致。新 PNG 不复刻 Blender 附加的 DPI、Exif、压缩和其它容器信息，文件哈希会不同；生成记录同时提供文件 SHA256 与解码像素 SHA256。旧线性数据图带通用 sRGB/gamma 容器标记，新入口不向粗糙度/法线图写这些标记；实际颜色语义由记录和 Godot 材质/导入约定区分。正式三图及 `.import` 均保留原值。

生成记录包含旧算法出处与脚本哈希、当前生成器哈希、实际 NumPy/Pillow 版本、尺寸、物理周期、重复次数、行序和量化规则，以及相对于输出目录的纹理路径；无开发机绝对地址。算法自包含，不读取旧项目。

程序测试比较三图全部像素、上下方向、16 像素平铺周期、色彩空间标记、输出哈希与 tile 参数；在改名宿主从无关工作目录运行默认入口，重复四文件全部一致。另验证独立脚本的显式输出及输出目标为现存文件时非零失败且原文件不变。测试副本置于 `.temp/` 并自动清理。

给外部制作 AI 的提示词：复用三图通道预览、程序平铺检查和像素身份，在固定灯光下提供近/中/远、多个角度的丝袜截图，确认颜色与法线相位一致、织纹尺度合理、粗糙度变化连续且没有方向颠倒或摩尔纹。分别输出合规错误、视觉优化建议或未评估；不要将程序周期通过视为柔和度或实测纺织标定完成。插件不调用 AI。

此入口仅重建当前运行时使用的纹理。Body 压力 corrective 已有独立 [软组织烘焙](soft_tissue_baking.md)；旧 Blender 的独立丝袜裁切/蒙皮/Blend/GLB 生成链未迁移或复验，未使用的独立 GLB 及派生图已从插件删除。纹理像素一致不证明这些旧几何产物已验收。
