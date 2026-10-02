extends RefCounted
## Fail at the binding boundary, before creating rendering or lighting resources.


static func validate(
	root: Node3D,
	paths: Array[NodePath],
	authored: bool,
	sdf_on_uv2 := false,
	outline_sources := PackedInt32Array(),
	hair_anisotropy := false
) -> PackedStringArray:
	var errors := PackedStringArray()
	var bound: Array[MeshInstance3D] = []
	var bounds := AABB()
	var has_bounds := false
	for index in range(paths.size()):
		var mesh := root.get_node_or_null(paths[index]) as MeshInstance3D
		var label := str(paths[index])
		if mesh == null or mesh.mesh == null:
			errors.append(label + ": expected MeshInstance3D with a mesh")
			continue
		bound.append(mesh)
		var transform := mesh.transform
		var ancestor := mesh.get_parent()
		while ancestor != null:
			if ancestor is Node3D:
				transform = ancestor.transform * transform
			if ancestor == root:
				break
			ancestor = ancestor.get_parent()
		if not transform.is_finite() or absf(transform.basis.determinant()) < 0.00000001:
			errors.append(label + ": nonfinite or singular transform")
			continue
		var current := transform * mesh.get_aabb()
		bounds = bounds.merge(current) if has_bounds else current
		has_bounds = true
		if mesh.mesh.get_surface_count() != 1:
			errors.append(label + ": version 1 requires exactly one surface per role")
			continue
		var array_mesh := mesh.mesh as ArrayMesh
		if array_mesh == null:
			errors.append(label + ": import or bake the geometry as ArrayMesh")
			continue
		if array_mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
			errors.append(label + ": triangles are required")
		var format := array_mesh.surface_get_format(0)
		var face_uv2 := sdf_on_uv2
		if authored and index == 1 and mesh.get_active_material(0) is ShaderMaterial:
			face_uv2 = bool(mesh.get_active_material(0).get_shader_parameter("u_sdf_on_uv2"))
		if index == 1 and face_uv2 and (format & Mesh.ARRAY_FORMAT_TEX_UV2) == 0:
			errors.append(label + ": SDF on UV2 requires an authored UV2 channel")
		var outline_source := outline_sources[index] if outline_sources.size() == 3 else 0
		if outline_source == 1 and (format & Mesh.ARRAY_FORMAT_TANGENT) == 0:
			errors.append(label + ": tangent smooth-outline source requires tangents")
		if outline_source == 2 and (format & Mesh.ARRAY_FORMAT_TEX_UV2) == 0:
			errors.append(label + ": UV2 smooth-outline source requires oct-encoded UV2")
		if index == 2 and hair_anisotropy and (format & Mesh.ARRAY_FORMAT_TANGENT) == 0:
			errors.append(label + ": anisotropic hair requires a tangent basis")
		if (
			(format & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TEX_UV))
			!= (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TEX_UV)
		):
			errors.append(label + ": normals and UV1 are required")
		if mesh.get_aabb().size.length_squared() <= 0.00000001:
			errors.append(label + ": geometry must have nonzero bounds")
		if (format & Mesh.ARRAY_FORMAT_BONES) != 0:
			if mesh.skin == null or not mesh.get_node_or_null(mesh.skeleton) is Skeleton3D:
				errors.append(label + ": skinned mesh requires Skin and a resolvable Skeleton3D")
		if authored:
			_validate_chain(mesh.get_active_material(0), index, label, errors)
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if mesh not in bound:
			errors.append(str(root.get_path_to(mesh)) + ": unbound mesh; merge equipment into Body")
	if not has_bounds or not is_finite(bounds.size.y) or bounds.size.y <= 0.0001:
		errors.append("Character requires finite nonzero Y height")
	return errors


static func _validate_chain(
	material: Material, role: int, label: String, errors: PackedStringArray
) -> void:
	var expected := [
		[preload("res://addons/npr_character_frame/shaders/body/body_npr.gdshader")],
		[
			preload("res://addons/npr_character_frame/shaders/face/face_base.gdshader"),
			preload("res://addons/npr_character_frame/shaders/face/face_eye_stencil.gdshader")
		],
		[
			preload("res://addons/npr_character_frame/shaders/hair/hair_base_without_eye.gdshader"),
			preload("res://addons/npr_character_frame/shaders/hair/hair_base_with_eye.gdshader")
		]
	]
	for shader in expected[role]:
		if not material is ShaderMaterial or material.shader == null:
			errors.append(label + ": incomplete NPR ShaderMaterial chain")
			return
		if material.shader != shader:
			errors.append(label + ": wrong shader for role")
		material = material.next_pass
