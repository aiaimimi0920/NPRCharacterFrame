extends Node
## Blender-authored skin palettes and shapes, with runtime blink/secondary motion.

signal visual_quality_changed(value: int)
signal pose_applied
signal expression_evaluated(frame: Dictionary)

const PERFORMANCE_DATA = preload("res://addons/npr_character_frame/runtime/npr_performance_data.gd")
const SOFT_DATA = preload("res://addons/npr_character_frame/runtime/npr_soft_tissue_data.gd")
const ACTIONS := ["idle", "greeting", "look_around", "presentation"]
const LABELS := ["呼吸待机", "招呼", "左右观察", "展示姿态"]
const SOFT_TISSUE_SHAPE := "soft_tissue_pressure"
const DYNAMICS := preload("res://addons/npr_character_frame/runtime/animation/npr_hair_dynamics.gd")
const CANONICAL_BONES := 16
const EYE_MOTION := preload("res://addons/npr_character_frame/runtime/face/npr_eye_motion.gd")
const EXPRESSION_CONTROL := preload(
	"res://addons/npr_character_frame/runtime/npr_expression_controller.gd"
)
const EXPRESSIONS := [
	"neutral", "blush", "sparkle", "surprised", "tense", "happy", "sad", "angry", "sleepy"
]
var expressions := EXPRESSION_CONTROL.new()
var performance_data_path := ""
var soft_tissue_data_path := ""
var base_eye_symbol := 0
var base_mouth_symbol := 0
var eye_emphasis_override := -1.0
var action := "idle"
var expression := 0
var automatic := true
var blink_enabled := true
var symbolic_eyes := false
var symbolic_mouth := false
var secondary_enabled := true
var blink_weight := 0.0
var wind_strength := 0.0
var soft_tissue_pressure := 0.0
## Technical LOD policy, deliberately excluded from saved wardrobe choices.
var visual_quality := 2
var hair_collision_enabled := false
var hair_dynamic_enabled := false
var visemes: Dictionary = {}
var clock := 0.0
var rigs: Array[Skeleton3D] = []
var dynamics: RefCounted
var _expression_material_values := Vector4(INF, INF, INF, INF)
var _actor: Node3D
var _face_profile: NPRFaceMotionProfile
var _data: Dictionary
var _sources: Array[MeshInstance3D] = []
var _bound: Array[Mesh] = []
var _bind_inputs: Array[Mesh] = []
var _spaces: Array[Transform3D] = []
var _space_inverses: Array[Transform3D] = []
var _eye_focus := Vector2.ZERO
var _pupil_scale := 1.0
var _eye_focus_right := Vector2.ZERO
var _pupil_scale_right := 1.0
var _pose_palette: Array[Transform3D] = []
var _pose_valid := false
var _face_values := PackedFloat64Array()
var _clips: Dictionary = {}
var _shape_names: Array = []
var _blink_clock := -3.0
var _random := RandomNumberGenerator.new()
var _spring := 0.0
var _velocity := 0.0
var _wind_spring := 0.0
var _wind_velocity := 0.0
var _axis_bindings: Array[Dictionary] = []
var _soft_tissue_shape_index := -1
var _soft_data: Dictionary = {}
var _paused := false
var _hair_dynamic_asset_loaded := false
var _authored_skins: Array[Dictionary] = []
var _last_attachments := PackedInt32Array()


