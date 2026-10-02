class_name NPRGeometryState
extends Node
## Source-owned geometry snapshot shared by depth/shadow proxies and surface picking.
## Bone matrices are the renderer's CPU palette, including final modifiers/skin scaling.

const PIXEL_OUTLINE = preload(
	"res://addons/npr_character_frame/shaders/face/face_outline_pixels.gdshader"
)
# TriangleMesh stores vertices snapped to 0.0001, not just welded hash keys.
# Keep that grid below ordinary float32 geometry precision, not ~1e-6 of the
# local bound's diagonal: that coarser grid can move thin foreground edges.
const PICK_NORMALIZED_EXTENT := 16384.0
const PICK_MAX_REFITS := 8

var source: MeshInstance3D
var role_index := 0
var revision := 0
var surface_revision := 0
var pick_build_count := 0
var pick_refit_count := 0
var local_bounds := AABB()
var rest_bounds := AABB()
var mask := Vector3i(255, 0, 0)
var skin_reference: SkinReference
var skeleton: Skeleton3D
var weights := PackedFloat32Array()
var _mesh: Mesh
var _shape_bounds: Array[AABB] = []
var _palette: Array[Transform3D] = []
var _state: Array = []
var _mesh_dirty := true
var _pose_dirty := true
var _max_weight_sum := 1.0
var _has_skinned_surface := false
var _has_unskinned_surface := false
var _shadow: MeshInstance3D
var _authored_aabb := AABB()
var _published_aabb: Variant = null
var _blend_mode := -1
var _surface_state: Array = []
var _pick_revision := -1
var _pick_mesh: TriangleMesh
var _pick_refit_age := 0
var _pick_topology_mask := Vector3i(-1, -1, -1)
var _pick_center := Vector3.ZERO
var _pick_scale := 1.0
var _pick_surfaces: Array[Dictionary] = []
var _surface_snapshots: Dictionary = {}
var _pick_inverse_transform := Transform3D.IDENTITY
var _pick_inverse := PackedFloat64Array()


static func attach(mesh_source: MeshInstance3D, kind: int) -> NPRGeometryState:
	var existing := mesh_source.get_node_or_null("NPRGeometryState") as NPRGeometryState
	if existing != null:
		return existing
	var helper := NPRGeometryState.new()
	helper.name = "NPRGeometryState"
	helper.source = mesh_source
	helper.role_index = kind
	mesh_source.add_child(helper)
	return helper


func _enter_tree() -> void:
	# _ready does not repeat after reparenting. Reconnect invalidation against
	# the current binding instead of retaining disconnected resource snapshots.
	_mesh = null
	skeleton = null
	skin_reference = null
	_mesh_dirty = true
	_pose_dirty = true
	_published_aabb = null
	RenderingServer.frame_pre_draw.connect(refresh)


func set_shadow_proxy(proxy: MeshInstance3D) -> void:
	_shadow = proxy
	_mesh_dirty = true


