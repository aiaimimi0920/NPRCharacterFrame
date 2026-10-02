extends SceneTree
## Controlled frame-delta experiment using the real showcase and active dynamics.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const CAPTURE_CLOCK = preload("capture_clock.gd")
const STEP := CAPTURE_CLOCK.STEP
const TICKS := 48
var _output: String
var _checks: Array[Dictionary] = []
var _trials: Dictionary = {}


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1440, 900)
	root.mouse_passthrough = true
	root.unfocusable = true
	var reference: Dictionary = await _trial("fixed", STEP, 0)
	var delayed: Dictionary = await _trial("delayed_render", STEP, 12)
	var recreated: Dictionary = await _trial("recreated", STEP, 0)
	var different_delta: Dictionary = await _trial("different_delta", STEP * 2.0, 0)
	for pair in [["delayed render", delayed], ["fresh scene", recreated]]:
		_check(reference.state == pair[1].state, pair[0] + " preserves exact simulation bytes")
		_check(reference.pixels == pair[1].pixels, pair[0] + " preserves exact GPU pixels")
	_check(
		reference.state != different_delta.state, "Different delta changes real simulation state"
	)
	_check(reference.pixels != different_delta.pixels, "Different delta changes real GPU pixels")
	FileAccess.open(_output.path_join("capture_clock.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "trials": _trials, "ticks": TICKS, "step": STEP}, "  ")
	)
	var failures := _checks.filter(func(row: Dictionary): return not row["pass"])
	print("CAPTURE_CLOCK_CHECKS=", _checks.size(), " FAILURES=", failures.size())
	print("REGRESSION_OK" if failures.is_empty() else "REGRESSION_FAILED")
	quit(0 if failures.is_empty() else 1)


func _trial(label: String, delta: float, render_every: int) -> Dictionary:
	var scene := SCENE.instantiate()
	scene.save_path = _output.path_join(label + "_unused_scheme.json")
	root.add_child(scene)
	var driver: Node = scene.performance
	var capture_clock := CAPTURE_CLOCK.new()
	capture_clock.bind(driver)
	scene.state.action = 1
	scene.state.secondary = true
	scene.state.hair_dynamic_enabled = true
	scene.state.hair_collision_enabled = true
	scene.state.wind_strength = 0.65
	scene._apply_state()
	driver.clock = 1.5
	driver.apply_pose(driver.clock, 0.0)
	await _render_frames()
	var start: PackedByteArray = scene.viewport.get_texture().get_image().get_data()
	for tick in TICKS:
		# Exercise exactly the same entry point as Node processing, with owned time.
		if delta == STEP:
			capture_clock.advance()
		else:
			driver._process(delta)
		if render_every > 0 and (tick + 1) % render_every == 0:
			await _render_frames()
	await _render_frames()
	var before: PackedByteArray = CAPTURE_CLOCK.simulation_bytes(driver)
	var pixels: Image = scene.viewport.get_texture().get_image()
	_check(start != pixels.get_data(), label + " keeps visible dynamic response")
	_check(
		driver.secondary_enabled and driver.hair_dynamic_enabled and driver.hair_collision_enabled,
		label + " keeps secondary, hair and collision enabled"
	)
	_check(driver.clock == 1.5, label + " automatic=false freezes only the clip clock")
	await _render_frames()
	_check(
		CAPTURE_CLOCK.simulation_bytes(driver) == before,
		label + " render-only waits do not advance simulation"
	)
	_check(
		pixels.get_data() == scene.viewport.get_texture().get_image().get_data(),
		label + " render-only waits preserve exact pixels"
	)
	pixels.save_png(_output.path_join(label + ".png"))
	FileAccess.open(_output.path_join(label + "_simulation.bin"), FileAccess.WRITE).store_buffer(
		before
	)
	_trials[label] = {
		"delta": delta,
		"render_every": render_every,
		"clock": driver.clock,
		"spring": driver._spring,
		"wind_spring": driver._wind_spring,
		"accumulator": driver.dynamics.accumulator,
		"png_sha256": FileAccess.get_sha256(_output.path_join(label + ".png")),
		"simulation_sha256": FileAccess.get_sha256(_output.path_join(label + "_simulation.bin")),
	}
	scene.free()
	await _render_frames()
	return {"state": before, "pixels": pixels.get_data()}


func _render_frames() -> void:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("CAPTURE_CLOCK_FAILED: " + label)
