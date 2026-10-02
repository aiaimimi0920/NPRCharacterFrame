extends SceneTree
## Deterministic GPU evidence for hosiery, including feature-off controls.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const MODEL_PATH := (
	"res://addons/npr_character_frame/" + "samples/silver_wolf/scenes/silver_wolf.tscn"
)
const MATERIAL_PATH := (
	"res://addons/npr_character_frame/"
	+ "samples/silver_wolf/profiles/silver_wolf_npr11_materials.tres"
)
const BODY_SHADER_PATH := "res://addons/npr_character_frame/shaders/body/body_npr.gdshader"
const HOSIERY_INCLUDE_PATH := (
	"res://addons/npr_character_frame/" + "shaders/body/npr_hosiery.gdshaderinc"
)
const GENERATION_PATH := (
	"res://addons/npr_character_frame/"
	+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/generation.json"
)
var _wardrobe: Control
var _body: ShaderMaterial
var _output: String
var _checks: Array[Dictionary] = []
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("unused_scheme.json")
	root.add_child(_wardrobe)
	_wardrobe.performance.automatic = false
	_wardrobe.state.blink = false
	_wardrobe.state.secondary = false
	_wardrobe._apply_state()
	_body = _wardrobe.preview.materials[0]
	var baseline := OS.get_environment("NPR_HOSIERY_BASELINE_SHADER")
	if not baseline.is_empty():
		var reference := Shader.new()
		reference.code = FileAccess.get_file_as_string(baseline)
		_check(not reference.code.is_empty(), "Archived pre-change shader is readable")
		_body.shader = reference
	await _frames(8)
	_check(_wardrobe.preview.initialized, "Production character initialized")
	await _capture("full")
	_wardrobe.camera.h_offset = 0.0
	_wardrobe.camera.position = Vector3(0, 1.12, 2.65)
	_wardrobe.camera.look_at(Vector3(0, 1.05, 0))
	for percent in [0, 25, 50, 75, 100]:
		_set_transparency(percent / 100.0)
		await _capture("front_%03d" % percent)
	_body.set_shader_parameter("u_npr_wardrobe_enabled", false)
	await _capture("uncovered")
	_body.set_shader_parameter("u_npr_wardrobe_enabled", true)
	for angle in [45, 90, 180]:
		_wardrobe.turntable.rotation_degrees.y = angle
		_set_transparency(0.5)
		await _capture("angle_%03d" % angle)
		_set_transparency(1.0)
		await _capture("angle_%03d_bare" % angle)
	_wardrobe.turntable.rotation_degrees.y = 0.0
	_set_transparency(0.5)
	for yaw in [-85, 0, 85, 160]:
		_wardrobe.preview.light_yaw = yaw
		await _capture("light_%d" % yaw)
	_wardrobe.preview.light_yaw = -45.0
	await _capture("front_repeat")
	await _capture_controls()
	for step in 6:
		_wardrobe.turntable.rotation_degrees.y = step * 0.15
		_set_transparency(0.5)
		await _capture("motion_%02d" % step)
		_set_transparency(1.0)
		await _capture("motion_%02d_bare" % step)
	await _capture_detail()
	_check(
		_wardrobe.preview.meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] != null,
		"Animated body retains the authored hosiery domain"
	)
	var report := {
		"checks": _checks,
		"captures": _captures,
		"engine": Engine.get_version_info(),
		"input": _input_metadata(),
	}
	FileAccess.open(_output.path_join("hosiery.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	var failed := _checks.filter(func(check: Dictionary): return not check["pass"])
	_wardrobe.free()
	print("HOSIERY_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _capture_controls() -> void:
	var uniforms := _body.shader.get_shader_uniform_list()
	for feature in ["sheen_strength", "angle_strength", "weave_strength"]:
		var parameter: String = "u_npr_hosiery_" + feature
		# The same probe also captures the unmodified pre-research material.
		var present := uniforms.any(func(item: Dictionary): return item.name == parameter)
		if not present:
			continue
		var original: Variant = _body.get_shader_parameter(parameter)
		_body.set_shader_parameter(parameter, 0.0)
		await _capture("without_" + feature)
		_body.set_shader_parameter(parameter, original)
	_set_transparency(0.0)
	await _capture("opaque_lit")
	_wardrobe.preview.set_shadow_strength(0.0)
	await _capture("opaque_no_shadow")
	_wardrobe.preview.set_shadow_strength(0.28)
	_set_transparency(0.5)


func _set_transparency(value: float) -> void:
	_wardrobe.state.stocking_transparency = value
	_body.set_shader_parameter("u_npr_hosiery_opacity", 1.0 - value)


func _capture_detail() -> void:
	_wardrobe.turntable.rotation_degrees.y = 0.0
	for distance in [1.15, 1.6, 2.2, 3.6]:
		_wardrobe.camera.position = Vector3(0, 0.95, distance)
		_wardrobe.camera.look_at(Vector3(0, 0.9, 0))
		_set_transparency(0.5)
		var label := "detail_%03d" % roundi(distance * 100)
		await _capture(label)
		var strength: Variant = _body.get_shader_parameter("u_npr_hosiery_weave_strength")
		_body.set_shader_parameter("u_npr_hosiery_weave_strength", 0.0)
		await _capture(label + "_smooth")
		_body.set_shader_parameter("u_npr_hosiery_weave_strength", strength)
		_set_transparency(1.0)
		await _capture(label + "_bare")
	_wardrobe.camera.position = Vector3(0, 0.95, 1.15)
	_wardrobe.camera.look_at(Vector3(0, 0.9, 0))
	for step in 6:
		_wardrobe.turntable.rotation_degrees.y = step * 0.15
		_set_transparency(0.5)
		await _capture("close_motion_%02d" % step)
		_set_transparency(1.0)
		await _capture("close_motion_%02d_bare" % step)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _capture(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var frame: Image = _wardrobe.viewport.get_texture().get_image()
	_check(frame.save_png(_output.path_join(label + ".png")) == OK, "GPU image saved: " + label)
	(
		_captures
		. append(
			{
				"name": label,
				"size": [frame.get_width(), frame.get_height()],
				"transparency": _wardrobe.state.stocking_transparency,
				"yaw": _wardrobe.turntable.rotation_degrees.y,
				"light_yaw": _wardrobe.preview.light_yaw,
				"camera": str(_wardrobe.camera.position),
			}
		)
	)


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("HOSIERY_FAILED: " + label)


func _input_metadata() -> Dictionary:
	var baseline := OS.get_environment("NPR_HOSIERY_BASELINE_SHADER")
	var body_shader_source := BODY_SHADER_PATH if baseline.is_empty() else baseline
	return {
		"scene":
		{"path": SCENE.resource_path, "sha256": FileAccess.get_sha256(SCENE.resource_path)},
		"model": {"path": MODEL_PATH, "sha256": FileAccess.get_sha256(MODEL_PATH)},
		"material": {"path": MATERIAL_PATH, "sha256": FileAccess.get_sha256(MATERIAL_PATH)},
		"body_shader": {"path": body_shader_source, "sha256": _sha256(body_shader_source)},
		"hosiery_include":
		{
			"path": HOSIERY_INCLUDE_PATH,
			"sha256": FileAccess.get_sha256(HOSIERY_INCLUDE_PATH),
		},
		"generation": {"path": GENERATION_PATH, "sha256": FileAccess.get_sha256(GENERATION_PATH)},
		"shader_override": baseline,
		"renderer":
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")),
		"viewport":
		[root.size.x, root.size.y, _wardrobe.viewport.size.x, _wardrobe.viewport.size.y],
		"parameters":
		{
			"u_npr_hosiery_opacity": _body.get_shader_parameter("u_npr_hosiery_opacity"),
			"u_npr_hosiery_compression_strength":
			_body.get_shader_parameter("u_npr_hosiery_compression_strength"),
			"u_npr_hosiery_weave_strength":
			_body.get_shader_parameter("u_npr_hosiery_weave_strength"),
		},
	}


func _sha256(path: String) -> String:
	if path.begins_with("res://"):
		return FileAccess.get_sha256(path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		context.update(file.get_buffer(1024 * 1024))
	file.close()
	return context.finish().hex_encode()
