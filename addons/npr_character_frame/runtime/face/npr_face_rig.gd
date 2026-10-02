extends Node3D
## One-shot face runtime owned by the character's lifetime, without showcase state.

signal eye_controls_changed

const GEOMETRY = preload("res://addons/npr_character_frame/runtime/face/npr_eye_geometry.gd")
const CONTROLS = preload("res://addons/npr_character_frame/runtime/face/npr_eye_controls.gd")
const PRESENTATION = preload(
	"res://addons/npr_character_frame/runtime/face/npr_face_presentation.gd"
)
const EYELIDS = preload("res://addons/npr_character_frame/runtime/face/npr_eyelids.gd")
const SYMBOL_SURFACE = preload(
	"res://addons/npr_character_frame/runtime/face/npr_symbol_surface.gd"
)

var eye_layer: Node3D
var original_lids: Node3D
var symbol_mouth: MeshInstance3D
var symbol_eyes: MeshInstance3D
var controls := CONTROLS.new()
var presentation := PRESENTATION.new()
var _actor: NPRCharacter
var _driver: Node
var _skin: Array[MeshInstance3D] = []


## Add to the actor-space tree first; actor and performance must already be initialized.
func setup(actor: NPRCharacter, driver: Node) -> void:
	assert(is_inside_tree() and _actor == null, "Face rig requires a fresh attached instance")
	if actor.definition.face_atlas_profile == null:
		push_error("Face rig requires an authored face_atlas_profile")
		return
	_actor = actor
	_driver = driver
	controls.controls_changed.connect(eye_controls_changed.emit)
	eye_layer = Node3D.new()
	eye_layer.name = "AuthoredEyeGeometry"
	eye_layer.visible = false
	add_child(eye_layer)
	_skin.append_array(
		GEOMETRY.assemble(
			eye_layer,
			actor.definition.eye_geometry_profile,
			actor.definition.face_motion_profile,
			actor.materials[1],
			actor.meshes[1].layers,
			controls.wetness
		)
	)
	_bind_controls()
	original_lids = EYELIDS.new()
	original_lids.name = "OriginalEyelids"
	add_child(original_lids)
	original_lids.setup(actor.materials[1], actor.definition.face_motion_profile)
	var face_space: Transform3D = driver.source_space(1)
	symbol_mouth = SYMBOL_SURFACE.new()
	symbol_mouth.name = "SymbolMouthCanvas"
	symbol_mouth.setup(
		actor.meshes[1], face_space, actor.materials[1], actor.definition.symbol_surface_profile
	)
	symbol_eyes = SYMBOL_SURFACE.new()
	symbol_eyes.name = "SymbolEyeCanvas"
	symbol_eyes.setup(
		actor.meshes[1],
		face_space,
		actor.materials[1],
		actor.definition.symbol_surface_profile,
		true
	)
	_skin.append(symbol_eyes)
	_skin.append(symbol_mouth)
	for surface: MeshInstance3D in original_lids.surfaces:
		_skin.append(surface)
	_bind_controls()
	presentation.bind(
		actor,
		eye_layer,
		original_lids,
		symbol_eyes,
		symbol_mouth,
		_skin,
		controls,
		driver.bone_deformation.bind("head")
	)
	driver.pose_applied.connect(sync_pose)
	driver.expression_evaluated.connect(apply_expression_frame)
	RenderingServer.frame_pre_draw.connect(_sync_light)


func _exit_tree() -> void:
	if is_instance_valid(_driver):
		if _driver.pose_applied.is_connected(sync_pose):
			_driver.pose_applied.disconnect(sync_pose)
		if _driver.expression_evaluated.is_connected(apply_expression_frame):
			_driver.expression_evaluated.disconnect(apply_expression_frame)
	if RenderingServer.frame_pre_draw.is_connected(_sync_light):
		RenderingServer.frame_pre_draw.disconnect(_sync_light)
	# Symbol surfaces live under the source face for skinning, not under this rig.
	for canvas in [symbol_mouth, symbol_eyes]:
		if is_instance_valid(canvas):
			canvas.queue_free()


func _bind_controls() -> void:
	controls.bind(
		self,
		eye_layer,
		_actor.materials[1],
		_actor.definition.eye_geometry_profile,
		_driver.set_independent_eye_controls,
		original_lids
	)


func set_eye_focus(direction: Vector2, side := -1) -> void:
	controls.set_eye_focus(direction, side)


func set_pupil_scale(value: float, side := -1) -> void:
	controls.set_pupil_scale(value, side)


func set_eye_lid_closure(value: float) -> void:
	controls.set_eye_lid_closure(value)


func set_eye_wetness(value: float) -> void:
	controls.set_eye_wetness(value)


func eye_pupil_contract(side := -1) -> Dictionary:
	return controls.eye_pupil_contract(side)


func apply_expression_frame(frame: Dictionary) -> void:
	presentation.apply_expression_frame(frame)


func sync_pose() -> void:
	presentation.sync_pose()


func _sync_light() -> void:
	presentation.sync_light()
