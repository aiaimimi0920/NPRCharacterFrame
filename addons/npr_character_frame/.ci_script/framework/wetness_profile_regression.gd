extends SceneTree
## Verify configured wetness inputs on real material chains without changing amounts.

const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const FIELDS := ["body_mask", "material_regions", "eye_tear_mask", "hair_mask"]
const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")

var _checks: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source: NPRWetnessProfile = DEFINITION.wetness_profile
	_check(source.validate().is_empty(), "Sample wetness profile validates")
	_check(not NPRWetnessProfile.new().validate().is_empty(), "Empty wetness profile rejected")
	for limit in [Vector2(NAN, 1), Vector2(1, INF), Vector2(-0.1, 1), Vector2(1, 1.1)]:
		var invalid := source.duplicate() as NPRWetnessProfile
		invalid.eye_tear_uv_limit = limit
		_check(not invalid.validate().is_empty(), "Invalid eye tear UV limit rejected")
	for field in FIELDS:
		var invalid := source.duplicate() as NPRWetnessProfile
		invalid.set(field, null)
		_check(not invalid.validate().is_empty(), field + " is required")
		invalid.set(field, ImageTexture.new())
		_check(not invalid.validate().is_empty(), field + " needs nonzero dimensions")
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.wetness_profile = NPRWetnessProfile.new()
	_check(not definition.validate().is_empty(), "Definition propagates wetness errors")
	definition.wetness_profile = null
	_check(definition.validate().is_empty(), "Base rendering permits no wetness profile")
	var profile := source.duplicate() as NPRWetnessProfile
	profile.eye_tear_uv_limit = Vector2(0.4, 0.5)
	for index in FIELDS.size():
		var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		pixels.fill(Color(0.1 + index * 0.1, 0.4, 0.6, 1))
		profile.set(FIELDS[index], ImageTexture.create_from_image(pixels))
	definition.wetness_profile = profile
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate profile initializes actual character")
	if actor.initialized:
		var body: ShaderMaterial = actor.materials[0]
		var face: ShaderMaterial = actor.materials[1]
		var hairs: Array[ShaderMaterial] = [actor.materials[2], actor.materials[2].next_pass]
		face.set_shader_parameter("u_npr_eye_wetness", 0.37)
		for hair in hairs:
			hair.set_shader_parameter("u_npr_hair_wetness", 0.42)
		profile.apply_materials(body, face, hairs)
		_check(
			face.get_shader_parameter("u_npr_eye_tear_uv_limit") == Vector2(0.4, 0.5),
			"Alternate tear UV limit reaches face shader"
		)
		_check(
			body.get_shader_parameter("u_npr_wetness_map") == profile.body_mask, "Body mask binds"
		)
		_check(
			body.get_shader_parameter("u_npr_material_wetness_map") == profile.material_regions,
			"Material regions bind"
		)
		_check(
			face.get_shader_parameter("u_npr_eye_tear_mask") == profile.eye_tear_mask,
			"Tear mask binds"
		)
		_check(
			is_equal_approx(face.get_shader_parameter("u_npr_eye_wetness"), 0.37),
			"Texture binding preserves eye amount"
		)
		for index in hairs.size():
			_check(
				hairs[index].get_shader_parameter("u_npr_hair_wetness_map") == profile.hair_mask,
				"Hair pass " + str(index) + " binds"
			)
			_check(
				is_equal_approx(hairs[index].get_shader_parameter("u_npr_hair_wetness"), 0.42),
				"Texture binding preserves hair amount"
			)
		for field in FIELDS:
			_check(source.get(field) != profile.get(field), field + " source remains unchanged")
		var second := NPRCharacter.new()
		second.definition = DEFINITION
		root.add_child(second)
		_check(second.initialized, "Second character initializes")
		if second.initialized:
			source.apply_materials(
				second.materials[0],
				second.materials[1],
				[second.materials[2], second.materials[2].next_pass]
			)
			_check(
				(
					(
						second.materials[0].get_shader_parameter("u_npr_wetness_map")
						== source.body_mask
					)
					and body.get_shader_parameter("u_npr_wetness_map") == profile.body_mask
				),
				"Two characters retain independent bindings"
			)
		second.free()
	actor.free()
	var output := OS.get_cmdline_user_args()[1]
	await _render_tear_gate(output)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks}, "  ")
	)
	var passed := _checks.all(func(row: Dictionary): return row["pass"])
	print("REGRESSION_OK" if passed else "REGRESSION_FAILED")
	quit(0 if passed else 1)


func _render_tear_gate(output: String) -> void:
	var scene := SCENE.instantiate()
	scene.save_path = output.path_join("unused_scheme.json")
	root.add_child(scene)
	scene.performance.automatic = false
	scene.performance.set_process(false)
	scene.state.blink = false
	scene.state.secondary = false
	scene.state.hair_dynamic_enabled = false
	scene.state.eye_geometry_enabled = false
	scene.state.eye_wetness = 1.0
	scene._apply_state()
	scene.performance.apply_pose(0.0)
	scene.set_view("face")
	var baseline := await _capture_face(scene, output, "tear_default")
	var source: NPRWetnessProfile = scene.preview.definition.wetness_profile
	var profile := source.duplicate() as NPRWetnessProfile
	profile.eye_tear_uv_limit = Vector2.ZERO
	_check(profile.validate().is_empty(), "Zero tear UV limit validates as a disabled region")
	var face: ShaderMaterial = scene.preview.materials[1]
	var hairs: Array[ShaderMaterial] = [
		scene.preview.materials[2], scene.preview.materials[2].next_pass
	]
	profile.apply_materials(scene.preview.materials[0], face, hairs)
	var disabled := await _capture_face(scene, output, "tear_zero_region")
	_check(disabled != baseline, "Tear UV region changes actual original-eye rendering")
	face.set_shader_parameter("u_npr_eye_wetness", 0.0)
	var dry := await _capture_face(scene, output, "tear_dry")
	_check(dry == disabled, "Zero UV region removes tear contribution exactly")
	source.apply_materials(scene.preview.materials[0], face, hairs)
	face.set_shader_parameter("u_npr_eye_wetness", 1.0)
	var restored := await _capture_face(scene, output, "tear_restored")
	_check(restored == baseline, "Source tear region restores exact pixels")
	_check(
		source.eye_tear_uv_limit == Vector2(0.26, 0.32), "Sample tear calibration remains unchanged"
	)
	scene.free()


func _capture_face(scene: Control, output: String, label: String) -> PackedByteArray:
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = scene.viewport.get_texture().get_image()
	_check(image.save_png(output.path_join(label + ".png")) == OK, "Saved " + label)
	return image.get_data()


func _check(passed: bool, label: String) -> void:
	_checks.append({"label": label, "pass": passed})
	if not passed:
		push_error("WETNESS_PROFILE_FAILED: " + label)