func refresh() -> void:
	if _published_aabb == null or source.custom_aabb != _published_aabb:
		_authored_aabb = source.custom_aabb
	if source.mesh != _mesh:
		if _mesh != null and _mesh.changed.is_connected(_invalidate_mesh):
			_mesh.changed.disconnect(_invalidate_mesh)
		_mesh = source.mesh
		if _mesh != null:
			_mesh.changed.connect(_invalidate_mesh)
		_mesh_dirty = true
	var binding := source.get_skin_reference()
	var next_skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D
	if next_skeleton != skeleton or binding != skin_reference:
		_disconnect_skeleton()
		skeleton = next_skeleton
		skin_reference = binding
		if skeleton != null:
			skeleton.skeleton_updated.connect(_invalidate_pose)
		_pose_dirty = true
	weights = PackedFloat32Array()
	for index in range(source.get_blend_shape_count() if _mesh != null else 0):
		weights.append(source.get_blend_shape_value(index))
	var blend_mode := (_mesh as ArrayMesh).blend_shape_mode if _mesh is ArrayMesh else -1
	if blend_mode != _blend_mode:
		_blend_mode = blend_mode
		# This engine changes Mesh mode without dirtying existing deformation buffers.
		# Re-submit even equal weights to refresh the source's actual GPU vertices.
		for index in range(weights.size()):
			source.set_blend_shape_value(index, weights[index])
	mask = _read_mask()
	var chain: Array[ShaderMaterial] = []
	var material := source.get_active_material(0) as ShaderMaterial if _mesh != null else null
	while material != null:
		chain.append(material)
		material = material.next_pass as ShaderMaterial
	var state: Array = [
		source.global_transform,
		source.visible,
		source.layers,
		source.lod_bias,
		_authored_aabb,
		source.extra_cull_margin,
		weights,
		mask,
		skin_reference,
		chain,
		# ArrayMesh.set_blend_shape_mode does not emit Resource.changed in this engine.
		_blend_mode
	]
	if state == _state and not _mesh_dirty and not _pose_dirty:
		return
	var changed := state != _state or _mesh_dirty
	var palette_changed := false
	if _pose_dirty:
		var palette: Array[Transform3D] = []
		if skin_reference != null:
			var rid := skin_reference.get_skeleton()
			for index in range(RenderingServer.skeleton_get_bone_count(rid)):
				palette.append(RenderingServer.skeleton_bone_get_transform(rid, index))
		palette_changed = palette != _palette
		changed = changed or palette_changed
		_palette = palette
		_pose_dirty = false
	if not changed:
		return
	_state = state
	# A local-space BVH does not depend on node transforms, visibility, or camera.
	# Keep its invalidation separate from the broader proxy synchronization revision.
	var surface_state: Array = [weights, mask, _blend_mode]
	if _mesh_dirty or palette_changed or surface_state != _surface_state:
		surface_revision += 1
		_surface_state = surface_state
	if _mesh_dirty:
		_pick_surfaces.clear()
		_surface_snapshots.clear()
		_pick_mesh = null
		_cache_bounds()
	local_bounds = _deformed_bounds()
	# Color-pass culling must agree too, especially for BlendShapes outside rest bounds.
	_published_aabb = (
		local_bounds if not weights.is_empty() or skin_reference != null else _authored_aabb
	)
	if source.custom_aabb != _published_aabb:
		source.custom_aabb = _published_aabb
	revision += 1
	_mesh_dirty = false
	_pose_dirty = false
	for item in chain:
		if item.shader == PIXEL_OUTLINE:
			item.set_shader_parameter("geometry_mask", mask)
	if is_instance_valid(_shadow):
		apply_to(_shadow)


func apply_to(proxy: MeshInstance3D) -> void:
	if proxy.mesh != _mesh:
		proxy.mesh = _mesh
	var skin: Skin = skin_reference.get_skin() if skin_reference != null else null
	var path := skeleton.get_path() if is_instance_valid(skeleton) and skin != null else NodePath()
	if proxy.skin != skin:
		proxy.skin = skin
	if proxy.skeleton != path:
		proxy.skeleton = path
	var mode_changed: bool = proxy.get_meta(&"_npr_blend_mode", -2) != _blend_mode
	if mode_changed:
		proxy.set_meta(&"_npr_blend_mode", _blend_mode)
	for index in range(weights.size()):
		if mode_changed or proxy.get_blend_shape_value(index) != weights[index]:
			proxy.set_blend_shape_value(index, weights[index])
	if proxy.get_parent() == source:
		# Avoid inverse(parent) * parent roundoff on the child shadow caster.
		proxy.transform = Transform3D.IDENTITY
		proxy.layers = source.layers
	else:
		proxy.global_transform = source.global_transform
	proxy.force_update_transform()
	proxy.lod_bias = source.lod_bias
	proxy.extra_cull_margin = source.extra_cull_margin
	# The renderer's default AABB does not account for arbitrary BlendShape weights.
	proxy.custom_aabb = (local_bounds if not weights.is_empty() or skin != null else _authored_aabb)
	var material := proxy.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("geometry_mask", mask)


## Return selected source-local vertices using the same decoded renderer weights,
## blend shapes and final skin palette as picking. Invalid requests fail atomically.
func sample_surface_vertices(surface: int, indices: PackedInt32Array) -> PackedVector3Array:
	refresh()
	if _mesh == null or surface < 0 or surface >= _mesh.get_surface_count() or indices.is_empty():
		return PackedVector3Array()
	var data := _surface_snapshot(surface)
	var count: int = data.arrays[Mesh.ARRAY_VERTEX].size()
	for index in indices:
		if index < 0 or index >= count:
			return PackedVector3Array()
	return _pick_vertices(data, indices)


