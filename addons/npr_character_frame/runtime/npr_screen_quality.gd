class_name NPRScreenQuality
extends Node
## Opt-in per-actor budgets. Never changes expression, topology or outline width.
## Register every active view of this actor; the largest footprint wins.

signal quality_changed(tier: int)

const LABELS := ["远景", "中景", "近景"]
const RAIN_UPDATES := [8, 16, 32]
const AUXILIARY_SCALES := [0.25, 0.5, 1.0]

@export var near_pixels := 900.0
@export var middle_pixels := 350.0
@export_range(0.0, 0.4) var hysteresis := 0.15
@export_range(0.1, 2.0) var settle_seconds := 0.35

var enabled := false
var tier := 2
var pixel_height := 0.0
var transitions := 0
var cameras: Array[Camera3D] = []
var _actor: NPRCharacter
var _local_bounds: AABB
var _manual_depth := 2
var _manual_auxiliary_scale := 1.0
var _pending := -1
var _pending_time := 0.0
var _sample_time := 0.0


func setup(actor: NPRCharacter, views: Array[Camera3D] = []) -> void:
	_actor = actor
	cameras.assign(views)
	# Cache a conservative rest bound. Do not skin/read back every vertex per sample.
	_local_bounds = actor.global_transform.affine_inverse() * actor.get_world_bounds()
	_local_bounds = _local_bounds.grow(_local_bounds.size.y * 0.04)
	set_process(false)


func set_enabled(value: bool) -> void:
	if value == enabled or not is_instance_valid(_actor):
		return
	enabled = value
	_pending = -1
	_pending_time = 0.0
	_sample_time = 0.0
	if enabled:
		_manual_depth = _actor.depth_pass.quality
		_manual_auxiliary_scale = _actor.auxiliary_pass.resolution_scale
		tier = _manual_depth
		_actor.auxiliary_pass.resolution_scale = AUXILIARY_SCALES[tier]
	else:
		_actor.set_depth_quality(_manual_depth)
		_actor.auxiliary_pass.resolution_scale = _manual_auxiliary_scale
		tier = _manual_depth
	set_process(enabled)
	quality_changed.emit(tier)


func _process(delta: float) -> void:
	_sample_time += delta
	if _sample_time < 0.1:
		return
	evaluate(_sample_time)
	_sample_time = 0.0


func evaluate(delta: float) -> void:
	if not enabled or not is_instance_valid(_actor) or not _actor.is_inside_tree():
		return
	var views: Array[Camera3D] = cameras.duplicate()
	if views.is_empty():
		var current := _actor.get_viewport().get_camera_3d()
		if current != null:
			views.append(current)
	pixel_height = 0.0
	for camera in views:
		if is_instance_valid(camera) and camera.is_inside_tree():
			if camera.get_world_3d() == _actor.get_world_3d() and _visible_in(camera):
				pixel_height = maxf(
					pixel_height, projected_height(camera, _actor.global_transform, _local_bounds)
				)
	var desired := requested_tier(pixel_height)
	if desired == tier:
		_pending = -1
		_pending_time = 0.0
		return
	if _pending != desired:
		_pending = desired
		_pending_time = 0.0
	else:
		_pending_time += maxf(delta, 0.0)
	if _pending_time < settle_seconds:
		return
	tier = desired
	transitions += 1
	_pending = -1
	_actor.set_depth_quality(tier)
	_actor.auxiliary_pass.resolution_scale = AUXILIARY_SCALES[tier]
	quality_changed.emit(tier)


func _visible_in(camera: Camera3D) -> bool:
	for mesh in _actor.meshes:
		if mesh.is_visible_in_tree() and (mesh.layers & camera.cull_mask) != 0:
			return true
	return false


func requested_tier(height: float) -> int:
	if height >= near_pixels * (1.0 + hysteresis):
		return 2
	if tier == 2 and height >= near_pixels * (1.0 - hysteresis):
		return 2
	if height >= middle_pixels * (1.0 + hysteresis):
		return 1
	if tier >= 1 and height >= middle_pixels * (1.0 - hysteresis):
		return 1
	return 0


func budget() -> Dictionary:
	var dimensions: Vector2i = _actor.get_viewport().get_visible_rect().size
	var actual_tier: int = tier if enabled else _actor.depth_pass.quality
	var depth_scale := 1.0 if actual_tier == 2 else 0.5
	var depth_size := Vector2i((Vector2(dimensions) * depth_scale).ceil())
	var auxiliary_size := Vector2i(
		(Vector2(dimensions) * _actor.auxiliary_pass.resolution_scale).ceil()
	)
	return {
		"tier": tier,
		"pixel_height": pixel_height,
		"transitions": transitions,
		"depth_pixels_per_pass": depth_size.x * depth_size.y,
		"auxiliary_pixels":
		auxiliary_size.x * auxiliary_size.y if _actor.auxiliary_pass.enabled else 0,
		"rain_updates_per_frame": RAIN_UPDATES[tier]
	}


static func projected_height(camera: Camera3D, transform: Transform3D, bounds: AABB) -> float:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var near_count := 0
	var front_count := 0
	var view := camera.get_camera_transform().affine_inverse()
	for index in 8:
		var world := transform * bounds.get_endpoint(index)
		var depth := -(view * world).z
		if depth <= camera.near:
			near_count += 1
		if depth > 0.0:
			front_count += 1
		if depth <= camera.near:
			continue
		var point := camera.unproject_position(world)
		low = low.min(point)
		high = high.max(point)
	if front_count == 0:
		return 0.0
	if near_count > 0:
		return INF
	if not Rect2(low, high - low).intersects(camera.get_viewport().get_visible_rect()):
		return 0.0
	return maxf(high.y - low.y, 0.0)


func _exit_tree() -> void:
	if enabled:
		set_enabled(false)
