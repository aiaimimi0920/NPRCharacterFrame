extends RefCounted
## Feature pages share the same setters/defaults as the complete parameter overview.

const UI = preload("res://addons/npr_character_frame/showcase/wardrobe_ui.gd")
const DEBUG = preload("res://addons/npr_character_frame/showcase/wardrobe_debug_panel.gd")
const STATE = preload("res://addons/npr_character_frame/showcase/wardrobe_state.gd")


static func build(host: Control, page: int) -> void:
	match page:
		0:
			host._paragraph("配色与装备随方案保存。角色发色、肤色和原眼保持固定。")
			host._build_clothing()
			for slot in 4:
				var toggle := CheckButton.new()
				toggle.name = "EquipmentSlot%d" % slot
				toggle.text = host.equipment.slot_label(slot)
				toggle.button_pressed = host.state.equipment[slot]
				toggle.toggled.connect(func(value: bool): host._equip(slot, value))
				host._content.add_child(toggle)
			option(host, "authored_materials_enabled", "AuthoredMaterialsEnabled", "装备独立材质")
			wetness(host, 3)
		1:
			host._paragraph("透明度、袜口、织纹、湿润和独立薄纱集中调节；材质近似标记为临时预览。")
			host._build_hosiery()
		2:
			host._content.add_child(UI.button("查看头部近景", "HairView", host.set_view.bind("face")))
			host._debug_group("动态与风场 · 随方案保存")
			option(host, "hair_dynamic_enabled", "HairDynamicEnabled", "发束与布带动态")
			option(host, "hair_collision_enabled", "HairCollisionEnabled", "发束与身体碰撞")
			DEBUG._slider(host, "风场强度", 0, 1, 0, 0.01, host._set_wind_strength)
			wetness(host, 2)
			DEBUG.hair_materials(host)
		3:
			host._paragraph("湿润和降雨随方案保存；暂停与重播仅用于观察。区域湿润也可在对应功能分类调整。")
			DEBUG._toggle(host, "启用表面雨水", "DropletsEnabled", false, host._set_droplets_enabled)
			DEBUG._slider(host, "降雨密度", 0, 12, 0, 1, host._set_droplet_count)
			DEBUG._slider(host, "雨水演化速度", 0, 1, 0, 0.01, host._set_droplet_speed)
			DEBUG._droplet_preview(host)
			for region in 4:
				wetness(host, region)
		4:
			host._paragraph("灯光、曝光、轮廓和材质对照为临时预览，不写入装扮方案。")
			DEBUG._lighting(host)
			DEBUG._materials(host)
			DEBUG._rendering(host)
		5:
			host._build_actions()
			host._build_pressure()
		6:
			host._build_expressions()
		7:
			host._paragraph("完整参数总览；日常手动测试推荐使用左侧功能分类。")
			host._build_debug()
		8:
			host.framework.build()


static func option(host: Control, key: String, id: String, title: String) -> void:
	DEBUG._toggle(host, title, id, host.state.get(key), host._set_visual_option.bind(key))


static func wetness(host: Control, region: int) -> void:
	DEBUG._slider(
		host,
		["皮肤湿润", "丝袜／薄纱湿润", "头发湿润", "衣服／装备湿润"][region],
		0,
		1,
		0,
		0.01,
		host._set_wetness_region.bind(region)
	)


static func eye_wetness(host: Control) -> void:
	DEBUG._slider(host, "原眼湿润", 0, 1, 0, 0.01, host._set_eye_wetness)


static func refresh_choices(host: Control) -> void:
	# Update existing controls in place: preserve scroll, focus and held input.
	for node in host._content.find_children("*", "Button", true, false):
		var id := str(node.name)
		for prefix in ["HosieryStyle", "Expression", "Action", "EquipmentSlot"]:
			if id.begins_with(prefix) and id.trim_prefix(prefix).is_valid_int():
				var choice := int(id.trim_prefix(prefix))
				var selected: bool = (
					host.state.equipment[choice]
					if prefix == "EquipmentSlot"
					else (
						choice
						== {
							"HosieryStyle": host.state.hosiery_style,
							"Expression": host.state.expression,
							"Action": host.state.action
						}[prefix]
					)
				)
				node.set_pressed_no_signal(selected)
	DEBUG.refresh(host)


static func symbols(host: Control) -> void:
	host._debug_group("2D 符号表情 · 随方案保存")
	for part in ["eye", "mouth"]:
		var eye: bool = part == "eye"
		host._debug_group("眼睛" if eye else "嘴巴")
		var modes := OptionButton.new()
		modes.name = "EyeSymbolMode" if eye else "MouthSymbolMode"
		for title in STATE.EYE_SYMBOLS if eye else STATE.MOUTH_SYMBOLS:
			modes.add_item(title)
		modes.select(host.state.get(part + "_symbol"))
		modes.item_selected.connect(
			func(index: int):
				host.state.set(part + "_symbol", index)
				host._changed()
		)
		host._content.add_child(modes)
		DEBUG._slider(
			host,
			"符号大小" if eye else "嘴部符号大小",
			0.65,
			1.2,
			1.0,
			0.01,
			func(value: float):
				host.state.set(part + "_symbol_size", value)
				host._changed()
		)
		DEBUG._slider(
			host,
			"符号线宽" if eye else "嘴部符号线宽",
			0.05,
			0.18,
			0.10,
			0.01,
			func(value: float):
				host.state.set(part + "_symbol_stroke", value)
				host._changed()
		)
	host._paragraph("眼睛与嘴巴可以独立组合。开启时临时接管对应部位，关闭后恢复原眼、眨眼和口型。")


static func height_slider(host: Control, profile: NPRShowcaseHeightProfile) -> Control:
	return host._debug_slider(
		"袜口高度（米）",
		profile.min_height,
		profile.max_height,
		host.state.hosiery_height,
		profile.step,
		host._set_hosiery_height
	)
