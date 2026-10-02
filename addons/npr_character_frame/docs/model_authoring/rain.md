# 持续表面雨水数据

`NPRCharacterDefinition.rain_profile` 指向 `NPRRainProfile`，包含 `surface_path`、`chart_path`、`vertex_uv_path` 三个现存 `res://` 文件路径。基础渲染允许无配置；持续面雨与完整 showcase 需要配置。样例见 [rain.tres](../../samples/silver_wolf/profiles/rain.tres)。`load_surface()` 每次解析独立 Dictionary，不修改源资产。切换角色需要重新创建雨水实例，运行期间修改 profile 不会自动重建 GPU 场。

## JSON 与二进制合同

`surface_path` 是 schema 1 JSON，提供 Body 原始顶点顺序的独立雨水 atlas；装备追加顶点不属于雨水接收前缀。数据必须与角色静止 actor 空间及运行时 Body 前缀对应，禁止重排顶点后沿用旧文件。

- `size`：两个正整数，范围 [1,16384]，为 atlas 宽高；实际 GPU 支持与资源开销由交付环境验证。
- `vertex_texture_height`：正整数，范围 [1,16384]；顶点纹理宽度固定为 256，这是 Body shader 的寻址合同。
- `positions`：每顶点三个有限数值，以米为单位、actor 静止空间，Y 向上；`uv` 为同数量的二维有限 atlas 坐标，分量在 [0,1]。
- `indices`：每三角形三个有效顶点索引；`neighbors` 为同数量的三元组，对应重心分量降到零时跨越的对边，-1 表示边界，其余为有效三角索引。
- `charts`：每三角形一个 [1,65535] 整数 chart ID；`areas` 为每三角形有限非负面积。
- `kinds`：每三角形一个整数：0 不接收、1 织物、2 涂层/皮革、3 聚合物、4 金属、5 丝袜。丝袜仍按现有高度与透明度状态门控，吸收/流速常量不由本 profile 配置。
- `candidates`：非空有效三角索引数组，采样权重来自 `areas`，总面积必须有限且大于零。

`chart_path` 是无头原始 RGBA8 数据，长度恰为 `size.x * size.y * 4`；chart ID 按 `R + 256 * G` 解码，0 禁止沉积。相邻 chart 及禁用重叠区域需正确烘焙，不能经过 sRGB 转换或图像压缩。

`vertex_uv_path` 是无头原始 RGBAF 数据，每像素四个小端 float32，长度恰为 `256 * vertex_texture_height * 16`。顶点 i 位于 `(i % 256, i / 256)`，RG 存对应 atlas UV；容量至少覆盖所有 positions，尾部填充保留。二进制与 JSON 必须成套生成。

`validate()` 检查路径、schema、有限行数据、数组数量、索引范围、候选总面积与两个二进制长度。它不证明二进制通道内容、邻接互反性、几何面积精度、UV 展开质量或与真实 Body 的拓扑一致；这些仍需实际模型回归。持续面雨运行时与 GPU 场位于 `runtime/rain/`，shader 位于 `shaders/rain/`，动态状态使用显式参数配置。旧隐藏点滴标记/GLB 已删除，不属于交付需求。接入与生命周期见 [雨水运行时](../developer/rain_runtime.md)；生成器迁移与第二角色验收仍未完成。

给制作 AI 的提示词：从最终 Body 静止网格制作独立雨水 atlas，保留顶点顺序、三角邻接和材质分类，导出上述三份一致的数据及来源身份。运行程序检查后，按 [雨水复核](tests/rain_review.md) 提供流动、接缝、暂停与残留水迹证据；不要套用样例角色的坐标和索引。

现有样例已提供 [雨水资产重建入口](rain_baking.md)，可在新项目内离线重建，不依赖旧项目。该工具保留样例校准，完整生成器迁移及新角色通用烘焙配置仍待完成。
