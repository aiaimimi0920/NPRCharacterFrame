extends "wardrobe_regression.gd"
## Pin the shipped sample/save contract before extracting authored palette inputs.

const SAMPLE_PALETTES := [
	["原色", "7772c9", "303041", "e6e8ee"],
	["霜蓝", "638aa6", "28394d", "e8eff3"],
	["绯红", "9d4759", "302633", "e9dce1"],
	["薄荷", "54958e", "283e43", "e6eee8"],
	["暮金", "a98d50", "34323e", "eae3d2"],
	["夜紫", "7861aa", "262437", "dcd9ec"],
	["樱雪", "c588a7", "514151", "f0e5eb"],
]
const ADDED_AFTER_SCHEMA := {
	1: ["equipment", "action", "blink", "secondary"],
	2:
	[
		"hosiery_style",
		"hosiery_stitch",
		"wetness_regions",
		"eye_wetness",
		"wind_strength",
		"soft_tissue_pressure"
	],
	3:
	[
		"droplets_enabled",
		"droplet_count",
		"droplet_speed",
		"droplet_seed",
		"tulle_geometry_enabled",
		"eye_geometry_enabled"
	],
	4: ["hair_dynamic_enabled", "hair_collision_enabled", "authored_materials_enabled"],
	5: ["hosiery_height"],
	6: ["hosiery_sheen", "hosiery_weave", "hosiery_roughness"],
	7: ["eye_left", "eye_right"],
	8: ["eye_symbol", "eye_symbol_size", "eye_symbol_stroke"],
	9: ["mouth_symbol", "mouth_symbol_size", "mouth_symbol_stroke"],
}
var _palette_images: Dictionary = {}
var _palette_observations: Dictionary = {}


