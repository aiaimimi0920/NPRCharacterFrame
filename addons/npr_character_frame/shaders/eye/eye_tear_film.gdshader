shader_type spatial;

// The authored tear film is an opt-in screen-space transmission approximation.
// It deliberately lives on the independent eye mesh so the production face
// depth/stencil chain remains unchanged when eye geometry is disabled.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://addons/npr_character_frame/shaders/eye/eye_profile.gdshaderinc"
varying vec2 aperture_position;

void vertex() {
	aperture_position = VERTEX.xy;
	VERTEX.z = npr_eye_depth(aperture_position);
}

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tear_tint : source_color = vec4(0.70, 0.90, 1.0, 1.0);
uniform float tear_alpha : hint_range(0.0, 1.0) = 0.20;
uniform float refraction_strength : hint_range(0.0, 0.05) = 0.012;
uniform float ior : hint_range(1.0, 2.0) = 1.333;
uniform float thickness : hint_range(0.0, 0.02) = 0.0015;
uniform float tear_transmission : hint_range(0.0, 1.0) = 0.72;
uniform float wetness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	if (wetness <= 0.0 || !npr_eye_aperture(aperture_position)) {
		discard;
	}
	vec3 normal_view = normalize(NORMAL);
	float facing = max(dot(normal_view, VIEW), 0.001);
	float index = max(ior, 1.0);
	float f0 = pow((index - 1.0) / (index + 1.0), 2.0);
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - clamp(facing, 0.0, 1.0), 5.0);
	// Snell's law through a locally parallel film. Project the displacement in
	// metres; screen pixels no longer stand in for thickness or viewing angle.
	vec3 direction = refract(-VIEW, normal_view, 1.0 / index);
	vec3 hit = VERTEX + direction * thickness / max(-dot(direction, normal_view), 0.05);
	vec3 straight = VERTEX - VIEW * thickness / max(facing, 0.05);
	vec4 hit_clip = PROJECTION_MATRIX * vec4(hit, 1.0);
	vec4 straight_clip = PROJECTION_MATRIX * vec4(straight, 1.0);
	vec2 offset = (hit_clip.xy / hit_clip.w - straight_clip.xy / straight_clip.w) * 0.5;
	vec2 sample_uv = clamp(SCREEN_UV + offset * (refraction_strength / 0.012), vec2(0.0), vec2(1.0));
	float scene_depth = texture(depth_texture, sample_uv).r;
	vec4 scene_position = INV_PROJECTION_MATRIX * vec4(sample_uv * 2.0 - 1.0, scene_depth, 1.0);
	// A foreground eyelid or hair strand must not be pulled into the eye.
	if (scene_position.z / scene_position.w > VERTEX.z + 0.001) {
		sample_uv = SCREEN_UV;
	}
	vec3 transmitted = textureLod(screen_texture, sample_uv, 0.0).rgb;
	vec3 absorption = exp(-max(vec3(1.0) - tear_tint.rgb, vec3(0.0)) * thickness * 20.0);
	ALBEDO = mix(transmitted * absorption, tear_tint.rgb, fresnel * (1.0 - tear_transmission));
	ALPHA = tear_alpha * wetness;
	ROUGHNESS = 0.06;
}
