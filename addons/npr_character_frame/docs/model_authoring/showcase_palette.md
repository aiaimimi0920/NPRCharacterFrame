# 展示配色制作规范

`NPRShowcasePaletteProfile` 通过 `NPRCharacterDefinition.showcase_palette_profile` 提供作者配色。基础渲染可省略；完整展示必须显式提供有效资源。参考 [银狼资源](../../samples/silver_wolf/profiles/showcase_palette.tres)，不要把样例颜色当作所有角色的标准。

## 字段与顺序

| 字段 | 规则 |
|---|---|
| `labels` | 非空 `PackedStringArray`；每个标签去除首尾空白后不得为空。数组顺序就是持久预设索引。 |
| `rgb` | `PackedStringArray`，长度恰为标签数量的三倍；每组三项依次为主色、辅色、饰边。每项是六位十六进制 RGB，无 `#`、无 alpha，大小写均可。 |
| `default_index` | 有效槽位索引，默认 0；初始状态、重置及不存在方案文件时使用。不能设为 -1。 |

`validate()` 返回结构/范围错误；`colors_at(index)` 为已验证且有效的索引返回新的三颜色数组。颜色按既有 `Color(hex)` 路径解释，不做额外线性化，不改变原服装 shader 的颜色域。

## 必须保留的存档语义

- 槽位 **0 永远关闭服装染色，使用原材质**。它的三个 RGB 仍用于界面及存档，但不能把此槽位当作普通染色预设。
- **-1 表示用户自定义颜色**，由颜色编辑进入；`select_palette(-1)` 仍会 clamp 到槽位 0，不是自定义选择 API。
- 保存格式仍为 schema 10。用户文件中的三色是权威快照，即使与当前预设颜色不一致也不能重新计算。
- 同一角色身份的预设索引不可随意重排或删除。加载不存在的槽位原子拒绝，不做 clamp、不丢字段。新增迁移方案前，作者应保留旧槽位顺序；标签或 RGB 的更新只影响新选择，不改写既有用户颜色。
- 旧 schema 的其他字段填充值仍是历史迁移合同，与作者工厂配色分开；本资源不覆盖丝袜高度、湿润、表情或动态默认值。

## 实例和创建路径

展示入树前提供完整定义。入树时 `duplicate(true)` 获取私有快照，UI、初始状态、`reset_scheme()` 和入树后的 `configure_save_path()` 都使用同一快照。修改源资源不会热更新当前展示；需要重新实例化来应用新作者输入。各 `wardrobe_state` 再持有自己的深复制，避免状态之间共享可变配置。

内部状态构造签名为 `STATE.new(character_id, palette_profile, height_profile)`；调用方须先验证 profile。没有隐式银狼配置 fallback。直接消费该内部脚本的宿主或测试需要显式传入资源；通常宿主只配置展示的 `character_definition`。

## 验收责任

程序门禁为 `palette_contract_regression.gd` 和 `showcase_palette_profile_regression.gd`，分别覆盖历史样例/存档兼容与替代作者输入、错误配置、状态隔离、三条创建路径、实际 UI 和 GPU 恢复。替代配色仍使用样例几何，不等于第二标准角色验收。

作者应在实际包中检查每个标签与三色预览、槽位 0 原材质、自定义后的预设高亮清除、重新选择、保存重载与重置。提供截图、角色/包身份、输入颜色和保存记录；颜色搭配、可读性及服装分区质量分别记为视觉建议或未评估，不以数字校验替代审美验收。

袜口高度作者配置及旧方案兼容规则见 [展示高度校准](showcase_height.md)。
