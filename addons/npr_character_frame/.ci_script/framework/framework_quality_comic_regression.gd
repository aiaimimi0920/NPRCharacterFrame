extends "res://addons/npr_character_frame/.ci_script/framework/framework_workbench_regression.gd"
## Projection, real buffer budgets, attached ink and depth negative controls.


func _run() -> void:
	_spawn()
	_wardrobe.select_section(8)
	await _capture("baseline")
	var saved: Dictionary = _wardrobe.state.to_data()
	await _quality()
	await _comics()
	_check(_wardrobe.state.to_data() == saved, "Quality and comics never write the saved scheme")
	_wardrobe.framework.reset()
	await _capture("reset")
	_check(_same_image("baseline", "reset"), "Quality/comic reset restores exact original pixels")
	_finish("QUALITY_COMIC")


func _quality() -> void:
	var workbench: Node = _wardrobe.framework
	var policy: Node = workbench.quality
	var actor: NPRCharacter = _wardrobe.preview
	var camera: Camera3D = _wardrobe.camera
	var camera_state := camera.transform
	var offset := camera.h_offset
	var fov := camera.fov
	var outline: Variant = actor.outlines[0].get_shader_parameter("outline_width_pixels")
	var face_mesh := actor.meshes[1].mesh
	var shapes: Array[float] = []
	for index in face_mesh.get_blend_shape_count():
		shapes.append(actor.meshes[1].get_blend_shape_value(index))
	actor.set_depth_quality(1)
	actor.auxiliary_pass.resolution_scale = 0.75
	actor.auxiliary_pass.set_enabled(true)
	workbench._host.visual_layers.surface_rain.updates_per_frame = 12
	workbench.set_auto_quality(true)
	policy.set_process(false)
	var records: Array[Dictionary] = []
	for index in 3:
		workbench.set_quality_view(index)
		_settle_quality()
		_check(policy.tier == 2 - index, "Actual distance selects expected tier: %d" % index)
		await _capture("quality_%d" % index)
		var start := Time.get_ticks_usec()
		for sample in 64:
			policy.evaluate(0.0)
		var record: Dictionary = policy.budget()
		record.evaluation_usec = float(Time.get_ticks_usec() - start) / 64.0
		record.actual_auxiliary_size = str(actor.auxiliary_pass.viewport.size)
		record.actual_depth_size = str(actor.depth_pass.viewports[0].size)
		var frames: Array[float] = []
		for sample in 24:
			start = Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			frames.append(float(Time.get_ticks_usec() - start) / 1000.0)
		frames.sort()
		record.frame_interval_median_ms = frames[12]
		record.frame_interval_p95_ms = frames[22]
		record.draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		records.append(record)
		var size: Vector2i = actor.auxiliary_pass.viewport.size
		_check(
			size.x * size.y == record.auxiliary_pixels,
			"Budget matches allocated auxiliary pixels: %d" % index
		)
		_check(
			(
				workbench._host.visual_layers.surface_rain.updates_per_frame
				== policy.RAIN_UPDATES[2 - index]
			),
			"Rain work cap follows tier: %d" % index
		)
	_measurements.quality = records
	_check(
		(
			records[0].auxiliary_pixels > records[1].auxiliary_pixels
			and records[1].auxiliary_pixels > records[2].auxiliary_pixels
		),
		"Auxiliary pixel cost decreases across tiers"
	)
	_check(actor.meshes[1].mesh == face_mesh, "Quality retains the exact eye/face mesh")
	_check(
		actor.outlines[0].get_shader_parameter("outline_width_pixels") == outline,
		"Quality preserves outline width"
	)
	for index in shapes.size():
		_check(
			actor.meshes[1].get_blend_shape_value(index) == shapes[index],
			"Quality preserves blend shape %d" % index
		)
	var narrow: float = policy.pixel_height
	camera.fov = fov * 1.5
	policy.evaluate(0.0)
	_check(policy.pixel_height < narrow, "Real perspective FOV changes the footprint")
	camera.fov = fov
	await _multiple_views()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_set_height(500)
	_settle_quality()
	_check(policy.tier == 1, "Orthographic camera selects middle quality")
	var transitions: int = policy.transitions
	for height in [880, 920, 870, 915, 890, 940]:
		_set_height(height)
		_settle_quality()
	_check(
		policy.tier == 1 and policy.transitions == transitions,
		"Near threshold jitter never oscillates"
	)
	_set_height(1100)
	policy.evaluate(0.1)
	_check(policy.tier == 1, "Quality change waits for stable demand")
	_settle_quality()
	_check(policy.tier == 2, "Stable upper band selects near tier")
	_set_height(850)
	_settle_quality()
	_check(policy.tier == 2, "Near tier holds inside hysteresis band")
	_set_height(730)
	await _capture("boundary_full")
	_settle_quality()
	await _capture("boundary_middle")
	_check(policy.tier == 1, "Crossing lower band drops to middle")
	_set_height(330)
	_settle_quality()
	_check(policy.tier == 1, "Middle tier holds above lower hysteresis band")
	_set_height(270)
	_settle_quality()
	_check(policy.tier == 0, "Stable small projection selects far tier")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.transform = camera_state
	camera.h_offset = offset
	camera.fov = fov
	camera.position = Vector3(0, 1.5, 0.01)
	policy.evaluate(0)
	_check(is_inf(policy.pixel_height), "Near-plane intersection is conservatively high quality")
	camera.transform = camera_state
	workbench.set_auto_quality(false)
	_check(actor.depth_pass.quality == 1, "Disabling policy restores manual depth quality")
	_check(
		actor.auxiliary_pass.resolution_scale == 0.75,
		"Disabling policy restores manual auxiliary scale"
	)
	_check(
		workbench._host.visual_layers.surface_rain.updates_per_frame == 12,
		"Disabling policy restores manual rain work cap"
	)
	actor.auxiliary_pass.set_enabled(false)
	actor.auxiliary_pass.resolution_scale = 1.0
	actor.set_depth_quality(2)
	workbench._host.visual_layers.surface_rain.updates_per_frame = 32
	_wardrobe.set_view("face")
	await _capture("quality_restored")
	_check(
		_same_image("baseline", "quality_restored"),
		"Quality toggling restores exact baseline pixels"
	)


