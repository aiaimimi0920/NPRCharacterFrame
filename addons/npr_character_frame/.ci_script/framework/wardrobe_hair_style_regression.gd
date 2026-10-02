extends "res://addons/npr_character_frame/.ci_script/framework/wardrobe_hair_clearance.gd"
## Art direction: rigid nape, flexible shaped tail, and small bidirectional bangs.

const PROFILE_PATH := (
	"res://addons/npr_character_frame/"
	+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/hair_motion_profile_v1.json"
)
var _checks: Array[Dictionary] = []
var _style_rows: Array[Dictionary] = []
var _zones: Dictionary
var _wind_references: Dictionary = {}


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	_scene = SCENE.instantiate()
	_scene.save_path = _output.path_join("unused.json")
	root.add_child(_scene)
	var performance = _scene.performance
	performance.automatic = false
	performance.set_process(false)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	_zones = {"nape": profile.static_zones[0].vertices}
	for name: String in profile.braid_probes:
		_zones["braid_" + name] = profile.braid_probes[name]
	_add_bangs_zones()
	_scene.state.blink = false
	_scene.state.hair_dynamic_enabled = true
	_scene.state.hair_collision_enabled = true
	_scene.set_view("face")
	_scene.turntable.rotation_degrees.y = 180
	for wind in [0.0, 1.0]:
		for action in 4:
			performance.reset_simulation()
			_scene.state.action = action
			_scene.state.wind_strength = wind
			_scene._apply_state()
			var arrays: Array = performance._sources[2].mesh.surface_get_arrays(0)
			var metrics := {}
			for name: String in _zones:
				metrics[name] = {
					"sum2": 0.0,
					"count": 0,
					"maximum": 0.0,
					"wind_min": [0.0, 0.0, 0.0],
					"wind_max": [0.0, 0.0, 0.0]
				}
			for frame in 120:
				performance.apply_pose(frame / 30.0, 1.0 / 30.0)
				_measure_style(arrays, metrics, action, wind, frame)
				if wind == 1.0 and action in [0, 2] and frame in [30, 60, 90]:
					await process_frame
					await RenderingServer.frame_post_draw
					_scene.viewport.get_texture().get_image().save_png(
						_output.path_join("%s_back_%d.png" % [performance.action, frame])
					)
					for angle in [0, 45, -45]:
						_scene.turntable.rotation_degrees.y = angle
						await process_frame
						await RenderingServer.frame_post_draw
						_scene.viewport.get_texture().get_image().save_png(
							_output.path_join(
								"%s_bangs_%d_%d.png" % [performance.action, angle, frame]
							)
						)
					_scene.turntable.rotation_degrees.y = 180
			for name: String in metrics:
				metrics[name]["rms"] = sqrt(metrics[name].sum2 / metrics[name].count)
				if name.begins_with("bangs."):
					_check_bangs(name, metrics[name], performance.action, wind)
			_style_rows.append({"action": action, "wind": wind, "metrics": metrics})
			_checks.append(
				{
					"name": "%s wind %s nape follows head rigidly" % [performance.action, wind],
					"pass": metrics.nape.maximum < 0.00001,
					"maximum_m": metrics.nape.maximum
				}
			)
			if wind == 1.0:
				_checks.append(
					{
						"name": performance.action + " shaped braid lower end remains free",
						"pass":
						(
							metrics.braid_tip.rms > 0.005
							and metrics.braid_tip.rms > metrics.braid_middle.rms * 1.5
							and metrics.braid_tip.rms > metrics.braid_upper.rms * 3.0
							and metrics.braid_upper.maximum < 0.008
						),
						"upper_rms_m": metrics.braid_upper.rms,
						"middle_rms_m": metrics.braid_middle.rms,
						"tip_rms_m": metrics.braid_tip.rms
					}
				)
	var report := {
		"checks": _checks,
		"rows": _style_rows,
		"profile_sha256": FileAccess.get_sha256(PROFILE_PATH),
		"asset_path": performance.dynamics.data_path,
		"asset_sha256": FileAccess.get_sha256(performance.dynamics.data_path),
		"engine": Engine.get_version_info()
	}
	FileAccess.open(_output.path_join("hair_style.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	var failed := _checks.any(func(row: Dictionary): return not row.pass)
	_scene.free()
	await process_frame
	print(
		"HAIR_STYLE checks=",
		_checks.size(),
		" failures=",
		_checks.filter(func(row: Dictionary): return not row.pass).size()
	)
	print("REGRESSION_FAILED" if failed else "REGRESSION_OK")
	quit(1 if failed else 0)


func _measure_style(
	arrays: Array, metrics: Dictionary, action: int, wind: float, frame: int
) -> void:
	var performance = _scene.performance
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var space: Transform3D = performance._spaces[2]
	var parent: Transform3D = performance._pose_palette[5]
	for name: String in _zones:
		var key := "%d/%d/%s" % [action, frame, name]
		var baseline: PackedVector3Array = _wind_references.get(key, PackedVector3Array())
		var slot_index := 0
		for value in _zones[name]:
			var index := int(value)
			var rest := space * vertices[index]
			var point := Vector3.ZERO
			var total := 0.0
			for slot in 4:
				var offset := index * 4 + slot
				point += (performance._pose_palette[bones[offset]] * rest) * weights[offset]
				total += weights[offset]
			var distance := point.distance_to((parent * rest) * total)
			metrics[name].sum2 += distance * distance
			metrics[name].count += 1
			metrics[name].maximum = maxf(metrics[name].maximum, distance)
			if name.begins_with("bangs."):
				var offset := parent.basis.inverse() * (point - (parent * rest) * total)
				if wind == 0.0:
					baseline.append(offset)
				else:
					var change := offset - baseline[slot_index]
					for axis in 3:
						metrics[name].wind_min[axis] = minf(
							metrics[name].wind_min[axis], change[axis]
						)
						metrics[name].wind_max[axis] = maxf(
							metrics[name].wind_max[axis], change[axis]
						)
				slot_index += 1
		if name.begins_with("bangs.") and wind == 0.0:
			_wind_references[key] = baseline


func _add_bangs_zones() -> void:
	var performance = _scene.performance
	var arrays: Array = performance._sources[2].mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for zone: Dictionary in performance.dynamics.data.dynamic_zones:
		if not zone.name.begins_with("bangs."):
			continue
		var low := INF
		var high := -INF
		for value in zone.vertices:
			var point: Vector3 = performance._spaces[2] * vertices[int(value)]
			low = minf(low, point.y)
			high = maxf(high, point.y)
		_zones[zone.name + "_root"] = []
		_zones[zone.name + "_tip"] = []
		for value in zone.vertices:
			var point: Vector3 = performance._spaces[2] * vertices[int(value)]
			if point.y >= high - 0.035:
				_zones[zone.name + "_root"].append(int(value))
			if point.y <= low + 0.055:
				_zones[zone.name + "_tip"].append(int(value))


func _check_bangs(name: String, metrics: Dictionary, action: String, wind: float) -> void:
	if name.ends_with("_root"):
		_checks.append(
			{
				"name": "%s wind %s %s remains attached" % [action, wind, name],
				"pass": metrics.count > 0 and metrics.maximum < 0.00001,
				"maximum_m": metrics.maximum
			}
		)
	elif wind == 1.0:
		var lateral: float = metrics.wind_max[0] - metrics.wind_min[0]
		var forward: float = metrics.wind_max[2] - metrics.wind_min[2]
		_checks.append(
			{
				"name": "%s %s small wind movement in both head-local axes" % [action, name],
				"pass": lateral > 0.001 and forward > 0.0004 and metrics.maximum < 0.012,
				"lateral_span_m": lateral,
				"forward_span_m": forward,
				"maximum_m": metrics.maximum
			}
		)
