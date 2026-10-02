extends RefCounted
## Sparse authored normal corrections in original Body mesh-local space.


static func load_data(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func validate(data: Dictionary, vertices: Variant = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("schema") != 1:
		errors.append("Body normal correction requires schema 1")
	var count: Variant = data.get("vertex_count")
	if not _number(count) or count <= 0 or count != floor(float(count)):
		errors.append("vertex_count requires a positive integer")
		return errors
	if vertices != null:
		if not vertices is PackedVector3Array or vertices.size() != count:
			errors.append("Normal correction vertex_count does not match original Body")
			return errors
	var rows: Variant = data.get("normal_rows")
	if not rows is Array:
		errors.append("normal_rows requires an array")
		return errors
	var seen := {}
	for row: Variant in rows:
		if not row is Array or row.size() != 7 or not row.all(_number):
			errors.append("Each normal row requires seven finite numbers")
			return errors
		var index: float = row[0]
		if index != floor(index) or index < 0 or index >= count or seen.has(index):
			errors.append("Normal row indices must be unique integers within vertex_count")
			return errors
		seen[index] = true
		var normal := Vector3(row[4], row[5], row[6])
		if not normal.is_finite() or normal.is_zero_approx():
			errors.append("Corrected normal must be finite and nonzero")
			return errors
		var source := Vector3(row[1], row[2], row[3])
		if not source.is_finite():
			errors.append("Normal row source position must be finite")
			return errors
		if vertices != null:
			var actual: Vector3 = vertices[int(index)]
			if not actual.is_finite() or actual.distance_to(source) >= 0.00001:
				errors.append("Normal row source position does not match original Body")
				return errors
	return errors


static func apply_normals(arrays: Array, data: Dictionary) -> PackedStringArray:
	if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		return PackedStringArray(["Body surface arrays require vertices"])
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var errors := validate(data, vertices)
	if not errors.is_empty():
		return errors
	if not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		return PackedStringArray(["Body surface arrays require normals"])
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != vertices.size():
		return PackedStringArray(["Body normals must match vertex count"])
	for row: Array in data.normal_rows:
		normals[int(row[0])] = Vector3(row[4], row[5], row[6])
	arrays[Mesh.ARRAY_NORMAL] = normals
	return PackedStringArray()


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
