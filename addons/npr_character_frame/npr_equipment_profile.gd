class_name NPREquipmentProfile
extends Resource
## Authored inputs for the fixed head/chest/back/weapon equipment contract.

const SLOTS := ["head", "chest", "back", "weapon"]

@export_file("*.json") var geometry_path := ""
@export var material_scene: PackedScene
@export var slot_labels := PackedStringArray()
@export var attachment_bones := PackedStringArray()
@export var swatch_uvs: Dictionary = {}
@export var material_slots: Dictionary = {}


func load_geometry() -> Dictionary:
	if not geometry_path.begins_with("res://") or not FileAccess.file_exists(geometry_path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(geometry_path))
	return data if data is Dictionary else {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for values in [slot_labels, attachment_bones]:
		if values.size() != SLOTS.size():
			errors.append("Equipment requires four labels and four attachment bone names")
		for value in values:
			if value.strip_edges().is_empty():
				errors.append("Equipment labels and bone names must be nonempty")
	for key: Variant in swatch_uvs:
		var uv: Variant = swatch_uvs[key]
		if not key is String or not uv is Vector2:
			errors.append("Swatches require string keys and Vector2 UV values")
		elif not uv.is_finite() or uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1:
			errors.append("Swatch UV components require finite [0, 1] values")
	errors.append_array(validate_geometry(load_geometry()))
	var names := {}
	for slot in SLOTS:
		var group: Variant = material_slots.get(slot)
		if not group is PackedStringArray or group.is_empty():
			errors.append("Each material slot requires a nonempty PackedStringArray: " + slot)
			continue
		for node_name: String in group:
			if node_name.is_empty() or names.has(node_name):
				errors.append("Material mesh names must be nonempty and unique across slots")
			names[node_name] = true
	if material_slots.size() != SLOTS.size():
		errors.append("Material slots must contain exactly head/chest/back/weapon")
	if material_scene == null:
		errors.append("Equipment material_scene is required")
	else:
		var instance := material_scene.instantiate()
		if not instance is Node3D or not instance.transform.is_equal_approx(Transform3D.IDENTITY):
			errors.append("Equipment scene requires an identity Node3D root")
		for child in instance.get_children():
			if not child is MeshInstance3D or not names.has(str(child.name)):
				errors.append("Equipment scene requires direct, explicitly grouped mesh children")
				continue
			names.erase(str(child.name))
			if (
				child.get_child_count() != 0
				or child.mesh == null
				or child.mesh.get_surface_count() == 0
			):
				errors.append("Equipment meshes require surfaces and no nested nodes")
				continue
			for surface in child.mesh.get_surface_count():
				if not child.get_active_material(surface) is StandardMaterial3D:
					errors.append("Equipment material surfaces require StandardMaterial3D")
		if not names.is_empty():
			errors.append("Equipment scene is missing configured material meshes")
		instance.free()
	return errors


func validate_bones(bones: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	for bone in attachment_bones:
		if not bones is Array or not bones.has(bone):
			errors.append("Equipment attachment bone is absent from performance data: " + bone)
	return errors


func validate_geometry(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.size() != SLOTS.size():
		errors.append("Equipment geometry requires exactly four slot dictionaries")
	for slot in SLOTS:
		var part: Variant = data.get(slot)
		if not part is Dictionary:
			errors.append("Missing equipment geometry slot: " + slot)
			continue
		var arrays_valid := true
		for field in ["positions", "normals", "swatches", "indices"]:
			if not part.get(field) is Array or part[field].is_empty():
				errors.append(slot + " requires a nonempty " + field + " array")
				arrays_valid = false
		if not arrays_valid:
			continue
		var count: int = part.positions.size()
		if part.normals.size() != count or part.swatches.size() != count:
			errors.append(slot + " requires one normal and swatch per vertex")
		for field in ["positions", "normals"]:
			for vector: Variant in part[field]:
				if not _finite_vector(vector):
					errors.append(slot + " requires finite three-component " + field)
					break
		for swatch: Variant in part.swatches:
			if not swatch is String or not swatch_uvs.has(swatch):
				errors.append(slot + " references an unknown swatch")
				break
		if part.indices.size() % 3 != 0:
			errors.append(slot + " requires triangle index triplets")
		for index: Variant in part.indices:
			if not (index is int or index is float):
				errors.append(slot + " requires numeric indices")
				break
			if (
				not is_finite(float(index))
				or index != floor(float(index))
				or index < 0
				or index >= count
			):
				errors.append(slot + " has an out-of-range or nonintegral index")
				break
	return errors


static func _finite_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
	return true
