extends SceneTree
## Real scene scheduling; visibility must not override an explicit pose pause.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
var _scene: Control
var _output: String
var _cycle := 0
var _checks: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _visibility_observations: Array[Dictionary] = []


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	var connections := RenderingServer.frame_pre_draw.get_connections().size()
	for cycle in 2:
		_cycle = cycle
		_scene = SCENE.instantiate()
		_scene.save_path = _output.path_join("scheme_%d.json" % cycle)
		root.add_child(_scene)
		await _frames(12, "startup")
		_scene.save_scheme()
		var factory := FileAccess.get_file_as_bytes(_scene.save_path)
		var target: Node3D = _scene.preview if cycle == 0 else _scene.turntable
		_check(_scene.preview.initialized, "Fresh actor initializes")
		_scene._select_action(1)
		_scene._set_visual_option(true, "hair_dynamic_enabled")
		_scene._set_visual_option(true, "hair_collision_enabled")
		_scene._set_visual_option(true, "tulle_geometry_enabled")
		_scene._set_soft_tissue_pressure(0.8)
		_scene._set_wind_strength(0.7)
		_scene._set_droplet_count(12)
		_scene._set_droplets_enabled(true)
		_scene.framework.duration = 60.0
		_scene.framework.overlay = true
		_scene.framework.play_behavior(&"star_eyes")
		_scene.framework.play_behavior(&"wave_mouth")
		_scene.framework.play_comic("anger")
		_scene.framework.play_comic("tear")
		await _frames(32, "active")
		_check(_scene.performance.automatic, "Automatic pose clock remains enabled")
		_check(_scene.visual_layers.surface_rain.births > 0, "Actual rain drops exist")
		_check(_scene.performance.dynamics.enabled, "Authored dynamic hair is enabled")
		_check(_pressure() > 0.0, "Authored pressure corrective is active")
		_check(_scene.visual_layers._symbol_eyes.visible, "Temporary symbol eyes are active")
		_check(_scene.visual_layers._symbol_mouth.visible, "Temporary symbol mouth is active")
		_scene.save_scheme()
		var saved := FileAccess.get_file_as_bytes(_scene.save_path)
		await _locked_visibility(target)
		await _running_visibility(target)
		await _manual_pause(target)
		_scene.save_scheme()
		_check(
			FileAccess.get_file_as_bytes(_scene.save_path) == saved,
			"Visibility preserves scheme bytes"
		)
		_scene.framework.set_locked(true)
		target.hide()
		await _frames(3, "hidden_before_reset")
		_scene.reset_scheme()
		_check(not target.visible, "Reset does not silently show the hidden node")
		_check(not _scene.framework.locked, "Hidden reset releases A/B lock")
		_check(not _scene.performance.is_paused(), "Hidden reset releases pose pause")
		_check(
			_scene.performance.expressions.active_count() == 0, "Hidden reset clears expressions"
		)
		_check(_scene.framework.comics.active_count() == 0, "Hidden reset clears comics")
		_check(_scene.visual_layers.surface_rain.drops.is_empty(), "Hidden reset clears drops")
		_check(
			_scene.visual_layers.surface_rain.water.is_empty(), "Hidden reset clears water traces"
		)
		target.show()
		await _frames(12, "reset_shown")
		_check(_scene.performance.clock > 0.0, "Factory animation resumes after hidden reset")
		_check(_scene.visual_layers.surface_rain.elapsed == 0.0, "Reset rain stays disabled")
		_scene.save_scheme()
		_check(
			FileAccess.get_file_as_bytes(_scene.save_path) == factory,
			"Hidden reset saves factory bytes"
		)
		var weak: WeakRef = weakref(_scene)
		_scene.queue_free()
		_scene = null
		for index in 4:
			await process_frame
		_check(weak.get_ref() == null, "Actor scene is released")
		_check(
			RenderingServer.frame_pre_draw.get_connections().size() == connections,
			"Render callbacks return to baseline"
		)
	_finish()


