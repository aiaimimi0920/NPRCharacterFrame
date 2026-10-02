class_name NPRExpressionController
extends RefCounted
## Deterministic, bounded arbitration. The caller owns time and the rendering adapter.
## Suppression never stops a speech/blink producer or restores an obsolete input.

const PROFILE = preload("res://addons/npr_character_frame/npr_expression_profile.gd")
const CHANNELS := ["eyes", "mouth", "brows", "color"]
const MAX_REQUESTS := 32

var profile: NPRExpressionProfile
var blink: Dictionary = {}
var speech: Dictionary = {}
var speech_active := false
var output: Dictionary = {}
var _base: Dictionary = {}
var _requests: Array[Dictionary] = []
var _serial := 0
var _smooth: Dictionary = {}
var _previous_symbols := Vector2i.ZERO


func set_base(pose: Dictionary) -> bool:
	if not PROFILE.valid_pose(pose):
		return false
	_base = pose.duplicate(true)
	return true


func play(behavior: StringName, duration: float, priority := 50, key: StringName = &"") -> int:
	if profile == null:
		return 0
	return push(profile.pose(behavior), duration, priority, key, behavior)


func push(
	pose: Dictionary,
	duration: float,
	priority := 50,
	key: StringName = &"",
	label: StringName = &"request"
) -> int:
	if not PROFILE.valid_pose(pose) or not is_finite(duration) or duration < 0.0:
		return 0
	var replacement := -1
	for index in _requests.size():
		if not key.is_empty() and _requests[index].key == key:
			replacement = index
			break
	if replacement < 0 and _requests.size() >= MAX_REQUESTS:
		return 0
	_serial += 1
	var request := {
		"token": _serial,
		"key": key,
		"label": label,
		"priority": priority,
		"remaining": duration,
		"timed": duration > 0.0,
		"pose": pose.duplicate(true)
	}
	if replacement >= 0:
		_requests[replacement] = request
	else:
		_requests.append(request)
	return _serial


func cancel(token: int) -> void:
	for index in range(_requests.size() - 1, -1, -1):
		if _requests[index].token == token:
			_requests.remove_at(index)


func clear() -> void:
	_requests.clear()
	_smooth.clear()
	_previous_symbols = Vector2i.ZERO


func active_count() -> int:
	return _requests.size()


func advance(delta: float) -> Dictionary:
	var step := maxf(delta, 0.0) if is_finite(delta) else 0.0
	for index in range(_requests.size() - 1, -1, -1):
		var request := _requests[index]
		if request.timed:
			request.remaining -= step
			if request.remaining <= 0.0:
				_requests.remove_at(index)
	var winners := {}
	var owners := {}
	for channel in CHANNELS:
		var winner := {"pose": _base, "priority": -2147483648, "token": 0, "label": &"base"}
		for request in _requests:
			if not _claims(request.pose, channel):
				continue
			if (
				request.priority > winner.priority
				or (request.priority == winner.priority and request.token > winner.token)
			):
				winner = request
		winners[channel] = winner.pose
		owners[channel] = String(winner.label)
	var eye_pose: Dictionary = winners.eyes
	var mouth_pose: Dictionary = winners.mouth
	var symbols := Vector2i(eye_pose.get("eye_symbol", 0), mouth_pose.get("mouth_symbol", 0))
	var resolved := {"owners": owners, "eye_symbol": symbols.x, "mouth_symbol": symbols.y}
	for channel in CHANNELS:
		var pose: Dictionary = winners[channel]
		var target: Variant = pose.get(channel, Vector3.ZERO if channel == "color" else {})
		var geometric_switch: bool = (
			(channel == "eyes" and (symbols.x != 0 or _previous_symbols.x != 0))
			or (channel == "mouth" and (symbols.y != 0 or _previous_symbols.y != 0))
		)
		var seconds := 0.0 if geometric_switch else float(pose.get("transition", 0.0))
		resolved[channel] = _blend(channel, target, step, seconds)
	if symbols.x != 0:
		resolved.eyes = {}
	elif not eye_pose.get("block_blink", false):
		for shape in blink:
			resolved.eyes[shape] = maxf(resolved.eyes.get(shape, 0.0), blink[shape])
		if not blink.is_empty():
			owners.eyes += " + blink"
	if symbols.y != 0:
		resolved.mouth = {}
	elif speech_active and not mouth_pose.get("block_speech", false):
		resolved.mouth = speech.duplicate()
		owners.mouth = "speech"
	resolved.eye_emphasis = eye_pose.get("eye_emphasis", 0.0)
	resolved.blink_suppressed = symbols.x != 0 or eye_pose.get("block_blink", false)
	resolved.speech_suppressed = symbols.y != 0 or mouth_pose.get("block_speech", false)
	_previous_symbols = symbols
	output = resolved
	return resolved


func _claims(pose: Dictionary, channel: String) -> bool:
	if pose.has(channel):
		return true
	if channel == "eyes":
		return pose.has("eye_symbol") or pose.has("eye_emphasis") or pose.has("block_blink")
	if channel == "mouth":
		return pose.has("mouth_symbol") or pose.has("block_speech")
	return false


func _blend(channel: String, target: Variant, delta: float, seconds: float) -> Variant:
	if seconds <= 0.0 or not _smooth.has(channel):
		_smooth[channel] = target.duplicate() if target is Dictionary else target
	elif target is Vector3:
		_smooth[channel] = (_smooth[channel] as Vector3).lerp(target, minf(delta / seconds, 1.0))
	else:
		var current: Dictionary = _smooth[channel]
		var keys: Array = target.keys()
		for shape in current:
			if shape not in keys:
				keys.append(shape)
		for shape in keys:
			current[shape] = lerpf(
				current.get(shape, 0.0), target.get(shape, 0.0), minf(delta / seconds, 1.0)
			)
	return _smooth[channel].duplicate() if _smooth[channel] is Dictionary else _smooth[channel]
