extends SceneTree
## Real GUI mouse events + observed state and GPU frames. No direct UI callback calls.

var _lab: Control
var _output := ""
var _failures := 0
var _checks: Array[Dictionary] = []


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	# Keep desktop input in the user's interactive viewer, not this test window.
	# Explicit Viewport.push_input events still traverse the actual GUI handlers.
	root.mouse_passthrough = true
	root.unfocusable = true
	_lab = load("res://addons/npr_character_frame/showcase/npr_lab.tscn").instantiate()
	root.add_child(_lab)
	await _frames(8)
	_check_assembly()
	await _capture("full")
	await _click(_lab.get_node("%HalfView"))
	_check(_lab.view_mode == "half", "Half-view button")
	await _capture("half")
	await _click(_lab.get_node("%FaceView"))
	_check(_lab.view_mode == "face", "Face-view button")
	_check(_lab.get_node("%FaceView").button_pressed, "Face-view selected state")
	_check(is_equal_approx(_lab.camera.position.z, 2.0), "Face-view camera distance")
	await _capture("face")
	await _check_rotation()
	await _check_zoom()
	await _check_sliders()
	await _check_native_lighting()
	await _check_resize()
	await _click(_lab.get_node("%Reset"))
	_check(_lab.view_mode == "full", "Reset restores full view")
	_check(not _lab.auto_rotate.button_pressed, "Reset stops auto rotation")
	for spec in _lab.PARAMETERS:
		_check(is_equal_approx(_lab.sliders[spec[0]].value, spec[5]), "Reset: " + spec[0])
	await _capture("ready")
	var file := FileAccess.open(_output.path_join("lab_checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_checks, "  "))
	_lab.queue_free()
	await process_frame
	print("LAB_CHECKS count=", _checks.size(), " failures=", _failures)
	print("REGRESSION_OK" if _failures == 0 else "REGRESSION_FAILED")
	quit(0 if _failures == 0 else 1)


func _check_assembly() -> void:
	var bounds: AABB = _lab.preview.get_world_bounds()
	print("LAB_BOUNDS ", bounds)
	_check(absf(bounds.position.y) < 0.005, "Character grounded on plinth")
	_check(absf(bounds.size.y - 3.0) < 0.005, "Normalized 3-unit height")
	_check(absf(bounds.get_center().x) < 0.005, "Character centered horizontally")
	for mesh in _lab.preview.meshes:
		_check(mesh.get_active_material(0) is ShaderMaterial, "NPR ShaderMaterial: " + mesh.name)
		_check(mesh.get_node("ShadowCaster").mesh == mesh.mesh, "Shared shadow mesh: " + mesh.name)
		_check(
			mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"Color pass does not duplicate shadow casting"
		)
		var caster: MeshInstance3D = mesh.get_node("ShadowCaster")
		_check(
			(
				caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				and caster.material_override is ShaderMaterial
				and caster.material_override.shader.resource_path.ends_with(
					"npr_shadow_caster.gdshader"
				)
			),
			"Dedicated opaque shadow proxy"
		)
	_check(
		_lab.preview.materials[0].shader.resource_path.ends_with("body_npr.gdshader"),
		"Real body NPR"
	)
	_check(
		_lab.preview.materials[1].shader.resource_path.ends_with("face_base.gdshader"),
		"Real face SDF"
	)
	_check(
		_lab.preview.materials[2].shader.resource_path.ends_with("hair_base_without_eye.gdshader"),
		"Real hair Ramp"
	)
	_check(_lab.preview.outlines.size() == 3, "All three meshes use pixel outlines")
	for index in [0, 2]:
		_check(
			_lab.preview.meshes[index].material_overlay == null,
			"Native Ramp receiver has no coplanar shadow overlay"
		)
	_check(
		_lab.preview.meshes[1].material_overlay == null,
		"Face uses authored SDF, not generic mesh self-shadow"
	)
	for parameter in ["u_emission_threshold", "u_emission_intensity"]:
		_check(
			_lab.preview.materials[1].get_shader_parameter(parameter) == 1.0,
			"Protected face vertex-alpha remap: " + parameter
		)
	_check_framing()
	var character: Node3D = _lab.preview.character
	var contract = (
		load("res://addons/npr_character_frame/.ci_script/framework/neck_seam_contract.gd").new()
	)
	var seam: Dictionary = contract.measure(character)
	_check(seam["pass"], "Actual face/neck seam, not merely overlapping AABBs")
	var head := character.get_node("Head") as Node3D
	var pose := head.transform
	head.transform = Transform3D(Basis.IDENTITY, Vector3(0, 8.5, 0))
	var broken: Dictionary = contract.measure(character)
	_check(
		not broken["pass"] and broken.max_gap > 1.0, "Seam gate rejects previous disconnected pose"
	)
	head.transform = pose
	var report := FileAccess.open(_output.path_join("neck_seam_checks.json"), FileAccess.WRITE)
	report.store_string(
		JSON.stringify({"corrected": seam, "old_pose_negative_control": broken}, "  ")
	)


func _check_rotation() -> void:
	await _click(_lab.get_node("%RotateRight"))
	_check(
		is_equal_approx(_lab.turntable.rotation_degrees.y, 15.0), "Right click rotates 15 degrees"
	)
	await _click(_lab.get_node("%RotateLeft"))
	_check(absf(_lab.turntable.rotation_degrees.y) < 0.01, "Left click reverses rotation")
	await _click(_lab.get_node("%AutoRotate"))
	var before: float = _lab.turntable.rotation_degrees.y
	await create_timer(0.3).timeout
	_check(
		absf(_lab.turntable.rotation_degrees.y - before) > 2.0, "Auto rotation moves continuously"
	)
	await _click(_lab.get_node("%AutoRotate"))
	before = _lab.turntable.rotation_degrees.y
	await create_timer(0.2).timeout
	_check(is_equal_approx(_lab.turntable.rotation_degrees.y, before), "Auto rotation stops")
	await _click(_lab.get_node("%Front"))
	await _drag_stage()
	await _click(_lab.get_node("%Front"))
	await _click(_lab.get_node("%FullView"))
	await _drag_slider("yaw", 0.5, 0.625)
	_check(
		_lab.turntable.rotation_degrees.y > 35 and _lab.turntable.rotation_degrees.y < 55,
		"Yaw slider rotates character"
	)
	await _capture("quarter")
	await _click(_lab.get_node("%Front"))
	for step in range(6):
		await _click(_lab.get_node("%RotateRight"))
	_check(is_equal_approx(_lab.turntable.rotation_degrees.y, 90.0), "Side view reaches 90 degrees")
	await _capture("side")
	_check_framing()
	for step in range(6):
		await _click(_lab.get_node("%RotateRight"))
	_check(absf(_lab.turntable.rotation_degrees.y) > 179.0, "Back view reaches 180 degrees")
	await _capture("back")
	_check_framing()
	await _click(_lab.get_node("%Reset"))
	await _click(_lab.get_node("%FaceView"))


func _check_sliders() -> void:
	await _capture("light_before")
	await _drag_slider("light_yaw", 0.375, 0.78)
	_check(_lab.preview.light_yaw > 75, "Key-light yaw slider")
	await _capture("light_after")
	await _drag_slider("light_elevation", 0.333, 0.7)
	_check(_lab.preview.light_elevation > 50, "Key-light elevation slider")
	await _click(_lab.get_node("%Reset"))
	await _click(_lab.get_node("%FaceView"))
	await _drag_slider("ramp", 0.45, 0.0)
	await _capture("ramp_warm")
	await _drag_slider("ramp", 0.0, 1.0)
	await _capture("ramp_cool")
	await _drag_slider("light_yaw", 0.375, 0.75)
	await _drag_slider("sdf", 0.1, 0.0)
	await _capture("sdf_hard")
	await _drag_slider("sdf", 0.0, 0.8)
	await _capture("sdf_soft")
	var feather: float = _lab.preview.materials[1].get_shader_parameter("u_sdf_feather_radius")
	_check(feather > 0.1, "SDF slider reaches actual shader uniform")
	await _drag_slider("light_yaw", 0.75, 0.375)
	await _drag_slider("shadow", 0.43, 0.0)
	_check(
		not _lab.preview.character.shadow_light.shadow_enabled, "Zero shadow slider disables CSM"
	)
	await _capture("shadow_off")
	await _drag_slider("shadow", 0.0, 0.9)
	_check(_lab.preview.character.shadow_strength > 0.5, "Shadow slider reaches adapter strength")
	for index in [0, 2]:
		_check(
			_lab.preview.meshes[index].get_instance_shader_parameter("u_npr_shadow_strength") > 0.5,
			"Shadow strength reaches each native receiver"
		)
	await _capture("shadow_on")
	await _drag_slider("hair_highlight", 0.3, 0.0)
	await _capture("hair_off")
	await _drag_slider("hair_highlight", 0.0, 0.8)
	for material in [_lab.preview.materials[2], _lab.preview.materials[2].next_pass]:
		_check(
			material.get_shader_parameter("u_hair_highlight_strength") > 0.7,
			"Hair highlight slider reaches both stencil layers"
		)
	await _capture("hair_on")
	await _drag_slider("hair_contact", 0.35, 0.0)
	await _capture("contact_off")
	await _drag_slider("hair_contact", 0.0, 0.9)
	_check(
		_lab.preview.materials[1].get_shader_parameter("u_npr_contact_strength") > 0.8,
		"Contact shadow slider reaches the face depth consumer"
	)
	await _capture("contact_on")
	await _drag_slider("fill", 0.0, 0.8)
	_check(_lab.preview.fill_light.visible, "Fill slider enables its actual OmniLight3D")
	await _capture("fill_on")
	await _drag_slider("fill", 0.8, 0.0)
	_check(not _lab.preview.fill_light.visible, "Zero fill disables its light")
	await _capture("fill_off")
	await _drag_slider("rim", 0.2, 0.0)
	await _capture("rim_off")
	await _drag_slider("rim", 0.0, 0.8)
	for material in [
		_lab.preview.materials[0], _lab.preview.materials[2], _lab.preview.materials[2].next_pass
	]:
		_check(
			material.get_shader_parameter("u_npr_rim_strength") > 0.35,
			"Narrow rim slider reaches body and both hair layers"
		)
	await _capture("rim_on")
	await _drag_slider("outline", 0.333, 0.0)
	await _capture("outline_off")
	await _drag_slider("outline", 0.0, 0.9)
	for material in _lab.preview.outlines:
		_check(
			material.get_shader_parameter("outline_width_pixels") > 2.4,
			"Outline slider applies to each material"
		)
	await _capture("outline_on")
	await _drag_slider("exposure", 0.5, 0.1)
	await _capture("exposure_low")
	await _drag_slider("exposure", 0.1, 0.9)
	_check(_lab.environment.tonemap_exposure > 1.2, "Exposure slider reaches Environment")
	await _capture("exposure_high")


func _check_native_lighting() -> void:
	await _click(_lab.get_node("%Reset"))
	await _click(_lab.get_node("%HalfView"))
	# Exclude conventional PBR stage surfaces from the NPR light-isolation gate.
	var stage_meshes: Array[MeshInstance3D] = []
	for node in _lab.turntable.get_parent().get_children():
		if node is MeshInstance3D and node.visible:
			stage_meshes.append(node)
			node.hide()
	await _capture("native_base")
	var extra := DirectionalLight3D.new()
	_lab.preview.add_child(extra)
	await _capture("native_extra_light")
	extra.free()
	var light: DirectionalLight3D = _lab.preview.character.shadow_light
	light.visible = false
	await _capture("native_no_light")
	light.visible = true
	_lab.preview.set_shadow_strength(0.0)
	for index in [0, 2]:
		_check(
			(
				_lab.preview.meshes[index].get_instance_shader_parameter("u_npr_shadow_strength")
				== 0.0
			),
			"Disabled native shadow uniform is exactly zero"
		)
	await _capture("native_off")
	_lab.preview.set_shadow_strength(0.28)
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.scale = Vector3.ONE * 0.65
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_lab.preview.add_child(blocker)
	blocker.global_position = Vector3(0, 2.1, 0) + light.global_basis.z * 1.4
	await _capture("native_blocker")
	blocker.free()
	for mesh in stage_meshes:
		mesh.show()


func _check_zoom() -> void:
	await _click(_lab.get_node("%Reset"))
	var stage: Control = _lab.get_node("%StageView")
	var before: Transform3D = _lab.camera.transform
	await _wheel(stage.global_position + Vector2(10, 10), true)
	_check(_lab.camera.transform == before, "Background wheel does not move camera")
	await _wheel(_lab.get_node("%Reset").get_global_rect().get_center(), true)
	_check(_lab.camera.transform == before, "Sidebar wheel does not move camera")
	var gap := _find_mesh_gap()
	_check(gap != Vector2.ZERO, "There is a mesh-surface miss inside the model bounds")
	await _wheel(gap, true)
	_check(_lab.camera.transform == before, "AABB hit without a triangle hit does not zoom")
	await _click(_lab.get_node("%HalfView"))
	var point := _project_to_stage(Vector3(0, 1.8, 0))
	var screen := point - stage.global_position
	var hit: Dictionary = _lab.preview.pick_surface(
		_lab.camera.project_ray_origin(screen), _lab.camera.project_ray_normal(screen)
	)
	_check(not hit.is_empty() and hit.mesh == "模型", "Wheel target is an actual body surface")
	before = _lab.camera.transform
	await _wheel(point, true)
	_check(_lab.camera.position.z < before.origin.z - 0.1, "Wheel up physically dollies camera")
	_check(
		_lab.camera.basis == before.basis and _lab.camera.fov == 36.0, "Dolly preserves FOV and aim"
	)
	_check(_lab.view_mode == "custom", "Wheel clears fixed-view selected state")
	if not hit.is_empty():
		_check(
			_project_to_stage(hit.position).distance_to(point) < 0.05, "Detail stays under cursor"
		)
	await _capture("zoom_body")
	await _wheel(point, false)
	_check(_lab.camera.position.distance_to(before.origin) < 0.0001, "Wheel down reverses dolly")
	await _wheel(point, true, 40)
	var bounds: AABB = _lab.preview.get_world_bounds()
	_check(
		absf(_lab.camera.position.z - bounds.end.z - _lab.ZOOM_SURFACE_CLEARANCE) < 0.001,
		"Near limit prevents entering mesh"
	)
	await _capture("zoom_detail")
	await _click(_lab.get_node("%RotateRight"))
	bounds = _lab.preview.get_world_bounds()
	_check(
		_lab.camera.position.z >= bounds.end.z + _lab.ZOOM_SURFACE_CLEARANCE - 0.001,
		"Rotation after close-up preserves camera clearance"
	)
	await _click(_lab.get_node("%Front"))
	point = _project_to_stage(Vector3(0, 1.8, 0))
	await _wheel(point, false, 50)
	_check(is_equal_approx(_lab.camera.position.z, _lab.ZOOM_MAX_Z), "Far dolly limit")
	await _click(_lab.get_node("%FaceView"))
	_check(is_equal_approx(_lab.camera.position.z, 2.0), "Preset restores camera after free zoom")
	await _click(_lab.get_node("%RotateRight"))
	point = _project_to_stage(Vector3(0, 2.6, 0))
	before = _lab.camera.transform
	await _wheel(point, true)
	_check(_lab.camera.position.z < before.origin.z, "Rotated head/hair mesh supports picking")
	await _capture("zoom_face")
	await _click(_lab.get_node("%Reset"))
	await _click(_lab.get_node("%FaceView"))


func _project_to_stage(world: Vector3) -> Vector2:
	var stage: Control = _lab.get_node("%StageView")
	var size: Vector2 = Vector2(_lab.get_node("%Viewport").size)
	return stage.global_position + _lab.camera.unproject_position(world) * stage.size / size


func _find_mesh_gap() -> Vector2:
	var bounds: AABB = _lab.preview.get_world_bounds()
	for y in range(2, 9):
		for x in range(1, 9):
			var world := bounds.position + bounds.size * Vector3(x / 10.0, y / 10.0, 0.5)
			var screen: Vector2 = _lab.camera.unproject_position(world)
			var hit: Dictionary = _lab.preview.pick_surface(
				_lab.camera.project_ray_origin(screen), _lab.camera.project_ray_normal(screen)
			)
			if hit.is_empty():
				return _project_to_stage(world)
	return Vector2.ZERO


func _wheel(point: Vector2, up: bool, count: int = 1) -> void:
	for tick in range(count):
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		root.push_input(motion)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
			event.factor = 1.0
			event.pressed = pressed
			root.push_input(event)
		await _frames(2)


func _check_resize() -> void:
	root.size = Vector2i(1100, 700)
	await _frames(6)
	var panel := _lab.get_node("Margin/Columns/Sidebar") as Control
	_check(panel.get_global_rect().end.x <= 1100, "Sidebar remains in smaller window")
	var scrollbar: VScrollBar = _lab.get_node("%Scroll").get_v_scroll_bar()
	for label in _lab.values.values():
		_check(
			label.get_global_rect().end.x <= scrollbar.get_global_rect().position.x,
			"Value label avoids scrollbar"
		)
	await _drag_slider("exposure", 0.9, 0.7)
	_check(
		_lab.environment.tonemap_exposure > 1.08, "Compact window can scroll to and adjust exposure"
	)
	await _drag_slider("depth_quality", 1.0, 0.0)
	_check(_lab.preview.depth_pass.quality == 0, "Quality slider selects performance tier")
	_check(_lab.values.depth_quality.text == "性能", "Quality label describes actual tier")
	await _drag_slider("depth_quality", 0.0, 0.5)
	_check(_lab.preview.depth_pass.quality == 1, "Quality slider selects balanced tier")
	await _drag_slider("depth_quality", 0.5, 1.0)
	_check(_lab.preview.depth_pass.quality == 2, "Last slider restores full quality")
	await _click(_lab.get_node("%Reset"))
	await _capture("compact")
	_check_framing()
	var previous_z: float = _lab.camera.position.z
	await _wheel(_project_to_stage(Vector3(0, 1.8, 0)), true)
	_check(_lab.camera.position.z < previous_z, "Compact SubViewport wheel coordinates")
	root.size = Vector2i(1440, 900)
	await _frames(6)


func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	# Deliver one complete OS-like click in one frame, without a host cursor event
	# changing GUI hover between the synthetic press and release.
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event)
	await _frames(3)
	print(
		"LAB_CLICK ",
		control.name,
		" view=",
		_lab.view_mode,
		" yaw=",
		_lab.turntable.rotation_degrees.y
	)


func _check_framing() -> void:
	var bounds: AABB = _lab.preview.get_world_bounds()
	var viewport_size: Vector2i = _lab.get_node("%Viewport").size
	var frame := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var inside := true
	for corner in range(8):
		var world := bounds.get_endpoint(corner)
		inside = inside and not _lab.camera.is_position_behind(world)
		inside = inside and frame.has_point(_lab.camera.unproject_position(world))
	_check(inside, "Whole-character bounds fit camera: " + str(viewport_size))


func _mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event)
	await _frames(2)


