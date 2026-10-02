extends Node
## Optional camera-matched normal/material-role buffer. Disabled until requested.

const ENCODE = preload(
	"res://addons/npr_character_frame/shaders/common/npr_auxiliary_encode.gdshader"
)
const GEOMETRY = preload("res://addons/npr_character_frame/runtime/npr_geometry_state.gd")
const CAMERA_KEYS := [
	"projection",
	"keep_aspect",
	"fov",
	"size",
	"near",
	"far",
	"frustum_offset",
	"h_offset",
	"v_offset"
]
const VISIBILITY_PARAMETERS := [
	"u_npr_surface_effects_enabled",
	"u_npr_surface_effects",
	"u_npr_dissolve_noise",
	"u_npr_dissolve_edge_width",
	"u_npr_dissolve_edge_color",
	"u_npr_dissolve_world_space",
	"u_npr_dissolve_world_scale",
	"u_npr_dissolve_world_offset",
	"u_npr_dissolve_enabled",
	"u_npr_dissolve_amount",
	"u_npr_visibility_alpha",
	"u_npr_visibility_alpha_cutoff",
	"u_npr_visibility_dither_enabled"
]

var enabled := false
## Budget controller changes scale, never the consumer's enabled preference.
var resolution_scale := 1.0
var viewport: SubViewport
var camera: Camera3D
var sources: Array[MeshInstance3D] = []
var proxies: Array[MeshInstance3D] = []
var encoders: Array[ShaderMaterial] = []
var geometry: Array[NPRGeometryState] = []
var _camera_state: Array = []


func setup(meshes: Array[MeshInstance3D], materials: Array[ShaderMaterial]) -> void:
	assert(meshes.size() == 3 and materials.size() == 3, "Expected body, face and hair")
	sources = meshes
	viewport = SubViewport.new()
	viewport.name = "CharacterAuxiliary"
	viewport.size = Vector2i(16, 16)
	viewport.own_world_3d = true
	viewport.use_hdr_2d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.TRANSPARENT
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera = Camera3D.new()
	camera.environment = environment
	viewport.add_child(camera)
	for index in range(sources.size()):
		var encoder := ShaderMaterial.new()
		encoder.shader = ENCODE
		encoder.set_shader_parameter("u_npr_aux_role", index)
		if index != 1:
			var region_parameter := "u_texture_light_map" if index == 0 else "u_texture_ilm_map"
			var region_map: Variant = materials[index].get_shader_parameter(region_parameter)
			if region_map != null:
				encoder.set_shader_parameter("u_npr_aux_regions_enabled", true)
				encoder.set_shader_parameter("u_npr_aux_region_map", region_map)
		_copy_visibility(materials[index], encoder)
		encoders.append(encoder)
		var proxy := MeshInstance3D.new()
		proxy.mesh = sources[index].mesh
		proxy.material_override = encoder
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		viewport.add_child(proxy)
		proxies.append(proxy)
		geometry.append(GEOMETRY.attach(sources[index], index))
	RenderingServer.frame_pre_draw.connect(synchronize)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func get_texture() -> Texture2D:
	return viewport.get_texture() if is_instance_valid(viewport) else null


func set_dissolve(amount: float) -> void:
	var resolved := clampf(amount, 0.0, 1.0)
	for encoder in encoders:
		encoder.set_shader_parameter("u_npr_dissolve_enabled", resolved > 0.0)
		encoder.set_shader_parameter("u_npr_dissolve_amount", resolved)


func set_visibility(alpha: float, dither_enabled: bool) -> void:
	var resolved := clampf(alpha, 0.0, 1.0)
	for encoder in encoders:
		encoder.set_shader_parameter("u_npr_visibility_alpha", resolved)
		encoder.set_shader_parameter("u_npr_visibility_dither_enabled", dither_enabled)


func synchronize() -> void:
	if not enabled or not is_instance_valid(viewport):
		return
	var source_camera := get_viewport().get_camera_3d()
	if source_camera == null:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var dimensions := Vector2i(source_camera.get_viewport().get_visible_rect().size)
	dimensions = Vector2i((Vector2(dimensions) * clampf(resolution_scale, 0.25, 1.0)).ceil())
	dimensions = Vector2i(maxi(dimensions.x, 2), maxi(dimensions.y, 2))
	var state: Array = [source_camera.global_transform, dimensions, source_camera.cull_mask]
	for key in CAMERA_KEYS:
		state.append(source_camera.get(key))
	if state != _camera_state:
		_camera_state = state
		viewport.size = dimensions
		camera.global_transform = source_camera.global_transform
		camera.force_update_transform()
		for key in CAMERA_KEYS:
			camera.set(key, source_camera.get(key))
	for index in range(sources.size()):
		geometry[index].refresh()
		geometry[index].apply_to(proxies[index])
		proxies[index].visible = (
			sources[index].is_visible_in_tree()
			and (sources[index].layers & source_camera.cull_mask) != 0
		)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


static func _copy_visibility(source: ShaderMaterial, target: ShaderMaterial) -> void:
	for parameter in VISIBILITY_PARAMETERS:
		var value: Variant = source.get_shader_parameter(parameter)
		if value != null:
			target.set_shader_parameter(parameter, value)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(synchronize):
		RenderingServer.frame_pre_draw.disconnect(synchronize)
