extends "res://addons/npr_character_frame/runtime/npr_depth_array_update.gd"
## One view's PRE_OPAQUE transaction into a shared array. Configure before attach.
## target/flags storage is owned externally; this effect never reallocates either.

var flags: RefCounted
var view_index := -1
var view_epoch := -1
var destinations := PackedInt32Array()
var reset_taa_on_ready := false
var _last_success := false


func _render_callback(type: int, data: RenderData) -> void:
	var before: Dictionary = result()
	super._render_callback(type, data)
	var after: Dictionary = result()
	if after.completed == before.completed:
		return
	var success: bool = after.error == OK
	if reset_taa_on_ready and success != _last_success:
		var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
		if buffers != null and buffers.get_use_taa() and buffers.has_texture("taa", "history"):
			# The local Forward+ TAA stage initializes from current color when
			# this context is absent. Neither failure nor recovery may retain
			# history rendered under the opposite readiness state.
			buffers.clear_context("taa")
			_mutex.lock()
			_result["taa_resets"] = _result.get("taa_resets", 0) + 1
			_mutex.unlock()
	_last_success = success


func _prepare_readiness() -> Error:
	if flags == null:
		return ERR_INVALID_PARAMETER
	# Epoch rejection happens before any depth writes, not after copying stale data.
	return flags.set_ready(view_index, view_epoch, false)


func _publish_readiness() -> Error:
	return flags.set_ready(view_index, view_epoch, true)


func _execute_job(inputs: Array[RID], job: Dictionary) -> Error:
	if job.rebuild or inputs.is_empty() or inputs.size() != destinations.size():
		return ERR_INVALID_PARAMETER
	var seen := {}
	for index in job.dirty:
		if index < 0 or index >= inputs.size() or seen.has(index):
			return ERR_INVALID_PARAMETER
		seen[index] = true
	# Each queued job carries the complete view snapshot. Copying the whole view
	# also repairs a previously partial GPU failure without touching other views.
	return target.update_layers(inputs, destinations)


func release() -> void:
	if flags != null:
		flags.set_ready(view_index, view_epoch, false)
