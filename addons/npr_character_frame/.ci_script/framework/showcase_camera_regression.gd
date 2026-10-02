extends SceneTree
## Real showcase camera paths, GPU framing and saved-state preservation.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const CLOCK = preload("capture_clock.gd")
const POINTER = preload("capture_pointer.gd")
const PROFILE = preload("res://addons/npr_character_frame/npr_showcase_camera_profile.gd")
var _scene: Control
var _output: String
var _checks: Array[Dictionary] = []
var _captures: Dictionary = {}
var _clock := CLOCK.new()


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	await _spawn()
	_scene.save_scheme()
	var saved := FileAccess.get_file_as_bytes(_scene.save_path)
	await _capture("initial")
	for mode in ["full", "half", "face"]:
		_scene.set_view(mode)
		await _capture(mode)
	_scene._show_soft_pressure()
	await _capture("pressure")
	_check(_scene._distance == 1.1, "Sample pressure distance is preserved")
	_scene._reset_view()
	await _capture("reset")
	_check(_captures.initial == _captures.reset, "Initial and reset camera inputs match")
	_check(
		(
			FileAccess.get_sha256(_output.path_join("initial_stage.png"))
			== FileAccess.get_sha256(_output.path_join("reset_stage.png"))
		),
		"Camera reset restores exact stage pixels"
	)
	_scene._camera_pitch = 12.0
	_scene._target = Vector3(0.4, 1.8, -0.3)
	_scene.set_view("half")
	await _capture("pitched_half")
	_check(_scene._target.z == Vector3(0, 0, -0.3).z, "View switch preserves cursor zoom depth")
	_check(_scene._camera_pitch == 12.0, "View switch preserves orbit pitch")
	_scene._reset_view()
	_scene.save_scheme()
	_check(
		FileAccess.get_file_as_bytes(_scene.save_path) == saved, "Camera does not alter saved bytes"
	)
	_profile_checks()
	await _quality_views("sample")
	_scene.free()
	await _alternate_profile()
	await _spawn()
	await _capture("recreated")
	_check(_captures.initial == _captures.recreated, "Fresh sample restores all camera inputs")
	_check(
		(
			FileAccess.get_sha256(_output.path_join("initial_stage.png"))
			== FileAccess.get_sha256(_output.path_join("recreated_stage.png"))
		),
		"Fresh sample restores exact production pixels"
	)
	_scene.free()
	_finish()


func _spawn(profile: NPRShowcaseCameraProfile = null) -> void:
	_scene = SCENE.instantiate()
	if profile != null:
		_scene.character_definition = _scene.character_definition.duplicate()
		_scene.character_definition.showcase_camera_profile = profile
	_scene.save_path = _output.path_join("camera_scheme.json")
	root.add_child(_scene)
	_clock.bind(_scene.performance)
	for index in 10:
		await process_frame
		_clock.advance()
	POINTER.park(root)
	_check(_scene.preview.initialized, "Configured showcase initializes")


func _profile_checks() -> void:
	var sample: NPRShowcaseCameraProfile = _scene.character_definition.showcase_camera_profile
	_check(sample.validate().is_empty(), "Authored camera profile validates")
	_check(
		not PROFILE.new().validate().is_empty(), "Missing calibration cannot use sample defaults"
	)
	_check(sample.view_distances[0] == 5.6, "Camera distances retain float64 precision")
	var invalid: Array = [
		["view_heights", PackedFloat64Array([1.0, 2.0])],
		["view_heights", PackedFloat64Array([1.0, NAN, 3.0])],
		["view_distances", PackedFloat64Array([1.0, 2.0])],
		["view_distances", PackedFloat64Array([1.0, 0.0, 3.0])],
		["view_distances", PackedFloat64Array([1.0, -1.0, 3.0])],
		["view_distances", PackedFloat64Array([1.0, INF, 3.0])],
		["field_of_view", 0.0],
		["field_of_view", 180.0],
		["pressure_distance", 0.0],
		["pressure_distance", -1.0],
		["pressure_target", Vector3(NAN, 0, 0)],
		["pressure_target", Vector3(0, INF, 0)],
	]
	for field in ["horizontal_offset", "vertical_offset", "field_of_view", "pressure_distance"]:
		invalid.append([field, NAN])
		invalid.append([field, INF])
	for entry in invalid:
		var broken: NPRShowcaseCameraProfile = sample.duplicate()
		broken.set(entry[0], entry[1])
		_check(not broken.validate().is_empty(), "Reject invalid camera " + str(entry))
	var definition: NPRCharacterDefinition = _scene.character_definition.duplicate()
	definition.showcase_camera_profile = null
	_check(definition.validate().is_empty(), "Base rendering does not require showcase cameras")
	var candidate := SCENE.instantiate()
	candidate.character_definition = definition
	_check(
		"Full showcase requires showcase_camera_profile" in candidate._configuration_errors(),
		"Full showcase rejects missing calibration before stage construction"
	)
	definition.showcase_camera_profile = PROFILE.new()
	_check(not definition.validate().is_empty(), "Definition propagates invalid camera data")
	candidate.free()


