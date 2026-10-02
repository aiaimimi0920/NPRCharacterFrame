extends RefCounted
## Build private rest-pose Body geometry before equipment and animation setup.


static func install(
	source: MeshInstance3D, source_to_actor: Transform3D, profile: NPRHosieryProfile
) -> void:
	var arrays := source.mesh.surface_get_arrays(0)
	assert(profile != null, "Body garment regions require a hosiery profile")
	var normal_errors := profile.apply_normal_correction(arrays)
	if not normal_errors.is_empty():
		push_error("Body normal correction rejected: " + "; ".join(normal_errors))
		return
	assert(arrays[Mesh.ARRAY_CUSTOM0] == null, "Garment regions need an unused CUSTOM0 channel")
	assert(source.mesh.get_blend_shape_count() == 0, "Re-author regions for a new rigged asset")
	assert(source.skin == null, "Re-author regions for a new skinned asset")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	arrays[Mesh.ARRAY_CUSTOM0] = profile.build_regions(vertices, source_to_actor)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	)
	assert(mesh.get_surface_count() == 1, "Garment domain mesh creation failed")
	mesh.surface_set_material(0, source.mesh.surface_get_material(0))
	source.mesh = mesh
