extends RefCounted
## Restored developer controls, grouped separately from the wardrobe state controller.

const UI = preload("res://addons/npr_character_frame/showcase/wardrobe_ui.gd")


static func values(host: Control) -> Dictionary:
	var preview: NPRCharacter = host.preview
	var body: ShaderMaterial = preview.materials[0]
	var face: ShaderMaterial = preview.materials[1]
	var hair: ShaderMaterial = preview.materials[2]
	var pupil: Dictionary = host.visual_layers.eye_pupil_contract(host._eye_control_target)
	var state: RefCounted = host.state
	return {
		"方位角": preview.light_yaw,
		"高度角": preview.light_elevation,
		"环境光能量": host._environment.ambient_light_energy,
		"曝光": host._environment.tonemap_exposure,
		"镜头视场角": host.camera.fov,
		"补光": host._shader_float(body, "u_npr_fill_strength", 0.0),
		"阴影强度": preview.character.shadow_strength,
		"轮廓宽度": host._shader_float(preview.outlines[0], "outline_width_pixels", 1.0),
		"发丝高光": host._shader_float(hair, "u_hair_highlight_strength", 0.0),
		"发丝各向异性": _enabled_strength(host, hair, "u_npr_hair_anisotropy"),
		"刘海接触阴影": host._shader_float(face, "u_npr_contact_strength", 0.35),
		"眼神表达":
		(
			float(state.expression == 3)
			if host._debug_eye_expression < 0.0
			else host._debug_eye_expression
		),
		"瞳孔方向 X": pupil.focus.x,
		"瞳孔方向 Y": pupil.focus.y,
		"瞳孔缩放": pupil.scale,
		"面部 SDF 羽化": host._shader_float(face, "u_sdf_feather_radius", 0.06),
		"丝袜湿润近似 / 丝光": state.hosiery_sheen,
		"丝袜织纹": state.hosiery_weave,
		"丝袜粗糙度 / 湿润对照": state.hosiery_roughness,
		"袜边勒肉近似": host._shader_float(body, "u_npr_hosiery_compression_strength", 0.0),
		"通用丝袜效果": _enabled_strength(host, body, "u_npr_stocking"),
		"袜口／缝线强度": state.hosiery_stitch,
		"袜口高度（米）": state.hosiery_height,
		"皮肤湿润": state.wetness_regions[0],
		"丝袜／薄纱湿润": state.wetness_regions[1],
		"头发湿润": state.wetness_regions[2],
		"衣服／装备湿润": state.wetness_regions[3],
		"原眼湿润": state.eye_wetness,
		"符号大小": state.eye_symbol_size,
		"符号线宽": state.eye_symbol_stroke,
		"嘴部符号大小": state.mouth_symbol_size,
		"嘴部符号线宽": state.mouth_symbol_stroke,
		"风场强度": state.wind_strength,
		"软组织压力": state.soft_tissue_pressure,
		"降雨密度": state.droplet_count,
		"雨水演化速度": state.droplet_speed,
		"DropletsEnabled": state.droplets_enabled,
		"TulleGeometryEnabled": state.tulle_geometry_enabled,
		"EyeGeometryEnabled": state.eye_geometry_enabled,
		"HairDynamicEnabled": state.hair_dynamic_enabled,
		"HairCollisionEnabled": state.hair_collision_enabled,
		"AuthoredMaterialsEnabled": state.authored_materials_enabled,
		"ShadowEnabled": preview.character.shadow_strength > 0.0,
		"FillEnabled": preview.fill_light.visible,
		"MatcapEnabled": bool(body.get_shader_parameter("u_npr_matcap_enabled")),
	}


static func _enabled_strength(host: Control, material: ShaderMaterial, prefix: String) -> float:
	if not material.get_shader_parameter(prefix + "_enabled"):
		return 0.0
	return host._shader_float(material, prefix + "_global_strength", 0.0)


static func slider_text(title: String, value: float, default_value: float, step: float) -> String:
	var format := "%." + str(step_decimals(step)) + "f"
	return title + "\n当前 " + format % value + " · 默认 " + format % default_value


