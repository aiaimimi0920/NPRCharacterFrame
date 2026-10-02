class_name NPRDepthGroupStorage
extends RefCounted
## Render-thread-owned grouped depth storage.
##
## Each planner group owns one Texture2DArray and one readiness array. The
## replacement is transactional: new groups are fully allocated and copied
## before the previous groups are released. Shader publication is deliberately
## left to the transport layer because a grouped layout needs an explicit
## sampler mapping policy.

const ARRAY = preload("res://addons/npr_character_frame/runtime/npr_depth_array.gd")
const FLAGS = preload("res://addons/npr_character_frame/runtime/npr_depth_view_flags.gd")

var compact := false
var max_payload_bytes := 128 * 1024 * 1024
var max_live_payload_bytes := 256 * 1024 * 1024
var resident_payload_bytes := 0
var peak_live_payload_bytes := 0
var allocation_count := 0
var copy_count := 0
var generation := 0
var groups: Array[Dictionary] = []
var views: Array[Dictionary] = []
var _ready: Array[bool] = []


func replace(sources: Array[RID], sizes: Array[Vector2i], plan: Dictionary) -> Error:
	var validation := _validate_inputs(sources, sizes, plan)
	if validation.error != OK:
		return validation.error
	var planned_groups: Array = validation.groups
	var planned_views: Array = validation.views
	var requested: int = validation.requested
	var live: int = validation.live

	var next_groups: Array[Dictionary] = []
	var next_views: Array[Dictionary] = []
	next_views.resize(planned_views.size())
	var next_ready: Array[bool] = []
	next_ready.resize(planned_views.size())
	var next_payload := 0
	var error := OK
	for group_index in range(planned_groups.size()):
		if error != OK:
			break
		var planned: Dictionary = planned_groups[group_index]
		var indices: Array = planned.get("view_indices", [])
		if indices.is_empty():
			error = ERR_INVALID_PARAMETER
			break
		var group_sources: Array[RID] = []
		for view_index in indices:
			if not view_index is int or view_index < 0 or view_index >= planned_views.size():
				error = ERR_INVALID_PARAMETER
				break
			var view: Dictionary = planned_views[view_index]
			if int(view.get("group", -1)) != group_index:
				error = ERR_INVALID_PARAMETER
				break
			var body: Vector2i = view.get("body_size", Vector2i.ZERO)
			var hair: Vector2i = view.get("hair_size", Vector2i.ZERO)
			if sizes[view_index * 2] != body or sizes[view_index * 2 + 1] != hair:
				error = ERR_INVALID_PARAMETER
				break
			group_sources.append(sources[view_index * 2])
			group_sources.append(sources[view_index * 2 + 1])
		if error != OK:
			break
		var storage := ARRAY.new()
		storage.compact = compact
		storage.max_payload_bytes = int(planned.get("payload_bytes", 0))
		storage.max_live_payload_bytes = storage.max_payload_bytes
		error = storage.replace(group_sources)
		if error != OK:
			storage.release()
			break
		var flags := FLAGS.new()
		error = flags.reset(indices.size())
		if error != OK:
			storage.release()
			break
		next_groups.append(
			{
				"array": storage,
				"flags": flags,
				"extent": planned.get("extent", Vector2i.ZERO),
				"view_indices": indices.duplicate(),
				"base": 0
			}
		)
		next_payload += storage.resident_payload_bytes
		# The planner's view order is global; remap the temporary append order below.
		for view_index in indices:
			var local_index: int = indices.find(view_index)
			next_views[view_index] = {
				"group": group_index,
				"local_index": local_index,
				"base": local_index * 2,
				"body_size": planned_views[view_index].body_size,
				"hair_size": planned_views[view_index].hair_size,
				"extent": planned_views[view_index].extent
			}

	if error != OK:
		_release_groups(next_groups)
		return error
	if next_payload != requested:
		_release_groups(next_groups)
		return ERR_INVALID_DATA
	var old_groups := groups
	groups = next_groups
	views = next_views
	_ready = next_ready
	resident_payload_bytes = next_payload
	peak_live_payload_bytes = maxi(peak_live_payload_bytes, live)
	allocation_count += 1
	generation += 1
	copy_count = 0
	for group in groups:
		copy_count += group.array.copy_count
	_release_groups(old_groups)
	return OK


