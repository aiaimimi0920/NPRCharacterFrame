extends "symbolic_expression_regression.gd"
## Fixed production poses before/after atlas ownership changes, plus profile gates.

const ATLAS_DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)


func _run() -> void:
	if OS.get_environment("NPR_FACE_ATLAS_NEGATIVE") == "missing_profile":
		_missing_profile()
		return
	# Let shader defaults become available before taking the pre-actor snapshot.
	await process_frame
	await RenderingServer.frame_post_draw
	var original_source := _source_atlas_values()
	_check(not original_source.values().has(null), "Pre-actor shader defaults are resolved")
	_spawn()
	_check(_wardrobe.preview.initialized, "Production character initialized")
	await _baseline()
	await _profile_checks()
	var final_source := _source_atlas_values()
	FileAccess.open(_output.path_join("source_material.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"before": original_source, "after": final_source}, "  ")
	)
	_check(final_source == original_source, "First actor leaves imported atlas values intact")
	_authored_source_without_profile()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "captures": _captures}, "  ")
	)
	_wardrobe.free()
	print("FACE_ATLAS_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _baseline() -> void:
	await _capture("neutral")
	for scale in [0.65, 1.0, 1.35]:
		_wardrobe.visual_layers.set_pupil_scale(scale)
		await _capture("pupil_%s" % scale)
	_wardrobe.visual_layers.set_eye_focus(Vector2(0.4, -0.3), 0)
	_wardrobe.visual_layers.set_eye_focus(Vector2(-0.2, 0.25), 1)
	_wardrobe.visual_layers.set_pupil_scale(0.75, 0)
	_wardrobe.visual_layers.set_pupil_scale(1.25, 1)
	await _capture("independent_gaze")
	for closure in [0.5, 1.0]:
		_wardrobe.performance.blink_weight = closure
		_wardrobe.performance.apply_pose(0.0)
		await _capture("lid_%s" % closure)
	_wardrobe.performance.blink_weight = 0.0
	_wardrobe.visual_layers.set_eye_focus(Vector2.ZERO)
	_wardrobe.visual_layers.set_pupil_scale(1.0)
	_wardrobe._set_debug_eye_expression(1.0)
	_wardrobe.performance.apply_pose(0.0)
	await _capture("round_eyes")
	_wardrobe._set_debug_eye_expression(-1.0)
	_wardrobe.state.eye_symbol = 1
	_wardrobe._apply_state()
	_wardrobe.performance.apply_pose(0.0)
	await _capture("symbol_eyes")
	_wardrobe.state.mouth_symbol = 2
	_wardrobe._apply_state()
	_wardrobe.performance.apply_pose(0.0)
	await _capture("both_symbols")
	_wardrobe.performance.action = "look_around"
	_wardrobe.performance.apply_pose(1.0)
	await _capture("symbols_head_motion")
	_wardrobe.performance.action = "idle"
	_wardrobe.performance.apply_pose(0.0)
	_wardrobe.state.eye_symbol = 0
	_wardrobe._apply_state()
	_wardrobe.performance.apply_pose(0.0)
	await _capture("symbol_mouth")
	_wardrobe.state.mouth_symbol = 0
	_wardrobe._apply_state()
	_wardrobe.performance.visemes = {"aa": 1.0}
	_wardrobe.performance.apply_pose(0.0)
	await _capture("viseme")
	_wardrobe.performance.visemes = {}
	_wardrobe.performance.apply_pose(0.0)
	# The diagnostic representation is a runtime inspection, not saved preference.
	_wardrobe.state.eye_geometry_enabled = true
	_wardrobe._apply_state()
	_wardrobe.performance.apply_pose(0.0)
	await _capture("diagnostic_eyes")
	_wardrobe.state.eye_geometry_enabled = false
	_wardrobe._apply_state()
	_wardrobe.performance.apply_pose(0.0)
	await _capture("restored")
	_check(
		(
			Image.load_from_file(_output.path_join("neutral.png")).get_data()
			== Image.load_from_file(_output.path_join("restored.png")).get_data()
		),
		"Original rendering restores exactly after all representations"
	)


func _profile_checks() -> void:
	# These checks run after the unchanged pre-change poses and labels.
	var profile: NPRFaceAtlasProfile = _wardrobe.preview.definition.face_atlas_profile
	_check(profile.validate().is_empty(), "Sample atlas calibration validates")
	_check(not NPRFaceAtlasProfile.new().validate().is_empty(), "No implicit sample atlas layout")
	_contract(profile)
	await _alternates(profile)
	await _domain_probe(profile)
	_instances(profile)


func _contract(profile: NPRFaceAtlasProfile) -> void:
	for entry in [
		["accent_uv_min", Vector2(NAN, 0)],
		["accent_uv_max", Vector2(1.1, 0.5)],
		["accent_plate_uv", Vector2(-0.1, 0.2)],
		["skin_sample_v", INF],
		["skin_sample_v", -0.1],
		["replacement_eye_a_max_uv", Vector2(0.4, 1.1)],
		["replacement_eye_b_min_u", NAN],
		["replacement_eye_b_min_u", 1.1],
		["replacement_eye_b_v_range", Vector2(0.32, 0.125)],
		["round_eye_center_uv", Vector2(INF, 0)],
		["round_eye_aspect", Vector2(0, 1)],
		["round_eye_aspect", Vector2(1, NAN)],
		["round_eye_pupil_radii", Vector2(0.03, 0.03)],
		["round_eye_disc_radii", Vector2(-0.01, 0.1)],
		["accent_uv_min", profile.accent_uv_max]
	]:
		var bad := profile.duplicate() as NPRFaceAtlasProfile
		bad.set(entry[0], entry[1])
		_check(not bad.validate().is_empty(), "Reject atlas field " + str(entry))
		var definition := _wardrobe.preview.definition.duplicate() as NPRCharacterDefinition
		definition.face_atlas_profile = bad
		_check(
			Array(definition.validate()).any(
				func(error: String): return error.begins_with("face_atlas_profile:")
			),
			"Definition propagates atlas error " + str(entry)
		)
		var material := ShaderMaterial.new()
		material.shader = _wardrobe.preview.materials[1].shader
		material.set_shader_parameter("u_npr_face_atlas_skin_sample_v", 0.77)
		_check(not bad.apply_material(material), "Invalid binding refused " + str(entry))
		_check(
			material.get_shader_parameter("u_npr_face_atlas_skin_sample_v") == 0.77,
			"Invalid binding is atomic " + str(entry)
		)
	_check(not profile.apply_material(null), "Null material binding refused")
	var private_material: ShaderMaterial = _wardrobe.preview.materials[1]
	var before: Dictionary = {}
	for field in [
		"u_npr_eye_symbol",
		"u_npr_mouth_symbol",
		"u_npr_replace_eye",
		"u_npr_pupil_accent_scale",
		"u_npr_eye_expression",
		"u_npr_eye_wetness"
	]:
		before[field] = private_material.get_shader_parameter(field)
	_check(profile.apply_material(private_material), "Valid static binding accepted")
	for field in before:
		_check(
			private_material.get_shader_parameter(field) == before[field],
			"Static binding preserves dynamic " + field
		)
	for field in NPRFaceAtlasProfile.FIELDS:
		_check(
			(
				private_material.get_shader_parameter("u_npr_face_atlas_" + field)
				== profile.get(field)
			),
			"Production private material binds " + field
		)


func _alternates(profile: NPRFaceAtlasProfile) -> void:
	for entry in [
		["accent_uv_min", Vector2(0.31, 0.06)],
		["accent_uv_max", Vector2(0.30, 0.045)],
		["accent_plate_uv", Vector2(0.5, 0.4)],
		["skin_sample_v", 0.05],
		["replacement_eye_a_max_uv", Vector2(0.1, 0.1)],
		["replacement_eye_b_min_u", 1.0],
		["replacement_eye_b_v_range", Vector2(0.125, 0.13)],
		["round_eye_center_uv", Vector2(0.18, 0.20)],
		["round_eye_aspect", Vector2(0.6, 1.4)],
		["round_eye_pupil_radii", Vector2(0.04, 0.06)],
		["round_eye_disc_radii", Vector2(0.04, 0.05)]
	]:
		var field: String = entry[0]
		_wardrobe.state.eye_symbol = 0
		_wardrobe.state.mouth_symbol = 0
		_wardrobe.state.eye_geometry_enabled = field.begins_with("replacement")
		if field == "skin_sample_v":
			_wardrobe.state.eye_symbol = 1
			_wardrobe.state.mouth_symbol = 2
		_wardrobe._apply_state()
		_wardrobe.performance.apply_pose(0.0)
		var fixture_before: Dictionary = {}
		if field.begins_with("replacement_eye_b"):
			# The sample provides no visible B-domain sensitivity, even without its overlay.
			# Explicit valid-eye ILM/UV input isolates B in the real production shader.
			_wardrobe.visual_layers.eye_layer.visible = false
			fixture_before = _b_domain_fixture()
		_wardrobe.preview.set_face_eye_expression(1.0 if field.begins_with("round") else 0.0)
		_wardrobe.visual_layers.set_pupil_scale(1.35 if field.begins_with("accent") else 1.0)
		profile.apply_material(_wardrobe.preview.materials[1])
		await _capture(field + "_source")
		var alternate := profile.duplicate() as NPRFaceAtlasProfile
		alternate.set(field, entry[1])
		_check(alternate.validate().is_empty(), "Alternate authored " + field + " validates")
		_check(
			alternate.apply_material(_wardrobe.preview.materials[1]),
			"Alternate " + field + " binds"
		)
		await _capture(field + "_alternate")
		_check(
			not _same_image(field + "_source", field + "_alternate"),
			"Alternate " + field + " changes actual GPU pixels"
		)
		profile.apply_material(_wardrobe.preview.materials[1])
		await _capture(field + "_restored")
		_check(
			_same_image(field + "_source", field + "_restored"),
			"Restoring " + field + " exactly restores GPU pixels"
		)
		for parameter in fixture_before:
			_wardrobe.preview.materials[1].set_shader_parameter(
				parameter, fixture_before[parameter]
			)


func _b_domain_fixture() -> Dictionary:
	var material: ShaderMaterial = _wardrobe.preview.materials[1]
	var before: Dictionary = {}
	for parameter in ["u_texture_ilm_map", "u_uv1_scale", "u_uv1_offset"]:
		before[parameter] = material.get_shader_parameter(parameter)
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 1.0, 0.0, 0.5))
	material.set_shader_parameter("u_texture_ilm_map", ImageTexture.create_from_image(image))
	material.set_shader_parameter("u_uv1_scale", Vector2.ZERO)
	material.set_shader_parameter("u_uv1_offset", Vector2(0.9, 0.8))
	_check(
		material.get_shader_parameter("u_npr_replace_eye"),
		"B fixture keeps production replacement active"
	)
	return before


