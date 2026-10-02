extends "wardrobe_hair_style_regression.gd"
## Authored input validation followed by the existing motion/style regression.

const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const HAIR_DATA = preload("res://addons/npr_character_frame/runtime/npr_hair_dynamics_data.gd")
const DRIVER = preload("res://addons/npr_character_frame/runtime/animation/npr_performance.gd")
const CONTACT = preload("res://addons/npr_character_frame/runtime/animation/npr_surface_contact.gd")


func _run() -> void:
	_contract()
	_origin_contract()
	if not _failed():
		_alternate()
	if _failed():
		FileAccess.open(_output.path_join("hair_style.json"), FileAccess.WRITE).store_string(
			JSON.stringify({"checks": _checks}, "  ")
		)
		quit(1)
		return
	await super._run()


func _contract() -> void:
	var data := DEFINITION.load_hair_dynamics_data()
	_record(HAIR_DATA.validate(data).is_empty(), "Sample dynamic data satisfies schema 3")
	_record(not HAIR_DATA.validate({}).is_empty(), "Empty dynamic data is rejected")
	_record(
		not HAIR_DATA.validate(data, PackedInt32Array([1, 1, 1])).is_empty(),
		"Dynamic weights must match actual source topology"
	)
	var damaged := data.duplicate(true)
	damaged.chains[0].motion.pinned_nodes = [0, 2]
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Noncontiguous pins are rejected")
	damaged = data.duplicate(true)
	damaged.chains[0].motion.damping[0] = NAN
	_record(
		not HAIR_DATA.validate(damaged).is_empty(), "Nonfinite simulation parameter is rejected"
	)
	damaged = data.duplicate(true)
	damaged.chains[0].bones[0] = 5
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Chain cannot overwrite canonical bone")
	damaged = data.duplicate(true)
	damaged.chains[0].points[1] = damaged.chains[0].points[0].duplicate()
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Zero-length segment is rejected")
	damaged = data.duplicate(true)
	damaged.weights["2"][0][0] = data.source_vertices["2"]
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Out-of-range dynamic vertex is rejected")
	damaged = data.duplicate(true)
	damaged.chains[0].surface_samples[0][1] = [[3, 1.0]]
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Foreign sample skin parent is rejected")
	damaged = data.duplicate(true)
	damaged.chains[0].surface_samples[0][4] = -1
	_record(
		not HAIR_DATA.validate(damaged).is_empty(), "Negative surface witness index is rejected"
	)
	damaged = data.duplicate(true)
	damaged.colliders[0].parent = 999
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Collider parent must exist")
	damaged = data.duplicate(true)
	damaged.head_surface.body_faces.pop_back()
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Incomplete head triangle is rejected")
	damaged = data.duplicate(true)
	damaged.head_surface.erase("bvh_origin")
	_record(not HAIR_DATA.validate(damaged).is_empty(), "Missing head BVH origin is rejected")
	for origin: Variant in [
		null, [], [0, 0], [0, 0, 0, 0], [0, NAN, 0], [INF, 0, 0], [false, 0, 0]
	]:
		damaged = data.duplicate(true)
		damaged.head_surface.bvh_origin = origin
		_record(not HAIR_DATA.validate(damaged).is_empty(), "Invalid head BVH origin is rejected")
	damaged = data.duplicate(true)
	damaged.head_surface.bvh_origin = [3.25, -4.5, 2.0]
	_record(HAIR_DATA.validate(damaged).is_empty(), "Alternate finite head BVH origin is accepted")
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.hair_dynamics_data_path = "res://.temp/missing_hair_dynamics.json"
	_record(not definition.validate().is_empty(), "Missing configured asset is rejected")
	definition.hair_dynamics_data_path = ""
	_record(definition.validate().is_empty(), "Base rendering permits no dynamic asset")


