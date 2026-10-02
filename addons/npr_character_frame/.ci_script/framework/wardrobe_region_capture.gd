extends RefCounted
## Test-only ownership colors on the actual production fragment/vertex paths.
## Red: face/hair. Green: authored garment dye. Blue: active hosiery domain.

const BODY_CALL := (
	"npr_diagnostic_color(0, material_slot, v_world_normal.xyz, new_uv_1, "
	+ "albedo.rgb, 1.0, 0.0, 0)"
)
const BODY_REGIONS := (
	"vec3(0.0, float(dot(texture(u_npr_garment_mask, new_uv_1).rgb, vec3(1.0)) > 0.0), "
	+ "float(hosiery_domain > 0.0))"
)
const MODE_SOURCE := "if (u_npr_diagnostic_mode == 6) { return base; }"
const MODE_REGIONS := (
	"if (u_npr_diagnostic_mode == 6) { " + "return role == 0 ? vec3(0.0) : vec3(1.0, 0.0, 0.0); }"
)

var _expanded: Dictionary = {}
var _shaders: Dictionary = {}


func capture(tree: SceneTree, wardrobe: Control, path: String) -> Dictionary:
	var before: Image = wardrobe.viewport.get_texture().get_image()
	var camera: Transform3D = wardrobe.camera.global_transform
	var processing: bool = wardrobe.performance.is_processing()
	wardrobe.performance.set_process(false)
	var saved: Array[Dictionary] = []
	var materials: Array = wardrobe.preview.materials.duplicate()
	materials.append_array(wardrobe.preview.outlines)
	var seen: Dictionary = {}
	for first in materials:
		var material := first as ShaderMaterial
		while material != null:
			if not seen.has(material):
				seen[material] = true
				material.get_property_list()
				saved.append(
					{
						"material": material,
						"shader": material.shader,
						"mode": material.get_shader_parameter("u_npr_diagnostic_mode")
					}
				)
				material.shader = _region_shader(material.shader)
				material.set_shader_parameter("u_npr_diagnostic_mode", 6)
			material = material.next_pass as ShaderMaterial
	# The studio floor remains a depth occluder, but cannot masquerade as a region.
	var floors: Array[Dictionary] = []
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	for node in wardrobe.viewport.find_children("*", "MeshInstance3D", true, false):
		if not wardrobe.preview.is_ancestor_of(node):
			floors.append({"mesh": node, "material": node.material_override})
			node.material_override = black
	await _frames(tree)
	var regions: Image = wardrobe.viewport.get_texture().get_image()
	var save_error := regions.save_png(path)
	for item in saved:
		item.material.shader = item.shader
		item.material.set_shader_parameter("u_npr_diagnostic_mode", item.mode)
	for item in floors:
		item.mesh.material_override = item.material
	await _frames(tree)
	var restored: Image = wardrobe.viewport.get_texture().get_image()
	wardrobe.performance.set_process(processing)
	return {
		"schema": 1,
		"file": path.get_file(),
		"sha256": FileAccess.get_sha256(path),
		"size": [regions.get_width(), regions.get_height()],
		"saved": save_error == OK,
		"exact_restore": before.get_data() == restored.get_data(),
		"camera_unchanged": camera == wardrobe.camera.global_transform,
		"materials": saved.size(),
		"dye_source": wardrobe.character_definition.hosiery_profile.garment_mask.resource_path,
		"dye_source_sha256":
		FileAccess.get_sha256(
			wardrobe.character_definition.hosiery_profile.garment_mask.resource_path
		),
	}


func _region_shader(source: Shader) -> Shader:
	if _shaders.has(source):
		return _shaders[source]
	var code := _expand(source.code, source.resource_path.get_base_dir())
	if code.contains("uniform sampler2D u_npr_garment_mask") and code.count(BODY_CALL) != 1:
		push_error("Wardrobe region oracle requires exactly one production Body diagnostic call")
		return source
	code = code.replace(MODE_SOURCE, MODE_REGIONS)
	code = code.replace(BODY_CALL, BODY_REGIONS)
	var shader := Shader.new()
	shader.code = code
	_shaders[source] = shader
	return shader


func _expand(code: String, directory: String) -> String:
	var expression := RegEx.new()
	expression.compile('#include\\s+"([^"\\n]+)"')
	var found := expression.search(code)
	while found != null:
		var path := found.get_string(1)
		if not path.begins_with("res://"):
			path = directory.path_join(path)
		if not _expanded.has(path):
			_expanded[path] = _expand(FileAccess.get_file_as_string(path), path.get_base_dir())
		code = code.substr(0, found.get_start()) + _expanded[path] + code.substr(found.get_end())
		found = expression.search(code)
	return code


func _frames(tree: SceneTree) -> void:
	for index in 4:
		await tree.process_frame
	await RenderingServer.frame_post_draw
