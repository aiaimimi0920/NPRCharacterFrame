extends "soft_tissue_regression.gd"
## Invalid authoring inputs and alternate data, followed by the production regression.

const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const SOFT_DATA = preload("res://addons/npr_character_frame/runtime/npr_soft_tissue_data.gd")
const DRIVER = preload("res://addons/npr_character_frame/runtime/animation/npr_performance.gd")


func _run() -> void:
	_contract()
	if _checks.any(func(item: Dictionary): return not item.pass):
		quit(1)
		return
	_alternate_asset()
	if _checks.any(func(item: Dictionary): return not item.pass):
		quit(1)
		return
	await super._run()


func _contract() -> void:
	var data := DEFINITION.load_soft_tissue_data()
	_check(SOFT_DATA.validate(data).is_empty(), "Sample pressure data satisfies schema 1")
	_check(not SOFT_DATA.validate({}).is_empty(), "Empty pressure data is rejected")
	_check(
		not SOFT_DATA.validate(data, 1).is_empty(), "Pressure topology must match the actual Body"
	)
	for invalid: Variant in [-1, 0.5, data.source_vertices, NAN, "vertex"]:
		var damaged := data.duplicate(true)
		damaged.deltas[0][0] = invalid
		_check(
			not SOFT_DATA.validate(damaged).is_empty(), "Invalid pressure index: " + str(invalid)
		)
	var damaged := data.duplicate(true)
	damaged.deltas[0][1] = INF
	_check(not SOFT_DATA.validate(damaged).is_empty(), "Infinite pressure displacement is rejected")
	damaged = data.duplicate(true)
	damaged.deltas.append(damaged.deltas[0].duplicate())
	_check(not SOFT_DATA.validate(damaged).is_empty(), "Duplicate pressure indices are rejected")
	damaged = data.duplicate(true)
	damaged.deltas[0].pop_back()
	_check(not SOFT_DATA.validate(damaged).is_empty(), "Truncated pressure row is rejected")
	damaged = data.duplicate(true)
	damaged.range = [0, 2]
	_check(not SOFT_DATA.validate(damaged).is_empty(), "Unsupported pressure range is rejected")
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.soft_tissue_data_path = "res://.temp/nonexistent_pressure.json"
	_check(not definition.validate().is_empty(), "Character rejects a missing corrective asset")
	definition.soft_tissue_data_path = ""
	_check(definition.validate().is_empty(), "Base rendering allows no pressure asset")


func _alternate_asset() -> void:
	var original := DEFINITION.load_soft_tissue_data()
	var alternate := original.duplicate(true)
	for row: Array in alternate.deltas:
		for axis in range(1, 4):
			row[axis] *= 0.5
	var path := _output.path_join("alternate_pressure.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(alternate))
	file.close()
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.soft_tissue_data_path = ProjectSettings.localize_path(path.replace("\\", "/"))
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate pressure asset passes character initialization")
	if not actor.initialized:
		actor.free()
		return
	var driver := DRIVER.new()
	driver.automatic = false
	actor.add_child(driver)
	driver.setup(actor)
	var body: MeshInstance3D = actor.meshes[0]
	var shape: Array = body.mesh.surface_get_blend_shape_arrays(0)[0]
	var row: Array = alternate.deltas[0]
	var space := actor.global_transform.affine_inverse() * body.global_transform
	var delta: Vector3 = space.basis * shape[Mesh.ARRAY_VERTEX][int(row[0])]
	_check(
		delta.is_equal_approx(Vector3(row[1], row[2], row[3])),
		"Character-selected asset changes actual corrective mesh deltas"
	)
	driver.set_soft_tissue_pressure(0.5)
	_check(
		is_equal_approx(body.get_blend_shape_value(0), 0.5),
		"Alternate corrective remains controlled by production pressure"
	)
	_check(
		DEFINITION.load_soft_tissue_data() == original, "Alternate input leaves sample unchanged"
	)
	actor.free()
