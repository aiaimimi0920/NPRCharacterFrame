shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

#include "res://addons/npr_character_frame/shaders/body/npr_hosiery.gdshaderinc"
uniform sampler2D garment_mask : filter_linear, repeat_disable;
uniform float opacity = 0.5;
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 rest_position;
varying float leg_domain;

void vertex() {
	rest_position = CUSTOM0.yzw;
	leg_domain = CUSTOM0.r;
	// Keep the authored world-space offset under the existing uniform-scale contract.
	VERTEX += NORMAL * (u_npr_hosiery_shell_offset_m
		/ max(length(MODEL_MATRIX[0].xyz), 0.00001));
}

void fragment() {
	float domain = texture(garment_mask, vec2(UV.x, 1.0 - UV.y)).a * leg_domain;
	domain *= npr_hosiery_height_coverage(rest_position);
	if (domain < 0.001 || opacity <= 0.0) {
		discard;
	}
	float hem = npr_hosiery_metric_stitch(rest_position) * u_npr_stitch_strength;
	ALBEDO = mix(vec3(0.10, 0.085, 0.13), u_npr_stitch_color.rgb, hem);
	vec2 textile_uv = rest_position.xy
		/ (u_npr_hosiery_textile_period_m * u_npr_hosiery_textile_repeats);
	ALBEDO *= texture(albedo_texture, textile_uv).rgb;
	ROUGHNESS = clamp(texture(roughness_texture, textile_uv).r, 0.25, 1.0);
	NORMAL_MAP = texture(normal_texture, textile_uv).rgb;
	NORMAL_MAP_DEPTH = 0.35;
	ALPHA = domain * opacity * mix(0.25, 0.6, hem);
}
