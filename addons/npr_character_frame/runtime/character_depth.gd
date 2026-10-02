extends Node
## Per-character, camera-matched linear data buffers. Never render consumer materials here.

enum Quality { PERFORMANCE, BALANCED, FULL }
const ENCODE = preload("res://addons/npr_character_frame/shaders/common/npr_depth_encode.gdshader")
const GEOMETRY = preload("res://addons/npr_character_frame/runtime/npr_geometry_state.gd")
const ARRAY_BINDING = preload("res://addons/npr_character_frame/runtime/npr_depth_array_binding.gd")
const MULTIVIEW_BINDING = preload(
	"res://addons/npr_character_frame/runtime/npr_multiview_transport.gd"
)
const CAMERA_KEYS := [
	"projection",
	"keep_aspect",
	"fov",
	"size",
	"near",
	"far",
	"frustum_offset",
	"h_offset",
	"v_offset"
]
const VISIBILITY_PARAMETERS := [
	"u_npr_surface_effects_enabled",
	"u_npr_surface_effects",
	"u_npr_dissolve_noise",
	"u_npr_dissolve_edge_width",
	"u_npr_dissolve_edge_color",
	"u_npr_dissolve_world_space",
	"u_npr_dissolve_world_scale",
	"u_npr_dissolve_world_offset",
	"u_npr_dissolve_enabled",
	"u_npr_dissolve_amount",
	"u_npr_visibility_alpha",
	"u_npr_visibility_alpha_cutoff",
	"u_npr_visibility_dither_enabled"
]

## Reference/benchmark switch: same images, but redraw every demanded pass.
@export var force_continuous := false
## Full preserves the approved look. Lower tiers are explicit, lossy opt-ins.
@export var quality: Quality = Quality.FULL

var viewports: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var proxies: Array[MeshInstance3D] = []
var sources: Array[MeshInstance3D] = []
var consumers: Array[ShaderMaterial] = []
var depth_range := 16.0
var active := true
var camera: Camera3D
var requested_this_frame: Array[bool] = [false, false]
var redraw_requests: Array[int] = [0, 0]
var state_uploads := 0
var _encoders: Array[ShaderMaterial] = []
var _geometry: Array[Node] = []
var _proxy_indices: Array[int] = []
var _proxy_passes: Array[int] = []
var _proxy_uploaded_states: Array[Array] = []
var _camera_uploaded_states: Array[Array] = [[], []]
var _source_states: Array[Array] = []
var _mesh_resources: Array[Mesh] = []
var _mesh_callbacks: Array[Callable] = []
var _camera_state: Array = []
var _dirty: Array[bool] = [true, true]
var _bounds_dirty := true
var _range_dirty := true
var _bounds := AABB()
var _rest_bounds := AABB()
var _published_enabled: Variant = null
var _published_height := -1.0
var _projection_scale := Vector2.ONE
var _view_slot := 0
var _target_viewport: WeakRef
var _additional: Node
var _array_binding: Node
var _multiview_binding: Node
var _view_producers: Dictionary[int, Node] = {}
var _metadata_only := false
var _view_metadata: Dictionary = {}
var _metadata_revision := 0
var _record_state: Array = []
var _record_snapshot: Dictionary = {}


func _enter_tree() -> void:
	if viewports.is_empty():
		return
	# Existing pass resources survive a reparent, but exit-tree disconnected
	# callbacks and cleared consumer textures. Rebind rather than duplicate passes.
	_mesh_resources.fill(null)
	_camera_state.clear()
	_camera_uploaded_states.assign([[], []])
	for state in _source_states:
		state.clear()
	for state in _proxy_uploaded_states:
		state.clear()
	_dirty.assign([true, true])
	_bounds_dirty = true
	_range_dirty = true
	_published_enabled = null
	_bind_consumers()


