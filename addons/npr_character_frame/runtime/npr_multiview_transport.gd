extends Node
# gdlint: disable=max-file-lines
## One actor's shared depth storage, camera transactions and metadata publication.
## Producers are synchronized before this frame_pre_draw callback.

const ARRAY = preload("res://addons/npr_character_frame/runtime/npr_depth_array.gd")
const FLAGS = preload("res://addons/npr_character_frame/runtime/npr_depth_view_flags.gd")
const TABLE = preload("res://addons/npr_character_frame/runtime/npr_depth_view_table.gd")
const GROUP_PLAN = preload("res://addons/npr_character_frame/runtime/npr_depth_group_plan.gd")
const UPDATE = preload("res://addons/npr_character_frame/runtime/npr_depth_view_update.gd")
const GROUP_STORAGE = preload("res://addons/npr_character_frame/runtime/npr_depth_group_storage.gd")
const GROUP_UPDATE = preload(
	"res://addons/npr_character_frame/runtime/npr_depth_group_view_update.gd"
)
const HISTORY_RESET = preload("res://addons/npr_character_frame/runtime/npr_taa_history_reset.gd")
const NATIVE_VIEW = preload("res://addons/npr_character_frame/runtime/npr_native_view.gd")
const MAX_GROUP_SAMPLERS := 4
var depth: Node
var integer_sampling := true
var compact_storage := false
## Explicit opt-in. Legacy unified storage remains the default and fallback.
var grouped_storage_enabled := false
## Logical array payload budgets; source viewports and driver overhead are separate.
var max_payload_bytes := 128 * 1024 * 1024
var max_live_payload_bytes := 256 * 1024 * 1024
var _array: RefCounted
var _flags: RefCounted
var _table: RefCounted
var _grouped_storage: RefCounted
var _grouped_signature: Array = []
var _entries: Array[Dictionary] = []
var _mutex := Mutex.new()
var _build_result: Dictionary = {}
var _pending := false
var _built_signature: Array = []
var _attempt_signature: Array = []
var _retry_after := 0
var _published_count := -1
var _published_grouped_active := false
var _previous_integer: Array = []
var _generation := 0
var _build_attempts := 0
var _admission_signature: Array = []
var _admission_result: Dictionary = {}
var _admission_pending := false
var _admission_retry_after := 0
var _admission_attempts := 0
var _retaining := false
var _live_result: Dictionary = {}
var _candidate: Dictionary = {}
var _grouped_candidate: RefCounted
var _staging := false
var _retained_signature: Array = []
var _preserved_history: Array[Dictionary] = []


func _enter_tree() -> void:
	_mutex.lock()
	_generation += 1
	_build_result = {}
	_admission_result = {}
	_candidate = {}
	_grouped_candidate = null
	_mutex.unlock()
	_array = ARRAY.new()
	_array.compact = compact_storage
	_flags = FLAGS.new()
	_table = TABLE.new()
	_grouped_storage = null
	_grouped_signature.clear()
	_pending = false
	_build_attempts = 0
	_admission_signature.clear()
	_admission_pending = false
	_admission_attempts = 0
	_retaining = false
	_live_result = {}
	_staging = false
	_published_count = -1
	_published_grouped_active = false
	_retry_after = 0
	_built_signature.clear()
	_attempt_signature.clear()
	_previous_integer.clear()
	for material in depth.consumers:
		_previous_integer.append(material.get_shader_parameter("u_npr_depth_integer_sampling"))
		material.set_shader_parameter("u_npr_depth_integer_sampling", integer_sampling)
	if _entries.is_empty():
		_entries = [_entry(depth.get_viewport(), depth, false)]
	else:
		_entries[0].target = weakref(depth.get_viewport())
	_reconnect()
	# On subtree reentry, producer siblings reconnect after this child.
	_reconnect.call_deferred()


func set_grouped_storage(enabled: bool) -> void:
	if grouped_storage_enabled == enabled:
		return
	grouped_storage_enabled = enabled
	# The existing signature intentionally stays legacy-shaped. Clearing it
	# forces a fresh build without changing retained-view indexing.
	_built_signature.clear()
	_attempt_signature.clear()
	_published_count = -1
	if not enabled:
		_discard_grouped_candidate()
		_release_grouped_storage()


func _entry(viewport: Viewport, producer: Node, owned: bool) -> Dictionary:
	return {
		"target": weakref(viewport),
		"producer": producer,
		"owned": owned,
		"camera": null,
		"effect": null,
		"group_effect": null,
		"previous": null,
		"installed": null,
		"group_previous": null,
		"group_installed": null,
		"parents": []
	}