func _validate_inputs(sources: Array[RID], sizes: Array[Vector2i], plan: Dictionary) -> Dictionary:
	var error := OK
	if sources.is_empty() or sources.size() != sizes.size() or sources.size() % 2 != 0:
		error = ERR_INVALID_PARAMETER
	var plan_error := int(plan.get("error", ERR_INVALID_PARAMETER))
	if error == OK and plan_error != OK:
		error = plan_error
	var planned_groups: Array = plan.get("groups", [])
	var planned_views: Array = plan.get("views", [])
	if error == OK and (planned_groups.is_empty() or planned_views.size() * 2 != sources.size()):
		error = ERR_INVALID_PARAMETER
	var requested := int(plan.get("requested_payload_bytes", -1))
	if error == OK and (requested < 0 or requested > max_payload_bytes):
		error = ERR_OUT_OF_MEMORY
	var live := resident_payload_bytes + requested
	if error == OK and live > max_live_payload_bytes:
		error = ERR_OUT_OF_MEMORY
	return {
		"error": error,
		"groups": planned_groups,
		"views": planned_views,
		"requested": requested,
		"live": live
	}


func update_view(view_index: int, sources: Array[RID]) -> Error:
	if view_index < 0 or view_index >= views.size() or sources.size() != 2:
		return ERR_INVALID_PARAMETER
	var binding: Dictionary = views[view_index]
	var group: Dictionary = groups[int(binding.group)]
	var flags: RefCounted = group.flags
	var local_index: int = binding.local_index
	var epoch: int = flags.epoch
	var error: Error = flags.set_ready(local_index, epoch, false)
	if error != OK:
		_ready[view_index] = false
		return error
	var storage: RefCounted = group.array
	error = storage.update_layers(sources, PackedInt32Array([binding.base, binding.base + 1]))
	if error != OK:
		_ready[view_index] = false
		return error
	copy_count += 2
	error = flags.set_ready(local_index, epoch, true)
	_ready[view_index] = error == OK
	return error


func invalidate_view(view_index: int) -> Error:
	if view_index < 0 or view_index >= views.size():
		return ERR_INVALID_PARAMETER
	var binding: Dictionary = views[view_index]
	var group: Dictionary = groups[int(binding.group)]
	var flags: RefCounted = group.flags
	var error: Error = flags.set_ready(binding.local_index, flags.epoch, false)
	_ready[view_index] = false
	return error


func view_binding(view_index: int) -> Dictionary:
	if view_index < 0 or view_index >= views.size():
		return {}
	var binding: Dictionary = views[view_index].duplicate(true)
	var group: Dictionary = groups[int(binding.group)]
	binding["array"] = group.array
	binding["flags"] = group.flags
	binding["array_resource"] = group.array.resource
	binding["flags_resource"] = group.flags.resource
	binding["epoch"] = group.flags.epoch
	binding["ready"] = _ready[view_index]
	return binding


func status() -> Dictionary:
	var group_status: Array[Dictionary] = []
	for group in groups:
		var storage: RefCounted = group.array
		group_status.append(
			{
				"extent": group.extent,
				"view_indices": group.view_indices.duplicate(),
				"resident_payload_bytes": storage.resident_payload_bytes,
				"layers": storage.layer_sizes.size(),
				"epoch": group.flags.epoch
			}
		)
	return {
		"error": OK,
		"group_count": groups.size(),
		"view_count": views.size(),
		"resident_payload_bytes": resident_payload_bytes,
		"peak_live_payload_bytes": peak_live_payload_bytes,
		"allocation_count": allocation_count,
		"copy_count": copy_count,
		"generation": generation,
		"ready_views": _ready.count(true),
		"groups": group_status
	}


func release() -> void:
	_release_groups(groups)
	groups.clear()
	views.clear()
	_ready.clear()
	resident_payload_bytes = 0
	generation += 1


func _release_groups(value: Array) -> void:
	for group in value:
		var flags: RefCounted = group.get("flags")
		var storage: RefCounted = group.get("array")
		if flags != null:
			flags.release()
		if storage != null:
			storage.release()
