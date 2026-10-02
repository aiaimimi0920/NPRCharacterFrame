extends SceneTree
## Run with tests/run_validation.ps1 using the project's custom Forward+ build.

const MESH_PATHS := ["Body/模型", "Head/Face/脸部模型", "Head/Hair/头发模型"]

var _output := ""
var _mode := "capture"
var _scene: Node3D
var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]
	if args.size() > 1:
		_output = args[1]
	_run.call_deferred()


func _run() -> void:
	_scene = (
		load("res://addons/npr_character_frame/samples/silver_wolf/scenes/silver_wolf.tscn")
		. instantiate()
	)
	root.add_child(_scene)
	await process_frame
	await process_frame
	_check_assembly()
	for path in ["Body/模型", "Head/Face/脸部模型", "Head/Hair/头发模型"]:
		var mesh := _scene.get_node(path) as MeshInstance3D
		var bounds := mesh.global_transform * mesh.get_aabb()
		var arrays := mesh.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var counts := {}
		for color in colors:
			var key := str(color)
			counts[key] = counts.get(key, 0) + 1
		print("MESH ", path, " bounds=", bounds, " transform=", mesh.global_transform)
		print("COLORS ", path, " count=", colors.size(), " distinct=", counts.size())
		if counts.size() < 10:
			print(counts)
		if _mode == "inspect":
			var samples := []
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for index in range(mini(positions.size(), 200)):
				var pos := positions[index]
				var uv := uvs[index]
				samples.append([pos.x, pos.y, pos.z, uv.x, uv.y])
			var file := FileAccess.open(
				_output.path_join(str(mesh.name) + ".json"), FileAccess.WRITE
			)
			file.store_string(JSON.stringify(samples))
	if _mode == "inspect":
		_finish()
		return
	DirAccess.make_dir_recursive_absolute(_output)
	await _capture_character()
	await _capture_shader_variants()
	await _check_component_scenes()
	var contracts = (
		load("res://addons/npr_character_frame/.ci_script/framework/shader_contracts.gd").new()
	)
	_failures += await contracts.run(self, _output)
	await _capture_outline_widths()
	await _compile_shaders()
	_finish()


func _capture_character() -> void:
	var camera := _scene.get_node("Body/Camera3D") as Camera3D
	await _capture("full")
	camera.position = Vector3(0, 9, 18)
	camera.look_at(Vector3(0, 9, 0))
	await _capture("front")
	await _capture_shadow_variants()
	_scene.set_shadows_enabled(false)
	await _capture("front_no_shadows")
	_scene.shadow_light.visible = false
	await _capture("front_no_light")
	_scene.shadow_light.visible = true
	var overlays: Array[Material] = []
	for path in MESH_PATHS:
		var mesh := _scene.get_node(path) as MeshInstance3D
		overlays.append(mesh.material_overlay)
		mesh.material_overlay = null
	await _capture("front_no_overlay")
	for index in range(MESH_PATHS.size()):
		_scene.get_node(MESH_PATHS[index]).material_overlay = overlays[index]
	_scene.set_shadows_enabled(true)
	camera.position = Vector3(14, 9, 14)
	camera.look_at(Vector3(0, 9, 0))
	await _capture("quarter")
	camera.position = Vector3(18, 9, 0)
	camera.look_at(Vector3(0, 9, 0))
	await _capture("side")
	camera.position = Vector3(0, 9, 18)
	camera.look_at(Vector3(0, 9, 0))
	_scene.set_shadows_enabled(false)
	var face := _scene.get_node("Head/Face/脸部模型") as MeshInstance3D
	var stencil := face.get_active_material(0).next_pass
	var outline := stencil.next_pass
	stencil.next_pass = null
	await _capture("front_no_outline")
	stencil.next_pass = outline


func _capture_shadow_variants() -> void:
	var extra := DirectionalLight3D.new()
	_scene.add_child(extra)
	await _capture("front_extra_light")
	extra.queue_free()
	await process_frame
	var blocker := MeshInstance3D.new()
	blocker.mesh = BoxMesh.new()
	blocker.scale = Vector3(3, 3, 3)
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_scene.add_child(blocker)
	blocker.global_position = Vector3(0, 9.5, 0) + _scene.shadow_light.global_basis.z * 6.0
	await _capture("front_blocker")
	blocker.queue_free()
	await process_frame


