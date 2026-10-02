extends SceneTree
const SAMPLE_HEIGHT_PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/showcase_height.tres"
)
const SAMPLE_PALETTE_PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/showcase_palette.tres"
)

## Real UI input, saved-state round trip and GPU frames of wardrobe controls.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const STATE = preload("res://addons/npr_character_frame/showcase/wardrobe_state.gd")
const REGION_CAPTURE = preload("wardrobe_region_capture.gd")
const CAPTURE_CLOCK = preload("capture_clock.gd")
const CAPTURE_POINTER = preload("capture_pointer.gd")
var _wardrobe: Control
var _output: String
var _checks: Array[Dictionary] = []
var _state_only := false
var _region_capture := REGION_CAPTURE.new()
var _regions: Dictionary = {}
var _frames_sha256: Dictionary = {}
var _capture_clock := CAPTURE_CLOCK.new()
var _capture_states: Dictionary = {}


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		push_error("WARDROBE_FAILED: expected a dummy argument and output path")
		quit(1)
		return
	_output = arguments[1]
	_state_only = arguments.has("--state-only")
	_run.call_deferred()


func _run() -> void:
	if _state_only:
		_test_state_contract()
		var state_failures := _checks.filter(func(check: Dictionary): return not check["pass"])
		FileAccess.open(_output.path_join("wardrobe_state.json"), FileAccess.WRITE).store_string(
			JSON.stringify({"checks": _checks}, "  ")
		)
		print("WARDROBE_STATE_CHECKS=", _checks.size(), " FAILURES=", state_failures.size())
		print("REGRESSION_FAILED" if not state_failures.is_empty() else "REGRESSION_OK")
		quit(1 if not state_failures.is_empty() else 0)
		return
	root.mouse_passthrough = true
	root.unfocusable = true
	_wardrobe = SCENE.instantiate()
	root.add_child(_wardrobe)
	_wardrobe.configure_save_path(_output.path_join("scheme.json"))
	_capture_clock.bind(_wardrobe.performance)
	await _frames(10)
	_check(_wardrobe.preview.initialized, "Production actor initializes")
	var material_contract: Dictionary = _wardrobe.equipment.authored_material_contract()
	_check(
		(
			material_contract.loaded
			and material_contract.objects == 19
			# Three used color maps plus three corresponding roughness maps.
			and material_contract.textures == 6
			and not material_contract.enabled
		),
		"Authored equipment material bridge loads with neutral default"
	)
	_check_debug_panel()
	_test_private_geometry()
	await _test_cursor_zoom()
	await _press("Reset")
	await _capture("default")
	for index in range(1, 7):
		await _press("Palette%d" % index)
		_check(_wardrobe.state.palette == index, "Mouse selects palette %d" % index)
		await _capture("palette%d" % index)
	await _press("Palette0")
	await _press("Section1")
	var slider: HSlider = _wardrobe.find_child("StockingTransparency", true, false)
	await _slide(slider, 0.0)
	_check(_wardrobe.state.stocking_transparency < 0.03, "Slider makes stockings opaque")
	await _capture("stocking_opaque")
	await _slide(slider, 1.0)
	_check(_wardrobe.state.stocking_transparency > 0.97, "Slider reveals underlying skin")
	await _capture("stocking_transparent")
	await _press("HosieryStyle1")
	_check(_wardrobe.state.hosiery_style == 1, "Thin tulle style is selectable")
	await _capture("hosiery_tulle")
	await _press("HosieryStyle2")
	_check(_wardrobe.state.hosiery_style == 2, "Sock opening and stitch style is selectable")
	await _capture("hosiery_stitch")
	await _press("HosieryStyle0")
	await _press("Section6")
	for index in STATE.EXPRESSIONS.size():
		await _press("Expression%d" % index)
		_check(_wardrobe.state.expression == index, "Mouse selects expression %d" % index)
		await _capture("expression%d" % index)
	await _press("Section0")
	await _press("EquipmentSlot1")
	await _press("Save")
	_check(not _wardrobe.dirty, "Save finishes successfully")
	await _press("Save")
	_check(not _wardrobe.dirty, "Save replaces existing file")
	var saved: Dictionary = _wardrobe.state.to_data()
	var path: String = _wardrobe.save_path
	_wardrobe.free()
	await _frames(2)
	_wardrobe = SCENE.instantiate()
	root.add_child(_wardrobe)
	_wardrobe.configure_save_path(path)
	_capture_clock.bind(_wardrobe.performance)
	await _frames(10)
	_check(_wardrobe.state.to_data() == saved, "Restart restores saved choices")
	await _press("Section0")
	await _press("Reset")
	for index in range(1, 5):
		_check(_wardrobe.section == 0, "Equipment remains in clothing category %d" % index)
		await _press("EquipmentSlot%d" % (index - 1))
		_check(_wardrobe.state.equipment[index - 1], "Equip Blender part %d" % index)
		await _capture("equipment%d" % index)
		_check(
			_wardrobe.preview.depth_pass.proxies[0].mesh == _wardrobe.preview.meshes[0].mesh,
			"Equipment shares body depth geometry %d" % index
		)
		_check(
			(
				_wardrobe.preview.meshes[0].get_node("ShadowCaster").mesh
				== _wardrobe.preview.meshes[0].mesh
			),
			"Equipment shares body shadow geometry %d" % index
		)
		await _press("EquipmentSlot%d" % (index - 1))
		_check(not _wardrobe.state.equipment[index - 1], "Remove Blender part %d" % index)
	await _press("Section5")
	for index in 4:
		await _press("Action%d" % index)
		_wardrobe.performance.clock = 1.5
		await _capture("action%d" % index)
		_check(_wardrobe.state.action == index, "Blender action selection %d" % index)
	_wardrobe.performance.clock = 0.0
	await _press("Action0")
	await _press("Section6")
	_wardrobe.performance.blink_weight = 1.0
	await _capture("blink_closed")
	_check(_wardrobe.preview.meshes[1].get_blend_shape_value(0) == 1.0, "Blink drives face shape")
	_wardrobe.performance.blink_weight = 0.0
	await _capture("blink_open")
	for shape in ["aa", "ee", "ih", "oh", "ou"]:
		_wardrobe.performance.visemes = {shape: 1.0}
		await _capture("viseme_" + shape)
	_wardrobe.performance.visemes = {}
	await _capture("pending_actions")
	await _press("Section0")
	await _press("Reset")
	var front: float = _wardrobe.turntable.rotation_degrees.y
	await _mouse(Vector2(600, 350), true)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(650, 350)
	motion.relative = Vector2(50, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	await _mouse(Vector2(650, 350), false)
	_check(_wardrobe.turntable.rotation_degrees.y > front, "Drag rotates actual actor")
	_wardrobe.turntable.rotation_degrees.y = 180
	await _capture("back")
	await _press("Section1")
	slider = _wardrobe.find_child("StockingTransparency", true, false)
	await _slide(slider, 0.0)
	await _capture("back_opaque")
	await _slide(slider, 1.0)
	await _capture("back_transparent")
	_wardrobe.turntable.rotation_degrees.y = 0
	root.size = Vector2i(1152, 720)
	await _frames(5)
	await _capture("small")
	var rect: Rect2 = _wardrobe.find_child("Save", true, false).get_global_rect()
	_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect), "Save fits smallest window")
	await _test_navigation_layout(Vector2i(1152, 720))
	await _test_navigation_layout(Vector2i(1440, 900))
	_test_state_contract()
	await _test_region_negative_controls()
	FileAccess.open(_output.path_join("wardrobe_regions.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"schema": 1, "regions": _regions, "frames": _frames_sha256}, "  ")
	)
	FileAccess.open(_output.path_join("wardrobe.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "capture_states": _capture_states}, "  ")
	)
	var failures := _checks.filter(func(check: Dictionary): return not check["pass"])
	_wardrobe.free()
	print("WARDROBE_CHECKS=", _checks.size(), " FAILURES=", failures.size())
	if failures.is_empty():
		print("REGRESSION_OK")
	quit(0 if failures.is_empty() else 1)


func _test_navigation_layout(window_size: Vector2i) -> void:
	root.size = window_size
	await _frames(5)
	var footer: Control = _wardrobe.find_child("FullView", true, false)
	for index in _wardrobe.SECTIONS.size():
		await _press("Section%d" % index)
		var button: Control = _wardrobe.find_child("Section%d" % index, true, false)
		var rect := button.get_global_rect()
		_check(
			not rect.intersects(footer.get_global_rect()),
			"Navigation %d clears the footer at %s" % [index, window_size]
		)
		# The center used to work while the lower part of Section7 hit FullView.
		_wardrobe.select_section((index + 1) % _wardrobe.SECTIONS.size())
		var lower_edge := Vector2(rect.position.x + 32.0, rect.end.y - 10.0)
		await _mouse(lower_edge, true)
		await _mouse(lower_edge, false)
		_check(
			_wardrobe.section == index,
			"Navigation %d accepts lower-edge clicks at %s" % [index, window_size]
		)
	await _capture("navigation_%dx%d" % [window_size.x, window_size.y])


func _test_cursor_zoom() -> void:
	var camera: Camera3D = _wardrobe.camera
	var stage: Control = _wardrobe.get_node("Stage")
	var viewport: SubViewport = _wardrobe.viewport
	# Choose a real off-center surface, then inject wheel input through the UI.
	var pixel := camera.unproject_position(Vector3(-0.12, 2.55, 0.1))
	var hit: Dictionary = _wardrobe.preview.pick_surface(
		camera.project_ray_origin(pixel), camera.project_ray_normal(pixel)
	)
	_check(not hit.is_empty(), "Zoom anchor hits actual face geometry")
	if not hit.is_empty():
		var anchor: Vector3 = (
			camera.project_ray_origin(pixel) + camera.project_ray_normal(pixel) * hit.distance
		)
		var before := camera.position
		for step in 3:
			var wheel := InputEventMouseButton.new()
			wheel.position = pixel * stage.size / Vector2(viewport.size)
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			root.push_input(wheel)
			wheel.pressed = false
			root.push_input(wheel)
			await _frames(2)
			_check(
				camera.unproject_position(anchor).distance_to(pixel) < 1.0,
				"Cursor anchor stable at zoom step %d" % step
			)
		_check(
			camera.position.distance_to(anchor) < before.distance_to(anchor),
			"Wheel approaches selected surface"
		)
	var unchanged := camera.position
	_wardrobe._zoom_at(Vector2(10, 10), 1.0)
	_check(camera.position == unchanged, "Background does not move camera")
	_wardrobe.set_view("full")
	await _frames(2)


func _test_state_contract() -> void:
	var state := STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
	for key in ["hair_color", "skin_color", "eye_color", "ear_shape"]:
		var data := state.to_data()
		data[key] = "ffffff"
		_check(not state.load_data(data), "Identity field rejected: " + key)
	for value in [-1.0, 2.0, "0.5", NAN]:
		var data := state.to_data()
		data.stocking_transparency = value
		_check(not state.load_data(data), "Malformed opacity rejected: " + str(value))
	for key in [
		"hosiery_stitch", "eye_wetness", "wind_strength", "soft_tissue_pressure", "droplet_speed"
	]:
		for value in [-0.1, 1.1, "0.5", NAN]:
			var data := state.to_data()
			data[key] = value
			_check(
				not state.load_data(data), "Malformed visual scalar rejected: %s=%s" % [key, value]
			)
	var legacy := state.to_data()
	for key in [
		"hosiery_style",
		"hosiery_stitch",
		"wetness_regions",
		"eye_wetness",
		"wind_strength",
		"soft_tissue_pressure"
	]:
		legacy.erase(key)
	legacy.schema = 2
	_check(state.load_data(legacy), "Schema 2 migrates to visual-direction defaults")
	_check(
		state.to_data().schema == 10 and state.wetness_regions == [0.0, 0.0, 0.0, 0.0],
		"Migrated visual defaults are neutral"
	)
	var schema_three := state.to_data()
	for key in [
		"droplets_enabled",
		"droplet_count",
		"droplet_speed",
		"droplet_seed",
		"tulle_geometry_enabled",
		"eye_geometry_enabled"
	]:
		schema_three.erase(key)
	schema_three.schema = 3
	_check(state.load_data(schema_three), "Schema 3 migrates to droplet and geometry defaults")
	_check(
		state.to_data().schema == 10 and state.droplet_count == 0 and not state.droplets_enabled,
		"Migrated droplet defaults are neutral"
	)
	var schema_one_with_equipment := state.to_data()
	schema_one_with_equipment.schema = 1
	for key in [
		"action",
		"blink",
		"secondary",
		"hosiery_style",
		"hosiery_stitch",
		"wetness_regions",
		"eye_wetness",
		"wind_strength",
		"soft_tissue_pressure",
		"droplets_enabled",
		"droplet_count",
		"droplet_speed",
		"droplet_seed",
		"tulle_geometry_enabled",
		"eye_geometry_enabled"
	]:
		schema_one_with_equipment.erase(key)
	_check(
		state.load_data(schema_one_with_equipment),
		"Schema 1 with equipment migrates without dropping equipment"
	)
	_check(
		state.to_data().schema == 10 and state.equipment == schema_one_with_equipment.equipment,
		"Schema 1 equipment survives the migration chain"
	)
	for key in ["droplet_count", "droplet_seed"]:
		var bad_integer := state.to_data()
		bad_integer[key] = -1
		_check(not state.load_data(bad_integer), "Malformed droplet integer rejected: " + key)
	var baseline := state.to_data()
	for key in ["hair_dynamic_enabled", "hair_collision_enabled", "authored_materials_enabled"]:
		for value in [0, 1, "true", null]:
			var malformed := baseline.duplicate(true)
			malformed[key] = value
			_check(
				not state.load_data(malformed) and state.to_data() == baseline,
				"Visual boolean rejects malformed value atomically: " + key
			)
	var bad := baseline.duplicate(true)
	bad.colors = ["ffffff", "invalid", "ffffff"]
	_check(not state.load_data(bad) and state.to_data() == baseline, "Bad load is atomic")


func _test_private_geometry() -> void:
	var source: Node3D = _wardrobe.preview.definition.model_scene.instantiate()
	var original: MeshInstance3D = source.get_node(_wardrobe.preview.definition.body_path)
	var live: MeshInstance3D = _wardrobe.preview.meshes[0]
	_check(live.mesh.get_surface_count() == 1, "Derived body has one valid surface")
	var old := original.mesh.surface_get_arrays(0)
	var current := live.mesh.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		_check(
			old[channel] == current[channel], "Garment domain preserves source array %d" % channel
		)
	var normal_error := 0.0
	var authored: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(
			(
				"res://addons/npr_character_frame/"
				+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/hosiery_surface.json"
			)
		)
	)
	var repaired: Dictionary = {}
	for row: Array in authored.normal_rows:
		repaired[int(row[0])] = Vector3(row[4], row[5], row[6])
	for index in old[Mesh.ARRAY_NORMAL].size():
		var expected: Vector3 = repaired.get(index, old[Mesh.ARRAY_NORMAL][index])
		normal_error = maxf(normal_error, expected.distance_to(current[Mesh.ARRAY_NORMAL][index]))
	# Godot octahedrally re-encodes normals on add_surface_from_arrays.
	_check(normal_error < 0.0004, "Authored and untouched normals survive private mesh round-trips")
	print("WARDROBE_NORMAL_ROUNDTRIP_ERROR=", normal_error)
	_check(old[Mesh.ARRAY_CUSTOM0] == null, "Shared source has no garment mutations")
	_check(current[Mesh.ARRAY_CUSTOM0] != null, "Private body carries garment vertex domain")
	source.free()


func _press(id: String) -> void:
	var button: Button = _wardrobe.find_child(id, true, false)
	_check(button != null and button.is_visible_in_tree(), "Button visible: " + id)
	if button == null:
		return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(button)
			await _frames(3)
			break
		parent = parent.get_parent()
	var position := button.get_global_rect().get_center()
	# Queue an atomic click. Yielding with the button held lets unrelated OS
	# pointer motion cancel a synthetic release in the unfocusable test window.
	await _mouse(position, true, 0)
	await _mouse(position, false)
	await _frames(3)


func _slide(slider: HSlider, fraction: float) -> void:
	var parent := slider.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			parent.ensure_control_visible(slider)
			await _frames(3)
			break
		parent = parent.get_parent()
	var rect := slider.get_global_rect()
	await _mouse(rect.get_center(), true)
	var end := Vector2(lerpf(rect.position.x + 1, rect.end.x - 1, fraction), rect.get_center().y)
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.relative = end - rect.get_center()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	await _mouse(end, false)
	await _frames(3)


func _mouse(point: Vector2, pressed: bool, settle_frames := 2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event)
	await _frames(settle_frames)


func _frames(count: int) -> void:
	for index in count:
		await process_frame
		_capture_clock.advance()


func _capture(label: String) -> void:
	CAPTURE_POINTER.park(root)
	await _frames(4)
	await RenderingServer.frame_post_draw
	_capture_states[label] = _capture_clock.snapshot()
	root.get_texture().get_image().save_png(_output.path_join(label + ".png"))
	_wardrobe.viewport.get_texture().get_image().save_png(_output.path_join(label + "_stage.png"))
	_frames_sha256[label] = FileAccess.get_sha256(_output.path_join(label + "_stage.png"))
	if label in ["default", "back_opaque", "negative_reference"]:
		_regions[label] = await _region_capture.capture(
			self, _wardrobe, _output.path_join(label + "_regions.png")
		)
		var report: Dictionary = _regions[label]
		_check(report.saved, label + " semantic regions are saved")
		_check(report.exact_restore, label + " region capture restores exact production pixels")
		_check(report.camera_unchanged, label + " region capture preserves camera")


func _test_region_negative_controls() -> void:
	# Run after the original capture sequence; do not change its saved choices or images.
	_wardrobe.free()
	await _frames(2)
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("negative_unused.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	await _frames(10)
	await _capture("negative_reference")
	var face: ShaderMaterial = _wardrobe.preview.materials[1]
	var original_face_shader := face.shader
	var wrong_face := Shader.new()
	const FACE_ANCHOR := "float accent_scale ="
	_check(
		original_face_shader.code.count(FACE_ANCHOR) == 1,
		"Face negative control targets actual albedo"
	)
	wrong_face.code = original_face_shader.code.replace(
		FACE_ANCHOR, "albedo.rgb *= vec3(1.0, 0.0, 1.0);\n" + FACE_ANCHOR
	)
	face.shader = wrong_face
	await _capture("negative_face_dye")
	face.shader = original_face_shader
	var body: ShaderMaterial = _wardrobe.preview.materials[0]
	var original_shader := body.shader
	var wrong := Shader.new()
	const DYE_FACTOR := "coverage * u_npr_garment_mix"
	_check(
		original_shader.code.count(DYE_FACTOR) == 1, "Dye negative control targets actual coverage"
	)
	wrong.code = original_shader.code.replace(DYE_FACTOR, "u_npr_garment_mix")
	await _press("Palette1")
	body.shader = wrong
	await _capture("negative_clothing_leak")
	body.shader = original_shader
	await _press("Palette0")
	var vertex_regions: Variant = body.get_shader_parameter("u_npr_garment_vertex_regions")
	body.set_shader_parameter("u_npr_garment_vertex_regions", false)
	await _capture("negative_hosiery_leak")
	body.set_shader_parameter("u_npr_garment_vertex_regions", vertex_regions)
	var visibility: Variant = body.get_shader_parameter("u_npr_visibility_alpha")
	body.set_shader_parameter("u_npr_visibility_alpha", 0.5)
	await _capture("negative_alpha")
	body.set_shader_parameter("u_npr_visibility_alpha", visibility)
	await _capture("negative_restored")


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("WARDROBE_FAILED: " + label)


func _check_debug_panel() -> void:
	_wardrobe.select_section(7)
	_check(_wardrobe._navigation.size() > 7, "Developer debug section is available")
	_check(_wardrobe._navigation[7].text.contains("参数总览"), "Developer debug section is labeled")
	_check(
		_wardrobe._content.get_child_count() >= 12,
		"Developer debug panel exposes lighting and material controls"
	)
	var has_compression_control := false
	for child in _wardrobe._content.get_children():
		for nested in child.get_children():
			if nested is Label and nested.text.contains("勒肉"):
				has_compression_control = true
				break
		if has_compression_control:
			break
	_check(has_compression_control, "Developer debug panel exposes hosiery compression control")
	_check_pupil_panel()
	_wardrobe.preview.light_yaw = 37.0
	_wardrobe.preview.light_elevation = 58.0
	_check(
		(
			is_equal_approx(_wardrobe.preview.light_yaw, 37.0)
			and is_equal_approx(_wardrobe.preview.light_elevation, 58.0)
		),
		"Developer light direction accepts runtime changes"
	)
	_wardrobe.select_section(0)


func _check_pupil_panel() -> void:
	var values := {"瞳孔方向 X": 0.3, "瞳孔方向 Y": -0.4, "瞳孔缩放": 1.2}
	for title: String in values:
		var slider := _wardrobe._content.find_child("Debug" + title, true, false) as HSlider
		_check(slider != null, "Pupil slider exists: " + title)
		if slider != null:
			slider.value = values[title]
	var contract: Dictionary = _wardrobe.visual_layers.eye_pupil_contract()
	_check(
		contract.focus.is_equal_approx(Vector2(0.3, -0.4)) and is_equal_approx(contract.scale, 1.2),
		"Pupil slider signals reach the wardrobe visual layer"
	)
	_wardrobe.select_section(0)
	_wardrobe.select_section(7)
	for title: String in values:
		var slider := _wardrobe._content.find_child("Debug" + title, true, false) as HSlider
		_check(
			slider != null and is_equal_approx(slider.value, values[title]),
			"Reopened pupil panel shows runtime value: " + title
		)
	_wardrobe.reset_scheme()
	contract = _wardrobe.visual_layers.eye_pupil_contract()
	_check(
		contract.focus == Vector2.ZERO and is_equal_approx(contract.scale, 1.0),
		"Pupil panel reset restores neutral runtime controls"
	)
