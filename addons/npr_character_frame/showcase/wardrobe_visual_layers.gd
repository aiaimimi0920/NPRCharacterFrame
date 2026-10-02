extends Node3D
## Showcase orchestration for face, fitted hosiery and continuous surface rain.

signal eye_controls_changed

const FITTED_HOSIERY := preload(
	"res://addons/npr_character_frame/runtime/hosiery/npr_fitted_hosiery.gd"
)
const FACE_RIG := preload("res://addons/npr_character_frame/runtime/face/npr_face_rig.gd")
## Saved UI density range; actual rainfall uses candidate arrivals per second.
const MAX_DROPLETS := 12
const SURFACE_RAIN = preload("res://addons/npr_character_frame/runtime/rain/npr_surface_rain.gd")

var actor: NPRCharacter
var performance: Node
var tulle_layer: Node3D
var eye_layer: Node3D:
	get:
		return _face_rig.eye_layer
var surface_rain: RefCounted
var _hosiery: Node3D
var _fitted_hosiery: MeshInstance3D:
	get:
		return _hosiery.mesh_instance if is_instance_valid(_hosiery) else null
var _phase := 0.0
var _enabled := false
var _count := 0
var _speed := 0.35
var _seed := 17
var _paused := false
var _preview_paused := false
var _face_rig := FACE_RIG.new()
var _eye_controls: RefCounted:
	get:
		return _face_rig.controls
var _original_lids: Node3D:
	get:
		return _face_rig.original_lids
var _symbol_mouth: MeshInstance3D:
	get:
		return _face_rig.symbol_mouth
var _symbol_eyes: MeshInstance3D:
	get:
		return _face_rig.symbol_eyes
var _face_presentation: RefCounted:
	get:
		return _face_rig.presentation


func _init() -> void:
	_face_rig.name = "FaceRig"
	add_child(_face_rig)


func setup(character: NPRCharacter, performance_driver: Node) -> void:
	actor = character
	performance = performance_driver
	surface_rain = SURFACE_RAIN.new()
	surface_rain.setup(actor)
	_build_tulle_geometry()
	_face_rig.eye_controls_changed.connect(eye_controls_changed.emit)
	_face_rig.setup(actor, performance)
	_apply_visibility()
	RenderingServer.frame_pre_draw.connect(_sync_fitted_hosiery)


## 借用当前角色的诊断符号曲面，不转移节点所有权，不改变可见性。
func diagnostic_symbol_target(channel: StringName) -> MeshInstance3D:
	if not is_instance_valid(_face_rig) or _face_rig.is_queued_for_deletion():
		return null
	var target: MeshInstance3D
	match channel:
		&"eyes":
			target = _face_rig.symbol_eyes
		&"mouth":
			target = _face_rig.symbol_mouth
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return null
	return target


func _process(delta: float) -> void:
	if not _enabled or _paused or _preview_paused:
		return
	_phase += delta * _speed
	surface_rain.advance(delta, _speed * 2.85)


func apply_state(state: RefCounted) -> void:
	_eye_controls.restore(
		Vector3(state.eye_left[0], state.eye_left[1], state.eye_left[2]),
		Vector3(state.eye_right[0], state.eye_right[1], state.eye_right[2])
	)
	surface_rain.configure(
		bool(state.droplets_enabled),
		float(state.droplet_count) * 5.0,
		int(state.droplet_seed),
		Vector3(state.wetness_regions[0], state.wetness_regions[1], state.wetness_regions[3]),
		float(state.hosiery_height),
		1.0 - float(state.stocking_transparency)
	)
	_enabled = bool(state.droplets_enabled)
	_count = clampi(int(state.droplet_count), 0, MAX_DROPLETS)
	_speed = clampf(float(state.droplet_speed), 0.0, 1.0)
	_seed = maxi(int(state.droplet_seed), 0)
	if not _enabled:
		_phase = 0.0
		_preview_paused = false
	tulle_layer.visible = (
		bool(state.tulle_geometry_enabled) if is_instance_valid(tulle_layer) else false
	)
	_face_presentation.request_eye_geometry(bool(state.eye_geometry_enabled))
	var face: ShaderMaterial = actor.materials[1]
	face.set_shader_parameter("u_npr_eye_symbol_size", state.eye_symbol_size)
	face.set_shader_parameter("u_npr_eye_symbol_stroke", state.eye_symbol_stroke)
	for key in ["mouth_symbol_size", "mouth_symbol_stroke"]:
		face.set_shader_parameter("u_npr_" + key, state.get(key))
	performance.base_eye_symbol = state.eye_symbol
	performance.base_mouth_symbol = state.mouth_symbol
	# Apply even while the animation preview is paused.
	performance.evaluate_expression()
	_sync_eye_pose()
	_hosiery.set_surface_state(
		1.0 - float(state.stocking_transparency),
		float(state.hosiery_height),
		float(state.hosiery_stitch)
	)
	set_eye_wetness(float(state.eye_wetness))
	_apply_visibility()


