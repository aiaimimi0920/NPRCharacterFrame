extends Node3D
## Engine CSM with geometry-matched opaque casters, not unpopulated capture uniforms.
## Body/hair receive material-aware shadows in light(); face keeps its SDF color pass.

const SHADOW_SHADER = preload("res://addons/npr_character_frame/shaders/character_shadow.gdshader")
const GEOMETRY = preload("res://addons/npr_character_frame/runtime/npr_geometry_state.gd")
const CASTER = preload("res://addons/npr_character_frame/shaders/common/npr_shadow_caster.gdshader")
const KEY_POOL = preload("res://addons/npr_character_frame/runtime/npr_key_light_pool.gd")
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
@export var mesh_paths: Array[NodePath] = []

@export_range(0.0, 1.0) var shadow_strength := 0.35

var shadow_light: DirectionalLight3D
var key_pool: Node3D
var _overlays: Array[ShaderMaterial] = []
var _npr_receivers: Array[MeshInstance3D] = []
var _head_meshes: Array[MeshInstance3D] = []
var _casters: Array[ShaderMaterial] = []
var _body: MeshInstance3D
var _shadow_requested := true
var _key_available := true
var _published_strength := -1.0
var _direction := Vector3.ZERO
var _shared_layer := -1
var _shared_settings: Dictionary = {}


func _enter_tree() -> void:
	if _shared_layer >= 0:
		# Reparenting is a lifecycle operation, not an animation tick. Restore even
		# when the member's process_mode is disabled, after its subtree has entered.
		_restore_shared_key.call_deferred()


func _ready() -> void:
	if mesh_paths.size() != 3:
		push_error("NPR shadow rig requires validated body, face and hair paths")
		set_process(false)
		return
	_body = get_node(mesh_paths[0]) as MeshInstance3D
	shadow_light = DirectionalLight3D.new()
	shadow_light.name = "EngineShadowLight"
	shadow_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	shadow_light.directional_shadow_max_distance = 80.0
	shadow_light.shadow_enabled = true
	shadow_light.shadow_bias = 0.1
	shadow_light.shadow_normal_bias = 2.0
	shadow_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(shadow_light)
	for path in mesh_paths:
		var source := get_node(path) as MeshInstance3D
		if path != mesh_paths[0]:
			_head_meshes.append(source)
		if path == mesh_paths[1]:
			var overlay := ShaderMaterial.new()
			overlay.shader = SHADOW_SHADER
			overlay.render_priority = 6
			overlay.set_shader_parameter("shadow_strength", shadow_strength)
			_copy_visibility(source.get_active_material(0) as ShaderMaterial, overlay)
			source.material_overlay = overlay
			_overlays.append(overlay)
		else:
			_npr_receivers.append(source)
			source.set_instance_shader_parameter("u_npr_shadow_strength", shadow_strength)
		# Only the opaque proxy casts; do not double-submit lit NPR color passes.
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# ALPHA-writing NPR materials are transparent and do not provide reliable
		# opaque shadow casters. Share the mesh, not a second imported model scene.
		var caster := MeshInstance3D.new()
		caster.name = "ShadowCaster"
		caster.mesh = source.mesh
		var material := ShaderMaterial.new()
		material.shader = CASTER
		_copy_visibility(source.get_active_material(0) as ShaderMaterial, material)
		_casters.append(material)
		caster.material_override = material
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		source.add_child(caster)
		GEOMETRY.attach(source, mesh_paths.find(path)).set_shadow_proxy(caster)
	_update_light()


func sync_surface_visibility(source_materials: Array[ShaderMaterial]) -> void:
	if source_materials.size() != _casters.size():
		return
	for index in range(_casters.size()):
		_copy_visibility(source_materials[index], _casters[index])
	if not _overlays.is_empty():
		_copy_visibility(source_materials[1], _overlays[0])


func set_dissolve(amount: float) -> void:
	var resolved := clampf(amount, 0.0, 1.0)
	for material in _casters + _overlays:
		material.set_shader_parameter("u_npr_dissolve_enabled", resolved > 0.0)
		material.set_shader_parameter("u_npr_dissolve_amount", resolved)


