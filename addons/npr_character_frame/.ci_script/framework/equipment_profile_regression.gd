extends SceneTree
## Reject malformed equipment and exercise alternate assets in both production paths.

const DEFINITION = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/character_definition.tres"
)
const EQUIPMENT = preload("res://addons/npr_character_frame/runtime/equipment/npr_equipment.gd")

var _checks: Array[Dictionary] = []
var _output: String


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	_contract()
	_alternate()
	var failed := _checks.filter(func(row: Dictionary): return not row["pass"])
	FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"checks": _checks}, "  ")
	)
	print("EQUIPMENT_PROFILE_CHECKS=", _checks.size(), " FAILURES=", failed.size())
	if failed.is_empty():
		print("REGRESSION_OK")
	quit(0 if failed.is_empty() else 1)


func _contract() -> void:
	var source: NPREquipmentProfile = DEFINITION.equipment_profile
	_check(source.validate().is_empty(), "Sample equipment profile validates")
	_check(not NPREquipmentProfile.new().validate().is_empty(), "Empty equipment profile rejected")
	for field in ["positions", "normals", "swatches", "indices"]:
		var data := source.load_geometry()
		data.head.erase(field)
		_check(not source.validate_geometry(data).is_empty(), "Missing " + field + " rejected")
	var data := source.load_geometry()
	data.head.normals.pop_back()
	_check(not source.validate_geometry(data).is_empty(), "Mismatched vertex attributes rejected")
	data = source.load_geometry()
	data.head.positions[0][0] = NAN
	_check(not source.validate_geometry(data).is_empty(), "Nonfinite equipment position rejected")
	data = source.load_geometry()
	data.head.swatches[0] = "missing"
	_check(not source.validate_geometry(data).is_empty(), "Unknown equipment swatch rejected")
	for value in [-1, 0.5, 999999]:
		data = source.load_geometry()
		data.head.indices[0] = value
		_check(
			not source.validate_geometry(data).is_empty(),
			"Invalid equipment index rejected: " + str(value)
		)
	var invalid := source.duplicate(true) as NPREquipmentProfile
	invalid.slot_labels = PackedStringArray(["one"])
	_check(not invalid.validate().is_empty(), "Wrong label count rejected")
	invalid = source.duplicate(true) as NPREquipmentProfile
	invalid.material_slots.head = PackedStringArray(["missing"])
	_check(not invalid.validate().is_empty(), "Unbound material scene nodes rejected")
	invalid = source.duplicate(true) as NPREquipmentProfile
	invalid.attachment_bones[0] = "missing"
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.equipment_profile = invalid
	_check(not definition.validate().is_empty(), "Character rejects nonexistent equipment bone")
	definition.equipment_profile = null
	_check(definition.validate().is_empty(), "Base rendering permits no equipment profile")


