extends SceneTree
## Mouse-driven display modes, isolated materials, real rig geometry and restoration.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const BUTTONS := ["DisplayRender", "DisplayWhite", "DisplaySkeleton"]
const CAPTURE_CLOCK = preload("capture_clock.gd")
var _wardrobe: Control
var _output: String
var _checks: Array[Dictionary] = []
var _capture_clock := CAPTURE_CLOCK.new()
var _capture_states: Dictionary = {}


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		quit(1)
		return
	_output = arguments[1]
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1440, 900)
	root.mouse_passthrough = true
	root.unfocusable = true
	_spawn()
	await _frames()
	_wardrobe.select_section(7)
	await _capture("startup_debug")
	_test_debug_controls()
	var available := true
	for id in BUTTONS:
		available = available and _wardrobe.find_child(id, true, false) != null
	_check(available, "All three display controls exist in the real scene")
	if not available:
		_finish()
		return
	for size in [Vector2i(1152, 720), Vector2i(1440, 900)]:
		root.size = size
		await _frames()
		for id in BUTTONS:
			var button: Button = _wardrobe.find_child(id, true, false)
			_check(
				(
					button.is_visible_in_tree()
					and Rect2(Vector2.ZERO, Vector2(size)).encloses(button.get_global_rect())
				),
				"Display control fits %s: %s" % [size, id]
			)
	await _press("Section0")
	var camera_state := _camera_state()
	var saved_state: Dictionary = _wardrobe.state.to_data()
	var dirty: bool = _wardrobe.dirty
	var originals := _materials()
	var rendered := await _capture("render")
	await _press("DisplayWhite")
	_check(_wardrobe.display.mode == "white", "Mouse selects white mode")
	_check(_camera_state() == camera_state, "White mode preserves the camera and turntable")
	_check_white()
	await _capture("white")
	await _press("DisplaySkeleton")
	_check(_wardrobe.display.mode == "skeleton", "Mouse selects skeleton mode")
	var geometry: Dictionary = _wardrobe.display.diagnostic_geometry()
	_check(geometry.bones.size() == 16, "Authored body rig has 16 nonempty bone segments")
	_check(geometry.chains.size() == 7, "All seven authored dynamic chains are displayed")
	_check(geometry.colliders.size() == 3, "All three real collision capsules are displayed")
	_check(
		_wardrobe.display.overlay.mesh.get_surface_count() == 2,
		"Skeleton mode draws solid bones and capsule wire geometry"
	)
	await _capture("skeleton")
	_check(_camera_state() == camera_state, "Skeleton mode preserves the camera and turntable")
	await _press("Section7")
	_check(_wardrobe.display.mode == "skeleton", "Category switch keeps the display mode")
	_check(_camera_state() == camera_state, "Category switch keeps the camera")
	await _press("Section0")
	await _press("DisplayRender")
	var restored := await _capture("render_restored")
	_check(
		rendered.get_data() == restored.get_data(), "Render pixels restore exactly after all modes"
	)
	_check(_materials() == originals, "Every original override and overlay is restored")
	_check(_wardrobe.state.to_data() == saved_state, "Display switches do not alter saved settings")
	_check(_wardrobe.dirty == dirty, "Display switches do not mark the scheme dirty")
	await _test_optional_layers()
	await _test_camera_interactions()
	await _test_pose_and_restart()
	_finish()


