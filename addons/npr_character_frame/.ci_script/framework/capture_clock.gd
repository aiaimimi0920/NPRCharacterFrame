extends RefCounted
## Test-owned simulation time. Rendering waits never supply an unmeasured delta.

const STEP := 1.0 / 60.0
var ticks := 0
var _driver: Node


func bind(driver: Node) -> void:
	_driver = driver
	ticks = 0
	_driver.automatic = false
	_driver.set_process(false)


func advance() -> void:
	if not is_instance_valid(_driver):
		return
	if _driver.is_processing() or _driver.automatic:
		push_error("Capture clock requires exclusive ownership of simulation time")
		return
	_driver._process(STEP)
	ticks += 1


func snapshot() -> Dictionary:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(simulation_bytes(_driver))
	return {
		"ticks": ticks,
		"step_seconds": STEP,
		"clip_time": _driver.clock,
		"automatic": _driver.automatic,
		"processing": _driver.is_processing(),
		"simulation_sha256": digest.finish().hex_encode(),
	}


static func simulation_bytes(driver: Node) -> PackedByteArray:
	var points: Array = []
	for chain: Dictionary in driver.dynamics.chains:
		points.append([chain.points, chain.previous, chain.initialized])
	return var_to_bytes(
		[
			driver._pose_palette,
			driver._face_values,
			driver._spring,
			driver._velocity,
			driver._wind_spring,
			driver._wind_velocity,
			driver.dynamics.accumulator,
			points,
			driver.expressions.output,
		]
	)
