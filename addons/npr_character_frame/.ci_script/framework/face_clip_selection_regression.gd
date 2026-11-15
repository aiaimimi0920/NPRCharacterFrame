extends SceneTree
const ROOT := "res://addons/npr_character_frame/"
const OUTPUT := "res://.temp/face_clip_selection"


func _initialize():
	call_deferred("run")


func run():
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var camera = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 0, 1)
	camera.current = true
	camera.size = 2
	camera.near = .05
	camera.far = 10
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	root.add_child(environment)
	var mesh = ArrayMesh.new()
	var a = []
	a.resize(Mesh.ARRAY_MAX)
	var v = PackedVector3Array()
	var c = PackedColorArray()
	var idx = PackedInt32Array()
	for layer in range(2):
		var z = -float(layer) * .000002
		var k = v.size()
		v.append_array(
			PackedVector3Array(
				[Vector3(-.8, -.8, z), Vector3(.8, -.8, z), Vector3(.8, .8, z), Vector3(-.8, .8, z)]
			)
		)
		for i in range(4):
			c.append(Color.RED if layer == 0 else Color.GREEN)
		idx.append_array(PackedInt32Array([k, k + 2, k + 1, k, k + 3, k + 2]))
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_COLOR] = c
	a[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var node = MeshInstance3D.new()
	node.mesh = mesh
	root.add_child(node)
	var cases = {
		"default": "POSITION=render_condition?position_cs:C_POSITION_CLIPPED;",
		"old_float": "POSITION=mix(C_POSITION_CLIPPED,position_cs,float(render_condition));"
	}
	var errors = []
	for name in [
		"face/face_base.gdshader",
		"face/face_eye_stencil.gdshader",
		"face/sdf360/face_lighting_block_0.gdshaderinc"
	]:
		var found = ""
		for line in FileAccess.get_file_as_string(ROOT + "shaders/" + name).split("\n"):
			if line.contains("POSITION = mix(C_POSITION_CLIPPED, position_cs,"):
				found = line.strip_edges()
		if not found.contains("bvec4(render_condition)"):
			errors.append(name + ": exact selector missing")
		cases[name.get_file()] = found
	var results = {}
	for projection in [Camera3D.PROJECTION_ORTHOGONAL, Camera3D.PROJECTION_PERSPECTIVE]:
		camera.projection = projection
		for name in cases:
			var shader = Shader.new()
			shader.code = (
				"shader_type spatial;render_mode unshaded,cull_disabled;"
				+ "uniform bool show_mesh=true;"
				+ "const vec4 C_POSITION_CLIPPED=vec4(-99.0,-99.0,-99.0,1.0);"
				+ "void vertex(){bool render_condition=show_mesh&&(COLOR.r+COLOR.g>0.5);"
				+ "vec4 position_cs=PROJECTION_MATRIX*"
				+ "vec4((MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz,1.0);"
				+ cases[name]
				+ "}void fragment(){ALBEDO=COLOR.rgb;}"
			)
			var material = ShaderMaterial.new()
			material.shader = shader
			node.material_override = material
			for visible_mesh in [true, false]:
				material.set_shader_parameter("show_mesh", visible_mesh)
				for frame in range(8):
					await process_frame
				await RenderingServer.frame_post_draw
				var image = root.get_texture().get_image()
				var color = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
				var key = "%s-%s-%s" % [projection, name, visible_mesh]
				results[key] = [color.r, color.g, color.b]
				image.save_png(OUTPUT + "/" + key + ".png")
				# Old behavior is diagnostic only; some GPU compilers optimize it safely.
				if name != "old_float":
					var expected = Color.RED if visible_mesh else Color.BLACK
					if (
						Vector3(color.r, color.g, color.b).distance_to(
							Vector3(expected.r, expected.g, expected.b)
						)
						> .05
					):
						errors.append(key + ": wrong layer or hidden geometry")
	var report = {
		"errors": errors, "samples": results, "asset_free": true, "layer_separation_m": .000002
	}
	var output = FileAccess.open(OUTPUT + "/result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	print("FACE_CLIP_SELECTION_REGRESSION ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