func _multiple_views() -> void:
	var policy: Node = _wardrobe.framework.quality
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.world_3d = _wardrobe.preview.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.fov = 36
	camera.position = Vector3(0, 1.55, 3)
	policy.cameras.append(camera)
	_settle_quality()
	_check(policy.tier == 2, "Largest registered same-world view owns quality")
	var height: float = policy.pixel_height
	viewport.size = Vector2i(720, 450)
	policy.evaluate(0)
	_check(
		policy.pixel_height < height * 0.6, "Registered viewport resizing changes projected pixels"
	)
	viewport.size = Vector2i(1440, 900)
	camera.cull_mask = 0
	_settle_quality()
	_check(policy.tier == 0, "View with no visible actor layers does not inflate demand")
	policy.cameras.erase(camera)
	viewport.free()


func _set_height(height: float) -> void:
	var policy: Node = _wardrobe.framework.quality
	_wardrobe.camera.size = 10.0
	policy.evaluate(0.0)
	_wardrobe.camera.size *= policy.pixel_height / height


func _settle_quality() -> void:
	for sample in 6:
		_wardrobe.framework.quality.evaluate(0.1)


func _comics() -> void:
	var workbench: Node = _wardrobe.framework
	var layer: Node3D = workbench.comics
	workbench.set_locked(true)
	workbench.overlay = true
	for kind in [
		"sweat",
		"tear",
		"anger",
		"emphasis",
		"hatching",
		"shy",
		"tension",
		"star_eyes",
		"heart_eyes"
	]:
		workbench.play_comic(kind)
		await _capture("comic_" + kind)
		_check(not _same_image("baseline", "comic_" + kind), "Actual comic visibly drawn: " + kind)
		workbench.clear_effects()
	workbench.set_locked(false)
	workbench.overlay = false
	var token: int = layer.play("anger", workbench._anchor, 2.0)
	layer.advance(0.1)
	var before: Vector3 = layer._effects[0].mesh.global_position
	_wardrobe.performance.action = "look_around"
	_wardrobe.performance.apply_pose(1.0)
	layer.advance(0.0)
	_check(
		layer._effects[0].mesh.global_position.distance_to(before) > 0.005,
		"Comic follows actual animated head anchor"
	)
	_check(
		layer._effects[0].mesh.global_basis.is_equal_approx(_wardrobe.camera.global_basis),
		"Comic faces the observing camera"
	)
	layer.cancel(token)
	_wardrobe.performance.action = "idle"
	_wardrobe.performance.apply_pose(0.0)
	await _occlusion()
	await _hair_occlusion()
	var anchor := Node3D.new()
	_wardrobe.preview.add_child(anchor)
	var first: int = layer.play("sweat", anchor, 2.0, Vector3.ZERO, Vector2(0.1, 0.2), 0, &"test")
	var replacement: int = layer.play(
		"tear", anchor, 2.0, Vector3.ZERO, Vector2(0.1, 0.2), 0, &"test"
	)
	_check(
		first != replacement and layer.active_count() == 1,
		"Same-key replacement retires previous token"
	)
	layer.cancel(first)
	_check(layer.active_count() == 1, "Retired token cannot cancel replacement")
	layer.paused = true
	layer.advance(5.0)
	_check(layer.active_count() == 1, "Paused comic retains lifetime")
	layer.paused = false
	layer.advance(2.1)
	_check(layer.active_count() == 0, "Comic expiry removes actual effect node")
	layer.play("sweat", anchor)
	_wardrobe.preview.remove_child(anchor)
	layer.advance(0.0)
	_check(layer.active_count() == 0, "Anchor leaving the scene retires its attached effect")
	anchor.free()
	layer.clear()
	await _capture("comics_restored")
	_check(
		_same_image("baseline", "comics_restored"), "All comic lifecycles restore exact baseline"
	)