func _reconnect() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_synchronize):
		RenderingServer.frame_pre_draw.disconnect(_synchronize)
	RenderingServer.frame_pre_draw.connect(_synchronize)


func register_view(viewport: Viewport) -> bool:
	if not is_instance_valid(viewport) or viewport == depth.get_viewport():
		return false
	if viewport is NATIVE_VIEW and not viewport.has_consumer():
		return false
	if get_producer(viewport) != null:
		return true
	var owned: bool = not depth._view_producers.has(viewport.get_instance_id())
	var producer: Node = depth.register_view_producer(viewport)
	if producer == null:
		return false
	var entry := _entry(viewport, producer, owned)
	# A texture copied by RD does not itself establish a viewport dependency.
	# Parent the producer viewports under their consumer to enforce child-first draw.
	for source_view in producer.viewports:
		entry.parents.append(source_view.get_parent())
		source_view.reparent(viewport)
	_entries.append(entry)
	if viewport is NATIVE_VIEW:
		viewport.consumer_exiting.connect(_native_exiting.bind(entry))
		_bind_native_sources(entry)
	_reconnect()
	return true


func get_producer(viewport: Viewport) -> Node:
	for entry in _entries:
		if entry.target.get_ref() == viewport and is_instance_valid(entry.producer):
			return entry.producer
	return null


func unregister_view(viewport: Viewport = null) -> void:
	for index in range(_entries.size() - 1, 0, -1):
		var entry := _entries[index]
		if viewport == null or entry.target.get_ref() == viewport:
			_remove_entry(entry)
			_entries.remove_at(index)


func _remove_entry(entry: Dictionary, deferred_free := false) -> void:
	_detach(entry)
	var target: Viewport = entry.target.get_ref()
	if target is NATIVE_VIEW and target.consumer_exiting.is_connected(_native_exiting.bind(entry)):
		target.consumer_exiting.disconnect(_native_exiting.bind(entry))
	if is_instance_valid(entry.producer):
		for index in range(entry.parents.size()):
			var source_view: SubViewport = entry.producer.viewports[index]
			if is_instance_valid(source_view) and is_instance_valid(entry.parents[index]):
				source_view.reparent(entry.parents[index])
		if entry.owned:
			if deferred_free:
				if is_instance_valid(target):
					depth._view_producers.erase(target.get_instance_id())
				entry.producer.queue_free()
			elif is_instance_valid(target):
				depth.unregister_view_producer(target)
			else:
				entry.producer.free()


func _synchronize() -> void:
	for index in range(_entries.size() - 1, 0, -1):
		var target: Viewport = _entries[index].target.get_ref()
		if (
			not is_instance_valid(target)
			or target.is_queued_for_deletion()
			or not is_instance_valid(_entries[index].producer)
		):
			_remove_entry(_entries[index])
			_entries.remove_at(index)
	if not depth.active:
		_suspend()
		return
	var rows: Array[Dictionary] = []
	var inputs: Array[RID] = []
	var sizes: Array[Vector2i] = []
	var signature: Array = [max_payload_bytes, max_live_payload_bytes]
	var active_entries: Array[Dictionary] = []
	for entry in _entries:
		var target: Viewport = entry.target.get_ref()
		if target is NATIVE_VIEW and not target.has_consumer():
			_detach(entry, false)
			continue
		_bind_native_sources(entry)
		var record: Dictionary = entry.producer.get_view_snapshot(rows.size() * 2, rows.size())
		if record.is_empty():
			_detach(entry)
			continue
		active_entries.append(entry)
		rows.append(record)
		signature.append(_consumer_identity(entry))
		for source_view in entry.producer.viewports:
			inputs.append(source_view.get_texture().get_rid())
			sizes.append(source_view.size)
			signature.append([inputs.back(), sizes.back()])
	if rows.is_empty():
		_suspend()
		return
	_mutex.lock()
	var result := _build_result.duplicate(true)
	_mutex.unlock()
	_retaining = false
	if not _consume_build_result(result, signature, active_entries, rows):
		return
	# Replacement preparation preserves any sources still mapped to live storage.
	if signature != _built_signature:
		var retained := _retained_sources(signature, active_entries, _live_result)
		if not retained.is_empty():
			for entry in active_entries:
				if not retained.entries.has(entry):
					_detach(entry)
			_retained_signature = signature.duplicate(true)
			var retry_wait := (
				signature == _attempt_signature and Time.get_ticks_msec() < _retry_after
			)
			if (
				not _pending
				and not retry_wait
				and _admit_growth(signature, inputs, sizes, rows.size())
			):
				_queue_build(signature, inputs, sizes, rows.size(), true)
			_retaining = true
			rows.assign(retained.rows)
			inputs.assign(retained.inputs)
			active_entries.assign(retained.entries)
			signature = _built_signature.duplicate(true)
			result = _live_result.duplicate(true)
		elif _pending:
			_suspend()
			return
	if (
		signature != _built_signature
		or (not result.get("capacity_rejection", "").is_empty() and signature != _attempt_signature)
	):
		_suspend()
		if (
			signature == _attempt_signature
			and (
				not result.get("capacity_rejection", "").is_empty()
				or Time.get_ticks_msec() < _retry_after
			)
		):
			return
		_queue_build(signature, inputs, sizes, rows.size(), false)
		return
	_render_views(rows, active_entries, inputs, result)


