extends "res://addons/npr_character_frame/.ci_script/framework/equipment_material_lookdev.gd"

const ANCHORS = preload(
	"res://addons/npr_character_frame/.ci_script/framework/rain_capture_anchors.gd"
)


func _run() -> void:
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("unused.json")
	root.add_child(_wardrobe)
	_wardrobe.performance.automatic = false
	_wardrobe.performance.set_process(false)
	_wardrobe.state.blink = false
	_wardrobe.state.secondary = false
	_wardrobe.performance.apply_pose(0.0)
	_wardrobe.visual_layers.set_process(false)
	await _frames(4)
	_wardrobe.set_view("full")
	var original_camera: Transform3D = _wardrobe.camera.transform
	var original_fov: float = _wardrobe.camera.fov
	var original_offset: float = _wardrobe.camera.h_offset
	var original_yaw: float = _wardrobe.preview.light_yaw
	var rain: RefCounted = _wardrobe.visual_layers.surface_rain
	var arrays: Array = _wardrobe.preview.meshes[0].mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var maximum := 0.0
	var to_actor: Transform3D = (
		_wardrobe.preview.global_transform.affine_inverse()
		* _wardrobe.preview.meshes[0].global_transform
	)
	for i in rain.positions.size():
		maximum = maxf(maximum, (to_actor * vertices[i]).distance_to(rain.positions[i]))
	print("RAIN_TOPOLOGY_MAX_ERROR=", maximum)
	_check(maximum < 0.00001, "Runtime mesh prefix matches the baked topology by vertex index")
	await _capture("dry")
	_wardrobe._set_droplets_enabled(true)
	_wardrobe._set_droplet_count(12)
	var records: Array = []
	var began := Time.get_ticks_usec()
	for frame in 720:
		rain.advance(1.0 / 24.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [71, 239, 479, 719]:
			var record: Dictionary = rain.stats()
			record.field_hash = hash(rain.field.image().get_data())
			records.append(record)
			await _capture("rain_%03d" % frame)
	var cost := float(Time.get_ticks_usec() - began) / 720000.0
	_check(rain.births > 300, "Continuous stochastic rainfall replaces 12 looping markers")
	_check(rain.crossings > 100, "Water crosses surface triangle edges under gravity")
	_check(rain.water.size() > 300, "Flow deposits water across surface triangles")
	_check(
		records[1].field_hash != records[3].field_hash,
		"GPU wet tracks do not repeat the old period"
	)
	var wet_hash: int = rain.stats().state_hash
	_wardrobe.visual_layers.set_droplet_preview_paused(true)
	_wardrobe.visual_layers._process(1.0)
	_check(rain.stats().state_hash == wet_hash, "Pause freezes the water simulation")
	# Render close stockings and clothing without resimulating or relocating UVs.
	for marker in [2, 9]:
		var target: Vector3 = (
			_wardrobe.preview.global_transform
			* ANCHORS.sample_actor_position(_wardrobe.preview, marker)
		)
		_wardrobe.camera.h_offset = 0.0
		_wardrobe.camera.fov = 40.0
		_wardrobe.camera.position = target + Vector3(0.0, 0.01, 0.55)
		_wardrobe.camera.look_at(target)
		for yaw in [-60, 0, 60]:
			_wardrobe.preview.light_yaw = yaw
			_wardrobe.preview.materials[0].set_shader_parameter("u_npr_rain_enabled", false)
			await _capture("close_%d_%d_off" % [marker, yaw])
			_wardrobe.preview.materials[0].set_shader_parameter("u_npr_rain_enabled", true)
			await _capture("close_%d_%d" % [marker, yaw])
		_wardrobe.preview.materials[0].set_shader_parameter("u_npr_rain_debug", true)
		await _capture("field_%d" % marker)
		_wardrobe.preview.materials[0].set_shader_parameter("u_npr_rain_debug", false)
	# Stop new arrivals without clearing deposited water.
	var before: float = rain.deposited
	rain.input_rate = 0.0
	for frame in 240:
		rain.advance(1.0 / 24.0)
		await process_frame
		await RenderingServer.frame_post_draw
	_check(
		rain.water.size() > 0 and rain.deposited >= before,
		"Rain stop preserves residual wet tracks"
	)
	rain.field.image().save_png(_output.path_join("field.png"))
	_wardrobe.visual_layers.restart_droplet_preview()
	_check(rain.water.is_empty() and rain.drops.is_empty(), "Restart clears the whole simulation")
	_wardrobe._set_droplets_enabled(false)
	_wardrobe.set_view("full")
	_wardrobe.camera.transform = original_camera
	_wardrobe.camera.fov = original_fov
	_wardrobe.camera.h_offset = original_offset
	_wardrobe.preview.light_yaw = original_yaw
	await _capture("restored")
	FileAccess.open(_output.path_join("surface_rain.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "records": records, "step_ms_with_captures": cost}, "\t")
	)
	var passed := _checks.all(func(row: Dictionary): return row.pass)
	_wardrobe.free()
	print("REGRESSION_OK" if passed else "REGRESSION_FAILED")
	quit(0 if passed else 1)
