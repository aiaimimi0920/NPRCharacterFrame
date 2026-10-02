extends "framework_quality_comic_regression.gd"
## Spawn once, then orbit the same token: no camera-relative re-layout after birth.


func _run() -> void:
	_spawn()
	_wardrobe.select_section(8)
	var workbench: Node = _wardrobe.framework
	var layer: Node3D = workbench.comics
	var camera: Camera3D = _wardrobe.camera
	var original_camera := camera.transform
	layer.set_process(false)
	workbench.set_comic_hold(true)
	for kind in ["sweat", "anger", "emphasis"]:
		for mode in ["actor", "camera"]:
			camera.transform = original_camera
			_wardrobe.turntable.rotation_degrees.y = 0.0
			workbench.play_comic(kind)
			var effect: Dictionary = layer._effects[0]
			var mesh: MeshInstance3D = effect.mesh
			var fixed: Vector3 = workbench._anchor.to_local(mesh.global_position)
			var token: int = effect.token
			for view in 8:
				if mode == "actor":
					_wardrobe.turntable.rotation_degrees.y = view * 45.0
				else:
					var center: Vector3 = workbench._anchor.global_position
					var radius := original_camera.origin.distance_to(center)
					var angle := deg_to_rad(view * 45.0)
					camera.global_position = center + Vector3(sin(angle), 0.0, cos(angle)) * radius
					camera.look_at(center)
				layer.advance(0.0)
				_check(layer._effects[0].token == token, kind + " keeps the same token: " + mode)
				_check(
					workbench._anchor.to_local(mesh.global_position).distance_to(fixed) < 0.00001,
					kind + " keeps spawn-local position: %s / %d" % [mode, view]
				)
				var label := "%s_%s_%d" % [kind, mode, view]
				effect.material.set_shader_parameter("opacity", 0.0)
				await _capture(label + "_off")
				effect.material.set_shader_parameter("opacity", 1.0)
				await _capture(label)
				if view == 0:
					_check(
						not _same_image(label, label + "_off"), label + " starts visibly at preset"
					)
				if view in [3, 4, 5]:
					_check(
						_same_image(label, label + "_off"), label + " no ghost on the opposite side"
					)
			workbench.clear_effects()
		camera.transform = original_camera
		_wardrobe.turntable.rotation_degrees.y = 180.0
		workbench.play_comic(kind)
		layer.advance(0.0)
		var mesh: MeshInstance3D = layer._effects[0].mesh
		var fixed: Vector3 = workbench._anchor.to_local(mesh.global_position)
		_check(mesh.visible, kind + " can spawn at preset while viewing the back")
		_wardrobe.turntable.rotation_degrees.y = 0.0
		layer.advance(0.0)
		_check(not mesh.visible, kind + " rear-born token does not relocate to the face")
		_check(
			workbench._anchor.to_local(mesh.global_position).distance_to(fixed) < 0.00001,
			kind + " rear-born local position remains fixed"
		)
		workbench.clear_effects()
	workbench.play_comic("sweat")
	var mesh: MeshInstance3D = layer._effects[0].mesh
	var local: Vector3 = workbench._anchor.to_local(mesh.global_position)
	_wardrobe.performance.action = "look_around"
	_wardrobe.performance.apply_pose(1.0)
	layer.advance(0.0)
	_check(
		workbench._anchor.to_local(mesh.global_position).distance_to(local) < 0.00001,
		"Pinned symbol follows actual head bone motion"
	)
	workbench.set_comic_hold(false)
	layer.advance(2.0)
	_check(layer.active_count() == 0, "Pinned symbols expire after hold release")
	_finish("COMIC_SPAWN_PIN")
