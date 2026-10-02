class_name NPRDepthArray
extends RefCounted
## Render-thread-owned GPU copy target; never upload decoded depth through the CPU.
## Call replace/release on RenderingServer's render thread. Explicit release required.

const PIXEL_BYTES := {
	RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM: 4,
	RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT: 8,
	RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: 16,
}

const DECODE = preload("res://addons/npr_character_frame/runtime/npr_depth_decode.gd")

var texture := RID()
var resource := Texture2DArrayRD.new()
var dimensions := Vector2i.ZERO
var layer_sizes: Array[Vector2i] = []
## Logical color payload only, excluding driver alignment and metadata.
var max_payload_bytes := 128 * 1024 * 1024
## Replacement retains the old allocation until the new one is ready. Bound
## their combined logical payload, not just the final resident array.
var max_live_payload_bytes := 256 * 1024 * 1024
var resident_payload_bytes := 0
var peak_live_payload_bytes := 0
var allocation_count := 0
var copy_count := 0
var compact := false
var _format := -1
var _resident_compact := false
var _decoder := DECODE.new()


func replace(sources: Array[RID]) -> Error:
	var rd := RenderingServer.get_rendering_device()
	# Texture2DArrayRD requires at least two physical layers in this engine.
	if rd == null or sources.size() < 2:
		return ERR_INVALID_PARAMETER
	var formats := _read_formats(rd, sources)
	if formats.is_empty():
		return ERR_INVALID_PARAMETER
	var size := Vector2i.ZERO
	for format in formats:
		size = Vector2i(maxi(size.x, format.width), maxi(size.y, format.height))
	var next_bytes: int = (
		size.x * size.y * sources.size() * (4 if compact else PIXEL_BYTES[formats[0].format])
	)
	var live_bytes := resident_payload_bytes + next_bytes
	var target := RDTextureFormat.new()
	target.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	target.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT if compact else formats[0].format
	target.width = size.x
	target.height = size.y
	target.array_layers = sources.size()
	target.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var next := RID()
	if compact:
		target.usage_bits |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	if live_bytes <= max_live_payload_bytes:
		next = rd.texture_create(target, RDTextureView.new())
	if not next.is_valid():
		return ERR_OUT_OF_MEMORY if live_bytes > max_live_payload_bytes else ERR_CANT_CREATE
	peak_live_payload_bytes = maxi(peak_live_payload_bytes, live_bytes)
	# Padding is invalid: zero for packed RGB, negative for decoded scalar depth.
	# Never expose uninitialized memory or treat cleared pixels as near surfaces.
	var clear_error := rd.texture_clear(
		next, Color(-1 if compact else 0, 0, 0, 0), 0, 1, 0, sources.size()
	)
	if clear_error != OK:
		rd.free_rid(next)
		return clear_error
	var sizes: Array[Vector2i] = []
	for layer in range(sources.size()):
		var format := formats[layer]
		var error := _copy_texture(
			rd, sources[layer], next, layer, Vector2i(format.width, format.height)
		)
		if error != OK:
			rd.free_rid(next)
			return error
		copy_count += 1
		sizes.append(Vector2i(format.width, format.height))
	# Keep the RenderingServer texture alive so existing materials retain their
	# binding. Clearing the Resource here would orphan cached sampler RIDs.
	var previous := texture
	texture = next
	resource.texture_rd_rid = texture
	if previous.is_valid():
		rd.free_rid(previous)
	dimensions = size
	layer_sizes = sizes
	_format = formats[0].format
	_resident_compact = compact
	resident_payload_bytes = next_bytes
	allocation_count += 1
	return OK


func update(sources: Array[RID], dirty_layers: PackedInt32Array) -> Error:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not texture.is_valid() or sources.size() != layer_sizes.size():
		return ERR_INVALID_PARAMETER
	var formats := _read_formats(rd, sources)
	if formats.is_empty() or formats[0].format != _format or compact != _resident_compact:
		return ERR_INVALID_PARAMETER
	for layer in range(formats.size()):
		if Vector2i(formats[layer].width, formats[layer].height) != layer_sizes[layer]:
			return ERR_INVALID_PARAMETER
	var seen := {}
	for layer in dirty_layers:
		if layer < 0 or layer >= sources.size() or seen.has(layer):
			return ERR_INVALID_PARAMETER
		seen[layer] = true
	var selected: Array[RID] = []
	for layer in dirty_layers:
		selected.append(sources[layer])
	return _copy_layers(rd, selected, dirty_layers)


## Update an explicit destination mapping without passing unrelated view sources.
## One view can submit its own character/hair pair into a shared multi-view array.
func update_layers(sources: Array[RID], destinations: PackedInt32Array) -> Error:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not texture.is_valid() or sources.size() != destinations.size():
		return ERR_INVALID_PARAMETER
	if sources.is_empty():
		return OK
	var formats := _read_formats(rd, sources)
	if formats.is_empty() or formats[0].format != _format or compact != _resident_compact:
		return ERR_INVALID_PARAMETER
	var seen := {}
	for index in range(destinations.size()):
		var layer := destinations[index]
		if layer < 0 or layer >= layer_sizes.size() or seen.has(layer):
			return ERR_INVALID_PARAMETER
		seen[layer] = true
		if Vector2i(formats[index].width, formats[index].height) != layer_sizes[layer]:
			return ERR_INVALID_PARAMETER
	return _copy_layers(rd, sources, destinations)


func _copy_layers(
	rd: RenderingDevice, sources: Array[RID], destinations: PackedInt32Array
) -> Error:
	# Both public update paths validate the complete job before entering here.
	# A device failure can still partially write: consumers must invalidate the view.
	for index in range(destinations.size()):
		var layer := destinations[index]
		var size := layer_sizes[layer]
		var error := _copy_texture(rd, sources[index], texture, layer, size)
		if error != OK:
			return error
		copy_count += 1
	return OK


func _copy_texture(
	rd: RenderingDevice, source: RID, target: RID, layer: int, size: Vector2i
) -> Error:
	if compact:
		return _decoder.copy(source, target, layer, size)
	return rd.texture_copy(
		source, target, Vector3.ZERO, Vector3.ZERO, Vector3(size.x, size.y, 1), 0, 0, 0, layer
	)


func _read_formats(rd: RenderingDevice, sources: Array[RID]) -> Array[RDTextureFormat]:
	var formats: Array[RDTextureFormat] = []
	if sources.size() > rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_ARRAY_LAYERS):
		return []
	var size := Vector2i.ZERO
	for source in sources:
		if not rd.texture_is_valid(source):
			return []
		var format := rd.texture_get_format(source)
		if (
			not PIXEL_BYTES.has(format.format)
			or format.texture_type != RenderingDevice.TEXTURE_TYPE_2D
			or format.samples != RenderingDevice.TEXTURE_SAMPLES_1
			or not (format.usage_bits & RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
			or (compact and not (format.usage_bits & RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT))
			or (not formats.is_empty() and format.format != formats[0].format)
		):
			return []
		formats.append(format)
		size = Vector2i(maxi(size.x, format.width), maxi(size.y, format.height))
	if not formats.is_empty():
		var bytes: int = (
			size.x * size.y * sources.size() * (4 if compact else PIXEL_BYTES[formats[0].format])
		)
		if bytes > max_payload_bytes:
			return []
	return formats


func release() -> void:
	_decoder.release()
	resource.texture_rd_rid = RID()
	if texture.is_valid():
		RenderingServer.get_rendering_device().free_rid(texture)
	texture = RID()
	dimensions = Vector2i.ZERO
	layer_sizes.clear()
	_format = -1
	resident_payload_bytes = 0