func setup(meshes: Array[MeshInstance3D], materials: Array[ShaderMaterial]) -> void:
	assert(meshes.size() == 3 and materials.size() == 3, "Expected body, face and hair")
	sources = meshes
	_source_states.resize(sources.size())
	_mesh_resources.resize(sources.size())
	_mesh_callbacks.resize(sources.size())
	consumers.assign([materials[0], materials[1], materials[2], materials[2].next_pass])
	for index in range(sources.size()):
		_geometry.append(GEOMETRY.attach(sources[index], index))
		var encode := ShaderMaterial.new()
		encode.shader = ENCODE
		_copy_visibility(materials[index], encode)
		_encoders.append(encode)
	for pass_index in range(2):
		var viewport := SubViewport.new()
		viewport.name = "CharacterDepth" if pass_index == 0 else "HairDepth"
		viewport.size = Vector2i(16, 16)
		viewport.own_world_3d = true
		viewport.use_hdr_2d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(viewport)
		viewports.append(viewport)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color.BLACK
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		var view_camera := Camera3D.new()
		view_camera.environment = environment
		viewport.add_child(view_camera)
		cameras.append(view_camera)
		for index in range(sources.size()):
			if pass_index == 1 and index != 2:
				continue
			var proxy := MeshInstance3D.new()
			proxy.mesh = sources[index].mesh
			proxy.material_override = _encoders[index]
			proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			viewport.add_child(proxy)
			proxies.append(proxy)
			_proxy_indices.append(index)
			_proxy_passes.append(pass_index)
			_proxy_uploaded_states.append([])
	_bind_consumers()


func set_dissolve(amount: float) -> void:
	var resolved := clampf(amount, 0.0, 1.0)
	for encoder in _encoders:
		encoder.set_shader_parameter("u_npr_dissolve_enabled", resolved > 0.0)
		encoder.set_shader_parameter("u_npr_dissolve_amount", resolved)
	_dirty.assign([true, true])


func set_visibility(alpha: float, dither_enabled: bool) -> void:
	var resolved := clampf(alpha, 0.0, 1.0)
	for encoder in _encoders:
		encoder.set_shader_parameter("u_npr_visibility_alpha", resolved)
		encoder.set_shader_parameter("u_npr_visibility_dither_enabled", dither_enabled)
	_dirty.assign([true, true])


func refresh_visibility(source_materials: Array[ShaderMaterial]) -> void:
	if source_materials.size() != _encoders.size():
		return
	for index in range(_encoders.size()):
		_copy_visibility(source_materials[index], _encoders[index])
	_dirty.assign([true, true])


static func _copy_visibility(source: ShaderMaterial, target: ShaderMaterial) -> void:
	for parameter in VISIBILITY_PARAMETERS:
		var value: Variant = source.get_shader_parameter(parameter)
		if value != null:
			target.set_shader_parameter(parameter, value)


func _bind_consumers() -> void:
	for material in consumers:
		_set_parameter(material, "u_npr_depth_viewport_size", Vector2.ZERO)
		_set_parameter(material, "u_npr_character_depth", viewports[0].get_texture())
		_set_parameter(material, "u_npr_hair_depth", viewports[1].get_texture())
	RenderingServer.frame_pre_draw.connect(synchronize)
	_publish_enabled(false)


## Explicit opt-in until all view types have matching lifecycle evidence.
func set_array_transport(enabled: bool, integer_sampling := false) -> bool:
	if _view_slot != 0 or not is_inside_tree() or consumers.is_empty():
		return false
	if enabled and is_instance_valid(_multiview_binding):
		return false
	if not enabled:
		if is_instance_valid(_array_binding):
			_array_binding.free()
		_array_binding = null
	elif not is_instance_valid(_array_binding):
		_array_binding = ARRAY_BINDING.new()
		_array_binding.name = "DepthArrayTransport"
		_array_binding.depth = self
		_array_binding.integer_sampling = integer_sampling
		add_child(_array_binding)
	if enabled:
		_array_binding.integer_sampling = integer_sampling
	return true


