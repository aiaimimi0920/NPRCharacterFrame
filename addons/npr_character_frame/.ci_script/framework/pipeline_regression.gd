extends SceneTree
## Actual GPU depth decoding, same-frame camera changes, isolation, and timed viewports.

var _lab: Control
var _output: String
var _checks: Array[Dictionary] = []
var _depth_reports: Array[Dictionary] = []
var _benchmarks: Array[Dictionary] = []
## Logical-pixel spacing; derived fixtures may request denser independent rays.
var _depth_grid_spacing := 19.0


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_lab = load("res://addons/npr_character_frame/showcase/wardrobe.tscn").instantiate()
	root.add_child(_lab)
	await _frames(10)
	_check_depth("full")
	_lab.set_view("face")
	# No warmup: the producer must follow this very frame, not the last camera.
	await RenderingServer.frame_post_draw
	_check_depth("face_same_frame")
	_lab.turntable.rotation_degrees.y = 70.0
	_lab.set_view("half")
	await RenderingServer.frame_post_draw
	_check_depth("quarter_same_frame")
	root.size = Vector2i(1100, 700)
	await _frames(3)
	_check_depth("resized")
	_lab.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_lab.camera.size = 3.3
	await RenderingServer.frame_post_draw
	_check_depth("orthographic_same_frame")
	_lab.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var original_camera: Camera3D = _lab.camera
	var alternate := Camera3D.new()
	original_camera.get_parent().add_child(alternate)
	alternate.global_transform = original_camera.global_transform
	alternate.fov = 42.0
	alternate.make_current()
	_lab.camera = alternate
	await RenderingServer.frame_post_draw
	_check_depth("camera_switch_same_frame")
	_check(_lab.preview.depth_pass.camera == alternate, "Depth follows the current camera")
	original_camera.make_current()
	_lab.camera = original_camera
	alternate.queue_free()
	root.size = Vector2i(1440, 900)
	_lab.reset_scheme()
	_lab.set_view("full")
	await _frames(5)
	await _check_effects()
	await _check_isolation()
	await _benchmark()
	var failed := _checks.any(func(item): return not item["pass"])
	var file := FileAccess.open(_output.path_join("pipeline_checks.json"), FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{"checks": _checks, "depth": _depth_reports, "performance": _benchmarks}, "  "
		)
	)
	_lab.queue_free()
	await process_frame
	print("PIPELINE_CHECKS count=", _checks.size(), " failed=", failed)
	print("REGRESSION_FAILED" if failed else "REGRESSION_OK")
	quit(1 if failed else 0)


func _check_depth(label: String) -> void:
	var depth: Node = _lab.preview.depth_pass
	var camera: Camera3D = _lab.camera
	var reference := _visible_triangle_reference(camera)
	var image: Image = depth.viewports[0].get_texture().get_image()
	var hair: Image = depth.viewports[1].get_texture().get_image()
	var logical_size := Vector2(camera.get_viewport().get_visible_rect().size)
	var expected_size := Vector2i(logical_size)
	if depth.quality < 2:
		expected_size = Vector2i((logical_size * 0.5).ceil())
	_check(
		image.get_format() in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH],
		label + ": linear HDR data texture"
	)
	_check(
		image.get_size() == expected_size and hair.get_size() == expected_size,
		label + ": pixel alignment"
	)
	_check(
		depth.cameras[0].global_transform == camera.global_transform,
		label + ": same camera transform"
	)
	var errors: Array[float] = []
	var bad_samples: Array[Dictionary] = []
	var hair_samples := 0
	var invalid_hair := 0
	var boundary_samples := 0
	var ratio := logical_size / Vector2(image.get_size())
	var grid := maxi(3, roundi(_depth_grid_spacing / ratio.x))
	for y in range(12, image.get_height() - 12, grid):
		for x in range(12, image.get_width() - 12, grid):
			var point := Vector2(x + 0.5, y + 0.5) * ratio
			var ray := _reference_ray(camera, point)
			var hit: Dictionary = reference.intersect_ray(ray[0] * 100.0, ray[1])
			var encoded := image.get_pixel(x, y)
			if not hit.is_empty() and encoded.b > 0.5:
				var actual: float = -(
					(camera.get_camera_transform().affine_inverse() * (hit.position / 100.0)).z
				)
				# A CPU point ray and fixed-point GPU rasterization can choose opposite
				# triangles at subpixel discontinuities. Certify a small footprint first;
				# keep the strict world-space error gate on every continuous sample.
				var continuous := _continuous_depth(reference, camera, point, actual)
				if continuous:
					errors.append(absf(_decode(encoded, depth.depth_range) - actual))
				else:
					boundary_samples += 1
				if continuous and errors.back() > 0.005 and bad_samples.size() < 8:
					bad_samples.append(
						{
							"pixel": str(point),
							"encoded": str(encoded),
							"gpu": _decode(encoded, depth.depth_range),
							"cpu": actual
						}
					)
			var encoded_hair := hair.get_pixel(x, y)
			if encoded_hair.b > 0.5:
				hair_samples += 1
				if (
					encoded.b < 0.5
					or (
						_decode(encoded, depth.depth_range)
						> _decode(encoded_hair, depth.depth_range) + 0.005
					)
				):
					invalid_hair += 1
	var max_error: float = errors.max() if not errors.is_empty() else INF
	errors.sort()
	_check(
		errors.size() > 30 and max_error < 0.005, label + ": depth agrees with real triangle hits"
	)
	_check(
		hair_samples > 5 and invalid_hair == 0, label + ": separate hair is behind or at full depth"
	)
	_depth_reports.append(
		{
			"label": label,
			"samples": errors.size(),
			"subpixel_boundary_samples": boundary_samples,
			"max_world_error": max_error,
			"median_error": errors[errors.size() / 2] if not errors.is_empty() else INF,
			"format": image.get_format(),
			"range": depth.depth_range,
			"bad_samples": bad_samples,
			"hair_samples": hair_samples,
			"hair_order_failures": invalid_hair
		}
	)
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(_output.path_join(label + "_packed_depth.png"))
	hair.convert(Image.FORMAT_RGBA8)
	hair.save_png(_output.path_join(label + "_packed_hair.png"))


