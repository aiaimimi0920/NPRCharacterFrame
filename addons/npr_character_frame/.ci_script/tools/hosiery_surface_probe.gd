extends SceneTree
## Read the pristine, normalized character before wardrobe deformation/repacking.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor := preload("res://addons/npr_character_frame/showcase/npr_character_preview.gd").new()
	root.add_child(actor)
	var source: MeshInstance3D = actor.meshes[0]
	var arrays := source.mesh.surface_get_arrays(0)
	var rows: Array = []
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][i]
		var uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][i]
		var rest: Vector3 = actor.global_transform.affine_inverse() * source.global_transform * p
		rows.append([p.x, p.y, p.z, n.x, n.y, n.z, uv.x, uv.y, rest.x, rest.y, rest.z])
	var args := OS.get_cmdline_user_args()
	var output := ProjectSettings.globalize_path("res://.temp/hosiery_surface_probe")
	if args.size() >= 2:
		output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var report := {
		"vertices": rows,
		"indices": Array(arrays[Mesh.ARRAY_INDEX]),
		"source_sha256":
		FileAccess.get_sha256(
			(
				"res://addons/npr_character_frame/samples/silver_wolf/"
				+ "assets/canonical/silver_wolf/body/mesh.scn"
			)
		),
	}
	var file := FileAccess.open(output.path_join("body_surface.json"), FileAccess.WRITE)
	if file == null:
		actor.free()
		push_error("Cannot write Body surface probe")
		quit(1)
		return
	file.store_string(JSON.stringify(report))
	file.close()
	actor.free()
	print("REGRESSION_OK")
	quit()