func _check_assembly() -> void:
	var body_material := _scene.get_node(MESH_PATHS[0]).get_active_material(0) as ShaderMaterial
	_check(
		(
			body_material.next_pass.get_shader_parameter("u_material_values_pack_lut")
			== body_material.get_shader_parameter("u_material_values_pack_lut")
		),
		"Body outline shares the packed material color table"
	)
	# Exact CSV -> imported mesh mappings independently recovered from vertex data.
	var import_bases := [
		Basis(Vector3(-100, 0, 0), Vector3(0, 0, -100), Vector3(0, 100, 0)),
		Basis(Vector3(-0.01, 0, 0), Vector3(0, 0.01, 0), Vector3(0, 0, 0.01)),
		Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)),
	]
	var expected := Basis(Vector3(0, -20, 0), Vector3(0, 0, 20), Vector3(20, 0, 0))
	var head := _scene.get_node("Head") as Node3D
	for index in range(MESH_PATHS.size()):
		var mesh := _scene.get_node(MESH_PATHS[index]) as MeshInstance3D
		var actual: Basis = mesh.global_basis * import_bases[index]
		if index > 0:
			# Capture axes are local to the head; its rigid pose is checked at the seam.
			actual = head.global_basis.inverse() * actual
		_check(actual.is_equal_approx(expected), "Shared capture axes: " + MESH_PATHS[index])
		var caster := mesh.get_node("ShadowCaster") as MeshInstance3D
		_check(caster.mesh == mesh.mesh, "Shadow mesh is shared")
		_check(caster.global_transform.is_equal_approx(mesh.global_transform), "Caster alignment")
		_check(mesh.skin == null, "Static capture model (no unsupported skin)")
	_check(_scene.get_node("Head/Face").global_position == head.global_position, "Face attachment")
	_check(_scene.get_node("Head/Hair").global_position == head.global_position, "Hair attachment")
	var seam: Dictionary = (
		load("res://addons/npr_character_frame/.ci_script/framework/neck_seam_contract.gd")
		. new()
		. measure(_scene)
	)
	_check(seam["pass"], "Actual exposed head/neck boundary continuity")
	print("NECK_SEAM ", JSON.stringify(seam))


func _capture_shader_variants() -> void:
	var parameters: Array[Dictionary] = []
	for path in MESH_PATHS:
		var material := _scene.get_node(path).get_active_material(0) as ShaderMaterial
		while material != null:
			for uniform in material.shader.get_shader_uniform_list():
				if uniform.name in ["u_dither_mask", "u_color_mode"]:
					(
						parameters
						. append(
							{
								"material": material,
								"name": uniform.name,
								"value": material.get_shader_parameter(uniform.name),
							}
						)
					)
			material = material.next_pass as ShaderMaterial
	for bits in [4, 16, 32, 48, 60, 1, 2, 3]:
		for entry in parameters:
			entry.material.set_shader_parameter(entry.name, bits)
		await _capture("front_dither_%d" % bits)
	for entry in parameters:
		entry.material.set_shader_parameter(entry.name, entry.value)
	await _capture_depth_probe(parameters)
	await _check_shared_light()


func _capture_depth_probe(parameters: Array[Dictionary]) -> void:
	# A late transparent plane behind the character observes the actual depth test,
	# unlike hint_depth_texture, which is copied before this stencil/alpha chain.
	var plane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(12, 24)
	plane.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = (
		"shader_type spatial; render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled;"
		+ "void fragment() { ALBEDO = vec3(1.0, 0.0, 0.0); ALPHA = 0.75; }"
	)
	material.render_priority = 126
	plane.material_override = material
	_scene.add_child(plane)
	plane.global_position = Vector3(0, 7, -4)
	await _capture("depth_probe")
	for bits in [4, 16, 32, 48, 60]:
		for entry in parameters:
			entry.material.set_shader_parameter(entry.name, bits)
		await _capture("depth_probe_%d" % bits)
	for entry in parameters:
		entry.material.set_shader_parameter(entry.name, entry.value)
	# Negative control: a deliberately broken real face shader must expose the plane.
	var face := _scene.get_node(MESH_PATHS[1]) as MeshInstance3D
	var original := face.get_active_material(0) as ShaderMaterial
	var mutant := original.duplicate() as ShaderMaterial
	mutant.shader = Shader.new()
	var source := original.shader.code
	var insertion := source.rfind("}")
	mutant.shader.code = source.insert(insertion, "\nDEPTH = 0.0;\n")
	face.set_surface_override_material(0, mutant)
	await _capture("depth_probe_mutant")
	face.set_surface_override_material(0, original)
	plane.queue_free()
	await process_frame


