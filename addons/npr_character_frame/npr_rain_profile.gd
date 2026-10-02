class_name NPRRainProfile
extends Resource
## Authored surface atlas inputs. Simulation state remains owned by each rain instance.

const VERTEX_TEXTURE_WIDTH := 256

@export_file("*.json") var surface_path := ""
@export_file("*.bin") var chart_path := ""
@export_file("*.bin") var vertex_uv_path := ""


func load_surface() -> Dictionary:
	if not _resource_file(surface_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(surface_path))
	return parsed if parsed is Dictionary else {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in ["surface_path", "chart_path", "vertex_uv_path"]:
		if not _resource_file(get(field)):
			errors.append(field + " requires an existing res:// file")
	if not errors.is_empty():
		return errors
	var surface := load_surface()
	errors.append_array(validate_surface(surface))
	if not errors.is_empty():
		return errors
	var chart_bytes := int(surface.size[0]) * int(surface.size[1]) * 4
	var vertex_bytes := VERTEX_TEXTURE_WIDTH * int(surface.vertex_texture_height) * 16
	if _file_size(chart_path) != chart_bytes:
		errors.append("chart_path byte length must match size RGBA8")
	if _file_size(vertex_uv_path) != vertex_bytes:
		errors.append("vertex_uv_path byte length must match 256 x vertex_texture_height RGBAF")
	return errors


static func validate_surface(surface: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if surface.get("schema") != 1:
		errors.append("Expected rain surface schema 1")
	var size: Variant = surface.get("size")
	if not size is Array or size.size() != 2:
		errors.append("size requires two positive integers")
	elif not _integer(size[0], 1, 16384) or not _integer(size[1], 1, 16384):
		errors.append("size dimensions must be integers within [1, 16384]")
	var height: Variant = surface.get("vertex_texture_height")
	if not _integer(height, 1, 16384):
		errors.append("vertex_texture_height must be an integer within [1, 16384]")
	for key in [
		"positions", "uv", "indices", "neighbors", "charts", "areas", "kinds", "candidates"
	]:
		if not surface.get(key) is Array or surface[key].is_empty():
			errors.append(key + " requires a nonempty array")
	if not errors.is_empty():
		return errors
	var count: int = surface.positions.size()
	var triangles: int = surface.indices.size()
	if count > VERTEX_TEXTURE_WIDTH * int(height) or surface.uv.size() != count:
		errors.append("positions require matching UV rows and sufficient vertex texture capacity")
	for key in ["neighbors", "charts", "areas", "kinds"]:
		if surface[key].size() != triangles:
			errors.append(key + " must match triangle count")
	if not errors.is_empty():
		return errors
	for i in count:
		if not _vector(surface.positions[i], 3) or not _vector(surface.uv[i], 2):
			errors.append("positions/uv require finite numeric rows at vertex " + str(i))
			break
		var uv: Array = surface.uv[i]
		if uv[0] < 0 or uv[0] > 1 or uv[1] < 0 or uv[1] > 1:
			errors.append("Atlas UV must be within [0, 1] at vertex " + str(i))
			break
	for t in triangles:
		if not _indices(surface.indices[t], 3, 0, count - 1):
			errors.append("Invalid vertex indices at triangle " + str(t))
			break
		if not _indices(surface.neighbors[t], 3, -1, triangles - 1):
			errors.append("Invalid neighbor indices at triangle " + str(t))
			break
		if not _integer(surface.charts[t], 1, 65535) or not _integer(surface.kinds[t], 0, 5):
			errors.append("Invalid chart or material kind at triangle " + str(t))
			break
		if not _number(surface.areas[t]) or surface.areas[t] < 0:
			errors.append("Triangle areas must be finite and nonnegative")
			break
	if not errors.is_empty():
		return errors
	var total := 0.0
	for candidate: Variant in surface.candidates:
		if not _integer(candidate, 0, triangles - 1):
			errors.append("Candidates must be valid triangle indices")
			break
		total += float(surface.areas[int(candidate)])
	if not is_finite(total) or total <= 0:
		errors.append("Candidate triangles require finite positive total area")
	return errors


static func _resource_file(path: String) -> bool:
	return path.begins_with("res://") and FileAccess.file_exists(path)


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else -1


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and value == floor(float(value)) and value >= minimum and value <= maximum


static func _vector(value: Variant, width: int) -> bool:
	return value is Array and value.size() == width and value.all(_number)


static func _indices(value: Variant, width: int, minimum: int, maximum: int) -> bool:
	if not value is Array or value.size() != width:
		return false
	for index: Variant in value:
		if not _integer(index, minimum, maximum):
			return false
	return true
