extends SceneTree
## Real engine delta only: never bind CaptureClock or call simulation _process manually.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const POINTER = preload("capture_pointer.gd")
var _scene: Control
var _output: String
var _checks: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _cycle := 0


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	var connections := RenderingServer.frame_pre_draw.get_connections().size()
	for cycle in 3:
		_cycle = cycle
		_scene = SCENE.instantiate()
		_scene.save_path = _output.path_join("cycle_%d.json" % cycle)
		root.add_child(_scene)
		POINTER.park(root)
		await _frames(12, "startup")
		_check(_scene.preview.initialized, "Fresh scene initializes")
		_check(_scene.performance.automatic, "Real automatic animation is enabled")
		_check(_scene.performance.is_processing(), "Animation owns its engine process callback")
		_check(_scene.visual_layers.is_processing(), "Rain owns its engine process callback")
		_scene.save_scheme()
		var factory := FileAccess.get_file_as_bytes(_scene.save_path)
		await _exercise()
		_scene.framework.set_locked(true)
		_scene.reset_scheme()
		_check(not _scene.framework.locked, "Reset releases A/B lock")
		_check(not _scene.performance.is_paused(), "Reset releases pose pause")
		_check(not _scene.visual_layers._paused, "Reset releases global rain pause")
		_check(not _scene.visual_layers._preview_paused, "Reset releases rain preview pause")
		_check(not _scene.performance.hair_dynamic_enabled, "Reset disables dynamic hair")
		_check(_scene.framework.comics.active_count() == 0, "Reset clears temporary comics")
		_check(_scene.visual_layers.surface_rain.drops.is_empty(), "Reset clears water drops")
		_check(_scene.visual_layers.surface_rain.water.is_empty(), "Reset clears water traces")
		_scene.save_scheme()
		_check(
			FileAccess.get_file_as_bytes(_scene.save_path) == factory, "Reset saves factory bytes"
		)
		await _frames(20, "reset_running")
		_check(_scene.performance.clock > 0.0, "Animation resumes after reset")
		_check(_scene.visual_layers.surface_rain.elapsed == 0.0, "Disabled rain stays reset")
		var weak := weakref(_scene)
		_scene.queue_free()
		_scene = null
		for index in 4:
			await process_frame
		_check(weak.get_ref() == null, "Queued scene is actually released")
		_check(
			RenderingServer.frame_pre_draw.get_connections().size() == connections,
			"Render callbacks return to pre-scene baseline"
		)
	_finish()


func _exercise() -> void:
	_scene._select_action(1)
	_scene._set_visual_option(true, "hair_dynamic_enabled")
	_scene._set_visual_option(true, "hair_collision_enabled")
	_scene._set_wind_strength(0.7)
	_scene._set_droplet_count(12)
	_scene._set_droplets_enabled(true)
	_scene.select_section(3)
	_scene.framework.duration = 30.0
	_scene.framework.play_comic("anger")
	await _frames(45, "active")
	_check(_scene.performance.clock > 0.0, "Animation advances with real frame delta")
	_check(_scene.performance.hair_dynamic_enabled, "Authored dynamic hair is active")
	_check(_scene.visual_layers.surface_rain.elapsed > 0.0, "Rain advances with real frame delta")
	_check(_scene.visual_layers.surface_rain.births > 0, "Continuous rain creates actual drops")
	_check(_scene.framework.comics.active_count() == 1, "Comic remains active before expiry")
	await _capture("active")
	var pause := _scene.find_child("DropletPreviewPause", true, false) as Button
	_check(pause != null and not pause.disabled, "Real rain pause control is available")
	pause.button_pressed = true
	var pose_time: float = _scene.performance.clock
	var moving_hair := _hair_bytes()
	var water := _water_bytes()
	await _frames(20, "rain_preview_paused")
	_check(_water_bytes() == water, "Rain-only pause freezes water evolution")
	_check(_scene.performance.clock > pose_time, "Rain-only pause does not freeze animation")
	_check(_hair_bytes() != moving_hair, "Dynamic hair continues during rain-only pause")
	_scene.select_section(0)
	_scene.select_section(3)
	pause = _scene.find_child("DropletPreviewPause", true, false) as Button
	_check(pause.button_pressed, "Page rebuild preserves actual rain pause toggle")
	var moving_pose := var_to_bytes(_scene.performance._pose_palette)
	await _frames(10, "rain_follows_pose")
	_check(
		var_to_bytes(_scene.performance._pose_palette) != moving_pose,
		"Pose continues deforming during rain-only pause"
	)
	_scene.framework.set_locked(true)
	var locked := _simulation_bytes()
	var saved: Dictionary = _scene.state.to_data()
	await _frames(24, "ab_locked")
	_check(_simulation_bytes() == locked, "A/B lock freezes pose, hair, water and comic clocks")
	_check(_scene.state.to_data() == saved, "Temporary pause/lock never changes saved state")
	await _capture("locked")
	_scene.framework.set_locked(false)
	_check(_scene.visual_layers._preview_paused, "Unlock retains pre-existing rain-only pause")
	pose_time = _scene.performance.clock
	await _frames(12, "unlocked_rain_paused")
	_check(_scene.performance.clock > pose_time, "Unlock resumes previously running animation")
	_check(_water_bytes() == water, "Unlock does not accidentally resume independently paused rain")
	pause.button_pressed = false
	await _frames(20, "resumed")
	_check(_water_bytes() != water, "Explicit rain resume advances the existing timeline")
	_scene.find_child("DropletPreviewRestart", true, false).pressed.emit()
	_check(_scene.visual_layers.surface_rain.elapsed == 0.0, "Rain restart clears time immediately")
	_check(_scene.visual_layers.surface_rain.drops.is_empty(), "Rain restart clears existing drops")
	_check(_scene.state.to_data() == saved, "Rain restart preserves saved settings")
	await _frames(20, "rain_restarted")
	_check(_scene.visual_layers.surface_rain.elapsed > 0.0, "Restarted rain advances automatically")
	_scene.framework.clear_effects()
	_scene.framework.duration = 0.1
	_scene.framework.play_comic("anger")
	await create_timer(0.3).timeout
	await _frames(3, "comic_expired")
	_check(_scene.framework.comics.active_count() == 0, "Temporary comic expires on real time")
	for action in [2, 3, 0]:
		_scene._select_action(action)
		await _frames(10, "action_" + str(action))
		_check(_finite_hair(), "Action switch keeps dynamic hair finite")
	_check(
		_scene.visual_layers.surface_rain.elapsed > 0.0, "Action switches preserve rain timeline"
	)
	_scene.performance.set_paused(true)
	_scene.visual_layers.set_paused(true)
	_scene.framework.set_locked(true)
	_scene.framework.set_locked(false)
	_check(_scene.performance.is_paused(), "Unlock restores pre-existing pose pause")
	_check(_scene.visual_layers._paused, "Unlock restores pre-existing global rain pause")


