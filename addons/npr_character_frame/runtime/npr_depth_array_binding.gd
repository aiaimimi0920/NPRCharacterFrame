extends Node
## Primary-view transport owner. Secondary views keep their direct texture path.
## Mount after character_depth's synchronization so requests describe this frame.

const ARRAY = preload("res://addons/npr_character_frame/runtime/npr_depth_array.gd")
const UPDATE = preload("res://addons/npr_character_frame/runtime/npr_depth_array_update.gd")
var depth: Node
## Changes the sampling contract for both array and its direct fallback.
var integer_sampling := false
var effect: CompositorEffect
var _array: RefCounted
var _camera: Camera3D
var _previous: Compositor
var _installed: Compositor
var _published: Array = []
var _retry_full := true


func _enter_tree() -> void:
	_array = ARRAY.new()
	effect = UPDATE.new()
	effect.target = _array
	_published.clear()
	_retry_full = true
	RenderingServer.frame_pre_draw.connect(_synchronize)


func _synchronize() -> void:
	var camera: Camera3D = depth.camera
	if not depth.active or not is_instance_valid(camera) or not _has_array_consumers():
		_publish(false, [])
		_unmount()
		_retry_full = true
		return
	if camera != _camera or not _owns_effect(camera.compositor):
		_unmount()
		_mount(camera)
		_retry_full = true
	var inputs: Array[RID] = []
	var sizes: Array[Vector2i] = []
	var dirty := PackedInt32Array()
	var state: Dictionary = effect.result()
	# A failed update must recover even when camera/geometry stay stationary.
	# Otherwise no producer dirtiness would ever submit the recovery request.
	_retry_full = _retry_full or state.error != OK
	for index in range(depth.viewports.size()):
		var viewport: SubViewport = depth.viewports[index]
		inputs.append(viewport.get_texture().get_rid())
		sizes.append(viewport.size)
		if depth.requested_this_frame[index] or _retry_full:
			dirty.append(index)
	var rebuild: bool = state.get("sizes", []) != sizes
	var usable: bool = not rebuild and state.error == OK
	_publish(usable, sizes)
	if effect.queue_update(inputs, dirty, rebuild) < 0:
		# The viewport may not have rendered. Retain all dirtiness until a new
		# complete request can be accepted; do not consume stale metadata meanwhile.
		_retry_full = true
		_publish(false, [])
	else:
		_retry_full = false


func _has_array_consumers() -> bool:
	var flags: Vector2i = depth.get("_published_enabled")
	if integer_sampling or flags == Vector2i.ZERO:
		return flags != Vector2i.ZERO
	var body: Vector2i = depth.viewports[0].size
	var hair: Vector2i = depth.viewports[1].size
	var maximum := Vector2i(maxi(body.x, hair.x), maxi(body.y, hair.y))
	return (flags.x != 0 and body == maximum) or (flags.y != 0 and hair == maximum)


func _publish(usable: bool, sizes: Array) -> void:
	var state := [usable, sizes, integer_sampling]
	if _published == state:
		return
	_published = state.duplicate(true)
	for index in range(depth.consumers.size()):
		var material: ShaderMaterial = depth.consumers[index]
		material.set_shader_parameter("u_npr_depth_integer_sampling", integer_sampling)
		var compatible := usable
		if usable and not integer_sampling:
			var array_size := Vector2i(maxi(sizes[0].x, sizes[1].x), maxi(sizes[0].y, sizes[1].y))
			# Legacy normalized-nearest is not invariant under padding. Preserve
			# its original texture extent instead of silently changing edge texels.
			compatible = sizes[1 if index == 1 else 0] == array_size
		material.set_shader_parameter("u_npr_depth_array_base", 0 if compatible else -1)
		if not usable:
			# A false branch alone does not remove its descriptor. Replacing the
			# RD allocation during PRE_OPAQUE would invalidate a material uniform
			# set already prepared for this draw, even if sampling is disabled.
			material.set_shader_parameter("u_npr_depth_array", null)
			material.set_shader_parameter("u_npr_depth_array_ready", null)
			material.set_shader_parameter("u_npr_depth_array_guard", false)
		if usable:
			material.set_shader_parameter("u_npr_depth_array", _array.resource)
			material.set_shader_parameter("u_npr_depth_array_ready", effect.readiness)
			material.set_shader_parameter("u_npr_depth_array_guard", true)
			material.set_shader_parameter(
				"u_npr_depth_array_sizes", Vector4(sizes[0].x, sizes[0].y, sizes[1].x, sizes[1].y)
			)


func _mount(camera: Camera3D) -> void:
	_camera = camera
	_previous = camera.compositor
	_installed = Compositor.new()
	var effects: Array[CompositorEffect] = []
	if _previous != null:
		effects.assign(_previous.compositor_effects)
	effects.append(effect)
	_installed.compositor_effects = effects
	camera.compositor = _installed


func _owns_effect(compositor: Compositor) -> bool:
	return compositor != null and compositor.compositor_effects.has(effect)


func _unmount() -> void:
	if is_instance_valid(_camera) and _owns_effect(_camera.compositor):
		var current := _camera.compositor
		var remaining: Array[CompositorEffect] = []
		for item in current.compositor_effects:
			if item != effect:
				remaining.append(item)
		var previous_effects: Array[CompositorEffect] = []
		if _previous != null:
			previous_effects.assign(_previous.compositor_effects)
		if current == _installed and remaining == previous_effects:
			_camera.compositor = _previous
		else:
			# Other characters or external code may have added effects since
			# mount. Remove only ours; never restore a stale captured chain.
			var retained := Compositor.new()
			retained.compositor_effects = remaining
			_camera.compositor = retained
	_camera = null
	_previous = null
	_installed = null


func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(_synchronize)
	_publish(false, [])
	_unmount()
	for material in depth.consumers:
		material.set_shader_parameter("u_npr_depth_integer_sampling", false)
		material.set_shader_parameter("u_npr_depth_array_guard", false)
		material.set_shader_parameter("u_npr_depth_array_ready", null)
		material.set_shader_parameter("u_npr_depth_array", null)
	RenderingServer.call_on_render_thread(effect.release)
	RenderingServer.call_on_render_thread(_array.release)
