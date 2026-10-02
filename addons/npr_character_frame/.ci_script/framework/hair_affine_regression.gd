extends "res://addons/npr_character_frame/.ci_script/framework/pipeline_regression.gd"
## Actual two-pass hair: ordered fragment oracle vs affine light transport.

const COMMON := "res://addons/npr_character_frame/shaders/hair/hair_base_common.gdshaderinc"
const PROBE := """
uniform float test_attenuation = 0.25;
uniform float test_fill = 0.0;
uniform float test_shadow_factor = 0.04;

vec3 test_ratio() {
	vec2 uv = vec2(min(npr_ramp_uv_blend.x, 0.15), npr_ramp_uv_blend.y);
	vec3 ramp = mix(textureLod(u_texture_diffuse_ramp, uv, 0.0).rgb,
		textureLod(u_texture_diffuse_cool_ramp, uv, 0.0).rgb, npr_ramp_uv_blend.z);
	float visibility = 1.0 - clamp(u_npr_shadow_strength, 0.0, 1.0) * (1.0 - test_attenuation);
	return mix(min(ramp / max(npr_current_ramp, vec3(0.0001)), vec3(1.0)), vec3(1.0), visibility);
}
"""
const SHADOW := (
	"npr_shadow_delta(test_attenuation, " + "u_texture_diffuse_ramp, u_texture_diffuse_cool_ramp)"
)
const FILL := """
npr_fill_light(vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.7, 0.4, 0.2) * test_fill, 1.0)
+ npr_fill_light(vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.1, 0.3, 0.6) * test_fill, 0.6)
"""
# Keep each controlled light's scaling before accumulation. Factoring test_fill
# out of the sum changes float32 rounding and can cross a final quantization bin.
# This is an independent input calculation, not a call to npr_fill_light().
const REFERENCE_FILL := (
	"(vec3(0.7, 0.4, 0.2) * test_fill * (1.0 / PI)"
	+ " + vec3(0.1, 0.3, 0.6) * test_fill * (0.6 / PI))"
)
const EFFECTS := ["none", "contrast", "accent", "rim", "combined", "zero_gain"]

