extends SubViewport
## Canonical node-side state for an independently rendered native RID consumer.
## Keep this viewport disabled. Mutate its state/camera, not the exposed native RIDs.

signal consumer_exiting

const RESET = preload("res://addons/npr_character_frame/runtime/npr_taa_target_reset.gd")

var state_camera: Camera3D
var consumer_viewport := RID()
var consumer_camera := RID()
var _external_consumer := false
var _state: Array = []
var _consumer_world: World3D
var _resets: Array[CompositorEffect] = []


func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not is_instance_valid(state_camera):
		state_camera = Camera3D.new()
		add_child(state_camera)
	state_camera.current = true
	if not _external_consumer:
		consumer_viewport = RenderingServer.viewport_create()
		consumer_camera = RenderingServer.camera_create()
		RenderingServer.viewport_set_update_mode(
			consumer_viewport, RenderingServer.VIEWPORT_UPDATE_ALWAYS
		)
	if has_consumer():
		RenderingServer.viewport_attach_camera(consumer_viewport, consumer_camera)
		synchronize()
		if not _external_consumer:
			RenderingServer.viewport_set_active(consumer_viewport, true)
	RenderingServer.frame_pre_draw.connect(synchronize)


## Caller supplies live, exclusively controlled RS viewport/camera RIDs, never node RIDs.
## This transfers state authority, not ownership. Active/update mode remain caller-owned.
## Release before freeing either RID; original raw state cannot be queried or restored.
func bind_external(viewport: RID, camera: RID) -> Error:
	if consumer_viewport.is_valid() or consumer_camera.is_valid():
		return ERR_ALREADY_IN_USE
	if (
		not viewport.is_valid()
		or not camera.is_valid()
		or viewport == camera
		or viewport == get_viewport_rid()
	):
		return ERR_INVALID_PARAMETER
	_external_consumer = true
	consumer_viewport = viewport
	consumer_camera = camera
	_state.clear()
	if is_node_ready() and is_inside_tree():
		RenderingServer.viewport_attach_camera(consumer_viewport, consumer_camera)
		synchronize()
	return OK


## Leaves the caller's resources alive with their last managed state and clean compositor.
## Tree exit also releases the binding; reentry requires an explicit bind_external().
func release_external() -> Error:
	if not _external_consumer:
		return ERR_UNCONFIGURED
	_release_consumer()
	return OK


func has_consumer() -> bool:
	# Non-empty handles only. Their type/lifetime is a precondition of bind_external().
	return consumer_viewport.is_valid() and consumer_camera.is_valid()