## Explicit integer sampling changes the legacy normalized-nearest contract.
## Disable the old array transport and unregister its secondary view first.
func set_multiview_transport(
	enabled: bool, integer_sampling := true, compact_storage := false
) -> bool:
	if _view_slot != 0 or not is_inside_tree() or consumers.is_empty():
		return false
	if enabled and (is_instance_valid(_array_binding) or is_instance_valid(_additional)):
		return false
	if not enabled:
		if is_instance_valid(_multiview_binding):
			_multiview_binding.free()
		_multiview_binding = null
	elif not is_instance_valid(_multiview_binding):
		_multiview_binding = MULTIVIEW_BINDING.new()
		_multiview_binding.depth = self
		_multiview_binding.integer_sampling = integer_sampling
		_multiview_binding.compact_storage = compact_storage
		add_child(_multiview_binding)
	elif (
		_multiview_binding.integer_sampling != integer_sampling
		or _multiview_binding.compact_storage != compact_storage
	):
		return false
	return true


## Grouped storage is an explicit opt-in layered on the multiview transport.
## The legacy unified array remains the default when this is false.
func set_grouped_storage(enabled: bool) -> bool:
	if not is_instance_valid(_multiview_binding):
		return false
	_multiview_binding.set_grouped_storage(enabled)
	return true


func set_enabled(enabled: bool) -> void:
	for producer in _view_producers.values():
		if is_instance_valid(producer):
			producer.set_enabled(enabled)
	if is_instance_valid(_additional):
		_additional.set_enabled(enabled)
	if active == enabled:
		return
	active = enabled
	_dirty.assign([true, true])
	if not enabled:
		_stop_all()


func synchronize() -> void:
	_sync_additional()
	requested_this_frame.assign([false, false])
	if not active:
		return
	var target := _render_viewport()
	camera = target.get_camera_3d() if target != null else null
	if not is_instance_valid(camera) or sources.is_empty():
		_dirty.assign([true, true])
		_stop_all()
		return
	var rim_needed := (
		(_source_visible(0) and _positive(consumers[0], "u_npr_rim_strength"))
		or (
			_source_visible(2)
			and (
				_positive(consumers[2], "u_npr_rim_strength")
				or _positive(consumers[3], "u_npr_rim_strength")
			)
		)
	)
	var hair_needed := (
		_source_visible(1)
		and _source_visible(2)
		and _positive(consumers[1], "u_npr_contact_strength")
	)
	if not rim_needed and not hair_needed:
		_stop_all()
		return
	_refresh_sources()
	_refresh_camera()
	_refresh_bounds_and_range()
	_publish_enabled(rim_needed, hair_needed)
	for index in range(2):
		var needed: bool = [rim_needed, hair_needed][index]
		if not needed:
			_disable_viewport(index)
		elif _dirty[index] or force_continuous:
			_prepare_pass(index)
			# The renderer resets its UPDATE_ONCE, but SubViewport's cached getter
			# does not. Always submit ONCE again, even if get_update_mode says ONCE.
			viewports[index].render_target_update_mode = SubViewport.UPDATE_ONCE
			requested_this_frame[index] = true
			redraw_requests[index] += 1
			_dirty[index] = false


## One explicit additional view; never evict another live registration implicitly.
func register_view(viewport: Viewport) -> bool:
	if _view_slot != 0 or consumers.is_empty() or not is_inside_tree():
		return false
	if is_instance_valid(_multiview_binding):
		return _multiview_binding.register_view(viewport)
	_sync_additional()
	if not _valid_viewport(viewport) or viewport == get_viewport():
		return false
	if viewport.find_world_3d() != get_viewport().find_world_3d():
		return false
	if is_instance_valid(_additional):
		return _additional._target_viewport.get_ref() == viewport
	_additional = get_script().new()
	_additional.name = "AdditionalViewDepth"
	_additional._view_slot = 1
	_additional._target_viewport = weakref(viewport)
	_additional.active = active
	_additional.quality = quality
	_additional.force_continuous = force_continuous
	add_child(_additional)
	var materials: Array[ShaderMaterial] = [consumers[0], consumers[1], consumers[2]]
	# attach() reuses the existing source-owned geometry state; no actor or light copies.
	_additional.setup(sources, materials)
	return true


func unregister_view(viewport: Viewport = null) -> void:
	if is_instance_valid(_multiview_binding):
		_multiview_binding.unregister_view(viewport)
		return
	if not is_instance_valid(_additional):
		_additional = null
		return
	if viewport != null and _additional._target_viewport.get_ref() != viewport:
		return
	_additional.free()
	_additional = null


