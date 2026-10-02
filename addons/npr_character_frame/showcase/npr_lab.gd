extends Control
## Small, inspectable controls. Parameter labels describe their real rendering role.

const PREVIEW = preload("res://addons/npr_character_frame/showcase/npr_character_preview.gd")
const OUTPUT_SHADER = preload(
	"res://addons/npr_character_frame/showcase/shaders/npr_output.gdshader"
)
const ZOOM_RATIO := 0.84
const ZOOM_SURFACE_CLEARANCE := 0.35
const ZOOM_MAX_Z := 8.0
const PARAMETERS := [
	["yaw", "角色朝向", -180.0, 180.0, 1.0, 0.0, "°"],
	["light_yaw", "主光方位", -180.0, 180.0, 1.0, -45.0, "°"],
	["light_elevation", "主光高度", 5.0, 80.0, 1.0, 45.0, "°"],
	["ramp", "冷暖 Ramp", 0.0, 1.0, 0.01, 0.45, ""],
	["sdf", "面部阴影柔和度", 0.0, 0.15, 0.001, 0.06, ""],
	["shadow", "实时阴影强度", 0.0, 0.65, 0.01, 0.28, ""],
	["hair_highlight", "头发高光带", 0.0, 1.0, 0.01, 0.0, ""],
	["hair_emission", "头发自发光（可选）", 0.0, 1.0, 0.01, 0.0, ""],
	["hair_side_fade", "头发侧向透明（可选）", 0.0, 1.0, 0.01, 0.0, ""],
	["hair_contact", "刘海接触阴影", 0.0, 1.0, 0.01, 0.35, ""],
	["fill", "局部补光", 0.0, 1.0, 0.01, 0.0, ""],
	["rim", "深度边缘光", 0.0, 0.5, 0.01, 0.10, ""],
	["outline", "描边宽度", 0.0, 3.0, 0.1, 1.0, " px"],
	["exposure", "画面曝光", 0.7, 1.3, 0.01, 1.0, ""],
	["depth_quality", "深度质量（可选降质）", 0.0, 2.0, 1.0, 2.0, ""],
	["output_split", "输出分段调色（可选）", 0.0, 1.0, 0.01, 0.0, ""],
	["output_quantize", "输出量化（可选降色）", 0.0, 3.0, 1.0, 0.0, ""],
	["expression_shadow", "表情阴影（Face Expression R）", 0.0, 1.0, 0.01, 0.0, ""],
	["expression_highlight", "表情高光（Face Expression G）", 0.0, 1.0, 0.01, 0.0, ""],
	["expression_blush", "表情腮红（Face Expression B）", 0.0, 1.0, 0.01, 0.0, ""],
	["expression_eye", "惊讶圆瞳", 0.0, 1.0, 0.01, 0.0, ""],
]
const EXPRESSION_KEYS := ["expression_shadow", "expression_highlight", "expression_blush"]
const EXPRESSION_PRESET := Vector3.ZERO
const EXPRESSION_PRESETS := {
	"自然": Vector3(0.0, 0.0, 0.0),
	"腮红": Vector3(0.0, 0.0, 0.72),
	"高光": Vector3(0.0, 0.78, 0.08),
	"惊讶": Vector3(0.12, 0.92, 0.10),
	"阴沉": Vector3(0.52, 0.0, 0.0),
}

var preview: Node3D
var sliders: Dictionary[String, HSlider] = {}
var values: Dictionary[String, Label] = {}
var view_mode := "full"
var extended_materials := true
var _dragging := false
var _output_views: Array[SubViewportContainer] = []
var _output_material: ShaderMaterial
var _output_split := 0.0
var _output_quantize := 0

@onready var turntable: Node3D = %Turntable
@onready var camera: Camera3D = %StudioCamera
@onready var environment: Environment = %StudioEnvironment.environment
@onready var auto_rotate: CheckButton = %AutoRotate