func setup(actor: Node3D) -> void:
	_actor = actor
	_face_profile = actor.definition.face_motion_profile
	assert(_face_profile != null, "Face motion requires an authored NPRFaceMotionProfile")
	expressions.profile = _face_profile.expression_profile
	performance_data_path = actor.definition.performance_data_path
	_data = actor.definition.load_performance_data()
	var vertex_counts := PackedInt32Array()
	for role in 3:
		vertex_counts.append(actor.meshes[role].mesh.surface_get_array_len(0))
	var data_errors := PERFORMANCE_DATA.validate(_data, vertex_counts)
	if not data_errors.is_empty():
		push_error("Invalid performance data: " + "; ".join(data_errors))
		return
	soft_tissue_data_path = actor.definition.soft_tissue_data_path
	_soft_data = actor.definition.load_soft_tissue_data()
	var soft_errors := SOFT_DATA.validate(_soft_data, vertex_counts[0])
	if not soft_errors.is_empty():
		push_error("Invalid soft tissue data: " + "; ".join(soft_errors))
		return
	var hair_data: Dictionary = actor.definition.load_hair_dynamics_data()
	var hair_errors := NPRCharacterDefinition.HAIR_DYNAMICS_DATA.validate(hair_data, vertex_counts)
	if not hair_errors.is_empty():
		push_error("Invalid hair dynamics data: " + "; ".join(hair_errors))
		return
	dynamics = DYNAMICS.new(hair_data, actor.definition.hair_dynamics_data_path)
	_data.bones.append_array(dynamics.data.bones)
	_hair_dynamic_asset_loaded = true
	_shape_names = _data.shapes.keys()
	_pose_palette.resize(_data.bones.size())
	_random.randomize()
	for name: String in ACTIONS:
		var frames: Array = []
		for frame: Array in _data.actions[name].frames:
			var palette: Array[Transform3D] = []
			for values: Array in frame:
				palette.append(_transform(values))
			frames.append(palette)
		_clips[name] = frames
	for role in 3:
		var source: MeshInstance3D = actor.meshes[role]
		assert(
			source.mesh.surface_get_array_len(0) == _data.weights[role].size(),
			"Rebuild Blender rig for changed source topology"
		)
		_sources.append(source)
		_spaces.append(actor.global_transform.affine_inverse() * source.global_transform)
		_space_inverses.append(_spaces[role].affine_inverse())
		_bound.append(null)
		_bind_inputs.append(null)
		var skeleton := Skeleton3D.new()
		skeleton.name = "WardrobeSkinPalette"
		for name: String in _data.bones:
			skeleton.add_bone(name)
			skeleton.set_bone_rest(skeleton.get_bone_count() - 1, Transform3D.IDENTITY)
		source.add_child(skeleton)
		source.skeleton = skeleton.get_path()
		rigs.append(skeleton)
		bind_mesh(role)
		if role > 0:
			var material: ShaderMaterial = actor.materials[role]
			while material != null:
				var axes := {}
				for key in [
					"u_npr_face_forward",
					"u_npr_face_right",
					"u_npr_hair_sheen_axis",
					"u_npr_hair_side_axis"
				]:
					var value: Variant = material.get_shader_parameter(key)
					if value is Vector3:
						axes[key] = value
				_axis_bindings.append(
					{"role": role, "material": material, "axes": axes, "rotation": null}
				)
				material = material.next_pass as ShaderMaterial


func bind_authored_skin(mesh: MeshInstance3D) -> bool:
	## Imported vertices are in their authored bind space. Rebind joint indices
	## to an identity-rest palette, exactly like the three canonical surfaces.
	var imported := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if imported == null or mesh.skin == null:
		return false
	var skeleton := Skeleton3D.new()
	skeleton.name = "WardrobeAuthoredPalette"
	var skin := Skin.new()
	var mapping: Array[int] = []
	for slot in mesh.skin.get_bind_count():
		var bone_name := str(mesh.skin.get_bind_name(slot))
		if bone_name.is_empty():
			bone_name = imported.get_bone_name(mesh.skin.get_bind_bone(slot))
		var bone: int = _data.bones.find(bone_name.replace("_", "."))
		if bone < 0:
			skeleton.free()
			push_error("Unknown authored skin joint: " + bone_name)
			return false
		skeleton.add_bone(bone_name)
		skeleton.set_bone_rest(slot, Transform3D.IDENTITY)
		skin.add_bind(slot, Transform3D.IDENTITY)
		mapping.append(bone)
	mesh.add_child(skeleton)
	mesh.skin = skin
	mesh.skeleton = mesh.get_path_to(skeleton)
	var space := _actor.global_transform.affine_inverse() * mesh.global_transform
	_authored_skins.append(
		{
			"rig": skeleton,
			"mapping": mapping,
			"space": space,
			"inverse": space.affine_inverse(),
			"mesh": mesh,
			"corrective": mesh.find_blend_shape_by_name(SOFT_TISSUE_SHAPE)
		}
	)
	return true