func _hair_occlusion() -> void:
	var size := Vector2(_wardrobe.viewport.size)
	# Keep the old silhouette-straddling probe as an explicit negative control.
	await _hair_occlusion_at(size * Vector2(540.0 / 1152.0, 0.5), "edge_", false)
	# Authored sample bangs: the entire card must sit behind the actual hair surface.
	await _hair_occlusion_at(size * Vector2(420.0 / 1152.0, 300.0 / 720.0), "", true)


func _hair_occlusion_at(screen: Vector2, prefix: String, fully_covered: bool) -> void:
	var layer: Node3D = _wardrobe.framework.comics
	var camera: Camera3D = _wardrobe.camera
	var direction := camera.project_ray_normal(screen)
	var hit: Dictionary = _wardrobe.preview.intersect_role_ray(
		2, camera.project_ray_origin(screen), direction
	)
	_check(not hit.is_empty(), "Hair occlusion probe hits actual skinned hair")
	if hit.is_empty():
		return
	var anchor := Node3D.new()
	_wardrobe.turntable.add_child(anchor)
	anchor.global_position = hit.position + direction * 0.025
	var covered := 0
	var clearances: Array[float] = []
	for y in range(5):
		for x in range(5):
			var point := (
				anchor.global_position
				+ camera.global_basis.x * (x - 2) * 0.015
				+ camera.global_basis.y * (y - 2) * 0.015
			)
			var pixel := camera.unproject_position(point)
			var origin := camera.project_ray_origin(pixel)
			var surface: Dictionary = _wardrobe.preview.intersect_role_ray(
				2, origin, camera.project_ray_normal(pixel)
			)
			if not surface.is_empty():
				var clearance: float = point.distance_to(origin) - surface.distance
				clearances.append(clearance)
				if clearance > 0.0:
					covered += 1
	_measurements[prefix + "hair_coverage"] = {
		"screen": str(screen), "covered": covered, "samples": 25, "clearances": clearances
	}
	_check(
		covered == 25 if fully_covered else covered < 25,
		prefix + "Actual card footprint satisfies the declared hair coverage precondition"
	)
	await _capture(prefix + "hair_only")
	layer.play("anger", anchor, 3.0, Vector3.ZERO, Vector2(0.06, 0.06))
	layer.advance(0.1)
	layer.paused = true
	await _capture(prefix + "comic_behind_hair")
	_check(
		_same_image(prefix + "hair_only", prefix + "comic_behind_hair") == fully_covered,
		(
			"Scene mode is occluded by real hair shader"
			if fully_covered
			else "Silhouette-straddling card is not assumed fully occluded by its center hit"
		)
	)
	layer.clear()
	layer.play("anger", anchor, 3.0, Vector3.ZERO, Vector2(0.06, 0.06), layer.Occlusion.OVERLAY)
	layer.paused = false
	layer.advance(0.1)
	layer.paused = true
	await _capture(prefix + "comic_overlay_hair")
	_check(
		not _same_image(prefix + "hair_only", prefix + "comic_overlay_hair"),
		"Overlay is visible through the same real hair"
	)
	layer.clear()
	_wardrobe.framework.diagnostics.set_hair_hidden(true)
	await _capture(prefix + "hair_hidden")
	layer.play("anger", anchor, 3.0, Vector3.ZERO, Vector2(0.06, 0.06))
	layer.paused = false
	layer.advance(0.1)
	layer.paused = true
	await _capture(prefix + "comic_hair_removed")
	_check(
		not _same_image(prefix + "hair_hidden", prefix + "comic_hair_removed"),
		"Removing hair exposes the scene-mode comic"
	)
	layer.clear()
	layer.paused = false
	_wardrobe.framework.diagnostics.set_hair_hidden(false)
	anchor.free()