static func refresh(host: Control) -> void:
	var current := values(host)
	for node: Node in host._content.find_children("*", "", true, false):
		if node.name == "DropletPreviewPause" and node is Button:
			var water: Dictionary = host.visual_layers.contract()
			node.disabled = not water.enabled
			node.set_pressed_no_signal(water.preview_paused)
			node.text = "继续滑落" if water.preview_paused else "暂停滑落"
		elif node is HSlider and node.has_meta("debug_title"):
			var title: String = node.get_meta("debug_title")
			node.set_value_no_signal(current[title])
			var label: Label = node.get_parent().get_parent().get_child(0)
			label.text = slider_text(title, node.value, host._debug_defaults[title], node.step)
		elif node is CheckButton and current.has(str(node.name)):
			node.set_pressed_no_signal(current[str(node.name)])
			node.tooltip_text = (
				"当前：%s；默认：%s"
				% [
					"开" if node.button_pressed else "关",
					"开" if host._debug_defaults[str(node.name)] else "关"
				]
			)


static func reset_temporary(host: Control) -> void:
	var defaults: Dictionary = host._debug_defaults
	var preview: NPRCharacter = host.preview
	preview.light_yaw = defaults["方位角"]
	preview.light_elevation = defaults["高度角"]
	host._environment.ambient_light_energy = defaults["环境光能量"]
	host._environment.tonemap_exposure = defaults["曝光"]
	# Framing (including FOV) is explicitly preserved by scheme reset.
	preview.set_fill_strength(defaults["补光"])
	preview.set_shadow_strength(defaults["阴影强度"])
	preview.set_outline_width(defaults["轮廓宽度"])
	preview.set_hair_highlight(defaults["发丝高光"])
	preview.set_hair_anisotropy(defaults["发丝各向异性"])
	preview.set_hair_contact(defaults["刘海接触阴影"])
	preview.set_sdf_feather(defaults["面部 SDF 羽化"])
	preview.set_stocking_strength(defaults["通用丝袜效果"])
	preview.set_hosiery_compression(defaults["袜边勒肉近似"])
	preview.set_matcap_strength(0.24 if defaults["MatcapEnabled"] else 0.0)


static func build(host: Control) -> void:
	host._debug_group("显示模式")
	host._paragraph("顶部常驻按钮可切换渲染结果、白模、骨骼／碰撞，切换时保留当前视角。")
	host._paragraph("白模显示不透明双面几何；金色为骨骼，青色为动态链，粉色为已启用的碰撞体，暗色表示碰撞停用。")
	host._paragraph("显示模式用于临时诊断，不写入装扮方案；重置方案返回渲染结果。")
	_lighting(host)
	_materials(host)
	hair_materials(host)
	_eyes(host)
	_hosiery(host)
	_visual_layers(host)
	_rendering(host)


static func _lighting(host: Control) -> void:
	host._debug_group("观察与灯光")
	var preview: NPRCharacter = host.preview
	var environment: Environment = host._environment
	var camera: Camera3D = host.camera
	_slider(
		host,
		"方位角",
		-180.0,
		180.0,
		preview.light_yaw,
		1.0,
		func(value: float): preview.light_yaw = value
	)
	_slider(
		host,
		"高度角",
		5.0,
		85.0,
		preview.light_elevation,
		1.0,
		func(value: float): preview.light_elevation = value
	)
	_slider(
		host,
		"环境光能量",
		0.0,
		2.0,
		environment.ambient_light_energy,
		0.01,
		func(value: float): environment.ambient_light_energy = value
	)
	_slider(
		host,
		"曝光",
		-2.0,
		2.0,
		environment.tonemap_exposure,
		0.01,
		func(value: float): environment.tonemap_exposure = value
	)
	_slider(host, "镜头视场角", 20.0, 60.0, camera.fov, 0.1, func(value: float): camera.fov = value)


static func _materials(host: Control) -> void:
	host._debug_group("光影与轮廓 · 临时预览")
	var preview: NPRCharacter = host.preview
	_slider(
		host,
		"补光",
		0.0,
		1.0,
		0.35 if preview.fill_light.visible else 0.0,
		0.01,
		func(value: float): preview.set_fill_strength(value)
	)
	_slider(
		host, "阴影强度", 0.0, 0.65, 0.28, 0.01, func(value: float): preview.set_shadow_strength(value)
	)
	_slider(host, "轮廓宽度", 0.0, 3.0, 1.0, 0.01, func(value: float): preview.set_outline_width(value))


