extends SceneTree
## Verify texture contracts and alternate inputs in the production fitted layer.

const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const DRIVER = preload("res://addons/npr_character_frame/runtime/animation/npr_performance.gd")
const VISUAL = preload("res://addons/npr_character_frame/showcase/wardrobe_visual_layers.gd")
const FITTED = preload("res://addons/npr_character_frame/runtime/hosiery/npr_fitted_hosiery.gd")
const GARMENT_GEOMETRY = preload(
	"res://addons/npr_character_frame/runtime/hosiery/npr_garment_geometry.gd"
)
const SAMPLERS := {
	"weave_texture": "albedo_texture",
	"roughness_texture": "roughness_texture",
	"normal_texture": "normal_texture",
	"garment_mask": "garment_mask",
}
const BODY_SAMPLERS := {
	"garment_mask": "u_npr_garment_mask",
	"tulle_mask": "u_npr_tulle_mask",
	"stitch_mask": "u_npr_stitch_mask",
}

var _checks: Array[Dictionary] = []
var _output: String


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	_validate_profile()
	_validate_domain()
	_validate_cuff()
	_validate_textile()
	_validate_leg_ao()
	_validate_normals()
	_alternate_textures()
	var failed := _checks.filter(func(check: Dictionary): return not check["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks}, "  ")
	)
	print("HOSIERY_PROFILE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _validate_profile() -> void:
	var source: NPRHosieryProfile = DEFINITION.hosiery_profile
	_check(source.validate().is_empty(), "Sample hosiery profile validates")
	_check(not NPRHosieryProfile.new().validate().is_empty(), "Empty texture profile rejected")
	for field: String in SAMPLERS.keys() + ["tulle_mask", "stitch_mask"]:
		var invalid := source.duplicate() as NPRHosieryProfile
		invalid.set(field, null)
		_check(not invalid.validate().is_empty(), field + " is required")
		invalid.set(field, ImageTexture.new())
		_check(not invalid.validate().is_empty(), field + " requires image dimensions")
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.hosiery_profile = NPRHosieryProfile.new()
	_check(not definition.validate().is_empty(), "Character propagates hosiery profile errors")
	definition.hosiery_profile = null
	_check(definition.validate().is_empty(), "Base rendering permits no fitted hosiery profile")


func _validate_domain() -> void:
	var source: NPRHosieryProfile = DEFINITION.hosiery_profile
	for values in [
		["domain_height_range", Vector2(2, 1)],
		["domain_height_range", Vector2(1, 1)],
		["domain_height_range", Vector2(NAN, 1)],
		["domain_half_width", 0.0],
		["domain_half_width", INF],
		["domain_full_width_below", NAN],
	]:
		var invalid := source.duplicate() as NPRHosieryProfile
		invalid.set(values[0], values[1])
		_check(not invalid.validate().is_empty(), str(values[0]) + " rejects invalid domain")
	var profile := source.duplicate() as NPRHosieryProfile
	profile.domain_height_range = Vector2(1, 3)
	profile.domain_half_width = 0.5
	profile.domain_full_width_below = 2.0
	_check(profile.validate().is_empty(), "Alternate Body domain validates")
	var vertices := PackedVector3Array(
		[
			Vector3(0, 0, 0),
			Vector3(0, 2, 0),
			Vector3(0.5, 1, 0),
			Vector3(-0.5, 1, 0),
			Vector3(4, 0.5, 0),
			Vector3(0.25, 1, 0),
		]
	)
	var saved := vertices.duplicate()
	var regions := profile.build_regions(vertices, Transform3D(Basis.IDENTITY, Vector3(0, 1, 2)))
	_check(
		(
			regions
			== PackedFloat32Array(
				[
					0,
					0,
					1,
					2,
					0,
					0,
					3,
					2,
					0,
					0.5,
					2,
					2,
					0,
					-0.5,
					2,
					2,
					1,
					4,
					1.5,
					2,
					1,
					0.25,
					2,
					2,
				]
			)
		),
		"Transformed rest positions and strict domain boundaries reach CUSTOM0 layout"
	)
	_check(vertices == saved, "Domain construction preserves source vertices")
	_check(
		(
			source.domain_height_range == Vector2(0.45, 1.55)
			and is_equal_approx(source.domain_half_width, 0.32)
			and is_equal_approx(source.domain_full_width_below, 1.05)
		),
		"Alternate domain leaves sample configuration unchanged"
	)


func _validate_leg_ao() -> void:
	var source: NPRHosieryProfile = DEFINITION.hosiery_profile
	_check(
		not NPRHosieryProfile.new().leg_ao_repair_enabled,
		"New profiles do not apply sample AO repair"
	)
	for values in [
		["leg_ao_repair_uv", Vector4(NAN, 0, 1, 1)],
		["leg_ao_repair_uv", Vector4(-0.1, 0, 1, 1)],
		["leg_ao_repair_uv", Vector4(0, 0, 1.1, 1)],
		["leg_ao_repair_uv", Vector4(0.5, 0, 0.5, 1)],
		["leg_ao_repair_uv", Vector4(0, 1, 1, 0)],
		["leg_ao_repair_values", Vector3(1, 1, 0)],
		["leg_ao_repair_values", Vector3(2, 1, 0)],
		["leg_ao_repair_values", Vector3(0, INF, 0)],
		["leg_ao_repair_values", Vector3(0, 1, -0.1)],
		["leg_ao_repair_values", Vector3(0, 1, 1.1)],
	]:
		var profile := source.duplicate() as NPRHosieryProfile
		profile.set(values[0], values[1])
		_check(not profile.validate().is_empty(), str(values[0]) + " rejects invalid calibration")


func _validate_textile() -> void:
	var source: NPRHosieryProfile = DEFINITION.hosiery_profile
	for values in [
		["textile_period_m", 0.0],
		["textile_period_m", -0.01],
		["textile_period_m", INF],
		["textile_period_m", NAN],
		["textile_repeats", 0],
		["textile_repeats", -1],
		["shell_offset_m", -0.01],
		["shell_offset_m", INF],
		["shell_offset_m", NAN],
	]:
		var profile := source.duplicate() as NPRHosieryProfile
		profile.set(values[0], values[1])
		_check(not profile.validate().is_empty(), str(values[0]) + " rejects invalid scale")
	var profile := source.duplicate() as NPRHosieryProfile
	profile.shell_offset_m = 0.0
	_check(profile.validate().is_empty(), "Zero shell offset is valid")


func _validate_cuff() -> void:
	var source: NPRHosieryProfile = DEFINITION.hosiery_profile
	for field in ["cuff_band_width", "cuff_stitch_width", "cuff_stitch_offset"]:
		for value in [-0.01, INF, NAN]:
			var profile := source.duplicate() as NPRHosieryProfile
			profile.set(field, value)
			_check(not profile.validate().is_empty(), field + " rejects invalid value")
	for field in ["cuff_band_width", "cuff_stitch_width"]:
		var profile := source.duplicate() as NPRHosieryProfile
		profile.set(field, 0.0)
		_check(not profile.validate().is_empty(), field + " rejects zero width")


func _validate_normals() -> void:
	var source: NPRHosieryProfile = DEFINITION.hosiery_profile
	var profile := source.duplicate() as NPRHosieryProfile
	profile.normal_correction_path = ""
	_check(profile.validate().is_empty(), "Authored normals may require no correction")
	profile.normal_correction_path = "res://.temp/missing_normal_correction.json"
	_check(not profile.validate().is_empty(), "Missing configured correction is rejected")
	var valid := {"schema": 1, "vertex_count": 2, "normal_rows": [[1, 1, 2, 3, 0, 1, 0]]}
	var vertices := PackedVector3Array([Vector3.ZERO, Vector3(1, 2, 3)])
	_check(source.BODY_SURFACE.validate(valid, vertices).is_empty(), "Sparse correction validates")
	for values in [
		["schema", 2],
		["vertex_count", 0],
		["vertex_count", 2.5],
		["normal_rows", null],
		["normal_rows", [[0]]],
		["normal_rows", [[-1, 1, 2, 3, 0, 1, 0]]],
		["normal_rows", [[2, 1, 2, 3, 0, 1, 0]]],
		["normal_rows", [[0.5, 1, 2, 3, 0, 1, 0]]],
		["normal_rows", [[1, 1, 2, 3, 0, 0, 0]]],
		["normal_rows", [[1, NAN, 2, 3, 0, 1, 0]]],
		["normal_rows", [[1, 1, 2, 3, 0, INF, 0]]],
		["normal_rows", [[1, 1, 2, 3, 0, 1, 0], [1, 1, 2, 3, 1, 0, 0]]],
	]:
		var invalid := valid.duplicate(true)
		invalid[values[0]] = values[1]
		_check(
			not source.BODY_SURFACE.validate(invalid).is_empty(),
			"Invalid correction: " + str(values[0])
		)
	_check(
		not source.BODY_SURFACE.validate(valid, PackedVector3Array()).is_empty(),
		"Original vertex count mismatch rejected"
	)
	var wrong := vertices.duplicate()
	wrong[1].x += 0.001
	_check(
		not source.BODY_SURFACE.validate(valid, wrong).is_empty(),
		"Reordered or moved source rejected"
	)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = wrong
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT])
	var saved: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
	_check(
		not source.BODY_SURFACE.apply_normals(arrays, valid).is_empty(),
		"Invalid correction cannot apply"
	)
	_check(arrays[Mesh.ARRAY_NORMAL] == saved, "Rejected correction leaves every normal unchanged")
	arrays[Mesh.ARRAY_VERTEX] = vertices
	_check(source.BODY_SURFACE.apply_normals(arrays, valid).is_empty(), "Valid correction applies")
	_check(
		arrays[Mesh.ARRAY_NORMAL] == PackedVector3Array([Vector3.RIGHT, Vector3.UP]),
		"Only authored normal indices change"
	)
	var first := source.load_normal_correction()
	first.normal_rows.clear()
	_check(
		not source.load_normal_correction().normal_rows.is_empty(),
		"Loaded correction data is independent"
	)


