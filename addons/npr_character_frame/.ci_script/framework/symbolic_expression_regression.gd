extends "res://addons/npr_character_frame/.ci_script/framework/hosiery_lookdev.gd"
const SAMPLE_HEIGHT_PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/showcase_height.tres"
)
const SAMPLE_PALETTE_PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/showcase_palette.tres"
)

## Real scene, UI callbacks, persistence and deterministic rendered expression evidence.


func _run() -> void:
	_spawn()
	await _capture("neutral")
	var before: Dictionary = _wardrobe.state.to_data()
	for mode in range(1, 5):
		var picker := _wardrobe._content.find_child("EyeSymbolMode", true, false) as OptionButton
		picker.select(mode)
		picker.item_selected.emit(mode)
		_check(_wardrobe.state.eye_symbol == mode, "Actual picker applies mode %d" % mode)
		_check(_wardrobe.performance.symbolic_eyes, "Symbol mode overrides evaluated blink")
		_check(_wardrobe.state.blink == before.blink, "Blink preference preserved")
		_check(_wardrobe.state.eye_left == before.eye_left, "Gaze preference preserved")
		await _capture("symbol_%d" % mode)
	_wardrobe.state.eye_symbol = 1
	_wardrobe.state.eye_symbol_size = 1.2
	_wardrobe.state.eye_symbol_stroke = 0.18
	_wardrobe._changed()
	await _capture("large_thick")
	_wardrobe.state.eye_symbol_size = 0.65
	_wardrobe.state.eye_symbol_stroke = 0.05
	_wardrobe._changed()
	await _capture("small_thin")
	_wardrobe.state.eye_symbol_size = 1.0
	_wardrobe.state.eye_symbol_stroke = 0.1
	_wardrobe._changed()
	_wardrobe.performance.action = "look_around"
	_wardrobe.performance.apply_pose(1.0)
	await _capture("head_motion")
	_wardrobe.performance.action = "idle"
	_wardrobe.performance.apply_pose(0.0)
	for angle in [-35, 35, 90, 180]:
		_wardrobe.turntable.rotation_degrees.y = angle
		await _capture("angle_%d" % angle)
	_wardrobe.turntable.rotation_degrees.y = 0
	var saved: Dictionary = _wardrobe.state.to_data()
	_wardrobe.save_scheme()
	_wardrobe.free()
	_spawn()
	_check(_wardrobe.state.to_data() == saved, "Real file survives scene reconstruction")
	await _capture("reconstructed")
	_wardrobe.state.eye_symbol = 0
	_wardrobe._changed()
	await _capture("restored")
	_check(_wardrobe.state.to_data() == before, "Off preserves all original preferences")
	var old: Dictionary = before.duplicate(true)
	old.schema = 8
	for key in ["eye_symbol", "eye_symbol_size", "eye_symbol_stroke"]:
		old.erase(key)
	var migrated = _wardrobe.STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
	_check(migrated.load_data(old), "V1.2 schema migrates")
	_check(migrated.eye_symbol == 0, "Old schemes default to original eyes")
	for entry in [
		["eye_symbol", 5],
		["eye_symbol", 1.5],
		["eye_symbol_size", NAN],
		["eye_symbol_size", 0.1],
		["eye_symbol_stroke", 0.4]
	]:
		var bad: Dictionary = before.duplicate(true)
		bad[entry[0]] = entry[1]
		_check(not _wardrobe.state.load_data(bad), "Reject invalid " + str(entry))
		_check(_wardrobe.state.to_data() == before, "Invalid load is atomic")
	await _pages()
	_wardrobe.reset_scheme()
	_check(_wardrobe.state.eye_symbol == 0, "Scheme reset restores original eyes")
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "captures": _captures}, "  ")
	)
	_wardrobe.free()
	print("SYMBOL_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _spawn() -> void:
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("scheme.json")
	root.add_child(_wardrobe)
	_wardrobe.performance.automatic = false
	_wardrobe.performance.set_process(false)
	_wardrobe.state.blink = false
	_wardrobe.state.secondary = false
	_wardrobe._apply_state()
	_wardrobe.performance.apply_pose(0.0)
	_wardrobe.set_view("face")
	_wardrobe.select_section(6)


func _pages() -> void:
	var required := {
		0: ["EquipmentSlot0", "EquipmentSlot3"],
		1: ["StockingTransparency", "HosieryStyle2", "TulleGeometryEnabled"],
		2: ["HairDynamicEnabled", "HairCollisionEnabled"],
		3: ["DropletsEnabled", "DropletPreviewPause"],
		4: ["ShadowEnabled", "FillEnabled"],
		5: ["Action0", "SoftPressureView"],
		6: ["EyeSymbolMode", "EyeControlTarget", "SpeechDemo"]
	}
	var camera_before: Transform3D = _wardrobe.camera.transform
	var saved: Dictionary = _wardrobe.state.to_data()
	for size in [Vector2i(1440, 900), Vector2i(1152, 720)]:
		root.size = size
		for page: int in required:
			_wardrobe.select_section(page)
			await _frames(3)
			for id: String in required[page]:
				var widget: Control = _wardrobe._content.find_child(id, true, false)
				_check(widget != null, "Page %d contains %s" % [page, id])
				if widget != null:
					_wardrobe._options_scroll.ensure_control_visible(widget)
					await _frames(2)
					_check(
						_wardrobe._options_scroll.get_global_rect().intersects(
							widget.get_global_rect()
						),
						"Scrollable control reachable %s at %s" % [id, size]
					)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				_output.path_join("ui_%d_%d.png" % [size.x, page])
			)
	_check(_wardrobe.camera.transform == camera_before, "Categories preserve camera framing")
	_check(_wardrobe.state.to_data() == saved, "Categories preserve scheme values")
