extends "symbol_surface_profile_regression.gd"
## Validate ocular assets and prove alternate scene/landmarks reach production bindings.

const FACE_RIG_TEST = preload("res://addons/npr_character_frame/runtime/face/npr_face_rig.gd")
const GEOMETRY = preload("res://addons/npr_character_frame/runtime/face/npr_eye_geometry.gd")
const CONTROLS = preload("res://addons/npr_character_frame/runtime/face/npr_eye_controls.gd")
const PRESENTATION = preload(
	"res://addons/npr_character_frame/runtime/face/npr_face_presentation.gd"
)


func _run() -> void:
	_eye_contract()
	await _alternate_eye()
	_standalone_assembly()
	await super._run()


func _standalone_assembly() -> void:
	var first := Node3D.new()
	var second := Node3D.new()
	var profile: NPREyeGeometryProfile = FACE_DEFINITION.eye_geometry_profile
	var face_motion: NPRFaceMotionProfile = FACE_DEFINITION.face_motion_profile
	GEOMETRY.assemble(first, profile, face_motion, ShaderMaterial.new(), 8, 0.25)
	GEOMETRY.assemble(second, profile, face_motion, ShaderMaterial.new(), 16, 0.75)
	_check(first.get_child_count() == 2, "Standalone assembly creates both eyes without showcase")
	for side in ["EyeL", "EyeR"]:
		var path: String = side + "/" + side + "_TearFilm"
		var a := first.get_node(path) as MeshInstance3D
		var b := second.get_node(path) as MeshInstance3D
		_check(a.layers == 8 and b.layers == 16, side + " standalone render layers are explicit")
		_check(
			a.material_override != b.material_override, side + " instances own optical materials"
		)
		_check(
			is_equal_approx(a.material_override.get_shader_parameter("wetness"), 0.25),
			side + " first wetness remains independent"
		)
		_check(
			is_equal_approx(b.material_override.get_shader_parameter("wetness"), 0.75),
			side + " second wetness remains independent"
		)
		var curve: PackedVector4Array = a.material_override.get_shader_parameter("eye_profile")
		_check(curve.size() == 65, side + " standalone assembly binds lid profile")
	_standalone_controls(first, profile)
	first.free()
	second.free()


func _standalone_controls(layer: Node3D, profile: NPREyeGeometryProfile) -> void:
	var controls := CONTROLS.new()
	var calls := {"left": Vector3.ZERO, "right": Vector3.ZERO, "signals": 0}
	var callback := func(left: Vector3, right: Vector3) -> void:
		calls.left = left
		calls.right = right
	controls.controls_changed.connect(func() -> void: calls.signals += 1)
	controls.bind(layer, layer, ShaderMaterial.new(), profile, callback)
	controls.set_eye_focus(Vector2(0.3, -0.4), 0)
	controls.set_pupil_scale(1.2, 1)
	_check(
		calls.left == Vector3(0, 0, 1) and calls.right == Vector3(0, 0, 1),
		"Diagnostic representation neutralizes original eye controls"
	)
	layer.visible = false
	controls.apply_pupils()
	_check(
		calls.left == Vector3(0.3, -0.4, 1) and calls.right == Vector3(0, 0, 1.2),
		"Original representation restores latest independent inputs"
	)
	controls.set_eye_focus(Vector2(NAN, 0), 0)
	controls.set_pupil_scale(INF, 1)
	controls.set_eye_focus(Vector2.ONE, 2)
	_check(calls.signals == 2, "Rejected inputs do not emit change signals")
	controls.set_pupil_scale(10, 1)
	_check(
		is_equal_approx(controls.eye_pupil_contract(1).scale, 1.35),
		"Standalone pupil scale retains clamp"
	)
	controls.set_eye_lid_closure(0.6)
	controls.set_eye_wetness(0.8)
	var tear := layer.get_node("EyeL/EyeL_TearFilm") as MeshInstance3D
	_check(
		is_equal_approx(tear.material_override.get_shader_parameter("wetness"), 0.8),
		"Standalone controller applies tear wetness"
	)
	_check(
		is_equal_approx(tear.material_override.get_shader_parameter("lid_closure"), 0.6),
		"Standalone controller applies lid closure"
	)
	controls.restore(Vector3(-0.2, 0.1, 0.9), Vector3(0.4, -0.1, 1.1))
	_check(calls.signals == 3, "Scheme restore remains silent")
	controls.apply_pupils()
	_check(calls.left == Vector3(-0.2, 0.1, 0.9), "Restored scheme reaches original callback")
	controls.reset()
	_check(
		calls.left == Vector3(0, 0, 1) and calls.right == Vector3(0, 0, 1),
		"Reset restores neutral eye input"
	)
	_check(
		is_zero_approx(controls.lid_closure) and is_zero_approx(controls.wetness),
		"Reset restores reported closure and wetness"
	)


