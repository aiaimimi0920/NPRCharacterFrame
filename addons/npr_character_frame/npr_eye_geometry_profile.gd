class_name NPREyeGeometryProfile
extends Resource
## Authored diagnostic ocular scene and actor-space landmarks.

const PARTS := ["Sclera", "Iris", "Pupil", "TearFilm"]
@export var model_scene: PackedScene
@export_file("*.json") var landmarks_path := ""
@export_group("Ocular movement and shading")
@export var gaze_gain := Vector2.ZERO
@export var aperture_size := Vector2.ONE
@export var aperture_slope := 0.0
@export_range(0.0, 1.0) var upper_shade := 0.0
## Sclera, iris (also optional lids), pupil, tear film; positive values recede.
@export var layer_depths := Vector4.ZERO
@export_group("Sliding shell")
@export_range(0.0, 1.0) var closure_meeting := 0.5
@export var shell_offset := 0.0
@export var shell_bulge_max := 0.0
@export var shell_bulge_ratio := 0.0
@export_group("Tear film")
@export var tear_tint := Color.WHITE
@export_range(0.0, 1.0) var tear_alpha := 0.0
@export_range(0.0, 0.05) var refraction_strength := 0.0
@export_range(1.0, 2.0) var ior := 1.0
@export_range(0.0, 0.02) var thickness := 0.0
@export_range(0.0, 1.0) var tear_transmission := 1.0


func load_landmarks() -> Dictionary:
	if not landmarks_path.begins_with("res://") or not FileAccess.file_exists(landmarks_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(landmarks_path))
	return parsed if parsed is Dictionary else {}


func validate() -> PackedStringArray:
	var errors := validate_landmarks(load_landmarks())
	errors.append_array(validate_optics())
	if model_scene == null:
		errors.append("model_scene is required for diagnostic eye geometry")
	else:
		var instance := model_scene.instantiate()
		errors.append_array(validate_scene(instance))
		instance.free()
	return errors


func validate_optics() -> PackedStringArray:
	var errors := PackedStringArray()
	if not gaze_gain.is_finite() or gaze_gain.x < 0 or gaze_gain.y < 0:
		errors.append("gaze_gain must be finite and nonnegative")
	if not aperture_size.is_finite() or aperture_size.x <= 0 or aperture_size.y <= 0:
		errors.append("aperture_size must have finite positive components")
	if not is_finite(aperture_slope):
		errors.append("aperture_slope must be finite")
	for value in [
		layer_depths.x,
		layer_depths.y,
		layer_depths.z,
		layer_depths.w,
		shell_offset,
		shell_bulge_max,
		shell_bulge_ratio
	]:
		if not is_finite(value) or value < 0:
			errors.append("Layer depths and shell parameters must be finite and nonnegative")
	for value in [
		upper_shade,
		closure_meeting,
		tear_alpha,
		tear_transmission,
		tear_tint.r,
		tear_tint.g,
		tear_tint.b,
		tear_tint.a
	]:
		if not is_finite(value) or value < 0 or value > 1:
			errors.append("Shading, closure, transmission and tint components require [0, 1]")
	for entry in [[ior, 1.0, 2.0], [refraction_strength, 0.0, 0.05], [thickness, 0.0, 0.02]]:
		if not is_finite(entry[0]) or entry[0] < entry[1] or entry[0] > entry[2]:
			errors.append("Tear optical parameter is outside its supported range")
	return errors


func apply_surface(material: ShaderMaterial, surface_name: String) -> void:
	var depth := layer_depths.y
	if surface_name.ends_with("Sclera"):
		depth = layer_depths.x
	elif surface_name.ends_with("Pupil"):
		depth = layer_depths.z
	elif surface_name.ends_with("TearFilm"):
		depth = layer_depths.w
	material.set_shader_parameter("layer_depth", depth)
	for field in [
		"aperture_size",
		"aperture_slope",
		"upper_shade",
		"closure_meeting",
		"shell_offset",
		"shell_bulge_max",
		"shell_bulge_ratio"
	]:
		material.set_shader_parameter(field, get(field))


func apply_tear(material: ShaderMaterial) -> void:
	for field in [
		"tear_tint", "tear_alpha", "refraction_strength", "ior", "thickness", "tear_transmission"
	]:
		material.set_shader_parameter(field, get(field))


static func validate_lid_profiles(data: Dictionary) -> PackedStringArray:
	var errors := NPRFaceMotionProfile.validate_lid_data(data)
	if not errors.is_empty():
		return errors
	for side in ["L", "R"]:
		var rows: Array = data.profiles[side]
		if rows.size() != 65:
			errors.append("Diagnostic eye shader requires exactly 65 lid columns: " + side)
			continue
		var first: float = rows[0].upper[0]
		var last: float = rows[-1].upper[0]
		if last <= first:
			errors.append("Lid columns require increasing X bounds: " + side)
			continue
		for index in rows.size():
			var x := lerpf(first, last, index / 64.0)
			if (
				absf(rows[index].upper[0] - x) > 0.000001
				or absf(rows[index].lower[0] - x) > 0.000001
			):
				errors.append("Lid columns must share uniform upper/lower X sampling: " + side)
				break
	return errors


static func validate_landmarks(data: Dictionary) -> PackedStringArray:
	if data.get("schema") != 2 or not data.get("landmarks") is Dictionary:
		return PackedStringArray(["Eye landmarks require schema 2 and a landmarks dictionary"])
	var errors := PackedStringArray()
	for side in ["EyeL", "EyeR"]:
		var entry: Variant = data.landmarks.get(side)
		if not entry is Dictionary or not entry.get("center") is Array:
			errors.append(side + " requires an actor-space center")
			continue
		var center: Array = entry.center
		if center.size() != 3:
			errors.append(side + " center must contain three finite numbers")
			continue
		for number: Variant in center:
			if not (number is int or number is float) or not is_finite(float(number)):
				errors.append(side + " center must contain three finite numbers")
	return errors


static func validate_scene(instance: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if not instance is Node3D or not instance.transform.is_equal_approx(Transform3D.IDENTITY):
		return PackedStringArray(["Eye scene requires an identity Node3D root"])
	var allowed := {}
	for side in ["EyeL", "EyeR"]:
		for part in PARTS + ["UpperLid", "LowerLid"]:
			allowed[side + "_" + part] = true
		for part in PARTS:
			if instance.get_node_or_null(NodePath(side + "_" + part)) == null:
				errors.append("Missing eye surface: " + side + "_" + part)
	for child in instance.get_children():
		if not allowed.has(str(child.name)) or not child is MeshInstance3D:
			errors.append("Eye scene accepts only direct named EyeL/EyeR mesh surfaces")
			continue
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or mesh.mesh.get_surface_count() != 1:
			errors.append(str(mesh.name) + " requires one mesh surface")
			continue
		if mesh.get_child_count() != 0:
			errors.append(str(mesh.name) + " must not contain nested nodes")
		if (
			str(mesh.name).ends_with("Sclera")
			or str(mesh.name).ends_with("Iris")
			or str(mesh.name).ends_with("Pupil")
		):
			if not mesh.get_active_material(0) is StandardMaterial3D:
				errors.append(str(mesh.name) + " requires StandardMaterial3D color/texture inputs")
	return errors
