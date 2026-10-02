extends "face_motion_profile_regression.gd"
## Reject malformed authoring data and prove character-selected input reaches the rig.

const PERFORMANCE = preload("res://addons/npr_character_frame/runtime/npr_performance_data.gd")
const DRIVER = preload("res://addons/npr_character_frame/runtime/animation/npr_performance.gd")


func _run() -> void:
	_performance_contract()
	_test_alternate_asset()
	await super._run()


func _performance_contract() -> void:
	var data := FACE_DEFINITION.load_performance_data()
	_check(PERFORMANCE.validate(data).is_empty(), "Sample performance follows schema 1")
	var broken := data.duplicate(true)
	broken.bones.reverse()
	_check(not PERFORMANCE.validate(broken).is_empty(), "Wrong semantic bone order is rejected")
	broken = data.duplicate(true)
	broken.actions.idle.frames.resize(1)
	_check(not PERFORMANCE.validate(broken).is_empty(), "Single-frame interpolation is rejected")
	broken = data.duplicate(true)
	broken.actions.idle.frames[0][0][0] = NAN
	_check(not PERFORMANCE.validate(broken).is_empty(), "Nonfinite transform is rejected")
	broken = data.duplicate(true)
	broken.weights[0][0] = [[16, 1.0]]
	_check(not PERFORMANCE.validate(broken).is_empty(), "Out-of-range skin bone is rejected")
	broken.weights[0][0] = [[1.5, 1.0]]
	_check(not PERFORMANCE.validate(broken).is_empty(), "Fractional skin bone is rejected")
	broken.weights[0][0] = [[1, 0.4]]
	_check(not PERFORMANCE.validate(broken).is_empty(), "Unnormalized skin weights are rejected")
	broken = data.duplicate(true)
	broken.shapes.aa[0][0] = data.weights[1].size()
	_check(not PERFORMANCE.validate(broken).is_empty(), "Face deltas cannot exceed face topology")
	broken = data.duplicate(true)
	broken.shapes.erase("oh")
	_check(not PERFORMANCE.validate(broken).is_empty(), "Missing speech shape is rejected")
	_check(
		not PERFORMANCE.validate(data, PackedInt32Array([1, 1, 1])).is_empty(),
		"Actual source mesh counts must match all authored skin arrays"
	)
	var definition := FACE_DEFINITION.duplicate() as NPRCharacterDefinition
	definition.performance_data_path = "res://.temp/missing_performance.json"
	_check(not definition.validate().is_empty(), "Missing configured performance file is rejected")
	definition.performance_data_path = ""
	_check(not definition.validate().is_empty(), "Configured equipment requires performance bones")
	definition.equipment_profile = null
	_check(definition.validate().is_empty(), "Base rendering permits no performance configuration")


func _test_alternate_asset() -> void:
	var data := FACE_DEFINITION.load_performance_data()
	for frame: Array in data.actions.idle.frames:
		frame[0][3] = 0.125
	var path := _output.path_join("alternate_performance.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var definition := FACE_DEFINITION.duplicate() as NPRCharacterDefinition
	definition.performance_data_path = ProjectSettings.localize_path(path.replace("\\", "/"))
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate authored asset passes actual character initialization")
	var driver := DRIVER.new()
	driver.automatic = false
	actor.add_child(driver)
	driver.setup(actor)
	driver.apply_pose(0.0)
	_check(
		is_equal_approx(driver.bone_deformation("root").origin.x, 0.125),
		"Character-selected JSON changes the evaluated production bone palette"
	)
	_check(
		FACE_DEFINITION.load_performance_data().bones.size() == 16,
		"Appending dynamic bones never modifies authored input"
	)
	_check(
		FACE_DEFINITION.load_performance_data().actions.idle.frames[0][0][3] == 0.0,
		"Alternate action leaves sample data unchanged"
	)
	actor.free()
