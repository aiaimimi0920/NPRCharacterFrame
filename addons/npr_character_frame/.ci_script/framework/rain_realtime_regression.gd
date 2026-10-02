extends SceneTree
## Engine-driven rain; pose is frozen only to isolate water's actual GPU response.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
var _scene: Control
var _rain: RefCounted
var _output: String
var _anchors: Dictionary
var _checks: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _traces: Array[Dictionary] = []
var _decay: Array[Dictionary] = []
var _probes: Array[Vector2i] = []
var _views: Array[Dictionary] = []
var _frame := 0


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	root.mouse_passthrough = true
	root.unfocusable = true
	var fixture: String = get_script().resource_path.get_base_dir().path_join(
		"fixtures/silver_wolf_rain_anchors.json"
	)
	_anchors = JSON.parse_string(FileAccess.get_file_as_string(fixture)).anchors
	var connections := RenderingServer.frame_pre_draw.get_connections().size()
	_scene = SCENE.instantiate()
	_scene.save_path = _output.path_join("unused.json")
	root.add_child(_scene)
	_scene.performance.automatic = false
	_scene.performance.set_process(false)
	_scene.state.blink = false
	_scene.state.secondary = false
	_scene._apply_state()
	_scene.performance.apply_pose(0.0)
	_rain = _scene.visual_layers.surface_rain
	# Skeleton palette publication follows the first render. Sampling a camera
	# anchor before it would compare different cameras at dry and restored.
	await _frames(8, "initialize")
	_aim(2)
	await _frames(8, "dry")
	var dry := _capture("dry")
	var dry_view: Dictionary = _views.back()
	_check(_scene.visual_layers.is_processing(), "Rain retains its real engine process callback")
	_scene._set_droplet_count(12)
	_scene._set_droplet_speed(1.0)
	_scene._set_droplets_enabled(true)
	await _seconds(8.0, "raining")
	_check(_rain.births > 300, "Natural rain produces a substantial non-looping population")
	_check(_rain.crossings > 100, "Actual drops cross surface triangles")
	_check(_rain.water.size() > 300, "Actual flow leaves distributed surface water")
	for marker in [2, 9]:
		await _sequence(marker)
	_aim(2)
	var births: int = _rain.births
	var state_before: Dictionary = _scene.state.to_data()
	_rain.configure(
		true,
		0.0,
		_scene.state.droplet_seed,
		Vector3.ZERO,
		_scene.state.hosiery_height,
		1.0 - _scene.state.stocking_transparency
	)
	_check(_rain.enabled and not _rain.water.is_empty(), "Zero input keeps existing water enabled")
	var started := Time.get_ticks_usec()
	while not _rain.drops.is_empty() and Time.get_ticks_usec() - started < 35000000:
		await _tick("draining")
		for drop: Dictionary in _rain.drops:
			var value: Vector4 = _rain._snapshot(drop)
			if _probes.size() < 4096 and _frame % 12 == 0:
				_probes.append(Vector2i(value.x, value.y))
	_check(_rain.births == births, "Zero input never spawns a replacement bead")
	_check(_rain.drops.is_empty(), "The last real beads retire without a forced clear")
	await _frames(3, "drained")
	var heads: Image = _rain.field.heads.get_texture().get_image()
	_check(_channel_is_zero(heads, 1), "Every GPU head texel clears when real beads retire")
	var field: Image = _rain.field.image()
	var point := _bright_probe(field)
	var value := field.get_pixelv(point).r
	_check(value > 0.01, "Residual GPU water remains after the last bead is gone")
	_scene.visual_layers.set_droplet_preview_paused(true)
	var water := _water_bytes()
	var paused_field: PackedByteArray = field.get_data()
	var paused_heads := heads.get_data()
	var paused := _capture("paused_trails")
	await _frames(12, "paused")
	_check(_water_bytes() == water, "Pause preserves exact CPU water state and RNG")
	_check(_rain.field.image().get_data() == paused_field, "Pause freezes all GPU water texels")
	_check(
		_rain.field.heads.get_texture().get_image().get_data() == paused_heads,
		"Pause freezes all GPU bead texels"
	)
	_check(
		_capture("paused_restored").get_data() == paused.get_data(),
		"Paused real scene preserves exact GPU RGBA"
	)
	await _paired_trails("residual_begin")
	_scene.visual_layers.set_droplet_preview_paused(false)
	var elapsed: float = _rain.elapsed
	var decay_started := Time.get_ticks_usec()
	_decay.append({"wall_seconds": 0.0, "simulation_seconds": 0.0, "value": value})
	var previous := value
	for interval in [1.0, 1.0, 2.0, 4.0]:
		await _seconds(interval, "residual_decay")
		var next: float = _rain.field.image().get_pixelv(point).r
		var simulation: float = _rain.elapsed - elapsed
		_decay.append(
			{
				"wall_seconds": float(Time.get_ticks_usec() - decay_started) / 1000000.0,
				"simulation_seconds": simulation,
				"value": next,
				"ideal_retention_value": value * exp(-0.13 * simulation)
			}
		)
		_check(
			next > 0.0 and next < previous,
			"Residual GPU water persists and decreases without new beads"
		)
		_check(_rain.drops.is_empty() and _rain.births == births, "Decay has no hidden respawn")
		previous = next
	_check(previous < value * 0.5, "Eight real seconds produce substantial water decay")
	_scene.visual_layers.set_droplet_preview_paused(true)
	await _paired_trails("residual_end")
	_check(
		_scene.state.to_data() == state_before,
		"Runtime stop and pause never rewrite saved settings"
	)
	_scene.visual_layers.restart_droplet_preview()
	await _frames(3, "restarted")
	_check(_channel_is_zero(_rain.field.image(), 0), "Restart clears every GPU residue texel")
	_check(
		_channel_is_zero(_rain.field.heads.get_texture().get_image(), 1),
		"Restart clears every GPU head texel"
	)
	_check(
		_rain.drops.is_empty() and _rain.water.is_empty(), "Restart clears CPU particles and water"
	)
	_scene._set_droplets_enabled(false)
	await _frames(4, "restored")
	_check(
		_capture("restored").get_data() == dry.get_data(),
		"Restart and disable restore exact dry scene RGBA"
	)
	var restored_view: Dictionary = _views.back()
	for key in ["camera", "anchor_points", "mesh_transform", "pose_clock"]:
		_check(dry_view[key] == restored_view[key], "Dry restoration preserves " + key)
	var sparse := Image.create(32, 32, false, Image.FORMAT_RGBAH)
	sparse.fill(Color(0.0, 0.0, 0.0, 0.0))
	_check(_channel_is_zero(sparse, 1), "Exact zero detector accepts an empty field")
	sparse.set_pixel(31, 31, Color(0.0, 0.00006103515625, 0.0, 0.0))
	_check(not _channel_is_zero(sparse, 1), "Exact zero detector rejects one faint texel")
	var weak: WeakRef = weakref(_scene)
	_scene.queue_free()
	_scene = null
	_rain = null
	for index in 4:
		await process_frame
	_check(weak.get_ref() == null, "Rain scene is released")
	_check(
		RenderingServer.frame_pre_draw.get_connections().size() == connections,
		"Render callbacks return to baseline"
	)
	_finish(point)


