extends "hosiery_height_contract_regression.gd"
## Authored height selection is distinct from geometry and historical migration values.

const HEIGHT = preload("res://addons/npr_character_frame/npr_showcase_height_profile.gd")


func _run() -> void:
	_profile_contract()
	root.mouse_passthrough = true
	root.unfocusable = true
	var profile := _alternate()
	_wardrobe = SCENE.instantiate()
	_wardrobe.character_definition = _wardrobe.character_definition.duplicate()
	_wardrobe.character_definition.showcase_height_profile = profile
	_wardrobe.save_path = _output.path_join("authored_height.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	_wardrobe.visual_layers.set_process(false)
	_wardrobe.performance.apply_pose(0.0, 0.1)
	await _frames(5)
	var initial: Dictionary = _wardrobe.state.to_data()
	_check(initial.hosiery_height == 1.1, "Initial state uses authored factory height")
	_consumer_contract(1.1)
	_wardrobe.select_section(1)
	var slider := _wardrobe._content.find_child("Debug袜口高度（米）", true, false) as HSlider
	_check(slider.min_value == 0.4 and slider.max_value == 1.7, "UI consumes authored bounds")
	_check(slider.step == 0.02, "UI consumes authored step")
	await _snapshot("initial")
	slider.value = 0.6
	_check(is_equal_approx(_wardrobe.state.hosiery_height, 0.6), "Real slider updates state")
	_consumer_contract(0.6)
	await _snapshot("edited")
	_check(_palette_images.initial != _palette_images.edited, "Authored height affects pixels")
	_wardrobe._set_hosiery_height(-10.0)
	_check(_wardrobe.state.hosiery_height == 0.4, "Setter uses authored lower bound")
	_wardrobe._set_hosiery_height(10.0)
	_check(_wardrobe.state.hosiery_height == 1.7, "Setter uses authored upper bound")
	var data := initial.duplicate(true)
	data.hosiery_height = 1.431234567
	_check(_wardrobe.state.load_data(data), "Off-step saved height remains valid")
	_wardrobe._apply_state()
	_wardrobe.save_scheme()
	var saved := FileAccess.get_file_as_bytes(_wardrobe.save_path)
	profile.min_height = 2.0
	profile.max_height = 3.0
	profile.default_height = 2.5
	profile.step = 0.1
	_wardrobe.configure_save_path(_wardrobe.save_path)
	_check(_wardrobe.state.to_data() == data, "Reload keeps snapshot and exact saved height")
	_consumer_contract(data.hosiery_height)
	_wardrobe.save_scheme()
	_check(saved == FileAccess.get_file_as_bytes(_wardrobe.save_path), "Save bytes round trip")
	_wardrobe.reset_scheme()
	_check(_wardrobe.state.to_data() == initial, "Reset retains entry-time factory height")
	_consumer_contract(1.1)
	await _snapshot("reset")
	_check(_palette_images.initial == _palette_images.reset, "Reset restores exact pixels")
	_wardrobe.configure_save_path(_output.path_join("absent.json"))
	_check(_wardrobe.state.to_data() == initial, "Missing-path state uses entry snapshot")
	slider = _wardrobe._content.find_child("Debug袜口高度（米）", true, false) as HSlider
	_check(slider.min_value == 0.4 and slider.step == 0.02, "Rebuilt UI retains entry snapshot")
	_wardrobe.free()
	_wardrobe = SCENE.instantiate()
	_wardrobe.character_definition = _wardrobe.character_definition.duplicate()
	_wardrobe.character_definition.showcase_height_profile = _alternate()
	_wardrobe.save_path = _output.path_join("authored_height.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	_wardrobe.visual_layers.set_process(false)
	_wardrobe.performance.apply_pose(0.0, 0.1)
	await _frames(5)
	_check(_wardrobe.state.to_data() == data, "Fresh scene loads exact saved height")
	_wardrobe.reset_scheme()
	_check(_wardrobe.state.to_data() == initial, "Fresh reset restores authored defaults")
	await _snapshot("recreated")
	_check(_palette_images.initial == _palette_images.recreated, "Fresh reset restores pixels")
	_wardrobe.free()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	(
		FileAccess
		. open(_output.path_join("showcase_height_profile.json"), FileAccess.WRITE)
		. store_string(JSON.stringify({"checks": _checks, "images": _palette_images}, "  "))
	)
	print("SHOWCASE_HEIGHT_PROFILE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)


func _alternate() -> NPRShowcaseHeightProfile:
	var profile := HEIGHT.new()
	profile.min_height = 0.4
	profile.max_height = 1.7
	profile.default_height = 1.1
	profile.step = 0.02
	return profile


func _profile_contract() -> void:
	_check(SAMPLE_HEIGHT_PROFILE.validate().is_empty(), "Explicit sample calibration validates")
	_check(not HEIGHT.new().validate().is_empty(), "Empty profile has no sample fallback")
	for entry in [
		["min_height", 1.7],
		["min_height", 2.0],
		["max_height", 0.4],
		["default_height", 0.3],
		["default_height", 1.8],
		["step", 0.0],
		["step", -0.1]
	]:
		var invalid := _alternate()
		invalid.set(entry[0], entry[1])
		_check(not invalid.validate().is_empty(), "Reject invalid field " + str(entry))
	for field in ["min_height", "max_height", "default_height", "step"]:
		for value in [NAN, INF, -INF]:
			var invalid := _alternate()
			invalid.set(field, value)
			_check(not invalid.validate().is_empty(), "Reject nonfinite " + field)
	var candidate := SCENE.instantiate()
	candidate.character_definition = candidate.character_definition.duplicate()
	candidate.character_definition.showcase_height_profile = null
	_check(candidate.character_definition.validate().is_empty(), "Base rendering permits omission")
	_check(
		"Full showcase requires showcase_height_profile" in candidate._configuration_errors(),
		"Full showcase rejects missing calibration before assembly"
	)
	candidate.character_definition.showcase_height_profile = HEIGHT.new()
	_check(not candidate.character_definition.validate().is_empty(), "Definition validates height")
	candidate.free()
	_migration_contract()


func _migration_contract() -> void:
	var profile := _alternate()
	var state = STATE.new("review_actor", SAMPLE_PALETTE_PROFILE, profile)
	profile.default_height = 1.5
	_check(state.hosiery_height == 1.1, "State owns independent height snapshot")
	for schema in range(1, 11):
		var data: Dictionary = state.to_data()
		data.schema = schema
		data.hosiery_height = 1.431234567
		for version in range(schema, 10):
			for key in ADDED_AFTER_SCHEMA[version]:
				data.erase(key)
		var before := data.duplicate(true)
		_check(state.load_data(data), "Authored range accepts schema " + str(schema))
		_check(data == before, "Migration preserves caller data")
		_check(
			state.hosiery_height == (1.34 if schema < 6 else 1.431234567),
			"Historical fill and existing height remain authoritative"
		)
	profile.min_height = 1.6
	profile.max_height = 2.5
	profile.default_height = 1.9
	var tall = STATE.new("review_actor", SAMPLE_PALETTE_PROFILE, profile)
	var initial: Dictionary = tall.to_data()
	for value in [1.6, 1.9, 2.5]:
		var data := initial.duplicate(true)
		data.hosiery_height = value
		_check(tall.load_data(data), "Author bounds accept " + str(value))
		_check(tall.hosiery_height == value, "Double-precision endpoints remain exact")
	for value in [1.6 - 1e-9, 2.5 + 1e-9, NAN, INF, "1.9"]:
		var data := initial.duplicate(true)
		data.hosiery_height = value
		var before: Dictionary = tall.to_data()
		_check(not tall.load_data(data), "Invalid authored height rejected")
		_check(tall.to_data() == before, "Invalid height rejection is atomic")
	for schema in range(1, 6):
		var data := initial.duplicate(true)
		data.schema = schema
		for version in range(schema, 10):
			for key in ADDED_AFTER_SCHEMA[version]:
				data.erase(key)
		var before: Dictionary = tall.to_data()
		_check(not tall.load_data(data), "Out-of-range historical fill is rejected, not clamped")
		_check(tall.to_data() == before, "Historical rejection is atomic")