func _same_image(a: String, b: String) -> bool:
	return (
		Image.load_from_file(_output.path_join(a + ".png")).get_data()
		== Image.load_from_file(_output.path_join(b + ".png")).get_data()
	)


func _domain_probe(profile: NPRFaceAtlasProfile) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 1)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var surface := ColorRect.new()
	surface.size = Vector2(16, 1)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = (
		'shader_type canvas_item;\n#include "res://addons/npr_character_frame/'
		+ 'shaders/face/face_atlas_calibration.gdshaderinc"\n'
		+ "uniform vec2 probes[16];\nvoid fragment(){ vec2 uv = probes[int(FRAGCOORD.x)]; "
		+ "bool old_domain = (uv.x < 0.38 && uv.y < 0.32)"
		+ " || (uv.x > 0.84 && uv.y > 0.125 && uv.y < 0.32); "
		+ "COLOR = vec4(float(npr_face_atlas_replacement_eye(uv)), float(old_domain), 0.0, 1.0); }"
	)
	material.shader = shader
	profile.apply_material(material)
	material.set_shader_parameter(
		"probes",
		PackedVector2Array(
			[
				Vector2(-0.2, -0.2),
				Vector2(0, 0),
				Vector2(0.38, 0.2),
				Vector2(0.3799, 0.2),
				Vector2(0.2, 0.32),
				Vector2(0.2, 0.3199),
				Vector2(0.84, 0.2),
				Vector2(0.8401, 0.2),
				Vector2(0.9, 0.125),
				Vector2(0.9, 0.1251),
				Vector2(0.9, 0.32),
				Vector2(0.9, 0.3199),
				Vector2(1.1, 0.2),
				Vector2(0.6, 0.2),
				Vector2(0.1, -1),
				Vector2(2, 0.2)
			]
		)
	)
	surface.material = material
	viewport.add_child(surface)
	await _frames(5)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_check(
		image.save_png(_output.path_join("gpu_domains.png")) == OK, "GPU boundary evidence saved"
	)
	for index in 16:
		var pixel := image.get_pixel(index, 0)
		_check(
			pixel.r == pixel.g, "GPU strict domain equals original expression at probe %d" % index
		)
	for index in [0, 1, 12, 14, 15]:
		_check(image.get_pixel(index, 0).r == 1.0, "No hidden rectangle bound at probe %d" % index)
	for index in [2, 4, 6, 8, 10]:
		_check(image.get_pixel(index, 0).r == 0.0, "Open boundary preserved at probe %d" % index)
	viewport.free()


