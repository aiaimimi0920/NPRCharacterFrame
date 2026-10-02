extends RefCounted
## Surface-bound rainfall: stochastic arrivals, triangle walking and persistent water.
## The atlas is independent of mirrored garment UVs. No global animation phase.
const MAX_DROPS := 320
const UPDATES_PER_FRAME := 32
const MAX_FRAME_DELTA := 0.05
const FIELD = preload("res://addons/npr_character_frame/runtime/rain/npr_rain_field.gd")
var actor: NPRCharacter
var data: Dictionary
var positions := PackedVector3Array()
var uvs := PackedVector2Array()
var drops: Array[Dictionary] = []
var water: Dictionary = {}
var rng := RandomNumberGenerator.new()
var field: RefCounted
var size := Vector2i.ZERO
var elapsed := 0.0
var births := 0
var crossings := 0
var deposited := 0.0
var input_rate := 0.0
var enabled := false
var updates_last_frame := 0
var updates_per_frame := UPDATES_PER_FRAME
var dropped_time := 0.0
var _display_clock := 0.0
var _cursor := 0
var _slots: Array[int] = []
var _arrival := 0.0
var _seed := 17
var _wetness := Vector3.ZERO
var _height := 1.34
var _opacity := 0.5
var _cdf := PackedFloat64Array()
var _total := 0.0
var _cache: Dictionary = {}
var _geometry: NPRGeometryState
var _world := Transform3D.IDENTITY
var _material: ShaderMaterial


func setup(character: NPRCharacter) -> void:
	var profile := character.definition.rain_profile
	assert(profile != null, "Continuous surface rain requires rain_profile")
	assert(profile.validate().is_empty(), "Invalid rain_profile")
	actor = character
	data = profile.load_surface()
	size = Vector2i(data.size[0], data.size[1])
	for p: Array in data.positions:
		positions.append(Vector3(p[0], p[1], p[2]))
	for uv: Array in data.uv:
		uvs.append(Vector2(uv[0], uv[1]))
	for t: int in data.candidates:
		_total += float(data.areas[t])
		_cdf.append(_total)
	field = FIELD.new()
	field.setup(actor, size, FileAccess.get_file_as_bytes(profile.chart_path), MAX_DROPS)
	_material = actor.materials[0]
	var vertex_image := Image.create_from_data(
		NPRRainProfile.VERTEX_TEXTURE_WIDTH,
		int(data.vertex_texture_height),
		false,
		Image.FORMAT_RGBAF,
		FileAccess.get_file_as_bytes(profile.vertex_uv_path)
	)
	_material.set_shader_parameter(
		"u_npr_rain_vertex_uv", ImageTexture.create_from_image(vertex_image)
	)
	_material.set_shader_parameter("u_npr_rain_vertex_count", positions.size())
	_material.set_shader_parameter("u_npr_rain_field", field.trails.get_texture())
	_material.set_shader_parameter("u_npr_rain_heads", field.heads.get_texture())
	_geometry = actor.meshes[0].get_node("NPRGeometryState") as NPRGeometryState
	clear()


func configure(
	rain_enabled: bool,
	arrivals_per_second: float,
	random_seed: int,
	surface_wetness: Vector3,
	hosiery_height: float,
	hosiery_opacity: float
) -> void:
	if _seed != random_seed or (enabled and not rain_enabled):
		_seed = random_seed
		clear()
	enabled = rain_enabled
	input_rate = arrivals_per_second if enabled else 0.0
	_wetness = surface_wetness
	_height = hosiery_height
	_opacity = hosiery_opacity
	_material.set_shader_parameter("u_npr_rain_enabled", enabled)


func clear() -> void:
	drops.clear()
	water.clear()
	elapsed = 0.0
	births = 0
	crossings = 0
	deposited = 0.0
	_display_clock = 0.0
	_cursor = 0
	updates_last_frame = 0
	dropped_time = 0.0
	_slots.clear()
	for slot in MAX_DROPS:
		_slots.append(MAX_DROPS - slot - 1)
	_arrival = 0.0
	rng.seed = _seed
	field.clear()


