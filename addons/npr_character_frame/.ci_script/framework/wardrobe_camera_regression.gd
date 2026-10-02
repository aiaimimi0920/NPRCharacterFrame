extends "res://addons/npr_character_frame/.ci_script/framework/wardrobe_display_regression.gd"
## UI-01..03: real input routing, projection, isolation and lifecycle checks.

var _measurements: Array[Dictionary] = []


func _run() -> void:
	root.size = Vector2i(1440, 900)
	root.mouse_passthrough = true
	root.unfocusable = true
	_spawn()
	await _frames()
	var initial := _camera_state()
	var saved: Dictionary = _wardrobe.state.to_data()
	await _test_drags()
	await _test_releases()
	await _test_zoom()
	await _test_switches()
	_check(_wardrobe.state.to_data() == saved, "Camera input never mutates saved wardrobe choices")
	await _press("Save")
	var framing := _camera_state()
	await _press("Reset")
	_check(_camera_state() == framing, "Scheme reset preserves framing")
	var reset: Button = _wardrobe.find_child("ResetView", true, false)
	_check(reset != null, "An explicit reset-view control is available")
	if reset != null:
		await _press("Section7")
		var fov: HSlider = _wardrobe.find_child("Debug镜头视场角", true, false)
		fov.value = 49.0
		await _press("DisplayWhite")
		var choices: Dictionary = _wardrobe.state.to_data()
		await _press("ResetView")
		_check(_camera_state() == initial, "Reset view restores full default framing and yaw")
		_check(_wardrobe.state.to_data() == choices, "Reset view preserves saved wardrobe choices")
		_check(_wardrobe.display.mode == "white", "Reset view preserves diagnostic display mode")
		_check(is_equal_approx(fov.value, 36.0), "Reset view refreshes FOV control to default")
		var repeat := _camera_state()
		await _press("ResetView")
		_check(_camera_state() == repeat, "Reset view is idempotent")
		await _press("DisplayRender")
	await _capture("final_view")
	FileAccess.open(_output.path_join("camera_measurements.json"), FileAccess.WRITE).store_string(
		JSON.stringify(_measurements, "  ")
	)
	_wardrobe.free()
	await _frames()
	_spawn()
	await _frames()
	_check(
		_camera_state() == initial, "Recreated scene starts with default camera, not saved framing"
	)
	_finish()


func _fresh_camera() -> void:
	_wardrobe._target = Vector3(0, 1.55, 0)
	_wardrobe._camera_pitch = 0.0
	_wardrobe.turntable.rotation = Vector3.ZERO
	_wardrobe._model_yaw_degrees = 0.0
	_wardrobe.camera.fov = 36.0
	_wardrobe.set_view("full")


