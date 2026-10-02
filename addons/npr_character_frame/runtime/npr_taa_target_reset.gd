extends "res://addons/npr_character_frame/runtime/npr_taa_history_reset.gd"
## One-shot reset for RenderingServer consumers without a Camera3D/Viewport node.
## Caller owns target lifetime: cancel a pending effect before freeing its target.


static func schedule_target(target: RID, previous: Compositor = null) -> Compositor:
	if not target.is_valid():
		return previous
	var effect := new()
	if previous != null:
		for pending in previous.compositor_effects:
			if pending.get_script() == effect.get_script():
				pending._target_mutex.lock()
				var same_target: bool = pending.enabled and pending._render_target == target
				pending._target_mutex.unlock()
				if same_target:
					return previous
	effect.effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	effect._render_target = target
	var effects: Array[CompositorEffect] = []
	if previous != null:
		effects.assign(previous.compositor_effects)
	effects.append(effect)
	var installed := Compositor.new()
	installed.compositor_effects = effects
	effect._installed = weakref(installed)
	return installed


func cancel() -> void:
	_target_mutex.lock()
	_render_target = RID()
	enabled = false
	_target_mutex.unlock()
	_unmount.call_deferred()


func _unmount() -> void:
	var installed := _installed.get_ref() as Compositor
	if installed == null or not installed.compositor_effects.has(self):
		return
	var remaining: Array[CompositorEffect] = []
	for effect in installed.compositor_effects:
		if effect != self:
			remaining.append(effect)
	installed.compositor_effects = remaining