func _eye_contract() -> void:
	var profile: NPREyeGeometryProfile = FACE_DEFINITION.eye_geometry_profile
	_check(profile.validate().is_empty(), "Authored eye profile validates")
	_check(not NPREyeGeometryProfile.new().validate().is_empty(), "Empty eye profile rejected")
	var data := profile.load_landmarks()
	data.landmarks.erase("EyeR")
	_check(
		not NPREyeGeometryProfile.validate_landmarks(data).is_empty(), "Missing eye side rejected"
	)
	data = profile.load_landmarks()
	data.landmarks.EyeL.center[0] = NAN
	_check(
		not NPREyeGeometryProfile.validate_landmarks(data).is_empty(),
		"Nonfinite eye center rejected"
	)
	var invalid := profile.duplicate() as NPREyeGeometryProfile
	invalid.gaze_gain.x = NAN
	_check(not invalid.validate_optics().is_empty(), "Nonfinite gaze gain rejected")
	invalid = profile.duplicate() as NPREyeGeometryProfile
	invalid.aperture_size.y = 0.0
	_check(not invalid.validate_optics().is_empty(), "Zero shading aperture rejected")
	invalid = profile.duplicate() as NPREyeGeometryProfile
	invalid.ior = 0.9
	_check(not invalid.validate_optics().is_empty(), "Unsupported tear IOR rejected")
	var lids := FACE_DEFINITION.face_motion_profile.load_lid_data()
	_check(
		NPREyeGeometryProfile.validate_lid_profiles(lids).is_empty(),
		"Authored shader lid sampling validates"
	)
	lids.profiles.L[20].upper[0] += 0.001
	_check(
		not NPREyeGeometryProfile.validate_lid_profiles(lids).is_empty(),
		"Nonuniform lid sampling rejected"
	)
	lids = FACE_DEFINITION.face_motion_profile.load_lid_data()
	lids.profiles.R.pop_back()
	_check(
		not NPREyeGeometryProfile.validate_lid_profiles(lids).is_empty(),
		"Wrong shader lid column count rejected"
	)
	invalid = profile.duplicate() as NPREyeGeometryProfile
	invalid.landmarks_path = "res://.temp/missing_eye_landmarks.json"
	_check(not invalid.validate().is_empty(), "Missing configured landmarks rejected")
	var scene := profile.model_scene.instantiate()
	scene.get_node("EyeL_Pupil").name = "UnknownPupil"
	_check(
		not NPREyeGeometryProfile.validate_scene(scene).is_empty(),
		"Wrong eye node binding rejected"
	)
	scene.free()
	scene = profile.model_scene.instantiate()
	scene.position.x = 1
	_check(
		not NPREyeGeometryProfile.validate_scene(scene).is_empty(),
		"Nonidentity asset root rejected"
	)
	scene.free()
	scene = profile.model_scene.instantiate()
	scene.get_node("EyeL_Iris").material_override = ShaderMaterial.new()
	_check(
		not NPREyeGeometryProfile.validate_scene(scene).is_empty(),
		"Missing source color material rejected"
	)
	scene.free()
	var definition := FACE_DEFINITION.duplicate() as NPRCharacterDefinition
	definition.eye_geometry_profile = invalid
	_check(not definition.validate().is_empty(), "Character propagates eye profile errors")
	definition.eye_geometry_profile = null
	_check(definition.validate().is_empty(), "Base rendering permits no diagnostic eye profile")


