extends Node3D
## Separate sliding lid skin: fixed face/eye geometry with curved in-between poses.

var surfaces: Array[MeshInstance3D] = []


func setup(material: ShaderMaterial, profile: NPRFaceMotionProfile) -> void:
	var data := profile.load_lid_data()
	for surface: Dictionary in data.surfaces:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vectors(surface.vertices)
		arrays[Mesh.ARRAY_NORMAL] = _vectors(surface.normals)
		var uv := PackedVector2Array()
		for row: Array in surface.uv:
			uv.append(Vector2(row[0], row[1]))
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var tangents := PackedFloat32Array()
		for index in uv.size():
			tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface.indices)
		# Closed-pose coordinates stay fixed while the head moves. CUSTOM1 is
		# exclusive to lid skin; CUSTOM0 remains the original pupil contract.
		var canvas := PackedFloat32Array()
		var left: bool = surface.name.begins_with("L_")
		var center := profile.lid_centers[0 if left else 1]
		for index in uv.size():
			var point := Vector3(surface.vertices[index][0], surface.vertices[index][1], 0)
			point += Vector3(surface.closed[index][0], surface.closed[index][1], 0)
			var local := (Vector2(point.x, point.y) - center) / profile.lid_canvas_scale
			canvas.append_array(PackedFloat32Array([local.x, local.y, -1.0 if left else 1.0, 1.0]))
		arrays[Mesh.ARRAY_CUSTOM1] = canvas
		var mesh := ArrayMesh.new()
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
		var shapes: Array[Array] = []
		for key in ["closed", "arc"]:
			mesh.add_blend_shape(key)
			var shape: Array = []
			shape.resize(Mesh.ARRAY_MAX)
			shape[Mesh.ARRAY_VERTEX] = _vectors(surface[key])
			var normal_delta := PackedVector3Array()
			normal_delta.resize(uv.size())
			var tangent_delta := PackedFloat32Array()
			tangent_delta.resize(uv.size() * 4)
			shape[Mesh.ARRAY_NORMAL] = normal_delta
			shape[Mesh.ARRAY_TANGENT] = tangent_delta
			shapes.append(shape)
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			arrays,
			shapes,
			{},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		)
		var instance := MeshInstance3D.new()
		instance.name = surface.name
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		surfaces.append(instance)


func apply(closure: float) -> void:
	for surface in surfaces:
		surface.set_blend_shape_value(0, closure)
		surface.set_blend_shape_value(1, 4.0 * closure * (1.0 - closure))


func _vectors(rows: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for row: Array in rows:
		result.append(Vector3(row[0], row[1], row[2]))
	return result
