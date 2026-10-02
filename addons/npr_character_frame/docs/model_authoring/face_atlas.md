# Face atlas 作者校准

`NPRCharacterDefinition.face_atlas_profile` 引用 `NPRFaceAtlasProfile`。基础渲染可留空；绘制眼 accent 调整、圆眼表达、原眼诊断替换、符号眼嘴补肤及完整展示必须提供有效配置。未配置时 shader 默认关闭这些 atlas 校准操作，不回退到银狼。组合 face rig 在缺少配置时明确报错并拒绝 setup。

## 坐标与字段

全部 UV 为 Face 片元采样坐标 `(UV.x, 1 - UV.y)`，不是原网格 UV；与纹理分辨率无关，不要求 512×512 或沿用样例布局。

| 字段 | 作者数据及消费者 |
|---|---|
| `accent_uv_min/max` | 原瞳孔亮色 accent 的闭区间 crop，两维须递增且有限，均在 [0,1]。保留暗轮廓，仅搬运相对 plate 的正亮度残差。 |
| `accent_plate_uv` | 该瞳孔暗底的代表采样点，[0,1]；应选无 accent 的暗底。CPU 提供每组件 pivot，不从此字段推断 pivot。 |
| `skin_sample_v` | 同一 U 下的干净皮肤采样行，有限 [0,1]。补肤覆盖域仍由 symbol-surface 的 actor 坐标决定。 |
| `replacement_eye_a_max_uv` | A 域严格 `U < x && V < y`；没有新增 U/V 下界。 |
| `replacement_eye_b_min_u`、`replacement_eye_b_v_range` | B 域严格 `U > min_u && low_v < V < high_v`；没有新增 U 上界。阈值有限 [0,1]，V 范围递增。 |
| `round_eye_center_uv`、`round_eye_aspect` | 圆眼中心 [0,1] 与有限正双轴比例；距离为 `length((uv - center) * aspect)`。 |
| `round_eye_pupil_radii`、`round_eye_disc_radii` | 暗瞳/亮盘的 smoothstep 内外半径，有限、正、递增、外半径 ≤ 1。 |

replacement 两域取并集，再与 ILM 的 `0.1 < R < 0.8` 交集；不能用 ILM 单独消除嘴唇，也不能把两域改成有限闭矩形。repeat/负 UV 的比较语义保留。

## 与其它角色数据的边界

ILM 通道、SDF UV 规则、CPU 断开组件分类、作者睫毛索引、蒙皮、`CUSTOM0.xy` 瞳孔 pivot 和 `.w` 部件标签均保持已有制作标准。`face_motion_profile` 的 iris/pupil/glint 阈值仍是独立角色数据；湿润泪光上限由 wetness profile 提供。accent 内部 30% 比例、圆眼颜色/混合强度及符号覆盖域算法不是此资源的字段。

银狼 [face_atlas.tres](../../samples/silver_wolf/profiles/face_atlas.tres) 显式提供历史消费者数值，只是可重现样例，不是新角色默认值。样例离线眼睑/口型烘焙器保留其角色专属区域，不把它们包装成任意模型适配器。

## 绑定与验收

角色初始化时只绑定私有 Face 主材质；后创建的原眼睑、符号曲面共享这一材质。`apply_material()` 仅写静态 atlas uniforms，返回 bool；无效数据/null 材质不写入任何字段。definition 未提供 profile 时，角色初始化在私有材质上显式关闭 atlas，即使作者源材质曾启用也不能隐式继承；源材质本身不变。不得覆盖动态 gaze、pupil scale、眼嘴符号、替换开关、湿润或表情权重，也不要写入导入源材质。更换角色校准应构造新的角色实例；单个材质上的绑定不替代完整装配生命周期。

程序校验只能证明数值/范围合规，不能证明采样点真的落在暗底、补肤行干净、替换域完整或圆眼适合角色。提供锁定姿态/相机/光照下的原眼尺度、左右注视、半闭/全闭、圆眼、眼嘴符号、诊断眼及恢复图；每组需无功能/替代参数负对照和源输入身份。见 [程序及外部 AI 复核](tests/face_atlas_review.md) 和 [专项](../../.ci_script/framework/face_atlas_profile_regression.gd)。未实际调用外部 AI 时只记录证据已准备，不声明 AI 验收。
