extends SceneTree
## Visual contract for NORMAL, TANGENT and UV2-octahedral outline directions.

const OUTLINE = preload(
	"res://addons/npr_character_frame/shaders/face/face_outline_pixels.gdshader"
)

var _output := ""
var _viewport: SubViewport
var _outline: ShaderMaterial
var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		_output = args[1]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_output)
	_viewport = SubViewport.new()
	_viewport.name = "SmoothNormalFixture"
	_viewport.size = Vector2i(640, 480)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.055, 0.085)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.82)
	environment.ambient_light_energy = 0.55
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var camera := Camera3D.new()
	camera.position = Vector3(3.1, 2.35, 4.2)
	camera.fov = 34.0
	camera.current = true
	_viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -34, 0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	_viewport.add_child(light)

	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline.set_shader_parameter("outline_width_pixels", 3.0)
	_outline.set_shader_parameter("outline_color", Color(0.75, 0.28, 0.95))
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.42, 0.58, 0.92)
	base.metallic = 0.15
	base.roughness = 0.62
	base.next_pass = _outline
	var instance := MeshInstance3D.new()
	instance.mesh = _make_hard_cube()
	instance.material_override = base
	_viewport.add_child(instance)

	await _capture(0, "outline_vertex_normal")
	await _capture(1, "outline_tangent_smooth")
	await _capture(2, "outline_uv2_oct_smooth")
	print("REGRESSION_OK" if _failures == 0 else "REGRESSION_FAILED")
	quit(0 if _failures == 0 else 1)


func _make_hard_cube() -> ArrayMesh:
	var faces := [
		[
			Vector3(1, 0, 0),
			[Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]
		],
		[
			Vector3(-1, 0, 0),
			[Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]
		],
		[
			Vector3(0, 1, 0),
			[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)]
		],
		[
			Vector3(0, -1, 0),
			[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)]
		],
		[
			Vector3(0, 0, 1),
			[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
		],
		[
			Vector3(0, 0, -1),
			[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)]
		],
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var normal: Vector3 = face[0]
		var corners: Array = face[1]
		for vertex_index in [0, 1, 2, 0, 2, 3]:
			var position: Vector3 = corners[vertex_index]
			var smooth := position.normalized()
			surface.set_normal(normal)
			surface.set_tangent(Plane(smooth.x, smooth.y, smooth.z, 1.0))
			surface.set_uv(Vector2.ZERO)
			surface.set_uv2(_oct_encode(smooth) * 0.5 + Vector2(0.5, 0.5))
			surface.set_color(Color.WHITE)
			surface.add_vertex(position)
	return surface.commit()


func _oct_encode(direction: Vector3) -> Vector2:
	var normal := direction / (absf(direction.x) + absf(direction.y) + absf(direction.z))
	var encoded := Vector2(normal.x, normal.y)
	if normal.z < 0.0:
		encoded = Vector2(1.0 - absf(encoded.y), 1.0 - absf(encoded.x)) * encoded.sign()
	return encoded


func _capture(source: int, label: String) -> void:
	_outline.set_shader_parameter("u_npr_outline_smooth_normal_source", source)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error := _viewport.get_texture().get_image().save_png(_output.path_join(label + ".png"))
	if error != OK:
		_failures += 1
		push_error("Could not save " + label)