func synchronize() -> void:
	if not is_inside_tree() or not has_consumer() or not is_instance_valid(state_camera):
		return
	_prune_resets()
	var camera := state_camera
	var state: Array = [
		find_world_3d().scenario,
		size,
		scaling_3d_mode,
		scaling_3d_scale,
		use_taa,
		msaa_3d,
		screen_space_aa,
		transparent_bg,
		camera.get_camera_transform(),
		camera.projection,
		camera.fov,
		camera.size,
		camera.frustum_offset,
		camera.near,
		camera.far,
		camera.keep_aspect,
		camera.cull_mask,
		camera.environment,
		camera.attributes,
		camera.compositor,
	]
	if state == _state:
		return
	_state = state
	RenderingServer.viewport_set_scenario(consumer_viewport, find_world_3d().scenario)
	_consumer_world = find_world_3d()
	RenderingServer.viewport_set_size(consumer_viewport, size.x, size.y)
	RenderingServer.viewport_set_scaling_3d_mode(
		consumer_viewport, scaling_3d_mode as RenderingServer.ViewportScaling3DMode
	)
	RenderingServer.viewport_set_scaling_3d_scale(consumer_viewport, scaling_3d_scale)
	RenderingServer.viewport_set_use_taa(consumer_viewport, use_taa)
	RenderingServer.viewport_set_msaa_3d(consumer_viewport, msaa_3d as RenderingServer.ViewportMSAA)
	RenderingServer.viewport_set_screen_space_aa(
		consumer_viewport, screen_space_aa as RenderingServer.ViewportScreenSpaceAA
	)
	RenderingServer.viewport_set_transparent_background(consumer_viewport, transparent_bg)
	RenderingServer.camera_set_transform(consumer_camera, camera.get_camera_transform())
	RenderingServer.camera_set_use_vertical_aspect(
		consumer_camera, camera.keep_aspect == Camera3D.KEEP_WIDTH
	)
	match camera.projection:
		Camera3D.PROJECTION_PERSPECTIVE:
			RenderingServer.camera_set_perspective(
				consumer_camera, camera.fov, camera.near, camera.far
			)
		Camera3D.PROJECTION_ORTHOGONAL:
			RenderingServer.camera_set_orthogonal(
				consumer_camera, camera.size, camera.near, camera.far
			)
		Camera3D.PROJECTION_FRUSTUM:
			RenderingServer.camera_set_frustum(
				consumer_camera, camera.size, camera.frustum_offset, camera.near, camera.far
			)
	RenderingServer.camera_set_cull_mask(consumer_camera, camera.cull_mask)
	RenderingServer.camera_set_environment(
		consumer_camera, camera.environment.get_rid() if camera.environment != null else RID()
	)
	RenderingServer.camera_set_camera_attributes(
		consumer_camera, camera.attributes.get_rid() if camera.attributes != null else RID()
	)
	RenderingServer.camera_set_compositor(
		consumer_camera, camera.compositor.get_rid() if camera.compositor != null else RID()
	)


func publish_compositor() -> void:
	if consumer_camera.is_valid() and is_instance_valid(state_camera):
		var chain := state_camera.compositor
		RenderingServer.camera_set_compositor(
			consumer_camera, chain.get_rid() if chain != null else RID()
		)


func reset_history() -> void:
	if (
		not is_inside_tree()
		or not has_consumer()
		or not is_instance_valid(state_camera)
		or not use_taa
	):
		return
	_prune_resets()
	var target := RenderingServer.viewport_get_render_target(consumer_viewport)
	state_camera.compositor = RESET.schedule_target(target, state_camera.compositor)
	for effect in state_camera.compositor.compositor_effects:
		if effect is RESET and not _resets.has(effect):
			# Shared chains can carry another native consumer's pending request.
			effect._target_mutex.lock()
			var owns_target: bool = effect.enabled and effect._render_target == target
			effect._target_mutex.unlock()
			if owns_target:
				_resets.append(effect)
	publish_compositor()


func _prune_resets() -> void:
	# Transport may copy a pending effect into a newer chain before its callback.
	# Its deferred unmount only owns the original chain; clean our current copy too.
	var completed: Array[CompositorEffect] = []
	for effect in _resets:
		effect._target_mutex.lock()
		var finished: bool = not effect.enabled
		effect._target_mutex.unlock()
		if finished:
			completed.append(effect)
	var chain := state_camera.compositor
	if chain != null and not completed.is_empty():
		chain.compositor_effects = chain.compositor_effects.filter(
			func(effect): return not completed.has(effect)
		)
	for effect in completed:
		_resets.erase(effect)


func _release_consumer() -> void:
	if not has_consumer():
		return
	consumer_exiting.emit()
	for effect in _resets:
		effect.cancel()
	if is_instance_valid(state_camera):
		_prune_resets()
		publish_compositor()
	_resets.clear()
	if not _external_consumer:
		RenderingServer.viewport_set_active(consumer_viewport, false)
		RenderingServer.free_rid(consumer_viewport)
		RenderingServer.free_rid(consumer_camera)
	consumer_viewport = RID()
	consumer_camera = RID()
	_state.clear()
	_consumer_world = null


func _exit_tree() -> void:
	_release_consumer()
	if RenderingServer.frame_pre_draw.is_connected(synchronize):
		RenderingServer.frame_pre_draw.disconnect(synchronize)
	request_ready()
