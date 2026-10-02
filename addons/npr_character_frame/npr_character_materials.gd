class_name NPRCharacterMaterials
extends Resource
## Authored inputs. Textures are shared; every actor owns its material instances.

enum SmoothNormalSource { VERTEX_NORMAL, TANGENT, UV2_OCT }

const BODY = preload("res://addons/npr_character_frame/materials/body.tres")
const FACE = preload("res://addons/npr_character_frame/materials/face.tres")
const EYE = preload("res://addons/npr_character_frame/materials/eye.tres")
const HAIR = preload("res://addons/npr_character_frame/materials/hair.tres")
const EYE_HAIR = preload("res://addons/npr_character_frame/materials/eye_hair.tres")
const TEXTURE_FIELDS := [
	"body_base",
	"body_ilm",
	"body_lut",
	"body_ramp",
	"body_cool_ramp",
	"face_base",
	"face_ilm",
	"face_map",
	"face_ramp",
	"hair_base",
	"hair_ilm",
	"hair_ramp",
	"hair_cool_ramp"
]

@export_group("Body and equipment")
@export var body_base: Texture2D
@export var body_ilm: Texture2D
@export var body_lut: Texture2D
@export var body_ramp: Texture2D
@export var body_cool_ramp: Texture2D
@export_group("Optional packed controls")
## R stocking, G MatCap, B secondary emission, A dissolve protection.
@export var body_effects: Texture2D
@export var matcap_texture: Texture2D
@export_group("Face")
@export var face_base: Texture2D
@export var face_ilm: Texture2D
@export var face_map: Texture2D
@export var face_ramp: Texture2D
## R expression shadow, G highlight, B blush, A dissolve protection.
@export var face_expression: Texture2D
## R lip core, G lip feather/width, B face-outline holdout, A reserved.
@export var face_outline_control: Texture2D
@export var sdf_on_uv2 := false
## Local mesh axes, after Godot import. +Z faces the viewer in the standard.
@export var face_forward := Vector3(0, 0, 1)
@export var face_right := Vector3(1, 0, 0)
@export_group("Hair")
@export var hair_base: Texture2D
@export var hair_ilm: Texture2D
@export var hair_ramp: Texture2D
@export var hair_cool_ramp: Texture2D
## R anisotropy, G silhouette/side fade, B secondary emission, A dissolve protection.
@export var hair_effects: Texture2D
@export var hair_flow_map: Texture2D
@export var dissolve_noise: Texture2D
## Local view direction used by the eye-reveal alpha, not the highlight ribbon.
@export var hair_sheen_axis := Vector3(0, 0, 1)
## Local axis used only by side-selective silhouette fading.
@export var hair_side_axis := Vector3(1, 0, 0)
@export_group("Outline smooth normals")
@export var body_outline_smooth_normal_source := SmoothNormalSource.VERTEX_NORMAL
@export var face_outline_smooth_normal_source := SmoothNormalSource.VERTEX_NORMAL
@export var hair_outline_smooth_normal_source := SmoothNormalSource.VERTEX_NORMAL


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in TEXTURE_FIELDS:
		var texture := get(field) as Texture2D
		if texture == null or texture.get_width() < 1 or texture.get_height() < 1:
			errors.append(field + " requires a nonempty Texture2D")
	if body_lut != null and (body_lut.get_width() != 8 or body_lut.get_height() != 8):
		errors.append("body_lut must be 8 x 8, including reserved rim/bloom rows")
	for texture in [body_ramp, body_cool_ramp, hair_ramp, hair_cool_ramp]:
		if texture != null and (texture.get_width() < 2 or texture.get_height() != 16):
			errors.append("Body/hair ramps require 16 rows and at least two columns")
	errors.append_array(validate_optional())
	return errors


## Source-material characters may provide only these optional extension inputs.
func validate_optional() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _unit_axis(face_forward) or not _unit_axis(face_right):
		errors.append("Face axes must be finite unit vectors")
	elif absf(face_forward.dot(face_right)) > 0.001:
		errors.append("Face forward and right must be perpendicular")
	if not _unit_axis(hair_sheen_axis):
		errors.append("hair_sheen_axis must be a finite unit vector")
	if not _unit_axis(hair_side_axis):
		errors.append("hair_side_axis must be a finite unit vector")
	for field in [
		"body_effects",
		"matcap_texture",
		"face_expression",
		"face_outline_control",
		"hair_effects",
		"hair_flow_map",
		"dissolve_noise"
	]:
		var texture := get(field) as Texture2D
		if texture != null and (texture.get_width() < 1 or texture.get_height() < 1):
			errors.append(field + " must be null or a nonempty Texture2D")
	for source in [
		body_outline_smooth_normal_source,
		face_outline_smooth_normal_source,
		hair_outline_smooth_normal_source
	]:
		if source < SmoothNormalSource.VERTEX_NORMAL or source > SmoothNormalSource.UV2_OCT:
			errors.append("Outline smooth-normal sources must be NORMAL, TANGENT or UV2 oct")
	return errors