func _render_views(
	rows: Array[Dictionary],
	active_entries: Array[Dictionary],
	inputs: Array[RID],
	result: Dictionary
) -> void:
	var grouped_active := _apply_grouped_rows(rows)
	if _table.update_views(rows) != OK:
		_suspend()
		return
	_publish(rows.size(), grouped_active)
	for index in range(active_entries.size()):
		var entry := active_entries[index]
		if rows[index].enabled == 0:
			_detach(entry)
			continue
		_mount(entry, rows[index].ready_index, result.epoch)
		if grouped_active:
			_mount_group(entry, index)
		else:
			_detach_group(entry)
		var state: Dictionary = entry.effect.result()
		var sources: Array[RID] = [inputs[index * 2], inputs[index * 2 + 1]]
		if (
			state.completed == 0
			or state.error != OK
			or state.completed < entry.get("submitted", 0)
			or entry.producer.requested_this_frame.has(true)
		):
			var accepted: int = entry.effect.queue_update(sources, PackedInt32Array([0, 1]))
			if accepted > 0:
				entry.submitted = accepted
			entry.effect.enabled = true
		else:
			# Retain valid layers and readiness without dispatching an empty
			# render-thread callback every frame for each static camera.
			entry.effect.enabled = false
		if grouped_active:
			var group_state: Dictionary = entry.group_effect.result()
			if (
				group_state.completed == 0
				or group_state.error != OK
				or group_state.completed < entry.get("group_submitted", 0)
				or entry.producer.requested_this_frame.has(true)
			):
				var group_accepted: int = entry.group_effect.queue_update(sources)
				if group_accepted > 0:
					entry.group_submitted = group_accepted
				entry.group_effect.enabled = true
			else:
				entry.group_effect.enabled = false
	_flush_preserved_history()


func _apply_grouped_rows(rows: Array[Dictionary]) -> bool:
	if not _grouped_storage_enabled_for_rows(rows):
		return false
	for index in range(rows.size()):
		var binding: Dictionary = _grouped_storage.view_binding(index)
		if binding.is_empty():
			return false
		var row := rows[index].duplicate(true)
		row["group_id"] = int(binding.group)
		row["group_base"] = int(binding.base)
		row["group_ready_index"] = int(binding.local_index)
		row["group_epoch"] = int(binding.epoch)
		rows[index] = row
	return true


func _grouped_storage_enabled_for_rows(rows: Array[Dictionary]) -> bool:
	return (
		grouped_storage_enabled
		and _grouped_storage != null
		and _grouped_signature == _built_signature
		and _grouped_storage.views.size() == rows.size()
		and _grouped_storage.groups.size() <= MAX_GROUP_SAMPLERS
	)


func _consume_build_result(
	result: Dictionary, signature: Array, entries: Array[Dictionary], rows: Array[Dictionary]
) -> bool:
	if not _pending:
		return true
	if not _staging:
		_suspend()
	if result.is_empty():
		return _staging
	_pending = false
	if result.error == OK:
		if signature != _attempt_signature:
			# A completed GPU allocation is not permission to publish an old request.
			_discard_candidates()
			_mutex.lock()
			_build_result = {}
			_mutex.unlock()
			_staging = false
			return true
		if _staging:
			_commit_candidate(signature, entries, rows)
		var grouped_ok: bool = (
			grouped_storage_enabled
			and result.get("grouped_enabled", false)
			and int(result.get("grouped_error", ERR_UNCONFIGURED)) == OK
		)
		if grouped_ok:
			_commit_grouped_candidate(signature)
		else:
			_discard_grouped_candidate()
			if _grouped_storage != null and _grouped_signature != signature:
				_release_grouped_storage()
		_built_signature = _attempt_signature.duplicate(true)
		_live_result = result.duplicate(true)
	else:
		_retry_after = Time.get_ticks_msec() + 500
		if not _staging:
			_live_result = {}
	return true


func _discard_candidates() -> void:
	_mutex.lock()
	var obsolete := _candidate
	_candidate = {}
	_mutex.unlock()
	if not obsolete.is_empty():
		RenderingServer.call_on_render_thread(obsolete.flags.release)
		RenderingServer.call_on_render_thread(obsolete.array.release)
	_discard_grouped_candidate()


