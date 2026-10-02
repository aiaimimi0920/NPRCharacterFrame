extends RefCounted
## Matched exposed neck-cut arc: head-local face points, character-local body points.
## Rounded capture landmarks locate REAL imported vertices, not synthetic endpoints.

const TOLERANCE := 0.001
const FACE_POINTS := [
	Vector3(0, -0.2948, 0.6164),
	Vector3(0.1558, -0.2412, 0.5612),
	Vector3(0.3614, -0.1294, 0.4714),
	Vector3(0.5088, -0.0310, 0.3992),
	Vector3(0.6336, 0.0854, 0.3364),
	Vector3(0.7638, 0.2286, 0.2674),
	Vector3(0.9050, 0.4472, 0.1790),
	Vector3(0.9936, 0.6300, 0.1008),
	Vector3(-0.1558, -0.2412, 0.5612),
	Vector3(-0.3614, -0.1294, 0.4714),
	Vector3(-0.5088, -0.0310, 0.3992),
	Vector3(-0.6336, 0.0854, 0.3364),
	Vector3(-0.7638, 0.2286, 0.2674),
	Vector3(-0.9050, 0.4472, 0.1790),
	Vector3(-0.9936, 0.6300, 0.1008),
]
const BODY_POINTS := [
	Vector3(-0.5824, 7.7490, -0.3630),
	Vector3(-0.4314, 7.8096, -0.4244),
	Vector3(-0.2358, 7.9286, -0.5260),
	Vector3(-0.0970, 8.0314, -0.6082),
	Vector3(0.0180, 8.1512, -0.6824),
	Vector3(0.1362, 8.2974, -0.7654),
	Vector3(0.2592, 8.5176, -0.8746),
	Vector3(0.3328, 8.6988, -0.9696),
	Vector3(-0.7422, 7.7850, -0.4212),
	Vector3(-0.9564, 7.8716, -0.5186),
	Vector3(-1.1112, 7.9512, -0.5978),
	Vector3(-1.2452, 8.0512, -0.6694),
	Vector3(-1.3866, 8.1768, -0.7498),
	Vector3(-1.5448, 8.3748, -0.8560),
	Vector3(-1.6480, 8.5420, -0.9494),
]


func measure(character: Node3D) -> Dictionary:
	var head := character.get_node("Head") as Node3D
	var face_vertices := _vertices_in_frame(character.get_node("Head/Face/脸部模型"), head)
	var body_vertices := _vertices_in_frame(character.get_node("Body/模型"), character)
	var head_to_character := character.global_transform.affine_inverse() * head.global_transform
	var squared_error := 0.0
	var max_gap := 0.0
	var fixture_error := 0.0
	for index in range(FACE_POINTS.size()):
		var face := _nearest(face_vertices, FACE_POINTS[index])
		var body := _nearest(body_vertices, BODY_POINTS[index])
		fixture_error = maxf(fixture_error, face.distance_to(FACE_POINTS[index]))
		fixture_error = maxf(fixture_error, body.distance_to(BODY_POINTS[index]))
		var gap := (head_to_character * face).distance_to(body)
		max_gap = maxf(max_gap, gap)
		squared_error += gap * gap
	return {
		"pairs": FACE_POINTS.size(),
		"max_gap": max_gap,
		"rms_gap": sqrt(squared_error / FACE_POINTS.size()),
		"fixture_error": fixture_error,
		"pass": max_gap < TOLERANCE and fixture_error < TOLERANCE,
	}


func _vertices_in_frame(mesh: MeshInstance3D, frame: Node3D) -> PackedVector3Array:
	var relative := frame.global_transform.affine_inverse() * mesh.global_transform
	var result := PackedVector3Array()
	for surface in range(mesh.mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			result.append(relative * vertex)
	return result


func _nearest(vertices: PackedVector3Array, target: Vector3) -> Vector3:
	var best := Vector3.INF
	var distance := INF
	for vertex in vertices:
		var candidate := vertex.distance_squared_to(target)
		if candidate < distance:
			distance = candidate
			best = vertex
	return best
