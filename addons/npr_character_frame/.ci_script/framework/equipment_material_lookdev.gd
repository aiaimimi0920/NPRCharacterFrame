extends SceneTree
## MAT-06: authored equipment lookdev captures under a fixed light-yaw matrix.

const SCENE = preload("res://addons/npr_character_frame/showcase/wardrobe.tscn")
const LIGHT_YAWS := [-85.0, 0.0, 85.0, 160.0]
var _wardrobe: Control
var _output := ""
var _checks: Array[Dictionary] = []


func _initialize() -> void:
	_output = OS.get_cmdline_user_args()[1]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_output)
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("unused_scheme.json")
	root.add_child(_wardrobe)
	_wardrobe.performance.automatic = false
	_wardrobe.performance.set_process(false)
	_wardrobe.performance.apply_pose(0.0)
	await _frames(10)
	_check(_wardrobe.preview.initialized, "Production wardrobe initializes")
	_wardrobe.state.equipment = [true, true, true, true]
	_wardrobe.state.hosiery_style = 2
	_wardrobe.state.stocking_transparency = 0.5
	_wardrobe._apply_state()
	_check(
		_wardrobe.equipment.authored_material_contract().loaded,
		"Authored equipment material bridge is loaded"
	)
	_check(
		_wardrobe.equipment.authored_material_contract().objects == 19,
		"Authored equipment object count is bound"
	)
	_wardrobe.state.authored_materials_enabled = true
	_wardrobe._apply_state()
	_check(
		(
			_wardrobe.equipment.authored_material_contract().enabled
			and _wardrobe.equipment.attachments.is_empty()
		),
		"Authored material mode is visible and mutually exclusive with merged attachments"
	)
	await _capture("equipment_authored_on")
	_wardrobe.state.authored_materials_enabled = false
	_wardrobe._apply_state()
	_check(
		(
			not _wardrobe.equipment.authored_material_contract().enabled
			and not _wardrobe.equipment.attachments.is_empty()
		),
		"Neutral mode restores the merged equipment path"
	)
	await _capture("equipment_authored_off")
	_wardrobe.state.authored_materials_enabled = true
	for slot in 4:
		_wardrobe.state.equipment = [false, false, false, false]
		_wardrobe.state.equipment[slot] = true
		_wardrobe._apply_state()
		_check(
			(
				_wardrobe.equipment.authored_material_contract().enabled
				and _wardrobe.equipment.attachments.is_empty()
				and _wardrobe.equipment.authored_material_contract().visible_objects > 0
				and (
					_wardrobe.equipment.authored_material_contract().visible_objects
					== [3, 4, 7, 5][slot]
				)
			),
			"Authored equipment slot %d uses the exclusive visible path" % slot
		)
		await _capture("equipment_authored_slot_%d" % slot)
	_wardrobe.state.equipment = [true, true, true, true]
	for view in ["full", "half", "face"]:
		_wardrobe.set_view(view)
		_wardrobe.state.authored_materials_enabled = true
		_wardrobe._apply_state()
		await _capture("equipment_%s_authored_on" % view)
		_wardrobe.state.authored_materials_enabled = false
		_wardrobe._apply_state()
		await _capture("equipment_%s_authored_off" % view)
	_wardrobe.state.authored_materials_enabled = true
	_wardrobe._apply_state()
	await _surface_responses()
	_wardrobe.set_view("full")
	for yaw in LIGHT_YAWS:
		_wardrobe.preview.light_yaw = yaw
		await _capture("equipment_light_%d" % int(yaw))
	_wardrobe.performance.action = "greeting"
	_wardrobe.performance.apply_pose(0.8)
	await _capture("equipment_pose_current")
	for binding: Dictionary in _wardrobe.equipment._authored_bindings:
		binding.mesh.transform = binding.rest
	await _capture("equipment_pose_stale")
	_wardrobe.equipment.sync_pose(_wardrobe.performance)
	await _capture("equipment_pose_restored")
	await _saved_options()
	var report := {
		"schema": 1,
		"light_yaws": LIGHT_YAWS,
		"checks": _checks,
		"inputs":
		{
			"scene":
			FileAccess.get_sha256("res://addons/npr_character_frame/showcase/wardrobe.tscn"),
			"equipment":
			FileAccess.get_sha256(
				(
					"res://addons/npr_character_frame/"
					+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/equipment.json"
				)
			),
			"material_glb":
			FileAccess.get_sha256(
				(
					"res://addons/npr_character_frame/"
					+ "samples/silver_wolf/assets/runtime/equipment_materials_v1.glb"
				)
			),
			"material_manifest":
			(
				FileAccess
				. get_sha256(
					(
						"res://addons/npr_character_frame/"
						+ "samples/silver_wolf/assets/authoring/silver_wolf/wardrobe/material_authored_v1.json"
					)
				)
			),
			"equipment_script":
			FileAccess.get_sha256(
				"res://addons/npr_character_frame/runtime/equipment/npr_equipment.gd"
			),
		},
	}
	(
		FileAccess
		. open(_output.path_join("equipment_material_lookdev.json"), FileAccess.WRITE)
		. store_string(JSON.stringify(report, "  "))
	)
	var failed := _checks.any(func(row: Dictionary): return not row.pass)
	_wardrobe.free()
	print("EQUIPMENT_MATERIAL_LOOKDEV_CHECKS=", _checks.size(), " FAILURES=", int(failed))
	print("REGRESSION_FAILED" if failed else "REGRESSION_OK")
	quit(1 if failed else 0)


