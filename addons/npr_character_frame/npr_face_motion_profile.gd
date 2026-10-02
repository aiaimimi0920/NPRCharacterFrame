class_name NPRFaceMotionProfile
extends Resource
## Authored face calibration in actor space, after display-height alignment.
## Values are character data; this resource never modifies source geometry.

@export var expression_profile: NPRExpressionProfile
@export_file("*.json") var lid_surface_path := ""
@export_group("Disconnected feature classification")
@export var feature_component_limit := 0
@export var skin_component_min := 0
@export var eye_height_range := Vector2.ZERO
@export var eye_front_min := 0.0
@export var mouth_height_max := 0.0
@export var mouth_front_min := 0.0
@export var mouth_center_x := 0.0
@export var mouth_half_width := 0.0
@export var side_split_x := 0.0
@export_group("UV classification")
@export var iris_max_u := 0.0
@export var iris_min_v := 0.0
@export var pupil_u_range := Vector2.ZERO
@export var pupil_min_v := 0.0
## Minimum U, maximum U, minimum V, maximum V. Bounds are strict.
@export var glint_uv_bounds := Vector4.ZERO
@export var minimum_eye_vertices := 0
@export var expected_pupil_vertices := 0
@export_group("Eye movement")
@export var horizontal_motion := PackedVector3Array()
@export var vertical_motion := Vector3.ZERO
@export var pupil_scale_step := 0.0
@export var pupil_forward_offset := 0.0
@export_group("Lid canvas")
## Negative-X side first, positive-X side second; L_ and R_ surface prefixes.
@export var lid_centers := PackedVector2Array()
@export var lid_canvas_scale := Vector2.ZERO


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if expression_profile == null or expression_profile.behaviors.is_empty():
		errors.append("expression_profile requires authored behaviors")
	else:
		for behavior in expression_profile.behaviors:
			var pose: Variant = expression_profile.behaviors[behavior]
			if not pose is Dictionary or not NPRExpressionProfile.valid_pose(pose):
				errors.append("Invalid expression behavior: " + str(behavior))
	if feature_component_limit <= 0 or skin_component_min < feature_component_limit:
		errors.append("Component limits must be positive and keep feature/skin ranges separate")
	if not eye_height_range.is_finite() or eye_height_range.x >= eye_height_range.y:
		errors.append("eye_height_range requires finite increasing bounds")
	for field in [
		"eye_front_min",
		"mouth_height_max",
		"mouth_front_min",
		"mouth_center_x",
		"mouth_half_width",
		"side_split_x",
		"iris_max_u",
		"iris_min_v",
		"pupil_min_v",
		"pupil_scale_step",
		"pupil_forward_offset",
	]:
		if not is_finite(get(field)):
			errors.append(field + " must be finite")
	if mouth_half_width <= 0 or pupil_scale_step <= 0:
		errors.append("mouth_half_width and pupil_scale_step must be positive")
	if not _uv_range(pupil_u_range) or not glint_uv_bounds.is_finite():
		errors.append("Invalid pupil/glint UV bounds")
	elif (
		not _uv_range(Vector2(glint_uv_bounds.x, glint_uv_bounds.y))
		or not _uv_range(Vector2(glint_uv_bounds.z, glint_uv_bounds.w))
	):
		errors.append("glint_uv_bounds must be increasing within [0, 1]")
	for value in [iris_max_u, iris_min_v, pupil_min_v]:
		if value < 0 or value > 1:
			errors.append("UV thresholds must be within [0, 1]")
	if minimum_eye_vertices <= 0 or expected_pupil_vertices <= 0:
		errors.append("Expected eye/pupil topology counts must be positive")
	if horizontal_motion.size() != 2 or lid_centers.size() != 2:
		errors.append("horizontal_motion and lid_centers require exactly two sides")
	for value in horizontal_motion:
		if not value.is_finite():
			errors.append("horizontal_motion must be finite")
	for value in lid_centers:
		if not value.is_finite():
			errors.append("lid_centers must be finite")
	if not vertical_motion.is_finite() or not lid_canvas_scale.is_finite():
		errors.append("Motion and canvas vectors must be finite")
	if lid_canvas_scale.x <= 0 or lid_canvas_scale.y <= 0:
		errors.append("lid_canvas_scale components must be positive")
	if not lid_surface_path.begins_with("res://") or not FileAccess.file_exists(lid_surface_path):
		errors.append("lid_surface_path must name an existing res:// JSON asset")
	else:
		errors.append_array(validate_lid_data(load_lid_data()))
	return errors


func load_lid_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(lid_surface_path))
	return parsed if parsed is Dictionary else {}


static func validate_lid_data(data: Dictionary, face_vertex_count := -1) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("schema") != 2 or not data.get("surfaces") is Array:
		return PackedStringArray(["Lid data requires schema 2 and a surfaces array"])
	if data.surfaces.is_empty():
		errors.append("Lid surfaces cannot be empty")
	for surface in data.surfaces:
		if not surface is Dictionary:
			errors.append("Lid surface must be a dictionary")
			continue
		var label: String = str(surface.get("name", ""))
		if not label.begins_with("L_") and not label.begins_with("R_"):
			errors.append("Lid surface names require L_ or R_ prefix")
		var vertices: Variant = surface.get("vertices")
		if not vertices is Array or vertices.is_empty():
			errors.append(label + ": vertices are required")
			continue
		for field in ["vertices", "normals", "uv", "closed", "arc"]:
			if not _rows(surface.get(field), vertices.size(), 2 if field == "uv" else 3):
				errors.append(label + ": invalid or mismatched " + field)
		var indices: Variant = surface.get("indices")
		if not indices is Array or indices.is_empty() or indices.size() % 3 != 0:
			errors.append(label + ": indices require complete triangles")
		elif not _indices(indices, vertices.size()):
			errors.append(label + ": indices are outside the lid surface")
	for field in ["lash_vertices", "profiles"]:
		var sides: Variant = data.get(field)
		if not sides is Dictionary:
			errors.append(field + " requires L/R arrays")
			continue
		if sides.size() != 2 or not sides.has("L") or not sides.has("R"):
			errors.append(field + " accepts only the L and R sides")
		for side in ["L", "R"]:
			var rows: Variant = sides.get(side)
			if not rows is Array or rows.is_empty():
				errors.append(field + ": missing " + side)
				continue
			if field == "lash_vertices":
				if not _indices(rows, face_vertex_count):
					errors.append("Lash index is outside source face topology")
			else:
				for row in rows:
					if (
						not row is Dictionary
						or not _rows([row.get("upper"), row.get("lower")], 2, 3)
					):
						errors.append("Invalid lid profile row: " + side)
	return errors


static func _uv_range(value: Vector2) -> bool:
	return value.is_finite() and value.x >= 0 and value.y <= 1 and value.x < value.y


static func _rows(value: Variant, count: int, dimensions: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for row in value:
		if not row is Array or row.size() != dimensions:
			return false
		for component in row:
			if not (component is float or component is int) or not is_finite(component):
				return false
	return true


static func _indices(values: Array, count: int) -> bool:
	for value in values:
		if not (value is float or value is int) or not is_finite(value):
			return false
		if value != floor(value) or value < 0 or (count >= 0 and value >= count):
			return false
	return true
