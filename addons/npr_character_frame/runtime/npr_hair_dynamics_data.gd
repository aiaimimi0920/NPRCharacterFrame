extends RefCounted
## Schema 3 dynamic palettes and authored surface-contact witnesses.

const PERFORMANCE = preload("res://addons/npr_character_frame/runtime/npr_performance_data.gd")


static func load_data(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func validate(data: Dictionary, vertex_counts := PackedInt32Array()) -> PackedStringArray:
	var error := _validate(data, vertex_counts)
	return PackedStringArray() if error.is_empty() else PackedStringArray([error])


static func _validate(data: Dictionary, counts: PackedInt32Array) -> String:
	if data.get("schema") != 3:
		return "Expected hair dynamics schema 3"
	var bones: Variant = data.get("bones")
	if not bones is Array or bones.is_empty():
		return "bones must contain appended dynamic bone names"
	var names := {}
	for name: Variant in bones:
		if not name is String or name.is_empty() or names.has(name) or name in PERFORMANCE.BONES:
			return "Dynamic bone names must be unique and distinct from canonical bones"
		names[name] = true
	if not counts.is_empty() and counts.size() != 3:
		return "Expected Body, Face and Hair vertex counts"
	var vertices: Variant = data.get("source_vertices")
	var weights: Variant = data.get("weights")
	if not vertices is Dictionary or not weights is Dictionary:
		return "source_vertices and weights must be dictionaries keyed by 0 and 2"
	var maps := {}
	for role in [0, 2]:
		var count: Variant = vertices.get(str(role))
		if not _number(count) or count < 1 or count != floor(float(count)):
			return "Missing positive source vertex count for role " + str(role)
		if not counts.is_empty() and count != counts[role]:
			return "Dynamic source vertex count does not match role " + str(role)
		var rows: Variant = weights.get(str(role))
		if not rows is Array:
			return "Dynamic weights must be arrays"
		maps[role] = {}
		for row: Variant in rows:
			if not row is Array or row.size() != 2 or not _index(row[0], count):
				return "Dynamic weight row requires a source vertex index and influences"
			if maps[role].has(row[0]) or not _influences(row[1], bones.size() + 16):
				return "Dynamic weight indices must be unique with 1-4 normalized influences"
			maps[role][row[0]] = row[1]
	var chains: Variant = data.get("chains")
	if not chains is Array or chains.is_empty():
		return "chains must be a nonempty array"
	var used := {}
	names.clear()
	for chain: Variant in chains:
		var error := _chain(chain, bones.size() + 16, used)
		if not error.is_empty():
			return error
		if names.has(chain.name):
			return "Chain names must be unique"
		names[chain.name] = true
		error = _samples(
			chain, vertices[str(int(chain.role))], maps[int(chain.role)], bones.size() + 16
		)
		if not error.is_empty():
			return chain.name + ": " + error
	if used.size() != bones.size():
		return "Every appended bone must belong to exactly one chain segment"
	return _collisions(data)


static func _chain(value: Variant, total: int, used: Dictionary) -> String:
	if not value is Dictionary or not value.get("name") is String or value.name.is_empty():
		return "Each chain requires a nonempty name"
	if not _index(value.get("parent"), 16) or not _index(value.get("role"), 3):
		return "Chain requires canonical parent and Body/Hair role"
	if value.role == 1:
		return "Face role cannot own dynamic chains"
	if not _nonnegative(value.get("radius")):
		return "Chain radius must be finite and nonnegative"
	var points: Variant = value.get("points")
	var bones: Variant = value.get("bones")
	if not points is Array or points.size() < 2 or not bones is Array:
		return "Chain requires at least two points and a bone array"
	if bones.size() != points.size() - 1:
		return "Chain must have one bone per point segment"
	for i in points.size():
		if not _numbers(points[i], 3):
			return "Chain points must be finite vectors"
		if i > 0 and _vector(points[i]).distance_squared_to(_vector(points[i - 1])) <= 1e-12:
			return "Chain segments must have nonzero length"
	for bone: Variant in bones:
		if not _index(bone, total) or bone < 16 or used.has(bone):
			return "Chain segments must own distinct appended bone indices"
		used[bone] = true
	var motion: Variant = value.get("motion")
	if not motion is Dictionary:
		return "Missing chain motion parameters"
	var pins: Variant = motion.get("pinned_nodes")
	if not pins is Array or pins.is_empty() or pins.size() > points.size():
		return "Pinned nodes must form a nonempty root prefix"
	for i in pins.size():
		if not _index(pins[i], points.size()) or pins[i] != i:
			return "Pinned nodes must form a contiguous root prefix"
	for key in ["stiffness", "wind_gain", "damping", "max_offset"]:
		if not _numbers(motion.get(key), points.size()) or not motion[key].all(_nonnegative):
			return "Motion arrays must have one finite nonnegative value per point: " + key
	return ""


static func _samples(chain: Dictionary, count: int, weights: Dictionary, total: int) -> String:
	var samples: Variant = chain.get("surface_samples")
	if not samples is Array or samples.is_empty():
		return "surface_samples must contain authored contact witnesses"
	var seen := {}
	for row: Variant in samples:
		if not row is Array or row.size() != 5:
			return "Surface sample requires point, influences, plane, face gap and vertex index"
		if not _numbers(row[0], 3) or not _influences(row[1], total) or not _nonnegative(row[3]):
			return "Invalid sample point, influences or face gap"
		if chain.role == 2 and not _numbers(row[2], 4):
			return "Hair sample requires a finite contact plane"
		if chain.role == 2:
			if absf(_vector(row[2]).length() - 1.0) > 0.001:
				return "Hair contact plane normal must have unit length"
		if not _index(row[4], count) or seen.has(row[4]) or not weights.has(row[4]):
			return "Sample vertex must be unique, in range and have explicit dynamic weights"
		seen[row[4]] = true
		for influences: Array in [row[1], weights[row[4]]]:
			for pair: Array in influences:
				if pair[0] != chain.parent and not chain.bones.has(pair[0]):
					return "Sample influences must reference its own chain or canonical parent"
	return ""


static func _collisions(data: Dictionary) -> String:
	var head: Variant = data.get("head_surface")
	if not head is Dictionary or not _index(head.get("parent"), 16):
		return "head_surface requires a canonical parent"
	if not _numbers(head.get("bvh_origin"), 3):
		return "Head BVH origin must be a finite actor-space vector"
	var faces: Variant = head.get("body_faces")
	if not faces is Array or faces.size() < 3 or faces.size() % 3 != 0:
		return "Head surface requires triangle vertex triples"
	for point: Variant in faces:
		if not _numbers(point, 3):
			return "Head triangle positions must be finite vectors"
	var colliders: Variant = data.get("colliders")
	if not colliders is Array:
		return "colliders must be an array"
	var names := {}
	for collider: Variant in colliders:
		if not collider is Dictionary or not collider.get("name") is String:
			return "Collider requires a name"
		if collider.name.is_empty() or names.has(collider.name):
			return "Collider names must be nonempty and unique"
		names[collider.name] = true
		if not _index(collider.get("parent"), 16) or not _nonnegative(collider.get("radius")):
			return "Collider requires a canonical parent and finite nonnegative radius"
		if not _numbers(collider.get("start"), 3) or not _numbers(collider.get("end"), 3):
			return "Collider endpoints must be finite vectors"
	return ""


static func _influences(value: Variant, total: int) -> bool:
	if not value is Array or value.is_empty() or value.size() > 4:
		return false
	var sum := 0.0
	for row: Variant in value:
		if not _numbers(row, 2) or not _index(row[0], total) or row[1] < 0 or row[1] > 1:
			return false
		sum += row[1]
	return absf(sum - 1.0) <= 0.00001


static func _numbers(value: Variant, count: int) -> bool:
	return value is Array and value.size() == count and value.all(_number)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _nonnegative(value: Variant) -> bool:
	return _number(value) and value >= 0


static func _index(value: Variant, count: int) -> bool:
	return _nonnegative(value) and value == floor(float(value)) and value < count


static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
