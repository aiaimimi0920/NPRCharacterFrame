shader_type spatial;
render_mode unshaded, cull_back;
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
uniform ivec3 geometry_mask = ivec3(255, 0, 0);
varying vec2 visibility_uv;
varying vec3 visibility_position_ws;

void vertex() {
	visibility_uv = vec2(UV.x, 1.0 - UV.y);
	visibility_position_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);
	if (!npr_part_visible(COLOR, geometry_mask.x, geometry_mask.y != 0, geometry_mask.z != 0)) {
		POSITION = vec4(-99.0, -99.0, -99.0, 1.0);
	}
}

void fragment() {
	vec4 surface_fx = npr_surface_effects(visibility_uv);
	if (!npr_visibility_keep(FRAGCOORD.xy)) {
		discard;
	}
	if (npr_dissolve_signed_distance(visibility_uv, visibility_position_ws, surface_fx.a) < 0.0) {
		discard;
	}
}
