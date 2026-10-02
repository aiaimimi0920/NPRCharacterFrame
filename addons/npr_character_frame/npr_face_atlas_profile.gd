class_name NPRFaceAtlasProfile
extends Resource
## Authored normalized texture coordinates after the Face fragment Y flip.
## CPU eye-component classification and actor-space replacement surfaces stay separate.

const UV_FIELDS := [
	"accent_uv_min",
	"accent_uv_max",
	"accent_plate_uv",
	"replacement_eye_a_max_uv",
	"replacement_eye_b_v_range",
	"round_eye_center_uv"
]
const FIELDS := [
	"accent_uv_min",
	"accent_uv_max",
	"accent_plate_uv",
	"skin_sample_v",
	"replacement_eye_a_max_uv",
	"replacement_eye_b_min_u",
	"replacement_eye_b_v_range",
	"round_eye_center_uv",
	"round_eye_aspect",
	"round_eye_pupil_radii",
	"round_eye_disc_radii"
]

@export var accent_uv_min := Vector2.ZERO
@export var accent_uv_max := Vector2.ZERO
@export var accent_plate_uv := Vector2.ZERO
@export_range(0.0, 1.0) var skin_sample_v := 0.0
## A has only strict upper U/V bounds, not a lower-bound rectangle.
@export var replacement_eye_a_max_uv := Vector2.ZERO
## B has only a strict lower U bound and an open V interval, not an upper U bound.
@export_range(0.0, 1.0) var replacement_eye_b_min_u := 0.0
@export var replacement_eye_b_v_range := Vector2.ZERO
@export var round_eye_center_uv := Vector2.ZERO
@export var round_eye_aspect := Vector2.ZERO
@export var round_eye_pupil_radii := Vector2.ZERO
@export var round_eye_disc_radii := Vector2.ZERO


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in UV_FIELDS:
		var value: Vector2 = get(field)
		if (
			not value.is_finite()
			or value.x < 0.0
			or value.y < 0.0
			or value.x > 1.0
			or value.y > 1.0
		):
			errors.append(field + " requires finite components in [0,1]")
	for field in ["skin_sample_v", "replacement_eye_b_min_u"]:
		var value: float = get(field)
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append(field + " must be finite in [0,1]")
	if accent_uv_min.x >= accent_uv_max.x or accent_uv_min.y >= accent_uv_max.y:
		errors.append("accent_uv_min/max require increasing U and V bounds")
	if replacement_eye_b_v_range.x >= replacement_eye_b_v_range.y:
		errors.append("replacement_eye_b_v_range requires increasing bounds")
	if not round_eye_aspect.is_finite() or round_eye_aspect.x <= 0.0 or round_eye_aspect.y <= 0.0:
		errors.append("round_eye_aspect requires finite positive components")
	for field in ["round_eye_pupil_radii", "round_eye_disc_radii"]:
		var value: Vector2 = get(field)
		if not value.is_finite() or value.x <= 0.0 or value.x >= value.y or value.y > 1.0:
			errors.append(field + " requires finite increasing positive radii within [0,1]")
	return errors


## Bind static calibration only; invalid input leaves the material unchanged.
func apply_material(material: ShaderMaterial) -> bool:
	if material == null or not validate().is_empty():
		return false
	for field in FIELDS:
		material.set_shader_parameter("u_npr_face_atlas_" + field, get(field))
	material.set_shader_parameter("u_npr_face_atlas_enabled", true)
	return true
