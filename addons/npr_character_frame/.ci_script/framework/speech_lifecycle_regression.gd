extends SceneTree
## Real AudioStreamPlayer/mixer clock; Dummy output does not verify audible speakers.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
var _scene: Control
var _output: String
var _checks: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _completion: Dictionary = {}


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	_scene = SCENE.instantiate()
	_scene.save_path = _output.path_join("speech_scheme.json")
	root.add_child(_scene)
	await _wait(0.2, "startup")
	_scene.save_scheme()
	var saved := FileAccess.get_file_as_bytes(_scene.save_path)
	_scene._play_speech_demo()
	_check(_scene.speech.player.playing, "Actual sample audio starts")
	await _wait(0.8, "manual_play")
	_check(_scene.speech.player.get_playback_position() > 0.0, "Actual mixer clock advances")
	_check(
		_samples.any(func(row: Dictionary): return not row.visemes.is_empty()),
		"Live cues drive visemes"
	)
	_scene.framework.clear_effects()
	_check(_scene.speech.player.playing, "Clearing idle workbench preserves manual audio")
	_scene.framework.set_locked(true)
	await _wait(0.1, "lock_settle")
	var position: float = _scene.speech.player.get_playback_position()
	var visemes: Dictionary = _scene.performance.visemes.duplicate()
	await _wait(0.25, "locked")
	_check(
		_scene.speech.player.get_playback_position() == position, "A/B pauses actual audio clock"
	)
	_check(_scene.performance.visemes == visemes, "A/B holds current phoneme")
	_scene.framework.set_locked(false)
	await _wait(0.2, "unlocked")
	_check(
		_scene.speech.player.get_playback_position() > position, "A/B unlock resumes audio clock"
	)
	_scene.speech.stop()
	_check(_scene.performance.visemes.is_empty(), "Explicit stop clears phonemes immediately")
	_scene.framework.play_sequence()
	_check(_scene.speech.player.playing, "Sequence starts its sample audio")
	_scene.framework.clear_effects()
	await _wait(0.8, "cancelled")
	_check(not _scene.speech.player.playing, "Cancel stops sequence-owned audio")
	_check(_scene.performance.expressions.active_count() == 0, "Cancel retires delayed eye request")
	_scene.framework.play_sequence()
	await _wait(0.1, "before_manual_takeover")
	_scene._play_speech_demo()
	_scene.framework.clear_effects()
	_check(_scene.speech.player.playing, "Cancel preserves later manual playback of the same clip")
	await _wait(0.8, "manual_takeover")
	_check(
		_scene.performance.expressions.active_count() == 0, "Takeover cancellation retires timer"
	)
	_scene.speech.stop()
	_scene._play_speech_demo()
	var demo_path: String = _scene.demo_speech_path
	_scene.demo_speech_path = ""
	_scene.framework.play_sequence()
	_scene.framework.clear_effects()
	_check(
		_scene.speech.player.playing, "Missing optional demo cannot claim pre-existing manual audio"
	)
	_scene.demo_speech_path = demo_path
	_scene.speech.stop()
	_scene.framework.play_sequence()
	_scene.speech.play()
	_scene.framework.clear_effects()
	_check(_scene.speech.player.playing, "Direct replay also replaces sequence playback ownership")
	_scene.speech.stop()
	_scene._play_speech_demo()
	_scene.demo_speech_path = _output.path_join("missing_clip.json")
	_scene.framework.play_sequence()
	_scene.framework.clear_effects()
	_check(_scene.speech.player.playing, "Failed demo load cannot claim manual playback")
	_scene.demo_speech_path = demo_path
	_scene.speech.stop()
	_scene.framework.play_sequence()
	_scene.demo_speech_path = ""
	_scene.framework.play_sequence()
	_scene.framework.clear_effects()
	_check(not _scene.speech.player.playing, "No-op reentry retains ownership of its earlier audio")
	_scene.demo_speech_path = demo_path
	_scene.framework.play_sequence()
	_check(_scene.speech.load_clip(demo_path), "Replacement clip loads without auto-play")
	var loaded_id: int = _scene.speech.playback_id
	_scene.framework.clear_effects()
	_check(
		_scene.speech.playback_id == loaded_id, "Successful load retires stale playback ownership"
	)
	_scene.framework.play_sequence()
	_scene.framework.play_sequence()
	await _wait(0.8, "sequence_reentry")
	_check(
		_scene.performance.expressions.active_count() == 2,
		"Reentry keeps one demo and one delayed eye request"
	)
	_scene.reset_scheme()
	_check(not _scene.speech.player.playing, "Reset cancels sequence-owned audio")
	_check(_scene.performance.visemes.is_empty(), "Sequence reset clears phonemes")
	await _wait(0.8, "reset")
	_check(
		_scene.performance.expressions.active_count() == 0, "Reset prevents delayed resurrection"
	)
	_scene._play_speech_demo()
	var finished: Array[bool] = []
	_scene.speech.player.finished.connect(func(): finished.append(true))
	_scene.speech.player.stream_paused = true
	await _wait_for_finished(finished, 0.2, "completion_negative_paused")
	_check(
		(
			finished.is_empty()
			and _scene.speech.player.stream_paused
			and _scene.speech.player.has_stream_playback()
		),
		"Paused playback cannot satisfy the natural completion witness"
	)
	_scene.speech.player.stream_paused = false
	var started := Time.get_ticks_usec()
	# Dummy mixes on a sleeping worker thread, not a wall-clock-locked device.
	# Await the real finished signal; this deadline only bounds a stalled test.
	await _wait_for_finished(finished, _scene.speech.duration * 2.0 + 0.3, "natural_completion")
	_completion = {
		"duration": _scene.speech.duration,
		"elapsed_seconds": (Time.get_ticks_usec() - started) / 1000000.0,
		"finished_signals": finished.size(),
		"driver": AudioServer.get_driver_name(),
	}
	_check(finished.size() == 1, "Natural playback emits exactly one finished signal")
	_check(not _scene.speech.player.playing, "Actual audio completes naturally")
	_check(_scene.performance.visemes.is_empty(), "Finished signal clears phonemes")
	_scene.save_scheme()
	_check(
		FileAccess.get_file_as_bytes(_scene.save_path) == saved,
		"Speech lifecycle preserves scheme bytes"
	)
	_scene.framework.play_sequence()
	var actor: WeakRef = weakref(_scene)
	var player: WeakRef = weakref(_scene.speech.player)
	_scene.queue_free()
	_scene = null
	await create_timer(0.9).timeout
	_check(
		actor.get_ref() == null and player.get_ref() == null,
		"Exit before timer releases scene and player"
	)
	_scene = SCENE.instantiate()
	_scene.save_path = _output.path_join("fresh_scheme.json")
	root.add_child(_scene)
	await _wait(0.8, "fresh")
	_check(not _scene.speech.player.playing, "Fresh scene does not inherit old audio")
	_check(
		_scene.performance.expressions.active_count() == 0,
		"Fresh scene has no stale delayed expressions"
	)
	_scene.free()
	var failed := _checks.filter(func(row: Dictionary): return not row["pass"])
	FileAccess.open(_output.path_join("speech_lifecycle.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "samples": _samples, "completion": _completion}, "  ")
	)
	print("SPEECH_LIFECYCLE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	print("REGRESSION_OK" if failed.is_empty() else "REGRESSION_FAILED")
	quit(0 if failed.is_empty() else 1)


func _wait_for_finished(finished: Array[bool], timeout: float, phase: String) -> void:
	var deadline := Time.get_ticks_usec() + int(timeout * 1000000.0)
	while finished.is_empty() and Time.get_ticks_usec() < deadline:
		await _wait(0.01, phase)


func _wait(seconds: float, phase: String) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await process_frame
		_samples.append(
			{
				"phase": phase,
				"wall_usec": Time.get_ticks_usec(),
				"playing": _scene.speech.player.playing,
				"position": _scene.speech.player.get_playback_position(),
				"visemes": _scene.performance.visemes.duplicate()
			}
		)


func _check(value: bool, label: String) -> void:
	_checks.append({"label": label, "pass": value})
	if not value:
		push_error("SPEECH_LIFECYCLE_FAILED: " + label)