func _test_drags() -> void:
	_fresh_camera()
	var before := _camera_state()
	await _drag(MOUSE_BUTTON_LEFT, Vector2(580, 450), Vector2(650, 450))
	_check(_wardrobe.turntable.rotation.y > 0.1, "Horizontal left drag rotates the model")
	_check(
		_wardrobe.camera.transform == before[0], "Horizontal rotation does not pan or pitch camera"
	)
	await _drag(MOUSE_BUTTON_LEFT, Vector2(650, 450), Vector2(580, 450))
	_check(
		is_zero_approx(_wardrobe.turntable.rotation.y), "Opposite horizontal drag reverses rotation"
	)
	var yaw: float = _wardrobe.turntable.rotation.y
	await _drag(MOUSE_BUTTON_LEFT, Vector2(580, 450), Vector2(580, 390))
	_check(_wardrobe._camera_pitch < 0.0, "Upward left drag lowers viewpoint to see the chin")
	_check(_wardrobe.turntable.rotation.y == yaw, "Vertical left drag does not turn the model")
	await _capture("pitch_up")
	await _drag(MOUSE_BUTTON_LEFT, Vector2(580, 390), Vector2(580, 450))
	_check(is_zero_approx(_wardrobe._camera_pitch), "Opposite vertical drag restores pitch")
	for direction in [-1.0, 1.0]:
		for step in 4:
			await _drag(MOUSE_BUTTON_LEFT, Vector2(580, 450), Vector2(580, 450 + 160 * direction))
		_check(
			is_equal_approx(_wardrobe._camera_pitch, 35.0 * direction),
			"Pitch is clamped at " + str(direction)
		)
		var limit := _camera_state()
		await _drag(MOUSE_BUTTON_LEFT, Vector2(580, 450), Vector2(580, 450 + 160 * direction))
		_check(_camera_state() == limit, "Dragging past pitch limit cannot flip the camera")
	_fresh_camera()
	var target: Vector3 = _wardrobe._target
	yaw = _wardrobe.turntable.rotation.y
	var basis: Basis = _wardrobe.camera.basis
	var distance: float = _wardrobe._distance
	await _drag(MOUSE_BUTTON_MIDDLE, Vector2(580, 450), Vector2(650, 480))
	_check(
		_wardrobe._target.y > target.y, "Middle drag vertically translates the observation target"
	)
	_check(
		_wardrobe._target.x == target.x and _wardrobe._target.z == target.z,
		"Horizontal component of middle drag is ignored"
	)
	_check(_wardrobe.camera.basis.is_equal_approx(basis), "Middle pan preserves camera orientation")
	_check(
		_wardrobe._distance == distance and _wardrobe.turntable.rotation.y == yaw,
		"Middle pan preserves zoom and yaw"
	)
	await _capture("middle_pan")
	await _drag(MOUSE_BUTTON_MIDDLE, Vector2(650, 480), Vector2(580, 450))
	_check(_wardrobe._target.is_equal_approx(target), "Opposite middle pan restores target")
	_mouse(MOUSE_BUTTON_LEFT, Vector2(580, 450), true)
	_mouse(MOUSE_BUTTON_MIDDLE, Vector2(580, 450), true)
	var pitch: float = _wardrobe._camera_pitch
	_motion(Vector2(600, 470), Vector2(20, 20), MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)
	_check(
		_wardrobe._camera_pitch == pitch and _wardrobe.turntable.rotation.y == yaw,
		"Middle drag has priority while both buttons are held"
	)
	_mouse(MOUSE_BUTTON_LEFT, Vector2(600, 470), false)
	_mouse(MOUSE_BUTTON_MIDDLE, Vector2(600, 470), false)


func _test_releases() -> void:
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		_fresh_camera()
		_mouse(button, Vector2(580, 450), true)
		_mouse(button, Vector2(1300, 400), false)
		var released := _camera_state()
		_motion(Vector2(600, 470), Vector2(20, 20), 0)
		_check(
			_camera_state() == released, "Release over options panel cancels drag: " + str(button)
		)
		_mouse(button, Vector2(580, 450), true)
		_wardrobe.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		_check(
			not _wardrobe._dragging and not _wardrobe._middle_dragging,
			"Focus loss cancels drag: " + str(button)
		)
		var defocused := _camera_state()
		_motion(Vector2(600, 470), Vector2(20, 20), 0)
		_check(
			_camera_state() == defocused, "Returning without a pressed button cannot move camera"
		)
		_mouse(button, Vector2(600, 470), false)
	_fresh_camera()
	var unchanged := _camera_state()
	# Input beginning in a UI panel must never start viewport dragging.
	await _drag(MOUSE_BUTTON_MIDDLE, Vector2(1300, 400), Vector2(580, 450))
	_check(_camera_state() == unchanged, "Middle input starting on options does not pan scene")


