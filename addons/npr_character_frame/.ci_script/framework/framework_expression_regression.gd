extends "res://addons/npr_character_frame/.ci_script/framework/symbolic_expression_regression.gd"

const CONTROLLER = preload("res://addons/npr_character_frame/runtime/npr_expression_controller.gd")
const PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/silver_wolf_expressions.tres"
)


func _run() -> void:
	_contract()
	_spawn()
	await _capture("neutral")
	var driver: Node = _wardrobe.performance
	var saved: Dictionary = _wardrobe.state.to_data()
	driver.blink_weight = 0.4
	driver.visemes = {"aa": 0.7}
	driver.expressions.play(&"surprised", 3.0, 40)
	driver.evaluate_expression()
	await _capture("speaking_surprised")
	_check(_shape("aa") > 0.69, "Speech overrides surprised mouth, not the upper face")
	_check(is_equal_approx(_shape("blink.L"), 0.4), "Blink coexists with surprise")
	var eyes: int = driver.expressions.play(&"squeeze", 0.5, 80)
	var mouth: int = driver.expressions.play(&"wave_mouth", 1.0, 70)
	driver.evaluate_expression()
	await _capture("both_symbols")
	_check(is_zero_approx(_shape("aa")), "Symbol mouth suppresses live speech geometry")
	_check(is_zero_approx(_shape("blink.L")), "Symbol eyes suppress live blink geometry")
	_check(_wardrobe.visual_layers._symbol_eyes.visible, "Eye replacement drawn in same frame")
	_check(_wardrobe.visual_layers._symbol_mouth.visible, "Mouth replacement drawn in same frame")
	driver.visemes = {"oh": 0.3}
	driver.blink_weight = 0.6
	driver.evaluate_expression(0.6)
	_check(not driver.symbolic_eyes and driver.symbolic_mouth, "Independent expiry")
	_check(is_equal_approx(_shape("blink.R"), 0.6), "Latest blink restored after expiry")
	driver.expressions.cancel(mouth)
	driver.expressions.cancel(eyes)
	driver.evaluate_expression()
	_check(is_equal_approx(_shape("oh"), 0.3), "Cancel restores current phoneme, not old aa")
	_check(_wardrobe.state.to_data() == saved, "Temporary behavior never writes saved preferences")
	driver.expressions.clear()
	driver.visemes = {}
	driver.blink_weight = 0.0
	driver.evaluate_expression()
	await _capture("restored")
	_check(_same_image("neutral", "restored"), "Clearing requests restores exact original pixels")
	_immediate_evaluation()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "captures": _captures}, "  ")
	)
	_wardrobe.free()
	print("EXPRESSION_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _immediate_evaluation() -> void:
	var driver: Node = _wardrobe.performance
	var saved: Dictionary = _wardrobe.state.to_data()
	var inputs := {}
	for field in ["blink_weight", "visemes", "expression", "base_eye_symbol", "base_mouth_symbol"]:
		inputs[field] = driver.get(field)
	var was_paused: bool = driver.is_paused()
	driver.set_paused(true)
	driver.expression = 0
	driver.base_eye_symbol = 0
	driver.base_mouth_symbol = 0
	driver.expressions.clear()
	var clocks := [driver.clock, driver._blink_clock, driver._spring, driver._wind_spring]
	var palette: Array = driver._pose_palette.duplicate()
	var events: Array[Dictionary] = []
	var poses: Array[bool] = []
	var on_pose := func(): poses.append(true)
	var on_expression := func(frame: Dictionary):
		(
			events
			. append(
				{
					"frame": frame.duplicate(true),
					"blink": _shape("blink.L"),
					"aa": _shape("aa"),
					"oh": _shape("oh"),
					"eyes": _wardrobe.visual_layers._symbol_eyes.visible,
					"mouth": _wardrobe.visual_layers._symbol_mouth.visible,
				}
			)
		)
	driver.pose_applied.connect(on_pose)
	driver.expression_evaluated.connect(on_expression)
	driver.blink_weight = 0.4
	driver.visemes = {"aa": 0.7}
	driver.evaluate_expression()
	_check(events.size() == 1, "Public evaluation synchronously emits one expression event")
	_check(
		is_equal_approx(events[-1].blink, 0.4), "Expression signal observes applied blink geometry"
	)
	_check(
		is_equal_approx(events[-1].aa, 0.7), "Expression signal observes applied speech geometry"
	)
	driver.expressions.play(&"squeeze", 0.5, 80)
	var mouth: int = driver.expressions.play(&"wave_mouth", 1.0, 70)
	driver.evaluate_expression()
	_check(
		events[-1].eyes and events[-1].mouth,
		"Face presentation updates before later signal observers"
	)
	_check(
		is_zero_approx(events[-1].blink) and is_zero_approx(events[-1].aa),
		"Symbols suppress geometry while paused"
	)
	var requests: Array = driver.expressions._requests.duplicate(true)
	driver.evaluate_expression()
	_check(
		driver.expressions._requests == requests, "Default zero delta preserves request lifetime"
	)
	driver.blink_weight = 0.6
	driver.visemes = {"oh": 0.3}
	driver.evaluate_expression(0.6)
	_check(
		not events[-1].eyes and events[-1].mouth,
		"Explicit expression delta expires eyes independently"
	)
	_check(is_equal_approx(events[-1].blink, 0.6), "Expired symbol restores latest blink input")
	_check(events[-1].frame.speech_suppressed, "Live mouth symbol retains speech ownership")
	driver.expressions.cancel(mouth)
	driver.evaluate_expression()
	_check(
		is_equal_approx(events[-1].oh, 0.3),
		"Cancel restores latest phoneme without advancing action"
	)
	_check(not events[-1].mouth, "Cancel synchronously restores original mouth representation")
	_check(
		events[-1].frame.owners.mouth == "speech", "Latest speech producer regains mouth ownership"
	)
	_check(events.size() == 5, "Each public evaluation emits exactly one expression event")
	_check(poses.is_empty(), "Immediate face evaluation never emits pose_applied")
	_check(
		clocks == [driver.clock, driver._blink_clock, driver._spring, driver._wind_spring],
		"Face-only delta leaves action and simulation clocks unchanged"
	)
	_check(driver._pose_palette == palette, "Face-only evaluation preserves bone palette")
	_check(driver.is_paused(), "Public evaluation preserves explicit action pause")
	_check(_wardrobe.state.to_data() == saved, "Immediate evaluation never writes saved scheme")
	driver.expression_evaluated.disconnect(on_expression)
	driver.pose_applied.disconnect(on_pose)
	driver.expressions.clear()
	for field in inputs:
		driver.set(field, inputs[field])
	driver.evaluate_expression()
	driver.set_paused(was_paused)


func _contract() -> void:
	var control := CONTROLLER.new()
	control.profile = PROFILE
	control.set_base({"eyes": {}, "mouth": {}, "color": Vector3.ZERO})
	control.blink = {"left": 0.4, "right": 0.7}
	control.speech = {"aa": 0.8}
	control.speech_active = true
	var low := control.push({"eyes": {}, "eye_symbol": 1}, 0.0, 10)
	var high := control.push({"eyes": {}, "eye_symbol": 3}, 0.0, 20)
	_check(control.advance(0).eye_symbol == 3, "Higher priority owns eyes")
	var latest := control.push({"eyes": {}, "eye_symbol": 4}, 0.0, 20)
	_check(control.advance(0).eye_symbol == 4, "Latest wins equal priority")
	control.cancel(latest)
	_check(control.advance(0).eye_symbol == 3, "Cancel exposes still-live lower layer")
	control.cancel(high)
	_check(control.advance(0).eye_symbol == 1, "Second cancel exposes original request")
	control.cancel(low)
	var frame := control.advance(0)
	_check(
		frame.eyes.left == 0.4 and frame.eyes.right == 0.7, "Independent procedural eyes retained"
	)
	_check(frame.mouth.aa == 0.8, "Eye ownership leaves speech intact")
	control.push({"brows": {"frown": 0.9}, "color": Vector3(0.6, 0, 0)}, 1.0)
	control.set_base({"color": Vector3(0, 0, 0.5)})
	control.advance(0.5)
	_check(control.advance(0.5).color == Vector3(0, 0, 0.5), "Expiry resolves new base input")
	control.play(&"shy", 0.0, 50, &"emotion")
	frame = control.advance(0.03)
	_check(frame.color.z > 0.5 and frame.color.z < 0.8, "Ordinary color transition is smooth")
	control.play(&"tense", 0.0, 50, &"emotion")
	_check(control.active_count() == 1, "Replacement key keeps one request")
	_check(
		control.play(&"missing", 1.0) == 0,
		"Unknown behavior rejected without changing active layer"
	)
	_check(control.push({"mouth": {"aa": NAN}}, 1.0) == 0, "Invalid weights rejected atomically")
	control.clear()
	control.push({"mouth": {"oh": 0.2}, "block_speech": true}, 0.1)
	_check(control.advance(0).mouth == {"oh": 0.2}, "Explicit speech suppression")
	control.speech = {"ee": 0.6}
	_check(control.advance(0.2).mouth == {"ee": 0.6}, "Suppressed producer remains live")
	for index in control.MAX_REQUESTS:
		_check(control.play(&"squeeze", 0.0) > 0, "Bounded request slot %d" % index)
	_check(control.play(&"squeeze", 0.0) == 0, "Request capacity is bounded")
	control.clear()
	_check(control.active_count() == 0, "Reset clears all request lifetimes")
	_check(PROFILE.pose(&"surprised").mouth.oh == 0.6, "Shared profile not mutated by instance")


func _shape(name: String) -> float:
	var face: MeshInstance3D = _wardrobe.preview.meshes[1]
	return face.get_blend_shape_value(face.find_blend_shape_by_name(name))


func _same_image(first: String, second: String) -> bool:
	var a := Image.load_from_file(_output.path_join(first + ".png"))
	var b := Image.load_from_file(_output.path_join(second + ".png"))
	return a != null and b != null and a.get_data() == b.get_data()
