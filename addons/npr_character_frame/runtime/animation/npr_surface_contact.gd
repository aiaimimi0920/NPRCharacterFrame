extends RefCounted
## Segment-local bend contact with anchored roots and exact rendered head geometry.
## All authored surface samples participate; no per-vertex clipping or hidden tips.

const MARGIN := 0.0005
const SEARCH_STEPS := 8
# TriangleMesh uses an absolute determinant epsilon. Metre-scale ear triangles
# and millimetre travel fall below it; centimetre BVH units avoid false parallels.
const COLLISION_SCALE := 100.0
var _data: Dictionary
var _collision_origin: Vector3
var _samples: Dictionary = {}
var _blockers: Dictionary = {}
var _body_head := TriangleMesh.new()


func _init(data: Dictionary) -> void:
	_data = data
	_collision_origin = _vector(data.head_surface.bvh_origin)
	var faces := PackedVector3Array()
	for point: Array in data.head_surface.body_faces:
		faces.append((_vector(point) - _collision_origin) * COLLISION_SCALE)
	# Required initialization must run even when release strips assert expressions.
	var created := _body_head.create_from_faces(faces)
	assert(created)
	for source: Dictionary in data.chains:
		var samples: Array[Dictionary] = []
		var bones := PackedInt32Array(source.bones)
		for row: Array in source.surface_samples:
			var point := Vector3(row[0][0], row[0][1], row[0][2])
			var influences: Array = []
			for pair: Array in row[1]:
				var slot := bones.find(int(pair[0]))
				assert(slot >= 0 or int(pair[0]) == int(source.parent))
				influences.append([slot, PackedFloat32Array([pair[1]])[0]])
			var plane := Plane()
			if source.role == 2:
				plane = Plane(Vector3(row[2][0], row[2][1], row[2][2]), row[2][3])
			samples.append(
				{
					"point": point,
					"weights": influences,
					"head": source.role == 2,
					"plane": plane,
					"rest_distance": plane.distance_to(point),
					"face_gap": float(row[3]),
					"index": int(row[4])
				}
			)
		_samples[source.name] = samples


func bind_mesh(role: int, arrays: Array, space: Transform3D) -> void:
	_blockers.clear()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if role == 0:
		_bind_head(arrays, space)
	for source: Dictionary in _data.chains:
		if int(source.role) != role:
			continue
		for sample: Dictionary in _samples[source.name]:
			sample.point = space * vertices[sample.index]
			sample.weights = []
			sample.weight_sum = 0.0
			sample.active = false
			var bones := PackedInt32Array(source.bones)
			for slot in 4:
				var offset: int = sample.index * 4 + slot
				if weights[offset] == 0.0:
					continue
				var local_slot := bones.find(indices[offset])
				assert(local_slot >= 0 or indices[offset] == int(source.parent))
				sample.weights.append([local_slot, weights[offset]])
				sample.weight_sum += weights[offset]
				if local_slot >= source.motion.pinned_nodes.size() - 1:
					sample.active = true


func constrain(chain: Dictionary, parent: Transform3D, palette: Array[Transform3D]) -> float:
	var candidate: PackedVector3Array = chain.points.duplicate()
	var reference := PackedVector3Array()
	for point: Vector3 in chain.rest:
		reference.append(parent * point)
	var colliders: Array[Dictionary] = []
	for source: Dictionary in _data.colliders:
		# Hair uses the authored face surface rather than the coarse head capsule.
		if chain.source.role == 2 and source.name == "head":
			continue
		var transform := palette[int(source.parent)]
		colliders.append(
			{
				"start": transform * _vector(source.start),
				"end": transform * _vector(source.end),
				"radius": float(source.radius)
			}
		)
	var head_inverse := palette[int(_data.head_surface.parent)].affine_inverse()
	_prepare_samples(chain, parent, head_inverse, colliders)
	if _safe(chain, parent, head_inverse, colliders):
		return 0.0
	var best := reference.duplicate()
	if chain.source.role == 2:
		# Resolve distal bend first; a blocked middle segment must not freeze the tip.
		chain.points = best.duplicate()
		for joint in range(candidate.size() - 1, chain.pins.size() - 1, -1):
			var origin: Vector3 = best[joint - 1]
			var axis: Vector3 = (best[joint] - origin).normalized()
			var target: Vector3 = (candidate[joint] - candidate[joint - 1]).normalized()
			var rotation := Quaternion(axis, target)
			var lower := 0.0
			var upper := 1.0
			var accepted := best.duplicate()
			for iteration in SEARCH_STEPS + 1:
				var fraction := 1.0 if iteration == 0 else (lower + upper) * 0.5
				var basis := Basis(Quaternion.IDENTITY.slerp(rotation, fraction))
				chain.points = best.duplicate()
				for index in range(joint, candidate.size()):
					chain.points[index] = origin + basis * (best[index] - origin)
				if _safe(chain, parent, head_inverse, colliders):
					lower = fraction
					accepted = chain.points.duplicate()
					if iteration == 0:
						break
				else:
					upper = fraction
			best = accepted
	else:
		var lower := 0.0
		var upper := 1.0
		for iteration in SEARCH_STEPS:
			var fraction := (lower + upper) * 0.5
			for index in candidate.size():
				chain.points[index] = reference[index].lerp(candidate[index], fraction)
			if _safe(chain, parent, head_inverse, colliders):
				lower = fraction
				best = chain.points.duplicate()
			else:
				upper = fraction
	var correction := 0.0
	for index in candidate.size():
		var offset: Vector3 = best[index] - candidate[index]
		correction = maxf(correction, offset.length())
		chain.previous[index] += offset
	chain.points = best
	return correction


