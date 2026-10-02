extends SceneTree
## HAIR-01 diagnostic: distinguish particle, segment and skinned-surface coverage.
## Capsule overlap is NOT a triangle-mesh intersection or final visual acceptance.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const SAMPLES := 120
var _scene: Control
var _output: String
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	_scene = SCENE.instantiate()
	_scene.save_path = _output.path_join("unused.json")
	root.add_child(_scene)
	_scene.performance.automatic = false
	_scene.performance.set_process(false)
	_scene.state.blink = false
	_scene.state.hair_dynamic_enabled = true
	for action in 4:
		for wind in [0.0, 1.0]:
			for collision in [false, true]:
				await _sequence(action, wind, collision)
	var report := {
		"engine": Engine.get_version_info(),
		"scope": "Capsule coverage diagnostic, not triangle-mesh nonpenetration proof",
		"rows": _rows,
		"inputs": {}
	}
	for path in [
		"res://addons/npr_character_frame/runtime/animation/npr_hair_dynamics.gd",
		"res://addons/npr_character_frame/runtime/animation/npr_performance.gd",
		_scene.performance.dynamics.data_path,
		_scene.performance.performance_data_path,
		get_script().resource_path
	]:
		report.inputs[path] = FileAccess.get_sha256(path)
	FileAccess.open(_output.path_join("hair_clearance.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	_scene.free()
	await process_frame
	print("HAIR_CLEARANCE rows=", _rows.size())
	print("REGRESSION_OK")
	quit()


func _sequence(action: int, wind: float, collision: bool) -> void:
	var performance = _scene.performance
	performance.reset_simulation()
	_scene.state.action = action
	_scene.state.wind_strength = wind
	_scene.state.hair_collision_enabled = collision
	_scene._apply_state()
	var row := {
		"action": performance.ACTIONS[action],
		"wind": wind,
		"collision": collision,
		"node_overlap": 0.0,
		"segment_overlap": 0.0,
		"surface_overlap": 0.0,
		"new_surface_overlap": 0.0,
		"peak_sample": 0,
		"witness": {}
	}
	for sample in SAMPLES:
		performance.apply_pose(sample / 30.0, 1.0 / 30.0)
		var metrics := _measure()
		for key in ["node_overlap", "segment_overlap", "surface_overlap"]:
			row[key] = maxf(row[key], metrics[key])
		if metrics.new_surface_overlap > row.new_surface_overlap:
			row.new_surface_overlap = metrics.new_surface_overlap
			row.peak_sample = sample
			row.witness = metrics.witness
		if sample % 30 == 0:
			await process_frame
	_rows.append(row)
	if wind == 1.0:
		performance.reset_simulation()
		_scene.state.action = action
		_scene._apply_state()
		for sample in int(row.peak_sample) + 1:
			performance.apply_pose(sample / 30.0, 1.0 / 30.0)
		if action == 2 and collision:
			_dump_skin(float(row.peak_sample) / 30.0)
		var prefix := "%s_%s" % [row.action, "on" if collision else "off"]
		_scene.set_view("full")
		for angle in [0, 90, 180]:
			_scene.turntable.rotation_degrees.y = angle
			for mode in ["render", "white", "skeleton"]:
				_scene.display.set_mode(mode)
				await process_frame
				await RenderingServer.frame_post_draw
				await process_frame
				await RenderingServer.frame_post_draw
				_scene.viewport.get_texture().get_image().save_png(
					_output.path_join("%s_%d_%s.png" % [prefix, angle, mode])
				)
		_scene.display.set_mode("render")
		_scene.turntable.rotation = Vector3.ZERO


func _measure() -> Dictionary:
	var performance = _scene.performance
	var palette: Array[Transform3D] = performance._pose_palette
	var dynamics = performance.dynamics
	var colliders: Array[Dictionary] = []
	for collider: Dictionary in dynamics.data.colliders:
		var parent: Transform3D = palette[int(collider.parent)]
		colliders.append(
			{
				"start": parent * dynamics._vector(collider.start),
				"end": parent * dynamics._vector(collider.end),
				"radius": collider.radius,
				"name": collider.name
			}
		)
	var result := {
		"node_overlap": 0.0,
		"segment_overlap": 0.0,
		"surface_overlap": 0.0,
		"new_surface_overlap": 0.0,
		"witness": {}
	}
	for chain: Dictionary in dynamics.chains:
		for collider in colliders:
			var limit := float(collider.radius) + float(chain.source.radius)
			for index in range(1, chain.points.size()):
				var point: Vector3 = chain.points[index]
				var near := Geometry3D.get_closest_point_to_segment(
					point, collider.start, collider.end
				)
				result.node_overlap = maxf(result.node_overlap, limit - point.distance_to(near))
				var pair := Geometry3D.get_closest_points_between_segments(
					chain.points[index - 1], point, collider.start, collider.end
				)
				result.segment_overlap = maxf(
					result.segment_overlap, limit - pair[0].distance_to(pair[1])
				)
	for role in [0, 2]:
		var arrays: Array = performance._sources[role].mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var space: Transform3D = performance._spaces[role]
		for index: int in dynamics.weights[role]:
			var rest: Vector3 = space * vertices[index]
			var point := Vector3.ZERO
			var influences: Array = dynamics.weights[role][index]
			for slot in 4:
				point += (palette[bones[index * 4 + slot]] * rest) * weights[index * 4 + slot]
			var parent_index := 5 if role == 2 else 1
			var reference: Vector3 = palette[parent_index] * rest
			for collider in colliders:
				var radius := float(collider.radius)
				var near := Geometry3D.get_closest_point_to_segment(
					point, collider.start, collider.end
				)
				var base_near := Geometry3D.get_closest_point_to_segment(
					reference, collider.start, collider.end
				)
				var overlap := maxf(0.0, radius - point.distance_to(near))
				var base_overlap := maxf(0.0, radius - reference.distance_to(base_near))
				result.surface_overlap = maxf(result.surface_overlap, overlap)
				if overlap - base_overlap > result.new_surface_overlap:
					result.new_surface_overlap = overlap - base_overlap
					result.witness = {
						"role": role,
						"vertex": index,
						"collider": collider.name,
						"point": [point.x, point.y, point.z],
						"weights": influences
					}
	return result


func _dump_skin(time: float) -> void:
	var performance = _scene.performance
	var result := {
		"metadata":
		{
			"action": performance.action,
			"time": time,
			"wind": performance.wind_strength,
			"collision": performance.hair_collision_enabled,
			"reference": "Same-pose parent-bound positions; not previous-frame trajectories",
			"target": "Current production palette skin; face blend weights are zero"
		}
	}
	for role in 3:
		var arrays: Array = performance._sources[role].mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var positions: Array = []
		var reference: Array = []
		for index in vertices.size():
			var rest: Vector3 = performance._spaces[role] * vertices[index]
			var point := Vector3.ZERO
			for slot in 4:
				point += (
					(performance._pose_palette[bones[index * 4 + slot]] * rest)
					* weights[index * 4 + slot]
				)
			positions.append([point.x, point.y, point.z])
			var base: Vector3 = performance._pose_palette[5 if role == 2 else 1] * rest
			reference.append([base.x, base.y, base.z])
		result[str(role)] = {
			"vertices": positions,
			"reference": reference,
			"indices": Array(indices),
			"dynamic_indices": performance.dynamics.weights.get(role, {}).keys()
		}
	FileAccess.open(_output.path_join("skin_probe.json"), FileAccess.WRITE).store_string(
		JSON.stringify(result)
	)
