extends RefCounted
const LIT = preload("res://addons/npr_character_frame/shaders/face/posterior_lit.gdshader")
const OUTLINE = preload(
	"res://addons/npr_character_frame/shaders/face/face_outline_pixels.gdshader"
)


static func validate(mesh: ArrayMesh, material: ShaderMaterial) -> PackedStringArray:
	var errors = PackedStringArray()
	if mesh == null or mesh.get_surface_count() != 1 or material == null:
		errors.append("posterior: exactly one surface and material required")
		return errors
	var enabled = material.get_shader_parameter("u_npr_posterior_enabled") == true
	var tail = material.next_pass.next_pass if material.next_pass != null else null
	if tail is ShaderMaterial and tail.shader == OUTLINE:
		tail = tail.next_pass
	if not enabled:
		if tail != null:
			errors.append("posterior: disabled feature rejects extra pass")
		if mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM3] != null:
			errors.append("posterior: domain channel requires explicit opt-in")
		return errors
	if not tail is ShaderMaterial or tail.shader != LIT or tail.next_pass != null:
		errors.append("posterior: requires exactly one supported lit tail pass")
		return errors
	if tail.get_shader_parameter("u_npr_posterior_enabled") != true:
		errors.append("posterior: lit pass must explicitly opt in")
	if tail.render_priority != 0:
		errors.append("posterior: lit render priority must be zero")
	var alpha = _parameter(material, "u_npr_visibility_alpha")
	if not is_finite(alpha) or alpha < 0.0 or alpha > 1.0:
		errors.append("posterior: finite visibility alpha in [0,1] required")
	elif (
		alpha > 0.0
		and alpha < 1.0
		and material.get_shader_parameter("u_npr_visibility_dither_enabled") != true
	):
		errors.append("posterior: fractional visibility requires coverage dither")
	for info in RenderingServer.get_shader_parameter_list(LIT.get_rid()):
		if info.name == "u_npr_posterior_enabled":
			continue
		if _parameter(tail, info.name) != _parameter(material, info.name):
			errors.append("posterior: lit shared parameter must match Face: " + str(info.name))
	var a = mesh.surface_get_arrays(0)
	var n = a[0].size()
	var fmt = mesh.surface_get_format(0)
	for channel in [Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		var shift = (
			Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT
			if channel == Mesh.ARRAY_CUSTOM2
			else Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT
		)
		if (
			((fmt >> shift) & 7) != Mesh.ARRAY_CUSTOM_RGBA_FLOAT
			or a[channel] == null
			or a[channel].size() != n * 4
		):
			errors.append("posterior: RGBA_FLOAT domain/color arrays required")
			return errors
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
		if a[channel] == null or a[channel].size() != n:
			errors.append("posterior: required vertex attribute size mismatch")
			return errors
	for v in a[Mesh.ARRAY_VERTEX]:
		if not v.is_finite():
			errors.append("posterior: nonfinite base position")
			return errors
	for v in a[Mesh.ARRAY_NORMAL]:
		if not v.is_finite() or v.length_squared() < 0.000001:
			errors.append("posterior: invalid normal")
			return errors
	for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if a[channel] != null:
			if a[channel].size() != n:
				errors.append("posterior: UV size mismatch")
				return errors
			for v in a[channel]:
				if not v.is_finite():
					errors.append("posterior: nonfinite UV")
					return errors
	for c in a[Mesh.ARRAY_COLOR]:
		if not is_finite(c.r) or not is_finite(c.g) or not is_finite(c.b) or not is_finite(c.a):
			errors.append("posterior: nonfinite visibility color")
			return errors
	if a[Mesh.ARRAY_TANGENT] != null:
		if a[Mesh.ARRAY_TANGENT].size() != n * 4:
			errors.append("posterior: tangent size mismatch")
			return errors
		for v in a[Mesh.ARRAY_TANGENT]:
			if not is_finite(v):
				errors.append("posterior: nonfinite tangent")
				return errors
	if material.get_shader_parameter("u_npr_surface_effects_enabled") == true:
		errors.append("posterior: textured surface profiles need explicit patch UV support")
		return errors
	var tags = a[Mesh.ARRAY_CUSTOM3]
	var colors = a[Mesh.ARRAY_CUSTOM2]
	var count = 0
	for i in range(n):
		var tag = tags[i * 4]
		if tag != 0.0 and tag != 1.0:
			errors.append("posterior: binary finite domain required")
			return errors
		for c in range(1, 4):
			if tags[i * 4 + c] != 0.0:
				errors.append("posterior: reserved domain components must be zero")
				return errors
		if tag == 1.0:
			count += 1
			if colors[i * 4 + 3] != 1.0:
				errors.append("posterior: opaque patch alpha required")
				return errors
			for c in range(4):
				if (
					not is_finite(colors[i * 4 + c])
					or colors[i * 4 + c] < 0
					or colors[i * 4 + c] > 1
				):
					errors.append("posterior: invalid patch color")
					return errors
	if count == 0 or count == n:
		errors.append("posterior: both Face and Patch domains required")
	var ix = a[Mesh.ARRAY_INDEX]
	if (
		mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES
		or not ix is PackedInt32Array
		or ix.size() < 3
		or ix.size() % 3 != 0
	):
		errors.append("posterior: complete indexed triangles required")
		return errors
	for i in range(0, ix.size(), 3):
		if (
			ix[i] < 0
			or ix[i + 1] < 0
			or ix[i + 2] < 0
			or ix[i] >= n
			or ix[i + 1] >= n
			or ix[i + 2] >= n
		):
			errors.append("posterior: index out of bounds")
			return errors
		if tags[ix[i] * 4] != tags[ix[i + 1] * 4] or tags[ix[i] * 4] != tags[ix[i + 2] * 4]:
			errors.append("posterior: triangles may not cross domains")
			return errors
	var names = {}
	var shapes = mesh.surface_get_blend_shape_arrays(0)
	for k in range(mesh.get_blend_shape_count()):
		for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]:
			if shapes[k][channel] != null:
				var expected = n * 4 if channel == Mesh.ARRAY_TANGENT else n
				if shapes[k][channel].size() != expected:
					errors.append("posterior: morph attribute size mismatch")
					return errors
				for v in shapes[k][channel]:
					if (not v.is_finite()) if typeof(v) == TYPE_VECTOR3 else (not is_finite(v)):
						errors.append("posterior: nonfinite morph attribute")
						return errors
		var name = mesh.get_blend_shape_name(k)
		if str(name).is_empty() or names.has(name):
			errors.append("posterior: unique morph names required")
		names[name] = true
		if shapes[k][0] == null or shapes[k][0].size() != n:
			errors.append("posterior: morph vertex count mismatch")
			return errors
		for v in shapes[k][0]:
			if not v.is_finite():
				errors.append("posterior: nonfinite morph position")
				return errors
	return errors


