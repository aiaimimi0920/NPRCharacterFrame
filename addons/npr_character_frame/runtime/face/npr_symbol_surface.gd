extends MeshInstance3D
## Location-matched replacement skin. Eye and mouth share the source face's skinning,
## UVs, normals, vertex metadata and material; no independent head-space light basis.

var _source: Array
var _points := PackedVector3Array()
var _triangles: Array[Vector3i] = []
var _shape_inputs: Array[Array] = []
var _shape_positions: Array[PackedVector3Array] = []


func setup(
	face: MeshInstance3D,
	space: Transform3D,
	material: ShaderMaterial,
	profile: NPRSymbolSurfaceProfile,
	eye := false
) -> void:
	assert(profile != null and profile.validate().is_empty(), "Symbol surfaces require calibration")
	_source = face.mesh.surface_get_arrays(0)
	_shape_inputs = face.mesh.surface_get_blend_shape_arrays(0)
	for shape in _shape_inputs:
		_shape_positions.append(PackedVector3Array())
	var vertices: PackedVector3Array = _source[Mesh.ARRAY_VERTEX]
	var domain: PackedFloat32Array = _source[Mesh.ARRAY_CUSTOM1]
	for vertex in vertices:
		_points.append(space * vertex)
	var input: PackedInt32Array = _source[Mesh.ARRAY_INDEX]
	for i in range(0, input.size(), 3):
		var t := Vector3i(input[i], input[i + 1], input[i + 2])
		if (
			domain[t.x * 4 + 3] == 2.0
			and domain[t.y * 4 + 3] == 2.0
			and domain[t.z * 4 + 3] == 2.0
			and minf(_points[t.x].z, minf(_points[t.y].z, _points[t.z].z)) > profile.skin_front_min
		):
			_triangles.append(t)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array()
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array()
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()
	arrays[Mesh.ARRAY_CUSTOM1] = PackedFloat32Array()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()
	var centers := profile.eye_centers if eye else PackedVector2Array([profile.mouth_center])
	var radius := profile.eye_radius if eye else profile.mouth_radius
	for center: Vector2 in centers:
		_build_patch(arrays, center, radius, space, eye)
	var result := ArrayMesh.new()
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	var shapes: Array[Array] = []
	for index in _shape_positions.size():
		result.add_blend_shape(face.mesh.get_blend_shape_name(index))
		var shape: Array = []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = _shape_positions[index]
		shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		shape[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		shapes.append(shape)
	result.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		shapes,
		{},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	)
	mesh = result
	material_override = material
	# Identity child transform means MODEL_MATRIX and the animated SDF basis match.
	face.add_child(self)
	skin = face.skin
	skeleton = get_path_to(face.get_node(face.skeleton))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	_shape_inputs.clear()
	_shape_positions.clear()
	_source.clear()
	_points.clear()
	_triangles.clear()