func _spawn() -> void:
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("scheme.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	_wardrobe.performance.blink_weight = 0.0
	_wardrobe.performance.apply_pose(0.0)


func _test_optional_layers() -> void:
	await _press("DisplayWhite")
	await _press("Section7")
	for id in ["TulleGeometryEnabled", "AuthoredMaterialsEnabled"]:
		await _press(id)
	await _press("Section0")
	await _press("EquipmentSlot1")
	_check(_wardrobe.state.equipment[1], "Mouse equips the current clothing-page slot")
	_check(_wardrobe.state.tulle_geometry_enabled, "Mouse enables the fitted hosiery layer")
	_check(_wardrobe.state.authored_materials_enabled, "Mouse enables authored equipment materials")
	_check_white()
	_check(
		_wardrobe.display.overridden_count() > 3,
		"White mode includes enabled fitted hosiery and equipment"
	)
	await _press("Section1")
	var slider: HSlider = _wardrobe.find_child("StockingTransparency", true, false)
	_check(slider != null, "Hosiery page exposes the transparency slider")
	if slider == null:
		return
	slider.value = 0.6
	await _frames()
	_check(
		is_equal_approx(_wardrobe.state.stocking_transparency, 0.6),
		"Transparency slider signal updates the saved preference in white mode"
	)
	var tulle: Node3D = _wardrobe.visual_layers.tulle_layer
	var material: ShaderMaterial = tulle.material
	_check(
		is_equal_approx(material.get_shader_parameter("opacity"), 0.4),
		"White-mode edits reach the retained fitted shader opacity"
	)
	_check(
		tulle.mesh_instance.material_override == _wardrobe.display.white_material,
		"Fitted shell retains the opaque white override while its shader is edited"
	)
	_check_white()
	await _capture("white_optional_layers")
	await _press("DisplayRender")
	_check(_wardrobe.display.overridden_count() == 0, "Returning to render releases all overrides")
	_check(
		tulle.mesh_instance.material_override == material,
		"Render mode restores the same fitted shader instance"
	)
	_check(
		is_equal_approx(material.get_shader_parameter("opacity"), 0.4),
		"Hosiery transparency edited in white mode survives material restoration"
	)
	await _capture("render_optional_layers")
	await _press("Reset")
	await _frames()


func _test_camera_interactions() -> void:
	await _drag(MOUSE_BUTTON_LEFT, Vector2(580, 450), Vector2(635, 420))
	await _drag(MOUSE_BUTTON_MIDDLE, Vector2(630, 450), Vector2(630, 470))
	var snapshot := _camera_state()
	_check(absf(_wardrobe._camera_pitch) > 0.0, "Vertical drag changes camera pitch")
	for id in ["DisplaySkeleton", "DisplayWhite", "DisplayRender"]:
		await _press(id)
		_check(_camera_state() == snapshot, "Adjusted camera survives " + id)
	for id in ["Section1", "Section6", "Section0"]:
		await _press(id)
		_check(_camera_state() == snapshot, "Adjusted camera survives " + id)


func _test_pose_and_restart() -> void:
	await _press("DisplaySkeleton")
	var before: Dictionary = _wardrobe.display.diagnostic_geometry()
	_wardrobe.state.action = 1
	_wardrobe.state.hair_dynamic_enabled = true
	_wardrobe.state.hair_collision_enabled = true
	_wardrobe.state.wind_strength = 1.0
	_wardrobe._apply_state()
	_wardrobe.performance.clock = 0.8
	_wardrobe.performance.apply_pose(0.8, 1.0 / 60.0)
	await _frames()
	var after: Dictionary = _wardrobe.display.diagnostic_geometry()
	_check(before.bones != after.bones, "Diagnostic bones follow the actual animated pose")
	_check(before.chains != after.chains, "Dynamic chain diagnostics follow the simulation")
	await _capture("skeleton_animated")
	var camera_state := _camera_state()
	await _press("Reset")
	_check(_wardrobe.display.mode == "render", "Reset returns to normal rendering")
	_check(_camera_state() == camera_state, "Resetting the scheme preserves camera framing")
	await _press("DisplayWhite")
	await _press("Save")
	var saved_settings: Dictionary = _wardrobe.state.to_data()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_wardrobe.save_path))
	_check(not saved.has("display_mode"), "Diagnostic mode is transient and excluded from saves")
	_wardrobe.free()
	await _frames()
	_spawn()
	await _frames()
	_check(_wardrobe.display.mode == "render", "Recreated scene starts in normal rendering")
	_check(
		_wardrobe.state.to_data() == saved_settings, "Scene recreation restores the saved scheme"
	)
	await _capture("recreated")