func intersect_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	refresh()
	if (
		_mesh == null
		or direction.length_squared() == 0.0
		or not origin.is_finite()
		or not direction.is_finite()
		or ((mask.y != 0 or mask.z != 0) and mask.x == 0)
	):
		return {}
	var material := source.get_active_material(0) as ShaderMaterial
	if (
		bool(_parameter(material, "u_reflection_flag", false))
		if role_index == 0
		else bool(_instance_parameter("u_use_special_transform", false))
	):
		# Arbitrary clip-space placement has no unambiguous physical world-space hit.
		return {}
	var transform := source.global_transform
	if not transform.is_finite() or transform.basis.determinant() == 0.0:
		return {}
	var ray := _pick_inverse_ray(transform, origin, direction)
	if ray.is_empty():
		return {}
	var local_origin := Vector3(ray[0], ray[1], ray[2])
	var local_direction := Vector3(ray[3], ray[4], ray[5])
	var hit := {}
	# Reject misses before CPU deformation/BVH construction. This conservative
	# animated bound is shared with the renderer, not the stale import AABB.
	if (
		local_bounds.has_point(local_origin)
		or local_bounds.intersects_ray(local_origin, local_direction) != null
	):
		if _pick_revision != surface_revision:
			_rebuild_pick_mesh()
		if _pick_mesh != null:
			# Do not round the local origin to Vector3 before centering/scaling.
			# That can move a ray across a thin edge even when the BVH is precise.
			var normalized_origin := Vector3(
				(ray[0] - _pick_center.x) * _pick_scale,
				(ray[1] - _pick_center.y) * _pick_scale,
				(ray[2] - _pick_center.z) * _pick_scale
			)
			hit = _pick_mesh.intersect_ray(normalized_origin, local_direction)
	if hit.is_empty():
		return {}
	var point: Vector3 = transform * (hit.position / _pick_scale + _pick_center)
	return {"position": point, "distance": origin.distance_to(point), "mesh": source.name}


func _pick_inverse_ray(
	transform: Transform3D, origin: Vector3, direction: Vector3
) -> PackedFloat64Array:
	# Vector3/Basis use real_t=float in this engine; GDScript scalar float and this
	# packed array preserve double intermediates. Cache the inverse, not the ray.
	if _pick_inverse.is_empty() or transform != _pick_inverse_transform:
		var a: float = transform.basis.x.x
		var b: float = transform.basis.y.x
		var c: float = transform.basis.z.x
		var d: float = transform.basis.x.y
		var e: float = transform.basis.y.y
		var f: float = transform.basis.z.y
		var g: float = transform.basis.x.z
		var h: float = transform.basis.y.z
		var i: float = transform.basis.z.z
		var inverse := PackedFloat64Array(
			[
				e * i - f * h,
				c * h - b * i,
				b * f - c * e,
				f * g - d * i,
				a * i - c * g,
				c * d - a * f,
				d * h - e * g,
				b * g - a * h,
				a * e - b * d
			]
		)
		var determinant: float = a * inverse[0] + b * inverse[3] + c * inverse[6]
		if determinant == 0.0:
			return PackedFloat64Array()
		for index in range(9):
			inverse[index] /= determinant
		_pick_inverse = inverse
		_pick_inverse_transform = transform
	var x: float = float(origin.x) - float(transform.origin.x)
	var y: float = float(origin.y) - float(transform.origin.y)
	var z: float = float(origin.z) - float(transform.origin.z)
	var ray := PackedFloat64Array()
	ray.resize(6)
	for row in range(3):
		var index := row * 3
		ray[row] = (
			_pick_inverse[index] * x + _pick_inverse[index + 1] * y + _pick_inverse[index + 2] * z
		)
		ray[row + 3] = (
			_pick_inverse[index] * float(direction.x)
			+ _pick_inverse[index + 1] * float(direction.y)
			+ _pick_inverse[index + 2] * float(direction.z)
		)
	var length_squared := ray[3] * ray[3] + ray[4] * ray[4] + ray[5] * ray[5]
	if length_squared == 0.0:
		return PackedFloat64Array()
	var inverse_length := 1.0 / sqrt(length_squared)
	for index in range(3, 6):
		ray[index] *= inverse_length
	return ray