func _origin_contract() -> void:
	# Millimetre travel through a 4 mm triangle exercises the absolute engine epsilon.
	for origin: Vector3 in [Vector3(-0.112, 2.58, -0.06), Vector3(3.25, -4.5, 2.0)]:
		var base := origin + Vector3(0.12, 0.18, -0.08)
		var faces := PackedVector3Array(
			[base, base + Vector3(0.004, 0, 0), base + Vector3(0, 0.004, 0)]
		)
		var rows: Array = []
		for point in faces:
			rows.append([point.x, point.y, point.z])
		var contact := CONTACT.new(
			{
				"head_surface":
				{"parent": 5, "bvh_origin": [origin.x, origin.y, origin.z], "body_faces": rows},
				"chains": [],
				"colliders": []
			}
		)
		_record(
			contact._collision_origin == origin, "Contact uses the authored per-instance origin"
		)
		_record(
			_bvh_faces_match(contact, faces, origin),
			"Authored triangles use the configured BVH origin"
		)
		var from := base + Vector3(0.001, 0.001, 0.001)
		var raw := TriangleMesh.new()
		_record(raw.create_from_faces(faces), "Unscaled small-triangle control builds")
		_record(
			raw.intersect_segment(from, from + Vector3(0, 0, -0.002)).is_empty(),
			"Unscaled millimetre contact is below the absolute determinant epsilon"
		)
		_record(
			not _query_clear(contact, from, -0.002), "Scaled authored head blocks a crossing sample"
		)
		_record(_query_clear(contact, from, 0.002), "Authored head permits a noncrossing sample")
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
			[Vector3.ZERO, Vector3(0.004, 0, 0), Vector3(0, 0.004, 0)]
		)
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array([5, 0, 0, 0, 5, 0, 0, 0, 5, 0, 0, 0])
		arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
		var offset := Vector3(0.02, 0, 0)
		contact.bind_mesh(0, arrays, Transform3D(Basis.IDENTITY, base + offset))
		for index in faces.size():
			faces[index] += offset
		_record(
			_bvh_faces_match(contact, faces, origin), "Actual Body rebuild uses the same BVH origin"
		)
		_record(_query_clear(contact, from, -0.002), "Body rebuild replaces the original triangle")
		_record(
			not _query_clear(contact, from + offset, -0.002),
			"Rebuilt Body blocks a crossing sample"
		)
		_record(
			_query_clear(contact, from + offset, 0.002), "Rebuilt Body permits a noncrossing sample"
		)
		var head_pose := Transform3D(Basis(Vector3.UP, 0.35), Vector3(0.4, 0.2, -0.3))
		_record(
			not _query_clear(contact, from + offset, -0.002, head_pose),
			"Posed head query returns to actor rest space before applying the BVH origin"
		)


func _bvh_faces_match(contact: RefCounted, faces: PackedVector3Array, origin: Vector3) -> bool:
	var actual: PackedVector3Array = contact._body_head.get_faces()
	if actual.size() != faces.size():
		return false
	for index in faces.size():
		if not actual[index].is_equal_approx((faces[index] - origin) * 100.0):
			return false
	return true


func _query_clear(
	contact: RefCounted, from: Vector3, travel: float, head_pose := Transform3D.IDENTITY
) -> bool:
	var sample := {
		"point": from,
		"weights": [[0, 1.0]],
		"reference": head_pose * from,
		"head_reference": from,
		"head": true,
		"face_gap": 1.0
	}
	var transforms: Array[Transform3D] = [
		head_pose * Transform3D(Basis.IDENTITY, Vector3(0, 0, travel))
	]
	var colliders: Array[Dictionary] = []
	return contact._sample_safe(
		sample, transforms, head_pose, head_pose.affine_inverse(), colliders
	)


func _alternate() -> void:
	var original := DEFINITION.load_hair_dynamics_data()
	var data := original.duplicate(true)
	data.chains[0].motion.wind_gain.fill(0.0)
	data.chains[0].motion.max_offset.fill(0.0)
	var path := _output.path_join("alternate_hair.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.hair_dynamics_data_path = ProjectSettings.localize_path(path.replace("\\", "/"))
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_record(actor.initialized, "Alternate chain configuration initializes production actor")
	if not actor.initialized:
		actor.free()
		return
	var driver := DRIVER.new()
	driver.automatic = false
	actor.add_child(driver)
	driver.setup(actor)
	var neutral: Array = actor.meshes[2].mesh.surface_get_arrays(0)
	driver.wind_strength = 1.0
	driver.set_hair_dynamic_enabled(true)
	for frame in 30:
		driver.apply_pose(0.0, 1.0 / 60.0)
	var chain: Dictionary = driver.dynamics.chains[0]
	var parent: Transform3D = driver.bone_deformation("head")
	var stationary := true
	for i in chain.points.size():
		stationary = stationary and chain.points[i].distance_to(parent * chain.rest[i]) < 0.000001
	_record(stationary, "Configured zero offsets hold the actual simulated chain in wind")
	_record(
		driver.dynamics.data_path == definition.hair_dynamics_data_path,
		"Driver uses the character-selected asset path"
	)
	driver.set_hair_dynamic_enabled(false)
	var restored: Array = actor.meshes[2].mesh.surface_get_arrays(0)
	_record(
		(
			restored[Mesh.ARRAY_BONES] == neutral[Mesh.ARRAY_BONES]
			and restored[Mesh.ARRAY_WEIGHTS] == neutral[Mesh.ARRAY_WEIGHTS]
		),
		"Disabling dynamics restores canonical skin weights exactly"
	)
	_record(
		DEFINITION.load_hair_dynamics_data() == original, "Alternate input leaves sample unchanged"
	)
	actor.free()


func _failed() -> bool:
	return _checks.any(func(row: Dictionary): return not row.pass)


func _record(condition: bool, label: String) -> void:
	_checks.append({"name": label, "pass": condition})
	if not condition:
		push_error(label)