func get_view_pass(viewport: Viewport) -> Node:
	if not is_inside_tree() or not is_instance_valid(viewport):
		return null
	if viewport == get_viewport():
		return self
	if is_instance_valid(_multiview_binding):
		return _multiview_binding.get_producer(viewport)
	if is_instance_valid(_additional) and _additional._target_viewport.get_ref() == viewport:
		return _additional
	return null


func _sync_additional() -> void:
	_sync_view_producers()
	if not is_instance_valid(_additional):
		return
	var target: Viewport = _additional._target_viewport.get_ref()
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		unregister_view()
		return
	_additional.set_enabled(active)
	_additional.quality = quality
	_additional.force_continuous = force_continuous


func _valid_viewport(viewport: Viewport) -> bool:
	return (
		is_instance_valid(viewport)
		and viewport.is_inside_tree()
		and not viewport.is_queued_for_deletion()
	)


func _render_viewport() -> Viewport:
	if _view_slot == 0:
		return get_viewport()
	var target := _target_viewport.get_ref() as Viewport
	if not _valid_viewport(target):
		return null
	if target == get_viewport():
		return null  # Primary now renders this mapping; resume if the actor moves back.
	# A temporarily detached or foreign-World target keeps its registration but is
	# disabled until compatible again. A freed/queued target releases its slot.
	if target.find_world_3d() != get_viewport().find_world_3d():
		return null
	return target


func _set_parameter(material: ShaderMaterial, parameter: StringName, value: Variant) -> void:
	var key := String(parameter)
	_view_metadata[key] = value
	_metadata_revision += 1
	if _metadata_only:
		return
	if _view_slot == 1:
		key += "_secondary"
	material.set_shader_parameter(key, value)


## Producer registration only. The shared-array owner must publish its output
## through the dynamic table before this viewport has complete NPR depth effects.
func register_view_producer(viewport: Viewport) -> Node:
	if _view_slot != 0 or consumers.is_empty() or not is_inside_tree():
		return null
	_sync_view_producers()
	if not _valid_viewport(viewport) or viewport == get_viewport():
		return null
	if viewport.find_world_3d() != get_viewport().find_world_3d():
		return null
	var id := viewport.get_instance_id()
	if _view_producers.has(id):
		return _view_producers[id]
	var producer: Node = get_script().new()
	producer.name = "ViewDepthProducer_%d" % id
	producer._view_slot = 2
	producer._metadata_only = true
	producer._target_viewport = weakref(viewport)
	producer.active = active
	producer.quality = quality
	producer.force_continuous = force_continuous
	add_child(producer)
	var materials: Array[ShaderMaterial] = [consumers[0], consumers[1], consumers[2]]
	producer.setup(sources, materials)
	_view_producers[id] = producer
	return producer


func unregister_view_producer(viewport: Viewport) -> void:
	if not is_instance_valid(viewport):
		return
	var id := viewport.get_instance_id()
	if _view_producers.has(id):
		var producer: Node = _view_producers[id]
		_view_producers.erase(id)
		if is_instance_valid(producer):
			producer.free()


func _sync_view_producers() -> void:
	for id in _view_producers.keys():
		var producer: Node = _view_producers[id]
		var target: Viewport = null
		if is_instance_valid(producer):
			target = producer._target_viewport.get_ref()
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			_view_producers.erase(id)
			if is_instance_valid(producer):
				producer.free()
			continue
		producer.set_enabled(active)
		producer.quality = quality
		producer.force_continuous = force_continuous


## Snapshot for NPRDepthViewTable; no recomputation of projection conventions.
func get_view_record(array_base: int, ready_index: int) -> Dictionary:
	if not is_instance_valid(camera) or _render_viewport() == null:
		return {}
	if not _view_metadata.has("u_npr_depth_projection") or _published_enabled == null:
		return {}
	return _make_view_record(array_base, ready_index)


