class_name NPRMaterialProfile
extends Resource
## Eight-region artistic controls. Optional features default to an exact no-op.

@export_multiline var source_note := "Artist-authored; not recovered capture constants."
@export var capture_verified := false

@export_group("Body specular")
@export var specular_exponents := PackedFloat32Array([24, 24, 24, 24, 24, 24, 24, 24])

@export_group("Region outline")
@export var region_outline_enabled := false
@export var outline_colors := PackedColorArray(
	[
		Color(0.22, 0.09, 0.13),
		Color(0.22, 0.09, 0.13),
		Color(0.22, 0.09, 0.13),
		Color(0.22, 0.09, 0.13),
		Color(0.22, 0.09, 0.13),
		Color(0.22, 0.09, 0.13),
		Color(0.22, 0.09, 0.13),
		Color(0.22, 0.09, 0.13)
	]
)
@export var lip_outline_fix_enabled := false
@export_range(0.0, 1.0) var lip_outline_width_scale := 0.35
@export_range(0.0, 4.0, 0.1) var lip_outline_width_pixels := 0.7

@export_group("Stocking and translucent body")
@export var stocking_enabled := false
@export var stocking_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var stocking_color := Color(0.28, 0.32, 0.45)
@export var stocking_shadow_color := Color(0.08, 0.09, 0.15)
@export var stocking_sheen_color := Color(0.55, 0.65, 0.9)
@export_range(0.25, 16.0) var stocking_edge_power := 3.0
@export_range(0.0, 1.0) var stocking_opacity := 1.0
@export_range(0.0, 1.0) var stocking_global_strength := 1.0

@export_group("MatCap")
@export var matcap_enabled := false
@export var matcap_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var matcap_tint := Color.WHITE
@export_range(0.0, 1.0) var matcap_shadow_strength := 0.35
@export_range(0.0, 1.0) var matcap_global_strength := 1.0

@export_group("Layered emission")
@export var emission_hue_enabled := false
@export var emission_hues := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var secondary_emission_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var emission_hue_speed := 0.0

@export_group("Face expression")
@export var expression_shadow_color := Color(0.55, 0.32, 0.42)
@export var expression_highlight_color := Color(1.0, 0.65, 0.72)
@export var expression_blush_color := Color(1.0, 0.32, 0.42)
@export var face_skin_tint := Color.WHITE

@export_group("Face distance LUT")
@export_range(0.0001, 4.0, 0.0001) var face_distance_lut_distance_scale := 0.05

@export_group("Hair anisotropy")
@export var hair_anisotropy_enabled := false
@export var hair_anisotropy_strengths := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var hair_anisotropy_roughness := PackedFloat32Array(
	[0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35, 0.35]
)
@export var hair_anisotropy_shifts := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
@export var hair_anisotropy_color := Color(0.82, 0.9, 1.0)
@export_range(0.0, 1.0) var hair_anisotropy_global_strength := 1.0
@export_range(0.0, 1.0) var hair_side_fade_strength := 0.0
@export var hair_side_fade_range := Vector2(0.45, 0.9)
@export_range(-1, 1, 1) var hair_side_choose := 0
@export_range(0.0, 1.0) var hair_silhouette_strength := 0.0
@export_range(0.25, 8.0) var hair_silhouette_power := 2.0
@export var hair_silhouette_tint := Color(0.72, 0.75, 0.95)

@export_group("Dissolve")
@export_range(0.0, 0.25) var dissolve_edge_width := 0.04
@export var dissolve_edge_color := Color(0.25, 0.75, 1.0)
@export var dissolve_world_space := false
@export var dissolve_world_scale := Vector2.ONE
@export var dissolve_world_offset := Vector2.ZERO
@export_range(0.0, 1.0) var visibility_alpha_cutoff := 0.0
@export var visibility_dither_enabled := false


func is_valid() -> bool:
	return (
		_valid_float_array(specular_exponents, 0.01, 4096.0)
		and _valid_float_array(stocking_strengths, 0.0, 1.0)
		and _valid_float_array(matcap_strengths, 0.0, 8.0)
		and _valid_float_array(emission_hues, -1024.0, 1024.0)
		and _valid_float_array(secondary_emission_strengths, 0.0, 64.0)
		and _valid_float_array(hair_anisotropy_strengths, 0.0, 8.0)
		and _valid_float_array(hair_anisotropy_roughness, 0.0, 1.0)
		and _valid_float_array(hair_anisotropy_shifts, -4.0, 4.0)
		and outline_colors.size() == 8
		and _colors_finite(outline_colors)
		and _color_finite(stocking_color)
		and _color_finite(stocking_shadow_color)
		and _color_finite(stocking_sheen_color)
		and _color_finite(matcap_tint)
		and _color_finite(expression_shadow_color)
		and _color_finite(expression_highlight_color)
		and _color_finite(expression_blush_color)
		and _color_finite(face_skin_tint)
		and is_finite(face_distance_lut_distance_scale)
		and face_distance_lut_distance_scale >= 0.0001
		and face_distance_lut_distance_scale <= 4.0
		and _color_finite(hair_anisotropy_color)
		and _color_finite(hair_silhouette_tint)
		and _color_finite(dissolve_edge_color)
		and is_finite(emission_hue_speed)
		and hair_side_fade_range.is_finite()
		and hair_side_fade_range.x <= hair_side_fade_range.y
		and dissolve_world_scale.is_finite()
		and dissolve_world_offset.is_finite()
	)


