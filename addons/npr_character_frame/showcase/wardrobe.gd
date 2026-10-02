extends Control
## Game-facing customization. NPRLab remains an independent technical scene.

const STATE = preload("res://addons/npr_character_frame/showcase/wardrobe_state.gd")
const CONFIGURATION = preload("res://addons/npr_character_frame/showcase/wardrobe_configuration.gd")
const UI = preload("res://addons/npr_character_frame/showcase/wardrobe_ui.gd")
const PALETTE = preload("res://addons/npr_character_frame/showcase/wardrobe_palette.gd")
const BACKDROP = preload("shaders/wardrobe_background.gdshader")
const GARMENT_GEOMETRY = preload(
	"res://addons/npr_character_frame/runtime/hosiery/npr_garment_geometry.gd"
)
const EQUIPMENT = preload("res://addons/npr_character_frame/runtime/equipment/npr_equipment.gd")
const PERFORMANCE = preload("res://addons/npr_character_frame/runtime/animation/npr_performance.gd")
const SPEECH = preload("res://addons/npr_character_frame/showcase/wardrobe_speech.gd")
const VISUAL_LAYERS = preload("res://addons/npr_character_frame/showcase/wardrobe_visual_layers.gd")
const DISPLAY = preload("res://addons/npr_character_frame/showcase/wardrobe_display.gd")
const DEBUG_PANEL = preload("res://addons/npr_character_frame/showcase/wardrobe_debug_panel.gd")
const FEATURES = preload("res://addons/npr_character_frame/showcase/wardrobe_feature_panel.gd")
const FRAMEWORK = preload("res://addons/npr_character_frame/showcase/wardrobe_framework.gd")
const EXPRESSION_WEIGHTS := [
	Vector3.ZERO,
	Vector3(0, 0, 0.72),
	Vector3(0, 0.78, 0.08),
	Vector3(0.12, 0.92, 0.10),
	Vector3(0.52, 0, 0),
]
const SECTIONS := ["服装装备", "丝袜薄纱", "头发布带", "湿润雨水", "灯光渲染", "动作压迫", "面部表情", "参数总览", "框架工具"]

## Configure before entering the tree; a different character requires a new showcase.
@export var character_definition: NPRCharacterDefinition
@export var character_id := ""
@export var character_display_name := ""
@export_file("*.json") var demo_speech_path := ""

var state: STATE
## An explicit host/test override takes precedence over the per-character default.
var save_path := ""
var preview: NPRCharacter
var viewport: SubViewport
var camera: Camera3D
var turntable: Node3D
var section := 0
var dirty := false
var equipment := EQUIPMENT.new()
var performance: PERFORMANCE
var speech: SPEECH
var visual_layers: VISUAL_LAYERS
var display: DISPLAY
var framework: FRAMEWORK
var _active_character_id := ""
var _stage: SubViewportContainer
var _content: VBoxContainer
var _section_title: Label
var _options_scroll: ScrollContainer
var _status: Label
var _navigation: Array[Button] = []
var _palettes: Array[Button] = []
var _colors: Array[ColorPickerButton] = []
var _opacity: HSlider
var _opacity_label: Label
var _dragging := false
var _middle_dragging := false
var _camera_profile: NPRShowcaseCameraProfile
var _palette_profile: NPRShowcasePaletteProfile
var _height_profile: NPRShowcaseHeightProfile
var _target := Vector3.ZERO
var _distance := 0.0
var _camera_pitch := 0.0
var _model_yaw_degrees := 0.0
var _camera_initialized := false
var _environment: Environment
var _background := 0
var _backdrop_material: ShaderMaterial
var _debug_eye_expression := -1.0
var _eye_control_target := -1
var _display_buttons: Array[Button] = []
var _debug_defaults: Dictionary = {}