func _make_view_record(array_base: int, ready_index: int) -> Dictionary:
	var flags: Vector2i = _published_enabled
	var record: Dictionary = {
		"world": _view_metadata["u_npr_depth_camera_world"],
		"projection": _view_metadata["u_npr_depth_projection"],
		"viewport_size": _view_metadata["u_npr_depth_viewport_size"],
		"pixel_size": _view_metadata["u_npr_depth_pixel_size"],
		"layers": _view_metadata["u_npr_depth_layers"],
		"steps": _view_metadata["u_npr_contact_steps"],
		"enabled": flags.x | (flags.y << 1),
		"range": depth_range,
		"height": _published_height,
		"array_base": array_base,
		"ready_index": ready_index,
		"sizes":
		Vector4(viewports[0].size.x, viewports[0].size.y, viewports[1].size.x, viewports[1].size.y)
	}
	return record


## Immutable transport snapshot; the public record getter remains mutable.
func get_view_snapshot(array_base: int, ready_index: int) -> Dictionary:
	if not is_instance_valid(camera) or _render_viewport() == null:
		return {}
	if not _view_metadata.has("u_npr_depth_projection") or _published_enabled == null:
		return {}
	# Matrices/vectors are invalidated on every write, including signed zero.
	# Remaining floats are positive depth extents; indices/flags/sizes are integers.
	var state: Array = [
		_metadata_revision,
		depth_range,
		_published_height,
		_published_enabled,
		array_base,
		ready_index,
		viewports[0].size,
		viewports[1].size
	]
	if state != _record_state:
		var record := _make_view_record(array_base, ready_index)
		record.make_read_only()
		_record_snapshot = record
		_record_state = state
	return _record_snapshot


func _refresh_sources() -> void:
	for index in range(sources.size()):
		var source := sources[index]
		var mesh: Mesh = source.mesh if is_instance_valid(source) else null
		_watch_mesh(index, mesh)
		var state: Array = []
		if is_instance_valid(source) and mesh != null:
			state = [
				source.global_transform,
				source.is_visible_in_tree() and (source.layers & camera.cull_mask) != 0,
				source.lod_bias,
				mesh,
				_geometry[index].rest_bounds,
				_geometry[index].revision,
				_geometry[index].local_bounds
			]
		if _source_states[index] == state:
			continue
		_source_states[index] = state
		_invalidate_source(index)


func _watch_mesh(index: int, mesh: Mesh) -> void:
	if _mesh_resources[index] == mesh:
		return
	_disconnect_mesh(index)
	_mesh_resources[index] = mesh
	if mesh != null:
		_mesh_callbacks[index] = _invalidate_source.bind(index)
		mesh.changed.connect(_mesh_callbacks[index])
	_invalidate_source(index)


func _disconnect_mesh(index: int) -> void:
	var mesh := _mesh_resources[index]
	if mesh != null and mesh.changed.is_connected(_mesh_callbacks[index]):
		mesh.changed.disconnect(_mesh_callbacks[index])


func _invalidate_source(index: int) -> void:
	_dirty[0] = true
	if index == 2:
		_dirty[1] = true
	_bounds_dirty = true


## Shared by depth production and CPU cursor rays; do not duplicate native rounding.
static func get_render_size(source_viewport: Viewport, logical_size: Vector2i) -> Vector2i:
	var dimensions := logical_size
	if source_viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR:
		# RendererViewport uses float32 multiplication, truncation, and this clamp.
		# Its camera aspect AND shader VIEWPORT_SIZE use the internal size, not the
		# output size. Keep the near-1 optimization identical to the renderer.
		var scale: float = source_viewport.scaling_3d_scale
		# C++ promotes its float EPSILON to double when adding the 1.0 literal;
		# do not round the final interval endpoints back to float32.
		var native_epsilon: float = Vector2(0.0001, 0.0).x
		if scale < 1.0 - native_epsilon or scale > 1.0 + native_epsilon:
			dimensions = Vector2i(Vector2(logical_size) * scale).clamp(
				Vector2i.ONE, Vector2i(16384, 16384)
			)
	return dimensions