func _instances(profile: NPRFaceAtlasProfile) -> void:
	var imported: Node3D = _wardrobe.preview.definition.model_scene.instantiate()
	var source := (
		imported.get_node(_wardrobe.preview.definition.face_path).get_active_material(0)
		as ShaderMaterial
	)
	var source_values: Dictionary = {}
	for field in NPRFaceAtlasProfile.FIELDS + ["enabled"]:
		source_values[field] = source.get_shader_parameter("u_npr_face_atlas_" + field)
	var definition := _wardrobe.preview.definition.duplicate() as NPRCharacterDefinition
	definition.face_atlas_profile = null
	_check(definition.validate().is_empty(), "Base-rendering definition may omit atlas profile")
	var base := NPRCharacter.new()
	base.definition = definition
	base.visible = false
	_wardrobe.turntable.add_child(base)
	_check(base.initialized, "Actual base-only character initializes without atlas profile")
	_check(
		not base.materials[1].get_shader_parameter("u_npr_face_atlas_enabled"),
		"Base-only instance has no implicit atlas feature calibration"
	)
	var alternate := profile.duplicate() as NPRFaceAtlasProfile
	alternate.round_eye_center_uv = Vector2(0.2, 0.25)
	definition = _wardrobe.preview.definition.duplicate()
	definition.face_atlas_profile = alternate
	var other := NPRCharacter.new()
	other.definition = definition
	other.visible = false
	_wardrobe.turntable.add_child(other)
	_check(other.initialized, "Second actual character uses alternate atlas profile")
	_check(
		other.materials[1] != _wardrobe.preview.materials[1],
		"Actual actors own separate face materials"
	)
	_check(
		(
			other.materials[1].get_shader_parameter("u_npr_face_atlas_round_eye_center_uv")
			== alternate.round_eye_center_uv
		),
		"Alternate definition reaches actual setup binding"
	)
	_check(
		(
			_wardrobe.preview.materials[1].get_shader_parameter(
				"u_npr_face_atlas_round_eye_center_uv"
			)
			== profile.round_eye_center_uv
		),
		"Alternate setup does not change the first actor"
	)
	for field in source_values:
		_check(
			source.get_shader_parameter("u_npr_face_atlas_" + field) == source_values[field],
			"Imported source is unchanged: " + field
		)
	_check(
		_wardrobe.preview.definition.face_atlas_profile == profile,
		"Shared authored profile is not replaced"
	)
	base.free()
	other.free()
	imported.free()


