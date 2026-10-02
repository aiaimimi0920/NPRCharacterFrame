extends SceneTree
## P05 R3：固定 5+30 分钟真实调度，不加入日常 suite，不作为 Release EXE 证明。

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const DURATION := 2100.0
var _scene: Control
var _output: String
var _checks: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _first_frames: Array[float] = []
var _last_frames: Array[float] = []
var _events: Array[Dictionary] = []
var _budget_ok := true
var _max_updates := 0
var _max_active := 0


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	root.mouse_passthrough = true
	root.unfocusable = true
	_scene = SCENE.instantiate()
	_scene.save_path = _output.path_join("unused_scheme.json")
	root.add_child(_scene)
	_scene.select_section(8)
	_scene.state.hair_dynamic_enabled = true
	_scene.state.hair_collision_enabled = true
	_scene.state.wind_strength = 0.5
	_scene.state.action = 1
	_scene.state.droplets_enabled = true
	_scene.state.droplet_count = 12
	_scene.state.droplet_speed = 1.0
	_scene._apply_state()
	var rain: RefCounted = _scene.visual_layers.surface_rain
	var saved: Dictionary = _scene.state.to_data()
	var started := Time.get_ticks_usec()
	var previous := started
	var next_sample := 10.0
	var next_event := 0
	var event_times := [600.0, 602.0, 610.0, 900.0, 902.0, 1200.0, 1500.0, 1502.0, 1510.0]
	var frozen: Array = []
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var seconds := float(now - started) / 1000000.0
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		if seconds >= DURATION:
			break
		if seconds >= 300.0 and seconds < 600.0:
			_first_frames.append(frame_ms)
		if seconds >= 1800.0:
			_last_frames.append(frame_ms)
		_max_updates = maxi(_max_updates, rain.updates_last_frame)
		_max_active = maxi(_max_active, rain.drops.size())
		_budget_ok = (
			_budget_ok
			and rain.updates_last_frame <= rain.updates_per_frame
			and rain.drops.size() <= 320
		)
		if next_event < event_times.size() and seconds >= event_times[next_event]:
			match next_event:
				0, 6:
					_scene.framework.set_locked(true)
					frozen = [_scene.performance.clock, rain.elapsed]
				1, 7:
					_check(
						frozen == [_scene.performance.clock, rain.elapsed],
						"Locked pose and rain clocks remain exact"
					)
					_scene.framework.set_locked(false)
				2, 8:
					_check(
						_scene.performance.clock > frozen[0] and rain.elapsed > frozen[1],
						"Unlock resumes pose and rain clocks"
					)
				3:
					_scene._set_droplets_enabled(false)
				4:
					_scene._set_droplets_enabled(true)
				5:
					_scene.visual_layers.restart_droplet_preview()
			_events.append({"index": next_event, "wall_seconds": seconds})
			next_event += 1
		if seconds >= next_sample:
			(
				_samples
				. append(
					{
						"wall_seconds": seconds,
						"static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
						"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
						"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
						"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
						"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
						"render_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
						"rain_elapsed": rain.elapsed,
						"pose_clock": _scene.performance.clock,
						"active": rain.drops.size(),
						"updates": rain.updates_last_frame,
					}
				)
			)
			next_sample += 10.0
			_write("running")
			if int(next_sample) % 60 == 10:
				print("STABILITY_SECONDS=", int(seconds))
	_check(next_event == event_times.size(), "All fixed events executed")
	_check(_budget_ok, "Every observed frame respects rain budgets")
	_check(_scene.state.to_data() == saved, "Temporary sequence preserves configured scheme")
	_check(_scene.performance.clock > 0 and rain.elapsed > 0, "Simulation remains active at end")
	_first_frames.sort()
	_last_frames.sort()
	var first_p95 := _first_frames[int(_first_frames.size() * 0.95)]
	var last_p95 := _last_frames[int(_last_frames.size() * 0.95)]
	_check(last_p95 <= first_p95 * 1.25, "Same-configuration p95 degradation within 1.25x")
	var first := _samples.filter(
		func(row: Dictionary): return row.wall_seconds >= 300 and row.wall_seconds < 600
	)
	var last := _samples.filter(func(row: Dictionary): return row.wall_seconds >= 1800)
	for key in ["objects", "nodes", "orphans", "resources", "render_bytes"]:
		_check(_median(last, key) <= _median(first, key), "No steady-state accumulation: " + key)
	var initial_bytes := _median(first, "static_bytes")
	_check(
		_median(last, "static_bytes") <= initial_bytes + maxf(67108864.0, initial_bytes * 0.1),
		"Tracked memory growth within predeclared bound"
	)
	_scene.free()
	await process_frame
	await process_frame
	_write("finished")
	var failed := _checks.filter(func(row: Dictionary): return not row.passed)
	print("STABILITY_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _median(rows: Array, key: String) -> float:
	var values: Array[float] = []
	for row: Dictionary in rows:
		values.append(float(row[key]))
	values.sort()
	return values[values.size() / 2]


func _check(passed: bool, message: String) -> void:
	_checks.append({"passed": passed, "message": message})
	print("PASS " if passed else "FAIL ", message)


func _write(status: String) -> void:
	(
		FileAccess
		. open(_output.path_join("report.json"), FileAccess.WRITE)
		. store_string(
			(
				JSON
				. stringify(
					{
						"status": status,
						"duration_seconds": DURATION,
						"checks": _checks,
						"samples": _samples,
						"events": _events,
						"first_window_frame_ms": _first_frames,
						"last_window_frame_ms": _last_frames,
						"max_updates": _max_updates,
						"max_active": _max_active,
						"engine": Engine.get_version_info(),
					},
					"  "
				)
			)
		)
	)