static func hair_materials(host: Control) -> void:
	host._debug_group("发丝材质 · 临时预览")
	var preview: NPRCharacter = host.preview
	_slider(
		host, "发丝高光", 0.0, 1.0, 0.30, 0.01, func(value: float): preview.set_hair_highlight(value)
	)
	_slider(
		host, "发丝各向异性", 0.0, 1.0, 0.18, 0.01, func(value: float): preview.set_hair_anisotropy(value)
	)
	_slider(
		host, "刘海接触阴影", 0.0, 1.0, 0.35, 0.01, func(value: float): preview.set_hair_contact(value)
	)


static func _eyes(host: Control) -> void:
	host._debug_group("眼部与表情")
	var eye_value := (
		(1.0 if host.state.expression == 3 else 0.0)
		if host._debug_eye_expression < 0.0
		else float(host._debug_eye_expression)
	)
	_slider(host, "眼神表达", 0.0, 1.0, eye_value, 0.01, host._set_debug_eye_expression)
	eye_controls(host)
	_slider(
		host,
		"面部 SDF 羽化",
		0.0,
		0.15,
		0.06,
		0.001,
		func(value: float): host.preview.set_sdf_feather(value)
	)


static func eye_controls(host: Control) -> void:
	var target := OptionButton.new()
	target.name = "EyeControlTarget"
	for label in ["双眼联动", "角色左眼", "角色右眼"]:
		target.add_item(label)
	target.select(host._eye_control_target + 1)
	target.item_selected.connect(host._set_eye_control_target)
	host._content.add_child(target)
	host._paragraph("单眼独立保存；双眼模式显示均值，编辑时同步当前参数。左右沿用模型 EyeL／EyeR 命名。")
	var pupil: Dictionary = host.visual_layers.eye_pupil_contract(host._eye_control_target)
	_slider(
		host,
		"瞳孔方向 X",
		-1.0,
		1.0,
		pupil.focus.x,
		0.01,
		func(value: float): host._set_eye_focus_axis(value, true)
	)
	_slider(
		host,
		"瞳孔方向 Y",
		-1.0,
		1.0,
		pupil.focus.y,
		0.01,
		func(value: float): host._set_eye_focus_axis(value, false)
	)
	_slider(host, "瞳孔缩放", 0.65, 1.35, pupil.scale, 0.01, host._set_pupil_scale)


static func hosiery_material_controls(host: Control) -> void:
	_slider(
		host,
		"丝袜湿润近似 / 丝光",
		0.0,
		0.5,
		host.state.hosiery_sheen,
		0.01,
		host._set_hosiery_material.bind("hosiery_sheen")
	)
	_slider(
		host,
		"丝袜织纹",
		0.0,
		0.1,
		host.state.hosiery_weave,
		0.001,
		host._set_hosiery_material.bind("hosiery_weave")
	)
	_slider(
		host,
		"丝袜粗糙度 / 湿润对照",
		0.18,
		0.6,
		host.state.hosiery_roughness,
		0.01,
		host._set_hosiery_material.bind("hosiery_roughness")
	)


static func _hosiery(host: Control) -> void:
	host._debug_group("丝袜与材质输入")
	hosiery_material_controls(host)
	host._paragraph("丝光、织纹和粗糙度随装扮方案保存；下方材质近似保持临时调试。")
	var body: ShaderMaterial = host.preview.materials[0]
	_slider(
		host,
		"袜边勒肉近似",
		0.0,
		1.0,
		host._shader_float(body, "u_npr_hosiery_compression_strength", 0.0),
		0.01,
		func(value: float): host.preview.set_hosiery_compression(value)
	)
	_slider(
		host,
		"通用丝袜效果",
		0.0,
		1.0,
		0.0,
		0.01,
		func(value: float): host.preview.set_stocking_strength(value)
	)


