class_name NPRDepthGroupPlan
extends RefCounted
## Deterministic CPU contract for grouping multi-view depth layers by extent.
## This planner does not allocate GPU resources; it is the admission contract
## consumed by a future grouped Texture2DArray transport.

const DEFAULT_LAYER_LIMIT := 2048
const DEFAULT_ROW_LIMIT := 4096


static func build(
	sizes: Array[Vector2i],
	bytes_per_pixel: int,
	payload_limit: int,
	live_limit: int,
	resident_payload_bytes := 0,
	layer_limit := DEFAULT_LAYER_LIMIT,
	row_limit := DEFAULT_ROW_LIMIT,
	max_group_count := 0
) -> Dictionary:
	var result := {
		"error": OK,
		"capacity_rejection": "",
		"groups": [],
		"views": [],
		"requested_payload_bytes": 0,
		"requested_live_payload_bytes": resident_payload_bytes,
		"source_payload_bytes": 0,
		"legacy_shared_payload_bytes": 0,
		"padding_bytes_saved": 0,
		"group_count": 0,
		"requested_layers": sizes.size(),
		"device_max_layers": layer_limit,
		"metadata_rows": sizes.size() / 2,
		"max_group_count": max_group_count,
		"bytes_per_pixel": bytes_per_pixel,
		"coalesced_groups": 0
	}
	if bytes_per_pixel <= 0 or payload_limit < 0 or live_limit < 0:
		return _reject(result, ERR_INVALID_PARAMETER, "invalid_budget")
	if sizes.is_empty() or sizes.size() % 2 != 0:
		return _reject(result, ERR_INVALID_PARAMETER, "odd_layer_count")
	if sizes.size() > layer_limit:
		return _reject(result, ERR_OUT_OF_MEMORY, "device_layers")
	if sizes.size() / 2 > row_limit:
		return _reject(result, ERR_OUT_OF_MEMORY, "metadata_rows")

	var groups: Array[Dictionary] = []
	var views: Array[Dictionary] = []
	for view_index in range(sizes.size() / 2):
		var body := sizes[view_index * 2]
		var hair := sizes[view_index * 2 + 1]
		if body.x <= 0 or body.y <= 0 or hair.x <= 0 or hair.y <= 0:
			return _reject(result, ERR_INVALID_PARAMETER, "invalid_extent")
		var extent := Vector2i(maxi(body.x, hair.x), maxi(body.y, hair.y))
		var group_index := _find_group(groups, extent)
		if group_index < 0:
			group_index = groups.size()
			groups.append({"extent": extent, "view_indices": [], "layers": 0, "payload_bytes": 0})
		var group: Dictionary = groups[group_index]
		var base := int(group.layers)
		group.view_indices.append(view_index)
		group.layers = base + 2
		group.payload_bytes = int(group.layers) * extent.x * extent.y * bytes_per_pixel
		groups[group_index] = group
		views.append(
			{
				"group": group_index,
				"base": base,
				"body_size": body,
				"hair_size": hair,
				"extent": extent
			}
		)
		if max_group_count > 0 and groups.size() > max_group_count:
			return _reject(result, ERR_OUT_OF_MEMORY, "group_count")

	var requested := 0
	var source_bytes := 0
	var legacy_extent := Vector2i.ZERO
	for view_index in range(views.size()):
		var view: Dictionary = views[view_index]
		var extent: Vector2i = view.extent
		requested += extent.x * extent.y * 2 * bytes_per_pixel
		var body: Vector2i = view.body_size
		var hair: Vector2i = view.hair_size
		source_bytes += body.x * body.y * bytes_per_pixel
		source_bytes += hair.x * hair.y * bytes_per_pixel
		legacy_extent.x = maxi(legacy_extent.x, extent.x)
		legacy_extent.y = maxi(legacy_extent.y, extent.y)
	var legacy_shared := legacy_extent.x * legacy_extent.y * sizes.size() * bytes_per_pixel
	result.source_payload_bytes = source_bytes
	result.legacy_shared_payload_bytes = legacy_shared
	result.requested_payload_bytes = requested
	result.requested_live_payload_bytes = resident_payload_bytes + requested
	result.groups = groups
	result.views = views
	result.group_count = groups.size()
	result.padding_bytes_saved = maxi(legacy_shared - requested, 0)

	if requested > payload_limit:
		return _reject(result, ERR_OUT_OF_MEMORY, "payload_budget")
	if resident_payload_bytes + requested > live_limit:
		return _reject(result, ERR_OUT_OF_MEMORY, "replacement_overlap_budget")
	return result


