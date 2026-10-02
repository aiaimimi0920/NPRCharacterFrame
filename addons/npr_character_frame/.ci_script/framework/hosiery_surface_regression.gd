extends "res://addons/npr_character_frame/.ci_script/framework/hosiery_lookdev.gd"
## Single-layer alpha oracle and production shell rotation/feature-off controls.


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("unused_scheme.json")
	root.add_child(_wardrobe)
	_wardrobe.performance.automatic = false
	_wardrobe.performance.set_process(false)
	_wardrobe.state.blink = false
	_wardrobe.state.secondary = false
	_wardrobe.state.tulle_geometry_enabled = true
	_wardrobe.state.hosiery_stitch = 1.0
	_wardrobe._apply_state()
	_wardrobe.performance.apply_pose(0.0)
	_wardrobe.preview.character.set_shadows_enabled(false)
	_wardrobe._environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_wardrobe._environment.tonemap_exposure = 1.0
	_wardrobe.camera.h_offset = 0.0
	_wardrobe.camera.position = Vector3(0, 1.12, 1.65)
	_wardrobe.camera.look_at(Vector3(0, 1.0, 0))
	await _frames(5)
	var shell: MeshInstance3D = _wardrobe.visual_layers._fitted_hosiery
	var production: ShaderMaterial = shell.material_override
	_check(shell.mesh == _wardrobe.preview.meshes[0].mesh, "Oracle uses actual fitted mesh")
	_check(shell.skin != null, "Oracle has active skin")
	for angle in range(0, 360, 30):
		_wardrobe.turntable.rotation_degrees.y = angle
		shell.visible = false
		await _capture("rotation_off_%d" % angle)
		shell.visible = true
		await _capture("rotation_on_%d" % angle)
		production.set_shader_parameter("opacity", 0.0)
		await _capture("rotation_zero_%d" % angle)
		production.set_shader_parameter("opacity", 0.5)
	var oracle: ShaderMaterial = production.duplicate()
	var shader := Shader.new()
	shader.code = production.shader.code.replace(
		"blend_mix, depth_draw_never, cull_back", "unshaded, blend_mix, depth_draw_never, cull_back"
	)
	shader.code = shader.code.replace(
		"uniform float opacity = 0.5;",
		"uniform float opacity = 0.5; uniform vec4 oracle_color = vec4(1.0);"
	)
	shader.code = shader.code.replace(
		"ALPHA = domain * opacity * mix(0.25, 0.6, hem);",
		"ALBEDO = oracle_color.rgb; ALPHA = domain * oracle_color.a;"
	)
	oracle.shader = shader
	shell.material_override = oracle
	for angle in [0, 65, 180]:
		_wardrobe.turntable.rotation_degrees.y = angle
		shell.visible = false
		await _capture("base_%d" % angle)
		shell.visible = true
		oracle.set_shader_parameter("oracle_color", Vector4(1, 1, 1, 1))
		await _capture("mask_%d" % angle)
		for alpha in [0.2, 0.5]:
			oracle.set_shader_parameter("oracle_color", Vector4(0, 0, 0, alpha))
			await _capture("alpha_%d_%d" % [angle, roundi(alpha * 100)])
		if angle == 0:
			var wrong := Shader.new()
			wrong.code = shader.code.replace(
				"depth_draw_never, cull_back",
				"depth_draw_never, depth_test_disabled, cull_disabled"
			)
			oracle.shader = wrong
			oracle.render_priority = 0
			await _capture("backface_depth_disabled")
			oracle.shader = shader
			oracle.render_priority = production.render_priority
			var backfaces := Shader.new()
			backfaces.code = shader.code.replace("cull_back", "cull_front")
			oracle.shader = backfaces
			await _capture("backfaces_depth_on")
			oracle.shader = shader
			var blocker := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.22, 0.18, 0.03)
			blocker.mesh = box
			var opaque := StandardMaterial3D.new()
			opaque.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			opaque.albedo_color = Color(1, 0, 1)
			blocker.material_override = opaque
			_wardrobe.camera.add_child(blocker)
			blocker.position = Vector3(0, 0, -0.8)
			shell.visible = false
			await _capture("occluder_off")
			shell.visible = true
			await _capture("occluder_on")
			var no_depth := Shader.new()
			no_depth.code = shader.code.replace(
				"depth_draw_never", "depth_draw_never, depth_test_disabled"
			)
			oracle.shader = no_depth
			await _capture("occluder_depth_disabled")
			oracle.shader = shader
			blocker.free()
	shell.material_override = production
	_wardrobe.turntable.rotation_degrees.y = 0
	await _capture("rotation_restored")
	await _capture_cuff(production)
	await _capture_leg_ao()
	FileAccess.open(_output.path_join("surface.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"checks": _checks,
				"captures": _captures,
				"engine": Engine.get_version_info(),
				"gpu": RenderingServer.get_video_adapter_name(),
				"material_sha256":
				FileAccess.get_sha256(
					"res://addons/npr_character_frame/showcase/wardrobe_visual_layers.gd"
				),
				"shader_sha256": FileAccess.get_sha256(production.shader.resource_path)
			},
			"\t"
		)
	)
	var passed := _checks.all(func(row: Dictionary) -> bool: return row["pass"])
	_wardrobe.free()
	print("REGRESSION_OK" if passed else "REGRESSION_FAILED")
	quit(0 if passed else 1)