func _rebuild_pick_mesh() -> void:
	_pick_revision = surface_revision
	pick_build_count += 1
	var previous := _pick_mesh
	_pick_mesh = null
	if _pick_surfaces.is_empty():
		for surface in range(_mesh.get_surface_count()):
			if _mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			_pick_surfaces.append(_surface_snapshot(surface))
	# Normalize BEFORE TriangleMesh's weld and ray epsilon. The face's imported
	# coordinates are tiny; Mesh.get_faces() would already lose triangles.
	_pick_center = local_bounds.get_center()
	_pick_scale = PICK_NORMALIZED_EXTENT / maxf(local_bounds.size.length(), 0.000001)
	# Keep subtraction and scaling separate (including float32 intermediates).
	# One combined affine transform would change rounding at thin triangle edges.
	var center_transform := Transform3D(Basis.IDENTITY, -_pick_center)
	var scale_transform := Transform3D(Basis.from_scale(Vector3.ONE * _pick_scale), Vector3.ZERO)
	var candidate := previous if previous != null else TriangleMesh.new()
	var indexed := candidate.has_method("update_from_indexed_surfaces")
	var normalized: ArrayMesh
	if not indexed:
		normalized = ArrayMesh.new()
	var vertex_arrays: Array = []
	var index_arrays: Array = []
	for data in _pick_surfaces:
		var indices := _pick_surface_indices(data)
		if indices.is_empty():
			continue
		var vertices := _pick_vertices(data)
		if vertices.is_empty():
			continue
		vertices = center_transform * vertices
		vertices = scale_transform * vertices
		if indexed:
			vertex_arrays.append(vertices)
			index_arrays.append(indices)
			continue
		# Older engines retain the indexed ArrayMesh bridge, with identical rounding.
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		normalized.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if indexed and not index_arrays.is_empty():
		# Refit only a retained partition with unchanged semantic topology. Mesh
		# edits clear _pick_mesh in refresh(); masks may reorder/filter its faces.
		var refitting := (
			previous != null and _pick_topology_mask == mask and _pick_refit_age < PICK_MAX_REFITS
		)
		var updated: bool = candidate.call(
			"update_from_indexed_surfaces", vertex_arrays, index_arrays, refitting
		)
		if not updated and refitting:
			refitting = false
			updated = candidate.call("update_from_indexed_surfaces", vertex_arrays, index_arrays)
		if updated:
			_pick_mesh = candidate
			_pick_topology_mask = mask
			_pick_refit_age = _pick_refit_age + 1 if refitting else 0
			pick_refit_count += int(refitting)
	elif not indexed and normalized.get_surface_count() > 0:
		_pick_mesh = normalized.generate_triangle_mesh()


func _surface_snapshot(surface: int) -> Dictionary:
	# Bounds already decode skinned/shaped surfaces. Reuse that immutable snapshot
	# for picking instead of decoding the same renderer buffers again on first use.
	# Plain unskinned surfaces remain lazy; mesh changes invalidate both consumers.
	if not _surface_snapshots.has(surface):
		var arrays: Array
		var shapes: Array
		if (
			RenderingServer.has_method("mesh_surface_get_geometry_arrays")
			and RenderingServer.has_method("mesh_surface_get_geometry_blend_shape_arrays")
		):
			# Avoid allocating unused decoded attributes, not merely retaining them.
			var mesh_rid := _mesh.get_rid()
			arrays = RenderingServer.call("mesh_surface_get_geometry_arrays", mesh_rid, surface)
			shapes = RenderingServer.call(
				"mesh_surface_get_geometry_blend_shape_arrays", mesh_rid, surface
			)
		else:
			# The original supplied engine still needs the full-decode fallback.
			arrays = _mesh.surface_get_arrays(surface)
			for slot in range(Mesh.ARRAY_MAX):
				if (
					slot
					not in [
						Mesh.ARRAY_VERTEX,
						Mesh.ARRAY_COLOR,
						Mesh.ARRAY_BONES,
						Mesh.ARRAY_WEIGHTS,
						Mesh.ARRAY_INDEX
					]
				):
					arrays[slot] = null
			shapes = _mesh.surface_get_blend_shape_arrays(surface)
			for shape in shapes:
				for slot in range(1, Mesh.ARRAY_MAX):
					shape[slot] = null
		_surface_snapshots[surface] = {
			"arrays": arrays,
			"shapes": shapes,
		}
	return _surface_snapshots[surface]


