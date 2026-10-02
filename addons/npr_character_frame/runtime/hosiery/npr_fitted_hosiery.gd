extends Node3D
## One-shot fitted layer; caller owns scheduling and lifetime with the source Body.

const SURFACE_SHADER := preload(
	"res://addons/npr_character_frame/shaders/body/hosiery_fitted_shell.gdshader"
)

var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var _source: MeshInstance3D


func setup(source: MeshInstance3D, profile: NPRHosieryProfile) -> void:
	assert(
		is_inside_tree() and _source == null, "Fitted hosiery requires a fresh attached instance"
	)
	assert(profile != null, "Fitted hosiery requires an authored profile")
	_source = source
	visible = false
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "FittedHosiery"
	add_child(mesh_instance)
	material = ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	# Body is an alpha-pipeline NPR material; textile must composite after it.
	material.render_priority = 10
	profile.apply_material(material)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sync_body()


func sync_body() -> void:
	if not is_instance_valid(mesh_instance):
		return
	# Equipment can rebuild the private Body mesh and skin palette.
	mesh_instance.mesh = _source.mesh
	mesh_instance.global_transform = _source.global_transform
	mesh_instance.custom_aabb = _source.custom_aabb
	mesh_instance.extra_cull_margin = _source.extra_cull_margin + 0.02
	var binding := _source.get_skin_reference()
	mesh_instance.skin = binding.get_skin() if binding != null else _source.skin
	var skeleton := _source.get_node_or_null(_source.skeleton)
	if skeleton != null:
		mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	for index in _source.mesh.get_blend_shape_count():
		mesh_instance.set_blend_shape_value(index, _source.get_blend_shape_value(index))


func set_surface_state(opacity: float, height: float, stitch_strength: float) -> void:
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("u_npr_hosiery_height", height)
	material.set_shader_parameter("u_npr_stitch_strength", stitch_strength)
