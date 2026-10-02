extends RefCounted
## GPU probes read production declarations/functions, not independent copies of the math.

const BODY := "res://addons/npr_character_frame/shaders/body/body_npr.gdshader"
const FACE := "res://addons/npr_character_frame/shaders/face/face_base.gdshader"
const HAIR := "res://addons/npr_character_frame/shaders/hair/hair_base_common.gdshaderinc"
const EYE := "res://addons/npr_character_frame/shaders/face/face_eye_stencil.gdshader"
const MATH := '#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"\n'
const SURFACE := (
	'#include "res://addons/npr_character_frame/shaders/common/'
	+ 'npr_surface_features.gdshaderinc"\n'
)

var _tree: SceneTree
var _viewport: SubViewport
var _quad: MeshInstance3D
var _failures := 0
var _results: Array[Dictionary] = []


func run(tree: SceneTree, output: String) -> int:
	_tree = tree
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(32, 32)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(_viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 3.0
	_viewport.add_child(camera)
	_quad = MeshInstance3D.new()
	_quad.mesh = QuadMesh.new()
	_quad.mesh.size = Vector2(2, 2)
	_viewport.add_child(_quad)
	await _check_samplers()
	await _check_sdf()
	await _check_dither()
	await _check_eye_effect()
	await _check_eye_vfx()
	await _check_surface_features()
	var file := FileAccess.open(output.path_join("shader_contracts.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_results, "  "))
	_viewport.queue_free()
	await tree.process_frame
	print("SHADER_CONTRACTS failures=", _failures, " checks=", _results.size())
	return _failures


func _check_samplers() -> void:
	var gray := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	gray.fill(Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1))
	var texture := ImageTexture.create_from_image(gray)
	var expected := await _probe("", "vec3(128.0 / 255.0)")
	for entry in [
		[BODY, "u_texture_light_map"],
		[BODY, "u_material_values_pack_lut"],
		[FACE, "u_texture_ilm_map"],
		[FACE, "u_texture_face"],
		[HAIR, "u_texture_ilm_map"],
		[EYE, "u_texture_ilm"],
	]:
		var name: String = entry[1]
		var actual := await _probe(
			_declaration(entry[0], name), "texture(%s, vec2(0.5)).rgb" % name, {name: texture}
		)
		_record("linear_data:" + name + ":" + entry[0], actual, expected)
	var converted := await _probe(MATH, "npr_srgb_to_linear(vec3(128.0 / 255.0))")
	var color_value := await _probe(
		_declaration(BODY, "u_texture_base_map"),
		"texture(u_texture_base_map, vec2(0.5)).rgb",
		{"u_texture_base_map": texture}
	)
	_record("packed_color_rows_preserve_srgb", converted, color_value)
	var ramp := Image.create(8, 2, false, Image.FORMAT_RGBA8)
	ramp.fill(Color.BLACK)
	ramp.set_pixel(7, 0, Color.WHITE)
	ramp.set_pixel(7, 1, Color.WHITE)
	var ramp_texture := ImageTexture.create_from_image(ramp)
	for path in [BODY, HAIR]:
		var actual := await _probe(
			_declaration(path, "u_texture_diffuse_ramp"),
			"textureLod(u_texture_diffuse_ramp, vec2(1.0, 0.5), 0.0).rgb",
			{"u_texture_diffuse_ramp": ramp_texture}
		)
		_record("ramp_endpoint_clamps:" + path, actual, Color.WHITE)


func _check_sdf() -> void:
	var factor := MATH + "uniform float u_sdf_feather_radius = 0.0;\n"
	factor += _function_source(FACE, "calculate_sdf_factor")
	for center in [0.0, 0.0001, 0.5, 0.9999, 1.0]:
		var expression := "vec3(calculate_sdf_factor(%s, %s))" % [center, center]
		var actual := await _probe(factor, expression)
		_record("zero_feather_hard_step:" + str(center), actual, Color.WHITE)
		for offset in [-0.0002, 0.0002]:
			var side_expression := "vec3(calculate_sdf_factor(%s, %s))" % [center + offset, center]
			var side := await _probe(factor, side_expression)
			_record(
				"hard_step_side:%s:%s" % [center, offset],
				side,
				Color.WHITE if offset > 0 else Color.BLACK
			)
	var direction := _function_source(FACE, "calculate_sdf_uv_and_angle")
	for parameter in ["u_npr_sdf_basis_enabled", "u_npr_face_forward", "u_npr_face_right"]:
		direction = _declaration(FACE, parameter) + "\n" + direction
	var expression := "calculate_sdf_uv_and_angle(%s, mat3(1.0), vec2(0.2, 0.3))"
	var unit := await _probe(direction, expression % "vec3(0.0, 1.0, 0.0)")
	var short_dir := await _probe(direction, expression % "vec3(0.0, 0.1, 0.0)")
	_record("sdf_direction_magnitude_invariant", short_dir, unit)
	var fallback := await _probe("", "vec3(0.2, 0.3, 0.0001)")
	for vector in ["vec3(0.0)", "vec3(1.0, 0.0, 0.0)"]:
		var actual := await _probe(direction, expression % vector)
		_record("sdf_degenerate_preserves_uv:" + vector, actual, fallback)
	var finite := await _probe(MATH, "vec3(float(!isnan(0.0 / npr_nonzero(0.0))))")
	_record("collapsed_range_finite", finite, Color.WHITE)
	for spec in [
		["vec3(0,0,1)", "vec3(0.2,0.3,0.0001)"],
		["vec3(1,0,0)", "vec3(0.2,0.3,0.5)"],
		["vec3(-1,0,0)", "vec3(0.8,0.3,0.5)"],
		["vec3(0,0,-1)", "vec3(0.2,0.3,0.9999)"],
		["vec3(0,1,0)", "vec3(0.2,0.3,0.0001)"]
	]:
		var actual := await _probe(
			direction, expression % spec[0], {"u_npr_sdf_basis_enabled": true}
		)
		var expected := await _probe("", spec[1])
		_record("generic_sdf_axes:" + spec[0], actual, expected)


func _check_dither() -> void:
	var expected := await _probe("", "vec3(0.3, 0.5, 0.7)")
	for mode in [0, 4, 16, 32, 48, 60]:
		var actual := await _probe(
			MATH, "npr_dither_color(vec3(0.3, 0.5, 0.7), %s, FRAGCOORD.xy)" % mode
		)
		_record("attachment_bits_ignored:" + str(mode), actual, expected)
	# CPU oracle retains the original table and indexing, not the new select tree.
	var table := [-3.0 / 256.0, 1.0 / 256.0, 3.0 / 256.0, -1.0 / 256.0]
	var declarations := MATH + "uniform vec2 probe_pixel;\nuniform int probe_mask;\n"
	declarations += "uniform vec3 probe_color;\n"
	for origin: Vector2 in [Vector2.ZERO, Vector2(18, 42), Vector2(4096, 8192)]:
		for x in range(2):
			for y in range(2):
				var pixel := origin + Vector2(x, y) + Vector2(0.5, 0.5)
				var offset: float = table[x * 2 + y]
				var actual := await _probe(
					declarations,
					"vec3(0.5 + 32.0 * npr_dither_value(probe_pixel))",
					{"probe_pixel": pixel}
				)
				var reference := await _probe("", "vec3(%s)" % (0.5 + 32.0 * offset))
				_record("dither_table:%s" % pixel, actual, reference, 0.0)
	for color: Vector3 in [Vector3(0.3, 0.5, 0.7), Vector3(0.019, 0.981, 0.123)]:
		for mask in [0, 1, 2, 3, 13, 18, 63]:
			for index in range(4):
				var pixel := Vector2(index / 2, index % 2) + Vector2(0.5, 0.5)
				var mode: int = mask & 3
				var offset := Vector3.ONE * float(table[index])
				var levels := Vector3.ONE * 31.0
				if mode == 1:
					offset *= 2.0
					levels = Vector3.ONE * 15.0
				elif mode == 3:
					offset.y *= 0.5
					levels.y = 63.0
				var quantized := (
					color if mode == 0 else ((color + offset) * levels).round() / levels
				)
				var reference := await _probe(
					"", "vec3(%s, %s, %s)" % [quantized.x, quantized.y, quantized.z]
				)
				var actual := await _probe(
					declarations,
					"npr_dither_color(probe_color, probe_mask, probe_pixel)",
					{"probe_pixel": pixel, "probe_mask": mask, "probe_color": color}
				)
				_record(
					"dither_quantization:%s:%s:%s" % [color, mask, index], actual, reference, 0.0
				)


func _check_eye_effect() -> void:
	var declarations := "uniform float u_eyeball_effect_intensity;\n"
	declarations += "uniform vec3 u_eyeball_effect_tint;\n"
	declarations += "uniform vec3 probe_color;\nuniform float probe_mask;\n"
	declarations += _function_source(FACE, "apply_eyeball_effect")
	var tint := Vector3(0.2, 0.7, 1.3)
	for color: Vector3 in [Vector3(0.2, 0.6, 0.8), Vector3(-0.2, 0.4, 1.6)]:
		for mask in [0.1, 0.1001, 0.5, 0.7999, 0.8]:
			for intensity in [-1.0, 0.0, 0.6, 2.0]:
				var weight := clampf(intensity, 0.0, 1.0) if mask > 0.1 and mask < 0.8 else 0.0
				var luminance := color.dot(Vector3(0.3, 0.59, 0.11))
				# Algebraic expansion of the two blends; preserves the unconditional final clamp.
				var expected := color * (1.0 - weight)
				expected += (
					weight
					* (1.0 + luminance * 0.5)
					* (color * (1.0 - weight) + tint * luminance * (weight + luminance))
				)
				expected = expected.clamp(Vector3.ZERO, Vector3.ONE)
				var reference := await _probe(
					"", "vec3(%s, %s, %s)" % [expected.x, expected.y, expected.z]
				)
				var actual := await _probe(
					declarations,
					"apply_eyeball_effect(probe_color, probe_mask)",
					{
						"probe_color": color,
						"probe_mask": mask,
						"u_eyeball_effect_intensity": intensity,
						"u_eyeball_effect_tint": tint
					}
				)
				_record("eye_effect:%s:%s:%s" % [color, mask, intensity], actual, reference)


func _check_eye_vfx() -> void:
	var declarations := _declaration(FACE, "u_eyeball_vfx_pattern_texture")
	declarations += "uniform bool u_procedural_fx_enable;\n"
	declarations += "uniform vec4 u_eyeball_vfx_uv_transform;\n"
	declarations += "uniform vec4 u_eyeball_vfx_anim_params;\n"
	declarations += "uniform vec4 u_eyeball_vfx_color_a;\n"
	declarations += "uniform vec4 u_eyeball_vfx_color_b;\n"
	declarations += "uniform float u_eyeball_vfx_intensity;\n"
	declarations += "uniform vec2 probe_uv;\nuniform float probe_time;\n"
	declarations += "uniform float probe_mask;\nuniform vec2 probe_sdf;\n"
	declarations += _function_source(FACE, "apply_eyeball_vfx")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			image.set_pixel(x, y, Color(float(x) / 3.0, float((x + 2 * y) % 4) / 3.0, 0, 1))
	var texture := ImageTexture.create_from_image(image)
	var base := Vector3(0.2, 0.6, 0.8)
	var tint_a := Vector3(1.1, 0.2, 0.3)
	var tint_b := Vector3(0.1, 0.8, 1.2)
	for enabled in [false, true]:
		for mask in [0.1, 0.5, 0.8]:
			for time in [0.0, 0.7]:
				for intensity in [0.0, 1.7]:
					# Non-symmetric coordinates expose swapped center/UV/channel mistakes.
					var uv := Vector2(0.23, 0.81)
					var center_offset := Vector2(uv.y * 0.7 + 0.13 - 0.31, uv.x * 1.3 - 0.2 + 0.17)
					var pattern_a := _eye_pattern_sample(
						image, center_offset.rotated(-time * 0.9) + Vector2(-0.17, 0.31)
					)
					var pattern_b := _eye_pattern_sample(
						image, center_offset.rotated(time * 0.4) + Vector2(-0.17, 0.31)
					)
					var area := 1.0 if mask > 0.1 and mask < 0.8 else 0.0
					var expected := base
					if enabled:
						expected = expected.lerp(tint_b, pattern_b.g * 0.7 * area)
						expected = expected.lerp(tint_a, pattern_a.r * 0.6 * area)
						# Production deliberately extrapolates when sdf.x + area exceeds one.
						expected *= 1.0 + (intensity - 1.0) * (0.6 + area)
					var encoded := Vector3.ONE * 0.25 + expected * 0.0625
					var reference := await _probe(
						"", "vec3(%s, %s, %s)" % [encoded.x, encoded.y, encoded.z]
					)
					var actual := await _probe(
						declarations,
						(
							"vec3(0.25) + 0.0625 * apply_eyeball_vfx(vec3(0.2, 0.6, 0.8), "
							+ "probe_uv, probe_time, probe_mask, probe_sdf)"
						),
						{
							"u_eyeball_vfx_pattern_texture": texture,
							"u_procedural_fx_enable": enabled,
							"u_eyeball_vfx_uv_transform": Vector4(1.3, 0.7, -0.2, 0.13),
							"u_eyeball_vfx_anim_params": Vector4(-0.17, 0.31, 0.9, -0.4),
							"u_eyeball_vfx_color_a": Vector4(1.1, 0.2, 0.3, 0.6),
							"u_eyeball_vfx_color_b": Vector4(0.1, 0.8, 1.2, 0.7),
							"u_eyeball_vfx_intensity": intensity,
							"probe_uv": uv,
							"probe_time": time,
							"probe_mask": mask,
							"probe_sdf": Vector2(0.6, 0.4)
						}
					)
					_record(
						"eye_vfx:%s:%s:%s:%s" % [enabled, mask, time, intensity], actual, reference
					)


func _check_surface_features() -> void:
	var disabled := await _probe(
		SURFACE, "vec3(npr_dissolve_signed_distance(vec2(0.5), vec3(0.0), 0.0))"
	)
	_record("dissolve_disabled_is_noop", disabled, Color.WHITE)
	var zero_amount := await _probe(
		SURFACE,
		"vec3(npr_dissolve_signed_distance(vec2(0.5), vec3(0.0), 0.0))",
		{"u_npr_dissolve_enabled": true, "u_npr_dissolve_amount": 0.0}
	)
	_record("dissolve_zero_amount_is_noop", zero_amount, Color.WHITE)
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.4, 0.4, 1.0))
	var noise := ImageTexture.create_from_image(image)
	var declarations := SURFACE + "uniform float probe_protection;\n"
	var unprotected := await _probe(
		declarations,
		"vec3(0.5 + 0.25 * npr_dissolve_signed_distance(vec2(0.5), vec3(0.0), probe_protection))",
		{
			"u_npr_dissolve_enabled": true,
			"u_npr_dissolve_amount": 0.6,
			"u_npr_dissolve_noise": noise,
			"probe_protection": 0.0
		}
	)
	var protected := await _probe(
		declarations,
		"vec3(0.5 + 0.25 * npr_dissolve_signed_distance(vec2(0.5), vec3(0.0), probe_protection))",
		{
			"u_npr_dissolve_enabled": true,
			"u_npr_dissolve_amount": 0.6,
			"u_npr_dissolve_noise": noise,
			"probe_protection": 0.3
		}
	)
	var protection_works := await _probe(
		"uniform vec3 probe_values;\n",
		"vec3(float(probe_values.y > probe_values.x))",
		{"probe_values": Vector3(unprotected.r, protected.r, 0.0)}
	)
	_record("dissolve_alpha_protection_delays_cutout", protection_works, Color.WHITE)
	var hue_identity := await _probe(MATH, "npr_hue_rotate(vec3(0.2, 0.5, 0.8), 0.0)")
	var hue_reference := await _probe("", "vec3(0.2, 0.5, 0.8)")
	_record("emission_hue_zero_is_identity", hue_identity, hue_reference)
	var slot_wrap := await _probe(MATH, "vec3(npr_material_slot(1.0) / 8.0)")
	_record("material_slot_one_wraps_to_zero", slot_wrap, Color.BLACK)
	var matcap_center := await _probe(MATH, "vec3(npr_matcap_uv(vec3(0.0, 0.0, 1.0)), 0.0)")
	var matcap_reference := await _probe("", "vec3(0.5, 0.5, 0.0)")
	_record("matcap_forward_normal_is_center", matcap_center, matcap_reference)
	var oct_unit := await _probe(MATH, "vec3(length(npr_oct_decode(vec2(0.3, -0.2))))")
	_record("oct_decode_is_unit_length", oct_unit, Color.WHITE)
	var hidden := await _probe(
		SURFACE, "vec3(float(npr_visibility_keep(vec2(0.5))))", {"u_npr_visibility_alpha": 0.0}
	)
	_record("visibility_zero_discards_all_passes", hidden, Color.BLACK)
	var visible := await _probe(
		SURFACE,
		"vec3(float(npr_visibility_keep(vec2(0.5))))",
		{"u_npr_visibility_alpha": 1.0, "u_npr_visibility_dither_enabled": true}
	)
	_record("visibility_one_keeps_all_passes", visible, Color.WHITE)