func _check_shared_light() -> void:
	var body := _scene.get_node(MESH_PATHS[0]) as MeshInstance3D
	var original: Vector4 = body.get_instance_shader_parameter("u_custom_main_light_dir")
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP]:
		var packed := Vector4(direction.x, direction.y, direction.z, 1.0)
		body.set_instance_shader_parameter("u_custom_main_light_dir", packed)
		await process_frame
		await process_frame
		for path in [MESH_PATHS[1], MESH_PATHS[2]]:
			var actual: Vector4 = _scene.get_node(path).get_instance_shader_parameter(
				"u_custom_main_light_dir"
			)
			_check(actual.is_equal_approx(packed), "Shared head light: " + path)
		_check(
			_scene.shadow_light.global_basis.z.is_equal_approx(direction), "CSM light follows body"
		)
		await _capture("light_" + str(direction))
	body.set_instance_shader_parameter("u_custom_main_light_dir", original)
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("REGRESSION_FAILED: " + label)


func _check_component_scenes() -> void:
	_scene.visible = false
	for part in ["body", "face", "hair"]:
		var path := (
			"res://addons/npr_character_frame/.ci_script/framework/fixtures/silver_wolf/%s.tscn"
			% part
		)
		if part == "body":
			path = "res://addons/npr_character_frame/samples/silver_wolf/scenes/body.tscn"
		var component := load(path).instantiate() as Node3D
		root.add_child(component)
		await process_frame
		await RenderingServer.frame_post_draw
		component.queue_free()
		await process_frame
		print("COMPONENT_OK ", part)


func _capture_outline_widths() -> void:
	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var outline := (
		(
			load(
				"res://addons/npr_character_frame/samples/silver_wolf/scenes/materials/face_outline.tres"
			)
			. duplicate()
		)
		as ShaderMaterial
	)
	outline.set_shader_parameter("outline_color", Color.RED)
	white.next_pass = outline
	sphere.material_override = white
	root.add_child(sphere)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position.z = 4
	await _capture("outline_near")
	camera.position.z = 8
	await _capture("outline_far")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3
	await _capture("outline_ortho")
	root.size = Vector2i(648, 900)
	await _capture("outline_portrait")
	root.size = Vector2i(1152, 648)
	sphere.queue_free()
	camera.queue_free()
	await process_frame


func _compile_shaders() -> void:
	# Preserve the capture grid order after moving the two legacy outline shaders.
	var paths: Array[String] = [
		"res://addons/npr_character_frame/shaders/body/body_outline.gdshader",
		"res://addons/npr_character_frame/shaders/hair/hair_outline.gdshader",
	]
	for path in _shader_paths("res://addons/npr_character_frame/shaders"):
		if path not in paths:
			paths.append(path)
	var grid := Node3D.new()
	root.add_child(grid)
	var camera := Camera3D.new()
	grid.add_child(camera)
	camera.current = true
	camera.position.z = 15
	for index in range(paths.size()):
		var mesh := MeshInstance3D.new()
		mesh.mesh = SphereMesh.new()
		var material := ShaderMaterial.new()
		material.shader = load(paths[index])
		mesh.material_override = material
		mesh.position = Vector3(float(index % 5 - 2) * 2, float(index / 5 - 1) * 2, 0)
		grid.add_child(mesh)
	await _capture("shader_compile")
	print("SHADERS_COMPILED ", paths.size())
	grid.queue_free()
	await process_frame


func _shader_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gdshader"):
			paths.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		paths.append_array(_shader_paths(directory.path_join(child)))
	return paths


func _capture(label: String) -> void:
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var frame_image := root.get_texture().get_image()
	var error := frame_image.save_png(_output.path_join(label + ".png"))
	if error != OK:
		push_error("Failed to save frame: " + label)
		quit(1)
	print("CAPTURE ", label)


func _finish() -> void:
	_scene.queue_free()
	await process_frame
	print("REGRESSION_OK" if _failures == 0 else "REGRESSION_FAILED")
	quit(0 if _failures == 0 else 1)