func _water_bytes() -> PackedByteArray:
	var rain = _scene.visual_layers.surface_rain
	return var_to_bytes(
		[
			rain.elapsed,
			rain.births,
			rain.crossings,
			rain.deposited,
			rain.water,
			rain.drops,
			rain.rng.state
		]
	)


func _hair_bytes() -> PackedByteArray:
	var hair: Array = []
	for chain: Dictionary in _scene.performance.dynamics.chains:
		hair.append([chain.points, chain.previous])
	return var_to_bytes(hair)


func _simulation_bytes() -> PackedByteArray:
	var comics: Array = []
	for effect: Dictionary in _scene.framework.comics._effects:
		comics.append(effect.elapsed)
	return var_to_bytes(
		[
			_scene.performance.clock,
			_scene.performance._pose_palette,
			_hair_bytes(),
			_water_bytes(),
			comics,
			_scene.camera.transform
		]
	)


func _finite_hair() -> bool:
	for chain: Dictionary in _scene.performance.dynamics.chains:
		for point: Vector3 in chain.points:
			if not point.is_finite():
				return false
	return true


func _frames(count: int, phase: String) -> void:
	for index in count:
		await process_frame
		await RenderingServer.frame_post_draw
		var rain: Dictionary = _scene.visual_layers.surface_rain.stats()
		_samples.append(
			{
				"cycle": _cycle,
				"phase": phase,
				"wall_usec": Time.get_ticks_usec(),
				"pose_clock": _scene.performance.clock,
				"rain": rain,
				"hair_finite": _finite_hair(),
				"automatic": _scene.performance.automatic,
				"processing": _scene.performance.is_processing(),
				"comics": _scene.framework.comics.active_count()
			}
		)
		_check_sample(rain)


func _check_sample(rain: Dictionary) -> void:
	if not _finite_hair() or rain.updates > rain.update_budget:
		_check(false, "Continuous sample violated finite hair or rain work budget")


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _scene.viewport.get_texture().get_image()
	_check(
		image.save_png(_output.path_join("%d_%s.png" % [_cycle, label])) == OK,
		"Live evidence image saved"
	)


func _check(value: bool, label: String) -> void:
	_checks.append({"cycle": _cycle, "label": label, "pass": value})
	if not value:
		push_error("REALTIME_LIFECYCLE_FAILED: " + label)


func _finish() -> void:
	var failed := _checks.filter(func(row: Dictionary): return not row["pass"])
	FileAccess.open(_output.path_join("realtime_lifecycle.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "samples": _samples}, "  ")
	)
	print("REALTIME_LIFECYCLE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)
