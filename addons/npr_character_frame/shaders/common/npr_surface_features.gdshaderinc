#ifndef NPR_SURFACE_FEATURES_INCLUDED
#define NPR_SURFACE_FEATURES_INCLUDED

// Optional packed per-surface controls. The channel meanings are role-specific
// and are documented by asset_contract.json. Alpha always delays dissolve.
uniform bool u_npr_surface_effects_enabled = false;
uniform sampler2D u_npr_surface_effects : filter_linear_mipmap, repeat_enable;

// One visibility contract is shared by color, eye stencil, outline, depth and
// shadow-caster passes. A disabled or zero-amount dissolve is an exact no-op.
uniform bool u_npr_dissolve_enabled = false;
uniform sampler2D u_npr_dissolve_noise : filter_linear_mipmap, repeat_enable;
uniform float u_npr_dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float u_npr_dissolve_edge_width : hint_range(0.0, 0.25) = 0.04;
uniform vec4 u_npr_dissolve_edge_color : source_color = vec4(0.25, 0.75, 1.0, 1.0);
uniform bool u_npr_dissolve_world_space = false;
uniform vec2 u_npr_dissolve_world_scale = vec2(1.0);
uniform vec2 u_npr_dissolve_world_offset = vec2(0.0);

// Cross-pass scalar visibility. Continuous alpha affects color passes; enabling
// coverage dither makes stencil, outline, depth, shadow and auxiliary agree.
uniform float u_npr_visibility_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float u_npr_visibility_alpha_cutoff : hint_range(0.0, 1.0) = 0.0;
uniform bool u_npr_visibility_dither_enabled = false;

vec4 npr_surface_effects(vec2 uv) {
	return u_npr_surface_effects_enabled ? texture(u_npr_surface_effects, uv) : vec4(0.0);
}

float npr_dissolve_signed_distance(vec2 uv, vec3 position_ws, float protection) {
	if (!u_npr_dissolve_enabled || u_npr_dissolve_amount <= 0.0) {
		return 1.0;
	}
	vec2 world_uv = position_ws.xz * u_npr_dissolve_world_scale + u_npr_dissolve_world_offset;
	vec2 sample_uv = u_npr_dissolve_world_space ? world_uv : uv;
	float threshold = clamp(u_npr_dissolve_amount - clamp(protection, 0.0, 1.0), 0.0, 1.0);
	return texture(u_npr_dissolve_noise, sample_uv).r - threshold;
}

float npr_dissolve_edge(float signed_distance) {
	float width = max(u_npr_dissolve_edge_width, 0.0001);
	return 1.0 - smoothstep(0.0, width, signed_distance);
}

vec3 npr_apply_dissolve_edge(vec3 color, float signed_distance) {
	float edge = npr_dissolve_edge(signed_distance) * float(u_npr_dissolve_enabled);
	return mix(color, u_npr_dissolve_edge_color.rgb, edge * u_npr_dissolve_edge_color.a);
}

float npr_visibility_dither_threshold(vec2 pixel) {
	bool odd_x = (uint(floor(pixel.x)) & 1u) != 0u;
	bool odd_y = (uint(floor(pixel.y)) & 1u) != 0u;
	return odd_x ? (odd_y ? 0.375 : 0.875) : (odd_y ? 0.625 : 0.125);
}

bool npr_visibility_keep(vec2 pixel) {
	float alpha = clamp(u_npr_visibility_alpha, 0.0, 1.0);
	if (alpha <= u_npr_visibility_alpha_cutoff) {
		return false;
	}
	return !u_npr_visibility_dither_enabled || alpha >= npr_visibility_dither_threshold(pixel);
}

#endif