static func configure(
	face: ShaderMaterial, outline: ShaderMaterial, authored_lit: ShaderMaterial = null
) -> void:
	var enabled = face.get_shader_parameter("u_npr_posterior_enabled") == true
	face.next_pass.set_shader_parameter("u_npr_posterior_enabled", enabled)
	outline.set_shader_parameter("u_npr_posterior_enabled", enabled)
	if enabled:
		var lit = authored_lit
		assert(lit != null and lit.shader == LIT, "Validated authored lit pass required")
		lit.set_shader_parameter("u_npr_posterior_enabled", true)
		outline.next_pass = lit
		# Profiles may reset dither; retain the authored supported coverage mode.
		var alpha = _parameter(face, "u_npr_visibility_alpha")
		if alpha > 0.0 and alpha < 1.0:
			for pass_material in [face, face.next_pass, outline]:
				pass_material.set_shader_parameter("u_npr_visibility_dither_enabled", true)
		for info in RenderingServer.get_shader_parameter_list(lit.shader.get_rid()):
			if info.name == "u_npr_posterior_enabled":
				continue
			var value = face.get_shader_parameter(info.name)
			if value != null:
				lit.set_shader_parameter(info.name, value)


static func _parameter(material: ShaderMaterial, key: StringName) -> Variant:
	var value = material.get_shader_parameter(key)
	if value == null:
		return RenderingServer.shader_get_parameter_default(material.shader.get_rid(), key)
	return value
