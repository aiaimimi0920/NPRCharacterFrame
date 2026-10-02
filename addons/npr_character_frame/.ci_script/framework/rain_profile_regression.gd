extends SceneTree
## Validate authored rain inputs and prove all three paths reach the real GPU setup.

const PROFILE = preload("res://addons/npr_character_frame/npr_rain_profile.gd")
const RAIN = preload("res://addons/npr_character_frame/runtime/rain/npr_surface_rain.gd")
const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)

var _checks: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ProjectSettings.localize_path(OS.get_cmdline_user_args()[1])
	var source: NPRRainProfile = DEFINITION.rain_profile
	_check(source.validate().is_empty(), "Sample rain profile validates")
	_check(not PROFILE.new().validate().is_empty(), "Missing rain paths rejected")
	for field in ["surface_path", "chart_path", "vertex_uv_path"]:
		var invalid := source.duplicate() as NPRRainProfile
		invalid.set(field, "res://missing_rain_input")
		_check(not invalid.validate().is_empty(), field + " missing input rejected")
		invalid.set(field, ProjectSettings.globalize_path(source.get(field)))
		_check(not invalid.validate().is_empty(), field + " absolute path rejected")
	_test_structure()
	var profile := source.duplicate() as NPRRainProfile
	profile.surface_path = output.path_join("surface.json")
	profile.chart_path = output.path_join("chart.bin")
	profile.vertex_uv_path = output.path_join("vertex_uv.bin")
	var surface := source.load_surface()
	var first: int = surface.candidates[0]
	surface.candidates = [first]
	FileAccess.open(profile.surface_path, FileAccess.WRITE).store_string(JSON.stringify(surface))
	var chart := FileAccess.get_file_as_bytes(source.chart_path)
	chart[0] = 123
	FileAccess.open(profile.chart_path, FileAccess.WRITE).store_buffer(chart)
	var vertex := FileAccess.get_file_as_bytes(source.vertex_uv_path)
	vertex.encode_float(0, 0.125)
	FileAccess.open(profile.vertex_uv_path, FileAccess.WRITE).store_buffer(vertex)
	_check(profile.validate().is_empty(), "Alternate files validate")
	FileAccess.open(profile.chart_path, FileAccess.WRITE).store_buffer(chart.slice(0, -1))
	_check(not profile.validate().is_empty(), "Truncated chart rejected")
	FileAccess.open(profile.chart_path, FileAccess.WRITE).store_buffer(chart)
	FileAccess.open(profile.vertex_uv_path, FileAccess.WRITE).store_buffer(vertex.slice(0, -1))
	_check(not profile.validate().is_empty(), "Truncated vertex texture rejected")
	FileAccess.open(profile.vertex_uv_path, FileAccess.WRITE).store_buffer(vertex)
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.rain_profile = PROFILE.new()
	_check(not definition.validate().is_empty(), "Definition propagates rain errors")
	definition.rain_profile = null
	_check(definition.validate().is_empty(), "Base rendering permits no rain profile")
	definition.rain_profile = profile
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate profile initializes real character")
	if actor.initialized:
		var rain := RAIN.new()
		rain.setup(actor)
		_check(
			rain.data.candidates.size() == 1 and rain.data.candidates[0] == first,
			"Simulation reads alternate surface JSON"
		)
		_check(rain._cdf.size() == 1, "Spawn distribution uses alternate candidates")
		var texture: Texture2D = actor.materials[0].get_shader_parameter("u_npr_rain_vertex_uv")
		_check(
			texture.get_image().get_data() == vertex, "Body sampler receives alternate vertex BIN"
		)
		var stamp: ShaderMaterial = rain.field._stamp_materials[0]
		var chart_texture: Texture2D = stamp.get_shader_parameter("chart_map")
		_check(
			chart_texture.get_image().get_data() == chart, "Rain field receives alternate chart BIN"
		)
		_check(
			rain.drops.is_empty() and rain.water.is_empty(),
			"New instance starts without rain state"
		)
		_test_controls(rain, actor.materials[0])
	actor.free()
	_check(
		source.load_surface().candidates.size() > 1, "Loaded data mutation leaves source unchanged"
	)
	_check(
		FileAccess.get_file_as_bytes(source.chart_path) != chart, "Source chart remains unchanged"
	)
	_check(
		FileAccess.get_file_as_bytes(source.vertex_uv_path) != vertex, "Source UV remains unchanged"
	)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks}, "  ")
	)
	var passed := _checks.all(func(row: Dictionary): return row["pass"])
	print("REGRESSION_OK" if passed else "REGRESSION_FAILED")
	quit(0 if passed else 1)


