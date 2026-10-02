extends SceneTree
const SAMPLE_HEIGHT_PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/showcase_height.tres"
)
const SAMPLE_PALETTE_PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/showcase_palette.tres"
)

## Focused runtime, image and negative-control evidence for the six directions.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const STATE = preload("res://addons/npr_character_frame/showcase/wardrobe_state.gd")
const CAPTURE_CLOCK = preload("capture_clock.gd")
const CONTRACT := (
	"res://addons/npr_character_frame/"
	+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/visual_contract.json"
)
const MANIFEST := (
	"res://addons/npr_character_frame/"
	+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/visual_maps_generation.json"
)
const GEOMETRY := (
	"res://addons/npr_character_frame/"
	+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/visual_geometry_contract.json"
)
const HOSIERY_WEAVE_TEXTURE := preload(
	"res://addons/npr_character_frame/samples/silver_wolf/assets/runtime/hosiery_weave_v1.png"
)
const HOSIERY_ROUGHNESS_TEXTURE := preload(
	"res://addons/npr_character_frame/samples/silver_wolf/assets/runtime/hosiery_roughness_v1.png"
)
var _scene: Control
var _output: String
var _checks: Array[Dictionary] = []
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	if OS.get_cmdline_user_args().has("--malformed-save-only"):
		_run_malformed_save.call_deferred()
	else:
		_run.call_deferred()