func _decode(color: Color, depth_range: float) -> float:
	return (color.r + color.g / 256.0) * depth_range


func _reference_ray(camera: Camera3D, point: Vector2) -> Array[Vector3]:
	if camera.projection != Camera3D.PROJECTION_FRUSTUM:
		return [camera.project_ray_origin(point), camera.project_ray_normal(point)]
	# This engine's project_local_ray_normal assumes a symmetric frustum. Invert
	# the actual projection for this independent off-center-frustum oracle instead.
	var uv := point / camera.get_viewport().get_visible_rect().size
	var clip := Vector4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, -1.0, 1.0)
	var local: Vector4 = _render_projection(camera).inverse() * clip
	var pose := camera.get_camera_transform()
	return [pose.origin, (pose.basis * Vector3(local.x, local.y, local.z) / local.w).normalized()]


func _render_projection(camera: Camera3D) -> Projection:
	if camera.projection != Camera3D.PROJECTION_FRUSTUM:
		return camera.get_camera_projection()
	# Camera3D's CPU getter omits keep_aspect for FRUSTUM in this engine, while
	# RendererSceneCull passes it. Match the renderer, not the incomplete getter.
	var dimensions := camera.get_viewport().get_visible_rect().size
	return Projection.create_frustum_aspect(
		camera.size,
		dimensions.x / dimensions.y,
		camera.frustum_offset,
		camera.near,
		camera.far,
		camera.keep_aspect == Camera3D.KEEP_WIDTH
	)


func _continuous_depth(
	reference: TriangleMesh, camera: Camera3D, point: Vector2, depth: float
) -> bool:
	for offset in [Vector2(0.125, 0), Vector2(-0.125, 0), Vector2(0, 0.125), Vector2(0, -0.125)]:
		var sample: Vector2 = point + offset
		var ray := _reference_ray(camera, sample)
		var hit := reference.intersect_ray(ray[0] * 100.0, ray[1])
		if hit.is_empty():
			return false
		var other_depth: float = -(
			(camera.get_camera_transform().affine_inverse() * (hit.position / 100.0)).z
		)
		if absf(other_depth - depth) > 0.005:
			return false
	return true