var _hair: Array[ShaderMaterial] = []
var _variants: Dictionary = {}
var _oracle_pairs: Array[Dictionary] = []
var _response_pairs: Array[Dictionary] = []
var _native_post_light := false


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
	# Captured globals have rim tint alpha zero and half intensity. Use explicit,
	# process-local non-neutral values so colored gain and negative-gain gates run.
	RenderingServer.global_shader_parameter_set("g_u_rim_shadow_color", Color(0.8, 0.9, 1.0, 0.7))
	RenderingServer.global_shader_parameter_set("g_u_rim_shadow_intensity", 1.0)
	_hair.assign([_lab.preview.materials[2], _lab.preview.materials[2].next_pass])
	# Keep the face/eye writer and both real stencil passes. Hide unrelated stage geometry.
	_lab.preview.meshes[0].hide()
	for node in _lab.turntable.get_parent().get_children():
		if node is MeshInstance3D:
			node.hide()
	_prepare_shaders()
	for effect in EFFECTS:
		_set_effect(effect)
		for attenuation in [1.0, 0.25, 0.0]:
			for fill in [0.0, 0.7]:
				await _oracle(effect, attenuation, fill)
		if effect in ["contrast", "rim", "combined"]:
			await _broken_gain(effect)
	await _clamp_check()
	await _entry_visibility_checks()
	await _real_light_checks()
	await _guard_checks()
	_set_variant("original")
	var report := {"checks": _checks, "oracle": _oracle_pairs, "responses": _response_pairs}
	var file := FileAccess.open(_output.path_join("hair_affine_checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	_lab.queue_free()
	await process_frame
	var failed := _checks.any(func(item): return not item["pass"])
	print("HAIR_AFFINE_CHECKS count=", _checks.size(), " oracle=", _oracle_pairs.size())
	print("REGRESSION_FAILED" if failed else "REGRESSION_OK")
	quit(1 if failed else 0)


func _prepare_shaders() -> void:
	var capability := Shader.new()
	capability.code = """
shader_type spatial;
#ifdef HAS_MATERIAL_POST_LIGHT
uniform bool actual_post_light_capability = true;
#endif
void fragment() { ALBEDO = vec3(1.0); }
"""
	_native_post_light = capability.get_shader_uniform_list().any(
		func(uniform): return uniform["name"] == "actual_post_light_capability"
	)
	for name in [
		"original",
		"transport",
		"reference",
		"broken_gain",
		"clamp",
		"clamp_reference",
		"wrong_clamp"
	]:
		_variants[name] = []
	var common := FileAccess.get_file_as_string(COMMON)
	for material in _hair:
		_variants.original.append(material.shader)
		var source: String = material.shader.code.replace('#include "%s"' % COMMON, common)
		var offset := source.find("void light() {")
		_check(offset > 0, "Expanded actual hair entrypoint")
		var prefix := source.substr(0, offset).replace(
			"void fragment() {", PROBE + "\nvoid fragment() {"
		)
		prefix = _controlled_shadow_prefix(prefix)
		var anchor := "float contrast_gain;"
		_check(prefix.count(anchor) == 1, "Ordered oracle precedes contrast, accent, and rim")
		var light := "void light() { DIFFUSE_LIGHT = %s; SPECULAR_LIGHT += %s; }" % [SHADOW, FILL]
		_add_shader("transport", prefix + light)
		_add_shader(
			"broken_gain",
			(prefix + light).replace(
				"npr_surface_color = albedo.rgb * fill_gain;", "npr_surface_color = albedo.rgb;"
			)
		)
		# Raw diffuse lighting changes BEFORE the existing color functions and albedo.
		# Specular is intentionally added later and receives only key visibility.
		var reference := prefix.replace(
			anchor,
			(
				"tonal_mapped_color = tonal_mapped_color * test_ratio() + "
				+ REFERENCE_FILL
				+ ";\n"
				+ anchor
			)
		)
		reference = (reference.replace(
			"final_color += npr_specular_contribution;",
			(
				"final_color += npr_specular_contribution * "
				+ "(1.0 - clamp(u_npr_shadow_strength, 0.0, 1.0) * (1.0 - test_attenuation));"
			)
		))
		reference = reference.replace(
			"shader_type spatial;", "shader_type spatial;\n#define NPR_HAIR_LEGACY_REFERENCE\n"
		)
		_add_shader("reference", reference + "void light() {}")
		# Force excessive shadow metadata without adding that energy to the base.
		# This directly tests the shared clamp's domain; normal physical inputs do not saturate it.
		var clamp_source := prefix.replace(
			"EMISSION = npr_final_color;",
			"npr_specular_contribution = vec3(8.0);\nEMISSION = npr_final_color;"
		)
		_add_shader("clamp", clamp_source + light)
		_add_shader(
			"wrong_clamp",
			(clamp_source + light).replace(
				(
					"npr_pre_composition_color = npr_diffuse_contribution "
					+ "+ npr_specular_contribution + edge_light;"
				),
				"npr_pre_composition_color = npr_final_color;"
			)
		)
		var direct := (
			prefix
			. replace(
				"EMISSION = npr_final_color;",
				"""
	float visibility = 1.0 - clamp(u_npr_shadow_strength, 0.0, 1.0) * (1.0 - test_attenuation);
	vec3 shadowed = max(rim_shadow_light * base_lit_color * silhouette_gain * test_ratio()
		+ npr_specular_contribution + edge_light - vec3(8.0) * (1.0 - visibility), vec3(0.0));
	EMISSION = shadowed + rim_shadow_light * (accented_light - base_lit_color) * silhouette_gain;
	"""
			)
		)
		direct = direct.replace(
			"shader_type spatial;", "shader_type spatial;\n#define NPR_HAIR_LEGACY_REFERENCE\n"
		)
		_add_shader("clamp_reference", direct + "void light() {}")


func _controlled_shadow_prefix(source: String) -> String:
	# The retired atlas now leaves a neutral fragment input. Keep the independent
	# oracle's contrast input observable, and fail when its production anchor moves.
	var anchor := "float shadow_factor = 1.0;"
	_check(source.count(anchor) == 1, "Controlled fragment shadow input has one production anchor")
	return source.replace(anchor, "float shadow_factor = test_shadow_factor;")


func _add_shader(name: String, source: String) -> void:
	var shader := Shader.new()
	shader.code = source
	_variants[name].append(shader)


func _set_variant(name: String) -> void:
	for index in range(_hair.size()):
		_hair[index].shader = _variants[name][index]


func _set_parameter(name: String, value: Variant) -> void:
	for material in _hair:
		material.set_shader_parameter(name, value)


func _set_effect(effect: String) -> void:
	# This legacy-atlas oracle injects its own fragment shadow factor. Native-key
	# contrast has a separate real-light gate, not this independent test input.
	_set_parameter("u_npr_native_shadow_contrast", false)
	_set_parameter("u_npr_hair_silhouette_strength", 0.22)
	_set_parameter("u_npr_fill_strength", 1.0)
	_set_parameter("test_shadow_factor", 0.0 if effect == "zero_gain" else 0.04)
	_set_parameter("g_u_level_adjust_on", false)
	_set_parameter("u_dither_mask", 0)
	_set_parameter("u_contrast_adjust_on", effect in ["contrast", "combined", "zero_gain"])
	_set_parameter("u_contrast_strength", -1.0 if effect == "zero_gain" else 1.6)
	_set_parameter("u_accent_split_tone_strength", 0.0)
	_set_parameter(
		"u_accent_additive_highlight_strength",
		0.7 if effect in ["accent", "combined", "zero_gain"] else 0.0
	)
	_set_parameter("u_accent_additive_highlight_color", Vector3(0.08, 0.17, 0.31))
	_set_parameter("u_rim_shadow_width", 1.0 if effect in ["rim", "combined", "zero_gain"] else 0.0)
	_set_parameter("u_rim_shadow_feather", 0.04)
	_set_parameter("u_rim_shadow_ct", 1.0)
	_set_parameter("u_rim_shadow_intensity", 3.0)
	_set_parameter("u_rim_shadow_color", Color(0.35, 0.55, 0.8))


func _oracle(effect: String, attenuation: float, fill: float) -> void:
	var label := "%s_%.2f_%.2f" % [effect, attenuation, fill]
	for variant in ["transport", "reference"]:
		_set_variant(variant)
		_set_parameter("test_attenuation", attenuation)
		_set_parameter("test_fill", fill)
		await _capture(label + "_" + variant)
	_oracle_pairs.append({"first": label + "_transport", "second": label + "_reference"})


func _broken_gain(effect: String) -> void:
	_set_variant("broken_gain")
	_set_parameter("test_attenuation", 0.25)
	_set_parameter("test_fill", 0.7)
	await _capture(effect + "_broken_gain")
	_response_pairs.append(
		{
			"first": effect + "_0.25_0.70_reference",
			"second": effect + "_broken_gain",
			"minimum": 100
		}
	)


func _clamp_check() -> void:
	_set_effect("combined")
	_set_parameter("test_attenuation", 0.0)
	_set_parameter("test_fill", 0.0)
	for variant in ["clamp", "clamp_reference", "wrong_clamp"]:
		_set_variant(variant)
		await _capture(variant)
	_oracle_pairs.append({"first": "clamp", "second": "clamp_reference"})
	_response_pairs.append({"first": "clamp_reference", "second": "wrong_clamp", "minimum": 100})


func _real_light_checks() -> void:
	_set_variant("original")
	# The front-facing hair is not reliably self-occluded. A shadows-only fixture
	# supplies real atlas attenuation without painting over the tested pixels.
	var caster := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 0.15, 1.5)
	caster.mesh = box
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_lab.turntable.get_parent().add_child(caster)
	var mesh: MeshInstance3D = _lab.preview.meshes[2]
	caster.global_position = (
		mesh.global_transform * mesh.get_aabb().get_center()
		+ _lab.preview.character.shadow_light.global_basis.z * 1.0
	)
	for effect in ["none", "accent", "rim", "combined"]:
		_set_effect(effect)
		_lab.preview.set_shadow_strength(0.65)
		_set_parameter("u_npr_fill_strength", 0.0)
		await _capture(effect + "_csm")
		_lab.preview.set_shadow_strength(0.0)
		await _capture(effect + "_no_csm")
		_response_pairs.append(
			{"first": effect + "_csm", "second": effect + "_no_csm", "minimum": 30}
		)
		_lab.preview.fill_light.show()
		_set_parameter("u_npr_fill_strength", 0.8)
		await _capture(effect + "_fill")
		_response_pairs.append(
			{"first": effect + "_no_csm", "second": effect + "_fill", "minimum": 100}
		)
		_lab.preview.fill_light.hide()
	caster.queue_free()
	await process_frame


func _entry_visibility_checks() -> void:
	var pose: Transform3D = _lab.camera.global_transform
	var mesh: MeshInstance3D = _lab.preview.meshes[2]
	var focus: Vector3 = mesh.global_transform * mesh.get_aabb().get_center() + Vector3.UP * 0.2
	_lab.camera.global_position = focus + _lab.camera.global_basis.z * 1.1
	_lab.camera.look_at(focus)
	_set_effect("combined")
	_set_parameter("test_attenuation", 0.25)
	_set_parameter("test_fill", 0.7)
	_set_variant("reference")
	await _capture("both_entries")
	for index in range(_hair.size()):
		_set_variant("reference")
		var black := Shader.new()
		black.code = _hair[index].shader.code.replace(
			"EMISSION = npr_final_color;", "EMISSION = vec3(0.0);"
		)
		_hair[index].shader = black
		await _capture("entry_%d_black" % index)
		_response_pairs.append(
			{"first": "both_entries", "second": "entry_%d_black" % index, "minimum": 30}
		)
	_lab.camera.global_transform = pose


func _guard_checks() -> void:
	for guard in ["level", "split", "dither1", "dither2", "dither3", "identity4", "negative_rim"]:
		_set_effect("combined")
		if guard == "level":
			_set_parameter("g_u_level_adjust_on", true)
		elif guard == "split":
			_set_parameter("u_accent_split_tone_strength", 0.5)
		elif guard == "negative_rim":
			# pow(base, 0) is one even on directly facing fragments.
			_set_parameter("u_rim_shadow_ct", 0.0)
			_set_parameter("u_rim_shadow_width", 1.0)
			_set_parameter("u_rim_shadow_intensity", 16.0)
			# Mixed signs keep a visible response; an all-negative result could
			# clamp to black in both images without proving correct lighting.
			_set_parameter("u_rim_shadow_color", Color(0.2, 1.0, 1.0))
		else:
			_set_parameter("u_dither_mask", int(guard.right(1)))
		_lab.preview.set_shadow_strength(0.0)
		_set_parameter("u_npr_fill_strength", 0.0)
		await _capture(guard + "_off")
		_lab.preview.set_shadow_strength(0.65)
		_lab.preview.fill_light.show()
		_set_parameter("u_npr_fill_strength", 0.8)
		await _capture(guard + "_on")
		var pair := {"first": guard + "_off", "second": guard + "_on"}
		if _native_post_light or guard == "identity4":
			pair.minimum = 100
			_response_pairs.append(pair)
		else:
			_oracle_pairs.append(pair)
		_lab.preview.fill_light.hide()