func _build_patch(
	arrays: Array, center: Vector2, radius: Vector2, space: Transform3D, eye: bool
) -> void:
	var offset: int = arrays[Mesh.ARRAY_VERTEX].size()
	const STEPS := 40
	var rims: Array[Vector3] = []
	var source_depths := PackedFloat32Array()
	for step in 16:
		var angle := TAU * float(step) / 16.0
		var rim := center + Vector2(cos(angle), sin(angle)) * radius * 0.86
		rims.append(Vector3(rim.x, rim.y, float(_sample(rim).depth)))
	for y in STEPS + 1:
		for x in STEPS + 1:
			var q := Vector2(float(x), float(y)) / STEPS * 2.0 - Vector2.ONE
			var xy := center + q * radius
			var sample := _sample(xy)
			var t: Vector3i = sample.triangle
			var w: Vector3 = sample.weights
			var z: float = sample.depth
			source_depths.append(z)
			# Smooth over the original aperture/crease, converging to exact skin at the edge.
			var bridge := 0.0
			var total := 0.0
			for rim in rims:
				var weight := 1.0 / maxf(xy.distance_squared_to(Vector2(rim.x, rim.y)), 0.000001)
				bridge += rim.z * weight
				total += weight
			var blend := 1.0 - smoothstep(0.45, 0.94, q.length())
			# The boundary follows the original facial blend shapes; symbol centers stay stable.
			for index in _shape_inputs.size():
				var positions: PackedVector3Array = _shape_inputs[index][Mesh.ARRAY_VERTEX]
				_shape_positions[index].append(
					(
						(positions[t.x] * w.x + positions[t.y] * w.y + positions[t.z] * w.z)
						* (1.0 - blend)
					)
				)
			z = lerpf(z, bridge / total, blend)
			var point := Vector3(
				xy.x, xy.y, z + 0.00012 * (1.0 - smoothstep(0.94, 1.0, q.length()))
			)
			arrays[Mesh.ARRAY_VERTEX].append(space.affine_inverse() * point)
			var normals: PackedVector3Array = _source[Mesh.ARRAY_NORMAL]
			arrays[Mesh.ARRAY_NORMAL].append(
				(normals[t.x] * w.x + normals[t.y] * w.y + normals[t.z] * w.z).normalized()
			)
			for channel in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
				if _source[channel] != null:
					arrays[channel].append(
						(
							_source[channel][t.x] * w.x
							+ _source[channel][t.y] * w.y
							+ _source[channel][t.z] * w.z
						)
					)
				elif channel == Mesh.ARRAY_COLOR:
					arrays[channel].append(Color(1, 1, 1, 0))
				else:
					arrays[channel].append(Vector2.ZERO)
			var closest := t.x if w.x >= maxf(w.y, w.z) else (t.y if w.y >= w.z else t.z)
			for channel in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
				for slot in 4:
					arrays[channel].append(_source[channel][closest * 4 + slot])
			arrays[Mesh.ARRAY_CUSTOM1].append_array(
				PackedFloat32Array([xy.x, xy.y, point.z, 4.0 if eye else 3.0])
			)
			if x < STEPS and y < STEPS:
				var i := offset + y * (STEPS + 1) + x
				arrays[Mesh.ARRAY_INDEX].append_array(
					PackedInt32Array([i, i + STEPS + 1, i + 1, i + 1, i + STEPS + 1, i + STEPS + 2])
				)
	# Harmonic continuation of the surrounding face across the aperture. This
	# preserves spatial SDF UVs rather than pinning each pixel to a hole edge.
	for channel in [
		Mesh.ARRAY_VERTEX,
		Mesh.ARRAY_NORMAL,
		Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_TEX_UV2,
		Mesh.ARRAY_COLOR
	]:
		for iteration in 160:
			for y in range(1, STEPS):
				for x in range(1, STEPS):
					var q := Vector2(float(x), float(y)) / STEPS * 2.0 - Vector2.ONE
					if q.length() >= 0.86:
						continue
					var i := offset + y * (STEPS + 1) + x
					arrays[channel][i] = (
						(
							arrays[channel][i - 1]
							+ arrays[channel][i + 1]
							+ arrays[channel][i - STEPS - 1]
							+ arrays[channel][i + STEPS + 1]
						)
						* 0.25
					)
	# Retain a narrow overlap with the uncut source skin. Never sink the new
	# eye surface behind the original socket when harmonically filling its hole.
	for y in STEPS + 1:
		for x in STEPS + 1:
			var index := y * (STEPS + 1) + x
			var point: Vector3 = space * arrays[Mesh.ARRAY_VERTEX][offset + index]
			point.z = maxf(point.z, source_depths[index] + 0.00015)
			arrays[Mesh.ARRAY_VERTEX][offset + index] = space.affine_inverse() * point


func _sample(p: Vector2) -> Dictionary:
	var best := INF
	var chosen := Vector3i.ZERO
	var weights := Vector3.ZERO
	var front := -INF
	for t in _triangles:
		var a := Vector2(_points[t.x].x, _points[t.x].y)
		var b := Vector2(_points[t.y].x, _points[t.y].y)
		var c := Vector2(_points[t.z].x, _points[t.z].y)
		var determinant := (b - a).cross(c - a)
		if absf(determinant) < 0.00000001:
			continue
		var u := (p - a).cross(c - a) / determinant
		var v := (b - a).cross(p - a) / determinant
		var w := Vector3(1.0 - u - v, u, v)
		var clamped := Vector3(maxf(w.x, 0), maxf(w.y, 0), maxf(w.z, 0))
		clamped /= clamped.x + clamped.y + clamped.z
		var projected := a * clamped.x + b * clamped.y + c * clamped.z
		var distance := p.distance_squared_to(projected)
		var depth := (
			_points[t.x].z * clamped.x + _points[t.y].z * clamped.y + _points[t.z].z * clamped.z
		)
		if distance < best - 0.0000000001 or (distance < 0.0000000001 and depth > front):
			best = distance
			front = depth
			chosen = t
			weights = clamped
	return {
		"triangle": chosen,
		"weights": weights,
		"depth":
		(
			_points[chosen.x].z * weights.x
			+ _points[chosen.y].z * weights.y
			+ _points[chosen.z].z * weights.z
		)
	}