func _ready() -> void:
	get_window().min_size = Vector2i(1024, 640)
	_apply_theme()
	preview = Node3D.new()
	preview.set_script(PREVIEW)
	preview.name = "SilverWolfPreview"
	turntable.add_child(preview)
	_register_output_view(%StageView)
	_build_sliders()
	_build_expression_presets()
	%RotateLeft.pressed.connect(_rotate_step.bind(-15.0))
	%RotateRight.pressed.connect(_rotate_step.bind(15.0))
	%Front.pressed.connect(_set_front)
	%Reset.pressed.connect(reset_all)
	%FullView.pressed.connect(set_view.bind("full"))
	%HalfView.pressed.connect(set_view.bind("half"))
	%FaceView.pressed.connect(set_view.bind("face"))
	%StageView.gui_input.connect(_on_stage_input)
	%ExtendedMaterials.toggled.connect(_on_extended_materials_toggled)
	reset_all()
	%RotateRight.grab_focus()


func _process(delta: float) -> void:
	if auto_rotate.button_pressed:
		_set_yaw(wrapf(turntable.rotation_degrees.y + delta * 22.0, -180.0, 180.0))


func _apply_theme() -> void:
	var ui_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", Color("dfe5f2"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("30334d") if state == "normal" else Color("4e456b")
		box.set_corner_radius_all(7)
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 9
		box.content_margin_bottom = 9
		if state == "focus":
			box.bg_color = Color.TRANSPARENT
			box.set_border_width_all(2)
			box.border_color = Color("bda1ff")
		ui_theme.set_stylebox(state, "Button", box)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("3b4055")
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	track.set_corner_radius_all(3)
	ui_theme.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("a48bdb")
	ui_theme.set_stylebox("grabber_area", "HSlider", fill)
	ui_theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	theme = ui_theme