func _drag_stage() -> void:
	var point: Vector2 = _lab.get_node("%StageView").get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await _mouse_button(point, true)
	for step in range(100):
		motion = InputEventMouseMotion.new()
		point.x += 1.0
		motion.position = point
		motion.global_position = point
		motion.relative = Vector2(1, 0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion)
	await _mouse_button(point, false)
	_check(
		absf(_lab.turntable.rotation_degrees.y - 45.0) < 0.1,
		"Fine mouse dragging rotates without quantization"
	)


func _drag_slider(key: String, start: float, end: float) -> void:
	var slider: HSlider = _lab.sliders[key]
	_lab.get_node("%Scroll").ensure_control_visible(slider)
	await _frames(3)
	var rect := slider.get_global_rect()
	var a := Vector2(lerpf(rect.position.x + 7, rect.end.x - 7, start), rect.get_center().y)
	var b := Vector2(lerpf(rect.position.x + 7, rect.end.x - 7, end), rect.get_center().y)
	var hover := InputEventMouseMotion.new()
	hover.position = a
	hover.global_position = a
	root.push_input(hover)
	await _mouse_button(a, true)
	var previous := a
	for index in range(1, 7):
		var motion := InputEventMouseMotion.new()
		motion.position = a.lerp(b, index / 6.0)
		motion.global_position = motion.position
		motion.relative = motion.position - previous
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion)
		previous = motion.position
		await process_frame
	await _mouse_button(b, false)
	_check(
		(
			absf(slider.value - lerpf(slider.min_value, slider.max_value, end))
			< (slider.max_value - slider.min_value) * 0.06
		),
		"Real drag changes slider: " + key
	)


func _frames(count: int) -> void:
	for frame in range(count):
		await process_frame


func _capture(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(_output.path_join(label + ".png")) == OK, "Screenshot: " + label)
	var stage: Image = _lab.get_node("%Viewport").get_texture().get_image()
	stage.save_png(_output.path_join(label + "_stage.png"))
	print("LAB_CAPTURE ", label)


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		_failures += 1
		push_error("LAB_FAILED: " + label)