func _locked_visibility(target: Node3D) -> void:
	_scene.framework.set_locked(true)
	await _frames(4, "lock_settle")
	var pose := _pose_bytes()
	var water := _water_bytes()
	var effects := _effect_bytes()
	var image := _capture("locked_before")
	target.hide()
	await _frames(8, "locked_hidden")
	_check(not _scene.preview.is_visible_in_tree(), "Actor inherits hidden visibility")
	_check(_hidden_geometry(_scene.preview), "All actor geometry including face canvases is hidden")
	_check(_pose_bytes() == pose, "A/B hidden actor preserves exact pose and dynamics")
	_check(_water_bytes() == water, "A/B hidden actor preserves exact rain state")
	_check(_effect_bytes() == effects, "A/B hidden actor preserves temporary effect lifetimes")
	var hidden := _capture("locked_hidden")
	_check(hidden.get_data() != image.get_data(), "GPU hide is observable, not a no-op")
	target.show()
	await _frames(4, "locked_shown")
	_check(_scene.preview.is_visible_in_tree(), "Actor becomes visible again")
	_check(_pose_bytes() == pose, "A/B showing restores the exact locked pose and dynamics")
	_check(_water_bytes() == water, "A/B showing does not restart rain")
	_check(_effect_bytes() == effects, "A/B showing does not duplicate temporary requests")
	var restored := _capture("locked_restored")
	_check(
		restored.get_data() == image.get_data(),
		"A/B visible-hidden-visible restores exact GPU RGBA"
	)
	_scene.framework.set_locked(false)
	var clock: float = _scene.performance.clock
	await _frames(12, "unlocked")
	_check(_scene.performance.clock > clock, "Unlock resumes automatic motion")


func _running_visibility(target: Node3D) -> void:
	var clock: float = _scene.performance.clock
	var rain_time: float = _scene.visual_layers.surface_rain.elapsed
	target.hide()
	await _frames(3, "running_hide_settle")
	var pose := _pose_bytes()
	var requests := var_to_bytes(_scene.performance.expressions._requests)
	var effect_time: float = _scene.framework.comics._effects[0].elapsed
	_check(_pressure() == 0.0, "Unpaused hidden actor neutralizes pressure")
	_check(_neutral_hair(), "Unpaused hidden actor resets hair to current parent rest pose")
	await _frames(16, "running_hidden")
	_check(_scene.performance.clock == clock, "Unpaused hidden actor freezes its pose clock")
	_check(_pose_bytes() == pose, "Hidden neutral pose does not accumulate simulation debt")
	_check(
		var_to_bytes(_scene.performance.expressions._requests) == requests,
		"Expression durations follow the hidden pose clock"
	)
	_check(
		_scene.visual_layers.surface_rain.elapsed > rain_time,
		"Independent rain timeline continues hidden"
	)
	_check(
		_scene.framework.comics._effects[0].elapsed > effect_time,
		"Independent comic lifetime continues hidden"
	)
	_check(_hidden_geometry(_scene.preview), "Continuing timers do not reveal hidden geometry")
	target.show()
	await _frames(12, "running_shown")
	_check(_scene.performance.clock > clock, "Showing resumes the pose clock")
	_check(_pressure() > 0.0, "Showing restores current pressure")
	_check(not _neutral_hair(), "Showing restarts dynamic hair without stale hidden state")
	_check(_scene.visual_layers._symbol_eyes.is_visible_in_tree(), "Unexpired symbol eyes return")
	_check(
		_scene.visual_layers._symbol_mouth.is_visible_in_tree(), "Unexpired symbol mouth returns"
	)
	_scene.framework.clear_effects()
	_scene.framework.duration = 0.15
	_scene.framework.play_comic("anger")
	target.hide()
	await create_timer(0.4).timeout
	await _frames(2, "comic_expired_hidden")
	_check(_scene.framework.comics.active_count() == 0, "Unpaused comic expires while hidden")
	target.show()
	await _frames(3, "expired_shown")
	_check(_scene.framework.comics.active_count() == 0, "Expired comic never revives on show")
	_check(
		_scene.performance.expressions.active_count() == 0,
		"Cancelled hidden expressions never revive"
	)


func _manual_pause(target: Node3D) -> void:
	_scene.performance.set_paused(true)
	var pose := _pose_bytes()
	target.hide()
	_scene.performance.apply_pose(_scene.performance.clock + 3.0, 0.1)
	_check(_pose_bytes() == pose, "Explicit apply_pose respects pause while hidden")
	await _frames(4, "manually_paused_hidden")
	_check(_pose_bytes() == pose, "Engine process respects manual pause while hidden")
	target.show()
	await _frames(4, "manually_paused_shown")
	_check(_pose_bytes() == pose, "Manual paused pose survives hide/show")
	_check(_scene.performance.is_paused(), "Showing does not release a manual pause")
	_scene.performance.set_paused(false)


