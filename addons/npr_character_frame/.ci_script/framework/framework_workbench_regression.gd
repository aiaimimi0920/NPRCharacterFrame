extends "res://addons/npr_character_frame/.ci_script/framework/framework_expression_regression.gd"
## Real production shaders and workbench controls; no replacement test materials.

var _measurements: Dictionary = {}


func _run() -> void:
	_spawn()
	_wardrobe.select_section(8)
	await _capture("baseline")
	var baseline_size: Vector2i = _wardrobe.viewport.size
	var baseline_camera: Transform3D = _wardrobe.camera.transform
	var baseline_fov: float = _wardrobe.camera.fov
	var baseline_offset: float = _wardrobe.camera.h_offset
	var saved: Dictionary = _wardrobe.state.to_data()
	await _diagnostics()
	await _styles()
	_wardrobe.framework.play_sequence()
	_wardrobe.framework.clear_effects()
	await create_timer(0.75).timeout
	_check(
		_wardrobe.performance.expressions.active_count() == 0,
		"Cancel retires pending sequence callbacks"
	)
	_check(not _wardrobe.speech.player.playing, "Cancel stops speech started by this workbench")
	await _comparison()
	await _workbench_ui()
	_check(_wardrobe.state.to_data() == saved, "Workbench does not alter the saved scheme")
	_wardrobe.reset_scheme()
	_check(not _wardrobe.framework.locked, "Reset releases the observation lock")
	_check(_wardrobe.framework.diagnostics.mode == 0, "Reset clears diagnostics")
	_check(_wardrobe.framework.captures == [{}, {}], "Reset releases captured images")
	_check(
		(
			_wardrobe.state.to_data()
			== (
				_wardrobe
				. STATE
				. new(_wardrobe.character_id, SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
				. to_data()
			)
		),
		"Reset restores factory scheme, not deterministic fixture overrides"
	)
	_check(
		_wardrobe.performance.blink_enabled and _wardrobe.performance.secondary_enabled,
		"Reset restores enabled factory blink and secondary motion"
	)
	await _capture("reset")
	_check(
		_wardrobe.viewport.size == baseline_size, "Reset comparison preserves viewport dimensions"
	)
	_check(
		_wardrobe.camera.transform == baseline_camera, "Reset preserves baseline camera transform"
	)
	_check(
		_wardrobe.camera.fov == baseline_fov and _wardrobe.camera.h_offset == baseline_offset,
		"Reset preserves baseline camera projection"
	)
	_measurements.reset_comparison = {
		"baseline_size": [baseline_size.x, baseline_size.y],
		"reset_size": [_wardrobe.viewport.size.x, _wardrobe.viewport.size.y],
		"baseline_camera": str(baseline_camera),
		"reset_camera": str(_wardrobe.camera.transform),
		"baseline_scheme": saved,
		"reset_scheme": _wardrobe.state.to_data()
	}
	_check(_same_image("baseline", "reset"), "Full reset returns exact baseline pixels")
	_finish("WORKBENCH")


func _diagnostics() -> void:
	var workbench: Node = _wardrobe.framework
	workbench.diagnostics.set_hair_hidden(true)
	await _capture("without_hair")
	_check(not _wardrobe.preview.meshes[2].visible, "Hair hide affects actual production mesh")
	var fingerprints: Array[int] = []
	for mode in range(1, 10):
		_choose("DiagnosticMode", mode)
		await _capture("diagnostic_%d" % mode)
		var frame := Image.load_from_file(_output.path_join("diagnostic_%d.png" % mode))
		var fingerprint := hash(frame.get_data())
		_check(not fingerprints.has(fingerprint), "Diagnostic %d has distinct GPU output" % mode)
		fingerprints.append(fingerprint)
		if mode == 1:
			var colors := _partition_colors(frame)
			_measurements.partition_pixels = colors
			for key in colors:
				_check(colors[key] > 8, "Visible partition color: " + key)
	_choose("DiagnosticMode", 4)
	var yaw: float = _wardrobe.preview.light_yaw
	_wardrobe.preview.light_yaw = -85
	await _capture("sdf_left")
	_wardrobe.preview.light_yaw = 85
	await _capture("sdf_right")
	_check(
		not _same_image("sdf_left", "sdf_right"),
		"SDF diagnostic responds to actual light direction"
	)
	_wardrobe.preview.light_yaw = yaw
	_choose("DiagnosticMode", 1)
	var token: int = _wardrobe.performance.expressions.play(&"squeeze", 0.1)
	_wardrobe.performance._apply_face()
	_wardrobe.performance._apply_face(0.2)
	_check(
		_wardrobe.visual_layers._symbol_eyes.visible, "Partition view survives expression expiry"
	)
	_wardrobe.performance.expressions.cancel(token)
	_choose("DiagnosticMode", 0)
	_check(
		not _wardrobe.visual_layers._symbol_eyes.visible,
		"Leaving partitions restores current eye owner"
	)
	workbench.diagnostics.set_hair_hidden(false)
	await _capture("diagnostics_restored")
	_check(
		_same_image("baseline", "diagnostics_restored"), "All diagnostics restore exact baseline"
	)
	_choose("DiagnosticMode", 2)
	_wardrobe._set_display_mode("white")
	_check(workbench.diagnostics.mode == 0, "White display disables render diagnostics")
	_check(
		(_widget("DiagnosticMode") as OptionButton).selected == 0,
		"Diagnostic picker reflects display override"
	)
	_wardrobe._set_display_mode("render")


func _styles() -> void:
	var workbench: Node = _wardrobe.framework
	var style: Resource = workbench.STYLE.capture(_wardrobe.preview)
	var other := NPRCharacter.new()
	other.definition = _wardrobe.preview.definition.duplicate()
	_wardrobe.turntable.add_child(other)
	other.hide()
	var untouched: Resource = workbench.STYLE.capture(other)
	var environment := [
		_wardrobe._environment.ambient_light_energy, _wardrobe._environment.tonemap_exposure
	]
	workbench.PRESETS[4].apply(_wardrobe.preview)
	await _capture("preset_before")
	var previous := "preset_before"
	for index in workbench.PRESETS.size():
		workbench.preset_index = index
		_check(workbench.apply_preset(), "Preset validates and applies: %d" % index)
		await _capture("preset_%d" % index)
		_check(
			not _same_image(previous, "preset_%d" % index),
			"Preset has visible response: %d" % index
		)
		previous = "preset_%d" % index
		if index == 0:
			_check(
				_same_image("baseline", previous),
				"Daily preset preserves the approved default style"
			)
		var snapshot: Resource = workbench.STYLE.capture(other)
		_check(
			snapshot.character_values == untouched.character_values,
			"Other actor material isolation: %d" % index
		)
		_check(
			snapshot.lighting_values == untouched.lighting_values,
			"Other actor lighting isolation: %d" % index
		)
	_check(
		(
			environment
			== [
				_wardrobe._environment.ambient_light_energy, _wardrobe._environment.tonemap_exposure
			]
		),
		"Presets preserve host environment"
	)
	style.apply(_wardrobe.preview)
	workbench.preset_index = 3
	workbench.preset_scope = workbench.STYLE.Scope.CHARACTER
	workbench.apply_preset()
	_check(
		workbench.STYLE.capture(_wardrobe.preview).lighting_values == style.lighting_values,
		"Character scope preserves lighting"
	)
	var character_values: Dictionary = workbench.STYLE.capture(_wardrobe.preview).character_values
	workbench.preset_index = 2
	workbench.preset_scope = workbench.STYLE.Scope.LIGHTING
	workbench.apply_preset()
	_check(
		workbench.STYLE.capture(_wardrobe.preview).character_values == character_values,
		"Lighting scope preserves character style"
	)
	style.apply(_wardrobe.preview)
	var body_direction: Variant = _wardrobe.preview.meshes[0].get_instance_shader_parameter(
		"u_custom_main_light_dir"
	)
	_wardrobe.preview.set_face_light(Vector3(1, 0.1, 0.1), 1.0)
	await _capture("face_art_right")
	_wardrobe.preview.set_face_light(Vector3(-1, 0.1, 0.1), 1.0)
	await _capture("face_art_left")
	_check(
		not _same_image("face_art_left", "face_art_right"),
		"Independent face art direction changes actual SDF"
	)
	_check(
		(
			_wardrobe.preview.meshes[0].get_instance_shader_parameter("u_custom_main_light_dir")
			== body_direction
		),
		"Face art direction preserves body scene light"
	)
	style.apply(_wardrobe.preview)
	await _capture("styles_restored")
	_check(
		_same_image("baseline", "styles_restored"), "Preset restore returns exact original pixels"
	)
	other.free()
	workbench.preset_scope = 0


func _comparison() -> void:
	var workbench: Node = _wardrobe.framework
	await workbench.capture(0)
	_check(workbench.locked, "Capture A automatically locks observation")
	_check(
		(_widget("FrameworkLock") as CheckButton).button_pressed,
		"Automatic lock synchronizes actual control"
	)
	var camera: Transform3D = _wardrobe.camera.transform
	var clock: float = _wardrobe.performance.clock
	var lighting: Dictionary = workbench.STYLE.capture(_wardrobe.preview).lighting_values
	_wardrobe.set_view("full")
	_wardrobe.preview.light_yaw = 80
	_wardrobe.performance._process(0.4)
	await _frames(3)
	_check(_wardrobe.camera.transform == camera, "Locked camera rejects view changes")
	_check(_wardrobe.performance.clock == clock, "Locked pose clock does not advance")
	_check(
		workbench.STYLE.capture(_wardrobe.preview).lighting_values == lighting,
		"Locked lighting restored before draw"
	)
	workbench.preset_index = 3
	workbench.preset_scope = 0
	_check(not workbench.apply_preset(), "Locked workbench rejects lighting preset scope")
	workbench.preset_scope = workbench.STYLE.Scope.CHARACTER
	_check(workbench.apply_preset(), "Locked workbench permits material comparison")
	await workbench.capture(1)
	_check(
		workbench.captures[0].camera == workbench.captures[1].camera,
		"A/B share actual camera transform"
	)
	_check(
		workbench.captures[0].lighting == workbench.captures[1].lighting,
		"A/B share lighting metadata"
	)
	_check(
		workbench.captures[0].image.get_data() != workbench.captures[1].image.get_data(),
		"A/B store different actual rendered styles"
	)
	for slot in 2:
		workbench.captures[slot].image.save_png(_output.path_join("reference_%d.png" % slot))
		workbench.show_capture(slot)
		_check(not _wardrobe._stage.visible, "Recorded view hides live stage: %d" % slot)
		_check(
			(
				workbench._reference.texture.get_image().get_data()
				== workbench.captures[slot].image.get_data()
			),
			"Displayed reference matches recorded pixels: %d" % slot
		)
	workbench.show_capture(-1)
	_check(
		_wardrobe._stage.visible and not workbench._reference.visible,
		"Live view restores the real stage"
	)
	workbench.set_locked(false)
	workbench.restore_style()
	workbench.preset_scope = 0


func _workbench_ui() -> void:
	var original_size := root.size
	var ids := [
		"Comic_sweat",
		"Comic_heart_eyes",
		"ExpressionSequence",
		"DiagnosticMode",
		"FrameworkLock",
		"CaptureA",
		"ShowB",
		"StylePreset",
		"StyleScope",
		"FaceArtLightWeight",
		"ScreenQualityEnabled",
		"QualityView2"
	]
	for dimensions in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = dimensions
		await _frames(3)
		for id: String in ids:
			var widget := _widget(id)
			_check(widget != null, "Workbench widget exists: " + id)
			if widget != null:
				_wardrobe._options_scroll.ensure_control_visible(widget)
				await _frames(2)
				_check(
					_wardrobe._options_scroll.get_global_rect().encloses(widget.get_global_rect()),
					"Entire control reachable at %s: %s" % [dimensions, id]
				)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("ui_%d.png" % dimensions.x))
	root.size = original_size
	await _frames(3)
	_check(root.size == original_size, "UI reachability probe restores its caller's window size")