func _visible_triangle_reference(camera: Camera3D) -> TriangleMesh:
	# GPU uses cull_back. The surface picker is intentionally two-sided, so its
	# nearest eyelid/backface is NOT an independent reference for an opaque pass.
	var vertices := PackedVector3Array()
	for mesh in _lab.preview.meshes:
		# Never use Mesh.get_faces(): its internal BVH welds in tiny import units,
		# before the face's large node scale, changing the reference geometry.
		var faces := PackedVector3Array()
		for surface in range(mesh.mesh.get_surface_count()):
			var data: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
			for index in range(indices.size() if not indices.is_empty() else positions.size()):
				faces.append(positions[indices[index] if not indices.is_empty() else index])
		var local_camera: Vector3 = (
			mesh.global_transform.affine_inverse() * camera.get_camera_transform().origin
		)
		for index in range(0, faces.size(), 3):
			var a := faces[index]
			var b := faces[index + 1]
			var c := faces[index + 2]
			var toward := local_camera - a
			if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
				toward = mesh.global_basis.inverse() * camera.global_basis.z
			if Plane(a, b, c).normal.dot(toward) <= 0.0:
				continue
			for point in [a, b, c]:
				vertices.append(mesh.global_transform * point * 100.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var reference := ArrayMesh.new()
	reference.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return reference.generate_triangle_mesh()


func _check_effects() -> void:
	_lab.set_view("face")
	_lab.preview.set_hair_contact(0.0)
	await _capture("contact_off")
	_lab.preview.set_hair_contact(1.0)
	await _capture("contact_on")
	_lab.preview.depth_pass.set_enabled(false)
	await _capture("depth_disabled")
	_lab.preview.set_hair_contact(0.0)
	await _capture("disabled_contact_zero")
	_lab.preview.depth_pass.set_enabled(true)
	_lab.preview.set_rim_strength(0.5)
	await _capture("depth_rim")
	_lab.preview.depth_pass.set_enabled(false)
	await _capture("fresnel_fallback")
	_lab.preview.depth_pass.set_enabled(true)
	_lab.preview.set_fill_strength(0.0)
	await _capture("fill_off")
	_lab.preview.set_fill_strength(0.8)
	await _capture("fill_on")
	_lab.preview.fill_light.position.x = -1.0
	await _capture("fill_moved")
	_lab.preview.set_fill_strength(0.0)
	# Isolate body when checking the explicit legacy-compositor policy.
	var body: ShaderMaterial = _lab.preview.materials[0]
	var visibility: Array[bool] = []
	for mesh in _lab.turntable.get_parent().get_children():
		if mesh is MeshInstance3D:
			visibility.append(mesh.visible)
			mesh.hide()
	_lab.preview.meshes[1].hide()
	_lab.preview.meshes[2].hide()
	for feature in ["height_lerp", "bloom", "special_effect", "fog", "dithering"]:
		body.set_shader_parameter("u_debug_frag_%s_enabled" % feature, true)
		# Quantization, not an identity mask, is the remaining nonlinear guard.
		body.set_shader_parameter("u_color_mode", 1 if feature == "dithering" else 0)
		_lab.preview.set_shadow_strength(0.65)
		await _capture("legacy_%s_on" % feature)
		_lab.preview.set_shadow_strength(0.0)
		await _capture("legacy_%s_off" % feature)
		body.set_shader_parameter("u_debug_frag_%s_enabled" % feature, false)
	body.set_shader_parameter("u_color_mode", 0)
	var index := 0
	for mesh in _lab.turntable.get_parent().get_children():
		if mesh is MeshInstance3D:
			mesh.visible = visibility[index]
			index += 1
	_lab.preview.meshes[1].show()
	_lab.preview.meshes[2].show()
	_lab.reset_scheme()
	_lab.set_view("full")


func _check_isolation() -> void:
	var profile: Resource = _lab.preview.material_profile.duplicate(true)
	var original: PackedFloat32Array = profile.specular_exponents.duplicate()
	profile.specular_exponents = PackedFloat32Array([3.5, 12.125, 24, 48, 96, 128, 256.25, 500])
	var saved := _output.path_join("float_profile.tres")
	_check(ResourceSaver.save(profile, saved) == OK, "Full float profile saves")
	var reloaded: Resource = ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(
		reloaded.specular_exponents == profile.specular_exponents,
		"Eight HDR-range exponent values round-trip exactly"
	)
	profile.specular_exponents = PackedFloat32Array([24])
	_check(
		not profile.apply_to(_lab.preview.materials[0]),
		"Malformed profile rejected without uploading"
	)
	_check(
		_lab.preview.material_profile.specular_exponents == original,
		"Shared profile was not mutated"
	)
	# Isolate NPR material/light masks here; stage-inclusive same-key sharing and
	# illumination ownership have dedicated gates in shared_key_regression.gd.
	var stage_meshes: Array[MeshInstance3D] = []
	for child in _lab.turntable.get_parent().get_children():
		if child is MeshInstance3D and child.visible:
			stage_meshes.append(child)
			child.hide()
	await _capture("isolation_before")
	var other: Node3D = load("res://addons/npr_character_frame/showcase/npr_character_preview.gd").new()
	other.position.x = 3.0
	_lab.turntable.add_child(other)
	# Godot repacks its shared directional shadow atlas when a second shadowed
	# key appears. Exclude that resolution change from the material/light-mask test.
	other.set_shadow_strength(0.0)
	other.set_ramp_mix(1.0)
	other.set_hair_highlight(1.0)
	other.set_fill_strength(1.0)
	other.light_yaw = 130.0
	_check(reloaded.apply_to(other.materials[0]), "Eight-slot profile uploads successfully")
	_check(
		(
			other.materials[0].get_shader_parameter("u_npr_specular_exponents")
			== reloaded.specular_exponents
		),
		"Shader receives all full-float slot values"
	)
	_check(other.materials[0] != _lab.preview.materials[0], "Per-actor material ownership")
	_check(
		(
			other.materials[0].get_shader_parameter("u_npr_ramp_mix")
			!= _lab.preview.materials[0].get_shader_parameter("u_npr_ramp_mix")
		),
		"Independent Ramp values"
	)
	_check(other.meshes[0].layers != _lab.preview.meshes[0].layers, "Unique key/fill light layers")
	_check(
		(
			other.depth_pass.viewports[0].get_texture()
			!= _lab.preview.depth_pass.viewports[0].get_texture()
		),
		"Independent actor depth textures"
	)
	_check(
		absf(other.get_world_bounds().get_center().x - 3.0) < 0.005,
		"Pre-positioned character is aligned in local space"
	)
	other.position.x = 6.0
	other.fill_light.global_position = _lab.preview.fill_light.global_position
	await _capture("isolation_other_changed")
	other.queue_free()
	await _frames(4)
	await _capture("isolation_other_freed")
	for mesh in stage_meshes:
		mesh.show()


func _benchmark() -> void:
	var actors: Array[Node3D] = [_lab.preview]
	_lab.preview.position.x = -2.1
	_lab.camera.position = Vector3(0, 1.6, 8)
	_lab.camera.look_at(Vector3(0, 1.5, 0))
	for x in [0.0, 2.1]:
		var other: Node3D = load("res://addons/npr_character_frame/showcase/npr_character_preview.gd").new()
		other.position.x = x
		_lab.turntable.add_child(other)
		other.set_ramp_mix(0.45)
		other.set_shadow_strength(0.28)
		other.set_hair_highlight(0.3)
		other.set_hair_contact(0.35)
		other.set_rim_strength(0.1)
		actors.append(other)
	var views: Array[Viewport] = [root, _lab.viewport]
	for actor in actors:
		views.append_array(actor.depth_pass.viewports)
	for viewport in views:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	for count in [1, 3]:
		for update_mode in ["disabled", "cached", "continuous"]:
			var enabled: bool = update_mode != "disabled"
			for index in range(actors.size()):
				actors[index].visible = index < count
				actors[index].depth_pass.force_continuous = update_mode == "continuous"
				actors[index].depth_pass.set_enabled(enabled and index < count)
			await _frames(45)
			var gpu_samples: Array[float] = []
			var depth_samples: Array[float] = []
			var cpu_samples: Array[float] = []
			var draws: Array[int] = []
			for sample in range(90):
				await RenderingServer.frame_post_draw
				var gpu := 0.0
				var cpu := 0.0
				var depth_gpu := 0.0
				for index in range(views.size()):
					if index >= 2 and (not enabled or (index - 2) / 2 >= count):
						continue
					if index >= 2:
						var depth: Node = actors[(index - 2) / 2].depth_pass
						if not depth.requested_this_frame[(index - 2) % 2]:
							# Viewport timestamps are last-rendered, not zero on skips.
							continue
					var rid := views[index].get_viewport_rid()
					var time := RenderingServer.viewport_get_measured_render_time_gpu(rid)
					gpu += time
					cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
					if index >= 2:
						depth_gpu += time
				gpu_samples.append(gpu)
				depth_samples.append(depth_gpu)
				cpu_samples.append(cpu)
				draws.append(
					RenderingServer.get_rendering_info(
						RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
					)
				)
			gpu_samples.sort()
			depth_samples.sort()
			cpu_samples.sort()
			draws.sort()
			_benchmarks.append(
				{
					"actors": count,
					"depth_enabled": enabled,
					"update_mode": update_mode,
					"gpu_median_ms": gpu_samples[45],
					"gpu_p95_ms": gpu_samples[85],
					"depth_gpu_median_ms": depth_samples[45],
					"render_cpu_median_ms": cpu_samples[45],
					"draws_median": draws[45],
					"samples": 90,
					"warmup": 45
				}
			)
			_check(
				gpu_samples[45] > 0.0,
				"Real GPU timestamps: actors=%d mode=%s" % [count, update_mode]
			)
			await _capture("budget_%d_%s" % [count, update_mode])
	for actor in actors.slice(1):
		actor.queue_free()


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("PIPELINE_FAILED: " + label)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _capture(label: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var image: Image = _lab.viewport.get_texture().get_image()
	image.save_png(_output.path_join(label + ".png"))
