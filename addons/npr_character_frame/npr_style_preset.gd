class_name NPRStylePreset
extends Resource
## Scoped actor-owned lookdev. Host Environment, exposure and external lights are untouched.

enum Scope { ALL, CHARACTER, LIGHTING }

const CHARACTER_RANGES := {
	"ramp_mix": Vector2(0, 1),
	"sdf_feather": Vector2(0, 0.15),
	"outline_width": Vector2(0, 3),
	"hair_highlight": Vector2(0, 1),
	"rim_strength": Vector2(0, 0.5),
	"face_light_weight": Vector2(0, 1)
}
const LIGHT_RANGES := {
	"yaw": Vector2(-180, 180),
	"elevation": Vector2(5, 85),
	"fill_strength": Vector2(0, 1),
	"shadow_strength": Vector2(0, 0.65)
}

@export var display_name := ""
@export var character_values: Dictionary = {}
@export var lighting_values: Dictionary = {}
## World-space art direction, blended only into the face SDF and contact sampling.
@export var face_light_direction := Vector3(0.15, 0.5, 0.85)


func apply(actor: NPRCharacter, scope: Scope = Scope.ALL) -> bool:
	if not is_instance_valid(actor) or not actor.initialized or not is_valid():
		return false
	if scope != Scope.LIGHTING:
		for key in character_values:
			if key == "face_light_weight":
				actor.set_face_light(face_light_direction, character_values[key])
			else:
				actor.call("set_" + key, character_values[key])
	if scope != Scope.CHARACTER:
		for key in lighting_values:
			if key in ["yaw", "elevation"]:
				actor.set("light_" + key, lighting_values[key])
			else:
				actor.call("set_" + key, lighting_values[key])
	actor._apply_light()
	return true


func is_valid() -> bool:
	return (
		_valid_values(character_values, CHARACTER_RANGES)
		and _valid_values(lighting_values, LIGHT_RANGES)
		and face_light_direction.is_finite()
		and face_light_direction.length_squared() > 0.0001
	)


static func capture(actor: NPRCharacter) -> NPRStylePreset:
	var preset := NPRStylePreset.new()
	preset.display_name = "Captured actor look"
	preset.face_light_direction = actor.face_light_direction
	preset.character_values = {
		"ramp_mix": _value(actor.materials[0], "u_npr_ramp_mix", 0.45),
		"sdf_feather": _value(actor.materials[1], "u_sdf_feather_radius", 0.015),
		"outline_width": _value(actor.outlines[0], "outline_width_pixels", 1.0),
		"hair_highlight": _value(actor.materials[2], "u_hair_highlight_strength", 0.0),
		"rim_strength": _value(actor.materials[0], "u_npr_rim_strength", 0.1),
		"face_light_weight": actor.face_light_weight
	}
	preset.lighting_values = {
		"yaw": actor.light_yaw,
		"elevation": actor.light_elevation,
		"fill_strength": _value(actor.materials[0], "u_npr_fill_strength", 0.0),
		"shadow_strength": actor.character.shadow_strength
	}
	return preset


static func _valid_values(values: Dictionary, ranges: Dictionary) -> bool:
	for key in values:
		var value: Variant = values[key]
		if not ranges.has(key) or not (value is float or value is int) or not is_finite(value):
			return false
		if value < ranges[key].x or value > ranges[key].y:
			return false
	return true


static func _value(material: ShaderMaterial, name: String, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(name)
	return float(value) if value != null else fallback
