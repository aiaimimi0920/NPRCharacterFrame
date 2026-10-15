extends "res://addons/npr_character_frame/npr_character_materials.gd"
## Optional directional SDF material for the fixed plugin installation.
@export var face_sdf360: Texture2D


func validate_optional() -> PackedStringArray:
	var errors := super.validate_optional()
	if face_sdf360 == null:
		return errors
	if not sdf_on_uv2:
		errors.append("Directional SDF requires sdf_on_uv2=true and authored face UV2")
	var width := face_sdf360.get_width()
	var height := face_sdf360.get_height()
	if width <= 0 or height <= 0 or width % 24 != 0 or height % 7 != 0:
		errors.append("Directional SDF atlas requires 24 columns and 7 rows of equal-sized tiles")
	elif width / 24 <= 4 or height / 7 <= 4:
		errors.append("Directional SDF tiles require an interior plus 2px padding on each side")
	return errors


func validate_source_materials() -> PackedStringArray:
	var errors := validate_optional()
	if face_sdf360 != null:
		errors.append("Directional SDF requires use_source_materials=false")
	return errors


func build() -> Array[ShaderMaterial]:
	var built := super.build()
	if built.size() < 2 or face_sdf360 == null:
		return built
	var face := built[1]
	var params := {}
	for entry in face.shader.get_shader_uniform_list():
		var value = face.get_shader_parameter(entry.name)
		if value != null:
			params[entry.name] = value
	face.shader = preload("res://addons/npr_character_frame/shaders/face/sdf360/face_base.gdshader")
	for name in params:
		face.set_shader_parameter(name, params[name])
	face.set_shader_parameter("u_npr_sdf360_enabled", true)
	face.set_shader_parameter("u_npr_sdf360_atlas", face_sdf360)
	return built
