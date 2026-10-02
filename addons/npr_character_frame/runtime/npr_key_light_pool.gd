class_name NPRKeyLightPool
extends Node3D
## One effective World3D's key ownership and mask-aware rendering-view budgets.
## Actor layers stay private for fills; compatible keys share one real CSM light.

signal budget_changed(active_groups: int, denied_groups: int)

const MAX_DIRECTIONAL_LIGHTS := 8
const STAGE_LAYER := 1
const EXCLUDED_SETTINGS := ["light_cull_mask", "shadow_caster_mask", "shadow_enabled"]
const ACTOR_LAYERS = preload("res://addons/npr_character_frame/runtime/npr_actor_layers.gd")

static var _world_pools: Dictionary = {}

var active_groups := 0
var denied_groups := 0
var state_uploads := 0
var _members: Dictionary = {}
var _groups: Array[Dictionary] = []
var _external_lights: Dictionary = {}
var _render_views: Dictionary = {}
var _setting_names: Array[StringName] = []
var _published: Array = []
var _world_id := 0
var _retiring := false
var _synchronizing := false
var _exited_tree := false


static func attach(viewport: Viewport, during_sync: bool = false) -> NPRKeyLightPool:
	# .world_3d omits inherited/own worlds. Key by the effective resource instead.
	var world := viewport.find_world_3d()
	var world_id := world.get_instance_id()
	var reference: WeakRef = _world_pools.get(world_id)
	var pool := reference.get_ref() as NPRKeyLightPool if reference != null else null
	if pool == null:
		# A disabled viewport gives the lights a stable scenario without rendering.
		# No member's viewport owns it, so deleting the creator cannot delete a key
		# still used by another view. The last member retires this entire host.
		var host := SubViewport.new()
		host.name = "NPRWorldKeyHost"
		host.size = Vector2i(2, 2)
		host.world_3d = world
		host.render_target_update_mode = SubViewport.UPDATE_DISABLED
		pool = NPRKeyLightPool.new()
		pool.name = "NPRKeyLightPool"
		pool._world_id = world_id
		_world_pools[world_id] = weakref(pool)
		host.add_child(pool)
		if during_sync:
			# World migration at pre-draw must install its scenario this frame.
			viewport.get_tree().root.add_child(host)
		else:
			# The root is blocked while the real main scene receives _ready.
			# Keep the original member lights parented until this host enters.
			viewport.get_tree().root.add_child.call_deferred(host)
	return pool


func _ready() -> void:
	get_tree().node_added.connect(_track_budget_node)
	for type in ["DirectionalLight3D", "Camera3D", "ReflectionProbe"]:
		for node in get_tree().root.find_children("*", type, true, false):
			_track_budget_node(node)
	RenderingServer.frame_pre_draw.connect(synchronize)
	for group in _groups:
		_adopt_light(group.light)
	if not _members.is_empty():
		synchronize()


func register_member(
	member: Node3D, light: DirectionalLight3D, layer: int, direction: Vector3, shadows: bool
) -> void:
	assert(not _members.has(member), "Key-light member registered twice")
	if _setting_names.is_empty():
		for property in light.get_property_list():
			var key := String(property.name)
			if (
				(property.usage & PROPERTY_USAGE_STORAGE) != 0
				and key not in EXCLUDED_SETTINGS
				and (
					key.begins_with("light_")
					or key.begins_with("shadow_")
					or key.begins_with("directional_")
					or key in ["sky_mode", "editor_only", "layers"]
				)
			):
				_setting_names.append(StringName(key))
	var settings := _settings(light)
	_members[member] = {
		"direction": direction, "settings": settings, "layer": layer, "shadows": shadows
	}
	if is_inside_tree():
		_adopt_light(light)
	_groups.append(
		{"light": light, "direction": direction, "settings": settings, "members": [member]}
	)
	_published.clear()
	synchronize()


func _adopt_light(light: DirectionalLight3D) -> void:
	if light.get_parent() == null:
		add_child(light)
	elif light.get_parent() != self:
		light.reparent(self, true)


func unregister_member(member: Node3D) -> void:
	_members.erase(member)
	_published.clear()
	if _exited_tree:
		return
	if is_inside_tree() and not is_queued_for_deletion():
		synchronize()
	else:
		# A member can be removed before the deferred startup host enters. Its
		# original light must not remain in the pending adoption list.
		for group in _groups.duplicate():
			if member in group.members:
				_groups.erase(group)
				group.light.queue_free()
	_retire_if_empty()


func member_settings(member: Node3D) -> Dictionary:
	if _exited_tree or not _members.has(member):
		return {}
	var values: Array = _members[member].settings
	# Preserve a direct group edit even if the member exits before pre-draw.
	for group in _groups:
		if member in group.members:
			var actual := _settings(group.light)
			if actual != group.settings:
				values = actual
			break
	var result := {}
	for index in range(_setting_names.size()):
		result[_setting_names[index]] = values[index]
	return result