## Merge extent groups until at most `group_limit` remain so a fixed set of
## group samplers can still serve more distinct view sizes. Each merge pads the
## smaller extent up to the union extent; the pair with the least added padding
## is merged first, ties resolved by group order, so the result is deterministic.
## The merged payload never exceeds the legacy single-extent payload.
static func coalesce(
	plan: Dictionary,
	group_limit: int,
	payload_limit: int,
	live_limit: int,
	resident_payload_bytes := 0
) -> Dictionary:
	if plan.get("error", ERR_INVALID_PARAMETER) != OK or group_limit <= 0:
		return plan
	if int(plan.get("group_count", 0)) <= group_limit:
		return plan
	var bytes_per_pixel := int(plan.get("bytes_per_pixel", 0))
	if bytes_per_pixel <= 0:
		return _reject(plan.duplicate(true), ERR_INVALID_PARAMETER, "invalid_budget")
	var groups: Array[Dictionary] = []
	for group in plan.groups:
		groups.append(group.duplicate(true))
	var merged := 0
	while groups.size() > group_limit:
		var best_first := -1
		var best_second := -1
		var best_cost := 0
		for first in range(groups.size()):
			for second in range(first + 1, groups.size()):
				var union := _union(groups[first].extent, groups[second].extent)
				var layers := int(groups[first].layers) + int(groups[second].layers)
				var cost := (
					layers * union.x * union.y * bytes_per_pixel
					- int(groups[first].payload_bytes)
					- int(groups[second].payload_bytes)
				)
				if best_first < 0 or cost < best_cost:
					best_first = first
					best_second = second
					best_cost = cost
		var target: Dictionary = groups[best_first]
		var source: Dictionary = groups[best_second]
		var indices: Array = target.view_indices.duplicate()
		indices.append_array(source.view_indices)
		indices.sort()
		var extent := _union(target.extent, source.extent)
		var layers := int(target.layers) + int(source.layers)
		groups[best_first] = {
			"extent": extent,
			"view_indices": indices,
			"layers": layers,
			"payload_bytes": layers * extent.x * extent.y * bytes_per_pixel
		}
		groups.remove_at(best_second)
		merged += 1
	var views: Array[Dictionary] = []
	for view in plan.views:
		views.append(view.duplicate(true))
	var requested := 0
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		requested += int(group.payload_bytes)
		var indices: Array = group.view_indices
		for position in range(indices.size()):
			var view: Dictionary = views[int(indices[position])]
			view.group = group_index
			view.base = position * 2
			view.extent = group.extent
	var result := plan.duplicate(true)
	result.error = OK
	result.capacity_rejection = ""
	result.groups = groups
	result.views = views
	result.group_count = groups.size()
	result.coalesced_groups = merged
	result.requested_payload_bytes = requested
	result.requested_live_payload_bytes = resident_payload_bytes + requested
	result.padding_bytes_saved = maxi(int(result.legacy_shared_payload_bytes) - requested, 0)
	if requested > payload_limit:
		return _reject(result, ERR_OUT_OF_MEMORY, "payload_budget")
	if resident_payload_bytes + requested > live_limit:
		return _reject(result, ERR_OUT_OF_MEMORY, "replacement_overlap_budget")
	return result


static func _union(first: Vector2i, second: Vector2i) -> Vector2i:
	return Vector2i(maxi(first.x, second.x), maxi(first.y, second.y))


static func _find_group(groups: Array[Dictionary], extent: Vector2i) -> int:
	for index in range(groups.size()):
		if groups[index].extent == extent:
			return index
	return -1


static func _reject(result: Dictionary, error: Error, reason: String) -> Dictionary:
	result.error = error
	result.capacity_rejection = reason
	return result
