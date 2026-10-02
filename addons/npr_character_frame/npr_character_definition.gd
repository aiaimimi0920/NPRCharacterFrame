class_name NPRCharacterDefinition
extends Resource
## Three explicit rendering roles; body includes clothing and equipment.

const PERFORMANCE_DATA = preload("res://addons/npr_character_frame/runtime/npr_performance_data.gd")
const SOFT_TISSUE_DATA = preload("res://addons/npr_character_frame/runtime/npr_soft_tissue_data.gd")
const HAIR_DYNAMICS_DATA = preload(
	"res://addons/npr_character_frame/runtime/npr_hair_dynamics_data.gd"
)
const RIG_LAYOUT_DATA = preload("res://addons/npr_character_frame/runtime/npr_rig_layout_data.gd")

@export var model_scene: PackedScene
@export var body_path := NodePath("Body")
@export var face_path := NodePath("Face")
@export var hair_path := NodePath("Hair")
@export var material_set: NPRCharacterMaterials
## For authored Godot scenes whose three material chains already use this module.
@export var use_source_materials := false
@export var material_profile: NPRMaterialProfile = NPRMaterialProfile.new()
## Required by the face-motion feature; optional for base rendering-only consumers.
@export var face_motion_profile: NPRFaceMotionProfile
## Required by calibrated painted-eye/replacement features; optional for base rendering.
@export var face_atlas_profile: NPRFaceAtlasProfile
## Required by symbolic replacement surfaces; optional for base rendering.
@export var symbol_surface_profile: NPRSymbolSurfaceProfile
## Required by authored comic placement; optional for base rendering.
@export var comic_profile: NPRComicProfile
## Required by diagnostic ocular geometry; optional for base rendering.
@export var eye_geometry_profile: NPREyeGeometryProfile
## Required by the dynamic fitted hosiery layer; optional for base rendering.
@export var hosiery_profile: NPRHosieryProfile
## Required by wetness effects; optional for base rendering.
@export var wetness_profile: NPRWetnessProfile
## Required by continuous surface rain; optional for base rendering.
@export var rain_profile: NPRRainProfile
## Required by four-slot equipment; optional for base rendering.
@export var equipment_profile: NPREquipmentProfile
## Optional for base rendering; required by the full showcase camera controls.
@export var showcase_camera_profile: NPRShowcaseCameraProfile
## Optional for base rendering; required by the full showcase palette and defaults.
@export var showcase_palette_profile: NPRShowcasePaletteProfile
## Optional for base rendering; required by showcase hosiery selection.
@export var showcase_height_profile: NPRShowcaseHeightProfile
## Optional for base rendering; required by the authored performance feature.
@export_file("*.json") var performance_data_path := ""
## Optional for base rendering; required by the authored pressure corrective.
@export_file("*.json") var soft_tissue_data_path := ""
## Optional for base rendering; required by the showcase dynamic palette.
@export_file("*.json") var hair_dynamics_data_path := ""
## Optional for base rendering; required by authored skeleton diagnostics.
@export_file("*.json") var rig_layout_data_path := ""
## Zero preserves authored size and pivot. Positive height grounds/centers the model.
@export_range(0.0, 100.0) var display_height := 3.0


func mesh_paths() -> Array[NodePath]:
	return [body_path, face_path, hair_path]


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if model_scene == null:
		errors.append("model_scene is required")
	var paths := mesh_paths()
	for path in paths:
		if path.is_empty() or path.is_absolute() or ".." in str(path).split("/"):
			errors.append("Mesh paths must be nonempty relative descendant paths")
	if paths[0] == paths[1] or paths[0] == paths[2] or paths[1] == paths[2]:
		errors.append("Body, face and hair must bind distinct nodes")
	if not is_finite(display_height) or display_height < 0.0:
		errors.append("display_height must be finite and nonnegative")
	if material_profile == null or not material_profile.is_valid():
		errors.append("material_profile contains an invalid eight-region NPR parameter array")
	if not use_source_materials:
		if material_set == null:
			errors.append("material_set is required unless use_source_materials is enabled")
		else:
			errors.append_array(material_set.validate())
	elif material_set != null:
		errors.append_array(material_set.validate_optional())
	if face_motion_profile != null:
		for error in face_motion_profile.validate():
			errors.append("face_motion_profile: " + error)
	if face_atlas_profile != null:
		for error in face_atlas_profile.validate():
			errors.append("face_atlas_profile: " + error)
	if symbol_surface_profile != null:
		for error in symbol_surface_profile.validate():
			errors.append("symbol_surface_profile: " + error)
	if comic_profile != null:
		for error in comic_profile.validate():
			errors.append("comic_profile: " + error)
	if eye_geometry_profile != null:
		for error in eye_geometry_profile.validate():
			errors.append("eye_geometry_profile: " + error)
		if face_motion_profile == null:
			errors.append("Diagnostic eyes require face_motion_profile lid data")
		else:
			for error in NPREyeGeometryProfile.validate_lid_profiles(
				face_motion_profile.load_lid_data()
			):
				errors.append("eye_geometry_profile: " + error)
	if hosiery_profile != null:
		for error in hosiery_profile.validate():
			errors.append("hosiery_profile: " + error)
	if wetness_profile != null:
		for error in wetness_profile.validate():
			errors.append("wetness_profile: " + error)
	if rain_profile != null:
		for error in rain_profile.validate():
			errors.append("rain_profile: " + error)
	if equipment_profile != null:
		var equipment_errors := equipment_profile.validate()
		equipment_errors.append_array(
			equipment_profile.validate_bones(load_performance_data().get("bones", []))
		)
		for error in equipment_errors:
			errors.append("equipment_profile: " + error)
	if not performance_data_path.is_empty():
		for error in PERFORMANCE_DATA.validate(load_performance_data()):
			errors.append("performance_data: " + error)
	if not soft_tissue_data_path.is_empty():
		for error in SOFT_TISSUE_DATA.validate(load_soft_tissue_data()):
			errors.append("soft_tissue_data: " + error)
	if not hair_dynamics_data_path.is_empty():
		for error in HAIR_DYNAMICS_DATA.validate(load_hair_dynamics_data()):
			errors.append("hair_dynamics_data: " + error)
	if not rig_layout_data_path.is_empty():
		for error in RIG_LAYOUT_DATA.validate(load_rig_layout_data()):
			errors.append("rig_layout_data: " + error)
	if showcase_camera_profile != null:
		for error in showcase_camera_profile.validate():
			errors.append("showcase_camera_profile: " + error)
	if showcase_height_profile != null:
		for error in showcase_height_profile.validate():
			errors.append("showcase_height_profile: " + error)
	if showcase_palette_profile != null:
		for error in showcase_palette_profile.validate():
			errors.append("showcase_palette_profile: " + error)
	return errors


func load_performance_data() -> Dictionary:
	return PERFORMANCE_DATA.load_data(performance_data_path)


func load_soft_tissue_data() -> Dictionary:
	return SOFT_TISSUE_DATA.load_data(soft_tissue_data_path)


func load_hair_dynamics_data() -> Dictionary:
	return HAIR_DYNAMICS_DATA.load_data(hair_dynamics_data_path)


func load_rig_layout_data() -> Dictionary:
	return RIG_LAYOUT_DATA.load_data(rig_layout_data_path)
