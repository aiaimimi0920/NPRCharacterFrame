# 展示镜头共用复核

## 无需 AI

先运行 `check_model.gd` 检查实际 definition 中已提供的镜头配置；基础渲染允许省略，不能据此声称完整展示通过。完整展示还需通过 `wardrobe_configuration.gd` 必需项校验。在真实展示中记录全身、半身、面部、软组织观察、重置及带俯仰切换，附 profile/definition 身份、分辨率、相机参数、动作和截图。对照切换前后方案文件字节，区分视角重置与方案重置。

## 外部 AI / 人工

复用以上证据，不重新计算已有数值。判断头脚裁切、面部可读性、UI 遮挡、压力区域可见性、动作下构图稳定性及重置一致性。不得仅凭合法距离或一张正面图评定全部通过；缺少动作序列、分辨率或相机数据时列入 `not_evaluated`。本工具不调用外部 AI。

输出沿用 `compliance_errors`、`visual_suggestions`、`measurements`、`not_evaluated`。明确数值违规与作者构图建议的区别，不虚构通用审美分数。银狼替代 profile 只验证输入接口，不等于第二标准角色验收。