func _ready() -> void:
	var errors := _configuration_errors()
	if not errors.is_empty():
		push_error("Invalid showcase configuration: " + "; ".join(errors))
		return
	_active_character_id = character_id
	_camera_profile = character_definition.showcase_camera_profile.duplicate(true)
	_palette_profile = character_definition.showcase_palette_profile.duplicate(true)
	_height_profile = character_definition.showcase_height_profile.duplicate(true)
	_target = Vector3(0, _camera_profile.view_heights[0], 0)
	_distance = _camera_profile.view_distances[0]
	state = STATE.new(_active_character_id, _palette_profile, _height_profile)
	if save_path.is_empty():
		save_path = "user://%s_wardrobe.json" % _active_character_id
	get_window().min_size = Vector2i(1152, 720)
	theme = UI.theme()
	if not _build_stage():
		return
	# Capture factory values before loading a saved scheme or building any controls.
	_debug_defaults = DEBUG_PANEL.values(self)
	_load_saved()
	_build_ui()
	_apply_state()
	select_section(0)
	_status.text = "已读取保存方案" if FileAccess.file_exists(save_path) and not dirty else "本地方案 / 未保存"
	if dirty:
		_status.text = "保存文件无效，已使用默认方案"


func _configuration_errors() -> PackedStringArray:
	return CONFIGURATION.validate(
		character_definition, character_id, character_display_name, demo_speech_path
	)


func _build_stage() -> bool:
	var backdrop := ColorRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_material = ShaderMaterial.new()
	_backdrop_material.shader = BACKDROP
	backdrop.material = _backdrop_material
	add_child(backdrop)
	_stage = SubViewportContainer.new()
	_stage.name = "Stage"
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.stretch = true
	_stage.gui_input.connect(_stage_input)
	add_child(_stage)
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_stage.add_child(viewport)
	var studio := Node3D.new()
	viewport.add_child(studio)
	var world := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0, 0, 0, 0)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.66, 0.7, 0.85)
	_environment.ambient_light_energy = 0.6
	world.environment = _environment
	studio.add_child(world)
	camera = Camera3D.new()
	camera.fov = _camera_profile.field_of_view
	camera.near = 0.03
	camera.h_offset = _camera_profile.horizontal_offset
	studio.add_child(camera)
	turntable = Node3D.new()
	studio.add_child(turntable)
	preview = NPRCharacter.new()
	preview.definition = character_definition.duplicate()
	turntable.add_child(preview)
	if not preview.initialized:
		return false
	performance = PERFORMANCE.new()
	speech = SPEECH.new()
	visual_layers = VISUAL_LAYERS.new()
	display = DISPLAY.new()
	framework = FRAMEWORK.new()
	_install_garment_regions()
	equipment.setup(preview)
	preview.set_sdf_feather(0.06)
	preview.set_stocking_strength(0.0)
	preview.materials[2].set_shader_parameter(
		"u_npr_secondary_emission_strengths", PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	)
	var floor_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.06
	cylinder.height = 0.035
	cylinder.radial_segments = 96
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("aec1ce")
	material.roughness = 0.65
	cylinder.material = material
	floor_mesh.mesh = cylinder
	floor_mesh.position.y = -0.025
	studio.add_child(floor_mesh)
	_update_camera()
	add_child(performance)
	performance.setup(preview)
	performance.pose_applied.connect(equipment.sync_pose.bind(performance))
	speech.performance = performance
	add_child(speech)
	preview.add_child(visual_layers)
	visual_layers.setup(preview, performance)
	visual_layers.eye_controls_changed.connect(_store_eye_controls)
	preview.add_child(display)
	display.setup(preview, performance)
	add_child(framework)
	framework.setup(self)
	return true


func _install_garment_regions() -> void:
	var source: MeshInstance3D = preview.meshes[0]
	GARMENT_GEOMETRY.install(
		source,
		preview.global_transform.affine_inverse() * source.global_transform,
		preview.definition.hosiery_profile
	)