func _pick_surface_indices(data: Dictionary) -> PackedInt32Array:
	# Pose/shape changes move vertices, not their indices or vertex part IDs.
	# Mesh changes clear the entire surface cache; only mask changes re-filter it.
	if data.get("pick_mask") == mask:
		return data.pick_indices
	var indices := PackedInt32Array()
	if data.arrays[Mesh.ARRAY_INDEX] != null:
		indices = data.arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	if indices.is_empty():
		indices.resize(vertices.size() - vertices.size() % 3)
		for index in range(indices.size()):
			indices[index] = index
	if mask.y != 0 or mask.z != 0:
		var colors := PackedColorArray()
		if data.arrays[Mesh.ARRAY_COLOR] != null:
			colors = data.arrays[Mesh.ARRAY_COLOR]
		var visible := PackedByteArray()
		visible.resize(vertices.size())
		for vertex in range(vertices.size()):
			var color := colors[vertex] if not colors.is_empty() else Color.WHITE
			var value := color.g if mask.y != 0 else color.r
			visible[vertex] = int((int(value * 256.0) & mask.x) != 0)
		var filtered := PackedInt32Array()
		for triangle in range(0, indices.size() - 2, 3):
			var a := indices[triangle]
			var b := indices[triangle + 1]
			var c := indices[triangle + 2]
			if visible[a] and visible[b] and visible[c]:
				filtered.append(a)
				filtered.append(b)
				filtered.append(c)
		indices = filtered
	data.pick_mask = mask
	data.pick_indices = indices
	return indices


func _pick_vertices(data: Dictionary, indices := PackedInt32Array()) -> PackedVector3Array:
	var base: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	var selected := not indices.is_empty()
	var vertices := PackedVector3Array()
	if selected:
		vertices.resize(indices.size())
		for at in indices.size():
			vertices[at] = base[indices[at]]
	else:
		vertices = base.duplicate()
	var total := 0.0
	for weight in weights:
		if absf(weight) > 0.0001:
			total += weight
	if _blend_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED and total != 0.0:
		for index in range(vertices.size()):
			vertices[index] *= 1.0 - total
	for shape in range(weights.size()):
		if absf(weights[shape]) <= 0.0001:
			continue
		var points: PackedVector3Array = data.shapes[shape][Mesh.ARRAY_VERTEX]
		for index in range(vertices.size()):
			vertices[index] += points[indices[index] if selected else index] * weights[shape]
	if _palette.is_empty() or data.arrays[Mesh.ARRAY_BONES] == null:
		return vertices
	var bones: PackedInt32Array = data.arrays[Mesh.ARRAY_BONES]
	if bones.is_empty():
		return vertices
	# These are decoded renderer weights (including UNORM16 quantization), not
	# normalized authoring values. The palette includes final modifiers and binds.
	var skin_weights: PackedFloat32Array = data.arrays[Mesh.ARRAY_WEIGHTS]
	var stride := bones.size() / base.size()
	var bone_count := _palette.size()
	for index in range(vertices.size()):
		var point := vertices[index]
		# Preserve slot order and float32 Vector3 rounding, but accumulate locally:
		# repeated packed-array reads/writes dominate the sparse 4/8-slot VM loop.
		var skinned := Vector3.ZERO
		var start := (indices[index] if selected else index) * stride
		for at in range(start, start + stride):
			var weight := skin_weights[at]
			if weight == 0.0:
				continue
			var bone := bones[at]
			if bone >= bone_count:
				return PackedVector3Array()
			skinned += (_palette[bone] * point) * weight
		vertices[index] = skinned
	return vertices


func _read_mask() -> Vector3i:
	var material := source.get_active_material(0) as ShaderMaterial if _mesh != null else null
	if role_index == 0:
		return Vector3i(
			int(_parameter(material, "u_part_mask_visible", 255)),
			int(_parameter(material, "u_hide_parts_flag", false)),
			0
		)
	return Vector3i(
		int(_instance_parameter("u_show_part_id", 255)),
		int(_instance_parameter("u_hide_character_parts", false)),
		int(_parameter(material, "u_hide_npc_parts", false)) if role_index == 2 else 0
	)


func _parameter(material: ShaderMaterial, key: StringName, fallback: Variant) -> Variant:
	var value: Variant = material.get_shader_parameter(key) if material != null else null
	return fallback if value == null else value


func _instance_parameter(key: StringName, fallback: Variant) -> Variant:
	var value: Variant = source.get_instance_shader_parameter(key)
	return fallback if value == null else value


