# 样例视觉数据图重建

[生成器](../../.ci_script/tools/generate_wardrobe_visual_maps.py) 一次重建薄纱、缝线、身体湿润、眼泪光和头发湿润五张 L 模式 1024×512 数据图。依赖 Python、NumPy、Pillow；从宿主根运行：

```powershell
python addons/npr_character_frame/.ci_script/tools/generate_wardrobe_visual_maps.py
python addons/npr_character_frame/.ci_script/tools/test_generate_wardrobe_visual_maps.py -v
```

默认输入为 [历史服装源图](../../samples/silver_wolf/import_sources/visual_maps_garment_v1.png)，SHA256 为 `6c9cad2c6e4882b0ba784593a9ca316a954123e9b4584e5d6dc597397571fc8b`。它与当前 garment_mask 不同，是五图可重建所必需的源输入，不是待删除的临时截图。不要用当前服装生成器输出替换它。历史生成记录保留原路径用于追溯，当前执行入口使用 import_sources 中的源图。

默认输出为宿主 `.temp/visual_maps_bake/`，包含五张 PNG 与 `visual_maps_generation.json`；不会自动覆盖正式运行资产。支持 `--source` 和 `--output`，相对参数按工作目录解析，默认路径从脚本发现宿主，项目根目录可改名。源图必须 RGBA 1024×512；缺失、尺寸或模式错误在输出目录创建前拒绝。记录输入名称/哈希、生成器哈希、软件版本和相对于输出目录的 PNG 路径，不记录绝对地址。

这是样例固定 UV 与艺术参数的重建入口：薄纱来自历史 alpha 与正弦细纹并模糊，缝线来自 alpha 边缘及固定高度窗；身体湿润来自皮肤/布料权重和渐变；眼泪光使用原眼 UV 下部固定高斯区域；头发使用独立方向性标量。全部作为线性 R 通道数据消费，不能用于任意 UV 布局。现有度量空间缝线优先级见 [丝袜规范](hosiery.md)，泪光还受 [湿润纹理](wetness.md) 中的眼球分类和上限约束。

程序回归检查全部五图像素、输入身份、输出哈希、改名宿主、无关工作目录和六文件重复生成一致。外部 AI 可复用这些数据与各通道预览、湿润/薄纱/缝线开关的固定多角度截图，检查区域贴合、错误串色、眼泪光位置和头发双 pass；仅输出有证据的合规错误或视觉建议，无法确认时说明未评估，不自动修改模型。生成一致不代表新角色视觉验收完成。