func _refresh_camera() -> void:
	var source_viewport := camera.get_viewport()
	var logical_size := Vector2i(source_viewport.get_visible_rect().size)
	logical_size = Vector2i(maxi(logical_size.x, 2), maxi(logical_size.y, 2))
	var dimensions := get_render_size(source_viewport, logical_size)
	var tier := clampi(quality, Quality.PERFORMANCE, Quality.FULL)
	var data_size := Vector2i(maxi(dimensions.x, 2), maxi(dimensions.y, 2))
	if tier != Quality.FULL:
		data_size = Vector2i((Vector2(dimensions) * 0.5).ceil())
		data_size = Vector2i(maxi(data_size.x, 2), maxi(data_size.y, 2))
	var ratio := Vector2(data_size) / Vector2(dimensions)
	_projection_scale = (
		Vector2(1.0, ratio.y / ratio.x)
		if camera.keep_aspect == Camera3D.KEEP_WIDTH
		else Vector2(ratio.x / ratio.y, 1.0)
	)
	var state: Array = [
		camera.get_instance_id(),
		camera.global_transform,
		data_size,
		(
			source_viewport.mesh_lod_threshold
			* ratio.x
			* (float(dimensions.x) / logical_size.x)
			/ _projection_scale.x
		)
	]
	for key in CAMERA_KEYS:
		state.append(camera.get(key))
	# Preserve logical dimensions even when half-resolution rounding is unchanged.
	state.append(dimensions)
	state.append(logical_size)
	state.append(tier)
	state.append(camera.cull_mask)
	if state == _camera_state:
		return
	_camera_state = state
	for encode in _encoders:
		encode.set_shader_parameter("projection_scale", _projection_scale)
	# Match the actual Forward+ camera UBO, including reverse-Z and the Y correction.
	# A jittered/foreign projection must fall back, not sample this unjittered texture.
	var camera_projection := camera.get_camera_projection()
	if dimensions != logical_size and camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		camera_projection = Projection.create_perspective(
			camera.fov,
			float(dimensions.x) / dimensions.y,
			camera.near,
			camera.far,
			camera.keep_aspect == Camera3D.KEEP_WIDTH
		)
	elif dimensions != logical_size and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera_projection = Projection.create_orthogonal_aspect(
			camera.size,
			float(dimensions.x) / dimensions.y,
			camera.near,
			camera.far,
			camera.keep_aspect == Camera3D.KEEP_WIDTH
		)
	elif camera.projection == Camera3D.PROJECTION_FRUSTUM:
		# This engine's CPU getter omits KEEP_WIDTH for frustums; the renderer does not.
		camera_projection = Projection.create_frustum_aspect(
			camera.size,
			float(dimensions.x) / dimensions.y,
			camera.frustum_offset,
			camera.near,
			camera.far,
			camera.keep_aspect == Camera3D.KEEP_WIDTH
		)
	var projection := Projection.create_depth_correction(true) * camera_projection
	for material in consumers:
		_set_parameter(material, "u_npr_depth_camera_world", camera.get_camera_transform())
		_set_parameter(material, "u_npr_depth_projection", projection)
		_set_parameter(material, "u_npr_depth_viewport_size", Vector2(dimensions))
		_set_parameter(material, "u_npr_depth_layers", camera.cull_mask)
		_set_parameter(material, "u_npr_depth_pixel_size", Vector2.ONE / Vector2(logical_size))
		_set_parameter(material, "u_npr_contact_steps", 2 if tier == Quality.PERFORMANCE else 4)
	state_uploads += 1
	_range_dirty = true
	_dirty.assign([true, true])


func _prepare_pass(index: int) -> void:
	# Only demanded targets allocate their full render size and upload proxy state.
	if _camera_uploaded_states[index] != _camera_state:
		_camera_uploaded_states[index] = _camera_state
		viewports[index].size = _camera_state[2]
		viewports[index].mesh_lod_threshold = _camera_state[3]
		var copy := cameras[index]
		copy.global_transform = _camera_state[1]
		copy.force_update_transform()
		for key_index in range(CAMERA_KEYS.size()):
			copy.set(CAMERA_KEYS[key_index], _camera_state[key_index + 4])
		for proxy_index in range(proxies.size()):
			if _proxy_passes[proxy_index] == index:
				# Odd-size aspect correction happens after camera frustum culling.
				# Only four depth-only instances: don't lose a boundary mesh to that
				# slightly different frustum. Raster clipping still uses the right one.
				RenderingServer.instance_set_ignore_culling(
					proxies[proxy_index].get_instance(), _projection_scale != Vector2.ONE
				)
		state_uploads += 1
	for proxy_index in range(proxies.size()):
		if _proxy_passes[proxy_index] != index:
			continue
		var source_index := _proxy_indices[proxy_index]
		var state := _source_states[source_index]
		if state == _proxy_uploaded_states[proxy_index]:
			continue
		_proxy_uploaded_states[proxy_index] = state
		var proxy := proxies[proxy_index]
		proxy.mesh = _mesh_resources[source_index]
		proxy.visible = not state.is_empty() and state[1]
		if not state.is_empty():
			proxy.global_transform = state[0]
			# pre_draw is after the deferred Node3D transform flush.
			proxy.force_update_transform()
			proxy.lod_bias = state[2]
			_geometry[source_index].apply_to(proxy)
		state_uploads += 1