func _test_controls(rain: RefCounted, material: ShaderMaterial) -> void:
	rain.configure(true, 60.0, 123, Vector3.ZERO, 1.34, 0.5)
	for frame in 96:
		rain.advance(1.0 / 24.0)
	var initial: Dictionary = rain.stats()
	_check(initial.births > 0 and initial.wet_triangles > 0, "Explicit inputs drive real rain flow")
	_check(
		material.get_shader_parameter("u_npr_rain_enabled"), "Explicit enable reaches Body shader"
	)
	rain.configure(true, 60.0, 123, Vector3(0.2, 0.4, 0.8), 1.2, 0.7)
	_check(rain.stats() == initial, "Surface changes preserve running simulation")
	rain.configure(true, 0.0, 123, Vector3.ZERO, 1.34, 0.5)
	for frame in 24:
		rain.advance(1.0 / 24.0)
	_check(
		rain.births == initial.births and rain.water.size() > 0,
		"Zero arrival rate stops new rain without discarding water"
	)
	rain.configure(true, 60.0, 456, Vector3.ZERO, 1.34, 0.5)
	_check(rain.births == 0 and rain.water.is_empty(), "Seed change clears previous water state")
	for frame in 96:
		rain.advance(1.0 / 24.0)
	_check(
		rain.stats().state_hash != initial.state_hash, "Different seed changes actual trajectory"
	)
	rain.configure(true, 60.0, 123, Vector3.ZERO, 1.34, 0.5)
	for frame in 96:
		rain.advance(1.0 / 24.0)
	_check(rain.stats() == initial, "Restoring seed reproduces the complete simulation record")
	rain.configure(false, 60.0, 123, Vector3.ZERO, 1.34, 0.5)
	_check(
		rain.drops.is_empty() and rain.water.is_empty() and rain.input_rate == 0.0,
		"Disabling clears droplets and water and stops arrivals"
	)
	_check(not material.get_shader_parameter("u_npr_rain_enabled"), "Disable reaches Body shader")
	var disabled: Dictionary = rain.stats()
	rain.advance(1.0)
	_check(rain.stats() == disabled, "Disabled simulation does not advance")
	rain.configure(true, 60.0, 123, Vector3.ZERO, 1.34, 0.5)
	for frame in 96:
		rain.advance(1.0 / 24.0)
	_check(rain.stats() == initial, "Re-enabling restarts deterministic rain")
	rain.configure(true, 60.0, 123, Vector3(0, 0, 1), 1.34, 0.5)
	rain.clear()
	for frame in 96:
		rain.advance(1.0 / 24.0)
	_check(
		rain.stats().state_hash != initial.state_hash,
		"Clothing wetness changes physical absorption on the selected metal triangle"
	)


func _test_structure() -> void:
	var valid := {
		"schema": 1,
		"size": [16, 16],
		"vertex_texture_height": 1,
		"positions": [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
		"uv": [[0, 0], [1, 0], [0, 1]],
		"indices": [[0, 1, 2]],
		"neighbors": [[-1, -1, -1]],
		"charts": [1],
		"areas": [0.5],
		"kinds": [1],
		"candidates": [0],
	}
	_check(PROFILE.validate_surface(valid).is_empty(), "Minimal boundary triangle validates")
	var replacements := {
		"schema": 2,
		"size": [16.5, 16],
		"vertex_texture_height": 0,
		"positions": [[NAN, 0, 0], [1, 0, 0], [0, 1, 0]],
		"uv": [[0, 0], [1.1, 0], [0, 1]],
		"indices": [[0, 1, 3]],
		"neighbors": [[-1, 1, -1]],
		"charts": [65536],
		"areas": [0],
		"kinds": [6],
		"candidates": [0.5],
	}
	for field in replacements:
		var invalid := valid.duplicate(true)
		invalid[field] = replacements[field]
		_check(not PROFILE.validate_surface(invalid).is_empty(), "Invalid " + field + " rejected")
	var mismatched := valid.duplicate(true)
	mismatched.neighbors.append([-1, -1, -1])
	_check(
		not PROFILE.validate_surface(mismatched).is_empty(), "Mismatched triangle arrays rejected"
	)

	for field in ["positions", "uv", "indices", "neighbors"]:
		var invalid := valid.duplicate(true)
		invalid[field][0] = {"unexpected": 1}
		_check(
			not PROFILE.validate_surface(invalid).is_empty(), "Non-array " + field + " row rejected"
		)


func _check(passed: bool, label: String) -> void:
	_checks.append({"label": label, "pass": passed})
	if not passed:
		push_error("RAIN_PROFILE_FAILED: " + label)
