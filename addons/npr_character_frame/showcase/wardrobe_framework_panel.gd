extends RefCounted

const UI = preload("res://addons/npr_character_frame/showcase/wardrobe_ui.gd")


static func build(host: Control, workbench: Node) -> void:
	host._paragraph("以下为临时框架工具，不写入装扮方案。正式眼嘴曲面由标准模型提供；银狼使用拟合预览。")
	host._content.add_child(UI.button("查看面部近景", "FrameworkFaceView", host.set_view.bind("face")))
	host._debug_group("表情组合与漫画表现")
	workbench.owner_label = UI.label("正在读取通道…", 13)
	host._content.add_child(workbench.owner_label)
	_slider(
		host,
		"持续时间（秒）",
		"EffectDuration",
		0.25,
		8,
		workbench.duration,
		func(value: float): workbench.duration = value
	)
	_toggle(host, "保持悬浮符号，允许旋转观察", "ComicHold", workbench.hold_comics, workbench.set_comic_hold)
	var occlusion := CheckButton.new()
	occlusion.name = "ComicOverlay"
	occlusion.text = "前置漫画叠层（忽略全部场景遮挡）"
	occlusion.button_pressed = workbench.overlay
	occlusion.toggled.connect(func(value: bool): workbench.overlay = value)
	host._content.add_child(occlusion)
	host._paragraph("悬浮符号生成后固定在头部原位置，旋转到背面会隐藏。泪滴与排线贴合眼下、脸颊。")
	var effects := GridContainer.new()
	effects.columns = 2
	host._content.add_child(effects)
	for entry in [
		["汗滴", "sweat"],
		["泪滴", "tear"],
		["怒气", "anger"],
		["强调", "emphasis"],
		["脸部排线", "hatching"],
		["害羞", "shy"],
		["紧张阴影", "tension"],
		["星形眼", "star_eyes"],
		["爱心眼", "heart_eyes"]
	]:
		effects.add_child(
			UI.button(entry[0], "Comic_" + entry[1], workbench.play_comic.bind(entry[1]))
		)
	for entry in [["惊讶", "surprised"], ["短时挤眼 ><", "squeeze"], ["短时波浪嘴", "wave_mouth"]]:
		effects.add_child(
			UI.button(entry[0], "Behavior_" + entry[1], workbench.play_behavior.bind(entry[1]))
		)
	host._content.add_child(
		UI.button("说话 → 惊讶 → 短时 ><", "ExpressionSequence", workbench.play_sequence)
	)
	host._content.add_child(UI.button("取消本页临时表现", "ClearFrameworkEffects", workbench.clear_effects))
	host._debug_group("渲染诊断与固定条件 A/B")
	_picker(
		host,
		"DiagnosticMode",
		workbench.DIAGNOSTICS.LABELS,
		workbench.diagnostics.mode,
		workbench.set_diagnostic
	)
	workbench.diagnostic_label = UI.label(
		workbench.DIAGNOSTICS.LEGENDS[workbench.diagnostics.mode], 13
	)
	workbench.diagnostic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host._content.add_child(workbench.diagnostic_label)
	_toggle(
		host,
		"隐藏头发检查接缝",
		"DiagnosticHideHair",
		workbench.diagnostics.hair_hidden,
		workbench.diagnostics.set_hair_hidden
	)
	_toggle(host, "锁定相机、动作、灯光", "FrameworkLock", workbench.locked, workbench.set_locked)
	host._paragraph("记录 A/B 会自动锁定。锁定期间可调整角色材质；计时与动作暂停。解除锁定后继续播放。")
	var ab := GridContainer.new()
	ab.columns = 2
	host._content.add_child(ab)
	for slot in 2:
		var name := "A" if slot == 0 else "B"
		ab.add_child(UI.button("记录 " + name, "Capture" + name, workbench.capture.bind(slot)))
		ab.add_child(UI.button("查看 " + name, "Show" + name, workbench.show_capture.bind(slot)))
	host._content.add_child(UI.button("返回实时渲染", "ShowLive", workbench.show_capture.bind(-1)))
	host._debug_group("角色风格与光照预设")
	var titles: Array = []
	for preset in workbench.PRESETS:
		titles.append(preset.display_name)
	_picker(
		host,
		"StylePreset",
		titles,
		workbench.preset_index,
		func(index: int): workbench.preset_index = index
	)
	_picker(
		host,
		"StyleScope",
		["角色与灯光", "仅角色参数", "仅灯光参数"],
		workbench.preset_scope,
		func(index: int): workbench.preset_scope = index
	)
	host._content.add_child(UI.button("应用所选预设", "ApplyStylePreset", workbench.apply_preset))
	host._content.add_child(UI.button("恢复初始风格", "RestoreStylePreset", workbench.restore_style))
	_slider(
		host,
		"脸部艺术光权重",
		"FaceArtLightWeight",
		0,
		1,
		host.preview.face_light_weight,
		workbench.set_face_light_weight
	)
	host._paragraph("0 跟随角色场景主光；1 使用预设的世界空间脸部艺术光。场景曝光、环境和后处理由宿主保持。")
	host._debug_group("屏幕尺寸与质量预算")
	_toggle(
		host,
		"按屏幕大小自动调整质量",
		"ScreenQualityEnabled",
		workbench.quality.enabled,
		workbench.set_auto_quality
	)
	workbench.quality_label = UI.label("正在读取预算…", 13)
	workbench.quality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host._content.add_child(workbench.quality_label)
	var views := HBoxContainer.new()
	host._content.add_child(views)
	for index in 3:
		views.add_child(
			UI.button(
				["近景", "中景", "远景"][index],
				"QualityView%d" % index,
				workbench.set_quality_view.bind(index)
			)
		)
	host._paragraph("900 / 350 px 分界；15% 迟滞，稳定 0.35 秒后切换。保留眼部、表情、描边和压力形变。")
	workbench.status_label = UI.label("就绪", 13)
	workbench.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host._content.add_child(workbench.status_label)


static func _picker(
	host: Control, name: String, titles: Array, selected: int, callback: Callable
) -> void:
	var picker := OptionButton.new()
	picker.name = name
	for title in titles:
		picker.add_item(title)
	picker.select(selected)
	picker.item_selected.connect(callback)
	host._content.add_child(picker)


static func _toggle(
	host: Control, title: String, name: String, value: bool, callback: Callable
) -> void:
	var button := CheckButton.new()
	button.name = name
	button.text = title
	button.button_pressed = value
	button.toggled.connect(callback)
	host._content.add_child(button)


static func _slider(
	host: Control,
	title: String,
	name: String,
	low: float,
	high: float,
	value: float,
	callback: Callable
) -> void:
	var label := UI.label("%s：%.2f" % [title, value], 14)
	host._content.add_child(label)
	var slider := HSlider.new()
	slider.name = name
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.scrollable = false
	slider.value = value
	slider.custom_minimum_size.y = 28
	slider.set_meta("value_label", label)
	slider.value_changed.connect(
		func(next: float):
			callback.call(next)
			label.text = "%s：%.2f" % [title, next]
	)
	host._content.add_child(slider)
