class_name NPRSymbolSurfaceProfile
extends Resource
## Shared actor-space calibration for replacement geometry, ink and outline masking.

@export var eye_centers := PackedVector2Array()
@export var eye_radius := Vector2.ZERO
@export var eye_ink_scale := Vector2.ZERO
@export var mouth_center := Vector2.ZERO
@export var mouth_radius := Vector2.ZERO
@export var mouth_ink_scale := Vector2.ZERO
@export var outline_eye_centers := PackedVector2Array()
@export var outline_eye_radius := Vector2.ZERO
@export var skin_front_min := 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in ["eye_centers", "outline_eye_centers"]:
		var centers: PackedVector2Array = get(field)
		if centers.size() != 2:
			errors.append(field + " requires negative-X and positive-X eye centers")
		for center in centers:
			if not center.is_finite():
				errors.append(field + " must be finite")
	for field in [
		"eye_radius", "eye_ink_scale", "mouth_radius", "mouth_ink_scale", "outline_eye_radius"
	]:
		var value: Vector2 = get(field)
		if not value.is_finite() or value.x <= 0 or value.y <= 0:
			errors.append(field + " requires finite positive components")
	if not mouth_center.is_finite() or not is_finite(skin_front_min):
		errors.append("Mouth center and front threshold must be finite")
	return errors


func apply_material(material: ShaderMaterial) -> void:
	var values := {
		"eye_left": eye_centers[0],
		"eye_right": eye_centers[1],
		"eye_radius": eye_radius,
		"eye_ink_scale": eye_ink_scale,
		"mouth_center": mouth_center,
		"mouth_radius": mouth_radius,
		"mouth_ink_scale": mouth_ink_scale,
		"outline_eye_left": outline_eye_centers[0],
		"outline_eye_right": outline_eye_centers[1],
		"outline_eye_radius": outline_eye_radius,
		"skin_front_min": skin_front_min,
	}
	for key: String in values:
		material.set_shader_parameter("u_npr_symbol_" + key, values[key])
