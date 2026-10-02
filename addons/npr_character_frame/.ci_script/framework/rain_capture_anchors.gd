extends RefCounted
## Sample-only camera targets sampled from the actual deformed Body surface.

const DATA := (
	"res://addons/npr_character_frame/.ci_script/framework/fixtures/"
	+ "silver_wolf_rain_anchors.json"
)


static func sample_actor_position(actor: NPRCharacter, marker: int) -> Vector3:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	assert(data.schema == 1 and data.anchors.has(str(marker)), "Unknown rain capture anchor")
	var anchor: Dictionary = data.anchors[str(marker)]
	var source: MeshInstance3D = actor.meshes[0]
	var geometry := source.get_node("NPRGeometryState") as NPRGeometryState
	var samples := geometry.sample_surface_vertices(0, PackedInt32Array(anchor.surface_triangle))
	assert(samples.size() == 3, "Rain capture anchor must match the sample Body")
	var space := actor.global_transform.affine_inverse() * source.global_transform
	var a := space * samples[0]
	var b := space * samples[1]
	var c := space * samples[2]
	var bary := Vector3(anchor.barycentric[0], anchor.barycentric[1], anchor.barycentric[2])
	var normal := (b - a).cross(c - a).normalized() * float(anchor.normal_sign)
	return a * bary.x + b * bary.y + c * bary.z + normal * float(anchor.surface_offset)
