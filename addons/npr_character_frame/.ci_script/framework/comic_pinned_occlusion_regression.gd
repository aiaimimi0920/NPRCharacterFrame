extends "framework_quality_comic_regression.gd"
## 有界真实头发夹具；验证 PINNED，不代表工作台出生避让或 Release UI 验收。


func _run() -> void:
	_spawn()
	_wardrobe.select_section(8)
	await _capture("baseline")
	var saved: Dictionary = _wardrobe.state.to_data()
	_measurements.pixel_pairs = []
	var size := Vector2(_wardrobe.viewport.size)
	await _pinned_hair(size * Vector2(420.0 / 1152.0, 300.0 / 720.0), "covered", true)
	await _pinned_hair(size * Vector2(540.0 / 1152.0, 0.5), "edge", false)
	await _capture("restored")
	_expect_pixels("baseline", "restored", true)
	_check(_wardrobe.state.to_data() == saved, "Fixture preserves saved scheme")
	_finish("COMIC_PINNED_OCCLUSION")


func _pinned_hair(screen: Vector2, label: String, fully_covered: bool) -> void:
	var layer: NPRComicLayer = _wardrobe.framework.comics
	var camera: Camera3D = _wardrobe.camera
	var direction := camera.project_ray_normal(screen)
	var hit: Dictionary = _wardrobe.preview.intersect_role_ray(
		2, camera.project_ray_origin(screen), direction
	)
	_check(not hit.is_empty(), label + " ray hits actual skinned hair")
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
	_measurements[label] = {
		"screen": str(screen), "covered": covered, "samples": 25, "clearances": clearances
	}
	_check(
		covered == 25 if fully_covered else covered < 25,
		label + " footprint meets declared depth precondition"
	)
	for mode in [NPRComicLayer.Occlusion.SCENE, NPRComicLayer.Occlusion.OVERLAY]:
		var prefix := label + ("_scene" if mode == NPRComicLayer.Occlusion.SCENE else "_overlay")
		await _capture(prefix + "_hair_empty")
		layer.paused = false
		var token := layer.play("anger", anchor, 3.0, Vector3.ZERO, Vector2(0.06, 0.06), mode)
		layer.advance(0.1)
		layer.pin(token, anchor.global_position)
		layer.paused = true
		var geometry := layer.geometry_snapshot(token)
		_check(not geometry.is_empty(), prefix + " has a live token")
		if geometry.is_empty():
			layer.clear()
			continue
		var effect: Dictionary = layer._effects[0]
		_check(effect.attachment == NPRComicLayer.Attachment.PINNED, prefix + " is PINNED")
		_check(effect.mesh.visible, prefix + " birth-facing guard allows visibility")
		_check(
			geometry.transform.origin.distance_to(anchor.global_position) < 0.000001,
			prefix + " pin preserves the measured depth position"
		)
		await _capture(prefix + "_hair_effect")
		_expect_pixels(
			prefix + "_hair_empty",
			prefix + "_hair_effect",
			fully_covered and mode == NPRComicLayer.Occlusion.SCENE
		)
		_wardrobe.framework.diagnostics.set_hair_hidden(true)
		await _capture(prefix + "_nohair_effect")
		_check(layer.geometry_snapshot(token) == geometry, prefix + " hair toggle keeps geometry")
		_check(layer._effects[0].token == token, prefix + " hair toggle keeps the same token")
		_wardrobe.framework.diagnostics.set_hair_hidden(false)
		await _capture(prefix + "_hair_restored")
		_expect_pixels(prefix + "_hair_effect", prefix + "_hair_restored", true)
		_wardrobe.framework.diagnostics.set_hair_hidden(true)
		layer.cancel(token)
		await _capture(prefix + "_nohair_empty")
		_expect_pixels(prefix + "_nohair_effect", prefix + "_nohair_empty", false)
		_expect_pixels(prefix + "_hair_empty", prefix + "_nohair_empty", false)
		_wardrobe.framework.diagnostics.set_hair_hidden(false)
		await _capture(prefix + "_empty_restored")
		_expect_pixels(prefix + "_hair_empty", prefix + "_empty_restored", true)
		_check(layer.geometry_snapshot(token).is_empty(), prefix + " cancel retires token")
		layer.paused = false
	anchor.free()


func _expect_pixels(first: String, second: String, equal: bool) -> void:
	_measurements.pixel_pairs.append({"first": first, "second": second, "equal": equal})
	_check(_same_image(first, second) == equal, first + " / " + second + " equal=" + str(equal))
