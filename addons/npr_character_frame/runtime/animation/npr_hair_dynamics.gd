extends RefCounted
## Fixed-step particle chains drive authored weights on the canonical NPR meshes.

const STEP := 1.0 / 120.0
const SURFACE_CONTACT := preload(
	"res://addons/npr_character_frame/runtime/animation/npr_surface_contact.gd"
)

var data: Dictionary
var data_path: String
var chains: Array[Dictionary] = []
var weights := {0: {}, 2: {}}
var accumulator := 0.0
var contacts := 0
var maximum_correction := 0.0
var enabled := false
var collision_enabled := false
var _surface_contact: RefCounted


func _init(authored: Dictionary, path: String) -> void:
	data = authored.duplicate(true)
	data_path = path
	assert(data.schema == 3, "Rebuild the canonical dynamic-chain asset")
	_surface_contact = SURFACE_CONTACT.new(data)
	for role in [0, 2]:
		for row: Array in data.weights[str(role)]:
			weights[role][int(row[0])] = row[1]
	for source: Dictionary in data.chains:
		var pins := PackedInt32Array(source.motion.pinned_nodes)
		assert(not pins.is_empty() and pins[0] == 0)
		for index in pins.size():
			assert(pins[index] == index, "Pinned nodes must form a contiguous root prefix")
		var rest := PackedVector3Array()
		for point: Array in source.points:
			rest.append(_vector(point))
		chains.append(
			{
				"source": source,
				"pins": pins,
				"rest": rest,
				"points": rest.duplicate(),
				"previous": rest.duplicate(),
				"initialized": false
			}
		)


func reset() -> void:
	accumulator = 0.0
	contacts = 0
	maximum_correction = 0.0
	for chain in chains:
		chain.initialized = false


func bind_surface(role: int, arrays: Array, space: Transform3D) -> void:
	_surface_contact.bind_mesh(role, arrays, space)


func update(
	palette: Array[Transform3D], delta: float, time: float, wind: float, active: bool
) -> void:
	contacts = 0
	maximum_correction = 0.0
	accumulator = minf(accumulator + maxf(delta, 0.0), 0.1)
	var steps := floori(accumulator / STEP)
	accumulator -= steps * STEP
	for chain in chains:
		var source: Dictionary = chain.source
		var parent: Transform3D = palette[int(source.parent)]
		var rest: PackedVector3Array = chain.rest
		if not enabled or not active or not chain.initialized:
			for i in rest.size():
				chain.points[i] = parent * rest[i]
				chain.previous[i] = chain.points[i]
			chain.initialized = enabled and active
		if enabled and active:
			for substep in steps:
				_integrate(chain, parent, palette, time - (steps - substep - 1) * STEP, wind)
			if collision_enabled:
				var correction: float = _surface_contact.constrain(chain, parent, palette)
				if correction > 0.0:
					contacts += 1
					maximum_correction = maxf(maximum_correction, correction)
		var transforms := SURFACE_CONTACT.segment_transforms(chain, parent)
		for segment in source.bones.size():
			palette[int(source.bones[segment])] = (
				transforms[segment] if enabled and active else parent
			)


func _integrate(
	chain: Dictionary, parent: Transform3D, palette: Array[Transform3D], time: float, wind: float
) -> void:
	var rest: PackedVector3Array = chain.rest
	var points: PackedVector3Array = chain.points
	var previous: PackedVector3Array = chain.previous
	var motion: Dictionary = chain.source.motion
	var pins: PackedInt32Array = chain.pins
	points[0] = parent * rest[0]
	previous[0] = points[0]
	var force := Vector3(sin(time * 2.7) * 1.4, -0.18, cos(time * 1.9) * 0.6) * wind
	for i in range(1, points.size()):
		var current := points[i]
		var target: Vector3 = parent * rest[i]
		if pins.has(i):
			points[i] = target
			previous[i] = target
			continue
		var stiffness := float(motion.stiffness[i])
		var wind_gain := float(motion.wind_gain[i])
		var velocity := (current - previous[i]) * exp(-float(motion.damping[i]) * STEP)
		points[i] += velocity + ((target - current) * stiffness + force * wind_gain) * STEP * STEP
		points[i] = target + (points[i] - target).limit_length(float(motion.max_offset[i]))
		previous[i] = current
	for _iteration in 8:
		points[0] = parent * rest[0]
		for index in pins:
			points[index] = parent * rest[index]
		for i in range(1, points.size()):
			if pins.has(i):
				continue
			var length := rest[i].distance_to(rest[i - 1])
			var offset := points[i] - points[i - 1]
			if offset.length_squared() > 0.00000001:
				var correction := offset * (1.0 - length / offset.length())
				var anchored := pins.has(i - 1)
				points[i] -= correction * (1.0 if anchored else 0.5)
				if not anchored:
					points[i - 1] += correction * 0.5
		if collision_enabled:
			for i in range(1, points.size()):
				if pins.has(i):
					continue
				points[i] = _project(points[i], float(chain.source.radius), palette)
	chain.points = points
	chain.previous = previous


func _project(point: Vector3, radius: float, palette: Array[Transform3D]) -> Vector3:
	for collider: Dictionary in data.colliders:
		var transform := palette[int(collider.parent)]
		var start: Vector3 = transform * _vector(collider.start)
		var end: Vector3 = transform * _vector(collider.end)
		var nearest := Geometry3D.get_closest_point_to_segment(point, start, end)
		var offset := point - nearest
		var distance := offset.length()
		var limit := float(collider.radius) + radius
		if distance < limit:
			contacts += 1
			maximum_correction = maxf(maximum_correction, limit - distance)
			point = nearest + (offset.normalized() if distance > 0.000001 else Vector3.BACK) * limit
	return point


func snapshot(palette: Array[Transform3D]) -> Dictionary:
	var result: Array[Dictionary] = []
	for chain in chains:
		var points: Array = []
		var rest: Array = []
		for point: Vector3 in chain.points:
			points.append([point.x, point.y, point.z])
		for point: Vector3 in chain.rest:
			var transformed := palette[int(chain.source.parent)] * point
			rest.append([transformed.x, transformed.y, transformed.z])
		result.append(
			{
				"name": chain.source.name,
				"points": points,
				"rest": rest,
				"radius": chain.source.radius
			}
		)
	var colliders: Array[Dictionary] = []
	for collider: Dictionary in data.colliders:
		var parent := palette[int(collider.parent)]
		var start := parent * _vector(collider.start)
		var end := parent * _vector(collider.end)
		colliders.append(
			{
				"name": collider.name,
				"start": [start.x, start.y, start.z],
				"end": [end.x, end.y, end.z],
				"radius": collider.radius
			}
		)
	return {"chains": result, "colliders": colliders}


static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
