extends SceneTree
## Production corrective: actual deformed vertices/BVH, passes, images and lifecycle.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const GENERATION := (
	"res://addons/npr_character_frame/"
	+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/soft_tissue_generation.json"
)
var _scene: Control
var _body: MeshInstance3D
var _geometry: Node
var _output: String
var _checks: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _timings: Array[Dictionary] = []
var _domain: Dictionary = {}
var _rest := PackedVector3Array()


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_instantiate()
	var authored: Dictionary = _scene.preview.definition.load_soft_tissue_data()
	for row: Array in authored.deltas:
		_domain[int(row[0])] = true
	await _frames()
	_rest = _vertices()
	_check(_domain.size() >= 24, "Blender pressure asset has a nonempty local domain")
	_check_directions()
	for view in ["front", "side", "back", "full"]:
		_set_view(view)
		_set_pressure(0.0)
		await _capture(view + "_off")
		_set_pressure(0.5)
		await _capture(view + "_half")
		var half := _vertices()
		_set_pressure(1.0)
		await _capture(view + "_on")
		var full := _vertices()
		_check_geometry(half, full, authored, view)
		_set_pressure(0.0)
		await _capture(view + "_reset")
		_check(_vertices() == _rest, "Off restores exact deformed vertices: " + view)
	_set_pressure(1.0)
	await _frames()
	_check_picking()
	await _check_lifecycle()
	await _check_actions()
	await _check_negative()
	await _measure()
	# Save/reinstantiate the production scene with the same authored resource.
	_scene.state.soft_tissue_pressure = 0.75
	_scene.save_scheme()
	_scene.free()
	_instantiate()
	await _frames()
	_check(
		is_equal_approx(_body.get_blend_shape_value(0), 0.75),
		"Scene re-instantiation restores saved pressure on the authored shape"
	)
	_scene.reset_scheme()
	_scene.performance.apply_pose(0.0)
	await _frames()
	_check(_body.get_blend_shape_value(0) == 0.0, "Reset after reload returns neutral")
	var report := {
		"schema": 1,
		"engine": Engine.get_version_info(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [_scene.viewport.size.x, _scene.viewport.size.y],
		"asset_path": _scene.performance.soft_tissue_data_path,
		"asset_sha256": FileAccess.get_sha256(_scene.performance.soft_tissue_data_path),
		"generation_sha256": FileAccess.get_sha256(GENERATION),
		"checks": _checks,
		"captures": _captures,
		"timings": _timings,
		"domain_vertices": _domain.size(),
	}
	FileAccess.open(_output.path_join("soft_tissue.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	var failures := _checks.filter(func(check: Dictionary): return not check.pass).size()
	_scene.free()
	print("SOFT_TISSUE_CHECKS=", _checks.size(), " FAILURES=", failures)
	print("REGRESSION_OK" if failures == 0 else "REGRESSION_FAILED")
	quit(0 if failures == 0 else 1)


func _instantiate() -> void:
	_scene = SCENE.instantiate()
	_scene.save_path = _output.path_join("scheme.json")
	root.add_child(_scene)
	_scene.performance.automatic = false
	_scene.performance.set_process(false)
	_scene.performance.blink_weight = 0.0
	_scene.performance.apply_pose(0.0)
	_body = _scene.preview.meshes[0]
	_geometry = _body.get_node("NPRGeometryState")


func _set_pressure(value: float) -> void:
	_scene.state.soft_tissue_pressure = value
	_scene.performance.soft_tissue_pressure = value
	_scene.performance.apply_pose(0.0)


func _set_view(view: String) -> void:
	_scene.set_view("full")
	if view == "full":
		return
	var target := Vector3(-0.13, 1.295, 0.0)
	var offset: Vector3 = {
		"front": Vector3(0.0, 0.0, 1.10),
		"side": Vector3(-1.10, 0.0, 0.1),
		"back": Vector3(0.0, 0.0, -1.10)
	}[view]
	_scene.camera.h_offset = 0.0
	_scene.camera.position = target + offset
	_scene.camera.look_at(target)


func _vertices() -> PackedVector3Array:
	_geometry.refresh()
	var local: PackedVector3Array = _geometry._pick_vertices(_geometry._surface_snapshot(0))
	for index in local.size():
		local[index] = _body.global_transform * local[index]
	return local


func _check_geometry(
	half: PackedVector3Array, full: PackedVector3Array, authored: Dictionary, view: String
) -> void:
	var unchanged := true
	var linear := true
	var maximum := 0.0
	var changed := 0
	var collision_clearance := INF
	var center := Vector3(
		authored.collision.center[0], authored.collision.center[1], authored.collision.center[2]
	)
	for index in full.size():
		var delta := full[index] - _rest[index]
		maximum = maxf(maximum, delta.length())
		if not _domain.has(index):
			unchanged = unchanged and delta == Vector3.ZERO
		else:
			changed += 1 if delta.length() > 0.000001 else 0
			linear = (
				linear and half[index].distance_to(_rest[index].lerp(full[index], 0.5)) < 0.000002
			)
			var radial := Vector2(full[index].x - center.x, full[index].z - center.z)
			collision_clearance = minf(
				collision_clearance, radial.length() - authored.collision.radius
			)
	_check(unchanged, "Head, torso, hands and other leg vertices are unchanged: " + view)
	_check(
		changed >= 24 and maximum <= 0.00901,
		"Actual local position deformation is bounded: " + view
	)
	_check(linear, "Half pressure interpolates the actual deformed surface: " + view)
	_check(collision_clearance >= 0.00099, "Actual surface stays outside the rigid core: " + view)
	_check_proxies(view)


func _check_proxies(label: String) -> void:
	for proxy: MeshInstance3D in [
		_scene.preview.depth_pass.proxies[0], _body.get_node("ShadowCaster")
	]:
		_check(
			(
				proxy.mesh == _body.mesh
				and proxy.get_skin_reference() == _body.get_skin_reference()
				and proxy.get_blend_shape_value(0) == _body.get_blend_shape_value(0)
			),
			(
				"Depth/shadow share geometry, skin and current pressure: "
				+ label
				+ "/"
				+ str(proxy.name)
			)
		)


func _check_directions() -> void:
	var base: Array = _body.mesh.surface_get_arrays(0)
	var shape: Array = _body.mesh.surface_get_blend_shape_arrays(0)[0]
	var valid: bool = shape[Mesh.ARRAY_NORMAL].size() == _rest.size()
	valid = valid and shape[Mesh.ARRAY_TANGENT].size() == _rest.size() * 4
	for index in _rest.size():
		var normal: Vector3 = shape[Mesh.ARRAY_NORMAL][index]
		valid = valid and normal.is_finite() and normal.dot(base[Mesh.ARRAY_NORMAL][index]) > 0.999
	_check(valid, "Compressed corrective normals/tangents retain valid canonical directions")


func _check_picking() -> void:
	var full := _vertices()
	var indices: PackedInt32Array = _body.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var observed := false
	for at in range(0, indices.size(), 3):
		var a := indices[at]
		var b := indices[at + 1]
		var c := indices[at + 2]
		if not (_domain.has(a) and _domain.has(b) and _domain.has(c)):
			continue
		var point := (full[a] + full[b] + full[c]) / 3.0
		var origin := point + Vector3(0.0, 0.0, 0.25)
		var hit: Dictionary = _geometry.intersect_ray(origin, Vector3.FORWARD)
		if hit.is_empty() or hit.position.distance_to(point) > 0.0002:
			continue
		_set_pressure(0.0)
		var rest_hit: Dictionary = _geometry.intersect_ray(origin, Vector3.FORWARD)
		_set_pressure(1.0)
		if not rest_hit.is_empty() and rest_hit.position.distance_to(hit.position) > 0.001:
			observed = true
			break
	_check(observed, "Production BVH ray hits the pressure-deformed triangle, not the rest mesh")


func _check_lifecycle() -> void:
	var performance: Node = _scene.performance
	_set_pressure(1.0)
	var before := _vertices()
	performance.set_paused(true)
	performance.apply_pose(2.0, 0.1)
	_check(_vertices() == before, "Pause freezes shape and bone palette")
	performance.set_paused(false)
	performance.set_visual_quality(0)
	_check(_vertices() == _rest, "Performance LOD neutralizes the corrective")
	performance.set_visual_quality(1)
	_check(_vertices() == before, "Balanced LOD restores the current pressure without stale data")
	performance.set_visual_quality(2)
	_scene.preview.hide()
	performance._process(0.1)
	_check(_body.get_blend_shape_value(0) == 0.0, "Hidden actor clears the corrective")
	_scene.preview.show()
	performance.apply_pose(0.0)
	_check(_vertices() == before, "Showing the actor restores the current authored pose")
	_scene.state.equipment = [true, true, true, true]
	_scene._apply_state()
	performance.apply_pose(0.0)
	await _frames()
	var deltas: PackedVector3Array = _body.mesh.surface_get_blend_shape_arrays(0)[0][
		Mesh.ARRAY_VERTEX
	]
	var extras_zero := true
	for index in range(_rest.size(), deltas.size()):
		extras_zero = extras_zero and deltas[index] == Vector3.ZERO
	_check(
		extras_zero and deltas.size() > _rest.size(), "Equipment gets no soft-tissue displacement"
	)
	_check_proxies("equipment swap")
	_scene.reset_scheme()
	performance.apply_pose(0.0)
	await _frames()
	_check(_vertices() == _rest, "Reset removes equipment and restores geometry exactly")


func _check_actions() -> void:
	_set_view("full")
	for action: String in _scene.PERFORMANCE.ACTIONS:
		_scene.performance.action = action
		for pressure in [0.0, 1.0]:
			_scene.performance.soft_tissue_pressure = pressure
			_scene.performance.apply_pose(1.5)
			await _capture(action + ("_off" if pressure == 0.0 else "_on"))
			_check_proxies(action)
	_scene.performance.action = "idle"
	_set_pressure(0.0)


func _check_negative() -> void:
	_set_view("full")
	_set_pressure(0.0)
	await _capture("wrong_off")
	# Deliberately corrupt a COPY of the loaded asset in this test process only.
	# A broad torso displacement must be rejected by the fixed stocking ROI gate.
	var original: Array = _scene.performance._soft_data.deltas.duplicate(true)
	for index in _rest.size():
		if _rest[index].y > 2.0 and _rest[index].y < 2.16 and absf(_rest[index].x) < 0.2:
			_scene.performance._soft_data.deltas.append([index, 0.04, 0.0, 0.0])
	_body.mesh = _body.mesh.duplicate()
	_scene.performance.bind_mesh(0)
	_set_pressure(1.0)
	await _capture("wrong_domain")
	_scene.performance._soft_data.deltas = original
	_body.mesh = _body.mesh.duplicate()
	_scene.performance.bind_mesh(0)
	_set_pressure(0.0)


func _measure() -> void:
	var rid: RID = _scene.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for action: String in _scene.PERFORMANCE.ACTIONS:
		await _measure_action(action, rid)


func _measure_action(action: String, rid: RID) -> void:
	_scene.performance.action = action
	for pressure in [0.0, 1.0]:
		_scene.performance.reset_simulation()
		_scene.performance.soft_tissue_pressure = pressure
		var rows: Array[Dictionary] = []
		var previous_velocity := 0.0
		var peaks := Vector3.ZERO
		for frame in 180:
			await process_frame
			var started := Time.get_ticks_usec()
			_scene.performance.apply_pose(frame / 60.0, 1.0 / 60.0)
			var pose_us := Time.get_ticks_usec() - started
			var velocity: float = _scene.performance._velocity
			peaks.x = maxf(peaks.x, absf(_scene.performance._spring))
			peaks.y = maxf(peaks.y, absf(velocity))
			peaks.z = maxf(peaks.z, absf(velocity - previous_velocity) * 60.0)
			previous_velocity = velocity
			await RenderingServer.frame_post_draw
			if frame >= 60:
				(
					rows
					. append(
						{
							"pose_us": pose_us,
							"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid),
							"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
						}
					)
				)
		(
			_timings
			. append(
				{
					"action": action,
					"pressure": pressure,
					"warmup": 60,
					"samples": rows,
					"secondary_peaks": [peaks.x, peaks.y, peaks.z],
					"secondary_budgets": [0.008, 0.08, 0.75],
				}
			)
		)
		_check(
			peaks.x <= 0.008 and peaks.y <= 0.08 and peaks.z <= 0.75,
			"Secondary displacement/velocity/acceleration budget: " + action
		)
		_check(
			rows.all(func(row: Dictionary): return row.gpu_ms > 0.0 and is_finite(row.gpu_ms)),
			"Measured real GPU frame timings for pressure " + str(pressure)
		)


func _capture(label: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	var image: Image = _scene.viewport.get_texture().get_image()
	image.save_png(_output.path_join(label + ".png"))
	var depth: Image = _scene.preview.depth_pass.viewports[0].get_texture().get_image()
	FileAccess.open(_output.path_join(label + "_depth.bin"), FileAccess.WRITE).store_buffer(
		depth.get_data()
	)
	# Fixed world-space region, independent of the current shape/mutated test data.
	var roi := Rect2(_scene.camera.unproject_position(Vector3(-0.35, 1.13, -0.20)), Vector2.ZERO)
	for x in [-0.35, 0.05]:
		for y in [1.13, 1.46]:
			for z in [-0.20, 0.30]:
				roi = roi.expand(_scene.camera.unproject_position(Vector3(x, y, z)))
	(
		_captures
		. append(
			{
				"name": label,
				"roi": [roi.position.x, roi.position.y, roi.end.x, roi.end.y],
				"shadow_roi": _shadow_roi(),
				"camera_transform": str(_scene.camera.global_transform),
				"fov": _scene.camera.fov,
				"pressure": _body.get_blend_shape_value(0),
				"action": _scene.performance.action,
				"depth_size": [depth.get_width(), depth.get_height()],
				"depth_format": depth.get_format(),
				"depth_range": _scene.preview.depth_pass.depth_range,
				"depth_stride": depth.get_data().size() / (depth.get_width() * depth.get_height()),
			}
		)
	)


func _shadow_roi() -> Array:
	var bounds := AABB(Vector3(-1.06, -0.05, -1.06), Vector3(2.12, 0.10, 2.12))
	var roi := Rect2(_scene.camera.unproject_position(bounds.position), Vector2.ZERO)
	for index in 8:
		var point := bounds.get_endpoint(index)
		if _scene.camera.is_position_behind(point):
			return [0, 0, 0, 0]
		roi = roi.expand(_scene.camera.unproject_position(point))
	return [roi.position.x, roi.position.y, roi.end.x, roi.end.y]


func _frames() -> void:
	for frame in 5:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks.append({"pass": condition, "label": label})
	if not condition:
		push_error("SOFT_TISSUE: " + label)
