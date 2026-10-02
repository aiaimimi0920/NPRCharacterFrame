extends Node
## Release-safe checks: only the explicit engine sentinel belongs in assert().

const CONTACT = preload("res://addons/npr_character_frame/runtime/animation/npr_surface_contact.gd")
var _checks: Array[Dictionary] = []
var _assert_evaluated := false
var _mode: String
var _output: String


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[0]
	_output = args[1]
	# Deliberate negative control, not a required test or production operation.
	assert(_mark_assert_evaluated())
	_run.call_deferred()


func _mark_assert_evaluated() -> bool:
	_assert_evaluated = true
	return true


func _run() -> void:
	_record(not OS.has_feature("editor"), "Actual exported template executes the test scene")
	_record(OS.is_debug_build() == (_mode == "debug"), "Template matches the requested debug mode")
	_record(
		_assert_evaluated == (_mode == "debug"), "Engine removes assert expressions only in release"
	)
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
		var label := str(origin) + " "
		_record(_faces_match(contact, faces, origin), label + "Authored BVH is created")
		var from := base + Vector3(0.001, 0.001, 0.001)
		_record(not _query_clear(contact, from, -0.002), label + "Authored head blocks crossing")
		_record(_query_clear(contact, from, 0.002), label + "Authored head allows a miss")
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
		_record(_faces_match(contact, faces, origin), label + "Actual Body BVH is rebuilt")
		_record(_query_clear(contact, from, -0.002), label + "Body rebuild replaces old triangles")
		_record(
			not _query_clear(contact, from + offset, -0.002), label + "Rebuilt head blocks crossing"
		)
		_record(_query_clear(contact, from + offset, 0.002), label + "Rebuilt head allows a miss")
		var head_pose := Transform3D(Basis(Vector3.UP, 0.35), Vector3(0.4, 0.2, -0.3))
		_record(
			not _query_clear(contact, from + offset, -0.002, head_pose),
			label + "Posed head query uses the rebuilt BVH"
		)
	var failures := _checks.filter(func(row: Dictionary): return not row.pass).size()
	var report := {
		"checks": _checks,
		"failures": failures,
		"mode": _mode,
		"debug_build": OS.is_debug_build(),
		"assert_evaluated": _assert_evaluated,
		"engine": Engine.get_version_info()
	}
	FileAccess.open(_output.path_join("surface_contact.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SURFACE_CONTACT_CHECKS=", _checks.size(), " FAILURES=", failures)
	print("REGRESSION_OK" if failures == 0 else "REGRESSION_FAILED")
	get_tree().quit(0 if failures == 0 else 1)


func _faces_match(contact: RefCounted, faces: PackedVector3Array, origin: Vector3) -> bool:
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


func _record(condition: bool, label: String) -> void:
	_checks.append({"name": label, "pass": condition})
	if not condition:
		push_error(label)
