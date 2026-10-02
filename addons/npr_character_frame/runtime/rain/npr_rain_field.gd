extends RefCounted
## GPU rasterization of bounded particle snapshots. No CPU atlas painting/readback.

const STAMP = preload("res://addons/npr_character_frame/shaders/rain/rain_stamp.gdshader")
const DECAY = preload("res://addons/npr_character_frame/shaders/rain/rain_decay.gdshader")
const ROW_WIDTH := 4
var heads: SubViewport
var trails: SubViewport
var _stamp_materials: Array[ShaderMaterial] = []
var _decay: ShaderMaterial
var _state_image: Image
var _state_texture: ImageTexture
var _state := PackedFloat32Array()
var _size := Vector2i.ZERO


func setup(parent: Node, size: Vector2i, chart: PackedByteArray, capacity: int) -> void:
	_size = size
	_state.resize(capacity * ROW_WIDTH * 4)
	_state.fill(0.0)
	_state_image = Image.create_from_data(
		ROW_WIDTH, capacity, false, Image.FORMAT_RGBAF, _state.to_byte_array()
	)
	_state_texture = ImageTexture.create_from_image(_state_image)
	var chart_texture := ImageTexture.create_from_image(
		Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, chart)
	)
	trails = _viewport(parent, "RainTrails", size)
	trails.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	var fade := ColorRect.new()
	fade.size = Vector2(size)
	_decay = ShaderMaterial.new()
	_decay.shader = DECAY
	fade.material = _decay
	trails.add_child(fade)
	heads = _viewport(parent, "RainHeads", size)
	for target in [trails, heads]:
		var material := ShaderMaterial.new()
		material.shader = STAMP
		material.set_shader_parameter("particle_state", _state_texture)
		material.set_shader_parameter("chart_map", chart_texture)
		material.set_shader_parameter("atlas_size", Vector2(size))
		material.set_shader_parameter("trail_pass", target == trails)
		_stamp_materials.append(material)
		var draw := MultiMeshInstance2D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_2D
		multi.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		multi.mesh = quad
		multi.instance_count = capacity * 2
		for i in capacity * 2:
			# Bounds cover the atlas; the shader positions small quads from snapshots.
			multi.set_instance_transform_2d(
				i, Transform2D(Vector2(size.x, 0), Vector2(0, size.y), Vector2(size) * 0.5)
			)
			multi.set_instance_custom_data(i, Color(float(i), 0.0, 0.0, 0.0))
		draw.multimesh = multi
		draw.material = material
		target.add_child(draw)
	clear()


func _viewport(parent: Node, label: String, size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.size = size
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	return viewport


func write(slot: int, previous: Vector4, next: Vector4, timing: Vector4) -> void:
	var offset := slot * ROW_WIDTH * 4
	for value in [previous, next, timing]:
		for component in 4:
			_state[offset] = value[component]
			offset += 1


func clear() -> void:
	_state.fill(0.0)
	trails.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	present(0.0, 0.0)


func present(clock: float, delta: float) -> void:
	_state_image.set_data(
		ROW_WIDTH, _state_image.get_height(), false, Image.FORMAT_RGBAF, _state.to_byte_array()
	)
	_state_texture.update(_state_image)
	for material in _stamp_materials:
		material.set_shader_parameter("display_time", clock)
		material.set_shader_parameter("deposit_delta", delta)
	_decay.set_shader_parameter("retention", exp(-delta * 0.13))
	heads.render_target_update_mode = SubViewport.UPDATE_ONCE
	trails.render_target_update_mode = SubViewport.UPDATE_ONCE


func image() -> Image:
	# Validation only. Never called on the gameplay update path.
	return trails.get_texture().get_image()