func _cache_bounds() -> void:
	_shape_bounds.clear()
	_max_weight_sum = 1.0
	_has_skinned_surface = false
	_has_unskinned_surface = false
	if _mesh == null:
		rest_bounds = AABB()
		return
	rest_bounds = _mesh.get_aabb()
	_shape_bounds.resize(_mesh.get_blend_shape_count())
	var initialized: Array[bool] = []
	initialized.resize(_shape_bounds.size())
	var base_initialized := false
	for surface in range(_mesh.get_surface_count()):
		var skinned := bool(_mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_BONES)
		_has_skinned_surface = _has_skinned_surface or skinned
		_has_unskinned_surface = _has_unskinned_surface or not skinned
		if _shape_bounds.is_empty() and not skinned:
			continue
		var data := _surface_snapshot(surface)
		var arrays: Array = data.arrays
		if not _shape_bounds.is_empty():
			# Mesh.get_aabb() already unions shape endpoints. Weight the true base
			# vertices instead, otherwise extrapolation greatly inflates depth ranges.
			var base_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for point in base_vertices:
				rest_bounds = (
					rest_bounds.expand(point) if base_initialized else AABB(point, Vector3.ZERO)
				)
				base_initialized = true
		var bone_weights := PackedFloat32Array()
		if arrays[Mesh.ARRAY_WEIGHTS] != null:
			bone_weights = arrays[Mesh.ARRAY_WEIGHTS]
		var bone_count := (
			8 if (_mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
		)
		for vertex in range(0, bone_weights.size(), bone_count):
			var total := 0.0
			for component in range(bone_count):
				total += clampf(bone_weights[vertex + component], 0.0, 1.0)
			_max_weight_sum = maxf(_max_weight_sum, total + bone_count / 65535.0)
		var shapes: Array = data.shapes
		for shape in range(shapes.size()):
			var vertices: PackedVector3Array = shapes[shape][Mesh.ARRAY_VERTEX]
			for point in vertices:
				_shape_bounds[shape] = (
					_shape_bounds[shape].expand(point)
					if initialized[shape]
					else AABB(point, Vector3.ZERO)
				)
				initialized[shape] = true


func _deformed_bounds() -> AABB:
	if _mesh == null:
		return AABB()
	var total := 0.0
	for weight in weights:
		if absf(weight) > 0.0001:
			total += weight
	var array_mesh := _mesh as ArrayMesh
	var normalized := (
		array_mesh != null and array_mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	)
	var base_weight := 1.0 - total if normalized else 1.0
	var bounds := _scaled_bounds(rest_bounds, base_weight)
	for index in range(weights.size()):
		if absf(weights[index]) <= 0.0001:
			continue
		var shape := _scaled_bounds(_shape_bounds[index], weights[index])
		# Minkowski interval SUM, not a union of poses: GPU adds weighted positions.
		# This also handles relative shapes and normalized weights outside [0, 1].
		bounds = AABB(bounds.position + shape.position, bounds.size + shape.size)
	if _has_skinned_surface and not _palette.is_empty():
		# Union of all bind transforms encloses every weighted vertex. Including zero
		# and the measured maximum weight sum also covers non-normalized skin weights.
		var skinned := AABB()
		for transform in _palette:
			skinned = skinned.merge(transform * bounds)
		skinned = _scaled_bounds(skinned, _max_weight_sum)
		# An attached SkinReference does not skin surfaces without bone attributes.
		# Preserve their local envelope when a mesh mixes both surface formats.
		bounds = skinned.merge(bounds) if _has_unskinned_surface else skinned
	if _authored_aabb != AABB():
		bounds = bounds.merge(_authored_aabb)
	return bounds


func _scaled_bounds(bounds: AABB, factor: float) -> AABB:
	var low := bounds.position * factor
	var high := bounds.end * factor
	return AABB(low.min(high), (high - low).abs())


func _invalidate_mesh() -> void:
	_mesh_dirty = true


func _invalidate_pose() -> void:
	_pose_dirty = true


func _disconnect_skeleton() -> void:
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_invalidate_pose):
		skeleton.skeleton_updated.disconnect(_invalidate_pose)


func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(refresh)
	_disconnect_skeleton()
	if _mesh != null and _mesh.changed.is_connected(_invalidate_mesh):
		_mesh.changed.disconnect(_invalidate_mesh)
	if is_instance_valid(source) and source.custom_aabb == _published_aabb:
		source.custom_aabb = _authored_aabb