func _run() -> void:
	_state_contract()
	root.mouse_passthrough = true
	root.unfocusable = true
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("palette_scheme.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	_wardrobe.visual_layers.set_process(false)
	_wardrobe.performance.apply_pose(0.0, 0.1)
	await _frames(5)
	var initial: Dictionary = _wardrobe.state.to_data()
	await _snapshot("initial")
	for index in SAMPLE_PALETTES.size():
		var button: Button = _wardrobe.find_child("Palette%d" % index, true, false)
		_check(button.get("caption") == SAMPLE_PALETTES[index][0], "Authored label %d" % index)
		await _press("Palette%d" % index)
		_check(_wardrobe.state.palette == index, "Real button selects %d" % index)
		_check(
			_wardrobe.state.to_data().colors == SAMPLE_PALETTES[index].slice(1),
			"Selected RGB %d" % index
		)
		_check(_mix() == (0.0 if index == 0 else 1.0), "Material dye gate %d" % index)
		await _snapshot("palette%d" % index)
		_check(
			(
				_palette_images["palette%d" % index] != _palette_images.initial
				if index > 0
				else _palette_images.palette0 == _palette_images.initial
			),
			"Actual GPU palette %d" % index
		)
	await _loaded_color_contract()
	await _custom_selection_contract()
	await _press("Reset")
	_check(_wardrobe.state.to_data() == initial, "Reset restores all shipped defaults")
	_wardrobe.save_scheme()
	var bytes := FileAccess.get_file_as_bytes(_wardrobe.save_path)
	_wardrobe.configure_save_path(_wardrobe.save_path)
	_wardrobe.save_scheme()
	_check(
		FileAccess.get_file_as_bytes(_wardrobe.save_path) == bytes,
		"Ready path reload preserves saved bytes"
	)
	_wardrobe.free()
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("palette_scheme.json")
	root.add_child(_wardrobe)
	_capture_clock.bind(_wardrobe.performance)
	_check(_wardrobe.state.to_data() == initial, "Fresh scene loads all saved defaults")
	_wardrobe.free()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("palette_contract.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"checks": _checks,
				"images": _palette_images,
				"defaults": initial,
				"observations": _palette_observations
			},
			"  "
		)
	)
	print("PALETTE_CONTRACT_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)


func _state_contract() -> void:
	var defaults = STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
	var original: Dictionary = defaults.to_data()
	var fixture: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			(
				"res://addons/npr_character_frame/.ci_script/framework/fixtures/"
				+ "silver_wolf_schema10_defaults.json"
			)
		)
	)
	var fixture_path := (
		"res://addons/npr_character_frame/.ci_script/framework/fixtures/"
		+ "silver_wolf_schema10_defaults.json"
	)
	_check(
		(
			JSON.stringify(original, "  ", true, true).to_utf8_buffer()
			== FileAccess.get_file_as_bytes(fixture_path)
		),
		"All default disk bytes match the shipped 1.3.0.55 saved fixture"
	)
	var fixture_state = STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
	_check(fixture_state.load_data(fixture), "Shipped default fixture loads")
	_check(
		fixture_state.to_data() == original, "Shipped default fixture restores all runtime values"
	)
	_check(original.schema == 10 and original.palette == 0, "Schema and original sentinel")
	_check(original.colors == SAMPLE_PALETTES[0].slice(1), "Default RGB snapshot")
	for index in SAMPLE_PALETTES.size():
		var state = STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
		state.select_palette(index)
		_check(
			state.to_data().colors == SAMPLE_PALETTES[index].slice(1),
			"Preset order and RGB %d" % index
		)
		var restored = STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
		_check(
			restored.load_data(JSON.parse_string(JSON.stringify(state.to_data()))),
			"Preset JSON accepted %d" % index
		)
		_check(restored.to_data() == state.to_data(), "Preset JSON round trip %d" % index)
	defaults.select_palette(-1)
	_check(defaults.palette == 0, "Selection API clamps negative to original, not custom")
	defaults.select_palette(99)
	_check(defaults.palette == 6, "Selection API clamps high indices")
	_check(
		(
			STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE).to_data()
			== original
		),
		"State instances do not share mutable choices"
	)
	for schema in range(1, 10):
		var legacy := original.duplicate(true)
		legacy.schema = schema
		legacy.palette = -1
		legacy.colors = ["123456", "abcdef", "654321"]
		for version in range(schema, 10):
			for key in ADDED_AFTER_SCHEMA[version]:
				legacy.erase(key)
		var source := legacy.duplicate(true)
		var target = STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
		_check(target.load_data(legacy), "Legacy schema %d loads" % schema)
		var expected := original.duplicate(true)
		expected.palette = -1
		expected.colors = legacy.colors.duplicate()
		_check(
			target.to_data() == expected,
			"Legacy schema %d preserves custom RGB and fills defaults" % schema
		)
		_check(legacy == source, "Legacy schema %d does not mutate caller data" % schema)
	for entry in [
		["palette", -2],
		["palette", 7],
		["palette", 0.5],
		["palette", NAN],
		["colors", ["bad", "123456", "abcdef"]],
		["colors", ["123456"]],
		["character", "another_actor"],
		["schema", 11]
	]:
		var invalid := original.duplicate(true)
		invalid[entry[0]] = entry[1]
		var target = STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
		target.select_palette(4)
		var before: Dictionary = target.to_data()
		_check(not target.load_data(invalid), "Reject invalid palette payload " + str(entry))
		_check(
			target.to_data() == before, "Rejected payload preserves previous state " + str(entry)
		)