func _build_sliders() -> void:
	for spec in PARAMETERS:
		var key: String = spec[0]
		var row := VBoxContainer.new()
		row.name = key.capitalize() + "Control"
		row.add_theme_constant_override("separation", 6)
		%ParameterRows.add_child(row)
		var heading := HBoxContainer.new()
		row.add_child(heading)
		var label := Label.new()
		label.text = spec[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(label)
		var value := Label.new()
		value.add_theme_color_override("font_color", Color("c6adfa"))
		heading.add_child(value)
		values[key] = value
		var slider := HSlider.new()
		# The wheel navigates this scrolling panel; drag/keyboard edit values.
		slider.scrollable = false
		slider.name = key.capitalize() + "Slider"
		slider.custom_minimum_size.y = 27
		slider.min_value = spec[2]
		slider.max_value = spec[3]
		slider.step = spec[4]
		slider.focus_mode = Control.FOCUS_ALL
		slider.tooltip_text = spec[1]
		row.add_child(slider)
		sliders[key] = slider
		slider.value_changed.connect(_on_parameter.bind(key, spec[6]))
		if key == "yaw":
			slider.drag_started.connect(func(): auto_rotate.button_pressed = false)


func _build_expression_presets() -> void:
	var row := HBoxContainer.new()
	row.name = "ExpressionPresets"
	row.add_theme_constant_override("separation", 6)
	%ParameterRows.add_child(row)
	%ParameterRows.move_child(row, 0)
	for preset_name in EXPRESSION_PRESETS:
		var button := Button.new()
		button.name = "Expression_" + preset_name
		button.text = preset_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "应用" + preset_name + "表情预设"
		button.pressed.connect(_set_expression_preset.bind(preset_name))
		row.add_child(button)


func _set_expression_preset(preset_name: String) -> void:
	_set_expression_sliders(EXPRESSION_PRESETS[preset_name])
	_set_control("expression_eye", 1.0 if preset_name == "惊讶" else 0.0)


func _on_parameter(value: float, key: String, suffix: String) -> void:
	values[key].text = ("%.3f" % value if key == "sdf" else "%.2f" % value) + suffix
	if key == "depth_quality":
		values[key].text = ["性能", "均衡", "完整"][int(value)]
	elif key == "output_quantize":
		values[key].text = ["关闭", "RGB444", "RGB555", "RGB565"][int(value)]
	match key:
		"yaw":
			turntable.rotation_degrees.y = value
			# A close-up must remain outside the newly rotated silhouette as well.
			var bounds: AABB = preview.get_world_bounds()
			camera.position.z = maxf(camera.position.z, bounds.end.z + ZOOM_SURFACE_CLEARANCE)
		"light_yaw":
			preview.light_yaw = value
		"light_elevation":
			preview.light_elevation = value
		"ramp":
			preview.set_ramp_mix(value)
		"sdf":
			preview.set_sdf_feather(value)
		"shadow":
			preview.set_shadow_strength(value)
		"hair_highlight":
			preview.set_hair_highlight(value)
		"hair_emission":
			_apply_hair_emission(value)
		"hair_side_fade":
			preview.set_hair_side_fade(value)
		"expression_eye":
			preview.set_face_eye_expression(value)
		"hair_contact":
			preview.set_hair_contact(value)
		"fill":
			preview.set_fill_strength(value)
		"rim":
			preview.set_rim_strength(value)
		"outline":
			preview.set_outline_width(value)
		"exposure":
			environment.tonemap_exposure = value
		"depth_quality":
			preview.set_depth_quality(int(value))
		"output_split":
			_output_split = value
			_update_output_composition()
		"output_quantize":
			_output_quantize = int(value)
			_update_output_composition()
		"expression_shadow", "expression_highlight", "expression_blush":
			_apply_expression()


func _apply_expression() -> void:
	if not is_instance_valid(preview) or not preview.initialized:
		return
	preview.set_face_expression(
		Vector3(
			sliders.expression_shadow.value,
			sliders.expression_highlight.value,
			sliders.expression_blush.value
		)
	)


## The three expression sliders are the single source of truth; the preset
## toggle only moves them, so the panel always shows the weights in effect.
func _set_expression_sliders(weights: Vector3) -> void:
	for index in range(EXPRESSION_KEYS.size()):
		var key: String = EXPRESSION_KEYS[index]
		sliders[key].set_value_no_signal(weights[index])
		values[key].text = "%.2f" % weights[index]
	_apply_expression()


func _set_control(key: String, value: float) -> void:
	sliders[key].set_value_no_signal(value)
	_on_parameter(value, key, "")


func _apply_hair_emission(strength: float) -> void:
	var strengths: PackedFloat32Array = (
		preview.material_profile.secondary_emission_strengths.duplicate()
	)
	for index in range(strengths.size()):
		strengths[index] *= strength
	for material in [preview.materials[2], preview.materials[2].next_pass]:
		material.set_shader_parameter("u_npr_secondary_emission_strengths", strengths)


func _register_output_view(view: SubViewportContainer) -> bool:
	# The lab presents LDR, display-referred textures into a non-HDR 2D canvas.
	# Never overwrite another presentation material or opt HDR targets in implicitly.
	if not is_instance_valid(view) or not view.is_inside_tree():
		return false
	if view.material != null and view.material != _output_material:
		return false
	if view.get_viewport().use_hdr_2d:
		return false
	var sources := view.get_children().filter(func(child): return child is SubViewport)
	if sources.size() != 1 or sources[0].use_hdr_2d:
		return false
	if view not in _output_views:
		_output_views.append(view)
	_update_output_composition()
	return true


func _update_output_composition() -> void:
	var enabled := _output_split > 0.0 or _output_quantize != 0
	if enabled:
		if _output_material == null:
			_output_material = ShaderMaterial.new()
			_output_material.shader = OUTPUT_SHADER
		_output_material.set_shader_parameter("split_strength", _output_split)
		_output_material.set_shader_parameter("quantization_mode", _output_quantize)
	for view in _output_views:
		if is_instance_valid(view) and (view.material == null or view.material == _output_material):
			# Neutral output uses the exact original presentation path, not an extra pass.
			view.material = _output_material if enabled else null


func reset_all() -> void:
	auto_rotate.button_pressed = false
	%Scroll.scroll_vertical = 0
	for spec in PARAMETERS:
		sliders[spec[0]].set_value_no_signal(spec[5])
		_on_parameter(spec[5], spec[0], spec[6])
	_apply_material_preset(extended_materials)
	set_view("full")


func _on_extended_materials_toggled(enabled: bool) -> void:
	extended_materials = enabled
	_apply_material_preset(enabled)


func _apply_material_preset(enabled: bool) -> void:
	if not is_instance_valid(preview) or not preview.initialized:
		return
	_set_expression_sliders(EXPRESSION_PRESET if enabled else Vector3.ZERO)
	_set_control("expression_eye", 0.0)
	_set_control("hair_emission", 0.0)
	_set_control("hair_side_fade", 0.0)
	preview.set_stocking_strength(0.28 if enabled else 0.0)
	preview.set_matcap_strength(0.24 if enabled else 0.0)
	preview.set_hair_anisotropy(0.18 if enabled else 0.0)
	preview.set_hair_silhouette(0.22 if enabled else 0.0)
	for material in [preview.materials[0]]:
		var strengths: PackedFloat32Array = (
			preview.material_profile.secondary_emission_strengths
			if enabled
			else PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
		)
		material.set_shader_parameter("u_npr_secondary_emission_strengths", strengths)
		material.set_shader_parameter("u_npr_emission_hue_enabled", enabled)
	for index in [0, 2]:
		preview.outlines[index].set_shader_parameter("u_npr_outline_regions_enabled", enabled)
	preview.set_lip_outline_enabled(enabled)


func _set_yaw(value: float) -> void:
	sliders.yaw.set_value_no_signal(value)
	_on_parameter(value, "yaw", "°")


func _rotate_step(step_degrees: float) -> void:
	auto_rotate.button_pressed = false
	_set_yaw(wrapf(sliders.yaw.value + step_degrees, -180.0, 180.0))


func _set_front() -> void:
	auto_rotate.button_pressed = false
	_set_yaw(0.0)


func set_view(mode: String) -> void:
	view_mode = mode
	var target_y := 1.53
	var distance := 5.6
	if mode == "half":
		target_y = 2.18
		distance = 3.0
	elif mode == "face":
		target_y = 2.54
		distance = 2.0
	camera.position = Vector3(0, target_y + 0.06, distance)
	camera.look_at(Vector3(0, target_y, 0))
	for entry in [[%FullView, "full"], [%HalfView, "half"], [%FaceView, "face"]]:
		entry[0].button_pressed = entry[1] == mode


func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if _dragging:
				auto_rotate.button_pressed = false
		elif (
			event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		):
			var steps: float = event.factor if event.factor > 0.0 else 1.0
			_zoom_at(
				event.position, steps if event.button_index == MOUSE_BUTTON_WHEEL_UP else -steps
			)
	elif event is InputEventMouseMotion and _dragging:
		_set_yaw(wrapf(turntable.rotation_degrees.y + event.relative.x * 0.45, -180.0, 180.0))


func _zoom_at(stage_point: Vector2, steps: float) -> void:
	# gui_input already localizes event.position to StageView; do not subtract
	# global_position again. Only account for the child viewport's render size.
	var point: Vector2 = stage_point * Vector2(%Viewport.size) / %StageView.size
	# Camera3D's CPU ray APIs use logical aspect; the renderer uses the rounded
	# internal aspect. Remap around the center to keep the picked detail under
	# the cursor with bilinear scaling, without changing the native-size path.
	var rendered: Vector2i = PREVIEW.DEPTH_PASS.get_render_size(%Viewport, %Viewport.size)
	if rendered != %Viewport.size:
		var center := Vector2(%Viewport.size) * 0.5
		var aspect_ratio: float = (
			float(rendered.x) * %Viewport.size.y / (rendered.y * %Viewport.size.x)
		)
		if camera.keep_aspect == Camera3D.KEEP_WIDTH:
			point.y = center.y + (point.y - center.y) / aspect_ratio
		else:
			point.x = center.x + (point.x - center.x) * aspect_ratio
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var hit: Dictionary = preview.pick_surface(origin, direction)
	if hit.is_empty():
		return
	# Dolly along the cursor ray: the selected detail stays under the pointer.
	# Do not change FOV or zoom on an AABB, UI, plinth or background miss.
	var travel: float = hit.distance * (1.0 - pow(ZOOM_RATIO, steps))
	travel = minf(travel, hit.distance - ZOOM_SURFACE_CLEARANCE)
	var bounds: AABB = preview.get_world_bounds()
	var min_z := bounds.end.z + ZOOM_SURFACE_CLEARANCE
	var end_z := clampf(camera.position.z + direction.z * travel, min_z, ZOOM_MAX_Z)
	travel = (end_z - camera.position.z) / direction.z
	camera.position += direction * travel
	auto_rotate.button_pressed = false
	view_mode = "custom"
	for button in [%FullView, %HalfView, %FaceView]:
		button.button_pressed = false
	%StageView.accept_event()