func _saved_options() -> void:
	_wardrobe.select_section(7)
	var options := {
		"HairDynamicEnabled": "hair_dynamic_enabled",
		"HairCollisionEnabled": "hair_collision_enabled",
		"AuthoredMaterialsEnabled": "authored_materials_enabled"
	}
	for name: String in options:
		var button := _wardrobe._content.find_child(name, true, false) as CheckButton
		_check(button != null, "Saved visual toggle exists: " + name)
		if button != null:
			button.button_pressed = false
			button.button_pressed = true
			_check(_wardrobe.state.get(options[name]), "UI signal updates state: " + name)
	_wardrobe.save_scheme()
	var saved: Dictionary = _wardrobe.state.to_data()
	_wardrobe.free()
	await process_frame
	_wardrobe = SCENE.instantiate()
	_wardrobe.save_path = _output.path_join("unused_scheme.json")
	root.add_child(_wardrobe)
	_wardrobe.performance.automatic = false
	_wardrobe.performance.set_process(false)
	_wardrobe.performance.apply_pose(0.0)
	_check(_wardrobe.state.to_data() == saved, "Schema 5 recreates saved visual options")
	_check(
		(
			_wardrobe.performance.hair_dynamic_enabled
			and _wardrobe.performance.hair_collision_enabled
			and _wardrobe.equipment.authored_materials_enabled
		),
		"Recreated saved options reach runtime"
	)
	_wardrobe.reset_scheme()
	_check(
		(
			not _wardrobe.performance.hair_dynamic_enabled
			and not _wardrobe.performance.hair_collision_enabled
			and not _wardrobe.equipment.authored_materials_enabled
		),
		"Reset disables saved visual options"
	)


func _surface_responses() -> void:
	_wardrobe.set_view("half")
	_wardrobe.preview.light_yaw = -45.0
	await _capture("material_reference")
	for surface in ["dark", "silver", "violet"]:
		var meshes: Array[MeshInstance3D] = []
		for binding: Dictionary in _wardrobe.equipment._authored_bindings:
			var mesh: MeshInstance3D = binding.mesh
			var material := mesh.get_active_material(0) as StandardMaterial3D
			if material.resource_name == "Authored_" + surface:
				meshes.append(mesh)
				_check(material.roughness_texture != null, surface + " imports roughness map")
				_check(
					is_equal_approx(material.metallic, 0.72 if surface == "silver" else 0.0),
					surface + " imports metallic value"
				)
		_check(not meshes.is_empty(), "Visible material family: " + surface)
		for white in [false, true]:
			var mask := StandardMaterial3D.new()
			mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mask.albedo_color = Color.WHITE if white else Color.BLACK
			for mesh in meshes:
				mesh.material_override = mask
			await _capture("material_%s_mask_%s" % [surface, str(white)])
		for mesh in meshes:
			mesh.material_override = null
			var flat := mesh.get_active_material(0).duplicate() as StandardMaterial3D
			flat.metallic = 0.0
			flat.metallic_specular = 0.0
			flat.roughness = 1.0
			flat.roughness_texture = null
			flat.clearcoat_enabled = false
			mesh.material_override = flat
		await _capture("material_" + surface + "_flat")
		for mesh in meshes:
			mesh.material_override = null
	await _capture("material_restored")


func _capture(label: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join(label + ".png"))
	_wardrobe.viewport.get_texture().get_image().save_png(_output.path_join(label + "_stage.png"))


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks.append({"label": label, "pass": condition})
	if not condition:
		push_error("EQUIPMENT_LOOKDEV_FAILED: " + label)
