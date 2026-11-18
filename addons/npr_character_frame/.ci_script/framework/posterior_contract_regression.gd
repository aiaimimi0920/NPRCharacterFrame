extends SceneTree

const CONTRACT = preload("res://addons/npr_character_frame/runtime/npr_posterior_contract.gd")
const BASE = preload("res://addons/npr_character_frame/shaders/face/face_base.gdshader")
const EYE = preload("res://addons/npr_character_frame/shaders/face/face_eye_stencil.gdshader")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _material() -> ShaderMaterial:
	var base := ShaderMaterial.new()
	base.shader = BASE
	base.set_shader_parameter("u_npr_posterior_enabled", true)
	var eye := ShaderMaterial.new()
	eye.shader = EYE
	var lit := ShaderMaterial.new()
	lit.shader = CONTRACT.LIT
	lit.set_shader_parameter("u_npr_posterior_enabled", true)
	base.next_pass = eye
	eye.next_pass = lit
	return base


func _mesh(
	tag: float = 1.0, primitive: int = Mesh.PRIMITIVE_TRIANGLES, indexed: bool = true
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[
			Vector3.ZERO,
			Vector3.RIGHT,
			Vector3.UP,
			Vector3(0, 0, 1),
			Vector3(1, 0, 1),
			Vector3(0, 1, 1)
		]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
		[
			Vector3.FORWARD,
			Vector3.FORWARD,
			Vector3.FORWARD,
			Vector3.FORWARD,
			Vector3.FORWARD,
			Vector3.FORWARD
		]
	)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
		[Vector2.ZERO, Vector2.RIGHT, Vector2.UP, Vector2.ZERO, Vector2.RIGHT, Vector2.UP]
	)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(
		[Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
	)
	var colors := PackedFloat32Array()
	var tags := PackedFloat32Array()
	for i in range(6):
		colors.append_array(PackedFloat32Array([0.5, 0.5, 0.5, 1.0]))
		tags.append_array(PackedFloat32Array([0.0 if i < 3 else tag, 0.0, 0.0, 0.0]))
	arrays[Mesh.ARRAY_CUSTOM2] = colors
	arrays[Mesh.ARRAY_CUSTOM3] = tags
	if indexed:
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var mesh := ArrayMesh.new()
	var flags := (
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	)
	mesh.add_surface_from_arrays(primitive, arrays, [], {}, flags)
	return mesh


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _run() -> void:
	_check(not CONTRACT.validate(null, _material()).is_empty(), "null mesh rejected")
	_check(not CONTRACT.validate(ArrayMesh.new(), _material()).is_empty(), "empty mesh rejected")
	_check(not CONTRACT.validate(_mesh(), null).is_empty(), "null material rejected")
	var original_arrays = _mesh().surface_get_arrays(0)
	original_arrays[Mesh.ARRAY_CUSTOM2] = null
	original_arrays[Mesh.ARRAY_CUSTOM3] = null
	var untagged := ArrayMesh.new()
	untagged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original_arrays)
	var disabled := _material()
	disabled.set_shader_parameter("u_npr_posterior_enabled", false)
	disabled.next_pass.next_pass = null
	_check(CONTRACT.validate(untagged, disabled).is_empty(), "untagged default off allowed")
	var mesh := _mesh()
	var material := _material()
	_check(CONTRACT.validate(mesh, material).is_empty(), "valid synthetic domains")
	_check(not CONTRACT.validate(_mesh(0.5), material).is_empty(), "fractional domain rejected")
	_check(not CONTRACT.validate(_mesh(0.0), material).is_empty(), "missing patch rejected")
	_check(
		not CONTRACT.validate(_mesh(1.0, Mesh.PRIMITIVE_TRIANGLE_STRIP), material).is_empty(),
		"non triangle primitive rejected"
	)
	_check(
		not CONTRACT.validate(_mesh(1.0, Mesh.PRIMITIVE_TRIANGLES, false), material).is_empty(),
		"nonindexed rejected without script error"
	)
	var tail := material.next_pass.next_pass
	material.next_pass.next_pass = null
	_check(not CONTRACT.validate(mesh, material).is_empty(), "missing pass rejected")
	material.next_pass.next_pass = tail
	material.set_shader_parameter("u_npr_surface_effects_enabled", true)
	_check(not CONTRACT.validate(mesh, material).is_empty(), "unsupported profile rejected")
	material.set_shader_parameter("u_npr_surface_effects_enabled", false)
	material.set_shader_parameter("u_npr_posterior_enabled", false)
	_check(not CONTRACT.validate(mesh, material).is_empty(), "disabled tagged rejected")
	material = _material()
	var lit := material.next_pass.next_pass as ShaderMaterial
	lit.render_priority = 1
	_check(not CONTRACT.validate(mesh, material).is_empty(), "custom priority rejected")
	lit.render_priority = 0
	lit.set_shader_parameter("u_npr_dissolve_amount", 0.3)
	_check(not CONTRACT.validate(mesh, material).is_empty(), "divergent lit parameter rejected")
	lit.set_shader_parameter("u_npr_dissolve_amount", 0.0)
	for part in [material, lit]:
		part.set_shader_parameter("u_npr_visibility_alpha", 0.5)
	_check(not CONTRACT.validate(mesh, material).is_empty(), "continuous alpha rejected")
	for part in [material, lit]:
		part.set_shader_parameter("u_npr_visibility_dither_enabled", true)
	_check(CONTRACT.validate(mesh, material).is_empty(), "coverage alpha accepted")
	var outline := ShaderMaterial.new()
	outline.shader = CONTRACT.OUTLINE
	material.next_pass.next_pass = outline
	material.set_shader_parameter("u_npr_visibility_dither_enabled", false)
	CONTRACT.configure(material, outline, lit)
	_check(outline.next_pass == lit, "authored lit identity retained")
	_check(lit.get_shader_parameter("u_npr_visibility_alpha") == 0.5, "alpha preserved")
	_check(
		lit.get_shader_parameter("u_npr_visibility_dither_enabled") == true,
		"profile cannot disable required coverage"
	)
	print(JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("REGRESSION_OK")
	quit(0 if failures.is_empty() else 1)