func _alternate_eye() -> void:
	var source: NPREyeGeometryProfile = FACE_DEFINITION.eye_geometry_profile
	var profile := source.duplicate() as NPREyeGeometryProfile
	profile.gaze_gain = Vector2(0.006, 0.004)
	profile.layer_depths = Vector4(0.002, 0.0015, 0.0009, 0.0003)
	profile.aperture_size = Vector2(0.04, 0.02)
	profile.aperture_slope = 0.12
	profile.closure_meeting = 0.6
	profile.shell_offset = 0.0005
	profile.ior = 1.4
	profile.thickness = 0.002
	var data := source.load_landmarks()
	data.landmarks.EyeL.center[0] += 0.003
	data.landmarks.EyeL.center[1] += 0.002
	var path := _output.path_join("alternate_eye_landmarks.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	profile.landmarks_path = ProjectSettings.localize_path(path.replace("\\", "/"))
	var model := source.model_scene.instantiate()
	var pupil := model.get_node("EyeL_Pupil") as MeshInstance3D
	pupil.position.x += 0.001
	var expected_position := pupil.position
	profile.model_scene = PackedScene.new()
	_check(profile.model_scene.pack(model) == OK, "Alternate ocular scene can be packed")
	model.free()
	var definition := FACE_DEFINITION.duplicate() as NPRCharacterDefinition
	definition.eye_geometry_profile = profile
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate ocular asset initializes production character")
	if not actor.initialized:
		actor.free()
		return
	var driver := DRIVER.new()
	driver.automatic = false
	actor.add_child(driver)
	driver.setup(actor)
	var pose_connections: int = driver.pose_applied.get_connections().size()
	var expression_connections: int = driver.expression_evaluated.get_connections().size()
	var frame_connections := RenderingServer.frame_pre_draw.get_connections().size()
	var layers := FACE_RIG_TEST.new()
	actor.add_child(layers)
	layers.setup(actor, driver)
	_check(
		driver.source_space(1).is_equal_approx(
			actor.global_transform.affine_inverse() * actor.meshes[1].global_transform
		),
		"Public source space matches initialized face transform"
	)
	var actual := layers.eye_layer.get_node("EyeL/EyeL_Pupil") as MeshInstance3D
	_check(
		actual.position.is_equal_approx(expected_position), "Selected eye scene reaches live pupil"
	)
	var rows: Array = definition.face_motion_profile.load_lid_data().profiles.L
	var center: Array = data.landmarks.EyeL.center
	var material := actual.material_override as ShaderMaterial
	var bounds: Vector2 = material.get_shader_parameter("eye_bounds")
	var curve: PackedVector4Array = material.get_shader_parameter("eye_profile")
	_check(
		is_equal_approx(bounds.x, rows[0].upper[0] - center[0]), "Authored center drives eye bounds"
	)
	_check(
		is_equal_approx(curve[0].x, rows[0].upper[1] - center[1]),
		"Authored center drives lid curve"
	)
	_check(source.load_landmarks() != data, "Alternate landmarks leave sample unchanged")
	for side in ["EyeL", "EyeR"]:
		for part in ["Sclera", "Iris", "Pupil", "TearFilm"]:
			var surface := (
				layers.eye_layer.get_node(side + "/" + side + "_" + part) as MeshInstance3D
			)
			var shader := surface.material_override as ShaderMaterial
			var depth_index := ["Sclera", "Iris", "Pupil", "TearFilm"].find(part)
			_check(
				is_equal_approx(
					shader.get_shader_parameter("layer_depth"), profile.layer_depths[depth_index]
				),
				side + part + " uses configured depth"
			)
			_check(
				is_equal_approx(
					shader.get_shader_parameter("closure_meeting"), profile.closure_meeting
				),
				side + part + " uses configured closure"
			)
			if part == "TearFilm":
				_check(
					is_equal_approx(shader.get_shader_parameter("ior"), profile.ior),
					side + " uses configured tear IOR"
				)
				_check(
					is_equal_approx(shader.get_shader_parameter("thickness"), profile.thickness),
					side + " uses configured tear thickness"
				)
			if part not in ["Iris", "Pupil"]:
				continue
			var base_position := surface.position
			var focus := Vector2(0.4, -0.3) if side == "EyeL" else Vector2(-0.2, 0.5)
			layers.set_eye_focus(Vector2.ZERO, 0 if side == "EyeL" else 1)
			base_position = surface.position
			layers.set_eye_focus(focus, 0 if side == "EyeL" else 1)
			var offset := focus * profile.gaze_gain
			_check(
				surface.position.is_equal_approx(base_position + Vector3(offset.x, offset.y, 0)),
				side + part + " CPU gaze uses profile"
			)
			_check(
				(shader.get_shader_parameter("focus_offset") as Vector2).is_equal_approx(offset),
				side + part + " shader gaze matches CPU"
			)
	_check(source.gaze_gain != profile.gaze_gain, "Alternate optics leave sample unchanged")
	_standalone_presentation(actor, layers.eye_layer)
	var old_eyes := weakref(layers.symbol_eyes)
	var old_mouth := weakref(layers.symbol_mouth)
	_check(
		driver.pose_applied.get_connections().size() == pose_connections + 1,
		"Face rig owns one pose connection"
	)
	layers.free()
	# Check synchronous disconnection before unrelated deferred renderer initialization.
	var frame_connections_at_exit := RenderingServer.frame_pre_draw.get_connections().size()
	_check(
		frame_connections_at_exit == frame_connections,
		"Rig teardown disconnects global frame callback"
	)
	await process_frame
	print(
		"FACE_RIG_FRAME_CONNECTIONS before=",
		frame_connections,
		" exit=",
		frame_connections_at_exit,
		" next_frame=",
		RenderingServer.frame_pre_draw.get_connections().size()
	)
	_check(
		old_eyes.get_ref() == null and old_mouth.get_ref() == null,
		"Rig teardown frees symbol surfaces attached outside rig"
	)
	_check(
		(
			driver.pose_applied.get_connections().size() == pose_connections
			and driver.expression_evaluated.get_connections().size() == expression_connections
		),
		"Rig teardown disconnects performance signals"
	)
	var rebuilt := FACE_RIG_TEST.new()
	actor.add_child(rebuilt)
	rebuilt.setup(actor, driver)
	rebuilt.presentation.request_eye_geometry(true)
	driver._apply_face()
	_check(
		rebuilt.eye_layer.visible and rebuilt.symbol_eyes.name == "SymbolEyeCanvas",
		"Fresh rig recreates clean representation on surviving actor"
	)
	_check(
		driver.pose_applied.get_connections().size() == pose_connections + 1,
		"Recreated rig has no duplicate pose connection"
	)
	actor.free()


func _standalone_presentation(actor: NPRCharacter, layer: Node3D) -> void:
	var original_lids := Node3D.new()
	actor.add_child(original_lids)
	var eyes := MeshInstance3D.new()
	var mouth := MeshInstance3D.new()
	for surface in [eyes, mouth]:
		surface.mesh = actor.meshes[1].mesh
		surface.material_override = actor.materials[1]
		actor.add_child(surface)
	var controls := CONTROLS.new()
	var no_motion := func(_left: Vector3, _right: Vector3) -> void: pass
	controls.bind(
		layer, layer, actor.materials[1], actor.definition.eye_geometry_profile, no_motion
	)
	var presentation := PRESENTATION.new()
	var expected_pose := Transform3D(Basis.IDENTITY, Vector3(0.1, 0.2, 0.3))
	var head_pose := func() -> Transform3D: return expected_pose
	var skin: Array[MeshInstance3D] = [eyes, mouth]
	presentation.bind(actor, layer, original_lids, eyes, mouth, skin, controls, head_pose)
	presentation.request_eye_geometry(true)
	presentation.apply_expression_frame({"eye_symbol": 0, "mouth_symbol": 0})
	_check(
		layer.visible and original_lids.visible and not eyes.visible and not mouth.visible,
		"Runtime presentation selects diagnostic representation"
	)
	_check(
		(
			layer.transform.is_equal_approx(expected_pose)
			and original_lids.transform.is_equal_approx(expected_pose)
		),
		"Runtime presentation uses supplied head deformation"
	)
	presentation.apply_expression_frame({"eye_symbol": 1, "mouth_symbol": 2})
	_check(
		not layer.visible and not original_lids.visible and eyes.visible and mouth.visible,
		"Runtime presentation selects both symbol surfaces"
	)
	_check(
		(
			actor.outlines[1].get_shader_parameter("u_npr_symbolic_eyes") == true
			and actor.materials[1].next_pass.get_shader_parameter("u_npr_symbolic_eyes") == true
		),
		"Runtime presentation synchronizes outline and face pass"
	)
	eyes.visible = false
	presentation.apply_expression_frame({"eye_symbol": 1, "mouth_symbol": 2})
	_check(not eyes.visible, "Unchanged expression preserves diagnostic visibility override")
	presentation.invalidate_expression_frame()
	presentation.apply_expression_frame({"eye_symbol": 1, "mouth_symbol": 2})
	_check(eyes.visible, "Explicit invalidation restores current symbol owner")
	var face: MeshInstance3D = actor.meshes[1]
	var blink := face.find_blend_shape_by_name("blink.L")
	_check(blink >= 0, "Presentation fixture has authored blink shape")
	if blink >= 0:
		face.set_blend_shape_value(blink, 0.7)
		presentation.sync_pose()
		_check(
			(
				is_equal_approx(eyes.get_blend_shape_value(blink), 0.7)
				and is_equal_approx(mouth.get_blend_shape_value(blink), 0.7)
			),
			"Visible symbol surfaces follow source blend shapes"
		)
		_check(
			is_equal_approx(controls.lid_closure, 0.7),
			"Presentation forwards evaluated blink closure"
		)
	var direction := Vector3(0.2, 0.4, 0.8)
	face.set_instance_shader_parameter("u_custom_main_light_dir", direction)
	presentation.sync_light()
	_check(
		(
			eyes.get_instance_shader_parameter("u_custom_main_light_dir") == direction
			and mouth.get_instance_shader_parameter("u_custom_main_light_dir") == direction
		),
		"Runtime presentation shares source face light"
	)
