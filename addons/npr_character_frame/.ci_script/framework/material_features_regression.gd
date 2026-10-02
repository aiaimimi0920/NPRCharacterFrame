extends SceneTree
## Silver Wolf NPR 1.1 visual acceptance using non-canonical diagnostic maps.

const LAB = preload("res://addons/npr_character_frame/showcase/npr_lab.tscn")
const PREVIEW = preload("res://addons/npr_character_frame/showcase/npr_character_preview.gd")
const ACCEPTANCE_MATERIALS = preload(
	(
		"res://addons/npr_character_frame/"
		+ "samples/silver_wolf/profiles/silver_wolf_acceptance_materials.tres"
	)
)
const ACCEPTANCE_PROFILE = preload(
	"res://addons/npr_character_frame/samples/silver_wolf/profiles/silver_wolf_acceptance_profile.tres"
)
const MESH_PATHS := ["Body/模型", "Head/Face/脸部模型", "Head/Hair/头发模型"]

var _output := ""
var _lab: Control
var _actor: Node3D
var _viewport: SubViewport
var _failures := 0
var _captures := PackedStringArray()
var _auxiliary := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		_output = args[1]
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_output)
	_lab = LAB.instantiate()
	root.add_child(_lab)
	await process_frame
	await process_frame
	var original: Node = _lab.preview
	_lab.preview = null
	original.queue_free()
	await process_frame

	_actor = PREVIEW.new()
	_actor.name = "SilverWolfAcceptancePreview"
	_actor.definition.material_set = ACCEPTANCE_MATERIALS
	_actor.definition.material_profile = ACCEPTANCE_PROFILE
	_lab.turntable.add_child(_actor)
	_lab.preview = _actor
	await process_frame
	await process_frame
	await process_frame
	_check(_actor.initialized, "Acceptance actor initializes")
	if not _actor.initialized:
		for error in _actor.validation_errors:
			push_error(error)
		_finish()
		return
	_viewport = _lab.get_node("%Viewport") as SubViewport
	_check_source_bindings()
	_check_mesh_attributes()
	_disable_extended_features()

	_lab.set_view("full")
	await _capture("baseline_full")
	await _capture_stocking_and_matcap()
	await _capture_emission()
	await _capture_outline_controls()
	await _capture_expression()
	await _capture_hair()
	await _capture_dissolve_and_visibility()
	await _capture_auxiliary()
	_write_report()
	_finish()


func _check_source_bindings() -> void:
	var body := _actor.materials[0] as ShaderMaterial
	var face := _actor.materials[1] as ShaderMaterial
	var eye := face.next_pass as ShaderMaterial
	var hair := _actor.materials[2] as ShaderMaterial
	var eye_hair := hair.next_pass as ShaderMaterial
	_check(
		body.get_shader_parameter("u_npr_surface_effects") == ACCEPTANCE_MATERIALS.body_effects,
		"Body packed effects reached the duplicated source material"
	)
	_check(
		body.get_shader_parameter("u_npr_matcap_texture") == ACCEPTANCE_MATERIALS.matcap_texture,
		"MatCap reached the duplicated source material"
	)
	for material in [face, eye]:
		_check(
			(
				material.get_shader_parameter("u_npr_surface_effects")
				== ACCEPTANCE_MATERIALS.face_expression
			),
			"Face expression reached both face passes"
		)
	_check(
		(
			face.get_shader_parameter("u_distance_lut_distance_scale")
			== ACCEPTANCE_PROFILE.face_distance_lut_distance_scale
		),
		"Face distance LUT scale reached the duplicated source material"
	)
	_check(
		(
			face.get_shader_parameter("u_npr_outline_control")
			== ACCEPTANCE_MATERIALS.face_outline_control
		),
		"Face outline control reached the duplicated source material"
	)
	_check(
		(
			eye.get_shader_parameter("u_npr_outline_control")
			== ACCEPTANCE_MATERIALS.face_outline_control
		),
		"Face outline control reached the duplicated eye pass"
	)
	_check(
		(
			_actor.outlines[1].get_shader_parameter("u_npr_outline_control")
			== ACCEPTANCE_MATERIALS.face_outline_control
		),
		"Face outline control reached the face outline pass"
	)
	for material in [hair, eye_hair]:
		_check(
			(
				material.get_shader_parameter("u_npr_surface_effects")
				== ACCEPTANCE_MATERIALS.hair_effects
			),
			"Hair effects reached both hair passes"
		)
		_check(
			(
				material.get_shader_parameter("u_npr_hair_flow_map")
				== ACCEPTANCE_MATERIALS.hair_flow_map
			),
			"Hair flow reached both hair passes"
		)
	for material in [body, face, eye, hair, eye_hair]:
		_check(
			(
				material.get_shader_parameter("u_npr_dissolve_noise")
				== ACCEPTANCE_MATERIALS.dissolve_noise
			),
			"Dissolve noise reached every color/stencil pass"
		)


