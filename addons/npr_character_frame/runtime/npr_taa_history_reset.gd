extends CompositorEffect
## One-shot consumer-render invalidation; never access scene buffers off-render.

var _camera: WeakRef
var _installed: WeakRef
var _previous: Compositor
var _render_target := RID()
var _target_mutex := Mutex.new()


static func schedule(camera: Camera3D) -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	if not camera.get_viewport().use_taa:
		return
	var effect := new()
	if camera.compositor != null:
		for pending in camera.compositor.compositor_effects:
			if pending.get_script() == effect.get_script() and pending.enabled:
				var target: WeakRef = pending.get("_camera")
				if target != null and target.get_ref() == camera:
					return  # One pending reset covers all owners of this consumer.
	effect.effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	effect._camera = weakref(camera)
	effect._render_target = RenderingServer.viewport_get_render_target(
		camera.get_viewport().get_viewport_rid()
	)
	effect._previous = camera.compositor
	var effects: Array[CompositorEffect] = []
	if camera.compositor != null:
		effects.assign(camera.compositor.compositor_effects)
	effects.append(effect)
	var compositor := Compositor.new()
	compositor.compositor_effects = effects
	effect._installed = weakref(compositor)
	camera.compositor = compositor
	camera.tree_exiting.connect(effect._suspend_target)
	camera.tree_entered.connect(effect._refresh_target)


func _suspend_target() -> void:
	_target_mutex.lock()
	_render_target = RID()
	_target_mutex.unlock()


func _refresh_target() -> void:
	var camera := _camera.get_ref() as Camera3D
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var target := RenderingServer.viewport_get_render_target(
		camera.get_viewport().get_viewport_rid()
	)
	_target_mutex.lock()
	_render_target = target
	_target_mutex.unlock()


func _render_callback(_type: int, data: RenderData) -> void:
	var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
	# An externally shared Compositor can invoke us for another viewport.
	# Do not consume this request or touch that viewport's temporal state.
	_target_mutex.lock()
	if buffers == null or buffers.get_render_target() != _render_target:
		_target_mutex.unlock()
		return
	if buffers != null and buffers.get_use_taa() and buffers.has_texture("taa", "history"):
		buffers.clear_context("taa")
	enabled = false
	_target_mutex.unlock()
	_unmount.call_deferred()


func _unmount() -> void:
	var camera := _camera.get_ref() as Camera3D
	if not is_instance_valid(camera):
		return
	if camera.tree_exiting.is_connected(_suspend_target):
		camera.tree_exiting.disconnect(_suspend_target)
	if camera.tree_entered.is_connected(_refresh_target):
		camera.tree_entered.disconnect(_refresh_target)
	if camera.compositor == null:
		return
	var current := camera.compositor
	if not current.compositor_effects.has(self):
		return
	var remaining: Array[CompositorEffect] = []
	for item in current.compositor_effects:
		if item != self:
			remaining.append(item)
	var previous: Array[CompositorEffect] = []
	if _previous != null:
		previous.assign(_previous.compositor_effects)
	if current == _installed.get_ref() and remaining == previous:
		camera.compositor = _previous
	else:
		var retained := Compositor.new()
		retained.compositor_effects = remaining
		camera.compositor = retained