func _test_zoom() -> void:
	for size in [Vector2i(1152, 720), Vector2i(1440, 900)]:
		root.size = size
		await _frames()
		for view in ["full", "half", "face"]:
			_fresh_camera()
			_wardrobe.set_view(view)
			await _frames()
			for button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var hit := _surface_hit()
				_check(not hit.is_empty(), "Real model hit available for zoom " + view + str(size))
				if hit.is_empty():
					continue
				var distance: float = _wardrobe._distance
				var pitch: float = _wardrobe._camera_pitch
				var yaw: float = _wardrobe.turntable.rotation.y
				_mouse(button, hit.point, true)
				_mouse(button, hit.point, false)
				await _frames()
				var moved: float = _wardrobe._distance - distance
				_check(
					moved < 0.0 if button == MOUSE_BUTTON_WHEEL_UP else moved > 0.0,
					"Wheel changes distance in correct direction"
				)
				var error := _project(hit.position).distance_to(hit.point)
				_measurements.append(
					{"size": str(size), "view": view, "wheel": button, "pixel_error": error}
				)
				_check(
					error < 0.5,
					"Zoom holds picked surface under cursor within 0.5 px: " + str(error)
				)
				_check(
					_wardrobe._camera_pitch == pitch and _wardrobe.turntable.rotation.y == yaw,
					"Zoom preserves pitch and model yaw"
				)
				var snapshot := _camera_state()
				await _drag(MOUSE_BUTTON_LEFT, Vector2(500, 420), Vector2(500, 420))
				_check(_camera_state() == snapshot, "Zero drag after zoom cannot snap camera back")
	_fresh_camera()
	await _frames()
	var background := _camera_state()
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(280, 150), true)
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(280, 150), false)
	_check(_camera_state() == background, "Wheel over empty background is a no-op")
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(1300, 400), true)
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(1300, 400), false)
	_check(_camera_state() == background, "Wheel over options cannot zoom the model")
	for direction in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		for step in 32:
			var hit := _surface_hit()
			if hit.is_empty():
				break
			_mouse(direction, hit.point, true)
			_mouse(direction, hit.point, false)
			await _frames()
		var expected := 0.35 if direction == MOUSE_BUTTON_WHEEL_UP else 7.5
		_check(
			is_equal_approx(_wardrobe._distance, expected),
			"Repeated wheel reaches bounded distance " + str(expected)
		)


func _test_switches() -> void:
	_fresh_camera()
	await _drag(MOUSE_BUTTON_LEFT, Vector2(580, 450), Vector2(650, 390))
	await _drag(MOUSE_BUTTON_MIDDLE, Vector2(580, 450), Vector2(580, 475))
	var hit := _surface_hit()
	if not hit.is_empty():
		_mouse(MOUSE_BUTTON_WHEEL_UP, hit.point, true)
		_mouse(MOUSE_BUTTON_WHEEL_UP, hit.point, false)
	var snapshot := _camera_state()
	var image_before := await _capture("adjusted")
	for index in 8:
		await _press("Section%d" % index)
		_check(
			_camera_state() == snapshot,
			"Category preserves transform, target, zoom and yaw: " + str(index)
		)
	await _press("Section0")
	var image_after := await _capture("category_return")
	_check(
		image_before.get_data() == image_after.get_data(),
		"A-B-A category switches preserve exact scene pixels"
	)
	for mode in ["DisplayWhite", "DisplaySkeleton", "DisplayRender"]:
		await _press(mode)
		_check(_camera_state() == snapshot, "Display mode preserves camera: " + mode)
	await _press("Section1")
	await _press("Equip1")
	_check(_wardrobe.state.equipment[0], "Equipment still changes while framing is preserved")
	_check(_camera_state() == snapshot, "Equipment enable preserves framing")
	await _press("Equip0")
	_check(not _wardrobe.state.equipment[0], "Equipment can return to unequipped state")
	await _press("Section0")
	await _press("Palette1")
	_check(_wardrobe.state.palette == 1, "Palette switch still takes effect")
	_check(_camera_state() == snapshot, "Palette switch preserves framing")
	await _press("Palette0")


func _surface_hit() -> Dictionary:
	var camera: Camera3D = _wardrobe.camera
	var pose := camera.get_camera_transform()
	var inverse := camera.get_camera_projection().inverse()
	for uv in [
		Vector2(0.43, 0.45),
		Vector2(0.43, 0.55),
		Vector2(0.40, 0.4),
		Vector2(0.48, 0.5),
		Vector2(0.5, 0.35)
	]:
		var local := inverse * Vector4(uv.x * 2 - 1, 1 - uv.y * 2, 1, 1)
		var ray := (pose.basis * (Vector3(local.x, local.y, local.z) / local.w)).normalized()
		var hit: Dictionary = _wardrobe.preview.pick_surface(pose.origin, ray)
		if not hit.is_empty():
			hit.point = uv * _wardrobe._stage.size
			return hit
	return {}


func _project(world: Vector3) -> Vector2:
	var camera: Camera3D = _wardrobe.camera
	var local := camera.get_camera_transform().affine_inverse() * world
	var clip := camera.get_camera_projection() * Vector4(local.x, local.y, local.z, 1)
	return (Vector2(clip.x, -clip.y) / clip.w * 0.5 + Vector2.ONE * 0.5) * _wardrobe._stage.size


func _motion(point: Vector2, relative: Vector2, mask: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.relative = relative
	motion.button_mask = mask
	root.push_input(motion)