func apply_expression_frame(frame: Dictionary) -> void:
	_face_presentation.apply_expression_frame(frame)


func invalidate_expression_frame() -> void:
	_face_presentation.invalidate_expression_frame()


func set_paused(paused: bool) -> void:
	_paused = paused


func set_droplet_preview_paused(value: bool) -> void:
	_preview_paused = value and _enabled


func restart_droplet_preview() -> void:
	# Only reset the water timeline. Pose, camera and saved settings stay intact.
	_phase = 0.0
	surface_rain.clear()


func reset() -> void:
	_phase = 0.0
	if surface_rain != null:
		surface_rain.clear()
		actor.materials[0].set_shader_parameter("u_npr_rain_enabled", false)
	_enabled = false
	_count = 0
	_speed = 0.35
	_seed = 17
	_paused = false
	_preview_paused = false
	_eye_controls.reset()
	if is_instance_valid(tulle_layer):
		tulle_layer.visible = false
	if is_instance_valid(eye_layer):
		eye_layer.visible = false
	_apply_visibility()


func contract() -> Dictionary:
	return {
		"max_count": MAX_DROPLETS,
		"gravity": Vector3(0.0, -1.0, 0.0),
		"paused": _paused,
		"preview_paused": _preview_paused,
		"phase": _phase,
		"enabled": _enabled,
		"count": _count,
		"speed": _speed,
		"seed": _seed,
		"eye_lid_closure": _eye_controls.lid_closure,
		"eye_wetness": _eye_controls.wetness,
		"transparent_depth": false,
		"material_response": true,
	}


func _build_tulle_geometry() -> void:
	_hosiery = FITTED_HOSIERY.new()
	tulle_layer = _hosiery
	tulle_layer.name = "AuthoredHosiery"
	add_child(tulle_layer)
	_hosiery.setup(actor.meshes[0], actor.definition.hosiery_profile)


func _sync_fitted_hosiery() -> void:
	if is_instance_valid(_hosiery):
		_hosiery.sync_body()


func set_eye_focus(direction: Vector2, side := -1) -> void:
	_eye_controls.set_eye_focus(direction, side)


func _sync_eye_pose() -> void:
	_face_presentation.sync_pose()


func set_pupil_scale(value: float, side := -1) -> void:
	_eye_controls.set_pupil_scale(value, side)


func set_eye_lid_closure(value: float) -> void:
	_eye_controls.set_eye_lid_closure(value)


func set_eye_wetness(value: float) -> void:
	_eye_controls.set_eye_wetness(value)


func eye_pupil_contract(side := -1) -> Dictionary:
	return _eye_controls.eye_pupil_contract(side)


func _apply_visibility() -> void:
	if is_instance_valid(tulle_layer):
		# The UI sets the exact geometry state after setup; this guard only hides
		# the layer while the actor is not ready.
		tulle_layer.visible = tulle_layer.visible and is_instance_valid(actor)
	if is_instance_valid(eye_layer):
		eye_layer.visible = eye_layer.visible and is_instance_valid(actor)
