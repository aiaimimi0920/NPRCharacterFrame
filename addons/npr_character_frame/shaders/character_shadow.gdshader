shader_type spatial;
#include "res://addons/npr_character_frame/shaders/common/npr_vertex.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_surface_features.gdshaderinc"
render_mode blend_mul, depth_draw_never, cull_back, ambient_light_disabled, specular_disabled, fog_disabled;

// Preserve the stylized eye-through-hair region. This pass never writes stencil or depth.
stencil_mode read, compare_not_equal, 0x11;

uniform float shadow_strength : hint_range(0.0, 1.0) = 0.35;
varying vec2 visibility_uv;
varying vec3 visibility_position_ws;

void vertex() {
	visibility_uv = vec2(UV.x, 1.0 - UV.y);
	visibility_position_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = npr_clip_position(PROJECTION_MATRIX, MODELVIEW_MATRIX, VERTEX);
}

void fragment() {
	vec4 surface_fx = npr_surface_effects(visibility_uv);
	if (!npr_visibility_keep(FRAGCOORD.xy)
			|| npr_dissolve_signed_distance(visibility_uv, visibility_position_ws, surface_fx.a) < 0.0) {
		discard;
	}
	ALBEDO = vec3(1.0);
	EMISSION = vec3(1.0);
	ALPHA = 1.0;
}

void light() {
	// Only consume Godot's real shadow attenuation. Do not reapply Lambert, light
	// energy or light color to the already shaded NPR color underneath this pass.
	// Forward+ adds diffuse to emission after light(). Start from neutral white
	// even with NO lights. Keep only the strongest directional shadow, so an
	// extra unshadowed light cannot erase a shadow or brighten the multiplier.
	if (LIGHT_IS_DIRECTIONAL) {
		float occlusion = clamp(shadow_strength, 0.0, 1.0) * (1.0 - ATTENUATION);
		DIFFUSE_LIGHT = min(DIFFUSE_LIGHT, vec3(-occlusion));
	}
}