func _discard_grouped_candidate() -> void:
	_mutex.lock()
	var grouped := _grouped_candidate
	_grouped_candidate = null
	_mutex.unlock()
	if grouped != null:
		RenderingServer.call_on_render_thread(grouped.release)


func _commit_grouped_candidate(signature: Array) -> void:
	_mutex.lock()
	var candidate := _grouped_candidate
	_grouped_candidate = null
	_mutex.unlock()
	if candidate == null:
		return
	var previous: RefCounted = _grouped_storage
	_grouped_storage = candidate
	_grouped_signature = signature.duplicate(true)
	_published_count = -1
	if previous != null:
		RenderingServer.call_on_render_thread(previous.release)


func _release_grouped_storage() -> void:
	for entry in _entries:
		_detach_group(entry)
	var previous: RefCounted = _grouped_storage
	_grouped_storage = null
	_grouped_signature.clear()
	_published_count = -1
	_published_grouped_active = false
	_publish(0, false)
	if previous != null:
		RenderingServer.call_on_render_thread(previous.release)


func _queue_build(
	signature: Array, inputs: Array[RID], sizes: Array[Vector2i], count: int, staged: bool
) -> void:
	_attempt_signature = signature.duplicate(true)
	_mutex.lock()
	_build_result = {}
	_mutex.unlock()
	_pending = true
	_staging = staged
	_build_attempts += 1
	RenderingServer.call_on_render_thread(
		_build.bind(
			inputs.duplicate(),
			sizes.duplicate(),
			count,
			_array,
			_flags,
			_generation,
			{
				"payload_limit": max_payload_bytes,
				"live_limit": max_live_payload_bytes,
				"preflight_only": false,
				"staged": staged
			}
		)
	)


func _commit_candidate(
	signature: Array, entries: Array[Dictionary], rows: Array[Dictionary]
) -> void:
	_mutex.lock()
	var candidate := _candidate
	_candidate = {}
	_mutex.unlock()
	var old_array: RefCounted = _array
	var old_flags: RefCounted = _flags
	_publish(0)
	for entry in _entries:
		var position := entries.find(entry)
		var preserve := false
		if (
			signature == _attempt_signature
			and position >= 0
			and rows[position].enabled != 0
			and entry.effect != null
			and entry.camera == entry.producer.camera
		):
			var offset: int = 2 + entry.effect.view_index * 3
			var current_offset := 2 + position * 3
			var state: Dictionary = entry.effect.result()
			preserve = (
				(
					_built_signature.slice(offset, offset + 3)
					== signature.slice(current_offset, current_offset + 3)
				)
				and state.error == OK
				and state.completed > 0
				and state.completed >= entry.get("submitted", 0)
			)
		_detach(entry, not preserve)
		if preserve:
			_preserved_history.append(entry)
	_array = candidate.array
	_flags = candidate.flags
	RenderingServer.call_on_render_thread(old_flags.release)
	RenderingServer.call_on_render_thread(old_array.release)


func _retained_sources(
	signature: Array, entries: Array[Dictionary], result: Dictionary
) -> Dictionary:
	var count := (_built_signature.size() - 2) / 3
	if (
		count < 1
		or result.get("error", ERR_UNCONFIGURED) != OK
		or result.get("resident_payload_bytes", 0) > max_payload_bytes
		or result.get("resident_payload_bytes", 0) > max_live_payload_bytes
	):
		return {}
	var rows: Array[Dictionary] = []
	var inputs: Array[RID] = []
	var retained: Array[Dictionary] = []
	for index in range(count):
		var offset := 2 + index * 3
		var found := -1
		for candidate in range(entries.size()):
			var start := 2 + candidate * 3
			if signature.slice(start, start + 3) == _built_signature.slice(offset, offset + 3):
				found = candidate
				break
		if found == -1:
			continue
		var entry := entries[found]
		# Table rows are compact, but retained depth/readiness keep old physical slots.
		var record: Dictionary = entry.producer.get_view_snapshot(index * 2, index)
		if record.is_empty():
			continue
		rows.append(record)
		retained.append(entry)
		for source_view in entry.producer.viewports:
			inputs.append(source_view.get_texture().get_rid())
	return {} if rows.is_empty() else {"rows": rows, "inputs": inputs, "entries": retained}