func _loaded_color_contract() -> void:
	var payload: Dictionary = _wardrobe.state.to_data()
	payload.palette = 0
	payload.colors = ["ff0000", "00ff00", "0000ff"]
	_check(_wardrobe.state.load_data(payload), "Original sentinel permits stored RGB snapshot")
	_wardrobe._apply_state()
	_check(_mix() == 0.0, "Original sentinel disables dye regardless of stored RGB")
	await _snapshot("original_custom_rgb")
	_check(
		_palette_images.original_custom_rgb == _palette_images.initial,
		"Original sentinel preserves exact production pixels"
	)
	# Negative control: reproduce an accidental dye-enabled original slot on the GPU.
	_wardrobe.preview.materials[0].set_shader_parameter("u_npr_garment_mix", 1.0)
	await _snapshot("negative_original_dyed")
	_check(
		_palette_images.negative_original_dyed != _palette_images.initial,
		"GPU negative control detects dye accidentally enabled on the original slot"
	)
	_wardrobe._apply_state()
	await _snapshot("negative_restored")
	_check(
		_palette_images.negative_restored == _palette_images.initial,
		"GPU negative control restores exact original pixels"
	)
	for index in [2, -1]:
		payload.palette = index
		_check(_wardrobe.state.load_data(payload), "Load explicit RGB with sentinel %d" % index)
		_wardrobe._apply_state()
		_check(
			_wardrobe.state.to_data().colors == payload.colors,
			"Stored RGB is authoritative %d" % index
		)
		_check(_mix() == 1.0, "Nonzero palette enables dye %d" % index)
		await _snapshot("stored_rgb_%d" % index)
	_check(
		_palette_images["stored_rgb_2"] == _palette_images["stored_rgb_-1"],
		"Preset index does not override stored RGB on load"
	)
	_check(
		_palette_images["stored_rgb_-1"] != _palette_images.initial,
		"Custom RGB actually changes GPU pixels"
	)
	_wardrobe._color_changed(Color("abcdef"), 1)
	var selected: Array[int] = []
	for index in _wardrobe._palettes.size():
		if _wardrobe._palettes[index].button_pressed:
			selected.append(index)
	_palette_observations["custom_color_selected_buttons"] = selected
	_check(_wardrobe.state.palette == -1, "Color picker handler selects custom sentinel")
	_check(
		_wardrobe.state.to_data().colors == ["ff0000", "abcdef", "0000ff"],
		"Color picker changes only its channel"
	)
	_wardrobe.save_scheme()
	var expected: Dictionary = _wardrobe.state.to_data()
	var saved := FileAccess.get_file_as_bytes(_wardrobe.save_path)
	_wardrobe.configure_save_path(_wardrobe.save_path)
	_check(_wardrobe.state.to_data() == expected, "Custom scheme reload preserves all fields")
	_wardrobe.save_scheme()
	_check(
		FileAccess.get_file_as_bytes(_wardrobe.save_path) == saved,
		"Custom scheme round trip preserves disk bytes"
	)


func _mix() -> float:
	return float(_wardrobe.preview.materials[0].get_shader_parameter("u_npr_garment_mix"))


func _custom_selection_contract() -> void:
	for channel in 3:
		await _press("Palette2")
		var previous_colors: Array = _wardrobe.state.to_data().colors.duplicate()
		var notifications := [0]
		var record_press := func(): notifications[0] += 1
		for button in _wardrobe._palettes:
			button.pressed.connect(record_press)
		_wardrobe._colors[channel].color_changed.emit(Color("abcdef"))
		_check(_wardrobe.state.palette == -1, "Picker signal selects custom channel %d" % channel)
		previous_colors[channel] = "abcdef"
		_check(
			_wardrobe.state.to_data().colors == previous_colors,
			"Picker preserves other channels %d" % channel
		)
		_check(
			_wardrobe._palettes.all(func(button: Button): return not button.button_pressed),
			"Custom edit clears all preset highlights %d" % channel
		)
		_check(notifications[0] == 0, "Clearing highlights emits no preset actions %d" % channel)
		for button in _wardrobe._palettes:
			button.pressed.disconnect(record_press)
		_wardrobe.select_section(0)
		await _frames(3)
		_check(
			_wardrobe._palettes.all(func(button: Button): return not button.button_pressed),
			"Custom highlight stays clear after page rebuild %d" % channel
		)
	await _press("Palette4")
	_check(
		_wardrobe.state.palette == 4 and _wardrobe._palettes[4].button_pressed,
		"Preset remains selectable after custom editing"
	)
	_check(
		_wardrobe.state.to_data().colors == SAMPLE_PALETTES[4].slice(1),
		"Reselecting preset restores authored RGB"
	)


func _frames(count: int) -> void:
	# A single evaluated neutral pose; these waits do not advance the simulation.
	for index in count:
		await process_frame


func _snapshot(label: String) -> void:
	CAPTURE_POINTER.park(root)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := _output.path_join(label + ".png")
	var image: Image = _wardrobe.viewport.get_texture().get_image()
	_check(image.save_png(path) == OK, label + " GPU capture saved")
	_palette_images[label] = FileAccess.get_sha256(path)
