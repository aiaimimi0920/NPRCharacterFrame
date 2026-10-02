extends CompositorEffect
## Same-frame GPU updates for an already allocated NPRDepthArray.
## Configure target before attaching; detach before releasing its storage.
## The owner must order depth viewports before this consumer and handle failures.

var target: RefCounted
var readiness := Texture2DRD.new()
var _ready_texture := RID()
var _needs_full_refresh := false
var _mutex := Mutex.new()
var _pending: Dictionary = {}
var _serial := 0
var _result := {"error": OK, "calls": 0, "completed": 0, "copies": 0}


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE


## Positive serial means accepted, zero means no work, -1 means backpressure.
## Never overwrite an unconsumed job: that could lose a dirty layer update.
func queue_update(sources: Array[RID], dirty: PackedInt32Array, rebuild := false) -> int:
	if dirty.is_empty() and not rebuild:
		return 0
	_mutex.lock()
	if not _pending.is_empty():
		_mutex.unlock()
		return -1
	_serial += 1
	_pending = {
		"sources": sources.duplicate(),
		"dirty": dirty.duplicate(),
		"serial": _serial,
		"rebuild": rebuild
	}
	var accepted := _serial
	_mutex.unlock()
	return accepted


func result() -> Dictionary:
	_mutex.lock()
	var value := _result.duplicate(true)
	_mutex.unlock()
	return value


func _render_callback(_type: int, _data: RenderData) -> void:
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
	var error := _prepare_readiness()
	if error == OK:
		error = _execute_job(inputs, job)
		if error == OK:
			error = _publish_readiness()
	_needs_full_refresh = error != OK
	_mutex.lock()
	_result["error"] = error
	_result["completed"] = job.serial
	_result["copies"] += target.copy_count - copies_before
	_result["sizes"] = target.layer_sizes.duplicate()
	_result["allocations"] = target.allocation_count
	_result["resident_payload_bytes"] = target.resident_payload_bytes
	_result["peak_live_payload_bytes"] = target.peak_live_payload_bytes
	_mutex.unlock()


func _execute_job(inputs: Array[RID], job: Dictionary) -> Error:
	return target.replace(inputs) if job.rebuild else _update_layers(inputs, job.dirty)


func _publish_readiness() -> Error:
	return RenderingServer.get_rendering_device().texture_clear(
		_ready_texture, Color.WHITE, 0, 1, 0, 1
	)


func _update_layers(inputs: Array[RID], requested: PackedInt32Array) -> Error:
	# Recovery expands valid requests, not invalid ones. Do not accidentally
	# turn an out-of-range/duplicate request into success by replacing its list.
	var seen := {}
	for layer in requested:
		if layer < 0 or layer >= inputs.size() or seen.has(layer):
			return ERR_INVALID_PARAMETER
		seen[layer] = true
	var dirty := requested
	if _needs_full_refresh:
		dirty = PackedInt32Array()
		for layer in range(inputs.size()):
			dirty.append(layer)
	return target.update(inputs, dirty)


func _prepare_readiness() -> Error:
	var rd := RenderingServer.get_rendering_device()
	if not _ready_texture.is_valid():
		var format := RDTextureFormat.new()
		format.width = 1
		format.height = 1
		format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
		format.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		)
		_ready_texture = rd.texture_create(format, RDTextureView.new())
		if not _ready_texture.is_valid():
			return ERR_CANT_CREATE
		readiness.texture_rd_rid = _ready_texture
	# Invalidate before writing any layer. Failure leaves the shader on the
	# already-rendered direct depth path, including in this very draw.
	return rd.texture_clear(_ready_texture, Color.BLACK, 0, 1, 0, 1)


## Render thread only, after detaching this effect and unbinding readiness.
func release() -> void:
	readiness.texture_rd_rid = RID()
	if _ready_texture.is_valid():
		RenderingServer.get_rendering_device().free_rid(_ready_texture)
	_ready_texture = RID()
