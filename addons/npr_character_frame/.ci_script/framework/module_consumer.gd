extends Node
## Runs unchanged in the source project, an addon-only consumer, and its release PCK.

const FACTORY = preload("res://addons/npr_character_frame/examples/mannequin_factory.gd")
const VALIDATOR = preload("res://addons/npr_character_frame/runtime/npr_model_validator.gd")
const INSTALLER = preload("res://addons/npr_character_frame/config/install_settings.gd")

var _checks: Array[Dictionary] = []
var _failures := 0
var _output := ""


func _ready() -> void:
	_output = OS.get_cmdline_user_args()[-1]
	get_window().mouse_passthrough = true
	get_window().unfocusable = true
	_run.call_deferred()


func _run() -> void:
	var definition := FACTORY.create_definition()
	_check(definition.validate().is_empty(), "Generated input definition is valid")
	var model := definition.model_scene.instantiate() as Node3D
	_check(
		VALIDATOR.validate(model, definition.mesh_paths(), false).is_empty(), "Three-role geometry"
	)
	var face_mesh := model.get_node(definition.face_path) as MeshInstance3D
	var original_face_mesh := face_mesh.mesh as ArrayMesh
	var arrays := original_face_mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_TEX_UV2] = null
	var missing_uv2 := ArrayMesh.new()
	missing_uv2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	face_mesh.mesh = missing_uv2
	_check(
		not VALIDATOR.validate(model, definition.mesh_paths(), false, true).is_empty(),
		"Missing UV2 rejected"
	)
	face_mesh.mesh = original_face_mesh
	var extra := MeshInstance3D.new()
	extra.mesh = model.get_node("Body").mesh
	model.add_child(extra)
	_check(
		not VALIDATOR.validate(model, definition.mesh_paths(), false).is_empty(),
		"Unbound equipment rejected"
	)
	extra.free()
	var original_lut := definition.material_set.body_lut
	definition.material_set.body_lut = definition.material_set.body_base
	_check(not definition.validate().is_empty(), "Undersized LUT rejected before rendering")
	definition.material_set.body_lut = original_lut
	definition.material_set.face_right = Vector3(0, 0, 1)
	_check(not definition.validate().is_empty(), "Collinear face axes rejected")
	definition.material_set.face_right = Vector3.RIGHT
	# Actual glTF round trip, independent of the Silver Wolf Godot scene format.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	_check(document.append_from_scene(model, state) == OK, "glTF export accepts source geometry")
	var buffer := document.generate_buffer(state)
	var imported := GLTFState.new()
	_check(document.append_from_buffer(buffer, "", imported) == OK, "GLB byte stream imports")
	var imported_model := document.generate_scene(imported)
	model.free()
	_check(
		VALIDATOR.validate(imported_model, definition.mesh_paths(), false).is_empty(),
		"Imported GLB preserves role bindings"
	)
	var scene := PackedScene.new()
	_check(scene.pack(imported_model) == OK, "Imported model packs without rig script")
	imported_model.free()
	definition.model_scene = scene
	var world := Node3D.new()
	add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = preload(
		"res://addons/npr_character_frame/materials/studio_environment.tres"
	)
	world.add_child(environment)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.55, 5)
	camera.current = true
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var actor := NPRCharacter.new()
	actor.definition = definition
	actor.set_hair_highlight(0.47)
	world.add_child(actor)
	_check(actor.initialized and actor.validation_errors.is_empty(), "Generic actor initializes")
	if not actor.initialized:
		_finish()
		return
	_check(
		is_equal_approx(actor.materials[2].get_shader_parameter("u_hair_highlight_strength"), 0.47),
		"Pre-ready setter retained"
	)
	actor.set_face_expression(Vector3(0.2, 0.3, 0.4))
	_check(
		(
			actor.materials[1].get_shader_parameter("u_npr_expression_weights")
			== Vector3(0.2, 0.3, 0.4)
		),
		"Face expression weights reach the production material"
	)
	actor.set_face_expression(Vector3.ZERO)
	actor.set_dissolve(0.25)
	_check(
		(
			is_equal_approx(
				actor.depth_pass._encoders[0].get_shader_parameter("u_npr_dissolve_amount"), 0.25
			)
			and is_equal_approx(
				actor.character._casters[0].get_shader_parameter("u_npr_dissolve_amount"), 0.25
			)
			and is_equal_approx(
				actor.outlines[0].get_shader_parameter("u_npr_dissolve_amount"), 0.25
			)
		),
		"Dissolve amount is synchronized across color, outline, depth and shadow"
	)
	actor.set_dissolve(0.0)
	actor.set_visibility_alpha(0.5)
	_check(
		(
			is_equal_approx(
				actor.depth_pass._encoders[0].get_shader_parameter("u_npr_visibility_alpha"), 0.5
			)
			and bool(
				actor.character._casters[0].get_shader_parameter("u_npr_visibility_dither_enabled")
			)
			and is_equal_approx(
				actor.outlines[0].get_shader_parameter("u_npr_visibility_alpha"), 0.5
			)
		),
		"Dithered alpha visibility is synchronized across auxiliary passes"
	)
	actor.set_visibility_alpha(1.0)
	actor.set_auxiliary_buffer_enabled(true)
	await _frames(6)
	var auxiliary := actor.get_auxiliary_texture().get_image()
	_check(_coverage(auxiliary) > 1000, "Normal/material auxiliary buffer contains character data")
	actor.set_auxiliary_buffer_enabled(false)
	actor.set_hair_highlight(0.30)
	await _frames(12)
	_check(actor.isolation_available, "Actor leases an isolated lighting layer")
	_check(
		absf(actor.get_world_bounds().size.y - 3.0) < 0.01,
		"Generic model normalized to requested height"
	)
	_check(
		actor.depth_pass.redraw_requests[0] > 0 and actor.depth_pass.redraw_requests[1] > 0,
		"Both depth producers rendered"
	)
	var base := await _capture("generic_front")
	_check(_coverage(base) > 1000, "GPU output contains visible character pixels")
	var face_pixel := base.get_pixel(base.get_width() / 2, int(base.get_height() * 0.39))
	_check(
		face_pixel.g < 0.95 and face_pixel.r > face_pixel.g + 0.05,
		"Unbound capture fog cannot bleach generic face"
	)
	actor.light_yaw = 120
	var changed := await _capture("generic_back_light")
	_check(base.get_data() != changed.get_data(), "Lighting and generic SDF affect real pixels")
	actor.light_yaw = -45
	actor.rotation_degrees.y = 35
	await _capture("generic_quarter")
	actor.rotation_degrees.y = 0
	var second := NPRCharacter.new()
	second.definition = definition
	second.position.x = 1.1
	actor.position.x = -1.1
	world.add_child(second)
	await _frames(8)
	_check(second.initialized, "Same definition creates a second actor")
	_check(actor.materials[0] != second.materials[0], "Body material instances are isolated")
	_check(
		actor.materials[2].next_pass != second.materials[2].next_pass,
		"Eye-hair passes are isolated"
	)
	var peer_highlight: float = second.materials[2].get_shader_parameter(
		"u_hair_highlight_strength"
	)
	_check(is_zero_approx(peer_highlight), "Generic hair highlight is opt-in")
	actor.set_hair_highlight(0.8)
	_check(
		is_equal_approx(
			second.materials[2].get_shader_parameter("u_hair_highlight_strength"), peer_highlight
		),
		"Editing actor does not mutate peer"
	)
	_check(
		actor.character.key_pool.get_group_count() == 1,
		"Compatible generic actors share a key light"
	)
	await _capture("generic_two_actors")
	world.remove_child(second)
	world.add_child(second)
	await _frames(8)
	_check(second.character.key_pool != null, "Reparented actor restores its key lease")
	_check(
		second.pick_surface(Vector3(1.1, 1.5, 5), Vector3(0, 0, -1)).size() > 0,
		"Imported generic geometry supports picking"
	)
	# Installer conflict must be atomic: no default globals are modified on failure.
	var setting := "shader_globals/g_u_character_shadow_factor"
	var prior: Variant = ProjectSettings.get_setting(setting)
	ProjectSettings.set_setting(setting, {"type": "bool", "value": true})
	_check(not INSTALLER.install().is_empty(), "Host shader-global conflict rejected")
	_check(
		ProjectSettings.get_setting(setting).type == "bool",
		"Installer leaves conflicting host value untouched"
	)
	ProjectSettings.set_setting(setting, prior)
	world.queue_free()
	await _frames(4)
	_finish()


func _frames(count: int) -> void:
	for frame in range(count):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture(label: String) -> Image:
	await _frames(8)
	var image := get_viewport().get_texture().get_image()
	_check(image.save_png(_output.path_join(label + ".png")) == OK, "Capture " + label)
	return image


func _coverage(image: Image) -> int:
	var background := image.get_pixel(0, 0)
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var color := image.get_pixel(x, y)
			if (
				(
					absf(color.r - background.r)
					+ absf(color.g - background.g)
					+ absf(color.b - background.b)
				)
				> 0.08
			):
				count += 1
	return count


func _check(condition: bool, label: String) -> void:
	_checks.append({"check": label, "pass": condition})
	if not condition:
		_failures += 1
		print("MODULE_CHECK_FAILED: ", label)


func _finish() -> void:
	var file := FileAccess.open(_output.path_join("module_checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures}, "  "))
	print("REGRESSION_OK" if _failures == 0 else "REGRESSION_FAILED")
	get_tree().quit(0 if _failures == 0 else 1)
