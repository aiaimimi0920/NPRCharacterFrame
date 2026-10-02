extends RefCounted
## Authored Body corrective in aligned actor space; metadata is not a collision solver.

const SHAPE_NAME := "soft_tissue_pressure"


static func load_data(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func validate(data: Dictionary, body_vertex_count := -1) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("schema") != 1 or data.get("name") != SHAPE_NAME:
		errors.append("Expected schema 1 and name soft_tissue_pressure")
	var count: Variant = data.get("source_vertices")
	if not _number(count) or count <= 0 or count != floor(float(count)):
		errors.append("source_vertices must be a positive integer")
		return errors
	if body_vertex_count >= 0 and count != body_vertex_count:
		errors.append("source_vertices does not match original Body surface 0")
	var default_value: Variant = data.get("default")
	if not _number(default_value) or default_value != 0 or not _pressure_range(data.get("range")):
		errors.append("Pressure requires default 0 and range [0, 1]")
	var deltas: Variant = data.get("deltas")
	if not deltas is Array:
		errors.append("deltas must be an array of [vertex, dx, dy, dz]")
		return errors
	var seen := {}
	for row: Variant in deltas:
		if not row is Array or row.size() != 4:
			errors.append("Each delta must contain exactly four numbers")
			break
		if not row.all(_number):
			errors.append("Delta indices and displacements must be finite numbers")
			break
		var index: float = row[0]
		if index != floor(index) or index < 0 or index >= count:
			errors.append("Delta vertex index must be an integer within source_vertices")
			break
		if seen.has(index):
			errors.append("Duplicate delta vertex indices are not allowed")
			break
		seen[index] = true
	return errors


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _pressure_range(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and value.all(_number)
		and value[0] == 0
		and value[1] == 1
	)