func build() -> Array[ShaderMaterial]:
	if not validate().is_empty():
		return []
	var body := BODY.duplicate() as ShaderMaterial
	var face := FACE.duplicate() as ShaderMaterial
	var eye := EYE.duplicate() as ShaderMaterial
	var hair := HAIR.duplicate() as ShaderMaterial
	var eye_hair := EYE_HAIR.duplicate() as ShaderMaterial
	_bind(
		body,
		{
			"u_texture_base_map": body_base,
			"u_texture_light_map": body_ilm,
			"u_material_values_pack_lut": body_lut,
			"u_texture_diffuse_ramp": body_ramp,
			"u_texture_diffuse_cool_ramp": body_cool_ramp,
			"u_npr_surface_effects_enabled": body_effects != null,
			"u_npr_surface_effects": body_effects,
			"u_npr_matcap_texture": matcap_texture,
			"u_npr_dissolve_noise": dissolve_noise
		}
	)
	_bind(
		face,
		{
			"u_texture_base_map": face_base,
			"u_texture_ilm_map": face_ilm,
			"u_texture_face": face_map,
			"u_texture_diffuse_ramp": face_ramp,
			"u_sdf_on_uv2": sdf_on_uv2,
			"u_npr_sdf_basis_enabled": true,
			"u_npr_face_forward": face_forward,
			"u_npr_face_right": face_right,
			"u_npr_capture_fog_enabled": false,
			"u_npr_surface_effects_enabled": face_expression != null,
			"u_npr_surface_effects": face_expression,
			"u_npr_outline_control_enabled": face_outline_control != null,
			"u_npr_outline_control": face_outline_control,
			"u_npr_dissolve_noise": dissolve_noise
		}
	)
	# Eye coverage uses the base UV atlas, independently of the face SDF UV set.
	_bind(
		eye,
		{
			"u_texture_ilm": face_ilm,
			"u_sdf_on_uv2": true,
			"u_npr_surface_effects_enabled": face_expression != null,
			"u_npr_surface_effects": face_expression,
			"u_npr_outline_control_enabled": face_outline_control != null,
			"u_npr_outline_control": face_outline_control,
			"u_npr_dissolve_noise": dissolve_noise
		}
	)
	for material in [hair, eye_hair]:
		_bind(
			material,
			{
				"u_texture_base_map": hair_base,
				"u_texture_ilm_map": hair_ilm,
				"u_texture_diffuse_ramp": hair_ramp,
				"u_texture_diffuse_cool_ramp": hair_cool_ramp,
				"u_npr_hair_sheen_axis": hair_sheen_axis,
				"u_npr_hair_side_axis": hair_side_axis,
				"u_npr_surface_effects_enabled": hair_effects != null,
				"u_npr_surface_effects": hair_effects,
				"u_npr_hair_flow_enabled": hair_flow_map != null,
				"u_npr_hair_flow_map": hair_flow_map,
				"u_npr_dissolve_noise": dissolve_noise
			}
		)
	face.next_pass = eye
	hair.next_pass = eye_hair
	return [body, face, hair]


## Bind extension textures to duplicated, module-compatible source materials.
## Existing base/ILM/LUT/ramp parameters remain owned by the authored source chain.
func apply_optional_to(source_materials: Array[ShaderMaterial]) -> bool:
	if source_materials.size() != 3 or not validate_optional().is_empty():
		return false
	var body := source_materials[0]
	var face := source_materials[1]
	var hair := source_materials[2]
	if face.next_pass is not ShaderMaterial or hair.next_pass is not ShaderMaterial:
		return false
	var eye := face.next_pass as ShaderMaterial
	var eye_hair := hair.next_pass as ShaderMaterial
	_bind(
		body,
		{
			"u_npr_surface_effects_enabled": body_effects != null,
			"u_npr_surface_effects": body_effects,
			"u_npr_matcap_texture": matcap_texture,
			"u_npr_dissolve_noise": dissolve_noise
		}
	)
	for material in [face, eye]:
		_bind(
			material,
			{
				"u_npr_surface_effects_enabled": face_expression != null,
				"u_npr_surface_effects": face_expression,
				"u_npr_outline_control_enabled": face_outline_control != null,
				"u_npr_outline_control": face_outline_control,
				"u_npr_dissolve_noise": dissolve_noise
			}
		)
	for material in [hair, eye_hair]:
		_bind(
			material,
			{
				"u_npr_hair_side_axis": hair_side_axis,
				"u_npr_surface_effects_enabled": hair_effects != null,
				"u_npr_surface_effects": hair_effects,
				"u_npr_hair_flow_enabled": hair_flow_map != null,
				"u_npr_hair_flow_map": hair_flow_map,
				"u_npr_dissolve_noise": dissolve_noise
			}
		)
	return true


static func _bind(material: ShaderMaterial, values: Dictionary) -> void:
	for key in values:
		if values[key] != null:
			material.set_shader_parameter(key, values[key])


func outline_smooth_normal_source(role: int) -> int:
	return [
		body_outline_smooth_normal_source,
		face_outline_smooth_normal_source,
		hair_outline_smooth_normal_source
	][clampi(role, 0, 2)]


static func _unit_axis(axis: Vector3) -> bool:
	return axis.is_finite() and absf(axis.length_squared() - 1.0) < 0.001