func _partition_colors(frame: Image) -> Dictionary:
	frame.resize(360, 225, Image.INTERPOLATE_NEAREST)
	var counts := {"original_blue": 0, "eye_green": 0, "mouth_cyan": 0, "hidden_red": 0}
	for y in frame.get_height():
		for x in frame.get_width():
			var color := frame.get_pixel(x, y)
			if color.a < 0.9:
				continue
			if color.b > 0.7 and color.r < 0.3 and color.g < 0.6:
				counts.original_blue += 1
			if color.g > 0.7 and color.r < 0.3 and color.b < 0.6:
				counts.eye_green += 1
			if color.g > 0.7 and color.b > 0.7 and color.r < 0.3:
				counts.mouth_cyan += 1
			if color.r > 0.7 and color.g < 0.3 and color.b < 0.3:
				counts.hidden_red += 1
	return counts


func _widget(id: String) -> Control:
	return _wardrobe._content.find_child(id, true, false) as Control


func _choose(id: String, index: int) -> void:
	var picker := _widget(id) as OptionButton
	picker.select(index)
	picker.item_selected.emit(index)


func _finish(label: String) -> void:
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"checks": _checks,
				"captures": _captures,
				"measurements": _measurements,
				"engine": Engine.get_version_info()
			},
			"  "
		)
	)
	_wardrobe.free()
	print(label, "_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)
