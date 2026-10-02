extends "symbolic_expression_regression.gd"
## Real controller -> save file -> public loader -> recreated scene, including endpoints.


func _run() -> void:
	_spawn()
	var records: Array[Dictionary] = []
	for value in [1.0, 0.65, 1.35, 1.30]:
		_wardrobe.visual_layers.set_pupil_scale(value)
		_wardrobe.save_scheme()
		var file := FileAccess.get_file_as_string(_wardrobe.save_path)
		var disk: Dictionary = JSON.parse_string(file)
		_check(
			(
				disk.eye_left == _wardrobe.state.eye_left
				and disk.eye_right == _wardrobe.state.eye_right
			),
			"Real file retains controller pupil values at %s" % value
		)
		var restored = _wardrobe.STATE.new(
			"silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE
		)
		var accepted: bool = restored.load_data(disk)
		_check(accepted, "Actual saved pupil scale %s reloads" % value)
		_check(
			restored.eye_left == disk.eye_left and restored.eye_right == disk.eye_right,
			"Loaded pupil values are exact at %s" % value
		)
		_wardrobe.free()
		_spawn()
		for side in 2:
			var key := "eye_left" if side == 0 else "eye_right"
			_check(
				_wardrobe.visual_layers.eye_pupil_contract(side).scale == disk[key][2],
				"Recreated scene restores %s at %s" % [key, value]
			)
		records.append(
			{
				"requested": value,
				"left": disk.eye_left,
				"right": disk.eye_right,
				"load_accepted": accepted,
				"saved": disk
			}
		)
	_check_boundaries()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "records": records}, "  ", true, true)
	)
	_wardrobe.free()
	print("PUPIL_PERSISTENCE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _check_boundaries() -> void:
	var pupil_range := Vector2(0.65, 1.35)
	var minimum := minf(0.65, pupil_range.x)
	var maximum := maxf(1.35, pupil_range.y)
	for key in ["eye_left", "eye_right"]:
		for value in [0.65, 1.35, minimum, maximum, 0.73123456789]:
			var data: Dictionary = (
				_wardrobe
				. STATE
				. new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
				. to_data()
			)
			data[key] = [0.125, -0.25, value]
			var target = _wardrobe.STATE.new(
				"silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE
			)
			_check(target.load_data(data), "%s accepts exact endpoint/interior %s" % [key, value])
			_check(target.get(key) == data[key], "%s preserves input without rounding" % key)
		for value in [minimum - 1e-9, maximum + 1e-9, 0.64, 1.36, NAN, INF, -INF, "1.0", null]:
			var target = _wardrobe.STATE.new(
				"silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE
			)
			var before: Dictionary = target.to_data()
			var data: Dictionary = before.duplicate(true)
			data[key][2] = value
			_check(not target.load_data(data), "%s rejects invalid scale %s" % [key, value])
			_check(target.to_data() == before, "Rejected %s leaves state unchanged" % key)
	_wardrobe.visual_layers.set_pupil_scale(0.65, 0)
	_wardrobe.visual_layers.set_pupil_scale(1.35, 1)
	_wardrobe.save_scheme()
	var saved := FileAccess.get_file_as_string(_wardrobe.save_path)
	_wardrobe.free()
	_spawn()
	_check(
		(
			_wardrobe.visual_layers.eye_pupil_contract(0).scale == pupil_range.x
			and _wardrobe.visual_layers.eye_pupil_contract(1).scale == pupil_range.y
		),
		"Recreated scene preserves independent opposite endpoints"
	)
	_wardrobe.save_scheme()
	_check(
		FileAccess.get_file_as_string(_wardrobe.save_path) == saved,
		"Reload and save preserve all scheme bytes at opposite endpoints"
	)