func request(member: Node3D, direction: Vector3, shadows: bool) -> void:
	if _members.has(member):
		_members[member].direction = direction
		_members[member].shadows = shadows


func update_member_layer(member: Node3D, layer: int) -> void:
	if _members.has(member):
		_members[member].layer = layer


func configure_member(member: Node3D, overrides: Dictionary) -> bool:
	if not _members.has(member):
		return false
	for key in overrides:
		if StringName(key) not in _setting_names:
			return false
	# Normalize through native setters BEFORE key matching (e.g. float32 shadow
	# bias). Otherwise restoring 0.1 can spuriously create a second key for a frame.
	var normalized := DirectionalLight3D.new()
	for index in range(_setting_names.size()):
		normalized.set(_setting_names[index], _members[member].settings[index])
	for key in overrides:
		normalized.set(key, overrides[key])
	_members[member].settings = _settings(normalized)
	normalized.free()
	return true


func get_group_count() -> int:
	return _groups.size()


func synchronize() -> void:
	if _retiring or _synchronizing or not is_inside_tree():
		return
	# Two worlds may exchange several members in one frame. A destination
	# registration can call back into this pool; finish the outer transaction first.
	_synchronizing = true
	# Also cover explicit synchronization between draws. The allocator settles all
	# Worlds before this pool migrates members or publishes receiver/caster masks.
	ACTOR_LAYERS.synchronize()
	# Direct light edits are group-wide (diagnostics/editor). configure_member() is
	# the explicit per-actor API for a config change that may split a shared key.
	for group in _groups:
		var settings := _settings(group.light)
		if settings != group.settings:
			group.settings = settings
			for member in group.members:
				if _members.has(member):
					_members[member].settings = settings
	_move_changed_worlds()
	var external_masks := _external_masks()
	var view_masks := _view_masks()
	var snapshot: Array = [external_masks, view_masks]
	for member in _members:
		var entry: Dictionary = _members[member]
		snapshot.append(
			[
				member,
				entry.direction,
				entry.settings,
				entry.layer,
				entry.shadows,
				member.is_visible_in_tree()
			]
		)
	if snapshot == _published:
		_synchronizing = false
		return
	_published = snapshot
	var buckets: Array[Dictionary] = []
	for member in _members:
		var entry: Dictionary = _members[member]
		var bucket := _matching(buckets, entry)
		if bucket.is_empty():
			bucket = {
				"direction": entry.direction,
				"settings": entry.settings,
				"members": [],
				"mask": 0,
				"shadows": false
			}
			buckets.append(bucket)
		bucket.members.append(member)
		if member.is_visible_in_tree():
			bucket.mask |= entry.layer
			bucket.shadows = bucket.shadows or entry.shadows
	var budgets: Array[Dictionary] = []
	for mask in view_masks:
		var used := 0
		for external_mask in external_masks:
			used += int((mask & external_mask) != 0)
		budgets.append({"mask": mask, "used": used})
	_reconcile(buckets, budgets)
	state_uploads += 1
	_retire_if_empty()
	_synchronizing = false


func _move_changed_worlds() -> void:
	# World replacement sends enter/exit-world, not exit-tree. Resolve it at
	# pre-draw as well as normal member requests, before rendering any view.
	for member in _members.keys():
		if member.get_world_3d() == get_world_3d():
			continue
		var entry: Dictionary = _members[member]
		var light := DirectionalLight3D.new()
		var settings := member_settings(member)
		for key in settings:
			light.set(key, settings[key])
		_members.erase(member)
		_published.clear()
		var target := attach(member.get_viewport(), true)
		member.key_pool = target
		target.register_member(member, light, entry.layer, entry.direction, entry.shadows)


func _retire_if_empty() -> void:
	if not _members.is_empty() or _retiring:
		return
	_retiring = true
	_forget_registry()
	get_parent().queue_free()


func _forget_registry() -> void:
	var reference: WeakRef = _world_pools.get(_world_id)
	if reference != null and reference.get_ref() == self:
		_world_pools.erase(_world_id)