func _prepare_samples(
	chain: Dictionary, parent: Transform3D, head_inverse: Transform3D, colliders: Array[Dictionary]
) -> void:
	for sample: Dictionary in _samples[chain.source.name]:
		if not sample.active:
			continue
		sample.reference = (parent * sample.point) * sample.weight_sum
		sample.head_reference = head_inverse * sample.reference
		var distance: float = sample.plane.distance_to(sample.head_reference)
		sample.face_clearance = minf(MARGIN, distance * (0.5 if distance > 0.0 else 1.0))
		var distances := PackedFloat32Array()
		for collider in colliders:
			distances.append(_capsule_distance(sample.reference, collider))
		sample.capsule_distances = distances


func _safe(
	chain: Dictionary, parent: Transform3D, head_inverse: Transform3D, colliders: Array[Dictionary]
) -> bool:
	var transforms := segment_transforms(chain, parent)
	var name: String = chain.source.name
	# Recheck the last limiting witness first. Unsafe bisection trials normally
	# fail at the same contact, without rescanning thousands of unrelated samples.
	var blocker: Dictionary = _blockers.get(name, {})
	if (
		not blocker.is_empty()
		and not _sample_safe(blocker, transforms, parent, head_inverse, colliders)
	):
		return false
	for sample: Dictionary in _samples[name]:
		if not sample.active:
			continue
		if not _sample_safe(sample, transforms, parent, head_inverse, colliders):
			_blockers[name] = sample
			return false
	return true


func _sample_safe(
	sample: Dictionary,
	transforms: Array[Transform3D],
	parent: Transform3D,
	head_inverse: Transform3D,
	colliders: Array[Dictionary]
) -> bool:
	var point := Vector3.ZERO
	for pair: Array in sample.weights:
		var transform: Transform3D = parent if pair[0] < 0 else transforms[int(pair[0])]
		point += (transform * sample.point) * float(pair[1])
	var movement := point.distance_to(sample.reference)
	if sample.head:
		var from: Vector3 = sample.head_reference
		var to: Vector3 = head_inverse * point
		var travel := to - from
		if travel.length_squared() > 0.0000000001:
			var direction := travel.normalized()
			if not (
				_body_head
				. intersect_segment(
					(from + direction * 0.00005 - _collision_origin) * COLLISION_SCALE,
					(to + direction * MARGIN - _collision_origin) * COLLISION_SCALE
				)
				. is_empty()
			):
				return false
		if movement + MARGIN >= sample.face_gap:
			if sample.plane.distance_to(to) < sample.face_clearance - 0.000001:
				return false
	for index in colliders.size():
		var distance: float = sample.capsule_distances[index]
		# Distance is 1-Lipschitz: remote samples cannot reach this capsule.
		if movement + MARGIN < distance:
			continue
		var clearance := minf(MARGIN, distance * (0.5 if distance > 0.0 else 1.0))
		if _capsule_distance(point, colliders[index]) < clearance - 0.000001:
			return false
	return true


func _bind_head(arrays: Array, space: Transform3D) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var head := PackedByteArray()
	head.resize(vertices.size())
	for index in vertices.size():
		var weight := 0.0
		for slot in 4:
			if bones[index * 4 + slot] == int(_data.head_surface.parent):
				weight += weights[index * 4 + slot]
		head[index] = int(weight > 0.99999)
	var faces := PackedVector3Array()
	for offset in range(0, indices.size(), 3):
		if head[indices[offset]] and head[indices[offset + 1]] and head[indices[offset + 2]]:
			for corner in 3:
				faces.append(
					(
						(space * vertices[indices[offset + corner]] - _collision_origin)
						* COLLISION_SCALE
					)
				)
	var created := _body_head.create_from_faces(faces)
	assert(created)


static func _capsule_distance(point: Vector3, collider: Dictionary) -> float:
	var near := Geometry3D.get_closest_point_to_segment(point, collider.start, collider.end)
	return point.distance_to(near) - float(collider.radius)


static func segment_transforms(chain: Dictionary, parent: Transform3D) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var rest: PackedVector3Array = chain.rest
	for segment in chain.source.bones.size():
		var bind_axis := (rest[segment + 1] - rest[segment]).normalized()
		var axis: Vector3 = (chain.points[segment + 1] - chain.points[segment]).normalized()
		var rotation := Basis(Quaternion((parent.basis * bind_axis).normalized(), axis))
		var basis := rotation * parent.basis
		transforms.append(Transform3D(basis, chain.points[segment] - basis * rest[segment]))
	return transforms


static func _vector(row: Array) -> Vector3:
	return Vector3(row[0], row[1], row[2])