func _admit_growth(
	signature: Array, inputs: Array[RID], sizes: Array[Vector2i], count: int
) -> bool:
	_mutex.lock()
	var result := _admission_result.duplicate(true)
	_mutex.unlock()
	if _admission_pending:
		if result.is_empty():
			return false
		_admission_pending = false
		_admission_retry_after = Time.get_ticks_msec() + 500
	if signature == _admission_signature and not result.is_empty():
		if result.error == OK:
			return true
		if (
			not result.capacity_rejection.is_empty()
			or Time.get_ticks_msec() < _admission_retry_after
		):
			return false
	_admission_signature = signature.duplicate(true)
	_mutex.lock()
	_admission_result = {}
	_mutex.unlock()
	_admission_pending = true
	_admission_attempts += 1
	RenderingServer.call_on_render_thread(
		_build.bind(
			inputs.duplicate(),
			sizes.duplicate(),
			count,
			_array,
			_flags,
			_generation,
			{
				"payload_limit": max_payload_bytes,
				"live_limit": max_live_payload_bytes,
				"preflight_only": true,
				"staged": false
			}
		)
	)
	return false


func _build(
	inputs: Array[RID],
	sizes: Array[Vector2i],
	count: int,
	array: RefCounted,
	flags: RefCounted,
	generation: int,
	options: Dictionary
) -> void:
	var payload_limit := int(options.get("payload_limit", max_payload_bytes))
	var live_limit := int(options.get("live_limit", max_live_payload_bytes))
	var preflight_only := bool(options.get("preflight_only", false))
	var staged := bool(options.get("staged", false))
	var grouped_enabled := grouped_storage_enabled
	var rd := RenderingServer.get_rendering_device()
	var sources: Array[RID] = []
	var error := OK
	var extent := Vector2i.ZERO
	var pixel_bytes := 0
	var source_format := -1
	for index in range(inputs.size()):
		var source := RenderingServer.texture_get_rd_texture(inputs[index])
		if not rd.texture_is_valid(source):
			error = ERR_UNCONFIGURED
			break
		var format := rd.texture_get_format(source)
		if Vector2i(format.width, format.height) != sizes[index]:
			error = ERR_UNCONFIGURED
			break
		# Capacity accounting is meaningful only for a valid homogeneous copy job.
		# Keep unready/incompatible source failures on the existing retry path.
		if (
			not ARRAY.PIXEL_BYTES.has(format.format)
			or format.texture_type != RenderingDevice.TEXTURE_TYPE_2D
			or format.samples != RenderingDevice.TEXTURE_SAMPLES_1
			or not (format.usage_bits & RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
			or (source_format != -1 and source_format != format.format)
		):
			error = ERR_INVALID_PARAMETER
			break
		source_format = format.format
		sources.append(source)
		extent = Vector2i(maxi(extent.x, format.width), maxi(extent.y, format.height))
		pixel_bytes = maxi(pixel_bytes, ARRAY.PIXEL_BYTES.get(format.format, 0))
	var requested_bytes: int = (
		extent.x * extent.y * inputs.size() * (4 if array.compact else pixel_bytes)
	)
	var live_bytes: int = array.resident_payload_bytes + requested_bytes
	var max_layers := rd.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_ARRAY_LAYERS)
	var grouped_plan := GROUP_PLAN.build(
		sizes,
		4 if array.compact else pixel_bytes,
		payload_limit,
		live_limit,
		array.resident_payload_bytes,
		max_layers
	)
	# More distinct extents than fixed group samplers: merge the cheapest pairs
	# so grouped storage stays available instead of falling back to unified.
	# Merged views are padded, which the normalized-nearest contract cannot
	# sample exactly, so coalescing is only offered under integer sampling.
	if (
		grouped_enabled
		and integer_sampling
		and grouped_plan.error == OK
		and grouped_plan.group_count > MAX_GROUP_SAMPLERS
	):
		grouped_plan = GROUP_PLAN.coalesce(
			grouped_plan,
			MAX_GROUP_SAMPLERS,
			payload_limit,
			live_limit,
			array.resident_payload_bytes
		)
	var grouped_candidate: RefCounted = null
	var grouped_error := OK
	var grouped_rejection := ""
	if grouped_enabled:
		if grouped_plan.error != OK:
			grouped_error = int(grouped_plan.error)
			grouped_rejection = grouped_plan.capacity_rejection
		elif grouped_plan.group_count > MAX_GROUP_SAMPLERS:
			grouped_error = ERR_UNAVAILABLE
			grouped_rejection = "group_sampler_limit"
		elif error == OK and not preflight_only:
			grouped_candidate = GROUP_STORAGE.new()
			grouped_candidate.compact = array.compact
			grouped_candidate.max_payload_bytes = payload_limit
			grouped_candidate.max_live_payload_bytes = live_limit
			grouped_error = grouped_candidate.replace(sources, sizes, grouped_plan)
			if grouped_error != OK:
				grouped_candidate.release()
				grouped_candidate = null
	var rejection := ""
	if error == OK:
		if inputs.size() > max_layers:
			rejection = "device_layers"
		elif count > 4096:
			rejection = "metadata_rows"
		elif requested_bytes > payload_limit:
			rejection = "payload_budget"
		elif live_bytes > live_limit:
			rejection = "replacement_overlap_budget"
		if not rejection.is_empty():
			error = ERR_OUT_OF_MEMORY
	var previous_array: RefCounted = array
	var next: Dictionary = {}
	if error == OK and staged and not preflight_only:
		array = ARRAY.new()
		array.compact = previous_array.compact
		array.allocation_count = previous_array.allocation_count
		array.copy_count = previous_array.copy_count
		array.peak_live_payload_bytes = previous_array.peak_live_payload_bytes
		var previous_epoch: int = flags.epoch
		flags = FLAGS.new()
		flags.epoch = previous_epoch
		next = {"array": array, "flags": flags}
	if error == OK and not preflight_only:
		array.max_payload_bytes = payload_limit
		array.max_live_payload_bytes = (
			live_limit - previous_array.resident_payload_bytes if staged else live_limit
		)
		error = array.replace(sources)
	if error == OK and not preflight_only:
		error = flags.reset(count)
	if not next.is_empty() and error == OK:
		array.max_live_payload_bytes = live_limit
		array.peak_live_payload_bytes = maxi(array.peak_live_payload_bytes, live_bytes)
	_mutex.lock()
	if generation == _generation:
		var report := {
			"error": error,
			"epoch": flags.epoch,
			"allocations": array.allocation_count,
			"copies": array.copy_count,
			"capacity_rejection": rejection,
			"requested_layers": inputs.size(),
			"device_max_layers": max_layers,
			"requested_payload_bytes": requested_bytes,
			"requested_live_payload_bytes": live_bytes,
			"resident_payload_bytes": array.resident_payload_bytes,
			"peak_live_payload_bytes": array.peak_live_payload_bytes,
			"grouped_plan": grouped_plan,
			"grouped_enabled": grouped_enabled,
			"grouped_error": grouped_error,
			"grouped_rejection": grouped_rejection,
			"grouped_resident_payload_bytes":
			grouped_candidate.resident_payload_bytes if grouped_candidate != null else 0,
			"grouped_group_count": grouped_plan.group_count if grouped_error == OK else 0
		}
		if preflight_only:
			_admission_result = report
		else:
			_build_result = report
			if error == OK and not next.is_empty():
				_candidate = next
				next = {}
			if error == OK and grouped_candidate != null:
				_grouped_candidate = grouped_candidate
				grouped_candidate = null
	_mutex.unlock()
	if not next.is_empty():
		next.flags.release()
		next.array.release()
	if grouped_candidate != null:
		grouped_candidate.release()


