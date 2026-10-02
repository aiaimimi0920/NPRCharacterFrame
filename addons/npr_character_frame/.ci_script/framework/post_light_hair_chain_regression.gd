extends "res://addons/npr_character_frame/.ci_script/framework/hair_affine_regression.gd"
## Both real stencil passes; direct before-tonal-map oracle versus production hook.


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	_lab = load("res://addons/npr_character_frame/showcase/npr_lab.tscn").instantiate()
	root.add_child(_lab)
	await _frames(8)
	_lab.set_view("face")
	_lab.preview.set_fill_strength(0.0)
	_lab.preview.set_shadow_strength(0.65)
	_lab.preview.set_hair_contact(0.0)
	RenderingServer.global_shader_parameter_set("g_u_rim_shadow_color", Color(0.8, 0.9, 1.0, 0.7))
	RenderingServer.global_shader_parameter_set("g_u_rim_shadow_intensity", 1.0)
	_hair.assign([_lab.preview.materials[2], _lab.preview.materials[2].next_pass])
	_lab.preview.meshes[0].hide()
	for node in _lab.turntable.get_parent().get_children():
		if node is MeshInstance3D:
			node.hide()
	_prepare_shaders()
	for effect in ["level", "split", "negative", "combined"]:
		_set_effect("combined")
		_set_parameter("g_u_level_adjust_on", effect in ["level", "combined"])
		_set_parameter("u_level_white_point", 0.95)
		_set_parameter("u_level_mid_point", 0.48)
		_set_parameter("u_level_black_point", 0.1)
		_set_parameter("u_level_light_color", Color(0.8, 0.5, 1.0, 0.5))
		_set_parameter("u_level_shadow_color", Color(0.6, 0.8, 1.0, 0.5))
		_set_parameter(
			"u_accent_split_tone_strength", 0.65 if effect in ["split", "combined"] else 0.0
		)
		_set_parameter("u_contrast_strength", -1.3 if effect == "negative" else 1.6)
		for mode in [0, 1, 2, 3]:
			_set_parameter("u_dither_mask", mode)
			for attenuation in [1.0, 0.25]:
				for fill in [0.0, 0.7, 3.0]:
					await _oracle("%s_mode_%d" % [effect, mode], attenuation, fill)
		_set_parameter("u_dither_mask", 0)
		_set_parameter("test_attenuation", 0.25)
		_set_parameter("test_fill", 0.7)
		_set_variant("legacy")
		await _capture(effect + "_legacy_safe_off")
		_response_pairs.append(
			{
				"first": effect + "_mode_0_0.25_0.70_reference",
				"second": effect + "_legacy_safe_off",
				"minimum": 30
			}
		)
	await _post_entry_checks()
	_set_variant("original")
	var file := FileAccess.open(_output.path_join("nonlinear_checks.json"), FileAccess.WRITE)
	(
		file
		. store_string(
			(
				JSON
				. stringify(
					{
						"checks": _checks,
						"oracle": _oracle_pairs,
						"responses": _response_pairs,
						"inputs":
						{
							"engine": Engine.get_version_info(),
							"shader_sha256": FileAccess.get_sha256(COMMON),
							"fixture_sha256": FileAccess.get_sha256(get_script().resource_path),
							"affine_fixture_sha256":
							(
								FileAccess
								. get_sha256(
									"res://addons/npr_character_frame/.ci_script/framework/hair_affine_regression.gd"
								)
							),
							"silhouette_strength":
							_hair[0].get_shader_parameter("u_npr_hair_silhouette_strength")
						}
					},
					"  "
				)
			)
		)
	)
	_lab.queue_free()
	await process_frame
	var failed := _checks.any(func(item): return not item["pass"])
	print("HAIR_CHAIN_CAPTURE pairs=", _oracle_pairs.size(), " run image gate for acceptance")
	print("REGRESSION_FAILED" if failed else "REGRESSION_OK")
	quit(1 if failed else 0)


func _prepare_shaders() -> void:
	_variants = {"original": [], "transport": [], "reference": [], "legacy": []}
	var capability := Shader.new()
	capability.code = """
shader_type spatial;
#ifdef HAS_MATERIAL_POST_LIGHT
uniform bool actual_post_light_capability = true;
#endif
void fragment() { ALBEDO = vec3(1.0); }
"""
	_check(
		capability.get_shader_uniform_list().any(
			func(uniform): return uniform["name"] == "actual_post_light_capability"
		),
		"Require native post_light, not legacy safe-off"
	)
	var common := FileAccess.get_file_as_string(COMMON)
	for material in _hair:
		_variants.original.append(material.shader)
		var source: String = material.shader.code.replace('#include "%s"' % COMMON, common)
		var offset := source.find("void light() {")
		_check(offset > 0, "Expand actual hair entry and retain production post_light")
		var prefix := source.substr(0, offset).replace(
			"void fragment() {", PROBE + "\nvoid fragment() {"
		)
		prefix = _controlled_shadow_prefix(prefix)
		var light := (
			"void light() { MATERIAL_LIGHT_DATA.w = "
			+ "1.0 - clamp(u_npr_shadow_strength, 0.0, 1.0) * (1.0 - test_attenuation);"
			+ " DIFFUSE_LIGHT = %s; SPECULAR_LIGHT += %s; }" % [SHADOW, FILL]
		)
		_add_shader("transport", prefix + light)
		_add_shader(
			"legacy",
			(
				prefix.replace(
					"shader_type spatial;",
					"shader_type spatial;\n#define NPR_HAIR_LEGACY_REFERENCE\n"
				)
				+ light
			)
		)
		var anchor := "vec3 tonal_mapped_color = apply_tonal_mapping(diffuse_ramp_color, is_skin);"
		_check(prefix.count(anchor) == 1, "Reference injects BEFORE tonal mapping, not after it")
		var reference := prefix.replace(
			"shader_type spatial;", "shader_type spatial;\n#define NPR_HAIR_LEGACY_REFERENCE\n"
		)
		reference = reference.replace(
			anchor,
			(
				"diffuse_ramp_color = diffuse_ramp_color * test_ratio()"
				+ " + "
				+ REFERENCE_FILL
				+ ";\n"
				+ anchor
			)
		)
		reference = reference.replace(
			"final_color += npr_specular_contribution;",
			(
				"final_color += npr_specular_contribution * "
				+ "(1.0 - clamp(u_npr_shadow_strength, 0.0, 1.0) * (1.0 - test_attenuation));"
			)
		)
		_add_shader("reference", reference + "void light() {}")


func _post_entry_checks() -> void:
	var mesh: MeshInstance3D = _lab.preview.meshes[2]
	var focus: Vector3 = mesh.global_transform * mesh.get_aabb().get_center() + Vector3.UP * 0.2
	_lab.camera.global_position = focus + _lab.camera.global_basis.z * 1.1
	_lab.camera.look_at(focus)
	_set_variant("transport")
	await _capture("post_both_entries")
	for index in range(_hair.size()):
		_set_variant("transport")
		var shader := Shader.new()
		var source := _hair[index].shader.code
		var anchor := "POST_LIGHT_COLOR = npr_dither_color(color, u_dither_mask, FRAGCOORD.xy);"
		_check(source.count(anchor) == 1, "Blacken only the actual post stage of entry %d" % index)
		shader.code = source.replace(anchor, "POST_LIGHT_COLOR = vec3(0.0);")
		_hair[index].shader = shader
		await _capture("post_entry_%d_black" % index)
		_response_pairs.append(
			{"first": "post_both_entries", "second": "post_entry_%d_black" % index, "minimum": 30}
		)