func advance(delta: float, speed: float = 1.0) -> void:
	updates_last_frame = 0
	if not enabled or delta <= 0.0 or speed <= 0.0:
		return
	# No catch-up loop: a slow frame or faster evolution never buys more CPU work.
	var wall_delta := minf(delta, MAX_FRAME_DELTA)
	var simulation_delta := wall_delta * clampf(speed, 0.0, 2.85)
	dropped_time += maxf(delta - wall_delta, 0.0)
	_display_clock += wall_delta
	elapsed += simulation_delta
	_arrival -= simulation_delta * input_rate
	for _attempt in 8:
		if _arrival > 0.0 or input_rate <= 0.0:
			break
		_arrival += -log(maxf(rng.randf(), 0.0001))
		if not _slots.is_empty():
			_spawn()
	_arrival = maxf(_arrival, 0.0)
	var batch: Array[Dictionary] = []
	var budget := clampi(updates_per_frame, 1, UPDATES_PER_FRAME)
	for i in mini(budget, drops.size()):
		batch.append(drops[(_cursor + i) % drops.size()])
	_cursor = (_cursor + batch.size()) % maxi(drops.size(), 1)
	_cache.clear()
	_world = actor.meshes[0].global_transform
	_batch_triangles(batch)
	var span := maxf(wall_delta, wall_delta * ceil(float(drops.size()) / budget))
	for drop in batch:
		_update_drop(drop, minf(span * speed, 0.25), span)
		updates_last_frame += 1
	field.present(_display_clock, simulation_delta)


func _triangle(t: int) -> PackedVector3Array:
	if not _cache.has(t):
		var ids := PackedInt32Array(data.indices[t])
		var samples := _geometry.sample_surface_vertices(0, ids)
		for i in samples.size():
			samples[i] = _world * samples[i]
		_cache[t] = samples
	return _cache[t]


func _batch_triangles(batch: Array[Dictionary]) -> void:
	var needed: Dictionary = {}
	for drop in batch:
		needed[int(drop.triangle)] = true
		for neighbor: int in data.neighbors[int(drop.triangle)]:
			if neighbor >= 0:
				needed[neighbor] = true
	var indices := PackedInt32Array()
	var keys := needed.keys()
	for t: int in keys:
		indices.append_array(PackedInt32Array(data.indices[t]))
	var samples := _geometry.sample_surface_vertices(0, indices)
	for i in keys.size():
		var at := i * 3
		_cache[int(keys[i])] = PackedVector3Array(
			[_world * samples[at], _world * samples[at + 1], _world * samples[at + 2]]
		)


func _uv(t: int, bary: Vector3) -> Vector2:
	var ids: Array = data.indices[t]
	return uvs[ids[0]] * bary.x + uvs[ids[1]] * bary.y + uvs[ids[2]] * bary.z


func _kind(t: int, bary: Vector3) -> int:
	var kind := int(data.kinds[t])
	if kind == 5:
		var ids: Array = data.indices[t]
		var height := (
			positions[ids[0]].y * bary.x
			+ positions[ids[1]].y * bary.y
			+ positions[ids[2]].y * bary.z
		)
		if height >= _height or _opacity < 0.01:
			kind = 0
	return kind


func _update_drop(drop: Dictionary, step: float, span: float) -> void:
	var previous := _snapshot(drop)
	var previous_chart := int(data.charts[int(drop.triangle)])
	if drop.dead:
		if _display_clock < float(drop.display_start) + float(drop.display_span):
			return
		field.write(drop.slot, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO)
		_slots.append(int(drop.slot))
		drops.erase(drop)
		return
	# Begin the next trajectory at the currently displayed point if cadence changes.
	if drop.has("display_from") and drop.display_chart == previous_chart:
		var blend := clampf((_display_clock - drop.display_start) / drop.display_span, 0.0, 1.0)
		previous = (drop.display_from as Vector4).lerp(previous, blend)
	if drop.age == 0.0:
		previous.w = 0.0
	drop.age += step
	var kind := _kind(drop.triangle, drop.bary)
	var saturation := maxf(
		_saturation(drop.triangle), _wetness[1 if kind == 5 else (0 if kind == 0 else 2)]
	)
	var absorb: float = [0.08, 0.85, 0.18, 0.015, 0.01, 0.22][kind]
	drop.volume *= exp(-absorb * lerpf(1.0, 0.12, saturation) * step)
	if drop.age > drop.pin:
		var mobility: float = [0.038, 0.007, 0.028, 0.065, 0.07, 0.032][kind]
		drop.velocity = move_toward(
			float(drop.velocity), mobility * sqrt(float(drop.volume)), step * 0.03
		)
		_walk(drop, float(drop.velocity) * step)
	_stamp(drop)
	drop.dead = drop.dead or drop.volume < 0.08 or drop.age > 16.0
	var next := _snapshot(drop)
	if drop.dead:
		next.w = 0.0
	field.write(
		drop.slot,
		previous,
		next,
		Vector4(_display_clock, span, previous_chart, int(data.charts[int(drop.triangle)]))
	)
	drop.display_from = previous
	drop.display_start = _display_clock
	drop.display_span = span
	# A seam crossfade has two unrelated atlas coordinates; never interpolate
	# that pair again as if it were a trajectory inside the destination chart.
	drop.display_chart = previous_chart