func _capture_cuff(material: ShaderMaterial) -> void:
	var source: NPRHosieryProfile = _wardrobe.preview.definition.hosiery_profile
	var body: ShaderMaterial = _wardrobe.preview.materials[0]
	await _capture("cuff_default")
	var baseline := Image.load_from_file(_output.path_join("cuff_default.png")).get_data()
	for values in [
		["cuff_band_width", 0.06],
		["cuff_stitch_offset", 0.08],
		["cuff_stitch_width", 0.02],
		["textile_period_m", 0.01],
		["textile_repeats", 2],
		["shell_offset_m", 0.005],
	]:
		var profile := source.duplicate() as NPRHosieryProfile
		profile.set(values[0], values[1])
		_check(profile.validate().is_empty(), str(values[0]) + " alternate validates")
		profile.apply_cuff(body)
		profile.apply_cuff(material)
		profile.apply_textile(body)
		profile.apply_textile(material)
		var uniform_name: String = "u_npr_hosiery_" + str(values[0])
		_check(
			(
				is_equal_approx(body.get_shader_parameter(uniform_name), values[1])
				and is_equal_approx(material.get_shader_parameter(uniform_name), values[1])
			),
			str(values[0]) + " binds both Body and fitted layer"
		)
		await _capture(str(values[0]))
		var changed := Image.load_from_file(_output.path_join(str(values[0]) + ".png")).get_data()
		_check(changed != baseline, str(values[0]) + " changes the actual fitted render")
	source.apply_cuff(body)
	source.apply_cuff(material)
	source.apply_textile(body)
	source.apply_textile(material)
	await _capture("cuff_restored")
	_check(
		Image.load_from_file(_output.path_join("cuff_restored.png")).get_data() == baseline,
		"Restoring source cuff restores exact pixels"
	)


func _capture_leg_ao() -> void:
	var source: NPRHosieryProfile = _wardrobe.preview.definition.hosiery_profile
	var body: ShaderMaterial = _wardrobe.preview.materials[0]
	await _capture("ao_default")
	var baseline := Image.load_from_file(_output.path_join("ao_default.png")).get_data()
	var profile := source.duplicate() as NPRHosieryProfile
	profile.leg_ao_repair_uv = Vector4(0, 0, 1, 1)
	profile.leg_ao_repair_values = Vector3(0, 3, 1)
	profile.leg_ao_repair_enabled = true
	_check(profile.validate().is_empty(), "Alternate AO calibration validates")
	profile.apply_body_material(body)
	_check(
		(
			body.get_shader_parameter("u_npr_leg_ao_repair_uv") == profile.leg_ao_repair_uv
			and (
				body.get_shader_parameter("u_npr_leg_ao_repair_values")
				== profile.leg_ao_repair_values
			)
		),
		"Alternate AO bounds and floor reach Body uniforms"
	)
	await _capture("ao_alternate")
	var repaired := Image.load_from_file(_output.path_join("ao_alternate.png")).get_data()
	_check(repaired != baseline, "Alternate AO calibration changes actual render")
	profile.leg_ao_repair_enabled = false
	profile.apply_body_material(body)
	await _capture("ao_disabled")
	var disabled := Image.load_from_file(_output.path_join("ao_disabled.png")).get_data()
	_check(disabled != repaired, "Disabling AO repair removes its visual effect")
	profile.leg_ao_repair_values = Vector3(0.5, 1.5, 0.1)
	profile.apply_body_material(body)
	await _capture("ao_disabled_changed")
	_check(
		Image.load_from_file(_output.path_join("ao_disabled_changed.png")).get_data() == disabled,
		"Disabled AO ignores changed calibration"
	)
	source.apply_body_material(body)
	await _capture("ao_restored")
	_check(
		Image.load_from_file(_output.path_join("ao_restored.png")).get_data() == baseline,
		"Source AO calibration restores exact pixels"
	)