func _run() -> void:
	root.mouse_passthrough = true
	root.unfocusable = true
	_scene = SCENE.instantiate()
	root.add_child(_scene)
	_scene.configure_save_path(_output.path_join("visual_scheme.json"))
	_scene.performance.automatic = false
	# Pose/dynamics advance explicitly below. Eye material comparisons must not
	# include additional spring-solver steps between otherwise identical frames.
	_scene.performance.set_process(false)
	# Rain also owns a simulation clock; rendering must not advance it implicitly.
	_scene.visual_layers.set_process(false)
	# Compare evaluated neutral poses, not uninitialized bind axes against a pose.
	_scene.performance.apply_pose(0.0, 0.1)
	await _frames(10)
	_check(_scene.preview.initialized, "Production character initializes")
	_check_hosiery_surface()
	_check(
		(
			FileAccess.file_exists(CONTRACT)
			and FileAccess.file_exists(MANIFEST)
			and FileAccess.file_exists(GEOMETRY)
		),
		"Authored visual contract, geometry contract and generation manifest exist"
	)
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var geometry_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY))
	_check(contract.schema == 1 and manifest.schema == 1, "Visual input schemas are recognized")
	_check(manifest.maps.size() == 5, "Five independent authored maps are registered")
	_check(
		_scene.preview.definition.rain_profile.validate().is_empty(),
		"Continuous rain profile validates"
	)
	_check(
		(
			not _scene.visual_layers.surface_rain.enabled
			and _scene.visual_layers.surface_rain.input_rate == 0.0
			and _scene.visual_layers.surface_rain.drops.is_empty()
			and _scene.visual_layers.surface_rain.water.is_empty()
		),
		"Continuous rain starts disabled with no water state"
	)
	_check(
		geometry_data.layers.size() == 4,
		"Tulle, stitch, eye and tear presentation contracts are registered"
	)
	await _capture("default")
	var baseline: Dictionary = _scene.state.to_data()
	_scene.state.hosiery_style = 1
	_scene.state.hosiery_stitch = 0.5
	_scene.state.wetness_regions = [1.0, 0.5, 0.75, 1.0]
	_scene.state.eye_wetness = 1.0
	_scene.state.wind_strength = 1.0
	_scene.state.soft_tissue_pressure = 1.0
	_scene.state.droplets_enabled = true
	_scene.state.droplet_count = 8
	_scene.state.droplet_speed = 0.5
	_scene.state.tulle_geometry_enabled = true
	_scene.state.eye_geometry_enabled = true
	_scene.state.hair_dynamic_enabled = true
	_scene.state.hair_collision_enabled = true
	_scene.state.authored_materials_enabled = true
	_scene.state.equipment = [true, true, true, true]
	_scene._apply_state()
	_scene.performance.apply_pose(1.0, 0.1)
	await _capture("enabled")
	_check(
		_scene.preview.materials[0].get_shader_parameter("u_npr_tulle_strength") == 1.0,
		"Tulle style uses its independent map"
	)
	_check(
		_scene.preview.materials[1].get_shader_parameter("u_npr_eye_wetness") == 0.0,
		"Independent wetness does not also shade the replaced original eye"
	)
	_check(
		_scene.preview.materials[2].get_shader_parameter("u_npr_hair_wetness") == 0.75,
		"Hair wetness uses the hair region value"
	)
	_check(
		(
			_scene.visual_layers.contract().count == 8
			and _scene.visual_layers.surface_rain.input_rate == 40.0
		),
		"Saved rain density maps to actual arrival rate"
	)
	_check(
		_scene.preview.materials[0].get_shader_parameter("u_npr_rain_enabled"),
		"Surface rainfall is enabled on the production body material"
	)
	_check(
		_scene.visual_layers.tulle_layer.visible and _scene.visual_layers.eye_layer.visible,
		"Independent geometry layers are visible"
	)
	var tear_left := (
		_scene.visual_layers.eye_layer.find_child("EyeL_TearFilm", true, false) as MeshInstance3D
	)
	var tear_material := (
		tear_left.material_override as ShaderMaterial if tear_left != null else null
	)
	_check(
		(
			tear_material != null
			and tear_material.shader != null
			and tear_material.shader.resource_path.ends_with("eye_tear_film.gdshader")
			and is_equal_approx(float(tear_material.get_shader_parameter("wetness")), 1.0)
		),
		"Authored tear film uses the independent screen-space transmission shader"
	)
	_check(
		(
			tear_material != null
			and is_equal_approx(float(tear_material.get_shader_parameter("ior")), 1.333)
			and is_equal_approx(float(tear_material.get_shader_parameter("thickness")), 0.0015)
			and is_equal_approx(
				float(tear_material.get_shader_parameter("tear_transmission")), 0.72
			)
		),
		"Authored tear film exposes IOR, thickness and transmission controls"
	)
	_scene.visual_layers.set_eye_wetness(0.0)
	_check(
		(
			tear_material != null
			and is_equal_approx(float(tear_material.get_shader_parameter("wetness")), 0.0)
		),
		"Tear film wetness can disable the transmission contribution"
	)
	_scene.visual_layers.set_eye_wetness(1.0)
	var hosiery_meshes: Array[Node] = _scene.visual_layers.tulle_layer.find_children(
		"*", "MeshInstance3D", true, false
	)
	var hosiery_contract_ok: bool = hosiery_meshes.size() == 1
	for hosiery_node: Node in hosiery_meshes:
		var hosiery_mesh := hosiery_node as MeshInstance3D
		var hosiery_material := hosiery_mesh.material_override as ShaderMaterial
		hosiery_contract_ok = (
			hosiery_contract_ok
			and hosiery_material != null
			and hosiery_mesh.mesh == _scene.preview.meshes[0].mesh
			and hosiery_mesh.skin == _scene.preview.meshes[0].get_skin_reference().get_skin()
			and hosiery_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			and hosiery_material.render_priority > 6
			and hosiery_material.get_shader_parameter("albedo_texture") == HOSIERY_WEAVE_TEXTURE
			and (
				hosiery_material.get_shader_parameter("roughness_texture")
				== HOSIERY_ROUGHNESS_TEXTURE
			)
		)
	_check(hosiery_contract_ok, "Fitted hosiery shares body geometry, skin and textile maps")
	_check(
		hosiery_meshes.size() == 1 and _scene.visual_layers.eye_layer.get_child_count() == 2,
		"Independent fitted hosiery and eye geometry have child groups"
	)
	_scene.visual_layers.set_eye_focus(Vector2(0.75, -0.5))
	_scene.visual_layers.set_pupil_scale(1.2)
	var pupil_left := _scene.visual_layers.eye_layer.get_node("EyeL/EyeL_Pupil") as MeshInstance3D
	var pupil_right := _scene.visual_layers.eye_layer.get_node("EyeR/EyeR_Pupil") as MeshInstance3D
	_check(
		_scene.visual_layers.eye_pupil_contract().count == 2,
		"Authored left and right pupils are independently addressable"
	)
	_check(
		(
			pupil_left != null
			and pupil_right != null
			and is_equal_approx(pupil_left.scale.x, 1.2)
			and is_equal_approx(pupil_right.scale.x, 1.2)
			and pupil_left.position != pupil_right.position
		),
		"Pupil scaling and directional focus are applied deterministically"
	)
	var upper_lid_left := (
		_scene.visual_layers._original_lids.find_child("L_UpperLid", true, false) as Node3D
	)
	var lower_lid_left := (
		_scene.visual_layers._original_lids.find_child("L_LowerLid", true, false) as Node3D
	)
	_check(
		(
			upper_lid_left != null
			and lower_lid_left != null
			and _scene.visual_layers.eye_pupil_contract().lid_count == 4
		),
		"Both eye representations share the fitted upper and lower eyelids"
	)
	_scene.visual_layers.set_eye_lid_closure(1.0)
	_check(
		(
			_scene.visual_layers.contract().eye_lid_closure == 1.0
			and upper_lid_left != null
			and lower_lid_left != null
			and (upper_lid_left as MeshInstance3D).get_blend_shape_value(0) == 1.0
			and (lower_lid_left as MeshInstance3D).get_blend_shape_value(0) == 1.0
		),
		"Authored eyelid closure applies a deterministic topology-layer deformation"
	)
	_scene.visual_layers.set_eye_lid_closure(0.0)
	_check(
		(
			upper_lid_left != null
			and lower_lid_left != null
			and (upper_lid_left as MeshInstance3D).get_blend_shape_value(0) == 0.0
			and (lower_lid_left as MeshInstance3D).get_blend_shape_value(0) == 0.0
		),
		"Authored eyelid closure restores the neutral transform"
	)
	# Authored eye temporal path: combine pupil focus/scale with the production
	# expression control, then restore the exact neutral state. Captures are kept
	# for the image analyzer so this cannot pass on metadata-only changes.
	_scene.visual_layers.set_eye_focus(Vector2.ZERO)
	_scene.visual_layers.set_pupil_scale(1.0)
	_scene.visual_layers.set_paused(true)
	var face_material: ShaderMaterial = _scene.preview.materials[1]
	face_material.set_shader_parameter("u_npr_expression_weights", Vector3.ZERO)
	face_material.set_shader_parameter("u_npr_eye_expression", 0.0)
	await _capture("eye_temporal_neutral")
	var neutral_pupil_left := pupil_left.position
	_scene.visual_layers.set_eye_focus(Vector2(-0.8, 0.25))
	_scene.visual_layers.set_pupil_scale(0.72)
	face_material.set_shader_parameter("u_npr_expression_weights", Vector3(0.0, 0.0, 0.8))
	face_material.set_shader_parameter("u_npr_eye_expression", 1.0)
	await _capture("eye_temporal_left_expression")
	_check(
		pupil_left.position != neutral_pupil_left and is_equal_approx(pupil_left.scale.x, 0.72),
		"Authored eye focus and constriction persist during expression"
	)
	_scene.visual_layers.set_eye_focus(Vector2(0.8, -0.2))
	_scene.visual_layers.set_pupil_scale(1.28)
	face_material.set_shader_parameter("u_npr_expression_weights", Vector3(0.0, 0.8, 0.0))
	face_material.set_shader_parameter("u_npr_eye_expression", 0.0)
	await _capture("eye_temporal_right_expression")
	_check(
		pupil_left.position != neutral_pupil_left and is_equal_approx(pupil_left.scale.x, 1.28),
		"Authored eye focus and dilation update on the next frame"
	)
	_scene.visual_layers.set_eye_focus(Vector2.ZERO)
	_scene.visual_layers.set_pupil_scale(1.0)
	face_material.set_shader_parameter("u_npr_expression_weights", Vector3.ZERO)
	face_material.set_shader_parameter("u_npr_eye_expression", 0.0)
	await _capture("eye_temporal_reset")
	_check(
		pupil_left.position == neutral_pupil_left and is_equal_approx(pupil_left.scale.x, 1.0),
		"Authored eye temporal reset restores neutral pupil state"
	)
	_scene.visual_layers.set_paused(false)
	var rain: RefCounted = _scene.visual_layers.surface_rain
	var initial_time: float = rain.elapsed
	_scene.visual_layers._process(0.2)
	await RenderingServer.frame_post_draw
	_check(rain.elapsed > initial_time, "Enabled rainfall advances the stateful surface simulation")
	_check(
		rain.births > 0 and not rain.drops.is_empty() and not rain.water.is_empty(),
		"Fixed rain sampling retains actual drops and deposited water"
	)
	_scene.visual_layers.set_paused(true)
	var paused_field: int = rain.stats().state_hash
	var paused_inputs := _capture_inputs()
	_scene.visual_layers._process(0.5)
	await RenderingServer.frame_post_draw
	_check(rain.stats().state_hash == paused_field, "Paused rain preserves the surface simulation")
	_check(
		_capture_inputs().rain_sha256 == paused_inputs.rain_sha256,
		"Paused rain preserves complete sampled water and random state"
	)
	_check(
		not _scene.visual_layers.contract().transparent_depth,
		"Surface water adds no separate opaque depth layer"
	)
	_scene.save_scheme()
	var saved: Dictionary = _scene.state.to_data()
	_check(
		_saved_file_matches(_scene.save_path, saved),
		"Schema 10 visual state saves with exact disk round trip"
	)
	_check(
		not _scene.dirty and not FileAccess.file_exists(_scene.save_path + ".tmp"),
		"Successful save clears dirty state and commits the temporary file"
	)
	_check(
		(
			_scene.performance.hair_dynamic_enabled
			and _scene.performance.hair_collision_enabled
			and _scene.equipment.authored_material_contract().visible_objects == 19
		),
		"All six directions coexist with dynamic hair and authored equipment"
	)
	for view in ["full", "half", "face"]:
		_scene.set_view(view)
		await _capture("combined_" + view)
	_scene.set_view("full")
	_scene.visual_layers.set_paused(true)
	_scene.reset_scheme()
	_scene.performance.apply_pose(0.0, 0.1)
	await _capture("reset")
	_check(
		(
			FileAccess.get_sha256(_output.path_join("default.png"))
			== FileAccess.get_sha256(_output.path_join("reset.png"))
		),
		"Reset restores exact production PNG bytes"
	)
	_check(
		_captures[0].inputs == _captures[-1].inputs,
		"Reset restores evaluated simulation and material inputs"
	)
	_check(_scene.state.to_data() == baseline, "Reset restores all visual-direction defaults")
	_check(not _scene.visual_layers.contract().paused, "Reset resumes the visual layer clock")
	_check(
		not _scene.preview.materials[0].get_shader_parameter("u_npr_rain_enabled"),
		"Reset disables continuous rain rendering"
	)
	_check(
		not _scene.visual_layers.tulle_layer.visible and not _scene.visual_layers.eye_layer.visible,
		"Reset hides independent geometry"
	)
	_check(
		(
			_scene.visual_layers.contract().count == 0
			and _scene.visual_layers.surface_rain.drops.is_empty()
			and _scene.visual_layers.surface_rain.water.is_empty()
			and _scene.visual_layers.surface_rain.elapsed == 0.0
		),
		"Reset clears actual rain droplets, water and simulation clock"
	)
	# Wrong-domain negative control: remove garment vertex gating. The capture is
	# retained for the Python ROI analyzer and the runtime check records the input.
	var body: ShaderMaterial = _scene.preview.materials[0]
	body.set_shader_parameter("u_npr_garment_vertex_regions", false)
	_scene.state.hosiery_style = 1
	_scene._apply_state()
	body.set_shader_parameter("u_npr_garment_vertex_regions", false)
	await _capture("wrong_domain")
	_check(
		body.get_shader_parameter("u_npr_garment_vertex_regions") == false,
		"Wrong-domain negative control is explicit"
	)
	body.set_shader_parameter("u_npr_garment_vertex_regions", true)
	# Do not change the established capture sequence while testing persistence.
	_check_save_contract(saved)
	FileAccess.open(_output.path_join("visual_directions.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"checks": _checks,
				"captures": _captures,
				"contract_sha256": FileAccess.get_sha256(CONTRACT),
				"manifest_sha256": FileAccess.get_sha256(MANIFEST),
				"engine": Engine.get_version_info()
			},
			"  "
		)
	)
	var failed := _checks.any(func(check: Dictionary): return not check.pass)
	_scene.free()
	print(
		"VISUAL_DIRECTIONS_CHECKS=",
		_checks.size(),
		" FAILURES=",
		_checks.filter(func(check: Dictionary): return not check.pass).size()
	)
	print("REGRESSION_FAILED" if failed else "REGRESSION_OK")
	quit(1 if failed else 0)


