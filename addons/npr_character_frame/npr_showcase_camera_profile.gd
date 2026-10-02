class_name NPRShowcaseCameraProfile
extends Resource
## Authored showcase framing in displayed actor space; not automatic model fitting.

const VIEW_INDICES := {"full": 0, "half": 1, "face": 2}

@export var view_heights := PackedFloat64Array()
@export var view_distances := PackedFloat64Array()
@export var horizontal_offset := 0.0
@export var vertical_offset := 0.0
@export_range(1.0, 179.0) var field_of_view := 36.0
@export var pressure_target := Vector3.ZERO
@export var pressure_distance := 1.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if view_heights.size() != VIEW_INDICES.size() or view_distances.size() != VIEW_INDICES.size():
		errors.append("view_heights and view_distances require full, half and face in order")
	for height in view_heights:
		if not is_finite(height):
			errors.append("view_heights must be finite")
	for distance in view_distances:
		if not is_finite(distance) or distance <= 0.0:
			errors.append("view_distances must be finite and positive")
	if not is_finite(horizontal_offset) or not is_finite(vertical_offset):
		errors.append("Camera offsets must be finite")
	if not is_finite(field_of_view) or field_of_view < 1.0 or field_of_view > 179.0:
		errors.append("field_of_view must be finite and within 1 to 179 degrees")
	if not pressure_target.is_finite():
		errors.append("pressure_target must be finite")
	if not is_finite(pressure_distance) or pressure_distance <= 0.0:
		errors.append("pressure_distance must be finite and positive")
	return errors
