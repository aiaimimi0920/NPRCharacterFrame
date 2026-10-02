extends "res://addons/npr_character_frame/showcase/npr_lab.gd"
## Optional live two-view demo. The default lab scene and target count are unchanged.

var secondary_view: SubViewport
var secondary_camera: Camera3D
var depth_toggle: CheckButton
var _panel: PanelContainer
var _status: Label


func _ready() -> void:
	super._ready()
	_panel = PanelContainer.new()
	_panel.name = "SecondViewPanel"
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1a1c28")
	box.border_color = Color("a48bdb")
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	column.add_child(_status)
	var container := SubViewportContainer.new()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.tooltip_text = "同一角色的侧面近景；共用下方旋转与右侧调参。滚轮缩放请使用主视图。"
	column.add_child(container)
	secondary_view = SubViewport.new()
	secondary_view.world_3d = preview.get_world_3d()
	secondary_view.msaa_3d = %Viewport.msaa_3d
	secondary_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(secondary_view)
	secondary_camera = Camera3D.new()
	secondary_camera.environment = environment
	secondary_camera.fov = 36.0
	secondary_camera.near = camera.near
	secondary_view.add_child(secondary_camera)
	secondary_camera.position = Vector3(0.9, 2.58, 2.05)
	secondary_camera.look_at(Vector3(0, 2.5, 0))
	_register_output_view(container)
	depth_toggle = CheckButton.new()
	depth_toggle.name = "SecondaryDepthToggle"
	depth_toggle.text = "第二视角深度"
	depth_toggle.tooltip_text = "关闭仅释放第二视角深度；主视角不变，侧面回退普通边缘光。"
	column.add_child(depth_toggle)
	depth_toggle.toggled.connect(_toggle_secondary_depth)
	depth_toggle.button_pressed = true
	%StageView.resized.connect(_place_panel)
	_place_panel.call_deferred()


func reset_all() -> void:
	super.reset_all()
	if is_instance_valid(depth_toggle):
		depth_toggle.button_pressed = true


func _place_panel() -> void:
	var stage: Control = %StageView
	_panel.size = Vector2(stage.size.x * 0.38, stage.size.y * 0.56)
	_panel.position = (
		stage.global_position - global_position + Vector2(stage.size.x - _panel.size.x - 12, 12)
	)


func _toggle_secondary_depth(enabled: bool) -> void:
	if enabled:
		var registered: bool = preview.depth_pass.register_view(secondary_view)
		depth_toggle.set_pressed_no_signal(registered)
		_status.text = "同一角色 · 独立深度" if registered else "注册失败 · 安全回退"
	else:
		preview.depth_pass.unregister_view(secondary_view)
		_status.text = "同一角色 · 普通边缘光"