func _publish(count: int, grouped_active := false) -> void:
	if _published_count == count and _published_grouped_active == grouped_active:
		return
	_published_count = count
	_published_grouped_active = grouped_active
	var group_count := 0
	if grouped_active and _grouped_storage != null:
		group_count = mini(_grouped_storage.groups.size(), MAX_GROUP_SAMPLERS)
	for index in range(depth.consumers.size()):
		var material: ShaderMaterial = depth.consumers[index]
		material.set_shader_parameter("u_npr_depth_view_count", count)
		material.set_shader_parameter("u_npr_depth_view_channel", 1 if index == 1 else 0)
		material.set_shader_parameter("u_npr_depth_array_base", -1)
		material.set_shader_parameter("u_npr_depth_array_base_secondary", -1)
		material.set_shader_parameter("u_npr_depth_array", _array.resource if count > 0 else null)
		material.set_shader_parameter("u_npr_depth_array_compact", count > 0 and _array.compact)
		material.set_shader_parameter(
			"u_npr_depth_view_ready", _flags.resource if count > 0 else null
		)
		material.set_shader_parameter(
			"u_npr_depth_view_table", _table.texture if count > 0 else null
		)
		material.set_shader_parameter("u_npr_depth_group_enabled", grouped_active and count > 0)
		material.set_shader_parameter("u_npr_depth_group_count", group_count)
		material.set_shader_parameter(
			"u_npr_depth_group_compact", grouped_active and count > 0 and _grouped_storage.compact
		)
		for group_index in range(MAX_GROUP_SAMPLERS):
			var array_resource: Variant = null
			var flags_resource: Variant = null
			if group_index < group_count:
				var group: Dictionary = _grouped_storage.groups[group_index]
				array_resource = group.array.resource
				flags_resource = group.flags.resource
			material.set_shader_parameter(
				"u_npr_depth_group_array_%d" % group_index, array_resource
			)
			material.set_shader_parameter(
				"u_npr_depth_group_ready_%d" % group_index, flags_resource
			)