func _aim(marker: int) -> Vector3:
	var anchor: Dictionary = _anchors[str(marker)]
	var mesh: MeshInstance3D = _scene.preview.meshes[0]
	var geometry: NPRGeometryState = mesh.get_node("NPRGeometryState")
	var points := geometry.sample_surface_vertices(0, PackedInt32Array(anchor.surface_triangle))
	var bary := Vector3(anchor.barycentric[0], anchor.barycentric[1], anchor.barycentric[2])
	var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var target := (
		mesh.global_transform
		* (
			points[0] * bary.x
			+ points[1] * bary.y
			+ points[2] * bary.z
			+ normal * float(anchor.normal_sign) * float(anchor.surface_offset)
		)
	)
	_scene.camera.h_offset = 0.0
	_scene.camera.fov = 40.0
	_scene.camera.position = target + Vector3(0.0, 0.01, 0.55)
	_scene.camera.look_at(target)
	_record_view("aim_%d" % marker)
	return target


func _record_view(label: String) -> void:
	var mesh: MeshInstance3D = _scene.preview.meshes[0]
	var geometry: NPRGeometryState = mesh.get_node("NPRGeometryState")
	var points := geometry.sample_surface_vertices(
		0, PackedInt32Array(_anchors["2"].surface_triangle)
	)
	_views.append(
		{
			"label": label,
			"frame": _frame,
			"camera": var_to_bytes(_scene.camera.global_transform).hex_encode(),
			"camera_position": str(_scene.camera.global_position),
			"anchor_points": var_to_bytes(points).hex_encode(),
			"mesh_transform": var_to_bytes(mesh.global_transform).hex_encode(),
			"mesh_id": mesh.mesh.get_instance_id(),
			"pose_clock": _scene.performance.clock
		}
	)