func _build_ui() -> void:
	var title := UI.label(character_display_name + "  /  角色装扮", 25)
	title.position = Vector2(32, 27)
	add_child(title)
	var version := UI.label(
		"V%s  ·  角色装扮" % ProjectSettings.get_setting("application/config/version"), 13
	)
	version.position = Vector2(34, 65)
	add_child(version)
	var navigation_scroll := ScrollContainer.new()
	navigation_scroll.name = "Navigation"
	navigation_scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	navigation_scroll.offset_left = 30
	navigation_scroll.offset_right = 202
	navigation_scroll.offset_top = 150
	# Keep the operation hint and bottom controls outside the navigation viewport.
	navigation_scroll.offset_bottom = -120
	navigation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	navigation_scroll.follow_focus = true
	add_child(navigation_scroll)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	navigation_scroll.add_child(nav)
	for index in SECTIONS.size():
		var button := UI.button(
			"%02d    %s" % [index + 1, SECTIONS[index]],
			"Section%d" % index,
			select_section.bind(index)
		)
		button.custom_minimum_size = Vector2(155, 54)
		button.toggle_mode = true
		button.add_theme_stylebox_override("normal", UI.box(Color(0.15, 0.25, 0.36, 0.08)))
		nav.add_child(button)
		_navigation.append(button)
	var panel := PanelContainer.new()
	panel.name = "Options"
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -370
	panel.offset_right = -28
	panel.offset_top = 95
	panel.offset_bottom = -105
	panel.add_theme_stylebox_override("panel", UI.box(Color(0.16, 0.25, 0.36, 0.86), 16))
	add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	_section_title = UI.label("", 25)
	stack.add_child(_section_title)
	var scroll := ScrollContainer.new()
	_options_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	stack.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	scroll.add_child(_content)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(30, -76)
	bottom.add_theme_constant_override("separation", 8)
	add_child(bottom)
	bottom.add_child(UI.button("全身", "FullView", set_view.bind("full")))
	bottom.add_child(UI.button("半身", "HalfView", set_view.bind("half")))
	bottom.add_child(UI.button("面部", "FaceView", set_view.bind("face")))
	bottom.add_child(UI.button("切换背景", "Background", _cycle_background))
	bottom.add_child(UI.button("重置方案", "Reset", reset_scheme))
	var reset_view := UI.button("重置视角", "ResetView", _reset_view)
	reset_view.tooltip_text = "恢复全身正面、默认俯仰、平移、缩放和视场角；保留装扮方案与显示模式。"
	bottom.add_child(reset_view)
	var save := UI.button("✓   保存方案", "Save", save_scheme)
	save.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	save.offset_left = -370
	save.offset_right = -28
	save.offset_top = -76
	save.offset_bottom = -28
	add_child(save)
	_status = UI.label("", 13)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_status.position = Vector2(-368, 60)
	add_child(_status)
	var hint := UI.label("左键旋转／俯仰  ·  中键上下平移  ·  滚轮定点缩放", 13)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(34, -105)
	add_child(hint)
	_build_display_toolbar()


func _build_display_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "DisplayModes"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 240
	panel.offset_right = -394
	panel.offset_top = 20
	panel.offset_bottom = 86
	panel.add_theme_stylebox_override("panel", UI.box(Color(0.16, 0.25, 0.36, 0.72)))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(UI.label("显示模式", 14))
	var group := ButtonGroup.new()
	var labels := ["渲染结果", "白模", "骨骼／碰撞"]
	var ids := ["DisplayRender", "DisplayWhite", "DisplaySkeleton"]
	for index in DISPLAY.MODES.size():
		var mode: String = DISPLAY.MODES[index]
		var button := UI.button(labels[index], ids[index], _set_display_mode.bind(mode))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = mode == display.mode
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "临时显示模式；保留相机状态。重置方案返回渲染结果。"
		row.add_child(button)
		_display_buttons.append(button)


func select_section(index: int) -> void:
	section = index
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_palettes.clear()
	_colors.clear()
	for nav_index in _navigation.size():
		_navigation[nav_index].button_pressed = nav_index == index
	_section_title.text = SECTIONS[index]
	_options_scroll.scroll_vertical = 0
	FEATURES.build(self, index)
	# Section changes must not overwrite the user's camera framing or model turn.
	# Apply the initial preset once, before the user has interacted with the stage.
	if not _camera_initialized:
		set_view("face" if index in [1, 6] else "half" if index in [2, 3] else "full")
		_model_yaw_degrees = 180.0 if index == 3 else 0.0
		turntable.rotation_degrees.y = _model_yaw_degrees
		_camera_initialized = true


