extends "res://addons/npr_character_frame/.ci_script/framework/wardrobe_display_regression.gd"
## Verify renderer state, cross-page values and stable per-control defaults.


func _run() -> void:
	root.size = Vector2i(1440, 900)
	_spawn()
	await _frames()
	_wardrobe.select_section(7)
	await _frames()
	var shader: ShaderMaterial = _wardrobe.preview.materials[2]
	var slider: HSlider = _wardrobe.find_child("Debug发丝高光", true, false)
	_check(
		is_equal_approx(
			slider.value, float(shader.get_shader_parameter("u_hair_highlight_strength"))
		),
		"Hair slider reads the actual renderer value"
	)
	slider.value = 0.67
	_wardrobe.select_section(0)
	_wardrobe.select_section(7)
	await _frames()
	slider = _wardrobe.find_child("Debug发丝高光", true, false)
	_check(is_equal_approx(slider.value, 0.67), "Hair slider retains edited value across pages")
	var wind: HSlider = _wardrobe.find_child("Debug风场强度", true, false)
	wind.value = 0.73
	_wardrobe.select_section(0)
	_wardrobe.select_section(7)
	await _frames()
	await _press("Reset风场强度")
	_check(
		is_zero_approx(_wardrobe.state.wind_strength),
		"Individual reset restores factory wind after page rebuild"
	)
	_wardrobe.reset_scheme()
	_check(
		is_zero_approx(float(shader.get_shader_parameter("u_hair_highlight_strength"))),
		"Scheme reset restores temporary hair style"
	)
	await _capture("debug_reset")
	await _test_all_controls()
	await _test_saved_defaults()
	_finish()


func _test_all_controls() -> void:
	var baseline := await _capture("default_materials")
	var ids: Array[String] = []
	for slider: HSlider in _wardrobe._content.find_children("*", "HSlider", true, false):
		ids.append(str(slider.name))
	_check(ids.size() == 30, "All 30 debug sliders are covered")
	for id in ids:
		var slider: HSlider = _wardrobe.find_child(id, true, false)
		var original := slider.value
		var button: Button = slider.get_parent().get_child(1)
		var reset_id := str(button.name)
		var tooltip := button.tooltip_text
		slider.value = slider.min_value + (slider.max_value - slider.min_value) * 0.72
		var edited := slider.value
		_check(not is_equal_approx(original, edited), "Control changes: " + id)
		_wardrobe.select_section(0)
		_wardrobe.select_section(7)
		await _frames()
		slider = _wardrobe.find_child(id, true, false)
		button = _wardrobe.find_child(reset_id, true, false)
		_check(is_equal_approx(slider.value, edited), "Cross-page current value: " + id)
		_check(button.tooltip_text == tooltip, "Cross-page default remains immutable: " + id)
		await _press(reset_id)
		_check(is_equal_approx(slider.value, original), "Mouse reset restores factory value: " + id)
	var toggles: Array[String] = []
	for toggle: CheckButton in _wardrobe._content.find_children("*", "CheckButton", true, false):
		toggles.append(str(toggle.name))
	_check(toggles.size() == 8, "All eight supported debug toggles are covered")
	for id in toggles:
		var toggle: CheckButton = _wardrobe.find_child(id, true, false)
		var original := toggle.button_pressed
		var caption := toggle.text
		await _press(id)
		_check(toggle.button_pressed != original, "Mouse toggle changes state: " + id)
		_wardrobe.select_section(0)
		_wardrobe.select_section(7)
		await _frames()
		toggle = _wardrobe.find_child(id, true, false)
		_check(toggle.button_pressed != original, "Cross-page toggle current state: " + id)
		_check(toggle.text == caption, "Cross-page toggle default remains immutable: " + id)
		await _press(id)
	# A disabled/enabled shadow toggle resets strength to its documented on value.
	_wardrobe.reset_scheme()
	var restored := await _capture("all_controls_reset")
	_check(
		baseline.get_data() == restored.get_data(), "All debug edits reset to exact baseline pixels"
	)
	var fill: HSlider = _wardrobe.find_child("Debug补光", true, false)
	fill.value = 0.61
	var fill_toggle: CheckButton = _wardrobe.find_child("FillEnabled", true, false)
	_check(fill_toggle.button_pressed, "Fill slider immediately synchronizes paired toggle")
	await _press("FillEnabled")
	_check(is_zero_approx(fill.value), "Fill toggle immediately synchronizes paired slider")
	var framing := _camera_state()
	_wardrobe.reset_scheme()
	_check(_camera_state() == framing, "Debug reset preserves camera framing")


func _test_saved_defaults() -> void:
	await _frames()
	var wind: HSlider = _wardrobe.find_child("Debug风场强度", true, false)
	wind.value = 0.73
	var hair: HSlider = _wardrobe.find_child("Debug发丝高光", true, false)
	hair.value = 0.67
	_check(
		_wardrobe.find_child("EyeGeometryEnabled", true, false) == null,
		"Replacement eyes are not offered in the user interface"
	)
	var wet: HSlider = _wardrobe.find_child("Debug原眼湿润", true, false)
	wet.value = 0.65
	await _press("Save")
	var saved: Dictionary = _wardrobe.state.to_data()
	_wardrobe.free()
	await _frames()
	_spawn()
	await _frames()
	_wardrobe.select_section(7)
	await _frames()
	_check(_wardrobe.state.to_data() == saved, "Saved wardrobe state survives recreation")
	wind = _wardrobe.find_child("Debug风场强度", true, false)
	hair = _wardrobe.find_child("Debug发丝高光", true, false)
	_check(is_equal_approx(wind.value, 0.73), "Saved wind repopulates current value")
	_check(is_zero_approx(hair.value), "Temporary hair style is excluded from saved state")
	wet = _wardrobe.find_child("Debug原眼湿润", true, false)
	_check(
		is_equal_approx(wet.value, 0.65) and not _wardrobe.state.eye_geometry_enabled,
		"Saved wetness keeps the original model eyes"
	)
	await _press("Reset原眼湿润")
	_check(is_zero_approx(_wardrobe.state.eye_wetness), "Wetness reset restores original shading")
	await _press("Reset风场强度")
	_check(
		is_zero_approx(_wardrobe.state.wind_strength),
		"Saved wind does not become the reset default"
	)
	await _capture("saved_current_factory_default")
	_wardrobe.reset_scheme()
	_check(
		not _wardrobe.state.eye_geometry_enabled,
		"Scheme reset restores saved toggles to factory defaults"
	)