func _saved_file_matches(path: String, expected: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		return false
	var data: Dictionary = json.data
	# JSON numbers decode as floats; compare wire values before typed restoration.
	var wire_expected: Dictionary = JSON.parse_string(JSON.stringify(expected, "", true, true))
	if data.get("schema") != 10 or data != wire_expected:
		return false
	var restored := STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
	return restored.load_data(data) and restored.to_data() == expected


func _check_save_contract(saved: Dictionary) -> void:
	var original_path: String = _scene.save_path
	var original_hash := FileAccess.get_sha256(original_path)
	_scene.configure_save_path(original_path)
	_check(
		not _scene.dirty and _scene.state.to_data() == saved,
		"Showcase reloads every saved visual field from disk"
	)
	_check(
		(
			_scene.performance.hair_dynamic_enabled == saved.hair_dynamic_enabled
			and _scene.performance.hair_collision_enabled == saved.hair_collision_enabled
			and _scene.equipment.authored_material_contract().visible_objects == 19
			and _scene.visual_layers.surface_rain.input_rate == float(saved.droplet_count) * 5.0
		),
		"Reload applies saved hair, equipment and rainfall choices to runtime modules"
	)
	var cases := {"truncated": "{", "array": "[]"}
	for name in ["old_schema", "missing_field", "changed_value", "extra_field", "wrong_character"]:
		var data := saved.duplicate(true)
		match name:
			"old_schema":
				data.schema = 6
			"missing_field":
				data.erase("wind_strength")
			"changed_value":
				data.wind_strength = 0.25
			"extra_field":
				data.unexpected = true
			"wrong_character":
				data.character = "different_character"
		cases[name] = JSON.stringify(data, "  ", true, true)
	var missing := _output.path_join("save_missing.json")
	_check(
		not FileAccess.file_exists(missing) and not _saved_file_matches(missing, saved),
		"Saved-file gate rejects a missing file"
	)
	for name: String in cases:
		var path := _output.path_join("save_negative_" + name + ".json")
		_check(_write_fixture(path, cases[name]), "Save negative fixture writes: " + name)
		_check(not _saved_file_matches(path, saved), "Saved-file gate rejects: " + name)
		if name in ["array", "missing_field", "extra_field", "wrong_character"]:
			var hash_before := FileAccess.get_sha256(path)
			_scene.configure_save_path(path)
			_check(
				(
					_scene.dirty
					and (
						_scene.state.to_data()
						== (
							STATE
							. new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
							. to_data()
						)
					)
				),
				"Showcase rejects invalid saved file and retains defaults: " + name
			)
			_check(
				FileAccess.get_sha256(path) == hash_before,
				"Invalid saved file is preserved for recovery: " + name
			)
	_check_schema_migrations(saved)
	_check(
		FileAccess.get_sha256(original_path) == original_hash,
		"Readback and negative controls preserve the original saved file"
	)


func _check_schema_migrations(saved: Dictionary) -> void:
	# Independent protocol expectations, not defaults copied from the serializer.
	var introduced := {
		7: {"hosiery_sheen": 0.20, "hosiery_weave": 0.035, "hosiery_roughness": 0.27},
		8: {"eye_left": [0.0, 0.0, 1.0], "eye_right": [0.0, 0.0, 1.0]},
		9: {"eye_symbol": 0, "eye_symbol_size": 1.0, "eye_symbol_stroke": 0.10},
		10: {"mouth_symbol": 0, "mouth_symbol_size": 1.0, "mouth_symbol_stroke": 0.10},
	}
	var current := saved.duplicate(true)
	current.hosiery_sheen = 0.31
	current.hosiery_weave = 0.071
	current.hosiery_roughness = 0.43
	current.eye_left = [0.123456789012345, -0.234567890123456, 0.876543210987654]
	current.eye_right = [-0.345678901234567, 0.456789012345678, 1.234567890123456]
	current.eye_symbol = 3
	current.eye_symbol_size = 0.83
	current.eye_symbol_stroke = 0.13
	current.mouth_symbol = 2
	current.mouth_symbol_size = 0.91
	current.mouth_symbol_stroke = 0.16
	for schema in [6, 7, 8, 9, 10]:
		var legacy := current.duplicate(true)
		var expected := current.duplicate(true)
		legacy.schema = schema
		for version: int in introduced:
			if version <= schema:
				continue
			for key: String in introduced[version]:
				legacy.erase(key)
				expected[key] = introduced[version][key]
		# Old replacement-eye requests must not revive the retired presentation.
		legacy.eye_geometry_enabled = true
		var path := _output.path_join("save_schema_%d.json" % schema)
		_check(
			_write_fixture(path, JSON.stringify(legacy, "  ", true, true)),
			"Schema %d migration fixture writes" % schema
		)
		var decoded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var untouched := decoded.duplicate(true)
		var restored := STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE)
		_check(
			restored.load_data(decoded) and restored.to_data() == expected,
			"Schema %d migrates with exact field preservation and declared defaults" % schema
		)
		_check(decoded == untouched, "Schema %d migration preserves caller data" % schema)
		_scene.configure_save_path(path)
		_check(
			not _scene.dirty and _scene.state.to_data() == expected,
			"Showcase loads schema %d through its real saved-file entry" % schema
		)
	# Exercise the actual save method with non-default, high-precision eye controls.
	_check(_scene.state.load_data(current), "Non-default schema 10 persistence fixture validates")
	_scene.save_path = _output.path_join("save_current_nondefault.json")
	_scene.dirty = true
	_scene.save_scheme()
	_check(
		_saved_file_matches(_scene.save_path, current) and not _scene.dirty,
		"Actual save preserves all non-default fields and full-precision eye values"
	)
	_scene.configure_save_path(_scene.save_path)
	_check(
		not _scene.dirty and _scene.state.to_data() == current,
		"Showcase reload preserves non-default schema 10 values"
	)
	var intact: Dictionary = _scene.state.to_data()
	for schema in [0, 11]:
		var unsupported := current.duplicate(true)
		unsupported.schema = schema
		_check(
			not _scene.state.load_data(unsupported) and _scene.state.to_data() == intact,
			"Unsupported schema %d is rejected without changing live state" % schema
		)