func _alternate_profile() -> void:
	var profile := PROFILE.new()
	profile.view_heights = PackedFloat64Array([1.65, 2.28, 2.6])
	profile.view_distances = PackedFloat64Array([6.1, 3.25, 1.6])
	profile.horizontal_offset = 0.21
	profile.vertical_offset = 0.1
	profile.field_of_view = 42.0
	profile.pressure_target = Vector3(-0.2, 1.42, 0.05)
	profile.pressure_distance = 1.25
	_check(profile.validate().is_empty(), "Alternate authored framing validates")
	await _spawn(profile)
	_check(_scene._camera_profile != profile, "Showcase owns a camera calibration snapshot")
	await _quality_views("alternate")
	for mode: String in PROFILE.VIEW_INDICES:
		_scene.set_view(mode)
		var index: int = PROFILE.VIEW_INDICES[mode]
		_check(_scene._distance == profile.view_distances[index], mode + " uses authored distance")
		_check(
			_scene._target.y == Vector3(0, profile.view_heights[index], 0).y,
			mode + " uses authored target height"
		)
		await _capture("alternate_" + mode)
		_check(
			(
				FileAccess.get_sha256(_output.path_join(mode + "_stage.png"))
				!= FileAccess.get_sha256(_output.path_join("alternate_" + mode + "_stage.png"))
			),
			mode + " changes actual GPU framing"
		)
	_scene._show_soft_pressure()
	_check(_scene._target == profile.pressure_target, "Pressure view uses authored target")
	_check(_scene._distance == profile.pressure_distance, "Pressure view uses authored distance")
	await _capture("alternate_pressure")
	_scene.camera.fov = 30.0
	_scene._reset_view()
	_check(_scene.camera.fov == 42.0, "View reset restores authored factory FOV")
	profile.view_distances[0] = 9.0
	profile.view_heights[0] = 2.9
	profile.horizontal_offset = 0.9
	await _quality_views("snapshot")
	_scene.set_view("full")
	_check(_scene._distance == 6.1, "Source edits cannot mutate the active calibration snapshot")
	_scene.framework.set_locked(true)
	var locked: Transform3D = _scene.camera.transform
	_scene.set_view("face")
	_check(_scene.camera.transform == locked, "A/B lock still blocks view switching")
	_scene.framework.set_locked(false)
	_scene.free()


func _quality_views(label: String) -> void:
	_scene.save_scheme()
	var saved := FileAccess.get_file_as_bytes(_scene.save_path)
	var profile: NPRShowcaseCameraProfile = _scene._camera_profile
	for index in 3:
		_scene._target = Vector3(0.4, 2.0, -0.3)
		_scene._camera_pitch = 12.0
		var fov: float = _scene.camera.fov
		_scene.framework.set_quality_view(index)
		var distance: float = [3.0, 7.0, 18.0][index]
		var prefix := label + " quality " + str(index)
		_check(_scene._distance == distance, prefix + " preserves evaluation distance")
		_check(
			_scene._target == Vector3(0, profile.view_heights[0], 0),
			prefix + " consumes authored height and resets lateral/depth target"
		)
		_check(
			is_equal_approx(
				_scene.camera.h_offset,
				profile.horizontal_offset * distance / profile.view_distances[0]
			),
			prefix + " consumes authored horizontal framing"
		)
		_check(_scene._camera_pitch == 12.0, prefix + " preserves pitch")
		_check(_scene.camera.fov == fov, prefix + " preserves FOV")
		await _capture(label + "_quality_" + str(index))
	_scene.framework.set_locked(true)
	var locked := var_to_bytes(
		[_scene._target, _scene._distance, _scene.camera.h_offset, _scene.camera.transform]
	)
	for index in 3:
		_scene.framework.set_quality_view(index)
		_check(
			(
				var_to_bytes(
					[
						_scene._target,
						_scene._distance,
						_scene.camera.h_offset,
						_scene.camera.transform
					]
				)
				== locked
			),
			label + " quality A/B lock " + str(index)
		)
	_scene.framework.set_locked(false)
	_scene._reset_view()
	_check(_scene._distance == profile.view_distances[0], label + " reset authored distance")
	_check(
		_scene._target == Vector3(0, profile.view_heights[0], 0), label + " reset authored height"
	)
	_scene.save_scheme()
	_check(
		FileAccess.get_file_as_bytes(_scene.save_path) == saved, label + " quality save unchanged"
	)


func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _scene.viewport.get_texture().get_image()
	_check(image.save_png(_output.path_join(label + "_stage.png")) == OK, label + " stage saved")
	_captures[label] = {
		"target": var_to_bytes(_scene._target).hex_encode(),
		"distance": _scene._distance,
		"camera": var_to_bytes(_scene.camera.transform).hex_encode(),
		"fov": _scene.camera.fov,
		"offset": _scene.camera.h_offset,
		"simulation": _clock.snapshot(),
	}


func _finish() -> void:
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("showcase_camera.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "captures": _captures}, "  ")
	)
	print("SHOWCASE_CAMERA_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("SHOWCASE_CAMERA_FAILED: " + label)
