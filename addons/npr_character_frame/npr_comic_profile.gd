class_name NPRComicProfile
extends Resource
## Authored actor-rest calibration; runtime animation and effect state stay separate.

const PERFORMANCE_DATA = preload("res://addons/npr_character_frame/runtime/npr_performance_data.gd")
const CARDS := ["sweat", "anger", "emphasis"]

@export var anchor_bone := ""
@export var anchor_origin := Vector3.ZERO
@export var card_offsets := PackedVector3Array()
@export var card_sizes := PackedVector2Array()
@export var tear_left := Vector4.ZERO
@export var tear_right := Vector4.ZERO
@export var hatching_left := Vector4.ZERO
@export var hatching_right := Vector4.ZERO


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if anchor_bone not in PERFORMANCE_DATA.BONES:
		errors.append("anchor_bone must name a canonical performance bone")
	if not anchor_origin.is_finite():
		errors.append("anchor_origin must be finite")
	if card_offsets.size() != CARDS.size() or card_sizes.size() != CARDS.size():
		errors.append("card_offsets and card_sizes require sweat, anger and emphasis in order")
	for offset in card_offsets:
		if not offset.is_finite():
			errors.append("card_offsets must be finite")
	for size in card_sizes:
		if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0:
			errors.append("card_sizes require finite positive components")
	for field in ["tear_left", "tear_right", "hatching_left", "hatching_right"]:
		var region: Vector4 = get(field)
		if not region.is_finite() or region.z <= 0.0 or region.w <= 0.0:
			errors.append(field + " requires finite XY center and positive ZW size")
	return errors


func apply_material(material: ShaderMaterial) -> void:
	for field in ["anchor_origin", "tear_left", "tear_right", "hatching_left", "hatching_right"]:
		material.set_shader_parameter("u_npr_comic_" + field, get(field))
