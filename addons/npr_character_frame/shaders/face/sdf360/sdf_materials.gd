extends "res://addons/npr_character_frame/npr_character_materials.gd"
## Optional project-level SDF extension. Pinned framework remains unchanged.
@export var face_sdf360: Texture2D


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
