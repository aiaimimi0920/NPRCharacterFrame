# model.contract：外部 AI 复核

与 `.ci_script/model/check_model.gd` 使用同一用例 ID。先运行程序检查并提交 report.json、asset_contract.json 以及对应模型配置给外部 AI。AI 可解释程序错误、检查制作说明与纹理语义是否匹配，但不能覆盖程序的硬性失败或声称读取了未提供的资产。

输出 compliance_errors、visual_suggestions、not_evaluated。每项明确对象/字段、规则、证据、建议；不足以确认的内容归入 not_evaluated。不得修改模型，不要求调用某个特定 AI 服务。
