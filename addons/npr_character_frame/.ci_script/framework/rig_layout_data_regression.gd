extends SceneTree
## Authored diagnostic endpoints, pose palettes and transient display restoration.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const DISPLAY = preload("res://addons/npr_character_frame/showcase/wardrobe_display.gd")
const DRIVER = preload("res://addons/npr_character_frame/runtime/animation/npr_performance.gd")
const RIG_DATA = preload("res://addons/npr_character_frame/runtime/npr_rig_layout_data.gd")
var _output: String
var _checks: Array[Dictionary] = []
var _geometry: Array[Dictionary] = []


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	await _sample_display()
	_test_layout_contract()
	_finish()


func _sample_display() -> void:
	root.size = Vector2i(1440, 900)
	var scene := SCENE.instantiate()
	scene.save_path = _output.path_join("unused_scheme.json")
	root.add_child(scene)
	scene.performance.automatic = false
	scene.performance.set_process(false)
	scene.state.blink = false
	scene.state.secondary = false
	scene.state.hair_dynamic_enabled = false
	scene.state.hair_collision_enabled = true
	scene._apply_state()
	for action in 4:
		scene.state.action = action
		scene._apply_state()
		for time in [0.0, 0.8]:
			scene.performance.apply_pose(time)
			var label := "%s_%s" % [scene.performance.action, str(time).replace(".", "_")]
			var geometry: Dictionary = scene.display.diagnostic_geometry()
			_geometry.append({"label": label, "geometry": geometry})
			var saved: Dictionary = scene.state.to_data()
			var render: Image
			for mode in ["render", "white", "skeleton", "render"]:
				scene.display.set_mode(mode)
				await _frames()
				var pixels: Image = scene.viewport.get_texture().get_image()
				if mode == "render" and render != null:
					_check(pixels.get_data() == render.get_data(), label + " exact render restore")
				else:
					pixels.save_png(_output.path_join(label + "_" + mode + ".png"))
					if mode == "render":
						render = pixels
			_check(scene.display.overridden_count() == 0, label + " releases all materials")
			_check(scene.state.to_data() == saved, label + " preserves saved state")
			_check(geometry.bones.size() == 16, label + " displays the standard palette")
			_check(geometry.chains.size() == 7, label + " displays authored dynamic chains")
			_check(geometry.colliders.size() == 3, label + " displays collision capsules")
	var targets := {"viewport": [root.size.x, root.size.y], "buttons": {}}
	for id in ["DisplayRender", "DisplayWhite", "DisplaySkeleton", "Save"]:
		var button: BaseButton = scene.find_child(id, true, false)
		var bounds := button.get_global_rect()
		targets.buttons[id] = [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
	FileAccess.open(_output.path_join("gui_targets.json"), FileAccess.WRITE).store_string(
		JSON.stringify(targets, "  ")
	)
	scene.free()


func _test_layout_contract() -> void:
	var original := DEFINITION.load_rig_layout_data()
	var source_text := FileAccess.get_file_as_string(DEFINITION.rig_layout_data_path)
	_check(RIG_DATA.validate(original).is_empty(), "Sample authored layout follows the standard")
	var broken := original.duplicate(true)
	broken.erase("schema")
	_reject(broken, "Missing schema")
	for schema in [true, 2, "1"]:
		broken = original.duplicate(true)
		broken.schema = schema
		_reject(broken, "Invalid schema " + str(schema))
	for bones in [null, [], original.bones.slice(0, 15)]:
		broken = original.duplicate(true)
		broken.bones = bones
		_reject(broken, "Incomplete standard bone array")
	broken = original.duplicate(true)
	broken.bones.reverse()
	_reject(broken, "Wrong canonical order")
	broken = original.duplicate(true)
	broken.bones[1] = 42
	_reject(broken, "Nondictionary bone")
	broken = original.duplicate(true)
	broken.bones[1].name = "root"
	_reject(broken, "Duplicate bone name")
	broken = original.duplicate(true)
	broken.bones[0].erase("parent")
	_reject(broken, "Missing root parent")
	broken = original.duplicate(true)
	broken.bones[0].parent = "hips"
	_reject(broken, "Root parent cycle")
	for parent in [null, false, "missing", "hips", "head"]:
		broken = original.duplicate(true)
		broken.bones[1].parent = parent
		_reject(broken, "Invalid parent " + str(parent))
	for endpoint in [null, [0, 1], [true, 0, 0], [NAN, 0, 0], [0, INF, 0], [1.0e100, 0, 0]]:
		for field in ["head", "tail"]:
			broken = original.duplicate(true)
			broken.bones[1][field] = endpoint
			_reject(broken, "Invalid " + field + " endpoint")
	broken = original.duplicate(true)
	broken.bones[1].tail = broken.bones[1].head.duplicate()
	_reject(broken, "Zero-length bone")
	var independent := DEFINITION.load_rig_layout_data()
	independent.bones[0].head[0] = 0.125
	_check(
		DEFINITION.load_rig_layout_data() == original, "Loading returns independent endpoint data"
	)
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.rig_layout_data_path = "res://.temp/missing_rig_layout.json"
	_check(not definition.validate().is_empty(), "Definition rejects a missing configured layout")
	definition.rig_layout_data_path = ""
	_check(definition.validate().is_empty(), "Base rendering allows no diagnostic layout")
	var directory := "res://.temp/framework/rig_layout_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join("alternate.json")
	var alternate := original.duplicate(true)
	for bone: Dictionary in alternate.bones:
		bone.head[0] += 0.125
		bone.tail[0] += 0.125
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(alternate))
	definition.rig_layout_data_path = path
	var loaded_alternate := definition.load_rig_layout_data()
	_check(definition.validate().is_empty(), "Alternate authored endpoint file validates")
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate layout passes actual character initialization")
	if actor.initialized:
		var driver := DRIVER.new()
		driver.automatic = false
		actor.add_child(driver)
		driver.setup(actor)
		var display := DISPLAY.new()
		actor.add_child(display)
		display.setup(actor, driver)
		var changed := false
		for action: String in DRIVER.ACTIONS:
			driver.action = action
			for time in [0.0, 0.8]:
				driver.apply_pose(time)
				var geometry: Dictionary = display.diagnostic_geometry()
				var matches := true
				var sample_matches := true
				for index in alternate.bones.size():
					var bone: Dictionary = alternate.bones[index]
					var deformation: Transform3D = driver.bone_deformation(bone.name)
					var actual: Dictionary = geometry.bones[index]
					matches = (
						matches
						and actual.name == bone.name
						and actual.parent == bone.parent
						and actual.head == _point(deformation, bone.head)
						and actual.tail == _point(deformation, bone.tail)
					)
					sample_matches = (
						sample_matches
						and actual.head == _point(deformation, original.bones[index].head)
					)
					changed = changed or deformation != Transform3D.IDENTITY
				_check(matches, "%s %s transforms all configured rest endpoints" % [action, time])
				_check(
					not sample_matches,
					"%s %s does not fall back to sample endpoints" % [action, time]
				)
			_check(changed, "Endpoint checks include nonidentity production animation")
			display.set_mode("skeleton")
			_check(
				display.overlay.mesh.get_surface_count() == 2,
				"Configured bones draw real overlay geometry"
			)
			display.set_mode("render")
			_check(
				display.overridden_count() == 0, "Alternate layout releases diagnostic materials"
			)
		var existing: Dictionary = display.diagnostic_geometry()
		var second := definition.load_rig_layout_data()
		second.bones[0].head[0] = -99.0
		_check(
			definition.load_rig_layout_data() == loaded_alternate,
			"Another load cannot modify the alternate asset"
		)
		_check(
			display.diagnostic_geometry() == existing,
			"Another load cannot mutate the initialized display"
		)
	actor.free()
	FileAccess.open(directory.path_join("invalid.json"), FileAccess.WRITE).store_string("[]")
	definition.rig_layout_data_path = directory.path_join("invalid.json")
	_check(not definition.validate().is_empty(), "Definition rejects a nonobject layout file")
	_check(
		FileAccess.get_file_as_string(DEFINITION.rig_layout_data_path) == source_text,
		"Sample source remains byte-identical"
	)
	FileAccess.open(_output.path_join("fixture_path.txt"), FileAccess.WRITE).store_string(directory)


func _reject(data: Dictionary, label: String) -> void:
	_check(not RIG_DATA.validate(data).is_empty(), label + " is rejected")


func _point(deformation: Transform3D, coordinates: Array) -> Array:
	var point := deformation * Vector3(coordinates[0], coordinates[1], coordinates[2])
	return [point.x, point.y, point.z]


func _frames() -> void:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw


func _check(passed: bool, label: String) -> void:
	_checks.append({"name": label, "pass": passed})
	if not passed:
		print("FAIL: ", label)


func _finish() -> void:
	FileAccess.open(_output.path_join("rig_layout.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks, "geometry": _geometry}, "  ")
	)
	var failures := _checks.filter(func(row: Dictionary): return not row["pass"])
	print("RIG_LAYOUT_CHECKS=", _checks.size(), " FAILURES=", failures.size())
	print("REGRESSION_OK" if failures.is_empty() else "REGRESSION_FAILED")
	quit(0 if failures.is_empty() else 1)