func _build_clothing() -> void:
	_content.add_child(UI.label(character_display_name + " · 初始服装", 19))
	_content.add_child(UI.label("配色方案", 15))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for index in _palette_profile.labels.size():
		var button := PALETTE.new()
		button.name = "Palette%d" % index
		button.caption = _palette_profile.labels[index]
		button.tooltip_text = button.caption
		button.palette_colors = _palette_profile.colors_at(index)
		button.pressed.connect(_select_palette.bind(index))
		button.custom_minimum_size = Vector2(88, 72)
		button.toggle_mode = true
		button.button_pressed = index == state.palette
		var style := UI.box(button.palette_colors[0].darkened(0.35))
		button.add_theme_stylebox_override("normal", style)
		grid.add_child(button)
		_palettes.append(button)
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 10)
	_content.add_child(colors)
	for channel in 3:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colors.add_child(column)
		column.add_child(UI.label(["主色", "辅色", "饰边"][channel], 14))
		var picker := ColorPickerButton.new()
		picker.name = "GarmentColor%d" % channel
		picker.custom_minimum_size.y = 35
		picker.edit_alpha = false
		picker.color = state.colors[channel]
		picker.color_changed.connect(_color_changed.bind(channel))
		column.add_child(picker)
		_colors.append(picker)


func _build_hosiery() -> void:
	_content.add_child(UI.button("查看腿部近景", "HosieryView", _show_soft_pressure))
	_opacity_label = UI.label("丝袜透明度  %d%%" % roundi(state.stocking_transparency * 100), 16)
	_content.add_child(_opacity_label)
	_opacity = HSlider.new()
	_opacity.name = "StockingTransparency"
	_opacity.min_value = 0
	_opacity.max_value = 1
	_opacity.step = 0.01
	_opacity.value = state.stocking_transparency
	_opacity.scrollable = false
	_opacity.custom_minimum_size.y = 30
	_opacity.value_changed.connect(_transparency_changed)
	_content.add_child(_opacity)
	_paragraph("0% 不透 · 100% 透出原有腿部\n丝袜覆盖在皮肤之上，身体保持完整。")
	_content.add_child(UI.label("薄纱与缝线", 15))
	_content.add_child(FEATURES.height_slider(self, _height_profile))
	var hosiery_styles := ["丝袜", "薄纱", "袜口／缝线"]
	for index in hosiery_styles.size():
		var style: String = hosiery_styles[index]
		var button := UI.button(style, "HosieryStyle%d" % index, _select_hosiery_style.bind(index))
		button.toggle_mode = true
		button.button_pressed = state.hosiery_style == index
		_content.add_child(button)
	_content.add_child(
		_debug_slider("袜口／缝线强度", 0.0, 1.0, state.hosiery_stitch, 0.01, _set_hosiery_stitch)
	)
	DEBUG_PANEL._hosiery(self)
	FEATURES.wetness(self, 1)
	DEBUG_PANEL._toggle(
		self,
		"独立薄纱／袜口几何",
		"TulleGeometryEnabled",
		state.tulle_geometry_enabled,
		_set_tulle_geometry_enabled
	)


func _build_pressure() -> void:
	_content.add_child(UI.label("绑带局部压迫", 15))
	_content.add_child(UI.button("查看绑带近景", "SoftPressureView", _show_soft_pressure))
	_content.add_child(
		_debug_slider(
			"软组织压力", 0.0, 1.0, state.soft_tissue_pressure, 0.01, _set_soft_tissue_pressure
		)
	)
	_paragraph("左腿固定绑带附近的真实几何压迫；0 为原形，1 为最大。独立于次级动态，性能档停用；不随袜口高度移动。")


func _build_expressions() -> void:
	_content.add_child(UI.label("眼部控制 · 随方案保存", 15))
	_content.add_child(UI.button("查看面部近景", "EyeControlView", set_view.bind("face")))
	FEATURES.symbols(self)
	DEBUG_PANEL._eyes(self)
	FEATURES.eye_wetness(self)
	_content.add_child(UI.button("播放口型示例", "SpeechDemo", _play_speech_demo))
	_content.add_child(UI.button("载入口型与语音", "SpeechImport", _import_speech))
	_content.add_child(UI.button("停止语音", "SpeechStop", speech.stop))
	for index in STATE.EXPRESSIONS.size():
		var button := UI.button(
			STATE.EXPRESSIONS[index], "Expression%d" % index, _select_expression.bind(index)
		)
		button.toggle_mode = true
		button.button_pressed = state.expression == index
		_content.add_child(button)
	var blink := CheckButton.new()
	blink.text = "自动眨眼"
	blink.button_pressed = state.blink
	blink.toggled.connect(
		func(value: bool):
			state.blink = value
			_changed()
	)
	_content.add_child(blink)
	_paragraph("面部形变与材质表情混合；眨眼独立运行。")
	_paragraph("导入 Rhubarb JSON 与同目录 WAV。中文使用 phonetic 识别器。")


