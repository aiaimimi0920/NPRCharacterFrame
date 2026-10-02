class_name NPRHosieryProfile
extends Resource
## Authored textures and rest-pose Body domain for the fitted hosiery layer.

const BODY_SURFACE = preload("res://addons/npr_character_frame/runtime/npr_body_surface.gd")

@export_file("*.json") var normal_correction_path := ""
@export var weave_texture: Texture2D
@export var roughness_texture: Texture2D
@export var normal_texture: Texture2D
@export var garment_mask: Texture2D
@export var tulle_mask: Texture2D
@export var stitch_mask: Texture2D
@export var domain_height_range := Vector2(0.45, 1.55)
@export var domain_half_width := 0.32
@export var domain_full_width_below := 1.05
@export var cuff_band_width := 0.016
@export var cuff_stitch_offset := 0.012
@export var cuff_stitch_width := 0.0012
@export var textile_period_m := 0.0025
@export var textile_repeats := 8
@export var shell_offset_m := 0.00025
@export var leg_ao_repair_enabled := false
@export var leg_ao_repair_uv := Vector4(0, 0, 1, 1)
@export var leg_ao_repair_values := Vector3(0, 1, 0)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in [
		"weave_texture",
		"roughness_texture",
		"normal_texture",
		"garment_mask",
		"tulle_mask",
		"stitch_mask"
	]:
		var texture := get(field) as Texture2D
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			errors.append(field + " requires a nonempty Texture2D")
	if not domain_height_range.is_finite() or domain_height_range.x >= domain_height_range.y:
		errors.append("domain_height_range requires finite increasing bounds")
	if not is_finite(domain_half_width) or domain_half_width <= 0.0:
		errors.append("domain_half_width requires a finite positive width")
	if not is_finite(domain_full_width_below):
		errors.append("domain_full_width_below requires a finite height")
	if not normal_correction_path.is_empty():
		errors.append_array(BODY_SURFACE.validate(load_normal_correction()))
	for field in ["cuff_band_width", "cuff_stitch_width"]:
		var value: float = get(field)
		if not is_finite(value) or value <= 0.0:
			errors.append(field + " requires a finite positive width")
	if not is_finite(cuff_stitch_offset) or cuff_stitch_offset < 0.0:
		errors.append("cuff_stitch_offset requires a finite nonnegative offset")
	if not is_finite(textile_period_m) or textile_period_m <= 0.0:
		errors.append("textile_period_m requires a finite positive period")
	if textile_repeats <= 0:
		errors.append("textile_repeats requires a positive count")
	if not is_finite(shell_offset_m) or shell_offset_m < 0.0:
		errors.append("shell_offset_m requires a finite nonnegative offset")
	if (
		not leg_ao_repair_uv.is_finite()
		or leg_ao_repair_uv.x < 0
		or leg_ao_repair_uv.y < 0
		or leg_ao_repair_uv.z > 1
		or leg_ao_repair_uv.w > 1
		or leg_ao_repair_uv.x >= leg_ao_repair_uv.z
		or leg_ao_repair_uv.y >= leg_ao_repair_uv.w
	):
		errors.append("leg_ao_repair_uv requires increasing bounds within [0, 1]")
	if (
		not leg_ao_repair_values.is_finite()
		or leg_ao_repair_values.x >= leg_ao_repair_values.y
		or leg_ao_repair_values.z < 0
		or leg_ao_repair_values.z > 1
	):
		errors.append("leg_ao_repair_values requires increasing heights and G floor within [0, 1]")
	return errors


func load_normal_correction() -> Dictionary:
	return BODY_SURFACE.load_data(normal_correction_path)


func validate_normal_correction(vertices: PackedVector3Array) -> PackedStringArray:
	if normal_correction_path.is_empty():
		return PackedStringArray()
	return BODY_SURFACE.validate(load_normal_correction(), vertices)


func apply_normal_correction(arrays: Array) -> PackedStringArray:
	if normal_correction_path.is_empty():
		return PackedStringArray()
	return BODY_SURFACE.apply_normals(arrays, load_normal_correction())


func build_regions(
	vertices: PackedVector3Array, source_to_actor: Transform3D
) -> PackedFloat32Array:
	var regions := PackedFloat32Array()
	regions.resize(vertices.size() * 4)
	for index in vertices.size():
		var rest := source_to_actor * vertices[index]
		var leg := absf(rest.x) < domain_half_width or rest.y < domain_full_width_below
		regions[index * 4] = (
			1.0
			if rest.y > domain_height_range.x and rest.y < domain_height_range.y and leg
			else 0.0
		)
		regions[index * 4 + 1] = rest.x
		regions[index * 4 + 2] = rest.y
		regions[index * 4 + 3] = rest.z
	return regions


func apply_material(material: ShaderMaterial) -> void:
	apply_cuff(material)
	apply_textile(material)
	material.set_shader_parameter("albedo_texture", weave_texture)
	material.set_shader_parameter("roughness_texture", roughness_texture)
	material.set_shader_parameter("normal_texture", normal_texture)
	material.set_shader_parameter("garment_mask", garment_mask)


func apply_body_material(material: ShaderMaterial) -> void:
	apply_cuff(material)
	apply_textile(material)
	apply_leg_ao(material)
	material.set_shader_parameter("u_npr_garment_mask", garment_mask)
	material.set_shader_parameter("u_npr_tulle_mask", tulle_mask)
	material.set_shader_parameter("u_npr_stitch_mask", stitch_mask)


func apply_cuff(material: ShaderMaterial) -> void:
	material.set_shader_parameter("u_npr_hosiery_cuff_band_width", cuff_band_width)
	material.set_shader_parameter("u_npr_hosiery_cuff_stitch_offset", cuff_stitch_offset)
	material.set_shader_parameter("u_npr_hosiery_cuff_stitch_width", cuff_stitch_width)


func apply_leg_ao(material: ShaderMaterial) -> void:
	material.set_shader_parameter("u_npr_leg_ao_repair_enabled", leg_ao_repair_enabled)
	material.set_shader_parameter("u_npr_leg_ao_repair_uv", leg_ao_repair_uv)
	material.set_shader_parameter("u_npr_leg_ao_repair_values", leg_ao_repair_values)


func apply_textile(material: ShaderMaterial) -> void:
	material.set_shader_parameter("u_npr_hosiery_textile_period_m", textile_period_m)
	material.set_shader_parameter("u_npr_hosiery_textile_repeats", float(textile_repeats))
	material.set_shader_parameter("u_npr_hosiery_shell_offset_m", shell_offset_m)
