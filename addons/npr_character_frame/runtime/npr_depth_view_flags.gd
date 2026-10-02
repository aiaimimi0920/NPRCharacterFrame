class_name NPRDepthViewFlags
extends RefCounted
## Render-thread-owned per-view GPU validity. One sampler, not one per camera.
## Before reset/release, consumers must unbind the old texture descriptor.

var resource := Texture2DArrayRD.new()
var texture := RID()
var view_count := 0
var epoch := 0


func reset(count: int) -> Error:
	var rd := RenderingServer.get_rendering_device()
	if rd == null or count <= 0:
		return ERR_INVALID_PARAMETER
	var layers := maxi(count, 2)  # Texture2DArrayRD requires two physical layers.
	if layers > rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_ARRAY_LAYERS):
		return ERR_INVALID_PARAMETER
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.width = 1
	format.height = 1
	format.array_layers = layers
	format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var next := rd.texture_create(format, RDTextureView.new())
	if not next.is_valid():
		return ERR_CANT_CREATE
	var error := rd.texture_clear(next, Color.BLACK, 0, 1, 0, layers)
	if error != OK:
		rd.free_rid(next)
		return error
	var previous := texture
	texture = next
	resource.texture_rd_rid = next
	view_count = count
	epoch += 1
	if previous.is_valid():
		rd.free_rid(previous)
	return OK


## A queued write must carry the epoch captured when its view mapping was built.
## Old generations cannot make a newly allocated/reused view appear ready.
func set_ready(view: int, expected_epoch: int, ready: bool) -> Error:
	if expected_epoch != epoch or view < 0 or view >= view_count or not texture.is_valid():
		return ERR_INVALID_PARAMETER
	return RenderingServer.get_rendering_device().texture_clear(
		texture, Color.WHITE if ready else Color.BLACK, 0, 1, view, 1
	)


func release() -> void:
	resource.texture_rd_rid = RID()
	if texture.is_valid():
		RenderingServer.get_rendering_device().free_rid(texture)
	texture = RID()
	view_count = 0
	epoch += 1