func _test_debug_controls() -> void:
	var sliders := _wardrobe.find_children("*", "HSlider", true, false)
	_check(sliders.size() >= 10, "Debug panel exposes grouped slider controls")
	var marked := 0
	var reset_buttons := 0
	for slider: HSlider in sliders:
		var row := slider.get_parent()
		var box := row.get_parent()
		var label := box.get_child(0) if box.get_child_count() > 0 else null
		if label is Label and str(label.text).contains("当前") and str(label.text).contains("默认"):
			marked += 1
		for sibling in row.get_children():
			if sibling is Button and sibling.text == "恢复默认":
				reset_buttons += 1
	_check(marked == sliders.size(), "Debug sliders show current and default values")
	_check(reset_buttons == sliders.size(), "Every debug slider exposes a default reset")
	var toggles: Array[Node] = _wardrobe._content.find_children("*", "CheckButton", true, false)
	_check(toggles.size() >= 5, "Debug panel exposes grouped toggle controls")
	var toggle_defaults := 0
	for toggle: CheckButton in toggles:
		if str(toggle.text).contains("默认") and str(toggle.tooltip_text).contains("默认"):
			toggle_defaults += 1
	_check(toggle_defaults == toggles.size(), "Every debug toggle shows default state metadata")


func _check_white() -> void:
	_check(_wardrobe.display.overridden_count() >= 3, "White mode covers the three primary meshes")
	for row: Dictionary in _wardrobe.display.material_snapshots:
		var geometry: GeometryInstance3D = row.geometry
		_check(
			(
				geometry.material_override == _wardrobe.display.white_material
				and geometry.material_overlay == null
				and _wardrobe.display.white_material.albedo_color.a == 1.0
			),
			"White material stays opaque and isolated: " + str(geometry.get_path())
		)


func _materials() -> Array:
	var result: Array = []
	for node: Node in _wardrobe.preview.find_children("*", "GeometryInstance3D", true, false):
		result.append([node, node.material_override, node.material_overlay])
	return result


func _camera_state() -> Array:
	return [
		_wardrobe.camera.transform,
		_wardrobe.camera.fov,
		_wardrobe.camera.h_offset,
		_wardrobe._target,
		_wardrobe._distance,
		_wardrobe._camera_pitch,
		_wardrobe.turntable.transform
	]


func _press(id: String) -> void:
	var button: BaseButton = _wardrobe.find_child(id, true, false)
	_check(button != null, "Input target exists: " + id)
	if button == null:
		return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await _frames()
			break
		parent = parent.get_parent()
	var point := button.get_global_rect().get_center()
	_mouse(MOUSE_BUTTON_LEFT, point, true)
	_mouse(MOUSE_BUTTON_LEFT, point, false)
	await _frames()


func _drag(button: MouseButton, start: Vector2, end: Vector2) -> void:
	_mouse(button, start, true)
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.relative = end - start
	motion.button_mask = (
		MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
	)
	root.push_input(motion)
	_mouse(button, end, false)
	await _frames()


func _mouse(button: MouseButton, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = pressed
	root.push_input(event)


func _frames() -> void:
	for frame in 4:
		await process_frame
		_capture_clock.advance()
	await RenderingServer.frame_post_draw


func _capture(label: String) -> Image:
	await _frames()
	_capture_states[label] = _capture_clock.snapshot()
	root.get_texture().get_image().save_png(_output.path_join(label + "_ui.png"))
	var result: Image = _wardrobe.viewport.get_texture().get_image()
	result.save_png(_output.path_join(label + ".png"))
	return result


func _check(passed: bool, label: String) -> void:
	_checks.append({"name": label, "pass": passed})
	if not passed:
		print("FAIL: ", label)


func _finish() -> void:
	var failures := _checks.filter(func(row: Dictionary): return not row["pass"])
	FileAccess.open(_output.path_join("display_modes.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"checks": _checks,
				"engine": Engine.get_version_info(),
				"capture_states": _capture_states
			},
			"  "
		)
	)
	_wardrobe.free()
	print("DISPLAY_MODE_CHECKS=", _checks.size(), " FAILURES=", failures.size())
	print("REGRESSION_OK" if failures.is_empty() else "REGRESSION_FAILED")
	quit(0 if failures.is_empty() else 1)
