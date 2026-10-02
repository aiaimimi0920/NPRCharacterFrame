# 构建与版本

在宿主项目根目录运行：

```powershell
python ./addons/npr_character_frame/.ci_script/build/build.py --godot $env:NPR_GODOT_PATH
```

默认三位发布版本来自宿主 `project.godot` 的 `config/version`，可用 `--version 1.4.0` 指定。Windows debug 模板默认从给定 Godot 所在目录查找 `godot.windows.template_debug.x86_64.exe`，也可用 `--template` 显式指定。这里只确认文件可用，不检查引擎 patch/版本兼容性。

每次构建开始原子创建 `.export/<三位版本>.<构建号>/`，第四位从 0 开始；失败目录保留，因此失败也占号，不覆盖旧包。三位版本改变后单独从 0 计数。不要删除某个发布版本下全部编号目录后还期望工具记得旧编号。

构建在 `.temp/build/<版本>/project/` 生成独立导出副本，不改宿主导出设置，不复制临时文件、文档、测试或作者输入备份进运行包。明确包括 JSON/BIN 动态数据，执行导入、导出和隔离用户数据的可运行包启动检查。

成功目录包含 `NPRShowcase.exe`、`NPRShowcase.pck`、模板配套 DLL、`build.json`、`source-inputs.json`，并保留模板目录提供的 licenses。`build.json` 的 `status=success` 才是成功包；失败仍保留 `status=failed`、错误摘要和日志相对地址。日志在 `.temp/`，staging 项目在尝试结束后自动清理，已导出包不依赖它们。

当前构建平台为 Windows，输出开发验证包；不声称自动向外发布。对外版本仍用三位，第四位只标识本地构建。最终人工界面验收与框架回归结果另行记录，启动成功不能代替全部测试。

## 头部接触的实际模板回归

在宿主项目根目录运行专用夹具：

```powershell
playgodot-python ./addons/npr_character_frame/.ci_script/framework/run_surface_contact_templates.py --godot $env:NPR_GODOT_PATH
```

默认从提供的编辑器旁查找 Windows debug/release 模板，可用 `--debug-template`、`--release-template` 指定。默认输出为宿主 `.temp/surface_contact_templates/<时间戳>/`；`--output` 可指定新的空目录，不允许覆盖既有证据或写入交付 addon。夹具只复制正式接触脚本与测试资源，不依赖展示场景、样例角色或历史临时文件；临时宿主将测试放在非隐藏 `tests/`，确保场景、脚本及 preload 依赖进入 PCK。正式测试入口仍保存在插件 `.ci_script/framework/`，不进入常规展示包。

工具先通过提供的编辑器导出，再分别启动实际 `SurfaceContact.exe` 与同名 PCK，不使用模板不支持的 `--script` 覆盖。检查模板身份、Debug/Release 模式、两个原点下作者 BVH 创建、实际 Body 重建、旧面替换、命中/未命中及头部变换查询。所有必要测试操作均在 `assert` 外；唯一有意的断言负对照用于证明 Release 会省略表达式。退出码、错误/警告和 JSON 检查必须同时通过，缺少报告不能当作成功。

每次运行保留 `result.json`、两个模式的 `surface_contact.json`、导入/导出/运行日志及源、夹具、引擎和产物哈希；隔离 APPDATA，不修改用户方案。进程有界退出，超时只清理本次启动的进程树。此项是真实模板的小型头部接触回归，不代替完整角色、长序列、人工视觉或完整展示 Release 包验收；常规构建仍是前述 Windows Debug 开发包。