func _suspend() -> void:
	_publish(0)
	for entry in _entries:
		_detach(entry)
	_flush_preserved_history()


func _flush_preserved_history() -> void:
	# A retained camera that did not remount must discard history before fallback.
	for entry in _preserved_history:
		if is_instance_valid(entry.producer):
			_reset_history(entry)
	_preserved_history.clear()


func _mount(entry: Dictionary, index: int, epoch: int) -> void:
	var camera: Camera3D = entry.producer.camera
	if (
		entry.camera == camera
		and entry.effect != null
		and entry.effect.target == _array
		and entry.effect.flags == _flags
		and entry.effect.view_index == index
		and entry.effect.view_epoch == epoch
		and camera.compositor != null
		and camera.compositor.compositor_effects.has(entry.effect)
	):
		return
	_detach(entry)
	var effect := UPDATE.new()
	effect.target = _array
	effect.reset_taa_on_ready = true
	# Equivalent storage changes are not a loss/recovery of this view's depth.
	# A failed first copy still transitions true -> false and rejects old history.
	effect._last_success = _preserved_history.has(entry)
	_preserved_history.erase(entry)
	effect.flags = _flags
	effect.view_index = index
	effect.view_epoch = epoch
	effect.destinations = PackedInt32Array([index * 2, index * 2 + 1])
	var effects: Array[CompositorEffect] = []
	entry.previous = camera.compositor
	if camera.compositor != null:
		effects.assign(camera.compositor.compositor_effects)
	effects.append(effect)
	var compositor := Compositor.new()
	compositor.compositor_effects = effects
	camera.compositor = compositor
	entry.camera = camera
	entry.installed = compositor
	entry.effect = effect
	entry.submitted = 0
	_publish_native_compositor(entry)


func _mount_group(entry: Dictionary, index: int) -> void:
	if _grouped_storage == null:
		return
	var camera: Camera3D = entry.producer.camera
	if (
		entry.group_effect != null
		and entry.group_effect.target == _grouped_storage
		and entry.group_effect.view_index == index
		and is_instance_valid(camera)
		and camera.compositor != null
		and camera.compositor.compositor_effects.has(entry.group_effect)
	):
		return
	_detach_group(entry)
	var effect := GROUP_UPDATE.new()
	effect.target = _grouped_storage
	effect.view_index = index
	# Legacy and grouped effects may coexist during migration; only the legacy
	# owner resets TAA so one camera cannot clear history twice in one frame.
	effect.reset_taa_on_ready = false
	var effects: Array[CompositorEffect] = []
	entry.group_previous = camera.compositor
	if camera.compositor != null:
		effects.assign(camera.compositor.compositor_effects)
	effects.append(effect)
	var compositor := Compositor.new()
	compositor.compositor_effects = effects
	camera.compositor = compositor
	entry.group_installed = compositor
	entry.group_effect = effect
	entry.group_submitted = 0


func _detach_group(entry: Dictionary) -> void:
	var effect: CompositorEffect = entry.group_effect
	if effect == null:
		return
	var camera: Camera3D = entry.camera if is_instance_valid(entry.camera) else null
	if is_instance_valid(camera) and camera.compositor != null:
		var current := camera.compositor
		if current.compositor_effects.has(effect):
			var remaining: Array[CompositorEffect] = []
			for item in current.compositor_effects:
				if item != effect:
					remaining.append(item)
			var previous: Array[CompositorEffect] = []
			if entry.group_previous != null:
				previous.assign(entry.group_previous.compositor_effects)
			if current == entry.group_installed and remaining == previous:
				camera.compositor = entry.group_previous
			else:
				var retained := Compositor.new()
				retained.compositor_effects = remaining
				camera.compositor = retained
	RenderingServer.call_on_render_thread(effect.release)
	entry.group_effect = null
	entry.group_previous = null
	entry.group_installed = null
	entry.group_submitted = 0


func _detach(entry: Dictionary, reset_history := true) -> void:
	# A destroyed target frees its camera before the next frame_pre_draw purge.
	# Validate the Variant before assigning it to a typed Object local.
	_detach_group(entry)
	var camera: Camera3D = entry.camera if is_instance_valid(entry.camera) else null
	var effect: CompositorEffect = entry.effect
	if effect == null:
		return
	if is_instance_valid(camera) and camera.compositor != null:
		var current := camera.compositor
		if current.compositor_effects.has(effect):
			var remaining: Array[CompositorEffect] = []
			for item in current.compositor_effects:
				if item != effect:
					remaining.append(item)
			var previous: Array[CompositorEffect] = []
			if entry.previous != null:
				previous.assign(entry.previous.compositor_effects)
			if current == entry.installed and remaining == previous:
				camera.compositor = entry.previous
			else:
				var retained := Compositor.new()
				retained.compositor_effects = remaining
				camera.compositor = retained
	RenderingServer.call_on_render_thread(effect.release)
	if reset_history:
		_reset_history(entry)
	_publish_native_compositor(entry)
	entry.effect = null
	entry.camera = null
	entry.previous = null
	entry.installed = null


