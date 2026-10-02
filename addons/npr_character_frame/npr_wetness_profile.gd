class_name NPRWetnessProfile
extends Resource
## Authored wetness masks; simulation and wetness amounts belong to the caller.

@export var body_mask: Texture2D
@export var material_regions: Texture2D
@export var eye_tear_mask: Texture2D
@export var hair_mask: Texture2D
@export var eye_tear_uv_limit := Vector2.ONE


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in ["body_mask", "material_regions", "eye_tear_mask", "hair_mask"]:
		var texture := get(field) as Texture2D
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			errors.append(field + " requires a nonempty Texture2D")
	if (
		not eye_tear_uv_limit.is_finite()
		or eye_tear_uv_limit.x < 0
		or eye_tear_uv_limit.y < 0
		or eye_tear_uv_limit.x > 1
		or eye_tear_uv_limit.y > 1
	):
		errors.append("eye_tear_uv_limit requires finite components within [0, 1]")
	return errors


func apply_materials(
	body: ShaderMaterial, face: ShaderMaterial, hair_passes: Array[ShaderMaterial]
) -> void:
	body.set_shader_parameter("u_npr_wetness_map", body_mask)
	body.set_shader_parameter("u_npr_material_wetness_map", material_regions)
	face.set_shader_parameter("u_npr_eye_tear_mask", eye_tear_mask)
	face.set_shader_parameter("u_npr_eye_tear_uv_limit", eye_tear_uv_limit)
	for material in hair_passes:
		material.set_shader_parameter("u_npr_hair_wetness_map", hair_mask)
