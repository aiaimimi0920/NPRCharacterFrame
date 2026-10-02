extends RefCounted
## Full showcase inputs are stricter than the optional base-rendering definition.

const REQUIRED_PROFILES := [
	"face_motion_profile",
	"face_atlas_profile",
	"symbol_surface_profile",
	"comic_profile",
	"eye_geometry_profile",
	"hosiery_profile",
	"wetness_profile",
	"rain_profile",
	"equipment_profile",
	"showcase_camera_profile",
	"showcase_palette_profile",
	"showcase_height_profile"
]
const REQUIRED_DATA := [
	"performance_data_path",
	"soft_tissue_data_path",
	"hair_dynamics_data_path",
	"rig_layout_data_path"
]


static func validate(
	definition: NPRCharacterDefinition, id: String, display_name: String, demo_path: String
) -> PackedStringArray:
	var errors := PackedStringArray()
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}$")
	var matched := pattern.search(id)
	if matched == null or matched.get_string() != id:
		errors.append("character_id must match [a-z][a-z0-9_]{0,63}")
	if display_name.strip_edges().is_empty():
		errors.append("character_display_name is required")
	if definition == null:
		errors.append("character_definition is required")
	else:
		errors.append_array(definition.validate())
		for field in REQUIRED_PROFILES:
			if definition.get(field) == null:
				errors.append("Full showcase requires " + field)
		for field in REQUIRED_DATA:
			if str(definition.get(field)).is_empty():
				errors.append("Full showcase requires " + field)
	if not demo_path.is_empty():
		if demo_path.get_extension().to_lower() != "json" or not FileAccess.file_exists(demo_path):
			errors.append("demo_speech_path must reference an existing Rhubarb JSON file")
	return errors