func _run_malformed_save() -> void:
	# The real loader intentionally logs a parser error. Run this negative control
	# separately so the ordinary visual gate still requires a clean engine log.
	var path := _output.path_join("save_truncated.json")
	_check(_write_fixture(path, "{"), "Truncated save fixture writes")
	var original_hash := FileAccess.get_sha256(path)
	_scene = SCENE.instantiate()
	_scene.save_path = path
	root.add_child(_scene)
	_check(
		(
			_scene.dirty
			and (
				_scene.state.to_data()
				== STATE.new("silver_wolf", SAMPLE_PALETTE_PROFILE, SAMPLE_HEIGHT_PROFILE).to_data()
			)
		),
		"Showcase rejects truncated JSON and retains defaults"
	)
	_check(FileAccess.get_sha256(path) == original_hash, "Truncated save is preserved for recovery")
	var failed := _checks.any(func(check: Dictionary): return not check.pass)
	_write_fixture(
		_output.path_join("malformed_save.json"),
		JSON.stringify({"checks": _checks, "expected_parser_errors": 1}, "  ")
	)
	_scene.free()
	print("MALFORMED_SAVE_NEGATIVE_OK" if not failed else "MALFORMED_SAVE_NEGATIVE_FAILED")
	quit(1 if failed else 0)


