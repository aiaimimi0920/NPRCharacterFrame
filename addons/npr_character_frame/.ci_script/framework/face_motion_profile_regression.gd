extends "framework_expression_regression.gd"
## Configuration rejection, independent authored input and production face behavior.

const FACE_DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const LID_RUNTIME = preload("res://addons/npr_character_frame/runtime/face/npr_eyelids.gd")
const EYE_RUNTIME = preload("res://addons/npr_character_frame/runtime/face/npr_eye_motion.gd")


func _run() -> void:
	_profile_contract()
	await super._run()


func _profile_contract() -> void:
	var source: NPRFaceMotionProfile = FACE_DEFINITION.face_motion_profile
	_check(source.validate().is_empty(), "Sample face calibration satisfies the profile contract")
	_check(
		not NPRFaceMotionProfile.new().validate().is_empty(),
		"An unconfigured profile cannot silently use sample calibration"
	)
	var invalid := source.duplicate() as NPRFaceMotionProfile
	invalid.pupil_scale_step = 0.0
	_check(not invalid.validate().is_empty(), "Zero pupil scale denominator is rejected")
	invalid = source.duplicate()
	invalid.lid_canvas_scale = Vector2(NAN, 1)
	_check(not invalid.validate().is_empty(), "Nonfinite canvas coordinates are rejected")
	invalid = source.duplicate()
	invalid.horizontal_motion = PackedVector3Array([Vector3.ZERO])
	_check(not invalid.validate().is_empty(), "A missing eye side is rejected")
	var definition := FACE_DEFINITION.duplicate() as NPRCharacterDefinition
	definition.face_motion_profile = invalid
	_check(not definition.validate().is_empty(), "Character validation includes face configuration")
	var data := source.load_lid_data()
	_check_lid_side_keys(data)
	var damaged := data.duplicate(true)
	damaged.surfaces[0].closed.pop_back()
	_check(
		not NPRFaceMotionProfile.validate_lid_data(damaged).is_empty(),
		"Mismatched authored lid deltas are rejected before mesh creation"
	)
	damaged = data.duplicate(true)
	damaged.surfaces[0].indices[0] = -1
	_check(
		not NPRFaceMotionProfile.validate_lid_data(damaged).is_empty(),
		"Negative surface index is rejected"
	)
	damaged = data.duplicate(true)
	damaged.lash_vertices.L[0] = 2147483647
	_check(
		not NPRFaceMotionProfile.validate_lid_data(damaged, 100000).is_empty(),
		"Lash indices are checked against source face topology"
	)
	var material := ShaderMaterial.new()
	var baseline := LID_RUNTIME.new()
	baseline.setup(material, source)
	var alternate := source.duplicate() as NPRFaceMotionProfile
	alternate.lid_centers = source.lid_centers.duplicate()
	alternate.lid_centers[0] += Vector2(0.02, 0)
	var altered_data := data.duplicate(true)
	altered_data.surfaces[0].closed[0][0] += 0.025
	var path := _output.path_join("alternate_lids.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(altered_data))
	file.close()
	alternate.lid_surface_path = ProjectSettings.localize_path(path.replace("\\", "/"))
	var alternate_errors := alternate.validate()
	_check(
		alternate_errors.is_empty(),
		"Alternate authored asset path validates: " + "; ".join(alternate_errors)
	)
	var other := LID_RUNTIME.new()
	other.setup(material, alternate)
	var original: Array = baseline.surfaces[0].mesh.surface_get_arrays(0)
	var modified: Array = other.surfaces[0].mesh.surface_get_arrays(0)
	_check(
		original[Mesh.ARRAY_CUSTOM1] != modified[Mesh.ARRAY_CUSTOM1],
		"Alternate coordinates and data drive the actual lid canvas"
	)
	_check(
		source.load_lid_data() == data and source.lid_centers != alternate.lid_centers,
		"Per-character calibration leaves shared sample data unchanged"
	)
	baseline.apply(0.5)
	_check(
		(
			baseline.surfaces[0].get_blend_shape_value(0) == 0.5
			and baseline.surfaces[0].get_blend_shape_value(1) == 1.0
		),
		"Half closure preserves the authored arc evaluation"
	)
	baseline.free()
	other.free()
	_check_eye_binding(source, data)


func _check_lid_side_keys(data: Dictionary) -> void:
	var damaged := data.duplicate(true)
	damaged.lash_vertices["extra"] = "bad"
	_check(
		not NPRFaceMotionProfile.validate_lid_data(damaged).is_empty(),
		"Unexpected lash side cannot bypass validation and enter mesh generation"
	)


func _check_eye_binding(source: NPRFaceMotionProfile, data: Dictionary) -> void:
	# A six-vertex fixture has a different topology from the delivered character.
	var profile := source.duplicate() as NPRFaceMotionProfile
	profile.minimum_eye_vertices = 3
	profile.expected_pupil_vertices = 3
	profile.horizontal_motion = PackedVector3Array([Vector3(0.02, 0, 0), Vector3(0.03, 0, 0)])
	var authored := data.duplicate(true)
	authored.lash_vertices = {"L": [0], "R": [3]}
	var path := _output.path_join("eye_binding_lids.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(authored))
	file.close()
	profile.lid_surface_path = ProjectSettings.localize_path(path.replace("\\", "/"))
	_check(profile.validate().is_empty(), "A different eye topology has valid authored calibration")
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[
			Vector3(-0.2, 2.52, 0.05),
			Vector3(-0.19, 2.52, 0.05),
			Vector3(-0.2, 2.53, 0.05),
			Vector3(0.2, 2.52, 0.05),
			Vector3(0.21, 2.52, 0.05),
			Vector3(0.2, 2.53, 0.05),
		]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var uv := PackedVector2Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	for index in 6:
		uv.append(Vector2(0.30, 0.90))
		normals.append(Vector3.FORWARD)
		tangents.append_array(PackedFloat32Array([1, 0, 0, 1]))
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	var shapes: Array[Array] = []
	EYE_RUNTIME.append_shapes(mesh, arrays, shapes, Transform3D.IDENTITY, profile)
	_check(shapes.size() == 12, "Independent topology produces both sets of six eye controls")
	_check(
		(
			shapes[0][Mesh.ARRAY_VERTEX][0] == Vector3(0.02, 0, 0)
			and shapes[6][Mesh.ARRAY_VERTEX][3] == Vector3(0.03, 0, 0)
		),
		"Both eyes use their own configured motion instead of sample displacements"
	)
