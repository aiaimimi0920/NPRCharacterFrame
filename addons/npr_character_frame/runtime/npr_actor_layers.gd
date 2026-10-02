extends RefCounted
## World-scoped private render-layer leases. Layer 1 remains the public stage.
## Resolve all World moves before allocating, so simultaneous exchanges are atomic.

const MAX_ACTOR_LAYERS := 19

static var _leases: Dictionary = {}
static var _synchronizing := false
static var _dirty := false
static var reconciliations := 0


static func register(actor: Node3D, publish: Callable) -> void:
	assert(not _leases.has(actor.get_instance_id()), "Actor layer registered twice")
	if _leases.is_empty():
		# Preview registers before creating its character/depth helpers. Allocation
		# therefore precedes their pre-draw consumers, even when processing is paused.
		RenderingServer.frame_pre_draw.connect(synchronize)
	_leases[actor.get_instance_id()] = {
		"actor": weakref(actor),
		"publish": publish,
		"world": 0,
		"layer": 0,
		"preferred": 0,
		"published": -1,
	}
	invalidate()
	synchronize()


static func unregister(actor: Node3D) -> void:
	_leases.erase(actor.get_instance_id())
	invalidate()
	_disconnect_if_empty()


static func invalidate() -> void:
	_dirty = true


static func synchronize() -> void:
	if _synchronizing or not _dirty:
		return
	_synchronizing = true
	_dirty = false
	reconciliations += 1
	var occupied := {}
	var pending: Array[Dictionary] = []
	# First release every departing slot; never let callback/pool order decide
	# whether a two-World swap is falsely considered over capacity.
	for id in _leases.keys():
		var lease: Dictionary = _leases[id]
		var actor := lease.actor.get_ref() as Node3D
		if actor == null:
			_leases.erase(id)
			continue
		var world_id: int = lease.world
		if actor.is_inside_tree():
			world_id = actor.get_world_3d().get_instance_id()
		if world_id != lease.world:
			lease.world = world_id
			lease.layer = 0
		if lease.layer != 0:
			occupied[world_id] = int(occupied.get(world_id, 1)) | int(lease.layer)
		elif actor.is_inside_tree():
			pending.append(lease)
	# Incumbents and temporarily detached actors retain their reservations.
	# A full World fails closed with layer zero, then retries when a slot opens.
	for lease in pending:
		var used: int = occupied.get(lease.world, 1)
		var preferred: int = lease.preferred
		if preferred != 0 and (used & preferred) == 0:
			lease.layer = preferred
		else:
			for index in range(1, MAX_ACTOR_LAYERS + 1):
				var candidate := 1 << index
				if (used & candidate) == 0:
					lease.layer = candidate
					break
		if lease.layer != 0:
			lease.preferred = lease.layer
			occupied[lease.world] = used | int(lease.layer)
	# Publish only after allocation is settled for every World and every actor.
	for lease in _leases.values():
		if lease.published != lease.layer:
			lease.published = lease.layer
			lease.publish.call(lease.layer)
	_synchronizing = false
	_disconnect_if_empty()


static func _disconnect_if_empty() -> void:
	if _leases.is_empty() and RenderingServer.frame_pre_draw.is_connected(synchronize):
		RenderingServer.frame_pre_draw.disconnect(synchronize)
