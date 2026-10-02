shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, shadows_disabled;
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"

uniform float depth_range = 16.0;
uniform vec2 projection_scale = vec2(1.0);
uniform ivec3 geometry_mask = ivec3(255, 0, 0);
varying float view_depth;
varying vec2 visibility_uv;
varying vec3 visibility_position_ws;

void vertex() {
	visibility_uv = vec2(UV.x, 1.0 - UV.y);
	visibility_position_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	POSITION = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);
	// Keep the logical camera aspect, including off-center frusta, when an odd
	// viewport dimension rounds up at half resolution. Depth itself is unchanged.
	POSITION.xy *= projection_scale;
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
	// Split across two half-float channels instead of losing near-contact precision
	// to one R16F depth. B is coverage; clear pixels are not a near-plane surface.
	float d = clamp(view_depth / depth_range, 0.0, 0.999999);
	ALBEDO = vec3(floor(d * 256.0) / 256.0, fract(d * 256.0), 1.0);
}
