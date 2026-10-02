extends RefCounted
## Coordinate face representations after expression evaluation, without UI state.

var _actor: NPRCharacter
var _eye_layer: Node3D
var _original_lids: Node3D
var _symbol_eyes: MeshInstance3D
var _symbol_mouth: MeshInstance3D
var _skin: Array[MeshInstance3D] = []
var _controls: RefCounted
var _head_pose: Callable
var _eye_geometry_requested := false
var _symbol_modes := Vector2i(-1, -1)


## Caller owns nodes and signal connections; head_pose returns actor-space deformation.
func bind(
	actor: NPRCharacter,
	eye_layer: Node3D,
	original_lids: Node3D,
	symbol_eyes: MeshInstance3D,
	symbol_mouth: MeshInstance3D,
	skin: Array[MeshInstance3D],
	controls: RefCounted,
	head_pose: Callable
) -> void:
	_actor = actor
	_eye_layer = eye_layer
	_original_lids = original_lids
	_symbol_eyes = symbol_eyes
	_symbol_mouth = symbol_mouth
	_skin = skin
	_controls = controls
	_head_pose = head_pose


func request_eye_geometry(enabled: bool) -> void:
	_eye_geometry_requested = enabled
	invalidate_expression_frame()


func invalidate_expression_frame() -> void:
	_symbol_modes = Vector2i(-1, -1)


func apply_expression_frame(frame: Dictionary) -> void:
	var modes := Vector2i(frame.eye_symbol, frame.mouth_symbol)
	if modes == _symbol_modes:
		sync_pose()
		return
	_symbol_modes = modes
	var face: ShaderMaterial = _actor.materials[1]
	face.set_shader_parameter("u_npr_eye_symbol", modes.x)
	face.set_shader_parameter("u_npr_mouth_symbol", modes.y)
	_original_lids.visible = modes.x == 0
	_symbol_eyes.visible = modes.x != 0
	_symbol_mouth.visible = modes.y != 0
	_eye_layer.visible = _eye_geometry_requested and modes.x == 0
	face.set_shader_parameter("u_npr_replace_eye", _eye_layer.visible)
	_actor.outlines[1].set_shader_parameter("u_npr_symbolic_eyes", modes.x != 0)
	_actor.outlines[1].set_shader_parameter("u_npr_symbolic_mouth", modes.y != 0)
	face.next_pass.set_shader_parameter("u_npr_symbolic_eyes", modes.x != 0)
	_controls.apply_pupils()
	sync_pose()


func sync_pose() -> void:
	if is_instance_valid(_eye_layer):
		_eye_layer.transform = _head_pose.call()
	if is_instance_valid(_original_lids):
		_original_lids.transform = _head_pose.call()
	# Expressions and automatic blink have already been combined on the source face.
	var face: MeshInstance3D = _actor.meshes[1]
	for canvas in [_symbol_mouth, _symbol_eyes]:
		if not is_instance_valid(canvas) or not canvas.visible:
			continue
		for index in face.mesh.get_blend_shape_count():
			canvas.set_blend_shape_value(index, face.get_blend_shape_value(index))
	var closure := 0.0
	for shape in ["blink.L", "blink.R"]:
		var index := face.find_blend_shape_by_name(shape)
		if index >= 0:
			closure = maxf(closure, face.get_blend_shape_value(index))
	_controls.set_eye_lid_closure(closure)


func sync_light() -> void:
	for mesh in _skin:
		mesh.set_instance_shader_parameter(
			"u_custom_main_light_dir",
			_actor.meshes[1].get_instance_shader_parameter("u_custom_main_light_dir")
		)