func _alternate() -> void:
	var source: NPREquipmentProfile = DEFINITION.equipment_profile
	var profile := source.duplicate(true) as NPREquipmentProfile
	profile.slot_labels[0] = "Alternate accessory"
	profile.attachment_bones[0] = "hips"
	profile.swatch_uvs.violet = Vector2(0.25, 0.75)
	var data := source.load_geometry()
	data.head.positions[0][0] += 0.123
	data.head.swatches[0] = "violet"
	var path := _output.path_join("alternate_equipment.json")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(data))
	profile.geometry_path = ProjectSettings.localize_path(path.replace("\\", "/"))
	var instance := source.material_scene.instantiate()
	var first := instance.get_node(NodePath(source.material_slots.head[0])) as MeshInstance3D
	first.name = "AlternateEquipmentMesh"
	var extra := first.duplicate() as MeshInstance3D
	extra.name = "ExtraEquipmentMesh"
	var material := first.get_active_material(0).duplicate() as StandardMaterial3D
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	material.albedo_texture = ImageTexture.create_from_image(image)
	extra.material_override = material
	instance.add_child(extra)
	extra.owner = instance
	var group: PackedStringArray = profile.material_slots.head
	group[0] = str(first.name)
	group.append(str(extra.name))
	profile.material_slots.head = group
	profile.material_scene = PackedScene.new()
	_check(profile.material_scene.pack(instance) == OK, "Alternate equipment scene packs")
	instance.free()
	_check(profile.validate().is_empty(), "Alternate equipment resources validate")
	var definition := DEFINITION.duplicate() as NPRCharacterDefinition
	definition.equipment_profile = profile
	var actor := NPRCharacter.new()
	actor.definition = definition
	root.add_child(actor)
	_check(actor.initialized, "Alternate equipment definition initializes")
	if not actor.initialized:
		actor.free()
		return
	var body: MeshInstance3D = actor.meshes[0]
	var arrays := body.mesh.surface_get_arrays(0)
	var base_count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var custom := PackedFloat32Array()
	custom.resize(base_count * 4)
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var base := ArrayMesh.new()
	base.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	)
	body.mesh = base
	var equipment := EQUIPMENT.new()
	equipment.setup(actor)
	_check(equipment.slot_label(0) == "Alternate accessory", "UI label comes from selected profile")
	_check(
		equipment.authored_material_contract().objects == 20,
		"Object count comes from alternate scene"
	)
	_check(
		equipment.authored_material_contract().textures == 7,
		"Texture count comes from actual materials"
	)
	for texture_id: int in equipment._textures:
		var texture := instance_from_id(texture_id) as Texture2D
		print("EQUIPMENT_TEXTURE ", texture_id, " ", texture.resource_path)
	var extra_live := equipment._authored_root.get_node("ExtraEquipmentMesh") as MeshInstance3D
	var before_wetness: float = extra_live.get_active_material(0).roughness
	equipment.set_wetness(1.0)
	_check(
		is_equal_approx(extra_live.get_active_material(0).roughness, before_wetness * 0.55),
		"Authored material override receives live wetness"
	)
	var source_scene := profile.material_scene.instantiate()
	_check(
		is_equal_approx(
			source_scene.get_node("ExtraEquipmentMesh").get_active_material(0).roughness,
			before_wetness
		),
		"Wetness leaves packed source material unchanged"
	)
	source_scene.free()
	equipment.apply(actor, body, [true, false, false, false])
	var merged := body.mesh.surface_get_arrays(0)
	var position: Array = data.head.positions[0]
	var expected: Vector3 = (
		body.global_transform.affine_inverse()
		* actor.global_transform
		* Vector3(position[0], position[1], position[2])
	)
	_check(
		merged[Mesh.ARRAY_VERTEX][base_count].is_equal_approx(expected),
		"Selected geometry reaches merged Body"
	)
	_check(
		merged[Mesh.ARRAY_TEX_UV][base_count].is_equal_approx(Vector2(0.25, 0.25)),
		"Selected swatch reaches merged UV with V flip"
	)
	_check(equipment.attachments[0] == 1, "Named hips attachment resolves to performance index")
	equipment.set_authored_materials_enabled(true)
	equipment.apply(actor, body, [true, false, false, false])
	_check(
		body.mesh == base and equipment.attachments.is_empty(),
		"Authored mode remains exclusive with merged geometry"
	)
	_check(
		equipment.authored_material_contract().visible_objects == 4,
		"Alternate head grouping controls authored visibility"
	)
	var bound := false
	for binding: Dictionary in equipment._authored_bindings:
		if binding.mesh.name == "AlternateEquipmentMesh":
			bound = binding.bone == "hips"
	_check(bound, "Authored attachment uses selected bone name")
	_check(
		source.slot_labels[0] != profile.slot_labels[0] and source.material_slots.head.size() == 3,
		"Alternate profile leaves sample metadata unchanged"
	)
	actor.free()


func _check(passed: bool, label: String) -> void:
	_checks.append({"label": label, "pass": passed})
	if not passed:
		push_error("EQUIPMENT_PROFILE_FAILED: " + label)
