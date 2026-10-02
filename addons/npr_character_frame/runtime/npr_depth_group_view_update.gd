class_name NPRDepthGroupViewUpdate
extends CompositorEffect
## Same-frame GPU update for one view in NPRDepthGroupStorage.
## The effect owns no GPU allocation; the transport owns the grouped storage.

var target: RefCounted
var view_index := -1
var reset_taa_on_ready := false
var _last_success := false
var _pending: Dictionary = {}
var _serial := 0
var _mutex := Mutex.new()
var _result := {"error": OK, "calls": 0, "completed": 0, "copies": 0}


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE


func queue_update(sources: Array[RID]) -> int:
	if sources.size() != 2:
		return -1
	_mutex.lock()
	if not _pending.is_empty():
		_mutex.unlock()
		return -1
	_serial += 1
	_pending = {"sources": sources.duplicate(), "serial": _serial}
	var accepted := _serial
	_mutex.unlock()
	return accepted


func result() -> Dictionary:
	_mutex.lock()
	var value := _result.duplicate(true)
	_mutex.unlock()
	return value


func _render_callback(_type: int, data: RenderData) -> void:
	_mutex.lock()
	var job := _pending
	_pending = {}
	_result["calls"] += 1
	_mutex.unlock()
	if job.is_empty():
		return
	var inputs: Array[RID] = []
	for source: RID in job.sources:
		inputs.append(RenderingServer.texture_get_rd_texture(source))
	var copies_before: int = target.copy_count
	var error: Error = target.update_view(view_index, inputs)
	var success := error == OK
	if reset_taa_on_ready and success != _last_success:
		var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
		if buffers != null and buffers.get_use_taa() and buffers.has_texture("taa", "history"):
			buffers.clear_context("taa")
	_last_success = success
	_mutex.lock()
	_result["error"] = error
	_result["completed"] = job.serial
	_result["copies"] += target.copy_count - copies_before
	_mutex.unlock()


func release() -> void:
	if target != null and view_index >= 0:
		target.invalidate_view(view_index)