func _spawn() -> void:
	var target := rng.randf() * _total
	var index := _cdf.bsearch(target)
	var t := int(data.candidates[mini(index, _cdf.size() - 1)])
	var a := sqrt(rng.randf())
	var b := rng.randf()
	var bary := Vector3(1.0 - a, a * (1.0 - b), a * b)
	if _kind(t, bary) == 0:
		return
	births += 1
	(
		drops
		. append(
			{
				"slot": _slots.pop_back(),
				"triangle": t,
				"bary": bary,
				"age": 0.0,
				"volume": rng.randf_range(0.5, 1.0),
				"radius": rng.randf_range(0.0014, 0.0026),
				"pin": rng.randf_range(0.15, 1.5),
				"velocity": 0.0,
				"dead": false,
			}
		)
	)


func _bary(p: Vector3, tri: PackedVector3Array) -> Vector3:
	var e := tri[1] - tri[0]
	var f := tri[2] - tri[0]
	var q := p - tri[0]
	var det := maxf(e.dot(e) * f.dot(f) - e.dot(f) * e.dot(f), 1e-16)
	var v := (q.dot(e) * f.dot(f) - q.dot(f) * e.dot(f)) / det
	var w := (q.dot(f) * e.dot(e) - q.dot(e) * e.dot(f)) / det
	return Vector3(1.0 - v - w, v, w)


func _walk(drop: Dictionary, distance: float) -> void:
	var visited: Array[int] = []
	for _iteration in 8:
		var t: int = drop.triangle
		visited.append(t)
		var tri := _triangle(t)
		if tri.size() != 3:
			drop.dead = true
			return
		var normal := (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
		var downhill := Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
		var p: Vector3 = tri[0] * drop.bary.x + tri[1] * drop.bary.y + tri[2] * drop.bary.z
		var destination := _bary(p + downhill * distance, tri)
		var change: Vector3 = destination - drop.bary
		var fraction := 1.0
		var edge := -1
		for k in 3:
			if destination[k] < -0.000001 and change[k] < -0.000001:
				var hit: float = -drop.bary[k] / change[k]
				if hit < fraction:
					fraction = maxf(hit, 0.0)
					edge = k
		drop.bary += change * fraction
		_stamp(drop)
		if edge < 0:
			return
		var next := int(data.neighbors[t][edge])
		if next in visited:
			# A local geometric valley pins the bead; do not bounce across its edge.
			drop.velocity = 0.0
			drop.pin = drop.age + 0.3
			return
		if next < 0 or int(data.kinds[next]) == 0:
			drop.dead = true
			return
		p = tri[0] * drop.bary.x + tri[1] * drop.bary.y + tri[2] * drop.bary.z
		drop.triangle = next
		drop.bary = _bary(p, _triangle(next)).clamp(Vector3.ZERO, Vector3.ONE)
		drop.bary /= maxf(drop.bary.x + drop.bary.y + drop.bary.z, 0.00001)
		distance *= 1.0 - fraction
		crossings += 1


func _snapshot(drop: Dictionary) -> Vector4:
	var t: int = drop.triangle
	var ids: Array = data.indices[t]
	var center := _uv(t, drop.bary) * Vector2(size)
	# Atlas charts preserve original UV orientation. Metric converts mm to texels.
	var physical := maxf((positions[ids[1]] - positions[ids[0]]).length(), 0.0001)
	var metric := (uvs[ids[1]] - uvs[ids[0]]).length() * float(size.x) / physical
	var radius := clampf(float(drop.radius) * metric * pow(float(drop.volume), 0.3333), 0.7, 3.5)
	return Vector4(center.x, center.y, radius, minf(float(drop.volume) * 2.0, 1.0))


func _saturation(triangle: int) -> float:
	var sample: Vector2 = water.get(triangle, Vector2.ZERO)
	return sample.x * exp(-maxf(elapsed - sample.y, 0.0) * 0.13)


func _stamp(drop: Dictionary) -> void:
	# Coarse, lazily decayed absorption state is bounded by mesh triangle count.
	# The visible high-resolution history lives entirely in the GPU field.
	var previous := _saturation(drop.triangle)
	var next := maxf(previous, 0.65 * float(drop.volume))
	water[int(drop.triangle)] = Vector2(next, elapsed)
	deposited += next - previous


func stats() -> Dictionary:
	return {
		"elapsed": elapsed,
		"births": births,
		"active": drops.size(),
		"wet_triangles": water.size(),
		"crossings": crossings,
		"deposited": deposited,
		"state_hash": hash([elapsed, births, crossings, deposited]),
		"updates": updates_last_frame,
		"update_budget": updates_per_frame,
		"dropped_time": dropped_time,
	}
