extends RefCounted
## Eye state and material/mesh application, independent of showcase and saved schemes.

signal controls_changed

const GEOMETRY = preload("res://addons/npr_character_frame/runtime/face/npr_eye_geometry.gd")

var lid_closure := 0.0
var wetness := 0.0
var _left := Vector3(0, 0, 1)
var _right := Vector3(0, 0, 1)
var _layer: Node3D
var _face: ShaderMaterial
var _profile: NPREyeGeometryProfile
var _original_lids: Node3D
var _apply_original: Callable
var _surfaces: Array[MeshInstance3D] = []
var _materials: Dictionary = {}
var _irises: Array[MeshInstance3D] = []
var _iris_positions: Array[Vector3] = []
var _pupils: Array[MeshInstance3D] = []
var _pupil_positions: Array[Vector3] = []
var _lid_count := 0


## Bind at rest. The caller owns nodes and supplies the original-eye motion callback.
func bind(
	search_root: Node,
	layer: Node3D,
	face: ShaderMaterial,
	profile: NPREyeGeometryProfile,
	apply_original: Callable,
	original_lids: Node3D = null
) -> void:
	_layer = layer
	_face = face
	_profile = profile
	_apply_original = apply_original
	_original_lids = original_lids
	_surfaces.clear()
	_materials.clear()
	for node: Node in layer.find_children("*", "MeshInstance3D", true, false):
		var surface := node as MeshInstance3D
		_surfaces.append(surface)
		_materials[surface] = surface.material_override as ShaderMaterial
	_irises.clear()
	_iris_positions.clear()
	for node: Node in layer.find_children("*Iris", "MeshInstance3D", true, false):
		_irises.append(node as MeshInstance3D)
		_iris_positions.append((node as MeshInstance3D).position)
	_pupils.clear()
	_pupil_positions.clear()
	for node: Node in search_root.find_children("*Pupil", "MeshInstance3D", true, false):
		var pupil := node as MeshInstance3D
		if pupil == null or not pupil.name.ends_with("Pupil"):
			continue
		_pupils.append(pupil)
		_pupil_positions.append(pupil.position)
	apply_pupils()
	_lid_count = search_root.find_children("*UpperLid", "MeshInstance3D", true, false).size()
	_lid_count += search_root.find_children("*LowerLid", "MeshInstance3D", true, false).size()
	apply_lids()


## Restore already validated scheme values silently; caller controls application order.
func restore(left: Vector3, right: Vector3) -> void:
	_left = left
	_right = right


func reset() -> void:
	restore(Vector3(0, 0, 1), Vector3(0, 0, 1))
	lid_closure = 0.0
	wetness = 0.0
	apply_pupils()
	apply_lids()


func set_eye_focus(direction: Vector2, side := -1) -> void:
	if not direction.is_finite() or side < -1 or side > 1:
		return
	var focus := direction.limit_length(1.0)
	if side != 1:
		_left.x = focus.x
		_left.y = focus.y
	if side != 0:
		_right.x = focus.x
		_right.y = focus.y
	apply_pupils()
	controls_changed.emit()


func set_pupil_scale(value: float, side := -1) -> void:
	if not is_finite(value) or side < -1 or side > 1:
		return
	if side != 1:
		_left.z = clampf(value, 0.65, 1.35)
	if side != 0:
		_right.z = clampf(value, 0.65, 1.35)
	apply_pupils()
	controls_changed.emit()


func set_eye_lid_closure(value: float) -> void:
	lid_closure = clampf(value, 0.0, 1.0)
	apply_lids()


func set_eye_wetness(value: float) -> void:
	wetness = clampf(value, 0.0, 1.0)
	_face.set_shader_parameter("u_npr_eye_wetness", 0.0 if _layer.visible else wetness)
	for surface in _surfaces:
		if not surface.name.ends_with("TearFilm"):
			continue
		var material := _materials[surface] as ShaderMaterial
		if material != null and material.shader == GEOMETRY.TEAR_SHADER:
			material.set_shader_parameter("wetness", wetness)


func eye_pupil_contract(side := -1) -> Dictionary:
	var value := _left if side == 0 else _right
	if side == -1:
		value = (_left + _right) * 0.5
	return {
		"count": _pupils.size(),
		"lid_count": _lid_count,
		"focus": Vector2(value.x, value.y),
		"scale": value.z,
		"range": [0.65, 1.35],
	}


func apply_pupils() -> void:
	var gain := _profile.gaze_gain
	var original := not _layer.visible
	_apply_original.call(
		_left if original else Vector3(0, 0, 1), _right if original else Vector3(0, 0, 1)
	)
	_face.set_shader_parameter("u_npr_pupil_accent_scale", _left.z if original else 1.0)
	_face.set_shader_parameter("u_npr_pupil_accent_scale_right", _right.z if original else 1.0)
	_face.set_shader_parameter(
		"u_npr_pupil_accent_independent", original and not is_equal_approx(_left.z, _right.z)
	)
	for index in _irises.size():
		var iris := _irises[index]
		var side := 0 if str(iris.name).begins_with("EyeL") else 1
		var focus: Vector2 = eye_pupil_contract(side).focus
		iris.position = _iris_positions[index] + Vector3(focus.x * gain.x, focus.y * gain.y, 0)
		(_materials[iris] as ShaderMaterial).set_shader_parameter("focus_offset", focus * gain)
	for index in _pupils.size():
		var pupil := _pupils[index]
		if not is_instance_valid(pupil):
			continue
		var side := 0 if str(pupil.name).begins_with("EyeL") else 1
		var contract := eye_pupil_contract(side)
		var focus: Vector2 = contract.focus
		pupil.position = _pupil_positions[index] + Vector3(focus.x * gain.x, focus.y * gain.y, 0)
		pupil.scale = Vector3(contract.scale, contract.scale, 1.0)
		var material := _materials[pupil] as ShaderMaterial
		material.set_shader_parameter("focus_offset", focus * gain)
		material.set_shader_parameter("pupil_scale", contract.scale)


func apply_lids() -> void:
	_face.set_shader_parameter("u_npr_eye_lid_closure", lid_closure)
	if is_instance_valid(_original_lids):
		_original_lids.apply(lid_closure)
	for surface in _surfaces:
		if is_instance_valid(surface):
			(_materials[surface] as ShaderMaterial).set_shader_parameter("lid_closure", lid_closure)