func _sequence(marker: int) -> void:
	var target := _aim(marker)
	var tracked: Dictionary = {}
	var nearest := INF
	for drop: Dictionary in _rain.drops:
		if drop.dead or (marker == 2 and _rain._kind(drop.triangle, drop.bary) != 5):
			continue
		var position := _drop_world(drop)
		if position.distance_to(target) < nearest:
			nearest = position.distance_to(target)
			tracked = drop
	_check(not tracked.is_empty(), "A real nearby bead is available for trajectory recording")
	for index in 60:
		await _tick("sequence_%d" % marker)
		var row := {
			"marker": marker,
			"index": index,
			"frame": _frame,
			"wall_usec": Time.get_ticks_usec(),
			"rain_elapsed": _rain.elapsed
		}
		if not tracked.is_empty():
			var position := _drop_world(tracked)
			var screen: Vector2 = _scene.camera.unproject_position(position)
			row.drop = {
				"slot": tracked.slot,
				"age": tracked.age,
				"triangle": tracked.triangle,
				"bary": [tracked.bary.x, tracked.bary.y, tracked.bary.z],
				"dead": tracked.dead,
				"volume": tracked.volume,
				"world": [position.x, position.y, position.z],
				"screen": [screen.x, screen.y]
			}
			_check(position.is_finite(), "Recorded real drop position is finite")
		_traces.append(row)
		_capture("m%d_%04d" % [marker, index])


func _drop_world(drop: Dictionary) -> Vector3:
	var ids: Array = _rain.data.indices[int(drop.triangle)]
	var mesh: MeshInstance3D = _scene.preview.meshes[0]
	var geometry: NPRGeometryState = mesh.get_node("NPRGeometryState")
	var points := geometry.sample_surface_vertices(0, PackedInt32Array(ids))
	return (
		mesh.global_transform
		* (points[0] * drop.bary.x + points[1] * drop.bary.y + points[2] * drop.bary.z)
	)


func _paired_trails(label: String) -> void:
	await _frames(2, "pair_settle")
	var before := _capture(label + "_on")
	_scene.preview.materials[0].set_shader_parameter("u_npr_rain_enabled", false)
	await _frames(2, "pair_off")
	var off := _capture(label + "_off")
	_check(
		before.get_data() != off.get_data(),
		"Residual water changes the real material with zero live beads"
	)
	_scene.preview.materials[0].set_shader_parameter("u_npr_rain_enabled", true)
	await _frames(2, "pair_restored")
	_check(
		_capture(label + "_restored").get_data() == before.get_data(),
		"Material-only A/B restores exact residual-water RGBA"
	)


func _bright_probe(field: Image) -> Vector2i:
	var value := -1.0
	var result := Vector2i.ZERO
	for point in _probes:
		for y in range(maxi(0, point.y - 3), mini(field.get_height(), point.y + 4)):
			for x in range(maxi(0, point.x - 3), mini(field.get_width(), point.x + 4)):
				var sample := field.get_pixel(x, y).r
				if sample > value:
					value = sample
					result = Vector2i(x, y)
	return result


func _water_bytes() -> PackedByteArray:
	return var_to_bytes(
		[
			_rain.elapsed,
			_rain.births,
			_rain.water,
			_rain.drops,
			_rain.rng.state,
			_rain._display_clock,
			_rain._cursor,
			_rain._arrival
		]
	)


func _channel_is_zero(image: Image, channel: int) -> bool:
	# Inspect every texel, not a filtered average that can lose faint residue.
	var copy := image.duplicate() as Image
	copy.convert(Image.FORMAT_RGBAF)
	var values := copy.get_data().to_float32_array()
	for index in range(channel, values.size(), 4):
		if values[index] != 0.0:
			return false
	return true


func _seconds(seconds: float, phase: String) -> void:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		await _tick(phase)


func _frames(count: int, phase: String) -> void:
	for index in count:
		await _tick(phase)


func _tick(phase: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_frame += 1
	var stats: Dictionary = _rain.stats()
	_samples.append(
		{
			"frame": _frame,
			"phase": phase,
			"wall_usec": Time.get_ticks_usec(),
			"rain": stats,
			"pose_clock": _scene.performance.clock
		}
	)
	if stats.updates > stats.update_budget or stats.active > 320:
		_check(false, "Rain exceeded its per-frame work or population budget")


func _capture(label: String) -> Image:
	if label in ["dry", "restored"]:
		_record_view(label)
	var result: Image = _scene.viewport.get_texture().get_image()
	_check(result.save_png(_output.path_join(label + ".png")) == OK, "Frame saved")
	return result


func _check(value: bool, label: String) -> void:
	_checks.append({"label": label, "pass": value})
	if not value:
		push_error("RAIN_REALTIME_FAILED: " + label)


func _finish(point: Vector2i) -> void:
	var failed := _checks.filter(func(row: Dictionary): return not row["pass"])
	var result := {
		"checks": _checks,
		"samples": _samples,
		"traces": _traces,
		"decay": _decay,
		"views": _views,
		"probe_texel": [point.x, point.y],
		"fps_cap": 60,
		"readback_is_test_only": true
	}
	FileAccess.open(_output.path_join("rain_realtime.json"), FileAccess.WRITE).store_string(
		JSON.stringify(result, "  ")
	)
	print("RAIN_REALTIME_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)
