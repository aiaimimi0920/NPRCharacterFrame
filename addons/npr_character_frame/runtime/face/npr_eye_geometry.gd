extends RefCounted
## Assemble validated diagnostic ocular assets without showcase or animation state.

const TEAR_SHADER := preload("res://addons/npr_character_frame/shaders/eye/eye_tear_film.gdshader")
const SURFACE_SHADER := preload("res://addons/npr_character_frame/shaders/eye/eye_surface.gdshader")


## The caller owns target and returned optional lid meshes. Inputs must be validated.
static func assemble(
	target: Node3D,
	profile: NPREyeGeometryProfile,
	face_motion: NPRFaceMotionProfile,
	face_material: ShaderMaterial,
	render_layers: int,
	wetness: float
) -> Array[MeshInstance3D]:
	var skin: Array[MeshInstance3D] = []
	assert(profile != null, "Diagnostic eye geometry requires an authored profile")
	if profile.model_scene == null:
		push_error("Required authored eye asset is unavailable")
		return skin
	var instance := profile.model_scene.instantiate()
	var left := Node3D.new()
	left.name = "EyeL"
	var right := Node3D.new()
	right.name = "EyeR"
	target.add_child(left)
	target.add_child(right)
	for child: Node in instance.get_children():
		instance.remove_child(child)
		child.owner = null
		(left if child.name.begins_with("EyeL_") else right).add_child(child)
		var mesh := child as MeshInstance3D
		mesh.layers = render_layers
		if child.name.ends_with("TearFilm"):
			var material := ShaderMaterial.new()
			material.shader = TEAR_SHADER
			profile.apply_tear(material)
			material.set_shader_parameter("wetness", wetness)
			mesh.material_override = material
		elif (
			child.name.ends_with("Iris")
			or child.name.ends_with("Pupil")
			or child.name.ends_with("Sclera")
		):
			var original := mesh.get_active_material(0) as StandardMaterial3D
			var material := ShaderMaterial.new()
			material.shader = SURFACE_SHADER
			material.set_shader_parameter("eye_color", original.albedo_color)
			material.set_shader_parameter("textured", original.albedo_texture != null)
			material.set_shader_parameter("iris_texture", original.albedo_texture)
			mesh.material_override = material
		else:
			mesh.material_override = face_material
			skin.append(mesh)
	bind_profiles(target, profile, face_motion.load_lid_data())
	instance.queue_free()
	return skin


static func bind_profiles(
	target: Node3D, profile: NPREyeGeometryProfile, lid_data: Dictionary
) -> void:
	var eye_data := profile.load_landmarks()
	for node: Node in target.find_children("*", "MeshInstance3D", true, false):
		var surface := node as MeshInstance3D
		var side := "L" if str(surface.name).begins_with("EyeL") else "R"
		var center: Array = eye_data.landmarks["Eye" + side].center
		var rows: Array = lid_data.profiles[side]
		var curve := PackedVector4Array()
		for row: Dictionary in rows:
			curve.append(
				Vector4(
					row.upper[1] - center[1],
					row.lower[1] - center[1],
					row.upper[2] - center[2],
					row.lower[2] - center[2]
				)
			)
		var material := surface.material_override as ShaderMaterial
		material.set_shader_parameter("eye_profile", curve)
		material.set_shader_parameter(
			"eye_bounds", Vector2(rows[0].upper[0] - center[0], rows[-1].upper[0] - center[0])
		)
		profile.apply_surface(material, str(surface.name))