static func _visual_layers(host: Control) -> void:
	host._debug_group("动态、独立几何与装备")
	var state: RefCounted = host.state
	for region in 4:
		_slider(
			host,
			["皮肤湿润", "丝袜／薄纱湿润", "头发湿润", "衣服／装备湿润"][region],
			0.0,
			1.0,
			state.wetness_regions[region],
			0.01,
			host._set_wetness_region.bind(region)
		)
	_slider(host, "原眼湿润", 0.0, 1.0, state.eye_wetness, 0.01, host._set_eye_wetness)
	host._paragraph("保留模型原眼与高光，仅增强虹膜下部光泽；0 为原效果，1 为最大增强。")
	_slider(host, "风场强度", 0.0, 1.0, state.wind_strength, 0.01, host._set_wind_strength)
	_slider(
		host, "软组织压力", 0.0, 1.0, state.soft_tissue_pressure, 0.01, host._set_soft_tissue_pressure
	)
	host._paragraph("左腿固定绑带的几何压迫，独立于次级动态；动作压迫页可打开近景。性能档停用。")
	_toggle(host, "启用表面雨水", "DropletsEnabled", state.droplets_enabled, host._set_droplets_enabled)
	_slider(host, "降雨密度", 0.0, 12.0, state.droplet_count, 1.0, host._set_droplet_count)
	_slider(host, "雨水演化速度", 0.0, 1.0, state.droplet_speed, 0.01, host._set_droplet_speed)
	_droplet_preview(host)
	_toggle(
		host,
		"独立薄纱／袜口几何",
		"TulleGeometryEnabled",
		state.tulle_geometry_enabled,
		host._set_tulle_geometry_enabled
	)
	for option in [
		["hair_dynamic_enabled", "HairDynamicEnabled", "发束与布带动态"],
		["hair_collision_enabled", "HairCollisionEnabled", "发束与身体碰撞"],
		["authored_materials_enabled", "AuthoredMaterialsEnabled", "装备独立材质"]
	]:
		_toggle(
			host,
			option[2],
			option[1],
			state.get(option[0]),
			host._set_visual_option.bind(option[0])
		)
	host._paragraph("降雨密度为零时停止新雨，已有水痕继续衰减；关闭雨水清空痕迹。发束、布带响应风场和动作。")


static func _droplet_preview(host: Control) -> void:
	var row := HBoxContainer.new()
	host._content.add_child(row)
	var pause := UI.button("暂停滑落", "DropletPreviewPause", func(): pass)
	pause.toggle_mode = true
	pause.toggled.connect(
		func(value: bool):
			host.visual_layers.set_droplet_preview_paused(value)
			refresh(host)
	)
	row.add_child(pause)
	row.add_child(
		UI.button(
			"从头播放", "DropletPreviewRestart", func(): host.visual_layers.restart_droplet_preview()
		)
	)
	host._paragraph("随机降雨在表面流动并留下湿痕。暂停冻结雨水演化，仍贴随动作；从头播放清空水痕并重置随机序列。")
	refresh(host)


static func _rendering(host: Control) -> void:
	host._debug_group("渲染对照")
	var preview: NPRCharacter = host.preview
	_toggle(
		host,
		"启用实时阴影",
		"ShadowEnabled",
		true,
		func(enabled: bool): preview.set_shadow_strength(0.28 if enabled else 0.0)
	)
	_toggle(
		host,
		"启用补光灯",
		"FillEnabled",
		preview.fill_light.visible,
		func(enabled: bool): preview.set_fill_strength(0.35 if enabled else 0.0)
	)
	_toggle(
		host,
		"启用 MatCap 反射",
		"MatcapEnabled",
		false,
		func(enabled: bool): preview.set_matcap_strength(0.24 if enabled else 0.0)
	)
	host._paragraph("灯光、曝光和材质对照用于临时预览；眼部控制与丝袜丝光、织纹、粗糙度随方案保存。")


static func _slider(
	host: Control,
	title: String,
	minimum: float,
	maximum: float,
	_value: float,
	step: float,
	callback: Callable
) -> void:
	host._content.add_child(
		host._debug_slider(title, minimum, maximum, values(host)[title], step, callback)
	)


static func _toggle(
	host: Control, title: String, id: String, _value: bool, callback: Callable
) -> void:
	var toggle := CheckButton.new()
	toggle.name = id
	var default_value: bool = host._debug_defaults[id]
	toggle.text = "%s  · 默认 %s" % [title, "开" if default_value else "关"]
	toggle.button_pressed = values(host)[id]
	toggle.tooltip_text = (
		"当前：%s；默认：%s" % ["开" if toggle.button_pressed else "关", "开" if default_value else "关"]
	)
	toggle.toggled.connect(
		func(next: bool):
			callback.call(next)
			refresh(host)
	)
	host._content.add_child(toggle)