func _occlusion() -> void:
	var layer: Node3D = _wardrobe.framework.comics
	var anchor := Node3D.new()
	_wardrobe.turntable.add_child(anchor)
	anchor.position = Vector3(-0.43, 2.60, 0.4)
	var blocker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.40)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.05, 0.08, 0.12)
	quad.material = material
	blocker.mesh = quad
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wardrobe.turntable.add_child(blocker)
	blocker.global_position = anchor.global_position + _wardrobe.camera.global_basis.z * 0.1
	blocker.global_basis = _wardrobe.camera.global_basis
	await _capture("occluder_only")
	layer.play("anger", anchor, 3.0)
	layer.advance(0.1)
	layer.paused = true
	await _capture("comic_scene_blocked")
	_check(
		_same_image("occluder_only", "comic_scene_blocked"),
		"Scene comic accepts real foreground occlusion"
	)
	layer.clear()
	layer.play("anger", anchor, 3.0, Vector3.ZERO, Vector2(0.18, 0.22), layer.Occlusion.OVERLAY)
	layer.paused = false
	layer.advance(0.1)
	layer.paused = true
	await _capture("comic_overlay_blocker")
	_check(
		not _same_image("occluder_only", "comic_overlay_blocker"),
		"Overlay explicitly ignores the same foreground occluder"
	)
	layer.clear()
	blocker.hide()
	await _capture("occluder_hidden")
	layer.play("anger", anchor, 3.0)
	layer.paused = false
	layer.advance(0.1)
	layer.paused = true
	await _capture("comic_scene_unblocked")
	_check(
		not _same_image("occluder_hidden", "comic_scene_unblocked"),
		"Scene comic is visible when occluder is removed"
	)
	layer.clear()
	layer.paused = false
	blocker.free()
	anchor.free()