func _check_mesh_attributes() -> void:
	var rows: Array[Dictionary] = []
	for index in range(MESH_PATHS.size()):
		var mesh := _actor.meshes[index] as MeshInstance3D
		var format: int = mesh.mesh.surface_get_format(0)
		var tangent: bool = (format & Mesh.ARRAY_FORMAT_TANGENT) != 0
		var uv2: bool = (format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
		rows.append({"path": MESH_PATHS[index], "format": format, "tangent": tangent, "uv2": uv2})
		if index == 2:
			_check(tangent, "Silver Wolf hair provides Tangent for anisotropy")
	_auxiliary["mesh_attributes"] = rows


func _disable_extended_features() -> void:
	_actor.set_face_expression(Vector3.ZERO)
	_actor.set_stocking_strength(0.0)
	_actor.set_matcap_strength(0.0)
	_actor.set_hair_anisotropy(0.0)
	_actor.set_hair_side_fade(0.0)
	_actor.set_hair_silhouette(0.0)
	_actor.set_dissolve(0.0)
	_actor.set_visibility_alpha(1.0)
	_set_secondary_emission(false)


func _capture_stocking_and_matcap() -> void:
	_lab.set_view("half")
	_actor.set_stocking_strength(0.0)
	await _capture("stocking_off")
	_actor.set_stocking_strength(0.5)
	await _capture("stocking_half")
	_actor.set_stocking_strength(1.0)
	await _capture("stocking_full")
	_actor.set_stocking_strength(0.0)
	_actor.set_matcap_strength(0.0)
	await _capture("matcap_off")
	_actor.set_matcap_strength(1.0)
	await _capture("matcap_full")
	_actor.set_matcap_strength(0.0)


func _capture_emission() -> void:
	_lab.set_view("half")
	_set_secondary_emission(false)
	await _capture("secondary_emission_off")
	_set_secondary_emission(true)
	await _capture("secondary_emission_on")
	_set_secondary_emission(false)


func _capture_outline_controls() -> void:
	_lab.set_view("full")
	for outline in _actor.outlines:
		outline.set_shader_parameter("u_npr_outline_regions_enabled", false)
	await _capture("region_outline_off")
	_actor.outlines[0].set_shader_parameter("u_npr_outline_regions_enabled", true)
	_actor.outlines[2].set_shader_parameter("u_npr_outline_regions_enabled", true)
	await _capture("region_outline_on")
	_lab.set_view("face")
	_actor.set_lip_outline_enabled(false)
	await _capture("lip_outline_fix_off")
	_actor.set_lip_outline_enabled(true)
	await _capture("lip_outline_fix_on")


func _capture_expression() -> void:
	_lab.set_view("face")
	_actor.set_face_expression(Vector3.ZERO)
	await _capture("expression_off")
	_actor.set_face_expression(Vector3(1, 0, 0))
	await _capture("expression_shadow")
	_actor.set_face_expression(Vector3(0, 1, 0))
	await _capture("expression_highlight")
	_actor.set_face_expression(Vector3(0, 0, 1))
	await _capture("expression_blush")
	_actor.set_face_expression(Vector3(0.65, 0.55, 0.75))
	await _capture("expression_combined")
	_actor.set_face_expression(Vector3.ZERO)


func _capture_hair() -> void:
	_lab.set_view("face")
	_actor.light_yaw = -55.0
	_actor.set_hair_anisotropy(0.0)
	await _capture("hair_anisotropy_off")
	_actor.set_hair_anisotropy(1.0)
	await _capture("hair_anisotropy_left_light")
	_actor.light_yaw = 55.0
	await _capture("hair_anisotropy_right_light")
	_actor.set_hair_anisotropy(0.0)
	_actor.light_yaw = -45.0
	_lab.turntable.rotation_degrees.y = 65.0
	_actor.set_hair_side_fade(0.0)
	await _capture("hair_side_fade_off")
	_actor.set_hair_side_fade(0.85)
	await _capture("hair_side_fade_on")
	_actor.set_hair_side_fade(0.0)
	_lab.turntable.rotation_degrees.y = 0.0
	_actor.set_hair_silhouette(0.0)
	await _capture("hair_silhouette_off")
	_actor.set_hair_silhouette(0.9)
	await _capture("hair_silhouette_on")
	_actor.set_hair_silhouette(0.0)


func _capture_dissolve_and_visibility() -> void:
	_lab.set_view("full")
	for entry in [
		[0.0, "dissolve_000"],
		[0.25, "dissolve_025"],
		[0.5, "dissolve_050"],
		[0.75, "dissolve_075"],
		[0.9, "dissolve_090"]
	]:
		_actor.set_dissolve(entry[0])
		await _capture(entry[1])
	_actor.set_dissolve(0.0)
	_actor.set_visibility_alpha(1.0)
	await _capture("visibility_100")
	_actor.set_visibility_alpha(0.5)
	await _capture("visibility_050")
	_actor.set_visibility_alpha(1.0)


func _capture_auxiliary() -> void:
	_actor.set_auxiliary_buffer_enabled(true)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_actor.set_dissolve(0.0)
	await _save_auxiliary("auxiliary_dissolve_000")
	_actor.set_dissolve(0.5)
	await _save_auxiliary("auxiliary_dissolve_050")
	_actor.set_dissolve(0.0)
	_actor.set_auxiliary_buffer_enabled(false)


func _set_secondary_emission(enabled: bool) -> void:
	var strengths := (
		ACCEPTANCE_PROFILE.secondary_emission_strengths
		if enabled
		else PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	)
	for material in [_actor.materials[0], _actor.materials[2], _actor.materials[2].next_pass]:
		material.set_shader_parameter("u_npr_secondary_emission_strengths", strengths)
		material.set_shader_parameter("u_npr_emission_hue_enabled", enabled)


func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var error := image.save_png(_output.path_join(label + ".png"))
	_check(error == OK, "Save " + label)
	_captures.append(label)


func _save_auxiliary(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var texture: Texture2D = _actor.get_auxiliary_texture()
	_check(texture != null, "Auxiliary texture exists")
	if texture == null:
		return
	var image := texture.get_image()
	var error := image.save_png(_output.path_join(label + ".png"))
	_check(error == OK, "Save " + label)
	var coverage := 0
	var roles := PackedInt32Array([0, 0, 0])
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.01:
				continue
			coverage += 1
			var packed_id := clampi(int(floor(pixel.b * 24.0)), 0, 23)
			roles[packed_id / 8] += 1
	_auxiliary[label] = {
		"width": image.get_width(),
		"height": image.get_height(),
		"coverage": coverage,
		"roles": Array(roles),
	}
	_check(coverage > 0, label + " has coverage")
	_captures.append(label)


func _write_report() -> void:
	var report := {
		"schema_version": 1,
		"captures": Array(_captures),
		"auxiliary": _auxiliary,
		"failures": _failures,
	}
	var file := FileAccess.open(_output.path_join("material_features.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _finish() -> void:
	if is_instance_valid(_lab):
		_lab.queue_free()
	await process_frame
	print("REGRESSION_OK" if _failures == 0 else "REGRESSION_FAILED")
	quit(0 if _failures == 0 else 1)