func _play_speech_demo() -> void:
	if demo_speech_path.is_empty():
		_status.text = "未配置口型示例，请载入口型与语音"
		return
	_play_speech(demo_speech_path)


func _play_speech(path: String) -> void:
	if speech.load_clip(path):
		speech.play()
		_status.text = "语音播放中 / 发音时间轴驱动口型"
	else:
		_status.text = speech.last_error


func _import_speech() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Rhubarb lip sync"])
	dialog.file_selected.connect(_play_speech)
	dialog.file_selected.connect(func(_path: String): dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.65)


func _build_equipment(slot: int) -> void:
	for enabled in [false, true]:
		var button := UI.button(
			equipment.slot_label(slot) if enabled else "未装备",
			"Equip%d" % int(enabled),
			_equip.bind(slot, enabled)
		)
		button.toggle_mode = true
		button.button_pressed = state.equipment[slot] == enabled
		_content.add_child(button)
	_paragraph("Blender 制作 · 与角色共享深度、阴影和拾取。")


func _equip(slot: int, enabled: bool) -> void:
	state.equipment[slot] = enabled
	_changed()
	_refresh_choices()


func _build_actions() -> void:
	for index in PERFORMANCE.ACTIONS.size():
		var button := UI.button(
			PERFORMANCE.LABELS[index], "Action%d" % index, _select_action.bind(index)
		)
		button.toggle_mode = true
		button.button_pressed = state.action == index
		_content.add_child(button)
	var secondary := CheckButton.new()
	secondary.text = "胸部次级骨骼动态"
	secondary.button_pressed = state.secondary
	secondary.toggled.connect(
		func(value: bool):
			state.secondary = value
			_changed()
	)
	_content.add_child(secondary)
	_paragraph("Blender 动作 · 小幅度阻尼动态。")


func _debug_group(title: String) -> void:
	var rule := HSeparator.new()
	rule.custom_minimum_size.y = 8
	_content.add_child(rule)
	_content.add_child(UI.label(title, 17))


func _paragraph(text: String) -> void:
	var label := UI.label(text, 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("c8d8e6"))
	_content.add_child(label)


func _refresh_choices() -> void:
	FEATURES.refresh_choices(self)


func _select_palette(index: int) -> void:
	state.select_palette(index)
	for channel in mini(3, _colors.size()):
		_colors[channel].color = state.colors[channel]
	for palette in _palettes.size():
		_palettes[palette].button_pressed = index == palette
	_changed()


func _color_changed(color: Color, channel: int) -> void:
	state.colors[channel] = Color(color, 1.0)
	state.palette = -1
	for button in _palettes:
		button.set_pressed_no_signal(false)
	_changed()


func _transparency_changed(value: float) -> void:
	state.stocking_transparency = value
	if is_instance_valid(_opacity_label):
		_opacity_label.text = "丝袜透明度  %d%%" % roundi(value * 100)
	_changed()


func _select_hosiery_style(index: int) -> void:
	state.hosiery_style = index
	if index == 2:
		state.hosiery_stitch = 1.0
	_changed()
	_refresh_choices()


func _set_hosiery_stitch(value: float) -> void:
	state.hosiery_stitch = value
	_changed()


func _set_hosiery_height(value: float) -> void:
	state.hosiery_height = clampf(value, _height_profile.min_height, _height_profile.max_height)
	_changed()


func _select_expression(index: int) -> void:
	state.expression = index
	_changed()
	_refresh_choices()


func _select_action(index: int) -> void:
	state.action = index
	performance.clock = 0.0
	_changed()
	_refresh_choices()


func _set_display_mode(mode: String) -> void:
	if mode != "render":
		framework.diagnostics.set_mode(0)
		framework._sync_controls()
	display.set_mode(mode)
	for index in _display_buttons.size():
		_display_buttons[index].set_pressed_no_signal(DISPLAY.MODES[index] == display.mode)


