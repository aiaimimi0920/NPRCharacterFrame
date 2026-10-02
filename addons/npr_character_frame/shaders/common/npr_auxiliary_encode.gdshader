shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, shadows_disabled;

#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_math.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"

uniform int u_npr_aux_role : hint_range(0, 2) = 0;
uniform bool u_npr_aux_regions_enabled = false;
uniform sampler2D u_npr_aux_region_map : filter_linear_mipmap, repeat_enable;
uniform ivec3 geometry_mask = ivec3(255, 0, 0);

varying vec2 aux_uv;
varying vec3 aux_normal_ws;
varying vec3 aux_position_ws;


vec2 npr_oct_encode(vec3 normal) {
	vec3 value = normal / max(abs(normal.x) + abs(normal.y) + abs(normal.z), 0.0001);
	if (value.z < 0.0) {
		value.xy = (1.0 - abs(value.yx)) * sign(value.xy);
	}
	return value.xy;
}


void vertex() {
	aux_uv = vec2(UV.x, 1.0 - UV.y);
	aux_normal_ws = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	aux_position_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);
	if (!npr_part_visible(COLOR, geometry_mask.x, geometry_mask.y != 0, geometry_mask.z != 0)) {
		POSITION = vec4(-99.0, -99.0, -99.0, 1.0);
	}
}


void fragment() {
	vec4 surface_fx = npr_surface_effects(aux_uv);
	if (!npr_visibility_keep(FRAGCOORD.xy)) {
		discard;
	}
	if (npr_dissolve_signed_distance(aux_uv, aux_position_ws, surface_fx.a) < 0.0) {
		discard;
	}
	float slot = u_npr_aux_regions_enabled
		? npr_material_slot(texture(u_npr_aux_region_map, aux_uv).a) : 0.0;
	vec2 encoded_normal = npr_oct_encode(normalize(aux_normal_ws)) * 0.5 + 0.5;
	// RG: octahedral world normal. B: centered packed (role * 8 + material slot).
	ALBEDO = vec3(encoded_normal, (float(u_npr_aux_role * 8) + slot + 0.5) / 24.0);
	ALPHA = 1.0;
}
