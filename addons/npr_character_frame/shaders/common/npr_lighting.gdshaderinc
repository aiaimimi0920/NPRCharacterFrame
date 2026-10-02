// Material-aware engine shadows. Slot 15 is shared by both native NPR receivers.
// Keep zero as the standalone-material default; the character adapter owns it.
instance uniform float u_npr_shadow_strength : instance_index(15) = 0.0;
uniform float u_npr_rim_strength : hint_range(0.0, 0.5) = 0.0;
uniform vec4 u_npr_rim_color : source_color = vec4(0.78, 0.84, 1.0, 1.0);
#include "res://addons/npr_character_frame/shaders/common/npr_screen_depth.gdshaderinc"
#include "res://addons/npr_character_frame/shaders/common/npr_style.gdshaderinc"
uniform float u_npr_fill_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 npr_final_color;
varying vec3 npr_diffuse_contribution;
varying vec3 npr_specular_contribution;
varying vec3 npr_current_ramp;
varying vec3 npr_ramp_uv_blend;
varying vec3 npr_key_direction_vs;
varying vec3 npr_surface_color;
varying float npr_composition_compatible;
// For color-affine post stages F(C) = gain * C + bias, light increments
// transform by gain only. Bias must be applied once, never once per light.
varying vec3 npr_composition_gain;
varying vec3 npr_pre_composition_color;

vec3 npr_fill_light(vec3 n, vec3 l, vec3 light_color, float attenuation) {
	if (u_npr_fill_strength <= 0.0 || npr_composition_compatible < 0.5) {
		return vec3(0.0);
	}
	float band = smoothstep(-0.1, 0.2, dot(n, l));
	return npr_surface_color * light_color * (band * attenuation * u_npr_fill_strength / PI) * npr_composition_compatible * npr_composition_gain;
}

// Pixel-footprint-aware threshold, not temporal jitter or TAA.
float npr_filtered_step(float signed_distance, float artistic_feather) {
	float width = max(max(artistic_feather, fwidth(signed_distance) * 0.75), 0.0001);
	return smoothstep(-width, width, signed_distance);
}

vec3 npr_edge_light(vec3 normal_ws, vec3 view_ws, vec3 light_ws, vec2 screen_uv, vec3 normal_vs, float depth) {
	if (u_npr_rim_strength <= 0.0) {
		return vec3(0.0);
	}
	float edge = 1.0 - abs(dot(normal_ws, view_ws));
	float band = npr_filtered_step(edge - 0.84, 0.035);
	if (npr_depth_view_slot > 0.5) {
		band = npr_depth_rim(screen_uv, normal_vs, depth);
	}
	float facing_light = smoothstep(-0.1, 0.3, dot(normal_ws, light_ws));
	return u_npr_rim_color.rgb * (u_npr_rim_strength * band * facing_light);
}

vec3 npr_shadow_delta(float attenuation, sampler2D warm_ramp, sampler2D cool_ramp) {
	if (u_npr_shadow_strength <= 0.0 || npr_composition_compatible < 0.5) {
		return vec3(0.0);
	}
	float visibility = mix(1.0, clamp(attenuation, 0.0, 1.0), clamp(u_npr_shadow_strength, 0.0, 1.0));
	// Reevaluate the real material Ramp, rather than multiplying the result gray.
	// Already-dark/AO texels never move to a brighter Ramp coordinate.
	vec2 uv = vec2(min(npr_ramp_uv_blend.x, 0.15), npr_ramp_uv_blend.y);
	vec3 ramp = mix(textureLod(warm_ramp, uv, 0.0).rgb, textureLod(cool_ramp, uv, 0.0).rgb, npr_ramp_uv_blend.z);
	// Blend evaluated colors AFTER PCF, not the Ramp coordinate: feeding a smooth
	// penumbra through a steep toon Ramp recreates hard, crawling shadow edges.
	vec3 ratio = mix(min(ramp / max(npr_current_ramp, vec3(0.0001)), vec3(1.0)), vec3(1.0), visibility);
	vec3 delta = npr_diffuse_contribution * (ratio - vec3(1.0));
	// A highlight cannot remain fully bright underneath an occluder.
	delta -= npr_specular_contribution * (1.0 - visibility);
	// Clamp BEFORE the affine stages. Clamping against fog/pattern-biased output
	// instead would incorrectly let a strong shadow erase their additive color.
	delta = max(delta, -npr_pre_composition_color);
	return delta * npr_composition_gain;
}
