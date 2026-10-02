extends "res://addons/npr_character_frame/.ci_script/model/check_model.gd"
## Shared six-view evidence; no AI call and no aesthetic pass claim.

const ANGLES := [-90, -45, 0, 45, 90, 180]


func _run() -> void:
	_collect()
	if not _report.compliance_errors.is_empty():
		_finish()
		return
	var output_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_output)
	)
	if output_error != OK:
		_issue("output", "Cannot create screenshot directory")
		_finish()
		return
	root.size = Vector2i(768, 768)
	var actor := NPRCharacter.new()
	actor.definition = _definition
	root.add_child(actor)
	await process_frame
	if not actor.initialized:
		_issue("runtime", "; ".join(actor.validation_errors))
		actor.free()
		_finish()
		return
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.18, 0.18, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.3
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var bounds := actor.get_world_bounds()
	var target := bounds.get_center()
	target.y = bounds.position.y + bounds.size.y * 0.85
	camera.size = bounds.size.y * 0.45
	_report.case_id = "appearance.face_softness"
	_report.capture = {
		"projection": "orthographic",
		"size": camera.size,
		"target": [target.x, target.y, target.z],
		"resolution": [768, 768],
		"framing": "upper 45 percent of model height; review actual face visibility",
	}
	_report.views = []
	for angle: int in ANGLES:
		var radians := deg_to_rad(float(angle))
		camera.position = target + Vector3(sin(radians), 0, cos(radians)) * bounds.size.y * 2.0
		camera.look_at(target)
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var filename := "face_%+04d.png" % angle
		var image := root.get_texture().get_image()
		var save_error := image.save_png(_output.path_join(filename))
		if save_error != OK:
			_issue("capture", "Failed to save " + filename)
		_report.views.append({"yaw_degrees": angle, "image": filename})
	actor.free()
	camera.free()
	environment.free()
	_finish()
