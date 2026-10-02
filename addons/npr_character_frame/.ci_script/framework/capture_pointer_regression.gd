extends SceneTree
## Real production tooltip, pending timer cancellation and exact non-hover restore.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const CLOCK = preload("capture_clock.gd")
const POINTER = preload("capture_pointer.gd")
var _scene: Control
var _output: String
var _checks: Array[Dictionary] = []
var _clock := CLOCK.new()


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	for size in [Vector2i(1152, 720), Vector2i(1440, 900)]:
		root.size = size
		_scene = SCENE.instantiate()
		_scene.save_path = _output.path_join("unused.json")
		root.add_child(_scene)
		_clock.bind(_scene.performance)
		for index in 10:
			await process_frame
			_clock.advance()
		await _test_size(str(size.x))
		_scene.free()
		await process_frame
	var failures := _checks.filter(func(check: Dictionary): return not check["pass"])
	FileAccess.open(_output.path_join("capture_pointer.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks}, "  ")
	)
	print("CAPTURE_POINTER_CHECKS=", _checks.size(), " FAILURES=", failures.size())
	print("REGRESSION_OK" if failures.is_empty() else "REGRESSION_FAILED")
	quit(0 if failures.is_empty() else 1)


func _test_size(prefix: String) -> void:
	var button := _scene.find_child("Palette0", true, false) as Button
	var tooltip := button.tooltip_text
	var state: Dictionary = _scene.state.to_data()
	var simulation := CLOCK.simulation_bytes(_scene.performance)
	var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.3
	POINTER.park(root)
	var neutral := await _capture(prefix + "_neutral")
	_check(root.gui_get_hovered_control() == null, prefix + " neutral pointer is outside controls")
	_hover(button)
	await create_timer(delay).timeout
	var hovered := await _capture(prefix + "_tooltip_visible")
	_check(root.gui_get_hovered_control() == button, prefix + " production palette is hovered")
	_check(_tooltip_visible(), prefix + " production tooltip appears after delay")
	_check(hovered != neutral, prefix + " visible tooltip changes actual GPU pixels")
	POINTER.park(root)
	var restored := await _capture(prefix + "_restored")
	_check(not _tooltip_visible(), prefix + " moving away closes visible tooltip")
	_check(restored == neutral, prefix + " full UI pixels restore exactly")
	_hover(button)
	_check(root.gui_get_hovered_control() == button, prefix + " pending hover input is delivered")
	POINTER.park(root)
	await create_timer(delay).timeout
	var pending := await _capture(prefix + "_pending_cancelled")
	_check(not _tooltip_visible(), prefix + " pending tooltip does not appear later")
	_check(pending == neutral, prefix + " pending cancellation preserves full UI pixels")
	_check(
		button.tooltip_text == tooltip and not tooltip.is_empty(), prefix + " tooltip is preserved"
	)
	_check(_scene.state.to_data() == state, prefix + " pointer does not change saved state")
	_check(
		CLOCK.simulation_bytes(_scene.performance) == simulation,
		prefix + " render waits do not advance simulation"
	)


func _hover(button: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion)


func _tooltip_visible() -> bool:
	for node in root.find_children("*", "PopupPanel", true, false):
		if node.visible:
			return true
	return false


func _capture(label: String) -> PackedByteArray:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(_output.path_join(label + ".png")) == OK, label + " saved")
	return image.get_data()


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("CAPTURE_POINTER_FAILED: " + label)
