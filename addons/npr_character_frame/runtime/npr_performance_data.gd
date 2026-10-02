extends RefCounted
## Schema 1 authored skin palettes, sparse face deltas and sampled actions.

const BONES := [
	"root",
	"hips",
	"spine",
	"chest",
	"neck",
	"head",
	"arm.L",
	"forearm.L",
	"arm.R",
	"forearm.R",
	"thigh.L",
	"shin.L",
	"thigh.R",
	"shin.R",
	"secondary.L",
	"secondary.R",
]
const ACTIONS := ["idle", "greeting", "look_around", "presentation"]
const SHAPES := [
	"blink.L",
	"blink.R",
	"blink_mid.L",
	"blink_mid.R",
	"happy",
	"sad",
	"angry",
	"aa",
	"ee",
	"ih",
	"oh",
	"ou",
]


static func load_data(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func validate(data: Dictionary, vertex_counts := PackedInt32Array()) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("schema") != 1 or data.get("bones") != BONES:
		errors.append("Expected schema 1 and the canonical 16 bones in documented order")
	if not vertex_counts.is_empty() and vertex_counts.size() != 3:
		errors.append("Topology requires body, face and hair vertex counts")
		return errors
	var weights: Variant = data.get("weights")
	if not weights is Array or weights.size() != 3:
		errors.append("weights must contain body, face and hair arrays")
		return errors
	for role in 3:
		if not weights[role] is Array or weights[role].is_empty():
			errors.append("weights[%d] must be a nonempty vertex array" % role)
			return errors
		if not vertex_counts.is_empty() and weights[role].size() != vertex_counts[role]:
			errors.append("weights[%d] does not match source topology" % role)
		for influences: Variant in weights[role]:
			if not _valid_influences(influences):
				errors.append("weights[%d] requires 1-4 valid influences with sum 1" % role)
				break
	errors.append_array(_validate_shapes(data.get("shapes"), weights[1].size()))
	errors.append_array(_validate_actions(data.get("actions")))
	return errors


static func _valid_influences(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > 4:
		return false
	var total := 0.0
	for row: Variant in value:
		if not _numbers(row, 2) or not _index(row[0], BONES.size()):
			return false
		if row[1] < 0.0 or row[1] > 1.0:
			return false
		total += row[1]
	return absf(total - 1.0) <= 0.00001


static func _validate_shapes(value: Variant, face_count: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		return PackedStringArray(["shapes must be a dictionary"])
	for name in SHAPES:
		if not value.has(name):
			errors.append("Missing required face shape: " + name)
	for name: Variant in value:
		if not name is String or name.is_empty() or not value[name] is Array:
			errors.append("Face shape names must be nonempty strings with delta arrays")
			continue
		for row: Variant in value[name]:
			if not _numbers(row, 4) or not _index(row[0], face_count):
				errors.append("Invalid face delta [vertex, dx, dy, dz]: " + name)
				break
	return errors


static func _validate_actions(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		return PackedStringArray(["actions must be a dictionary"])
	for name in ACTIONS:
		var clip: Variant = value.get(name)
		if not clip is Dictionary or clip.get("fps") != 30:
			errors.append("Action requires 30 fps: " + name)
			continue
		var frames: Variant = clip.get("frames")
		if not frames is Array or frames.size() < 2:
			errors.append("Action requires at least two frames: " + name)
			continue
		if not _valid_frames(frames):
			errors.append("Action requires 16 finite row-major 3x4 transforms per frame: " + name)
	return errors


static func _valid_frames(frames: Array) -> bool:
	for frame: Variant in frames:
		if not frame is Array or frame.size() != BONES.size():
			return false
		for transform: Variant in frame:
			if not _numbers(transform, 12):
				return false
	return true


static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number: Variant in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return false
	return true


static func _index(value: float, count: int) -> bool:
	return value == floor(value) and value >= 0 and value < count