func _build_debug() -> void:
	DEBUG_PANEL.build(self)


func _debug_slider(
	title: String, minimum: float, maximum: float, value: float, step: float, callback: Callable
) -> VBoxContainer:
	var box := VBoxContainer.new()
	var default_value := float(_debug_defaults[title])
	var label := UI.label(DEBUG_PANEL.slider_text(title, value, default_value, step), 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.name = "Debug" + title
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.set_meta("debug_title", title)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 28
	var reset := Button.new()
	reset.name = "Reset" + title
	reset.text = "恢复默认"
	reset.tooltip_text = "将此项恢复为 %s" % default_value
	reset.pressed.connect(
		func():
			# Linked eyes may have a neutral mean while each eye is non-neutral.
			# A reset is an explicit action, including when Range emits no change.
			slider.set_value_no_signal(default_value)
			callback.call(default_value)
			DEBUG_PANEL.refresh(self)
	)
	slider.value_changed.connect(
		func(next: float):
			callback.call(next)
			DEBUG_PANEL.refresh(self)
	)
	row.add_child(slider)
	row.add_child(reset)
	box.add_child(row)
	return box


func _shader_float(material: ShaderMaterial, parameter: String, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(parameter)
	return fallback if value == null else float(value)


func _set_eye_focus_axis(value: float, horizontal: bool) -> void:
	for side in 2:
		if _eye_control_target != -1 and side != _eye_control_target:
			continue
		var focus: Vector2 = visual_layers.eye_pupil_contract(side).focus
		if horizontal:
			focus.x = value
		else:
			focus.y = value
		visual_layers.set_eye_focus(focus, side)


func _set_eye_control_target(index: int) -> void:
	_eye_control_target = clampi(index - 1, -1, 1)
	DEBUG_PANEL.refresh(self)


func _set_pupil_scale(value: float) -> void:
	visual_layers.set_pupil_scale(value, _eye_control_target)


func _store_eye_controls() -> void:
	var left: Dictionary = visual_layers.eye_pupil_contract(0)
	var right: Dictionary = visual_layers.eye_pupil_contract(1)
	state.eye_left = [left.focus.x, left.focus.y, left.scale]
	state.eye_right = [right.focus.x, right.focus.y, right.scale]
	dirty = true
	if _status != null:
		_status.text = "方案已修改 / 未保存"


func _set_debug_eye_expression(value: float) -> void:
	_debug_eye_expression = value
	performance.eye_emphasis_override = value
	performance.evaluate_expression()


func _set_wetness_region(value: float, index: int) -> void:
	state.wetness_regions[index] = value
	_changed()


func _set_eye_wetness(value: float) -> void:
	state.eye_wetness = value
	_changed()


func _set_droplets_enabled(value: bool) -> void:
	state.droplets_enabled = value
	_changed()


func _set_droplet_count(value: float) -> void:
	state.droplet_count = clampi(roundi(value), 0, 12)
	_changed()


func _set_droplet_speed(value: float) -> void:
	state.droplet_speed = clampf(value, 0.0, 1.0)
	_changed()


func _set_tulle_geometry_enabled(value: bool) -> void:
	state.tulle_geometry_enabled = value
	_changed()


func _set_visual_option(value: bool, key: String) -> void:
	state.set(key, value)
	_changed()


func _set_wind_strength(value: float) -> void:
	state.wind_strength = clampf(value, 0.0, 1.0)
	_changed()


func _set_soft_tissue_pressure(value: float) -> void:
	state.soft_tissue_pressure = clampf(value, 0.0, 1.0)
	dirty = true
	if _status != null:
		_status.text = "方案已修改 / 未保存"
	performance.set_soft_tissue_pressure(state.soft_tissue_pressure)


func _set_hosiery_material(value: float, key: String) -> void:
	var bounds: Dictionary = {
		"hosiery_sheen": Vector2(0.0, 0.5),
		"hosiery_weave": Vector2(0.0, 0.1),
		"hosiery_roughness": Vector2(0.18, 0.6),
	}
	if not bounds.has(key) or not is_finite(value):
		return
	state.set(key, clampf(value, bounds[key].x, bounds[key].y))
	dirty = true
	if _status != null:
		_status.text = "方案已修改 / 未保存"
	_apply_hosiery_material()


func _apply_hosiery_material() -> void:
	var body: ShaderMaterial = preview.materials[0]
	body.set_shader_parameter("u_npr_hosiery_sheen_strength", state.hosiery_sheen)
	body.set_shader_parameter("u_npr_hosiery_weave_strength", state.hosiery_weave)
	body.set_shader_parameter("u_npr_hosiery_roughness", state.hosiery_roughness)


func _changed() -> void:
	dirty = true
	if _status != null:
		_status.text = "方案已修改 / 未保存"
	_apply_state()


func _apply_state() -> void:
	if preview == null or not preview.initialized:
		return
	display.restore_materials()
	performance.set_hair_dynamic_enabled(state.hair_dynamic_enabled)
	performance.set_hair_collision_enabled(state.hair_collision_enabled)
	equipment.set_authored_materials_enabled(state.authored_materials_enabled)
	equipment.set_wetness(state.wetness_regions[3])
	equipment.apply(preview, preview.meshes[0], state.equipment)
	performance.bind_mesh(0, equipment.attachments)
	performance.action = PERFORMANCE.ACTIONS[state.action]
	performance.expression = state.expression
	performance.eye_emphasis_override = _debug_eye_expression
	performance.blink_enabled = state.blink
	performance.secondary_enabled = state.secondary
	performance.wind_strength = state.wind_strength
	performance.soft_tissue_pressure = state.soft_tissue_pressure
	_apply_hosiery_material()
	var body: ShaderMaterial = preview.materials[0]
	body.set_shader_parameter("u_npr_wardrobe_enabled", true)
	body.set_shader_parameter("u_npr_garment_vertex_regions", true)
	body.set_shader_parameter("u_npr_hosiery_metric_seams", true)
	body.set_shader_parameter("u_npr_hosiery_height", state.hosiery_height)
	preview.definition.hosiery_profile.apply_body_material(body)
	var wetness_profile: NPRWetnessProfile = preview.definition.wetness_profile
	assert(wetness_profile != null, "Showcase wetness requires an authored profile")
	wetness_profile.apply_materials(
		body, preview.materials[1], [preview.materials[2], preview.materials[2].next_pass]
	)
	body.set_shader_parameter("u_npr_material_wetness_enabled", true)
	body.set_shader_parameter("u_npr_garment_primary", state.colors[0])
	body.set_shader_parameter("u_npr_garment_secondary", state.colors[1])
	body.set_shader_parameter("u_npr_garment_trim", state.colors[2])
	body.set_shader_parameter("u_npr_garment_mix", 0.0 if state.palette == 0 else 1.0)
	body.set_shader_parameter("u_npr_hosiery_opacity", 1.0 - state.stocking_transparency)
	body.set_shader_parameter("u_npr_tulle_strength", 1.0 if state.hosiery_style == 1 else 0.0)
	body.set_shader_parameter("u_npr_stitch_strength", state.hosiery_stitch)
	body.set_shader_parameter("u_npr_wetness_regions", PackedFloat32Array(state.wetness_regions))
	preview.materials[1].set_shader_parameter("u_npr_eye_wetness", state.eye_wetness)
	for hair: ShaderMaterial in [preview.materials[2], preview.materials[2].next_pass]:
		hair.set_shader_parameter("u_npr_hair_wetness", state.wetness_regions[2])
	visual_layers.apply_state(state)
	display.refresh()
	framework.refresh()


func reset_scheme() -> void:
	framework.reset()
	_set_display_mode("render")
	DEBUG_PANEL.reset_temporary(self)
	_debug_eye_expression = -1.0
	_eye_control_target = -1
	state = STATE.new(_active_character_id, _palette_profile, _height_profile)
	performance.reset_simulation()
	visual_layers.reset()
	_changed()
	select_section(section)


func save_scheme() -> void:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		_status.text = "保存失败：无法写入本地文件"
		return
	# Preserve Vector2-derived eye values across a real JSON save/load round trip.
	file.store_string(JSON.stringify(state.to_data(), "  ", true, true))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(save_path + ".tmp", save_path) != OK:
		_status.text = "保存失败：原方案保留"
		return
	dirty = false
	_status.text = "方案已保存"


func _load_saved() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null or file.get_length() > 16384:
		dirty = true
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	dirty = not state.load_data(parsed)


func configure_save_path(path: String) -> void:
	save_path = path
	if not is_node_ready():
		return
	state = STATE.new(_active_character_id, _palette_profile, _height_profile)
	dirty = false
	_load_saved()
	_apply_state()
	select_section(section)
	if _status != null:
		_status.text = (
			"已读取保存方案" if FileAccess.file_exists(save_path) and not dirty else "本地方案 / 未保存"
		)
		if dirty:
			_status.text = "保存文件无效，已使用默认方案"


func set_view(mode: String) -> void:
	if framework.locked:
		return
	var index: int = NPRShowcaseCameraProfile.VIEW_INDICES[mode]
	_target.x = 0.0
	_target.y = _camera_profile.view_heights[index]
	_distance = _camera_profile.view_distances[index]
	camera.h_offset = (
		_camera_profile.horizontal_offset * _distance / _camera_profile.view_distances[0]
	)
	_update_camera()


func _show_soft_pressure() -> void:
	_target = _camera_profile.pressure_target
	_distance = _camera_profile.pressure_distance
	_camera_pitch = 0.0
	_model_yaw_degrees = 0.0
	turntable.rotation_degrees.y = 0.0
	camera.h_offset = 0.0
	_update_camera()


func _reset_view() -> void:
	_dragging = false
	_middle_dragging = false
	_target = Vector3(0, _camera_profile.view_heights[0], 0)
	_camera_pitch = 0.0
	_model_yaw_degrees = 0.0
	turntable.rotation_degrees.y = 0.0
	camera.fov = float(_debug_defaults["镜头视场角"])
	set_view("full")
	DEBUG_PANEL.refresh(self)


func _update_camera() -> void:
	var pitch := deg_to_rad(_camera_pitch)
	camera.position = (
		_target
		+ Vector3(
			0.0, sin(pitch) * _distance + _camera_profile.vertical_offset, cos(pitch) * _distance
		)
	)
	camera.look_at(_target)


func _stage_input(event: InputEvent) -> void:
	if framework.locked:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_dragging = event.pressed
		elif (
			event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		):
			_zoom_at(event.position, 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
	elif event is InputEventMouseMotion:
		if _middle_dragging:
			_target.y += event.relative.y * 0.0028 * _distance
			_update_camera()
		elif _dragging:
			if not is_zero_approx(event.relative.x):
				# Keep input state in a scalar; reading Node3D's float32 Euler
				# angles back each event accumulates round-trip rotation error.
				_model_yaw_degrees = wrapf(_model_yaw_degrees + event.relative.x * 0.4, -180, 180)
				turntable.rotation_degrees.y = _model_yaw_degrees
			_camera_pitch = clampf(_camera_pitch + event.relative.y * 0.25, -35.0, 35.0)
			_update_camera()


func _zoom_at(stage_point: Vector2, steps: float) -> void:
	var point := stage_point * Vector2(viewport.size) / _stage.size
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var hit: Dictionary = preview.pick_surface(origin, direction)
	if hit.is_empty():
		return
	var focus: Vector3 = hit.position
	_distance = clampf(_distance * pow(0.88, steps), 0.35, 30.0)
	_update_camera()
	for _iteration in 4:
		var error := camera.unproject_position(focus) - point
		if error.length_squared() < 0.04:
			break
		var scale := (
			2.0
			* maxf(camera.global_position.distance_to(focus), 0.25)
			* tan(deg_to_rad(camera.fov) * 0.5)
			/ float(viewport.size.y)
		)
		_target += camera.global_transform.basis.x.normalized() * error.x * scale
		_target -= camera.global_transform.basis.y.normalized() * error.y * scale
		_update_camera()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = false
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_dragging = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false
		_middle_dragging = false


func _cycle_background() -> void:
	_background = (_background + 1) % 3
	_backdrop_material.set_shader_parameter(
		"edge_color", [Color("6d8eab"), Color("292c4d"), Color("95858b")][_background]
	)
	_backdrop_material.set_shader_parameter(
		"center_color", [Color("d1e0e8"), Color("737899"), Color("e2d9d4")][_background]
	)