func _consumer_identity(entry: Dictionary) -> Variant:
	var target: Viewport = entry.target.get_ref()
	if target is NATIVE_VIEW:
		return [target.get_instance_id(), target.consumer_viewport, target.consumer_camera]
	return target.get_instance_id()


func _bind_native_sources(entry: Dictionary) -> void:
	var target: Viewport = entry.target.get_ref()
	if not target is NATIVE_VIEW or not target.consumer_viewport.is_valid():
		return
	var identity: Variant = _consumer_identity(entry)
	if entry.get("native_identity") == identity:
		return
	for source_view in entry.producer.viewports:
		RenderingServer.viewport_set_parent_viewport(
			source_view.get_viewport_rid(), target.consumer_viewport
		)
	entry.native_identity = identity


func _native_exiting(entry: Dictionary) -> void:
	_detach(entry, false)
	if is_instance_valid(entry.producer):
		for source_view in entry.producer.viewports:
			if is_instance_valid(source_view):
				RenderingServer.viewport_set_parent_viewport(source_view.get_viewport_rid(), RID())
	entry.erase("native_identity")


func _publish_native_compositor(entry: Dictionary) -> void:
	var target: Viewport = entry.target.get_ref()
	if target is NATIVE_VIEW:
		target.publish_compositor()


func _reset_history(entry: Dictionary) -> void:
	var target: Viewport = entry.target.get_ref()
	if target is NATIVE_VIEW:
		target.reset_history()
	else:
		# A destroyed target can invalidate its borrowed producer before the
		# next synchronization pass detaches the entry. History reset is best
		# effort in that case; do not dereference the freed producer.
		var producer: Variant = entry.get("producer")
		if not is_instance_valid(producer):
			return
		var camera: Variant = producer.camera
		if not is_instance_valid(camera):
			return
		HISTORY_RESET.schedule(camera)


func status() -> Dictionary:
	_mutex.lock()
	var value := (_live_result if _build_result.is_empty() else _build_result).duplicate(true)
	if _retaining and not (_staging and _attempt_signature == _retained_signature):
		value.merge(_admission_result, true)
	_mutex.unlock()
	value.merge(
		{
			"pending": _pending,
			"published_views": maxi(_published_count, 0),
			"registered_views": _entries.size(),
			"build_attempts": _build_attempts,
			"admission_attempts": _admission_attempts,
			"admission_pending": _admission_pending,
			"retained_views": maxi(_published_count, 0) if _retaining else 0,
			"grouped_storage_enabled": grouped_storage_enabled,
			"grouped_active": _published_grouped_active,
			"grouped_storage": _grouped_storage.status() if _grouped_storage != null else {},
			"grouped_candidate_pending": _grouped_candidate != null,
			"grouped_signature_matches": _grouped_signature == _built_signature
		}
	)
	return value


func _exit_tree() -> void:
	_mutex.lock()
	_generation += 1
	var candidate := _candidate
	_candidate = {}
	var grouped_candidate := _grouped_candidate
	_grouped_candidate = null
	_mutex.unlock()
	RenderingServer.frame_pre_draw.disconnect(_synchronize)
	_suspend()
	for index in range(depth.consumers.size()):
		depth.consumers[index].set_shader_parameter(
			"u_npr_depth_integer_sampling", _previous_integer[index]
		)
	RenderingServer.call_on_render_thread(_flags.release)
	RenderingServer.call_on_render_thread(_array.release)
	var grouped_storage := _grouped_storage
	_grouped_storage = null
	_grouped_signature.clear()
	if grouped_storage != null:
		RenderingServer.call_on_render_thread(grouped_storage.release)
	if grouped_candidate != null:
		RenderingServer.call_on_render_thread(grouped_candidate.release)
	if not candidate.is_empty():
		RenderingServer.call_on_render_thread(candidate.flags.release)
		RenderingServer.call_on_render_thread(candidate.array.release)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for entry in _entries:
			_detach(entry)
		# A child exit callback runs while its parent's child list is locked.
		# Never free sibling producers synchronously from that callback.
		for index in range(_entries.size() - 1, 0, -1):
			_remove_entry(_entries[index], true)
		_entries.clear()