func _source_atlas_values() -> Dictionary:
	var definition := ATLAS_DEFINITION as NPRCharacterDefinition
	var model := definition.model_scene.instantiate()
	var material := model.get_node(definition.face_path).get_active_material(0) as ShaderMaterial
	# Populate lazy uniform defaults before comparing snapshots across actor creation.
	material.get_property_list()
	var values := {}
	for field in NPRFaceAtlasProfile.FIELDS + ["enabled"]:
		values[field] = material.get_shader_parameter("u_npr_face_atlas_" + field)
	model.free()
	return values


func _authored_source_without_profile() -> void:
	var definition := _wardrobe.preview.definition.duplicate() as NPRCharacterDefinition
	var model := definition.model_scene.instantiate()
	var face := model.get_node(definition.face_path) as MeshInstance3D
	var source := face.get_active_material(0).duplicate() as ShaderMaterial
	source.set_shader_parameter("u_npr_face_atlas_enabled", true)
	face.set_surface_override_material(0, source)
	var scene := PackedScene.new()
	_check(scene.pack(model) == OK, "Authored enabled-atlas fixture packs")
	definition.model_scene = scene
	definition.face_atlas_profile = null
	_check(
		definition.validate().is_empty(), "Authored enabled-atlas source validates without profile"
	)
	var actor := NPRCharacter.new()
	actor.definition = definition
	actor.visible = false
	_wardrobe.turntable.add_child(actor)
	_check(actor.initialized, "Authored enabled-atlas base actor initializes")
	_check(actor.materials[1] != source, "Authored source material is copied")
	_check(
		not actor.materials[1].get_shader_parameter("u_npr_face_atlas_enabled"),
		"Absent profile disables inherited atlas enable state"
	)
	_check(source.get_shader_parameter("u_npr_face_atlas_enabled"), "Authored source stays enabled")
	actor.free()
	model.free()


func _missing_profile() -> void:
	var source := ATLAS_DEFINITION as NPRCharacterDefinition
	var definition := source.duplicate() as NPRCharacterDefinition
	definition.face_atlas_profile = null
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	var rig := load("res://addons/npr_character_frame/runtime/face/npr_face_rig.gd").new() as Node3D
	actor.add_child(rig)
	var driver := Node.new()
	rig.setup(actor, driver)
	_check(rig.get_child_count() == 0, "Missing atlas rejected before child assembly")
	_check(rig._actor == null, "Missing atlas rejected before actor ownership")
	_check(actor.initialized, "Missing atlas still allows base character initialization")
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks}, "  ")
	)
	driver.free()
	actor.free()
	var failed := _checks.filter(func(item: Dictionary): return not item["pass"])
	print("ATLAS_EXPECTED_ERROR=Face rig requires an authored face_atlas_profile")
	quit(0 if failed.is_empty() else 1)