func _alternate_textures() -> void:
	var source: NPRHosieryProfile = DEFINITION.hosiery_profile
	var profile := source.duplicate() as NPRHosieryProfile
	var index := 0
	for field: String in SAMPLERS.keys() + ["tulle_mask", "stitch_mask"]:
		var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		pixels.fill(Color(0.2 + index * 0.1, 0.5, 1.0, 1.0))
		profile.set(field, ImageTexture.create_from_image(pixels))
		index += 1
	var correction := source.load_normal_correction()
	var corrected_index := int(correction.normal_rows[0][0])
	correction.normal_rows[0][4] = 0.6
	correction.normal_rows[0][5] = 0.8
	correction.normal_rows[0][6] = 0.0
	var correction_path := _output.path_join("alternate_normals.json")
	FileAccess.open(correction_path, FileAccess.WRITE).store_string(JSON.stringify(correction))
	profile.normal_correction_path = ProjectSettings.localize_path(
		correction_path.replace("\\", "/")
	)
	_check(profile.validate().is_empty(), "Alternate texture dimensions validate")
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.hosiery_profile = profile
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate hosiery profile initializes production character")
	if not actor.initialized:
		actor.free()
		return
	profile.apply_body_material(actor.materials[0])
	for field: String in BODY_SAMPLERS:
		_check(
			actor.materials[0].get_shader_parameter(BODY_SAMPLERS[field]) == profile.get(field),
			field + " reaches actual Body sampler"
		)
		_check(profile.get(field) != source.get(field), field + " sample texture remains unchanged")
	profile.domain_height_range = Vector2(100, 101)
	var original_mesh: ArrayMesh = actor.meshes[0].mesh
	GARMENT_GEOMETRY.install(
		actor.meshes[0],
		actor.global_transform.affine_inverse() * actor.meshes[0].global_transform,
		profile
	)
	_check(actor.meshes[0].mesh != original_mesh, "Independent builder creates a private mesh")
	_check(
		actor.meshes[0].mesh.surface_get_material(0) == original_mesh.surface_get_material(0),
		"Independent builder preserves the material binding"
	)
	var before_arrays := original_mesh.surface_get_arrays(0)
	var after_arrays := actor.meshes[0].mesh.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		_check(
			before_arrays[channel] == after_arrays[channel],
			"Independent builder preserves channel " + str(channel)
		)
	var corrected: PackedVector3Array = actor.meshes[0].mesh.surface_get_arrays(0)[
		Mesh.ARRAY_NORMAL
	]
	_check(
		corrected[corrected_index].distance_to(Vector3(0.6, 0.8, 0)) < 0.0004,
		"Alternate correction path reaches the actual Body normal"
	)
	_check(
		source.load_normal_correction() != correction,
		"Alternate correction leaves sample JSON unchanged"
	)
	var regions: PackedFloat32Array = actor.meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	var empty_domain := not regions.is_empty()
	for vertex in regions.size() / 4:
		empty_domain = empty_domain and regions[vertex * 4] == 0.0
	_check(empty_domain, "Alternate profile bounds reach the actual private Body domain")
	_check(
		original_mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] == null,
		"Body domain installation preserves the original mesh"
	)
	var driver := DRIVER.new()
	driver.automatic = false
	actor.add_child(driver)
	driver.setup(actor)
	var layers := VISUAL.new()
	layers.actor = actor
	actor.add_child(layers)
	layers._build_tulle_geometry()
	var shell := layers.tulle_layer.get_node("FittedHosiery") as MeshInstance3D
	var material := shell.material_override as ShaderMaterial
	_check(
		(
			material.get_shader_parameter("garment_mask")
			== actor.materials[0].get_shader_parameter("u_npr_garment_mask")
		),
		"Body dye/coverage and fitted layer use the same configured garment mask"
	)
	for field: String in SAMPLERS:
		_check(
			material.get_shader_parameter(SAMPLERS[field]) == profile.get(field),
			field + " reaches production shell sampler"
		)
		_check(source.get(field) != profile.get(field), field + " sample remains unchanged")
	_check(shell.mesh == actor.meshes[0].mesh, "Fitted shell shares animated Body geometry")
	_check(
		shell.get_node(shell.skeleton) == actor.meshes[0].get_node(actor.meshes[0].skeleton),
		"Fitted shell shares Body skeleton"
	)
	var second := FITTED.new()
	actor.add_child(second)
	second.setup(actor.meshes[0], profile)
	var second_shell: MeshInstance3D = second.mesh_instance
	_check(second_shell.material_override != material, "Fitted instances retain private materials")
	_check(not second.visible, "Independent runtime layer starts hidden")
	_check(second_shell.mesh == shell.mesh, "Independent runtime uses the same animated Body")
	_check(
		second_shell.get_node(second_shell.skeleton) == shell.get_node(shell.skeleton),
		"Independent runtime binds the actual Body skeleton"
	)
	var initial_opacity: Variant = material.get_shader_parameter("opacity")
	second.set_surface_state(0.3, 1.2, 0.7)
	_check(
		(
			is_equal_approx(second.material.get_shader_parameter("opacity"), 0.3)
			and is_equal_approx(second.material.get_shader_parameter("u_npr_hosiery_height"), 1.2)
			and is_equal_approx(second.material.get_shader_parameter("u_npr_stitch_strength"), 0.7)
		),
		"Independent runtime applies explicit surface controls"
	)
	_check(
		material.get_shader_parameter("opacity") == initial_opacity,
		"Independent controls do not change another instance"
	)
	actor.meshes[0].mesh = actor.meshes[0].mesh.duplicate()
	layers._sync_fitted_hosiery()
	_check(shell.mesh == actor.meshes[0].mesh, "Body rebuild refreshes fitted geometry binding")
	second.sync_body()
	_check(second_shell.mesh == actor.meshes[0].mesh, "Independent runtime follows Body rebuild")
	var body: MeshInstance3D = actor.meshes[0]
	body.position += Vector3(0.01, 0.02, 0.03)
	body.custom_aabb = AABB(Vector3(-1, -2, -3), Vector3(2, 4, 6))
	body.extra_cull_margin = 0.12
	second.sync_body()
	_check(second_shell.global_transform == body.global_transform, "Runtime follows Body transform")
	_check(
		(
			second_shell.custom_aabb == body.custom_aabb
			and is_equal_approx(second_shell.extra_cull_margin, 0.14)
		),
		"Runtime preserves animated bounds and culling padding"
	)
	second.free()
	_check(
		not is_instance_valid(second_shell) and is_instance_valid(body),
		"Runtime owns only its fitted nodes"
	)
	actor.free()


func _check(passed: bool, label: String) -> void:
	_checks.append({"label": label, "pass": passed})
	if not passed:
		push_error("HOSIERY_PROFILE_FAILED: " + label)