## Rest transform from a source surface's local space into actor space.
func source_space(role: int) -> Transform3D:
	assert(role >= 0 and role < _spaces.size(), "Source space requires an initialized surface")
	return _spaces[role]


func bone_deformation(name: String) -> Transform3D:
	var index: int = _data.bones.find(name)
	return _pose_palette[index] if _pose_valid and index >= 0 else Transform3D.IDENTITY


func _apply_authored_skins() -> void:
	for binding in _authored_skins:
		var skeleton: Skeleton3D = binding.rig
		if not is_instance_valid(skeleton):
			continue
		for joint in binding.mapping.size():
			var local: Transform3D = (
				binding.inverse * _pose_palette[binding.mapping[joint]] * binding.space
			)
			skeleton.set_bone_pose_position(joint, local.origin)
			skeleton.set_bone_pose_rotation(joint, local.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(joint, local.basis.get_scale())


func set_hair_collision_enabled(value: bool) -> void:
	hair_collision_enabled = value
	dynamics.collision_enabled = value


func set_hair_dynamic_enabled(value: bool) -> void:
	if hair_dynamic_enabled == value:
		return
	hair_dynamic_enabled = value and _hair_dynamic_asset_loaded
	dynamics.enabled = hair_dynamic_enabled
	dynamics.reset()
	_refresh_dynamic_weights()


func _refresh_dynamic_weights() -> void:
	for role in [0, 2]:
		bind_mesh(role, _last_attachments if role == 0 else PackedInt32Array(), true)


func hair_collision_contract() -> Dictionary:
	return {
		"enabled": hair_collision_enabled,
		"spans": dynamics.data.colliders.size(),
		"last_penetration": dynamics.maximum_correction,
		"dynamic_asset_loaded": _hair_dynamic_asset_loaded,
		"dynamic_enabled": hair_dynamic_enabled,
		"dynamic_chains": dynamics.chains.size(),
		"contacts": dynamics.contacts,
		"geometry": dynamics.snapshot(_pose_palette),
	}


func bind_mesh(role: int, attachments := PackedInt32Array(), force := false) -> void:
	if role == 0:
		_last_attachments = attachments
	var source := _sources[role]
	if source.mesh == _bound[role] and not force:
		return
	# Rebinding weights must start from the original input. Repeatedly decoding
	# and repacking the generated mesh drifts its compressed normals/tangents.
	if source.mesh != _bound[role]:
		_bind_inputs[role] = source.mesh
	var input := _bind_inputs[role]
	var arrays := input.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for index in vertices.size():
		var influences: Array
		if index < _data.weights[role].size():
			influences = _data.weights[role][index]
			if (
				hair_dynamic_enabled
				and visual_quality > 0
				and dynamics.weights.has(role)
				and dynamics.weights[role].has(index)
			):
				influences = dynamics.weights[role][index]
		else:
			var extra: int = index - _data.weights[role].size()
			assert(extra < attachments.size(), "Equipment requires an authored attachment")
			influences = [[attachments[extra], 1.0]]
		for slot in 4:
			bones.append(int(influences[slot][0]) if slot < influences.size() else 0)
			weights.append(float(influences[slot][1]) if slot < influences.size() else 0.0)
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	# Independent eyes and phonemes must add deltas, not normalized full meshes.
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	var shapes: Array[Array] = []
	if role == 0:
		mesh.add_blend_shape(SOFT_TISSUE_SHAPE)
		var soft_shape: Array = []
		soft_shape.resize(Mesh.ARRAY_MAX)
		var positions := PackedVector3Array()
		positions.resize(vertices.size())
		# The Blender Shape Key owns the domain and the collision-constrained
		# position deltas. Appended equipment vertices stay exactly zero.
		for row: Array in _soft_data.deltas:
			positions[int(row[0])] = _space_inverses[role].basis * Vector3(row[1], row[2], row[3])
		soft_shape[Mesh.ARRAY_VERTEX] = positions
		if arrays[Mesh.ARRAY_NORMAL] != null:
			soft_shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		if arrays[Mesh.ARRAY_TANGENT] != null:
			soft_shape[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
		shapes.append(soft_shape)
		_soft_tissue_shape_index = 0
	if role == 1:
		for name: String in _shape_names:
			mesh.add_blend_shape(name)
			var face_shape: Array = []
			face_shape.resize(Mesh.ARRAY_MAX)
			var positions := PackedVector3Array()
			positions.resize(vertices.size())
			for row: Array in _data.shapes[name]:
				positions[int(row[0])] += (
					_space_inverses[role].basis * Vector3(row[1], row[2], row[3])
				)
			face_shape[Mesh.ARRAY_VERTEX] = positions
			# Octahedral normal/tangent storage cannot represent a zero delta.
			# Relative blending normalizes the sum: adding the authored direction
			# preserves it for our nonnegative weights, including combined phonemes.
			face_shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
			face_shape[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
			shapes.append(face_shape)
	if role == 1:
		EYE_MOTION.append_shapes(mesh, arrays, shapes, _spaces[role], _face_profile)
		EYE_MOTION.append_mouth_holds(mesh, arrays, shapes, _spaces[role], _face_profile)
	var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT if role <= 1 else 0
	if role == 1:
		flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes, {}, flags)
	mesh.surface_set_material(0, input.surface_get_material(0))
	source.mesh = mesh
	_bound[role] = mesh
	# Contact witnesses must use the same packed/decompressed positions as the
	# final skin, not the pre-repack input (which can differ by tens of microns).
	if hair_dynamic_enabled and visual_quality > 0:
		dynamics.bind_surface(role, mesh.surface_get_arrays(0), _spaces[role])
	if role == 1:
		# Replacing the mesh resets instance weights, even when inputs are unchanged.
		_face_values.resize(_shape_names.size())
		_face_values.fill(NAN)
		EYE_MOTION.apply(source, _eye_focus, _pupil_scale, _face_profile)
		EYE_MOTION.apply(source, _eye_focus_right, _pupil_scale_right, _face_profile, 1)
	elif role == 0:
		source.set_blend_shape_value(_soft_tissue_shape_index, 0.0)


func set_eye_controls(focus: Vector2, scale: float) -> void:
	set_independent_eye_controls(Vector3(focus.x, focus.y, scale), Vector3(focus.x, focus.y, scale))


func set_independent_eye_controls(left: Vector3, right: Vector3) -> void:
	_eye_focus = Vector2(left.x, left.y).limit_length(1.0)
	_pupil_scale = clampf(left.z, 0.65, 1.35)
	_eye_focus_right = Vector2(right.x, right.y).limit_length(1.0)
	_pupil_scale_right = clampf(right.z, 0.65, 1.35)
	EYE_MOTION.apply(_sources[1], _eye_focus, _pupil_scale, _face_profile)
	EYE_MOTION.apply(_sources[1], _eye_focus_right, _pupil_scale_right, _face_profile, 1)


func _process(delta: float) -> void:
	# An explicit pause owns the pose even when visibility changes.
	if _sources.is_empty() or _paused:
		return
	if not _actor.is_visible_in_tree():
		_clear_dynamic_offsets()
		apply_pose(clock)
		return
	if automatic:
		clock += minf(delta, 0.1)
		_blink_clock += delta
		if _blink_clock > 0.19:
			_blink_clock = -_random.randf_range(2.4, 5.2)
		blink_weight = sin(PI * clampf(_blink_clock / 0.19, 0.0, 1.0)) if blink_enabled else 0.0
	apply_pose(clock, delta)


func apply_pose(time: float, delta := 0.0) -> void:
	if _paused:
		return
	var active := _actor.is_visible_in_tree()
	var frames: Array = _clips[action]
	var phase := fposmod(time * 30.0, frames.size() - 1)
	var frame := int(phase)
	var blend := phase - frame
	var target := sin(time * TAU / 4.0) * 0.003 if secondary_enabled and active else 0.0
	var wind_target := (
		(sin(time * 2.7) * 0.004 + sin(time * 5.3) * 0.0015) * clampf(wind_strength, 0.0, 1.0)
		if active and visual_quality > 0
		else 0.0
	)
	# Fixed small substeps, critical damping and a hard displacement bound avoid
	# frame-rate-dependent explosions after stalls or action switches.
	var remaining := minf(delta, 0.1)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		_velocity += ((target - _spring) * 160.0 - _velocity * 18.0) * step
		_spring = clampf(_spring + _velocity * step, -0.008, 0.008)
		_wind_velocity += ((wind_target - _wind_spring) * 96.0 - _wind_velocity * 16.0) * step
		_wind_spring = clampf(_wind_spring + _wind_velocity * step, -0.007, 0.007)
		remaining -= step
	if not secondary_enabled or not active:
		_spring = 0.0
		_velocity = 0.0
	if wind_strength <= 0.0 or not active or visual_quality == 0:
		_wind_spring = 0.0
		_wind_velocity = 0.0
	for bone in CANONICAL_BONES:
		var source_bone: int = 3 if bone >= 14 and (not secondary_enabled or not active) else bone
		var deformation: Transform3D = frames[frame][source_bone].interpolate_with(
			frames[frame + 1][source_bone], blend
		)
		if bone >= 14:
			var side := -1.0 if bone == 14 else 1.0
			deformation.origin += Vector3(_wind_spring * side, _spring, _spring * 0.3)
			deformation.origin.z = maxf(deformation.origin.z, -0.006)
		# Compare after spring integration; a frozen clip can still have secondary motion.
		if _pose_valid and _pose_palette[bone] == deformation:
			continue
		_pose_palette[bone] = deformation
		for role in rigs.size():
			var local := _space_inverses[role] * deformation * _spaces[role]
			rigs[role].set_bone_pose_position(bone, local.origin)
			rigs[role].set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
			rigs[role].set_bone_pose_scale(bone, local.basis.get_scale())
	dynamics.update(_pose_palette, delta, time, wind_strength, active and visual_quality > 0)
	for bone in range(CANONICAL_BONES, _data.bones.size()):
		for role in rigs.size():
			var local := _space_inverses[role] * _pose_palette[bone] * _spaces[role]
			rigs[role].set_bone_pose_position(bone, local.origin)
			rigs[role].set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
			rigs[role].set_bone_pose_scale(bone, local.basis.get_scale())
	_pose_valid = true
	for binding in _axis_bindings:
		var rotation := rigs[binding.role].get_bone_pose(5).basis
		if binding.rotation == rotation:
			continue
		binding.rotation = rotation
		for key: String in binding.axes:
			binding.material.set_shader_parameter(key, (rotation * binding.axes[key]).normalized())
	_apply_face(delta)
	_apply_soft_tissue_shape()
	_apply_authored_skins()
	pose_applied.emit()


func set_paused(value: bool) -> void:
	_paused = value


## 仅查询显式动作暂停，不合并可见性、automatic 或节点处理开关。
func is_paused() -> bool:
	return _paused


func set_visual_quality(value: int) -> void:
	var next_quality := clampi(value, 0, 2)
	if visual_quality == next_quality:
		return
	visual_quality = next_quality
	_refresh_dynamic_weights()
	if visual_quality == 0:
		_wind_spring = 0.0
		_wind_velocity = 0.0
	_apply_soft_tissue_shape()
	visual_quality_changed.emit(visual_quality)


func reset_simulation() -> void:
	expressions.clear()
	clock = 0.0
	_blink_clock = -3.0
	blink_weight = 0.0
	_paused = false
	set_hair_dynamic_enabled(false)
	_clear_dynamic_offsets()


func _clear_dynamic_offsets() -> void:
	if dynamics != null:
		dynamics.reset()
	_spring = 0.0
	_velocity = 0.0
	_wind_spring = 0.0
	_wind_velocity = 0.0
	_pose_valid = false


func set_soft_tissue_pressure(value: float) -> void:
	soft_tissue_pressure = clampf(value, 0.0, 1.0)
	_apply_soft_tissue_shape()
	pose_applied.emit()


func _apply_soft_tissue_shape() -> void:
	if _sources.is_empty() or _soft_tissue_shape_index < 0:
		return
	var value := (
		clampf(soft_tissue_pressure, 0.0, 1.0)
		if visual_quality > 0 and _actor.is_visible_in_tree()
		else 0.0
	)
	_sources[0].set_blend_shape_value(_soft_tissue_shape_index, value)
	for binding in _authored_skins:
		if binding.corrective >= 0 and is_instance_valid(binding.mesh):
			binding.mesh.set_blend_shape_value(binding.corrective, value)


## setup 完成后同步求值最新面部输入；即使动作暂停也生效。
## delta 仅推进表情请求和过渡，不推进动作、眨眼时钟或头发模拟。
func evaluate_expression(delta := 0.0) -> void:
	_apply_face(delta)


func _apply_face(delta := 0.0) -> void:
	var base: Dictionary = _face_profile.expression_profile.pose(EXPRESSIONS[expression])
	base.eye_symbol = base_eye_symbol
	base.mouth_symbol = base_mouth_symbol
	if eye_emphasis_override >= 0.0:
		base.eye_emphasis = eye_emphasis_override
	expressions.set_base(base)
	expressions.blink = {"blink.L": blink_weight, "blink.R": blink_weight}
	expressions.speech = visemes
	expressions.speech_active = not visemes.is_empty()
	var frame: Dictionary = expressions.advance(delta)
	symbolic_eyes = frame.eye_symbol != 0
	symbolic_mouth = frame.mouth_symbol != 0
	var weights: Dictionary = frame.eyes.duplicate()
	weights.merge(frame.mouth, true)
	weights.merge(frame.brows, true)
	for index in _shape_names.size():
		var name: String = _shape_names[index]
		var value: float = weights.get(name, 0.0)
		if name in ["blink_mid.L", "blink_mid.R"]:
			var closure: float = weights.get(name.replace("blink_mid", "blink"), 0.0)
			value = 4.0 * closure * (1.0 - closure)
		value = clampf(value, 0.0, 1.0)
		if name in ["happy", "sad", "angry"]:
			var hold := _sources[1].find_blend_shape_by_name("symbol_hold_" + name)
			_sources[1].set_blend_shape_value(hold, value if symbolic_mouth else 0.0)
		if _face_values[index] != value:
			_sources[1].set_blend_shape_value(index, value)
			_face_values[index] = value
	var material_values := Vector4(frame.color.x, frame.color.y, frame.color.z, frame.eye_emphasis)
	if _expression_material_values != material_values:
		_actor.set_face_expression(frame.color)
		_actor.set_face_eye_expression(frame.eye_emphasis)
		_expression_material_values = material_values
	expression_evaluated.emit(frame)


func _transform(v: Array) -> Transform3D:
	return Transform3D(
		Basis(Vector3(v[0], v[4], v[8]), Vector3(v[1], v[5], v[9]), Vector3(v[2], v[6], v[10])),
		Vector3(v[3], v[7], v[11])
	)