func _reconcile(buckets: Array[Dictionary], budgets: Array[Dictionary]) -> void:
	var unused := _groups.duplicate()
	var assigned: Array[Dictionary] = []
	var active := 0
	var denied := 0
	for bucket in buckets:
		var group := _matching(unused, bucket)
		if group.is_empty():
			# Reuse a no-longer-needed key before allocating. A whole group rotating
			# together keeps its Light RID instead of replacing it every frame.
			for candidate in unused:
				if _matching(buckets, candidate).is_empty():
					group = candidate
					break
		if group.is_empty():
			var light := DirectionalLight3D.new()
			light.name = "SharedNPRKey"
			add_child(light)
			group = {"light": light}
		else:
			unused.erase(group)
		var light: DirectionalLight3D = group.light
		for index in range(_setting_names.size()):
			if light.get(_setting_names[index]) != bucket.settings[index]:
				light.set(_setting_names[index], bucket.settings[index])
		var toward: Vector3 = bucket.direction
		var up := Vector3.UP if absf(toward.y) < 0.99 else Vector3.RIGHT
		light.global_basis = Basis.looking_at(-toward, up)
		light.force_update_transform()
		# Native culling uses VisualInstance3D.layers, NOT light_cull_mask (receivers).
		# Admit a key only if every known view that can see it has a free native slot.
		var available: bool = bucket.mask != 0 and _reserve_light(light.layers, budgets)
		if bucket.mask != 0 and not available:
			denied += 1
		# Exactly one active group owns public-stage illumination, regardless of
		# actor count. Every group can still receive shadows cast by stage geometry.
		light.light_cull_mask = bucket.mask | (STAGE_LAYER if available and active == 0 else 0)
		light.shadow_caster_mask = bucket.mask | STAGE_LAYER
		# Publish demand changes, not unrelated bookkeeping changes. This also
		# preserves an explicit diagnostic toggle on the actual shared Light node.
		if group.get("published_visible") != available:
			light.visible = available
			group.published_visible = available
		var shadows: bool = available and bucket.shadows
		if group.get("published_shadows") != shadows:
			light.shadow_enabled = shadows
			group.published_shadows = shadows
		active += int(available)
		group.direction = bucket.direction
		group.settings = bucket.settings
		group.members = bucket.members
		assigned.append(group)
		for member in bucket.members:
			member.shadow_light = light
			member.set_key_available(available)
	for group in unused:
		group.light.free()
	_groups = assigned
	if active_groups != active or denied_groups != denied:
		active_groups = active
		denied_groups = denied
		budget_changed.emit(active, denied)


func _matching(groups: Array[Dictionary], key: Dictionary) -> Dictionary:
	for group in groups:
		if group.direction == key.direction and group.settings == key.settings:
			return group
	return {}


func _settings(light: DirectionalLight3D) -> Array:
	var values: Array = []
	for key in _setting_names:
		values.append(light.get(key))
	return values


func _reserve_light(layers: int, budgets: Array[Dictionary]) -> bool:
	for budget in budgets:
		if (layers & budget.mask) != 0 and budget.used >= MAX_DIRECTIONAL_LIGHTS:
			return false
	# Reserve atomically: rejection by one view must not consume another view's slot.
	for budget in budgets:
		if (layers & budget.mask) != 0:
			budget.used += 1
	return true


func _track_budget_node(node: Node) -> void:
	if node is DirectionalLight3D:
		# node_added repeats on reparent; reserve a slot per instance, not entry event.
		_external_lights[node.get_instance_id()] = weakref(node)
	elif node is Camera3D or node is ReflectionProbe:
		_render_views[node.get_instance_id()] = weakref(node)


func _external_count() -> int:
	return _external_masks().size()


func _external_masks() -> Array[int]:
	var live := {}
	var masks: Array[int] = []
	for reference in _external_lights.values():
		var light := reference.get_ref() as DirectionalLight3D
		if not is_instance_valid(light):
			continue
		live[light.get_instance_id()] = reference
		if (
			light.is_inside_tree()
			and not light.is_queued_for_deletion()
			and not is_ancestor_of(light)
			and light.is_visible_in_tree()
			and light.get_world_3d() == get_world_3d()
		):
			masks.append(light.layers)
	_external_lights = live
	# Order is irrelevant, multiplicity is not. Same-count mask edits invalidate too.
	masks.sort()
	return masks


func _view_masks() -> Array[int]:
	var live := {}
	var unique := {}
	for reference in _render_views.values():
		var view := reference.get_ref() as Node3D
		if not is_instance_valid(view):
			continue
		live[view.get_instance_id()] = reference
		if (
			view.is_inside_tree()
			and not view.is_queued_for_deletion()
			and view.get_world_3d() == get_world_3d()
		):
			# Reserve noncurrent cameras/hidden probes too, avoiding activation races.
			# Reflection probes also call _render_scene with their own cull mask.
			unique[view.cull_mask] = true
	_render_views = live
	var masks: Array[int] = []
	masks.assign(unique.keys())
	if masks.is_empty():
		# No known view is not evidence that arbitrarily many lights are safe.
		masks.append(0xFFFFFFFF)
	masks.sort()
	return masks


func _exit_tree() -> void:
	_exited_tree = true
	_forget_registry()
	RenderingServer.frame_pre_draw.disconnect(synchronize)
	get_tree().node_added.disconnect(_track_budget_node)
