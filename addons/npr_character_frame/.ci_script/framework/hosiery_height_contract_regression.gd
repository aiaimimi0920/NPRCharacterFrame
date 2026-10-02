extends "palette_contract_regression.gd"
## Pin coordinate, UI, persistence and consumer contracts before author calibration changes.

var _height_observations: Dictionary = {}


func _run() -> void:
	_state_height_contract()
	root.mouse_passthrough = true
	root.unfocusable = true
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("height_scheme.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	_wardrobe.visual_layers.set_process(false)
	_wardrobe.performance.apply_pose(0.0, 0.1)
	await _frames(5)
	var defaults: Dictionary = _wardrobe.state.to_data()
	_wardrobe.select_section(1)
	var slider := _wardrobe._content.find_child("Debug袜口高度（米）", true, false) as HSlider
	_check(slider != null, "Real hosiery height slider exists")
	_check(
		slider.min_value == 0.5 and slider.max_value == 1.55 and slider.step == 0.01,
		"Current UI bounds and step are pinned independently of the author domain"
	)
	await _snapshot("initial")
	for value in [0.5, 1.0, 1.34, 1.55]:
		slider.value = value
		_check(
			is_equal_approx(_wardrobe.state.hosiery_height, value), "Slider signal stores height"
		)
		_consumer_contract(value)
		var expected := defaults.duplicate(true)
		expected.hosiery_height = _wardrobe.state.hosiery_height
		_check(_wardrobe.state.to_data() == expected, "Height edit preserves unrelated state")
		await _snapshot("height_" + str(roundi(value * 100)))
	_check(_palette_images.height_50 != _palette_images.height_155, "Height changes actual pixels")
	_check(
		_palette_images.initial == _palette_images.height_134,
		"Default height restores exact pixels"
	)
	_wardrobe._set_hosiery_height(-10.0)
	_check(_wardrobe.state.hosiery_height == 0.5, "Setter clamps below UI range")
	_wardrobe._set_hosiery_height(10.0)
	_check(_wardrobe.state.hosiery_height == 1.55, "Setter clamps above UI range")
	_rain_boundary_contract()
	_wardrobe._set_hosiery_height(1.0)
	_wardrobe.save_scheme()
	var saved := FileAccess.get_file_as_bytes(_wardrobe.save_path)
	_wardrobe.configure_save_path(_wardrobe.save_path)
	_consumer_contract(1.0)
	_wardrobe.save_scheme()
	_check(
		saved == FileAccess.get_file_as_bytes(_wardrobe.save_path), "Height save bytes round trip"
	)
	_wardrobe.reset_scheme()
	_check(_wardrobe.state.to_data() == defaults, "Reset restores current complete defaults")
	_consumer_contract(1.34)
	await _snapshot("reset")
	_check(_palette_images.initial == _palette_images.reset, "Reset restores exact height pixels")
	_wardrobe.configure_save_path(_output.path_join("absent.json"))
	_check(_wardrobe.state.to_data() == defaults, "Missing-path defaults match initial state")
	_wardrobe._set_tulle_geometry_enabled(true)
	_wardrobe._set_hosiery_height(0.5)
	await _snapshot("fitted_low")
	_wardrobe._set_hosiery_height(1.55)
	await _snapshot("fitted_high")
	_check(
		_palette_images.fitted_low != _palette_images.fitted_high,
		"Visible fitted height changes pixels"
	)
	_wardrobe.reset_scheme()
	await _snapshot("fitted_reset")
	_check(
		_palette_images.initial == _palette_images.fitted_reset,
		"Fitted toggle and height restore exactly"
	)
	_record_open_calibration()
	_wardrobe.free()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	(
		FileAccess
		. open(_output.path_join("hosiery_height_contract.json"), FileAccess.WRITE)
		. store_string(
			JSON.stringify(
				{
					"checks": _checks,
					"images": _palette_images,
					"observations": _height_observations
				},
				"  "
			)
		)
	)
	print("HOSIERY_HEIGHT_CONTRACT_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)


func _state_height_contract() -> void:
	var factory = STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
	var original: Dictionary = factory.to_data()
	_check(original.hosiery_height == 1.34, "Current factory height")
	for value in [0.5, 1.0, 1.34, 1.55]:
		var data := original.duplicate(true)
		data.hosiery_height = value
		_check(factory.load_data(data), "Saved height accepts interval value " + str(value))
		_check(factory.to_data() == data, "Saved height stays authoritative " + str(value))
	for value in [0.5 - 1e-9, 1.55 + 1e-9, NAN, INF, "1.34"]:
		var data := original.duplicate(true)
		data.hosiery_height = value
		var before: Dictionary = factory.to_data()
		_check(not factory.load_data(data), "Reject invalid saved height " + str(value))
		_check(factory.to_data() == before, "Height rejection is atomic")
	for schema in range(1, 6):
		var data := original.duplicate(true)
		data.schema = schema
		for version in range(schema, 10):
			for key in ADDED_AFTER_SCHEMA[version]:
				data.erase(key)
		var before := data.duplicate(true)
		_check(factory.load_data(data), "Pre-height schema loads " + str(schema))
		_check(factory.hosiery_height == 1.34, "Historical missing-height migration remains 1.34")
		_check(data == before, "Migration leaves caller data unchanged")
	for schema in range(6, 11):
		var data := original.duplicate(true)
		data.schema = schema
		data.hosiery_height = 0.82
		for version in range(schema, 10):
			for key in ADDED_AFTER_SCHEMA[version]:
				data.erase(key)
		_check(factory.load_data(data), "Height-bearing schema loads " + str(schema))
		_check(factory.hosiery_height == 0.82, "Existing height survives migration")


func _consumer_contract(height: float) -> void:
	var body: ShaderMaterial = _wardrobe.preview.materials[0]
	var fitted: ShaderMaterial = _wardrobe.visual_layers._hosiery.material
	_check(
		is_equal_approx(float(body.get_shader_parameter("u_npr_hosiery_height")), height),
		"Body receives saved actor-rest height"
	)
	_check(
		is_equal_approx(float(fitted.get_shader_parameter("u_npr_hosiery_height")), height),
		"Fitted hosiery receives the same height even while hidden"
	)
	_check(
		is_equal_approx(float(_wardrobe.visual_layers.surface_rain._height), height),
		"Rain classification receives the same height even while disabled"
	)


func _rain_boundary_contract() -> void:
	var rain = _wardrobe.visual_layers.surface_rain
	var triangle := -1
	var rest_height := 0.0
	var bary := Vector3(0.25, 0.25, 0.5)
	for index in rain.data.kinds.size():
		if int(rain.data.kinds[index]) != 5:
			continue
		var ids: Array = rain.data.indices[index]
		var height: float = (
			rain.positions[ids[0]].y * bary.x
			+ rain.positions[ids[1]].y * bary.y
			+ rain.positions[ids[2]].y * bary.z
		)
		if height > 0.6 and height < 1.45:
			triangle = index
			rest_height = height
			break
	_check(triangle >= 0, "Actual rain asset contains an interior hosiery candidate")
	if triangle < 0:
		return
	_wardrobe._set_hosiery_height(rest_height)
	_check(rain._kind(triangle, bary) == 0, "Rain boundary at equal rest height is exposed skin")
	_wardrobe._set_hosiery_height(rest_height + 0.01)
	_check(rain._kind(triangle, bary) == 5, "Rain below selected height is hosiery")
	_wardrobe._transparency_changed(1.0)
	_check(rain._kind(triangle, bary) == 0, "Fully transparent hosiery is exposed skin for rain")
	_wardrobe._transparency_changed(0.5)
	_height_observations = {"rain_triangle": triangle, "rain_actor_rest_y": rest_height}


func _record_open_calibration() -> void:
	# Record limitations, not assertions that would canonize them as desired behavior.
	var profile: NPRHosieryProfile = _wardrobe.character_definition.hosiery_profile.duplicate(true)
	profile.domain_height_range = Vector2(1.6, 2.5)
	profile.domain_full_width_below = 2.0
	var state = STATE.new("review_actor", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
	var payload: Dictionary = state.to_data()
	payload.hosiery_height = 1.9
	_height_observations["alternate_domain"] = {
		"profile_errors": profile.validate(),
		"saved_height": 1.9,
		"state_accepted": state.load_data(payload),
		"note": "Structural profile validity is not proof of geometry fit"
	}
	var rain = _wardrobe.visual_layers.surface_rain
	var custom: PackedFloat32Array = _wardrobe.preview.meshes[0].mesh.surface_get_arrays(0)[
		Mesh.ARRAY_CUSTOM0
	]
	var max_error := 0.0
	for index in mini(rain.positions.size(), custom.size() / 4):
		max_error = maxf(max_error, absf(rain.positions[index].y - custom[index * 4 + 2]))
	_height_observations["rain_vs_body_rest_y"] = {
		"rain_vertices": rain.positions.size(),
		"body_vertices": custom.size() / 4,
		"max_absolute_error": max_error
	}
	_check(
		rain.positions.size() * 4 == custom.size(),
		"Rain and Body have the same sample vertex count"
	)
	_check(max_error == 0.0, "Sample rain and Body actor-rest Y coordinates match exactly")
	var data_before: Dictionary = _wardrobe.state.to_data()
	_wardrobe._camera_profile.view_heights[0] = 1.8
	_wardrobe._camera_profile.view_distances[0] = 6.0
	_wardrobe._camera_profile.horizontal_offset = 0.2
	_wardrobe.framework.set_quality_view(0)
	_height_observations["quality_view_camera"] = {
		"authored_height": 1.8,
		"actual_height": _wardrobe._target.y,
		"authored_horizontal_offset": 0.2,
		"expected_scaled_horizontal_offset": 0.2 * _wardrobe._distance / 6.0,
		"actual_horizontal_offset": _wardrobe.camera.h_offset,
		"distance": _wardrobe._distance
	}
	_check(_wardrobe.state.to_data() == data_before, "Quality view does not mutate saved state")
