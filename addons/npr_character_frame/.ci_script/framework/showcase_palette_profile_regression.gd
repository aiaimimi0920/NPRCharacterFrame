extends "palette_contract_regression.gd"
## Alternate author inputs use the real showcase without changing sample/save contracts.

const PROFILE = preload("res://addons/npr_character_frame/npr_showcase_palette_profile.gd")


func _run() -> void:
	_profile_contract()
	root.mouse_passthrough = true
	root.unfocusable = true
	var authored := _alternate()
	await _spawn_profile(authored)
	var initial: Dictionary = _wardrobe.state.to_data()
	_check(initial.palette == 1, "Initial state uses authored default index")
	_check(initial.colors == ["226688", "884422", "ddeeff"], "Initial authored RGB")
	_check(_wardrobe._palettes.size() == 3, "UI uses authored slot count")
	for index in 3:
		var button = _wardrobe.find_child("Palette%d" % index, true, false)
		_check(button.caption == authored.labels[index], "Authored UI label %d" % index)
		_check(button.palette_colors == authored.colors_at(index), "Authored swatches %d" % index)
	await _snapshot("authored_initial")
	await _press("Palette0")
	_check(_mix() == 0.0, "Alternate original slot still disables dye")
	await _snapshot("authored_original")
	_check(
		_palette_images.authored_initial != _palette_images.authored_original,
		"Alternate palette affects actual GPU pixels"
	)
	await _press("Palette2")
	_check(_wardrobe.state.palette == 2, "Actual button selects alternate last slot")
	_check(_wardrobe.state.colors == authored.colors_at(2), "Actual button applies alternate RGB")
	var payload: Dictionary = _wardrobe.state.to_data()
	payload.colors = ["123456", "abcdef", "654321"]
	_check(_wardrobe.state.load_data(payload), "Alternate profile accepts saved RGB snapshot")
	_wardrobe._apply_state()
	_wardrobe.save_scheme()
	var saved := FileAccess.get_file_as_bytes(_wardrobe.save_path)
	_wardrobe.configure_save_path(_wardrobe.save_path)
	_check(_wardrobe.state.to_data() == payload, "Path reload does not recompute palette RGB")
	_wardrobe.save_scheme()
	_check(saved == FileAccess.get_file_as_bytes(_wardrobe.save_path), "Alternate save round trip")
	# Mutate the source after entry, including shape: live/reset/load must retain the snapshot.
	authored.labels = PackedStringArray(["Changed source"])
	authored.rgb = PackedStringArray(["ff0000", "00ff00", "0000ff"])
	authored.default_index = 0
	await _press("Reset")
	_check(_wardrobe.state.to_data() == initial, "Reset retains entry-time authored defaults")
	_check(_wardrobe._palettes.size() == 3, "Rebuilt UI retains entry-time slot count")
	_check(_wardrobe._palettes[1].caption == "海铜", "Rebuilt UI retains entry-time label")
	await _snapshot("authored_reset")
	_check(
		_palette_images.authored_initial == _palette_images.authored_reset,
		"Reset restores exact authored GPU pixels"
	)
	_wardrobe.configure_save_path(_output.path_join("missing_scheme.json"))
	_check(_wardrobe.state.to_data() == initial, "Missing-path defaults retain entry snapshot")
	_wardrobe.configure_save_path(_output.path_join("authored_scheme.json"))
	_check(_wardrobe.state.to_data() == payload, "Existing-path load retains original slot range")
	_wardrobe.free()
	await _spawn_profile(_alternate())
	_check(_wardrobe.state.to_data() == payload, "Fresh scene restores authored saved snapshot")
	await _press("Reset")
	await _snapshot("authored_recreated")
	_check(
		_palette_images.authored_initial == _palette_images.authored_recreated,
		"Fresh authored instance restores exact GPU pixels"
	)
	_wardrobe.free()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	(
		FileAccess
		. open(_output.path_join("showcase_palette_profile.json"), FileAccess.WRITE)
		. store_string(JSON.stringify({"checks": _checks, "images": _palette_images}, "  "))
	)
	print("SHOWCASE_PALETTE_PROFILE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)


func _alternate() -> NPRShowcasePaletteProfile:
	var profile := PROFILE.new()
	profile.labels = PackedStringArray(["原材质", "海铜", "紫绿"])
	profile.rgb = PackedStringArray(
		["112233", "445566", "778899", "226688", "884422", "ddeeff", "553388", "228844", "eeddaa"]
	)
	profile.default_index = 1
	return profile


func _spawn_profile(profile: NPRShowcasePaletteProfile) -> void:
	_wardrobe = SCENE.instantiate()
	_wardrobe.character_definition = _wardrobe.character_definition.duplicate()
	_wardrobe.character_definition.showcase_palette_profile = profile
	_wardrobe.save_path = _output.path_join("authored_scheme.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	_wardrobe.visual_layers.set_process(false)
	_wardrobe.performance.apply_pose(0.0, 0.1)
	await _frames(5)


func _profile_contract() -> void:
	_check(SAMPLE_PALETTE_PROFILE.validate().is_empty(), "Sample author profile validates")
	_check(not PROFILE.new().validate().is_empty(), "Empty profile has no sample fallback")
	for entry in [
		["labels", PackedStringArray()],
		["labels", PackedStringArray(["原材质", " ", "紫绿"])],
		["rgb", PackedStringArray(["ffffff"])],
		["default_index", -1],
		["default_index", 3]
	]:
		var invalid := _alternate()
		invalid.set(entry[0], entry[1])
		_check(not invalid.validate().is_empty(), "Reject malformed profile " + str(entry))
	for value in ["", "#ffffff", "ffffff00", "fff", "gggggg", "ffffff\n"]:
		var invalid := _alternate()
		invalid.rgb[0] = value
		_check(not invalid.validate().is_empty(), "Reject invalid authored RGB " + value)
	var candidate := SCENE.instantiate()
	var definition: NPRCharacterDefinition = candidate.character_definition.duplicate()
	definition.showcase_palette_profile = null
	candidate.character_definition = definition
	_check(definition.validate().is_empty(), "Base rendering permits omitted palette profile")
	_check(
		"Full showcase requires showcase_palette_profile" in candidate._configuration_errors(),
		"Showcase rejects missing profile before assembly"
	)
	definition.showcase_palette_profile = PROFILE.new()
	_check(not definition.validate().is_empty(), "Definition propagates invalid palette")
	candidate.free()
	var profile := _alternate()
	var first = STATE.new("review_actor", profile, SAMPLE_HEIGHT_PROFILE)
	var second = STATE.new("review_actor", profile, SAMPLE_HEIGHT_PROFILE)
	var defaults: Dictionary = first.to_data()
	profile.rgb[3] = "ff0000"
	profile.labels.resize(1)
	profile.default_index = 0
	first.select_palette(1)
	_check(first.to_data() == defaults, "State owns a deep profile snapshot")
	first.colors[0] = Color.RED
	_check(second.to_data() == defaults, "State colors are instance-local")
	second.select_palette(99)
	_check(second.palette == 2, "Selection clamps to instance slot range")
	second.select_palette(-1)
	_check(second.palette == 0, "Negative selection still means original, not custom")
	var invalid := defaults.duplicate(true)
	invalid.palette = 3
	var previous: Dictionary = second.to_data()
	_check(not second.load_data(invalid), "Load rejects absent slot without clamping")
	_check(second.to_data() == previous, "Rejected slot preserves entire previous state")
	for schema in range(1, 10):
		var legacy := defaults.duplicate(true)
		legacy.schema = schema
		legacy.palette = -1
		legacy.colors = ["123456", "abcdef", "654321"]
		for version in range(schema, 10):
			for key in ADDED_AFTER_SCHEMA[version]:
				legacy.erase(key)
		var target = STATE.new("review_actor", _alternate(), SAMPLE_HEIGHT_PROFILE)
		var expected := defaults.duplicate(true)
		expected.palette = -1
		expected.colors = legacy.colors.duplicate()
		_check(target.load_data(legacy), "Alternate legacy schema loads %d" % schema)
		_check(target.to_data() == expected, "Historical migration defaults preserved %d" % schema)