## Backward-compatible body-profile entry point.
func apply_to(material: ShaderMaterial) -> bool:
	return apply_body(material)


func apply_body(material: ShaderMaterial) -> bool:
	if not is_valid():
		return false
	_set_dissolve_style(material)
	_bind(
		material,
		{
			"u_npr_specular_exponents": specular_exponents,
			"u_npr_material_profile_enabled": true,
			"u_use_specular_exponent_override": false,
			"u_npr_stocking_enabled": stocking_enabled,
			"u_npr_stocking_strengths": stocking_strengths,
			"u_npr_stocking_color": stocking_color,
			"u_npr_stocking_shadow_color": stocking_shadow_color,
			"u_npr_stocking_sheen_color": stocking_sheen_color,
			"u_npr_stocking_edge_power": stocking_edge_power,
			"u_npr_stocking_opacity": stocking_opacity,
			"u_npr_stocking_global_strength": stocking_global_strength,
			"u_npr_matcap_enabled": matcap_enabled,
			"u_npr_matcap_strengths": matcap_strengths,
			"u_npr_matcap_tint": matcap_tint,
			"u_npr_matcap_shadow_strength": matcap_shadow_strength,
			"u_npr_matcap_global_strength": matcap_global_strength
		}
	)
	_set_emission(material)
	return true


func apply_face(material: ShaderMaterial) -> bool:
	if not is_valid():
		return false
	_set_dissolve_style(material)
	_bind(
		material,
		{
			"u_npr_expression_shadow_color": expression_shadow_color,
			"u_npr_expression_highlight_color": expression_highlight_color,
			"u_npr_expression_blush_color": expression_blush_color,
			"u_npr_face_skin_tint": face_skin_tint,
			"u_distance_lut_distance_scale": face_distance_lut_distance_scale,
			"u_npr_outline_lip_fix_enabled": lip_outline_fix_enabled,
			"u_npr_outline_lip_width_pixels": lip_outline_width_pixels
		}
	)
	return true


func apply_hair(material: ShaderMaterial) -> bool:
	if not is_valid():
		return false
	_set_dissolve_style(material)
	_bind(
		material,
		{
			"u_npr_hair_anisotropy_enabled": hair_anisotropy_enabled,
			"u_npr_hair_anisotropy_strengths": hair_anisotropy_strengths,
			"u_npr_hair_anisotropy_roughness": hair_anisotropy_roughness,
			"u_npr_hair_anisotropy_shifts": hair_anisotropy_shifts,
			"u_npr_hair_anisotropy_color": hair_anisotropy_color,
			"u_npr_hair_anisotropy_global_strength": hair_anisotropy_global_strength,
			"u_npr_hair_side_fade_strength": hair_side_fade_strength,
			"u_npr_hair_side_fade_range": hair_side_fade_range,
			"u_npr_hair_side_choose": hair_side_choose,
			"u_npr_hair_silhouette_strength": hair_silhouette_strength,
			"u_npr_hair_silhouette_power": hair_silhouette_power,
			"u_npr_hair_silhouette_tint": hair_silhouette_tint
		}
	)
	_set_emission(material)
	return true


func apply_outline(material: ShaderMaterial) -> bool:
	if not is_valid():
		return false
	_set_dissolve_style(material)
	_bind(
		material,
		{
			"u_npr_outline_regions_enabled": region_outline_enabled,
			"u_npr_outline_colors": outline_colors,
			"u_npr_outline_lip_fix_enabled": lip_outline_fix_enabled,
			"u_npr_outline_lip_width_scale": lip_outline_width_scale,
			"u_npr_outline_lip_width_pixels": lip_outline_width_pixels
		}
	)
	return true


func apply_visibility(material: ShaderMaterial) -> bool:
	if not is_valid():
		return false
	_set_dissolve_style(material)
	return true


func _set_emission(material: ShaderMaterial) -> void:
	_bind(
		material,
		{
			"u_npr_emission_hue_enabled": emission_hue_enabled,
			"u_npr_emission_hues": emission_hues,
			"u_npr_secondary_emission_strengths": secondary_emission_strengths,
			"u_npr_emission_hue_speed": emission_hue_speed
		}
	)


func _set_dissolve_style(material: ShaderMaterial) -> void:
	_bind(
		material,
		{
			"u_npr_dissolve_edge_width": dissolve_edge_width,
			"u_npr_dissolve_edge_color": dissolve_edge_color,
			"u_npr_dissolve_world_space": dissolve_world_space,
			"u_npr_dissolve_world_scale": dissolve_world_scale,
			"u_npr_dissolve_world_offset": dissolve_world_offset,
			"u_npr_visibility_alpha_cutoff": visibility_alpha_cutoff,
			"u_npr_visibility_dither_enabled": visibility_dither_enabled
		}
	)


static func _bind(material: ShaderMaterial, values: Dictionary) -> void:
	for key in values:
		material.set_shader_parameter(key, values[key])


static func _valid_float_array(values: PackedFloat32Array, minimum: float, maximum: float) -> bool:
	if values.size() != 8:
		return false
	for value in values:
		if not is_finite(value) or value < minimum or value > maximum:
			return false
	return true


static func _colors_finite(values: PackedColorArray) -> bool:
	for value in values:
		if not _color_finite(value):
			return false
	return true


static func _color_finite(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
