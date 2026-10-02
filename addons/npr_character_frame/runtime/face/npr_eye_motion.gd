extends RefCounted
## Rigid eye components selected by authored calibration, before head skinning.

const NAMES := ["gaze_right", "gaze_left", "gaze_up", "gaze_down", "pupil_grow", "pupil_shrink"]


static func append_shapes(
	mesh: ArrayMesh,
	arrays: Array,
	shapes: Array[Array],
	space: Transform3D,
	profile: NPRFaceMotionProfile
) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var adjacency: Array = []
	adjacency.resize(vertices.size())
	for index in vertices.size():
		adjacency[index] = []
	for index in range(0, indices.size(), 3):
		for edge in 3:
			var a := indices[index + edge]
			var b := indices[index + (edge + 1) % 3]
			adjacency[a].append(b)
			adjacency[b].append(a)
	var visited := PackedByteArray()
	visited.resize(vertices.size())
	var symbol_eyes: Array[int] = []
	var symbol_mouth: Array[int] = []
	var skin: Array[int] = []
	var eyes: Array = [[], []]
	var pupils: Array = [[], []]
	for seed in vertices.size():
		if visited[seed]:
			continue
		var pending: Array[int] = [seed]
		var component: Array[int] = []
		visited[seed] = 1
		while not pending.is_empty():
			var current: int = pending.pop_back()
			component.append(current)
			for neighbor: int in adjacency[current]:
				if not visited[neighbor]:
					visited[neighbor] = 1
					pending.append(neighbor)
		# Classify complete disconnected features, not fragments or shared skin.
		var eye_part := component.size() < profile.feature_component_limit
		var mouth_part := component.size() < profile.feature_component_limit
		for index in component:
			var actor_point := space * vertices[index]
			eye_part = (
				eye_part
				and actor_point.y > profile.eye_height_range.x
				and actor_point.y < profile.eye_height_range.y
				and actor_point.z > profile.eye_front_min
			)
			mouth_part = (
				mouth_part
				and actor_point.y < profile.mouth_height_max
				and actor_point.z > profile.mouth_front_min
				and absf(actor_point.x - profile.mouth_center_x) < profile.mouth_half_width
			)
		if eye_part:
			symbol_eyes.append_array(component)
		if mouth_part:
			symbol_mouth.append_array(component)
		if component.size() > profile.skin_component_min:
			skin.append_array(component)
		var iris := true
		var pupil := true
		var glint := true
		for index in component:
			iris = iris and uv[index].x < profile.iris_max_u and uv[index].y > profile.iris_min_v
			pupil = (
				pupil
				and uv[index].x > profile.pupil_u_range.x
				and uv[index].x < profile.pupil_u_range.y
				and uv[index].y > profile.pupil_min_v
			)
			glint = (
				glint
				and uv[index].x > profile.glint_uv_bounds.x
				and uv[index].x < profile.glint_uv_bounds.y
				and uv[index].y > profile.glint_uv_bounds.z
				and uv[index].y < profile.glint_uv_bounds.w
			)
		if not (iris or pupil or glint):
			continue
		# Only whole disconnected components qualify; atlas-adjacent skin stays fixed.
		var point := space * vertices[seed]
		var side := 0 if point.x < profile.side_split_x else 1
		eyes[side].append_array(component)
		if pupil:
			pupils[side].append_array(component)
	var deltas: Array[PackedVector3Array] = []
	for side in 2:
		for label in NAMES:
			mesh.add_blend_shape(label + ("" if side == 0 else ".R"))
			var values := PackedVector3Array()
			values.resize(vertices.size())
			deltas.append(values)
	var inverse := space.basis.inverse()
	var pupil_pivots := PackedFloat32Array()
	pupil_pivots.resize(vertices.size() * 4)
	for side in 2:
		assert(
			(
				eyes[side].size() >= profile.minimum_eye_vertices
				and pupils[side].size() == profile.expected_pupil_vertices
			),
			"Eye topology does not match the authored face motion profile"
		)
		var shape_offset: int = side * NAMES.size()
		var center := Vector3.ZERO
		var uv_center := Vector2.ZERO
		for index: int in pupils[side]:
			center += space * vertices[index]
			uv_center += uv[index]
		center /= pupils[side].size()
		uv_center /= pupils[side].size()
		for index: int in eyes[side]:
			# One translation for every iris/pupil/glint vertex: no radial falloff.
			var horizontal := profile.horizontal_motion[side]
			var vertical := profile.vertical_motion
			deltas[shape_offset][index] = inverse * horizontal
			deltas[shape_offset + 1][index] = inverse * -horizontal
			deltas[shape_offset + 2][index] = inverse * vertical
			deltas[shape_offset + 3][index] = inverse * -vertical
		for index: int in pupils[side]:
			pupil_pivots[index * 4] = uv_center.x
			pupil_pivots[index * 4 + 1] = 1.0 - uv_center.y
			pupil_pivots[index * 4 + 2] = float(side)
			var radial := (space * vertices[index] - center) * profile.pupil_scale_step
			# Clearance includes the curved iris's half-blink deformation.
			# A shared forward offset preserves the pupil's 3D similarity.
			deltas[shape_offset + 4][index] = (
				inverse * (radial + Vector3(0.0, 0.0, profile.pupil_forward_offset))
			)
			deltas[shape_offset + 5][index] = inverse * -radial
	# Exact authored lash vertices only: no atlas-threshold skin removal.
	var lids := profile.load_lid_data()
	assert(NPRFaceMotionProfile.validate_lid_data(lids, vertices.size()).is_empty())
	for side: Array in lids.lash_vertices.values():
		for index: int in side:
			pupil_pivots[index * 4 + 3] = 1.0
	for index in symbol_eyes:
		pupil_pivots[index * 4 + 3] = 1.0
	for index in symbol_mouth:
		pupil_pivots[index * 4 + 3] = 2.0
	var canvas := PackedFloat32Array()
	canvas.resize(vertices.size() * 4)
	for index in skin:
		var point := space * vertices[index]
		canvas[index * 4] = point.x
		canvas[index * 4 + 1] = point.y
		canvas[index * 4 + 2] = point.z
		canvas[index * 4 + 3] = 2.0
	arrays[Mesh.ARRAY_CUSTOM1] = canvas
	arrays[Mesh.ARRAY_CUSTOM0] = pupil_pivots
	for values in deltas:
		var shape: Array = []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = values
		# Positive weights preserve packed relative normals, as with face expressions.
		shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		shape[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		shapes.append(shape)


static func append_mouth_holds(
	mesh: ArrayMesh,
	arrays: Array,
	shapes: Array[Array],
	space: Transform3D,
	profile: NPRFaceMotionProfile
) -> void:
	# Cancel only the lower-face delta; eyebrows retain the selected 3D expression.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for label in ["happy", "sad", "angry"]:
		var index := -1
		for shape_index in mesh.get_blend_shape_count():
			if mesh.get_blend_shape_name(shape_index) == label:
				index = shape_index
		assert(index >= 0)
		var source: PackedVector3Array = shapes[index][Mesh.ARRAY_VERTEX]
		var positions := PackedVector3Array()
		positions.resize(vertices.size())
		for vertex in vertices.size():
			if (space * vertices[vertex]).y < profile.mouth_height_max:
				positions[vertex] = -source[vertex]
		var hold: Array = []
		hold.resize(Mesh.ARRAY_MAX)
		hold[Mesh.ARRAY_VERTEX] = positions
		hold[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		hold[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		mesh.add_blend_shape("symbol_hold_" + label)
		shapes.append(hold)


static func apply(
	mesh: MeshInstance3D, focus: Vector2, scale: float, profile: NPRFaceMotionProfile, side := 0
) -> void:
	var size := (scale - 1.0) / profile.pupil_scale_step
	var weights := [
		maxf(focus.x, 0),
		maxf(-focus.x, 0),
		maxf(focus.y, 0),
		maxf(-focus.y, 0),
		maxf(size, 0),
		maxf(-size, 0)
	]
	for index in NAMES.size():
		var label: String = NAMES[index] + ("" if side == 0 else ".R")
		mesh.set_blend_shape_value(mesh.find_blend_shape_by_name(label), weights[index])