func set_visibility(alpha: float, dither_enabled: bool) -> void:
	var resolved := clampf(alpha, 0.0, 1.0)
	for material in _casters + _overlays:
		material.set_shader_parameter("u_npr_visibility_alpha", resolved)
		material.set_shader_parameter("u_npr_visibility_dither_enabled", dither_enabled)


static func _copy_visibility(source: ShaderMaterial, target: ShaderMaterial) -> void:
	if source == null:
		return
	for parameter in VISIBILITY_PARAMETERS:
		var value: Variant = source.get_shader_parameter(parameter)
		if value != null:
			target.set_shader_parameter(parameter, value)


func _process(_delta: float) -> void:
	_update_light()


func set_shadows_enabled(enabled: bool) -> void:
	_shadow_requested = enabled
	if is_instance_valid(key_pool):
		key_pool.request(self, _direction, enabled)
		key_pool.synchronize()
	elif is_instance_valid(shadow_light):
		shadow_light.shadow_enabled = enabled
	_publish_strength()


func share_key_light(layer: int) -> void:
	_update_light()
	_shared_layer = layer
	key_pool = KEY_POOL.attach(get_viewport())
	key_pool.register_member(self, shadow_light, layer, _direction, _shadow_requested)


func set_key_available(available: bool) -> void:
	_key_available = available
	_publish_strength()


func update_shared_layer(layer: int) -> void:
	if _shared_layer < 0:
		return
	_shared_layer = layer
	if is_instance_valid(key_pool):
		key_pool.update_member_layer(self, layer)


func _publish_strength() -> void:
	var value := shadow_strength if _shadow_requested and _key_available else 0.0
	if _published_strength == value:
		return
	_published_strength = value
	for receiver in _npr_receivers:
		receiver.set_instance_shader_parameter("u_npr_shadow_strength", value)
	for overlay in _overlays:
		overlay.set_shader_parameter("shadow_strength", value)


func _update_light() -> void:
	_restore_shared_key()
	# This scene uses body's local character light (not the monster/global fallback).
	# One resolved direction owns body lighting, face SDF, hair Ramp and engine CSM.
	# MeshInstance returns null for an unset instance override, not the shader default.
	var main_override: Variant = _body.get_instance_shader_parameter("u_main_light_position")
	var custom_override: Variant = _body.get_instance_shader_parameter("u_custom_main_light_dir")
	var main: Vector4 = main_override if main_override is Vector4 else Vector4(0, 0, 1, 0)
	var custom: Vector4 = custom_override if custom_override is Vector4 else Vector4.ZERO
	var toward_light := Vector3(main.x, main.y, main.z).lerp(
		Vector3(custom.x, custom.y, custom.z), custom.w
	)
	if toward_light.length_squared() < 0.00001:
		return
	toward_light = toward_light.normalized()
	if _direction != toward_light:
		_direction = toward_light
		var head_direction := Vector4(toward_light.x, toward_light.y, toward_light.z, 1.0)
		for mesh in _head_meshes:
			mesh.set_instance_shader_parameter("u_custom_main_light_dir", head_direction)
	if is_instance_valid(key_pool):
		key_pool.request(self, toward_light, _shadow_requested)
		return
	var up := Vector3.UP if absf(toward_light.y) < 0.99 else Vector3.RIGHT
	# NPR dot(N,L) uses a direction TOWARD the light; Godot lights emit along -Z.
	shadow_light.global_basis = Basis.looking_at(-toward_light, up)


func _restore_shared_key() -> void:
	if _shared_layer < 0 or is_instance_valid(key_pool) or not is_inside_tree():
		return
	# Re-entering does not call _ready again. Restore the last valid direction
	# even if today's shader direction is zero; layer zero is a valid empty mask.
	shadow_light = DirectionalLight3D.new()
	for key in _shared_settings:
		shadow_light.set(key, _shared_settings[key])
	key_pool = KEY_POOL.attach(get_viewport())
	key_pool.register_member(self, shadow_light, _shared_layer, _direction, _shadow_requested)


func _exit_tree() -> void:
	if is_instance_valid(key_pool):
		_shared_settings = key_pool.member_settings(self)
		key_pool.unregister_member(self)
		key_pool = null
		shadow_light = null
