extends SceneTree
## Reuse production validators; report structural errors separately from visual advice.

const VALIDATOR = preload("res://addons/npr_character_frame/runtime/npr_model_validator.gd")
const SAMPLE := "res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"

var _definition: NPRCharacterDefinition
var _output := "res://.temp/model_check"
var _report := {
	"schema_version": 1,
	"case_id": "model.contract",
	"compliance_errors": [],
	"visual_suggestions": [],
	"measurements": {},
	"not_evaluated": ["visual appearance", "full-feature role data", "texture channel semantics"],
}


func _initialize() -> void:
	_run.call_deferred()


func _collect() -> void:
	var options := OS.get_cmdline_user_args()
	var definition_path := SAMPLE
	if options.size() % 2 != 0:
		_issue("arguments", "Arguments must be --definition/--output value pairs")
		return
	for index in range(0, options.size(), 2):
		match options[index]:
			"--definition":
				definition_path = options[index + 1]
			"--output":
				_output = options[index + 1]
			_:
				_issue("arguments", "Unknown argument: " + options[index])
	if not _report.compliance_errors.is_empty():
		return
	_report.definition = definition_path
	if not ResourceLoader.exists(definition_path):
		_issue("definition", "Definition resource does not exist")
		return
	_definition = load(definition_path) as NPRCharacterDefinition
	if _definition == null:
		_issue("definition", "Expected NPRCharacterDefinition")
		return
	for error in _definition.validate():
		_issue("definition", error)
	if not _report.compliance_errors.is_empty():
		return
	var model := _definition.model_scene.instantiate()
	if not model is Node3D:
		_issue("geometry", "Model root must be Node3D")
		model.free()
		return
	var materials := _definition.material_set
	var outline_sources := PackedInt32Array()
	if materials != null:
		outline_sources = PackedInt32Array(
			[
				materials.body_outline_smooth_normal_source,
				materials.face_outline_smooth_normal_source,
				materials.hair_outline_smooth_normal_source,
			]
		)
	var errors := VALIDATOR.validate(
		model,
		_definition.mesh_paths(),
		_definition.use_source_materials,
		materials.sdf_on_uv2 if materials != null else false,
		outline_sources,
		_definition.material_profile.hair_anisotropy_enabled
	)
	for error in errors:
		_issue("geometry", error)
	if _definition.hosiery_profile != null and errors.is_empty():
		var body := model.get_node(_definition.body_path) as MeshInstance3D
		var vertices: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for error in _definition.hosiery_profile.validate_normal_correction(vertices):
			_issue("hosiery_normals", error)
	if _definition.face_motion_profile != null:
		var face := model.get_node_or_null(_definition.face_path) as MeshInstance3D
		if face != null and face.mesh != null and face.mesh.get_surface_count() == 1:
			var profile := _definition.face_motion_profile
			for error in NPRFaceMotionProfile.validate_lid_data(
				profile.load_lid_data(), face.mesh.surface_get_array_len(0)
			):
				_issue("face_motion", error)
	for path in _definition.mesh_paths():
		var node := model.get_node_or_null(path) as MeshInstance3D
		if node != null and node.mesh is ArrayMesh:
			_report.measurements[str(path)] = {
				"surfaces": node.mesh.get_surface_count(),
				"blend_shapes": node.mesh.get_blend_shape_count(),
			}
	if not _definition.performance_data_path.is_empty() and errors.is_empty():
		var counts := PackedInt32Array()
		for path in _definition.mesh_paths():
			var mesh := model.get_node(path) as MeshInstance3D
			counts.append(mesh.mesh.surface_get_array_len(0))
		for error in _definition.PERFORMANCE_DATA.validate(
			_definition.load_performance_data(), counts
		):
			_issue("performance", error)
	if not _definition.soft_tissue_data_path.is_empty() and errors.is_empty():
		var body := model.get_node(_definition.body_path) as MeshInstance3D
		for error in _definition.SOFT_TISSUE_DATA.validate(
			_definition.load_soft_tissue_data(), body.mesh.surface_get_array_len(0)
		):
			_issue("soft_tissue", error)
	if not _definition.hair_dynamics_data_path.is_empty() and errors.is_empty():
		var counts := PackedInt32Array()
		for path in _definition.mesh_paths():
			var mesh := model.get_node(path) as MeshInstance3D
			counts.append(mesh.mesh.surface_get_array_len(0))
		for error in _definition.HAIR_DYNAMICS_DATA.validate(
			_definition.load_hair_dynamics_data(), counts
		):
			_issue("hair_dynamics", error)
	model.free()


func _issue(category: String, message: String) -> void:
	(
		_report
		. compliance_errors
		. append(
			{
				"category": category,
				"message": message,
				"suggestion": "Correct the reported field or geometry against asset_contract.json.",
			}
		)
	)


func _run() -> void:
	_collect()
	_finish()


func _finish() -> void:
	_report.status = "pass" if _report.compliance_errors.is_empty() else "fail"
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	if error != OK:
		push_error("Cannot create model report directory")
		quit(2)
		return
	var file := FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write model report")
		quit(2)
		return
	file.store_string(JSON.stringify(_report, "  "))
	file.close()
	print("MODEL_CHECK_", str(_report.status).to_upper())
	quit(0 if _report.status == "pass" else 1)
