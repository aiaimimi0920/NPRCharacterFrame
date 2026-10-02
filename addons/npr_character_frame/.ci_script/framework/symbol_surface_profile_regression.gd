extends "performance_data_regression.gd"
## Shared character calibration reaches replacement meshes and both shader passes.

const SYMBOL_SURFACE = preload(
	"res://addons/npr_character_frame/runtime/face/npr_symbol_surface.gd"
)


func _run() -> void:
	_symbol_contract()
	_alternate_symbols()
	await super._run()


func _symbol_contract() -> void:
	var source: NPRSymbolSurfaceProfile = FACE_DEFINITION.symbol_surface_profile
	_check(source.validate().is_empty(), "Sample symbolic surface calibration validates")
	_check(not NPRSymbolSurfaceProfile.new().validate().is_empty(), "Unconfigured symbols rejected")
	var invalid := source.duplicate(true) as NPRSymbolSurfaceProfile
	invalid.eye_centers.resize(1)
	_check(not invalid.validate().is_empty(), "Both eye centers are required")
	invalid = source.duplicate(true)
	invalid.mouth_radius.x = 0.0
	_check(not invalid.validate().is_empty(), "Zero mouth radius is rejected")
	invalid = source.duplicate(true)
	invalid.eye_ink_scale.y = NAN
	_check(not invalid.validate().is_empty(), "Nonfinite glyph scale is rejected")
	invalid = source.duplicate(true)
	invalid.outline_eye_centers[0] = Vector2(INF, 0)
	_check(not invalid.validate().is_empty(), "Nonfinite outline center is rejected")
	var definition := FACE_DEFINITION.duplicate() as NPRCharacterDefinition
	definition.symbol_surface_profile = invalid
	_check(not definition.validate().is_empty(), "Character validates symbolic calibration")
	definition.symbol_surface_profile = null
	_check(definition.validate().is_empty(), "Base rendering permits no symbolic calibration")


func _alternate_symbols() -> void:
	var source: NPRSymbolSurfaceProfile = FACE_DEFINITION.symbol_surface_profile
	var profile := source.duplicate(true) as NPRSymbolSurfaceProfile
	profile.mouth_center.x += 0.004
	profile.mouth_radius *= 0.9
	profile.eye_centers[0] += Vector2(0.003, 0.002)
	profile.eye_centers[1] += Vector2(-0.003, 0.002)
	profile.outline_eye_centers[0] += Vector2(0.003, 0.002)
	profile.outline_eye_centers[1] += Vector2(-0.003, 0.002)
	var definition := FACE_DEFINITION.duplicate() as NPRCharacterDefinition
	definition.symbol_surface_profile = profile
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate symbol calibration initializes actor")
	if not actor.initialized:
		actor.free()
		return
	var driver := DRIVER.new()
	driver.automatic = false
	actor.add_child(driver)
	driver.setup(actor)
	var face := actor.meshes[1]
	var space: Transform3D = actor.global_transform.affine_inverse() * face.global_transform
	var mouth := SYMBOL_SURFACE.new()
	mouth.setup(face, space, actor.materials[1], profile)
	var mouth_vertices: PackedVector3Array = mouth.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var first := space * mouth_vertices[0]
	_check(
		Vector2(first.x, first.y).is_equal_approx(profile.mouth_center - profile.mouth_radius),
		"Authored mouth center and radius move the actual replacement boundary"
	)
	var eyes := SYMBOL_SURFACE.new()
	eyes.setup(face, space, actor.materials[1], profile, true)
	var eye_vertices: PackedVector3Array = eyes.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for side in 2:
		var vertex: Vector3 = space * eye_vertices[side * (eye_vertices.size() / 2)]
		_check(
			Vector2(vertex.x, vertex.y).is_equal_approx(
				profile.eye_centers[side] - profile.eye_radius
			),
			"Authored eye center moves replacement side " + str(side)
		)
	_check(
		(
			actor.materials[1].get_shader_parameter("u_npr_symbol_mouth_center")
			== profile.mouth_center
		),
		"Face shader receives matching mouth calibration"
	)
	_check(
		(
			actor.outlines[1].get_shader_parameter("u_npr_symbol_outline_eye_left")
			== profile.outline_eye_centers[0]
		),
		"Outline shader receives character-specific eye masking"
	)
	_check(
		source.mouth_center != profile.mouth_center and source.eye_centers != profile.eye_centers,
		"Alternate calibration leaves the sample resource unchanged"
	)
	actor.free()