func _write_fixture(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _check_hosiery_surface() -> void:
	var layer: Node3D = _scene.visual_layers.tulle_layer
	_check(layer.name == "AuthoredHosiery", "Fitted hosiery layer retains its showcase node name")
	for child: Node in layer.find_children("*", "MeshInstance3D", true, false):
		_check(child is MeshInstance3D, "Hosiery child is a mesh: " + str(child.name))
		if not child is MeshInstance3D:
			continue
		var mesh: Mesh = child.mesh
		_check(
			mesh.get_surface_count() == 1,
			"Hosiery child has one material surface: " + str(child.name)
		)
		var arrays: Array = mesh.surface_get_arrays(0)
		_check(
			(
				arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size()
				and arrays[Mesh.ARRAY_NORMAL].size() == arrays[Mesh.ARRAY_VERTEX].size()
			),
			"Fitted hosiery UV and normals are complete: " + str(child.name)
		)


func _capture(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var image: Image = _scene.viewport.get_texture().get_image()
	_check(image.save_png(_output.path_join(label + ".png")) == OK, "GPU image saved: " + label)
	(
		_captures
		. append(
			{
				"name": label,
				"size": [image.get_width(), image.get_height()],
				"state": _scene.state.to_data(),
				"inputs": _capture_inputs(),
				"rain_stats": _scene.visual_layers.surface_rain.stats(),
			}
		)
	)


func _frames(count: int) -> void:
	for index in count:
		await process_frame
		_scene.visual_layers._process(1.0 / 60.0)


func _capture_inputs() -> Dictionary:
	var rain: RefCounted = _scene.visual_layers.surface_rain
	var rain_state := [
		rain.elapsed,
		rain.births,
		rain.crossings,
		rain.deposited,
		rain.drops,
		rain.water,
		rain.rng.state,
		rain._display_clock,
		rain._cursor,
		rain._slots,
		rain._arrival,
	]
	var materials: Array = []
	for source: ShaderMaterial in _scene.preview.materials:
		var material := source
		while material != null:
			var parameters: Dictionary = {}
			for parameter in material.shader.get_shader_uniform_list():
				var value: Variant = material.get_shader_parameter(parameter.name)
				# Unset overrides still supply the shader's declared default.
				if value == null:
					value = RenderingServer.shader_get_parameter_default(
						material.shader.get_rid(), parameter.name
					)
				parameters[str(parameter.name)] = (
					value.resource_path if value is Resource else value
				)
			materials.append(parameters)
			material = material.next_pass as ShaderMaterial
	return {
		"simulation_sha256": _digest(CAPTURE_CLOCK.simulation_bytes(_scene.performance)),
		"rain_sha256": _digest(var_to_bytes(rain_state)),
		"materials_sha256": _digest(var_to_bytes(materials)),
	}


func _digest(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish().hex_encode()


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("VISUAL_DIRECTIONS_FAILED: " + label)
