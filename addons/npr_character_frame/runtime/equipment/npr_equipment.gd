extends RefCounted
## Blender geometry joins the body surface so depth, shadows and picking agree.

const SLOTS := NPREquipmentProfile.SLOTS
var authored_materials_enabled := false
var attachments := PackedInt32Array()
var _base: ArrayMesh
var _data: Dictionary
var _choice: Array = []
var _authored_materials_loaded := false
var _authored_root: Node3D
var _authored_bindings: Array[Dictionary] = []
var _surface_finishes: Array[Dictionary] = []
var _profile: NPREquipmentProfile
var _bone_indices := PackedInt32Array()
var _object_count := 0
var _textures: Dictionary = {}


func setup(actor: NPRCharacter) -> void:
	_base = actor.meshes[0].mesh
	_profile = actor.definition.equipment_profile
	assert(_profile != null, "Equipment requires an authored profile")
	_data = _profile.load_geometry()
	var bones: Array = actor.definition.load_performance_data().bones
	for bone in _profile.attachment_bones:
		_bone_indices.append(bones.find(bone))
	_load_authored_materials(actor)


func slot_label(slot: int) -> String:
	return _profile.slot_labels[slot]


func set_authored_materials_enabled(value: bool) -> void:
	authored_materials_enabled = value
	_update_authored_visibility(_choice)


func set_wetness(value: float) -> void:
	var amount := clampf(value, 0.0, 1.0)
	for finish in _surface_finishes:
		var material: StandardMaterial3D = finish.material
		# Retain authored maps and metallic identity; add a bounded surface film.
		material.roughness = float(finish.roughness) * lerpf(1.0, 0.55, amount)
		material.clearcoat_enabled = bool(finish.enabled) or amount > 0.0
		material.clearcoat = lerpf(float(finish.coat), maxf(float(finish.coat), 0.45), amount)
		material.clearcoat_roughness = lerpf(
			float(finish.coat_roughness), minf(float(finish.coat_roughness), 0.18), amount
		)


func authored_material_contract() -> Dictionary:
	return {
		"enabled": authored_materials_enabled,
		"loaded": _authored_materials_loaded,
		"objects": _object_count,
		"textures": _textures.size(),
		"visible_objects": _authored_visible_count(),
	}


func _authored_visible_count() -> int:
	if not is_instance_valid(_authored_root):
		return 0
	var count := 0
	for child: Node in _authored_root.get_children():
		if child is Node3D and (child as Node3D).visible:
			count += 1
	return count


func _load_authored_materials(actor: Node3D) -> void:
	var packed := _profile.material_scene
	if packed == null:
		return
	var authored := packed.instantiate() as Node3D
	if authored == null:
		return
	authored.name = "AuthoredEquipmentMaterials"
	authored.visible = false
	actor.add_child(authored)
	_authored_root = authored
	_authored_materials_loaded = true
	for child: Node in authored.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh := child as MeshInstance3D
		_object_count += 1
		mesh.layers = actor.meshes[0].layers
		var override := mesh.material_override as StandardMaterial3D
		mesh.material_override = null
		for surface in mesh.mesh.get_surface_count():
			var source := (
				override if override != null else mesh.get_active_material(surface)
				as StandardMaterial3D
			)
			if source == null:
				continue
			for property: Dictionary in source.get_property_list():
				if property.type != TYPE_OBJECT:
					continue
				var texture: Variant = source.get(property.name)
				if texture is Texture2D:
					_textures[texture.get_instance_id()] = true
			var material := source.duplicate() as StandardMaterial3D
			mesh.set_surface_override_material(surface, material)
			(
				_surface_finishes
				. append(
					{
						"material": material,
						"roughness": source.roughness,
						"enabled": source.clearcoat_enabled,
						"coat": source.clearcoat,
						"coat_roughness": source.clearcoat_roughness,
					}
				)
			)
		for slot in SLOTS.size():
			if _profile.material_slots[SLOTS[slot]].has(str(mesh.name)):
				_authored_bindings.append(
					{"mesh": mesh, "rest": mesh.transform, "bone": _profile.attachment_bones[slot]}
				)
	_update_authored_visibility(_choice)


func sync_pose(performance: Node) -> void:
	for binding in _authored_bindings:
		var mesh: MeshInstance3D = binding.mesh
		mesh.transform = (performance.bone_deformation(binding.bone) * binding.rest)


func apply(actor: Node3D, source: MeshInstance3D, choices: Array) -> void:
	_choice = choices.duplicate()
	attachments.clear()
	_update_authored_visibility(_choice)
	if authored_materials_enabled:
		source.mesh = _base
		return
	if not choices.has(true):
		source.mesh = _base
		return
	var arrays := _base.surface_get_arrays(0)
	var to_local := source.global_transform.affine_inverse() * actor.global_transform
	for slot in SLOTS.size():
		if not choices[slot]:
			continue
		var part: Dictionary = _data[SLOTS[slot]]
		var offset: int = arrays[Mesh.ARRAY_VERTEX].size()
		for index in part.positions.size():
			attachments.append(_bone_indices[slot])
			arrays[Mesh.ARRAY_VERTEX].append(to_local * _vector(part.positions[index]))
			arrays[Mesh.ARRAY_NORMAL].append(
				(to_local.basis.inverse().transposed() * _vector(part.normals[index])).normalized()
			)
			var uv: Vector2 = _profile.swatch_uvs[part.swatches[index]]
			# Production body shader flips V; swatches address source texture pixels.
			uv.y = 1.0 - uv.y
			arrays[Mesh.ARRAY_TEX_UV].append(uv)
			if arrays[Mesh.ARRAY_TEX_UV2] != null:
				arrays[Mesh.ARRAY_TEX_UV2].append(uv)
			if arrays[Mesh.ARRAY_COLOR] != null:
				arrays[Mesh.ARRAY_COLOR].append(Color(1, 1, 1, 1))
			if arrays[Mesh.ARRAY_TANGENT] != null:
				arrays[Mesh.ARRAY_TANGENT].append_array(PackedFloat32Array([1, 0, 0, 1]))
			# Signed region: -1 identifies actual equipment, 0 body, +1 hosiery.
			# Dyeable original clothing must not receive equipment wetness.
			arrays[Mesh.ARRAY_CUSTOM0].append_array(PackedFloat32Array([-1, 0, 0, 0]))
		for triangle in range(0, part.indices.size(), 3):
			for corner in [0, 2, 1]:
				arrays[Mesh.ARRAY_INDEX].append(offset + int(part.indices[triangle + corner]))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	)
	mesh.surface_set_material(0, _base.surface_get_material(0))
	source.mesh = mesh


func _update_authored_visibility(choices: Array) -> void:
	if not is_instance_valid(_authored_root):
		return
	_authored_root.visible = authored_materials_enabled and choices.has(true)
	for node: Node in _authored_root.get_children():
		var slot := -1
		for candidate in SLOTS.size():
			if _profile.material_slots[SLOTS[candidate]].has(str(node.name)):
				slot = candidate
				break
		if slot >= 0 and node is Node3D:
			(node as Node3D).visible = (
				authored_materials_enabled and slot < choices.size() and bool(choices[slot])
			)


func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
