extends "res://addons/npr_character_frame/.ci_script/framework/equipment_material_lookdev.gd"
## GPU trajectory witness plus real-scene continuous rainfall. Readback is test-only.

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
	_wardrobe._set_droplets_enabled(true)
	_wardrobe._set_droplet_count(12)
	await _frames(4)
	var rain: RefCounted = _wardrobe.visual_layers.surface_rain
	await _trajectory_witness(rain)
	rain.clear()
	var maximum_updates := 0
	for frame in 600:
		rain.advance(1.0 / 60.0, 2.85)
		maximum_updates = maxi(maximum_updates, rain.updates_last_frame)
		await process_frame
		await RenderingServer.frame_post_draw
	_check(rain.drops.size() > 200, "Performance fixture has dense live rainfall")
	_check(maximum_updates <= 32, "High speed stays within the per-frame particle budget")
	var before: float = rain.elapsed
	rain.advance(5.0, 2.85)
	_check(
		rain.updates_last_frame <= 32 and rain.elapsed - before < 0.15,
		"A five-second stall is discarded without a catch-up burst"
	)
	await _frames(2)
	for marker in [2, 9]:
		var target: Vector3 = (
			_wardrobe.preview.global_transform
			* ANCHORS.sample_actor_position(_wardrobe.preview, marker)
		)
		_wardrobe.camera.h_offset = 0.0
		_wardrobe.camera.fov = 40.0
		_wardrobe.camera.position = target + Vector3(0.0, 0.01, 0.55)
		_wardrobe.camera.look_at(target)
		for frame in 120:
			rain.advance(1.0 / 60.0, 2.85)
			await process_frame
			await RenderingServer.frame_post_draw
			_wardrobe.viewport.get_texture().get_image().save_png(
				_output.path_join("m%d_%04d.png" % [marker, frame])
			)
	var head_hash := hash(rain.field.heads.get_texture().get_image().get_data())
	var trail_hash := hash(rain.field.image().get_data())
	_wardrobe.visual_layers.set_droplet_preview_paused(true)
	for frame in 12:
		_wardrobe.visual_layers._process(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
	_check(
		(
			hash(rain.field.heads.get_texture().get_image().get_data()) == head_hash
			and hash(rain.field.image().get_data()) == trail_hash
		),
		"Pause freezes the actual GPU head and trail textures exactly"
	)
	_wardrobe.visual_layers.restart_droplet_preview()
	await _frames(2)
	_check(_energy(rain.field.image(), 0) == 0.0, "Restart clears the GPU trail history")
	_check(
		_energy(rain.field.heads.get_texture().get_image(), 1) == 0.0,
		"Restart clears the GPU bead snapshots"
	)
	FileAccess.open(_output.path_join("rain_continuity.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "maximum_updates": maximum_updates}, "\t")
	)
	var passed := _checks.all(func(row: Dictionary): return row.pass)
	_wardrobe.free()
	print("REGRESSION_OK" if passed else "REGRESSION_FAILED")
	quit(0 if passed else 1)


func _trajectory_witness(rain: RefCounted) -> void:
	# Select a real stocking triangle with enough atlas area, then verify a known
	# sub-texel trajectory through the production GPU rasterizer at 60 Hz.
	var chosen := -1
	var largest := 0.0
	for t: int in rain.data.candidates:
		if int(rain.data.kinds[t]) != 5:
			continue
		var area: float = rain.data.areas[t]
		if area > largest:
			largest = area
			chosen = t
	var a: Vector2 = rain._uv(chosen, Vector3(0.4, 0.35, 0.25)) * Vector2(rain.size)
	var b: Vector2 = rain._uv(chosen, Vector3(0.25, 0.35, 0.4)) * Vector2(rain.size)
	var chart := int(rain.data.charts[chosen])
	rain.field.write(
		0, Vector4(a.x, a.y, 1.4, 1.0), Vector4(b.x, b.y, 1.4, 1.0), Vector4(0.0, 0.2, chart, chart)
	)
	var samples: Array = []
	var minimum_energy := INF
	var maximum_energy := 0.0
	var maximum_error := 0.0
	var distinct := 0
	var previous := Vector2.ZERO
	for frame in 13:
		var time := float(frame) / 60.0
		rain.field.present(time, 0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = rain.field.heads.get_texture().get_image()
		var expected := a.lerp(b, float(frame) / 12.0)
		var center := Vector2.ZERO
		var energy := 0.0
		for y in range(int(expected.y) - 8, int(expected.y) + 9):
			for x in range(int(expected.x) - 8, int(expected.x) + 9):
				var value := image.get_pixel(x, y).g
				center += Vector2(x + 0.5, y + 0.5) * value
				energy += value
		center /= maxf(energy, 0.000001)
		minimum_energy = minf(minimum_energy, energy)
		maximum_energy = maxf(maximum_energy, energy)
		maximum_error = maxf(maximum_error, expected.distance_to(center))
		if frame > 0 and center.distance_to(previous) > 0.01:
			distinct += 1
		previous = center
		samples.append({"frame": frame, "energy": energy, "centroid": [center.x, center.y]})
		image.save_png(_output.path_join("witness_%02d.png" % frame))
	_check(minimum_energy > 0.1, "The GPU witness remains visible in every frame")
	_check(distinct == 12, "Bead position advances on all 12 rendered frame intervals")
	_check(maximum_error < 0.35, "Sub-texel bead centroid follows the continuous trajectory")
	_check(
		minimum_energy / maxf(maximum_energy, 0.000001) > 0.85,
		"Sub-texel motion does not flash in and out of the atlas"
	)
	FileAccess.open(_output.path_join("trajectory.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"samples": samples, "maximum_error": maximum_error}, "\t")
	)
	rain.field.present(0.2, 0.1)
	await _frames(2)
	var wet: float = rain.field.image().get_pixelv(Vector2i(b)).r
	rain.field.write(0, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO)
	rain.field.present(0.3, 1.0)
	await _frames(2)
	var remaining: float = rain.field.image().get_pixelv(Vector2i(b)).r
	_check(wet > 0.01, "A rendered bead deposits real GPU trail water")
	_check(
		remaining > wet * 0.7 and remaining < wet * 0.99,
		"Without new beads, GPU wet tracks persist and gradually decay"
	)


func _energy(image: Image, channel: int) -> float:
	# Tiny mip averages test the actual full field without a GDScript pixel scan.
	var copy := image.duplicate() as Image
	copy.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	return copy.get_pixel(0, 0)[channel]
