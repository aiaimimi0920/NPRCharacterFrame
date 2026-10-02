extends RefCounted
## Schema 1 actor-rest endpoints for the framework's canonical performance palette.

const PERFORMANCE_DATA = preload("res://addons/npr_character_frame/runtime/npr_performance_data.gd")


static func load_data(path: String) -> Dictionary:
	return PERFORMANCE_DATA.load_data(path)


static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var schema: Variant = data.get("schema")
	if not (schema is int or schema is float) or schema != 1:
		errors.append("Expected rig layout schema 1")
	var bones: Variant = data.get("bones")
	if not bones is Array or bones.size() != PERFORMANCE_DATA.BONES.size():
		errors.append("Rig layout requires all canonical performance bones in documented order")
		return errors
	var preceding: Array[String] = []
	for index in bones.size():
		var bone: Variant = bones[index]
		if not bone is Dictionary:
			errors.append("Rig layout bone %d must be a dictionary" % index)
			continue
		var name: String = PERFORMANCE_DATA.BONES[index]
		if bone.get("name") != name:
			errors.append("Rig layout bone %d must be %s" % [index, name])
		var parent: Variant = bone.get("parent")
		if not bone.has("parent") or (index == 0 and parent != null):
			errors.append("Rig layout root requires an explicit null parent")
		elif index > 0 and (not parent is String or parent not in preceding):
			errors.append("Rig layout parent must refer to an earlier canonical bone: " + name)
		if not _endpoint(bone.get("head")) or not _endpoint(bone.get("tail")):
			errors.append("Rig layout head/tail must be finite three-component endpoints: " + name)
		elif (
			Vector3(bone.head[0], bone.head[1], bone.head[2])
			== Vector3(bone.tail[0], bone.tail[1], bone.tail[2])
		):
			errors.append("Rig layout bone segment must be nonzero: " + name)
		preceding.append(name)
	return errors


static func _endpoint(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for number: Variant in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return false
	return Vector3(value[0], value[1], value[2]).is_finite()