func _pressure() -> float:
	return _scene.preview.meshes[0].get_blend_shape_value(
		_scene.performance._soft_tissue_shape_index
	)


func _pose_bytes() -> PackedByteArray:
	var p: Node = _scene.performance
	var chains: Array = []
	for chain: Dictionary in p.dynamics.chains:
		chains.append([chain.points, chain.previous, chain.initialized])
	return var_to_bytes(
		[
			p.clock,
			p._blink_clock,
			p._pose_palette,
			chains,
			p.dynamics.accumulator,
			p._spring,
			p._velocity,
			p._wind_spring,
			p._wind_velocity,
			_pressure(),
			p._face_values
		]
	)


func _water_bytes() -> PackedByteArray:
	var rain: RefCounted = _scene.visual_layers.surface_rain
	return var_to_bytes(
		[
			rain.elapsed,
			rain.births,
			rain.crossings,
			rain.deposited,
			rain.water,
			rain.drops,
			rain.rng.state,
			rain._arrival,
			rain._cursor
		]
	)


func _effect_bytes() -> PackedByteArray:
	var times: Array = []
	for effect: Dictionary in _scene.framework.comics._effects:
		times.append([effect.token, effect.elapsed])
	return var_to_bytes([times, _scene.performance.expressions._requests])


func _neutral_hair() -> bool:
	for chain: Dictionary in _scene.performance.dynamics.chains:
		if chain.initialized:
			return false
		var parent: Transform3D = _scene.performance._pose_palette[int(chain.source.parent)]
		for index in chain.rest.size():
			if chain.points[index] != parent * chain.rest[index]:
				return false
	return true


func _hidden_geometry(node: Node) -> bool:
	var hidden := true
	if node is GeometryInstance3D and node.is_visible_in_tree():
		_visibility_observations.append(
			{
				"cycle": _cycle,
				"path": str(node.get_path()),
				"viewport": str(node.get_viewport().get_path()),
				"stage_world": node.get_world_3d() == _scene.preview.get_world_3d()
			}
		)
		# Disabled independent render targets may retain their last proxy visibility.
		hidden = (
			node.get_world_3d() != _scene.preview.get_world_3d()
			and node.get_viewport().render_target_update_mode == SubViewport.UPDATE_DISABLED
		)
	for child in node.get_children():
		if not _hidden_geometry(child):
			hidden = false
	return hidden


func _frames(count: int, phase: String) -> void:
	for index in count:
		await process_frame
		await RenderingServer.frame_post_draw
		var rain: Dictionary = _scene.visual_layers.surface_rain.stats()
		var finite := true
		for chain: Dictionary in _scene.performance.dynamics.chains:
			for point: Vector3 in chain.points:
				finite = finite and point.is_finite()
		_samples.append(
			{
				"cycle": _cycle,
				"phase": phase,
				"wall_usec": Time.get_ticks_usec(),
				"visible": _scene.preview.is_visible_in_tree(),
				"clock": _scene.performance.clock,
				"rain": rain,
				"hair_finite": finite
			}
		)
		if not finite or rain.updates > rain.update_budget:
			_check(false, "Continuous sample exceeded rain budget or finite hair contract")


func _capture(label: String) -> Image:
	var result: Image = _scene.viewport.get_texture().get_image()
	_check(result.save_png(_output.path_join("%d_%s.png" % [_cycle, label])) == OK, "Capture saved")
	return result


func _check(value: bool, label: String) -> void:
	_checks.append({"cycle": _cycle, "label": label, "pass": value})
	if not value:
		push_error("VISIBILITY_LIFECYCLE_FAILED: " + label)


func _finish() -> void:
	var failed := _checks.filter(func(row: Dictionary): return not row["pass"])
	FileAccess.open(_output.path_join("visibility_lifecycle.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"checks": _checks,
				"samples": _samples,
				"visibility_observations": _visibility_observations
			},
			"  "
		)
	)
	print("VISIBILITY_LIFECYCLE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)