func _eye_pattern_sample(image: Image, uv: Vector2) -> Color:
	var texel := uv * 4.0 - Vector2.ONE * 0.5
	var origin := Vector2i(floori(texel.x), floori(texel.y))
	var fraction := texel - Vector2(origin)
	var rows: Array[Color] = []
	for y in range(2):
		var left := image.get_pixel(posmod(origin.x, 4), posmod(origin.y + y, 4)).srgb_to_linear()
		var right := (
			image.get_pixel(posmod(origin.x + 1, 4), posmod(origin.y + y, 4)).srgb_to_linear()
		)
		rows.append(left.lerp(right, fraction.x))
	return rows[0].lerp(rows[1], fraction.y)


func _declaration(path: String, uniform_name: String) -> String:
	var declaration := RegEx.new()
	declaration.compile("^\\s*uniform\\s+\\w+\\s+" + uniform_name + "\\s*[:;=]")
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if declaration.search(line) != null:
			return line.strip_edges() + "\n"
	push_error("Missing production uniform: " + uniform_name)
	_failures += 1
	return ""


func _function_source(path: String, name: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	var start := source.find(name + "(")
	start = source.rfind("\n", start) + 1
	var opening := source.find("{", start)
	var depth := 1
	var end := opening + 1
	while depth > 0 and end < source.length():
		if source[end] == "{":
			depth += 1
		elif source[end] == "}":
			depth -= 1
		end += 1
	return source.substr(start, end - start) + "\n"


func _probe(declarations: String, expression: String, params: Dictionary = {}) -> Color:
	var shader := Shader.new()
	shader.code = (
		"shader_type spatial;\nrender_mode unshaded, fog_disabled;\n"
		+ declarations
		+ "void fragment() { ALBEDO = "
		+ expression
		+ "; }\n"
	)
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in params:
		material.set_shader_parameter(key, params[key])
	_quad.material_override = material
	for frame in range(4):
		await _tree.process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image().get_pixel(16, 16)


func _record(label: String, actual: Color, expected: Color, tolerance := 2.0 / 255.0) -> void:
	var delta := maxf(absf(actual.r - expected.r), absf(actual.g - expected.g))
	delta = maxf(delta, absf(actual.b - expected.b))
	var passed := delta <= tolerance
	_results.append(
		{"label": label, "actual": str(actual), "expected": str(expected), "pass": passed}
	)
	if not passed:
		_failures += 1
		push_error("SHADER_CONTRACT_FAILED: %s actual=%s expected=%s" % [label, actual, expected])