func _refresh_bounds_and_range() -> void:
	if not _bounds_dirty and not _range_dirty:
		return
	if _bounds_dirty:
		var initialized := false
		for state in _source_states:
			if state.is_empty():
				continue
			var bounds: AABB = state[0] * state[6]
			_bounds = _bounds.merge(bounds) if initialized else bounds
			var rest: AABB = state[0] * state[4]
			_rest_bounds = _rest_bounds.merge(rest) if initialized else rest
			initialized = true
		_bounds_dirty = false
	_range_dirty = false
	var new_range := maxf(
		(
			camera.get_camera_transform().origin.distance_to(_bounds.get_center())
			+ _bounds.size.length()
		),
		0.001
	)
	if new_range != depth_range or _published_height != _rest_bounds.size.y:
		depth_range = new_range
		_published_height = _rest_bounds.size.y
		for encode in _encoders:
			encode.set_shader_parameter("depth_range", depth_range)
		for material in consumers:
			_set_parameter(material, "u_npr_depth_range", depth_range)
			_set_parameter(material, "u_npr_character_height", _published_height)
		_dirty.assign([true, true])
		state_uploads += 1


func _source_visible(index: int) -> bool:
	var source := sources[index]
	return (
		is_instance_valid(source)
		and source.mesh != null
		and source.is_visible_in_tree()
		and (source.layers & camera.cull_mask) != 0
	)


func _positive(material: ShaderMaterial, parameter: StringName) -> bool:
	var value: Variant = material.get_shader_parameter(parameter)
	return value != null and float(value) > 0.0


func _publish_enabled(rim_enabled: bool, hair_enabled: bool = false) -> void:
	var flags := Vector2i(int(rim_enabled), int(hair_enabled))
	if _published_enabled == flags:
		return
	_published_enabled = flags
	for index in range(consumers.size()):
		# The face must not sample retained hair data when hair is hidden, even
		# if the body still needs its independent character-depth rim pass.
		_set_parameter(
			consumers[index], "u_npr_depth_enabled", hair_enabled if index == 1 else rim_enabled
		)


func _disable_viewport(index: int) -> void:
	if not is_instance_valid(viewports[index]):
		return
	if viewports[index].render_target_update_mode != SubViewport.UPDATE_DISABLED:
		viewports[index].render_target_update_mode = SubViewport.UPDATE_DISABLED


func _stop_all() -> void:
	_publish_enabled(false)
	requested_this_frame.assign([false, false])
	for index in range(viewports.size()):
		_disable_viewport(index)


func _exit_tree() -> void:
	_stop_all()
	if RenderingServer.frame_pre_draw.is_connected(synchronize):
		RenderingServer.frame_pre_draw.disconnect(synchronize)
	for index in range(_mesh_resources.size()):
		_disconnect_mesh(index)
	for material in consumers:
		_set_parameter(material, "u_npr_depth_enabled", false)
		_set_parameter(material, "u_npr_depth_viewport_size", Vector2.ZERO)
		_set_parameter(material, "u_npr_character_depth", null)
		_set_parameter(material, "u_npr_hair_depth", null)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Multiview depth targets may be parented under their consumer viewport.
		for viewport in viewports:
			if is_instance_valid(viewport) and viewport.get_parent() != self:
				viewport.free()
